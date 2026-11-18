"""tools/calibrate.py: the development-only comparison with TSM's region data."""

import importlib.util
import io
import pathlib
import tempfile
import unittest
from contextlib import redirect_stdout

ROOT = pathlib.Path(__file__).resolve().parent.parent

APPDATA = '''select(2, ...).LoadData("AUCTIONDB_REGION_SALE","Forever-EU",[[return {downloadTime=1794703501,\
fields={"itemString","regionSale","regionSoldPerDay","regionSalePercent"},\
data={{789,1T8,EHF,AB},{790,0,0,0},{"i:791::2:1",5,5,5},{2589,100,7Q8,FA}}}]]) --<x>
select(2, ...).LoadData("AUCTIONDB_REGION_STAT","Forever-EU",[[return {downloadTime=1794701746,\
fields={"itemString","regionMarketValue"},data={{789,1000000A},{2589,C8}}}]]) --<y>
'''

SAVE = '''ForeverFlipData = { markets = {
  ["Realm-Alliance"] = { history = {
    ["c:2589"] = { scan = { at = 1000, market = 400, above = { 0, 0, 0, 0 }, low = 390 } },
    ["g:15210:raider's shortsword"] = { scan = { at = 1000, market = 9000, above = { 0, 0, 0, 0 } } },
  } },
} }
'''


def tool():
    spec = importlib.util.spec_from_file_location('calibrate', ROOT / 'tools' / 'calibrate.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CalibrateToolTests(unittest.TestCase):
    def setUp(self):
        self.cal = tool()
        self.tmp = tempfile.TemporaryDirectory()
        base = pathlib.Path(self.tmp.name)
        self.tsm, self.save = base / 'AppData.lua', base / 'ForeverFlip.lua'
        self.tsm.write_text(APPDATA, encoding='utf-8')
        self.save.write_text(SAVE, encoding='utf-8')

    def tearDown(self):
        self.tmp.cleanup()

    def test_tsm_numbers_are_base_32_and_long_ones_come_in_two_halves(self):
        self.assertEqual(self.cal.tsm_number('1T8'), 1 * 1024 + 29 * 32 + 8)
        self.assertEqual(self.cal.tsm_number('1000000A'), 10 + 32 * 2**30)

    def test_region_data_is_read_with_sale_rate_and_daily_sold_back_in_units(self):
        data = self.cal.read_tsm(self.tsm)
        sale = data[('AUCTIONDB_REGION_SALE', 'Forever-EU')]
        self.assertEqual(sale['at'], 1794703501)
        self.assertEqual(sale['items'][789]['regionSale'], 1960)
        self.assertAlmostEqual(sale['items'][789]['regionSoldPerDay'], 14.895)
        self.assertAlmostEqual(sale['items'][789]['regionSalePercent'], 0.331)
        self.assertNotIn(791, sale['items'])  # an item string with bonus IDs is not a plain item

    def test_an_item_without_own_sales_but_selling_in_the_region_is_counted_as_cold(self):
        scope, rows = self.cal.ff_estimates(self.cal.load_addon(self.save), None)
        self.assertEqual(scope, 'Realm-Alliance')
        self.assertEqual([r['key'] for r in rows], ['c:2589'])  # gear versions are left out
        result = self.cal.compare(rows, self.cal.read_tsm(self.tsm), 'Forever-EU')
        self.assertEqual([j['key'] for j in result['cold']], ['c:2589'])
        self.assertEqual(result['sale'], [400 / 1024])
        self.assertEqual(result['market'], [400 / 392])

    def test_the_report_runs_from_the_command_line_and_writes_its_rows(self):
        out, table = io.StringIO(), pathlib.Path(self.tmp.name) / 'rows.csv'
        with redirect_stdout(out):
            code = self.cal.main(['--save', str(self.save), '--tsm', str(self.tsm), '--csv', str(table)])
        self.assertEqual(code, 0, out.getvalue())
        self.assertIn('1 items with a usual price, 1 also in TSM', out.getvalue())
        self.assertIn('c:2589', table.read_text(encoding='utf-8'))

    def test_an_unknown_region_is_refused(self):
        with redirect_stdout(io.StringIO()):
            self.assertEqual(self.cal.main(['--save', str(self.save), '--tsm', str(self.tsm),
                                            '--region', 'Nowhere']), 2)


if __name__ == '__main__':
    unittest.main()
