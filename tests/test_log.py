"""ForeverFlip's messages (Log.lua): categories, chat echo, history, and the ForeverFlip chat tab."""

import unittest

from test_addon import SETUP, run

BASE = SETUP + '''local F = ForeverFlip
local Log = F.Log
'''

# The game's chat windows: General in the first, the others free; FCF_OpenNewWindow takes the first
# free one and docks it. waits() runs ForeverFlip's delayed calls now.
CHAT = '''windows, selected = {}, nil
NUM_CHAT_WINDOWS = 10
for i = 1, 10 do
    windows[i] = { name = '', shown = false, docked = false }
    _G['ChatFrame' .. i] = { lines = {},
        AddMessage = function(self, m) self.lines[#self.lines + 1] = m end,
        Clear = function(self) self.lines = {} end }
end
windows[1] = { name = 'General', shown = true, docked = true }
function GetChatWindowInfo(i)
    local w = windows[i]
    return w.name, 14, 0, 0, 0, 0, w.shown, false, w.docked
end
function FCF_OpenNewWindow(name)
    for i = 2, 10 do
        if not windows[i].shown and not windows[i].docked then
            windows[i] = { name = name, shown = true, docked = true }
            local f = _G['ChatFrame' .. i]
            f.lines, f.isDocked = {}, true
            return f, i
        end
    end
end
function FCF_SelectDockFrame(f) selected = f end
function waits()
    for _, w in ipairs(F.Share.waits) do w.run() end
    F.Share.waits = {}
end
'''


