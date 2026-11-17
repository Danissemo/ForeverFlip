"""Sounds of sales and outbids, the window's size, the data summary, My results, and table headers
that fit their columns in both languages."""

import unittest

from test_addon import SETUP, run, runtime

BASE = SETUP + r'''local F, UI = ForeverFlip, ForeverFlip.UI
ERR_AUCTION_OUTBID_S = "You have been outbid on %s."
local function box(page, setting)
    for _, b in ipairs(UI.settingFrames[page].optionBoxes) do
        if b.setting == setting then return b end
    end
end
'''

PAGES = ['deals', 'shop', 'mybids', 'crafting', 'deals:disenchant', 'sell', 'auctions', 'undercuts',
         'analytics', 'stats', 'journal']


class EventSoundTests(unittest.TestCase):
    def test_a_sale_sounds_once_in_a_few_seconds(self):
        run(BASE + r'''local before = sounds
        fire('CHAT_MSG_SYSTEM', 'A buyer has been found for your auction of Linen Cloth.')
        assert(sounds == before + 1, 'a sale sounds')
        fire('CHAT_MSG_SYSTEM', 'A buyer has been found for your auction of Linen Cloth.')
        assert(sounds == before + 1, 'a second sale at once makes no second sound')
        now = now + 4
        fire('CHAT_MSG_SYSTEM', 'A buyer has been found for your auction of Linen Bag.')
        assert(sounds == before + 2)
        F.db.settings.soundSold = false; now = now + 10
        fire('CHAT_MSG_SYSTEM', 'A buyer has been found for your auction of Linen Bag.')
        assert(sounds == before + 2, 'turned off')''')

    def test_an_outbid_on_a_bid_of_ours_sounds(self):
        run(BASE + r'''local before = sounds
        fire('CHAT_MSG_SYSTEM', 'You have been outbid on Linen Bag.')
        assert(sounds == before, 'no bid of ours: no sound')
        F.Bids.outbid = function() return true end
        fire('CHAT_MSG_SYSTEM', 'You have been outbid on Linen Bag.')
        assert(sounds == before + 1)
        F.db.settings.soundOutbid = false; now = now + 10
        fire('CHAT_MSG_SYSTEM', 'You have been outbid on Linen Bag.')
        assert(sounds == before + 1, 'turned off')''')

    def test_the_automation_page_switches_them(self):
        run(BASE + r'''UI.show('settings:auto')
        local sold, outbid = box('auto', 'soundSold'), box('auto', 'soundOutbid')
        assert(sold:GetChecked() and outbid:GetChecked(), 'on for a new profile')
        sold:SetChecked(false); sold:Click()
        assert(F.db.settings.soundSold == false and F.db.settings.soundOutbid == true)''')


class WindowScaleTests(unittest.TestCase):
    def test_the_display_page_sizes_the_window_and_reset_brings_it_back(self):
        run(BASE + r'''UI.show('settings:display')
        assert(#UI.scaleButtons == 3 and not UI.scaleButtons[2]:IsEnabled(), '100% now')
        UI.scaleButtons[1]:Click()
        assert(F.db.settings.windowScale == 0.9 and UI.shownScale == 0.9)
        assert(not UI.scaleButtons[1]:IsEnabled() and UI.scaleButtons[2]:IsEnabled())
        UI.resetSettings()
        assert(F.db.settings.windowScale == 1 and UI.shownScale == 1, 'a reset brings 100% back')
        F.db.settings.windowScale = 7; UI.applyScale()
        assert(UI.shownScale == 1.25, 'a broken value is kept in bounds')''')


class DataSummaryTests(unittest.TestCase):
    def test_the_data_page_says_what_is_saved(self):
        run(BASE + r'''fullScan()
        F.db.fitDropped = { at = now, items = 42, constants = 1 }
        F.db.lastScan = F.Engine.clock() - 7200
        UI.show('settings:data')
        local t = UI.safetyText:GetText()
        assert(t:find('Saved: prices of %d+ items on this auction house'), t)
        assert(t:find('Last full scan: 2 h ago.', 1, true), t)
        assert(t:find('At the last logout 42 items', 1, true), t)''')


class ResultsViewTests(unittest.TestCase):
    def test_my_results_lists_every_item_of_the_period(self):
        run(BASE + r'''local c = F.Data.char(F.db, F.Engine.owner())
        c.journal[#c.journal + 1] = { at = now - 60, kind = 'sell', key = 'c:10', name = 'Linen Cloth', qty = 5, amount = 1000, profit = 400 }
        c.journal[#c.journal + 1] = { at = now - 30, kind = 'sell', key = 'c:30', name = 'Linen Bag', qty = 1, amount = 500, profit = -100 }
        UI.show('analytics'); UI.analyticsDays = 1; UI.marketView = 'results'; UI.refreshAnalytics()
        local h = UI.marketTable.headers
        assert(h[2]:GetText() == 'Profit' and h[5]:GetText() == 'Return', h[2]:GetText())
        local rows = UI.marketTable.rows
        assert(rows[1]:IsShown() and rows[2]:IsShown() and not rows[3]:IsShown())
        local first, second = rows[1].cols, rows[2].cols
        assert(first[1]:GetText() == F.Util.money(400) and first[3]:GetText() == '5' and first[4]:GetText():find('67'), first[1]:GetText() .. '|' .. first[3]:GetText())
        assert(second[1]:GetText():find('-' .. F.Util.money(100), 1, true), second[1]:GetText())
        UI.marketView = 'gaps'; UI.refreshAnalytics()
        assert(h[2]:GetText() == 'Usual price', 'the market lists get their names back')''')


