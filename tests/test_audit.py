"""Current regression coverage for scheduling, trading, selling, accounting and UI behavior.

The beta.4 priority and work-budget scenarios live in test_foreground.py/test_optimization.py;
historical regressions here still exercise the current addon and remain part of the checker.
"""

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
        T.checkPrice('i:30')
        assert(not T.cancelAuction(a), 'the selected item has a price check in flight')
        answer();run(1.1)
        assert(T.cancelAuction(a))
        assert(not T.cancelAuction(a), 'the same auction is not cancelled twice')''')


class MailTests(unittest.TestCase):
    def test_a_mail_the_game_keeps_refusing_stops_the_job(self):
        run(BASE + '''inbox = { { sender = 'Auction House', subject = 'Auction expired: Linen Bag', money = 0, items = 1 } }
        AutoLootMailItem = function() end -- the game refuses it
        MailFrame:Show(); fire('MAIL_SHOW'); F.Mail.start()
        run(5)
        assert(not F.Mail.job and F.Engine.message == 'mail_stuck', tostring(F.Engine.message))''')




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
        run(1)
        assert(D.search and D.search.key == 'i:30' and D.search.phase == 'browse', 'tried again at once by name, like gear')''')


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

    def test_post_all_reads_queue_prices_when_requested(self):
        run(self.SELL + '''F.db.settings.vendorMargin = 0
        F.Data.market(F.db, F.Engine.scope()).history['i:30'] = { scan = { at = now, market = 90000 } }
        UI.show('sell'); UI.refresh()
        assert(not D.pending('i:30'), 'rendering does not start a bag-wide search')
        T.postAll(true)
        assert(D.pending('i:30'), 'Post all prepares the queue on request')''')


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


class QuietTests(unittest.TestCase):
    def test_the_sniper_waits_while_selling_is_open(self):
        run(BASE + '''UI.show('sell')
        assert(D.holding(), 'background work waits on the Selling page')
        UI.show('analytics')
        assert(not D.holding())''')

    DEAL = BASE + """addItem(40, 'Moon Gem', 2000, 'item')
    for i = 1, 30 do addAuction(40, 5000 + i, 1) end
    fullScan()
    addAuction(40, 1001, 1)
    D.verify('i:40'); answer()
    assert(D.get('i:40') and D.get('i:40').verified, 'a checked vendor deal')
    """

    def test_an_item_purchase_is_confirmed_by_the_money_leaving(self):
        run(self.DEAL + """C_AuctionHouse.PlaceBid = function() end -- no purchase event, no chat line
        assert(T.buy('i:40'))
        money = money - 1001
        fire('PLAYER_MONEY')
        assert(not T.op, 'bought: no wait for an event or a chat line')
        assert(F.Data.char(F.db, F.Engine.owner()).positions['i:40'].qty == 1)""")

    def test_a_dropped_purchase_is_said_at_once(self):
        run(self.DEAL + """C_AuctionHouse.PlaceBid = function() end -- the server never answers it
        assert(T.buy('i:40'))
        fire('AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED')
        assert(not T.op and F.Engine.message == 'buy_dropped', tostring(F.Engine.message))""")


class MerchantLayoutTests(unittest.TestCase):
    def test_one_sell_button_at_a_time_and_tooltips_on_rows(self):
        run(BASE + '''F.db.settings.vendorMargin = 0
        addItem(71, 'Murloc Fin', 28, 'commodity'); putBag(0, 1, 71, 4)
        F.Data.market(F.db, F.Engine.scope()).history['c:71'] = { scan = { at = now, market = 20 } }
        MerchantFrame:Show(); fire('MERCHANT_SHOW')
        assert(UI.merchantButton:IsShown(), 'the Merchant tab has the button')
        UI.merchantTab:Click()
        assert(not UI.merchantButton:IsShown(), 'the ForeverFlip tab has Sell all instead')
        UI.merchantSelect(false)
        assert(UI.merchantButton:IsShown(), 'back on the Merchant tab')
        local row = UI.merchantView.sellRows[1]
        assert(row.bag == 0 and row.slot == 1 and type(row.scripts.OnEnter) == 'function', 'the row shows the bag item tooltip')
        fire('MERCHANT_CLOSED')
        assert(not UI.merchantButton:IsShown() and not UI.merchantView:IsShown())''')


