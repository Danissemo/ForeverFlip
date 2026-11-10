import pathlib
import unittest

import lupa.lua51 as lupa

HERE = pathlib.Path(__file__).resolve().parent
ADDON = HERE.parent / 'ForeverFlip'


def runtime(open_ah=True):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute((HERE / 'mock.lua').read_text(encoding='utf-8'))
    toc = (ADDON / 'ForeverFlip.toc').read_text(encoding='utf-8')
    for line in toc.splitlines():
        line = line.strip()
        if line.endswith('.lua'):
            lua.execute((ADDON / line).read_text(encoding='utf-8'))
    lua.execute("fire('ADDON_LOADED','ForeverFlip')")
    if open_ah:
        lua.execute("fire('AUCTION_HOUSE_SHOW');ForeverFlip.UI.frame:Show()")
    return lua


def run(code):
    return runtime().execute(code)


class MarketTests(unittest.TestCase):
    def test_money_helpers(self):
        run('''local U=ForeverFlip.Util
        assert(U.parseMoney('1g 20s 5c')==12005 and U.parseMoney('20s')==2000 and U.parseMoney('15')==1500)
        assert(U.parseMoney(U.plainMoney(12345))==12345)
        assert(U.below(900,'gear')==800 and U.below(950,'gear')==900 and U.below(950,'commodity')==949)
        assert(U.key('gear',2078,'Northern Shortsword of Healing')=='g:2078:northern shortsword of healing')
        local k=U.parseKey('g:2078:northern shortsword of healing');assert(k.kind=='gear' and k.id==2078 and k.name=='northern shortsword of healing')''')

    def test_vendor_deal_takes_every_unit_below_vendor_price(self):
        run('''local M=ForeverFlip.Market
        local d=M.evaluate({{unit=800,qty=2},{unit=900,qty=1},{unit=1200,qty=5}},{kind='gear',vendor=1070,budget=100000,now=now,settings={vendorMinProfit=10}})
        assert(d.mode=='vendor' and d.qty==3 and d.cost==2500 and d.profit==3*1070-2500)
        d=M.evaluate({{unit=800,qty=2}},{kind='gear',vendor=1070,budget=1000,now=now,settings={}})
        assert(d.qty==1 and d.cost==800)''')

    def test_resale_needs_sales_and_prices_below_the_lots_left(self):
        run('''local M=ForeverFlip.Market
        -- 8 flasks at 9-10s, one at 49s, a wall from 78s: the addon once called this +1g87s.
        local rows={{unit=900,qty=2},{unit=998,qty=5},{unit=999,qty=1},{unit=4900,qty=1},{unit=7800,qty=16},{unit=9000,qty=10}}
        local h={flow={hours=24,sold={3,3,3,3},pairs=4,at=now,market=7800}}
        local d,why=M.evaluate(rows,{kind='commodity',budget=1000000,history=h,market=7800,now=now,settings={minProfit=100,minROI=0.2}})
        assert(not d,'no resale: three bought, five cheap flasks left')
        local _,why2=M.evaluate(rows,{kind='commodity',budget=1000000,history={},market=7800,now=now,settings={}})
        assert(why2=='collecting')
        h.flow.sold={30,30,30,30}
        d=M.evaluate(rows,{kind='commodity',budget=1000000,history=h,market=7800,now=now,settings={minProfit=100,minROI=0.2}})
        assert(d and d.mode=='flip' and d.qty==9 and d.exit==7799 and d.profit>0)
        h.flow.sold={0,0,0,0}
        d,why=M.evaluate(rows,{kind='commodity',budget=1000000,history=h,market=7800,now=now,settings={}})
        assert(not d and why=='not_selling')''')

    def test_sales_flow_ignores_cheap_lots_bought_by_resellers(self):
        run('''local M=ForeverFlip.Market;local h={}
        local function book(cheap,wall)local b={};if cheap>0 then M.bucketAdd(b,900,cheap)end;M.bucketAdd(b,7800,wall);return b end
        M.recordFlow(h,book(8,16),7800,now);M.recordFlow(h,book(2,16),7800,now+900);M.recordFlow(h,book(8,16),7800,now+1800)
        local d=M.demandAt(h,7700,now+1800);assert(d.pairs==2 and d.perDay==0)
        M.recordFlow(h,book(8,10),7800,now+2700);d=M.demandAt(h,7700,now+2700)
        assert(d.pairs==3 and d.sold==6 and d.perDay>29 and d.perDay<31)''')

    def test_break_even_covers_the_cut(self):
        run('''local M=ForeverFlip.Market
        local p=M.breakEven(1000,1,'gear');assert(p==1100 and M.net(p,1)>=1000)
        p=M.breakEven(1000,1,'commodity');assert(M.net(p,1)>=1000 and M.net(p-1,1)<1000)''')


SETUP = '''
ForeverFlip.Engine.autoVerify=false;ForeverFlip.db.settings.autoScan=false
ForeverFlip.db.settings.sniper=false
addItem(10,'Linen Cloth',100,'commodity')
addItem(20,'Northern Shortsword',1070,'gear')
addItem(30,'Linen Bag',2000,'item')
for i=1,3 do addAuction(10,60,5) end      -- 15 cloth at 60c, vendor pays 100c
addAuction(10,150,20)
addAuction(20,800,1,'Seller','Northern Shortsword of Nature Protection')
addAuction(20,3000,1,'Seller','Northern Shortsword of Nature Protection')
addAuction(20,400,1,'Seller','Northern Shortsword of Healing')
addAuction(20,5000,1,'Seller','Northern Shortsword of Healing')
addAuction(20,700,1,'Me','Northern Shortsword of Healing')
addAuction(30,30000,1)
'''


