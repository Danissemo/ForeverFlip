"""Market-based routing stays consistent with the merchant list and bounded selling text."""

import unittest

from test_addon import run


WOOL = '''local F=ForeverFlip;local T,UI=F.Trade,F.UI
F.db.settings.autoScan=false;F.db.settings.sniper=false;F.Engine.autoVerify=false
F.db.settings.vendorMargin=0
addItem(3530,'Wool Bandage',28,'commodity');putBag(0,1,3530,41)
local key='c:3530';local c=F.Data.char(F.db,F.Engine.owner())
F.Data.addPosition(c,key,'Wool Bandage',21,21*27,'other',nil,now)
c.rates={['wool bandage']={sold=10,failed=0}}
local history=F.Data.market(F.db,F.Engine.scope()).history
history[key]={scan={at=now,market=28}}
T.prices[key]={rows={{unit=27,qty=100}},at=now}
'''


class VendorConsistencyTests(unittest.TestCase):
    def test_tooltip_best_column_and_merchant_agree_below_the_floor(self):
        run(WOOL + '''UI.show('sell');UI.sellSelected=F.AH.bagItems()[1];UI.refreshSell()
        local row
        for _,r in ipairs(UI.sellTable.rows) do if r.key==key then row=r end end
        assert(row and row.cols[4]:GetText():find('Vendor',1,true))
        tooltipLines={};GameTooltip.itemLink=link(3530)
        for _,fn in ipairs(tooltipCalls) do fn(GameTooltip) end
        local tip=table.concat(tooltipLines,' | ')
        assert(tip:find('Best: sell to a vendor',1,true) and not tip:find('Best: post on the auction house',1,true))
        assert(tip:find('Auction at market price, after fees',1,true))
        assert(UI.sellBox.full():find('Vendor pays',1,true) and #T.vendorSellList()==1)
        ''')

    def test_new_merchant_path_does_not_add_untracked_bound_items(self):
        run(WOOL + '''bags[0][1].isBound=true
        assert(#T.vendorSellList()==0,'generic merchant advice must preserve the old bound-item exclusion')
        ''')

    def test_profit_floor_does_not_invent_a_better_auction_exit(self):
        run(WOOL + '''local q=T.quote(key,3530)
        assert(q.belowFloor and q.post>q.market and q.post==q.floor,'manual posting still respects the floor')
        assert(q.best=='vendor' and T.bestWay(key,3530)=='vendor','compare actual market proceeds, not the raised floor')
        assert(q.marketNet<q.vendor and q.marketPost==q.market)
        ''')

    def test_advice_does_not_flip_when_live_cache_expires_or_cost_basis_disappears(self):
        run(WOOL + '''assert(T.bestWay(key,3530)=='vendor')
        now=now+301;assert(T.bestWay(key,3530)=='vendor','the usual price is still below vendor after fees')
        c.positions[key]=nil
        assert(T.bestWay(key,3530)=='vendor','cost basis changes posting protection, not the best real exit')
        ''')

    def test_merchant_list_does_not_require_auction_sellability(self):
        run(WOOL + '''C_AuctionHouse.IsSellItemValid=function() return false end
        AuctionHouseFrame:Hide();MerchantFrame:Show()
        local list=T.vendorSellList()
        assert(#list==1 and list[1].key==key and list[1].count==41,'best vendor item must remain sellable outside the auction house')
        ''')

    def test_hidden_kept_and_locked_items_are_not_sold(self):
        run(WOOL + '''c.positions[key].mode='vendor'
        T.hide(key,'Wool Bandage');assert(#T.vendorSellList()==0,'hidden vendor stock stays')
        T.unhide(key);T.setRule(key,{keep=1});assert(#T.vendorSellList()==0,'reserved vendor stock stays')
        T.setRule(key,{});bags[0][1].isLocked=true
        assert(#T.vendorSellList()==0,'locked stock stays')
        ''')

    def test_sell_explanation_scrolls_without_growing_into_the_price_controls(self):
        run(WOOL + '''UI.show('sell');UI.sellSelected=F.AH.bagItems()[1];UI.refreshSell()
        assert(UI.sellBox and UI.sellBox.rows==3,'three fixed text rows above the price controls')
        assert(UI.sellBox.full():find('below your minimum',1,true),'warning is retained in scrollable content')
        assert(#UI.sellBox.lines>UI.sellBox.rows)
        UI.sellBox.bar.forward:Click();local offset=UI.sellBox.offset
        assert(offset==1);UI.refreshSell();assert(UI.sellBox.offset==offset,'same item keeps scroll position')
        for i=1,20 do UI.sellBox.bar.forward:Click() end
        assert(UI.sellText:GetText():find('below your minimum',1,true),'scroll reaches the warning')
        ''')


if __name__ == '__main__':
    unittest.main()
