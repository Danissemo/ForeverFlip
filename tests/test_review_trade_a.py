"""Review fixes in Trade.lua: purchase confirmation, invoices, listings, cancels, recount and summary."""

import unittest

from test_addon import SETUP, run

BASE = SETUP + '''local F = ForeverFlip
local T, D = F.Trade, F.Deals
local c = F.Data.char(F.db, F.Engine.owner())
c.recount, c.returnsMarked = T.RECOUNT, true -- no journal recount in these synthetic states
local function count(name)
    local n = 0
    for _, call in ipairs(calls) do
        if call[1] == name then
            n = n + 1
        end
    end
    return n
end
local function entries(kind)
    local n = 0
    for _, e in ipairs(c.journal) do
        if e.kind == kind then
            n = n + 1
        end
    end
    return n
end
'''

# An item purchase of the 8s sword that got no answer: after 30 seconds the wallet is watched (T.late).
LATE = BASE + '''local nature = F.Util.key('gear', 20, 'Northern Shortsword of Nature Protection')
local healing = F.Util.key('gear', 20, 'Northern Shortsword of Healing')
local placeBid = C_AuctionHouse.PlaceBid
C_AuctionHouse.PlaceBid = function() end -- the game sends nothing back
fullScan(); D.verify(nature); answer(); assert(T.buy(nature))
local op = T.op
fire('AUCTION_HOUSE_SHOW_ERROR'); run(31)
assert(F.Engine.message == 'buy_no_answer' and T.late and op.cost == 800)
C_AuctionHouse.PlaceBid = placeBid
-- Answers every search, the deal's own check again too.
local function check(key)
    D.verify(key)
    local guard = 0
    while (D.search or D.pending()) and guard < 400 do
        if D.search then
            answer()
        end
        run(0.05)
        guard = guard + 1
    end
    run(1.2)
end
'''

# One Linen Bag lot of 10s (a merchant pays 20s): a vendor deal bought one auction per click.
BAG = BASE + '''addAuction(30, 1000, 1)
fullScan()
D.verify('i:30'); answer(); run(1.2)
'''

# A commodity purchase confirmed without any answer: kept as unknown after 30 seconds.
UNKNOWN = BASE + '''fullScan()
C_AuctionHouse.ConfirmCommoditiesPurchase = function() end
D.verify('c:10'); answer()
assert(T.buy('c:10')); fire('COMMODITY_PRICE_UPDATED', 60, 900); assert(T.confirm())
money = money - 900; run(31)
assert(#c.unknown == 1 and F.Engine.message == 'buy_unknown')
'''

# One Linen Bag (cost 20000) on sale in auction 77, posted with ForeverFlip (deposit 100).
LISTED = BASE + '''F.Data.addPosition(c, 'i:30', 'Linen Bag', 1, 20000, 'flip', 30000, now)
F.Data.log(c, { at = now, kind = 'buy', key = 'i:30', name = 'Linen Bag', qty = 1, amount = 20000 })
c.listings = { { key = 'i:30', name = 'Linen Bag', ids = { 77 }, qty = 1, open = 1, auctions = 1, price = 30000,
    deposit = 100, at = now } }
owned = { { auctionID = 77, itemKey = { itemID = 30 }, itemLink = link(30), quantity = 1, buyoutAmount = 30000,
    status = 0, timeLeftSeconds = 40000 } }
fire('OWNED_AUCTIONS_UPDATED')
local cost0 = c.positions['i:30'].cost
'''


