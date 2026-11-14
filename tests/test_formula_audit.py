"""The formula audit of 13 November 2026: each confirmed defect, fixed."""
import unittest

from test_addon import SETUP, run
from test_audit import AntiUndercutTests


class SaleChancesTests(unittest.TestCase):
    def test_a_far_tail_is_not_read_as_certain(self):
        run(SETUP + '''local T = ForeverFlip.Trade
        local p = T.saleChances(1000, 24, 48)(2000)
        assert(p > 2e-5 and p < 5e-5, 'about 0.0031%: ' .. p)
        local q = T.saleChances(1000, 24, 48)(1500)
        assert(q > 0.9 and q < 1, tostring(q))''')

    def test_the_tail_falls_as_k_grows(self):
        run(SETUP + '''local tail = ForeverFlip.Trade.saleChances(30, 12, 24)
        local last = 1
        for k = 1, 200 do local p = tail(k); assert(p <= last + 1e-12, k); last = p end
        assert(tail(0) == 1)''')


class UndercutDepositTests(unittest.TestCase):
    def test_cancelling_does_not_lose_the_old_deposit_twice(self):
        run(AntiUndercutTests.PLAN + '''local plan = T.fightPlans()[1]
        local vendor = F.AH.vendorPrice(30, true)
        local fee = plan.cancel - F.Trade.depositFor(F.AH.keyFor(30), 1, 2) -- what the cancel books
        assert(plan.vendor.ev == vendor - fee, plan.vendor.ev .. ' vs ' .. (vendor - fee))''')


class BidReturnTests(unittest.TestCase):
    def test_a_first_bid_keeps_the_minimum_return(self):
        run(SETUP + '''local F, B = ForeverFlip, ForeverFlip.Bids
        local s = F.db.settings
        s.minProfit, s.minROI = 100, 0.2
        local worth = B.value('i:30', 30, F.Data.market(F.db, F.Engine.scope()).history)
        local j = { scope = F.Engine.scope() }
        B.consider(j, 'i:30', 'item', { id = 30, band = 0, minBid = worth - 150, count = 1 })
        B.finish(j, F.Data.market(F.db, j.scope).history)
        assert(#B.candidates == 0, 'profit above the minimum, but the return is under 20%')
        j = { scope = F.Engine.scope() }
        B.consider(j, 'i:30', 'item', { id = 30, band = 0, minBid = B.maxBid(worth), count = 1 })
        B.finish(j, F.Data.market(F.db, j.scope).history)
        assert(#B.candidates == 1)''')


class LotMatchingTests(unittest.TestCase):
    def test_another_sellers_smaller_lot_is_no_partial_sale(self):
        run(SETUP + '''local M = ForeverFlip.Market
        -- Seller 111 left and seller 222 came: no sure sale, only a vanished lot that the next scan
        -- must confirm (the gone list), never 5 units read as bought out of one lot.
        local _, byPrice, gone = M.trackSales({ 100, 10, 3 }, { 100, 5, 3 }, 900, { 111 }, { 222 })
        local suspect = gone[2] or 0
        assert((byPrice[100] or 0) - suspect == 0 and suspect == 10, 'sure sales: ' .. ((byPrice[100] or 0) - suspect))
        local sold = M.trackSales({ 100, 10, 3 }, { 100, 5, 3 }, 900, { 111 }, { 111 })
        assert(sold == 5, 'the same seller: 5 bought')''')


class SureFilterTests(unittest.TestCase):
    def test_purchases_at_another_price_do_not_raise_sure(self):
        run(SETUP + '''local M = ForeverFlip.Market
        local function h(extra)
            local x = { sales = { pairs = 4, hours = 24, at = now, b = {}, sure = 0, lots = 10, log = {} } }
            M.bucketAdd(x.sales.b, 1000, 10)
            for i = 1, 10 do x.sales.log[#x.sales.log + 1] = now .. ':1000:1:l' end
            if extra then
                x.sales.sure = 100
                for i = 1, 10 do table.insert(x.sales.log, 1, now .. ':1:10:p') end
            end
            return x
        end
        local a = M.confidence(h(false), 1000, 5, now)
        local b = M.confidence(h(true), 1000, 5, now)
        assert(math.abs(a - b) < 1e-9, a .. ' vs ' .. b)''')


