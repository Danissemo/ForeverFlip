"""Full scans for the community: capture in the addon, the Sync helper's formats, the aggregator."""

import pathlib
import sys
import tempfile
import time
import unittest
import urllib.error

from test_addon import SETUP, runtime

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / 'sync'))
import aggregate  # noqa: E402
import ffscan  # noqa: E402

RAW = SETUP + '''enableTimeLeft()
local F=ForeverFlip
F.db.settings.rawScans=true
fullScan()
'''


def lua_literal(value, indent=0):
    """Serialises like World of Warcraft's SavedVariables writer (strings escaped, arrays with
    `-- [n]` comments)."""
    pad = '\t' * indent
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'
    if isinstance(value, list):
        inner = ''.join(f'{pad}\t{lua_literal(v, indent + 1)}, -- [{i}]\n' for i, v in enumerate(value, 1))
        return '{\n' + inner + pad + '}'
    inner = ''.join(f'{pad}\t[{lua_literal(k)}] = {lua_literal(v, indent + 1)},\n' for k, v in value.items())
    return '{\n' + inner + pad + '}'


def to_python(lua, value):
    if lua.eval('type')(value) != 'table':
        return value
    keys = list(value.keys())
    if keys and all(isinstance(k, int) for k in keys):
        return [to_python(lua, value[i]) for i in range(1, len(keys) + 1)]
    return {k: to_python(lua, value[k]) for k in keys}


def saved_variables(lua):
    return 'ForeverFlipRaw = ' + lua_literal(to_python(lua, lua.eval('ForeverFlipRaw'))) + '\n'


class AddonCaptureTests(unittest.TestCase):
    def test_every_auction_is_kept_in_scan_order(self):
        lua = runtime()
        lua.execute(RAW)
        scan = lua.eval('ForeverFlipRaw.scans[1]')
        self.assertEqual(scan.scope, 'Realm-Alliance')
        self.assertEqual(scan.count, lua.eval('#auctions'))
        lines = scan.rows.split('\n')
        self.assertEqual(lines[0], '10,5,300,0,0,3,0,c,')
        gear = [l for l in lines if l.startswith('20,')]
        self.assertIn('20,1,700,0,0,3,1,g,Northern Shortsword of Healing', gear)  # the player's own lot

    def test_only_the_last_scans_are_kept(self):
        lua = runtime()
        lua.execute(RAW + '''for i=1,3 do now=now+901;F.db.lastScan=0;fullScan() end''')
        self.assertEqual(lua.eval('#ForeverFlipRaw.scans'), 2)

    def test_nothing_is_kept_with_the_setting_off(self):
        lua = runtime()
        lua.execute(SETUP + '''fullScan()''')
        self.assertIsNone(lua.eval('ForeverFlipRaw'))


class HelperFormatTests(unittest.TestCase):
    def test_saved_variables_round_trip(self):
        lua = runtime()
        lua.execute(RAW)
        scans = ffscan.scans_from_saved_variables(saved_variables(lua))
        self.assertEqual(len(scans), 1)
        scan = scans[0]
        self.assertEqual((scan.scope, scan.realm, scan.faction), ('Realm-Alliance', 'Realm', 'Alliance'))
        self.assertEqual(len(scan.rows), lua.eval('#auctions'))
        back = ffscan.decode_raw(ffscan.encode_raw(scan))
        self.assertEqual(back.rows, scan.rows)
        self.assertEqual(back.rows[0].key(), 'c:10')

    def test_reader_handles_comments_escapes_and_nesting(self):
        data = ffscan.lua_assignments('-- comment\nA = {\n\t["x"] = "a\\"b\\n\\092", -- note\n\t{ 1, 2.5, true, nil, }, -- [1]\n}\nB = 3\n')
        self.assertEqual(data['A']['x'], 'a"b\n\\')
        self.assertEqual(data['A'][1], [1, 2.5, True, None])
        self.assertEqual(data['B'], 3)

    def test_usual_price_matches_the_addon(self):
        lua = runtime()
        lots = [(60, 15), (150, 20), (153, 4), (300, 1), (95.5, 7)]
        lua.execute('buckets={}')
        for unit, qty in lots:
            lua.execute(f'ForeverFlip.Market.bucketAdd(buckets,{unit},{qty})')
        lua.execute('usual=ForeverFlip.Market.bucketValue(buckets)')
        self.assertEqual(ffscan.usual_price(lots), lua.eval('usual'))

    def test_summary_is_read_by_the_addon(self):
        lua = runtime()
        lua.execute(RAW)
        scan = ffscan.scans_from_saved_variables(saved_variables(lua))[0]
        scan.at += 600  # another player's scan ten minutes later
        text = ffscan.encode_summary(scan.scope, scan.at, ffscan.summarize(scan))
        snap = lua.eval('ForeverFlip.Share.decode')(text)
        self.assertEqual(snap.scope, 'Realm-Alliance')
        items = {snap['items'][i]['key']: snap['items'][i] for i in range(1, len(snap['items']) + 1)}
        self.assertEqual(items['c:10'].min, 60)
        self.assertIn('g:20:northern shortsword of healing', items)

    def test_shared_data_file_is_imported_by_the_addon(self):
        lua = runtime()
        lua.execute(RAW)
        scan = ffscan.scans_from_saved_variables(saved_variables(lua))[0]
        scan.at += 600
        text = ffscan.encode_summary(scan.scope, scan.at, ffscan.summarize(scan))
        lua.execute(ffscan.lua_data_file([text], time.time()))
        self.assertEqual(lua.eval('ForeverFlip.Raw.importCommunity()'), 1)
        self.assertEqual(lua.eval("ForeverFlip.Data.market(ForeverFlip.db,'Realm-Alliance').history['c:10'].shared.from"),
                         'community')


