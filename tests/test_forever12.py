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
        assert(A.isPlayer('player') and A.isPlayer(me) and A.isPlayer(me .. '-' .. GetRealmName()))
        assert(not A.isPlayer(me .. '-OtherRealm'), 'names are not unique: another realm is somebody else')
        assert(not A.isPlayer('Seller') and not A.isPlayer('') and not A.isPlayer(nil))''')


class OwnLotTests(unittest.TestCase):
    def test_own_lots_named_player_or_with_a_realm_are_skipped_in_the_scan(self):
        run(SETUP + '''local me = UnitName('player')
        addAuction(10, 10, 5, 'player')
        addAuction(10, 11, 5, me .. '-' .. GetRealmName())
        addAuction(10, 12, 5, me .. '-OtherRealm')  -- a namesake
        fullScan()
        assert(ForeverFlip.Scan.last.own == 3, ForeverFlip.Scan.last.own)''')


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

    def test_a_browse_of_the_player_is_not_taken_for_the_gear_search(self):
        run(SETUP + '''enableBrowse()
        function hooksecurefunc(t, name, fn)
            local orig = t[name]
            t[name] = function(...) local a, b = orig(...); fn(...); return a, b end
        end
        ForeverFlip.AH.browseHooked = false; ForeverFlip.AH.hookBrowse()
        fullScan()
        local D, U = ForeverFlip.Deals, ForeverFlip.Util
        local key = U.key('gear', 20, 'Northern Shortsword of Nature Protection')
        for i = #auctions, 1, -1 do if auctions[i].item == 20 then table.remove(auctions, i) end end
        local got
        D.enqueue(key, function(_, rows, complete) got = { rows = rows, complete = complete } end)
        C_AuctionHouse.SendBrowseQuery({ searchString = 'Linen' })  -- the player, in the Buy tab
        browseAnswer()
        assert(got and not got.complete and got.rows == nil, 'unknown, not "nobody sells it"')''')

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
        assert(key == 'scan_waiting' and done >= 29 and done <= 31 and total == ForeverFlip.Scan.ANSWER_WAIT)''')


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
        DE.onCast('UNIT_SPELLCAST_START', 'player', 'g1', DE.SPELL)
        DE.onCast('UNIT_SPELLCAST_INTERRUPTED', 'player', 'g1', DE.SPELL)
        loot = { { 2589, 2 } }
        assert(not DE.onLoot(), 'an interrupted cast: the next loot is not a disenchant')
        DE.onCast('UNIT_SPELLCAST_START', 'player', 'g2', DE.SPELL)
        DE.onCast('UNIT_SPELLCAST_FAILED', 'player', 'g3', DE.SPELL)  -- a second press while casting
        loot = { { 10940, 2 } }
        assert(DE.onLoot(), 'the running cast still counts, also with the loot before SUCCEEDED')
        F.db.deSeen = {}
        for i = 1, DE.LEARN do
            DE.onCast('UNIT_SPELLCAST_START', 'player', nil, DE.SPELL)
            DE.onCast('UNIT_SPELLCAST_SUCCEEDED', 'player', nil, DE.SPELL)
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


