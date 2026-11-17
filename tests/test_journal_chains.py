"""T21: journal chains, purchase -> craft or disenchant -> sale.

Held units made into other items leave their lots at the position's cost; the products become lots
of their own that carry that cost, the journal logs the craft or disenchant with its chain, and the
lot history shows what the chain earned. Older entries and lots have no chain (no migration)."""

import re
import unittest

from test_addon import SETUP, run
from test_crafting import CRAFT


def clean(text):
    return re.sub(r'\|c[0-9a-fA-F]{8}|\|r', '', text)


BASE = SETUP + '''local F, D = ForeverFlip, ForeverFlip.Data
local c = D.char(F.db, F.Engine.owner())
local function lotOf(key)
    for _, lot in ipairs(D.lots(c)) do if lot.key == key then return lot end end
end
'''


class ConvertTests(unittest.TestCase):
    def test_the_products_carry_the_cost_and_the_sale_shows_the_chain_profit(self):
        run(BASE + '''D.addPosition(c, 'c:10', 'Linen Cloth', 5, 1000, 'flip', nil, now - 60)
        local chain = assert(D.convert(c, 'craft', { { key = 'c:10', qty = 2 } },
            { { key = 'c:50', name = 'Bolt of Linen Cloth', qty = 1 } }, now))
        assert(chain.cost == 400 and chain.inputs[1].qty == 2)
        local cloth = lotOf('c:10')
        assert(cloth.left == 3 and cloth.converted == 2 and cloth.convertedCost == 400 and cloth.sold == 0)
        assert(cloth.events[#cloth.events].kind == 'craft' and cloth.events[#cloth.events].chain == chain.id)
        assert(c.positions['c:10'].qty == 3 and c.positions['c:10'].cost == 600)
        local bolt = lotOf('c:50')
        assert(bolt.chain == chain.id and bolt.cost == 400 and bolt.left == 1)
        assert(c.positions['c:50'].cost == 400)
        assert(not c.stats['c:50'] or c.stats['c:50'].spent == 0, 'no purchase of the product')
        local e = c.journal[#c.journal]
        assert(e.kind == 'craft' and e.chain == chain.id and e.amount == 400 and e.key == 'c:10')
        local p = D.chainProfit(c, chain.id)
        assert(p.left == 1 and not p.done and p.profit == -400)
        D.sale(c, 'c:50', 'Bolt of Linen Cloth', 1, 900, now + 60)
        p = D.chainProfit(c, chain.id)
        assert(p.done and p.received == 900 and p.profit == 500, p.profit)''')

    def test_cost_is_shared_by_worth_and_nothing_joins_a_chain_lot(self):
        run(BASE + '''D.addPosition(c, 'c:40', 'Boots', 1, 3000, 'flip', nil, now - 60)
        local chain = assert(D.convert(c, 'disenchant', { { key = 'c:40', qty = 1 } }, {
            { key = 'c:1', qty = 2, value = 100 }, { key = 'c:2', qty = 1, value = 400 } }, now))
        assert(chain.outputs[1].cost == 1000 and chain.outputs[2].cost == 2000)
        D.addPosition(c, 'c:1', 'Dust', 3, 300, 'flip', nil, now + 30)
        local n = 0
        for _, lot in ipairs(D.lots(c)) do if lot.key == 'c:1' then n = n + 1 end end
        assert(n == 2, 'a purchase right after does not join the chain lot')''')

    def test_nothing_held_no_chain_and_old_lots_have_none(self):
        run(BASE + '''D.addPosition(c, 'c:10', 'Linen Cloth', 5, 1000, 'flip', nil, now - 60)
        assert(D.convert(c, 'craft', { { key = 'c:11', qty = 2 } }, { { key = 'c:50', qty = 1 } }, now) == nil)
        assert(c.chainSeq == nil and c.positions['c:10'].qty == 5)
        assert(D.chainProfit(c, nil) == nil and D.chainProfit(c, 7) == nil)
        local text = table.concat(F.UI.lotHistory(lotOf('c:10')), ' ## ')
        assert(not text:find('Chain'), text)''')

    def test_the_lot_history_shows_the_chain(self):
        text = clean(run(BASE + '''D.addPosition(c, 'c:10', 'Linen Cloth', 2, 1000, 'flip', nil, now - 60)
        D.convert(c, 'craft', { { key = 'c:10', qty = 2 } }, { { key = 'c:50', name = 'Bolt', qty = 1 } }, now)
        local closed = F.UI.lotRow(lotOf('c:10'))
        assert(closed.closed and closed.profit == 0, 'the cost went on with the chain')
        return table.concat(F.UI.lotHistory(lotOf('c:10')), ' ## ') .. ' || '
            .. table.concat(F.UI.lotHistory(lotOf('c:50')), ' ## ')'''))
        self.assertIn('Used in a craft', text)
        self.assertIn('Made by crafting', text)
        self.assertIn('Chain (craft): cost ', text)
        self.assertIn('(1 unsold)', text)


