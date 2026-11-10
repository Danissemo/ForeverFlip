import unittest
from test_ui import ui_runtime as base_runtime

def ui_runtime():
    lua = base_runtime()
    lua.execute("GetLocale=function()return 'enUS'end")
    return lua

class AuditUITests(unittest.TestCase):
    def test_explicit_search_opens_deal(self):
        ui_runtime().execute("u:show('trade','sell');u.fields.item:SetText('2589');u.actions.search:Click();assert(u.pages.trade=='deal')")
    def test_calculation_has_visible_result_page(self):
        ui_runtime().execute("u:show('tools','craft');u.fields.materials:SetText('2589*3@0.01');u.fields.outputQty:SetText('2');u.fields.outputPrice:SetText('1');u.actions.craftCalc:Click();assert(u.pages.tools=='result');assert(u.toolScroll:GetParent()==u.sections.tools.split.pages.result)")
    def test_cyrillic_case_fold(self):
        ui_runtime().execute("assert(ForeverFlip.Locale.fold('РУДА ҐАНОК ЇЖА Є')=='руда ґанок їжа є')")
    def test_manual_error_priority(self):
        ui_runtime().execute("c.radar={enabled=true,paused=false,opportunities={},candidates={},index=1};c.message='post_floor';u:show('deals');u:refresh();assert(ForeverFlip.Progress.state(c).mode=='error');assert(u.status:GetText()=='Price below sale floor or NPC net value.')")
    def test_sell_paging_and_selection_outside_page(self):
        ui_runtime().execute('''local entries={};for i=1,13 do entries[i]={key={itemID=i},qty=1,slots={{key={itemID=i},qty=1,bag=0,slot=i}}} end
        u.sellCandidates=function() return entries end;c.postReady=function() return false end
        u.sellEntry=entries[13];u.sellItem=entries[13].slots[1];u:refreshSell();assert(u.sellEntry==entries[13]);assert(u.actions.sellNext)
        u.actions.sellNext:Click();assert(u.sellRows[1].entry==entries[7]);u.actions.sellNext:Click();assert(u.sellRows[1].entry==entries[13])''')
    def test_owned_paging(self):
        ui_runtime().execute('''c.owned={};for i=1,19 do c.owned[i]={key={itemID=i},qty=i,buyout=10000} end
        u:refreshOwnedPage();assert(u.actions.ownedNext);u.actions.ownedNext:Click();assert(u.ownedRows[1].qty:GetText()=='9')
        u.actions.ownedNext:Click();assert(u.ownedRows[1].qty:GetText()=='17')''')
    def test_undercut_is_legal_silver_step(self):
        ui_runtime().execute('''c.owned={{key={itemID=1},qty=1,buyout=20000}};c.ownedStatus=function()return 'undercut',10000 end
        u:refreshOwnedPage();assert(u.ownedRows[1].advice:GetText():find(ForeverFlip.Util.money(9900),1,true))''')
    def test_visible_card_tooltip(self):
        ui_runtime().execute("""assert(type(u.cardTooltip)=='table' and type(u.cardTooltip.scripts.OnEnter)=='function')
        c.selection={key={itemID=1,itemSuffix=2},link='item:1:0:0:0:0:0:2'};u:show('trade','deal');u:refresh()
        local link;GameTooltip.SetHyperlink=function(_,v)link=v end
        u.cardTooltip.scripts.OnEnter(u.cardTooltip);assert(link==c.selection.link and GameTooltip:IsShown())
        u.cardTooltip.scripts.OnLeave(u.cardTooltip);assert(not GameTooltip:IsShown())""")

    def test_visible_portfolio_accounts_for_reserve_and_extra_cost(self):
        ui_runtime().execute("""ForeverFlip.Util.vendor=function()return nil end
        c.price=function()return 1000 end;c.rule=function()return {fee=.05,reserve=.1,extraCost=0} end
        u:show('portfolio','items');local r={positions={{key='1:0:0:0',qty=1,cost=900,at=now}},stock=900}
        u:refreshSimplePortfolio(r);assert(u.portfolioRows[1].advice:GetText()=='Wait: it sells below your cost now')
        c.rule=function()return {fee=.05,reserve=0,extraCost=0} end
        u:refreshSimplePortfolio(r);assert(u.portfolioRows[1].advice:GetText():find('List at',1,true))
        c.rule=function()return {fee=.05,reserve=0,extraCost=100} end
        u:refreshSimplePortfolio(r);assert(u.portfolioRows[1].advice:GetText()=='Wait: it sells below your cost now')""")
    def test_long_pages_have_scrolling_content(self):
        ui_runtime().execute("""local chart=u.sections.history.split.pages.chart
        local groups=u.sections.watch.split.pages.groups
        assert(chart.ffScroll and groups.ffScroll)
        assert(u.chart:GetParent()==chart.ffContent)
        assert(u.groupSummary:GetParent()==groups.ffContent)
        u:show('history','chart');u:layout();assert(chart.ffContent:GetHeight()>chart:GetHeight())""")
    def test_owned_advice_is_snapshot_and_not_sale_guarantee(self):
        ui_runtime().execute("""c.owned={{key={itemID=1},qty=1,buyout=20000}};c.ownedAt=now
        c.ownedStatus=function()return 'cheapest' end;u:refreshOwnedPage()
        assert(u.ownedRows[1].advice:GetText():find('snapshot',1,true))
        assert(u.ownedInfo:GetText():find('snapshot',1,true))""")

    def test_statistics_separates_closed_profit_expenses_and_net(self):
        ui_runtime().execute("""local period={label='Today',sales=1,revenue=2000,profit=500,closedProfit=500,expenses=100,netProfit=400}
        ForeverFlip.Stats.compute=function()return {periods={period,period,period},top={},tips={}} end
        u:refreshStats();assert(u.statRows[1].summary)
        assert(u.statRows[1].summary:GetText():find(ForeverFlip.Util.money(100),1,true))
        assert(u.statRows[1].summary:GetText():find(ForeverFlip.Util.money(400),1,true))""")

    def test_card_displays_exact_price_snapshot_age(self):
        ui_runtime().execute("""c:search({itemID=1});c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1);now=now+12
        u:show('trade','deal');u:refresh();assert(type(u.cardFreshness)=='table')
        assert(u.cardFreshness:GetText():find('12 s ago',1,true))""")
    def test_cyrillic_filter_matches_item_and_group(self):
        ui_runtime().execute("""ForeverFlip.DealCache.get=function()return {{key={itemID=1},group='ҐРУПА',canBuy=false,qty=1,cost=100,profit=0,reasons={}}} end
        ForeverFlip.ItemDisplay.name=function()return 'Мідна руда' end
        u.fields.dealFilter:SetText('мідна');u:show('deals');assert(#u.visibleDeals==1)
        u.fields.dealFilter:SetText('ґрупа');u:refresh();assert(#u.visibleDeals==1)
        u.fields.dealFilter:SetText('інший');u:refresh();assert(#u.visibleDeals==0)""")

    def test_sell_refresh_resolves_moved_stack_and_clamps_quantity(self):
        ui_runtime().execute("""local bags={{id=1,key={itemID=1},bag=0,slot=1,qty=5}}
        db.ledger={{uid='buy',kind='buy',owner='owner',scope='scope',key='1:0:0:0',qty=5,total=500,at=now}}
        api.bagItems=function()return bags end;api.deposit=function()return 0 end
        local posted;api.post=function(item,kind,qty,price,duration,confirm)posted={slot=item.slot,qty=qty,confirm=confirm};return false end
        u:refreshSell();u:selectSellItem(u.sellRows[1].entry)
        c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1);u.fields.cardQty:SetText('5')
        c.postPending={location='1:0:0:0|0|1',price=2000,qty=5,duration=2}
        bags={{id=1,key={itemID=1},bag=0,slot=2,qty=2}}
        u:refreshSell();assert(u.sellItem.slot==2 and u.sellItem.qty==2)
        assert(u.fields.cardQty:GetText()=='2' and not c.postPending)
        u.fields.cardPrice:SetText('0.2000');u.actions.cardPost:Click()
        assert(posted and posted.slot==2 and posted.qty==2 and not posted.confirm)
        assert(c.message=='post_sent')""")
    def test_manual_completion_has_priority_over_paused_live(self):
        ui_runtime().execute("""db.lastReplicate=now;c:radarStart();c:search({itemID=1})
        c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        assert(c.radar.paused and c.message=='plan_ready')
        local p=ForeverFlip.Progress.state(c);assert(p.mode=='done' and p.label=='Search complete')
        c.message='calculation_done';assert(ForeverFlip.Progress.state(c).mode=='done')""")