class WholeCodeReviewTests(unittest.TestCase):
    def test_a_faction_auctioneer_means_the_faction_house_in_any_zone(self):
        run(SETUP + '''local E = ForeverFlip.Engine
        C_Map = { GetBestMapForUnit = function() return 1434 end }  -- Stranglethorn Vale
        function UnitExists(u) return u == 'npc' end
        npcFaction = 'Alliance'
        local real = UnitFactionGroup
        UnitFactionGroup = function(u) if u == 'npc' then return npcFaction end return real(u) end
        assert(E.detectHouse() == nil, 'an Alliance auctioneer is the Alliance house')
        npcFaction = nil
        assert(E.detectHouse() == 'Neutral', 'a goblin auctioneer in a neutral town')''')

    def test_rows_that_never_loaded_are_not_booked_as_sold(self):
        run(SETUP + '''enableTimeLeft(); local F = ForeverFlip
        fullScan()
        local h = F.Data.market(F.db, F.Engine.scope()).history['c:10']
        assert(h.lots, 'lots of the first scan')
        -- The next scan cannot read cloth's rows (item data never loads in time).
        items[10].cached = false
        now = now + 901; F.db.lastScan = 0; fullScan()
        assert((F.Market.demandAt(h, 60).sold or 0) == 0, 'unread rows are not sales')
        assert(h.lots, 'the lots stay for the next full scan')''')

    def test_a_far_smaller_scan_books_no_vanished_sales(self):
        run(SETUP + '''enableTimeLeft(); local F = ForeverFlip
        for i = 1, 40 do addAuction(30, 30000 + i, 1) end
        fullScan()
        for i = #auctions, 1, -1 do if auctions[i].item == 30 then table.remove(auctions, i) end end
        now = now + 901; F.db.lastScan = 0; fullScan()
        local h = F.Data.market(F.db, F.Engine.scope()).history['i:30']
        assert((F.Market.demandAt(h, 30000).sold or 0) == 0, 'a scan with most auctions missing is partial')
        assert(h.lots, 'the lots stay for the next full scan')''')

    def test_opening_another_house_shows_its_own_scan(self):
        run(SETUP + '''local F = ForeverFlip
        fullScan(); assert(#F.Deals.list > 0)
        fire('AUCTION_HOUSE_CLOSED')
        F.Engine.detectHouse = function() return 'Neutral' end
        fire('AUCTION_HOUSE_SHOW')
        assert(F.Engine.scope() == 'Realm-Neutral')
        assert(F.Scan.last == nil and #F.Deals.list == 0, 'no Alliance deals at the neutral house')''')

    def test_an_invoice_after_the_owned_list_does_not_book_the_sale_twice(self):
        run(SETUP + '''local F, T = ForeverFlip, ForeverFlip.Trade
        local c = F.Data.char(F.db, F.Engine.owner())
        F.Data.addPosition(c, 'i:30', 'Linen Bag', 3, 3000, 'flip', 5000, now)
        c.listings = { { key = 'i:30', name = 'Linen Bag', ids = { 77 }, open = 3, price = 5000, at = now } }
        owned = { { auctionID = 77, itemKey = { itemID = 30 }, quantity = 1, buyoutAmount = 5000, status = 1 } }
        fire('OWNED_AUCTIONS_UPDATED')
        local afterOwned = c.positions['i:30'] and c.positions['i:30'].qty
        T.onInvoice({ item = 'Linen Bag', count = 1, bid = 5000, cut = 250 })
        local afterInvoice = c.positions['i:30'] and c.positions['i:30'].qty
        assert(afterOwned == afterInvoice, tostring(afterOwned) .. ' vs ' .. tostring(afterInvoice))''')


class SniperGearTests(unittest.TestCase):
    def test_a_sniper_check_of_gear_completes_without_an_error(self):
        run(SETUP + '''enableBrowse(); fullScan()
        local D, U = ForeverFlip.Deals, ForeverFlip.Util
        local key = U.key('gear', 20, 'Northern Shortsword of Nature Protection')
        local errs = {}
        ForeverFlip.Engine.report = function(e) errs[#errs + 1] = tostring(e) end
        assert(D.request(key, D.verifyCallback, 'sniper', true))
        answer(); run(1)
        assert(#errs == 0, table.concat(errs, ' | '))
        assert(D.get(key) and D.get(key).verified, 'the gear deal is checked')''')


class ScanAnswerTests(unittest.TestCase):
    def test_an_answer_of_the_same_size_is_noticed_without_the_event(self):
        run(SETUP + '''local S = ForeverFlip.Scan
        fullScan()
        now = now + 901; ForeverFlip.db.lastScan = 0
        assert(S.start())
        -- The server's answer: the same number of auctions, one price changed (the fake client
        -- keeps references, so the change made now is what the answer holds).
        auctions[1].buyout = auctions[1].buyout + 5
        run(3)
        assert(S.job == nil or S.job.state ~= 'waiting', 'the new list was noticed by polling')''')

    def test_searches_wait_for_the_whole_scan(self):
        run(SETUP + '''local S = ForeverFlip.Scan
        replicateIgnored = true; assert(S.start()); run(90)
        assert(S.blocking(), 'the sniper and checks wait while the answer is awaited')''')


