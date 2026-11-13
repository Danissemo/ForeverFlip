"""Review fixes in AH.lua, Mail.lua and Merchant.lua: keys, kinds, deposits, browse learning, bids,
auction mail and merchant offers."""

import unittest

from test_addon import SETUP, run
from test_audit import AXE

BASE = SETUP + '''local F, T = ForeverFlip, ForeverFlip.Trade
local c = F.Data.char(F.db, F.Engine.owner())
local EMPTY = '|cff1eff00|Hitem:20::|h[]|h|r'
'''

MAIL = BASE + '''local function said(text)
    for _, l in ipairs(printed) do if l:find(text, 1, true) then return true end end
    return false
end
local function summary(gold, items)
    return string.format(F.Locale.text('auction mail taken: %s gold, %d items'), F.Util.money(gold), items)
end
local function failed() return c.rates and c.rates['linen bag'] and c.rates['linen bag'].failed or 0 end
'''

MERCHANT = BASE + '''addItem(60, 'Fine Thread', 5, 'commodity')
local h = F.Data.market(F.db, F.Engine.scope()).history
h['c:60'] = { scan = { at = now, market = 500 },
    flow = { hours = 20, sold = { 48, 48, 48, 48 }, pairs = 3, at = now, market = 500 } }
merchantItems = { { id = 60, price = 100 } }
'''


class KeyTests(unittest.TestCase):
    def test_gear_with_endings_gets_no_key_from_a_link_without_a_name(self):
        run(BASE + '''fullScan() -- the shortsword is listed only with endings ("of Healing")
        assert(F.AH.keyFor(20, EMPTY) == nil, 'its own name names no lot')
        owned = { { auctionID = 5, itemKey = { itemID = 20, itemLevel = 18, itemSuffix = 0 }, itemLink = EMPTY,
            quantity = 1, buyoutAmount = 700, status = 0, timeLeftSeconds = 14400 } }
        fire('OWNED_AUCTIONS_UPDATED')
        assert(T.owned[1].key == nil, 'read again later: ' .. tostring(T.owned[1].key))
        owned[1].itemLink = link(20, 'Northern Shortsword of Healing')
        fire('OWNED_AUCTIONS_UPDATED')
        assert(T.owned[1].key == 'g:20:northern shortsword of healing', tostring(T.owned[1].key))''')

    def test_endings_searched_before_count_and_gear_without_endings_keeps_its_name(self):
        run(BASE + '''F.db.itemKeys = { [20] = { at = now, list = { { l = 18, s = 0, n = 'northern shortsword',
            e = 'northern shortsword of healing' } } } }
        assert(F.AH.keyFor(20, EMPTY) == nil, 'a version searched before carries an ending')
        addItem(82, 'Sharp Throwing Axe', 1200, 'gear')
        local key = F.AH.keyFor(82, '|cffffffff|Hitem:82::|h[]|h|r')
        assert(key == 'g:82:sharp throwing axe', tostring(key))''')


class BagKindTests(unittest.TestCase):
    KINDS = BASE + '''Enum.ItemCommodityStatus = { Unknown = 0, Item = 1, Commodity = 2 }
    C_AuctionHouse.GetItemCommodityStatus = function() return 1 end
    C_Item.GetItemInfoInstant = function(id)
        if id == 30 then return 30, 'Container', 'Bag', 'INVTYPE_BAG', 133, 1, 0 end
        if id == 31 then return 31, 'Weapon', 'Sword', 'INVTYPE_WEAPON', 133, 2, 7 end
        return id
    end
    addItem(31, 'Odd Blade', 500, 'item') -- the auction house will not call it equipment
    local keyInfo, known = C_AuctionHouse.GetItemKeyInfo, false
    C_AuctionHouse.GetItemKeyInfo = function(k)
        if (k.itemID == 30 or k.itemID == 31) and not known then return nil end
        return keyInfo(k)
    end
    putBag(0, 1, 30, 1); putBag(0, 2, 31, 1)
    local function keys()
        now = now + 1
        local out = {}
        for _, b in ipairs(F.AH.bagItems()) do out[b.id] = b.key end
        return out
    end
    '''

    def test_a_bag_is_no_gear_before_the_auction_house_tells_its_kind(self):
        run(self.KINDS + '''local before = keys()
        assert(before[30] == 'i:30', tostring(before[30]))
        known = true
        assert(keys()[30] == 'i:30', 'the same key once the auction house answered')''')

    def test_a_guessed_kind_gives_way_to_the_auction_house_answer(self):
        run(self.KINDS + '''assert(keys()[31] == 'g:31:odd blade', 'a weapon is guessed gear')
        known = true
        assert(F.AH.kindOf(31) == 'item' and keys()[31] == 'i:31', tostring(F.AH.kindOf(31)))''')


