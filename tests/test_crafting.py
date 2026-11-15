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

    def test_shopping_limit_uses_the_same_material_cost_as_profit(self):
        run(CRAFT + '''F.Crafting.rememberMerchantPrice(10,10)
        fire('TRADE_SKILL_SHOW');local p=F.Crafting.profits()[1]
        assert(F.Crafting.shopMaterials(2963,1)==1)
        local e=F.Shopping.entry('c:10')
        assert(e.max*e.qty==p.cost,'shopping must not spend above the recipe material estimate')''')

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

    def test_learned_professions_button_shows_known_ranks(self):
        run(CRAFT + '''GetProfessions=function() return 171,164 end
        GetProfessionInfo=function(id) if id==171 then return 'Alchemy',nil,225,300 end return 'Tailoring',nil,150,225 end
        local UI=F.UI;UI.show('crafting');UI.craftProfButton:Click()
        local t=UI.craftProfText.full()
        assert(t:find('Alchemy') and t:find('225/300') and t:find('Tailoring') and t:find('150/225'),t)''')

    def test_every_profession_line_is_reachable(self):
        run(CRAFT + '''GetProfessions=function() return 171,164,333,185,129,356 end
        GetProfessionInfo=function(id) return 'P'..id,nil,100,225 end
        local UI=F.UI;UI.show('crafting');UI.craftProfButton:Click()
        local box=UI.craftProfText
        assert(#box.lines==7,'one heading and six professions: '..#box.lines)
        box.bar.forward:Click()
        assert(box.rowTexts[1]:GetText()==box.lines[2],'the list scrolls, no line runs off the window')''')


UNLEARNED = SETUP + '''local F=ForeverFlip
addItem(50,'Bolt of Linen Cloth',100,'commodity')
addItem(2840,'Copper Bar',100,'commodity')
for i=1,3 do addAuction(50,900,5);addAuction(2840,900,5) end
C_TradeSkillUI={
  GetAllRecipeIDs=function() return {2963,2657} end,
  GetRecipeSchematic=function(id) if id==2963 then return {name='Bolt of Linen Cloth',outputItemID=50,quantityMin=1,
    reagentSlotSchematics={{quantityRequired=2,reagents={{itemID=10}}}}} end
    return {name='Smelt Copper',outputItemID=2840,quantityMin=1,
      reagentSlotSchematics={{quantityRequired=1,reagents={{itemID=11}}}}} end,
  GetRecipeInfo=function(id) return {recipeID=id,learned=(id==2963)} end,
}
fullScan()
'''


class UnlearnedRecipeTests(unittest.TestCase):
    def test_the_flag_is_read_from_the_game(self):
        run(UNLEARNED + '''fire('TRADE_SKILL_SHOW')
        local c=F.Data.char(F.db,F.Engine.owner())
        assert(c.recipes[2963].learned==true and c.recipes[2657].learned==false)''')

    def test_both_are_profitable_so_only_the_flag_separates_them(self):
        run(UNLEARNED + '''fire('TRADE_SKILL_SHOW')
        assert(#F.Crafting.profits()==2,'off by default: both recipes are listed')''')

    def test_the_setting_leaves_the_unlearned_recipe_out(self):
        run(UNLEARNED + '''fire('TRADE_SKILL_SHOW');F.db.settings.hideUnlearned=true
        local p=F.Crafting.profits()
        assert(#p==1 and p[1].name=='Bolt of Linen Cloth',#p)''')

    def test_the_button_toggles_it_and_shows_the_count(self):
        run(UNLEARNED + '''fire('TRADE_SKILL_SHOW');local UI=F.UI;UI.show('crafting')
        local function listed(id)
          for _,r in ipairs(UI.craftTable.rows) do
            if type(r.recipe)=='table' and r.recipe.id==id then return true end
          end
          return false
        end
        assert(UI.craftHideButton:GetText()=='All recipes (1)',UI.craftHideButton:GetText())
        assert(listed(2657),'off by default: the unlearned recipe is listed')
        UI.craftHideButton:Click()
        assert(F.db.settings.hideUnlearned==true)
        assert(not listed(2657),'the unlearned row is gone')
        assert(listed(2963),'the learned one stays')
        assert(UI.craftHideButton:GetText()=='Learned recipes only (1)',UI.craftHideButton:GetText())
        UI.craftHideButton:Click()
        assert(listed(2657) and UI.craftHideButton:GetText()=='All recipes (1)')''')

    def test_a_recipe_saved_before_the_flag_counts_as_learned(self):
        run(UNLEARNED + '''fire('TRADE_SKILL_SHOW');F.db.settings.hideUnlearned=true
        local c=F.Data.char(F.db,F.Engine.owner());c.recipes[2657].learned=nil
        assert(#F.Crafting.profits()==2,'only a known "no" hides a recipe')''')

    def test_an_unlearned_recipe_is_marked_when_it_is_listed(self):
        run(UNLEARNED + '''fire('TRADE_SKILL_SHOW');local UI=F.UI;UI.show('crafting')
        local marked
        for _,r in ipairs(UI.craftTable.rows) do
          if type(r.recipe)=='table' and r.recipe.id==2657 then marked=r.name:GetText() end
        end
        assert(marked and marked:find('(not learned)',1,true),marked)''')

    def test_hiding_everything_says_so(self):
        run(UNLEARNED + '''fire('TRADE_SKILL_SHOW');F.db.settings.hideUnlearned=true
        local c=F.Data.char(F.db,F.Engine.owner());c.recipes[2963].learned=false
        local UI=F.UI;UI.show('crafting')
        assert(UI.craftTable.empty:IsShown())
        assert(UI.craftTable.empty:GetText():find('has not learned',1,true),UI.craftTable.empty:GetText())''')


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



