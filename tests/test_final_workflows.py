import unittest
from test_domain import runtime
from test_controller import controller_runtime
from test_ui import ui_runtime

class FinalWorkflowTests(unittest.TestCase):
    def test_trade_overrides_cannot_raise_group_caps(self):
        controller_runtime().execute('''db.groups={{name='g',items={[1]=true},rule={budget=100,maxQty=2}}}
        c.overrides={budget=100000,maxQty=100};local o=c:options({itemID=1});assert(o.budget==100 and o.maxQty==2)''')
    def test_mail_proposal_requires_unique_posting_match(self):
        controller_runtime().execute('''db.listings={{owner='owner',scope='scope',key='1:0:0:0',name='Test item',qty=2}}
        c.mail={{kind='seller',name='Test item',qty=2,amount=100}}
        c:mailProposals();assert(c.mail[1].suggestedKey=='1:0:0:0')
        db.listings[2]={owner='owner',scope='scope',key='1:0:7:0',name='Test item',qty=2}
        c:mailProposals();assert(c.mail[1].suggestedKey==nil)''')
    def test_legacy_malformed_financial_rows_stop_trading(self):
        runtime().execute("local d=ForeverFlip.Store.open({ledger={{kind='buy',id=1,qty=2,unit='damaged'}}});assert(not ForeverFlip.Store.writable(d))")
    def test_interface_recovers_refresh_guard_after_render_error(self):
        l=ui_runtime()
        l.execute("u.refreshers.overview=function()error('test render failure')end;pcall(function()u:refresh()end);assert(not u.refreshing)")

if __name__=='__main__':unittest.main()
