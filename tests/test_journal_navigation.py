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


if __name__ == '__main__':
    unittest.main()