class ScanPartsTests(unittest.TestCase):
    def test_a_list_sent_in_parts_is_read_whole(self):
        run(BASE + '''local S = F.Scan
        for i = 1, 60 do addAuction(10, 100 + i, 1) end
        fullScan()
        local full = S.last.total
        now = now + 901; F.db.lastScan = 0
        -- The server sends a tenth of the list, pauses 12 seconds, then the rest.
        local real = C_AuctionHouse.GetNumReplicateItems
        local started = now
        C_AuctionHouse.GetNumReplicateItems = function()
            return now - started < 12 and math.floor(full / 10) or real()
        end
        assert(S.start())
        run(10)
        assert(S.job and S.job.state == 'waiting', 'a part far below the last scan is not read')
        local n = 0
        while S.busy() do run(0.5); n = n + 1; assert(n < 400) end
        assert(S.last.total == full, 'the whole list: ' .. S.last.total .. ' of ' .. full)''')

    def test_a_partial_answer_does_not_lower_the_measure_of_the_next(self):
        run(BASE + '''local S = F.Scan
        for i = 1, 60 do addAuction(10, 100 + i, 1) end
        fullScan()
        local full = S.last.total
        assert(F.Data.market(F.db, F.Engine.scope()).peak.total == full, 'a complete scan sets the measure')
        -- The server only ever sends a tenth: read at the end of the wait, marked partial.
        local real = C_AuctionHouse.GetNumReplicateItems
        now = now + 901; F.db.lastScan = 0
        assert(S.start())
        C_AuctionHouse.GetNumReplicateItems = function() return math.floor(full / 10) end
        run(S.SHORT - 10)
        assert(S.job and S.job.state == 'waiting', 'a part is not read after a few quiet seconds')
        local n = 0
        while S.busy() do run(1); n = n + 1; assert(n < 600) end
        assert(S.last.partial and S.last.total == math.floor(full / 10), 'read but marked partial')
        assert(S.reference(F.Engine.scope()) == full, 'the measure stays the complete list')
        -- The next answer of the same small size is again held back.
        now = now + 901; F.db.lastScan = 0
        C_AuctionHouse.GetNumReplicateItems = real
        assert(S.start())
        C_AuctionHouse.GetNumReplicateItems = function() return math.floor(full / 10) + 1 end
        run(S.SHORT - 10)
        assert(S.job and S.job.state == 'waiting', 'still a part')
        C_AuctionHouse.GetNumReplicateItems = real''')


