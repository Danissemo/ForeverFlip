"""T11: the auction house and the vendor route are judged apart.

Before, Market.evaluate returned one deal per lot, the route that paid more: a lot below the vendor
price that also resold at a profit was listed under Resale only (or To vendor only), never both.
Now the other route rides along as `alt`, each list shows its own route, and the buy run of the
To vendor page buys the vendor route. Selling -> My items says "AH / V" when held stock passes the
thresholds of both routes, and the hover explains each."""

import re
import unittest

from test_addon import SETUP, run

# Two cloth at 8c (a vendor pays 10c), the next lot at 50s, and 30 sold a day just below 50s.
ROUTES = '''local F=ForeverFlip;local M=F.Market
addItem(10,'Linen Cloth',1000,'commodity')
local rows={{unit=800,qty=2},{unit=5000,qty=10}}
local h={};M.recordSales(h,{[4999]=30},24*3600,now);h.sales.pairs=4
local function judge(vendor, extra)
    local ctx={kind='commodity',vendor=vendor,budget=1000000,history=h,market=5000,now=now,
        settings={minProfit=100,minROI=0.2,vendorMinProfit=10}}
    for k,v in pairs(extra or {}) do ctx[k]=v end
    return M.evaluate(rows,ctx)
end
'''


def clean(text):
    return re.sub(r'\|c[0-9a-fA-F]{8}|\|r', '', text)


class MarketTests(unittest.TestCase):
    def test_a_lot_that_pays_both_ways_carries_both_routes(self):
        run(ROUTES + '''local d=judge(1000)
        assert(d and d.mode=='flip', 'the resale pays more and leads')
        assert(d.alt and d.alt.mode=='vendor' and d.alt.qty==2 and d.alt.profit==400, 'the vendor route is kept')
        assert(d.alt.alt==nil)''')

    def test_when_the_vendor_pays_more_it_leads_and_the_resale_is_kept(self):
        run(ROUTES + '''local d=judge(4900)
        assert(d.mode=='vendor', d.mode)
        assert(d.alt and d.alt.mode=='flip', 'the resale is not dropped')''')

    def test_one_route_only_has_no_alt(self):
        run(ROUTES + '''local d=judge(nil)
        assert(d.mode=='flip' and d.alt==nil)
        d=judge(1000,{noResale=true})
        assert(d.mode=='vendor' and d.alt==nil)''')


DEALS = ROUTES + '''local g={key='c:10',kind='commodity',id=10,link=link(10),market=5000,rows=rows}
local D=F.Deals
F.Data.market(F.db,F.Engine.scope()).history['c:10']=h
local deal=D.evaluate(g,1000,h,now)
D.replace({deal},F.Engine.scope())
'''


class DealListTests(unittest.TestCase):
    def test_the_lot_is_on_the_resale_and_the_to_vendor_list(self):
        run(DEALS + '''assert(deal.mode=='flip' and deal.alt and deal.alt.mode=='vendor')
        assert(deal.alt.key=='c:10' and deal.alt.id==10, 'the vendor route is a full deal')
        local flip, vendor, all=D.visible('flip'), D.visible('vendor'), D.visible('all')
        assert(#flip==1 and flip[1].mode=='flip')
        assert(#vendor==1 and vendor[1].mode=='vendor')
        assert(#all==1 and all[1]==deal, 'All lists the item once, by its better route')
        assert(D.get('c:10','vendor').mode=='vendor' and D.get('c:10','flip').mode=='flip')''')

    def test_all_names_the_other_route_of_a_lot_that_pays_both_ways(self):
        out = run(DEALS + '''local UI = ForeverFlip.UI
        UI.show('deals'); UI.filter = 'all'; UI.refresh()
        local all
        for _, r in ipairs(UI.dealTable.rows) do if r:IsShown() and r.key == 'c:10' then all = r.name:GetText() end end
        UI.filter = 'flip'; UI.refresh()
        local flip
        for _, r in ipairs(UI.dealTable.rows) do if r:IsShown() and r.key == 'c:10' then flip = r.name:GetText() end end
        return tostring(all) .. ' @@ ' .. tostring(flip)''')
        all, flip = out.split(' @@ ')
        self.assertIn('+ vendor', all)
        self.assertNotIn('+ vendor', flip)

    def test_the_to_vendor_page_selects_and_buys_the_vendor_route(self):
        run(DEALS + '''F.UI.show('deals:vendor')
        assert(D.get('c:10').mode=='vendor', 'the page decides the route')
        F.UI.show('deals:flip')
        assert(D.get('c:10').mode=='flip')
        F.UI.show('sell')
        assert(D.get('c:10').mode=='flip', 'elsewhere the better route')
        local targets=F.Trade.runTargets()
        assert(#targets==1 and targets[1].mode=='vendor', 'Buy first buys it as a vendor deal')''')

    def test_a_check_marks_both_routes_checked(self):
        run(DEALS + '''F.UI.show('deals:vendor')
        D.verifyCallback('c:10',{{unit=800,qty=2},{unit=5000,qty=10}},true)
        local live=D.get('c:10','all')
        assert(live.verified and live.alt and live.alt.verified==live.verified)''')

    def test_a_merchant_refusal_drops_only_the_vendor_route(self):
        run(DEALS + '''D.refused(10)
        local d=D.get('c:10','all')
        assert(d and d.mode=='flip' and d.alt==nil)
        assert(#D.visible('vendor')==0 and #D.visible('flip')==1)''')

    def test_the_saved_scan_keeps_both_routes_without_rows(self):
        run(DEALS + '''deal.rows={1};deal.alt.rows={1}
        F.Scan.last={scope=F.Engine.scope(),at=now,stats={},groups={}}
        F.Scan.save()
        local saved=F.Data.market(F.db,F.Engine.scope()).last.deals[1]
        assert(saved.alt and saved.alt.mode=='vendor' and saved.rows==nil and saved.alt.rows==nil)''')


