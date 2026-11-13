"""Review fixes of the auction house window, second part (UI.lua, Locale.lua): each test is the
failure the review found, reproduced, and the behaviour that replaces it."""

import pathlib
import re
import unittest

from test_addon import SETUP, run, runtime
from test_locale import unescape

BASE = SETUP + r'''local F, D, T, UI = ForeverFlip, ForeverFlip.Deals, ForeverFlip.Trade, ForeverFlip.UI
-- The game's Hide: OnHide runs for the frame and for every descendant that was on screen.
local function gameHide(frame)
    local gone = {}
    for _, w in ipairs(widgets) do
        local f = w
        while f and f ~= frame do f = rawget(f, 'parent') end
        if f == frame and w:IsVisible() then gone[#gone + 1] = w end
    end
    frame:Hide()
    for _, w in ipairs(gone) do
        if w.scripts.OnHide then w.scripts.OnHide(w) end
    end
end
'''

# Settings, Key bindings: the first button waits for a key. The game gives a key press to the
# catcher only while it is on screen.
KEYS = BASE + r'''bound = { W = 'MOVEFORWARD', B = 'OPENALLBAGS' }; saved = 0
function GetBindingKey(cmd) for k, c in pairs(bound) do if c == cmd then return k end end end
function SetBinding(key, cmd) bound[key] = cmd end
function SaveBindings() saved = saved + 1 end
function GetCurrentBindingSet() return 2 end
local function press(key)
    local c = UI.keyCatcher
    if c and c:IsVisible() then c.scripts.OnKeyDown(c, key) end
end
UI.show('settings'); UI.show('settings:keys')
UI.keyButtons[1]:Click()
assert(UI.capturing == 'FOREVERFLIP_BUY' and UI.keyCatcher:IsVisible())
'''

SETTINGS = BASE + r'''UI.show('settings')
local box = {}
for _, e in ipairs(UI.settingBoxes) do box[e.field[1]] = e end
local function safetyBox(name)
    for _, e in ipairs(UI.safetyBoxes) do if e.field[1] == name then return e end end
end
'''


class KeyCaptureTests(unittest.TestCase):
    def test_closing_the_auction_house_ends_a_waiting_capture(self):
        run(KEYS + r'''gameHide(AuctionHouseFrame); fire('AUCTION_HOUSE_CLOSED')
        assert(not UI.keyCatcher:IsVisible(), 'the catcher went with the window')
        assert(UI.capturing == nil, 'the capture ended')
        press('W')
        assert(bound.W == 'MOVEFORWARD' and saved == 0, 'W still walks: nothing bound or saved')
        -- Back at the auction house on the key page: no key is swallowed with nothing waiting.
        AuctionHouseFrame:Show(); fire('AUCTION_HOUSE_SHOW'); UI.show('settings:keys')
        assert(not UI.keyCatcher:IsVisible(), 'the catcher does not come back with the page')
        assert(UI.keyButtons[1]:GetText() == 'Not bound', UI.keyButtons[1]:GetText())''')

    def test_another_page_ends_a_waiting_capture(self):
        run(KEYS + r'''UI.show('deals:all')
        assert(UI.capturing == nil and not UI.keyCatcher:IsShown())
        press('B')
        assert(bound.B == 'OPENALLBAGS' and saved == 0)''')

    def test_a_key_pressed_on_the_page_is_still_bound(self):
        run(KEYS + r'''press('B')
        assert(bound.B == 'FOREVERFLIP_BUY' and saved == 1 and UI.capturing == nil)
        assert(not UI.keyCatcher:IsShown())''')


