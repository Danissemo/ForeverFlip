"""Hiding items from the Sell page and returning them."""

import unittest

from test_addon import SETUP, run

HIDE = SETUP + '''local F=ForeverFlip
local T,UI=F.Trade,F.UI
fullScan()
putBag(0,1,30,1);putBag(0,2,10,20)
UI.show('sell')
local function row(key) for _,r in ipairs(UI.sellTable.rows) do if r.key==key and r:IsShown() then return r end end end
'''


class HiddenItemsTests(unittest.TestCase):
    def test_hide_removes_the_item_from_sale_and_post_all(self):
        run(HIDE + '''assert(row('i:30'));row('i:30'):Click();UI.sellHide:Click()
        assert(T.hidden('i:30') and not row('i:30'),'hidden from the list')
        for _,b in ipairs(T.toPostAll()) do assert(b.key~='i:30','not posted by Post all') end
        assert(UI.sellHiddenTab:GetText()=='Hidden (1)' and UI.sellSaleTab:GetText()=='For sale (1)',UI.sellHiddenTab:GetText())''')

    def test_hidden_view_lists_and_returns_items(self):
        run(HIDE + '''row('i:30'):Click();UI.sellHide:Click()
        UI.sellHiddenTab:Click();assert(row('i:30') and not row('c:10'),'only hidden items')
        assert(UI.sellHide:GetText()=='Return to sale' and not UI.postButton:IsEnabled())
        if F.Deals.search then answer() end;run(1.1)
        row('i:30'):Click();assert(not F.Deals.search,'no price check in the hidden view')
        UI.sellHide:Click();assert(not T.hidden('i:30'))
        UI.sellSaleTab:Click();assert(row('i:30'))''')

    def test_hidden_item_not_in_the_bags_is_still_listed(self):
        run(HIDE + '''T.hide('c:99','Old Junk');UI.sellHiddenTab:Click()
        local r=row('c:99');assert(r and r.name:GetText()=='Old Junk' and r.cols[1]:GetText()=='-')''')

    def test_hidden_purchase_is_skipped_by_post_next_bought(self):
        run(HIDE + '''local c=F.Data.char(F.db,F.Engine.owner())
        F.Data.addPosition(c,'i:30','Linen Bag',1,20000,'flip',29900,now)
        assert(#T.toPost()==1);T.hide('i:30','Linen Bag');assert(#T.toPost()==0)''')

    def test_price_box_is_cleared_after_posting(self):
        run(HIDE + '''row('i:30'):Click();run(1.1);answer();UI.refresh()
        assert(UI.sellPrice:GetText()~='');UI.postButton:Click()
        assert(UI.sellPrice:GetText()=='' and UI.sellSelected==nil)''')


if __name__ == '__main__':
    unittest.main()


class BestWayTests(unittest.TestCase):
    """The Best column and the two Post all buttons: everything, or only what the auction house pays
    more for than a vendor."""

    SETUP = HIDE + """F.db.settings.vendorMargin = 0
    local history = F.Data.market(F.db, F.Engine.scope()).history
    -- Linen Bag: a merchant pays 20s, the auction house about 21s before the cut and deposits.
    history['i:30'] = { scan = { at = now, market = 2100 } }
    -- Linen Cloth: a merchant pays 1s, the auction house far more.
    history['c:10'] = { scan = { at = now, market = 5000 } }
    """

    def test_vendor_or_auction_per_item(self):
        run(self.SETUP + """assert(T.bestWay('i:30', 30) == 'vendor', T.bestWay('i:30', 30))
        assert(T.bestWay('c:10', 10) == 'auction', T.bestWay('c:10', 10))
        F.Data.market(F.db, F.Engine.scope()).history['i:30'] = nil
        assert(T.bestWay('i:30', 30) == 'unknown', 'no auction price: unknown, not vendor')""")

    def test_post_ah_worthy_leaves_vendor_items_out(self):
        run(self.SETUP + """local function has(list, key) for _, b in ipairs(list) do if b.key == key then return true end end end
        assert(has(T.toPostAll(), 'i:30') and has(T.toPostAll(), 'c:10'), 'Post all: everything')
        assert(not has(T.toPostAll(true), 'i:30') and has(T.toPostAll(true), 'c:10'), 'AH-worthy: no vendor item')
        UI.refresh()
        assert(UI.postAll:GetText() == 'Post all (2)', UI.postAll:GetText())
        assert(UI.postAuction:GetText() == 'Post AH-worthy (1)', UI.postAuction:GetText())
        assert(row('i:30').cols[4]:GetText():find('Vendor'), row('i:30').cols[4]:GetText())
        assert(row('c:10').cols[4]:GetText():find('AH'), row('c:10').cols[4]:GetText())
        UI.postAuction:Click()
        local q = lastCall('SendSearchQuery') or lastCall('PostCommodity') or lastCall('PostItem')
        assert(not lastCall('PostItem'), 'the vendor item is not posted')""")