class HookTests(unittest.TestCase):
    def test_a_craft_of_a_saved_recipe_with_held_materials(self):
        run(CRAFT + '''fire('TRADE_SKILL_SHOW')
        local D = F.Data
        local c = D.char(F.db, F.Engine.owner())
        D.addPosition(c, 'c:10', 'Linen Cloth', 4, 800, 'flip', nil, F.Engine.clock() - 60)
        fire('UNIT_SPELLCAST_SUCCEEDED', 'player', 'g1', 2963)
        local e = c.journal[#c.journal]
        assert(e.kind == 'craft' and e.chain, tostring(e.kind))
        assert(c.positions['c:10'].qty == 2 and c.positions['c:50'].cost == 400)
        fire('UNIT_SPELLCAST_SUCCEEDED', 'player', 'g2', 999)
        assert(c.journal[#c.journal] == e, 'another spell is no craft')''')

    def test_a_craft_without_held_materials_is_not_a_chain(self):
        run(CRAFT + '''fire('TRADE_SKILL_SHOW')
        local c = F.Data.char(F.db, F.Engine.owner())
        fire('UNIT_SPELLCAST_SUCCEEDED', 'player', 'g1', 2963)
        assert(not c.chains and not c.positions['c:50'])''')

    def test_a_disenchant_of_a_held_item(self):
        run(SETUP + '''local F = ForeverFlip
        local DE = F.Disenchant
        local info = F.Util.itemInfo
        addItem(41, 'Green Blade', 100, 'commodity')
        addItem(10939, 'Greater Magic Essence', 0, 'commodity')
        F.Util.itemInfo = function(id)
            if id == 41 then return 'Green Blade', nil, 2, 25, 20, '', '', 1, '', 0, 100, 2 end
            return info(id)
        end
        function GetNumLootItems() return 1 end
        function GetLootSlotLink() return '|Hitem:10939:|h[Greater Magic Essence]|h' end
        function GetLootSlotInfo() return 0, 'x', 2 end
        bags[0] = { [7] = { itemID = 41, stackCount = 1, isLocked = true, hyperlink = link(41) } }
        local c = F.Data.char(F.db, F.Engine.owner())
        local key = F.AH.keyFor(41, link(41))
        F.Data.addPosition(c, key, 'Green Blade', 1, 5000, 'flip', nil, F.Engine.clock() - 60)
        fire('UNIT_SPELLCAST_START', 'player', 'g1', DE.SPELL)
        fire('UNIT_SPELLCAST_SUCCEEDED', 'player', 'g1', DE.SPELL)
        fire('LOOT_OPENED')
        local e = c.journal[#c.journal]
        assert(e.kind == 'disenchant' and e.chain and e.amount == 5000, tostring(e.kind))
        local p = c.positions[F.AH.keyFor(10939)]
        assert(p and p.qty == 2 and p.cost == 5000 and not c.positions[key])''')


if __name__ == '__main__':
    unittest.main()
