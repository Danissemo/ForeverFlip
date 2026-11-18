"""The profession book's Disenchant bought button: one item bought on the Disenchant page a click,
as many of each as are held, never in combat or while a cast is running."""

import unittest

from test_addon import run
from test_disenchant_retail import RETAIL

BOOK = RETAIL + '''DE.canDisenchant = function() return true end
gear[50] = { 2, 197, 4, 11 }
gear[51] = { 2, 197, 4, 11 }
local c = F.Data.char(F.db, F.Engine.owner())
addItem(10, 'Linen Cloth', 100, 'commodity'); addItem(50, 'Gear 50', 100, 'gear'); addItem(51, 'Gear 51', 100, 'gear')
putBag(0, 1, 10, 5)
putBag(0, 2, 50, 1); putBag(0, 3, 50, 1); putBag(1, 4, 51, 1)
c.positions[F.AH.keyFor(50, bags[0][2].hyperlink)] = { qty = 1, cost = 100, mode = 'disenchant' }
c.positions[F.AH.keyFor(51, bags[1][4].hyperlink)] = { qty = 1, cost = 100, mode = 'flip' }
ProfessionsBookFrame = CreateFrame('Frame')
fire('ADDON_LOADED', 'Blizzard_ProfessionsBook')
local b = F.UI.deButton
assert(b, 'the button is made when the book loads')
'''


class DisenchantButtonTests(unittest.TestCase):
    def test_only_what_was_bought_to_disenchant_is_queued(self):
        run(BOOK + '''local q = DE.queue()
        assert(#q == 1 and q[1].bag == 0 and q[1].slot == 2, 'one held, the flip and the cloth stay')
        assert(b:GetText() == 'Disenchant bought (1)', b:GetText())''')

    def test_a_click_casts_disenchant_on_the_next_item(self):
        run(BOOK + '''b.scripts.PreClick(b)
        assert(b:GetAttribute('type') == 'spell' and b:GetAttribute('spell') == DE.SPELL)
        assert(b:GetAttribute('target-bag') == 0 and b:GetAttribute('target-slot') == 2)
        assert(b.scripts.OnClick == nil, 'the secure template keeps its own click')''')

    def test_the_press_reaches_the_secure_click(self):
        # With ActionButtonUseKeyDown on, the game's default, the secure click acts on the press;
        # a button registered for the release only did nothing in the game.
        run(BOOK + '''local got = table.concat(b.clicks or {}, ',')
        assert(got:find('AnyDown') and got:find('AnyUp'), got)''')

    def test_nothing_is_cast_while_busy_or_when_empty(self):
        run(BOOK + '''UnitCastingInfo = function() return 'Disenchant' end
        b.scripts.PreClick(b)
        assert(b:GetAttribute('type') == nil, 'a running cast: the click does nothing')
        UnitCastingInfo = function() return nil end
        bags[0][2] = nil; bags[0][3] = nil
        b.scripts.PreClick(b)
        assert(b:GetAttribute('type') == nil and b:GetAttribute('target-slot') == nil, 'nothing left')''')

    def test_combat_leaves_the_button_alone(self):
        run(BOOK + '''InCombatLockdown = function() return true end
        b.scripts.PreClick(b)
        assert(b:GetAttribute('type') == nil, 'no attribute is set in combat')''')

    def test_hidden_for_a_character_without_disenchant(self):
        run(BOOK + '''DE.canDisenchant = function() return false end
        F.UI.updateDisenchantButton()
        assert(not b.shown)
        DE.canDisenchant = function() return true end
        F.UI.deWatch.scripts.OnUpdate(F.UI.deWatch, 1)
        assert(b.shown, 'shown again once learned, by the watcher')''')


if __name__ == '__main__':
    unittest.main()