class DepositTests(unittest.TestCase):
    def test_a_failed_deposit_read_is_asked_again(self):
        run(BASE + '''local A = F.AH
        A.resetDeposits()
        C_AuctionHouse.CalculateCommodityDeposit = function(_, _, q)
            if not AuctionHouseFrame:IsShown() then return nil end
            return 100 * q
        end
        AuctionHouseFrame:Hide()
        assert(A.depositFn(10, 'commodity', 3) == nil, 'no answer away from the auction house')
        AuctionHouseFrame:Show()
        local fn = A.depositFn(10, 'commodity', 3)
        assert(fn and fn(1) == 100 and fn(20) == 2000, 'asked again at the auction house')
        local answer
        C_AuctionHouse.CalculateCommodityDeposit = function(_, _, q) return answer and answer * q end
        assert(A.depositFn(10, 'commodity', 2) == nil)
        answer = 50
        assert(A.depositFn(10, 'commodity', 2) == nil, 'not asked again at once')
        now = now + A.DEPOSIT_RETRY + 1
        fn = A.depositFn(10, 'commodity', 2)
        assert(fn and fn(1) == 50, 'asked again a while later')''')

    def test_deposits_are_kept_per_house(self):
        run(BASE + '''local A = F.AH
        A.resetDeposits()
        local per = 100
        C_AuctionHouse.CalculateCommodityDeposit = function(_, _, q) return per * q end
        C_AuctionHouse.CalculateItemDeposit = function() return per end
        assert(A.depositFn(10, 'commodity', 3)(1) == 100)
        A.learnDeposit({ id = 30, kind = 'item', loc = {} }, 3)
        F.Engine.house, per = 'Neutral', 500
        assert(A.depositFn(10, 'commodity', 3)(1) == 500, 'the neutral house tells its own')
        assert(A.depositFn(30, 'item', 3) == nil, 'a faction house deposit is no neutral one')
        A.learnDeposit({ id = 30, kind = 'item', loc = {} }, 3)
        assert(A.depositFn(30, 'item', 3)(2) == 1000)
        F.Engine.house = nil
        assert(A.depositFn(10, 'commodity', 3)(1) == 100 and A.depositFn(30, 'item', 3)(2) == 200)''')


class BrowseKeyTests(unittest.TestCase):
    BROWSE = BASE + '''for i = 1, 25 do
        addItem(1000 + i, 'Thing ' .. i, 10, 'item'); addAuction(1000 + i, 500 + i, 1)
    end
    enableBrowse(10)
    local calls, remember = 0, F.AH.rememberKey
    F.AH.rememberKey = function(...) calls = calls + 1; return remember(...) end
    local function round()
        F.AH.browse()
        while browsePendingNow() do
            browseAnswer()
            if not F.AH.browseFull() then F.AH.browseMore() end
        end
    end
    '''

    def test_each_browse_row_is_learned_once_per_browse(self):
        run(self.BROWSE + '''round()
        local rows = #C_AuctionHouse.GetBrowseResults()
        assert(rows > 20 and calls == rows, calls .. ' reads of ' .. rows .. ' rows')
        round()
        assert(calls == 2 * rows, 'a new browse learns its rows again: ' .. calls)
        assert(F.db.itemKeys[1025].at == F.Engine.clock())''')

    def test_item_keys_not_seen_for_two_weeks_are_forgotten(self):
        run(self.BROWSE + '''F.db.itemKeys = { [998] = { at = now - 86400, list = { { l = 0, s = 0 } } },
            [999] = { at = now - 15 * 86400, list = { { l = 0, s = 0 } } } }
        round()
        assert(F.db.itemKeys[998] and not F.db.itemKeys[999] and F.db.itemKeys[1001])''')