class ScanTests(unittest.TestCase):
    def test_full_scan_finds_vendor_deals_per_gear_ending_and_skips_own_auctions(self):
        run(SETUP + '''fullScan()
        local D=ForeverFlip.Deals;local U=ForeverFlip.Util
        local cloth=D.get('c:10');assert(cloth and cloth.mode=='vendor' and cloth.qty==15 and cloth.cost==900)
        local nature=D.get(U.key('gear',20,'Northern Shortsword of Nature Protection'))
        local healing=D.get(U.key('gear',20,'Northern Shortsword of Healing'))
        assert(nature and nature.qty==1 and nature.cost==800 and nature.profit==270)
        assert(healing and healing.qty==1 and healing.cost==400,'own 7s sword is not a lot to buy')
        local last=ForeverFlip.Scan.last;assert(last.own==1 and last.stats.items==4 and last.stats.belowVendor==3)
        local h=ForeverFlip.Data.market(ForeverFlip.db,ForeverFlip.Engine.scope()).history
        assert(h['c:10'] and h['c:10'].scan.market)''')

    def test_scan_respects_the_15_minute_cooldown(self):
        run(SETUP + '''fullScan();local ok,why=ForeverFlip.Scan.start();assert(not ok and why=='cooldown')
        now=now+901;assert(ForeverFlip.Scan.start())''')

    def test_rows_of_unloaded_items_are_read_again_when_data_arrives(self):
        run(SETUP + '''items[30].cached=false;addAuction(30,100,1)
        local ok=ForeverFlip.Scan.start();fire('REPLICATE_ITEM_LIST_UPDATE')
        local n=0;while ForeverFlip.Scan.job and ForeverFlip.Scan.job.state=='reading' do run(0.05) end
        assert(#ForeverFlip.Scan.job.deferred==2);items[30].cached=true
        while ForeverFlip.Scan.busy() do run(0.05) end
        assert(ForeverFlip.Deals.get('i:30') and ForeverFlip.Scan.last.skipped==0)''')

    def test_large_scan_is_spread_over_frames(self):
        run('''for id=1,3000 do addItem(1000+id,'Item '..id,0,'commodity') end
        for i=1,20000 do addAuction(1000+(i%3000)+1,100+(i%50),1) end
        local ok=ForeverFlip.Scan.start();fire('REPLICATE_ITEM_LIST_UPDATE')
        local frames=0;while ForeverFlip.Scan.busy() do run(0.05);frames=frames+1 end
        assert(frames>20 and ForeverFlip.Scan.last.stats.items==3000,frames)''')


