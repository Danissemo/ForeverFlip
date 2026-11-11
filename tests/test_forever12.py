"""Version 1.2: what other WoW Forever addons learned on the live server, and the features taken
from them (ForeverForge Auction, auxForever, AuctionHouse Forever, TSM, WOW4E AH Trader)."""

import unittest

from test_addon import SETUP, run, runtime

BUYBACK = '''
buyback = {}
function GetNumBuybackItems() return #buyback end
function GetBuybackItemLink(i) return link(buyback[i][1]) end
function GetBuybackItemInfo(i) local b = buyback[i]; return 'item', 0, b[2], b[3] end
local F = ForeverFlip
'''

REAL_HOOKS = '''
function hooksecurefunc(t, name, fn)
    local orig = t[name]
    t[name] = function(...) local a, b, c = orig(...); fn(...); return a, b, c end
end
ForeverFlip.Engine.replicateHooked = false
ForeverFlip.Engine.hookReplicate()
'''


class VendorPriceTests(unittest.TestCase):
    def test_unconfirmed_vendor_price_counts_less(self):
        run(SETUP + BUYBACK + '''F.db.settings.vendorMargin = 20
        local p, how = F.AH.vendorPrice(10)
        assert(p == 80 and how == 'estimate', p)
        p, how = F.AH.vendorPrice(10, true)
        assert(p == 100 and how == 'client')''')

    def test_the_price_a_merchant_paid_wins(self):
        run(SETUP + BUYBACK + '''F.db.settings.vendorMargin = 20
        buyback = { { 10, 300, 4 } }  -- 4 cloth sold for 3s: 75c each, the client says 1s
        assert(F.Merchant.learnBuyback() == 1)
        local p, how = F.AH.vendorPrice(10)
        assert(p == 75 and how == 'seen', p)
        local d = F.Merchant.differences()
        assert(#d == 1 and d[1].id == 10 and d[1].seen == 75 and d[1].client == 100)''')

    def test_damaged_gear_does_not_lower_the_learned_price(self):
        run(SETUP + BUYBACK + '''buyback = { { 20, 1070, 1 } }; F.Merchant.learnBuyback()
        buyback = { { 20, 500, 1 } }; F.Merchant.learnBuyback()
        assert(F.AH.vendorPrice(20) == 1070, 'a damaged sword sold for less')
        addItem(20, 'Northern Shortsword', 900, 'gear')  -- a patch changed the price
        F.Merchant.learnBuyback()
        assert(F.AH.vendorPrice(20) == 500, F.AH.vendorPrice(20))''')

    def test_a_learned_lower_price_removes_a_vendor_deal(self):
        run(SETUP + BUYBACK + '''buyback = { { 10, 50, 1 } }; F.Merchant.learnBuyback()
        fullScan()
        local d = F.Deals.get('c:10')
        assert(not (d and d.mode == 'vendor'), 'cloth at 60c is no deal when a vendor pays 50c')''')

    def test_vendor_deals_with_an_estimated_price_are_marked(self):
        run(SETUP + '''ForeverFlip.db.settings.vendorMargin = 10
        fullScan()
        local d = ForeverFlip.Deals.get('c:10')
        assert(d and d.mode == 'vendor' and d.vendorHow == 'estimate')''')


class ThrottleTests(unittest.TestCase):
    def test_a_stuck_throttle_lets_one_message_through(self):
        run(SETUP + '''local A = ForeverFlip.AH
        throttleReady = false
        assert(not A.ready())
        run(3); assert(not A.ready(), 'a short wait is normal'); assert((A.forced or 0) == 0)
        run(2.5); assert((A.forced or 0) >= 1, 'stuck for 5 seconds: one message went through')
        assert(not A.ready(), 'then it waits again')''')

    def test_the_ready_event_clears_the_watch(self):
        run(SETUP + '''local A = ForeverFlip.AH
        throttleReady = false; run(4)
        fire('AUCTION_HOUSE_THROTTLED_SYSTEM_READY')
        run(2); assert(not A.ready(), 'the 5 seconds start again')''')


class OwnerTests(unittest.TestCase):
    def test_the_player_token_and_names_with_a_realm_are_the_player(self):
        run(SETUP + '''local A = ForeverFlip.AH
        local me = UnitName('player')
        assert(A.isPlayer('player') and A.isPlayer(me) and A.isPlayer(me .. '-Some Realm'))
        assert(not A.isPlayer('Seller') and not A.isPlayer('') and not A.isPlayer(nil))''')


