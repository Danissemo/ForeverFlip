"""Review fixes in Deals.lua: the exact-search queue, deal fitting and checks after a purchase."""
import unittest

from test_addon import SETUP, run
from test_buy_run import RUN

BASE = SETUP + '''local F = ForeverFlip
local D, T, U, UI, S = F.Deals, F.Trade, F.Util, F.UI, F.Scan
local function searches()
    local n = 0
    for _, c in ipairs(calls) do
        if c[1] == 'SendSearchQuery' or c[1] == 'SendSellSearchQuery' or c[1] == 'SendBrowseQuery' then n = n + 1 end
    end
    return n
end
local nature = U.key('gear', 20, 'Northern Shortsword of Nature Protection')
local healing = U.key('gear', 20, 'Northern Shortsword of Healing')
'''


class ScanWaitTests(unittest.TestCase):
    """V12-a: only the player's clicks may search while a full scan waits for its answer."""

    WAIT = BASE + '''fullScan()
    UI.show('deals:all'); UI.refresh()
    now = now + 1000; run(0.1)
    assert(S.start() and S.blocking())
    '''

    def test_buy_hover_waits_and_a_click_goes_first(self):
        run(self.WAIT + '''UI.selected, UI.selectedAt = 'c:10', now
        local before = searches()
        UI.buyButton.scripts.OnEnter(UI.buyButton) -- the pointer on Buy: no click
        run(1)
        assert(searches() == before and D.pending('c:10'), 'a hover waits for the scan')
        UI.selectDeal(nature) -- a click on another deal's row
        run(0.1)
        assert(D.search and D.search.key == nature, 'the click goes, before the hovered check')''')

    def test_the_buy_run_frame_step_waits(self):
        run(self.WAIT + '''UI.show('deals:vendor'); UI.refresh()
        T.run = { skipped = {}, bought = 0, clicked = now } -- a run, then only frames
        local before = searches()
        run(0.5)
        assert(searches() == before and not D.search, 'no check of the run from a frame')''')

    def test_check_all_promoted_without_a_click_still_waits(self):
        run(self.WAIT + '''F.Engine.input(); D.startBatch(F.Engine.scope(), { 'c:10' }, true) -- the click on Check all
        run(1)
        assert(not D.search and D.pending('c:10'), 'Check all waits for the scan')
        D.verify('c:10') -- promoted by the run's frame step: no click
        run(0.5)
        assert(not D.search, 'still waits')''')

    def test_a_gear_search_between_versions_waits_unless_clicked(self):
        run(BASE + '''fullScan()
        F.db.itemKeys = { [20] = { at = now, list = { { l = 18, s = 1 }, { l = 18, s = 2 } } } }
        D.verify(nature) -- from a hover: no click
        assert(D.search and D.search.phase == 'keys' and not D.search.waitKey, 'first version sent')
        throttleReady = false
        fire('ITEM_SEARCH_RESULTS_UPDATED', D.search.keys[D.search.keyIndex])
        assert(D.search and D.search.waitKey, 'the second version waits')
        throttleReady = true; now = now + 1000
        assert(S.start() and S.blocking())
        local before = searches()
        run(1)
        assert(searches() == before, 'not sent while the scan waits')
        F.Engine.input(); D.verify(nature) -- the player clicks it
        run(0.1)
        assert(searches() == before + 1, 'a click continues it')''')


class OnlyYoursTests(unittest.TestCase):
    """V12-b: a search without an answer is "nobody else sells it" only for the player's own items."""

    LATE = BASE + '''addItem(50, 'Moonberry Juice', 2000, 'item')
    fullScan()
    for i = 1, 3 do addAuction(50, 1000 + i, 1) end -- listed after the scan
    D.verify('i:50'); answer()
    assert(D.get('i:50') and D.get('i:50').verified)
    now = now + 600; run(0.1)
    local why
    local function check() why = nil; D.verify('i:50', function(_, reason) why = reason end); run(12) end
    '''

    def test_no_answer_for_a_deal_listed_after_the_scan_keeps_the_deal(self):
        run(self.LATE + '''check()
        assert(D.get('i:50') and why == 'search_failed', tostring(why))''')

    def test_a_deal_checked_after_the_scan_proves_another_seller(self):
        run(self.LATE + '''T.owned = { { auctionID = 99, id = 50, key = 'i:50', qty = 1, price = 5000 } }
        check()
        assert(D.get('i:50') and why == 'search_failed', tostring(why))''')