class CheckAllTests(unittest.TestCase):
    """Check all on every page with a list: each entry is searched again and the page shows it."""

    DRIVE = """
    local function finish()
        local n = 0
        while select(3, F.Deals.batchProgress()) do
            if F.Deals.search then answer() end
            run(1.1); n = n + 1; assert(n < 200, 'the batch never ends')
        end
    end
    """

    def test_crafting_reads_materials_and_products_and_prices_with_them(self):
        run(HIDE + self.DRIVE + """F.Data.char(F.db, F.Engine.owner()).recipes = { [1] = { name = 'Bag', out = 30, n = 1, r = { { 10, 2 } } } }
        local keys = F.Crafting.keys()
        assert(#keys == 2 and keys[1] == 'c:10' and keys[2] == 'i:30', table.concat(keys, ','))
        UI.show('crafting'); UI.refresh()
        assert(UI.bulkButton:GetText() == 'Check all' and UI.bulkButton:IsEnabled())
        UI.bulkButton:Click(); finish()
        local live = F.Trade.freshCheapest('c:10')
        assert(live, 'the material was checked')
        local history = F.Data.market(F.db, F.Engine.scope()).history
        assert(F.Crafting.materialCost(history, 10) <= live, 'the recipe is priced with the check')""")

    def test_shopping_list_finds_shopping_deals(self):
        run(HIDE + self.DRIVE + """F.Shopping.add('c:10', 1000000, 5, 'Linen Cloth')
        UI.show('shop'); UI.refresh()
        assert(UI.bulkButton:IsEnabled(), 'the shopping list can be checked')
        UI.bulkButton:Click(); finish()
        local done, total = F.Deals.batchProgress()
        assert(total == 1 and done == 1, done .. '/' .. total)""")

    def test_bids_page_checks_every_candidate(self):
        run(HIDE + self.DRIVE + """F.Bids.candidates = { { key = 'i:30', id = 30, count = 1, value = 100000, bid = 100, profit = 1000 } }
        UI.show('bids'); UI.refresh()
        assert(UI.bulkButton:IsEnabled(), 'bids can be checked')
        UI.bulkButton:Click(); finish()
        local done, total = F.Deals.batchProgress()
        assert(total == 1 and done == 1, done .. '/' .. total)""")

    def test_a_fresh_check_moves_the_best_column(self):
        run(HIDE + """F.db.settings.vendorMargin = 0
        F.Data.market(F.db, F.Engine.scope()).history['i:30'] = { scan = { at = now, market = 2100 } }
        assert(T.bestWay('i:30', 30) == 'vendor')
        T.prices['i:30'] = { rows = { { unit = 90000, qty = 1 } }, at = now }
        assert(T.bestWay('i:30', 30) == 'auction', 'the live price says the auction house pays more')""")


class PostingQueueTests(unittest.TestCase):
    def test_the_first_click_reads_every_price_then_each_click_posts(self):
        run(HIDE + """local posts = 0
        local function count() posts = 0 for _, c in ipairs(calls) do if c[1] == 'PostItem' or c[1] == 'PostCommodity' then posts = posts + 1 end end return posts end
        local ok, why = T.postAll()
        assert(why == 'checking', tostring(why))
        assert(F.Deals.pending('i:30') and F.Deals.pending('c:10'), 'both prices are read at once')
        local n = 0
        while F.Deals.search or #F.Deals.requests > 0 do
            if F.Deals.search then answer() end
            run(1.1); n = n + 1; assert(n < 50)
        end
        T.postAll(); fire('AUCTION_HOUSE_AUCTION_CREATED', 1); run(1)
        assert(count() == 1, 'the second click posts: ' .. count())
        T.posting = nil
        T.postAll(); fire('AUCTION_HOUSE_AUCTION_CREATED', 2); run(1)
        assert(count() == 2, 'the third click posts the other item: ' .. count())""")


class ScrollTests(unittest.TestCase):
    def test_a_long_list_scrolls_with_the_mouse_wheel(self):
        run(SETUP + """local F, UI = ForeverFlip, ForeverFlip.UI
        for i = 1, 15 do addItem(700 + i, 'Ware ' .. string.format('%02d', i), 10, 'item'); putBag(1 + math.floor((i - 1) / 16), 1 + (i - 1) % 16, 700 + i, 1) end
        UI.show('sell'); UI.refresh()
        local function shown() local n, names = 0, {} for _, r in ipairs(UI.sellTable.rows) do if r:IsShown() then n = n + 1; names[r.key] = true end end return n, names end
        local n, names = shown()
        assert(n == 12, 'twelve rows: ' .. n)
        assert(UI.sellTable.headers[1]:GetText():find('1%-12 / 15'), UI.sellTable.headers[1]:GetText())
        UI.sellTable.wheel(nil, -1); UI.sellTable.wheel(nil, -1)
        n, names = shown()
        assert(UI.sellTable.headers[1]:GetText():find('4%-15 / 15'), UI.sellTable.headers[1]:GetText())
        local seen = 0
        for i = 1, 15 do if names['i:' .. (700 + i)] then seen = seen + 1 end end
        assert(n == 12 and seen >= 1, 'the last items are reachable')
        UI.sellTable.wheel(nil, 5)
        assert(UI.sellTable.headers[1]:GetText():find('1%-12'), 'back to the top')""")