class GearSearchTests(unittest.TestCase):
    def test_gear_is_searched_by_browse_then_by_version(self):
        run(SETUP + '''enableBrowse()
        fullScan()
        local D, U = ForeverFlip.Deals, ForeverFlip.Util
        local key = U.key('gear', 20, 'Northern Shortsword of Nature Protection')
        assert(D.get(key))
        D.verify(key)
        local q = lastCall('SendBrowseQuery')
        assert(q and q[2].searchString == 'Northern Shortsword', 'browse by the plain name')
        assert(D.search.phase == 'browse')
        assert(not lastCall('SendSellSearchQuery'), 'the sell search is never answered on Forever')
        answer()
        assert(lastCall('SendSearchQuery')[2] == 20, 'then the version found')
        assert(D.get(key).verified, 'the deal is checked')''')

    def test_gear_nobody_sells_is_known_at_once(self):
        run(SETUP + '''enableBrowse()
        fullScan()
        local D, U = ForeverFlip.Deals, ForeverFlip.Util
        local key = U.key('gear', 20, 'Northern Shortsword of Nature Protection')
        for i = #auctions, 1, -1 do if auctions[i].item == 20 then table.remove(auctions, i) end end
        local got
        D.enqueue(key, function(_, rows, complete) got = { rows = rows, complete = complete } end)
        answer()
        assert(got and got.complete and #got.rows == 0, 'a full browse without it: nobody sells it')''')

    def test_without_browse_the_old_search_is_used(self):
        run(SETUP + '''fullScan()
        local D, U = ForeverFlip.Deals, ForeverFlip.Util
        D.verify(U.key('gear', 20, 'Northern Shortsword of Nature Protection'))
        assert(lastCall('SendSellSearchQuery'))''')


class FullScanTests(unittest.TestCase):
    def test_a_full_scan_another_addon_starts_is_caught_by_the_call(self):
        run(SETUP + REAL_HOOKS + '''local S = ForeverFlip.Scan
        C_AuctionHouse.ReplicateItems()
        assert(S.busy() and ForeverFlip.Engine.message == 'scan_other')
        assert(S.cooldown() > 800, 'the account window is used')
        fire('REPLICATE_ITEM_LIST_UPDATE')
        local n = 0
        while S.busy() do run(0.05); n = n + 1; assert(n < 20000) end
        assert(ForeverFlip.Deals.get('c:10'))''')

    def test_our_own_scan_is_not_taken_for_another_addons(self):
        run(SETUP + REAL_HOOKS + '''ForeverFlip.Engine.message = nil
        assert(ForeverFlip.Scan.start())
        assert(ForeverFlip.Engine.message ~= 'scan_other')''')

    def test_waiting_shows_the_seconds(self):
        run(SETUP + '''replicateIgnored = true; assert(ForeverFlip.Scan.start()); run(30)
        local key, done, total = ForeverFlip.Scan.progress()
        assert(key == 'scan_waiting' and done >= 29 and done <= 31 and total == 600)''')


class DisenchantTests(unittest.TestCase):
    def test_green_weapons_21_to_30_give_greater_magic_essence(self):
        run('''local DE = ForeverFlip.Disenchant
        local w = DE.outcomes(2, 25, 2); assert(w[2][1] == 10939, w[2][1])
        w = DE.outcomes(2, 28, 2); assert(w[2][1] == 10939)
        local a = DE.outcomes(2, 25, 4); assert(a[2][1] == 10998, 'armor keeps the astral essence')
        assert(DE.outcomes(2, 32, 2)[2][1] ~= 10939)''')

    def test_an_essence_is_worth_at_most_what_its_other_form_allows(self):
        run('''local DE = ForeverFlip.Disenchant
        local h = ForeverFlip.Data.market(ForeverFlip.db, ForeverFlip.Engine.scope()).history
        h['c:10938'] = { scan = { market = 500, at = now } }   -- lesser magic
        h['c:10939'] = { scan = { market = 900, at = now } }   -- greater magic
        assert(DE.materialPrice(h, 10938) == 300, 'three lesser make one greater')
        assert(DE.materialPrice(h, 10939) == 900)
        h['c:10938'].scan.market = 200
        assert(DE.materialPrice(h, 10939) == 600, 'a greater splits into three lesser')''')

    def test_own_disenchants_replace_the_table(self):
        run('''local F = ForeverFlip
        local DE = F.Disenchant
        local info = F.Util.itemInfo
        F.Util.itemInfo = function(id)
            if id == 40 then return 'Test Blade', nil, 2, 25, 20, '', '', 1, '', 0, 100, 2 end
            return info(id)
        end
        loot = {}
        function GetNumLootItems() return #loot end
        function GetLootSlotLink(i) return '|Hitem:' .. loot[i][1] .. ':|h[x]|h' end
        function GetLootSlotInfo(i) return 0, 'x', loot[i][2] end
        bags[0] = { [1] = { itemID = 40, stackCount = 1, isLocked = true } }
        assert(select(2, DE.outcomes(2, 25, 2)) == 'table')
        for i = 1, DE.LEARN do
            DE.onCast('player', nil, DE.SPELL)
            loot = { i % 3 == 0 and { 10939, 1 } or { 10940, 3 } }
            assert(DE.onLoot())
        end
        local out, how = DE.outcomes(2, 25, 2)
        assert(how == 'yours')
        local dust
        for _, o in ipairs(out) do if o[1] == 10940 then dust = o[2] end end
        assert(dust and math.abs(dust - 30 / 15) < 1e-9, dust)
        assert(not DE.onLoot(), 'loot without a disenchant is not counted')''')


