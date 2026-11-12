import unittest

from test_addon import runtime


DEALS = '''
local F = ForeverFlip
local D, UI = F.Deals, F.UI
F.Engine.autoVerify=false;F.db.settings.autoScan=false
addItem(10,'Zulu',500,'commodity');addItem(20,'Alpha',500,'commodity');addItem(30,'beta',500,'commodity')
local z={key='c:10',id=10,kind='commodity',link=link(10),mode='vendor',qty=1,cost=300,profit=100,maxUnit=300,exit=400,verified=now}
local a={key='c:20',id=20,kind='commodity',link=link(20):gsub('1eff00','ffff00'),mode='flip',qty=2,cost=200,profit=200,maxUnit=100,exit=250}
local b={key='c:30',id=30,kind='commodity',link=link(30):gsub('1eff00','000000'),mode='vendor',qty=2,cost=100,profit=50,maxUnit=50,exit=75,verified=now-100}
D.list={z,a,b};UI.refreshDeals()
local function click(label)
    for _,w in ipairs(widgets) do
        if w.template=='AuctionHouseTableHeaderStringTemplate' and w:GetText()==label then w:Click();return end
    end
    error('missing deal header '..label)
end
local function keys()
    local out={}
    for _,r in ipairs(UI.dealTable.rows) do if r:IsShown() then out[#out+1]=r.key end end
    return table.concat(out,',')
end
'''


class TableTests(unittest.TestCase):
    def test_default_profit_sort_is_a_view_and_does_not_reorder_verification_queue(self):
        runtime().execute(DEALS + '''
        assert(keys()=='c:20,c:10,c:30',keys())
        assert(D.list[1]==z and D.list[2]==a and D.list[3]==b)
        ''')

    def test_header_clicks_sort_plain_names_and_all_numeric_columns_in_both_directions(self):
        runtime().execute(DEALS + '''
        click('Name');assert(keys()=='c:20,c:30,c:10',keys())
        click('Name');assert(keys()=='c:10,c:30,c:20',keys())
        click('Buy at');assert(keys()=='c:30,c:20,c:10',keys())
        click('Buy at');assert(keys()=='c:10,c:20,c:30',keys())
        click('Qty');assert(keys()=='c:10,c:20,c:30',keys())
        click('Qty');assert(keys()=='c:20,c:30,c:10',keys())
        click('Sells at');assert(keys()=='c:30,c:20,c:10',keys()) -- per unit: 75, 250, 400
        click('Sells at');assert(keys()=='c:10,c:20,c:30',keys())
        click('Profit');assert(keys()=='c:20,c:10,c:30',keys())
        click('Profit');assert(keys()=='c:30,c:10,c:20',keys())
        click('Status');assert(keys()=='c:10,c:30,c:20',keys())
        click('Status');assert(keys()=='c:20,c:10,c:30',keys()) -- c:10 and c:30 are both fresh now: a tie, by key
        ''')

    def test_sort_survives_refresh_filter_switches_and_live_data_changes(self):
        runtime().execute(DEALS + '''
        click('Buy at');UI.refresh();assert(keys()=='c:30,c:20,c:10')
        UI.show('deals:vendor');assert(keys()=='c:30,c:10')
        UI.show('deals:flip');assert(keys()=='c:20')
        UI.show('deals:all');assert(keys()=='c:30,c:20,c:10')
        a.cost=5;UI.refresh();assert(keys()=='c:20,c:30,c:10')
        ''')

    def test_sort_happens_before_scrolling_and_ties_stay_deterministic(self):
        runtime().execute(DEALS + '''
        D.list={}
        for id=39,10,-1 do
            addItem(id,'Item '..id,100,'commodity')
            D.list[#D.list+1]={key='c:'..id,id=id,kind='commodity',mode='vendor',qty=1,cost=id,profit=10,maxUnit=id,exit=id+10}
        end
        UI.refreshDeals();local seen={}
        for page=1,3 do
            for _,r in ipairs(UI.dealTable.rows) do
                if r:IsShown() then seen[r.key]=true end -- the last screen may overlap the one before
            end
            if page<3 then assert(UI.dealTable.bar.thumb:IsShown());UI.dealTable.offset=UI.dealTable.offset+13;UI.refresh() end
        end
        local count=0;for _ in pairs(seen) do count=count+1 end;assert(count==30)
        click('Buy at');assert(UI.dealTable.offset==0 and UI.dealTable.rows[1].key=='c:10','a new sort starts at the top')
        click('Buy at');assert(UI.dealTable.rows[1].key=='c:39')
        click('Profit');assert(UI.dealTable.rows[1].key=='c:10')
        click('Profit');assert(UI.dealTable.rows[1].key=='c:10')
        ''')

    def test_inactive_headers_have_no_native_handler_or_visible_sort_arrow(self):
        runtime().execute(DEALS + '''
        local dealHeader
        for _,w in ipairs(widgets) do
            if w.template=='AuctionHouseTableHeaderStringTemplate' and w:GetText()=='Buy at' then dealHeader=w.parent end
        end
        for _,w in ipairs(widgets) do
            if w.template=='AuctionHouseTableHeaderStringTemplate' and w.parent~=dealHeader then
                w:Click();assert(not w.Arrow:IsShown())
            end
        end
        local active=0
        for _,w in ipairs(widgets) do
            if w.template=='AuctionHouseTableHeaderStringTemplate' and w.parent==dealHeader and w.Arrow:IsShown() then active=active+1 end
        end
        assert(active==1)
        ''')


