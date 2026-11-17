"""T31: ForeverFlip's tooltip block needs auction scan data of the last 24 hours.

Either way of getting them is enough: a complete Full scan in the game, or a scan of the house
brought by the Sync helper. Sync is optional. Older or no data: the block gives way to one warning
that offers both. Lines of the game and of other addons stay."""

import re
import time
import unittest

from test_addon import SETUP, run, runtime
from test_sync import RAW, ffscan, saved_variables

TIP = """
    tooltipLines = {}
    GameTooltip:AddLine('Linen Cloth from the game')
    GameTooltip.itemLink = link(10)
    for _, fn in ipairs(tooltipCalls) do fn(GameTooltip) end
    return table.concat(tooltipLines, ' ## ')"""


def clean(text):
    return re.sub(r'\|c[0-9a-fA-F]{8}|\|r', '', text)


def tip(code):
    return clean(run(SETUP + code + TIP))


# The own full scan of RAW, made `scan_age` seconds old; then a Sync file holding a scan of the
# house taken `sync_age` seconds ago (none when None), imported as at login.
def with_sync(scan_age, sync_age, scans=True):
    lua = runtime()
    lua.execute(RAW)
    scan = ffscan.scans_from_saved_variables(saved_variables(lua))[0]
    lua.execute(f'''local F = ForeverFlip
    F.Data.market(F.db, F.Engine.scope()).scannedAt = F.Engine.clock() - {scan_age}''')
    if sync_age is not None:
        clock = lua.eval('ForeverFlip.Engine.clock()')
        at = int(clock - sync_age)
        text = ffscan.encode_summary(scan.scope, at, ffscan.summarize(scan))
        lua.execute(ffscan.lua_data_file([text] if scans else [], time.time()))
        lua.eval('ForeverFlip.Raw.importCommunity()')
    return lua


def sync_tip(lua):
    return clean(lua.execute(TIP))


class FullScanTests(unittest.TestCase):
    def test_a_scan_of_today_shows_the_prices(self):
        text = tip("fullScan()")
        self.assertIn('Median AH price', text)
        self.assertNotIn('out of date', text)

    def test_a_scan_a_day_old_shows_only_the_warning_with_both_ways(self):
        text = tip("""fullScan(); local F = ForeverFlip
        F.Data.market(F.db, F.Engine.scope()).scannedAt = F.Engine.clock() - 24 * 3600""")
        self.assertIn('data out of date, not shown', text)
        self.assertIn('Last auction scan data: 24 h ago.', text)
        self.assertIn('Run a Full scan, or ForeverFlip Sync and then /reload.', text)
        for gone in ('Median AH price', 'Sure', 'Recommendation', 'Lowest AH price', 'Deal now'):
            self.assertNotIn(gone, text)
        self.assertIn('Linen Cloth from the game', text)

    def test_one_second_short_of_a_day_still_shows_the_prices(self):
        text = tip("""fullScan(); local F = ForeverFlip
        F.Data.market(F.db, F.Engine.scope()).scannedAt = F.Engine.clock() - 24 * 3600 + 1""")
        self.assertNotIn('out of date', text)

    def test_no_scan_data_at_all_says_to_get_them(self):
        text = tip("""local F = ForeverFlip
        local c = F.Data.char(F.db, F.Engine.owner())
        F.Data.addPosition(c, 'c:10', 'Linen Cloth', 1, 50, 'other', nil, now)""")
        self.assertIn('No auction scan data of this house yet.', text)
        self.assertIn('Run a Full scan, or ForeverFlip Sync and then /reload.', text)
        self.assertNotIn('You hold', text)

    def test_a_new_scan_lifts_the_block(self):
        text = tip("""local F = ForeverFlip; fullScan()
        F.Data.market(F.db, F.Engine.scope()).scannedAt = F.Engine.clock() - 3 * 86400
        F.db.lastScan = 0; fullScan()""")
        self.assertIn('Median AH price', text)

    def test_without_the_sync_helper_a_fresh_scan_is_enough(self):
        text = tip("fullScan(); ForeverFlipShared = nil")
        self.assertIn('Median AH price', text)


class SyncTests(unittest.TestCase):
    def test_fresh_sync_data_need_no_full_scan(self):
        text = sync_tip(with_sync(scan_age=3 * 86400, sync_age=3600))
        self.assertIn('Median AH price', text)
        self.assertNotIn('out of date', text)

    def test_old_scan_data_from_sync_do_not_count_as_fresh(self):
        lua = with_sync(scan_age=3 * 86400, sync_age=25 * 3600)
        text = sync_tip(lua)
        self.assertIn('Last auction scan data: 25 h ago.', text)

    def test_running_sync_without_new_scans_does_not_reset_the_timer(self):
        # The helper wrote its file just now (generated = now) but brought no scan.
        text = sync_tip(with_sync(scan_age=2 * 86400, sync_age=0, scans=False))
        self.assertIn('Last auction scan data: 2 d ago.', text)
        self.assertNotIn('Median AH price', text)

    def test_the_newest_data_win_whichever_way_they_came(self):
        # Sync's scan is old, the own scan fresh: the tooltip works.
        text = sync_tip(with_sync(scan_age=60, sync_age=30 * 3600))
        self.assertIn('Median AH price', text)

    def test_a_sync_scan_read_at_an_earlier_login_still_counts(self):
        lua = with_sync(scan_age=3 * 86400, sync_age=3600)
        lua.execute('''local F = ForeverFlip
        F.Data.market(F.db, F.Engine.scope()).syncScanAt = nil''')
        lua.eval('ForeverFlip.Raw.importCommunity()')  # the same file at the next login: a duplicate
        self.assertIn('Median AH price', sync_tip(lua))


class TwoSureTests(unittest.TestCase):
    def test_the_deal_line_says_its_sure_is_for_every_unit_at_the_exit_price(self):
        # T17: the Demand Sure is for one unit at the post price; the deal's is for the deal's
        # units plus the ones held, at the deal's exit price. Both read "Sure 26%" before.
        text = tip("""fullScan(); local F = ForeverFlip
        local c = F.Data.char(F.db, F.Engine.owner())
        F.Data.addPosition(c, 'c:10', 'Linen Cloth', 3, 50, 'other', nil, now)
        F.Deals.get = function() return { key = 'c:10', mode = 'flip', qty = 12, exit = 75, profit = 180 } end
        F.Deals.sure = function() return 0.26 end""")
        self.assertIn('Sure 26% to sell all 15 at 75c', text)


if __name__ == '__main__':
    unittest.main()