class ShareChannelTests(unittest.TestCase):
    CHANNEL = '''sentMessages = {}
    C_ChatInfo = { RegisterAddonMessagePrefix = function() end,
        SendAddonMessage = function(prefix, text, channel, target)
            sentMessages[#sentMessages + 1] = { prefix, text, channel, target } end }
    function GetChannelName(name) return name == 'ForeverFlipPrices' and 5 or 0 end
    local S = ForeverFlip.Share
    local function sent(kind)
        for _, m in ipairs(sentMessages) do if m[2]:sub(1, #kind) == kind then return m end end
    end
    local function drain() for _ = 1, 400 do run(0.1) end end
    '''

    def test_a_new_scan_is_announced_and_sent_when_asked(self):
        run(SETUP + self.CHANNEL + '''fullScan(); drain()
        local h = sent('!H'); assert(h and h[3] == 'CHANNEL' and h[4] == 5, 'the new scan is announced')
        sentMessages = {}
        local at = ForeverFlip.Scan.last.at
        S.onMessage('ForeverFlip', '!R|' .. UnitName('player') .. '|' .. 'Realm-Alliance|' .. S.enc(at), 'CHANNEL', 'Other-Realm')
        drain()
        local data = 0
        for _, m in ipairs(sentMessages) do if m[2]:sub(1, 1) ~= '!' then data = data + 1 end end
        assert(data > 0, 'the scan goes out on the channel')''')

    def test_a_question_is_answered_by_one_player(self):
        run(SETUP + self.CHANNEL + '''fullScan(); drain(); sentMessages = {}
        S.onMessage('ForeverFlip', '!Q|Realm-Alliance|0', 'CHANNEL', 'Other-Realm')
        drain()
        assert(sent('!H'), 'an older scan is asked for: we have a newer one')
        sentMessages = {}
        S.heard['Realm-Alliance'] = ForeverFlip.Scan.last.at + 1
        S.onMessage('ForeverFlip', '!Q|Realm-Alliance|0', 'CHANNEL', 'Other-Realm')
        drain()
        assert(not sent('!H'), 'someone already announced a newer scan')''')

    def test_an_announced_newer_scan_is_requested(self):
        run(SETUP + self.CHANNEL + '''ForeverFlip.db.settings.shareChannel = true
        S.onMessage('ForeverFlip', '!H|Realm-Alliance|' .. S.enc(now - 60), 'CHANNEL', 'Holder-Realm')
        drain()
        local r = sent('!R'); assert(r and r[2]:find('Holder', 1, true), 'asked the holder')''')

    def test_prices_far_from_the_known_ones_are_left_out(self):
        run(SETUP + '''fullScan()
        local S = ForeverFlip.Share
        local snap = S.snapshot()
        snap.at = now + 300
        for _, it in ipairs(snap.items) do if it.key == 'c:10' then it.m = it.m * 50 end end
        S.merge(snap, 'Bad', 'CHANNEL')
        local h = ForeverFlip.Data.market(ForeverFlip.db, 'Realm-Alliance').history['c:10']
        assert(not h.shared or h.shared.from ~= 'Bad', 'a 50x price is not merged')''')


