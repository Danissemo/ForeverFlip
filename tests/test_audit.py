"""Findings of the two latency audits of 1.2.0-beta.2 that were confirmed and fixed: stuck states,
queue fairness, request budgets, purchases bound to what is on screen, the price field, posting and
cancelling twice, late answers, mail that never goes away, and one failing part stopping the rest."""

import unittest

from test_addon import SETUP, run

BASE = SETUP + '''local F, D, T, UI = ForeverFlip, ForeverFlip.Deals, ForeverFlip.Trade, ForeverFlip.UI
F.Engine.autoVerify = false; F.db.settings.sniper = false
'''


class StuckStateTests(unittest.TestCase):
    def test_a_quote_nobody_confirms_ends_after_a_minute(self):
        run(BASE + '''fullScan(); D.verify('c:10'); answer()
        assert(T.buy('c:10')); fire('COMMODITY_PRICE_UPDATED', 60, 900)
        assert(T.op and T.op.state == 'quoted')
        run(61)
        assert(not T.op and F.Engine.message == 'quote_expired', 'searches and checks go on again')''')

    def test_a_request_the_api_keeps_refusing_ends_and_spends_no_budget(self):
        run(BASE + '''F.AH.search = function() error('refused') end
        T.checkPrice('c:10')
        for _ = 1, 50 do run(0.2) end
        assert(not D.pending('c:10'), 'given up after three tries')
        assert(#D.sent == 0, 'nothing was sent, so nothing counts against the 100 a minute')''')

    def test_an_error_in_one_part_does_not_stop_the_others(self):
        run(BASE + '''local steps = 0
        local trade = F.Trade.step
        F.Trade.step = function(...) steps = steps + 1; return trade(...) end
        F.Scan.step = function() error('scan broke') end
        run(1)
        assert(steps > 0, 'the trade step still runs')''')


class QueueTests(unittest.TestCase):
    def test_a_single_check_goes_before_a_check_all_batch(self):
        run(BASE + '''for i = 1, 20 do T.checkPrice('c:' .. (900 + i), function() end, true) end
        T.checkPrice('c:10')
        assert(D.requests[1].key == 'c:10', 'the click is next, not after the batch')''')

    def test_a_sniper_candidate_that_could_not_start_is_kept(self):
        run(BASE + '''F.Sniper.candidates = { { key = 'c:10', score = 1 } }
        F.Sniper.active = function() return true end
        D.request = function() return false end
        F.db.settings.sniper = true; D.scope = F.Engine.scope(); D.lastRequest = -10
        D.snipe()
        assert(F.Sniper.candidates[1] and F.Sniper.candidates[1].key == 'c:10', 'back in the list')''')

    def test_reading_a_scan_does_not_hold_back_checks(self):
        run(BASE + '''local S = F.Scan
        S.job = { state = 'reading' }
        assert(not S.blocking(), 'reading is local work')
        S.job = { state = 'waiting' }
        assert(S.blocking(), 'waiting for the answer still holds searches back')
        S.job = nil''')


class LateAnswerTests(unittest.TestCase):
    def test_answers_after_the_house_closed_check_nothing(self):
        run(BASE + '''fullScan()
        local called = false
        D.verifyCallback = function() called = true end
        fire('AUCTION_HOUSE_CLOSED'); AuctionHouseFrame:Hide() -- the game hides it
        D.onResults(10)
        assert(not called, 'a late answer does not mark a deal checked')''')

    def test_a_bid_check_without_an_answer_reads_no_old_results(self):
        run(BASE + '''fullScan()
        F.Bids.candidates = { { key = 'i:30', id = 30, count = 1, value = 100000, bid = 100, profit = 1000 } }
        local read = false
        F.Bids.read = function() read = true end
        local done = false
        F.Bids.check('i:30', function() done = true end)
        run(12)
        assert(done and not read, 'the timeout is no answer')''')


class PurchaseOnScreenTests(unittest.TestCase):
    def test_selecting_another_deal_drops_the_quote(self):
        run(BASE + '''fullScan(); D.verify('c:10'); answer()
        assert(T.buy('c:10')); fire('COMMODITY_PRICE_UPDATED', 60, 900)
        UI.selectDeal('i:30')
        assert(not T.op and lastCall('CancelCommoditiesPurchase'), 'Confirm cannot buy c:10 now')''')

    def test_buy_next_confirms_the_quoted_deal_and_shows_it(self):
        run(BASE + '''fullScan(); D.verify('c:10'); answer()
        UI.selected = 'c:10'; assert(T.buy('c:10')); fire('COMMODITY_PRICE_UPDATED', 60, 900)
        UI.selected = nil
        F.Engine.keyBuyNext()
        assert(UI.selected == 'c:10' and T.op.state == 'awaiting')''')

    def test_the_status_line_follows_the_purchase(self):
        run(BASE + '''fullScan(); D.verify('c:10'); answer()
        assert(T.buy('c:10')); UI.refresh()
        assert(UI.status:GetText():find('Asking'), UI.status:GetText())
        fire('COMMODITY_PRICE_UPDATED', 60, 900); UI.refresh()
        assert(UI.status:GetText():find('Confirm'), UI.status:GetText())''')


