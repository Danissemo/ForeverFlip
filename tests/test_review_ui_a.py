"""Review fixes of the auction house window (UI.lua, Shopping.lua, Locale.lua): each test is the
failure the review found, reproduced, and the behaviour that replaces it."""

import unittest

from test_addon import SETUP, run
from test_hidden_items import HIDE

BASE = SETUP + r'''local F, D, T, UI = ForeverFlip, ForeverFlip.Deals, ForeverFlip.Trade, ForeverFlip.UI
F.db.settings.autoVerify = false; F.db.settings.sniper = false
local function count(name)
    local n = 0
    for _, c in ipairs(calls) do if c[1] == name then n = n + 1 end end
    return n
end
local function shownRows(t)
    local out = {}
    for _, r in ipairs(t.rows) do if r:IsShown() then out[#out + 1] = r end end
    return out
end
-- A row shows an item link without its brackets: |h<name>|h.
local function shownName(r)
    return r.name:GetText():match('|h(.-)|h') or r.name:GetText()
end
'''

# A cloth vendor deal checked and quoted for purchase (the Buy button reads "Confirm").
QUOTED = BASE + r'''fullScan(); D.verify('c:10'); answer()
UI.show('deals:all'); UI.selectDeal('c:10')
UI.buyButton:Click(); fire('COMMODITY_PRICE_UPDATED', 60, 900)
assert(T.op and T.op.state == 'quoted' and T.op.key == 'c:10')
'''

# Two vendor purchases of cloth in the journal: 5 bought two hours ago, 3 now.
LOTS = BASE + r'''local c = F.Data.char(F.db, F.Engine.owner())
local function buy(qty, cost, at)
    F.Data.addPosition(c, 'c:10', 'Linen Cloth', qty, cost, 'vendor', nil, at)
    F.Data.log(c, { kind = 'buy', key = 'c:10', name = 'Linen Cloth', qty = qty, amount = cost, at = at,
        mode = 'vendor' })
end
local function lotRow(lot)
    for _, r in ipairs(UI.lotTable.rows) do if r:IsShown() and r.lotID == lot.id then return r end end
end
'''

# One undercut own auction per item ('Item 01'.. ), each with two cheaper units of a rival.
UNDERCUTS = BASE + r'''fullScan(); F.Scan.last.groups = nil
owned = {}
local h = F.Data.market(F.db, F.Engine.scope()).history
local function undercut(n, id, name, kind)
    addItem(id, name, 10, kind or 'item')
    owned[#owned + 1] = { auctionID = 100 + n, itemKey = { itemID = id }, itemLink = link(id), quantity = 1,
        buyoutAmount = 25000, status = 0, timeLeftSeconds = 43200 }
    local key = (kind == 'commodity' and 'c:' or 'i:') .. id
    T.prices[key] = { rows = { { unit = 20000 + n * 10, qty = 2 } }, at = now }
    h[key] = h[key] or {}
    h[key].flow = { hours = 24, sold = { 6, 6, 6, 6, 6, 6, 6, 6, 6, 6 }, pairs = 4, at = now, market = 25000 }
end
'''


class SelectionQuoteTests(unittest.TestCase):
    def test_ignoring_the_quoted_deal_cancels_its_quote(self):
        run(QUOTED + r'''UI.ignoreButton:Click()
        assert(F.Shopping.blocked('c:10') and UI.selected == nil)
        assert(not T.op and count('CancelCommoditiesPurchase') == 1, 'the quote went with the selection')
        UI.buyButton:Click()
        assert(count('ConfirmCommoditiesPurchase') == 0, 'nothing of the ignored item is bought')''')

    def test_a_page_filter_that_hides_the_quoted_deal_cancels_its_quote(self):
        run(QUOTED + r'''UI.show('deals:flip')
        assert(UI.selected == nil and not T.op)
        UI.buyButton:Click()
        assert(count('ConfirmCommoditiesPurchase') == 0)''')

    def test_buy_with_nothing_selected_cancels_a_quote_instead_of_confirming_it(self):
        run(QUOTED + r'''UI.selected = nil; UI.refresh()
        UI.buyButton:Click()
        assert(not T.op and count('ConfirmCommoditiesPurchase') == 0)''')


