"""T27: our auction house tab goes after the last visible tab (others' tabs are only read), and the
three price settings explain what they do."""

import unittest

from test_addon import SETUP, run, runtime

# A laid-out auction house: the window from x 0 to RIGHT, top 600, the game's three tabs under it
# (100 px wide from x 20, top 100). Our tab's position follows the anchor ForeverFlip gives its
# frame; the game's and the other addon's tabs refuse to be moved or written to.
GEOMETRY = r'''
local RIGHT = %d
local function box(w, l, r, t, b)
    rawset(w, 'GetLeft', function() return l end); rawset(w, 'GetRight', function() return r end)
    rawset(w, 'GetTop', function() return t end); rawset(w, 'GetBottom', function() return b end)
end
local function untouchable(w, name)
    for _, m in ipairs({ 'SetPoint', 'ClearAllPoints', 'SetParent', 'SetWidth', 'SetSize', 'Hide', 'SetText' }) do
        rawset(w, m, function() error(name .. ':' .. m .. ' called') end)
    end
    rawset(w, 'GetObjectType', function() return 'Button' end)
end
box(AuctionHouseFrame, 0, RIGHT, 600, 100)
AuctionHouseFrame.Tabs = {}
for i = 1, 3 do
    local t = CreateFrame('Button', nil, AuctionHouseFrame)
    box(t, 20 + (i - 1) * 100, 120 + (i - 1) * 100, 100, 68)
    untouchable(t, 'game tab ' .. i)
    AuctionHouseFrame.Tabs[i] = t
end
-- Another addon's tab, on a frame of its own on the auction house (the way LibAHTab builds them).
otherRoot = CreateFrame('Frame', nil, AuctionHouseFrame)
otherTab = CreateFrame('Button', 'OtherAddonTab', otherRoot)
untouchable(otherTab, 'other tab')
function placeOther(l) box(otherTab, l, l + 100, 100, 68) end
placeOther(320)          -- right after the game's last tab: where ours would go
local addonFrames = { otherRoot }
rawset(AuctionHouseFrame, 'GetChildren', function() return unpack(addonFrames) end)
rawset(otherRoot, 'GetChildren', function() return otherTab end)
-- Ours: built by ForeverFlip; its position is what its frame's anchor says.
anchors = {}
local create = CreateFrame
CreateFrame = function(kind, name, parent, template)
    local w = create(kind, name, parent, template)
    if parent == AuctionHouseFrame and kind == 'Frame' then
        rawset(w, 'SetPoint', function(_, point, rel, relPoint, x, y)
            anchors[#anchors + 1] = { point, rel, relPoint, x, y }
        end)
    elseif name == 'ForeverFlipTab' then
        rawset(w, 'GetObjectType', function() return 'Button' end)
        local function at() local a = ForeverFlip.UI.tabAt; return a and a[1] or 320, a and a[2] or -500 end
        rawset(w, 'GetLeft', function() return (at()) + 3 end)
        rawset(w, 'GetRight', function() return (at()) + 103 end)
        rawset(w, 'GetTop', function() local _, y = at(); return 600 + y end)
        rawset(w, 'GetBottom', function() local _, y = at(); return 568 + y end)
    end
    return w
end
'''


def lua(right=900):
    rt = runtime(False)
    rt.execute(GEOMETRY % right + "fire('AUCTION_HOUSE_SHOW')")
    return rt


