"""T25: the market reset, a strategy of its own (Deals -> Market reset, internal id "median").

Every lot priced under an item's usual price (the median of the last 7 daily prices) is bought, all
or nothing, to relist alone at that price. It has no switch (0 in its day gold or share is off), its
own money limits (per item, per day, share of the money on hand), takes at most three days of sales
(a day with few sales data) and RESET_MAX_LOTS lots, says why its page is empty, and shows the profit
after the cut and the deposits with the risk (Sure and its limits)."""

import re
import unittest

from test_addon import SETUP, run


def clean(text):
    return re.sub(r'\|c[0-9a-fA-F]{8}|\|r', '', text)


BASE = SETUP + '''local F, M, D, UI = ForeverFlip, ForeverFlip.Market, ForeverFlip.Deals, ForeverFlip.UI
local market = F.Data.market(F.db, F.Engine.scope())
local today = math.floor(now / 86400)
-- Item 10: usual price 1g on each of the last five days, and `pairs` scan pairs of sales at 1g.
local function history(pairs, prices)
    prices = prices or { 10000, 10000, 10000, 10000, 10000 }
    local h = { days = {} }
    for i, p in ipairs(prices) do
        h.days[#h.days + 1] = { d = today - (#prices - i), m = p, min = p, n = 10 }
    end
    for _ = 1, pairs do M.recordSales(h, { [10000] = 3 }, 900, now) end
    market.history['c:10'] = h
    D.sureCache = {}
    return h
end
local rows = { { unit = 7000, qty = 3 }, { unit = 9000, qty = 5 }, { unit = 12000, qty = 10 } }
local function judge(h, extra)
    local ctx = { kind = 'commodity', history = h, now = now, budget = 10000000,
        deposit = function() return 0 end, settings = { minProfit = 100, minROI = 0.01 } }
    for k, v in pairs(extra or {}) do ctx[k] = v end
    return M.evaluateMedian(rows, ctx)
end
'''


class MedianTargetTests(unittest.TestCase):
    def test_the_median_of_the_last_seven_days_needs_three_of_them(self):
        run(BASE + '''local h = { days = {
            { d = today - 9, m = 1 }, { d = today - 2, m = 300 }, { d = today - 1, m = 100 }, { d = today, m = 200 } } }
        local m, n = M.medianTarget(h, now)
        assert(m == 200 and n == 3, 'a day older than 7 days is left out: ' .. tostring(m))
        table.remove(h.days, 2)
        local none, days = M.medianTarget(h, now)
        assert(none == nil and days == 2, 'two days give no median')''')


class EvaluateTests(unittest.TestCase):
    def test_lots_below_the_median_are_bought_to_relist_at_it(self):
        run(BASE + '''local d = assert(judge(history(8)))
        assert(d.mode == 'flip' and d.strategy == 'median', 'a resale of its own strategy')
        assert(d.exit <= 10000 and d.median == 10000 and d.days == 5)
        assert(d.qty == 8 and d.cost == 3 * 7000 + 5 * 9000, 'the 1g20s lots are above the median: ' .. d.qty)
        assert(d.profit == M.net(d.exit, 8) - d.cost, 'profit after the cut (no deposit here)')
        assert(d.quality and d.quality.reliable)
        assert(d.sure and d.sureLow <= d.sure and d.sureHigh >= d.sure, 'the risk with its limits')''')

    def test_the_deposit_is_counted_as_a_cost(self):
        run(BASE + '''local d = assert(judge(history(8), { deposit = function(q) return 100 * q end }))
        assert(d.risk == 800 and d.profit == M.net(d.exit, 8) - d.cost - 800, d.profit)''')

    def test_weak_data_resets_a_day_of_sales_at_most(self):
        run(BASE + '''rows = { { unit = 7000, qty = 1000 } }
        local _, why = judge(history(1))
        assert(why == 'too_much', 'more than a weak day of sales: ' .. tostring(why))
        rows = { { unit = 7000, qty = 1 }, { unit = 12000, qty = 10 } }
        local d = assert(judge(history(1)))
        assert(d.weak and not d.quality.reliable and d.qty == 1, 'marked as few sales data')
        local none = assert(judge(history(0)))
        assert(none.weak and none.qty == 1, 'one unit when no sales are measured: ' .. none.qty)''')

    def test_a_price_known_one_day_with_no_sale_measured_well_is_not_reset(self):
        # In game: 5g lots offered to relist at 990g, an asking price that never sold (Est./day 0,
        # Sure 4%), because a price known for a day let one unit through on trust.
        run(BASE + '''rows = { { unit = 7000, qty = 1 }, { unit = 12000, qty = 10 } }
        local h = { days = { { d = today, m = 10000, min = 10000, n = 10 } } }
        for _ = 1, 8 do M.recordSales(h, {}, 900, now) end
        market.history['c:10'] = h; D.sureCache = {}
        local q = M.quality(h, 9999, now)
        assert(q.reliable and (q.perDay or 0) == 0, 'a reliable zero: ' .. tostring(q.reason))
        local d, why = judge(h)
        assert(d == nil and why == 'not_selling', tostring(why))''')

    def test_all_or_nothing_and_too_many_lots(self):
        run(BASE + '''local h = history(8)
        local d = assert(judge(h))
        assert(d.reset and #d.lots == 2 and d.maxUnit == 9000, 'every lot under the price')
        local many = {}
        for i = 1, M.RESET_MAX_LOTS + 1 do many[i] = { unit = 5000, qty = 1 } end
        rows = many
        local _, why = judge(h)
        assert(why == 'too_much', tostring(why))''')

    def test_too_few_days_of_prices_use_the_known_price_and_are_weak(self):
        run(BASE + '''local h = history(8, { 10000, 10000 })
        rows = { { unit = 7000, qty = 1 }, { unit = 12000, qty = 10 } }
        local d = assert(judge(h))
        assert(d.weak and d.median == 10000 and d.days == 2, 'two days: offered weak at their price')
        h.days = {}
        h.scan = { at = now, market = 10000 }
        local e = assert(judge(h))
        assert(e.weak and e.median == 10000 and e.days == 0, 'the last scan price alone is enough')
        h.scan = nil
        local none, why = judge(h)
        assert(not none and why == 'no_median', why)''')

    def test_a_lot_that_pays_nothing_after_the_cut_is_not_bought(self):
        run(BASE + '''local h = history(8)
        rows = { { unit = 9600, qty = 5 } }
        local d, why = judge(h)
        assert(not d and why == 'no_gap', why)''')

    def test_the_budget_and_the_stock_held_stop_a_reset(self):
        run(BASE + '''local h = history(8)
        local _, short = judge(h, { budget = 65999 })
        assert(short == 'budget', 'all or nothing: ' .. tostring(short))
        assert(judge(h, { budget = 66000 }))
        local _, why = judge(h, { budget = 5000 })
        assert(why == 'budget', why)
        local _, why2 = judge(h, { held = 10000 })
        assert(why2 == 'enough_stock', why2)''')


