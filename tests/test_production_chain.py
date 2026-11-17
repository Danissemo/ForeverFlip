"""T31: the production chain of an item in its tooltip.

The tooltip compares what one unit brings by each route: the auction house after the cut (with
Sure), a vendor, disenchanting it into materials and crafting it into a learned recipe's product.
The best route is marked and the others follow in one short line each; with no figure for any
route the tooltip says so. The comparison is kept per item until new scan data come."""

import re
import unittest

from test_addon import SETUP, run
from test_crafting import CRAFT


def clean(text):
    return re.sub(r'\|c[0-9a-fA-F]{8}|\|r', '', text)


PURE = SETUP + '''local M = ForeverFlip.Market
'''

TIP = '''
tooltipLines = {}
GameTooltip.itemLink = link(10)
for _, fn in ipairs(tooltipCalls) do fn(GameTooltip) end
return table.concat(tooltipLines, ' ## ')'''


class RoutesTests(unittest.TestCase):
    def test_the_routes_best_first(self):
        run(PURE + '''local c = M.chainRoutes({ auction = 900, sure = 0.7, vendor = 300, disenchant = 1200,
            craft = { value = 1000.4, name = 'Bolt' } })
        assert(c.best == 'disenchant' and #c.routes == 4)
        assert(c.routes[2].route == 'craft' and c.routes[2].value == 1000 and c.routes[2].name == 'Bolt')
        assert(c.routes[3].route == 'auction' and c.routes[3].sure == 0.7)
        assert(c.routes[4].route == 'vendor')''')

    def test_no_figure_is_no_chain(self):
        run(PURE + '''assert(M.chainRoutes({}) == nil and M.chainRoutes(nil) == nil)
        assert(M.chainRoutes({ auction = 0, vendor = -5, craft = { value = 0 } }) == nil)
        local c = M.chainRoutes({ vendor = 40 })
        assert(c.best == 'vendor' and #c.routes == 1)''')

    def test_the_craft_value_of_one_material(self):
        run(PURE + '''local row = { value = 1000, cost = 700, reagents = { { 10, 2 }, { 11, 1 } } }
        -- two units of 10 at 200 each, the other material 300: (1000 - 300) / 2
        assert(M.craftValue(row, 10, 200) == 350)
        assert(M.craftValue(row, 12, 200) == nil, 'not a material of the recipe')
        assert(M.craftValue({ cost = 5, reagents = { { 10, 1 } } }, 10, 5) == nil, 'no value')''')


class TooltipTests(unittest.TestCase):
    def test_the_tooltip_shows_the_chain_with_the_craft(self):
        text = clean(run(CRAFT + "fire('TRADE_SKILL_SHOW')" + TIP))
        # The chain's best route is the recommendation; the craft value has its own line.
        self.assertRegex(text, r'Craft = \(Bolt of Linen Cloth\)  \d')
        self.assertIn('Recommendation = Craft: Bolt of Linen Cloth', text)

    def test_kept_until_new_scan_data(self):
        run(CRAFT + '''fire('TRADE_SKILL_SHOW')
        local UI = F.UI
        UI.chainFor('c:10', 10, nil, F.Engine.clock())
        local c = UI.chainCache['c:10']
        assert(c and c.chain and c.chain.routes[1].route == 'craft')
        local calls, profits = 0, F.Crafting.profits
        F.Crafting.profits = function(...) calls = calls + 1 return profits(...) end
        UI.chainFor('c:10', 10, nil, F.Engine.clock())
        assert(calls == 0, 'cached')
        F.Data.market(F.db, F.Engine.scope()).scannedAt = F.Engine.clock() + 1
        UI.chainFor('c:10', 10, nil, F.Engine.clock())
        assert(calls == 1, 'new scan data: counted again')''')

    def test_no_route_says_so(self):
        text = clean(run(SETUP + '''local F = ForeverFlip
        fullScan()
        F.Trade.quote = function() return nil end
        F.Crafting.profits = function() return {} end
        local h = F.Data.market(F.db, F.Engine.scope()).history['c:10']
        assert(h, 'scanned')''' + TIP))
        self.assertNotIn('Recommendation', text)
        self.assertIn('Median AH price', text)


if __name__ == '__main__':
    unittest.main()
