import unittest

from test_addon import runtime


SETUP = '''
local F, D, UI = ForeverFlip, ForeverFlip.Deals, ForeverFlip.UI
F.Engine.autoVerify=false;F.db.settings.autoScan=false;F.db.settings.sniper=false
local function deal(id, mode)
    addItem(id,'Item '..id,100,'commodity')
    return {key='c:'..id,id=id,kind='commodity',link=link(id),mode=mode or 'vendor',
        qty=1,cost=20,profit=80,maxUnit=20,exit=100,verified=now}
end
local function requireBulk()
    assert(type(UI.bulkButton)=='table','missing current-category status button')
end
'''


class CategoryStatusTests(unittest.TestCase):
    def test_filtered_batch_checks_every_page_and_keeps_its_original_snapshot(self):
        runtime().execute(SETUP + '''
        requireBulk();D.list={}
        for id=10,27 do D.list[#D.list+1]=deal(id) end
        D.list[#D.list+1]=deal(100,'flip')
        UI.show('deals:vendor');throttleReady=false
        assert(UI.bulkButton:IsEnabled());UI.bulkButton:Click()
        local done,total,active=D.batchProgress()
        assert(done==0 and total==18 and active,'must include all category pages')
        for id=10,27 do assert(D.pending('c:'..id),'missing category item '..id) end
        assert(not D.pending('c:100'),'must not check another category')
        D.list[#D.list+1]=deal(28);UI.show('deals:flip')
        assert(not D.pending('c:28'),'new items must not expand the snapshot')
        assert(UI.bulkButton:GetText()=='Stop' and UI.bulkButton:IsEnabled(),'a running batch offers Stop, not a restart')
        assert(UI.status:GetText():find('Vendor deals') and UI.status:GetText():find('0/18'),UI.status:GetText())
        UI.bulkButton:Click()
        assert(not select(3,D.batchProgress()) and not D.pending('c:10'),'Stop ends the batch and its queue')
        assert(UI.bulkButton:GetText()=='Check all')
        ''')

    def test_all_deals_batch_includes_vendor_and_resale(self):
        runtime().execute(SETUP + '''
        requireBulk();D.list={deal(10),deal(20,'flip')};UI.show('deals:all');throttleReady=false
        UI.bulkButton:Click()
        local _,total,active=D.batchProgress()
        assert(total==2 and active and D.pending('c:10') and D.pending('c:20'))
        assert(D.batch.scope=='deals:all')
        ''')

    def test_sell_batch_checks_all_unique_bag_items_beyond_the_displayed_rows(self):
        runtime().execute(SETUP + '''
        requireBulk()
        for id=10,23 do addItem(id,'Item '..id,100,'commodity');putBag(0,id-9,id,1) end
        putBag(1,1,10,5)
        UI.show('sell');throttleReady=false;UI.bulkButton:Click()
        local _,total,active=D.batchProgress()
        assert(total==14 and active and D.batch.scope=='sell','must deduplicate all bag items')
        for id=10,23 do assert(D.pending('c:'..id)) end
        ''')

    def test_auction_batch_checks_unsold_unique_items_beyond_the_displayed_rows(self):
        runtime().execute(SETUP + '''
        requireBulk();F.Trade.owned={}
        for id=10,26 do
            addItem(id,'Item '..id,100,'commodity')
            F.Trade.owned[#F.Trade.owned+1]={key='c:'..id,id=id,link=link(id),auctionID=id,qty=1,price=100}
        end
        F.Trade.owned[#F.Trade.owned+1]={key='c:10',id=10,auctionID=100,qty=1,price=100}
        addItem(99,'Sold',100,'commodity')
        F.Trade.owned[#F.Trade.owned+1]={key='c:99',id=99,auctionID=99,qty=1,price=100,sold=true}
        UI.show('auctions');throttleReady=false;UI.bulkButton:Click()
        local _,total,active=D.batchProgress()
        assert(total==17 and active and D.batch.scope=='auctions')
        assert(not D.pending('c:99'),'sold lots do not need checking')
        for id=10,26 do assert(D.pending('c:'..id)) end
        UI.refreshAuctions();assert(not UI.checkOwned:IsEnabled(),'footer must share the active batch')
        ''')

    def test_bulk_button_disables_empty_unsupported_and_unavailable_actions(self):
        runtime().execute(SETUP + '''
        requireBulk();D.list={};UI.show('deals:all');assert(not UI.bulkButton:IsEnabled())
        D.list={deal(10)};UI.refresh();assert(UI.bulkButton:IsEnabled())
        for _,section in ipairs({'stats','journal','settings'}) do
            UI.show(section);assert(not UI.bulkButton:IsEnabled(),section)
        end
        UI.show('deals:vendor');F.Trade.op={state='quote'};UI.refresh();assert(not UI.bulkButton:IsEnabled())
        F.Trade.op=nil;assert(F.Scan.start());UI.refresh();assert(UI.bulkButton:GetText()=='Stop','a scan can be stopped')
        UI.bulkButton:Click();assert(not F.Scan.job,'Stop ends the scan')
        AuctionHouseFrame:Hide();fire('AUCTION_HOUSE_CLOSED');UI.refreshStatus();assert(not UI.bulkButton:IsEnabled())
        ''')

    def test_completed_batch_reports_failed_checks_and_localizes_the_controls(self):
        runtime().execute(SETUP + '''
        requireBulk();addItem(10,'Cloth',100,'commodity');putBag(0,1,10,1)
        UI.show('sell');UI.bulkButton:Click();run(0.1)
        assert(D.search,'batch must start an auction search')
        local oldRows=F.AH.rows;F.AH.rows=function() error('unavailable auction results') end
        answer();run(1.1);answer();F.AH.rows=oldRows;UI.refresh()
        local done,total,active,failed=D.batchProgress()
        assert(done==1 and total==1 and not active and failed==1)
        assert(UI.status:GetText():find('1/1') and UI.status:GetText():find('1 without an answer'),UI.status:GetText())
        assert(UI.bulkButton:IsEnabled(),'completed batches may be started again')
        F.Locale.apply('uk');UI.refresh()
        assert(UI.bulkButton:GetText()=='Перевірити все')
        ''')
        runtime(open_ah=False).execute('''
        ForeverFlip.Locale.apply('uk');fire('AUCTION_HOUSE_SHOW')
        assert(ForeverFlip.UI.dealTable.headers[6]:GetText()=='Оцін./д')
        ''')