class SealTests(unittest.TestCase):
    def saved(self):
        lua = runtime()
        lua.execute(RAW)
        return lua, ffscan.scans_from_saved_variables(saved_variables(lua))[0]

    def test_python_computes_the_addons_seal(self):
        _, scan = self.saved()
        self.assertIsNotNone(scan.seal)
        self.assertEqual(ffscan.compute_seal(scan), scan.seal)

    def test_the_seal_survives_the_upload_file(self):
        _, scan = self.saved()
        back = ffscan.decode_raw(ffscan.encode_raw(scan))
        self.assertEqual((back.seal, back.text), (scan.seal, scan.text))
        self.assertEqual(ffscan.compute_seal(back), back.seal)

    def test_any_change_breaks_the_seal(self):
        _, scan = self.saved()
        text = ffscan.encode_raw(scan)
        for old, new in [(',300,', ',299,'), ('|Realm-Alliance|', '|Realm-Horde|'), ('10,5,300', '10,50,300')]:
            changed = ffscan.decode_raw(text.replace(old, new, 1))
            self.assertNotEqual(ffscan.compute_seal(changed), changed.seal, old)
        added = ffscan.decode_raw(text.replace('|' + str(len(scan.rows)) + '|', '|' + str(len(scan.rows) + 1) + '|', 1)
                                  + '\n10,5,1,0,0,3,0,c,')
        self.assertNotEqual(ffscan.compute_seal(added), added.seal)


def make_scan(at, prices, scope='Realm-Alliance', seal=True):
    s = ffscan.RawScan(scope=scope, at=at, realm=scope.split('-')[0], faction=scope.split('-')[1], addon='1.1.0')
    s.rows = [ffscan.Auction(item=item, count=count, buyout=buyout, min_bid=0, bid=0, band=3, own=False,
                             kind='c', name='') for item, count, buyout in prices]
    if seal:
        s.seal = ffscan.compute_seal(s)
    return s


def market(extra=()):
    """60 lots of ten items, plus `extra`."""
    return [(item, 5, 100 * item + k) for item in range(1, 11) for k in range(6)] + list(extra)


class CheckTests(unittest.TestCase):
    def test_check_refuses_bad_scans(self):
        now = time.time()
        self.assertIsNone(ffscan.check(make_scan(int(now), market()), now))
        self.assertIn('7 days', ffscan.check(make_scan(int(now) - 8 * 86400, market()), now))
        self.assertIn('future', ffscan.check(make_scan(int(now) + 3600, market()), now))
        self.assertIn('number', ffscan.check(make_scan(int(now), market()[:3]), now))
        self.assertIn('seal', ffscan.check(make_scan(int(now), market(), seal=False), now))
        self.assertIn('name', ffscan.check(make_scan(int(now), market(), scope='Realm-Pirates'), now))
        bad = make_scan(int(now), market())
        bad.rows[0].buyout = 1
        self.assertIn('changed', ffscan.check(bad, now))
        silly = make_scan(int(now), market([(5, 50000, 1)]))
        self.assertIn('implausible', ffscan.check(silly, now))