class TradeTests(unittest.TestCase):
    def test_deal_is_verified_then_commodity_bought_with_quote_and_confirm(self):
        run(SETUP + '''fullScan();ForeverFlip.Engine.autoVerify=false
        local D,T=ForeverFlip.Deals,ForeverFlip.Trade
        local ok,why=T.buy('c:10');assert(not ok and why=='verify_first')
        assert(D.verify('c:10') and lastCall('SendSearchQuery')[2]==10);answer()
        local d=D.get('c:10');assert(d.verified and d.qty==15 and d.cost==900)
        assert(T.buy('c:10') and lastCall('StartCommoditiesPurchase')[3]==15)
        fire('COMMODITY_PRICE_UPDATED',60,900);assert(T.op.state=='quoted')
        assert(T.confirm() and lastCall('ConfirmCommoditiesPurchase'))
        fire('COMMODITY_PURCHASE_SUCCEEDED')
        local c=ForeverFlip.Data.char(ForeverFlip.db,ForeverFlip.Engine.owner())
        assert(c.positions['c:10'].qty==15 and c.positions['c:10'].cost==900 and c.positions['c:10'].mode=='vendor')
        assert(c.journal[1].kind=='buy' and not T.op)''')

    def test_higher_quote_is_cancelled(self):
        run(SETUP + '''fullScan();ForeverFlip.Engine.autoVerify=false
        local D,T=ForeverFlip.Deals,ForeverFlip.Trade
        D.verify('c:10');answer();T.buy('c:10');fire('COMMODITY_PRICE_UPDATED',70,1050)
        assert(not T.op and lastCall('CancelCommoditiesPurchase') and D.retry);run(1.1);assert(D.searching())''')

    def test_gear_is_searched_across_versions_and_bought_one_auction_per_click(self):
        run(SETUP + '''fullScan();ForeverFlip.Engine.autoVerify=false
        local D,T,U=ForeverFlip.Deals,ForeverFlip.Trade,ForeverFlip.Util
        local key=U.key('gear',20,'Northern Shortsword of Healing')
        assert(D.verify(key) and lastCall('SendSellSearchQuery')[2]==20);answer()
        local d=D.get(key);assert(d.verified and d.lots[1].unit==400 and d.qty==1)
        for _,l in ipairs(d.lots)do assert(l.auctionID) end
        assert(T.buy(key));local bid=lastCall('PlaceBid');assert(bid[3]==400)
        fire('CHAT_MSG_SYSTEM','You won an auction for Northern Shortsword of Healing')
        local c=ForeverFlip.Data.char(ForeverFlip.db,ForeverFlip.Engine.owner())
        assert(c.positions[key].qty==1 and not T.op);run(1.1);assert(D.searching(),'next lot is checked')''')

    def test_purchase_without_answer_is_settled_in_the_journal(self):
        run(SETUP + '''fullScan();ForeverFlip.Engine.autoVerify=false
        local D,T,U=ForeverFlip.Deals,ForeverFlip.Trade,ForeverFlip.Util
        local key=U.key('gear',20,'Northern Shortsword of Nature Protection')
        D.verify(key);answer();assert(T.buy(key));run(31)
        local c=ForeverFlip.Data.char(ForeverFlip.db,ForeverFlip.Engine.owner())
        assert(not T.op and #c.unknown==1);T.settle(1,true);assert(c.positions[key].qty==1 and #c.unknown==0)''')

    def test_vanished_deal_is_removed_after_verification(self):
        run(SETUP + '''fullScan();ForeverFlip.Engine.autoVerify=false
        local D=ForeverFlip.Deals
        for i=#auctions,1,-1 do if auctions[i].item==10 and auctions[i].buyout<500 then table.remove(auctions,i) end end
        D.verify('c:10');answer();assert(not D.get('c:10'))''')

    def test_automatic_verification_keeps_the_04_second_pace(self):
        run(SETUP + '''ForeverFlip.Engine.autoVerify=true;fullScan()
        run(0.5);local D=ForeverFlip.Deals;assert(D.search);local t1=D.lastRequest;answer()
        while not D.search do run(0.05) end;local gap=D.lastRequest-t1
        assert(gap>=0.4-1e-9 and gap<0.9,gap)''')

    def test_post_and_sale_are_booked_with_profit(self):
        run(SETUP + '''local c=ForeverFlip.Data.char(ForeverFlip.db,ForeverFlip.Engine.owner())
        ForeverFlip.Data.addPosition(c,'i:30','Linen Bag',1,20000,'flip',29900)
        putBag(0,1,30,1)
        local item=ForeverFlip.AH.bagItems()[1];assert(item.key=='i:30')
        assert(ForeverFlip.Trade.checkPrice('i:30'));answer()
        local price,floor,cheapest=ForeverFlip.Trade.suggest(item)
        assert(cheapest==30000 and price==29900 and floor==21100)
        local ok,why=ForeverFlip.Trade.post(item,1,29900,3);assert(ok and why=='posted')
        assert(lastCall('PostItem')[6]==29900)
        assert(#c.listings==0,'booked when the game creates the auction');fire('AUCTION_HOUSE_AUCTION_CREATED',777)
        assert(#c.listings==1)
        owned={{auctionID=777,itemKey={itemID=30},quantity=1,buyoutAmount=29900,status=1}}
        fire('OWNED_AUCTIONS_UPDATED')
        local e=c.journal[#c.journal];assert(e.kind=='sell' and e.amount==29900-1495 and e.profit==29900-1495-20000)
        assert(not c.positions['i:30'])
        fire('OWNED_AUCTIONS_UPDATED');assert(#c.journal==1,'booked once')''')

    def test_post_asks_for_confirmation_when_the_game_does(self):
        run(SETUP + '''putBag(0,1,30,1);postNeedsConfirm=true
        local item=ForeverFlip.AH.bagItems()[1]
        local ok,why=ForeverFlip.Trade.post(item,1,29900,3);assert(ok and why=='confirm')
        ok,why=ForeverFlip.Trade.post(item,1,29900,3);assert(ok and why=='posted' and lastCall('ConfirmPostItem'))
        postNeedsConfirm=false;now=now+60;ForeverFlip.Trade.post(item,1,29900,3);fire('AUCTION_HOUSE_POST_WARNING')
        assert(ForeverFlip.Trade.pendingPost);ForeverFlip.Trade.post(item,1,29900,3);assert(lastCall('ConfirmPostItem'))''')

    def test_vendor_deals_are_sold_at_the_merchant_in_one_click(self):
        run(SETUP + '''local c=ForeverFlip.Data.char(ForeverFlip.db,ForeverFlip.Engine.owner())
        ForeverFlip.Data.addPosition(c,'c:10','Linen Cloth',15,900,'vendor',100)
        putBag(0,1,10,15);putBag(0,2,30,1)
        fire('MERCHANT_SHOW');assert(ForeverFlip.UI.merchantButton:IsShown())
        ForeverFlip.UI.merchantButton:Click()
        assert(#soldToVendor==1 and soldToVendor[1].itemID==10)
        local e=c.journal[#c.journal];assert(e.kind=='vendor' and e.amount==1500 and e.profit==600)''')