class SellingTests(unittest.TestCase):
    SELL = BASE + '''putBag(0, 1, 30, 1); putBag(0, 2, 10, 20)
    UI.show('sell')
    local function pick(key) for _, r in ipairs(UI.sellTable.rows) do if r.key == key then r:Click() return end end end
    '''

    def test_the_selected_item_follows_its_bag_slot(self):
        run(self.SELL + '''pick('c:10'); assert(UI.sellSelected.slot == 2)
        bags[0][2] = nil; putBag(0, 7, 10, 20)
        run(0.1); UI.refresh() -- the bags are read once per frame
        assert(UI.sellSelected and UI.sellSelected.slot == 7, 'the post goes to the slot the item is in now')
        bags[0][7] = nil; run(0.1); UI.refresh()
        assert(not UI.sellSelected, 'an item gone from the bags is no longer selected')''')

    def test_a_filled_in_price_follows_a_new_check_and_a_typed_one_is_kept(self):
        run(self.SELL + '''pick('i:30')
        T.prices['i:30'] = { rows = { { unit = 50000, qty = 1 } }, at = now }; UI.refresh()
        local first = UI.sellPrice:GetText(); assert(first ~= '', 'a price is filled in')
        T.prices['i:30'] = { rows = { { unit = 90000, qty = 1 } }, at = now }; UI.refresh()
        assert(UI.sellPrice:GetText() ~= first, 'the new check changed the price')
        UI.sellPrice:SetText('7g'); UI.sellPriceAuto = nil -- typed by the player
        T.prices['i:30'] = { rows = { { unit = 30000, qty = 1 } }, at = now }; UI.refresh()
        assert(UI.sellPrice:GetText() == '7g', 'a typed price is kept')''')

    def test_a_second_post_waits_for_the_first(self):
        run(self.SELL + '''T.lastPost = { ids = {}, auctions = 1, at = now, qty = 1, open = 1 }
        local item = F.AH.bagItems()[1]
        local ok, why = T.post(item, 1, 50000, 3)
        assert(not ok and why == 'busy', tostring(why))
        run(11)
        assert(not T.postingNow(), 'no answer in 10 seconds: posting is free again')''')

    def test_an_auction_is_cancelled_once(self):
        run(self.SELL + '''local a = { auctionID = 5, qty = 1 }
        assert(T.cancelAuction(a))
        assert(not T.cancelAuction(a), 'the same auction is not cancelled twice')''')


class MailTests(unittest.TestCase):
    def test_a_mail_the_game_keeps_refusing_stops_the_job(self):
        run(BASE + '''inbox = { { sender = 'Auction House', subject = 'Auction expired: Linen Bag', money = 0, items = 1 } }
        AutoLootMailItem = function() end -- the game refuses it
        MailFrame:Show(); fire('MAIL_SHOW'); F.Mail.start()
        run(5)
        assert(not F.Mail.job and F.Engine.message == 'mail_stuck', tostring(F.Engine.message))''')


if __name__ == '__main__':
    unittest.main()


class AnalyticsInFramesTests(unittest.TestCase):
    def test_a_large_history_is_worked_out_a_slice_per_frame(self):
        run(BASE + '''fullScan()
        local A = F.Analytics
        local history = F.Data.market(F.db, F.Engine.scope()).history
        for i = 1, 3000 do history['i:' .. (6000 + i)] = { scan = { at = now, market = 1000 + i } } end
        A.invalidate()
        local m, working = A.market()
        assert(working, 'not worked out in the call itself')
        local frames = 0
        repeat run(0.05); frames = frames + 1; m, working = A.market() until not working or frames > 500
        assert(not working and m.items >= 3000 and frames > 1, 'ready after ' .. frames .. ' frames')
        A.invalidate()
        local old, again = A.market()
        assert(again and old and old.items >= 3000, 'the previous lists stay on screen meanwhile')''')


class VendorMarginTests(unittest.TestCase):
    def test_the_old_default_margin_is_reset_once(self):
        run('''local D = ForeverFlip.Data
        local db = D.open({ settings = { vendorMargin = 20 } })
        assert(db.settings.vendorMargin == 0 and db.vendorMarginReset, 'the old default goes')
        db.settings.vendorMargin = 20
        db = D.open(db)
        assert(db.settings.vendorMargin == 20, 'a margin set again by the player stays')
        local fresh = D.open({})
        assert(fresh.settings.vendorMargin == 0, 'new players start without a margin')''')


