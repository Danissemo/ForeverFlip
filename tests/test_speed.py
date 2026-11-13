"""Faster checks, Check all giving way to selling, new-player defaults and bids that last."""
import unittest

from test_addon import SETUP, run, runtime


class GearKeyCacheTests(unittest.TestCase):
    GEAR = SETUP + '''enableBrowse()
    fullScan()
    local F, D, U = ForeverFlip, ForeverFlip.Deals, ForeverFlip.Util
    F.db.settings.autoVerify = false
    local key = U.key('gear', 20, 'Northern Shortsword of Nature Protection')
    local function browses()
        local n = 0
        for _, c in ipairs(calls) do if c[1] == 'SendBrowseQuery' then n = n + 1 end end
        return n
    end
    '''

    def test_second_check_of_gear_skips_the_browse(self):
        run(self.GEAR + '''D.verify(key); answer()
        assert(D.get(key).verified and browses() == 1, 'the first check browses')
        assert(F.db.itemKeys[20] and #F.db.itemKeys[20].list > 0, 'its versions are remembered')
        run(1); D.verify(key)
        assert(browses() == 1, 'no browse the second time')
        assert(D.search and D.search.phase == 'keys' and lastCall('SendSearchQuery')[2] == 20)
        answer()
        assert(D.get(key).verified, 'checked from the remembered versions')''')

    def test_old_or_empty_versions_browse_again(self):
        run(self.GEAR + '''D.verify(key); answer(); run(1)
        now = now + 7 * 3600
        D.verify(key); assert(D.search.phase == 'browse', 'versions older than 6 hours: browse')
        answer(); run(1)
        for i = #auctions, 1, -1 do if auctions[i].item == 20 then table.remove(auctions, i) end end
        local got
        D.enqueue(key, function(_, rows, complete) got = { rows = rows, complete = complete } end)
        answer()
        assert(got and got.rows == nil, 'nothing in the remembered versions: unknown, not gone')
        assert(not F.db.itemKeys[20], 'forgotten: the next check browses')''')


class CheckAllGivesWayTests(unittest.TestCase):
    BATCH = SETUP + '''fullScan()
    local F, D, UI = ForeverFlip, ForeverFlip.Deals, ForeverFlip.UI
    F.db.settings.autoVerify = false
    local keys = {}
    for _, d in ipairs(D.list) do keys[#keys + 1] = d.key end
    '''

    def test_check_all_pauses_on_the_selling_page(self):
        run(self.BATCH + '''UI.show('deals'); assert(D.startBatch('deals:all', keys, true) > 0)
        if D.search then answer() end
        UI.show('sell'); run(1)
        assert(not D.search and D.batchPaused(), 'Check all rests while the player sells')
        assert(F.Trade.wayFree(), 'Post finds the way free')
        UI.refreshStatus(); assert(UI.status:GetText():find('paused'), UI.status:GetText())
        UI.show('deals'); run(0.3)
        assert(D.search or select(1, D.batchProgress()) == select(2, D.batchProgress()), 'goes on back on the page')''')

    def test_check_all_pauses_while_the_game_page_is_shown(self):
        run(self.BATCH + '''UI.show('deals'); D.startBatch('deals:all', keys, true)
        if D.search then answer() end
        AuctionHouseFrame.BrowseResultsFrame = CreateFrame('Frame')
        run(1); assert(not D.search, 'the game Buy tab is not overwritten')
        AuctionHouseFrame.BrowseResultsFrame:Hide(); run(0.3)
        assert(D.search or not select(3, D.batchProgress()))''')

    def test_a_click_goes_while_a_full_scan_waits(self):
        run(self.BATCH + '''run(1); now = now + 1000; assert(F.Scan.start())
        assert(F.Scan.blocking()); F.Engine.input(); F.Trade.checkPrice('c:10') -- the click
        assert(D.search and D.search.key == 'c:10')''')


class NewPlayerDefaultsTests(unittest.TestCase):
    def test_nothing_runs_by_itself_and_scans_are_kept_for_sync(self):
        lua = runtime()
        lua.execute('''local s = ForeverFlip.db.settings
        assert(not s.autoScan and not s.sniper and not s.autoVerify and not s.shareAuto)
        assert(s.rawScans, 'full scans are kept for the Sync helper')''')

    def test_a_player_choice_is_kept(self):
        lua = runtime()
        lua.execute('''local D = ForeverFlip.Data
        local db = D.open({ settings = { autoScan = true, sniper = true, rawScans = false } })
        assert(db.settings.autoScan and db.settings.sniper and not db.settings.rawScans)''')


