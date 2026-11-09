import unittest
from test_domain import runtime, ROOT

def workbench_runtime():
    l=runtime()
    file=ROOT/'ForeverFlip/Workbench.lua'
    assert file.exists(), 'Missing decision workbench'
    l.execute(file.read_text(encoding='utf-8-sig'))
    l.execute('''W=ForeverFlip.Workbench
    function offer(id,cost,target,qty)
        qty=qty or 1
        return {key={itemID=id},mode='flip',kind='item',qty=qty,cost=cost,profit=target*qty-cost,
        target=target,canBuy=true,complete=true,at=1000,feeRate=0,minFee=0,reserveRate=0,
        confidence=1,lots={{qty=qty,cost=cost,unit=cost/qty,auctionID=id}},stats={credible=true}}
    end''')
    return l

class WorkbenchTests(unittest.TestCase):
    def check(self,body): workbench_runtime().execute(body)
    def test_stress_includes_fixed_exit_cost(self):
        self.check('''local p=offer(1,100,150);p.extraCost=25
        local r=W.stress(p,1,100,0);assert(r.base==25 and r.stressed==25)''')
    def test_shared_budget_prefers_two_items_over_ratio_greedy(self):
        self.check('''local r=W.allocate({offer(1,6,18),offer(2,5,14),offer(3,5,14)},
        {budget=10,riskCap=0,drop=0,now=1000})
        assert(r.cost==10 and r.profit==18 and #r.lines==2 and r.cost<=r.budget)''')
    def test_group_budget_shared_across_recommendations(self):
        self.check('''local a,b=offer(1,50,80),offer(2,50,80);a.group='g';b.group='g';a.groupRemaining=50;b.groupRemaining=50
        local r=W.allocate({a,b},{budget=100,riskCap=100,drop=0,now=1000})
        assert(r.cost==50 and #r.lines==1)''')
    def test_risk_cap_uses_total_scenario_loss(self):
        self.check('''local r=W.allocate({offer(1,100,120),offer(2,100,120)},
        {budget=200,riskCap=50,drop=.5,now=1000})
        assert(r.loss<=50 and r.cost<=100)''')
    def test_stale_family_missing_and_duplicate_items_rejected(self):
        self.check('''local a,b,d=offer(1,10,30),offer(2,10,30),offer(3,10,30)
        a.at=0;b.family=true;d.canBuy=false
        local good=offer(4,10,30)
        local r=W.allocate({a,b,d,good,good},{budget=100,riskCap=100,drop=0,now=2000,maxAge=100})
        assert(#r.lines==0)
        r=W.allocate({good,good},{budget=100,riskCap=100,drop=0,now=1000})
        assert(#r.lines==1)''')
    def test_item_lot_is_never_partially_allocated(self):
        self.check('''local r=W.allocate({offer(1,100,80,2)},{budget=60,riskCap=60,drop=0,now=1000})
        assert(r.cost==0 and #r.lines==0)''')
    def test_item_plan_can_take_affordable_whole_lot_prefix(self):
        self.check('''local p=offer(1,100,100,2)
        p.lots={{qty=1,cost=50,unit=50,auctionID=1},{qty=1,cost=50,unit=50,auctionID=2}}
        local r=W.allocate({p},{budget=60,riskCap=0,drop=0,now=1000})
        assert(r.cost==50 and #r.lines==1 and r.lines[1].qty==1)''')
    def test_commodity_partial_uses_exact_prefix_depth(self):
        self.check('''local p=offer(1,120,20,10);p.kind='commodity'
        p.lots={{qty=5,unit=10,cost=50},{qty=5,unit=14,cost=70}}
        local r=W.allocate({p},{budget=50,riskCap=50,drop=0,now=1000})
        assert(#r.lines==1 and r.lines[1].qty==5 and r.lines[1].cost==50)''')
    def test_stress_respects_minimum_fees_and_vendor_mode(self):
        self.check('''local p=offer(1,100,200);p.feeRate=.05;p.minFee=30;p.reserveRate=.10
        local s=W.stress(p,1,100,.20);assert(s.base==50 and s.stressed==14)
        p.mode='vendor';s=W.stress(p,1,100,.50);assert(s.base==100 and s.stressed==100)''')
    def test_allocation_does_not_mutate_inputs_and_reports_limits(self):
        self.check('''local a={};for i=1,100 do a[i]=offer(i,1,2)end
        local r=W.allocate(a,{budget=100,riskCap=100,drop=0,now=1000})
        assert(r.truncated and r.considered<=60 and #a==100 and a[1].qty==1)
        assert(W.allocate(a,{budget=-1,riskCap=0,now=1000}).cost==0)''')
    def test_actual_analytics_excludes_unknown_cost_and_counts_loss_streak(self):
        self.check('''local r=W.performance({salesHistory={
        {key='1',qty=2,known=1,profit=40,total=200,fee=20,at=1},
        {key='2',qty=1,known=0,profit=0,total=1000,fee=0,at=2},
        {key='1',qty=1,known=1,profit=-10,total=100,fee=0,at=3},
        {key='1',qty=1,known=1,profit=-10,total=100,fee=0,at=4},
        {key='1',qty=1,known=1,profit=-30,total=100,fee=0,at=5}},realized=-10},10)
        assert(r.items['1'].knownUnits==4 and r.items['1'].lossStreak==3)
        assert(not r.items['2'] and r.items['1'].profit==-10 and r.items['1'].pauseSuggested)''')
    def test_replay_uses_past_only_and_does_not_claim_real_sales(self):
        self.check('''local samples={};for i=1,6 do samples[#samples+1]={at=i*20000,price=100,complete=true,token=i}end
        samples[#samples+1]={at=140000,price=60,complete=true,token=7}
        local a=W.replay(samples,{capital=1000,hold=86400,now=300000,fee=0,haircut=0,minROI=.1})
        assert(a.baseline.openCost>0 and a.baseline.closed==0 and a.simulated)
        samples[#samples+1]={at=240000,price=100,complete=true,token=8}
        local b=W.replay(samples,{capital=1000,hold=86400,now=300000,fee=0,haircut=0,minROI=.1})
        assert(b.baseline.closed==1 and b.baseline.pnl==40 and b.baseline.firstEntry==a.baseline.firstEntry)''')
    def test_replay_requires_training_and_filters_future_family_samples(self):
        self.check('''local r=W.replay({{at=1,price=1},{at=2,price=1000},{at=999999,price=1000},
        {at=3,price=1,family=true}},{capital=1000,now=100})
        assert(r.baseline.closed==0 and r.baseline.openCost==0 and r.trainingInsufficient)''')
    def test_frequent_scans_retain_actual_daily_anchors(self):
        self.check('''local S=ForeverFlip.Store;local d=S.open(nil)
        for i=1,360 do S.observe(d,'s','1:0:0:0',{at=i*600,price=100,qty=10,complete=true,token=i})end
        local h=d.markets.s['1:0:0:0'];local evidence=ForeverFlip.Market.evidence(h)
        assert(#h.samples==120 and ForeverFlip.Market.stats(evidence,216000).credible)
        local oldest=216000;for _,e in ipairs(evidence)do oldest=math.min(oldest,e.at)end;assert(oldest==600)''')

if __name__=='__main__':unittest.main()
