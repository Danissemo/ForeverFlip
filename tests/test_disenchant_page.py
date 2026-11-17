"""T12/T23: Crafting holds two pages, Crafting and Disenchant.

The disenchant deals moved from Deals into Crafting -> Disenchant (the deals page with the
disenchant filter). It has no switch: a character who knows Disenchant always gets the deals. An
empty page always says why: the profession is not learned, no full scan was made, or no material has
a price yet, each with what to do."""

import unittest

from test_addon import SETUP, run
from test_crafting import DE

PAGE = DE + '''local UI=F.UI
local function empty() return UI.dealTable.empty:IsShown() and UI.dealTable.empty:GetText() or '' end
'''


class MenuTests(unittest.TestCase):
    def test_crafting_has_the_crafting_and_disenchant_pages(self):
        run(SETUP + '''local UI=ForeverFlip.UI
        local g=UI.groupOf('deals:disenchant')
        assert(g.label=='Professions' and g.pages[1][1]=='crafting' and g.pages[2][1]=='deals:disenchant')
        assert(UI.groupOf('crafting')==g)
        for _,e in ipairs(UI.groupOf('deals:all').pages) do assert(e[1]~='deals:disenchant') end
        UI.show('deals:disenchant')
        assert(UI.section=='deals' and UI.filter=='disenchant' and g.current=='deals:disenchant')''')

    def test_there_is_no_switch_any_more(self):
        run(SETUP + '''local F=ForeverFlip;local UI=F.UI
        UI.show('deals:disenchant')
        assert(UI.disenchantBox==nil, 'the Disenchant deals check box is gone')
        F.db.settings.disenchant=false
        function IsPlayerSpell(id) return id==13262 end
        assert(F.Disenchant.active(), 'an old saved "off" no longer hides the deals')''')


class ReasonTests(unittest.TestCase):
    def test_not_learned(self):
        text = run(PAGE + '''function IsPlayerSpell() return false end
        UI.show('deals:disenchant');return empty()''')
        self.assertIn('has not learned Disenchant', text)

    def test_no_scan(self):
        text = run(PAGE + '''UI.show('deals:disenchant');return empty()''')
        self.assertIn('No full scan', text)

    def test_no_material_prices(self):
        text = run(SETUP + '''local F=ForeverFlip;local UI=F.UI
        function IsPlayerSpell(id) return id==13262 end
        fullScan();UI.show('deals:disenchant')
        return UI.dealTable.empty:GetText()''')
        self.assertIn('No disenchanting material has a known price', text)

    def test_a_deal_is_listed_and_none_says_why(self):
        run(PAGE + '''fullScan();UI.show('deals:disenchant')
        local list=F.Deals.visible('disenchant')
        assert(#list==1 and list[1].mode=='disenchant')
        assert(not UI.dealTable.empty:IsShown())
        F.Deals.remove(list[1].key);UI.refresh()
        assert(empty():find('No gear on the auction house sells now'), empty())''')


if __name__ == '__main__':
    unittest.main()