class JournalResolveTests(unittest.TestCase):
    def test_vendor_sold_books_only_the_oldest_open_lot_once_at_the_merchant_price(self):
        run(LOTS + r'''buy(5, 300, now - 7200); buy(3, 180, now)
        F.db.vendorSeen[10] = { p = 70, t = now, c = 100 } -- a merchant paid 70c; the client says 100c
        local old, new = c.lots[1], c.lots[2]
        UI.show('journal'); UI.refreshJournal()
        lotRow(new):Click(); UI.journalResolve.vendor:Click()
        assert(old.left == 5 and new.left == 3 and not new.reconciled, 'the newer lot would empty the older one')
        assert(F.Engine.message == 'older_lot', tostring(F.Engine.message))
        lotRow(old):Click(); UI.journalResolve.vendor:Click()
        assert(old.left == 0 and old.received == 350 and old.reconciled == 'vendor', old.received)
        assert(new.left == 3 and new.sold == 0, 'the newer lot is untouched')
        assert(not UI.journalResolve.vendor:IsEnabled() and not UI.journalResolve.held:IsEnabled(), 'resolved once')
        UI.journalResolve.vendor.scripts.OnClick(UI.journalResolve.vendor)
        assert(new.left == 3, 'a repeated click books nothing')
        lotRow(new):Click(); UI.journalResolve.vendor:Click()
        assert(new.left == 0 and new.received == 210, 'now the oldest open lot')''')

    def test_a_resolved_lot_does_not_flag_a_newer_one_unconfirmed(self):
        run(LOTS + r'''buy(5, 300, now - 86400) -- not in the bags (bank)
        UI.show('journal'); UI.refreshJournal()
        lotRow(c.lots[1]):Click(); UI.journalResolve.held:Click()
        buy(3, 180, now); putBag(0, 1, 10, 3) -- all three in the bags
        UI.refreshJournal()
        local text = lotRow(c.lots[2]).cols[6]:GetText()
        assert(not text:find('Unconfirmed', 1, true), text)''')


class BidsPageTests(unittest.TestCase):
    def test_an_ended_bid_cannot_be_bought_out(self):
        run(BASE + r'''local c = F.Data.char(F.db, F.Engine.owner())
        c.bids = { [77] = { key = 'i:30', name = 'Linen Bag', qty = 1, amount = 500, at = now - 60 } }
        myBids = { { auctionID = 77, itemKey = { itemID = 30 }, itemLink = link(30), minBid = 600,
            bidAmount = 500, buyoutAmount = 900, timeLeft = 1, bidder = 'Player-1' } }
        fire('BIDS_UPDATED')
        UI.show('mybids'); UI.myBidTable.rows[1]:Click(); UI.refresh()
        assert(UI.myBidBuyout:IsEnabled(), 'a running auction can be bought out')
        now = now + 60; myBids = {}; fire('BIDS_UPDATED'); UI.refresh() -- gone from the list: it ended
        assert(UI.myBidTable.rows[1].cols[5]:GetText():find('ended', 1, true))
        assert(not UI.myBidBuyout:IsEnabled(), 'the auction is over')''')

    def test_an_open_bid_without_a_name_does_not_break_the_bids_page(self):
        run(BASE + r'''addItem(40, 'Silk Bag', 500, 'item'); items[40].cached = false
        myBids = { { auctionID = 88, itemKey = { itemID = 40 }, minBid = 600, bidAmount = 500,
            buyoutAmount = 0, timeLeft = 1, bidder = 'Player-1' } }
        fire('BIDS_UPDATED')
        UI.show('bids'); UI.refreshBids()
        assert(UI.bidText:GetText():find('Your open bids: 1', 1, true), UI.bidText:GetText())''')