class LogTests(unittest.TestCase):
    def test_only_errors_reach_the_chat_by_default(self):
        run(BASE + '''local n = #printed
        Log.add('trade', 'sold 3 stacks')
        Log.add('scan', 'no answer for: Linen')
        Log.add('deal', 'ForeverFlip: deal Linen')
        assert(#printed == n, 'trade, scan and deal lines stay in the tab: ' .. tostring(printed[#printed]))
        Log.add('error', 'boom')
        assert(#printed == n + 1 and printed[#printed]:find('ForeverFlip error:', 1, true), printed[#printed])
        assert(#Log.history >= 4 and Log.last('trade') == 'sold 3 stacks' and Log.last() == 'boom')''')

    def test_a_category_can_be_echoed_and_errors_silenced(self):
        run(BASE + '''Log.setEcho('trade', true); Log.setEcho('error', false)
        local n = #printed
        Log.add('trade', 'auction mail taken')
        assert(#printed == n + 1 and printed[#printed] == 'ForeverFlip: auction mail taken', printed[#printed])
        Log.add('error', 'quiet')
        assert(#printed == n + 1, 'errors were turned off for the chat')
        assert(F.db.settings.logEcho.trade == true and F.db.settings.logEcho.error == false)''')

    def test_a_slash_answer_still_prints_unchanged(self):
        run(BASE + '''local n = #printed
        SlashCmdList.FOREVERFLIP('rescan')
        assert(#printed == n + 1 and printed[#printed]:find('^ForeverFlip: '), printed[#printed])
        assert(Log.last('info') == printed[#printed], 'and is kept in the history')''')

    def test_the_history_is_bounded(self):
        run(BASE + '''for i = 1, Log.KEEP + 50 do Log.add('info', 'line ' .. i) end
        assert(#Log.history == Log.KEEP, #Log.history)
        assert(Log.history[1].text == 'line 51' and Log.last() == 'line ' .. (Log.KEEP + 50))''')

    def test_a_repeated_error_is_counted_not_repeated(self):
        run(BASE + '''local n, s = #printed, sounds
        for _ = 1, 5 do Log.add('error', 'the server did not answer') end
        assert(#printed == n + 1, 'one chat line, not five')
        assert(sounds == s + 1, 'one sound')
        assert(Log.history[#Log.history].count == 5)
        assert(Log.format(Log.history[#Log.history]):find('(x5)', 1, true))
        now = now + Log.REPEAT_GAP + 1
        Log.add('error', 'the server did not answer')
        assert(#printed == n + 2 and sounds == s + 2, 'told again after a quiet minute')
        F.db.settings.logSound = false
        now = now + Log.REPEAT_GAP + 1
        Log.add('error', 'another')
        assert(sounds == s + 2, 'the sound can be turned off')''')

    def test_the_tab_is_made_once_and_gets_the_history(self):
        run(BASE + CHAT + '''Log.add('trade', 'before the tab')
        Log.entered(); waits()
        local tab = ChatFrame2
        assert(windows[2].name == 'ForeverFlip' and F.db.settings.logTabMade == true)
        assert(Log.chatFrame() == tab and tab.lines[#tab.lines]:find('before the tab', 1, true))
        Log.add('scan', 'after the tab')
        assert(tab.lines[#tab.lines]:find('after the tab', 1, true), 'new lines go to the tab')
        -- The player closes it: not made again at the next login, /ff log makes it and brings it forward.
        windows[2] = { name = 'ForeverFlip', shown = false, docked = false }
        assert(Log.chatFrame() == nil)
        Log.entered(); waits()
        assert(not windows[3].shown and Log.chatFrame() == nil, 'a closed tab stays closed')
        SlashCmdList.FOREVERFLIP('log')
        assert(Log.chatFrame() ~= nil and selected == Log.chatFrame())
        assert(#Log.chatFrame().lines == #Log.history, 'the remade tab gets the whole history')''')

    def test_without_a_free_window_log_says_so(self):
        run(BASE + CHAT + '''for i = 2, 10 do windows[i] = { name = 'Other', shown = true, docked = true } end
        local n = #printed
        SlashCmdList.FOREVERFLIP('log')
        assert(#printed == n + 1 and printed[#printed]:find('No free chat window', 1, true), printed[#printed])''')

    def test_the_messages_settings_page(self):
        run(BASE + CHAT + '''local UI = F.UI
        AuctionHouseFrame:Show(); fire('AUCTION_HOUSE_SHOW'); UI.show('settings:messages')
        assert(UI.settingsTab == 'messages' and UI.logEchoBoxes.trade and not UI.logEchoBoxes.trade:GetChecked())
        UI.logEchoBoxes.trade:SetChecked(true); UI.logEchoBoxes.trade:Click()
        assert(Log.echoes('trade'))
        UI.logSoundBox:SetChecked(false); UI.logSoundBox:Click()
        assert(F.db.settings.logSound == false and not Log.soundOn())
        UI.logTabButton:Click()
        assert(Log.chatFrame() ~= nil, 'the button makes the tab')''')

    def test_game_messages_go_to_their_categories(self):
        run(BASE + '''F.Locale.apply('en'); F.Trade.fightCount = function() return 2 end
        F.Trade.toldFights = nil; F.Trade.afterScan()
        assert(Log.last('trade'):find('2 of your auctions', 1, true))
        F.Engine.onBlocked('ADDON_ACTION_FORBIDDEN', 'ForeverFlip', 'UNKNOWN()')
        assert(Log.last('error'):find('UNKNOWN()', 1, true))''')

    def test_the_errors_box_governs_every_error(self):
        # A Lua error and a blocked call reach the general chat by default, and stay in the tab only
        # once the Errors box is off.
        run(BASE + '''F.Locale.apply('en')
        local n = #printed
        F.Engine.onBlocked('ADDON_ACTION_FORBIDDEN', 'ForeverFlip', 'FIRST()')
        assert(#printed == n + 1 and printed[#printed]:find('FIRST()', 1, true), 'on by default')
        Log.setEcho('error', false)
        n = #printed
        F.Engine.onBlocked('ADDON_ACTION_FORBIDDEN', 'ForeverFlip', 'SECOND()')
        F.Engine.report('kaboom')
        assert(#printed == n, 'Errors off: nothing in the general chat: ' .. tostring(printed[#printed]))
        assert(Log.last('error'):find('kaboom', 1, true), 'but the error is still in the tab')''')

    def test_info_has_no_box(self):
        run(BASE + CHAT + '''local UI = F.UI
        AuctionHouseFrame:Show(); fire('AUCTION_HOUSE_SHOW'); UI.show('settings:messages')
        assert(UI.logEchoBoxes.error and UI.logEchoBoxes.scan and not UI.logEchoBoxes.info,
            'slash answers always reach the chat, so Info has nothing to turn on or off')''')


if __name__ == '__main__':
    unittest.main()
