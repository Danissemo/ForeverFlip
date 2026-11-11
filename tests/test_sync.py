"""Full scans for the community: capture in the addon, the Sync helper's formats, the aggregator."""

import pathlib
import sys
import tempfile
import time
import unittest

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


class AggregatorTests(unittest.TestCase):
    def scan(self, at, rows=60):
        s = ffscan.RawScan(scope='Realm-Alliance', at=at, realm='Realm', faction='Alliance', addon='1.1.0')
        s.rows = [ffscan.Auction(item=10, count=5, buyout=300 + i, min_bid=0, bid=0, band=3, own=False,
                                 kind='c', name='') for i in range(rows)]
        return s

    def test_check_refuses_bad_scans(self):
        now = time.time()
        self.assertIsNone(aggregate.check(self.scan(int(now)), now))
        self.assertIsNotNone(aggregate.check(self.scan(int(now) - 8 * 86400), now))
        self.assertIsNotNone(aggregate.check(self.scan(int(now), rows=3), now))
        bad = self.scan(int(now))
        bad.scope = 'Realm-Pirates'
        self.assertIsNotNone(aggregate.check(bad, now))

    def test_summaries_keep_the_newest_and_skip_the_same_server_scan(self):
        with tempfile.TemporaryDirectory() as tmp:
            shared = pathlib.Path(tmp)
            base = int(time.time())
            for k in range(14):
                self.assertTrue(aggregate.add_summary(shared, self.scan(base + k * 900)))
            self.assertFalse(aggregate.add_summary(shared, self.scan(base + 13 * 900 + 30)))
            lines = (shared / 'Realm-Alliance.txt').read_text(encoding='utf-8').splitlines()
            self.assertEqual(len(lines), aggregate.KEEP)
            self.assertEqual(int(lines[0].split('|')[2], 36), base + 13 * 900)
            aggregate.write_index(shared)
            self.assertIn('Realm-Alliance', (shared / 'index.json').read_text(encoding='utf-8'))


if __name__ == '__main__':
    unittest.main()
