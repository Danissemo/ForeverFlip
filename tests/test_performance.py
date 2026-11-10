import unittest
from test_ui import ui_runtime
from test_controller import controller_runtime


class PerformanceTests(unittest.TestCase):
    def large_ui(self):
        l=ui_runtime()
        l.execute('''c.candidates={};local book={};for i=1,64 do book[i]={qty=1,unit=100+i,cost=100+i}end
        for i=1,2000 do c.candidates[i]={key={itemID=i},rows=book,kind='commodity',family=false,scope='scope',at=now}end
        plans=0;metas=0;local p=ForeverFlip.Market.plan
        ForeverFlip.Market.plan=function(...)plans=plans+1;return p(...)end
        local m=ForeverFlip.ItemDisplay.metadata
        ForeverFlip.ItemDisplay.metadata=function(...)metas=metas+1;return m(...)end''')
        return l

    def test_page_entry_does_not_rank_market_or_load_hidden_item_metadata(self):
        self.large_ui().execute('''u:show('deals');assert(plans==0 and metas==0)
        assert(c.dealCache and c.dealCache.job and ForeverFlip.Progress.state(c).mode=='processing')''')

    def test_incremental_rank_reuses_results_across_navigation_and_refreshes(self):
        self.large_ui().execute('''local D=ForeverFlip.DealCache;u:show('deals');D.tick(c)
        assert(plans<=8 and c.dealCache.job.index<=5)
        for i=1,2500 do D.tick(c)end;u:refresh();assert(#u.visibleDeals==2000 and metas<=20)
        local before=plans;u:refresh();u:show('overview');u:show('deals');assert(plans==before)''')

    def test_cache_invalidates_financial_and_market_inputs_and_cannot_trade(self):
        controller_runtime().execute('''local D=ForeverFlip.DealCache
        c.candidates={{key={itemID=1},rows=rows,kind='commodity',family=false,scope='scope',at=now}}
        local a=D.get(c);assert(#a==1 and a[1].canBuy and not c:fresh())
        db.settings.budget=0;c:invalidate();assert(not D.get(c)[1].canBuy)
        db.settings.budget=nil;c:invalidate();api.wallet=function()return 0 end
        assert(not D.get(c)[1].canBuy)
        api.scope=function()return 'other'end;assert(#D.get(c)==0 and spent==0)''')

    def test_incremental_ranks_match_existing_domain_results(self):
        self.large_ui().execute('''local D=ForeverFlip.DealCache;D.get(c)
        for i=1,2500 do D.tick(c)end
        local cached=D.get(c);local expected=c:rank();assert(#cached==#expected)
        for i,p in ipairs(expected)do local a=cached[i]
        assert(ForeverFlip.Util.key(a.key)==ForeverFlip.Util.key(p.key))
        assert(a.cost==p.cost and a.profit==p.profit and a.canBuy==p.canBuy and a.score==p.score)end''')

    def test_summary_cache_replays_only_after_mutations_or_scope_change(self):
        controller_runtime().execute('''local n=0;local original=ForeverFlip.Ledger.summary
        ForeverFlip.Ledger.summary=function(...)n=n+1;return original(...)end
        c:summary();c:summary();assert(n==1)
        db.ledger[1]={kind='buy',qty=1,total=50,key='1:0:0:0',owner='owner',scope='scope',at=now}
        assert(c:summary().stock==50 and n==2)
        api.owner=function()return 'other'end;assert(c:summary().stock==0 and n==3)''')

    def test_metadata_cache_is_variant_specific_and_invalidated_by_item_event(self):
        ui_runtime().execute('''local D=ForeverFlip.ItemDisplay;local calls=0
        GetItemInfo=function()calls=calls+1;return 'Old',nil,1,1,1,nil,nil,20,nil,123 end
        D.metadata({itemID=888});D.metadata({itemID=888});assert(calls==1)
        D.metadata({itemID=888,itemSuffix=7});assert(calls==2)
        D.invalidate(888);D.metadata({itemID=888});assert(calls==3)''')

    def test_unrelated_item_events_do_not_refresh_auction_ui(self):
        from test_domain import ROOT
        l=ui_runtime();l.execute((ROOT/'ForeverFlip/Core.lua').read_text(encoding='utf-8-sig'))
        l.execute('''ForeverFlip.boot('ForeverFlip');ForeverFlip.attach();local count=0
        ForeverFlip.ui.refresh=function()count=count+1 end;local f=ForeverFlip.eventFrame
        f.scripts.OnEvent(f,'GET_ITEM_INFO_RECEIVED',99999,true);f.scripts.OnUpdate(f,1)
        assert(count==0)''')

    def test_incremental_build_does_not_starve_on_live_candidate_revisions(self):
        self.large_ui().execute('''local D=ForeverFlip.DealCache;D.get(c)
        for i=1,700 do c.candidateVersion=i;D.get(c);D.tick(c)end
        assert(#D.get(c)==2000)''')

    def test_sort_ties_do_not_reparse_item_keys_in_every_comparison(self):
        self.large_ui().execute('''local D=ForeverFlip.DealCache;D.get(c)
        for i=1,2500 do D.tick(c)end;u:refresh()
        local keys=0;local key=ForeverFlip.Util.key
        ForeverFlip.Util.key=function(...)keys=keys+1;return key(...)end
        u:refresh();assert(keys<=80)''')

    def test_core_checks_idle_cache_freshness_while_radar_runs(self):
        from test_domain import ROOT
        l=ui_runtime();l.execute((ROOT/'ForeverFlip/Core.lua').read_text(encoding='utf-8-sig'))
        l.execute('''ForeverFlip.boot('ForeverFlip');ForeverFlip.attach()
        local c=ForeverFlip.controller;c.api=api;c.db.lastReplicate=now
        c.candidates={{key={itemID=1},rows=rows,kind='commodity',family=false,scope='scope',at=now}}
        c:radarStart();ForeverFlip.ui:show('deals');assert(#ForeverFlip.ui.visibleDeals==1)
        c.candidates={};c.candidateVersion=1
        local f=ForeverFlip.eventFrame;f.scripts.OnUpdate(f,1.1)
        assert(#ForeverFlip.ui.visibleDeals==0)''')

    def test_inflight_revision_is_not_claimed_as_covered_and_eviction_cannot_skip(self):
        controller_runtime().execute('''local D=ForeverFlip.DealCache;c.candidates={}
        for i=1,6 do c.candidates[i]={key={itemID=i},rows=rows,kind='commodity',scope='scope',at=now}end
        D.get(c);D.tick(c);table.remove(c.candidates,1)
        c.candidates[6]={key={itemID=7},rows=rows,kind='commodity',scope='scope',at=now};c.candidateVersion=1
        D.tick(c);assert(c.dealCache.inputs.revision==0)
        D.get(c);for i=1,5 do D.tick(c)end
        local seen={};for _,p in ipairs(D.get(c))do seen[p.key.itemID]=true end
        assert(not seen[1]and seen[5]and seen[7])''')

    def test_previous_rows_stay_visible_while_a_new_pass_runs(self):
        controller_runtime().execute('''local D=ForeverFlip.DealCache;c.candidates={}
        for i=1,6 do c.candidates[i]={key={itemID=i},rows=rows,kind='commodity',scope='scope',at=now}end
        D.get(c);for i=1,3 do D.tick(c)end;assert(#D.get(c)==6)
        c.candidateVersion=1;D.get(c);assert(c.dealCache.job)
        now=now+100;assert(#D.get(c)==6 and c.dealCache.job)
        for i=1,10 do D.tick(c)end;assert(not c.dealCache.job and #D.get(c)==6)''')

    def test_cold_commodity_filter_uses_auction_name_without_bulk_loads(self):
        ui_runtime().execute('''C_Item={IsItemDataCachedByID=function()return false end,
        GetItemInfo=function()return nil end,RequestLoadItemDataByID=function()error('No bulk load')end}
        C_AuctionHouse={GetItemKeyInfo=function()return {itemName='Copper Ore'}end}
        assert(ForeverFlip.ItemDisplay.name({itemID=2770})=='Copper Ore')''')

    def test_preparation_progress_does_not_claim_work_on_other_sections(self):
        self.large_ui().execute('''u:show('deals');assert(ForeverFlip.Progress.state(c).mode=='processing')
        u:show('tools');assert(ForeverFlip.Progress.state(c).mode~='processing')''')

    def test_cached_name_rejects_link_for_another_item(self):
        ui_runtime().execute('''assert(ForeverFlip.ItemDisplay.name({itemID=123},'|Hitem:999:0|h[Wrong item]|h')=='Item 123')''')


if __name__=='__main__': unittest.main()