class TableTests(unittest.TestCase):
    def test_item_links_sort_by_their_names(self):
        run(BASE + r'''addItem(300, 'Apple', 10, 'item'); addItem(25, 'Banana', 10, 'item')
        addItem(1000, 'Cherry', 10, 'item'); addItem(7, 'Zucchini', 10, 'item')
        owned = {}
        for i, id in ipairs({ 7, 1000, 300, 25 }) do
            owned[i] = { auctionID = i, itemKey = { itemID = id }, itemLink = link(id), quantity = 1,
                buyoutAmount = 100, status = 0, timeLeftSeconds = 43200 }
        end
        fire('OWNED_AUCTIONS_UPDATED')
        UI.show('auctions'); UI.auctionTable.headers[1]:Click()
        local names = {}
        for _, r in ipairs(shownRows(UI.auctionTable)) do names[#names + 1] = shownName(r) end
        assert(table.concat(names, ',') == 'Apple,Banana,Cherry,Zucchini', table.concat(names, ','))''')

    def test_undercuts_scroll_and_sort_past_the_first_ten(self):
        run(UNDERCUTS + r'''for n = 1, 13 do undercut(n, 500 + n, string.format('Item %02d', n)) end
        fire('OWNED_AUCTIONS_UPDATED')
        assert(#T.fightPlans() == 13)
        UI.show('undercuts')
        local t = UI.undercutTable
        assert(t.headers[1]:GetText():find('(1-10 / 13)', 1, true), t.headers[1]:GetText())
        local seen = {}
        for _, r in ipairs(shownRows(t)) do seen[r.plan.auction.auctionID] = true end
        for _ = 1, 3 do t.wheel(nil, -1) end
        assert(t.offset == 3, t.offset)
        for _, r in ipairs(shownRows(t)) do seen[r.plan.auction.auctionID] = true end
        for n = 1, 13 do assert(seen[100 + n], 'plan ' .. n .. ' reachable') end
        t.offset = 0; t.headers[1]:Click(); t.headers[1]:Click() -- Name, Z..A
        assert(shownName(t.rows[1]) == 'Item 13', t.rows[1].name:GetText())''')

    def test_statistics_count_every_stale_item(self):
        run(BASE + r'''local c = F.Data.char(F.db, F.Engine.owner())
        for n = 1, 20 do -- 18 held 5 days without a sale, 2 fresh
            addItem(700 + n, string.format('Stock %02d', n), 10, 'item')
            c.positions['i:' .. (700 + n)] = { qty = 1, cost = 100, since = now - (n <= 18 and 5 or 1) * 86400,
                name = string.format('Stock %02d', n) }
        end
        UI.show('stats')
        local function stale() return tonumber(UI.statsText:GetText():match('stale items[^:]*: (%d+)')) end
        assert(stale() == 18, UI.statsText:GetText())
        for _ = 1, 2 do UI.statsTable.wheel(nil, -1) end
        assert(UI.statsTable.offset > 0 and stale() == 18, 'scrolling does not change it')''')

    def test_my_auctions_count_every_undercut_auction(self):
        run(BASE + r'''owned = {}
        for n = 1, 24 do -- 20 undercut, 4 the cheapest
            addItem(800 + n, string.format('Lot %02d', n), 10, 'item')
            owned[n] = { auctionID = 300 + n, itemKey = { itemID = 800 + n }, itemLink = link(800 + n), quantity = 1,
                buyoutAmount = 25000, status = 0, timeLeftSeconds = 43200 }
        end
        fire('OWNED_AUCTIONS_UPDATED')
        for n = 1, 24 do
            T.prices['i:' .. (800 + n)] = { rows = { { unit = n <= 20 and 20000 or 30000, qty = 1 } }, at = now }
        end
        UI.show('auctions')
        assert(UI.auctionText:GetText():find('Undercut: 20', 1, true), UI.auctionText:GetText())
        for _ = 1, 3 do UI.auctionTable.wheel(nil, -1) end
        assert(UI.auctionTable.offset > 0, 'scrolled')
        assert(UI.auctionText:GetText():find('Undercut: 20', 1, true), UI.auctionText:GetText())''')

    def test_a_short_text_box_can_be_scrolled_with_its_thumb(self):
        run(BASE + r'''local cy = 500
        GetCursorPosition = function() return 0, cy end
        local box, lines = UI.dealBox, {}
        for i = 1, 12 do lines[i] = 'line ' .. i end
        local thumb, track = box.bar.thumb, box.bar.track
        thumb.SetHeight = function(self, h) rawset(self, 'h', h) end -- the mock keeps no height
        box.set(lines, 'test')
        local _, trackHeight = track:GetSize()
        local thumbHeight = rawget(thumb, 'h')
        assert(thumbHeight < trackHeight, thumbHeight .. ' of ' .. trackHeight)
        thumb.scripts.OnMouseDown(thumb); cy = 460; thumb.scripts.OnUpdate(thumb); thumb.scripts.OnMouseUp(thumb)
        assert(box.offset == #lines - box.rows, 'dragged to the end: ' .. box.offset)''')


class UndercutOrderTests(unittest.TestCase):
    def test_buy_out_while_an_order_runs_acts_only_on_that_item(self):
        run(UNDERCUTS + r'''undercut(1, 901, 'Xeno Ring'); undercut(2, 902, 'Yew Staff')
        addAuction(901, 20000, 1, 'Rival'); addAuction(901, 20000, 1, 'Rival')
        fire('OWNED_AUCTIONS_UPDATED')
        UI.show('undercuts')
        local function select(id)
            for _, r in ipairs(shownRows(UI.undercutTable)) do if r.plan.auction.auctionID == id then r:Click() end end
        end
        select(101); UI.fightButtons.buyout:Click()
        assert(T.fightOrder and T.fightOrder.key == 'i:901', 'the order for X')
        for _ = 1, 30 do if D.search then break end run(0.2) end
        if D.search then answer() end
        run(0.1); UI.refresh()
        assert(T.fightOrderReady(), 'X can be bought')
        select(102); UI.refresh()
        local b = UI.fightButtons.buyout
        assert(not b:IsEnabled(), 'Y selected: buy out would act on Y, not on the running order')
        b.scripts.OnClick(b)
        assert(T.fightOrder.key == 'i:901' and not F.Shopping.orderEntry('i:902'), "X's order stays")
        select(101); UI.refresh()
        assert(b:IsEnabled(), 'X selected: its order goes on')''')


