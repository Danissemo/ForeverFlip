import unittest
from test_controller import controller_runtime

SCAN = '''
local function scan(list)
  local j={groups={},groupsCount=0,at=now,scope='scope',total=0,skipped=0}
  for _,v in ipairs(list) do
    for _=1,v[2] do c:ingestReplica(j,{key={itemID=v[1]},qty=1,buyout=v[3],family=false},now);j.total=j.total+1 end
  end
  return j
end
'''


class SearchAuditTests(unittest.TestCase):
    def run_lua(self, code):
        controller_runtime().execute(SCAN + code)

    def test_restored_scan_older_than_30_minutes_is_still_searched(self):
        self.run_lua('''db.lastReplicate=now-2400;db.markets={scope={}}
        local rows={{qty=1,unit=100,cost=100}};for i=1,10 do rows[#rows+1]={qty=1,unit=1000,cost=1000}end
        for i=1,50 do db.markets.scope[i..':0:0:0']={latest={at=now-2400,rows=rows,family=false}}end
        c.candidates={};assert(c:radarStart());for _=1,40 do c:advanceRestoreCandidates(25)end
        for _=1,200 do c:tick()end;assert(#c.radar.queue>0 and calls>=1)
        local p=c:rankCandidate(c.candidates[1]);assert(p and p.canBuy)''')

    def test_restore_survives_new_market_entries_during_iteration(self):
        self.run_lua('''db.markets={scope={}}
        for i=1,500 do db.markets.scope[i..':0:0:0']={latest={at=now-60,rows={{qty=1,unit=100,cost=100}},family=false}}end
        c.candidates={};c:restoreCandidates();c:advanceRestoreCandidates(25)
        for i=1000,1300 do db.markets.scope[i..':0:0:0']={latest={at=now,rows={{qty=1,unit=100,cost=100}}}}end
        for _=1,40 do c:advanceRestoreCandidates(25)end;assert(#c.candidates==500)''')

    def test_scan_market_value_uses_full_depth_not_64_cheapest_rows(self):
        self.run_lua('''api.wallet=function()return 1000000 end
        local j=scan({{7,3,5000},{7,197,10000}});c:finishScan(j,now)
        local g=c.candidates[1];assert(#g.rows==64 and g.market>=9800 and g.market<=10000)
        local h=db.markets.scope['7:0:0:0'];assert(h.latest.market==g.market)
        h.flow={hours=10,sold={20,20,20,20},pairs=3,at=now,market=g.market}
        local p=c:rankCandidate(g);assert(p.canBuy and p.basis=='listings' and p.target>=9000)
        assert(p.qty==3)''')

    def test_demand_between_scans_blocks_items_that_never_sell_and_caps_quantity(self):
        self.run_lua('''local M=ForeverFlip.Market
        for n=1,4 do c:finishScan(scan({{5,20,1000},{5,40,4000}}),now);now=now+3600 end
        local h=db.markets.scope['5:0:0:0'];local d=M.demand(h,now)
        assert(d.pairs==3 and d.sold==0)
        local o=c:options({itemID=5},'flip');assert(o.demand.pairs==3)
        local rows={{qty=2,unit=500,cost=1000}};for i=1,10 do rows[#rows+1]={qty=1,unit=4000,cost=4000}end
        local p=M.plan(rows,{},o);assert(not p.canBuy)
        local found=false;for _,r in ipairs(p.reasons)do found=found or r=='no_demand' end;assert(found)
        local sold={scan={at=now-3600,market=1000,cheap=20}}
        local b={};M.bucketAdd(b,1000,5);M.bucketAdd(b,4000,40);M.recordDemand(sold,b,1000,now)
        assert(sold.demand[1].sold==15 and math.abs(M.demand(sold,now).perDay-360)<1e-6)''')

    def test_resale_needs_sales_near_the_exit_and_buys_one_day_of_them(self):
        self.run_lua('''local rows={};for i=1,3 do rows[#rows+1]={qty=2,unit=100,cost=200}end
        for i=1,60 do rows[#rows+1]={qty=1,unit=1000,cost=1000}end
        local M=ForeverFlip.Market
        local o=c:options({itemID=8},'flip');local p=M.plan(rows,{},o)
        assert(p.basis=='listings' and not p.canBuy and p.reasons[1]=='demand_unknown')
        db.markets.scope=db.markets.scope or {};db.markets.scope['8:0:0:0']={samples={},days={},flow={hours=24,sold={40,30,8,0},pairs=4,at=now,market=1000}}
        p=M.plan(rows,{},c:options({itemID=8},'flip'));assert(p.canBuy and p.qty==6 and p.demand.level==0.9 and p.target==900)
        db.markets.scope['8:0:0:0'].flow.sold={40,30,4,0}
        p=M.plan(rows,{},c:options({itemID=8},'flip'));assert(not p.canBuy and p.target==100)
        db.markets.scope['8:0:0:0'].flow.sold={40,30,0,0}
        p=M.plan(rows,{},c:options({itemID=8},'flip'));assert(not p.canBuy and p.reasons[1]=='no_demand')''')

    def test_resale_price_undercuts_the_cheap_lots_left_after_buying(self):
        self.run_lua('''local M=ForeverFlip.Market
        -- Screenshot case: 8 flasks at 9-10s, a wall from 78s, demand allows 3.
        local rows={{qty=2,unit=900,cost=1800},{qty=5,unit=998,cost=4990},{qty=1,unit=999,cost=999},{qty=1,unit=4900,cost=4900}}
        for i=1,16 do rows[#rows+1]={qty=1,unit=7800,cost=7800}end
        for i=1,10 do rows[#rows+1]={qty=1,unit=9000,cost=9000}end
        db.markets.scope=db.markets.scope or {};db.markets.scope['2593:0:0:0']={samples={},days={},flow={hours=24,sold={3,3,3,3},pairs=4,at=now,market=7800}}
        local o=c:options({itemID=2593},'flip');o.marketHint=7800
        local p=M.plan(rows,{},o)
        assert(not p.canBuy and (p.target or 0)<=900, tostring(p.target))
        -- Fewer cheap lots: the exit is one silver below the cheapest lot left after buying.
        table.remove(rows,2)
        p=M.plan(rows,{},c:options({itemID=2593},'flip'))
        assert(p.canBuy and p.qty==3 and p.target==4800 and p.competitor==4900)
        db.markets.scope['2593:0:0:0'].flow.sold={30,30,30,30}
        p=M.plan(rows,{},c:options({itemID=2593},'flip'))
        assert(p.canBuy and p.qty==4 and p.target==7700)''')

    def test_dropped_query_is_retried_without_waiting_for_timeout(self):
        self.run_lua('''db.lastReplicate=now
        c.candidates={{key={itemID=1},rows={{qty=1,unit=100,cost=100}},kind='commodity',family=false,at=now,scope='scope'}}
        api.vendor=function()return 1000 end;assert(c:radarStart());c:tick();assert(calls==1 and c.job)
        c:event('AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED');assert(not c.job)
        now=now+2;c:tick();assert(calls==2 and c.job and c.job.key.itemID==1)
        c:stop();now=now+2;assert(c:search({itemID=3}));c:event('AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED')
        assert(not c.job and c.reviewRequest and c.reviewRequest.key.itemID==3)''')

    def test_reload_during_scan_processing_keeps_the_processed_part(self):
        self.run_lua('''db.lastReplicate=nil;api.replicate=function()end;api.replicateCount=function()return 5000 end
        api.replicateRow=function(i)return {id=i%50+1,key={itemID=i%50+1},qty=1,buyout=100,complete=true,family=false}end
        assert(c:fullScan());c:event('REPLICATE_ITEM_LIST_UPDATE');c:tick()
        assert(c.fullJob and c.fullJob.index<5000)
        assert(c:saveScanProgress() and not c.fullJob and db.lastScan.partial and #c.candidates==50)
        assert(db.markets.scope['1:0:0:0'] and db.markets.scope['1:0:0:0'].latest.rows)
        assert(not c:saveScanProgress())''')

    def test_buying_one_equipment_lot_looks_up_the_next_one(self):
        self.run_lua('''api.rows=function()return {{qty=1,unit=5,cost=5,auctionID=77},{qty=1,unit=5,cost=5,auctionID=78}},true,'item' end
        c:search({itemID=414});c:event('ITEM_SEARCH_RESULTS_UPDATED',{itemID=414});assert(c:requestBuy())
        if c.active.status~='awaiting' then c:confirmBuy() end
        c:event('AUCTION_HOUSE_PURCHASE_COMPLETED',77)
        assert(#db.ledger==1 and c.reviewRequest and c.reviewRequest.key.itemID==414)
        now=now+3;c:tick();assert(c.job and c.job.key.itemID==414)''')

    def test_never_completing_check_backs_off_then_waits_for_new_data(self):
        self.run_lua('''db.lastReplicate=now;full=false
        c.candidates={{key={itemID=1},rows={{qty=1,unit=100,cost=100}},kind='commodity',family=false,at=now,scope='scope'}}
        api.vendor=function()return 1000 end;c.more=function()return true end;assert(c:radarStart())
        local s0=calls
        for _=1,3600 do now=now+1;c:tick();if c.job and c.job.key.itemID==1 then c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)end end
        assert(calls-s0<=4 and c.radar.fails['1:0:0:0']>=4 and c.radar.retryAt['1:0:0:0']==nil)''')

    def test_opening_a_live_deal_drops_per_item_caps(self):
        self.run_lua('''c.overrides={maxQty=1,budget=1}
        assert(c:openDeal({key={itemID=1},mode='flip',source='radar'}));assert(c.overrides==nil)
        c.overrides={maxQty=1};assert(c:openDeal({key={itemID=1},mode='flip'}));assert(c.overrides)''')

    def test_listed_deals_older_than_a_minute_are_rechecked_first(self):
        self.run_lua('''db.lastReplicate=now;c.candidates={}
        for i=1,30 do c.candidates[i]={key={itemID=i},rows={{qty=1,unit=100,cost=100}},kind='commodity',family=false,at=now,scope='scope'}end
        api.vendor=function()return 1000 end;assert(c:radarStart())
        c.radar.opportunities['25:0:0:0']={key={itemID=25},rows=rows,kind='commodity',at=now-120}
        for _=1,40 do c:tick()end;assert(c.job and c.job.key.itemID==25)''')

    def test_vendor_price_is_saved_and_reused_when_the_client_has_no_data(self):
        self.run_lua('''local A=ForeverFlip.Adapters;requested={}
        A.requestData=function(id)requested[id]=true return true end
        GetItemInfo=function(id)return 'X',nil,1,1,1,nil,nil,1,nil,nil,700 end
        assert(A.vendorPrice(db,4242)==700 and db.ui.vendorPrices[4242]==700)
        assert(A.vendorPrice(db,'|cff|Hitem:4242:0:0:0:0:0:15:0|h[X]|h|r')==700)
        GetItemInfo=function()return nil end
        assert(A.vendorPrice(db,4242)==700 and not requested[4242])
        assert(A.vendorPrice(db,5555)==nil and requested[5555])
        local asked=0;GetItemInfo=function()asked=asked+1 end
        C_Item={IsItemDataCachedByID=function()return false end}
        assert(A.vendorPrice(db,4242,true)==700 and A.vendorPrice(db,6666,true)==nil and asked==0 and not requested[6666])''')

    def test_vendor_deal_needs_little_profit_and_covers_suffix_gear(self):
        self.run_lua('''api.vendor=function()return 2000 end
        local o=c:options({itemID=9,itemSuffix=1200},'vendor');assert(o.vendor==2000)
        local p=ForeverFlip.Market.plan({{qty=1,unit=1000,cost=1000}},{},o)
        assert(p.mode=='vendor' and p.canBuy and p.minProfit<10000 and p.profit==1000)''')

    def test_full_scan_keeps_the_best_items_beyond_the_first_two_thousand(self):
        self.run_lua('''api.vendor=function()return nil end
        local list={};for i=1,3000 do list[i]={i,3,1000}end
        list[2900]={2900,1,100};list[#list+1]={2900,10,1000}
        local j=scan(list);c:finishScan(j,now)
        assert(#c.candidates==2000 and c.candidates[1].key.itemID==2900)
        assert(db.lastScan.items==3000 and db.markets.scope['2900:0:0:0'])''')

    def test_item_without_vendor_price_is_added_when_its_data_loads(self):
        self.run_lua('''local known={};api.vendor=function(id)return known[id] end
        local list={};for i=1,2100 do list[i]={i,2,1000}end
        local j=scan(list);c:finishScan(j,now);assert(#c.candidates==2000 and c.scanPool)
        local id;for i=1,2100 do local found=false
          for _,g in ipairs(c.candidates)do if g.key.itemID==i then found=true end end
          if not found then id=i break end end
        assert(id and c.scanPool.byItem[id])
        known[id]=5000;c:itemDataLoaded(id,true)
        assert(#c.candidates==2001 and c.candidates[2001].key.itemID==id and db.markets.scope[id..':0:0:0'])
        assert(not c.scanPool.byItem[id] and not c:promoteScanItem(id,true))''')

    def test_scan_finishing_is_spread_over_frames_and_keeps_old_candidates_until_done(self):
        self.run_lua('''api.vendor=function()return nil end;c.candidates={{key={itemID=99999}}}
        local list={};for i=1,3000 do list[i]={i,2,1000}end
        local j=scan(list);c.fullJob=j;local steps=0
        repeat steps=steps+1;local done=c:finishStep(j,now,false,6)
          if not done then assert(c.candidates[1].key.itemID==99999 and c.fullJob==j)end
        until done
        assert(steps>3 and #c.candidates==2000 and not c.fullJob and not j.finish)''')

    def test_reload_while_finishing_saves_everything(self):
        self.run_lua('''api.vendor=function()return 1 end
        local list={};for i=1,1000 do list[i]={i,2,1000}end
        local j=scan(list);c.fullJob=j;assert(not c:finishStep(j,now,false,6))
        assert(c:saveScanProgress() and #c.candidates==1000 and not c.fullJob and not db.lastScan.partial)''')

    def test_won_auction_chat_message_confirms_a_purchase_without_the_auction_event(self):
        self.run_lua('''ERR_AUCTION_WON_S='You won an auction for %s'
        GetItemInfo=function(id)if id==2593 then return 'Flask of Stormwind Tawny' end end
        api.rows=function()return {{qty=3,unit=5,cost=15,auctionID=77}},true,'item' end
        c:search({itemID=2593});c:event('ITEM_SEARCH_RESULTS_UPDATED',{itemID=2593});assert(c:requestBuy())
        if c.active.status~='awaiting' then c:confirmBuy() end
        c:event('CHAT_MSG_SYSTEM','You won an auction for Other Item (x3)');assert(c.active and #db.ledger==0)
        c:event('CHAT_MSG_SYSTEM','You won an auction for Flask of Stormwind Tawny (x2)');assert(c.active)
        c:event('CHAT_MSG_SYSTEM','You won an auction for Flask of Stormwind Tawny (x3)')
        assert(not c.active and #db.ledger==1 and db.ledger[1].qty==3)
        c:event('AUCTION_HOUSE_PURCHASE_COMPLETED',77);assert(#db.ledger==1)''')

    def test_sales_flow_counts_only_units_gone_near_the_resale_price(self):
        self.run_lua('''local M=ForeverFlip.Market;local h={}
        local function book(cheap,wall)local b={};if cheap>0 then M.bucketAdd(b,900,cheap)end;M.bucketAdd(b,7800,wall);return b end
        -- Flippers keep buying the cheap flasks; the 78s wall never moves.
        M.recordDemand(h,book(8,16),7800,now);M.recordDemand(h,book(2,16),7800,now+900)
        M.recordDemand(h,book(8,16),7800,now+1800)
        local d=M.demandAt(h,7700,now+1800);assert(d.pairs==2 and d.sold==0 and d.perDay==0)
        -- Wall units leave: real sales near the price.
        M.recordDemand(h,book(8,10),7800,now+2700)
        d=M.demandAt(h,7700,now+2700);assert(d.pairs==3 and d.sold==6 and d.perDay>100)
        assert(M.demandAt({},7700,now).pairs==0)''')

    def test_vendor_deal_uses_free_cash_and_needs_only_five_percent(self):
        self.run_lua('''api.wallet=function()return 100000 end;api.vendor=function()return 1000 end;db.settings.maxQty=100
        local rows={};for i=1,40 do rows[i]={qty=1,unit=900,cost=900}end
        local p=ForeverFlip.Market.plan(rows,{},c:options({itemID=9},'vendor'))
        assert(p.canBuy and p.minROI==0.05 and p.cost>10000 and p.qty==40,tostring(p.qty))''')

    def test_partial_resale_in_the_planner_is_priced_below_the_lots_left(self):
        self.run_lua('''local p={key={itemID=1},mode='flip',kind='commodity',qty=10,cost=1000,target=5000,feeRate=0.05,
          lots={{qty=10,unit=100,cost=1000}},confidence=1,canBuy=true,at=now,minProfit=0,minROI=0}
        local r=ForeverFlip.Workbench.allocate({p},{budget=100000,riskCap=100000,now=now,drop=0})
        for _,line in ipairs(r.lines)do assert(line.qty==10 or line.target<=100,line.qty..' '..line.target)end''')

    def test_sell_side_price_undercuts_the_cheapest_listing(self):
        self.run_lua('''db.markets.scope={['5:0:0:0']={latest={at=now,price=7800,rows={{qty=2,unit=900,cost=1800}}}}}
        assert(c:price(5)==7800 and c:price(5,'sell')==800)''')

    def test_scan_potential_needs_lots_below_the_next_listing(self):
        self.run_lua('''local same={market=100,rows={}};for i=1,10 do same.rows[i]={qty=1,unit=100}end
        assert(c:scanPotential(same)==0)
        local cheap={market=1000,rows={{qty=1,unit=100}}};for i=2,10 do cheap.rows[i]={qty=1,unit=1000}end
        assert(c:scanPotential(cheap)==850)''')

    def test_blocked_deal_shows_its_reason_instead_of_a_dash(self):
        self.run_lua('''local D=ForeverFlip.ItemDisplay
        assert(D.shortReason({reasons={'partial','demand_unknown'}})~='—')
        assert(D.shortReason({reasons={'no_demand'}})~=D.shortReason({reasons={'margin'}}))
        assert(D.shortReason({reasons={'legacy'}})=='—')''')

    def test_empty_live_selection_is_not_repeated_until_data_changes(self):
        self.run_lua('''db.lastReplicate=now;c.candidates={}
        for i=1,30 do c.candidates[i]={key={itemID=i},rows={{qty=1,unit=1000,cost=1000}},kind='commodity',family=false,at=now,scope='scope'}end
        api.vendor=function()return 10 end;assert(c:radarStart())
        local builds=0;local R=ForeverFlip.Radar
        for _=1,60 do now=now+1;c:tick();if c.radar.build then builds=builds+1 end end
        assert(#c.radar.queue==0 and c.radar.idleInputs and calls==0)
        local before=builds
        for _=1,60 do now=now+1;c:tick();if c.radar.build then builds=builds+1 end end
        assert(builds==before,builds..' '..before)
        c.itemDataEpoch=(c.itemDataEpoch or 0)+1;for _=1,20 do now=now+1;c:tick()end
        assert(not c.radar.idleInputs or c.radar.idleInputs:find(':'..c.itemDataEpoch..':'))''')

    def test_live_selection_prefilters_and_reports_what_it_found(self):
        self.run_lua('''db.lastReplicate=now;c.candidates={}
        for i=1,200 do c.candidates[i]={key={itemID=i},rows={{qty=1,unit=1000,cost=1000},{qty=1,unit=1500,cost=1500}},
          kind='commodity',family=false,at=now,scope='scope',market=1500}end
        api.vendor=function(id)if id<=3 then return 5000 end if id<=150 then return 10 end end
        assert(c:radarStart());for _=1,40 do c:tick()end
        local s=c.radar.stats;assert(s and s.items==200 and s.vendorKnown==150 and s.vendor==3)
        assert(s.collecting==197 and s.resale==0,s.collecting)
        assert(calls>=1 and c.job and c.job.key.itemID<=3)''')

    def test_found_deals_are_not_rechecked_in_a_loop(self):
        self.run_lua('''db.lastReplicate=now;c.candidates={}
        for i=1,2 do c.candidates[i]={key={itemID=i},rows=rows,kind='commodity',family=false,at=now,scope='scope'}end
        api.vendor=function()return 1000 end;assert(c:radarStart())
        for _=1,50 do now=now+1;c:tick();if c.job then c:event('COMMODITY_SEARCH_RESULTS_UPDATED',c.job.key.itemID)end end
        local first=calls;assert(first==2,first)
        for _=1,50 do now=now+0.2;c:tick();if c.job then c:event('COMMODITY_SEARCH_RESULTS_UPDATED',c.job.key.itemID)end end
        assert(calls==first,calls)
        for _=1,80 do now=now+1;c:tick();if c.job then c:event('COMMODITY_SEARCH_RESULTS_UPDATED',c.job.key.itemID)end end
        assert(calls>first and calls<=first+4,calls)''')


if __name__ == '__main__':
    unittest.main()