class FakeHub:
    """The parts of GitHub the aggregator uses, in memory."""

    repo = 'Owner/Data'

    def __init__(self):
        self.gists, self.archive, self.comments, self.closed, self.issues = {}, {}, {}, {}, []
        self.created = {}

    def add_upload(self, scan, login, number, tamper=None):
        import base64
        import gzip
        import hashlib
        packed = gzip.compress(ffscan.encode_raw(scan).encode(), mtime=0)
        digest = hashlib.sha256(packed).hexdigest()
        if tamper:
            packed = gzip.compress(tamper(ffscan.encode_raw(scan)).encode(), mtime=0)
        gist_id = f'{number:020x}'
        self.gists[gist_id] = {'owner': {'login': login}, 'files': {
            'scan.001.b64': {'content': base64.b64encode(packed).decode(), 'size': 10, 'truncated': False}}}
        self.issues.append({'number': number, 'user': {'login': login}, 'title': 'Scan upload: x',
                            'created_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
                            'body': f'scope: {scan.scope}\ntime: {scan.at}\nsha256: {digest}\ngist: {gist_id}\n'})

    def scan_issues(self):
        out, self.issues = self.issues, []
        return out

    def account_created(self, login):
        return self.created.get(login, 0)

    def gist(self, gist_id):
        if gist_id in getattr(self, 'offline', ()):
            raise urllib.error.URLError('rate limited')
        return self.gists[gist_id]

    def release(self, tag, create_body=None):
        return {'tag': tag}

    def upload(self, release, name, data):
        self.archive[(release['tag'], name)] = data

    def download_archived(self, tag, name):
        return self.archive[(tag, name)]

    def comment(self, number, text):
        self.comments[number] = text

    def close(self, number, completed):
        self.closed[number] = completed


