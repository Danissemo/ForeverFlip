"""Market.lua, Util.lua and Sniper.lua: deal maths, money parsing and the fast sniper (review fixes)."""

import unittest

from test_addon import SETUP, run, runtime
from test_fast_sniper import FAST

# Linen Bag (i:30) whose lots were watched: 15-minute scans, `days` long, `hours` a day of them.
WATCHED = SETUP + '''local F=ForeverFlip;local M=F.Market
function watched(days, hours, sales)
    local h={scan={at=now,market=3000}}
    local t=now
    for d=1,days do
        for i=1,hours*4 do
            t=t+900
            M.recordSales(h,(sales and i==1) and sales or {},900,t)
        end
        t=t+(24-hours)*3600
    end
    h.scan.at=t
    now=t
    return h
end
'''


class UnseenSalesTests(unittest.TestCase):
    def test_a_month_of_scans_without_a_sale_leaves_almost_no_chance(self):
        run(WATCHED + '''local h=watched(30,24)
        assert(h.sales.hours<110,'the decayed hours level off near 104')
        local a=M.advice(30,'i:30',h,3000)
        assert(math.abs(a.tries-(1+M.MAX_FAILED))<1e-9,'720 hours without a sale: '..a.tries)''')

    def test_a_few_hours_of_scans_a_day_add_up(self):
        run(WATCHED + '''local h=watched(30,4)
        assert(h.sales.hours<24,'decayed over the hours between sessions too')
        local a=M.advice(30,'i:30',h,3000)
        assert(a.tries>8,'120 hours watched in a month are no fair chance: '..a.tries)''')

    def test_a_cheaper_sale_leaves_the_hours_without_one_at_the_price(self):
        run(WATCHED + '''local h=watched(30,24,{[1000]=1})
        assert(M.saleability(h,1000,now).quiet<24,'it sells at 10 silver every day')
        assert(M.saleability(h,3000,now).quiet>700,'never at 30 silver')
        local a=M.advice(30,'i:30',h,3000)
        assert(math.abs(a.tries-(1+M.MAX_FAILED))<1e-9,'a post at 30 silver: '..a.tries)''')

    def test_the_hours_count_from_the_last_sale_at_the_price(self):
        run(WATCHED + '''local h=watched(1,24)
        M.recordSales(h,{[3000]=1},900,now+900)
        for i=1,8 do M.recordSales(h,{},900,now+900+i*900) end
        local s=M.saleability(h,3000,now)
        assert(math.abs(s.quiet-2)<1e-9,'two hours since the sale: '..tostring(s.quiet))
        assert(math.abs(M.saleability(h,4000,now).quiet-h.sales.watched)<1e-9,'never sold that high')''')

    def test_saves_from_before_the_count_keep_working(self):
        run(SETUP + '''local M=ForeverFlip.Market
        local h={scan={at=now,market=3000},sales={hours=50,pairs=3,at=now,b={}}}
        local s=M.saleability(h,3000,now)
        assert(s.known and s.perDay==0 and s.quiet==nil and s.hours==50)
        local a=M.advice(30,'i:30',h,3000)
        assert(a.tries>1 and a.tries<1+M.MAX_FAILED,'the decayed hours as before: '..a.tries)
        M.recordSales(h,{},900,now+900)
        assert(math.abs(h.sales.watched-50.25)<1e-9,'the count starts from them: '..tostring(h.sales.watched))''')

    def test_flow_only_history_counts_its_hours_too(self):
        # Clients without the time left of full-scan rows measure sales by the level method only.
        run(SETUP + '''local M=ForeverFlip.Market
        local b={};M.bucketAdd(b,3000,20)
        local h={}
        local t=now
        for i=1,30*96 do t=t+900;M.recordFlow(h,b,3000,t) end
        now=t
        assert(h.flow.hours<70 and h.flow.watched>719,h.flow.hours..' '..tostring(h.flow.watched))
        local a=M.advice(30,'i:30',h,3000)
        assert(math.abs(a.tries-(1+M.MAX_FAILED))<1e-9,'a month without a unit gone: '..a.tries)''')