class GearSellTests(unittest.TestCase):
    GEAR = BASE + '''UnitClass = function() return 'Druid', 'DRUID' end
    C_Item.GetItemInfoInstant = function(id)
        local kinds = { [81] = { 'INVTYPE_2HWEAPON', 2, 1 }, [82] = { 'INVTYPE_WEAPON', 2, 15 },
            [83] = { 'INVTYPE_HOLDABLE', 4, 0 }, [84] = { 'INVTYPE_CHEST', 4, 3 } }
        local k = kinds[id]
        if not k then return id end
        return id, '', '', k[1], 0, k[2], k[3]
    end
    addItem(81, 'Battle Slayer of the Tiger', 2162, 'gear'); addItem(82, 'Tail Spike', 1854, 'gear')
    addItem(83, 'Buccaneer Orb', 1148, 'gear'); addItem(84, 'Chain Vest', 900, 'gear')
    putBag(0, 1, 81, 1); putBag(0, 2, 82, 1); putBag(0, 3, 83, 1); putBag(0, 4, 84, 1)
    bags[0][2].isBound = true; bags[0][3].isBound = true
    '''

    def test_gear_the_class_cannot_use(self):
        run(self.GEAR + '''assert(F.AH.unusableGear(81) == true, 'a druid cannot wield axes')
        assert(F.AH.unusableGear(82) == false, 'daggers are fine')
        assert(F.AH.unusableGear(83) == false, 'off-hand items fit every class')
        assert(F.AH.unusableGear(84) == true, 'no mail for a druid')''')

    def test_the_gear_button_sells_bound_and_unbound_pieces_the_class_cannot_use(self):
        run(self.GEAR + '''F.db.settings.vendorMargin = 0
        local ids = {}
        for _, v in ipairs(T.unusableGearList()) do ids[#ids + 1] = v.id end
        table.sort(ids)
        assert(table.concat(ids, ',') == '81,84', table.concat(ids, ','))
        MerchantFrame:Show(); fire('MERCHANT_SHOW')
        assert(UI.gearButton:IsShown(), 'its own button at the merchant')
        UI.gearButton:Click()
        assert(#soldToVendor == 2)''')

    def test_bag_items_stay_for_sale_while_a_full_scan_is_awaited(self):
        run(BASE + '''addItem(91, 'Battle Axe', 2000, 'item'); putBag(0, 1, 91, 1)
        C_AuctionHouse.IsSellItemValid = function() return false end -- what the game says meanwhile
        replicateIgnored = true; assert(F.Scan.start()); run(2)
        local found = false
        for _, b in ipairs(F.AH.bagItems()) do if b.id == 91 then found = true end end
        assert(found, 'still listed for sale')''')


class MerchantScrollTests(unittest.TestCase):
    def test_more_offers_than_rows_scroll_with_the_mouse_wheel(self):
        run(BASE + '''local h = F.Data.market(F.db, F.Engine.scope()).history
        merchantItems = {}
        for i = 1, 7 do
            local id = 600 + i
            addItem(id, 'Ware ' .. i, 5, 'commodity')
            h['c:' .. id] = { scan = { at = now, market = 500 + i }, flow = { hours = 20, sold = { 48, 48, 48, 48 }, pairs = 3, at = now, market = 500 + i } }
            merchantItems[i] = { id = id, price = 100 }
        end
        MerchantFrame:Show(); fire('MERCHANT_SHOW'); UI.merchantTab:Click()
        local view = UI.merchantView
        assert(view.buyTitle:GetText():find('1%-4 / 7'), view.buyTitle:GetText())
        view.buyWheel(nil, -1); view.buyWheel(nil, -1); view.buyWheel(nil, -1); view.buyWheel(nil, -1)
        assert(view.buyTitle:GetText():find('4%-7 / 7'), 'scrolled to the end: ' .. view.buyTitle:GetText())''')


class CoinTests(unittest.TestCase):
    def test_money_shows_coins_and_edit_boxes_get_plain_text(self):
        run('''local U = ForeverFlip.Util
        U.coins = true
        local shown = U.money(123456)
        assert(shown:find('12|T', 1, true) and shown:find('UI-GoldIcon', 1, true) and shown:find('34|T', 1, true) and not shown:find('CopperIcon', 1, true), 'gold and silver, the copper left out: ' .. shown)
        assert(U.money(2650):find('26|T', 1, true) and U.money(2650):find('50|T', 1, true), 'silver and copper')
        assert(U.plainMoney(123456) == '12g 34s 56c', U.plainMoney(123456))
        assert(U.parseMoney(U.plainMoney(123456)) == 123456)
        assert(U.money(-250):sub(1, 1) == '-')''')


class BuyBusyTests(unittest.TestCase):
    def test_a_busy_way_is_said_on_the_click_and_cleared_for_the_next(self):
        run(BASE + '''fullScan(); D.verify('c:10'); answer()
        UI.selected = 'c:10'
        D.search = { key = 'c:999', item = { id = 999, kind = 'commodity' }, source = 'sniper', at = now, callbacks = {} }
        assert(T.canBuy(D.get('c:10')), 'Buy stays enabled for a ready deal')
        local ok, why = T.buy('c:10')
        assert(not ok and why == 'buy_busy' and D.holding(), 'said, and the background rests')
        D.search = nil
        assert(T.buy('c:10'), 'the next click buys')''')