class TrackingTests(unittest.TestCase):
    MAIL = SETUP + """local F, T = ForeverFlip, ForeverFlip.Trade
    local c = F.Data.char(F.db, F.Engine.owner())
    function GetInboxItemLink(i) return inbox[i] and inbox[i].link end
    MailFrame:Show(); fire('MAIL_SHOW')
    """

    def test_a_purchase_made_outside_foreverflip_is_booked_from_its_mail(self):
        run(self.MAIL + """inbox = { { sender = 'Auction House', subject = 'Auction won: Linen Bag', items = 1, link = link(30),
            invoice = { kind = 'buyer', item = 'Linen Bag', bid = 25000, count = 1 } } }
        fire('MAIL_INBOX_UPDATE'); F.Mail.record(1)
        local p = c.positions['i:30']
        assert(p and p.qty == 1 and p.cost == 25000 and p.mode == 'other', 'booked as bought elsewhere')""")

    def test_a_purchase_of_foreverflip_is_not_booked_again_by_its_mail(self):
        run(self.MAIL + """F.Data.addPosition(c, 'c:10', 'Linen Cloth', 5, 300, 'vendor', 100, now)
        c.awaitMail = { ['linen cloth'] = { n = 5, at = now } }
        inbox = { { sender = 'Auction House', subject = 'Auction won: Linen Cloth (5)', items = 1, link = link(10),
            invoice = { kind = 'buyer', item = 'Linen Cloth', bid = 300, count = 5 } } }
        fire('MAIL_INBOX_UPDATE'); F.Mail.record(1)
        assert(c.positions['c:10'].qty == 5, c.positions['c:10'].qty)""")

    def test_a_sale_to_a_merchant_by_hand_is_booked(self):
        run(SETUP + """local F = ForeverFlip
        local c = F.Data.char(F.db, F.Engine.owner())
        F.Data.addPosition(c, 'c:10', 'Linen Cloth', 5, 300, 'vendor', 100, now)
        buyback = {}
        function GetNumBuybackItems() return #buyback end
        function GetBuybackItemLink(i) return link(buyback[i][1]) end
        function GetBuybackItemInfo(i) local b = buyback[i]; return 'x', 0, b[2], b[3] end
        F.Merchant.watchBuyback(true)
        buyback = { { 10, 500, 5 } }
        F.Merchant.watchBuyback(false)
        assert(not c.positions['c:10'], 'the stock was sold')
        local e = c.journal[#c.journal]
        assert(e.kind == 'vendor' and e.amount == 500 and e.profit == 200)""")

    def test_the_sell_vendor_deals_button_is_not_booked_twice(self):
        run(SETUP + """local F = ForeverFlip
        local c = F.Data.char(F.db, F.Engine.owner())
        F.Data.addPosition(c, 'c:10', 'Linen Cloth', 10, 600, 'vendor', 100, now)
        buyback = {}
        function GetNumBuybackItems() return #buyback end
        function GetBuybackItemLink(i) return link(buyback[i][1]) end
        function GetBuybackItemInfo(i) local b = buyback[i]; return 'x', 0, b[2], b[3] end
        F.Merchant.watchBuyback(true)
        F.Merchant.expectSale(10, 5)
        F.Trade.onVendorSale('c:10', 5, 100)   -- what the button books itself
        buyback = { { 10, 500, 5 } }
        F.Merchant.watchBuyback(false)
        assert(c.positions['c:10'].qty == 5, c.positions['c:10'].qty)""")


class TooltipTests(unittest.TestCase):
    def lines(self, code):
        import re
        return re.sub(r'\|c[0-9a-fA-F]{8}|\|r', '', self._lines(code))

    def _lines(self, code):
        return run(SETUP + code + """
        tooltipLines = {}
        for _, fn in ipairs(tooltipCalls) do fn(GameTooltip) end
        return table.concat(tooltipLines, ' ## ')""")

    def test_the_tooltip_names_the_house_stock_and_auctions(self):
        text = self.lines("""fullScan()
        local F = ForeverFlip
        local c = F.Data.char(F.db, F.Engine.owner())
        F.Data.addPosition(c, 'c:10', 'Linen Cloth', 4, 200, 'flip', 100, now)
        F.Trade.owned = { { key = 'c:10', qty = 2, price = 160, sold = false } }
        GameTooltip.itemLink = link(10)""")
        self.assertIn('ForeverFlip: Alliance AH', text)
        self.assertIn('You hold = 4, paid 50c each', text)
        self.assertIn('On sale by you = 2 at 80c', text)
        self.assertIn('Vendor pays', text)
        self.assertNotIn('= -', text.split('Auction house')[1].split('##')[0], 'cloth posted as a stack does not lose to deposits')

    def test_an_item_without_history_still_shows_stock_and_vendor(self):
        text = self.lines("""local F = ForeverFlip
        local c = F.Data.char(F.db, F.Engine.owner())
        F.Data.addPosition(c, 'i:30', 'Linen Bag', 1, 1000, 'other', nil, now)
        GameTooltip.itemLink = link(30)""")
        self.assertIn('You hold = 1', text)
        self.assertIn('Best: sell to a vendor', text)

    def test_sales_not_measured_yet_are_said_so(self):
        text = self.lines("""fullScan(); GameTooltip.itemLink = link(10)""")
        self.assertIn('not measured yet', text)


class HouseBadgeTests(unittest.TestCase):
    def test_the_corner_names_the_open_auction_house(self):
        run(SETUP + '''local F, UI = ForeverFlip, ForeverFlip.UI
        UI.refresh()
        assert(UI.houseBadge:GetText():find('Alliance AH', 1, true), UI.houseBadge:GetText())
        F.Engine.house = 'Neutral'; UI.refresh()
        assert(UI.houseBadge:GetText():find('Neutral AH, 15% cut', 1, true), UI.houseBadge:GetText())''')


