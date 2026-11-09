import unittest
from test_controller import controller_runtime
from test_domain import runtime, ROOT

class NativeContractTests(unittest.TestCase):
    def test_reload_marks_sent_operations_unknown_even_before_guid_available(self):
        controller_runtime().execute('''db.pending.x={owner='original-owner',status='awaiting',total=100}
        api.owner=function()return 'realm:nil'end;ForeverFlip.Controller.new(db,api)
        assert(db.pending.x.status=='unknown')''')
    def test_replication_marks_verified_commodities_exact(self):
        l=runtime();l.execute((ROOT/'ForeverFlip/Adapters.lua').read_text(encoding='utf-8-sig'))
        l.execute('''C_AuctionHouse={GetReplicateItemInfo=function()return 'Cloth',1,10,1,true,1,'',0,0,100,0,nil,nil,'seller','seller',0,2589,true end,
        GetItemKeyInfo=function()return {isCommodity=true}end}
        local a=ForeverFlip.Adapters.native(ForeverFlip.Store.open(nil));local r=a.replicateRow(0)
        assert(r.complete and r.family==false and r.key.itemID==2589)''')

if __name__=='__main__':unittest.main()