class LatePurchaseTests(unittest.TestCase):
    def test_only_one_change_of_exactly_the_price_books_a_late_purchase(self):
        run(LATE + '''money = money - 500; fire('PLAYER_MONEY') -- a repair
        money = money - 400; fire('PLAYER_MONEY'); money = money - 400; fire('PLAYER_MONEY') -- two smaller costs
        assert(not c.positions[nature] and F.Engine.message == 'buy_no_answer', 'no phantom purchase')
        money = money - 800; fire('PLAYER_MONEY')
        assert(c.positions[nature].qty == 1 and F.Engine.message == 'bought_late' and F.Engine.spent == 800)''')

    def test_a_late_watch_never_takes_a_purchase_under_way(self):
        run(LATE + '''check('c:10')
        assert(T.buy('c:10')); fire('COMMODITY_PRICE_UPDATED', 60, 900); assert(T.confirm())
        money = money - 900; fire('PLAYER_MONEY')
        assert(T.op and T.op.key == 'c:10' and T.op.state == 'awaiting', 'the cloth purchase still waits')
        fire('COMMODITY_PURCHASE_SUCCEEDED')
        assert(c.positions['c:10'].qty == 15 and not c.positions[nature] and F.Engine.spent == 900)''')

    def test_a_new_purchase_ends_the_late_watch(self):
        run(LATE + '''check(healing)
        assert(T.buy(healing) and not T.late)
        money = money - 400; fire('PLAYER_MONEY')
        assert(c.positions[healing].qty == 1)
        money = money - 800; fire('PLAYER_MONEY') -- exactly the old price: something else
        assert(not c.positions[nature], 'the unanswered lot is not booked')''')

    def test_a_bid_ends_the_late_watch(self):
        run(LATE + '''c.bids = { [99] = { key = 'i:30', name = 'Linen Bag', qty = 1, amount = 800, at = now } }
        money = money - 800; fire('PLAYER_MONEY') -- the bid's money
        assert(not c.positions[nature] and not T.late)''')


class WonLineTests(unittest.TestCase):
    def test_a_buyouts_own_won_line_does_not_close_a_bid(self):
        for confirm in ("money = money - 1000; fire('PLAYER_MONEY')",
                        "fire('AUCTION_HOUSE_PURCHASE_COMPLETED', lastCall('PlaceBid')[2])"):
            with self.subTest(confirm=confirm):
                run(BAG + '''c.bids = { [7] = { key = 'i:30', name = 'Linen Bag', qty = 1, amount = 500, value = 2000,
                    at = now } }
                assert(T.buy('i:30'))
                ''' + confirm + '''
                fire('CHAT_MSG_SYSTEM', 'You won an auction for Linen Bag')
                assert(c.bids[7], 'the bid still runs')
                assert(c.positions['i:30'].qty == 1 and c.positions['i:30'].cost == 1000)
                assert(entries('buy') == 1 and c.awaitMail['linen bag'].n == 1)''')

    def test_a_late_won_line_does_not_confirm_the_next_purchase(self):
        run(BAG + '''addAuction(30, 1100, 1); D.verify('i:30'); answer(); run(1.2)
        assert(T.buy('i:30')); money = money - lastCall('PlaceBid')[3]; fire('PLAYER_MONEY')
        assert(T.buy('i:30'), 'the next lot, from the same check')
        fire('CHAT_MSG_SYSTEM', 'You won an auction for Linen Bag') -- the first purchase's line
        assert(T.op and T.op.state == 'awaiting', 'the second purchase still waits for its answer')
        assert(c.positions['i:30'].qty == 1)''')


class UnknownPurchaseTests(unittest.TestCase):
    def test_the_mail_of_an_unknown_purchase_books_it_once(self):
        run(UNKNOWN + '''T.onBuyerInvoice({ item = 'Linen Cloth', count = 15, bid = 900 }, link(10))
        local p = c.positions['c:10']
        assert(#c.unknown == 0 and p.qty == 15 and p.cost == 900 and p.mode == 'vendor', p.mode)
        assert(F.Engine.spent == 900 and F.Engine.message ~= 'bought_elsewhere')
        T.settle(1, true)
        assert(c.positions['c:10'].qty == 15 and entries('buy') == 1, 'It was bought cannot book it again')''')

    def test_the_won_line_of_an_unknown_purchase_settles_it(self):
        run(UNKNOWN + '''fire('CHAT_MSG_SYSTEM', 'You won an auction for Linen Cloth (x15)')
        assert(#c.unknown == 0 and c.positions['c:10'].qty == 15 and c.positions['c:10'].mode == 'vendor')
        T.onBuyerInvoice({ item = 'Linen Cloth', count = 15, bid = 900 }, link(10))
        assert(c.positions['c:10'].qty == 15 and entries('buy') == 1, 'its mail is only matched')''')


