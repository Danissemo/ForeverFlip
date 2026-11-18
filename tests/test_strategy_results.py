"""How the strategies earn: what each one's purchases really brought (Analytics -> By strategy), the
deals ranked by what they are worth on average (profit times Sure), a market reset kept under the
prices buyers paid and away from items undercut all the time, and a thin Est./day of gear leaned on
similar gear instead of on none."""

import unittest

from test_addon import SETUP, run
from test_median_resale import BASE


class StrategyResultTests(unittest.TestCase):
    def test_each_strategy_shows_what_its_purchases_earned(self):
        run(SETUP + '''local F, UI = ForeverFlip, ForeverFlip.UI
        local c = F.Data.char(F.db, F.Engine.owner())
        local D = F.Data
        -- Resale: 4 bought for 400, 3 sold for 900 after the cut, 1 left.
        D.addPosition(c, 'c:10', 'Linen Cloth', 4, 400, 'flip', 300, now - 2 * 86400)
        D.sale(c, 'c:10', 'Linen Cloth', 3, 900, now - 86400)
        -- Market reset: 2 bought for 1000, none sold, a deposit of 50 lost.
        D.addPosition(c, 'c:11', 'Wool Cloth', 2, 1000, 'flip', 700, now - 3600, nil, nil, nil, 'median')
        D.addCost(c, 'c:11', 50, now)
        -- Bought for the shopping list: own use, not a strategy.
        D.addPosition(c, 'c:12', 'Silk Cloth', 1, 999, 'shop', nil, now - 3600)
        local list = F.Analytics.strategies(7, now)
        assert(#list == 2, 'two strategies bought: ' .. #list)
        local resale, reset = list[1], list[2]
        assert(resale.id == 'flip' and reset.id == 'median', resale.id .. ' ' .. reset.id)
        assert(resale.sold == 3 and resale.qty == 4 and resale.spent == 400)
        assert(resale.profit == 900 - 300, 'the units gone, less their cost: ' .. resale.profit)
        assert(resale.held == 100 and math.abs(resale.roi - 2) < 1e-9, tostring(resale.roi))
        assert(reset.profit == -50 and reset.held == 1000 and reset.roi == nil, reset.profit)
        UI.show('analytics'); UI.marketView = 'strategies'; UI.refresh()
        local row = UI.marketTable.rows[1]
        assert(row:IsShown() and row.name:GetText():find('Resale'), row.name:GetText())
        assert(row.cols[2]:GetText() == '3/4', row.cols[2]:GetText())
        assert(UI.marketText:GetText():find('Still in unsold units'), UI.marketText:GetText())''')

    def test_a_lot_bought_before_the_period_is_left_out(self):
        run(SETUP + '''local F = ForeverFlip
        local c = F.Data.char(F.db, F.Engine.owner())
        F.Data.addPosition(c, 'c:10', 'Linen Cloth', 1, 100, 'flip', 300, now - 10 * 86400)
        assert(#F.Analytics.strategies(7, now) == 0)
        assert(#F.Analytics.strategies(30, now) == 1)''')


class ExpectedProfitTests(unittest.TestCase):
    def test_the_expected_profit_weighs_the_profit_by_sure(self):
        run(SETUP + '''local M = ForeverFlip.Market
        assert(M.expectedProfit(1000, 100, 0.5) == 450, M.expectedProfit(1000, 100, 0.5))
        assert(M.expectedProfit(1000, 100, nil) == 1000, 'no Sure: the profit')
        assert(M.expectedProfit(100, 1000, 0.1) < 0, 'rarely sold, dear deposits: a loss on average')
        local r, days = M.dayReturn(100, 1000, 10, 5)
        assert(days == 2 and math.abs(r - 0.05) < 1e-9, 'ten units at five a day: two days')
        assert(M.dayReturn(100, 1000, 1, 0) == nil)''')

    def test_a_reset_carries_its_expected_profit(self):
        run(BASE + '''local d = assert(judge(history(8)))
        assert(d.ev and d.ev <= d.profit and d.ev > 0, tostring(d.ev))
        local lines = table.concat(UI.dealDetail(d, { known = true, perDay = d.perDay }, d and market.history['c:10'], now), '\\n')
        assert(lines:find('on average'), lines)''')


class MarketResetTests(unittest.TestCase):
    def test_a_reset_relists_no_higher_than_buyers_paid(self):
        # The median is made of asking prices: 1g, while every unit seen sold went at 80s.
        run(BASE + '''local h = history(0)
        for _ = 1, 8 do M.recordSales(h, { [8000] = 3 }, 900, now) end
        rows = { { unit = 5000, qty = 2 }, { unit = 12000, qty = 10 } }
        local d = assert(judge(h))
        assert(d.paidCap and d.exit <= 8000, 'capped by the prices paid: ' .. d.exit)''')

    def test_an_item_undercut_all_the_time_is_not_reset(self):
        run(BASE + '''local h = history(8)
        h.sales.cuts = 40
        local d, why = judge(h)
        assert(not d and why == 'undercut', tostring(why))
        h.sales.cuts = 0
        assert(judge(h), 'not undercut: reset')''')


class ThinEstimateTests(unittest.TestCase):
    def test_a_thin_rate_leans_on_similar_items(self):
        run(SETUP + '''local M = ForeverFlip.Market
        local p = M.PRIOR_HOURS
        assert(M.withPrior(0, 0, 6) == 6, 'no hours watched: the similar items')
        local long = M.withPrior(0, 1000, 6)
        assert(long > 0 and long < 0.1, 'many hours: its own rate')
        assert(M.withPrior(2, p, 6) == 5, 'half and half')
        assert(M.withPrior(2, 1, nil) == 2, 'nothing similar: unchanged')''')

    def test_the_deals_figure_takes_the_prior_only_on_thin_data(self):
        run(SETUP + '''local F, D = ForeverFlip, ForeverFlip.Deals
        local calls = 0
        D.siblingEstimate = function() calls = calls + 1 return { perDay = 6, n = 3 } end
        local market = F.Data.market(F.db, F.Engine.scope())
        local h = { days = {} }
        F.Market.recordSales(h, { [10000] = 1 }, 900, now)
        market.history['g:1'] = h
        local own = F.Market.saleability(h, 10000, now)
        local s = D.saleability('g:1', h, 10000, now)
        assert(own.known and s.prior == 6 and s.perDay > own.perDay, tostring(s.perDay))
        for _ = 1, 20 do F.Market.recordSales(h, { [10000] = 1 }, 900, now) end
        local reliable = D.saleability('g:1', h, 10000, now)
        assert(not reliable.prior, 'its own sample is enough')''')


if __name__ == '__main__':
    unittest.main()
