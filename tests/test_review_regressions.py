import unittest
from test_domain import runtime
from test_controller import controller_runtime
from test_ui import ui_runtime

class ReviewRegressionTests(unittest.TestCase):
    def test_repeated_quote_increase_invalidates_confirmation(self):
        controller_runtime().execute('''c:search({itemID=1});c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1);c:requestBuy()
        c:event('COMMODITY_PRICE_UPDATED',100,1000);c:event('COMMODITY_PRICE_UPDATED',150,1500)
        assert(not c:confirmBuy()and spent==0)''')
    def test_unsolicited_same_key_partial_results_invalidate_plan(self):
        controller_runtime().execute('''c:search({itemID=1});c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        full=false;c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1);assert(not c:fresh()and not c:requestBuy())''')
    def test_itemid_only_receipt_cannot_claim_exact_item_lot(self):
        controller_runtime().execute('''api.rows=function()return {{qty=1,unit=100,cost=100,auctionID=1}},true,'item'end
        c:search({itemID=1});c:event('ITEM_SEARCH_RESULTS_UPDATED',{itemID=1});assert(c:requestBuy())
        c:event('ITEM_PURCHASED',1);assert(#db.ledger==0 and c:reserved()==100 and c.active.status=='unknown')''')
    def test_changed_bag_row_object_can_confirm_same_location(self):
        controller_runtime().execute('''local count=0;api.deposit=function()return 0 end
        api.post=function(_,_,_,_,_,confirm)if confirm then count=count+1 end;return not confirm end
        c.mode='flip';c.key={itemID=1};c.planMode='flip';c.plan={key=c.key,complete=true,scope='scope',at=now,ruleVersion=0,kind='commodity',minimum=1000,stats={lower=2000}}
        db.settings.sellFormula='100c';c:post({id=1,key={itemID=1},bag=0,slot=1,qty=10},1,10000,2)
        c:post({id=1,key={itemID=1},bag=0,slot=1,qty=10},1,10000,2);assert(count==1)''')
    def test_unknown_scope_and_owner_block_trading(self):
        controller_runtime().execute("api.scope=function()return 'wowf:?:x:Alliance'end;assert(not c:search({itemID=1}))")
        controller_runtime().execute("api.owner=function()return 'x:nil'end;assert(not c:search({itemID=1}))")
    def test_malformed_v5_ledger_is_never_cleared(self):
        runtime().execute("local old={schemaVersion=5,ledger='damaged',pending={}};local d=ForeverFlip.Store.open(old);assert(d.ledger=='damaged'and not ForeverFlip.Store.writable(d))")
    def test_future_schema_tick_does_not_mutate_pending(self):
        controller_runtime().execute("local old={schemaVersion=99,pending={}};for i=1,200 do old.pending[i]={status='done'}end;local d=ForeverFlip.Controller.new(old,api);d:tick();assert(#old.pending==200)")
    def test_unknown_purchase_formula_does_not_allow_spending(self):
        runtime().execute('''local h={};for i=1,8 do h[i]={price=10000,at=1000000-i*15000,token=i}end
        local p=ForeverFlip.Market.plan({{qty=10,unit=100,cost=1000}},h,{buyFormula='avgbuy',wallet=100000,now=1000000,minProfit=0})
        assert(not p.canBuy and p.qty==0)''')
    def test_conditional_missing_selected_source_stays_invalid(self):
        runtime().execute("assert(ForeverFlip.Expr.eval('ifgt(2,1,unknown,3g)',{})==nil)")
    def test_bid_below_one_gold_never_crosses_buyout(self):
        controller_runtime().execute('''local bid
        local r={auctionID=2,quantity=1,minBid=50,bidAmount=0,buyoutAmount=100}
        api.rows=function()return {{qty=1,unit=100,cost=100,auctionID=2}},true,'item',{r}end
        api.buyItem=function(_,amount)bid=amount end
        c.mode='flip';db.settings.minProfit=0;db.settings.buyFormula='10000c'
        api.wallet=function()return 10000000 end
        for i=1,8 do ForeverFlip.Store.observe(db,'scope','1:0:0:0',{at=now-i*15000,price=1000000,qty=10,complete=true,token=i})end
        c:search({itemID=1});c:event('ITEM_SEARCH_RESULTS_UPDATED',{itemID=1});c:bid(1)
        assert(bid==nil or bid==50)''')
    def test_bid_does_not_bypass_missing_history(self):
        controller_runtime().execute('''local bid=false;local r={auctionID=2,quantity=1,minBid=50,bidAmount=0,buyoutAmount=1000}
        api.rows=function()return {{qty=1,unit=1000,cost=1000,auctionID=2}},true,'item',{r}end
        api.buyItem=function()bid=true end
        c.mode='flip';db.settings.buyFormula='1000c';db.settings.sellFormula='100000c';db.settings.minProfit=0
        c:search({itemID=1});c:event('ITEM_SEARCH_RESULTS_UPDATED',{itemID=1});assert(not c:bid(1)and not bid)''')
    def test_malformed_group_numbers_do_not_throw(self):
        runtime().execute("local ok,g=pcall(ForeverFlip.Store.importGroup,'FFG1|bad|1|..|1|100|1');assert(ok and not g)")
    def test_v4_recipe_output_and_de_yields_migrate(self):
        runtime().execute('''local old={recipes={x={qty=3,materials='2589*2@1',id=100,outputPrice='2'}},disenchant={y={materials='10940*1.5@1',buyCost='1'}}}
        local d=ForeverFlip.Store.open(old);assert(tonumber(d.recipes.x.outputQty)==3)
        assert(d.disenchant.y.raw=='10940*1.5@1'and tonumber(d.disenchant.y.cost)==1)''')
    def test_real_library_major_name_attaches_a_tab(self):
        l=controller_runtime()
        l.execute((__import__('test_domain').ROOT/'tests/wow_mock.lua').read_text())
        l.execute('''made=false;lib={DoesIDExist=function()return false end,CreateTab=function()made=true end}
        LibStub=function(name)if name=='LibAHTab-1-0'then return lib end end''')
        root=__import__('test_domain').ROOT
        l.execute((root/'ForeverFlip/UI.lua').read_text(encoding='utf-8-sig'))
        l.execute((root/'ForeverFlip/Core.lua').read_text(encoding='utf-8-sig'))
        l.execute("ForeverFlip.boot('ForeverFlip');ForeverFlip.attach();assert(made and ForeverFlip.tabLibrary==lib)")

if __name__=='__main__':unittest.main()
