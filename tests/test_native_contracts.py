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
    def test_replicated_gear_is_keyed_by_its_full_name(self):
        l=runtime();l.execute((ROOT/'ForeverFlip/Adapters.lua').read_text(encoding='utf-8-sig'))
        l.execute('''local name='Northern Shortsword of Healing'
        C_AuctionHouse={GetReplicateItemInfo=function()return name,1,1,2,true,1,'',0,0,800,0,nil,nil,'s','s',0,2078,true end,
        GetReplicateItemLink=function()return '|cnIQ2:|Hitem:2078::::::::22:1484::1:1:12920:1:28:5240:::::|h['..name..']|h|r' end,
        GetItemKeyInfo=function()return {isCommodity=false,isEquipment=true}end}
        local a=ForeverFlip.Adapters.native(ForeverFlip.Store.open(nil));local U=ForeverFlip.Util
        local healing=a.replicateRow(0).key;name='Northern Shortsword of Nature Protection'
        local nature=a.replicateRow(1).key
        assert(healing.itemSuffix<0 and U.key(healing)~=U.key(nature) and r==nil)''')

if __name__=='__main__':unittest.main()