SALEABILITY = SETUP + '''
local history=F.Data.market(F.db,F.Engine.scope()).history
local function resale(id,rate,age)
    local d=deal(id,'flip');d.exit=1000;d.perDay=999
    if rate~=nil then
        history[d.key]={flow={hours=20,sold={40,20,rate,1},pairs=2,at=now-(age or 0),market=1000}}
    end
    return d
end
D.list={resale(10,8),resale(20,0),resale(30,nil),deal(40),resale(50,2,14400),resale(60,10),resale(70,0)}
history['c:40']={flow={hours=24,sold={100,100,100,100},pairs=2,at=now,market=1000}}
UI.refreshDeals()
local function row(key)
    for _,r in ipairs(UI.dealTable.rows) do if r.key==key then return r end end
    error('missing row '..key)
end
local function keys()
    local out={}
    for _,r in ipairs(UI.dealTable.rows) do if r:IsShown() then out[#out+1]=r.key end end
    return table.concat(out,',')
end
'''


class SaleabilityTableTests(unittest.TestCase):
    def test_estimates_use_resale_exit_history_and_distinguish_zero_unknown_and_vendor(self):
        runtime().execute(SALEABILITY + '''
        assert(UI.dealTable.headers[6]:GetText()=='Est./day')
        local function cell(key) return row(key).cols[5]:GetText() end
        assert(cell('c:10')=='8.0','must use history at resale exit, not purchase or cached rate')
        assert(cell('c:20')=='0','observed zero is known')
        assert(cell('c:30')=='-','unknown is not zero')
        assert(cell('c:40')=='vendor','vendor sale does not need AH demand')
        assert(cell('c:50'):find('|cff999999') and cell('c:50'):find('2.0',1,true))
        ''')

    def test_buy_at_and_sells_at_are_prices_of_one_unit_and_profit_is_the_whole_deal(self):
        runtime().execute(SALEABILITY + '''
        local U=F.Util
        assert(row('c:10').cols[2]:GetText()==U.money(20),'buy at: one unit')
        assert(row('c:10').cols[3]:GetText():find(U.money(1000),1,true),'sells at: the listing price of one unit')
        assert(row('c:10').cols[4]:GetText()==U.money(80),'profit: the whole deal')
        local d=D.get('c:10');d.qty,d.cost=4,80;UI.refresh()
        assert(row('c:10').cols[2]:GetText()==U.money(20),'the average price of one unit, not the total')
        ''')

    def test_estimate_sort_is_numeric_with_unknown_and_vendor_last_in_both_directions(self):
        runtime().execute(SALEABILITY + '''
        UI.dealTable.headers[6]:Click()
        assert(keys()=='c:60,c:10,c:50,c:20,c:70,c:30,c:40',keys())
        UI.dealTable.headers[6]:Click()
        assert(keys()=='c:20,c:70,c:50,c:10,c:60,c:30,c:40',keys())
        assert(D.list[1].key=='c:10','sorting must not reorder backend work')
        ''')

    def test_selected_detail_explains_estimation_limits_and_old_data_age(self):
        runtime().execute(SALEABILITY + '''
        UI.selected='c:50';UI.refreshDeals()
        local detail=UI.dealText:GetText()
        assert(detail:find('Bought per day'),detail)
        assert(detail:find('240 min') and detail:find('old data'),detail)
        assert(not detail:find('999'),'cached deal rate must not claim current sales')
        UI.selected='c:30';UI.refreshDeals();assert(UI.dealText:GetText():find('unavailable'))
        ''')

    def test_estimate_header_explains_disappeared_listings_and_unknown_values(self):
        runtime().execute(SALEABILITY + '''
        local header=UI.dealTable.headers[6]
        assert(type(header.scripts.OnEnter)=='function','estimate needs a caveat tooltip')
        header.scripts.OnEnter(header)
        local tip=GameTooltip:GetText()
        assert(tip:find('Expired/cancelled') and tip:find('probability'),tip)
        assert(tip:find('unknown') and tip:find('Zero') and tip:find('3 hours'),tip)
        header.scripts.OnLeave(header);assert(not GameTooltip:IsShown())
        ''')


if __name__ == '__main__':
    unittest.main()