class UITests(unittest.TestCase):
    def test_pages_render_and_buy_button_needs_a_fresh_check(self):
        run(SETUP + '''local UI=ForeverFlip.UI;ForeverFlip.Engine.autoVerify=false
        UI.refresh();assert(UI.dealTable.empty:IsShown())
        fullScan();UI.refresh();assert(UI.dealTable.rows[1]:IsShown())
        UI.dealTable.rows[1]:Click();assert(ForeverFlip.Deals.searching());answer();UI.refresh()
        assert(UI.buyButton:IsEnabled());UI.buyButton:Click();assert(ForeverFlip.Trade.op)
        for _,id in ipairs({'sell','journal','settings','deals'}) do UI.show(id) end
        assert(UI.status:GetText()~='')''')

    def test_settings_are_saved(self):
        run('''local UI=ForeverFlip.UI;UI.show('settings')
        UI.settingBoxes[1]:SetText('5s');UI.settingBoxes[3]:SetText('30')
        for _,w in ipairs(widgets) do if w.text=='Save' then w:Click() end end
        assert(ForeverFlip.db.settings.vendorMinProfit==500 and math.abs(ForeverFlip.db.settings.minROI-0.3)<1e-9)''')

    def test_ukrainian_text(self):
        lua = runtime(False)
        lua.execute("ForeverFlip.Locale.apply('uk');assert(ForeverFlip.Locale.text('Full scan')=='Повний скан')")

    def test_an_error_is_reported_once_and_saved_instead_of_every_frame(self):
        run('''local f=ForeverFlip.frame;ForeverFlip.Trade.onChat=function()error('boom')end
        for _=1,50 do f.scripts.OnEvent(f,'CHAT_MSG_SYSTEM','x') end
        local n=0;for _,line in ipairs(printed) do if line:find('boom') then n=n+1 end end
        assert(n==1 and #ForeverFlip.db.errors==1 and ForeverFlip.db.errors[1].message:find('boom'))''')

    def test_item_info_comes_from_c_item_when_the_global_is_missing(self):
        run('''assert(GetItemInfo==nil);addItem(5,'Thing',123,'item')
        assert(ForeverFlip.AH.vendorPrice(5)==123 and ForeverFlip.db.vendor[5]==123)''')

    def test_scan_and_deals_survive_a_reload_until_the_next_scan(self):
        run(SETUP + '''fullScan()
        local D,S=ForeverFlip.Deals,ForeverFlip.Scan
        D.remove('i:30');S.last.waitVendor[30]={{key='i:30',kind='item',id=30,rows={{unit=100,qty=1}}}}
        D.verify('c:10');answer();assert(D.get('c:10').verified)
        local n=#D.list;fire('PLAYER_LOGOUT')
        S.last=nil;D.list={};now=now+600;fire('AUCTION_HOUSE_SHOW')
        assert(S.last and #D.list==n and D.get('c:10') and not D.get('c:10').verified)
        assert(S.last.waitVendor[30],'items without a vendor price wait again')
        fire('ITEM_DATA_LOAD_RESULT',30,true);assert(D.get('i:30'))
        now=now+400;ForeverFlip.UI.refresh();assert(#D.visible('all')==#D.list)''')


class ToolsTests(unittest.TestCase):
    def test_full_scan_starts_by_itself_every_15_minutes(self):
        run('''ForeverFlip.db.lastScan=now-899;run(0.5);assert(not ForeverFlip.Scan.busy())
        now=now+2;run(0.1);assert(ForeverFlip.Scan.busy() and lastCall('ReplicateItems'))
        ForeverFlip.Scan.stop();ForeverFlip.db.settings.autoScan=false;ForeverFlip.db.lastScan=now-901
        run(0.5);assert(not ForeverFlip.Scan.busy())''')

    def test_resale_profit_counts_the_deposit_and_stock_in_hand(self):
        run('''local M=ForeverFlip.Market
        local rows={{unit=900,qty=2},{unit=999,qty=1},{unit=7800,qty=16}}
        local h={flow={hours=24,sold={30,30,30,30},pairs=4,at=now,market=7800}}
        local ctx={kind='gear',vendor=800,budget=1000000,history=h,market=7800,now=now,settings={minProfit=100,minROI=0.2}}
        local d=M.evaluate(rows,ctx);assert(d and d.qty==3 and d.exit==7700)
        assert(d.profit==M.net(7700,3)-2799-3*120,d.profit)
        ctx.held=29;local d2,why=M.evaluate(rows,ctx);assert(not d2 and why=='enough_stock',why)''')

    def test_one_item_cannot_take_more_than_its_share_of_money(self):
        run(SETUP + '''money=10000;ForeverFlip.db.settings.itemShare=0.3
        local c=ForeverFlip.Data.char(ForeverFlip.db,ForeverFlip.Engine.owner())
        ForeverFlip.Data.addPosition(c,'c:10','Linen Cloth',30,3000,'flip',200)
        local M=ForeverFlip.Market
        local h={flow={hours=24,sold={900,900,900,900},pairs=4,at=now,market=200}}
        local g={key='c:10',kind='commodity',id=10,rows={{unit=60,qty=5},{unit=200,qty=50}},market=200}
        local d=ForeverFlip.Deals.evaluate(g,nil,h,now)
        assert(not d,'3000 of 3000 allowed is already in stock');money=100000
        d=ForeverFlip.Deals.evaluate(g,nil,h,now);assert(d and d.qty==5 and d.cost==300)''')

    def test_my_auctions_show_undercut_and_cancel(self):
        run(SETUP + '''owned={{auctionID=5,itemKey={itemID=10},quantity=20,buyoutAmount=150,status=0,timeLeftSeconds=7200},
          {auctionID=6,itemKey={itemID=30},quantity=1,buyoutAmount=25000,status=1}}
        fire('OWNED_AUCTIONS_UPDATED');local T=ForeverFlip.Trade
        assert(#T.owned==2 and T.owned[1].key=='c:10' and T.ownedStatus(T.owned[2])=='sold')
        assert(T.checkOwned()==1);run(0.1);answer()
        local status,cheapest=T.ownedStatus(T.owned[1]);assert(status=='undercut' and cheapest==60)
        local UI=ForeverFlip.UI;UI.show('auctions');UI.auctionTable.rows[1]:Click()
        assert(UI.cancelAuction:IsEnabled());UI.cancelAuction:Click();assert(lastCall('CancelAuction')[2]==5)''')

    def test_statistics_per_item_and_stale_stock(self):
        run(SETUP + '''local c=ForeverFlip.Data.char(ForeverFlip.db,ForeverFlip.Engine.owner())
        local D=ForeverFlip.Data
        D.addPosition(c,'i:30','Linen Bag',2,20000,'flip',29900,now-2*86400)
        D.sale(c,'i:30','Linen Bag',1,28405,now)
        D.addPosition(c,'c:10','Linen Cloth',5,300,'flip',100,now-5*86400)
        local stats=ForeverFlip.Trade.itemStats()
        assert(stats[1].key=='c:10' and stats[1].stale,'stale stock first')
        local bag=stats[2];assert(bag.bought==2 and bag.sold==1 and bag.profit==28405-10000 and math.abs(bag.avgDays-2)<0.01 and bag.stock==1)
        local UI=ForeverFlip.UI;UI.show('stats');assert(UI.statsTable.rows[2]:IsShown())''')


