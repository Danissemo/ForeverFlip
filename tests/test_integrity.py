import unittest
from test_domain import runtime
from test_controller import controller_runtime

class IntegrityTests(unittest.TestCase):
    def test_malformed_legacy_tables_quarantined(self):
        runtime().execute('''local old={watchlist='bad',ledger='bad',recipes='bad',disenchant='bad'}
        local db,backup=ForeverFlip.Store.open(old)
        assert(type(db.watchlist)=='table'and type(db.legacyLedger)=='table'and type(db.recipes)=='table'and backup==old)
        assert(#db.quarantine>0 and old.ledger=='bad')''')
    def test_posting_rejects_changed_duration_confirmation(self):
        controller_runtime().execute('''local item={id=1,key={itemID=1},qty=10};local posted=0
        api.deposit=function()return 0 end;api.post=function(_,_,_,_,duration,confirm)if confirm then posted=posted+1 end;return true end
        c.mode='flip';c.key={itemID=1};c.planMode='flip';c.plan={key=c.key,complete=true,scope='scope',at=now,ruleVersion=0,kind='commodity',minimum=1000,stats={lower=2000}}
        db.settings.sellFormula='100c';assert(c:post(item,1,10000,1));assert(c:post(item,1,10000,2));assert(posted==0)''')
    def test_resolved_pending_records_are_bounded(self):
        controller_runtime().execute('''for i=1,200 do db.pending['old'..i]={owner='owner',status='done',total=1}end
        c:tick();local n=0;for _ in pairs(db.pending)do n=n+1 end;assert(n<=100)''')

if __name__=='__main__':unittest.main()
