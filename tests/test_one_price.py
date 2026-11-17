"""One sell price everywhere (Market.postPrice): the tooltip's recommendation, the Sell page's
suggestion and the Resale exit follow the same rule and say the same reason, so a player never sees
three different prices for one item."""

import re
import unittest

from test_addon import SETUP, run

TIP = """
    tooltipLines = {}
    GameTooltip.itemLink = link(10)
    for _, fn in ipairs(tooltipCalls) do fn(GameTooltip) end
    return table.concat(tooltipLines, ' ## ')"""


def clean(text):
    return re.sub(r'\|c[0-9a-fA-F]{8}|\|r', '', text)


class PostPriceTests(unittest.TestCase):
    def test_the_rule(self):
        out = run(SETUP + '''local M = ForeverFlip.Market
        local function p(o) o.kind = 'gear'; local price, why = M.postPrice(o); return tostring(price) .. ' ' .. tostring(why) end
        return table.concat({
            p({ usual = 13474, cheapest = 13000, limit = 26948 }),
            p({ usual = 13474, cheapest = 30000, limit = 26948 }),
            p({ usual = 13474, cap = 6950, cheapest = 13000, limit = 26948 }),
            p({ usual = 13474, cap = 6950 }),
            p({ usual = 13474 }),
            p({}),
        }, ' | ')''')
        undercut, ignored, capped, sales, usual, none = out.split(' | ')
        self.assertTrue(undercut.endswith(' undercut'), undercut)
        self.assertLess(int(undercut.split()[0]), 13000)
        self.assertTrue(ignored.endswith(' usual'), ignored)
        self.assertLessEqual(int(ignored.split()[0]), 13474)
        self.assertTrue(capped.endswith(' sales'), capped)
        self.assertLessEqual(int(capped.split()[0]), 6950)
        self.assertEqual(sales, capped)
        self.assertTrue(usual.endswith(' usual'), usual)
        self.assertEqual(none, 'nil nil')

    def test_the_sell_page_and_the_resale_exit_agree(self):
        out = run(SETUP + '''local F, M = ForeverFlip, ForeverFlip.Market
        local h = { scan = { market = 13474, at = 0 } }
        M.saleCap = function() return 6950 end
        M.demandAt = function() return { perDay = 5, pairs = 3, sold = 10 } end
        local resale = M.postPrice({ kind = 'gear', usual = 13474, cap = M.saleCap(h), cheapest = 20000,
            limit = F.Trade.postLimit(13474), undercut = F.Trade.undercut })
        local exit = M.evaluate({ { unit = 4400, qty = 1 }, { unit = 20000, qty = 1 } }, {
            kind = 'gear', history = h, now = 0, market = 6950, usual = 13474, saleCap = 6950,
            limit = F.Trade.postLimit(13474), undercut = F.Trade.undercut, budget = 1e9,
            settings = { minProfit = 1, minROI = 0 } })
        return tostring(resale) .. ' ' .. tostring(exit and exit.exit) .. ' ' .. tostring(exit and exit.exitWhy)''')
        resale, exit, why = out.split()
        self.assertEqual(resale, exit, out)
        self.assertEqual(why, 'sales')

    def test_resale_sells_where_sure_expects_the_most_money(self):
        def pick(sure, per_day=5, rows='{ unit = 4000, qty = 3 }, { unit = 20000, qty = 1 }'):
            return run(SETUP + '''local F, M = ForeverFlip, ForeverFlip.Market
            local h = { scan = { market = 13474, at = 0 } }
            M.demandAt = function() return { perDay = %s, pairs = 3, sold = 10 } end
            M.confidence = function(_, price) return %s end
            local d = M.evaluate({ %s }, {
                kind = 'gear', history = h, now = 0, market = 9000, usual = 13474, saleCap = 9000,
                limit = F.Trade.postLimit(13474), undercut = F.Trade.undercut, budget = 1e9,
                settings = { minProfit = 1, minROI = 0 } })
            return tostring(d and d.exit) .. ' ' .. tostring(d and d.exitWhy) .. ' ' .. tostring(d and d.qty)''' % (per_day, sure, rows))
        exit, why, qty = pick('price > 10000 and 0.1 or 0.9').split()
        self.assertEqual(why, 'sales', 'hardly anyone buys under the next lot: sell at what buyers paid')
        self.assertLessEqual(int(exit), 9000)
        exit, why, qty = pick('0.9').split()
        self.assertEqual(why, 'undercut', 'it sells there too: the higher price')
        self.assertGreater(int(exit), 13474)
        # One sale a day: one unit, not the three under the next lot (whole lots are bought).
        exit, why, qty = pick('0.9', 1, '{ unit = 4000, qty = 1 }, { unit = 7000, qty = 2 }, { unit = 20000, qty = 1 }').split()
        self.assertEqual(qty, '1', 'no more than sells in a day')
        self.assertLess(int(exit), 7000, 'one step under the next lot left')


class TooltipTests(unittest.TestCase):
    def test_a_resale_deal_sets_the_recommendation(self):
        text = clean(run(SETUP + '''fullScan(); local F = ForeverFlip
        F.Deals.get = function() return { key = 'c:10', kind = 'commodity', mode = 'flip', qty = 2, exit = 75,
            exitWhy = 'undercut', exitNext = 76, profit = 30 } end
        F.Deals.sure = function() return 0.5 end
        F.Market.env.vendorPrice = function() return 1, 'client' end''' + TIP))
        self.assertIn('Recommendation = Auction at 75c', text)
        self.assertNotIn('Why ', text, 'no reason when no other route comes close')

    def test_a_clear_route_is_one_short_line(self):
        text = clean(run(SETUP + 'fullScan()' + TIP))
        rec = text.split('Recommendation')[1].split('Demand')[0]
        self.assertTrue(rec.startswith(' = Vendor at 1s 00c ## '), text)
        self.assertNotIn('Why ', rec)
        self.assertNotIn('Pays more', rec)


    def test_the_vendor_price_is_for_the_stack_and_sure_is_coloured(self):
        raw = run(SETUP + """fullScan(); local F = ForeverFlip
        F.Deals.sureAt = function() return 0.9 end
        tooltipLines = {}
        GameTooltip.itemLink = link(10)
        for _, fn in ipairs(tooltipCalls) do fn(GameTooltip, { lines = { { type = 11, price = 300 } } }) end
        return table.concat(tooltipLines, ' ## ')""")
        text = clean(raw)
        self.assertIn('Vendor price = (3 x 1s 00c)  3s 00c', text)
        self.assertIn(ForeverFlip_good() + '90%', raw.split('Sells at')[1].split(' ## ')[0])


def ForeverFlip_good():
    return run(SETUP + 'return ForeverFlip.UI.C.good')


if __name__ == '__main__':
    unittest.main()