class TwoScanTests(unittest.TestCase):
    def test_resale_starts_after_two_scans_with_at_most_two_units(self):
        run('''local M=ForeverFlip.Market
        local rows={{unit=900,qty=5},{unit=7800,qty=16}}
        local h={flow={hours=0.25,sold={20,20,20,20},pairs=1,at=now,market=7800}}
        local ctx={kind='commodity',budget=1000000,history=h,market=7800,now=now,settings={minProfit=100,minROI=0.2}}
        local d,why=M.evaluate(rows,ctx);assert(not d,'5 cheap units left would undercut')
        rows={{unit=900,qty=2},{unit=7800,qty=16}};d=M.evaluate(rows,ctx);assert(d and d.qty==2)
        h.flow.pairs=0;d,why=M.evaluate(rows,ctx);assert(not d and why=='collecting')''')

    def test_selection_is_cleared_when_it_is_not_in_the_chosen_list(self):
        run(SETUP + '''fullScan();local UI=ForeverFlip.UI;UI.show('deals:vendor')
        UI.dealTable.rows[1]:Click();assert(UI.selected);UI.show('deals:flip');assert(not UI.selected)''')


SNIPE = '''
ForeverFlip.Engine.autoVerify=false;ForeverFlip.db.settings.autoScan=false
ForeverFlip.db.settings.sniper=false
addItem(10,'Linen Cloth',100,'commodity')
addItem(40,'Wool Cloth',300,'commodity')
for i=1,6 do addAuction(40,320,5) end          -- wool: 3s20 each, vendor pays 3s: near a deal
addAuction(10,150,20)
'''


class SniperTests(unittest.TestCase):
    def test_items_near_a_deal_form_the_sniper_list(self):
        run(SNIPE + '''fullScan();local S=ForeverFlip.Scan
        assert(#S.hot==1 and S.hot[1]=='c:40')
        local h=ForeverFlip.Data.market(ForeverFlip.db,ForeverFlip.Engine.scope()).history['c:40']
        assert(h.hits==1)''')

    def test_sniper_finds_a_cheap_lot_between_scans_and_alerts_once(self):
        run(SNIPE + '''fullScan();ForeverFlip.Engine.autoVerify=true;ForeverFlip.db.settings.sniper=true
        assert(#ForeverFlip.Deals.list==0)
        addAuction(40,200,4)                         -- someone lists wool far below vendor price
        run(1.1);local s=ForeverFlip.Deals.search;assert(s and s.key=='c:40');answer()
        local d=ForeverFlip.Deals.get('c:40');assert(d and d.verified and d.qty==4 and d.profit==400)
        assert(sounds==1 and #screen==1 and screen[1]:find('400') or screen[1]:find('4s'))
        run(1.1);if ForeverFlip.Deals.search then answer() end
        run(61);if ForeverFlip.Deals.search then answer() end
        assert(sounds==1,'one notice per deal')''')

    def test_sniper_and_alerts_can_be_turned_off(self):
        run(SNIPE + '''fullScan();ForeverFlip.Engine.autoVerify=true;ForeverFlip.db.settings.sniper=false
        addAuction(40,200,4);run(3);assert(not ForeverFlip.Deals.search)
        ForeverFlip.db.settings.sniper=true;ForeverFlip.db.settings.alerts=false
        run(1.1);answer();assert(ForeverFlip.Deals.get('c:40') and sounds==0)''')

    def test_sniper_list_survives_a_reload(self):
        run(SNIPE + '''fullScan();fire('PLAYER_LOGOUT');local S=ForeverFlip.Scan
        S.last=nil;S.hot=nil;fire('AUCTION_HOUSE_SHOW');assert(S.hot and S.hot[1]=='c:40')''')