class MenuAndStatusTests(unittest.TestCase):
    def test_only_the_open_settings_page_is_highlighted(self):
        run(BASE + r'''local function lit()
            local out = {}
            for _, c in ipairs(UI.categories) do
                for _, s in ipairs(c.subs) do if s:IsShown() and s.selected:IsShown() then out[#out + 1] = s.id end end
            end
            return table.concat(out, ',')
        end
        UI.show('settings:keys'); assert(lit() == 'settings:keys', lit())
        UI.show('journal:flip'); assert(lit() == 'journal', 'a view opens its page: ' .. lit())''')

    def test_the_run_checking_reason_is_shown_as_text(self):
        run(BASE + r'''F.Engine.notify('run_checking'); UI.refresh()
        local shown = UI.status:GetText()
        assert(shown == 'Checking the current price first: press again when it is ready.', shown)
        F.Locale.apply('uk'); UI.refresh()
        shown = UI.status:GetText()
        assert(shown ~= 'run_checking' and not shown:find('Checking', 1, true), shown)''')

    def test_check_all_on_undercuts_names_the_page(self):
        run(UNDERCUTS + r'''undercut(1, 901, 'Xeno Ring'); undercut(2, 902, 'Yew Staff')
        fire('OWNED_AUCTIONS_UPDATED')
        F.Locale.apply('uk')
        UI.show('undercuts'); F.Engine.message = nil
        UI.bulkButton:Click(); UI.refresh()
        assert(D.batch and D.batch.scope == 'undercuts')
        assert(UI.status:GetText():find(F.Locale.text('Undercuts'), 1, true), UI.status:GetText())''')

    def test_native_row_look_is_found_behind_a_texture(self):
        run(BASE + r'''local function tex(name)
            return { GetObjectType = function() return 'Texture' end, GetTexture = function() return name end,
                GetAtlas = function() return name end }
        end
        local text = { GetObjectType = function() return 'FontString' end,
            GetFont = function() return 'Fonts/ARIALN.TTF', 13, '' end, GetText = function() return 'Linen Cloth' end }
        local row = { NormalTexture = tex('stripe') }
        row.GetRegions = function() return tex('stripe'), text end -- the text is the second region
        AuctionHouseFrame.BrowseResultsFrame = { ItemList = { ScrollBox = { ScrollTarget = {
            GetChildren = function() return row end } } } }
        UI.nativeRows, UI.tables = nil, {}
        assert(UI.copyNativeRows() and UI.nativeRows)
        local a = { GetObjectType = function() return 'Frame' end, Alpha = {} }
        local b = { GetObjectType = function() return 'Button' end, Beta = {} }
        AuctionHouseFrame.CategoriesList = { ScrollBox = { ScrollTarget = {
            GetChildren = function() return a, b end } } }
        local report = table.concat(UI.lookReport(), '\n')
        assert(report:find('list elements: Frame{Alpha} Button{Beta}', 1, true), report)''')