class ItemQueueTests(unittest.TestCase):
    def test_item_data_requests_go_out_in_order_up_to_the_cap(self):
        run(BASE + '''local A = F.AH
        requestedItems = {}
        A.ITEM_QUEUE = 4000
        for id = 500001, 504100 do A.requestItem(id) end
        local t = now
        for _ = 1, 1100 do t = t + 0.2; A.pump(t) end
        assert(#requestedItems == 4000, #requestedItems)
        for i = 1, 4000 do assert(requestedItems[i] == 500000 + i, i) end
        A.requestItem(600001); A.requestItem(600002)
        t = t + 0.2; A.pump(t)
        assert(requestedItems[4001] == 600001 and requestedItems[4002] == 600002)''')


class BidTests(unittest.TestCase):
    def test_a_bid_led_by_another_player_is_not_leading(self):
        run(BASE + '''local function leading(bidder)
            myBids = { { auctionID = 77, itemKey = { itemID = 30 }, minBid = 700, bidAmount = 650, bidder = bidder } }
            return F.AH.bids()[1].leading
        end
        assert(leading('Player-2') == false and leading('Player-1') == true and leading(nil) == nil)''')

    def test_an_auction_of_another_character_of_the_account_takes_no_bid(self):
        run(BASE + '''local rows = { { auctionID = 11, minBid = 500, quantity = 1, containsAccountItem = true },
            { auctionID = 12, minBid = 600, quantity = 1 } }
        C_AuctionHouse.GetNumItemSearchResults = function() return #rows end
        C_AuctionHouse.GetItemSearchResultInfo = function(_, i) return rows[i] end
        local out = F.AH.bidRows({ id = 30, kind = 'item' })
        assert(#out == 1 and out[1].auctionID == 12, #out)''')