class FitWalletTests(unittest.TestCase):
    """V12-e, V12-f, V26-e: a vendor deal fits the money (and the visit's limit) without losing units."""

    def test_the_deal_grows_back_when_the_money_does(self):
        run(BASE + '''fullScan(); D.verify('c:10'); answer()
        money = 500
        local d = D.fitWallet(D.get('c:10'))
        assert(d.qty == 8 and d.cost == 480, d.qty)
        money = 1000000
        d = D.fitWallet(D.get('c:10'))
        assert(d.qty == 15 and d.cost == 900 and d.profit == 600, d.qty)''')

    def test_a_bucket_of_identical_auctions_fits_in_part(self):
        run(BASE + '''addItem(40, 'Moon Gem', 2000, 'item')
        for i = 1, 5 do addAuction(40, 1000, 1) end
        addAuction(40, 9000, 1)
        fullScan(); D.verify('i:40'); answer()
        money = 3000
        local d = D.fitWallet(D.get('i:40'))
        assert(d.qty == 3 and d.cost == 3000 and d.lots[1].qty == 3, d.qty)
        assert(D.best() and D.best().key == 'i:40', 'Buy next takes it')''')

    def test_the_visit_spending_limit_fits_the_deal_too(self):
        run(BASE + '''fullScan()
        F.db.settings.spendLimit = 1; F.Engine.spent = 9500 -- 5s left of 1g
        D.verify('c:10'); answer()
        local d = D.fitWallet(D.get('c:10'))
        assert(d.qty == 8 and d.cost == 480, d.qty)
        F.Engine.spent = 0
        assert(D.fitWallet(d).qty == 15)''')


class ThrottleTests(unittest.TestCase):
    """V19-a, V19-e: a stuck throttle's one message is not spent by a check that then waits."""

    def test_a_sniper_candidate_is_searched_with_a_stuck_throttle(self):
        run(BASE + '''enableBrowse(2)
        fullScan()
        F.db.settings.sniper = true; T.ownedDue = now + 1000
        local Sn, guard = F.Sniper, 0
        while guard < 400 do
            run(0.1)
            if D.search and not D.search.waitKey then answer()
            elseif browsePendingNow() then browseAnswer()
            elseif not Sn.query and #Sn.candidates == 0 and not D.search and #D.requests == 0 then break end
            guard = guard + 1
        end
        table.insert(Sn.candidates, { key = 'c:10', score = 1 })
        throttleReady = false
        local before = #calls
        run(30)
        local sent = false
        for i = before + 1, #calls do
            if calls[i][1] == 'SendSearchQuery' and calls[i][2] == 10 then sent = true end
        end
        assert(sent, 'the candidate got the message the stuck throttle lets through')''')

    def test_a_held_gear_version_leaves_the_stuck_throttle_to_buy(self):
        run(BASE + '''fullScan(); T.ownedDue = now + 1000
        UI.show('deals:all')
        D.verify('c:10'); answer()
        F.db.itemKeys = { [20] = { at = now, list = { { l = 18, s = 14320 }, { l = 19, s = 14321 } } } }
        run(0.5)
        D.startBatch(F.Engine.scope(), { nature }, true)
        local guard = 0
        while not (D.search and D.search.key == nature and not D.search.waitKey) and guard < 100 do
            run(0.05); guard = guard + 1
        end
        UI.selected, UI.buyHoverKey = 'c:10', 'c:10' -- the pointer on Buy: Check all is held
        fire('ITEM_SEARCH_RESULTS_UPDATED', D.search.keys[D.search.keyIndex])
        assert(D.search and D.search.waitKey)
        throttleReady = false
        local free = false
        for _ = 1, 200 do
            run(0.05)
            if F.AH.available() then free = true; break end
        end
        assert(free and D.search.waitKey, 'the held version did not take it')''')


