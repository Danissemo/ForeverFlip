"""Journal views expose only their own navigation and preserve the selected view."""
import unittest

from test_addon import SETUP, run

NAV = SETUP + '''local F, UI = ForeverFlip, ForeverFlip.UI
local analytics
for _, c in ipairs(UI.categories) do
    if c.group.label == 'Analytics' then analytics = c end
end
local journal = analytics.subs[3]
'''


class JournalNavigationTests(unittest.TestCase):
    def test_journal_opens_four_children_and_selects_all_by_default(self):
        run(NAV + '''UI.show('journal')
        assert(#journal.kids == 4 and journal.selected:IsShown())
        for i, kid in ipairs(journal.kids) do
            assert(kid:IsShown())
            assert(kid.selected:IsShown() == (i == 1))
        end
        assert(UI.pages.journal:IsShown() and UI.journalFilter == 'all')''')

    def test_each_child_click_selects_it_and_saves_the_view(self):
        run(NAV + '''UI.show('journal')
        for i, kid in ipairs(journal.kids) do
            kid:Click()
            assert(F.db.ui.section == kid.id and UI.groupOf(kid.id) == analytics.group)
            assert(journal.selected:IsShown() and analytics.selected:IsShown())
            for j, other in ipairs(journal.kids) do
                assert(other:IsShown() and other.selected:IsShown() == (i == j))
            end
        end''')

    def test_children_hide_on_other_pages_and_group_remembers_the_view(self):
        run(NAV + '''UI.show('journal:vendor')
        UI.show('sell')
        for _, kid in ipairs(journal.kids) do assert(not kid:IsShown()) end
        analytics:Click()
        assert(UI.journalFilter == 'vendor' and journal.kids[3].selected:IsShown())
        UI.show('analytics')
        for _, kid in ipairs(journal.kids) do assert(not kid:IsShown()) end''')

    def test_saved_child_view_is_restored_when_the_ui_is_recreated(self):
        run(NAV + '''UI.show('journal:bid')
        UI.frame = nil
        UI.create()
        assert(UI.section == 'journal' and UI.journalFilter == 'bid')
        for _, c in ipairs(UI.categories) do
            if c.group.label == 'Analytics' then
                assert(c.subs[3].kids[4]:IsShown() and c.subs[3].kids[4].selected:IsShown())
            end
        end''')


class JournalCheckAllTests(unittest.TestCase):
    BUY = SETUP + '''local F, UI = ForeverFlip, ForeverFlip.UI
local c = F.Data.char(F.db, F.Engine.owner())
F.Data.addPosition(c, 'c:10', 'Linen Cloth', 10, 600, 'flip', 150, now)
F.Data.log(c, { at = now, kind = 'buy', key = 'c:10', name = 'Linen Cloth', qty = 10, amount = 600, mode = 'flip' })
'''

    def test_check_all_reads_the_items_the_page_lists(self):
        run(self.BUY + '''UI.show('journal:all')
        local scope, keys, verify = UI.statusTargets()
        assert(scope == 'journal' and #keys == 1 and keys[1] == 'c:10', scope .. ' ' .. #keys)
        assert(not verify, 'a journal check is a price, not a deal')
        UI.checkStatuses(); assert(F.Deals.busy(), 'the page starts its own check')''')

    def test_the_check_leaves_a_live_price_behind(self):
        run(self.BUY + '''UI.show('journal:all')
        UI.checkStatuses()
        for _ = 1, 40 do if F.Deals.search then answer() end run(0.2) end
        UI.refresh()
        assert(not F.Deals.busy() and F.Trade.freshCheapest('c:10') == 60, tostring(F.Trade.freshCheapest('c:10')))''')

    def test_every_view_is_checked_only_for_the_items_it_shows(self):
        run(self.BUY + '''local c = F.Data.char(F.db, F.Engine.owner())
        F.Data.addPosition(c, 'c:30', 'Linen Bag', 1, 2000, 'vendor', 2200, now)
        F.Data.log(c, { at = now, kind = 'buy', key = 'c:30', name = 'Linen Bag', qty = 1, amount = 2000, mode = 'vendor' })
        UI.show('journal:flip')
        local _, flip = UI.statusTargets()
        assert(#flip == 1 and flip[1] == 'c:10', 'resale view: ' .. #flip)
        UI.show('journal:vendor')
        local _, vendor = UI.statusTargets()
        assert(#vendor == 1 and vendor[1] == 'c:30', 'to vendor view: ' .. #vendor)''')

    def test_an_item_shown_by_several_purchases_is_checked_once(self):
        run(self.BUY + '''local c = F.Data.char(F.db, F.Engine.owner())
        F.Data.addPosition(c, 'c:10', 'Linen Cloth', 5, 300, 'flip', 150, now)
        F.Data.log(c, { at = now, kind = 'buy', key = 'c:10', name = 'Linen Cloth', qty = 5, amount = 300, mode = 'flip' })
        UI.show('journal:all')
        local _, keys = UI.statusTargets()
        assert(#keys == 1, 'one key per item, not per purchase: ' .. #keys)''')


if __name__ == '__main__':
    unittest.main()