SELL = '''local F=ForeverFlip;local UI=F.UI
-- As T.sellWay: both routes passing and no choice made is "undecided" (no price: the player decides).
local function w(q,count) local r={name=q.best or 'auction',value=q.value,quote=q}
    r.routes=F.Market.sellRoutes(q,count,F.db.settings)
    if r.routes.both then r.name,r.value='undecided',nil end
    return r end
'''


class SellRouteTests(unittest.TestCase):
    def test_both_routes_passing_reads_ah_v(self):
        text = run(SELL + '''local q={post=1000,net=900,lost=50,tries=1.5,perDay=2,vendor=600,vendorHow='confirmed',cost=100,best='auction',value=900}
        local r=w(q,5)
        assert(r.routes.both and r.routes.auction.pass and r.routes.vendor.pass)
        assert(r.routes.auction.revenue==5000 and r.routes.vendor.revenue==3000)
        assert(r.routes.auction.profit==5*900-500, r.routes.auction.profit)
        return UI.bestText(r)''')
        self.assertEqual(clean(text), 'AH / V')

    def test_a_route_below_its_threshold_keeps_the_single_best(self):
        text = run(SELL + '''F.db.settings.vendorMinProfit=10
        local q={post=1000,net=900,lost=0,tries=1,vendor=101,vendorHow='confirmed',cost=100,best='auction',value=900}
        local r=w(q,1)
        assert(not r.routes.both and not r.routes.vendor.pass and r.routes.auction.pass)
        return UI.bestText(r)''')
        self.assertTrue(clean(text).startswith('AH '), text)

    def test_a_guessed_price_is_no_auction_route(self):
        run(SELL + '''local q={post=1000,net=900,guess=true,vendor=600,cost=0}
        local r=w(q,1)
        assert(r.routes.auction==nil and not r.routes.both)''')

    def test_the_hover_explains_each_route(self):
        text = run(SELL + '''local q={post=1000,net=900,lost=50,tries=1.5,perDay=2,vendor=600,vendorHow='confirmed',cost=100,best='auction',value=900}
        tooltipLines={}
        UI.bestTooltip(UI.frame,w(q,5),'Linen Cloth')
        return GameTooltip:GetText()..' ## '..table.concat(tooltipLines,' ## ')''')
        text = clean(text)
        for part in ('Best: AH / V', 'Both routes pass their thresholds', 'Expected revenue = 50s 00c',
                     'Cost of the stock = -5s 00c', 'Cut 5% and lost deposits', 'Risk: sells about 2.0 a day',
                     'Threshold: profit at least', 'Expected revenue = 30s 00c', 'Cut and fees = none',
                     'Risk: none: a merchant pays at once'):
            self.assertIn(part, text)


class VendorMinimumPerUnitTests(unittest.TestCase):
    def test_the_vendor_minimum_is_per_unit(self):
        run(SETUP + """local M = ForeverFlip.Market
        local s = { vendorMinProfit = 15, minProfit = 100, minROI = 0.2 }
        local ctx = { kind = 'gear', vendor = 100, budget = 100000, now = now, settings = s, vendorOnly = true }
        -- 6 units at 7c profit each: 42c in all, but no unit earns 15c.
        local d, why = M.evaluate({ { unit = 93, qty = 6 } }, ctx)
        assert(d == nil and why == 'small', tostring(why))
        -- One unit earns 20c: only that one is taken.
        d = M.evaluate({ { unit = 80, qty = 1 }, { unit = 93, qty = 6 } }, ctx)
        assert(d and d.qty == 1 and d.profit == 20, d and d.qty)
        assert(d.offer.qty == 1)""")


if __name__ == '__main__':
    unittest.main()