class ScanAnswerTests(unittest.TestCase):
    def test_answer_during_the_request_is_not_lost(self):
        run(SETUP + '''replicateEventInside=true;assert(ForeverFlip.Scan.start())
        assert(ForeverFlip.Scan.job.state=='reading')''')

    def test_scan_is_taken_without_the_event_once_the_list_stops_growing(self):
        run(SETUP + '''assert(ForeverFlip.Scan.start());run(3.2)
        assert(not ForeverFlip.Scan.job or ForeverFlip.Scan.job.state~='waiting')
        while ForeverFlip.Scan.busy() do run(0.05) end;assert(ForeverFlip.Deals.get('c:10'))''')

    def test_no_answer_retries_in_a_minute(self):
        run(SETUP + '''replicateIgnored=true;assert(ForeverFlip.Scan.start());run(47)
        assert(not ForeverFlip.Scan.busy() and ForeverFlip.Engine.message=='scan_timeout')
        local cd=ForeverFlip.Scan.cooldown();assert(cd>0 and cd<=60,cd)''')

    def test_a_full_scan_of_another_addon_is_read_too(self):
        run(SETUP + '''C_AuctionHouse.ReplicateItems();fire('REPLICATE_ITEM_LIST_UPDATE')
        assert(ForeverFlip.Scan.busy() and ForeverFlip.Scan.cooldown()>800)
        while ForeverFlip.Scan.busy() do run(0.05) end;assert(ForeverFlip.Deals.get('c:10'))''')


class FeatureTests(unittest.TestCase):
    def test_auction_mail_is_taken_in_one_click_and_other_mail_is_left(self):
        run('''inbox={
          {sender='Auction House',subject='Auction successful: Linen Bag',money=2850,invoice='seller'},
          {sender='Auction House',subject='Auction won: Wool Cloth',items=1,invoice='buyer'},
          {sender='Friend',subject='hi',money=500},
          {sender='Auction House',subject='Auction expired: Boots',items=1},
          {sender='Shady',subject='Auction won: Fake',items=1,cod=100}}
        fire('MAIL_SHOW');assert(ForeverFlip.Mail.count()==3 and ForeverFlip.UI.mailButton:IsShown())
        ForeverFlip.UI.mailButton:Click();for _=1,40 do run(0.1) end
        assert(#mailTaken==3 and not ForeverFlip.Mail.job,#mailTaken)
        assert(#inbox==2 and inbox[1].sender=='Friend' and inbox[2].cod==100,'player mail and COD stay')
        local said=false;for _,l in ipairs(printed) do said=said or l:find('auction mail taken') end;assert(said)''')

    def test_mail_run_stops_when_bags_are_full_or_mailbox_closes(self):
        run('''inbox={{subject='Auction won: A',items=1,invoice='buyer'},{subject='Auction won: B',items=1,invoice='buyer'}}
        freeBagSlots=1;fire('MAIL_SHOW');ForeverFlip.Mail.start();for _=1,20 do run(0.1) end
        assert(#mailTaken==1 and not ForeverFlip.Mail.job and #inbox==1)
        freeBagSlots=5;ForeverFlip.Mail.start();fire('MAIL_CLOSED');run(1);assert(#mailTaken==1)''')

    def test_post_next_bought_reads_the_price_then_posts_below_the_next_seller(self):
        run(SETUP + '''local c=ForeverFlip.Data.char(ForeverFlip.db,ForeverFlip.Engine.owner())
        ForeverFlip.Data.addPosition(c,'i:30','Linen Bag',1,20000,'flip',29900,now-60)
        ForeverFlip.Data.addPosition(c,'c:10','Linen Cloth',15,900,'vendor',100,now-60)
        putBag(0,1,30,1);putBag(0,2,10,15)
        local T=ForeverFlip.Trade;assert(#T.toPost()==1,'vendor deals are not posted')
        local ok,why=T.postNext();assert(ok and why=='checking');answer()
        ok,why=T.postNext();assert(ok and why=='posted' and lastCall('PostItem')[6]==29900)
        c.positions['i:30'].cost=40000;T.prices['i:30'].at=now;postNeedsConfirm=false
        fire('AUCTION_HOUSE_AUCTION_CREATED',9);assert(#T.toPost()==0,'listed items are not posted twice')''')

    def test_post_next_never_goes_below_break_even(self):
        run(SETUP + '''local c=ForeverFlip.Data.char(ForeverFlip.db,ForeverFlip.Engine.owner())
        ForeverFlip.Data.addPosition(c,'i:30','Linen Bag',1,40000,'flip',29900,now-60)
        putBag(0,1,30,1);local T=ForeverFlip.Trade;T.postNext();answer();T.postNext()
        assert(lastCall('PostItem')[6]==ForeverFlip.Market.breakEven(40000,1,'item'))''')

    def test_unsold_stock_lowers_the_sales_estimate(self):
        run(SETUP + '''local c=ForeverFlip.Data.char(ForeverFlip.db,ForeverFlip.Engine.owner())
        local D=ForeverFlip.Deals
        assert(D.trust('c:10',now)==1)
        ForeverFlip.Data.addPosition(c,'c:10','Linen Cloth',2,200,'flip',150,now-2*86400)
        assert(D.trust('c:10',now)==0.5)
        ForeverFlip.Data.addPosition(c,'c:20','X',1,1,'flip',1,now-4*86400);assert(D.trust('c:20',now)==0.25)
        ForeverFlip.Data.sale(c,'c:10','Linen Cloth',1,140,now);assert(D.trust('c:10',now)==1)
        local M=ForeverFlip.Market
        local h={flow={hours=20,sold={1.5,1.5,1.5,1.5},pairs=3,at=now,market=1000}}
        local rows={{unit=100,qty=1},{unit=1000,qty=10}}
        local ctx={kind='commodity',budget=100000,history=h,market=1000,now=now,settings={minProfit=1,minROI=0.1}}
        assert(M.evaluate(rows,ctx));ctx.trust=0.25;local d,why=M.evaluate(rows,ctx);assert(not d and why=='not_selling')''')

    def test_item_tooltip_shows_the_price_history_of_the_scans(self):
        run(SETUP + '''fullScan()
        local h=ForeverFlip.Data.market(ForeverFlip.db,ForeverFlip.Engine.scope()).history['c:10']
        assert(h.days and #h.days==1 and h.days[1].min==60)
        assert(#tooltipCalls==1);GameTooltip.itemLink=link(10)
        tooltipCalls[1](GameTooltip);assert(#tooltipLines>=2 and tooltipLines[1]:find('ForeverFlip'))
        ForeverFlip.db.settings.tooltipPrices=false;tooltipLines={};tooltipCalls[1](GameTooltip);assert(#tooltipLines==0)''')


    def test_items_a_vendor_does_not_buy_never_wait_for_a_vendor_price(self):
        run('''ForeverFlip.Engine.autoVerify=false;ForeverFlip.db.settings.autoScan=false
        addItem(50,'Quest Thing',0,'item');addAuction(50,100,1)
        fullScan();assert(not ForeverFlip.Scan.last.waitVendor[50])''')

    def test_sniper_list_keeps_the_best_items_in_order(self):
        run('''local S=ForeverFlip.Scan;local list={}
        for i=1,400 do S.hotInsert(list,{key='c:'..i,score=i%37}) end
        assert(#list==S.HOT and list[1].score==36)
        for i=2,#list do assert(list[i-1].score>=list[i].score) end''')


