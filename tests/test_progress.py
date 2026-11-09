import unittest
from test_controller import controller_runtime
from test_ui import ui_runtime


class ProgressTests(unittest.TestCase):
    def test_full_scan_wait_is_indeterminate_then_real_count_and_completion(self):
        controller_runtime().execute('''local P=ForeverFlip.Progress;assert(P)
        api.replicate=function()end;api.replicateCount=function()return 1000 end
        api.replicateRow=function()return nil end
        assert(c:fullScan());local s=P.state(c);assert(s.mode=='waiting' and s.value==nil)
        c:event('REPLICATE_ITEM_LIST_UPDATE');c:tick();s=P.state(c)
        assert(s.mode=='processing' and s.done==220 and s.total==1000 and s.value==.22)
        for i=1,10 do c:tick()end;s=P.state(c);assert(s.mode=='done' and s.value==1)''')
    def test_timeout_and_stop_stop_waiting_animation(self):
        controller_runtime().execute('''local P=ForeverFlip.Progress;api.replicate=function()end
        c:fullScan();now=now+36;c:tick();assert(P.state(c).mode=='error')
        now=now+1000;c:fullScan();c:stop();assert(P.state(c).mode=='stopped')''')
    def test_search_quote_and_receipt_show_real_stage_without_automatic_spending(self):
        controller_runtime().execute('''local P=ForeverFlip.Progress
        c:search({itemID=1});assert(P.state(c).mode=='waiting')
        c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1);assert(P.state(c).mode=='done')
        c:requestBuy();assert(P.state(c).mode=='waiting' and spent==0)
        c:event('COMMODITY_PRICE_UPDATED',100,1000);assert(P.state(c).mode=='action' and spent==0)
        c:confirmBuy();assert(P.state(c).mode=='waiting' and spent==1)
        c:event('COMMODITY_PURCHASED',1,10);assert(P.state(c).mode=='done')''')
    def test_unknown_purchase_requires_reconciliation_even_without_active_operation(self):
        controller_runtime().execute('''db.pending.x={owner='owner',scope='scope',status='unknown',total=100}
        assert(ForeverFlip.Progress.state(c).mode=='error')''')
    def test_partial_search_does_not_claim_finished(self):
        controller_runtime().execute('''c:search({itemID=1});full=false;c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        local s=ForeverFlip.Progress.state(c);assert(s.mode=='action' and s.value==nil)
        api.more=function()end;assert(c:more() and ForeverFlip.Progress.state(c).mode=='waiting')''')
    def test_footer_exists_on_every_section_and_updates_without_ranking(self):
        ui_runtime().execute('''assert(u.progressUI and u.progressUI.bar.kind=='StatusBar')
        for name in pairs(u.sections)do u:show(name);u:updateProgress(.1);assert(u.progressUI.bar:IsShown())end
        c.fullJob={waiting=false,index=50,total=100,at=now,scope='scope'}
        c.rank=function()error('must not rerank during progress paint')end
        u:updateProgress(.1);assert(u.progressUI.state.value==.5)''')
    def test_dense_native_rows_and_coins_keep_tooltip_links(self):
        ui_runtime().execute('''u:show('deals');u:layout()
        assert(u.dealRows[1]:GetHeight()==20 and u.dealRows[2]:GetHeight()==20)
        assert(u.dealRows[1].background and u.dealRows[2].background)
        assert(u.progressUI.bar:GetWidth()<=u.canvas:GetWidth())''')
    def test_item_level_and_native_coin_strings_come_from_game_data(self):
        ui_runtime().execute('''local link='|Hitem:123:0:0:0:0:0:7:0|h[Helm]|h'
        GetItemInfo=function()return 'Helm',link,2,11,1,nil,nil,1,nil,1000 end
        GetMoneyString=function(amount)return 'coins:'..amount end
        local row=u.dealRows[1];row:SetItem({key={itemID=123,itemSuffix=7},link=link,qty=1,cost=100,profit=20})
        assert(row.itemName:GetText()=='Helm (11)' and row.price:GetText()=='coins:100')
        assert(row.metadata.link==link and spent==0)''')
    def test_unavailable_scan_shows_failure_instead_of_idle_ready(self):
        controller_runtime().execute('''api.ready=function()return false end
        assert(not c:fullScan() and c.message=='throttled' and ForeverFlip.Progress.state(c).mode=='error')''')
    def test_core_tick_updates_full_scan_bar_without_whole_screen_refresh(self):
        from test_domain import ROOT
        l=ui_runtime();l.execute((ROOT/'ForeverFlip/Core.lua').read_text(encoding='utf-8-sig'))
        l.execute('''ForeverFlip.boot('ForeverFlip');ForeverFlip.attach();ForeverFlip.ui.frame:Show()
        local c=ForeverFlip.controller;c.fullJob={waiting=false,at=c.api.clock(),scope=c.api.scope(),
            total=1000,index=0,groups={},groupsCount=0,skipped=0}
        ForeverFlip.ui.refresh=function()error('No full refresh for each processed batch')end
        local f=ForeverFlip.eventFrame;f.scripts.OnUpdate(f,.06)
        assert(ForeverFlip.ui.progressUI.state.done==220 and ForeverFlip.ui.progressUI.state.total==1000)''')

if __name__=='__main__':unittest.main()
