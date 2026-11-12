"""Sales tracked lot by lot between full scans, sale prices, 14-day history and price age."""

import unittest

from test_addon import SETUP, run

LOTS = '''local M=ForeverFlip.Market
local function seq(t) local s={} for _,l in ipairs(t) do s[#s+1]=l[1];s[#s+1]=l[2];s[#s+1]=l[3] end return s end
'''


class TrackSalesTests(unittest.TestCase):
    def test_partial_purchase_counts_as_sold(self):
        run(LOTS + '''local n,by=M.trackSales(seq{{100,20,3},{120,5,3}},seq{{100,12,3},{120,5,3}},900)
        assert(n==8 and by[100]==8)''')

    def test_nonexpired_vanished_lot_is_a_sale_candidate(self):
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
    def test_whole_lot_sales_require_a_followup_scan_before_daily_units(self):
        run(SCANS + '''-- the cheapest cloth lot (5 at 60c) is bought; another seller lists more at 150c
        table.remove(auctions,1);addAuction(10,150,10,'Other')
        scan()
        local h=F.Data.market(F.db,F.Engine.scope()).history['c:10']
        -- a whole lot that vanished is only a suspect until the next scan
        assert(h.pending and M.demandAt(h,60,now).sold==0,'suspect, not sold yet')
        scan()
        assert(h.sales and h.sales.pairs==2,'lot sales recorded')
        local d=M.demandAt(h,60,now);assert(d.perDay>0 and d.sold==5,d.sold)
        assert(h.days[#h.days].s==5 and h.days[#h.days].n>0)
        assert(not h.pending)''')

    def test_lot_posted_again_a_scan_later_is_not_a_sale(self):
        run(SCANS + '''-- the seller cancels the 60c lot, and posts it again only after the next scan
        local lot=table.remove(auctions,1)
        scan()
        local h=F.Data.market(F.db,F.Engine.scope()).history['c:10']
        assert(h.pending)
        table.insert(auctions,lot)
        scan()
        assert(M.demandAt(h,60,now).sold==0 and not h.pending)
        assert((h.days[#h.days].s or 0)==0)''')

    def test_partly_bought_lot_is_sold_at_once(self):
        run(SCANS + '''auctions[1].count=auctions[1].count-2;auctions[1].buyout=60*auctions[1].count
        scan()
        local h=F.Data.market(F.db,F.Engine.scope()).history['c:10']
        assert(M.demandAt(h,60,now).sold==2 and not h.pending)''')

    def test_suspect_waits_at_most_three_hours(self):
        run(LOTS + '''local h={};local s={100,1,3,150,1,3}
        ForeverFlip.Scan.trackLots(h,s,now);now=now+900
        ForeverFlip.Scan.trackLots(h,{150,1,3},now);assert(h.pending)
        now=now+4*3600;ForeverFlip.Scan.trackLots(h,{150,1,3},now)
        assert(not h.pending and M.salePrice(h)==nil)''')

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
        now=now+901;F.db.lastScan=0;fullScan() -- still gone: the suspects are sales
        local h=F.Data.market(F.db,F.Engine.scope()).history['i:30']
        assert(h and h.sales and F.Market.demandAt(h,30000,now).sold==2 and not h.lots and not h.pending)''')

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



class SalesCleanupTests(unittest.TestCase):
    def test_sales_measured_before_the_repost_protection_are_dropped_once(self):
        run(LOTS + '''local db={markets={s={history={k={sales={hours=4,pairs=9,b={}},flow={hours=4},
          scan={market=10},days={{d=1,m=10,n=31,s=194}}}}}}}
        db=ForeverFlip.Data.open(db);local h=db.markets.s.history.k
        assert(not h.sales and not h.flow and h.days[1].s==nil and h.days[1].n==31 and h.scan.market==10)
        h.sales={hours=1};ForeverFlip.Data.open(db);assert(h.sales,'once')''')

    def test_watched_item_never_seen_sold_is_no_resale(self):
        run(LOTS + '''local h={sales={hours=3,pairs=12,b={}},flow={hours=3,pairs=12,market=9900,sold={0,0,0,0}}}
        local cap,unsold=ForeverFlip.Deals.resaleCap(9900,h);assert(cap==nil and unsold)
        local d,why=M.evaluate({{unit=2700,qty=1},{unit=9900,qty=3}},{kind='gear',budget=100000,history=h,
          market=cap,noResale=unsold,now=now,settings={}})
        assert(not d and why=='not_selling',why)''')

    def test_one_confirmed_sale_caps_the_resale_price(self):
        run(LOTS + '''local h={};M.recordSales(h,{[3000]=1},3600,now)
        assert(ForeverFlip.Deals.resaleCap(9900,h)==3000)
        assert(ForeverFlip.Deals.resaleCap(9900,{})==9900,'not watched: the asking price')''')


if __name__ == '__main__':
    unittest.main()


class HardenedSalesTests(unittest.TestCase):
    def test_a_seller_who_takes_a_lot_down_and_posts_it_cheaper_did_not_sell(self):
        run(SCANS + '''-- the seller of the 60c lot undercuts: takes it down, posts the same goods at 55c
        local lot=table.remove(auctions,1)
        addAuction(10,55,lot.count+1,lot.owner)
        scan(); scan()
        local h=F.Data.market(F.db,F.Engine.scope()).history['c:10']
        assert(M.demandAt(h,60,now).sold==0,'a repost at a new price and count is no sale')''')

    def test_own_purchases_are_not_market_demand(self):
        run(SCANS + '''local F=ForeverFlip
        local c=F.Data.char(F.db,F.Engine.owner())
        local lot=table.remove(auctions,1) -- the player buys the cheapest lot
        F.Data.log(c,{at=now+5,kind='buy',key='c:10',name='Linen Cloth',qty=lot.count,amount=lot.buyout})
        addAuction(10,150,10,'Other')
        scan(); scan()
        local h=F.Data.market(F.db,F.Engine.scope()).history['c:10']
        assert(M.demandAt(h,1,now).sold==0,'the player bought it: '..M.demandAt(h,1,now).sold)''')

    def test_a_one_off_sweep_is_counted_at_a_ceiling(self):
        run(LOTS + '''local h={}
        for i=1,4 do M.recordSales(h,{[100]=4},900,now+i*900) end
        M.recordSales(h,{[100]=400},900,now+5*900)
        assert(h.sales.sweeps==1,'the sweep was noticed')
        local d=M.lotDemand(h,100)
        assert(d.sold<4*4+13,'counted at three times the usual pair: '..d.sold)''')

    def test_the_evidence_names_kinds_prices_and_units(self):
        run(LOTS + '''local h={}
        M.recordSales(h,{[100]=6,[120]=2},900,now,{[120]=2})
        M.recordSales(h,{[110]=3},900,now+900)
        local e=M.saleEvidence(h)
        assert(e.units==11 and e.sure==9 and e.lots==2 and e.buys==3,e.units..' '..e.sure..' '..e.lots)
        assert(e.low==100 and e.high==120 and e.median==100,e.median)
        local above=M.saleEvidence(h,110)
        assert(above.units==5 and above.low==110)''')


class ThinEvidenceTests(unittest.TestCase):
    def test_a_deal_never_buys_more_than_was_ever_seen_bought(self):
        run(LOTS + '''local h={}
        M.recordSales(h,{[7700]=1},900,now-900); M.recordSales(h,{[7700]=1},900,now)
        assert(M.lotDemand(h,7700).perDay>5,'a high day rate from two purchases')
        local ctx={kind='commodity',vendor=10,budget=10000000,history=h,market=7800,now=now,settings={minProfit=1,minROI=0.01}}
        local d=M.evaluate({{unit=900,qty=1},{unit=900,qty=1},{unit=7800,qty=16}},ctx)
        assert(d and d.mode=='flip' and d.qty==2,'two seen bought, two bought: '..tostring(d and d.qty))
        d=M.evaluate({{unit=900,qty=1},{unit=900,qty=1},{unit=900,qty=1},{unit=7800,qty=16}},ctx)
        assert(not d,'three would be more than were ever seen bought')''')

    def test_the_deal_detail_lists_the_purchases_seen(self):
        from test_addon import SETUP
        run(SETUP + '''local F,UI,M=ForeverFlip,ForeverFlip.UI,ForeverFlip.Market
        local h={}
        M.recordSales(h,{[90]=5,[95]=3},900,now,{[95]=3})
        local line=UI.saleEvidenceLine(h,80)
        assert(line:find('2 purchases, 8 units') and line:find('5 from lots bought in part') and line:find('3 whole lots'),line)
        assert(UI.saleEvidenceLine({},80):find('No purchase'))''')