class EmptyLinkNameTests(unittest.TestCase):
    def test_a_purchase_with_a_link_named_empty_books_the_item_name(self):
        run(BAG + '''D.get('i:30').link = '|cff1eff00|Hitem:30::::::::22:1484::1:1:12743:1:28:7000:::::|h[]|h|r'
        assert(T.buy('i:30')); money = money - 1000; fire('PLAYER_MONEY')
        assert(c.positions['i:30'].name == 'Linen Bag' and c.awaitMail['linen bag'].n == 1)
        T.onBuyerInvoice({ item = 'Linen Bag', count = 1, bid = 1000 }, link(30))
        assert(c.positions['i:30'].qty == 1, 'its mail is matched, not booked again')''')


class InvoiceLifetimeTests(unittest.TestCase):
    def test_a_listing_waits_for_its_invoice_and_cancel_mail_past_three_days(self):
        run(BASE + '''F.Data.addPosition(c, 'i:30', 'Linen Bag', 3, 60000, 'flip', 29900, now - 3600)
        putBag(0, 1, 30, 3)
        assert(T.post(F.AH.bagItems()[1], 1, 29900, 3)); fire('AUCTION_HOUSE_AUCTION_CREATED', 777)
        c.listings[2] = { key = 'i:30', name = 'Linen Bag', ids = { 778 }, qty = 1, open = 1, auctions = 1,
            price = 29900, deposit = 100, at = now }
        owned = { { auctionID = 777, itemKey = { itemID = 30 }, quantity = 1, buyoutAmount = 29900, status = 1 },
            { auctionID = 778, itemKey = { itemID = 30 }, quantity = 1, buyoutAmount = 29900, status = 0 } }
        fire('OWNED_AUCTIONS_UPDATED')
        assert(T.cancelAuction(T.owned[2])); owned = { owned[1] }; run(3); fire('OWNED_AUCTIONS_UPDATED')
        local cost = c.positions['i:30'].cost
        now = now + 3 * 86400 + 60; owned = {}; fire('OWNED_AUCTIONS_UPDATED')
        assert(#c.listings == 2, 'their mails are still to come')
        T.onInvoice({ item = 'Linen Bag', count = 1, bid = 29900, cut = 1495 })
        assert(entries('sell') == 1 and c.positions['i:30'].qty == 2, 'the sale is booked once')
        T.onFailedPost('Linen Bag', 1)
        assert(c.positions['i:30'].cost == cost, 'the cancel deposit is not charged again')''')

    def test_a_listing_with_units_only_is_no_longer_on_sale_after_three_days(self):
        run(BASE + '''c.listings = { { key = 'i:30', name = 'Linen Bag', ids = { 5 }, qty = 2, open = 2, auctions = 2,
            price = 29900, at = now, awaiting = 1 } }
        now = now + 3 * 86400 + 60; fire('OWNED_AUCTIONS_UPDATED')
        assert(#c.listings == 1 and c.listings[1].open == 0, 'kept for its invoice, no unit on sale')''')

    def test_a_purchase_mail_is_matched_for_the_mail_lifetime(self):
        run(BASE + '''F.Data.addPosition(c, 'c:10', 'Linen Cloth', 5, 300, 'flip', 100, now)
        T.awaitBuyerInvoice('Linen Cloth', 5)
        now = now + 4 * 86400
        F.Data.addPosition(c, 'c:10', 'Linen Cloth', 5, 300, 'flip', 100, now)
        T.awaitBuyerInvoice('Linen Cloth', 5)
        assert(c.awaitMail['linen cloth'].n == 10, 'the older purchase still waits for its mail')
        now = now + 3 * 86400 + 60
        T.onBuyerInvoice({ item = 'Linen Cloth', count = 5, bid = 300 }, link(10))
        T.onBuyerInvoice({ item = 'Linen Cloth', count = 5, bid = 300 }, link(10))
        assert(c.positions['c:10'].qty == 10 and c.positions['c:10'].mode == 'flip' and entries('buy') == 0)''')

    def test_a_purchase_from_an_invoice_logs_its_mode(self):
        run(BASE + '''T.onBuyerInvoice({ item = 'Linen Bag', count = 1, bid = 600 }, link(30, 'Linen Bag'))
        local e = c.journal[#c.journal]
        assert(e.kind == 'buy' and e.mode == 'other' and e.source == 'buyer_invoice')''')


