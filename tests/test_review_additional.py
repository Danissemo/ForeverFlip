import unittest
from test_domain import runtime, ROOT
from test_controller import controller_runtime
from test_ui import ui_runtime

class AdditionalReviewTests(unittest.TestCase):
    def test_wallet_change_rechecks_rule_not_only_affordability(self):
        controller_runtime().execute('''c:search({itemID=1});c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        api.wallet=function()return 1000 end;assert(not c:requestBuy()and quoted==0)''')
    def test_family_replication_never_creates_exact_history_confidence(self):
        runtime().execute('''local d=ForeverFlip.Store.open(nil);for i=1,8 do
        ForeverFlip.Store.observe(d,'s','1:0:0:0',{at=1000000-i*15000,price=1000,complete=true,family=true,token=i})end
        assert(not ForeverFlip.Market.stats(d.markets.s['1:0:0:0'].samples,1000000).credible)''')
    def test_future_and_negative_age_prices_unavailable(self):
        controller_runtime().execute('''db.markets.scope={['1:0:0:0']={latest={price=100,at=now+999999}}}
        ForeverFlip.Adapters.prices=function()return {{source='auxForever',price=100,age=-1}}end
        assert(not c:price(1))''')
    def test_price_source_drops_old_aux_from_formulas(self):
        controller_runtime().execute('''ForeverFlip.Adapters.prices=function()return {{source='auxForever',price=100,age=1000000}}end
        assert(c:options({itemID=1}).aux==nil)''')
    def test_missing_commodity_quantity_not_booked(self):
        controller_runtime().execute('''c:search({itemID=1});c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1);c:requestBuy()
        c:event('COMMODITY_PRICE_UPDATED',100,1000);c:confirmBuy();c:event('COMMODITY_PURCHASED',1)
        assert(#db.ledger==0 and c:reserved()==1000)''')
    def test_pasted_link_keeps_item_identity(self):
        ui_runtime().execute('''C_Item={GetDetailedItemLevelInfo=function()return 42 end}
        u.fields.item:SetText('|Hitem:123:0:0:0:0:0:7:0:60|h[Test]|h')
        local k=u.readKey();assert(k.itemID==123 and k.itemSuffix==7 and k.itemLevel==42)''')
    def test_history_chart_uses_real_script_region_arguments(self):
        ui_runtime().execute('''local lines={}
        u.chart.CreateLine=function()local line={Hide=function()end,Show=function()end,SetThickness=function()end,SetColorTexture=function()end}
        line.SetStartPoint=function(_,point,region,x,y)assert(type(region)=='table'and type(x)=='number'and type(y)=='number')end
        line.SetEndPoint=line.SetStartPoint;lines[#lines+1]=line;return line end
        db.markets.scope={['1:0:0:0']={samples={},days={{day=1,price=100,qty=2},{day=2,price=200,qty=2}}}}
        u.fields.item:SetText('1');u:show('history');assert(#lines==1)''')
    def test_bulk_legacy_assignment_is_atomic_and_idempotent(self):
        runtime().execute('''local S=ForeverFlip.Store;local d=S.open({ledger={{kind='buy',id=1,qty=2,unit=100},{kind='buy',id=2,qty=3,unit=100}}})
        for i=1,9999 do d.ledger[i]={uid='a'..i}end
        assert(not S.adoptLegacy(d,'o','s',1000)and #d.ledger==9999)
        d.ledger={};assert(S.adoptLegacy(d,'o','s',1000));assert(S.adoptLegacy(d,'o','s',1000)and #d.ledger==2)''')
    def test_group_budget_counts_existing_holdings(self):
        controller_runtime().execute('''db.groups={{name='g',items={[1]=true,[2]=true},rule={budget=1000}}}
        ForeverFlip.Ledger.append(db,{kind='buy',owner='owner',scope='scope',key='2:0:0:0',qty=1,total=900})
        assert(c:options({itemID=1}).budget==100)''')
    def test_exact_key_watch_and_groups(self):
        controller_runtime().execute('''assert(ForeverFlip.Store.watch(db,'1:42:7:0'));assert(db.watchlist[1]=='1:42:7:0')
        local g=ForeverFlip.Store.importGroup('FFG2|Gear|1:42:7:0|25|1|100|2');assert(g and g.keys['1:42:7:0'])
        db.groups={g};assert(c:rule({itemID=1,itemLevel=42,itemSuffix=7}).group=='Gear')
        assert(not c:rule({itemID=1,itemLevel=42,itemSuffix=8}).group)''')

if __name__=='__main__':unittest.main()