class SweepRateTests(unittest.TestCase):
    def test_a_long_pair_at_the_usual_rate_is_not_a_sweep(self):
        run(SETUP + '''local M = ForeverFlip.Market
        local h, t = {}, now
        for _ = 1, 3 do t = t + 900; M.recordSales(h, { [100] = 4 }, 900, t) end
        t = t + 3 * 3600
        M.recordSales(h, { [100] = 48 }, 3 * 3600, t)
        assert((h.sales.sweeps or 0) < 0.5, 'the same 16 an hour: ' .. tostring(h.sales.sweeps))''')

    def test_sweeps_fade_with_the_pairs(self):
        run(SETUP + '''local M = ForeverFlip.Market
        local h = { sales = { pairs = 99, pairsSeen = 99, sweeps = 99, hours = 10, at = now, b = {}, rates = {} } }
        local t = now
        for _ = 1, 60 do t = t + 3 * 3600; M.recordSales(h, { [100] = 1 }, 900, t) end
        assert(h.sales.sweeps / h.sales.pairsSeen < 0.5, 'old sweeps weigh less: ' .. h.sales.sweeps / h.sales.pairsSeen)''')


class LostDepositTests(unittest.TestCase):
    def test_a_rarely_sold_item_loses_many_deposits(self):
        run(SETUP + '''local F, M = ForeverFlip, ForeverFlip.Market
        F.Trade.rate = function() return 0.05 end
        local a = M.advice(30, 'i:30', nil, 5000)
        assert(math.abs(a.tries - 20) < 1e-9, '19 posts expire before the one that sells: ' .. a.tries)''')

    def test_break_even_is_the_lowest_price_that_returns_the_cost(self):
        run(SETUP + '''local M = ForeverFlip.Market
        assert(M.breakEven(9, 1, 'commodity') == 9, tostring(M.breakEven(9, 1, 'commodity')))
        assert(M.net(M.breakEven(1000, 1, 'commodity'), 1) >= 1000)''')


class CraftCountTests(unittest.TestCase):
    def test_a_day_of_crafts_divides_by_the_units_made(self):
        run(SETUP + '''local F, UI = ForeverFlip, ForeverFlip.UI
        local asked
        F.Crafting.shopMaterials = function(_, count) asked = count; return 1 end
        UI.craftSelected = { id = 1, n = 5, perDay = 10 }
        UI.craftShop:Click()
        assert(asked == 2, 'ten a day of a recipe that makes five: two crafts, not ' .. tostring(asked))''')


class AnalyticsDaysTests(unittest.TestCase):
    def test_totals_outlive_the_journal(self):
        run(SETUP + '''local F = ForeverFlip
        local c = F.Data.char(F.db, F.Engine.owner())
        for i = 1, 501 do
            F.Data.log(c, { at = now, kind = 'sell', key = 'c:10', name = 'Linen Cloth', qty = 1, amount = 10, profit = 1 })
        end
        assert(#c.journal == 500)
        local r = F.Analytics.results(7, now)
        assert(r.profit == 501 and r.sales == 501, r.profit .. ' / ' .. r.sales)''')



class UnseenSalesTests(unittest.TestCase):
    def test_a_day_without_a_sale_is_no_proof_it_never_sells(self):
        run(SETUP + '''local F, M = ForeverFlip, ForeverFlip.Market
        local real = M.saleability
        local hours = 24
        M.saleability = function() return { known = true, perDay = 0, hours = hours } end
        local short = M.advice(30, 'i:30', { sales = {} }, 280000)
        hours = 60 * 24
        local long = M.advice(30, 'i:30', { sales = {} }, 280000)
        M.saleability = real
        assert(short.tries < 6, 'a day watched: a fair chance ' .. short.tries)
        assert(long.tries > short.tries * 3, 'two months without a sale: hardly any')''')


if __name__ == '__main__':
    unittest.main()
