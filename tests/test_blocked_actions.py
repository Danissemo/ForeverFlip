"""What the game blocks is recorded (Core.onBlocked), and the Buy tab marks leave the game's rows alone."""

import unittest

from test_addon import SETUP, run


class BlockedActionTests(unittest.TestCase):
    def test_a_blocked_action_is_kept_told_once_and_shown_by_diag(self):
        run(SETUP + '''local F = ForeverFlip
        fullScan()
        local n = #printed
        fire('ADDON_ACTION_FORBIDDEN', 'ForeverFlip', 'UNKNOWN()')
        fire('ADDON_ACTION_FORBIDDEN', 'ForeverFlip', 'UNKNOWN()')
        fire('ADDON_ACTION_BLOCKED', 'SomeOtherAddon', 'CastSpellByName()')
        assert(#F.db.blocked == 2, 'another addon is not ours: ' .. #F.db.blocked)
        local b = F.db.blocked[1]
        assert(b.event == 'forbidden' and b.func == 'UNKNOWN()' and b.doing:find('AH open', 1, true), b.doing)
        assert(#printed == n + 1 and printed[#printed]:find('UNKNOWN()', 1, true), 'told once')
        SlashCmdList.FOREVERFLIP('diag')
        local found = false
        for i = n + 2, #printed do if printed[i]:find('forbidden UNKNOWN()', 1, true) then found = true end end
        assert(found, 'diag lists it')''')

    def test_marks_off_leave_the_buy_tab_untouched(self):
        run(SETUP + '''local F = ForeverFlip
        fullScan()
        F.db.settings.highlight = false
        local asked = 0
        AuctionHouseFrame.CommoditiesBuyFrame = CreateFrame('Frame')
        AuctionHouseFrame.CommoditiesBuyFrame.ItemList = { ScrollBox = {
            GetFrames = function() asked = asked + 1 end } }
        run(1)
        assert(asked == 0, 'the rows are not even listed')''')

    def test_a_function_the_client_did_not_name_is_recorded_as_such(self):
        # ADDON_ACTION_BLOCKED on the older client: (addon) only, no function name.
        run(SETUP + '''local F = ForeverFlip
        fullScan()
        fire('ADDON_ACTION_BLOCKED', 'ForeverFlip')
        local b = F.db.blocked[1]
        assert(b.event == 'blocked' and b.func == '?', b.func)
        local said = printed[#printed]
        assert(said:find('?', 1, true) and not said:find('nil', 1, true), said)''')

    def test_diag_says_when_nothing_was_blocked(self):
        run(SETUP + '''local F = ForeverFlip
        fullScan()
        local n = #printed
        SlashCmdList.FOREVERFLIP('diag')
        local found = false
        for i = n + 1, #printed do
            if printed[i]:find('No blocked action', 1, true) then found = true end
        end
        assert(found, 'diag tells the player the list was checked and is empty')''')

    def test_diag_is_translated(self):
        run(SETUP + '''local F = ForeverFlip
        fullScan()
        fire('ADDON_ACTION_FORBIDDEN', 'ForeverFlip', 'UNKNOWN()')
        F.Locale.apply('uk')
        local n = #printed
        SlashCmdList.FOREVERFLIP('diag')
        local found = false
        for i = n + 1, #printed do
            -- the Ukrainian word for "forbidden", then the function name the game gave
            if printed[i]:find('заборонено UNKNOWN()', 1, true) then found = true end
        end
        assert(found, 'the diag line is in the player\\'s language too')''')

    def test_the_blocked_list_is_read_even_before_the_saved_data(self):
        run('''ForeverFlip.Engine.db = nil
        SlashCmdList.FOREVERFLIP('diag')''')


if __name__ == "__main__":
    unittest.main()