class DroppedBrowseTests(unittest.TestCase):
    """V19-b, V20-c: a browse left without its answer is foreign to other items only."""

    def test_the_retry_of_a_dropped_browse_can_be_complete(self):
        run(BASE + '''enableBrowse()
        fullScan(); F.db.itemKeys = {}; T.ownedDue = now + 1000
        local got
        D.verify(nature, function(d) got = d end)
        assert(D.search and D.search.phase == 'browse')
        fire('AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED')
        local waited = 0
        while not (D.search and D.search.phase == 'browse') and waited < 30 do run(0.05); waited = waited + 0.05 end
        assert(D.search and not D.search.foreign, 'its own retry is not foreign')
        answer()
        local guard = 0
        while D.search and guard < 200 do
            run(0.05)
            if D.search and not D.search.waitKey then answer() end
            guard = guard + 1
        end
        assert(got and D.get(nature).verified, 'the retry verified the deal')''')

    def test_stop_during_a_browse_keeps_its_late_answer_from_the_next_item(self):
        run(BASE + '''addItem(40, 'Ironwood Staff', 3000, 'gear')
        addAuction(40, 1000, 1, 'Seller', 'Ironwood Staff of the Owl')
        fullScan()
        F.db.itemKeys = {}
        local staff = U.key('gear', 40, 'Ironwood Staff of the Owl')
        assert(D.get(healing) and D.get(staff))
        local shown = {}
        C_AuctionHouse.SendBrowseQuery = function() shown = {} end
        C_AuctionHouse.GetBrowseResults = function() return shown end
        C_AuctionHouse.HasFullBrowseResults = function() return true end
        C_AuctionHouse.RequestMoreBrowseResults = function() end
        C_AuctionHouse.SearchForItemKeys = function() end
        D.verify(healing)
        assert(D.search and D.search.phase == 'browse')
        D.stopAll() -- Stop while the sword's browse is on the wire
        run(0.3)
        D.verify(staff); run(0.1)
        assert(D.search and D.search.key == staff and D.search.foreign, 'the staff search knows')
        -- the sword's late answer arrives: complete, without the staff
        shown = { { itemKey = { itemID = 20, itemLevel = 0, itemSuffix = 0 }, minPrice = 400, totalQuantity = 4 } }
        fire('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
        assert(D.get(staff), 'not removed as nobody sells it')''')


class InfoWaitTests(unittest.TestCase):
    """V20-a: the wait for an item's auction house data ends for automatic checks too."""

    def test_an_automatic_check_goes_after_the_item_data_wait(self):
        run(BASE + '''fullScan()
        local idx
        for i, d in ipairs(D.list) do if d.key == 'c:10' then idx = i end end
        table.insert(D.list, 1, table.remove(D.list, idx))
        items[10].cached = false -- its item key data never comes
        F.db.settings.autoVerify = true
        local before = #calls
        run(5)
        local sent = 0
        for i = before + 1, #calls do
            if calls[i][1] == 'SendSearchQuery' and calls[i][2] == 10 then sent = sent + 1 end
        end
        assert(sent >= 1, 'sent after 2 seconds of waiting')''')


GEAR_VERSIONS = BASE + '''fullScan()
-- Two item-key versions of the sword. s=1 holds another seller's Healing lot, s=2 only the player's
-- own: WoW Forever never answers a search that only the player's own lots match.
local sword = link(20, 'Northern Shortsword of Healing')
local byVersion = {
    [1] = { { itemKey = { itemID = 20, itemLevel = 18, itemSuffix = 1 }, itemLink = sword,
        quantity = 1, buyoutAmount = 400, auctionID = 501 } },
    [2] = { { itemKey = { itemID = 20, itemLevel = 18, itemSuffix = 2 }, itemLink = sword,
        quantity = 1, buyoutAmount = 700, auctionID = 502, containsOwnerItem = true } },
}
C_AuctionHouse.GetNumItemSearchResults = function(key) return #(byVersion[key.itemSuffix] or {}) end
C_AuctionHouse.GetItemSearchResultInfo = function(key, i) return (byVersion[key.itemSuffix] or {})[i] end
F.db.itemKeys = { [20] = { at = now, list = { { l = 18, s = 1 }, { l = 18, s = 2 } } } }
local function own() -- the player's auction under s=2
    T.owned = { { auctionID = 502, id = 20, itemKey = { itemID = 20, itemLevel = 18, itemSuffix = 2 }, key = healing,
        qty = 1, price = 700 } }
end
local function check()
    local got
    D.enqueue(healing, function(_, rows, complete) got = { rows = rows, complete = complete } end, nil, true)
    for _ = 1, 400 do
        local s = D.search
        if s and s.phase == 'keys' and not s.waitKey and s.keys[s.keyIndex].itemSuffix ~= 2 and not s.served then
            s.served = true
            fire('ITEM_SEARCH_RESULTS_UPDATED', s.keys[s.keyIndex])
            if D.search == s then s.served = nil end
        end
        run(0.05)
        if got then break end
    end
    return got
end
'''


