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
