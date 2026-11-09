import unittest
from test_controller import controller_runtime
from test_domain import runtime

class RefinementTests(unittest.TestCase):
    def test_history_buffer_does_not_retain_full_ladders(self):
        runtime().execute('''local db=ForeverFlip.Store.open(nil)
        ForeverFlip.Store.observe(db,'s','1:0:0:0',{at=1000,price=100,qty=10,complete=true,rows={{qty=10,unit=100,cost=1000}}})
        local h=db.markets.s['1:0:0:0'];assert(not h.samples[1].rows and h.latest.rows)''')
    def test_expression_comparison_preserves_zero_true_branch(self):
        runtime().execute("assert(ForeverFlip.Expr.eval('ifgt(2,1,0,3)',{})==0)")
    def test_confirm_after_house_change_blocked(self):
        controller_runtime().execute('''c:search({itemID=1});c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1);c:requestBuy()
        c:event('COMMODITY_PRICE_UPDATED',100,1000);api.scope=function()return 'other'end
        assert(not c:confirmBuy() and spent==0)''')
    def test_known_quantity_velocity_not_based_on_disappearing_listings(self):
        runtime().execute('''local M=ForeverFlip.Market;assert(not M.velocity({},'1',1000000).known)
        local sales={};for i=1,10 do sales[i]={key='1',known=2,at=1000000-i*86400}end
        local v=M.velocity(sales,'1',1000000);assert(v.known and v.lower>0 and v.lower<v.daily)''')
    def test_imported_price_scope_and_future_rejected(self):
        runtime().execute(r'''local S=ForeverFlip.Store;local db=S.open(nil)
        assert(not S.importPrices(db,'FFP1|foreign|1000\n1:0:0:0,100,3','local',2000))
        assert(not S.importPrices(db,'FFP1|local|3000\n1:0:0:0,100,3','local',2000))
        assert(S.importPrices(db,'FFP1|local|1000\n1:0:0:0,100,3','local',2000))
        assert(db.markets['local']['1:0:0:0'].latest.price==100)''')
    def test_snapshot_uses_volume_quantile_not_single_bait(self):
        runtime().execute('''local s=ForeverFlip.Market.snapshot({{qty=1,unit=1,cost=1},{qty=99,unit=100,cost=9900}})
        assert(s.price==100 and s.minimum==1 and s.qty==100)''')

if __name__=='__main__':unittest.main()