class GearVersionTimeoutTests(unittest.TestCase):
    """V20-b: one version without an answer does not throw away the others' lots."""

    def test_a_version_with_only_the_players_lot_is_passed_over(self):
        run(GEAR_VERSIONS + '''own()
        local got = check()
        assert(got and got.rows and #got.rows == 1 and got.rows[1].unit == 400 and got.complete,
            got and tostring(got.rows))''')

    def test_an_unexplained_silent_version_keeps_the_lots_found(self):
        run(GEAR_VERSIONS + '''T.owned = {}
        local got = check()
        assert(got and got.rows and #got.rows == 1 and not got.complete, 'found, but maybe not the cheapest')''')

    def test_rows_found_are_never_answered_as_nobody_else_sells_it(self):
        run(GEAR_VERSIONS + '''own()
        S.last.listed[healing] = nil -- the scan saw no other seller: one listed since, under s=1
        local got = check()
        assert(got and got.rows and #got.rows == 1, got and got.rows and #got.rows)''')


class SureCacheTests(unittest.TestCase):
    """V24-e: the tooltip's two questions about one item keep their own answers."""

    def test_each_price_and_quantity_keeps_its_entry(self):
        run(BASE + '''fullScan()
        local n, conf = 0, F.Market.confidence
        F.Market.confidence = function(...) n = n + 1; return conf(...) end
        for _ = 1, 3 do D.sureAt('c:10', 100, 1, now); D.sureAt('c:10', 100, 15, now) end
        assert(n == 2, n)
        D.sureAt('c:10', 100, 1, now + D.SURE_KEEP)
        assert(n == 3, 'still expires')''')


class LearnTests(unittest.TestCase):
    """V24-f: a search of the game's Buy tab does not parse the whole price history."""

    def test_only_the_items_own_gear_keys_are_read(self):
        run(BASE + '''fullScan()
        local history = F.Data.market(F.db, F.Engine.scope()).history
        for i = 1, 2000 do history['c:' .. (400000 + i)] = { scan = { at = now, market = 5000 } } end
        history['g:200:northern shortsword of x'] = { scan = { at = now, market = 3000 } }
        local parses, read, pk, rows = 0, {}, U.parseKey, F.AH.rows
        U.parseKey = function(k) parses = parses + 1; return pk(k) end
        F.AH.rows = function(item, key)
            read[#read + 1] = item.id .. ':' .. tostring(item.name)
            return rows(item, key)
        end
        fire('ITEM_SEARCH_RESULTS_UPDATED', { itemID = 20, itemLevel = 18, itemSuffix = 14320 })
        U.parseKey, F.AH.rows = pk, rows
        assert(parses < 100, parses)
        assert(#read == 2, #read)
        for _, r in ipairs(read) do assert(r:find('^20:northern shortsword of '), r) end''')


class ShopTests(unittest.TestCase):
    """V25-d: a disenchant bucket does not replace a shopping list deal."""

    def test_a_shopping_deal_stays_a_shopping_deal(self):
        run(BASE + '''F.Shopping.add(healing, 100000, nil, 'Northern Shortsword of Healing')
        F.Disenchant.active = function() return true end
        F.Disenchant.evaluate = function(rows)
            return { mode = 'disenchant', qty = #rows, cost = 50000 * #rows, profit = 10000 * #rows, lots = {} }
        end
        local rows = {}
        for i = 1, 6 do rows[i] = { unit = 50000, qty = 1, auctionID = 1000 + i } end
        local d = D.evaluate({ key = healing, kind = 'gear', id = 20, rows = rows, link = link(20) }, 1070, nil, now)
        assert(d and d.mode == 'shop' and d.qty == 1, d and d.mode)''')


class PendingTests(unittest.TestCase):
    """V25-e: the per-frame pending test makes no garbage."""

    def test_pending_without_owned_checks_allocates_nothing(self):
        run(BASE + '''T.checkQueue = nil
        D.pending()
        collectgarbage('collect'); collectgarbage('stop')
        local before = collectgarbage('count')
        for _ = 1, 10000 do D.pending(); D.pending('c:10') end
        local grown = collectgarbage('count') - before
        collectgarbage('restart')
        assert(grown < 16, grown .. ' KB')''')