DEALS = BASE + '''local h = history(8)
local g = { key = 'c:10', kind = 'commodity', id = 10, link = link(10), market = 10000, rows = rows }
function F.AH.depositFn() return function() return 0 end end
F.db.settings.minROI = 0.05 -- a reset buys the 90s lots too: about 15% here
'''


class DealsTests(unittest.TestCase):
    def test_on_by_default_with_half_of_the_gold(self):
        run(DEALS + '''assert(F.db.settings.median == true and F.db.settings.medianShare == 0.5)''')

    def test_the_old_saved_defaults_move_to_the_new_ones_once(self):
        run(SETUP + '''local D = ForeverFlip.Data
        local db = D.open({ schemaVersion = 2, settings = { median = false, medianShare = 0.2 } })
        assert(db.settings.median == true and db.settings.medianShare == 0.5 and db.medianDefaults)
        local kept = D.open({ schemaVersion = 2, settings = { median = false, medianShare = 0.3 } })
        assert(kept.settings.median == true and kept.settings.medianShare == 0, 'saved off stays off as a share of 0')''')

    def test_off_gives_nothing(self):
        run(DEALS + '''F.db.settings.medianShare = 0
        assert(D.medianOff())
        local d = D.evaluate(g, nil, h, now)
        assert(not (d and (d.strategy == 'median' or d.median)), 'nothing below the median while it is off')''')

    def test_its_own_page_and_not_the_resale_page(self):
        run(DEALS + '''F.db.settings.median = true
        F.db.settings.medianItemGold, F.db.settings.medianDayGold, F.db.settings.medianShare = 100, 100, 1
        local d = assert(D.evaluate(g, nil, h, now))
        local median = d.strategy == 'median' and d or d.median
        assert(median and median.key == 'c:10', 'the median deal is listed')
        D.replace({ d }, F.Engine.scope())
        local list = D.visible('median')
        assert(#list == 1 and list[1].strategy == 'median')
        for _, x in ipairs(D.visible('flip')) do assert(x.strategy ~= 'median', 'not on the Resale page') end
        UI.show('deals:median')
        assert(D.get('c:10').strategy == 'median', 'the page picks the strategy')''')

    def test_the_day_limit_counts_todays_purchases(self):
        run(DEALS + '''F.db.settings.median = true
        F.db.settings.medianItemGold, F.db.settings.medianDayGold, F.db.settings.medianShare = 100, 11, 1
        local c = F.Data.char(F.db, F.Engine.owner())
        F.Data.log(c, { at = now, kind = 'buy', key = 'c:99', qty = 1, amount = 40000, strategy = 'median' })
        F.Data.log(c, { at = now, kind = 'buy', key = 'c:98', qty = 1, amount = 99999 })
        F.Data.log(c, { at = now - 86400, kind = 'buy', key = 'c:97', qty = 1, amount = 99999, strategy = 'median' })
        assert(D.medianSpent(now) == 40000, D.medianSpent(now))
        assert(D.medianRoom(nil, now) == 70000, D.medianRoom(nil, now))
        local d = D.evaluateMedian(g, h, now)
        assert(d and d.cost <= 70000, 'the deal fits what is left today')
        F.db.settings.medianDayGold = 10
        local none, why = D.evaluateMedian(g, h, now)
        assert(not none and why == 'budget', why)''')

    def test_buying_keeps_to_the_day_limit(self):
        run(DEALS + '''F.db.settings.median = true
        F.db.settings.medianItemGold, F.db.settings.medianDayGold, F.db.settings.medianShare = 100, 100, 1
        local d = assert(D.evaluateMedian(g, h, now))
        d.key, d.kind, d.id, d.link, d.verified = 'c:10', 'commodity', 10, link(10), now
        D.list = { d }
        F.db.settings.medianDayGold = 1 -- the limit was lowered after the check
        local ok, why = F.Trade.buy('c:10', 'median')
        assert(not ok and why == 'spend_limit', tostring(why))''')

    def test_the_detail_shows_the_profit_after_fees_and_the_risk(self):
        text = clean(run(DEALS + '''F.db.settings.median = true
        F.db.settings.medianItemGold, F.db.settings.medianDayGold, F.db.settings.medianShare = 100, 100, 1
        local d = assert(D.evaluateMedian(g, h, now))
        return table.concat(UI.dealDetail(d, nil, h, now), ' ## ')'''))
        self.assertIn('usual price of 5 days', text)
        self.assertIn('Market reset: every lot', text)
        self.assertIn('after the 5% cut', text)
        self.assertRegex(text, r'Risk Sure \d+%')
        self.assertNotIn('80%', text)
        self.assertIn('scan pairs', text)

    def test_the_empty_page_says_it_is_off(self):
        text = clean(run(DEALS + '''F.db.settings.medianDayGold = 0
        UI.show('deals:median'); UI.refresh()
        return UI.noMedianText()'''))
        self.assertIn('Market reset is off', text)

    def test_the_empty_page_says_why_most_common_first(self):
        text = clean(run(DEALS + '''return UI.noMedianText({ salesReady = 0,
            medianReasons = { no_median = 40, no_gap = 7, small = 2, off = 9, too_much = 3 } })'''))
        self.assertIn('3 have more under the price', text)
        self.assertIn('No sales measured yet', text)
        self.assertLess(text.index('40 have no known price'), text.index('7 have no lot'))
        self.assertIn('2 would earn less', text)
        self.assertIn('Left to spend on this page today', text)
        empty = clean(run(DEALS + '''return UI.noMedianText({ salesReady = 3 })'''))
        self.assertIn('no full scan has been read yet', empty)
        self.assertNotIn('No sales measured', empty)

    def test_a_weak_find_says_few_sales_data(self):
        text = clean(run(BASE + '''rows = { { unit = 7000, qty = 1 } }
        local d = assert(judge(history(1)))
        d.key, d.kind, d.id = 'c:10', 'commodity', 10
        return table.concat(UI.dealDetail(d, nil, history(1), now), ' ## ')'''))
        self.assertIn('Few sales data', text)



