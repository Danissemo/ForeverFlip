"""Check all as fast as it can go, and how sure a resale is to pay back (Sure)."""
import unittest

from test_addon import SETUP, run

GEAR = SETUP + '''enableBrowse()
local F, D, U, A = ForeverFlip, ForeverFlip.Deals, ForeverFlip.Util, ForeverFlip.AH
F.Engine.autoVerify = false
local nature = U.key('gear', 20, 'Northern Shortsword of Nature Protection')
local healing = U.key('gear', 20, 'Northern Shortsword of Healing')
local function searches()
    local n = 0
    for _, c in ipairs(calls) do if c[1] == 'SendSearchQuery' then n = n + 1 end end
    return n
end
'''


class GearVersionTests(unittest.TestCase):
    def test_a_version_learns_its_ending_from_its_lots(self):
        run(GEAR + '''for i = #auctions, 1, -1 do
            if auctions[i].item == 20 and auctions[i].name ~= 'Northern Shortsword of Nature Protection' then
                table.remove(auctions, i)
            end
        end
        local key = { itemID = 20, itemLevel = 18, itemSuffix = 14320 }
        local name, rows, mixed = A.versionRows(key)
        assert(name == 'northern shortsword of nature protection' and #rows == 2 and not mixed, tostring(name))
        assert(F.db.itemKeys[20].list[1].e == name, 'remembered for the version')
        local keys, every = A.cachedKeys(U.parseKey(nature))
        assert(#keys == 1 and every)''')

    def test_a_version_with_several_endings_teaches_nothing(self):
        run(GEAR + '''local name, _, mixed = A.versionRows({ itemID = 20, itemLevel = 18, itemSuffix = 14320 })
        assert(name == nil and mixed)''')

    def test_versions_of_another_ending_are_not_searched(self):
        run(GEAR + '''F.db.itemKeys = { [20] = { at = now, list = {
            { l = 18, s = 1, e = 'northern shortsword of healing' },
            { l = 18, s = 2, e = 'northern shortsword of nature protection' },
            { l = 18, s = 3 } } } }
        local keys, every = A.cachedKeys(U.parseKey(nature))
        assert(#keys == 2 and not every, 'its own version and the one not known yet')
        assert(keys[1].itemSuffix == 2 and keys[2].itemSuffix == 3)''')

    def test_one_sweep_answers_every_ending_of_the_item(self):
        run(GEAR + '''fullScan()
        local got = {}
        D.enqueue(nature, function(_, rows, complete) got.nature = complete end)
        D.enqueue(healing, function(_, rows, complete) got.healing = { rows = rows, complete = complete } end)
        assert(D.queued[healing], 'waits behind the first')
        local n = D.shareSweep(20, nature, { ['northern shortsword of healing'] = {
            { unit = 5000, qty = 1, auctionID = 9 }, { unit = 400, qty = 1, auctionID = 8 } } })
        assert(n == 1 and not D.queued[healing], 'answered from the sweep')
        assert(got.healing and got.healing.complete and got.healing.rows[1].unit == 400, 'cheapest first')''')

    def test_an_ending_without_lots_in_the_sweep_keeps_its_own_search(self):
        run(GEAR + '''fullScan()
        D.enqueue(nature, function() end)
        D.enqueue(healing, function() end)
        assert(D.shareSweep(20, nature, {}) == 0 and D.queued[healing])''')


