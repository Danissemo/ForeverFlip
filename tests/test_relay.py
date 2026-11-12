"""Anonymous uploads through the relay, and the community-history check of every published scan."""

import gzip
import hashlib
import json
import pathlib
import shutil
import subprocess
import tempfile
import time
import unittest

from test_sync import FakeHub, aggregate, ffscan, make_scan

ROOT = pathlib.Path(__file__).resolve().parent.parent


def big_market(scale=None, extra=()):
    """Six lots of 30 items; `scale` maps an item to a price factor."""
    scale = scale or {}
    return [(item, 5, int((100 * item + k) * scale.get(item, 1))) for item in range(1, 31) for k in range(6)] \
        + list(extra)


class FakeRelay:
    def __init__(self):
        self.items, self.deleted = {}, []

    def add(self, scan, uploader, sha=None, scope=None):
        packed = gzip.compress(ffscan.encode_raw(scan).encode(), mtime=0)
        digest = sha or hashlib.sha256(packed).hexdigest()
        ident = f'{uploader}/{digest}'
        self.items[ident] = ({'id': ident, 'uploader': uploader, 'sha256': digest, 'scope': scope or scan.scope,
                              'at': scan.at, 'bytes': len(packed)}, packed)
        return ident

    def pending(self):
        return [meta for meta, _ in self.items.values()]

    def download(self, ident):
        return self.items[ident][1]

    def delete(self, ident):
        self.deleted.append(ident)
        self.items.pop(ident, None)


A, B = 'anon-' + 'a' * 12, 'anon-' + 'b' * 12


class RelayTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.data = pathlib.Path(self.tmp.name)
        (self.data / 'registry').mkdir()
        (self.data / 'registry' / 'uploaders.json').write_text('{"trusted": [], "banned": []}')
        self.now = int(time.time())
        self.hub, self.relay = FakeHub(), FakeRelay()

    def run_once(self, now=None):
        aggregate.process(self.hub, self.data, now or self.now, self.relay)
        return {e['uploader']: e for e in aggregate.load_registry(self.data)}

    def published(self, at):
        path = self.data / 'shared' / 'Realm-Alliance.txt'
        for when, items in aggregate.read_summaries(path):
            if when == at:
                return items
        return None

    def history(self, scale=None, days_ago=1):
        shared = self.data / 'shared'
        shared.mkdir(exist_ok=True)
        items = ffscan.summarize(make_scan(self.now - days_ago * 86400, big_market(scale)))
        aggregate.add_summary(shared, 'Realm-Alliance', self.now - days_ago * 86400, items)

    def test_relay_scan_is_archived_and_collected(self):
        self.relay.add(make_scan(self.now - 60, big_market()), A)
        result = self.run_once()
        self.assertEqual(result[A]['status'], 'pending')
        self.assertIsNone(result[A]['issue'])
        self.assertEqual(self.relay.items, {}, 'collected scans leave the relay')
        self.assertEqual(len(self.hub.archive), 1)

    def test_bad_relay_scans_are_refused_listed_and_removed(self):
        self.relay.add(make_scan(self.now - 60, big_market()), A, sha='0' * 64)
        self.relay.add(make_scan(self.now - 60, big_market(), seal=False), B)
        self.relay.add(make_scan(self.now - 30, big_market()), 'mallory')
        self.run_once()
        refused = [json.loads(l) for l in (self.data / 'registry' / 'refused.jsonl').read_text().splitlines()]
        reasons = ' | '.join(r['reason'] for r in refused)
        self.assertIn('SHA-256', reasons)
        self.assertIn('seal', reasons)
        self.assertIn('anonymous uploader', reasons)
        self.assertEqual(self.relay.items, {})
        self.assertEqual(aggregate.load_registry(self.data), [])

    def test_details_must_match_the_file(self):
        self.relay.add(make_scan(self.now - 60, big_market()), A, scope='Other-Horde')
        self.run_once()
        self.assertIn('do not match', (self.data / 'registry' / 'refused.jsonl').read_text())

    def test_two_anonymous_scans_publish_only_items_the_community_already_prices(self):
        self.history()
        new_item = [(77, 5, 999)] * 3
        self.relay.add(make_scan(self.now - 3000, big_market(extra=new_item)), A)
        self.relay.add(make_scan(self.now - 60, big_market(extra=new_item)), B)
        result = self.run_once()
        self.assertEqual(result[A]['status'], 'confirmed')
        items = self.published(self.now - 60)
        self.assertIn('c:5', items)
        self.assertNotIn('c:77', items, 'a new item needs a GitHub account or history behind it')

    def test_a_scan_of_a_github_account_lets_new_items_through(self):
        new_item = [(77, 5, 999)] * 3
        self.relay.add(make_scan(self.now - 60, big_market(extra=new_item)), A)
        self.hub.add_upload(make_scan(self.now - 3000, big_market(extra=new_item)), 'Alice', 1)
        self.run_once()
        self.assertIn('c:77', self.published(self.now - 60))

    def test_prices_far_from_the_history_are_left_out(self):
        self.history()
        odd = big_market({3: 5})  # item 3 five times dearer than the community saw
        self.hub.add_upload(make_scan(self.now - 3000, odd), 'Alice', 1)
        self.hub.add_upload(make_scan(self.now - 60, odd), 'Bob', 2)
        result = self.run_once()
        self.assertEqual(result['Bob']['status'], 'confirmed')
        items = self.published(self.now - 60)
        self.assertNotIn('c:3', items)
        self.assertIn('c:4', items)
        self.assertEqual(result['Bob']['history'], {'compared': 30, 'off': 1})

    def test_a_scan_mostly_out_of_line_is_disputed(self):
        self.history()
        odd = big_market({item: 4 for item in range(1, 12)})  # 11 of 30 items far off
        self.relay.add(make_scan(self.now - 3000, odd), A)
        self.relay.add(make_scan(self.now - 60, odd), B)
        result = self.run_once()
        self.assertEqual(result[B]['status'], 'disputed')
        self.assertIsNone(self.published(self.now - 60))

    def test_a_relay_player_is_limited_and_can_be_banned(self):
        (self.data / 'registry' / 'uploaders.json').write_text(json.dumps({'banned': [A]}))
        self.relay.add(make_scan(self.now - 60, big_market()), A)
        self.run_once()
        self.assertIn('not accepted', (self.data / 'registry' / 'refused.jsonl').read_text())


@unittest.skipUnless(shutil.which('node'), 'Node.js runs the relay check')
class RelayWorkerTests(unittest.TestCase):
    def test_worker(self):
        result = subprocess.run(['node', 'tests/relay_worker_check.mjs'], cwd=ROOT, capture_output=True,
                                text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)


if __name__ == '__main__':
    unittest.main()
