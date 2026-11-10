import unittest
from test_domain import runtime
from test_controller import controller_runtime


class AuditModelsTests(unittest.TestCase):
    def test_sparse_market_obeys_explicit_bounds_formulas_and_advisor(self):
        runtime().execute('''local M=ForeverFlip.Market
        local rows={{qty=1,unit=100,cost=100},{qty=10,unit=1000,cost=10000},{qty=10,unit=1100,cost=11000}}
        local o={wallet=100000,now=1000000,minROI=.25,minProfit=0,maxShare=1,maxQty=10,buyLimit=50,sellPrice=120}
        local p=M.plan(rows,{},o);assert(p.qty==0 and p.target==120 and not p.canBuy)
        o.buyLimit=nil;o.sellPrice=nil;o.buyFormula='50c';o.sellFormula='120c'
        p=M.plan(rows,{},o);assert(p.qty==0 and p.target==120)
        o.buyFormula=nil;o.sellFormula=nil;o.advice={priceCap=120,maxQty=10,reason='ok',prices={known=false},trades={}}
        p=M.plan(rows,{},o);assert(p.target==120 and not p.canBuy)
        o.advice=nil;o.buyFormula=ForeverFlip.Store.defaults.buyFormula;o.sellFormula=ForeverFlip.Store.defaults.sellFormula
        p=M.plan(rows,{},o);assert(p.basis=='listings' and p.canBuy)''')

    def test_extreme_roi_sparse_ladder_returns_safe_plan(self):
        runtime().execute('''local p=ForeverFlip.Market.plan({{qty=1,unit=100,cost=100},{qty=10,unit=1000,cost=10000},{qty=10,unit=1100,cost=11000}},
        {},{wallet=100000,now=1000000,minROI=10,vendor=1,minProfit=0});assert(not p.canBuy)''')

    def test_sale_price_exact_fee_floor_uses_quantity_and_extra_cost(self):
        runtime().execute('''local M=ForeverFlip.Market
        local p={avgBuy=1000,minimum=1200,feeRate=.05,minFee=500,reserveRate=0,extraCost=200}
        assert(M.salePrice(p,1)==1700);assert(M.salePrice(p,2)==1400)
        assert(M.priceStep(250,true)==200 and M.priceStep(200,true)==100 and M.priceStep(250)==200)
        assert(M.salePrice(p,0)==nil and M.salePrice(p,1.5)==nil)
        p.reserveRate=.1;assert(M.salePrice(p,1)==1900)
        assert(M.salePrice({avgBuy=0,minimum=100,extraCost=500,feeRate=0},1)==500)''')

    def test_break_even_matches_minimum_fee_without_double_charge(self):
        runtime().execute('''local M=ForeverFlip.Market
        local p=M.plan({{qty=1,unit=1000,cost=1000}},{},{wallet=1000000,now=1000000,buyLimit=1000,sellPrice=3000,
          minFee=500,reserve=0,fee=.05,minProfit=0,minROI=0,maxShare=1})
        assert(p.breakEven==1500)
        assert(M.breakEven(1000,1,.05,0,0,0)==1053)
        assert(M.breakEven(1000,1,.05,.1,500,200)==1888)''')

    def test_break_even_bounds_work_for_near_total_fee_rates(self):
        runtime().execute('''local M=ForeverFlip.Market
        debug.sethook(function()error('inverse calculation exceeded work budget')end,'',100000)
        local p=M.breakEven(100,1,.5,.499999999,0,0)
        debug.sethook()
        assert(p and p>100 and M.net(p,.5,.499999999,0)>=100)''')

    def test_duplicate_reagents_consume_shared_stock_once(self):
        runtime().execute('''local p=ForeverFlip.Professions.calculate({{id=1,qty=3,price=100,owned=3},{id=1,qty=3,price=100,owned=3}},nil,1,1000,{})
        assert(p.complete and p.cost==600 and p.cashCost==300)
        local n=0;for _,m in ipairs(p.shopping)do n=n+m.qty end;assert(n==3)''')

    def test_disenchant_minimum_fee_applies_per_output_id(self):
        runtime().execute('''local P=ForeverFlip.Professions
        local p=P.disenchant({{id=1,qty=1,price=1000},{id=2,qty=1,price=1000}},nil,100,{fee=.05,minFee=500})
        assert(p.complete and p.net==1000 and p.profit==900)
        p=P.disenchant({{id=1,qty=1,price=1000},{id=1,qty=1,price=1000}},nil,100,{fee=.05,minFee=500})
        assert(p.net==1500)''')

    def test_model_overflow_is_incomplete(self):
        runtime().execute('''local P=ForeverFlip.Professions
        assert(not P.calculate({{id=1,qty=1e200,price=1e200}},nil,1,1000,{}).complete)
        assert(not P.calculate({{id=1,qty=1,price=10}},nil,1e200,1e200,{}).complete)
        assert(not P.disenchant({{id=1,qty=1e200,price=1e200}},nil,100,{}).complete)''')

    def test_profession_scenarios_reject_invalid_financial_options(self):
        runtime().execute('''local P=ForeverFlip.Professions
        for _,o in ipairs({{fee=-.1},{reserve=math.huge},{minFee=-1},{extraCost='oops'}}) do
            assert(not P.calculate({{id=1,qty=1,price=100}},nil,1,1000,o).complete)
            assert(not P.disenchant({{id=1,qty=1,price=1000}},nil,100,o).complete)
        end''')

    def test_stats_excludes_void_buys_and_exposes_expenses_separately(self):
        controller_runtime().execute('''db.ledger={
        {uid='b',kind='buy',owner='owner',scope='scope',key='1:0:0:0',qty=1,total=100,at=now},
        {uid='v',kind='void',target='b',owner='owner',scope='scope',at=now},
        {uid='e',kind='expense',owner='owner',scope='scope',total=25,at=now}}
        local p=ForeverFlip.Stats.compute(c,now).periods[1]
        assert(p.spent==0 and p.buys==0);assert(p.expenses==25 and p.closedProfit==0 and p.netProfit==-25)''')


if __name__ == '__main__':
    unittest.main()
