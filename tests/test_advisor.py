import unittest
from test_domain import runtime, ROOT


def advisor_runtime():
    l=runtime()
    p=ROOT/'ForeverFlip/Advisor.lua'
    assert p.exists(), 'Missing Advisor module'
    l.execute(p.read_text(encoding='utf-8-sig'))
    l.execute('''A=ForeverFlip.Advisor;now=20*86400
    function prices(values)
      local r={};for i,v in ipairs(values)do r[#r+1]={at=now-(#values-i)*86400,price=v,token=i,complete=true}end;return r
    end
    function trade(at,profit,kind)
      return {key='1:0:0:0',at=at,profit=profit,total=100+profit,fee=0,qty=1,known=1,kind=kind or 'sell'}
    end''')
    return l


class AdvisorTests(unittest.TestCase):
    def check(self,s): advisor_runtime().execute(s)
    def test_daily_balancing_not_more_weight_for_repeated_scans(self):
        self.check('''local h=prices({100,100,100,100,100})
        local a=A.prices(h,now)
        for i=1,100 do h[#h+1]={at=now-1000+i,price=100,token='extra'..i}end
        local b=A.prices(h,now);assert(a.priceCap==b.priceCap and b.days==5)''')
    def test_declining_prices_lower_target_and_report_trend(self):
        self.check('''local a=A.prices(prices({100,95,90,85,80,75}),now)
        assert(a.known and a.priceCap<=75 and a.trend<0 and a.drop>=.1)''')
    def test_isolated_high_spike_does_not_raise_conservative_price(self):
        self.check('''local a=A.prices(prices({100,100,100,100,10000}),now)
        assert(a.priceCap==100 and a.ewma<200)''')
    def test_future_family_duplicate_and_sparse_history(self):
        self.check('''local h=prices({100,100});h[#h+1]={at=now+1,price=9999};h[#h+1]={at=now-86400,price=9999,family=true}
        local a=A.prices(h,now);assert(not a.known and a.days==2 and a.priceCap==nil)''')
    def test_wilson_lower_not_equal_raw_win_rate_and_no_sale_probability(self):
        self.check('''local h={};for i=1,10 do h[i]=trade(now-i*86400,i<=8 and 40 or -20)end
        local a=A.trades(h,'1:0:0:0',now,now-14*86400)
        assert(a.winRate==.8 and a.winLower>0 and a.winLower<.8)
        assert(a.kelly and a.kelly>0 and a.profitFactor==8 and a.saleProbability==nil)''')
    def test_unknown_vendor_foreign_and_future_do_not_train(self):
        self.check('''local h={trade(now,20,'vendor'),trade(now+1,30),trade(now,10)}
        h[3].known=0;h[4]=trade(now,20);h[4].key='foreign'
        local a=A.trades(h,'1:0:0:0',now,now-14*86400)
        assert(a.n==0 and not a.kelly and not a.rateKnown)''')
    def test_zero_sale_days_reduce_observed_rate(self):
        self.check('''local h={};for i=1,6 do h[i]=trade(now-i*86400,20)end
        local a=A.trades(h,'1:0:0:0',now,now-14*86400)
        local b=A.trades(h,'1:0:0:0',now,now-7*86400)
        assert(a.rateKnown and a.daily<b.daily and a.rateLower<a.daily)''')
    def test_all_wins_do_not_invent_loss_distribution(self):
        self.check('''local h={};for i=1,12 do h[i]=trade(now-i*86400,20)end
        local a=A.trades(h,'1:0:0:0',now,now-14*86400)
        assert(a.kelly==nil and a.profitFactor==nil and a.wins==12)''')
    def test_cold_start_probe_less_existing_inventory(self):
        self.check('''local a=A.parameters({}, {}, nil, now,'balanced',100000,0)
        assert(a.maxQty==1 and a.maxBudget<=3000 and not a.rateKnown)
        a=A.parameters({}, {}, nil, now,'balanced',100000,1);assert(a.maxQty==0)''')
    def test_stock_with_long_zero_sales_pauses_restock(self):
        self.check('''local a=A.parameters({}, {}, now-10*86400, now,'balanced',100000,5)
        assert(a.maxQty==0 and a.reason=='no_sales')''')
    def test_loss_history_produces_zero_kelly_budget(self):
        self.check('''local h={};for i=1,12 do h[i]=trade(now-i*86400,i<=3 and 10 or -30)end
        local a=A.parameters(prices({100,100,100,100,100}),h,now-14*86400,now,'balanced',100000,0,'1:0:0:0')
        assert(a.maxBudget==0 and a.trades.kelly==0)''')
    def test_position_sizing_normalizes_outcomes_by_purchase_cost(self):
        self.check('''local a,b={},{}
        for i=1,12 do
          local win=i<=9;local profit=win and 40 or -20
          a[i]=trade(now-i*86400,profit);b[i]=trade(now-i*86400,profit)
          if win then b[i].profit=profit*100;b[i].total=(100+profit)*100 end
        end
        local x=A.trades(a,'1:0:0:0',now,now-14*86400)
        local y=A.trades(b,'1:0:0:0',now,now-14*86400)
        assert(math.abs(x.kelly-y.kelly)<1e-9)''')

if __name__=='__main__': unittest.main()