class NameLinkTests(unittest.TestCase):
    def test_names_without_brackets_and_shift_click_links_to_chat(self):
        run(BASE + '''fullScan(); UI.show('deals:all'); UI.refresh()
        local row = UI.dealTable.rows[1]
        assert(row:IsShown() and row.link)
        local shown = row.name:GetText()
        assert(not shown:find('[', 1, true) and not shown:find(']', 1, true), shown)
        local inserted
        IsModifiedClick = function(what) return what == 'CHATLINK' end
        ChatEdit_InsertLink = function(l) inserted = l; return true end
        local selectedBefore = UI.selected
        row:Click()
        assert(inserted == row.link, 'the link goes to the chat line')
        assert(UI.selected == selectedBefore, 'a Shift-click does not select the deal')''')


class NativeLookTests(unittest.TestCase):
    def test_the_buy_tabs_look_is_copied_onto_the_menu_and_panels(self):
        run(BASE + '''local function tex(atlas)
            return { GetAtlas = function() return atlas end, GetTexture = function() return 1 end,
                GetVertexColor = function() return 1, 1, 1, 1 end, GetBlendMode = function() return 'BLEND' end }
        end
        local font = {}
        local native = {
            GetNormalTexture = function() return tex('native-button') end,
            GetHighlightTexture = function() return tex('native-highlight') end,
            GetSize = function() return 140, 22 end,
            GetFontString = function() return { GetFontObject = function() return font end } end,
        }
        local nine = { TopEdge = tex('native-top'), Center = tex('native-center') }
        AuctionHouseFrame.CategoriesList = {
            ScrollBox = { ScrollTarget = { GetChildren = function() return native end } },
            NineSlice = nine, Background = tex('native-background'),
        }
        AuctionHouseFrame.BrowseResultsFrame = { ItemList = { NineSlice = nine, Background = tex('native-results') } }
        UI.nativeLook = nil
        assert(UI.copyNativeLook(), 'copied')
        local c = UI.categories[1]
        assert(c.normal:GetAtlas() == 'native-button' and c.highlight:GetAtlas() == 'native-highlight')
        local w, h = c:GetSize()
        assert(w == 137 and h == 21, 'the size of the Buy tab buttons (137 by 21), kept')
        assert(UI.leftPanel.art:GetAtlas() == 'native-background' and UI.right.art:GetAtlas() == 'native-results')''')


class LookReportTests(unittest.TestCase):
    def test_the_look_report_runs_without_the_buy_tab(self):
        run(BASE + '''local lines = UI.lookReport()
        assert(#lines >= 1 and lines[1]:find('category list'), lines[1])
        SlashCmdList.FOREVERFLIP('look')''')


class DumpTests(unittest.TestCase):
    def test_the_dump_opens_a_box_to_copy(self):
        run(BASE + '''SlashCmdList.FOREVERFLIP('dump')
        local w = UI.exportFrame
        assert(w and w:IsShown(), 'a box to copy')
        assert(w.box:GetText():find('dump of the auction house window', 1, true), w.box:GetText():sub(1, 200))''')


class NativeMenuLayoutTests(unittest.TestCase):
    def test_the_menu_has_the_buy_tabs_sizes(self):
        run(BASE + '''UI.show('bids')
        local deals = UI.categories[1]
        local w, h = deals:GetSize()
        assert(w == 137 and h == 21, 'top entries 137 by 21')
        assert(deals.normal:GetAtlas() == 'auctionhouse-nav-button')
        local nw, nh = deals.normal:GetSize()
        assert(nw == 136 and nh == 32, 'the art keeps its own size')
        local sub = deals.subs[1]
        assert(sub.normal:GetAtlas() == 'auctionhouse-nav-button-secondary', 'sub-entries have the secondary art')
        local sw = sub:GetSize()
        assert(sw == 137, 'sub-entries are as wide as the top ones')''')


