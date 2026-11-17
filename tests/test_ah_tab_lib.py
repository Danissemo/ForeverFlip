"""With LibAHTab (Auctionator, TSM), our tab goes first in the library's chain of addon tabs, and the
other addons' tabs follow it in their old order; a tab made later is chained after the last one."""

import unittest

from test_addon import runtime

# A small LibAHTab with the library's own data layout: a root frame, a list of tabs, the first
# anchored to the root, each next one to the one before it.
LIB = r'''
local lib = { }
local function point(t)
    rawset(t, 'SetPoint', function(self, p, rel, relp, x, y) self.anchor = { p, rel, relp, x, y } end)
    rawset(t, 'ClearAllPoints', function(self) self.anchor = nil end)
    rawset(t, 'GetPoint', function(self) local a = self.anchor; if a then return a[1], a[2], a[3], a[4], a[5] end end)
end
function lib:CreateTab(id, frame, label)
    if not self.internalState then
        self.internalState = { Tabs = {}, usedIDs = {}, rootFrame = CreateFrame('Frame', nil, AuctionHouseFrame) }
    end
    local s = self.internalState
    local t = CreateFrame('Button', 'LibAHFrame-1.0-' .. id, s.rootFrame)
    point(t)
    t.label = label
    s.Tabs[#s.Tabs + 1] = t
    s.usedIDs[id] = t
    if #s.Tabs > 1 then
        t:SetPoint('TOPLEFT', s.Tabs[#s.Tabs - 1], 'TOPRIGHT', -14, 0)
    else
        t:SetPoint('TOPLEFT', s.rootFrame, 'TOPLEFT', -14, 0)
    end
    frame:Hide()
end
function lib:GetButton(id) return self.internalState.usedIDs[id] end
LibStub = function(name) if name == 'LibAHTab-1-0' then return lib end end
AHLIB = lib
'''


class LibTabOrderTests(unittest.TestCase):
    def test_ours_goes_first_and_the_others_follow(self):
        lua = runtime(False)
        lua.execute(LIB + '''
        AHLIB:CreateTab('Auctionator', CreateFrame('Frame'), 'Auctionator')
        AHLIB:CreateTab('TSM', CreateFrame('Frame'), 'TSM4')
        fire('AUCTION_HOUSE_SHOW')
        local s = AHLIB.internalState
        local mine, a, t = AHLIB:GetButton('ForeverFlip'), AHLIB:GetButton('Auctionator'), AHLIB:GetButton('TSM')
        assert(s.Tabs[1] == mine and s.Tabs[2] == a and s.Tabs[3] == t)
        assert(mine.anchor[2] == s.rootFrame and mine.anchor[4] == -14, 'ours at the root, the library gap')
        assert(a.anchor[2] == mine and a.anchor[3] == 'TOPRIGHT' and a.anchor[4] == -14)
        assert(t.anchor[2] == a)
        -- A tab made after ours chains after the last one; the next check keeps ours first.
        AHLIB:CreateTab('Late', CreateFrame('Frame'), 'Late')
        local late = AHLIB:GetButton('Late')
        assert(late.anchor[2] == t, 'not after ours')
        ForeverFlip.UI.tabFirst()
        assert(s.Tabs[1] == mine and s.Tabs[4] == late and late.anchor[2] == t)''')

    def test_a_broken_library_does_not_break_the_page(self):
        lua = runtime(False)
        lua.execute(LIB + '''
        fire('AUCTION_HOUSE_SHOW')
        AHLIB.internalState.Tabs[1].GetPoint = function() error('boom') end
        ForeverFlip.UI.tabFirst()
        assert(ForeverFlip.UI.tab == AHLIB)''')


if __name__ == '__main__':
    unittest.main()