class SafetyTests(unittest.TestCase):
    def test_the_spending_limit_stops_buying(self):
        run(SETUP + '''fullScan(); local D, T = ForeverFlip.Deals, ForeverFlip.Trade
        ForeverFlip.db.settings.spendLimit = 1   -- 1 gold
        ForeverFlip.Engine.spent = 9500
        D.verify('c:10'); answer()
        local ok, why = T.buy('c:10'); assert(not ok and why == 'spend_limit', why)
        ForeverFlip.Engine.spent = 0
        assert(T.buy('c:10'))''')

    def test_cheap_lots_are_left_for_others(self):
        run('''local M = ForeverFlip.Market
        local rows = { { unit = 60, qty = 5 }, { unit = 60, qty = 5 }, { unit = 70, qty = 5 }, { unit = 200, qty = 5 } }
        local d = M.evaluate(rows, { kind = 'commodity', vendor = 100, budget = 1000000, settings = { leaveLots = 4 } })
        assert(d.mode == 'vendor' and d.qty == 11, d.qty)
        d = M.evaluate(rows, { kind = 'commodity', vendor = 100, budget = 1000000, settings = { leaveLots = 15 } })
        assert(not d, 'everything left')''')

    def test_buy_next_selects_checks_then_buys(self):
        run(SETUP + '''fullScan(); local E, D, UI = ForeverFlip.Engine, ForeverFlip.Deals, ForeverFlip.UI
        UI.selected = nil
        E.keyBuyNext()
        local key = UI.selected; assert(key and D.searching(), 'the best deal is selected and checked')
        answer()
        E.keyBuyNext()
        assert(ForeverFlip.Trade.op, 'the next press buys it')''')

    def test_missing_saved_data_asks_the_player(self):
        lua = runtime(open_ah=False)
        lua.execute('''shown = nil
        StaticPopupDialogs = {}
        function StaticPopup_Show(name) shown = name end
        ForeverFlipData = nil
        fire('ADDON_LOADED', 'ForeverFlip')
        assert(shown == 'FOREVERFLIP_NO_DATA' and ForeverFlip.Engine.noSavedData)
        shown = nil
        fire('ADDON_LOADED', 'ForeverFlip')
        assert(not shown, 'data that was read is not questioned')''')


class OtherTests(unittest.TestCase):
    def test_hardcore_realms_have_their_own_house(self):
        run(SETUP + '''Enum = Enum or {}; Enum.GameRule = { HardcoreRuleset = 7 }
        C_GameRules = { IsGameRuleActive = function(rule) return rule == 7 end }
        assert(ForeverFlip.Engine.scope() == 'Realm (HC)-Alliance', ForeverFlip.Engine.scope())
        C_GameRules = nil
        assert(ForeverFlip.Engine.scope() == 'Realm-Alliance')''')

    def test_tooltip_advice_names_the_best_way_to_sell(self):
        run(SETUP + '''fullScan()
        local M = ForeverFlip.Market
        local h = ForeverFlip.Data.market(ForeverFlip.db, ForeverFlip.Engine.scope()).history
        local a = M.advice(10, 'c:10', h['c:10'])
        assert(a and a.best == 'vendor' and a.value == 100, 'cloth: the vendor pays more than the AH after costs')
        h['i:30'] = { scan = { market = 50000, at = now } }
        a = M.advice(30, 'i:30', h['i:30'])
        assert(a.best == 'auction' and a.auction < 50000)''')

    def test_six_menu_entries_with_tabs_for_grouped_pages(self):
        run(SETUP + '''local UI = ForeverFlip.UI
        assert(#UI.categories == 6, #UI.categories)
        UI.show('bids')
        local deals = UI.categories[1]
        assert(deals.selected:IsShown(), 'bids belong to Deals')
        local tabs = UI.groupTabs[deals.group]
        assert(#tabs == 5)
        local shown, current = 0, nil
        for _, b in ipairs(tabs) do
            if b:IsShown() then shown = shown + 1 end
            if b.id == 'bids' then current = b end
        end
        assert(shown == 5 and not current:IsEnabled(), 'the open page is the disabled tab')
        UI.show('stats'); UI.categories[1].scripts.OnClick(UI.categories[1])
        assert(UI.section == 'bids', 'a group opens the page it showed last')
        UI.show('settings')
        for _, b in ipairs(tabs) do assert(not b:IsShown()) end''')

    def test_shopping_for_a_craft_counts_what_the_bags_hold(self):
        run(SETUP + '''fullScan()
        function GetItemCount(id) return id == 10 and 7 or 0 end
        C_Item.GetItemCount = nil
        local C = ForeverFlip.Crafting
        assert(C.have(10) == 7)''')


if __name__ == '__main__':
    unittest.main()