class OwnRateTests(unittest.TestCase):
    SOLD = SETUP + '''local F=ForeverFlip;local M,U=F.Market,F.Util
    local c=F.Data.char(F.db,F.Engine.owner())
    -- The market sells the item (48 a day at 30 silver): only the player's own posts fail.
    local function sold()
        local h={scan={at=now,market=3000},sales={hours=24,pairs=5,at=now,b={}}}
        M.bucketAdd(h.sales.b,3000,48)
        return h
    end
    '''

    def test_gear_finds_its_sale_rate_under_its_full_name(self):
        run(self.SOLD + '''local key=U.key('gear',20,'Northern Shortsword of Healing')
        -- Rates are booked under the mail's name, the full one with the ending (Trade.onFailedPost).
        c.rates={['northern shortsword of healing']={sold=1,failed=9}}
        local a=M.advice(20,key,sold(),3000)
        assert(math.abs(a.tries-10)<1e-9,'one of ten posts sold: '..a.tries)''')

    def test_a_known_rate_of_zero_is_the_worst_case_not_unknown(self):
        run(self.SOLD + '''c.rates={['linen bag']={sold=0,failed=5}}
        local none=M.advice(30,'i:30',sold(),3000)
        c.rates={['linen bag']={sold=1,failed=19}}
        local one=M.advice(30,'i:30',sold(),3000)
        assert(math.abs(none.tries-(1+M.MAX_FAILED))<1e-9,'none of five sold: '..none.tries)
        assert(none.tries>=one.tries and none.best=='vendor','no better than one of twenty')''')


class FlowTests(unittest.TestCase):
    def test_levels_keep_the_market_they_were_measured_against(self):
        run('''local M=ForeverFlip.Market
        local function book(list) local b={};for _,x in ipairs(list) do M.bucketAdd(b,x[1],x[2]) end;return b end
        -- 30 units at 1 silver are bought, 10 at 2 silver stay: the usual price doubles.
        local b1,b2=book({{100,30},{200,10}}),book({{200,10}})
        local h={}
        M.recordFlow(h,b1,M.bucketValue(b1),now)
        M.recordFlow(h,b2,M.bucketValue(b2),now+900)
        assert(h.scan.market==200 and h.flow.market==100,tostring(h.flow.market))
        assert(M.demandAt(h,100).sold==30,'they sold at 1 silver')
        local d=M.demandAt(h,190)
        assert(d.sold==0 and d.perDay==0,'none at 1.9 silver: '..d.perDay)''')


class LearnLowTests(unittest.TestCase):
    def test_only_a_commodity_buyout_of_other_sellers_lowers_todays_cheapest(self):
        run(SETUP + '''local M=ForeverFlip.Market
        local day=math.floor(now/86400)
        local h={['c:10']={days={{d=day,min=100}}},['i:30']={days={{d=day,min=30000}}}}
        M.learnLow(h,{id=30,minPrice=5000,qty=1},now)
        assert(h['i:30'].days[1].min==30000,'the lowest price of a plain item may be a bid')
        M.learnLow(h,{id=10,minPrice=40,qty=10,containsOwnerItem=true},now)
        assert(h['c:10'].days[1].min==100,'the player\\'s own cloth is no cheapest of the house')
        M.learnLow(h,{id=10,minPrice=60,qty=5},now)
        assert(h['c:10'].days[1].min==60)''')


class BreakEvenTests(unittest.TestCase):
    def test_a_dear_commodity_takes_a_few_steps(self):
        run('''local M=ForeverFlip.Market
        local net,calls=M.net,0
        M.net=function(...) calls=calls+1;return net(...) end
        local p=M.breakEven(10000000,1,'commodity') -- 1000 gold
        M.net=net
        assert(calls<=5,'steps: '..calls)
        assert(M.net(p,1)>=10000000 and M.net(p-1,1)<10000000,p)''')

    def test_the_lowest_legal_price_that_returns_the_cost(self):
        # What the loop from the cost returned: the lowest legal price from the cost up that
        # returns it after the (rounded) cut.
        run('''local M,U=ForeverFlip.Market,ForeverFlip.Util
        math.randomseed(7)
        for _,cut in ipairs({0.05,0.15,0.01,0.33}) do
            M.CUT=cut
            for _=1,2500 do
                local kind=({'commodity','item','gear'})[math.random(3)]
                local step=kind=='commodity' and 1 or 100
                local qty=math.random()<0.7 and 1 or math.random(1,50)
                local cost=math.random(0,3000000)*(math.random()<0.3 and 1.05 or 1)
                local p=M.breakEven(cost,qty,kind)
                local low=math.max(step,U.stepUp(cost/qty,kind))
                assert(p>=low and p%step==0 and M.net(p,qty)>=cost,cut..' '..kind..' '..cost)
                assert(p==low or M.net(p-step,qty)<cost,cut..' '..kind..' '..cost..' -> '..p)
            end
        end
        M.CUT=0.05''')


