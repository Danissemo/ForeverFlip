"""One Sure (Market.confidence): rivals' undercuts take at most half the buyers instead of putting
a thousand units in the queue, the tooltip asks it for the units to sell as every page does, and a
route that is unlikely to sell is never the recommendation."""

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


# A busy ore: 110 units sold at 6s in 4 hours, but rivals undercut eight times an hour.
BUSY = """local M = ForeverFlip.Market
local h = { sales = { pairs = 5, hours = 4, at = 0, sure = 80, lots = 30, cuts = 62, sweeps = 0,
    b = { [2] = 110, [3] = 600 } }, lots = '' }
"""


class SureTests(unittest.TestCase):
    def test_undercuts_do_not_make_a_busy_item_unsellable(self):
        out = run(SETUP + BUSY + '''local s, parts = M.confidence(h, 600, 1, 0, 1)
        return string.format('%.3f %.2f', s, parts.share)''')
        sure, share = map(float, out.split())
        self.assertGreater(sure, 0.5, out)
        self.assertLessEqual(share, 0.5)

    def test_rivals_take_at_most_half_the_buyers(self):
        out = run(SETUP + BUSY + '''h.sales.cuts = 1e6
        local _, parts = M.confidence(h, 600, 1, 0, 1)
        return tostring(parts.share)''')
        self.assertEqual(float(out), 0.5)


class RouteTests(unittest.TestCase):
    def test_an_unlikely_auction_loses_to_the_vendor(self):
        out = run(SETUP + '''local c = ForeverFlip.Market.chainRoutes({ auction = 18000, sure = 0.01, post = 19900, vendor = 5542 })
        return c.best''')
        self.assertEqual(out, 'vendor')

    def test_the_auction_is_ranked_by_what_it_likely_brings(self):
        out = run(SETUP + '''local M = ForeverFlip.Market
        return M.chainRoutes({ auction = 1000, sure = 0.5, vendor = 600 }).best .. ' '
            .. M.chainRoutes({ auction = 1000, sure = 0.9, vendor = 600 }).best''')
        self.assertEqual(out, 'vendor auction')

    def test_only_an_unlikely_auction_recommends_nothing(self):
        text = clean(run(SETUP + '''fullScan(); local F = ForeverFlip
        F.Deals.sureAt = function() return 0.01 end
        F.Market.env.vendorPrice = function() return nil end''' + TIP))
        self.assertIn('Recommendation = hold, nothing sells now', text)
        self.assertIn('unlikely to sell (Sure 1%)', text)

    def test_the_recommendation_names_the_price_to_post(self):
        text = clean(run(SETUP + '''fullScan(); local F = ForeverFlip
        F.Deals.sureAt = function() return 0.9 end
        F.Market.env.vendorPrice = function() return 1, 'client' end''' + TIP))
        rec = text.split('Recommendation = ')[1].split(' ## ')[0]
        self.assertRegex(rec, r'^Auction at \d')
        self.assertNotIn('80%:', text)
        # The Demand line shows the same Sure (the deal line here is a vendor deal, sure by definition).
        self.assertIn('Sure 90%', text.split('Sells at ')[1].split(' ## ')[0])


if __name__ == '__main__':
    unittest.main()
