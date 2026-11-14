"""Market-based routing stays consistent with the merchant list and bounded selling text."""

import unittest

from test_addon import run


WOOL = '''local F=ForeverFlip;local T,UI=F.Trade,F.UI
F.db.settings.autoScan=false;F.db.settings.sniper=false;F.db.settings.autoVerify=false
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


class VendorOfferTests(unittest.TestCase):
    """A vendor offer is sure money: it is listed whatever the purse holds, and bought in part."""

    OFFER = '''local F=ForeverFlip
addItem(11,'Cheap Cloth',90000,'commodity')
for i=1,3 do addAuction(11,9000,5) end
fullScan()
local d=F.Deals.get('c:11')
'''

    def test_an_offer_too_dear_for_the_purse_is_still_listed(self):
        run(self.OFFER + '''money=1000
        F.UI.show('deals:vendor')
        F.Deals.fitWallet(d)
        assert(d.short and d.qty==0 and d.offer.qty==15 and d.offer.cost==135000, 'the whole offer stays')
        F.UI.refresh()
        local r=F.UI.vendorTable.rows[1]
        assert(r and r:IsShown() and r.cols[1]:GetText()=='15', 'the whole offer is in the row')
        assert(r.cols[6]:GetText():find('afford it yet',1,true), r.cols[6]:GetText())
        assert(not F.UI.buyButton:IsEnabled(), 'nothing to buy yet')''')

    def test_the_click_buys_the_part_the_money_covers(self):
        run(self.OFFER + '''money=50000
        F.Deals.fitWallet(d)
        assert(d.offer.qty==15 and d.qty==5 and d.cost==45000 and not d.short)''')

    def test_the_deal_grows_back_when_the_money_does(self):
        run(self.OFFER + '''money=1000; F.Deals.fitWallet(d)
        assert(d.short)
        money=1000000; F.Deals.fitWallet(d)
        assert(not d.short and d.qty==15 and d.cost==135000, 'the whole offer again')''')

    def test_a_short_offer_is_not_bought_by_the_run_or_buy_next(self):
        run(self.OFFER + '''money=1000; F.Deals.fitWallet(d)
        assert(#F.Trade.runTargets()==0, 'Buy all to vendor skips it')
        assert(F.Deals.best()==nil, 'Buy next skips it')''')


if __name__ == '__main__':
    unittest.main()
