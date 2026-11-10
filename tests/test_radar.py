import unittest
from test_controller import controller_runtime


class RadarTests(unittest.TestCase):
    def run_lua(self, body):
        l = controller_runtime()
        l.execute('''api.replicate=function() replicas=(replicas or 0)+1 end
        db.lastReplicate=now; replicas=0
        c.candidates={{key={itemID=1},rows=rows,kind='commodity',family=false,at=now,scope='scope'}}
        alerts=0;c.alert=function()alerts=alerts+1 end
        ''')
        l.execute(body)

    def test_queries_both_strategies_without_financial_actions(self):
        self.run_lua('''c.mode='flip';c.overrides={maxQty=0};assert(c:radarStart());c:tick()
        assert(c.job.origin=='radar' and calls==1)
        c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        local a=ForeverFlip.Radar.list(c);assert(#a==1 and a[1].mode=='vendor')
        assert(not c:fresh() and not c:requestBuy() and spent==0 and quoted==0 and alerts==1)''')

    def test_pacing_and_ready_gate(self):
        self.run_lua('''assert(c:radarStart());api.ready=function()return false end;c:tick();assert(calls==0)
        api.ready=function()return true end;c:tick();c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        c:tick();now=now+0.5;c:tick();assert(calls==1)
        now=now+20;c:tick();assert(calls==2)''')

    def test_manual_review_pauses_then_resume_and_stop(self):
        self.run_lua('''c:radarStart();c:tick();now=now+3
        assert(c:search({itemID=2}));assert(c.radar.paused and c.reviewRequest)
        c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1);c:tick();assert(c.job.origin~='radar')
        c:event('COMMODITY_SEARCH_RESULTS_UPDATED',2);now=now+10;c:tick();assert(calls==2)
        c:radarStart();c:tick();assert(calls==3);c:stop();now=now+100;c:tick()
        assert(not c.radar.enabled and calls==3)''')

    def test_empty_results_remove_opportunity_and_discovery(self):
        self.run_lua('''c:radarStart();c:tick();c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        assert(#ForeverFlip.Radar.list(c)==1);now=now+20;c:tick();rows={}
        c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        assert(#ForeverFlip.Radar.list(c)==0 and #c.candidates==0)''')

    def test_unchanged_alert_dedup_and_stale_expiry(self):
        self.run_lua('''c:radarStart();c:tick();c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        now=now+20;c:tick();c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1);assert(alerts==1)
        now=now+601;assert(#ForeverFlip.Radar.list(c)==0)''')

    def test_initial_replication_and_periodic_cooldown(self):
        self.run_lua('''db.lastReplicate=nil;c.candidates={};c:radarStart();c:tick()
        assert(replicas==1 and c.fullJob.origin=='radar')
        api.replicateCount=function()return 0 end;c:event('REPLICATE_ITEM_LIST_UPDATE');c:tick()
        now=now+899;c:tick();assert(replicas==1)
        now=now+1;c:tick();assert(replicas==2)''')

    def test_close_scope_and_owner_stop(self):
        for change in ["open=false", "api.scope=function()return 'other'end", "api.owner=function()return 'other'end"]:
            self.run_lua('c:radarStart();c:tick();'+change+''';c:tick()
            assert(not c.radar.enabled and not c.job and spent==0)''')

    def test_partial_pages_are_bounded_and_never_alert(self):
        self.run_lua('''pages=0;api.more=function()pages=pages+1 end;full=false
        c:radarStart();c:tick();c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        assert(alerts==0 and #ForeverFlip.Radar.list(c)==0)
        for i=1,5 do now=now+3;c:tick();c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)end
        assert(pages<=3 and alerts==0 and spent==0)''')

    def test_queue_bounded_and_family_not_guessed(self):
        self.run_lua('''c.candidates={};db.watchlist={}
        for i=1,150 do c.candidates[i]={key={itemID=i},rows=rows,kind='commodity',family=false,at=now,scope='scope'}end
        c.candidates[151]={key={itemID=999},rows=rows,family=true,at=now,scope='scope'}
        c:radarStart();for i=1,100 do c:tick()end;assert(#c.radar.queue<=120)
        for _,k in ipairs(c.radar.queue)do assert(k.itemID~=999)end''')

    def test_timeout_does_not_spin(self):
        self.run_lua('''c:radarStart();c:tick();now=now+21;c:tick();assert(calls==1)
        c:tick();assert(calls==1);now=now+30;c:tick();assert(calls==1 and c.radar.checkedAt['1:0:0:0'])''')

    def test_native_live_controls_pause_resume_and_manual_navigation(self):
        from test_ui import ui_runtime
        ui_runtime().execute('''db.lastReplicate=now
        c.candidates={{key={itemID=1},rows=rows,kind='commodity',family=false,at=now,scope='scope'}}
        assert(u.actions.live);u.actions.live:Click();assert(c.radar.enabled and u.liveOnly)
        c:tick();c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1);u:refresh();assert(#u.visibleDeals==1)
        u.actions.live:Click();assert(c.radar.paused);u.actions.live:Click();assert(not c.radar.paused)
        u:show('tools');assert(not c.radar.paused)
        u.actions.stop:Click();assert(not c.radar.enabled)''')

    def test_live_progress_displays_shortlist_not_market_percent(self):
        self.run_lua('''c:radarStart();c:tick();c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        local p=ForeverFlip.Progress.state(c);assert(p.mode=='live' and not p.value)
        c:radarPause();p=ForeverFlip.Progress.state(c);assert(p.mode=='action')''')

    def test_hiding_native_tab_pauses_queries(self):
        from test_ui import ui_runtime
        ui_runtime().execute('''db.lastReplicate=now;u.actions.live:Click();u.frame:Hide()
        assert(c.radar.paused);now=now+100;c:tick();assert(calls==0)''')

    def test_limits_still_apply_and_current_rules_recheck_results(self):
        self.run_lua('''c:radarStart();c:tick();c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        db.settings.budget=0;assert(#ForeverFlip.Radar.list(c)==0)
        db.settings.budget=nil;db.groups={{name='blocked',items={[1]=true},rule={budget=0}}}
        assert(#ForeverFlip.Radar.list(c)==0 and spent==0)''')

    def test_partial_item_updates_do_not_pause_live(self):
        self.run_lua('''api.rows=function()return rows,true,'item'end
        c:radarStart();c:tick();c:event('ITEM_SEARCH_RESULTS_UPDATED',{itemID=1})
        c:event('ITEM_SEARCH_RESULTS_UPDATED',{itemID=1});assert(not c.radar.paused)''')

    def test_cache_bound_and_replication_error_backoff(self):
        self.run_lua('''c:radarStart()
        for i=1,2100 do c.radar.alerts[tostring(i)]={signature='old',at=now-10000-i}
        c.radar.opportunities[tostring(i)]={at=now-601}end
        c:tick();local n=0;for _ in pairs(c.radar.alerts)do n=n+1 end
        assert(n<=2000 and next(c.radar.opportunities)==nil)
        -- Isolate replication backoff: with candidates, exact checks may own the request slot.
        c:stop();c.candidates={};db.lastReplicate=nil;api.replicate=function()replicas=replicas+1;error('offline')end
        c:radarStart();c:tick();c:tick();assert(replicas==1)
        now=now+29;c:tick();assert(replicas==1);now=now+1;c:tick();assert(replicas==2)''')

    def test_reload_uses_recent_cached_discovery_during_replication_cooldown(self):
        self.run_lua('''c.candidates={}
        ForeverFlip.Store.observe(db,'scope','1:0:0:0',{at=now-10,price=100,qty=10,complete=true,rows=rows,family=false,source='replicate'})
        ForeverFlip.Store.observe(db,'other','2:0:0:0',{at=now-10,price=100,qty=10,complete=true,rows=rows,family=false,source='replicate'})
        c:radarStart();c:tick();assert(c.job and c.job.key.itemID==1 and replicas==0)
        assert(#ForeverFlip.Radar.list(c)==0)''')

    def test_pausing_replication_preserves_passive_snapshot_ingestion(self):
        self.run_lua('''db.lastReplicate=nil;c.candidates={};c:radarStart();c:tick()
        c:radarPause();assert(c.fullJob)
        api.replicateCount=function()return 1 end
        api.replicateRow=function()return {complete=true,key={itemID=1},qty=10,buyout=1000,family=false}end
        c:event('REPLICATE_ITEM_LIST_UPDATE');c:tick();assert(#c.candidates==1)
        c:radarStart();c:tick();assert(c.job and c.job.key.itemID==1 and replicas==1)''')

    def test_same_key_manual_handoff_waits_for_background_response(self):
        self.run_lua('''c:radarStart();c:tick();assert(c:search({itemID=1}))
        assert(c.reviewRequest and calls==1 and c.radar.paused)
        c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        assert(not c:fresh() and not c:requestBuy() and quoted==0)
        now=now+3;c:tick();assert(calls==2 and c.job.origin~='radar')
        c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1);assert(c:fresh())''')

    def test_each_resolved_family_variant_gets_its_own_candidate(self):
        self.run_lua('''ForeverFlip.Adapters.keyFromInput=function(link)
        if link=='uncached'then return nil end;return {itemID=1,itemLevel=tonumber(link)}end
        api.vendor=function()return 1000 end
        c.candidates={{key={itemID=1},family=true,at=now,scope='scope',rows={
        {qty=1,unit=100,cost=100,link='uncached'},{qty=1,unit=100,cost=100,link='10'},
        {qty=1,unit=100,cost=100,link='20'}}}}
        c:radarStart();c:tick();assert(#c.radar.queue==2)
        local seen={};for _,key in ipairs(c.radar.queue)do seen[key.itemLevel]=true end
        assert(seen[10]and seen[20])''')

    def test_pagination_waits_for_a_response_and_times_out(self):
        self.run_lua('''pages=0;api.more=function()pages=pages+1 end;full=false
        c:radarStart();c:tick();c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        for i=1,4 do now=now+3;c:tick()end
        assert(pages==1 and c.job)
        now=now+21;c:tick();assert(not c.job and alerts==0)''')

    def test_shortlist_build_is_incremental(self):
        self.run_lua('''c.candidates={};for i=1,2000 do
        c.candidates[i]={key={itemID=i},rows=rows,kind='commodity',family=false,at=now,scope='scope'}end
        c:radarStart();c:tick();assert(c.radar.build and c.radar.build.index<2000 and calls==0)
        c:radarPause();local index=c.radar.build.index;c:tick();assert(c.radar.build.index==index)
        c:radarStart();for i=1,600 do c:tick()end;assert(not c.radar.build and #c.radar.queue<=120 and calls==1)''')

    def test_completed_cache_update_invalidates_live_opportunity(self):
        self.run_lua('''c:radarStart();c:tick();c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        assert(#ForeverFlip.Radar.list(c)==1);rows={};c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        assert(#ForeverFlip.Radar.list(c)==0 and not c.radar.paused)''')

    def test_stop_clears_displayed_results(self):
        self.run_lua('''c:radarStart();c:tick();c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        c:stop();assert(#ForeverFlip.Radar.list(c)==0)''')

    def test_incremental_ranking_retains_only_bounded_best_plans(self):
        self.run_lua('''c.candidates={};for i=1,2000 do
        c.candidates[i]={key={itemID=i},rows=rows,kind='commodity',family=false,at=now,scope='scope'}end
        c:radarStart();for i=1,100 do c:tick()end
        assert(c.radar.build and #c.radar.build.promising<=160)''')

    def test_live_updates_do_not_rerank_entire_all_items_view_every_second(self):
        from test_ui import ui_runtime
        from test_domain import ROOT
        l=ui_runtime();l.execute((ROOT/'ForeverFlip/Core.lua').read_text(encoding='utf-8-sig'))
        l.execute('''ForeverFlip.boot('ForeverFlip');ForeverFlip.attach()
        local c=ForeverFlip.controller;c.api=api;c.db.lastReplicate=now
        c:radarStart();ForeverFlip.ui:show('deals');ForeverFlip.ui.liveOnly=false
        ForeverFlip.ui.refresh=function()error('No full-market ranking for live paint')end
        local f=ForeverFlip.eventFrame;f.scripts.OnUpdate(f,1.1)''')

    def test_found_deals_stay_listed_for_ten_minutes(self):
        self.run_lua('''db.lastReplicate=now;c.candidates={{key={itemID=1},rows=rows,kind='commodity',family=false,at=now,scope='scope'}}
        assert(c:radarStart());for _=1,20 do c:tick()end;c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        assert(#ForeverFlip.Radar.list(c)==1);c:radarPause(true)
        now=now+300;assert(#ForeverFlip.Radar.list(c)==1)
        now=now+301;assert(#ForeverFlip.Radar.list(c)==0)''')

    def test_repeated_result_events_keep_a_found_deal(self):
        self.run_lua('''db.lastReplicate=now;c.candidates={{key={itemID=1},rows=rows,kind='commodity',family=false,at=now,scope='scope'}}
        assert(c:radarStart());for _=1,20 do c:tick()end;c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        assert(#ForeverFlip.Radar.list(c)==1)
        c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1);c:event('COMMODITY_SEARCH_RESULTS_ADDED',1)
        assert(#ForeverFlip.Radar.list(c)==1)
        full=false;c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1);assert(#ForeverFlip.Radar.list(c)==1)''')

    def test_echo_event_keeps_the_manual_trade_plan(self):
        self.run_lua('''c:search({itemID=1});c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1);assert(c.plan)
        c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1);assert(c.plan)
        rows={{qty=3,unit=90,cost=270,auctionID=9}};c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1);assert(not c.plan)''')

    def test_opening_a_deal_keeps_a_scan_being_processed(self):
        self.run_lua('''db.lastReplicate=nil;api.replicate=function()end;api.replicateCount=function()return 5000 end
        api.replicateRow=function(i)return {id=1,key={itemID=1},qty=1,buyout=100,complete=true,family=false}end
        assert(c:fullScan());c:event('REPLICATE_ITEM_LIST_UPDATE');c:tick();assert(c.fullJob and not c.fullJob.waiting)
        assert(c:openDeal({key={itemID=2},mode='flip'}));assert(c.fullJob and c.job and c.job.key.itemID==2)
        for _=1,50 do c:tick()end;assert(not c.fullJob and #c.candidates>=1)''')

    def test_saved_scans_up_to_two_hours_restore_candidates(self):
        self.run_lua('''db.markets={scope={}};c.candidates={{key={itemID=99},rows=rows,at=now,scope='scope'}}
        for i=1,300 do db.markets.scope[i..':0:0:0']={latest={at=now-2880,rows={{qty=1,unit=100,cost=100}},family=false}}end
        db.markets.scope['999:0:0:0']={latest={at=now-8000,rows={{qty=1,unit=100,cost=100}}}}
        assert(c:restoreCandidates()==0);while c.restoreJob do c:advanceRestoreCandidates(25) end;assert(#c.candidates==300)
        for _,r in ipairs(c.candidates)do assert(r.key.itemID~=999)end
        assert(c:restoreCandidates()==0);while c.restoreJob do c:advanceRestoreCandidates(25) end;assert(#c.candidates==300)''')


if __name__ == '__main__': unittest.main()
