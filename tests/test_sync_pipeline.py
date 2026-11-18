"""The community pipeline end to end (T22): an upload is checked, filed under its market, counted
once, confirmed only by an independent scan, recovered from the archive when its registry line was
lost, and told in shared/status.json; the helper reads that status and the addon shows "No community
price yet" with the reason."""

import base64
import gzip
import hashlib
import io
import json
import pathlib
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

from test_addon import SETUP, run
from test_sync import FakeHub, make_scan, market

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / 'sync'))
import aggregate  # noqa: E402
import ffscan  # noqa: E402
import foreverflip_sync as helper  # noqa: E402


class ArchiveHub(FakeHub):
    """FakeHub with the archive listing reconcile_archive reads."""

    def release(self, tag, create_body=None):
        return {'tag': tag, 'tag_name': tag}

    def raw_releases(self, since):
        return [{'tag_name': tag} for tag in sorted({t for t, _ in self.archive})]

    def assets(self, release):
        return [{'name': n, 'tag': t} for t, n in self.archive if t == release['tag_name']]

    def asset_bytes(self, asset):
        return self.archive[(asset['tag'], asset['name'])]


class Answer(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()


class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.data = pathlib.Path(self.tmp.name)
        (self.data / 'registry').mkdir()
        (self.data / 'registry' / 'uploaders.json').write_text('{"trusted": ["Owner"], "banned": []}')
        self.now = int(time.time())

    def tearDown(self):
        self.tmp.cleanup()

    def process(self, hub, now=None):
        report = aggregate.process(hub, self.data, now or self.now)
        return report, {e['issue']: e for e in aggregate.load_registry(self.data)}

    def status(self):
        return json.loads((self.data / 'shared' / 'status.json').read_text(encoding='utf-8'))

    def test_normal_submission_is_published_and_told_in_status(self):
        hub = ArchiveHub()
        hub.add_upload(make_scan(self.now - 4000, market()), 'Owner', 1)
        _, result = self.process(hub)
        self.assertEqual(result[1]['status'], 'trusted')
        house = self.status()['markets']['Realm-Alliance']
        self.assertEqual((house['published'], house['latest_published'], house['published_at']),
                         (1, self.now - 4000, self.now))
        self.assertFalse(house['reliable'])
        self.assertIn('only 1 published scan', house['reason'])
        hub.add_upload(make_scan(self.now - 60, market([(3, 5, 333)])), 'Owner', 2)
        self.process(hub, self.now + 30)
        house = self.status()['markets']['Realm-Alliance']
        self.assertEqual((house['published'], house['latest_scan'], house['reliable'], house['reason']),
                         (2, self.now - 60, True, None))
        self.assertEqual(house['published_at'], self.now + 30)

    def test_the_same_scan_counts_once_and_does_not_confirm_itself(self):
        hub = ArchiveHub()
        scan = make_scan(self.now - 60, market())
        hub.add_upload(scan, 'Alice', 1)
        self.process(hub)
        hub.add_upload(scan, 'Bob', 2)  # the very same file, under another name
        twin = make_scan(self.now - 60, market())
        twin.addon = '1.1.1'  # another file (other digest), same scan: same house, time and seal
        hub.add_upload(twin, 'Carol', 3)
        _, result = self.process(hub)
        self.assertIn('uploaded already', hub.comments[2])
        self.assertIn('counts once', hub.comments[3])
        self.assertEqual(result[1]['status'], 'pending')
        self.assertNotIn(2, result)
        self.assertIn('wait for another', self.status()['markets']['Realm-Alliance']['reason'])

    def test_an_independent_scan_confirms_an_untrusted_one(self):
        hub = ArchiveHub()
        hub.add_upload(make_scan(self.now - 3000, market()), 'Alice', 1)
        self.process(hub)
        hub.add_upload(make_scan(self.now - 60, market([(3, 5, 333)])[1:]), 'Bob', 2)
        _, result = self.process(hub)
        self.assertEqual((result[1]['status'], result[2]['status']), ('confirmed', 'confirmed'))
        house = self.status()['markets']['Realm-Alliance']
        self.assertEqual((house['published'], house['uploaders'], house['reliable']), (2, 2, True))

    def test_malformed_empty_and_stale_scans_are_refused(self):
        hub = ArchiveHub()
        hub.add_upload(make_scan(self.now - 60, market()), 'Alice', 1)
        hub.gists[f'{1:020x}']['files']['scan.001.b64']['content'] = base64.b64encode(b'not a gzip').decode()
        hub.add_upload(make_scan(self.now - 120, []), 'Alice', 2)
        hub.add_upload(make_scan(self.now - 8 * 86400, market()), 'Alice', 3)
        self.process(hub)
        self.assertFalse(hub.closed[1])
        self.assertIn('refused', hub.comments[1].lower())
        self.assertIn('number', hub.comments[2])
        self.assertIn('7 days', hub.comments[3])
        self.assertEqual(aggregate.load_registry(self.data), [])

    def test_a_wrong_market_id_is_refused(self):
        hub = ArchiveHub()
        moved = make_scan(self.now - 60, market())
        moved.faction = 'Horde'  # header says Horde, the auction house Alliance
        moved.seal = ffscan.compute_seal(moved)
        hub.add_upload(moved, 'Owner', 1)
        hub.add_upload(make_scan(self.now - 900, market()), 'Owner', 2)
        hub.issues[-1]['body'] = hub.issues[-1]['body'].replace('scope: Realm-Alliance', 'scope: Realm-Horde')
        hub.add_upload(make_scan(self.now - 1800, market()), 'Owner', 3)
        hub.issues[-1]['body'] += 'client: wow_classic 1.15.7.61000\n'
        hub.add_upload(make_scan(self.now - 2700, market()), 'Owner', 4)
        hub.issues[-1]['body'] += 'client: wowf 1.60.1.70938\n'
        _, result = self.process(hub)
        self.assertIn('market', hub.comments[1])
        self.assertIn('another auction house', hub.comments[2])
        self.assertIn('another game', hub.comments[3])
        self.assertEqual(list(result), [4])
        self.assertEqual(result[4]['client'], 'wowf 1.60.1.70938')

    def retail(self, hub, at, region, number, scope='Silvermoon-Server', login='Owner', prices=None):
        scan = make_scan(at, prices or market(), scope=scope)
        hub.add_upload(scan, login, number)
        if region is not None:
            hub.issues[-1]['body'] += f'client: wow 12.1.5.70961 {region}'.rstrip() + '\n'
        return scan

    def test_retail_scans_are_published_per_region_apart_from_forever(self):
        hub = ArchiveHub()
        hub.add_upload(make_scan(self.now - 4000, market()), 'Owner', 1)
        self.retail(hub, self.now - 3000, 'eu', 2)
        self.retail(hub, self.now - 2000, 'us', 3, prices=market([(3, 5, 333)]))
        _, result = self.process(hub)
        self.assertEqual([result[n]['status'] for n in (1, 2, 3)], ['trusted'] * 3)
        self.assertNotIn('market', result[1])
        self.assertEqual((result[2]['market'], result[3]['market']), ('retail-eu', 'retail-us'))
        self.assertTrue(result[2]['name'].startswith('retail-eu_'))
        shared = self.data / 'shared'
        self.assertTrue((shared / 'retail-eu' / 'Silvermoon-Server.txt').exists())
        self.assertTrue((shared / 'retail-us' / 'Silvermoon-Server.txt').exists())
        self.assertFalse((shared / 'Silvermoon-Server.txt').exists())
        self.assertEqual(list(self.status()['markets']), ['Realm-Alliance'])
        for region, at in (('eu', self.now - 3000), ('us', self.now - 2000)):
            status = json.loads((shared / f'retail-{region}' / 'status.json').read_text(encoding='utf-8'))
            self.assertEqual(status['markets']['Silvermoon-Server']['product'], 'wow')
            self.assertEqual(list(status['markets']), ['Silvermoon-Server'])
            self.assertEqual(status['markets']['Silvermoon-Server']['latest_published'], at)
        self.assertEqual(self.status()['markets']['Realm-Alliance']['product'], 'wowf')

    def test_retail_and_forever_houses_are_not_mixed(self):
        hub = ArchiveHub()
        self.retail(hub, self.now - 60, 'eu', 1, scope='Realm-Alliance')  # Retail has one house per realm
        self.retail(hub, self.now - 900, None, 2)  # an older helper: no region
        hub.issues[-1]['body'] += 'client: wow 12.1.5.70961\n'
        hub.add_upload(make_scan(self.now - 1800, market(), scope='Realm-Server'), 'Owner', 3)
        hub.issues[-1]['body'] += 'client: wowf 1.60.1.70938\n'
        _, result = self.process(hub)
        self.assertIn('market', hub.comments[1])
        self.assertIn('region', hub.comments[2])
        self.assertIn('market', hub.comments[3])
        self.assertEqual(result, {})

    def test_a_lost_retail_registry_line_keeps_its_region(self):
        hub = ArchiveHub()
        self.retail(hub, self.now - 600, 'eu', 1)
        self.process(hub)
        (self.data / 'registry' / 'scans.jsonl').unlink()
        (self.data / 'shared' / 'retail-eu' / 'Silvermoon-Server.txt').unlink()
        self.process(hub, self.now + 60)
        entries = aggregate.load_registry(self.data)
        self.assertEqual([(e['market'], e['scope'], e.get('recovered')) for e in entries],
                         [('retail-eu', 'Silvermoon-Server', True)])
        self.assertTrue((self.data / 'shared' / 'retail-eu' / 'Silvermoon-Server.txt').exists())

    def test_a_lost_registry_line_is_recovered_from_the_archive(self):
        hub = ArchiveHub()
        hub.add_upload(make_scan(self.now - 4000, market()), 'Owner', 1)
        hub.add_upload(make_scan(self.now - 60, market([(3, 5, 333)])), 'Owner', 2)
        self.process(hub)
        # The push of that run was rejected: the registry and the summaries are gone, the archive stays.
        (self.data / 'registry' / 'scans.jsonl').unlink()
        for path in (self.data / 'shared').iterdir():
            path.unlink()
        report, _ = self.process(hub, self.now + 60)
        self.assertEqual(sum('recovered' in line for line in report), 2, report)
        entries = aggregate.load_registry(self.data)
        self.assertTrue(all(e['recovered'] and e['status'] == 'trusted' for e in entries))
        self.assertTrue(self.status()['markets']['Realm-Alliance']['reliable'])
        report, _ = self.process(hub, self.now + 120)  # nothing twice
        self.assertFalse(any('recovered' in line for line in report))
        self.assertEqual(len(aggregate.load_registry(self.data)), 2)

    def test_an_unchanged_status_is_not_rewritten(self):
        hub = ArchiveHub()
        hub.add_upload(make_scan(self.now - 60, market()), 'Owner', 1)
        self.process(hub)
        self.process(hub, self.now + 60)
        self.assertEqual(self.status()['checked_at'], self.now)


class HelperStatusTests(unittest.TestCase):
    def download(self, status, summaries):
        def urlopen(req, timeout=None):
            if req.full_url.endswith('/status.json'):
                return Answer(json.dumps(status).encode())
            return Answer(summaries.encode())

        with tempfile.TemporaryDirectory() as tmp, \
                patch.object(helper, 'my_scopes', return_value={'Realm-Horde', 'Realm-Alliance'}), \
                patch.object(helper.urllib.request, 'urlopen', urlopen):
            report = {}
            count = helper.download_shared(pathlib.Path(tmp), 'o/r', [], report=report)
            data = (pathlib.Path(tmp) / 'Interface' / 'AddOns' / 'ForeverFlip_Shared' / 'Data.lua').read_text(
                encoding='utf-8')
        return count, report, data

    def test_unreliable_markets_are_withheld_with_their_reason(self):
        at = 1_700_000_000
        status = {'format': 1, 'checked_at': at + 600, 'markets': {
            'Realm-Horde': {'reliable': True, 'reason': None, 'published_at': at + 300, 'latest_published': at},
            'Realm-Alliance': {'reliable': False, 'published_at': at + 200, 'latest_published': at,
                               'reason': 'only 1 published scan in the last 7 days, 2 needed'}}}
        summary = ffscan.encode_summary('Realm-Horde', at, {'1': (10, 9, 2)})
        count, report, data = self.download(status, summary)
        self.assertEqual(count, 1)
        self.assertEqual(report['Realm-Alliance']['scans'], 0)
        self.assertEqual(report['Realm-Horde']['published_at'], at + 300)
        self.assertIn('reason = "only 1 published scan', data)
        lines = helper.community_status({'exchange': {'ok_at': at + 700, 'downloaded_at': at + 700,
                                                      'shared_at': at + 100, 'scopes': report},
                                          'uploaded': [f'Realm-Horde@{at + 50}']})
        text = '\n'.join(lines)
        self.assertIn('Realm-Alliance: No community price yet (only 1 published scan', text)
        self.assertIn('Uploaded: your last scan was sent', text)
        self.assertIn('Downloaded: community data written for the game', text)
        self.assertIn('Realm-Horde: your scan of', text)

    def test_without_a_status_file_the_summaries_are_used_as_before(self):
        def urlopen(req, timeout=None):
            if req.full_url.endswith('/status.json'):
                raise helper.urllib.error.HTTPError(req.full_url, 404, 'Not Found', {}, None)
            return Answer(ffscan.encode_summary('Realm-Horde', 1_700_000_000, {'1': (10, 9, 2)}).encode())

        with tempfile.TemporaryDirectory() as tmp, \
                patch.object(helper, 'my_scopes', return_value={'Realm-Horde'}), \
                patch.object(helper.urllib.request, 'urlopen', urlopen):
            report = {}
            self.assertEqual(helper.download_shared(pathlib.Path(tmp), 'o/r', [], report=report), 1)
        self.assertEqual(report, {'Realm-Horde': {'scans': 1, 'own': 0, 'latest': 1_700_000_000}})

    def test_a_retail_client_downloads_its_own_regions_folder(self):
        asked = []

        def urlopen(req, timeout=None):
            asked.append(req.full_url)
            if req.full_url.endswith('/status.json'):
                raise helper.urllib.error.HTTPError(req.full_url, 404, 'Not Found', {}, None)
            return Answer(ffscan.encode_summary('Silvermoon-Server', 1_700_000_000, {'1': (10, 9, 2)}).encode())

        with tempfile.TemporaryDirectory() as tmp, \
                patch.object(helper, 'client_line', return_value='wow 12.1.5.70961 eu'), \
                patch.object(helper, 'my_scopes', return_value={'Silvermoon-Server'}), \
                patch.object(helper.urllib.request, 'urlopen', urlopen):
            self.assertEqual(helper.download_shared(pathlib.Path(tmp), 'o/r', []), 1)
        self.assertEqual(asked, ['https://raw.githubusercontent.com/o/r/main/shared/retail-eu/status.json',
                                 'https://raw.githubusercontent.com/o/r/main/shared/retail-eu/Silvermoon-Server.txt'])

    def test_the_issue_names_the_client(self):
        scan = make_scan(1_700_000_000, market())
        packed = gzip.compress(ffscan.encode_raw(scan).encode(), mtime=0)
        body = helper.issue_body(scan, hashlib.sha256(packed).hexdigest(), 'a' * 20, 'wowf 1.60.1.70938')
        self.assertEqual(aggregate.parse_issue(body)['client'], 'wowf 1.60.1.70938')


class AddonDisplayTests(unittest.TestCase):
    BASE = SETUP + '''local F, R, UI = ForeverFlip, ForeverFlip.Raw, ForeverFlip.UI
local scope = F.Engine.scope()
'''

    def test_no_community_price_yet_with_the_reason(self):
        run(self.BASE + '''ForeverFlipShared = { generated = now - 60, scans = {}, status = {
            [scope] = { published_at = now - 3600, checked_at = now - 120,
                        reason = 'only 1 published scan in the last 7 days, 2 needed' } } }
        R.importCommunity()
        UI.show('settings:share'); UI.refreshShare()
        local text = UI.shareStatus
        assert(text:find('downloaded by the helper', 1, true), text)
        assert(text:find('published ', 1, true), text)
        assert(text:find('No community price yet: only 1 published scan', 1, true), text)''')

    def test_only_own_scans_give_no_community_price(self):
        line = ffscan.encode_summary('Realm-Alliance', 1_700_000_000, {'i:2589': (10, 9, 2)})
        run(self.BASE + f'''ForeverFlipShared = {{ generated = now - 60, scans = {{ [[{line}]] }},
            uploaded = {{ [scope .. '@1700000000'] = true }} }}
        R.importCommunity()
        assert(R.community.scopes[scope].own == 1 and R.community.scopes[scope].merged == 0)
        assert((F.Data.market(F.db, scope).syncScanAt or 0) == 0)
        UI.show('settings:share'); UI.refreshShare()
        local text = UI.shareStatus
        assert(text:find('only your own scans are published', 1, true), text)''')

    def test_own_uploaded_scans_fill_the_days_the_history_lacks(self):
        # After Reset all data the history has today alone; the helper brings back the player's
        # own scans of the days before: they are the player's prices, not the community's.
        day = 86400
        lines = [ffscan.encode_summary('Realm-Alliance', 1_800_000_000 - k * day, {'i:2589': (100 + k, 90, 20)})
                 for k in (1, 2, 3)]
        scans = ' '.join(f'[[{x}]],' for x in lines)
        uploaded = ' '.join(f"[scope .. '@{1_800_000_000 - k * day}'] = true," for k in (1, 2, 3))
        run(self.BASE + f'''ForeverFlipShared = {{ generated = now - 60, scans = {{ {scans} }},
            uploaded = {{ {uploaded} }} }}
        R.importCommunity()
        local info = R.community.scopes[scope]
        assert(info.own == 3 and info.restored == 3 and info.merged == 0, 'three own scans back')
        local h = F.Data.market(F.db, scope).history['i:2589']
        assert(h and #h.days == 3, 'three days of prices')
        for _, d in ipairs(h.days) do assert(d.lm and not d.cm, 'own prices, no community ones') end
        assert(h.shared == nil, 'no community scan')
        local ref = F.Market.marketReference(h, now)
        assert(ref.combined.n == 3 and ref.community.n == 0, 'the 14-day median has three days')
        assert(ref.trends[2].change, 'the 7-day trend is there')
        R.importCommunity()
        assert(#h.days == 3 and R.community.scopes[scope].restored == nil, 'merged once')''')

    def test_a_scan_the_history_holds_is_not_merged_again(self):
        # The player's full scan, uploaded and brought back by the helper: held, so skipped.
        run(self.BASE + '''addItem(2589,'Linen Cloth',13,'item')
        addAuction(2589,100,20,'Seller')
        fullScan()
        local at = F.Scan.last.at
        assert(F.db.sharedSeen[scope .. '@' .. at], 'the own scan is held')
        local h = F.Data.market(F.db, scope).history['i:2589']
        local before = #h.days
        F.Scan.last = nil -- another session: only the held list knows the scan
        local snap = { scope = scope, at = at, items = { { key = 'i:2589', m = 1, min = 1, n = 20 } } }
        local ok, why = F.Share.merge(snap, 'own', 'own')
        assert(not ok and why == 'duplicate', 'not merged again: ' .. tostring(why))
        assert(#h.days == before and h.days[#h.days].min ~= 1, 'the history is as it was')''')


if __name__ == '__main__':
    unittest.main()