class LateCreatedTests(unittest.TestCase):
    def test_a_late_created_auction_does_not_book_another_items_sale(self):
        run(BASE + '''F.Data.addPosition(c, 'i:30', 'Linen Bag', 1, 20000, 'flip', 29900, now - 3600)
        F.Data.addPosition(c, 'c:10', 'Linen Cloth', 5, 300, 'flip', 100, now - 3600)
        putBag(0, 1, 30, 1); putBag(0, 2, 10, 5)
        local bag, cloth
        for _, b in ipairs(F.AH.bagItems()) do
            if b.key == 'i:30' then bag = b elseif b.key == 'c:10' then cloth = b end
        end
        assert(T.post(bag, 1, 29900, 3)); run(11)
        assert(T.post(cloth, 5, 120, 3), 'no answer in 10 seconds: posting is free again')
        fire('AUCTION_HOUSE_AUCTION_CREATED', 111) -- the bag's answer, late
        fire('AUCTION_HOUSE_AUCTION_CREATED', 222) -- the cloth's own
        local l = c.listings[#c.listings]
        assert(l.key == 'c:10' and l.ids[1] == 111, 'the late ID went to the cloth listing')
        owned = { { auctionID = 111, itemKey = { itemID = 30 }, quantity = 1, buyoutAmount = 29900, status = 1 },
            { auctionID = 222, itemKey = { itemID = 10 }, quantity = 5, buyoutAmount = 120, status = 0 } }
        fire('OWNED_AUCTIONS_UPDATED')
        assert(c.positions['c:10'].qty == 5 and entries('sell') == 0, 'the bag sale is not booked as cloth')
        assert(#l.ids == 0, 'the bag auction left the cloth listing')
        now = now + 31; fire('OWNED_AUCTIONS_UPDATED')
        assert(l.ids[1] == 222, 'the cloth listing takes its own auction')
        T.onInvoice({ item = 'Linen Bag', count = 1, bid = 29900, cut = 1495 })
        assert(not c.positions['i:30'] and c.positions['c:10'].qty == 5)''')


