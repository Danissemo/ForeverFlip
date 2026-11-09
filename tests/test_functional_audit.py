import math
import random
import unittest
from test_domain import runtime
from test_controller import controller_runtime
from test_ui import ui_runtime


class FunctionalAuditTests(unittest.TestCase):
    def test_power_precedence_associativity_and_unary_sign(self):
        l=runtime();evaluate=l.globals().ForeverFlip.Expr.eval
        for formula,expected in [('2*3^2',18),('2^3^2',512),('-2^2',-4),('(-2)^2',4),('2^-2',.25),('3+2*4^2',35)]:
            with self.subTest(formula=formula):
                value,_=evaluate(formula,l.table())
                self.assertEqual(value,expected)
    def test_explicit_unknown_rounding_step_stays_unknown(self):
        runtime().execute("assert(ForeverFlip.Expr.eval('round(10g,missing)',{})==nil)")
    def test_decimal_rounding_does_not_lose_copper_at_binary_float_boundaries(self):
        l=runtime();evaluate=l.globals().ForeverFlip.Expr.eval
        for formula,want in [('round(.145,.01)',.15),('round(2.15,.1)',2.2),('rounddown(.3,.1)',.3),('roundup(.14,.01)',.14)]:
            actual,_=evaluate(formula,l.table());self.assertAlmostEqual(actual,want,places=12,msg=formula)
        self.assertEqual(l.globals().ForeverFlip.Util.copper('0.00015'),2)
    def test_fee_rounding_matches_integer_percentage_reference(self):
        l=runtime();fee=l.globals().ForeverFlip.Market.fee
        for rate in range(51):
            for total in range(1,2001):
                self.assertEqual(fee(total,rate/100,0),(total*rate+50)//100,(total,rate))
    def test_copper_input_matches_decimal_reference(self):
        copper=runtime().globals().ForeverFlip.Util.copper
        for i in range(1,5001):
            self.assertEqual(copper(f'{i/100000:.5f}'),(i+5)//10,i)
    def test_disenchant_deducts_extra_cost_like_craft(self):
        runtime().execute('''local P=ForeverFlip.Professions
        local r=P.disenchant({{id=1,qty=2,price=100}},nil,100,{fee=0,reserve=0,extraCost=30})
        assert(r.complete and r.net==200 and r.profit==70 and r.roi==.7)''')
    def test_fractional_disenchant_outputs_match_integer_gross_reference(self):
        l=runtime();calc=l.globals().ForeverFlip.Professions.disenchant;rng=random.Random(299)
        for _ in range(300):
            tenths=rng.randint(1,200);price=rng.randint(1,500);fee=rng.randint(0,15);reserve=rng.randint(0,30)
            gross=tenths*price//10
            expected=gross-(gross*fee+50)//100-(gross*reserve)//100
            result=calc(l.table_from([l.table_from(dict(id=1,qty=tenths/10,price=price))]),None,100,
                l.table_from(dict(fee=fee/100,reserve=reserve/100,extraCost=15)))
            self.assertEqual(result.net,expected,(tenths,price,fee,reserve))
            self.assertEqual(result.profit,expected-115)
    def test_stress_base_profit_equals_trade_plan_under_same_fee_model(self):
        l=runtime();plan=l.globals().ForeverFlip.Market.plan;stress=l.globals().ForeverFlip.Workbench.stress
        rng=random.Random(193)
        for _ in range(200):
            qty=rng.randint(1,10);cost=rng.randint(1,200);price=cost*4;fee=rng.randint(0,15);reserve=rng.randint(0,20)
            minimum=rng.randint(0,50);extra=rng.randint(0,25)
            p=plan(l.table_from([l.table_from(dict(qty=qty,unit=cost,cost=cost*qty))]),l.table(),
                l.table_from(dict(mode='flip',wallet=1000000,budget=100000,maxWallet=1,maxItem=1,cashFloor=0,
                    maxQty=qty,maxShare=1,sellPrice=price,buyLimit=cost,minROI=0,minProfit=0,
                    fee=fee/100,reserve=reserve/100,minFee=minimum,extraCost=extra,now=1)))
            self.assertEqual(p.qty,qty)
            gross=qty*price
            expected=gross-min(gross,max((gross*fee+50)//100,minimum))-(gross*reserve)//100-cost*qty-extra
            self.assertEqual(p.profit,expected)
            self.assertEqual(stress(p,qty,cost*qty,0).base,expected)
    def test_invalid_explicit_material_price_is_not_looked_up_as_missing(self):
        runtime().execute("assert(ForeverFlip.Professions.parse('1*2@..')==nil)")
    def test_vendor_break_even_does_not_include_auction_minimum_fee(self):
        runtime().execute('''local p=ForeverFlip.Market.plan({{qty=1,unit=100,cost=100}},{},
        {mode='vendor',vendor=500,wallet=10000,maxWallet=1,minFee=50,minProfit=0,extraCost=10,now=1})
        assert(p.breakEven==110 and p.profit==390)''')
    def test_vendor_sales_do_not_train_auction_velocity(self):
        runtime().execute('''local h={};for i=1,10 do h[i]={key='1',known=10,at=1000000-i*86400,kind='vendor'}end
        assert(not ForeverFlip.Market.velocity(h,'1',1000000).known)''')
    def test_posting_accepts_same_formula_sources_as_purchase_planning(self):
        controller_runtime().execute('''local L=ForeverFlip.Ledger
        L.append(db,{kind='buy',owner='owner',scope='scope',key='1:0:0:0',qty=1,total=10000,at=now-86400})
        local posted=0;api.deposit=function()return 0 end;api.post=function()posted=posted+1;return false end
        c.mode='flip';c.key={itemID=1};c.planMode='flip'
        c.plan={key=c.key,complete=true,scope='scope',at=now,ruleVersion=0,kind='commodity',minimum=1000,stats={lower=20000}}
        db.settings.sellFormula='120% avgbuy'
        assert(c:post({id=1,key=c.key,qty=1},1,20000,2) and posted==1)''')
    def test_posting_npc_floor_includes_minimum_auction_fee(self):
        controller_runtime().execute('''local posted=0
        api.deposit=function()return 0 end;api.post=function()posted=posted+1;return false end
        api.vendor=function()return 90 end
        c.mode='flip';c.key={itemID=1};c.planMode='flip'
        c.plan={key=c.key,complete=true,scope='scope',at=now,ruleVersion=0,kind='commodity',minimum=100,stats={lower=200}}
        db.settings.sellFormula='100c';db.settings.minFee=25;db.settings.reserve=0
        assert(not c:post({id=1,key=c.key,qty=1},1,100,2) and posted==0)''')
    def test_seller_mail_does_not_turn_refunded_deposit_into_profit(self):
        ui_runtime().execute('''ForeverFlip.Ledger.append(db,{kind='buy',owner='owner',scope='scope',key='1:0:0:0',qty=1,total=10000,at=now-86400})
        c.mail={{kind='seller',qty=1,amount=25000,bid=20000,cut=1000,deposit=6000,suggestedKey='1:0:0:0'}}
        u.actions.mailPrepare:Click();u.actions.entrySave:Click()
        assert(c:summary().realized==9000 and db.ledger[2].total==19000 and db.ledger[2].fee==0)''')
    def test_bad_or_unknown_returned_deposit_does_not_prepare_fictional_income(self):
        ui_runtime().execute('''u.fields.entryTotal:SetText('123')
        c.mail={{kind='seller',qty=1,amount=25000,suggestedKey='1:0:0:0'}}
        u.actions.mailPrepare:Click();assert(u.fields.entryTotal:GetText()=='123')''')

    def test_generated_arithmetic_matches_independent_reference(self):
        l=runtime();evaluate=l.globals().ForeverFlip.Expr.eval;rng=random.Random(714)
        for _ in range(300):
            a,b,c,d,e=[rng.randint(1,12) for _ in range(5)]
            power=rng.randint(1,3)
            formula=f'{a}*{b}^{power}+{c}/{d}-{e}'
            expected=a*(b**power)+c/d-e
            actual,_=evaluate(formula,l.table())
            self.assertAlmostEqual(actual,expected,places=9,msg=formula)
    def test_generated_trade_plans_respect_money_and_whole_lots(self):
        l=runtime();plan=l.globals().ForeverFlip.Market.plan;rng=random.Random(180)
        for _ in range(400):
            wallet=rng.randint(1,100000);reserved=rng.randint(0,wallet);budget=rng.randint(0,wallet)
            qty=rng.randint(1,20);unit=rng.randint(1,500);whole=rng.choice([True,False])
            o=l.table_from(dict(mode='vendor',vendor=unit*2,wallet=wallet,reserved=reserved,budget=budget,
                cashFloor=.2,maxWallet=.5,maxItem=1,maxQty=10,commodity=not whole,now=1,minProfit=0))
            p=plan(l.table_from([l.table_from(dict(qty=qty,unit=unit,cost=unit*qty,auctionID=1))]),l.table(),o)
            cap=max(0,min(budget,wallet-reserved-math.floor(wallet*.2),wallet*.5))
            self.assertLessEqual(p.cost,cap)
            self.assertLessEqual(p.qty,10)
            if whole:self.assertIn(p.qty,[0,qty])
            if p.canBuy:self.assertGreater(p.profit,0)
    def test_random_fifo_partial_disposals_conserve_all_purchase_copper(self):
        l=runtime();append=l.globals().ForeverFlip.Ledger.append;summary=l.globals().ForeverFlip.Ledger.summary
        rng=random.Random(960)
        for _ in range(100):
            db=l.globals().ForeverFlip.Store.open(None);db=db[0] if isinstance(db,tuple) else db
            qty=rng.randint(1,30);cost=rng.randint(1,100000);proceeds=fees=0
            append(db,l.table_from(dict(kind='buy',owner='o',scope='s',key='1:0:0:0',qty=qty,total=cost,at=1)))
            remaining=qty
            while remaining:
                take=rng.randint(1,remaining);total=rng.randint(1,10000);fee=rng.randint(0,total)
                append(db,l.table_from(dict(kind='sell',owner='o',scope='s',key='1:0:0:0',qty=take,total=total,fee=fee,at=2)))
                proceeds+=total;fees+=fee;remaining-=take
            result=summary(db.ledger,'o','s')
            self.assertEqual(result.stock,0)
            self.assertEqual(result.realized,proceeds-fees-cost)

if __name__=='__main__':unittest.main()
