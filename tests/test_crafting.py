"""Crafting profits from saved recipes and disenchant deals."""

import unittest

from test_addon import SETUP, run

CRAFT = SETUP + '''local F=ForeverFlip
addItem(50,'Bolt of Linen Cloth',100,'commodity')
addItem(51,'Coarse Thread',5,'commodity')
for i=1,4 do addAuction(50,900,5) end
C_TradeSkillUI={
  GetAllRecipeIDs=function() return {2963} end,
  GetRecipeSchematic=function(id) return {name='Bolt of Linen Cloth',outputItemID=50,quantityMin=1,
    reagentSlotSchematics={{required=true,quantityRequired=2,reagents={{itemID=10}}}}} end,
}
fullScan()
'''


class CraftingTests(unittest.TestCase):
    def test_recipes_are_learned_when_the_profession_window_opens(self):
        run(CRAFT + '''fire('TRADE_SKILL_SHOW')
        local c=F.Data.char(F.db,F.Engine.owner());local r=c.recipes[2963]
        assert(r and r.out==50 and r.r[1][1]==10 and r.r[1][2]==2)''')

    def test_profit_uses_material_and_product_prices(self):
        run(CRAFT + '''fire('TRADE_SKILL_SHOW')
        local p=F.Crafting.profits()[1]
        local cloth=F.Data.market(F.db,F.Engine.scope()).history['c:10'].scan.market
        local bolt=F.Data.market(F.db,F.Engine.scope()).history['c:50'].scan.market
        assert(p.cost==2*cloth,p.cost)
        assert(p.value==F.Market.net(bolt,1)-F.Market.deposit(100,1) and p.route=='auction')
        assert(p.profit==p.value-p.cost)''')

    def test_merchant_price_is_used_when_cheaper(self):
        run(CRAFT + '''F.Crafting.rememberMerchantPrice(10,10)
        fire('TRADE_SKILL_SHOW');assert(F.Crafting.profits()[1].cost==20)''')

    def test_missing_material_price_is_reported(self):
        run(CRAFT + '''C_TradeSkillUI.GetRecipeSchematic=function() return {name='X',outputItemID=50,quantityMin=1,
          reagentSlotSchematics={{quantityRequired=1,reagents={{itemID=51}}}}} end
        fire('TRADE_SKILL_SHOW');assert(F.Crafting.profits()[1].missing==51)''')

    def test_shop_materials_fills_the_shopping_list(self):
        run(CRAFT + '''fire('TRADE_SKILL_SHOW');assert(F.Crafting.shopMaterials(2963,3)==1)
        local e=F.Shopping.entry('c:10');assert(e and e.qty==6)''')

    def test_crafting_page_lists_the_recipe(self):
        run(CRAFT + '''fire('TRADE_SKILL_SHOW');local UI=F.UI;UI.show('crafting')
        assert(UI.craftTable.rows[1].recipe and UI.craftTable.rows[1].name:GetText()=='Bolt of Linen Cloth')
        UI.craftTable.rows[1]:Click();assert(UI.craftShop:IsEnabled())''')


DE = SETUP + '''local F=ForeverFlip
local DE=F.Disenchant
function IsPlayerSpell(id) return id==13262 end
addItem(10940,'Strange Dust',0,'commodity');addItem(10938,'Lesser Magic Essence',0,'commodity')
for i=1,3 do addAuction(10940,2000,10);addAuction(10938,5000,5) end
-- a level 12 green armor piece
addItem(60,'Rough Boots',50,'gear')
C_Item.GetItemInfo=function(id) local it=items[id];if not it then return nil end
  return it.name,link(id),id==60 and 2 or 1,id==60 and 12 or 1,1,'','',1,'',134400,it.vendor,id==60 and 4 or 7 end
addAuction(60,400,1,'Seller','Rough Boots');addAuction(60,9000,1,'Seller','Rough Boots')
'''


class DisenchantTests(unittest.TestCase):
    def test_outcome_table(self):
        run('''local DE=ForeverFlip.Disenchant
        local o=DE.outcomes(2,12,4);assert(o[1][1]==10940 and math.abs(o[1][2]-1.2)<1e-9 and o[2][1]==10938)
        local w=DE.outcomes(2,12,2);assert(math.abs(w[1][2]-0.3)<1e-9,'weapons give essence more often')
        assert(DE.outcomes(3,60,4)[2][1]==20725 and DE.outcomes(2,12,7)==nil and DE.outcomes(4,60,4)==nil)''')

    def test_cheap_green_is_a_disenchant_deal(self):
        run(DE + '''fullScan();local v=DE.value(60);assert(v and v>1000,v)
        local d=F.Deals.get('g:60:rough boots');assert(d and d.mode=='disenchant' and d.qty==1 and d.cost==400,d and d.mode)''')

    def test_no_disenchant_deal_without_the_skill(self):
        run(DE + '''function IsPlayerSpell() return false end;fullScan()
        local d=F.Deals.get('g:60:rough boots');assert(not d or d.mode~='disenchant')''')


if __name__ == '__main__':
    unittest.main()
