import unittest
from test_controller import controller_runtime


class AuditIntegrationTests(unittest.TestCase):
    def test_noncanonical_ledger_key_cannot_disable_cost_protection(self):
        controller_runtime().execute("""local ok=ForeverFlip.Ledger.append(db,
        {uid='x',kind='buy',owner='owner',scope='scope',key='01:0:0:0',qty=1,total=100,at=now})
        assert(not ok,'noncanonical ledger identity must be rejected')""")

    def test_damaged_day_is_preserved_readonly(self):
        controller_runtime().execute("""db.markets.scope={['1:0:0:0']={samples={},days={{day=1,price=100,n=1}}}}
        local result=ForeverFlip.Store.open(db);assert(result==db)
        assert(not ForeverFlip.Store.writable(result))""")

    def test_visible_identical_mail_in_adjacent_expiry_buckets_counts_both(self):
        controller_runtime().execute("""db.listings={{owner='owner',scope='scope',name='A',key='1:0:0:0',qty=1}}
        c.mail={{kind='seller',name='A',qty=1,amount=100,deposit=0,fingerprint='content',arrivalBucket=10},
        {kind='seller',name='A',qty=1,amount=100,deposit=0,fingerprint='content',arrivalBucket=11}}
        c:mailProposals();assert(#db.ledger==2)
        c:mailProposals();assert(#db.ledger==2)""")

if __name__=='__main__':unittest.main()