class AloneTests(unittest.TestCase):
    def test_no_answer_for_an_item_nobody_else_sells_is_that_answer(self):
        run(SETUP + '''local F, D = ForeverFlip, ForeverFlip.Deals
        F.Engine.autoVerify = false
        fullScan()
        F.Scan.last.listed['i:31'] = nil
        F.Scan.last.at = now - 3000 -- older than 20 minutes, within 2 hours
        F.AH.search = function() end -- the server never answers
        local got
        D.enqueue('i:31', function(_, rows, complete) got = { rows = rows, complete = complete } end, nil, true)
        run(D.FAST_WAIT + 3)
        assert(got and got.rows and #got.rows == 0 and got.complete, 'answered: nobody else sells it')''')

    def test_an_item_others_sell_still_fails_without_an_answer(self):
        run(SETUP + '''local F, D = ForeverFlip, ForeverFlip.Deals
        F.Engine.autoVerify = false
        fullScan()
        F.AH.search = function() end
        local got
        D.enqueue('c:10', function(_, rows) got = { rows = rows } end, nil, true)
        run(D.FAST_WAIT + 3)
        assert(got and got.rows == nil, 'others sell it: unknown, not empty')''')


class PacingTests(unittest.TestCase):
    def test_a_check_of_check_all_gives_up_sooner(self):
        run(SETUP + '''local F, D = ForeverFlip, ForeverFlip.Deals
        F.Engine.autoVerify = false
        F.AH.search = function() end -- never answered
        local done
        D.enqueue('c:10', function(_, rows) done = rows == nil end, nil, true)
        run(D.FAST_WAIT + 3) -- up to 2 seconds for the item's data, then the wait
        assert(done and D.FAST_WAIT + 3 < D.ANSWER_WAIT, 'gave up before the usual wait')''')

    def test_a_selected_deal_holds_check_all_only_briefly(self):
        run(SETUP + '''assert(ForeverFlip.Deals.SELECTED_HOLD <= 3)''')

    def test_check_all_loads_every_item_first(self):
        run(SETUP + '''local F, D = ForeverFlip, ForeverFlip.Deals
        fullScan(); F.Engine.autoVerify = false
        local asked = {}
        local real = F.AH.keyInfoReady
        F.AH.keyInfoReady = function(item, key) asked[item.id] = true; return real(item, key) end
        local keys = {}
        for _, d in ipairs(D.list) do keys[#keys + 1] = d.key end
        D.startBatch('deals:all', keys, true)
        for _, d in ipairs(D.list) do assert(asked[d.id], d.key) end''')


SURE = SETUP + '''local F, M = ForeverFlip, ForeverFlip.Market
local function history(units, hours, sure, lots, extra)
    local h = { sales = { pairs = 4, hours = hours, at = now, b = {}, sure = sure or units, lots = lots or 0 } }
    M.bucketAdd(h.sales.b, 1000, units)
    for k, v in pairs(extra or {}) do h.sales[k] = v end
    return h
end
'''


