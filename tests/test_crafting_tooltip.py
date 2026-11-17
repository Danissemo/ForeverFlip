"""T16: the Crafting row hover in the look of ForeverFlip's item tooltips.

Before, a recipe row listed its table columns again under the name (Materials, Product, Profit,
Est./day, Sell to). Now it has the ForeverFlip header, a Materials section (each material, its
price for the craft and where it is bought), a Product section (what it sells for, how fast) and
the profit of one craft, money through U.money, each figure once."""

import re
import unittest

from test_addon import run
from test_crafting import CRAFT


def clean(text):
    return re.sub(r'\|c[0-9a-fA-F]{8}|\|r', '', text)


HOVER = CRAFT + '''fire('TRADE_SKILL_SHOW');local UI=F.UI;UI.show('crafting')
local function hover()
    tooltipLines={}
    local r=UI.craftTable.rows[1]
    r.scripts.OnEnter(r)
    return GameTooltip:GetText()..' ## '..table.concat(tooltipLines,' ## ')
end
'''


class CraftTooltipTests(unittest.TestCase):
    def test_the_hover_has_the_header_and_sections(self):
        text = clean(run(HOVER + 'return hover()'))
        self.assertTrue(text.startswith('Bolt of Linen Cloth ## ForeverFlip  Crafting'), text)
        for part in ('Materials', '2 x Linen Cloth (auction) = ', 'Materials of one craft = ', 'Product',
                     '1 x Bolt of Linen Cloth', 'Sells for (after the cut and the deposit) = ',
                     'Bought a day = ', 'Profit per craft = ',
                     "Material prices: the cheaper of the usual auction price and a merchant's price."):
            self.assertIn(part, text)

    def test_the_figures_are_the_rows_and_are_not_repeated(self):
        text = clean(run(HOVER + '''local e=UI.craftTable.rows[1].recipe
        local U=F.Util
        assert(e.reagents and e.reagents[1][1]==10)
        local t=hover()
        assert(t:find(U.money(e.cost),1,true) and t:find(U.money(e.value),1,true))
        return t'''))
        # The old hover repeated the table columns by their header names.
        for column in ('Est./day =', 'Sell to =', 'Product = '):
            self.assertNotIn(column, text)

    def test_a_merchant_material_and_a_missing_price(self):
        text = clean(run(HOVER + '''F.Crafting.rememberMerchantPrice(10,10);UI.refresh()
        return hover()'''))
        self.assertIn('2 x Linen Cloth (merchant) = 20c', text)
        text = clean(run(CRAFT + '''C_TradeSkillUI.GetRecipeSchematic=function() return {name='X',outputItemID=50,quantityMin=1,
          reagentSlotSchematics={{quantityRequired=1,reagents={{itemID=51}}}}} end
        fire('TRADE_SKILL_SHOW');local UI=F.UI;UI.show('crafting')
        tooltipLines={};local r=UI.craftTable.rows[1];r.scripts.OnEnter(r)
        return table.concat(tooltipLines,' ## ')'''))
        self.assertIn('1 x Coarse Thread = no price', text)
        self.assertIn('has no price yet', text)
        self.assertNotIn('Profit per craft', text)


if __name__ == '__main__':
    unittest.main()