class SniperControlTests(unittest.TestCase):
    def test_top_toggle_and_settings_checkbox_stay_synchronized_during_scan(self):
        runtime().execute('''
        local F,UI=ForeverFlip,ForeverFlip.UI
        assert(type(UI.sniperButton)=='table','missing top sniper toggle')
        assert(not F.db.settings.sniper,'a new player has no sniper running')
        F.Deals.setSniper(true);UI.refresh()
        assert(UI.sniperButton:GetText()=='Sniper: ON' and UI.sniperBox:GetChecked())
        UI.sniperButton:Click()
        assert(not F.db.settings.sniper and not UI.sniperBox:GetChecked())
        assert(UI.sniperButton:GetText()=='Sniper: OFF')
        assert(F.Scan.start())
        UI.sniperBox:SetChecked(true);UI.sniperBox:Click();UI.refresh()
        assert(F.db.settings.sniper and UI.sniperButton:GetText()=='Sniper: ON')
        UI.sniperButton:Click();assert(not F.db.settings.sniper and not UI.sniperBox:GetChecked())
        F.Locale.apply('uk');UI.refresh()
        assert(UI.sniperButton:GetText()=='Снайпер: ВИМК')
        ''')

    def test_manual_check_can_queue_behind_background_and_rejects_duplicates(self):
        runtime().execute(DEALS + '''
        D.search={key='c:999',source='sniper',at=now}
        UI.selected='c:10';UI.refreshDeals()
        assert(UI.checkButton:IsEnabled(),'background must allow a manual request')
        UI.checkButton:Click();assert(D.pending('c:10'))
        assert(not UI.checkButton:IsEnabled(),'queued request must disable duplicates')
        local found=false
        for _,r in ipairs(UI.dealTable.rows) do
            if r.key=='c:10' then found=true;local t=r.cols[7]:GetText();assert(t:find('queued') or t:find('checking'),t) end
        end
        assert(found)
        ''')

    def test_check_button_waits_for_scan_and_trade_but_not_other_background_work(self):
        runtime().execute(DEALS + '''
        UI.selected='c:10';F.Trade.op={state='quote'};UI.refreshDeals();assert(not UI.checkButton:IsEnabled())
        F.Trade.op=nil;assert(F.Scan.start());UI.refreshDeals();assert(not UI.checkButton:IsEnabled())
        ''')

    def test_sell_price_check_queues_behind_another_background_search(self):
        runtime().execute('''
        local F,UI=ForeverFlip,ForeverFlip.UI
        F.Engine.autoVerify=false;F.db.settings.autoScan=false
        addItem(10,'Linen Cloth',100,'commodity');putBag(0,1,10,5)
        UI.show('sell');UI.sellSelected=F.AH.bagItems()[1]
        F.Deals.search={key='c:999',source='sniper',at=now}
        UI.refreshSell();assert(UI.sellCheck:IsEnabled())
        UI.sellCheck:Click();assert(F.Deals.pending('c:10'))
        assert(not UI.sellCheck:IsEnabled())
        local t=UI.sellText:GetText();assert(t:find('queued') or t:find('checking') or t:find('Reading'),t)
        ''')


if __name__ == '__main__':
    unittest.main()


class NativeScrollBarTests(unittest.TestCase):
    def test_scrollbar_works_like_the_auction_house_one(self):
        runtime().execute(DEALS + '''
        local bar = UI.dealTable.bar
        D.list = {}
        UI.refreshDeals()
        assert(not bar.thumb:IsShown() and not bar.back:IsEnabled() and not bar.forward:IsEnabled(), 'nothing to scroll')
        for id = 39, 10, -1 do
            addItem(id, 'Item ' .. id, 100, 'commodity')
            D.list[#D.list + 1] = { key = 'c:' .. id, id = id, kind = 'commodity', mode = 'vendor', qty = 1, cost = id, profit = 10, maxUnit = id, exit = id + 10 }
        end
        UI.refreshDeals()
        assert(bar.thumb:IsShown() and not bar.back:IsEnabled() and bar.forward:IsEnabled())
        bar.forward:Click(); assert(UI.dealTable.offset == 1, 'the down arrow scrolls one row')
        bar.back:Click(); assert(UI.dealTable.offset == 0)
        for _ = 1, 40 do bar.forward:Click() end
        assert(UI.dealTable.offset == 17 and not bar.forward:IsEnabled(), 'stops at the last row')
        ''')
