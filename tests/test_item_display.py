import unittest
from test_ui import ui_runtime


class ItemDisplayTests(unittest.TestCase):
    def test_auction_rows_have_icons_and_columns_and_real_item_tooltips(self):
        ui_runtime().execute('''local D=ForeverFlip.ItemDisplay;assert(D)
        local link='|cffa335ee|Hitem:123:0:0:0:0:0:7:0|h[Exact item]|h|r'
        local r=D.row(u.frame,0,0,810,function()spent=spent+1 end)
        r:SetItem({key={itemID=123,itemSuffix=7},link=link,qty=3,cost=300,profit=50,mode='flip'})
        assert(r.icon and r.itemName and r.quantity and r.price and r.profit and r.metadata.link==link)
        local seen;GameTooltip.SetHyperlink=function(_,v)seen=v end
        r.scripts.OnEnter(r);assert(seen==link and spent==0)
        r.scripts.OnLeave(r);assert(not GameTooltip:IsShown())''')
    def test_unknown_variant_never_uses_base_item_tooltip(self):
        ui_runtime().execute('''local D=ForeverFlip.ItemDisplay;local seen=false
        GameTooltip.SetHyperlink=function()seen=true end;GameTooltip.SetItemByID=function()seen=true end
        local r=D.row(u.frame,0,0,810,function()end)
        r:SetItem({key={itemID=123,itemSuffix=9},qty=1,cost=100,profit=1})
        r.scripts.OnEnter(r);assert(not seen and not r.metadata.link and not r.metadata.exact)''')
    def test_unknown_family_row_does_not_present_base_tooltip_as_exact(self):
        ui_runtime().execute('''local D=ForeverFlip.ItemDisplay;local seen=false
        GameTooltip.SetHyperlink=function()seen=true end;GameTooltip.SetItemByID=function()seen=true end
        local r=D.row(u.frame,0,0,810,function()end)
        r:SetItem({key={itemID=123},family=true,qty=1,cost=100,profit=1})
        r.scripts.OnEnter(r);assert(not seen and not r.metadata.exact)''')
    def test_cold_item_cache_requests_data_once_and_renders_available_icon(self):
        ui_runtime().execute('''local D=ForeverFlip.ItemDisplay;local loads=0
        GetItemInfo=function()return nil end
        C_Item={GetItemInfo=function()return nil end,GetItemIconByID=function()return 456 end,
          RequestLoadItemDataByID=function()loads=loads+1 end}
        local a=D.metadata({itemID=123});local b=D.metadata({itemID=123})
        assert(a.icon==456 and loads==1 and a.name and b.name)''')
    def test_deal_and_assistant_rows_use_item_renderer_without_hover_purchases(self):
        ui_runtime().execute('''c.candidates={{key={itemID=1},rows={{qty=10,unit=100,cost=1000}},at=now,scope='scope',family=false,kind='commodity'}}
        u:show('deals');assert(u.dealRows[1].metadata and u.dealRows[1].icon)
        u.dealRows[1].scripts.OnEnter(u.dealRows[1]);assert(spent==0 and quoted==0)
        u.actions.easyBuild:Click();assert(u.actions.adviceRow1.metadata and u.actions.adviceRow1.icon)''')
    def test_trade_card_shows_same_exact_native_link_as_search_result(self):
        ui_runtime().execute('''local link='|cffa335ee|Hitem:123:0:0:0:0:0:7:0|h[Exact item]|h|r'
        api.rows=function()return {{qty=1,unit=100,cost=100,auctionID=1,link=link}},true,'item' end
        api.vendor=function()return 1000 end
        c:search({itemID=123,itemSuffix=7});c:event('ITEM_SEARCH_RESULTS_UPDATED',{itemID=123,itemSuffix=7})
        u:show('trade');assert(u.tradeItem and u.tradeItem.metadata.link==link)''')
    def test_item_cache_event_burst_causes_one_deferred_refresh(self):
        from test_domain import ROOT
        l=ui_runtime()
        l.execute((ROOT/'ForeverFlip/Core.lua').read_text(encoding='utf-8-sig'))
        l.execute('''ForeverFlip.boot('ForeverFlip');ForeverFlip.attach();ForeverFlip.ui.frame:Show()
        local count=0;ForeverFlip.ui.refresh=function()count=count+1 end
        ForeverFlip.ItemDisplay.metadata({itemID=1})
        local f=ForeverFlip.eventFrame
        for i=1,100 do f.scripts.OnEvent(f,'GET_ITEM_INFO_RECEIVED',i,true)end
        assert(count==0);f.scripts.OnUpdate(f,1);assert(count==1)''')

if __name__=='__main__':unittest.main()