class TabPlaceTests(unittest.TestCase):
    def test_our_tab_goes_after_another_addons_tab(self):
        lua().execute(r'''local UI = ForeverFlip.UI
        assert(UI.tab and UI.tab ~= otherTab and UI.tabRow == 1, 'our tab, in the row of tabs')
        assert(UI.tabAt[1] == 420 and UI.tabAt[2] == -500, UI.tabAt[1] .. ' ' .. UI.tabAt[2])
        local last = anchors[#anchors]
        assert(last[1] == 'TOPLEFT' and last[2] == AuctionHouseFrame and last[4] == 420,
            'anchored to the auction house by an offset, never to the other addon\'s tab')''')

    def test_a_tab_added_a_moment_later_is_found_by_the_recheck(self):
        lua().execute(r'''local UI = ForeverFlip.UI
        -- A third addon adds its tab after ours a moment later: it overlaps our place.
        local late = CreateFrame('Button', nil, AuctionHouseFrame)
        rawset(late, 'GetObjectType', function() return 'Button' end)
        rawset(late, 'SetPoint', function() error('late tab moved') end)
        rawset(late, 'GetLeft', function() return 420 end); rawset(late, 'GetRight', function() return 520 end)
        rawset(late, 'GetTop', function() return 100 end); rawset(late, 'GetBottom', function() return 68 end)
        local kids = { otherRoot, late }
        rawset(AuctionHouseFrame, 'GetChildren', function() return unpack(kids) end)
        local root = UI.tabRoot
        root.scripts.OnUpdate(root, 0.2)
        assert(UI.tabAt[1] == 420, 'not yet')
        root.scripts.OnUpdate(root, 0.4)
        assert(UI.tabAt[1] == 520, 'after half a second: ' .. UI.tabAt[1])
        root.scripts.OnUpdate(root, 2)
        assert(root.scripts.OnUpdate == nil, 'the rechecks end')
        -- Settled: a recheck that finds the same place does not anchor again.
        local n = #anchors
        UI.placeTab()
        assert(#anchors == n, 'no new anchor when nothing changed')''')

    def test_a_tab_already_after_ours_is_left_alone(self):
        rt = lua()
        rt.execute(r'''local UI = ForeverFlip.UI
        assert(UI.tabAt[1] == 420)
        -- The other addon moved its tab after ours (to 523): it is not counted, ours goes back to
        -- the game's last tab and stays there; the two tabs do not chase each other.
        placeOther(523)
        UI.placeTab()
        assert(UI.tabAt[1] == 320, UI.tabAt[1])
        local n = #anchors
        UI.placeTab(); UI.placeTab()
        assert(UI.tabAt[1] == 320 and #anchors == n, 'settled')''')

    def test_a_hidden_tab_does_not_count(self):
        lua().execute(r'''local UI = ForeverFlip.UI
        rawset(otherTab, 'IsVisible', function() return false end)
        UI.placeTab()
        assert(UI.tabAt[1] == 320, 'after the game\'s last tab: ' .. UI.tabAt[1])''')

    def test_no_room_starts_a_second_row(self):
        # The window ends at 500: after the other tab (420) ours would pass its right edge.
        lua(500).execute(r'''local UI = ForeverFlip.UI
        assert(UI.tabRow == 2, 'a second row')
        assert(UI.tabAt[1] == 17 and UI.tabAt[2] == -530, UI.tabAt[1] .. ' ' .. UI.tabAt[2])''')

    def test_opening_again_places_the_tab_again(self):
        lua().execute(r'''local UI = ForeverFlip.UI
        fire('AUCTION_HOUSE_CLOSED'); placeOther(320)
        rawset(otherTab, 'GetRight', function() return 470 end)   -- a wider tab this time
        fire('AUCTION_HOUSE_SHOW')
        assert(UI.tabAt[1] == 470, UI.tabAt[1])''')


class PriceSettingHintTests(unittest.TestCase):
    def test_the_three_price_settings_explain_themselves(self):
        run(SETUP + r'''local F, UI = ForeverFlip, ForeverFlip.UI
        UI.show('settings')
        local seen = {}
        for _, e in ipairs(UI.settingBoxes) do
            local key = e.field[1]
            if key == 'undercutPercent' or key == 'minPricePercent' or key == 'maxPricePercent' then
                tooltipLines = {}
                e.scripts.OnEnter(e)
                local body = tooltipLines[#tooltipLines]
                assert(body and #body > 80 and body:find('0 =', 1, true), key .. ': ' .. tostring(body))
                assert(not seen[body], 'each says something of its own'); seen[body] = key
            end
        end
        assert(seen and next(seen), 'the three boxes are on the page')''')


if __name__ == '__main__':
    unittest.main()