class SettingsSaveTests(unittest.TestCase):
    def test_a_spending_limit_below_one_gold_is_kept(self):
        run(SETTINGS + r'''UI.show('settings:safety')
        local limit = safetyBox('spendLimit')
        limit:SetText('0.5'); UI.safetySave:Click()
        assert(F.db.settings.spendLimit == 0.5 and limit:GetText() == '0.5', tostring(F.db.settings.spendLimit))
        F.Engine.spent = 0
        assert(T.overLimit(6000), 'a 60 silver purchase is over the limit of 50 silver')
        limit:SetText('1,25'); UI.safetySave:Click()
        assert(F.db.settings.spendLimit == 1.25 and F.Engine.message == 'saved', tostring(F.db.settings.spendLimit))''')

    def test_a_safety_box_without_a_number_is_not_announced_as_saved(self):
        run(SETTINGS + r'''UI.show('settings:safety')
        F.db.settings.spendLimit = 3; UI.loadSafety()
        safetyBox('spendLimit'):SetText('50s'); safetyBox('vendorMargin'):SetText('12,5')
        UI.safetySave:Click()
        assert(F.db.settings.spendLimit == 3 and safetyBox('spendLimit'):GetText() == '3', 'the old limit stays')
        assert(F.db.settings.vendorMargin == 12, 'the other box is saved')
        assert(F.Engine.message == 'not_number', tostring(F.Engine.message))''')

    def test_percent_boxes_take_a_decimal_comma_and_a_percent_sign(self):
        run(SETTINGS + r'''box.minROI:SetText('12,5'); box.sellMinReturn:SetText('15%')
        UI.saveButton:Click()
        assert(F.db.settings.minROI == 0.125, tostring(F.db.settings.minROI))
        assert(math.abs(F.db.settings.sellMinReturn - 0.15) < 1e-12, tostring(F.db.settings.sellMinReturn))
        assert(F.Engine.message == 'saved', tostring(F.Engine.message))''')

    def test_a_general_box_without_a_number_is_not_announced_as_saved(self):
        run(SETTINGS + r'''local before = F.db.settings.minROI
        box.minROI:SetText('abc'); box.minProfit:SetText('2g')
        UI.saveButton:Click()
        assert(F.db.settings.minROI == before and F.db.settings.minProfit == 20000)
        assert(F.Engine.message == 'not_number', tostring(F.Engine.message))''')

    def test_a_fractional_percent_survives_an_unrelated_save(self):
        run(SETTINGS + r'''box.undercutPercent:SetText('2.5'); UI.saveButton:Click()
        assert(box.undercutPercent:GetText() == '2.5', box.undercutPercent:GetText())
        box.minProfit:SetText('2g'); UI.saveButton:Click()
        assert(F.db.settings.undercutPercent == 0.025, tostring(F.db.settings.undercutPercent))
        box.undercutPercent:SetText('0,4'); UI.saveButton:Click(); UI.saveButton:Click()
        assert(F.db.settings.undercutPercent == 0.004, '0.4% stays a percent, not one price step')''')


class MerchantPageTests(unittest.TestCase):
    def test_closing_the_merchant_on_the_foreverflip_tab_gives_the_next_one_its_items(self):
        run(BASE + r'''MERCHANT_ITEMS_PER_PAGE = 10
        for i = 1, 10 do CreateFrame('Frame', 'MerchantItem' .. i, MerchantFrame) end
        -- The game's update shows the buttons inside MerchantItem1..10, never those frames.
        local updates = 0
        function MerchantFrame_Update() updates = updates + 1 end
        local function shown()
            local n = 0
            for i = 1, 10 do if _G['MerchantItem' .. i]:IsShown() then n = n + 1 end end
            return n
        end
        MerchantFrame:Show(); fire('MERCHANT_SHOW')
        UI.merchantTab:Click()
        assert(shown() == 0 and UI.merchantView:IsShown(), 'the view covers the item pages')
        updates = 0
        fire('MERCHANT_CLOSED'); MerchantFrame:Hide()
        assert(shown() == 10, 'the item frames are back for the next merchant: ' .. shown())
        assert(updates == 0, 'nothing of the closing merchant is redrawn')''')


class RefreshTests(unittest.TestCase):
    def test_the_window_of_a_closed_auction_house_is_not_redrawn(self):
        run(BASE + r'''fullScan(); UI.show('sell'); UI.refresh()
        local sells, refreshSell = 0, UI.refreshSell
        UI.refreshSell = function(...) sells = sells + 1; return refreshSell(...) end
        run(3); assert(sells >= 2, 'on screen the page is redrawn: ' .. sells)
        AuctionHouseFrame:Hide(); fire('AUCTION_HOUSE_CLOSED')
        sells = 0
        for _ = 1, 8 do fire('BAG_UPDATE_DELAYED'); run(0.5) end
        UI.refresh()
        assert(UI.frame:IsShown() and sells == 0, 'nobody sees the page: ' .. sells)''')


