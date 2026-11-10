import unittest
from test_domain import runtime
from test_controller import controller_runtime
from test_ui import ui_runtime

FLIP = '''{mode='flip',wallet=40000,cashFloor=.2,maxWallet=.1,now=1000000,minROI=.25,minProfit=10000,
  maxShare=1,maxQty=10,sellPrice=2000,buyLimit=1500}'''


class EarningTests(unittest.TestCase):
    def test_small_wallet_gets_minimum_profit_scaled_to_usable_budget(self):
        runtime().execute('''local M=ForeverFlip.Market;local o=''' + FLIP + '''
        local fixed=M.plan({{qty=2,unit=1000,cost=2000}},{},o);assert(fixed.budget==4000 and fixed.minProfit==10000)
        o.adaptiveProfit=true;local p=M.plan({{qty=2,unit=1000,cost=2000}},{},o)
        assert(p.minProfit==200)
        o.wallet=100000000;local rich=M.plan({{qty=2,unit=1000,cost=2000}},{},o);assert(rich.minProfit==10000)''')

    def test_vendor_route_keeps_its_own_minimum(self):
        runtime().execute('''local p=ForeverFlip.Market.plan({{qty=1,unit=100,cost=100}},{},
        {mode='vendor',vendor=1000,wallet=40000,now=1000000,minROI=.25,minProfit=7,adaptiveProfit=true,maxShare=1})
        assert(p.minProfit==7 and p.canBuy)''')

    def test_group_minimum_is_not_adapted(self):
        controller_runtime().execute('''assert(c:rule({itemID=1}).adaptiveProfit==true)
        db.groups={{name='G',items={[1]=true},rule={minProfit=20000}}}
        assert(c:rule({itemID=1}).adaptiveProfit==false)
        db.settings.adaptiveProfit=false;db.groups={};assert(c:rule({itemID=1}).adaptiveProfit==false)''')

    def test_sale_price_undercuts_but_never_below_cost(self):
        runtime().execute('''local M=ForeverFlip.Market
        local p={minimum=1000,avgBuy=500,feeRate=.05,reserveRate=.02}
        local v,why=M.salePrice(p);assert(v==900 and why=='undercut')
        p.avgBuy=990;v,why=M.salePrice(p);assert(v==1100 and why=='cost')
        v=M.salePrice({minimum=150});assert(v==100)
        v,why=M.salePrice({target=800,feeRate=.05});assert(v==800 and why=='market')
        assert(M.salePrice(nil)==nil and M.salePrice({})==nil)''')

    def test_suggest_price_button_fills_the_post_field_only(self):
        ui_runtime().execute('''u:show('trade');c.plan={minimum=2500,feeRate=.05,reserveRate=.02}
        u.actions.suggestPrice:Click();assert(u.fields.postPrice:GetText()=='0.2400' and spent==0)
        c.plan=nil;u.fields.postPrice:SetText('');u.actions.suggestPrice:Click()
        assert(u.fields.postPrice:GetText()=='')''')

    def test_vendor_budget_grows_with_wallet_and_resets_daily(self):
        controller_runtime().execute('''api.wallet=function()return 1000000 end;assert(c:easyNPC())
        assert(c:npcRemaining()==250000)
        db.ledger[1]={kind='buy',owner='owner',scope='scope',key='1:0:0:0',qty=1,total=200000,at=now}
        assert(c:npcRemaining()==50000)
        now=now+86401;assert(c:npcRemaining()==250000)
        api.wallet=function()return 1000 end;assert(c:npcRemaining()==10000)''')

    def test_auto_scan_starts_only_when_idle_and_cooldown_passed(self):
        controller_runtime().execute('''db.lastReplicate=now;assert(not c:autoScanDue())
        now=now+905;assert(c:autoScanDue())
        db.settings.autoScan=false;assert(not c:autoScanDue());db.settings.autoScan=nil
        c:search({itemID=1});assert(not c:autoScanDue())''')

    def test_settings_toggle_and_simple_layout(self):
        ui_runtime().execute('''u:show('settings');u:layout()
        assert(u.actions.autoScan:GetParent()==u.sections.settings.split.pages.main and u.sections.settings.split.pages.main:IsShown())
        u.actions.autoScan:Click();assert(db.settings.autoScan==false)
        u.actions.autoScan:Click();assert(db.settings.autoScan==nil)''')

    def test_resale_without_history_is_priced_from_current_listings(self):
        runtime().execute('''local M=ForeverFlip.Market
        local rows={{qty=2,unit=100,cost=200},{qty=10,unit=300,cost=3000},{qty=10,unit=320,cost=3200}}
        assert(M.ladder(rows)==200)
        local p=M.plan(rows,{},{mode='flip',wallet=20000,cashFloor=.2,maxWallet=.1,now=1000000,minROI=.25,
          minProfit=10000,adaptiveProfit=true,maxShare=1,maxQty=10})
        assert(p.basis=='listings' and p.target==200 and p.qty==2 and p.cost==200 and p.canBuy)
        assert(p.profit>0 and p.confidence>.25 and p.confidence<.5 and p.listings==3 and p.reference==300)
        local fair=M.plan({{qty=5,unit=280,cost=1400},{qty=10,unit=300,cost=3000},{qty=10,unit=320,cost=3200}},{},
          {mode='flip',wallet=1000000,now=1000000,minROI=.25,minProfit=0,maxShare=1,maxQty=10})
        assert(not fair.canBuy)
        assert(M.ladder({{qty=1,unit=100,cost=100},{qty=1,unit=500,cost=500}})==nil)
        local off=M.plan(rows,{},{mode='flip',ladder=false,wallet=1000000,now=1000000,minROI=.25,minProfit=0,maxShare=1})
        assert(off.basis==nil and not off.canBuy)''')

    def test_live_search_resumes_after_a_check_but_not_after_user_pause(self):
        controller_runtime().execute('''db.lastReplicate=now;assert(c:radarStart())
        c:radarPause();assert(c:radarShouldResume('deals') and not c:radarShouldResume('trade'))
        c:search({itemID=1});assert(not c:radarShouldResume('deals'))
        c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1);assert(c:radarShouldResume('portfolio'))
        c:radarPause(true);assert(not c:radarShouldResume('deals'))
        assert(c:radarStart() and not c.radar.userPaused)''')

    def test_live_entry_leaves_vendor_only_mode_and_checks_all_deals(self):
        ui_runtime().execute('''db.lastReplicate=now;u:show('deals')
        u:startNPC();assert(c.smallNPCActive and u.filterMode=='vendor')
        u.shopping.listRows[2]:Click()
        assert(not c.smallNPCActive and u.filterMode=='all' and u.liveOnly and c.radar.enabled and not c.radar.paused)
        assert(u.shopping.listRows[2].selected:IsShown() and not u.shopping.listRows[1].selected:IsShown())
        assert(spent==0)''')

    def test_listing_exit_undercuts_the_next_competitor(self):
        runtime().execute('''local M=ForeverFlip.Market
        local rows={{qty=1,unit=100,cost=100},{qty=2,unit=250,cost=500},{qty=10,unit=300,cost=3000},{qty=10,unit=320,cost=3200}}
        local exit,count,fair=M.ladder(rows);assert(fair==300 and count==4 and exit==200)
        local busy={{qty=1,unit=100,cost=100}};for i=1,25 do busy[#busy+1]={qty=1,unit=300,cost=300}end
        local o={mode='flip',wallet=40000,cashFloor=.2,maxWallet=.1,now=1000000,minROI=.25,minProfit=0,maxShare=1,maxQty=10}
        local thin=M.plan({{qty=1,unit=100,cost=100},{qty=3,unit=300,cost=900},{qty=3,unit=300,cost=900}},{},o)
        local deep=M.plan(busy,{},o);assert(deep.canBuy and thin.canBuy and deep.confidence>thin.confidence)''')

    def test_real_market_cracked_egg_shells_is_not_a_deal(self):
        runtime().execute('''local M=ForeverFlip.Market;local s=100
        local rows={}
        for _,v in ipairs({{28,4*s},{1,4.5*s},{2,10*s},{2,16*s},{1,17*s},{1,19*s},{3,20*s},{2,40*s},{3,48*s},
          {3,70*s},{3,77*s},{6,78*s},{1,79*s},{1,85*s},{3,99*s},{3,100*s}})do
          rows[#rows+1]={qty=v[1],unit=v[2],cost=v[1]*v[2]}end
        local market=M.marketValue(rows);assert(market==400)
        local p=M.plan(rows,{},{mode='flip',wallet=40000,cashFloor=.2,maxWallet=.1,now=1000000,minROI=.25,
          minProfit=0,adaptiveProfit=true,maxShare=1,maxQty=100})
        assert(not p.canBuy and p.qty==0)''')


if __name__ == '__main__':
    unittest.main()
