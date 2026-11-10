import unittest
from test_ui import ui_runtime
from test_controller import controller_runtime


class TabWorkflowTests(unittest.TestCase):
    def test_craft_does_not_overwrite_native_shopping_and_all_tabs_remain_usable(self):
        ui_runtime().execute('''local shopping=u.shopping
        u.fields.materials:SetText('1*3@0.01');u.fields.outputQty:SetText('2');u.fields.outputPrice:SetText('1')
        u.actions.craftCalc:Click();assert(u.shopping==shopping and u.materialShopping)
        for _,id in ipairs({'deals','workbench','trade','watch','portfolio','history','tools','settings','overview'})do
        u:show(id);u:layout();u:refresh()end;assert(u.shopping.left)''')

    def test_material_purchase_uses_deferred_selection_and_preview(self):
        ui_runtime().execute('''u.fields.materials:SetText('1*3@0.01');u.fields.outputPrice:SetText('1')
        u.actions.craftCalc:Click();api.ready=function()return false end
        u.actions.materialSearch:Click();assert(u.section=='trade' and c.selection and c.reviewRequest)
        assert(c.overrides.maxQty==3 and spent==0)''')

    def test_plan_route_waits_for_throttle_and_previews_correct_item(self):
        ui_runtime().execute('''u.allocation={lines={{key={itemID=1},cost=1000,qty=10,mode='vendor'}}}
        api.ready=function()return false end;u.actions.planRoute:Click()
        assert(c.selection and c.selection.key.itemID==1 and c.reviewRequest and u.section=='trade')''')

    def test_portfolio_price_never_borrows_base_price_for_variant(self):
        controller_runtime().execute('''db.markets.scope={['1:0:0:0']={latest={at=now,price=900}},
        ['1:43:7:0']={latest={at=now,price=1234}}}
        assert(c:price({itemID=1,itemLevel=43,itemSuffix=7})==1234)
        assert(c:price({itemID=1,itemLevel=44,itemSuffix=7})==nil)''')

    def test_portfolio_paging_reaches_all_owned_entries(self):
        ui_runtime().execute('''for i=1,15 do ForeverFlip.Ledger.append(db,{kind='buy',owner='owner',scope='scope',
        key=i..':0:0:0',qty=1,total=i,at=now-i})end
        u:show('portfolio');assert(u.actions.portfolioNext:IsEnabled())
        u.actions.portfolioNext:Click();assert(u.portfolioPage==2 and u.portfolioText:GetText():find('9:0:0:0',1,true))
        u.actions.portfolioNext:Click();assert(u.portfolioPage==3 and not u.actions.portfolioNext:IsEnabled())
        u.actions.portfolioPrevious:Click();assert(u.portfolioPage==2)''')

    def test_shared_npc_plan_cannot_exceed_remaining_trial_budget(self):
        controller_runtime().execute('''api.wallet=function()return 40000 end;c:easyNPC();local candidates={}
        for i=1,3 do candidates[i]={key={itemID=i},rows={{qty=10,unit=400,cost=4000}},
        at=now,scope='scope',family=false,kind='commodity'}end;c.candidates=candidates
        local p=c:allocate({budget=100000,riskCap=100000,drop=.2});assert(p.budget<=10000 and p.cost<=10000)''')

    def test_material_buy_is_bounded_procurement_not_fake_resale_profit(self):
        ui_runtime().execute('''u.fields.materials:SetText('1*3@0.01');u.fields.outputPrice:SetText('1')
        u.actions.craftCalc:Click();u.actions.materialSearch:Click();c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        assert(c.plan.mode=='material' and c.plan.canBuy and c.plan.qty==3 and c.plan.cost==300)
        assert(c.plan.profit==0 and not c.plan.target)
        assert(c:requestBuy());c:event('COMMODITY_PRICE_UPDATED',100,300);assert(c:confirmBuy())
        c:event('COMMODITY_PURCHASED',1,3);now=now+3
        c:searchInput('1');c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1);assert(not c.plan.canBuy)''')

    def test_material_mode_without_explicit_request_cannot_buy(self):
        controller_runtime().execute('''c.mode='material';c:search({itemID=1});c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        assert(not c.plan.canBuy and not c:requestBuy() and quoted==0)''')

    def test_large_planner_runs_between_frames_and_matches_synchronous_math(self):
        controller_runtime().execute('''local P=ForeverFlip.Planner;assert(P)
        c.candidates={};for i=1,2000 do c.candidates[i]={key={itemID=i},rows=rows,kind='commodity',family=false,scope='scope',at=now}end
        local n=0;local model=ForeverFlip.Market.plan;ForeverFlip.Market.plan=function(...)n=n+1;return model(...)end
        local actual;assert(P.start(c,'balanced',nil,function(r)actual=r end));assert(n==0)
        P.tick(c);assert(n<=32 and not c.cachedSummary and not c.salesByKey)
        for i=1,10000 do if not c.planning then break end;P.tick(c)end
        assert(actual and not actual.error and not c.planning)
        local expected=c:recommend('balanced');assert(actual.cost==expected.cost and actual.profit==expected.profit and actual.loss==expected.loss)
        assert(spent==0)''')

    def test_planner_cancels_on_financial_change_and_stop(self):
        controller_runtime().execute('''local P=ForeverFlip.Planner;local result
        c.candidates={};for i=1,20 do c.candidates[i]={key={itemID=i},rows=rows,kind='commodity',family=false,scope='scope',at=now}end
        P.start(c,'balanced',nil,function(r)result=r end);P.tick(c)
        api.wallet=function()return 0 end;P.tick(c);assert(not c.planning and not result and spent==0)
        api.wallet=function()return 100000 end;P.start(c,'balanced');c:stop();assert(not c.planning)''')

    def test_large_planner_button_does_not_block_and_routes_result(self):
        ui_runtime().execute('''c.candidates={};for i=1,100 do c.candidates[i]={key={itemID=i},rows=rows,kind='commodity',family=false,scope='scope',at=now}end
        u.actions.easyBuild:Click();assert(c.planning and u.section=='workbench' and not u.allocation)
        for i=1,10000 do if not c.planning then break end;ForeverFlip.Planner.tick(c)end
        assert(u.allocation and #u.allocation.lines>0);u.actions.adviceRow1:Click()
        assert(u.section=='trade' and c.selection and spent==0)''')

    def test_material_confirmation_rechecks_total_cap_even_with_group_budget(self):
        ui_runtime().execute('''db.groups={{name='materials',items={[1]=true},rule={budget=100000}}}
        u.fields.materials:SetText('1*100@0.01');u.fields.outputPrice:SetText('1');u.actions.craftCalc:Click()
        u.actions.materialSearch:Click();c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        assert(c:requestBuy());c:event('COMMODITY_PRICE_UPDATED',100,1000)
        ForeverFlip.Ledger.append(db,{kind='buy',owner='owner',scope='scope',key='1:0:0:0',qty=1,total=9900,at=now})
        assert(not c:confirmBuy() and spent==0)''')

    def test_portfolio_navigation_selects_visible_pending_and_mail_indexes(self):
        ui_runtime().execute('''for i=1,7 do
        db.pending[tostring(i)]={uid=tostring(i),owner='owner',scope='scope',status='unknown',at=i,key='1:0:0:0',qty=1,total=1}
        c.mail[i]={kind='seller',name='item',qty=1,amount=1}end
        u:show('portfolio');u.actions.portfolioNext:Click()
        assert(u.fields.pendingIndex:GetText()=='4' and u.fields.mailIndex:GetText()=='5')''')

    def test_portfolio_sale_hint_uses_actual_group_fee_and_reserve(self):
        ui_runtime().execute('''GetLocale=function()return 'enUS'end;db.settings.fee=.30;db.settings.reserve=0
        db.markets.scope={['1:0:0:0']={latest={price=100,at=now}}}
        ForeverFlip.Ledger.append(db,{kind='buy',owner='owner',scope='scope',key='1:0:0:0',qty=1,total=80,at=now})
        u:show('portfolio');assert(not u.portfolioText:GetText():find('review sale',1,true))''')

    def test_material_bids_cannot_bypass_procurement_price_authorization(self):
        ui_runtime().execute('''local samples={};for i=1,6 do samples[i]={at=now-(i-1)*86400,price=1000,qty=1,complete=true}end
        db.markets.scope={['1:0:0:0']={samples=samples,days={}}}
        api.rows=function()return {{qty=1,unit=1000,cost=1000,auctionID=7}},true,'item',
        {{auctionID=7,quantity=1,minBid=250,buyoutAmount=1000}}end
        u.fields.materials:SetText('1*3@0.01');u.fields.outputPrice:SetText('1');u.actions.craftCalc:Click()
        u.actions.materialSearch:Click();c:event('ITEM_SEARCH_RESULTS_UPDATED',{itemID=1});c:bid(1)
        assert(spent==0)''')

    def test_reopening_same_material_row_preserves_consumed_quantity(self):
        ui_runtime().execute('''u.fields.materials:SetText('1*3@0.01');u.fields.outputPrice:SetText('1');u.actions.craftCalc:Click()
        u.actions.materialSearch:Click();c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1);c:requestBuy()
        c:event('COMMODITY_PRICE_UPDATED',100,300);c:confirmBuy();c:event('COMMODITY_PURCHASED',1,3)
        now=now+3;u:show('tools');u.actions.materialSearch:Click();c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        assert(not c.plan.canBuy and c.materialRequest.first==0)''')

    def test_second_material_does_not_inherit_previous_derived_row_caps(self):
        ui_runtime().execute('''u.fields.materials:SetText('1*1@0.01,2*10@0.03');u.fields.outputPrice:SetText('1');u.actions.craftCalc:Click()
        u.actions.materialSearch:Click();c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1);now=now+3
        u:show('tools');u.fields.materialIndex:SetText('2');u.actions.materialSearch:Click()
        assert(c.overrides.maxQty==10 and c.overrides.budget==3000 and c.materialRequest.itemID==2)''')

    def test_foreign_allocation_cannot_be_displayed_or_routed(self):
        ui_runtime().execute('''u.allocation={owner='other',scope='foreign',budget=1000,cost=100,profit=900,stressed=0,
        lines={{key={itemID=1},mode='vendor',qty=1,cost=100}}}
        u:show('workbench');u.actions.planRoute:Click();assert(not u.allocation and not c.job and spent==0)''')

    def test_all_reagent_rows_are_accessible_in_tool_result(self):
        ui_runtime().execute('''GetLocale=function()return 'enUS'end
        u.fields.materials:SetText('1*1@0.01,2*1@0.01,3*1@0.01,4*1@0.01,5*1@0.01,6*1@0.01')
        u.fields.outputPrice:SetText('1');u.actions.craftCalc:Click()
        assert(u.toolText:GetText():find('6. Item 6',1,true))''')


if __name__=='__main__':unittest.main()