class MailTests(unittest.TestCase):
    def test_identical_auction_mails_are_all_taken_and_counted(self):
        run(MAIL + '''mailEvents = true -- an emptied mail leaves the inbox with an update, as in the game
        inbox = {}
        for i = 1, 8 do
            inbox[i] = { sender = 'Auction House', subject = 'Auction successful: Linen Bag', money = 1900,
                invoice = { kind = 'seller', item = 'Linen Bag', bid = 2000, cut = 100, count = 1 } }
        end
        MailFrame:Show(); fire('MAIL_SHOW'); F.Mail.start()
        for _ = 1, 80 do run(0.1) end
        assert(#inbox == 0 and F.Engine.message == 'mail_done', #inbox .. ' left: ' .. tostring(F.Engine.message))
        assert(said(summary(8 * 1900, 0)), printed[#printed])''')

    def test_a_mail_the_game_refuses_is_neither_counted_nor_booked(self):
        run(MAIL + '''inbox = { { sender = 'Auction House', subject = 'Auction expired: Linen Bag', items = 1 } }
        local loot, refuse = AutoLootMailItem, true
        AutoLootMailItem = function(i) if not refuse then return loot(i) end end
        -- the game's own mailbox buttons, hooked as in the game
        hooksecurefunc = function(name, fn)
            local real = _G[name]
            _G[name] = function(...) real(...); fn(...) end
        end
        F.Mail.hooked = nil; F.Mail.hook()
        MailFrame:Show(); fire('MAIL_SHOW'); F.Mail.start(); run(5)
        assert(F.Engine.message == 'mail_stuck', tostring(F.Engine.message))
        assert(failed() == 0 and said(summary(0, 0)), 'the mail is still there: ' .. failed())
        refuse = false
        AutoLootMailItem(1) -- taken by hand
        assert(#inbox == 0 and failed() == 1, 'booked once, when taken: ' .. failed())''')

    def test_a_quiver_is_no_room_for_auction_mail(self):
        run(MAIL + '''-- general bags full, a quiver (bag family 1) with room
        C_Container.GetContainerNumFreeSlots = function(bag) if bag == 1 then return 4, 1 end return 0, 0 end
        inbox = { { sender = 'Auction House', subject = 'Auction expired: Linen Bag', items = 1 } }
        MailFrame:Show(); fire('MAIL_SHOW'); F.Mail.start(); run(2)
        assert(F.Engine.message == 'bags_full' and #mailTaken == 0 and failed() == 0, tostring(F.Engine.message))
        C_Container.GetContainerNumFreeSlots = function(bag) return bag == 0 and 3 or 0, 0 end
        F.Mail.start(); run(2)
        assert(F.Engine.message == 'mail_done' and #inbox == 0 and failed() == 1, tostring(F.Engine.message))''')

    def test_a_cancelled_auction_named_with_the_realm_is_no_purchase(self):
        run(MAIL + '''c.recount, c.returnsMarked = T.RECOUNT, true
        function GetInboxItemLink(i) return inbox[i] and inbox[i].link end
        F.Data.addPosition(c, 'i:30', 'Linen Bag', 3, 3000, 'flip', 1500, now - 3600)
        inbox = { { sender = 'Auction House', subject = 'Linen Bag', items = 1, link = link(30),
            invoice = { kind = 'buyer', item = 'Linen Bag', player = 'Me-Realm', bid = 4500, count = 3 } } }
        local n = #c.journal
        fire('MAIL_SHOW'); F.Mail.record(1)
        assert(c.positions['i:30'].qty == 3, 'no units added: ' .. c.positions['i:30'].qty)
        for i = n + 1, #c.journal do assert(c.journal[i].kind ~= 'buy', 'booked as a purchase') end''')


class MerchantTests(unittest.TestCase):
    def test_a_quiver_is_no_room_for_a_merchant_purchase(self):
        run(BASE + AXE + '''local offer = axeOffer(9)
        C_Container.GetContainerNumFreeSlots = function(bag) if bag == 1 then return 16, 1 end return 0, 0 end
        local ok, why = F.Merchant.buy(offer)
        assert(not ok and why == 'bags_full' and #merchantBought == 0 and not c.positions['i:70'], tostring(why))
        C_Container.GetContainerNumFreeSlots = function(bag)
            if bag == 1 then return 16, 1 end
            return bag == 0 and 2 or 0, 0
        end
        local bought
        ok, bought = F.Merchant.buy(offer)
        assert(ok and bought == 2 and c.positions['i:70'].qty == 2, tostring(bought))''')

    def test_offers_count_the_stock_held_and_the_trust(self):
        run(MERCHANT + '''local o = F.Merchant.offers(now)[1]
        assert(o and o.qty == 48, 'one day of sales')
        assert(F.Merchant.buy(o))
        assert(#F.Merchant.offers(now) == 0, 'a day of sales is held already')''')
        run(MERCHANT + '''F.Data.addPosition(c, 'c:60', 'Fine Thread', 10, 1000, 'flip', 499, now - 2 * 86400)
        local o = F.Merchant.offers(now)[1]
        -- stock unsold for two days halves the 48 a day; the 10 held count
        assert(o and o.qty == 14, tostring(o and o.qty))''')

    def test_a_merchant_purchase_is_logged_as_a_resale(self):
        run(MERCHANT + '''assert(F.Merchant.buy(F.Merchant.offers(now)[1]))
        local e = c.journal[#c.journal]
        assert(e.kind == 'buy' and e.merchant and e.mode == 'flip', tostring(e.mode))''')


if __name__ == '__main__':
    unittest.main()