class BidCandidateTests(unittest.TestCase):
    def test_bids_ending_within_two_hours_are_kept_until_they_end(self):
        run(SETUP + '''local F, B = ForeverFlip, ForeverFlip.Bids
        local j = { scope = F.Engine.scope() }
        F.db.settings.minProfit = 1
        B.consider(j, 'i:30', 'item', { id = 30, band = 1, minBid = 100, count = 1 })
        B.consider(j, 'i:31', 'item', { id = 30, band = 2, minBid = 100, count = 1 })
        F.Data.market(F.db, j.scope).history['i:30'] = nil
        B.finish(j, { ['i:30'] = { scan = { market = 50000, at = now } } })
        local vendorOnly = #B.current()
        assert(#j.bids == 1, 'up to 2 hours left: a candidate; longer: not')
        B.candidates = {}; B.scope = nil
        assert(#B.current() == vendorOnly, 'kept in the saved data')
        now = now + 7201
        assert(#B.current() == 0, 'gone once the auction has ended')''')


if __name__ == '__main__':
    unittest.main()


class SellingPagesAndHoverTests(unittest.TestCase):
    def test_a_check_of_undercuts_goes_on_while_my_auctions_is_shown(self):
        run(SETUP + '''local F, D, UI = ForeverFlip, ForeverFlip.Deals, ForeverFlip.UI
        UI.show('undercuts'); D.batch = { active = true, scope = 'undercuts', keySet = {}, total = 4, done = 1 }
        UI.show('auctions')
        assert(not D.batchPaused(), 'the selling pages share their checks')
        D.batch.scope = 'deals:all'
        assert(D.batchPaused(), 'a check of deals still rests there')
        D.batch = nil''')

    def test_hovering_a_row_shows_every_column_in_full(self):
        run(SETUP + '''local F, D, UI = ForeverFlip, ForeverFlip.Deals, ForeverFlip.UI
        fullScan(); UI.show('deals'); UI.refresh()
        local r = UI.dealTable.rows[1]
        assert(r:IsShown())
        tooltipLines = {}
        local lines = {}
        GameTooltip.AddDoubleLine = function(_, left, right) lines[#lines + 1] = left .. '=' .. right end
        r.scripts.OnEnter(r)
        local all = table.concat(lines, ' | ')
        assert(all:find('Status=') and all:find('Profit='), all)''')

    def test_hovering_the_status_shows_it_in_full(self):
        run(SETUP + '''local F, UI = ForeverFlip, ForeverFlip.UI
        UI.show('deals'); UI.status:SetText('a very long status line that does not fit')
        local shown
        GameTooltip.SetText = function(_, text) shown = text end
        UI.statusHover.scripts.OnEnter(UI.statusHover)
        assert(shown == 'a very long status line that does not fit', tostring(shown))''')


class AuctionTotalTests(unittest.TestCase):
    def test_my_auctions_shows_total_on_sale_and_pending(self):
        run(SETUP + '''local F, UI = ForeverFlip, ForeverFlip.UI
        F.Trade.owned = {
            { auctionID = 1, key = 'c:10', id = 10, qty = 164, price = 53, sold = false },
            { auctionID = 2, key = 'i:30', id = 30, qty = 1, price = 9800, sold = false },
            { auctionID = 3, key = 'c:10', id = 10, qty = 10, price = 60, sold = true },
        }
        U = F.Util; U.coins = false
        UI.show('auctions'); UI.refresh()
        local line = UI.auctionTotal:GetText():gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')
        assert(line:find('Total on sale: 1g 84s') and line:find('6s 0c pending'), line)
        assert(not UI.auctionText:GetText():find('Check prices'), UI.auctionText:GetText())''')


class NoResaleReasonTests(unittest.TestCase):
    def test_the_empty_resale_page_names_the_reasons(self):
        run(SETUP + '''local F, UI = ForeverFlip, ForeverFlip.UI
        local text = UI.noResaleText({ salesReady = 100, onePair = 90,
            reasons = { thin = 40, small = 12, not_selling = 300, no_gap = 5000 } })
        assert(text:find('300 are not bought'), text)
        assert(text:find('40 sell, but too few purchases'), text)
        assert(text:find('12 would earn less than your minimum'), text)
        assert(text:find('90 items were measured over one pair'), text)
        local first = text:find('300 are not bought'); local second = text:find('40 sell')
        assert(first < second, 'most common first')''')

    def test_one_scan_pair_reports_thin_not_unsold(self):
        run(SETUP + '''local M = ForeverFlip.Market
        local h = {}
        M.recordSales(h, { [7700] = 40 }, 900, now)
        local ctx = { kind = 'commodity', vendor = 10, budget = 10000000, history = h, market = 7800, now = now,
            settings = { minProfit = 1, minROI = 0.01 } }
        local d, why = M.evaluate({ { unit = 900, qty = 5 }, { unit = 7800, qty = 16 } }, ctx)
        assert(not d and why == 'thin', tostring(why))''')