class TwoStrategiesTests(unittest.TestCase):
    """Resale buys up to a lot and sells where buyers pay (under the next lot left, or at what they
    paid, whichever Sure expects to bring more); Market reset buys every lot under the median and
    sells at the median. The two pages must not show the same deal."""

    def test_the_reset_sells_at_the_median_and_the_resale_under_the_next_lot(self):
        run(DEALS + '''F.db.settings.median = true
        F.db.settings.medianItemGold, F.db.settings.medianDayGold, F.db.settings.medianShare = 100, 100, 1
        F.Market.saleCap = function() return 8000 end
        local m = assert(D.evaluateMedian(g, h, now))
        assert(m.exit > 9000 and m.exit <= 10000, 'at the median, not the 80s buyers paid: ' .. m.exit)
        F.Market.demandAt = function() return { perDay = 50, pairs = 5, sold = 100 } end
        local d = assert(D.evaluate(g, nil, h, now))
        local flip = d.strategy ~= 'median' and d or nil
        assert(flip, 'a resale deal')
        assert(flip.exit ~= m.exit, 'the two pages differ: ' .. flip.exit .. ' ' .. m.exit)
        assert(flip.exitWhy == 'undercut' or flip.exitWhy == 'sales', flip.exitWhy)
        assert(flip.qty <= 50, 'no more than a day of sales')''')

    def test_stock_of_a_reset_is_posted_at_the_median(self):
        run(DEALS + '''local c = F.Data.char(F.db, F.Engine.owner())
        F.Data.addPosition(c, 'c:10', 'x', 5, 40000, 'flip', 10000, now, nil, 'addon', nil, 'median')
        assert(F.Trade.heldStrategy('c:10') == 'median')
        F.Market.saleCap = function() return 8000 end
        F.Trade.prices['c:10'] = { rows = { { unit = 12000, qty = 10 } }, at = F.Engine.clock() }
        local price, _, _, why = F.Trade.suggest({ key = 'c:10', id = 10, kind = 'commodity' })
        assert(price <= 10000 and price > 9000 and why == 'median', tostring(price) .. ' ' .. tostring(why))''')

if __name__ == '__main__':
    unittest.main()
