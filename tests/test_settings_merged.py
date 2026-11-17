"""T28: Settings, General holds what the Safety page held (a Limits section); one Save saves it all.
Later: seven pages, Automation, Display and Data split off General and Messages."""

import unittest

from test_addon import SETUP, run

BASE = SETUP + r'''local F, UI = ForeverFlip, ForeverFlip.UI
local function boxes()
    local box = {}
    for _, e in ipairs(UI.settingBoxes) do box[e.field[1]] = e end
    for _, e in ipairs(UI.safetyBoxes) do box[e.field[1]] = e end
    return box
end
'''


class MergedSettingsTests(unittest.TestCase):
    def test_seven_pages_and_the_old_safety_page_opens_general(self):
        run(BASE + r'''local settings = UI.categories[#UI.categories]
        assert(#settings.subs == 7, 'General, Automation, Display, Key bindings, Sharing, Messages, Data')
        for i, id in ipairs(UI.SETTING_PAGES) do
            assert(UI.settingFrames[id], id)
            UI.show(i == 1 and 'settings' or 'settings:' .. id)
            assert(UI.settingsTab == id and UI.settingFrames[id]:IsShown(), id)
        end
        for _, sub in ipairs(settings.subs) do assert(sub.id ~= 'settings:safety', 'no Safety entry') end
        assert(UI.settingFrames.safety == nil, 'no separate page')
        UI.show('settings:keys')
        UI.show('settings:safety')     -- a page saved by an older version, or an old message
        assert(UI.section == 'settings' and UI.settingsTab == 'general' and UI.settingFrames.general:IsShown())''')

    def test_one_save_saves_every_box(self):
        run(BASE + r'''UI.show('settings')
        local box = boxes()
        local n = 0
        for _ in pairs(box) do n = n + 1 end
        assert(n == 16, n .. ' boxes on the page')
        box.vendorMargin:SetText('150'); box.spendLimit:SetText('2,5'); box.leaveLots:SetText('3.7')
        box.minROI:SetText('40'); box.undercutPercent:SetText('2')
        UI.saveButton:Click()
        local s = F.db.settings
        assert(s.vendorMargin == 90 and s.spendLimit == 2.5 and s.leaveLots == 3, 'the limits are saved')
        assert(math.abs(s.minROI - 0.4) < 1e-9 and math.abs(s.undercutPercent - 0.02) < 1e-9, 'the rest too')
        assert(box.vendorMargin:GetText() == '90', 'the box shows what was kept')
        -- A box without a number keeps its value, and Save says so instead of "saved".
        box.leaveLots:SetText('lots'); UI.saveButton:Click()
        assert(s.leaveLots == 3 and box.leaveLots:GetText() == '3')''')

    def test_save_is_off_until_a_box_changes(self):
        run(BASE + r'''UI.show('settings')
        local box = boxes()
        assert(not UI.saveButton:IsEnabled(), 'nothing to save on a fresh page')
        UI.saveButton.scripts.OnEnter(UI.saveButton)
        assert(GameTooltip:GetText() == 'Nothing to save', tostring(GameTooltip:GetText()))
        box.leaveLots:SetText('4')
        assert(UI.saveButton:IsEnabled(), 'a changed box can be saved')
        box.leaveLots:SetText(box.leaveLots.saved)
        assert(not UI.saveButton:IsEnabled(), 'typed back as it was')
        box.minROI:SetText('40'); UI.saveButton:Click()
        assert(not UI.saveButton:IsEnabled(), 'off again once saved')
        UI.applyPreset('balanced')
        assert(not UI.saveButton:IsEnabled(), 'a preset is saved at once')''')

    def test_the_sections_do_not_overlap_and_stay_above_the_bottom_bar(self):
        # The mock keeps no anchors: record the y of each TOPLEFT/TOPRIGHT anchor on the page while
        # the page is built again on a fresh frame.
        run(BASE + r'''local p = CreateFrame('Frame', nil, UI.frame)
        local ys, labels = {}, {}
        local function track(w)
            rawset(w, 'SetPoint', function(_, point, rel, _, _, y)
                if rel == p and (point == 'TOPLEFT' or point == 'TOPRIGHT') then ys[#ys + 1] = y end
            end)
            rawset(w, 'SetText', function(self, v) rawset(self, 'text', v); labels[v] = self end)
            return w
        end
        local create = CreateFrame
        CreateFrame = function(...) return track(create(...)) end
        rawset(p, 'CreateFontString', function(self) return track(create('FontString', nil, self)) end)
        rawset(p, 'CreateTexture', function(self) return track(create('Texture', nil, self)) end)
        UI.createGeneralSettings(p)
        CreateFrame = create
        local lowest = 0
        for _, y in ipairs(ys) do lowest = math.min(lowest, y) end
        -- A row is at most 26 px high; the bottom bar is the last 34 px of the 432 px page.
        assert(lowest - 26 >= -(432 - 34), 'lowest row at ' .. lowest)
        assert(#UI.safetyBoxes == 3 and #UI.settingDurations == 4, 'Limits, Market reset and Posting on the page')''')

    def test_what_was_learned_is_on_the_data_page(self):
        run(BASE + r'''UI.show('settings:data')
        assert(UI.safetyText:GetText():find('Vendor prices confirmed at merchants', 1, true), UI.safetyText:GetText())
        assert(UI.resetDataButton and UI.resetSettingsButton, 'both resets are on the page')''')

    def test_the_market_reset_limits_are_the_deals_page_ones(self):
        run(BASE + r'''UI.show('settings')
        local box = boxes()
        box.medianItemGold:SetText('75'); box.medianShare:SetText('40'); UI.saveButton:Click()
        local s = F.db.settings
        assert(s.medianItemGold == 75 and math.abs(s.medianShare - 0.4) < 1e-9, 'saved as the Deals page saves them')
        -- Changed elsewhere: the page shows the new value when it is opened again.
        s.medianDayGold = 333
        UI.show('settings:keys'); UI.show('settings')
        assert(box.medianDayGold:GetText() == '333', box.medianDayGold:GetText())
        -- A box being typed in keeps its text.
        box.minROI:SetText('41'); UI.show('settings:keys'); UI.show('settings')
        assert(box.minROI:GetText() == '41' and UI.saveButton:IsEnabled())''')

    def test_the_duration_buttons_are_the_selling_ones(self):
        run(BASE + r'''UI.show('settings')
        UI.settingDurations[4]:Click()
        assert(F.db.settings.duration == 0 and not UI.settingDurations[4]:IsEnabled())
        UI.settingDurations[1]:Click()
        assert(F.db.settings.duration == 1 and UI.settingDurations[4]:IsEnabled())''')

    def test_options_pages_follow_the_setting(self):
        run(BASE + r'''UI.show('settings:display')
        local boxes = UI.settingFrames.display.optionBoxes
        local unlearned
        for _, b in ipairs(boxes) do if b.setting == 'hideUnlearned' then unlearned = b end end
        assert(unlearned and not unlearned:GetChecked())
        F.db.settings.hideUnlearned = true -- the Crafting page's own switch
        UI.show('settings:keys'); UI.show('settings:display')
        assert(unlearned:GetChecked(), 'shown again, the box follows')
        unlearned:SetChecked(false); unlearned:Click()
        assert(F.db.settings.hideUnlearned == false)
        UI.show('settings:auto')
        local hold
        for _, b in ipairs(UI.settingFrames.auto.optionBoxes) do if b.setting == 'belowMin' then hold = b end end
        hold:SetChecked(true); hold:Click()
        assert(F.db.settings.belowMin == 'hold')''')

    def test_reset_settings_keeps_the_language_and_the_data(self):
        run(BASE + r'''local s = F.db.settings
        s.language = 'uk'; s.minROI = 0.9; s.autoScan = true; s.belowMin = 'hold'; s.medianDayGold = 1
        F.Deals.setSniper(true)
        F.db.markets.keep = { marker = true }
        UI.show('settings:data')
        UI.resetSettings()
        s = F.db.settings
        local careful = F.Data.PRESETS.careful
        assert(s.language == 'uk', 'the language stays')
        assert(math.abs(s.minROI - careful.minROI) < 1e-9 and s.autoScan == false and s.belowMin == 'min')
        assert(s.medianDayGold == F.Data.DEFAULTS.medianDayGold and s.sniper == false)
        assert(F.db.markets.keep and F.db.markets.keep.marker, 'the data stays')
        local box = boxes()
        assert(box.minROI:GetText() == string.format('%g', careful.minROI * 100), 'the boxes show it')''')


if __name__ == '__main__':
    unittest.main()
