"""Review fixes: analytics (stock, market lists, lost most), crafting and disenchant learning."""

import unittest

from test_addon import SETUP, run, runtime

# Linen Cloth (c:10) is shared by two recipes: a bolt takes 2, a bandage 1.
CRAFT = SETUP + '''local F=ForeverFlip
addItem(50,'Bolt of Linen Cloth',100,'commodity')
addItem(52,'Linen Bandage',5,'commodity')
for i=1,4 do addAuction(50,900,5) end
C_TradeSkillUI={
  GetAllRecipeIDs=function() return {2963,3275} end,
  GetRecipeSchematic=function(id)
    if id==2963 then return {name='Bolt of Linen Cloth',outputItemID=50,quantityMin=1,
      reagentSlotSchematics={{required=true,quantityRequired=2,reagents={{itemID=10}}}}} end
    return {name='Linen Bandage',outputItemID=52,quantityMin=1,
      reagentSlotSchematics={{required=true,quantityRequired=1,reagents={{itemID=10}}}}}
  end,
}
fullScan();fire('TRADE_SKILL_SHOW')
'''


class CraftingReviewTests(unittest.TestCase):
    def test_professions_after_an_unlearned_slot_are_listed(self):
        run('''local names={[171]='Alchemy',[164]='Blacksmithing',[356]='Fishing',[185]='Cooking',[129]='First Aid'}
        GetProfessionInfo=function(id) return names[id],nil,100,300 end
        local function listed()
            local out={}
            for _,p in ipairs(ForeverFlip.Crafting.professions()) do out[#out+1]=p.name end
            return table.concat(out,',')
        end
        GetProfessions=function() return 171,164,nil,356,185,129 end
        assert(listed()=='Alchemy,Blacksmithing,Fishing,Cooking,First Aid',listed())
        GetProfessions=function() return nil,nil,nil,nil,185,nil end
        assert(listed()=='Cooking',listed())''')

    def test_gear_product_is_priced_at_its_auction_price_and_checked(self):
        run(SETUP + '''local F=ForeverFlip
        addItem(70,'Heavy Copper Broadsword',500,'gear')
        for i=1,6 do addAuction(70,50000,1,'Seller'..i) end
        C_TradeSkillUI={
          GetAllRecipeIDs=function() return {3292} end,
          GetRecipeSchematic=function() return {name='Heavy Copper Broadsword',outputItemID=70,quantityMin=1,
            reagentSlotSchematics={{required=true,quantityRequired=2,reagents={{itemID=10}}}}} end,
        }
        fullScan();fire('TRADE_SKILL_SHOW')
        local key=F.AH.keyFor(70);assert(key=='g:70:heavy copper broadsword',key)
        local usual=F.Market.usual(F.Data.market(F.db,F.Engine.scope()).history[key]);assert(usual,'scanned')
        local p=F.Crafting.profits()[1]
        assert(p.route=='auction' and p.value==F.Market.net(usual,1)-F.Market.postDeposit(70,'gear',1),
          tostring(p.route)..' '..tostring(p.value))
        local keys=table.concat(F.Crafting.keys(),',')
        assert(keys:find(key,1,true),'Check all on Crafting searches the product: '..keys)''')

    def test_shop_materials_widens_an_entry_already_on_the_list(self):
        run(CRAFT + '''local C,Sh=F.Crafting,F.Shopping
        local unit=C.materialCost(F.Data.market(F.db,F.Engine.scope()).history,10)
        assert(C.shopMaterials(2963,3)==1 and Sh.entry('c:10').qty==6 and Sh.entry('c:10').max==math.floor(unit))
        C.shopMaterials(3275,2)
        assert(Sh.entry('c:10').qty==6,'another recipe keeps the larger quantity: '..tostring(Sh.entry('c:10').qty))
        C.shopMaterials(2963,3)
        assert(Sh.entry('c:10').qty==6,'the same click again does not grow the entry')
        Sh.add('c:10',80,nil,'Linen Cloth')
        assert(C.shopMaterials(2963,1)==1)
        local e=Sh.entry('c:10')
        assert(e.qty==nil and e.max==80,'the player\\'s "any quantity up to 80c" stays: '..tostring(e.qty)..' '..tostring(e.max))
        Sh.add('c:10',40,20,'Linen Cloth')
        C.shopMaterials(2963,1);e=Sh.entry('c:10')
        assert(e.qty==20 and e.max==math.floor(unit),'the materials can be bought at their current cost')''')