class SellPageTests(unittest.TestCase):
    def test_bag_items_the_auction_house_does_not_know_yet_are_listed(self):
        run(SETUP + '''local A = ForeverFlip.AH
        addItem(77, 'Bruiseweed', 10, 'commodity')
        local info = C_AuctionHouse.GetItemKeyInfo
        C_AuctionHouse.GetItemKeyInfo = function(key) if key.itemID == 77 then return nil end return info(key) end
        Enum = Enum or {}
        Enum.ItemCommodityStatus = { Unknown = 0, Item = 1, Commodity = 2 }
        C_AuctionHouse.GetItemCommodityStatus = function(loc) return 2 end
        putBag(0, 1, 77, 10)
        local found
        for _, b in ipairs(A.bagItems()) do if b.id == 77 then found = b end end
        assert(found and found.kind == 'commodity' and found.key == 'c:77')''')

    def test_the_reagent_bag_is_read(self):
        run(SETUP + '''local A = ForeverFlip.AH
        Enum = Enum or {}; Enum.BagIndex = { ReagentBag = 5 }
        putBag(5, 1, 10, 20)
        local found
        for _, b in ipairs(A.bagItems()) do if b.bag == 5 then found = b end end
        assert(found and found.key == 'c:10')''')


class ReviewTests(unittest.TestCase):
    def test_hardcore_scans_are_merged_and_cuts_learned_for_the_hardcore_house(self):
        run(SETUP + '''Enum = Enum or {}; Enum.GameRule = { HardcoreRuleset = 7 }
        C_GameRules = { IsGameRuleActive = function(rule) return rule == 7 end }
        local F = ForeverFlip
        fullScan()
        local snap = F.Share.snapshot(); snap.at = now + 300
        assert(snap.scope == 'Realm (HC)-Alliance')
        assert(F.Share.merge(snap, 'Friend', 'GUILD'), 'a scan of the same hardcore realm is merged')
        assert(F.Engine.realm() == 'Realm (HC)')''')

    def test_a_request_naming_the_holder_with_the_realm_is_served(self):
        run(SETUP + '''sentMessages = {}
        C_ChatInfo = { RegisterAddonMessagePrefix = function() end,
            SendAddonMessage = function(_, text, ch) sentMessages[#sentMessages + 1] = text end }
        function GetChannelName() return 5 end
        local S = ForeverFlip.Share
        fullScan()
        local at = ForeverFlip.Scan.last.at
        S.onMessage('ForeverFlip', '!R|' .. UnitName('player') .. '-' .. GetRealmName() .. '|Realm-Alliance|' .. S.enc(at),
            'CHANNEL', 'Other-Realm')
        assert(#S.outbox > 0, 'the scan is sent')''')

    def test_the_newest_scan_held_counts_merged_scans_after_a_reload(self):
        run(SETUP + '''local S = ForeverFlip.Share
        ForeverFlip.db.sharedSeen = { ['Realm-Alliance@' .. (now - 100)] = now }
        assert(S.newest('Realm-Alliance') == now - 100)''')

    def test_buy_next_skips_a_selected_deal_that_cannot_be_bought(self):
        run(SETUP + '''fullScan(); local E, D, UI = ForeverFlip.Engine, ForeverFlip.Deals, ForeverFlip.UI
        local best = D.best(); assert(best)
        UI.selected = 'i:30'
        D.list[#D.list + 1] = { key = 'i:30', cost = money + 1, profit = 1, mode = 'vendor', qty = 1 }
        E.keyBuyNext()
        assert(UI.selected == best.key, 'the affordable best deal is taken')''')

    def test_a_gear_check_waits_for_the_sniper_query_in_flight(self):
        run(SETUP + '''enableBrowse(); fullScan()
        local D, U, Sn = ForeverFlip.Deals, ForeverFlip.Util, ForeverFlip.Sniper
        Sn.query = { kind = 'keys', at = GetTime(), read = 0 }
        assert(not D.request(U.key('gear', 20, 'Northern Shortsword of Nature Protection')),
            'not started while the sniper waits for its answer')
        Sn.query = nil; run(1.1)
        assert(not D.search); assert(D.request(U.key('gear', 20, 'Northern Shortsword of Nature Protection')))''')

    def test_a_dropped_full_scan_request_is_tried_again_soon(self):
        run(SETUP + '''replicateIgnored = true; local S = ForeverFlip.Scan
        assert(S.start()); fire('AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED')
        assert(not S.busy() and S.cooldown() <= 10, S.cooldown())''')

    def test_a_buyback_price_per_unit_is_rounded_down(self):
        run(SETUP + BUYBACK + '''buyback = { { 10, 5, 2 } }; F.Merchant.learnBuyback()
        assert(F.AH.vendorPrice(10) == 2)''')


if __name__ == '__main__':
    unittest.main()