class AnalyticsTests(unittest.TestCase):
    def test_results_per_day_return_hit_rate_and_best_items(self):
        run('''local c=ForeverFlip.Data.char(ForeverFlip.db,ForeverFlip.Engine.owner());local D=ForeverFlip.Data
        local day=86400
        D.log(c,{at=now-2*day,kind='buy',key='c:1',name='A',qty=2,amount=1000})
        D.log(c,{at=now-2*day,kind='sell',key='c:1',name='A',qty=2,amount=1500,profit=500})
        D.log(c,{at=now-day,kind='vendor',key='c:2',name='B',qty=1,amount=300,profit=100})
        D.log(c,{at=now,kind='sell',key='c:3',name='C',qty=1,amount=200,profit=-50})
        D.log(c,{at=now-40*day,kind='sell',key='c:4',name='Old',qty=1,amount=999,profit=999})
        D.addPosition(c,'c:5','Stale',1,700,'flip',900,now-4*day)
        local r=ForeverFlip.Analytics.results(7,now)
        assert(r.profit==550 and r.sales==3 and r.wins==2 and r.vendor==100 and r.auction==450)
        assert(math.abs(r.roi-550/1450)<1e-9 and math.abs(r.hitRate-2/3)<1e-9)
        assert(#r.days==7 and r.days[7].profit==-50 and r.days[5].profit==500)
        assert(r.best[1].name=='A' and r.worst[1].name=='C' and r.stale==700 and r.held==700)''')

    def test_market_lists_gaps_liquid_items_and_price_moves(self):
        run('''local h=ForeverFlip.Data.market(ForeverFlip.db,ForeverFlip.Engine.scope()).history
        local day=math.floor(now/86400)
        h['c:1']={scan={at=now,market=1000},flow={hours=20,sold={24,24,24,24},pairs=3,at=now,market=1000},
          days={{d=day-2,m=1500,min=1400},{d=day-1,m=1500,min=1300},{d=day,m=1000,min=500}},units=40}
        h['c:2']={scan={at=now,market=500},flow={hours=20,sold={2,2,2,2},pairs=3,at=now,market=500},
          days={{d=day-1,m=400,min=400},{d=day,m=500,min=480}},units=10}
        local m=ForeverFlip.Analytics.market(now)
        assert(m.items==2 and m.liquid[1].key=='c:1' and m.gaps[1].key=='c:1' and m.gaps[1].gap==450)
        assert(m.falling[1].key=='c:1' and m.rising[1].key=='c:2' and math.abs(m.rising[1].change-0.25)<1e-9)''')

    def test_analytics_page_renders(self):
        run(SETUP + '''fullScan();local UI=ForeverFlip.UI;UI.show('analytics')
        assert(UI.resultsText:GetText():find('Profit') and #UI.bars==7)
        UI.periodButtons[30]:Click();assert(#UI.bars==30 and UI.analyticsDays==30)
        UI.viewButtons.liquid:Click();assert(UI.marketView=='liquid')''')