class AggregatorTests(unittest.TestCase):
    def run_aggregator(self, hub, data, now):
        aggregate.process(hub, data, now)
        return {e['issue']: e for e in aggregate.load_registry(data)}

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.data = pathlib.Path(self.tmp.name)
        (self.data / 'registry').mkdir()
        (self.data / 'registry' / 'uploaders.json').write_text('{"trusted": ["Owner"], "banned": ["Spammer"]}')
        self.now = int(time.time())

    def tearDown(self):
        self.tmp.cleanup()

    def summary(self):
        path = self.data / 'shared' / 'Realm-Alliance.txt'
        return path.read_text(encoding='utf-8').splitlines() if path.exists() else []

    def test_trusted_scans_are_published_at_once(self):
        hub = FakeHub()
        hub.add_upload(make_scan(self.now - 60, market()), 'Owner', 1)
        result = self.run_aggregator(hub, self.data, self.now)
        self.assertEqual(result[1]['status'], 'trusted')
        self.assertTrue(hub.closed[1])
        self.assertEqual(len(self.summary()), 1)
        self.assertIn(('raw-' + time.strftime('%Y-%m-%d', time.gmtime(self.now - 60)), result[1]['name']), hub.archive)

    def test_other_scans_wait_for_a_confirming_scan(self):
        hub = FakeHub()
        hub.add_upload(make_scan(self.now - 3000, market()), 'Alice', 1)
        result = self.run_aggregator(hub, self.data, self.now)
        self.assertEqual(result[1]['status'], 'pending')
        self.assertEqual(self.summary(), [])
        # Bob's scan an hour later: most lots are the same, one was bought, one is new.
        later = market([(3, 5, 333)])[1:]
        hub.add_upload(make_scan(self.now - 60, later), 'Bob', 2)
        result = self.run_aggregator(hub, self.data, self.now)
        self.assertEqual(result[1]['status'], 'confirmed')
        self.assertEqual(result[2]['status'], 'confirmed')
        self.assertEqual(len(self.summary()), 2)

    def test_a_lot_added_by_hand_is_not_published(self):
        hub = FakeHub()
        hub.add_upload(make_scan(self.now - 3000, market()), 'Alice', 1)
        # Mallory's scan lists a fake heap of cheap item 7 (sealed with the public algorithm).
        fake = make_scan(self.now - 60, market([(7, 500, 500)]))
        hub.add_upload(fake, 'Mallory', 2)
        result = self.run_aggregator(hub, self.data, self.now)
        self.assertEqual(result[2]['status'], 'confirmed')
        line = [l for l in self.summary() if l.split('|')[2] == ffscan.enc36(self.now - 60)][0]
        self.assertNotIn('c:7,', line)
        self.assertIn('c:6,', line)

    def test_a_scan_changed_after_sealing_is_refused(self):
        hub = FakeHub()
        hub.add_upload(make_scan(self.now - 60, market()), 'Alice', 1,
                       tamper=lambda text: text.replace(',100,', ',1,', 1))
        self.run_aggregator(hub, self.data, self.now)
        self.assertFalse(hub.closed[1])
        self.assertIn('SHA-256', hub.comments[1])

    def test_uploader_rules(self):
        hub = FakeHub()
        hub.add_upload(make_scan(self.now - 60, market()), 'Spammer', 1)
        hub.created['Newbie'] = self.now - 3600
        hub.add_upload(make_scan(self.now - 60, market()), 'Newbie', 2)
        hub.add_upload(make_scan(self.now - 900, market()), 'Alice', 3)
        hub.add_upload(make_scan(self.now - 700, market([(1, 5, 1)])), 'Alice', 4)
        hub.add_upload(make_scan(self.now - 30, market()), 'Carol', 5)
        hub.gists[f'{5:020x}']['owner']['login'] = 'Dave'
        self.run_aggregator(hub, self.data, self.now)
        self.assertIn('not accepted', hub.comments[1])
        self.assertIn('7 days', hub.comments[2])
        self.assertTrue(hub.closed[3])
        self.assertIn('10 minutes', hub.comments[4])
        self.assertIn('does not belong', hub.comments[5])

    def test_a_network_failure_postpones_the_upload(self):
        hub = FakeHub()
        hub.add_upload(make_scan(self.now - 60, market()), 'Owner', 1)
        hub.offline = {f'{1:020x}'}
        report = aggregate.process(hub, self.data, self.now)
        self.assertNotIn(1, hub.closed)
        self.assertTrue(any('postponed' in line for line in report))

    def test_unconfirmed_after_a_day(self):
        hub = FakeHub()
        hub.add_upload(make_scan(self.now - 60, market()), 'Alice', 1)
        self.run_aggregator(hub, self.data, self.now)
        result = self.run_aggregator(hub, self.data, self.now + aggregate.WAIT + 60)
        self.assertEqual(result[1]['status'], 'unconfirmed')
        self.assertEqual(self.summary(), [])

    def test_summaries_keep_the_newest_and_skip_the_same_server_scan(self):
        shared = self.data / 'shared'
        shared.mkdir()
        items = ffscan.summarize(make_scan(self.now, market()))
        for k in range(14):
            self.assertTrue(aggregate.add_summary(shared, 'Realm-Alliance', self.now + k * 900, items))
        self.assertFalse(aggregate.add_summary(shared, 'Realm-Alliance', self.now + 13 * 900 + 30, items))
        lines = self.summary()
        self.assertEqual(len(lines), aggregate.KEEP)
        self.assertEqual(int(lines[0].split('|')[2], 36), self.now + 13 * 900)
        aggregate.write_index(shared)
        self.assertIn('Realm-Alliance', (shared / 'index.json').read_text(encoding='utf-8'))


class HelperTests(unittest.TestCase):
    def test_package_splits_and_rebuilds_the_file(self):
        import base64
        import foreverflip_sync
        scan = make_scan(int(time.time()), market())
        foreverflip_sync.PART, old = 100, foreverflip_sync.PART
        try:
            packed, parts = foreverflip_sync.package(scan)
        finally:
            foreverflip_sync.PART = old
        self.assertGreater(len(parts), 1)
        self.assertEqual(base64.b64decode(''.join(parts[n] for n in sorted(parts))), packed)
        body = foreverflip_sync.issue_body(scan, 'a' * 64, 'b' * 32)
        fields = aggregate.parse_issue(body)
        self.assertEqual((fields['gist'], fields['sha256'], fields['scope']), ('b' * 32, 'a' * 64, 'Realm-Alliance'))


if __name__ == '__main__':
    unittest.main()