class PricesShownTests(unittest.TestCase):
    def test_cheapest_today_on_the_shopping_list_is_only_today(self):
        run(BASE + r'''F.Shopping.add('c:10', 200, nil, 'Linen Cloth')
        fullScan()
        UI.show('shop')
        assert(UI.shopTable.rows[1].cols[3]:GetText() ~= '-', 'scanned today')
        now = now + 3 * 86400; UI.refresh()
        assert(UI.shopTable.rows[1].cols[3]:GetText() == '-', UI.shopTable.rows[1].cols[3]:GetText())''')

    def test_the_shopping_list_shows_the_saved_rule_not_an_undercuts_order(self):
        run(BASE + r'''local S = F.Shopping
        S.add('c:10', 5000, nil, 'Linen Cloth')
        assert(S.order('c:10', 299, 2, 'Linen Cloth', 300))
        UI.show('shop')
        local r = UI.shopTable.rows[1]
        assert(r.key == 'c:10' and r.cols[1]:GetText() == F.Util.money(5000) and r.cols[2]:GetText() == 'any',
            r.cols[1]:GetText() .. ' / ' .. r.cols[2]:GetText())
        S.block('i:30', 'Linen Bag'); assert(S.order('i:30', 100, 1, 'Linen Bag', 200))
        UI.refresh()
        for _, row in ipairs(shownRows(UI.shopTable)) do if row.key == 'i:30' then row:Click() end end
        UI.shopRemove:Click()
        assert(not S.blocked('i:30'), 'Remove on the ignored row stops ignoring it')''')

    def test_why_the_normal_price_when_nobody_else_sells(self):
        run(BASE + r'''local alone = UI.quoteWhy({ why = 'normal' })
        assert(alone == 'normal price: nobody else sells it now', alone)
        local named = UI.quoteWhy({ why = 'normal', cheapest = 900 })
        assert(named:find(F.Util.money(900), 1, true), named)''')

    def test_price_history_days_are_labelled_with_their_utc_date(self):
        run(BASE + r'''-- A client five hours west of UTC: its local date at a UTC midnight is the day before.
        date = function(fmt, t)
            if fmt:sub(1, 1) == '!' then return os.date(fmt, t) end
            return os.date('!' .. fmt, (t or now) - 5 * 3600)
        end
        fullScan()
        local h = F.Data.market(F.db, F.Engine.scope()).history['c:10']
        local day = h.days[#h.days].d
        UI.showHistory('c:10')
        local label
        for _, bar in ipairs(UI.historyFrame.bars) do
            if bar.label:GetText() ~= '' then label = bar.label:GetText() end
        end
        assert(label == os.date('!%d.%m', day * 86400), tostring(label))''')

    def test_sell_suggestions_name_the_price_the_box_gets(self):
        run(HIDE + r'''F.db.settings.vendorMargin = 0
        F.Data.market(F.db, F.Engine.scope()).history['i:30'] = nil
        F.db.lastPosted = F.db.lastPosted or {}; F.db.lastPosted['i:30'] = 20000 -- posted at 2g before
        F.Data.addPosition(F.Data.char(F.db, F.Engine.owner()), 'i:30', 'Linen Bag', 1, 30000, 'flip', 40000, now)
        UI.show('sell'); UI.refresh(); row('i:30'):Click()
        if F.Deals.search then answer() end
        T.prices['i:30'] = { rows = {}, at = now } -- nobody else sells it
        UI.refresh()
        local price, floor, _, why = T.suggest({ key = 'i:30', id = 30, kind = 'item' })
        assert(why == 'last' and floor > price, tostring(why))
        local text = UI.sellBox.full()
        assert(text:find('your last price ' .. F.Util.money(floor), 1, true), text)
        assert(UI.sellPrice:GetText() == F.Util.plainMoney(floor))''')

    def test_the_sells_at_tooltip_names_the_house_cut(self):
        run(BASE + r'''F.Engine.house = 'Neutral'; F.Engine.applyCut()
        assert(F.Market.CUT == 0.15)
        UI.show('deals:all')
        local header = UI.dealTable.headers[4]
        header.scripts.OnEnter(header)
        assert(GameTooltip:GetText():find('Profit counts the 15% cut', 1, true), GameTooltip:GetText())
        F.Locale.apply('uk')
        header.scripts.OnEnter(header)
        assert(GameTooltip:GetText():find('15% комісії', 1, true), GameTooltip:GetText())''')

    def test_the_ukrainian_separator_is_no_pipe(self):
        run(BASE + r'''F.Locale.apply('uk')
        assert(not F.Locale.text('·'):find('|', 1, true), F.Locale.text('·'))''')


class DealsRepaintTests(unittest.TestCase):
    def test_sure_is_worked_out_for_the_rows_in_view_unless_sorted_by_it(self):
        run(BASE + r'''D.list = {}
        for n = 1, 40 do
            local id = 600 + n
            addItem(id, 'Potion ' .. n, 10, 'commodity')
            D.list[n] = { key = 'c:' .. id, id = id, kind = 'commodity', mode = 'flip', qty = 1, cost = 100,
                profit = 10 + n, maxUnit = 100, exit = 200, found = now }
        end
        local asked, sure = {}, D.sure
        D.sure = function(d, ...) asked[d.key] = true; return sure(d, ...) end
        local function counted()
            local n = 0
            for _ in pairs(asked) do n = n + 1 end
            asked = {}
            return n
        end
        UI.show('deals:all'); asked = {}; UI.refreshDeals()
        assert(counted() == #UI.dealTable.rows, 'the rows in view')
        UI.dealSort = 7; UI.refreshDeals()
        assert(counted() == 40, 'sorting by Sure needs every deal')''')


if __name__ == '__main__':
    unittest.main()