class SpellBookLearnedTests(unittest.TestCase):
    """WoW Forever's GetRecipeInfo gives no learned flag: the spell book answers instead."""

    NO_FLAG = UNLEARNED + """C_TradeSkillUI.GetRecipeInfo=function(id) return {recipeID=id} end
"""

    def test_the_spell_book_hides_a_recipe_the_character_does_not_know(self):
        run(self.NO_FLAG + """C_SpellBook={IsSpellKnown=function(id) return id==2963 end}
        fire('TRADE_SKILL_SHOW');F.db.settings.hideUnlearned=true
        local p=F.Crafting.profits()
        assert(#p==1 and p[1].name=='Bolt of Linen Cloth',#p)
        assert(F.Crafting.unlearnedCount()==1)""")

    def test_a_recipe_saved_without_the_flag_is_answered_by_the_spell_book(self):
        run(self.NO_FLAG + """fire('TRADE_SKILL_SHOW')
        local c=F.Data.char(F.db,F.Engine.owner())
        assert(c.recipes[2657].learned==nil,'no answer without the spell book')
        C_SpellBook={IsSpellKnown=function(id) return id==2963 end}
        F.db.settings.hideUnlearned=true
        assert(#F.Crafting.profits()==1,'hidden without reopening the profession window')""")

    def test_a_spell_book_that_knows_none_of_them_is_not_believed(self):
        run(self.NO_FLAG + """C_SpellBook={IsSpellKnown=function() return false end}
        fire('TRADE_SKILL_SHOW');F.db.settings.hideUnlearned=true
        assert(#F.Crafting.profits()==2,'IDs that are not spells hide nothing')""")



class CraftPlanTests(unittest.TestCase):
    """Crafting.plan: how many crafts pay, and up to what price each material is bought."""

    # A product that brings 755 a craft and sells 100 a day; two Linen Cloth a craft, listed in
    # three lots: 6 at 100, 4 at 200, 10 at 400.
    PLAN = CRAFT + r"""fire('TRADE_SKILL_SHOW')
    local profits = F.Crafting.profits
    F.Crafting.profits = function(all)
        local out = profits(all)
        for _, row in ipairs(out) do row.value, row.perDay, row.route = 755, 100, 'auction' end
        return out
    end
    F.Trade.prices['c:10'] = { rows = { { unit = 100, qty = 6 }, { unit = 200, qty = 4 }, { unit = 400, qty = 10 } }, at = F.Engine.clock() }
    """

    def test_crafts_stop_where_the_next_lots_no_longer_pay(self):
        run(self.PLAN + """local plan = F.Crafting.plan(2963)
        -- 2 x 400 = 800 a craft leaves less than 5% of 755: the dear lot is not bought.
        assert(plan.crafts == 5 and plan.limit == 'price', plan.crafts .. ' ' .. plan.limit)
        local m = plan.materials[1]
        assert(m.buy == 10 and m.maxPrice == 200 and m.spend == 6 * 100 + 4 * 200, m.buy .. ' ' .. tostring(m.maxPrice))
        assert(plan.profit == 5 * 755 - 1400, plan.profit)""")

    def test_the_money_on_hand_limits_the_plan(self):
        run(self.PLAN + """money = 1000 -- 80% may be spent: 800
        local plan = F.Crafting.plan(2963)
        assert(plan.crafts == 3 and plan.limit == 'money' and plan.spend == 600, plan.crafts .. ' ' .. plan.limit)""")

    def test_materials_in_the_bags_are_used_first(self):
        run(self.PLAN + """putBag(0, 1, 10, 4)
        local plan = F.Crafting.plan(2963)
        local m = plan.materials[1]
        assert(m.held == 4 and m.buy == plan.crafts * 2 - 4, m.held .. ' ' .. m.buy)""")

    def test_the_sales_cap_the_crafts(self):
        run(self.PLAN + """F.Crafting.profits = (function(inner) return function(all)
            local out = inner(all); for _, row in ipairs(out) do row.perDay = 2 end; return out end end)(F.Crafting.profits)
        local plan = F.Crafting.plan(2963)
        assert(plan.crafts == 2 and plan.limit == 'sales', plan.crafts .. ' ' .. plan.limit)""")

    def test_a_day_of_crafts_divides_by_the_units_made(self):
        run(self.PLAN + """F.Data.char(F.db, F.Engine.owner()).recipes[2963].n = 5
        F.Crafting.profits = (function(inner) return function(all)
            local out = inner(all); for _, row in ipairs(out) do row.perDay = 10 end; return out end end)(F.Crafting.profits)
        local plan = F.Crafting.plan(2963)
        assert(plan.crafts == 2 and plan.limit == 'sales', 'ten a day of a recipe that makes five: ' .. plan.crafts)""")

    def test_shop_materials_puts_the_plan_on_the_list(self):
        run(self.PLAN + """local n = F.Crafting.shopMaterials(2963)
        local e = F.Shopping.entry('c:10')
        assert(n == 1 and e.qty == 10 and e.max == 200, tostring(e and e.qty) .. ' ' .. tostring(e and e.max))""")

    def test_the_page_shows_the_plan(self):
        run(self.PLAN + """local UI = F.UI; UI.show('crafting'); UI.craftTable.rows[1]:Click(); UI.refresh()
        local t = UI.craftProfText.full()
        assert(t:find('5 crafts', 1, true) and t:find('buy 10', 1, true), t)
        UI.craftShop:Click()
        assert(F.Engine.message == 'craft_saved', tostring(F.Engine.message))""")


if __name__ == '__main__':
    unittest.main()