class ViewButtonsTests(unittest.TestCase):
    def test_the_list_buttons_share_the_row_and_stay_inside_it(self):
        run(BASE + r'''UI.show('analytics')
        local row, n = UI.viewRow, 0
        for _, b in pairs(UI.viewButtons) do
            n = n + 1
            b.SetWidth = function(s, w) rawset(s, 'testWidth', w) end
            b.GetWidth = function(s) return rawget(s, 'testWidth') or 0 end
        end
        assert(n == 7, n)
        row.GetWidth = function() return 600 end
        UI.layoutViewButtons()
        local w = UI.viewButtons.results:GetWidth()
        assert(w > 60, w)
        assert(6 + n * w + (n - 1) * UI.VIEW_GAP <= 600 - 6, 'the last button ends inside the row')''')


class NameFlickerTests(unittest.TestCase):
    def test_a_row_keeps_its_name_while_the_item_reloads(self):
        run(BASE + r'''local nameOf = UI.shared.nameOf
        local first = nameOf('c:10')
        assert(F.Util.linkName(first) == 'Linen Cloth', first)
        local info = F.Compat.itemInfo
        F.Compat.itemInfo = function() return nil end   -- dropped from the client's cache
        assert(nameOf('c:10') == first, nameOf('c:10'))
        assert(nameOf('c:10', '|cff1eff00|Hitem:10::|h[]|h|r') == first, 'an empty link keeps it too')
        assert(nameOf('c:99999') == 'item:99999', 'never seen: the id')
        F.Compat.itemInfo = info''')


class MenuSummaryTests(unittest.TestCase):
    def test_a_long_menu_leaves_the_summary_only_the_lines_that_fit(self):
        run(BASE + r'''UI.leftPanel.GetHeight = function() return 480 end
        UI.show('deals')
        local short = UI.summaryLines
        assert(short and short >= 8 and UI.summary:IsShown(), tostring(short))
        UI.show('journal:disenchant')
        assert(UI.summaryLines < short, 'Analytics with its views open leaves fewer lines')
        assert(UI.summary:IsShown() == (UI.summaryLines > 0))
        UI.leftPanel.GetHeight = function() return 200 end
        UI.show('journal')
        assert(UI.summaryLines == 0 and not UI.summary:IsShown(), 'no room: no summary')
        UI.leftPanel.GetHeight = function() return 480 end
        UI.show('deals')
        assert(UI.summary:IsShown(), 'it comes back with the room')''')

    def test_the_summary_grows_back_when_the_panel_does_without_a_page_change(self):
        run(BASE + r'''UI.leftPanel.GetHeight = function() return 300 end
        UI.show('deals')
        local short = UI.summaryLines
        UI.leftPanel.GetHeight = function() return 480 end -- the window laid out after
        UI.refresh()
        assert(UI.summaryLines > short, short .. ' -> ' .. UI.summaryLines)''')


class ChooseButtonTests(unittest.TestCase):
    def test_the_full_labels_come_back_whole_after_the_short_ones(self):
        run(BASE + r'''UI.show('sell')
        for _, b in ipairs({ UI.chooseAH, UI.chooseVendor }) do
            b.SetWidth = function(s, w) rawset(s, "testWidth", w) end
            b.GetWidth = function(s) return rawget(s, "testWidth") or 0 end
        end
        local list = UI.sellButtonsList
        list.GetWidth = function() return 300 end
        UI.layoutSellButtons()
        assert(UI.chooseShort and UI.chooseAH:GetText() == 'AH', UI.chooseAH:GetText())
        list.GetWidth = function() return 800 end
        UI.layoutSellButtons()
        for _, b in ipairs({ UI.chooseAH, UI.chooseVendor }) do
            assert(not UI.chooseShort and b:GetText():find('Choose', 1, true), b:GetText())
            assert(not rawget(b, 'labelCut'), 'the label is not cut: ' .. b:GetText() .. ' at ' .. b:GetWidth())
            assert(b:GetWidth() >= #b:GetText() * 7 + 24)
        end''')


class HeaderFitTests(unittest.TestCase):
    """Every fixed column's name fits in its width (the sort arrow takes 13 px), estimated at
    CHAR_WIDTH px a letter; a name that does not fit is cut in the game."""

    def overflow(self, language):
        lua = runtime(open_ah=False)
        pages = '{' + ','.join("'%s'" % p for p in PAGES) + '}'
        return lua.execute(r'''measureText = true
        ForeverFlip.db.settings.language = '%s'; ForeverFlip.Locale.apply('%s')
        fire('AUCTION_HOUSE_SHOW'); ForeverFlip.UI.frame:Show()
        for _, id in ipairs(%s) do ForeverFlip.UI.show(id) end
        local bad = {}
        for _, w in ipairs(widgets) do
            local width = rawget(w, 'columnWidth')
            if width then
                local need = w:GetUnboundedStringWidth()
                if need > width - 13 then
                    bad[#bad + 1] = string.format('%%s (%%d px, needs %%d)', w:GetText(), width, need)
                end
            end
        end
        return table.concat(bad, '; ')''' % (language, language, pages))

    def test_english_headers_fit(self):
        self.assertEqual(self.overflow('en'), '')

    def test_ukrainian_headers_fit(self):
        self.assertEqual(self.overflow('uk'), '')


if __name__ == '__main__':
    unittest.main()
