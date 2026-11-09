import unittest
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MODULES = ['Util', 'Locale', 'Expressions', 'Store', 'Ledger', 'Market', 'Professions', 'Advisor', 'Workbench', 'NativeLayout', 'ItemDisplay', 'NativeShopping']

def runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('ForeverFlip = {}; time = function() return 1000000 end')
    for name in MODULES:
        file = ROOT / 'ForeverFlip' / (name + '.lua')
        assert file.exists(), 'Missing domain module: ' + name
        lua.execute(file.read_text(encoding='utf-8-sig'))
    return lua

class DomainTests(unittest.TestCase):
    def check_lua(self, body):
        runtime().execute(body)

    def test_money_rejects_invalid_values(self):
        self.check_lua('''local U=ForeverFlip.Util
        assert(U.copper('0,0123')==123); assert(U.copper('-1')==nil)
        assert(U.copper('nan')==nil); assert(not U.finite(0/0)); assert(not U.finite(math.huge))''')

    def test_variants_do_not_merge(self):
        self.check_lua('''local U=ForeverFlip.Util
        assert(U.key({itemID=1,itemSuffix=2})~=U.key({itemID=1,itemSuffix=3}))''')

    def test_expression_math_and_sources(self):
        self.check_lua('''local E=ForeverFlip.Expr
        assert(E.eval('min(80% market, 10g)',{market=200000})==100000)
        assert(E.eval('first(missing, vendorsell * 0.8)',{vendorsell=100})==80)
        assert(E.eval('ifgt(market, 10g, 2g, 1g)',{market=200000})==20000)''')

    def test_expression_rejects_execution_divzero_depth(self):
        self.check_lua('''local E=ForeverFlip.Expr
        assert(E.eval('os.execute("x")',{})==nil)
        assert(E.eval('1/0',{})==nil); assert(E.eval('unknown+1g',{})==nil)
        assert(E.eval(string.rep('(',70)..'1'..string.rep(')',70),{})==nil)''')

    def test_migration_preserves_original_and_unknown_owner(self):
        self.check_lua('''local old={marketSchemaVersion=3,watchlist={2589},ledger={{kind='buy',id=2589,qty=5,unit=100}},recipes={x={id=2}}}
        local db,backup=ForeverFlip.Store.open(old)
        assert(db.schemaVersion==5 and backup==old and not old.schemaVersion)
        assert(db.watchlist[1]==2589 and #db.legacyLedger==1 and #db.ledger==0)
        assert(db.recipes.x.id==2); assert(ForeverFlip.Store.open(db)==db)''')

    def test_future_schema_readonly(self):
        self.check_lua('''local old={schemaVersion=99,ledger={}}
        local db=ForeverFlip.Store.open(old); assert(db==old)
        assert(not ForeverFlip.Store.writable(db))''')

    def test_history_duplicate_and_sixty_day_bounds(self):
        self.check_lua('''local S=ForeverFlip.Store; local db=S.open(nil)
        for i=1,200 do S.observe(db,'s','1:0:0:0',{at=i*900,price=100,qty=30,token=tostring(i),complete=true}) end
        local h=db.markets.s['1:0:0:0']; assert(#h.samples<=120)
        local n=#h.samples; local last=h.samples[n]
        S.observe(db,'s','1:0:0:0',last); assert(#h.samples==n)
        assert(h.days and #h.days<=60)''')

    def test_fifo_partial_unknown_consumes_known_stock(self):
        self.check_lua('''local L=ForeverFlip.Ledger; local e={
        {kind='buy',owner='a',scope='s',key='1',qty=5,total=500,at=1},
        {kind='sell',owner='a',scope='s',key='1',qty=8,total=1600,fee=0,at=2}}
        local r=L.summary(e,'a','s'); assert(r.stock==0 and r.unknown==3 and r.realized==500)''')

    def test_fifo_isolates_owners_and_variants(self):
        self.check_lua('''local r=ForeverFlip.Ledger.summary({
        {kind='buy',owner='a',scope='s',key='1:1',qty=3,total=300,at=1},
        {kind='sell',owner='b',scope='s',key='1:1',qty=3,total=600,fee=0,at=2},
        {kind='sell',owner='a',scope='s',key='1:2',qty=3,total=600,fee=0,at=3}},'a','s')
        assert(r.stock==300 and r.unknown==3 and r.realized==0)''')

    def test_fifo_integer_allocation_and_duplicate_ids(self):
        self.check_lua('''local L=ForeverFlip.Ledger; local e={
        {uid='a',kind='buy',owner='o',scope='s',key='1',qty=3,total=100,at=1},
        {uid='a',kind='buy',owner='o',scope='s',key='1',qty=3,total=100,at=1},
        {kind='sell',owner='o',scope='s',key='1',qty=1,total=100,fee=0,at=2},
        {kind='sell',owner='o',scope='s',key='1',qty=2,total=200,fee=0,at=3}}
        local r=L.summary(e,'o','s'); assert(r.stock==0 and r.realized==200 and r.buys==100)''')

    def test_ledger_correction_is_append_only(self):
        self.check_lua('''local L=ForeverFlip.Ledger; local db=ForeverFlip.Store.open(nil)
        local e={uid='x',kind='buy',owner='o',scope='s',key='1',qty=1,total=100,at=1}
        assert(L.append(db,e)); assert(not L.append(db,e)); assert(L.correct(db,'x','o',2))
        assert(#db.ledger==2 and db.ledger[1].total==100)
        assert(L.summary(db.ledger,'o','s').stock==0)''')

    def test_vendor_does_not_need_market_discount(self):
        self.check_lua('''local p=ForeverFlip.Market.plan({{qty=10,unit=100,cost=1000}}, {},
        {mode='vendor',vendor=1000,wallet=20000,budget=2000,maxQty=10,now=1000000,minROI=.25,minProfit=0,maxShare=1})
        assert(p.qty==10 and p.cost==1000 and p.profit==9000 and p.canBuy)''')

    def test_ladder_accounts_for_all_price_levels(self):
        self.check_lua('''local p=ForeverFlip.Market.plan({{qty=2,unit=100,cost=200},{qty=5,unit=200,cost=1000}}, {},
        {mode='vendor',vendor=500,wallet=10000,budget=700,maxQty=7,now=1000000,minROI=.1,minProfit=0,maxShare=1})
        assert(p.qty==4 and p.cost==600 and p.maxUnit==200 and p.nextPrice==200)''')

    def test_item_lots_are_indivisible(self):
        self.check_lua('''local p=ForeverFlip.Market.plan({{qty=5,unit=100,cost=500,auctionID=1}}, {},
        {mode='vendor',vendor=1000,wallet=10000,budget=300,maxQty=5,commodity=false,now=1,minProfit=0,maxShare=1})
        assert(p.qty==0 and not p.canBuy)''')

    def test_history_is_independent_and_future_not_credible(self):
        self.check_lua('''local M=ForeverFlip.Market; local h={}
        for i=1,5 do h[i]={at=100,price=500,token='same'} end
        assert(not M.stats(h,1000).credible)
        assert(not M.stats({{at=2000,price=500}},1000).credible)''')

    def test_missing_history_does_not_invent_flip_profit(self):
        self.check_lua('''local p=ForeverFlip.Market.plan({{qty=10,unit=100,cost=1000}}, {},
        {mode='flip',wallet=10000,budget=1000,now=1000000})
        assert(not p.canBuy and #p.reasons>0)''')

    def test_robust_reference_resists_single_extreme_outlier(self):
        self.check_lua('''local h={}; for i=1,7 do h[i]={at=1000000-i*15000,price=i==7 and 100000000 or 1000,token=i} end
        local s=ForeverFlip.Market.stats(h,1000000); assert(s.reference<2000 and s.credible)''')

    def test_reservations_and_wallet_floor(self):
        self.check_lua('''local p=ForeverFlip.Market.plan({{qty=100,unit=100,cost=10000}}, {},
        {mode='vendor',vendor=1000,wallet=1000,reserved=800,budget=1000,maxQty=100,now=1,minProfit=0,maxShare=1})
        assert(p.cost==0 and not p.canBuy)''')

    def test_unknown_material_is_not_free(self):
        self.check_lua('''local p=ForeverFlip.Professions.calculate({{id=1,qty=3}},function() return nil end,1,10000,{})
        assert(not p.complete and p.profit==nil)''')

    def test_crafting_expected_yield_and_opportunity_cost(self):
        self.check_lua('''local p=ForeverFlip.Professions.calculate({{id=1,qty=3,price=100,owned=3}},nil,2,1000,{fee=.05})
        assert(p.complete and p.cost==300 and p.cashCost==0 and p.profit==1600)''')

    def test_safe_group_exchange_rejects_lua(self):
        self.check_lua('''local S=ForeverFlip.Store; assert(not S.importGroup('return os.execute("x")'))
        local g=S.importGroup('FFG1|Herbs|2589,2592|25|1|100|10'); assert(g and g.items[2589] and g.rule.minROI==.25)''')

if __name__ == '__main__':
    unittest.main()