class CancelTests(unittest.TestCase):
    def test_a_cancel_without_a_listing_charges_its_deposit_once(self):
        run(BASE + '''F.Data.addPosition(c, 'i:30', 'Linen Bag', 3, 60000, 'flip', 29900, now - 3600)
        owned = { { auctionID = 900, itemKey = { itemID = 30 }, quantity = 1, buyoutAmount = 29900, status = 0 } }
        fire('OWNED_AUCTIONS_UPDATED')
        local cost0 = c.positions['i:30'].cost
        assert(T.cancelAuction(T.owned[1]))
        owned = {}; run(3); fire('OWNED_AUCTIONS_UPDATED') -- asked for after the cancel: it is gone
        local cost1 = c.positions['i:30'].cost
        assert(cost1 > cost0 and entries('cancel') == 1, 'the estimated deposit is booked')
        T.onFailedPost('Linen Bag', 1) -- its "Auction cancelled" mail
        assert(c.positions['i:30'].cost == cost1 and entries('cancel') == 1, 'and not estimated again')''')

    def test_a_cancel_whose_listing_lost_its_units_is_matched_by_name(self):
        run(BASE + '''F.Data.addPosition(c, 'i:30', 'Linen Bag', 4, 80000, 'flip', 29900, now - 3600)
        c.listings = { { key = 'i:30', name = 'Linen Bag', qty = 1, price = 29900, at = now, ids = { 900 }, open = 1,
            auctions = 1, deposit = 100 } }
        T.onFailedPost('Linen Bag', 1) -- an auction of the item posted elsewhere expired
        owned = { { auctionID = 900, itemKey = { itemID = 30 }, quantity = 1, buyoutAmount = 29900, status = 0 } }
        fire('OWNED_AUCTIONS_UPDATED')
        local cost0 = c.positions['i:30'].cost
        assert(T.cancelAuction(T.owned[1]))
        T.onFailedPost('Linen Bag', 1) -- the cancel's mail comes before any list
        local charged = c.positions['i:30'].cost - cost0
        assert(charged == 100, 'one deposit for the cancel: ' .. charged)
        owned = {}; run(3); fire('OWNED_AUCTIONS_UPDATED')
        assert(c.positions['i:30'].cost == cost0 + 100 and entries('cancel') == 1)''')

    def test_an_auction_is_not_cancelled_again_while_the_list_is_old(self):
        run(BASE + '''F.Data.addPosition(c, 'i:30', 'Linen Bag', 3, 300, 'flip', 29900, now - 3600)
        c.listings = { { key = 'i:30', name = 'Linen Bag', qty = 1, price = 29900, at = now, ids = { 900 }, open = 1,
            auctions = 1, deposit = 100 } }
        owned = { { auctionID = 900, itemKey = { itemID = 30 }, quantity = 1, buyoutAmount = 29900, status = 0 } }
        fire('OWNED_AUCTIONS_UPDATED')
        T.prices['i:30'] = { rows = { { unit = 20000, qty = 1 } }, at = now }
        assert(#T.undercutList() == 1 and T.cancelAuction(T.owned[1]))
        now = now + 31 -- no list asked for since
        T.prices['i:30'].at = now
        assert(#T.undercutList() == 0 and #T.fightPlans() == 0, 'not offered again')
        assert(not T.cancelAuction(T.owned[1]) and count('CancelAuction') == 1, 'not sent again')''')

    def test_a_dropped_cancel_books_nothing(self):
        run(LISTED + '''assert(T.cancelAuction(T.owned[1]))
        fire('AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED')
        local l = c.listings[1]
        assert(l.open == 1 and (l.cancelled or 0) == 0 and c.positions['i:30'].cost == cost0 and entries('cancel') == 0)
        now = now + 60; owned[1].status = 1; fire('OWNED_AUCTIONS_UPDATED') -- it sold later
        local e = c.journal[#c.journal]
        assert(e.kind == 'sell' and e.profit == 8500, 'the sale keeps its whole profit')''')

    def test_a_cancel_the_next_list_refutes_is_undone(self):
        run(LISTED + '''assert(T.cancelAuction(T.owned[1]))
        owned[1].status = 1 -- it had sold: the server refused the cancel
        run(3); fire('OWNED_AUCTIONS_UPDATED')
        local e = c.journal[#c.journal]
        assert(e.kind == 'sell' and e.profit == 8500 and entries('cancel') == 0, e.kind)
        assert(not c.positions['i:30'])''')

    def test_the_own_auction_list_waits_only_for_messages_on_the_wire(self):
        run(BASE + '''throttleReady = false
        D.startBatch('deals:all', { 'c:10', 'i:30' }, false)
        F.UI.show('auctions'); run(0.2)
        throttleReady = true; T.ownedDue = 0
        local asked = count('QueryOwnedAuctions'); run(0.5)
        assert(D.pending() and not D.searching(), 'a paused batch is queued')
        assert(count('QueryOwnedAuctions') > asked, 'the list is asked for anyway')''')

    def test_the_own_auction_list_waits_for_a_sniper_browse_and_a_post(self):
        run(BASE + '''T.ownedDue = 0
        local inFlight = F.Sniper.inFlight
        F.Sniper.inFlight = function() return true end
        local asked = count('QueryOwnedAuctions'); run(0.5)
        assert(count('QueryOwnedAuctions') == asked, 'not behind a sniper browse')
        F.Sniper.inFlight = inFlight
        T.lastPost = { ids = {}, auctions = 1, at = now, qty = 1, open = 1 }
        run(0.5)
        assert(count('QueryOwnedAuctions') == asked, 'not before the post is answered')
        T.lastPost = nil; run(0.5)
        assert(count('QueryOwnedAuctions') == asked + 1)''')


