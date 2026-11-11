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
