"""Est./day and Sure of a gear ending with no sales data of its own, from the item's other endings."""

import unittest

from test_addon import SETUP, run

BASE = SETUP + r'''local F, D, UI = ForeverFlip, ForeverFlip.Deals, ForeverFlip.UI
local history = F.Data.market(F.db, F.Engine.scope()).history
history['g:500:sword of the owl'] = { scan = { at = now, market = 10000 } }
history['g:500:sword of the bear'] = { scan = { at = now, market = 20000 } }
history['g:500:sword of the whale'] = { scan = { at = now, market = 30000 } }
history['g:501:axe of the owl'] = { scan = { at = now, market = 50000 } }
local perDay = { [10000] = 1, [20000] = 3, [30000] = 2 }
local sure = { [10000] = 0.4, [20000] = 0.8, [30000] = 0.6 }
F.Market.usual = function(h) return h.scan.market end
F.Market.saleability = function(h, price)
    if perDay[price] then return { known = true, perDay = perDay[price] } end
    return { known = false }
end
F.Market.confidence = function(h, price) return sure[price] end
D.siblingCache = {}
'''


class SiblingEstimateTests(unittest.TestCase):
    def test_a_new_ending_takes_the_average_demand_and_median_sure_of_the_others(self):
        run(BASE + r'''local e = D.siblingEstimate('g:500:sword of the eagle', 1, now)
        assert(e and e.n == 3 and math.abs(e.perDay - 2) < 1e-9 and e.sure == 0.6, e and e.perDay)
        local own = D.siblingEstimate('g:500:sword of the owl', 1, now)
        assert(own.n == 2, 'an ending does not count itself')
        assert(D.siblingEstimate('g:501:axe of the owl', 1, now) == nil, 'no other ending: nothing')
        assert(D.siblingEstimate('c:10', 1, now) == nil, 'only gear')''')

    def test_gear_with_no_other_ending_takes_gear_of_about_its_price(self):
        run(BASE + r'''history['g:502:pauldrons of the champion'] = { scan = { at = now, market = 18000 } }
        local e = D.siblingEstimate('g:502:pauldrons of the champion', 1, now)
        assert(e and e.peers and e.n == 3 and e.sure == 0.6, e and e.n)
        history['g:503:lonely'] = { scan = { at = now, market = 9000000 } }
        D.siblingCache = {}
        assert(D.siblingEstimate('g:503:lonely', 1, now) == nil, 'nothing alike: nothing')''')

    def test_the_deals_page_shows_it_greyed_with_a_tilde(self):
        run(BASE + r'''local d = { key = 'g:500:sword of the eagle', mode = 'flip', strategy = 'median', qty = 1, exit = 25000 }
        F.Deals.sure = function() return nil end
        local s, approx = UI.dealSure(d, now)
        assert(s == 0.6 and approx)
        local text = UI.dealSureText(d, now)
        assert(text:find('~60%', 1, true) and text:find(UI.C.dim, 1, true), text)''')


class TooltipTests(unittest.TestCase):
    def test_gear_without_data_of_its_own_shows_its_other_versions(self):
        out = run(BASE + r'''fullScan()
        F.Market.usual = function(h) return type(h) == 'table' and h.scan and h.scan.market or nil end
        F.Trade.quote = function() return { why = 'similar', post = 19900, best = 'auction' } end
        tooltipLines = {}
        GameTooltip.itemLink = '|cff1eff00|Hitem:500::::::::::|h[Sword of the Eagle]|h|r'
        F.AH.keyFor = function() return 'g:500:sword of the eagle' end
        for _, fn in ipairs(tooltipCalls) do fn(GameTooltip) end
        return table.concat(tooltipLines, ' ## ')''')
        self.assertIn('Demand', out)
        self.assertIn('other versions', out)
        self.assertIn('~2.0', out)
        self.assertIn('~60%', out)

class BidSureTests(unittest.TestCase):
    def test_a_bid_is_sure_from_the_vendor_its_sales_or_its_other_endings(self):
        run(BASE + r'''F.AH.vendorPrice = function(id) return id == 7 and 500 or nil end
        local s, approx = F.Bids.sure({ key = 'i:7', id = 7, count = 2, value = 1000 }, now)
        assert(s == 1 and not approx, 'a merchant pays the worth')
        F.Deals.sureAt = function() return 0.7 end
        s, approx = F.Bids.sure({ key = 'g:500:sword of the owl', id = 500, count = 1, value = 9000 }, now)
        assert(s == 0.7 and not approx, 'its own Sure at the usual price')
        F.Deals.sureAt = function() return nil end
        s, approx = F.Bids.sure({ key = 'g:500:sword of the eagle', id = 500, count = 1, value = 9000 }, now)
        assert(s == 0.6 and approx, 'the other endings, marked')''')



class MyItemsSureTests(unittest.TestCase):
    def test_my_items_shows_the_other_endings_sure_when_its_own_is_missing(self):
        from test_hidden_items import HIDE
        run(HIDE + r'''F.db.settings.vendorMargin = 0
        F.Data.market(F.db, F.Engine.scope()).history['i:30'] = { scan = { at = now, market = 5000 } }
        T.prices['i:30'] = { rows = { { unit = 4500, qty = 1 } }, at = now }
        T.setRouteChoice('i:30', 'auction')
        F.Deals.sureAt = function() return nil end
        F.Deals.siblingEstimate = function() return { sure = 0.5, perDay = 1, n = 2 } end
        UI.refresh()
        local text = row('i:30').cols[4]:GetText()
        assert(text:find('~50%', 1, true) and text:find(UI.C.dim, 1, true), text)''')

if __name__ == '__main__':
    unittest.main()