class StopTests(unittest.TestCase):
    """V18-d, V27-e: Stop ends the own-auction checks and Buy all to vendor."""

    def test_stop_ends_the_own_auction_checks(self):
        run(BASE + '''owned = {}
        for i = 1, 5 do
            addItem(100 + i, 'Thing ' .. i, 10, 'commodity'); addAuction(100 + i, 200, 1)
            owned[i] = { auctionID = 1000 + i, itemKey = { itemID = 100 + i }, quantity = 1, buyoutAmount = 400,
                status = 0 }
        end
        fire('OWNED_AUCTIONS_UPDATED')
        assert(T.checkOwned() == 5)
        run(0.05)
        D.stopAll()
        assert(T.checksRemaining() == 0, 'nothing left shown as checking')
        assert(T.checkOwned() == 5, 'Check prices starts again')''')

    def test_stop_ends_buy_all_to_vendor(self):
        run(RUN + '''T.runStart(); assert(T.run)
        D.stopAll()
        assert(not T.run, 'the run ended')
        run(1)
        assert(not D.search and not D.pending(), 'no check of the run after Stop')''')


class VersionsTests(unittest.TestCase):
    """V13-b: callbacks read an answer under the keys it came under (D.versions)."""

    def test_a_plain_search_answered_under_its_exact_key(self):
        run(BASE + '''local versions
        D.enqueue('i:30', function() versions = D.versions end)
        assert(D.search and D.search.key == 'i:30')
        fire('ITEM_SEARCH_RESULTS_UPDATED', { itemID = 30, itemLevel = 5, itemSuffix = 0 })
        assert(versions and #versions == 1 and versions[1].itemLevel == 5)''')

    def test_a_request_answered_from_another_endings_sweep(self):
        run(BASE + '''fullScan()
        -- Search results per exact version, one ending each.
        local ending = { [1] = 'northern shortsword of healing', [2] = 'northern shortsword of nature protection' }
        local answered = {}
        local function rowsFor(key)
            local out = {}
            if not answered[key.itemSuffix] then return out end
            for _, r in ipairs(itemRows(key.itemID)) do
                if string.lower(U.linkName(r.itemLink) or '') == ending[key.itemSuffix] then out[#out + 1] = r end
            end
            return out
        end
        C_AuctionHouse.GetNumItemSearchResults = function(key) return #rowsFor(key) end
        C_AuctionHouse.GetItemSearchResultInfo = function(key, i) return rowsFor(key)[i] end
        F.db.itemKeys = { [20] = { at = now, list = { { l = 18, s = 1 }, { l = 18, s = 2 } } } }
        local versions
        D.enqueue(healing, function() end)
        D.enqueue(nature, function() versions = D.versions end)
        local guard = 0
        while D.search and guard < 40 do
            local s = D.search
            if s.waitKey then run(0.05) else
                answered[s.keys[s.keyIndex].itemSuffix] = true
                fire('ITEM_SEARCH_RESULTS_UPDATED', s.keys[s.keyIndex])
            end
            guard = guard + 1
        end
        assert(not D.queued[nature], 'answered from the sweep')
        assert(versions and #versions == 2, 'the versions searched')''')


class AfterPurchaseTests(unittest.TestCase):
    """V27-d: buying one auction of a bucket leaves its other auctions in the deal."""

    def test_the_rest_of_a_bucket_stays_and_is_read_again(self):
        run(BASE + '''addItem(40, 'Heavy Box', 2000, 'item')
        for _ = 1, 3 do addAuction(40, 1000, 1) end
        fullScan(); D.verify('i:40'); answer()
        assert(D.get('i:40').qty == 3 and #D.get('i:40').rows == 1, 'one row of three auctions')
        assert(T.buy('i:40'))
        local bought = lastCall('PlaceBid')[2]
        for i, a in ipairs(auctions) do if a.id == bought then table.remove(auctions, i) break end end
        money = money - 1000; fire('PLAYER_MONEY')
        local d = D.get('i:40')
        assert(d and d.qty == 2 and not d.lots[1].auctionID, 'two left, their auctions not known yet')
        assert(D.pending('i:40'), 'read again')
        run(0.3); answer()
        d = D.get('i:40')
        assert(d and d.qty == 2 and d.lots[1].auctionID and d.lots[1].auctionID ~= bought)''')


if __name__ == '__main__':
    unittest.main()