class AgeTextTests(unittest.TestCase):
    def test_my_auctions_time_left_is_a_translated_duration(self):
        run(BASE + r'''F.Locale.apply('uk'); fullScan()
        owned = {
            { auctionID = 6, itemKey = { itemID = 30 }, quantity = 1, buyoutAmount = 25000, status = 0,
                timeLeftSeconds = 30 },
            { auctionID = 7, itemKey = { itemID = 30 }, quantity = 1, buyoutAmount = 26000, status = 0,
                timeLeftSeconds = 5400 },
        }
        fire('OWNED_AUCTIONS_UPDATED'); UI.show('auctions')
        local got, cells = {}, {}
        for _, r in ipairs(UI.auctionTable.rows) do
            if r:IsShown() then got[r.cols[5]:GetText()] = true; cells[#cells + 1] = r.cols[5]:GetText() end
        end
        assert(got['1 хв'] and got['1.5 год'], table.concat(cells, ' | '))''')

    def test_scan_age_reads_in_days_not_thousands_of_minutes(self):
        run(BASE + r'''fullScan(); F.Scan.last.at = F.Engine.clock() - 2 * 86400 - 60
        F.Engine.message = nil
        UI.show('deals:all')
        local summary, status = UI.summary:GetText(), UI.status:GetText()
        assert(summary:find('Scan: 2 d ago', 1, true), summary)
        assert(status:find('from the scan 2 d ago', 1, true), status)
        UI.show('bids')
        local empty = UI.bidTable.empty:GetText()
        assert(empty:find('The last full scan was 2 d ago:', 1, true), empty)''')


class UndercutCountTests(unittest.TestCase):
    def test_the_count_is_made_from_the_plans_of_the_rows(self):
        run(BASE + r'''local got, count = 'none', T.fightCount
        T.fightCount = function(plans) got = plans; return count(plans) end
        UI.show('undercuts')
        assert(type(got) == 'table', 'the plans already made are handed over: ' .. tostring(got))''')


class TooltipDealTests(unittest.TestCase):
    def test_a_closed_neutral_houses_deal_is_not_in_the_tooltip(self):
        runtime(open_ah=False).execute(SETUP + r'''local F = ForeverFlip
        F.db.settings.tooltipPrices = true
        function GetSubZoneText() return 'Ironforge' end
        fire('AUCTION_HOUSE_SHOW'); F.UI.frame:Show(); fullScan()
        fire('AUCTION_HOUSE_CLOSED')
        -- A Linen Bag at 10 silver at the neutral house, below its 20 silver vendor price.
        now = now + 1000
        function GetSubZoneText() return 'Gadgetzan' end
        addAuction(30, 1000, 1)
        fire('AUCTION_HOUSE_SHOW'); fullScan()
        local function dealLine()
            tooltipLines = {}
            GameTooltip.itemName, GameTooltip.itemLink = 'Linen Bag', link(30)
            for _, fn in ipairs(tooltipCalls) do fn(GameTooltip) end
            for _, l in ipairs(tooltipLines) do
                if tostring(l):find('Deal now', 1, true) then return l end
            end
        end
        assert(dealLine(), 'shown while the neutral house is open')
        fire('AUCTION_HOUSE_CLOSED'); F.UI.frame:Hide()
        assert(not dealLine(), 'not at the faction house the prices come from')''')


class BidCheckTests(unittest.TestCase):
    def test_check_all_leaves_out_bid_auctions_that_ended(self):
        run(BASE + r'''fullScan()
        local list = {
            { key = 'i:30', id = 30, count = 1, value = 100000, bid = 100, profit = 1000, ends = now + 3600 },
            { key = 'c:10', id = 10, count = 1, value = 100000, bid = 100, profit = 900, ends = now + 300 },
        }
        F.db.bidCandidates = { [F.Engine.scope()] = { at = now, list = list } }
        F.Bids.candidates, F.Bids.scope = list, F.Engine.scope()
        UI.show('bids')
        now = now + 600 -- the second auction ends before Check all is pressed
        local scope, keys = UI.statusTargets()
        assert(scope == 'bids' and #keys == 1 and keys[1] == 'i:30', table.concat(keys, ','))''')


class MessageTests(unittest.TestCase):
    def test_every_status_message_is_translated(self):
        source = (pathlib.Path(__file__).resolve().parent.parent / 'ForeverFlip' / 'UI.lua').read_text(encoding='utf-8')
        block = re.search(r'^local MESSAGES = \{\n(.*?)^\}', source, re.S | re.M).group(1)
        messages = dict(re.findall(r'^    (\w+) = "((?:[^"\\]|\\.)*)",', block, re.M))
        self.assertIn('not_number', messages)
        self.assertIn('share_too_large', messages)
        uk = runtime().eval('ForeverFlip.Locale.uk')
        missing = sorted(key for key, text in messages.items() if uk[unescape(text)] is None)
        self.assertEqual(missing, [])


if __name__ == '__main__':
    unittest.main()