class SettingsMenuTests(unittest.TestCase):
    def test_settings_pages_open_from_the_menu(self):
        run(BASE + '''UI.show('settings:keys')
        local settings = UI.categories[#UI.categories]
        assert(settings.group.label == 'Settings' and #settings.subs == 4, 'four pages under Settings')
        assert(UI.settingFrames.keys:IsShown() and not UI.settingFrames.general:IsShown(), 'key bindings shown')
        UI.show('settings')
        assert(UI.settingFrames.general:IsShown() and UI.settingsTab == 'general', 'general is the first page')
        UI.settingTabs.safety:Click()
        assert(UI.section == 'settings' and UI.settingFrames.safety:IsShown(), 'the old shortcut opens the page')''')


class MerchantRefreshTests(unittest.TestCase):
    def test_the_sell_list_empties_once_the_bags_settle(self):
        run(BASE + '''F.db.settings.vendorMargin = 0
        addItem(71, 'Murloc Fin', 28, 'commodity'); putBag(0, 1, 71, 4)
        F.Data.market(F.db, F.Engine.scope()).history['c:71'] = { scan = { at = now, market = 20 } }
        MerchantFrame:Show(); fire('MERCHANT_SHOW'); UI.merchantTab:Click()
        assert(UI.merchantView.sellRows[1]:IsShown(), 'listed before the sale')
        F.Trade.sellAllToVendor(); run(0.1); fire('BAG_UPDATE_DELAYED')
        assert(not UI.merchantView.sellRows[1]:IsShown(), 'gone without another click')''')


class AntiUndercutTests(unittest.TestCase):
    PLAN = BASE + '''local T = F.Trade
    fullScan(); F.Scan.last.groups = nil
    owned = {{auctionID = 6, itemKey = {itemID = 30}, quantity = 1, buyoutAmount = 25000, status = 0, timeLeftSeconds = 43200}}
    fire('OWNED_AUCTIONS_UPDATED')
    T.prices['i:30'] = { rows = {{unit = 20000, qty = 2}}, at = now }
    local h = F.Data.market(F.db, F.Engine.scope()).history
    h['i:30'] = h['i:30'] or {}
    h['i:30'].flow = { hours = 24, sold = {6, 6, 6, 6, 6, 6, 6, 6, 6, 6}, pairs = 4, at = now, market = 25000 }
    '''

    def test_poisson_chances(self):
        run(BASE + '''local T = F.Trade
        assert(math.abs(T.atLeast(1, 1) - (1 - math.exp(-1))) < 1e-9, 'one sale in a mean of one')
        assert(T.atLeast(0, 0) == 1 and T.atLeast(3, 0) == 0)
        assert(T.atLeast(200, 400) > 0.99 and T.atLeast(400, 200) < 0.01, 'the normal approximation')''')

    def test_every_option_is_priced_and_the_best_advised(self):
        run(self.PLAN + '''local plan = T.fightPlans()[1]
        assert(plan and plan.ahead == 2 and plan.cheapest == 20000, 'the cheaper lots')
        for _, id in ipairs({'wait', 'undercut', 'buyout', 'vendor'}) do assert(plan[id], 'option ' .. id) end
        assert(plan.wait.p and plan.wait.p > 0 and plan.wait.p <= 1, 'a chance from the sales')
        local best = plan.best
        for _, o in ipairs(plan.options) do
            if o.ev and not o.blocked then assert(o.ev <= best.ev, o.id .. ' beats the advice') end
        end
        UI.show('undercuts'); UI.undercutTable.rows[1]:Click()
        local text = UI.fightText:GetText()
        assert(text:find('> ', 1, true) and text:find('chance', 1, true), text)''')

    def test_undercut_below_the_floor_is_not_offered(self):
        run(self.PLAN + '''F.db.rules = { ['i:30'] = { min = 24000 } }
        local plan = T.fightPlans()[1]
        assert(plan.undercut.blocked == 'floor' and plan.verdict ~= 'undercut')''')

    def test_buyout_goes_through_the_shopping_list(self):
        run(self.PLAN + '''local plan = T.fightPlans()[1]
        assert(T.fight(plan, 'buyout'))
        local e = F.Shopping.entry('i:30')
        assert(e and e.max < 25000 and e.qty == 2, 'the cheaper units, up to one step below my price')''')

    def test_answering_cancels_and_counts_the_rounds(self):
        run(self.PLAN + '''local plan = T.fightPlans()[1]
        assert(T.fight(plan, 'undercut') and T.rounds('i:30') == 1)
        assert(#T.fightPlans() == 0, 'a cancelled auction leaves the list')''')