class DealTabTests(unittest.TestCase):
    def test_found_deals_are_checked_at_the_faster_pace(self):
        run(SETUP + '''addItem(11,'A',100,'commodity');addItem(12,'B',100,'commodity');addAuction(11,50,5);addAuction(12,50,5)
        fullScan();ForeverFlip.Engine.autoVerify=true;local seen={}
        for _=1,30 do run(0.1);local s=ForeverFlip.Deals.search;if s and not seen[s.key] then seen[s.key]=true;answer() end end
        local n=0;for _ in pairs(seen) do n=n+1 end;assert(n>=3,n)''')

    def test_status_shows_money_and_old_scan_and_detail_shows_return(self):
        run(SETUP + '''fullScan();local UI=ForeverFlip.UI;local D=ForeverFlip.Deals
        local d=D.get('c:10');d.found=now-1300;UI.refresh()
        local function status(key) for _,r in ipairs(UI.dealTable.rows) do if r.key==key then return r.cols[5]:GetText() end end end
        assert(status('c:10'):find('old scan'))
        money=100;UI.refresh();assert(status('c:10'):find('not enough money'))
        money=1000000;UI.selectDeal('c:10');answer();UI.refresh()
        assert(UI.dealText:GetText():find('Return') and UI.pageText:GetText():find('profit'))''')

    def test_merchant_items_worth_reselling_are_listed_and_bought_by_click(self):
        run('''addItem(60,'Fine Thread',5,'commodity');addItem(61,'Cheap Thing',5,'commodity')
        local h=ForeverFlip.Data.market(ForeverFlip.db,ForeverFlip.Engine.scope()).history
        h['c:60']={scan={at=now,market=500},flow={hours=20,sold={48,48,48,48},pairs=3,at=now,market=500}}
        h['c:61']={scan={at=now,market=60},flow={hours=20,sold={48,48,48,48},pairs=3,at=now,market=60}}
        merchantItems={{id=60,price=100},{id=61,price=100},{id=60,price=50,extended=true}}
        local offers=ForeverFlip.Merchant.offers(now)
        assert(#offers==1 and offers[1].key=='c:60' and offers[1].exit==499 and offers[1].qty==48)
        fire('MERCHANT_SHOW');assert(ForeverFlip.UI.offerPanel:IsShown())
        ForeverFlip.UI.offerPanel.rows[1].buy:Click()
        assert(merchantBought[1][1]==1 and merchantBought[1][2]==48)
        local c=ForeverFlip.Data.char(ForeverFlip.db,ForeverFlip.Engine.owner())
        assert(c.positions['c:60'].qty==48 and c.positions['c:60'].cost==4800 and c.positions['c:60'].mode=='flip')''')


class TimingTests(unittest.TestCase):
    def test_weekly_pattern_finds_the_cheap_and_the_dear_time(self):
        run('''local M=ForeverFlip.Market;local h={}
        -- Four weeks of scans every 6 hours; Friday evening is 30% dearer, Tuesday morning 20% cheaper.
        local start=1800000000;local fridayEvening,tuesdayMorning
        for k=0,4*7*4 do
          local t=start+k*6*3600;local w,p=M.slot(t);local price=1000
          if w==6 and p==4 then price=1300;fridayEvening={w=w,p=p} end
          if w==3 and p==2 then price=800;tuesdayMorning={w=w,p=p} end
          M.recordTiming(h,price,t)
        end
        local r=M.timing(h,start)
        assert(r.ready and r.high.w==6 and r.high.p==4 and r.low.w==3 and r.low.p==2)
        -- Day and time are separate factors: a spike only on one evening is spread out.
        assert(r.spread>0.15,r.spread)''')

    def test_pattern_needs_enough_days_and_parts(self):
        run('''local M=ForeverFlip.Market;local h={}
        for k=0,5 do M.recordTiming(h,1000,1800000000+k*3600) end
        assert(not M.timing(h,1800000000).ready)''')

    def test_cheap_now_list_and_tooltip_use_the_pattern(self):
        run(SETUP + '''local M=ForeverFlip.Market;local h=ForeverFlip.Data.market(ForeverFlip.db,ForeverFlip.Engine.scope()).history
        local w,p=M.slot(now)
        local t={b=1000,w={1,1,1,1,1,1,1},wn={3,3,3,3,3,3,3},p={1,1,1,1},pn={3,3,3,3}}
        t.w[w]=0.8;t.w[(w%7)+1]=1.3
        h['c:10']={scan={at=now,market=1000},flow={hours=20,sold={24,24,24,24},pairs=3,at=now,market=1000},t=t,units=40}
        ForeverFlip.Analytics.invalidate();local m=ForeverFlip.Analytics.market(now)
        assert(m.cheapNow[1] and m.cheapNow[1].key=='c:10')
        local UI=ForeverFlip.UI;UI.show('analytics');UI.viewButtons.cheapNow:Click()
        assert(UI.marketTable.rows[1].cols[3]:GetText()=='-20%')
        GameTooltip.itemLink=link(10);tooltipLines={};tooltipCalls[1](GameTooltip)
        local found=false;for _,l in ipairs(tooltipLines) do found=found or l:find('dearest') end;assert(found)''')


    def test_sell_page_hints_a_dearer_time(self):
        run(SETUP + '''local M=ForeverFlip.Market;local h=ForeverFlip.Data.market(ForeverFlip.db,ForeverFlip.Engine.scope()).history
        local w=M.slot(now);local t={b=30000,w={1,1,1,1,1,1,1},wn={3,3,3,3,3,3,3},p={1,1,1,1},pn={3,3,3,3}}
        t.w[w]=0.8;t.w[(w%7)+1]=1.3;h['i:30']={scan={at=now,market=30000},t=t,units=12}
        putBag(0,1,30,1);local UI=ForeverFlip.UI;UI.show('sell');UI.sellTable.rows[1]:Click();answer();UI.refresh()
        assert(UI.sellText:GetText():find('higher'),UI.sellText:GetText())''')


if __name__ == '__main__':
    unittest.main()