class EvaluateTests(unittest.TestCase):
    def test_a_deal_comes_without_a_reason(self):
        run('''local M=ForeverFlip.Market
        local rows={{unit=800,qty=2},{unit=900,qty=1},{unit=1200,qty=5}}
        local function ctx(extra)
            local c={kind='gear',vendor=1070,budget=100000,now=now,settings={vendorMinProfit=10}}
            for k,v in pairs(extra) do c[k]=v end
            return c
        end
        for _,extra in ipairs({{},{noResale=true},{vendorOnly=true}}) do
            local d,why=M.evaluate(rows,ctx(extra))
            assert(d and d.mode=='vendor' and why==nil,tostring(why))
        end
        local d,why=M.evaluate({{unit=2000,qty=1}},ctx({}))
        assert(not d and why=='no_gap',tostring(why))''')


class ParseMoneyTests(unittest.TestCase):
    def test_a_number_after_the_last_coin_is_the_next_smaller_coin(self):
        run('''local U=ForeverFlip.Util
        assert(U.parseMoney('5g 50')==55000,tostring(U.parseMoney('5g 50')))
        assert(U.parseMoney('1g50')==15000 and U.parseMoney('20s 5')==2005 and U.parseMoney('2g 3s 4')==20304)
        assert(U.parseMoney('1g 20s 5c 7')==nil,'nothing is smaller than copper')''')

    def test_a_negative_amount_is_no_price(self):
        run('''local U=ForeverFlip.Util
        assert(U.parseMoney('-5g')==nil and U.parseMoney('-5')==nil and U.parseMoney('5g -50')==nil)
        assert(U.parseMoney(U.plainMoney(-12345))==nil)''')

    def test_documented_formats_still_work(self):
        run('''local U=ForeverFlip.Util
        assert(U.parseMoney('1g 20s 5c')==12005 and U.parseMoney('20s')==2000 and U.parseMoney('1.5g')==15000)
        assert(U.parseMoney('15')==1500 and U.parseMoney('1,5g')==15000 and U.parseMoney('12,5')==1250)
        assert(U.parseMoney('5gold')==50000 and U.parseMoney(' 7 ')==700)
        assert(U.parseMoney('abc')==nil and U.parseMoney('')==nil and U.parseMoney('10 50')==nil)
        for _,x in ipairs({0,1,99,100,101,12345,10000,10005,999999,1000000}) do
            assert(U.parseMoney(U.plainMoney(x))==x,x)
        end''')


class SniperDropTests(unittest.TestCase):
    def test_a_dropped_query_frees_the_auction_house_at_once(self):
        lua = runtime()
        lua.execute(FAST + '''local F=ForeverFlip
        run(0.1);assert(Sn.query and Sn.inFlight(),'a round is sent')
        Sn.onDropped()
        assert(not Sn.query and not Sn.inFlight(),'nothing answers a dropped query')
        assert(Sn.nextRound>=GetTime()+Sn.PAUSE-1e-6,'the round starts again after the pause')
        assert(F.AH.foreignRecent(),'should it be answered after all, no gear search takes it for its own')
        D.verify('c:10');run(0.2)
        assert(D.search and D.search.key=='c:10','a check goes at once, not 10 seconds later')''')

    def test_a_drop_long_after_the_query_is_not_the_snipers(self):
        lua = runtime()
        lua.execute(FAST + '''
        run(0.1);assert(Sn.inFlight())
        run(3.5);assert(Sn.inFlight(),'no answer yet')
        Sn.onDropped()
        assert(Sn.inFlight(),'the server drops a message when it is sent')''')


class SniperGateTests(unittest.TestCase):
    def test_a_held_page_does_not_spend_the_stuck_throttle(self):
        # With the throttle stuck, ready() lets one message through every 5 seconds: the Buy
        # click the hold waits for needs it.
        lua = runtime()
        lua.execute(FAST + '''local A=ForeverFlip.AH
        run(0.1);assert(Sn.query and Sn.query.kind=='browse','a round is sent')
        browseAnswer();assert(Sn.query and Sn.query.more,'first page only')
        D.holding=function() return true end -- the pointer stays on Buy
        throttleReady=false
        local forced=A.forced or 0
        run(12)
        assert((A.forced or 0)==forced,'the held page spent '..((A.forced or 0)-forced))''')

    def test_the_games_buy_tab_is_not_overwritten(self):
        lua = runtime()
        lua.execute(FAST + '''local F=ForeverFlip
        -- The player clicked the game's Buy tab: ForeverFlip's frame is hidden for it.
        AuctionHouseFrame.BrowseResultsFrame=CreateFrame('Frame');F.UI.frame:Hide()
        assert(F.AH.nativeShown() and not D.holding())
        local n=#calls
        run(5)
        for i=n+1,#calls do
            assert(calls[i][1]~='SendBrowseQuery' and calls[i][1]~='SearchForItemKeys',calls[i][1])
        end''')

    def test_no_next_page_while_the_games_page_is_shown(self):
        lua = runtime()
        lua.execute(FAST + '''local F=ForeverFlip
        Sn.threshold=function() return nil end -- nothing on these pages is a candidate
        run(0.1);assert(Sn.query and Sn.query.kind=='browse')
        browseAnswer();assert(Sn.query and Sn.query.more)
        AuctionHouseFrame.BrowseResultsFrame=CreateFrame('Frame');F.UI.frame:Hide()
        run(2)
        assert(not lastCall('RequestMoreBrowseResults'),'the next page would replace the Buy tab')
        AuctionHouseFrame.BrowseResultsFrame:Hide()
        run(0.5)
        assert(lastCall('RequestMoreBrowseResults'),'it comes once the page is left')''')