class ItemAnswerTests(unittest.TestCase):
    def test_an_answer_under_the_exact_item_key_is_read_there(self):
        run(BASE + '''fullScan()
        F.AH.rows = function(item, key)
            if key and key.itemLevel == 5 then return { { unit = 900, qty = 1, auctionID = 7 } }, true end
            return {}, false
        end
        local got
        T.checkPrice('i:30', function(_, rows, complete) got = { rows = rows, complete = complete } end, true)
        assert(D.search and D.search.key == 'i:30')
        fire('ITEM_SEARCH_RESULTS_UPDATED', { itemID = 30, itemLevel = 5 })
        assert(got and got.complete and #got.rows == 1, 'read under the key the server answered with')''')

    def test_an_item_without_an_answer_is_searched_by_name_next_time(self):
        run(BASE + '''enableBrowse(); fullScan()
        F.AH.search = function() end -- the server never answers the plain search
        T.checkPrice('i:30', function() end, true)
        run(11)
        assert(D.byName[30], 'remembered')
        T.checkPrice('i:30', function() end, true); run(1)
        assert(D.search and D.search.phase == 'browse', 'searched by name, like gear')''')


class PostFeedbackTests(unittest.TestCase):
    SELL = BASE + '''putBag(0, 1, 30, 1)
    local item = F.AH.bagItems()[1]
    '''

    def test_auction_created_only_when_the_game_says_so(self):
        run(self.SELL + '''local ok, why = T.post(item, 1, 50000, 3)
        assert(ok and why == 'post_sent', tostring(why))
        fire('AUCTION_HOUSE_AUCTION_CREATED', 77)
        assert(F.Engine.message == 'posted', 'confirmed by the game')''')

    def test_a_dropped_post_is_said_at_once(self):
        run(self.SELL + '''assert(T.post(item, 1, 50000, 3))
        fire('AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED')
        assert(F.Engine.message == 'post_dropped' and not T.postingNow(), 'press again works at once')''')

    def test_an_unconfirmed_post_is_said_after_ten_seconds(self):
        run(self.SELL + '''assert(T.post(item, 1, 50000, 3))
        run(12)
        assert(F.Engine.message == 'post_unconfirmed', tostring(F.Engine.message))''')

    def test_the_selling_page_reads_the_queue_prices_ahead(self):
        run(self.SELL + '''F.db.settings.vendorMargin = 0
        F.Data.market(F.db, F.Engine.scope()).history['i:30'] = { scan = { at = now, market = 90000 } }
        UI.show('sell'); UI.refresh()
        assert(D.pending('i:30'), 'the price of the AH-worthy item is being read already')''')


class MerchantTests(unittest.TestCase):
    def test_items_that_do_not_stack_are_bought_one_call_each_and_only_what_fits(self):
        run(BASE + '''addItem(70, 'Weighted Throwing Axe', 50, 'item')
        local offer = { index = 1, key = 'i:70', link = link(70), unit = 270, qty = 9, exit = 900 }
        freeBagSlots = 5
        local ok, bought = F.Merchant.buy(offer)
        assert(ok and bought == 5, 'only what the bags hold: ' .. tostring(bought))
        assert(#merchantBought == 5 and merchantBought[1][2] == 1, 'one item per call (no Internal Bag Error)')''')

    def test_the_sell_list_holds_what_a_merchant_pays_most_for_except_hidden_and_kept(self):
        run(BASE + '''F.db.settings.vendorMargin = 0
        addItem(71, 'Murloc Fin', 28, 'commodity'); addItem(72, 'Healing Potion', 75, 'commodity')
        addItem(73, 'Silk Cloth', 150, 'commodity'); addItem(74, 'Wool Cloth', 33, 'commodity')
        putBag(0, 1, 71, 4); putBag(0, 2, 72, 1); putBag(0, 3, 73, 2); putBag(0, 4, 74, 5)
        local history = F.Data.market(F.db, F.Engine.scope()).history
        for _, k in ipairs({ 'c:71', 'c:72', 'c:73' }) do history[k] = { scan = { at = now, market = 20 } } end
        history['c:74'] = { scan = { at = now, market = 5000 } } -- the auction house pays more
        T.hide('c:72', 'Healing Potion')
        T.setRule('c:73', { keep = 2 })
        local keys = {}
        for _, v in ipairs(T.vendorSellList()) do keys[#keys + 1] = v.key end
        assert(table.concat(keys, ',') == 'c:71', table.concat(keys, ','))
        MerchantFrame:Show()
        local stacks, money = T.sellAllToVendor()
        assert(stacks == 1 and money == 112 and soldToVendor[1].itemID == 71)''')

    def test_the_merchant_tab_and_button_sell_the_list(self):
        run(BASE + '''F.db.settings.vendorMargin = 0
        addItem(71, 'Murloc Fin', 28, 'commodity'); putBag(0, 1, 71, 4)
        F.Data.market(F.db, F.Engine.scope()).history['c:71'] = { scan = { at = now, market = 20 } }
        MerchantFrame:Show(); fire('MERCHANT_SHOW')
        assert(UI.merchantButton:IsShown() and UI.merchantButton:GetText():find('Sell to vendor %(1%)'), UI.merchantButton:GetText())
        UI.merchantTab:Click()
        assert(UI.merchantView:IsShown() and UI.merchantView.sellRows[1]:IsShown())
        UI.merchantView.sellAll:Click()
        assert(#soldToVendor == 1, 'one click sells it all')''')