class EmptyLinkNameTests(unittest.TestCase):
    def test_an_own_auction_with_an_empty_link_name_is_named(self):
        run(BASE + '''addItem(82, 'Sharp Throwing Axe', 1200, 'gear')
        owned = {{auctionID = 9, itemKey = {itemID = 82}, itemLink = '|cffffffff|Hitem:82::|h[]|h|r', quantity = 1, buyoutAmount = 5400, status = 0, timeLeftSeconds = 14400}}
        fire('OWNED_AUCTIONS_UPDATED')
        local a = F.Trade.owned[1]
        assert(a.key and a.key:find('sharp throwing axe', 1, true), tostring(a.key))
        UI.show('auctions'); UI.refresh()
        local shown = UI.auctionTable.rows[1].name:GetText()
        assert(shown and shown:find('Sharp Throwing Axe', 1, true), tostring(shown))''')


class RepostTests(unittest.TestCase):
    def test_a_lot_posted_again_is_not_a_sale(self):
        run(BASE + '''local M = F.Market
        -- 65 s and 70 s lots vanish, the same price and count come back running longer: reposts.
        local prev = M.unpackLots('400:1:1,6500:1:1,7000:1:1')
        local cur = M.unpackLots('6500:1:3,7000:1:3')
        local sold, byPrice = M.trackSales(prev, cur, 900)
        assert(not byPrice[6500] and not byPrice[7000], 'reposts are not sales')
        assert(byPrice[400] == 1, 'the 4 silver lot that vanished sold')''')

    def test_the_resale_cap_stays_near_the_typical_sale(self):
        run(BASE + '''local M = F.Market
        local h = { sales = { b = {} } }
        M.bucketAdd(h.sales.b, 290, 3); M.bucketAdd(h.sales.b, 400, 2); M.bucketAdd(h.sales.b, 6500, 2); M.bucketAdd(h.sales.b, 8000, 1)
        local cap = M.saleCap(h)
        assert(cap <= 3 * 400, 'at most three times the median sale: ' .. tostring(cap))''')


class BuyWayTests(unittest.TestCase):
    def test_a_busy_buy_click_holds_check_all_back(self):
        run(BASE + '''local D = F.Deals
        D.holdUntil = now + 5
        D.enqueue('c:10', function() end, 'x', true)
        run(1.1)
        assert(not D.search, 'a Check all search waits while the player is buying')
        now = now + 6; run(1.1)
        assert(D.search or #D.requests == 0, 'it goes on afterwards')''')

    def test_one_button_buys_and_confirms_a_commodity(self):
        run(BASE + '''fullScan()
        local key
        for _, d in ipairs(F.Deals.list) do if d.kind == 'commodity' then key = d.key end end
        if not key then return end
        UI.show('deals:all'); UI.selectDeal(key)
        local n = 0
        while F.Deals.pending(key) or F.Deals.search do if F.Deals.search then answer() end run(1.1); n = n + 1; assert(n < 30) end
        UI.refresh()
        assert(UI.buyButton:GetText():find('2', 1, true), UI.buyButton:GetText())
        UI.buyButton:Click()
        if F.Trade.op and F.Trade.op.state == 'quote' then fire('COMMODITY_PRICE_UPDATED', F.Trade.op.cost, F.Trade.op.cost) end
        UI.refresh()
        if F.Trade.op and F.Trade.op.state == 'quoted' then
            assert(UI.buyButton:GetText():find('Confirm', 1, true), 'the same button confirms')
            assert(not UI.confirmButton:IsShown())
        end''')


if __name__ == '__main__':
    unittest.main()
