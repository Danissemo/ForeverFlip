import unittest
from test_controller import controller_runtime
from test_ui import ui_runtime
from test_domain import ROOT


class SearchReadinessTests(unittest.TestCase):
    def test_native_search_supplies_complete_key(self):
        l=controller_runtime()
        l.execute('''C_AuctionHouse={SendSearchQuery=function(k)
        assert(k.itemID==1 and k.itemLevel==0 and k.itemSuffix==0 and k.battlePetSpeciesID==0)end}
        Enum={AuctionHouseSortOrder={Price=0}}
        ForeverFlip.Adapters.native(db).search({itemID=1})''')

    def test_non_equipment_links_do_not_use_tooltip_level(self):
        controller_runtime().execute('''C_AuctionHouse={GetItemKeyInfo=function()return {isEquipment=false,isCommodity=false}end}
        C_Item={GetDetailedItemLevelInfo=function()return 19 end}
        local key=ForeverFlip.Adapters.keyFromInput('|Hitem:1:0:0:0:0:0:0:0|h[Food]|h')
        assert(key.itemLevel==0 and key.itemSuffix==0 and key.battlePetSpeciesID==0)''')

    def test_family_row_resolves_exact_key_and_displays_selection_immediately(self):
        ui_runtime().execute('''C_Item={GetDetailedItemLevelInfo=function()return 43 end}
        c.candidates={{key={itemID=1},rows={{qty=1,unit=100,cost=100,link='|Hitem:1:0:0:0:0:0:0:0|h[Gloves]|h'}},
        family=true,at=now,scope='scope'}}
        u:show('deals');u.dealRows[1]:Click()
        assert(u.section=='trade' and c.job.key.itemLevel==43 and u.tradeItem.metadata.link)
        assert(not c:fresh() and spent==0)''')

    def test_native_search_waits_for_key_data_instead_of_silently_sending(self):
        controller_runtime().execute('''local loaded=false;sent=0
        C_AuctionHouse={GetItemKeyInfo=function()return loaded and {}or nil end,
        SendSearchQuery=function()sent=sent+1 end};Enum={AuctionHouseSortOrder={Price=0}}
        local native=ForeverFlip.Adapters.native(db)
        assert(native.keyReady({itemID=1})==false);loaded=true;assert(native.keyReady({itemID=1}))
        ''')

    def test_transient_throttle_queues_manual_selection(self):
        ui_runtime().execute('''api.ready=function()return false end
        assert(c:openDeal({key={itemID=1},mode='vendor',family=false}))
        u:show('trade');assert(c.reviewRequest and u.tradeItem.metadata)
        api.ready=function()return true end;now=now+3;c:tick();assert(c.job and calls==1)''')

    def test_npc_starter_has_positive_margin_and_cumulative_one_gold_cap(self):
        controller_runtime().execute('''assert(c:easyNPC());local o=c:options({itemID=1},'vendor')
        assert(o.minProfit==1 and o.absoluteCap<=10000)
        db.ledger[#db.ledger+1]={kind='buy',owner='owner',scope='scope',key='1:0:0:0',qty=1,total=9999,at=now}
        assert(c:npcRemaining()==1)
        local p=ForeverFlip.Market.plan(rows,{},c:options({itemID=1},'vendor'));assert(not p.canBuy)
        c:stop();assert(c:easyNPC());assert(c:npcRemaining()==1 and spent==0)''')

    def test_live_explicitly_requests_cold_data_with_bounded_queue(self):
        controller_runtime().execute('''local A=ForeverFlip.Adapters;loaded=0
        C_Item={IsItemDataCachedByID=function()return false end,RequestLoadItemDataByID=function()loaded=loaded+1 end}
        for i=1,100 do A.requestData(i)end
        A.pumpData(now);assert(loaded<=2 and loaded>0);A.pumpData(now);assert(loaded<=2)''')

    def test_numeric_equipment_search_uses_cached_link_level(self):
        controller_runtime().execute('''C_AuctionHouse={GetItemKeyInfo=function()return {isEquipment=true}end}
        GetItemInfo=function()return 'Gloves','|Hitem:1:0:0:0:0:0:0:0|h[Gloves]|h'end
        C_Item={GetDetailedItemLevelInfo=function()return 43 end}
        local key=ForeverFlip.Adapters.keyFromInput('1');assert(key.itemLevel==43)''')

    def test_one_gold_trial_quote_excludes_its_own_reservation(self):
        controller_runtime().execute('''assert(c:easyNPC());assert(c:openDeal({key={itemID=1},mode='vendor'}))
        c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1);assert(c:requestBuy())
        c:event('COMMODITY_PRICE_UPDATED',100,1000);assert(c:confirmBuy())
        c:event('COMMODITY_PURCHASED',1,10);assert(c:npcRemaining()==9000)
        assert(#db.ledger==1 and db.ledger[1].total==1000)''')

    def test_item_load_request_memory_stays_bounded_without_callbacks(self):
        controller_runtime().execute('''local A=ForeverFlip.Adapters;C_Item={RequestLoadItemDataByID=function()end}
        for i=1,2000 do A.requestData(i)end
        for i=1,1000 do A.pumpData(now+i)end
        assert(not A.requestData(99999))''')

    def test_toolbar_routes_cold_id_to_deferred_search(self):
        ui_runtime().execute('''C_AuctionHouse={GetItemKeyInfo=function()return nil end}
        C_Item={GetItemInfo=function()return nil end,RequestLoadItemDataByID=function()end}
        u.fields.item:SetText('123');u.actions.search:Click()
        assert(u.section=='trade' and c.selectionRequest and c.selection.key.itemID==123)''')

    def test_cold_link_classification_is_retried_without_freezing_tooltip_level(self):
        ui_runtime().execute('''local ready=false
        C_AuctionHouse={GetItemKeyInfo=function()return ready and {isEquipment=false}or nil end}
        C_Item={GetDetailedItemLevelInfo=function()return 19 end,RequestLoadItemDataByID=function()end}
        u.fields.item:SetText('|Hitem:1:0:0:0:0:0:0:0|h[Food]|h');u.actions.search:Click()
        assert(c.selectionRequest and calls==0)
        ready=true;now=now+3;c:tick();assert(c.job and c.job.key.itemLevel==0)''')

    def test_item_data_result_and_failed_native_call_release_request_slots(self):
        from test_domain import ROOT
        l=ui_runtime();l.execute((ROOT/'ForeverFlip/Core.lua').read_text(encoding='utf-8-sig'))
        l.execute('''ForeverFlip.boot('ForeverFlip');local A=ForeverFlip.Adapters
        C_Item={RequestLoadItemDataByID=function()error('offline')end}
        for i=1,2000 do A.requestData(i)end;A.pumpData(now)
        assert(A.requestData(2001))
        local f=ForeverFlip.eventFrame;f.scripts.OnEvent(f,'ITEM_DATA_LOAD_RESULT',100,true)
        assert(A.requestData(2002))''')

    def test_late_background_plan_cannot_replace_selected_trade_preview(self):
        ui_runtime().execute('''db.lastReplicate=now;c.candidates={{key={itemID=1},rows=rows,family=false,kind='commodity',at=now,scope='scope'}}
        c:radarStart();c:tick();c:openDeal({key={itemID=2},mode='vendor'});u:show('trade')
        c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1);u:refresh()
        assert(u.tradeItem.metadata.key.itemID==2 and not c:fresh())''')

    def test_cold_snapshot_rows_are_replayed_after_data_load(self):
        controller_runtime().execute('''loaded=false
        api.replicate=function()end;api.replicateCount=function()return 1 end
        api.replicateRow=function()return loaded and {id=1,key={itemID=1},qty=1,buyout=100,complete=true,family=false}or{id=1,complete=false}end
        c:fullScan();c:event('REPLICATE_ITEM_LIST_UPDATE');c:tick();assert(#c.candidates==0)
        loaded=true;c:itemDataLoaded(1,true);c:tick();assert(#c.candidates==1)''')

    def test_changing_market_does_not_reset_trial_allowance(self):
        controller_runtime().execute('''c:easyNPC();db.ledger[1]={kind='buy',owner='owner',scope='scope',key='1:0:0:0',qty=1,total=9999,at=now}
        c:stop();api.scope=function()return 'other'end;c:easyNPC()
        assert(c:npcRemaining()==1)
        c:stop();api.scope=function()return 'scope'end;c:easyNPC();assert(c:npcRemaining()==1)''')

    def test_snapshot_recovery_keeps_candidate_count_bounded(self):
        controller_runtime().execute('''api.replicate=function()end;api.replicateCount=function()return 1 end
        local loaded=false;api.replicateRow=function()return loaded and {id=9999,key={itemID=9999},qty=1,buyout=100,complete=true}or{id=9999,complete=false}end
        c:fullScan();c:event('REPLICATE_ITEM_LIST_UPDATE');c:tick()
        for i=1,2000 do c.candidates[i]={key={itemID=i},rows=rows,at=now,scope='scope'}end
        loaded=true;c:itemDataLoaded(9999,true);c:tick();assert(#c.candidates<=2000)''')

    def test_starter_ui_prefers_profit_and_never_buys_automatically(self):
        ui_runtime().execute('''db.lastReplicate=now;u:show('deals')
        for _,row in ipairs(u.shopping.listRows)do if row.entry.kind=='starter'then row:Click();break end end
        assert(c.smallNPCActive and c.radar.enabled and u.liveOnly and u.sort=='profit' and u.sortDescending)
        assert(spent==0 and quoted==0)''')


if __name__=='__main__':unittest.main()