class ConfirmTests(unittest.TestCase):
    QUOTED = BASE + '''fullScan(); D.verify('c:10'); answer()
    assert(T.buy('c:10')); fire('COMMODITY_PRICE_UPDATED', 60, 900); assert(T.op.state == 'quoted')
    '''

    def test_a_failed_confirm_tells_why(self):
        run(self.QUOTED + '''now = now + 26
        local ok, why = T.confirm()
        assert(not ok and why == 'requote', tostring(why))
        fire('COMMODITY_PRICE_UPDATED', 60, 900)
        T.run = { key = 'c:10', skipped = {}, bought = 0, clicked = now }
        now = now + 26
        ok, why = T.runClick()
        assert(not ok and why == 'requote', 'the run passes the reason on: ' .. tostring(why))''')

    def test_the_run_never_confirms_a_quote_of_another_deal(self):
        run(self.QUOTED + '''assert(not T.run and T.runState() ~= 'confirm')
        T.runClick()
        assert(count('ConfirmCommoditiesPurchase') == 0, 'the run button bought the quoted deal')
        assert(T.buy('c:10')); fire('COMMODITY_PRICE_UPDATED', 60, 900)
        T.run = { key = 'c:10', skipped = {}, bought = 0, clicked = now }
        assert(T.runState() == 'confirm', 'the run confirms its own quote')''')


class RecountTests(unittest.TestCase):
    def test_the_recount_waits_for_merchant_prices_by_time(self):
        run(BASE + '''addItem(40, 'Bolt of Silk Cloth', 5000, 'item'); items[40].cached = false; F.db.vendor[40] = nil
        local last
        F.Data.recount = function(_, deposit) last = deposit('i:40', 20); return last ~= nil end
        c.recount = nil
        run(1.5)
        assert(c.recount ~= T.RECOUNT and last == nil, 'still waiting for the item')
        items[40].cached = true; run(0.1)
        assert(c.recount == T.RECOUNT and last == T.depositFor('i:40', 20, 3), tostring(last))''')

    def test_a_merchant_price_of_zero_is_known(self):
        run(BASE + '''addItem(41, 'Quest Thing', 0, 'item')
        F.Data.recount = function(_, deposit) return deposit('i:41', 1) ~= nil end
        c.recount = nil; run(0.05)
        assert(c.recount == T.RECOUNT)''')


class SummaryTests(unittest.TestCase):
    def test_the_summary_counts_trades_the_journal_no_longer_holds(self):
        run(BASE + '''local Data = F.Data
        c.journal, c.positions, c.stats, c.lots, c.daily = {}, {}, {}, {}, nil
        local t = now - 5 * 86400
        Data.addPosition(c, 'c:10', 'Linen Cloth', 100, 6000, 'flip', 150, t)
        Data.log(c, { at = t, kind = 'buy', key = 'c:10', name = 'Linen Cloth', qty = 100, amount = 6000,
            mode = 'flip' })
        local k = Data.sale(c, 'c:10', 'Linen Cloth', 100, 15000, t + 600)
        Data.log(c, { at = t + 600, kind = 'sell', key = 'c:10', name = 'Linen Cloth', qty = 100, amount = 15000,
            profit = 15000 - k })
        for i = 1, 520 do
            Data.log(c, { at = now - 2 * 86400 + i * 300, kind = 'post', key = 'i:30', name = 'Linen Bag', qty = 1,
                amount = 30000, deposit = 300 })
        end
        assert(c.journal[1].kind == 'post', 'the trades left the journal')
        local s = T.summary(7)
        assert(s.spent == 6000 and s.buys == 1 and s.earned == 15000 and s.sales == 1 and s.profit == 9000,
            s.spent .. ' ' .. s.earned .. ' ' .. s.profit)''')


class HouseTests(unittest.TestCase):
    def test_forgetting_the_house_clears_its_checks(self):
        run(BASE + '''local prices = T.prices
        T.prices['c:10'] = { rows = { { unit = 60, qty = 5 } }, at = now }
        T.noAnswer['i:30'] = now
        T.forgetHouse()
        assert(next(T.prices) == nil and next(T.noAnswer) == nil and T.prices == prices)''')


if __name__ == '__main__':
    unittest.main()