class SniperThresholdTests(unittest.TestCase):
    GEM = FAST + '''local F=ForeverFlip;local M=F.Market
    addItem(40,'Gem',100,'commodity')
    local hist=F.Data.market(F.db,F.Engine.scope()).history
    local h={scan={at=now,market=50000},sales={hours=24,pairs=5,at=now,b={}}}
    M.bucketAdd(h.sales.b,50000,240)
    hist['c:40']=h
    '''

    def test_the_history_part_is_worked_out_once_per_change(self):
        lua = runtime()
        lua.execute(self.GEM + '''
        local n,salePrice=0,M.salePrice
        M.salePrice=function(...) n=n+1;return salePrice(...) end
        local a=Sn.threshold('c:40',40,hist)
        local b=Sn.threshold('c:40',40,hist)
        assert(n==1 and a==b and a>30000,'worked out '..n..' times: '..tostring(a))
        M.recordSales(h,{[30000]=400},900,now+900) -- the next full scan saw more sold cheaper
        local c=Sn.threshold('c:40',40,hist)
        assert(n==2 and c<a,'again after the history changed: '..tostring(c))
        h.shared={at=now+1000,m=20000,min=20000,n=5,from='Friend'}
        local d=Sn.threshold('c:40',40,hist)
        assert(n==3,'a shared scan changes the history too')
        M.salePrice=salePrice''')

    def test_settings_and_prices_outside_the_history_count_at_once(self):
        lua = runtime()
        lua.execute(self.GEM + '''
        local a=Sn.threshold('c:40',40,hist)
        F.db.settings.minROI=0.5
        local b=Sn.threshold('c:40',40,hist)
        assert(b<a,'a higher minimum return lowers it: '..a..' '..b)
        F.Shopping.add('c:40',45000,1,'Gem')
        assert(Sn.threshold('c:40',40,hist)==45000,'the shopping list counts at once')''')

    def test_a_frame_reads_browse_rows_for_its_time_budget(self):
        lua = runtime()
        lua.execute(FAST + '''
        for i=1,50 do Sn.backlog[#Sn.backlog+1]={id=10,minPrice=500,qty=1} end
        local ms=0
        debugprofilestop=function() ms=ms+1;return ms end -- each row takes a millisecond
        local items=Sn.items
        Sn.step()
        debugprofilestop=nil
        local read=Sn.items-items
        assert(read>=1 and read<=Sn.BUDGET,'rows for '..Sn.BUDGET..' ms, not '..read)
        assert(#Sn.backlog==50 and Sn.backlogAt==read+1,'the rest waits for the next frame')''')


class SniperShoppingGearTests(unittest.TestCase):
    def test_a_shopping_list_ending_no_scan_has_seen_is_sniped(self):
        lua = runtime()
        lua.execute('''addItem(80,'Lionheart Helm',1,'gear')''' + FAST + '''local F=ForeverFlip
        local key=F.Shopping.resolve(link(80))
        assert(key=='g:80:lionheart helm' and not F.Data.market(F.db,F.Engine.scope()).history[key])
        F.Shopping.add(key,100000,1,'Lionheart Helm')
        addAuction(80,50000,1,'Seller')
        Sn.read({{id=80,minPrice=50000,qty=1}})
        assert(Sn.judged[key],'the key query of the shopping list reads it')
        local guard=0
        while not D.get(key) and guard<400 do
            if D.searching() then answer() elseif browsePendingNow() then browseAnswer() end
            run(0.1);guard=guard+1
        end
        assert(D.get(key) and D.get(key).mode=='shop','checked and found: '..tostring(D.get(key)))''')


if __name__ == '__main__':
    unittest.main()
