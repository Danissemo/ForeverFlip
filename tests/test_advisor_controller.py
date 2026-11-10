import unittest
from test_controller import controller_runtime


class AdvisorControllerTests(unittest.TestCase):
    def test_activity_is_owner_scope_and_void_aware(self):
        controller_runtime().execute('''local L=ForeverFlip.Ledger
        L.append(db,{uid='a',kind='buy',owner='owner',scope='scope',key='1:0:0:0',qty=5,total=500,at=now-864000})
        L.append(db,{uid='b',kind='buy',owner='other',scope='foreign',key='1:0:0:0',qty=5,total=500,at=1})
        L.append(db,{kind='vendor',owner='owner',scope='scope',key='1:0:0:0',qty=1,total=100,at=now})
        local s=c:summary();assert(s.activity['1:0:0:0'].since==now-864000 and s.salesHistory[1].kind=='vendor')
        L.correct(db,'a','owner',now);assert(not c:summary().activity['1:0:0:0'])''')
    def test_cold_probe_is_one_and_survives_exact_search(self):
        # One cheap unit: buying it clears every lot below the exit price.
        controller_runtime().execute('''c.advisorProfile='balanced';c.mode='flip';rows={{qty=1,unit=100,cost=100}}
        local h={};for i=1,12 do h[i]={at=now-i*15000,price=1000,token=i,complete=true}end
        db.markets.scope={['1:0:0:0']={samples=h,days={},flow={hours=10,sold={50,50,50,50},pairs=5,at=now,market=1000}}}
        assert(c:search({itemID=1}));c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        assert(c.plan.advice and c.plan.qty==1 and c.plan.target<=1000)''')
    def test_valid_probe_quote_can_still_confirm(self):
        controller_runtime().execute('''c.advisorProfile='balanced';c.mode='flip'
        rows={{qty=1,unit=100,cost=100}}
        local h={};for i=1,12 do h[i]={at=now-i*15000,price=1000,token=i,complete=true}end
        db.markets.scope={['1:0:0:0']={samples=h,days={},flow={hours=10,sold={50,50,50,50},pairs=5,at=now,market=1000}}}
        c:search({itemID=1});c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        assert(c.plan.qty==1 and c:requestBuy());c:event('COMMODITY_PRICE_UPDATED',100,100)
        assert(c:confirmBuy() and spent==1)''')
    def test_assistant_does_not_bypass_bad_formula_or_user_limits(self):
        controller_runtime().execute('''c.advisorProfile='balanced';c.mode='flip'
        db.settings.maxQty=1;db.settings.budget=25;db.settings.sellFormula='missing'
        c:search({itemID=1});c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        assert(not c.plan.canBuy and c.plan.cost<=25 and c.plan.qty<=1)''')
    def test_vendor_not_limited_by_auction_probe(self):
        controller_runtime().execute('''c.advisorProfile='safe';c:search({itemID=1});c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        assert(c.plan.mode=='vendor' and c.plan.qty==10 and not c.plan.advice)''')
    def test_recommend_uses_free_wallet_and_no_trade_calls(self):
        controller_runtime().execute('''c.candidates={{key={itemID=1},rows=rows,at=now,scope='scope',family=false,kind='commodity'}}
        local p=c:recommend('balanced');assert(#p.lines==1 and p.cost<=p.budget and spent==0 and quoted==0)
        db.pending.x={owner='owner',scope='scope',total=100000,status='unknown'}
        assert(c:recommend('balanced').cost==0)''')
    def test_profile_switch_invalidates_previously_quoted_plan(self):
        controller_runtime().execute('''c:search({itemID=1});c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1);c:requestBuy()
        c:event('COMMODITY_PRICE_UPDATED',100,1000)
        local p=c:recommend('safe');assert(not c.plan and not c.active and not c:confirmBuy() and spent==0)''')
    def test_recommend_during_scan_keeps_scan_and_profile(self):
        controller_runtime().execute('''c:search({itemID=1});local p=c:recommend('safe')
        assert(p.error=='busy' and c.job and not c.advisorProfile)''')
    def test_unresolved_same_item_purchase_counts_against_probe(self):
        controller_runtime().execute('''c.advisorProfile='balanced'
        db.pending.x={owner='owner',scope='scope',key='1:0:0:0',total=100,qty=1,status='unknown'}
        local o=c:options({itemID=1},'flip');assert(o.advice.maxQty==0)''')
    def test_group_quote_revalidation_keeps_fresh_advisor_budget(self):
        controller_runtime().execute('''c.advisorProfile='balanced';c.mode='flip'
        db.groups={{name='g',items={[1]=true},rule={budget=100000}}}
        local h={};for i=1,12 do h[i]={at=now-i*15000,price=10000,token=i,complete=true}end
        db.markets.scope={['1:0:0:0']={samples=h,days={},flow={hours=10,sold={50,50,50,50},pairs=5,at=now,market=10000}}}
        rows={{qty=1,unit=2900,cost=2900}};c:search({itemID=1});c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        assert(c:requestBuy());c:event('COMMODITY_PRICE_UPDATED',2900,2900)
        api.wallet=function()return 90000 end
        assert(c:options({itemID=1},'flip').advice.maxBudget==2700)
        assert(not c:confirmBuy() and spent==0)''')

if __name__=='__main__':unittest.main()
