import unittest
from test_controller import controller_runtime
from test_ui import ui_runtime

class WorkbenchUITests(unittest.TestCase):
    def test_workbench_is_inside_auction_window(self):
        ui_runtime().execute("assert(u.sections.workbench);u:show('workbench');u:refresh();assert(u.frame:GetParent()==AuctionHouseFrame)")
    def test_build_and_route_plan_only_searches_not_buys(self):
        ui_runtime().execute('''c.candidates={{key={itemID=1},rows={{qty=10,unit=100,cost=1000}},at=now,scope='scope',family=false,kind='commodity'}}
        u.fields.planBudget:SetText('1');u.fields.planRisk:SetText('1');u.fields.planDrop:SetText('20')
        u.actions.planBuild:Click();assert(u.allocation and #u.allocation.lines==1 and spent==0)
        u.actions.planRoute:Click();assert(c.job and c.key.itemID==1 and spent==0 and quoted==0)
        assert(c.overrides.maxQty==u.allocation.lines[1].qty)''')
    def test_unknown_reservation_stops_portfolio_spending(self):
        controller_runtime().execute('''db.pending.x={owner='owner',scope='scope',total=100000,status='unknown'}
        c.candidates={{key={itemID=1},rows={{qty=10,unit=100,cost=1000}},at=now,scope='scope',family=false}}
        local p=c:allocate({budget=100000,riskCap=100000,drop=.2});assert(p.cost==0)''')
    def test_route_never_raises_existing_tighter_caps(self):
        ui_runtime().execute('''u.allocation={lines={{key={itemID=1},cost=1000,qty=10,mode='vendor'}}}
        c.overrides={budget=100,maxQty=1};u.actions.planRoute:Click()
        assert(c.overrides.budget==100 and c.overrides.maxQty==1)''')
    def test_previous_market_candidates_not_reused(self):
        controller_runtime().execute('''c.candidates={{key={itemID=1},rows={{qty=10,unit=100,cost=1000}},at=now,scope='foreign',family=false}}
        assert(#c:rank()==0)''')
    def test_manual_history_replay_is_readonly(self):
        ui_runtime().execute('''u:show('workbench');u.fields.item:SetText('1')
        u.actions.replay:Click();assert(u.replay and u.replay.simulated and spent==0 and #db.ledger==0)''')
    def test_replay_uses_current_fee_and_group_assumptions(self):
        ui_runtime().execute('''db.settings.fee=.15;db.settings.minFee=15;db.settings.reserve=.03
        local original=ForeverFlip.Workbench.replay
        ForeverFlip.Workbench.replay=function(samples,o)
          assert(o.fee==.15 and o.minFee==15 and o.reserve==.03);return original(samples,o)
        end
        u.fields.item:SetText('1');u.actions.replay:Click();assert(u.replay)''')

if __name__=='__main__':unittest.main()
