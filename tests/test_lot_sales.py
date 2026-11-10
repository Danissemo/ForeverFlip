"""Sales tracked lot by lot between full scans, sale prices, 14-day history and price age."""

import unittest

from test_addon import SETUP, run, runtime

LOTS = '''local M=ForeverFlip.Market
local function seq(t) local s={} for _,l in ipairs(t) do s[#s+1]=l[1];s[#s+1]=l[2];s[#s+1]=l[3] end return s end
'''


class TrackSalesTests(unittest.TestCase):
    def test_partial_purchase_counts_as_sold(self):
        run(LOTS + '''local n,by=M.trackSales(seq{{100,20,3},{120,5,3}},seq{{100,12,3},{120,5,3}},900)
        assert(n==8 and by[100]==8)''')

    def test_vanished_lot_that_could_not_expire_is_sold(self):
        run(LOTS + '''local n=M.trackSales(seq{{100,1,3},{150,1,3}},seq{{150,1,3}},900);assert(n==1)''')

    def test_vanished_lot_that_could_have_expired_is_not_sold(self):
        run(LOTS + '''local n=M.trackSales(seq{{100,1,0},{150,1,3}},seq{{150,1,3}},900);assert(n==0)''')

    def test_vanished_lot_above_a_surviving_cheaper_lot_was_cancelled(self):
        run(LOTS + '''local n=M.trackSales(seq{{100,1,3},{150,1,3}},seq{{100,1,3}},900);assert(n==0)''')

    def test_new_lots_and_reposts_are_not_sales(self):
        run(LOTS + '''local n=M.trackSales(seq{{100,1,3},{150,1,3}},seq{{100,1,3},{150,1,3},{90,4,3}},900)
        assert(n==0)''')

    def test_pack_and_unpack_keep_the_lots(self):
        run(LOTS + '''local s=seq{{100,2,3},{1500,1,1}};local t=M.unpackLots(M.packLots(s))
        for i=1,#s do assert(s[i]==t[i]) end''')

    def test_sale_price_is_the_median_of_sales(self):
        run(LOTS + '''local h={};M.recordSales(h,{[100]=6,[200]=2,[1000]=1},900,now)
        local p=M.salePrice(h);assert(p>=98 and p<=100,p)
        assert(M.saleCap(h)>=196 and M.saleCap(h)<=200,M.saleCap(h))
        assert(M.salePrice({})==nil)''')


SCANS = SETUP + '''enableTimeLeft()
local F=ForeverFlip
local M=F.Market
local function scan() now=now+901;F.db.lastScan=0;fullScan() end
fullScan()
'''


class ScanTrackingTests(unittest.TestCase):
    def test_two_scans_record_sales_and_daily_units(self):
        run(SCANS + '''-- the cheapest cloth lot (5 at 60c) is bought; another seller lists more at 150c
        table.remove(auctions,1);addAuction(10,150,10)
        scan()
        local h=F.Data.market(F.db,F.Engine.scope()).history['c:10']
        assert(h.sales and h.sales.pairs==1,'lot sales recorded')
        local d=M.demandAt(h,60,now);assert(d.perDay>0 and d.sold==5,d.sold)
        assert(h.days[#h.days].s==5 and h.days[#h.days].n>0)''')

    def test_expired_lot_is_not_a_sale(self):
        run(SETUP + '''enableTimeLeft();local F=ForeverFlip
        auctions[1].timeLeft=1;fullScan();table.remove(auctions,1)
        now=now+901;F.db.lastScan=0;fullScan()
        local h=F.Data.market(F.db,F.Engine.scope()).history['c:10']
        assert(F.Market.demandAt(h,60,now).sold==0)''')

    def test_item_that_sold_out_counts(self):
        run(SETUP + '''enableTimeLeft();local F=ForeverFlip
        addAuction(30,31000,1);fullScan()
        for i=#auctions,1,-1 do if auctions[i].item==30 then table.remove(auctions,i) end end
        now=now+901;F.db.lastScan=0;fullScan()
        local h=F.Data.market(F.db,F.Engine.scope()).history['i:30']
        assert(h and h.sales and F.Market.demandAt(h,30000,now).sold==2 and not h.lots)''')

    def test_history_keeps_fourteen_days(self):
        run(SCANS + '''for i=1,20 do now=now+86400;F.db.lastScan=0;fullScan() end
        local h=F.Data.market(F.db,F.Engine.scope()).history['c:10'];assert(#h.days==14,#h.days)''')


class DisplayTests(unittest.TestCase):
    def test_tooltip_shows_the_age_of_the_price(self):
        run(SETUP + '''fullScan();now=now+7200
        GameTooltip.itemLink=link(10);for _,fn in ipairs(tooltipCalls) do fn(GameTooltip) end
        local found=false
        for _,l in ipairs(tooltipLines) do if l:find('2 h ago',1,true) then found=true end end
        assert(found,table.concat(tooltipLines,'\\n'))''')

    def test_right_click_opens_the_history(self):
        run(SETUP + '''fullScan();local UI=ForeverFlip.UI;UI.show('deals:all')
        local row=UI.dealTable.rows[1];assert(row.key)
        row.scripts.OnClick(row,'RightButton')
        assert(UI.historyFrame and UI.historyFrame:IsShown() and UI.historyFrame.key==row.key)''')


if __name__ == '__main__':
    unittest.main()