class DisenchantReviewTests(unittest.TestCase):
    CASE = '''local F=ForeverFlip
    local DE=F.Disenchant
    local info=F.Util.itemInfo
    F.Util.itemInfo=function(id)
      if id==40 then return 'Green Boots',nil,2,33,28,'','',1,'',0,100,4 end -- armor, band 2:a:35
      if id==41 then return 'Green Blade',nil,2,25,20,'','',1,'',0,100,2 end -- weapon, band 2:w:25
      return info(id)
    end
    addItem(10,'Linen Cloth',13,'commodity')
    function GetNumLootItems() return 1 end
    function GetLootSlotLink() return '|Hitem:10939:|h[Greater Magic Essence]|h' end
    function GetLootSlotInfo() return 0,'x',2 end
    bags[0]={[7]={itemID=41,stackCount=1,isLocked=true}} -- the blade is disenchanted
    %s
    fire('UNIT_SPELLCAST_START','player','g1',DE.SPELL)
    fire('UNIT_SPELLCAST_SUCCEEDED','player','g1',DE.SPELL)
    fire('LOOT_OPENED')
    local out={}
    for band,t in pairs(F.db.deSeen) do out[#out+1]=band..'='..t.n end
    table.sort(out)
    return table.concat(out,',')
    '''

    def learned(self, other):
        return runtime().execute(self.CASE % other)

    def test_another_locked_disenchantable_item_learns_nothing(self):
        # Boots attached to an unsent mail, earlier in the bags than the blade.
        self.assertEqual(self.learned("bags[0][3]={itemID=40,stackCount=1,isLocked=true}"), '')

    def test_a_locked_item_that_cannot_be_disenchanted_is_not_the_target(self):
        self.assertEqual(self.learned("bags[0][3]={itemID=10,stackCount=20,isLocked=true}"), '2:w:25=1')
        self.assertEqual(self.learned(''), '2:w:25=1')


class AnalyticsReviewTests(unittest.TestCase):
    def test_shopping_and_disenchant_purchases_are_not_stock_to_sell(self):
        run(SETUP + '''local F=ForeverFlip;local c=F.Data.char(F.db,F.Engine.owner());local day=86400
        F.Data.addPosition(c,'c:10','Linen Cloth',20,2000,'shop',100,now-4*day,nil,'addon')
        F.Data.addPosition(c,'g:20:northern shortsword of healing','Northern Shortsword of Healing',1,800,
          'disenchant',1500,now-4*day,nil,'addon')
        F.Data.addPosition(c,'i:30','Linen Bag',1,700,'flip',30000,now-4*day,nil,'addon')
        local r=F.Analytics.results(7,now)
        assert(r.held==700 and r.stale==700,r.held..' '..r.stale)
        local realm=F.Analytics.realm(7,now);assert(realm.stock==700,realm.stock)''')

    # Silk keeps the house large enough that a scan without the wool is no partial answer (Scan.isShort).
    MARKET = SETUP + '''local F=ForeverFlip;local A=F.Analytics
    addItem(41,'Silk Cloth',0,'commodity')
    for i=1,30 do addAuction(41,200,1) end
    addItem(40,'Wool Cloth',0,'commodity')
    addAuction(40,50,2)
    local wall={}
    for i=1,6 do wall[i]=addAuction(40,100,5) end
    fullScan()
    now=now+3600;F.db.lastScan=0
    for i=#auctions,1,-1 do if auctions[i]==wall[1] then table.remove(auctions,i) end end
    fullScan()
    local function find(list) for _,r in ipairs(list or {}) do if r.key=='c:40' then return r end end end
    local m=A.market()
    assert(find(m.gaps) and find(m.gaps).cheap==50 and find(m.liquid),'listed today: a bargain that sells')
    '''

    def test_item_the_last_scan_did_not_list_leaves_the_market_lists(self):
        run(self.MARKET + '''-- All of it bought out: the next full scan does not list it.
        now=now+3600;F.db.lastScan=0
        for i=#auctions,1,-1 do if auctions[i].item==40 then table.remove(auctions,i) end end
        local before=time();fullScan()
        assert(F.Scan.last.at>=before,'the scan was used')
        assert(F.Data.market(F.db,F.Engine.scope()).history['c:40'],'kept in the history for 14 days')
        m=A.market()
        assert(not find(m.gaps) and not find(m.liquid) and not find(m.falling) and not find(m.rising))''')

    def test_cheapest_today_is_not_an_earlier_days_price(self):
        run(self.MARKET + '''now=now+86400;A.invalidate();m=A.market(now)
        assert(not find(m.gaps),'no scan today: no cheapest today')
        assert(find(m.liquid) and find(m.liquid).cheap==nil,'still listed by the last scan')''')

    def test_deposits_lost_without_stock_count_in_lost_most(self):
        # Data.addCost books such a loss straight into the item's profit and the journal entry
        # carries it as its (negative) profit; a loss on stock joins the stock's cost instead.
        run(SETUP + '''local F=ForeverFlip;local D=F.Data;local c=D.char(F.db,F.Engine.owner())
        -- A looted bag posted twice that expired, and a cancelled post of looted wool.
        for i=1,2 do
            D.log(c,{at=now,kind='expired',key='i:30',name='Linen Bag',qty=1,lossQty=1,amount=100,profit=-100})
        end
        D.log(c,{at=now,kind='cancel',key='c:40',name='Wool Cloth',qty=1,amount=70,profit=-70})
        -- Bought cloth whose expired deposit joined the stock's cost: its sale counts it.
        D.addPosition(c,'c:10','Linen Cloth',5,300,'flip',100,now)
        D.addCost(c,'c:10',50,now,5)
        D.log(c,{at=now,kind='expired',key='c:10',name='Linen Cloth',qty=5,lossQty=5,amount=50})
        local r=F.Analytics.results(7,now)
        local worst={}
        for _,item in ipairs(r.worst) do worst[#worst+1]=item.key..'='..item.profit end
        worst=table.concat(worst,',')
        assert(worst=='i:30=-200,c:40=-70',worst)''')


if __name__ == '__main__':
    unittest.main()