class SureTests(unittest.TestCase):
    def test_few_sales_are_no_promise_however_fast(self):
        run(SURE + '''local fast = M.confidence(history(4, 1), 1000, 1, now)
        local steady = M.confidence(history(40, 24), 1000, 1, now)
        assert(steady > 0.9, 'forty sales in a day: ' .. steady)
        assert(fast < steady, fast .. ' vs ' .. steady)''')

    def test_one_buyer_of_four_is_not_four_buyers(self):
        run(SURE + '''local one = history(4, 1); one.sales.log = { now .. ':1000:4:p' }
        local four = history(4, 1)
        four.sales.log = { now .. ':1000:1:p', now .. ':1000:1:p', now .. ':1000:1:p', now .. ':1000:1:p' }
        local a, parts = M.confidence(one, 1000, 1, now)
        local b = M.confidence(four, 1000, 1, now)
        assert(parts.perBuy == 4 and a < b, a .. ' vs ' .. b)''')

    def test_before_lots_are_tracked_disappearances_give_a_capped_number(self):
        run(SURE + '''fullScan()
        local d
        for _, x in ipairs(F.Deals.list) do if x.mode == 'flip' then d = x end end
        local h = F.Data.market(F.db, F.Engine.scope()).history[d and d.key or 'c:10']
        if d then h.sales = nil end
        local h2 = { flow = { pairs = 1, hours = 0.25, at = now, market = 1000, sold = { 1, 1, 1, 1, 1, 1, 1, 1 } } }
        local sure, parts = M.confidence(h2, 1000, 1, now)
        assert(sure and parts.flow and sure <= M.FLOW_SURE_MAX, tostring(sure))
        local line = F.UI.sureSentence({ mode = 'flip', key = 'x', exit = 1000, qty = 1 }, now)
        assert(line == nil or line:find('Sure'), 'no crash without history')''')

    def test_more_units_are_less_sure(self):
        run(SURE + '''local h = history(10, 24)
        assert(M.confidence(h, 1000, 1, now) > M.confidence(h, 1000, 10, now))''')

    def test_sales_below_the_price_do_not_count(self):
        run(SURE + '''local h = history(40, 24)
        assert(M.confidence(h, 1200, 1, now) < 0.2, 'nobody paid 1200: ' .. M.confidence(h, 1200, 1, now))''')

    def test_whole_lots_count_half(self):
        run(SURE + '''local buyers = M.confidence(history(6, 24, 6, 0), 1000, 3, now)
        local lots = M.confidence(history(6, 24, 0, 6), 1000, 3, now)
        local _, parts = M.confidence(history(6, 24, 0, 6), 1000, 3, now)
        assert(lots < buyers and parts.real == 0.5)''')

    def test_sweeps_rivals_and_old_data_lower_it(self):
        run(SURE + '''local base = M.confidence(history(20, 24), 1000, 5, now)
        assert(M.confidence(history(20, 24, nil, nil, { sweeps = 4 }), 1000, 5, now) < base, 'sweeps')
        assert(M.confidence(history(20, 24, nil, nil, { cuts = 24 }), 1000, 5, now) < base, 'a rival')
        assert(M.confidence(history(20, 24), 1000, 5, now + 4 * 86400) < base, 'old data')''')

    def test_vendor_deals_are_sure_and_the_page_shows_it(self):
        run(SETUP + '''local F, UI = ForeverFlip, ForeverFlip.UI
        fullScan()
        local d = F.Deals.get('c:10')
        assert(d.mode == 'vendor' and F.Deals.sure(d) == 1)
        UI.show('deals:all'); UI.refresh()
        local found
        for _, r in ipairs(UI.dealTable.rows) do
            if r.key == 'c:10' then found = r.cols[6]:GetText() end
        end
        assert(found and found:find('100%%'), tostring(found))''')

    def test_the_detail_explains_the_number(self):
        run(SURE + '''local UI = F.UI
        local d = { mode = 'flip', key = 'i:30', exit = 1000, qty = 2 }
        F.Data.market(F.db, F.Engine.scope()).history['i:30'] = history(20, 24)
        local line = UI.sureSentence(d, now)
        assert(line and line:find('chance real buyers take 2'), tostring(line))''')



class VendorWalletTests(unittest.TestCase):
    def test_a_vendor_deal_shrinks_to_the_money_in_the_bags(self):
        run(SETUP + '''local F, D = ForeverFlip, ForeverFlip.Deals
        fullScan()
        local d = D.get('c:10')
        assert(d and d.mode == 'vendor' and d.qty > 1, 'a vendor deal of several units')
        local unit = d.lots[1].unit
        money = unit * 2 + 1
        D.fitWallet(d)
        assert(d.qty == 2 and d.cost == unit * 2 and d.cost <= money, d.qty .. ' for ' .. d.cost)
        assert(d.profit == 2 * d.exit - d.cost)''')

    def test_a_vendor_deal_may_use_all_the_money(self):
        run(SETUP + '''local F = ForeverFlip
        local deal = F.Market.evaluate({ { unit = 50, qty = 100 } }, {
            kind = 'commodity', vendor = 100, budget = 800, vendorBudget = 1000, settings = {} })
        assert(deal and deal.qty == 20, deal and deal.qty)''')


if __name__ == '__main__':
    unittest.main()
