import unittest
from test_controller import controller_runtime
from test_ui import ui_runtime


class DealFlowTests(unittest.TestCase):
    def test_listing_match_ignores_unknown_item_level_only(self):
        controller_runtime().execute('''local A=ForeverFlip.Adapters
        assert(A.sameListing({itemID=1,itemLevel=0},{itemID=1,itemLevel=14}))
        assert(A.sameListing({itemID=1,itemLevel=14},{itemID=1,itemLevel=14}))
        assert(not A.sameListing({itemID=1,itemLevel=20},{itemID=1,itemLevel=14}))
        assert(not A.sameListing({itemID=1,itemSuffix=7},{itemID=1}))
        assert(not A.sameListing({itemID=2},{itemID=1}))''')

    def test_leveled_gear_keeps_vendor_value_but_suffix_does_not(self):
        controller_runtime().execute('''GetItemInfo=function()return 'Dagger',nil,1,14,1,nil,nil,1,nil,nil,500 end
        local base=c:options({itemID=2632},'vendor').vendor
        assert(c:options({itemID=2632,itemLevel=14},'vendor').vendor==base)
        assert(c:options({itemID=2632,itemSuffix=7},'vendor').vendor==nil)''')

    def test_empty_leveled_item_search_retries_with_base_key(self):
        controller_runtime().execute('''api.rows=function()return {},true,'item' end
        assert(c:search({itemID=2632,itemLevel=14}))
        c:event('ITEM_SEARCH_RESULTS_UPDATED',{itemID=2632,itemLevel=14})
        assert(c.plan==nil and c.reviewRequest and c.reviewRequest.key.itemLevel==0)
        api.rows=function()return rows,true,'item' end
        now=now+3;c:tick();assert(calls==2 and c.job and c.job.key.itemLevel==0)
        c:event('ITEM_SEARCH_RESULTS_UPDATED',{itemID=2632,itemLevel=0});assert(c.plan and #c.plan.rows==1)''')

    def test_unverified_profit_is_hidden_and_sorted_last(self):
        ui_runtime().execute('''local good={key={itemID=1},identity='1',canBuy=true,profit=100,qty=1,cost=10,target=200,mode='vendor',minimum=10,totalQty=1}
        local bad={key={itemID=2},identity='2',canBuy=false,profit=99999,minimum=5,totalQty=1,reasons={'history'}}
        ForeverFlip.DealCache.get=function()return {bad,good}end
        u:show('deals');assert(u.visibleDeals[1]==good)
        assert(u.dealRows[2].profit:GetText()=='—' and u.dealRows[1].profit:GetText()~='—')
        assert(u.dealRows[1].note:find('1'))''')

    def test_simple_trade_card_guides_each_state_without_spending(self):
        ui_runtime().execute('''u:show('trade')
        assert(u.tradeCard:IsShown() and not u.tradeContent:IsShown())
        assert(not u.actions.cardRecheck:IsEnabled())
        c.selection={key={itemID=1},mode='vendor'};u:refresh()
        assert(u.actions.cardRecheck:IsEnabled() and u.cardVerdict:GetText()~='')
        u.actions.cardRecheck:Click();assert(calls==1 and spent==0)
        c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1);u:refresh()
        assert(c.plan and c.plan.canBuy and u.actions.cardBuy:IsEnabled())
        assert(u.cardRows[1]:IsShown() and u.cardRows[1].label:GetText():find('1%.') and u.cardRows[4].value:GetText():find('+',1,true))
        assert(not u.actions.cardConfirm:IsEnabled() and spent==0)
        u.actions.cardBuy:Click();c:event('COMMODITY_PRICE_UPDATED',100,1000);u:refresh()
        assert(u.actions.cardConfirm:IsEnabled() and spent==0)
        assert(u.tradeCard:GetParent()==u.sections.trade.split.pages.deal)
        assert(u.fields.tradeQty:GetParent()==u.sections.trade.split.pages.calc)''')

    def test_simple_portfolio_lists_items_and_settles_pending_with_row_buttons(self):
        ui_runtime().execute('''db.ledger[1]={uid='b1',kind='buy',owner='owner',scope='scope',key='1:0:0:0',qty=2,total=100,at=now}
        db.pending.x={uid='x',owner='owner',scope='scope',key='2:0:0:0',id=2,qty=1,total=50,status='unknown',kind='item',at=now}
        u:show('portfolio');u:layout()
        local pages=u.sections.portfolio.split.pages
        assert(u.portfolioSimple:IsShown() and pages.items:IsShown() and not pages.manual:IsShown())
        assert(u.fields.entryKey:GetParent()==pages.manual and u.portfolioPendingRoot:GetParent()==pages.pending)
        local row=u.portfolioRows[1];assert(row:IsShown() and row.qty:GetText()=='2' and row.advice:GetText()~='')
        assert(u.portfolioPending[1]:IsShown() and u.portfolioPending[1].op.uid=='x')
        u.portfolioPending[1].yes:Click();assert(#db.ledger==2 and c:reserved()==0)
        assert(not u.portfolioPendingPanel:IsShown())
        assert(u.portfolioNoPending:IsShown())
        row.sell:Click();assert(u.section=='trade' and u.pages.trade=='sell' and spent==0 and quoted==0)
        assert(c.message=='post_no_item')
        api.bagItems=function()return {{id=1,key={itemID=1},qty=2,bag=0,slot=1}}end
        u:show('portfolio','items');u.portfolioRows[1].sell:Click();assert(u.sellItem and u.sellItem.qty==2 and calls>=1)''')

    def test_item_purchase_is_recorded_from_the_auction_id_event(self):
        controller_runtime().execute('''api.rows=function()return {{qty=2,unit=5,cost=10,auctionID=77}},true,'item' end
        c:search({itemID=414});c:event('ITEM_SEARCH_RESULTS_UPDATED',{itemID=414})
        assert(c.plan and c.plan.canBuy and c:requestBuy())
        if c.active.status=='quote' or c.active.status=='quoted' then assert(c:confirmBuy()) end
        assert(c.active and c.active.status=='awaiting' and spent==1)
        c:event('AUCTION_HOUSE_PURCHASE_COMPLETED',999);assert(c.active and #db.ledger==0)
        c:event('AUCTION_HOUSE_PURCHASE_COMPLETED',77)
        assert(not c.active and #db.ledger==1 and db.ledger[1].total==10 and db.ledger[1].qty==2)
        assert(c.lastPurchase and c.lastPurchase.qty==2 and c:reserved()==0)
        c:event('AUCTION_HOUSE_PURCHASE_COMPLETED',77);assert(#db.ledger==1)''')

    def test_item_event_marked_unknown_is_settled_by_auction_id(self):
        controller_runtime().execute('''api.rows=function()return {{qty=2,unit=5,cost=10,auctionID=77}},true,'item' end
        c:search({itemID=414});c:event('ITEM_SEARCH_RESULTS_UPDATED',{itemID=414});c:requestBuy()
        if c.active.status~='awaiting' then c:confirmBuy() end
        c:event('ITEM_PURCHASED',414);assert(c.active.status=='unknown' and #db.ledger==0)
        c:event('AUCTION_HOUSE_PURCHASE_COMPLETED',77);assert(#db.ledger==1 and c:reserved()==0)''')

    def test_sell_bought_item_from_bags_end_to_end(self):
        ui_runtime().execute('''db.ledger={{uid='b',kind='buy',owner='owner',scope='scope',key='1:0:0:0',qty=5,total=500,at=now}}
        GetItemInfo=function(id)return 'Item',nil,1,1,1,nil,nil,20,nil,nil,1 end
        api.bagItems=function()return {{id=1,key={itemID=1},qty=5,bag=0,slot=1},{id=9,key={itemID=9},qty=1,bag=0,slot=2}}end
        api.deposit=function()return 10 end;api.vendor=function()return 1 end;posted=nil
        api.post=function(item,kind,qty,price,dur,confirm)posted={qty=qty,price=price,dur=dur};return false end
        u:show('trade','sell');u:refresh()
        assert(u.sellRows[1]:IsShown() and u.sellRows[1].entry.qty==5 and not u.sellRows[2]:IsShown())
        assert(not u.actions.cardPost:IsEnabled())
        u.sellRows[1].click:Click();assert(calls==1 and u.sellItem and u.fields.cardQty:GetText()=='5')
        c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1);u:refresh()
        assert(u.fields.cardPrice:GetText()=='0.0200' and u.actions.cardPost:IsEnabled())
        u.actions.cardDuration:Click();assert(u.sellDuration==3)
        u.actions.cardPost:Click();assert(posted and posted.qty==5 and posted.price==200 and posted.dur==3 and spent==0)''')

    def test_post_explains_missing_item_and_missing_price_check(self):
        controller_runtime().execute('''assert(not c:post(nil,1,100,2) and c.message=='post_no_item')
        assert(not c:post({key={itemID=1},qty=1},1,100,2) and c.message=='post_search')''')


if __name__ == '__main__':
    unittest.main()
