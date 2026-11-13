"""Review fixes of the full scan (Scan.lua) and the raw scans for the Sync helper (Raw.lua)."""

import pathlib
import sys
import time
import unittest

from test_addon import SETUP, run, runtime

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / 'sync'))
import ffscan  # noqa: E402
from test_sync import RAW, saved_variables  # noqa: E402

BASE = '''ForeverFlip.db.settings.autoVerify=false;ForeverFlip.db.settings.autoScan=false
ForeverFlip.db.settings.sniper=false
local F,S,M,U=ForeverFlip,ForeverFlip.Scan,ForeverFlip.Market,ForeverFlip.Util
'''

# A house large enough to be read over several frames (400 rows a frame in the tests).
MANY = '''for id=1,30 do addItem(5000+id,'Thing '..id,0,'commodity') end
for i=1,2000 do addAuction(5000+(i%30)+1,100+(i%50),1) end
'''


class WaitingTests(unittest.TestCase):
    def test_a_house_that_shrank_after_a_break_is_read_again(self):
        run(BASE + '''addItem(10,'Linen Cloth',0,'commodity')
        for i=1,2001 do addAuction(10,100+(i%9),1,'S'..(i%50)) end
        fullScan()
        fire('PLAYER_LOGOUT'); S.last=nil
        -- two days later the house holds under half of it
        for i=#auctions,901,-1 do table.remove(auctions,i) end
        now=now+2*86400
        fire('AUCTION_HOUSE_CLOSED'); fire('AUCTION_HOUSE_SHOW')
        assert(S.reference(F.Engine.scope())==0, 'a scan two days old is no measure of the house')
        fullScan()
        assert(S.last.total==900 and F.db.scanLog[1].outcome=='read', F.db.scanLog[1].outcome)''')

    def test_an_unanswered_call_over_the_last_list_is_a_miss(self):
        run(SETUP + '''local F,S=ForeverFlip,ForeverFlip.Scan
        fullScan()
        replicateIgnored=true -- the server answers no call: the client keeps the list read before
        run(S.cooldown()+1)
        assert(S.start())
        while S.busy() do run(1) end
        assert(F.db.scanLog[1].outcome=='no answer', F.db.scanLog[1].outcome)
        assert(F.db.scanMisses==1 and S.window()==S.COOLDOWN+S.MISS_STEP, 'the next call waits longer')''')

    def test_an_answer_read_before_closing_is_read_on_reopening_later(self):
        run(BASE + MANY + '''assert(S.start()); fire('REPLICATE_ITEM_LIST_UPDATE'); run(0.05)
        assert(S.job and S.job.state=='reading')
        fire('AUCTION_HOUSE_CLOSED')
        -- reopened 15 minutes after the call: past the answer wait, within the 20 minutes kept
        now=F.db.scanPending.at+900
        fire('AUCTION_HOUSE_SHOW')
        assert(S.busy())
        run(0.05)
        assert(S.busy(), 'not given up on the first frame')
        while S.busy() do run(0.05) end
        assert(S.last and S.last.total==2000 and F.db.scanLog[1].outcome=='read', F.db.scanLog[1].outcome)''')

    def test_another_addons_call_inside_the_window_holds_nothing_back(self):
        run(SETUP + '''local F,S=ForeverFlip,ForeverFlip.Scan
        fullScan()
        now=now+300
        replicateIgnored=true
        S.onOtherScan() -- another addon calls ReplicateItems 5 minutes after our call
        assert(not S.busy() and not S.blocking(), 'the server does not answer it: nothing to wait for')
        assert(F.db.lastScan==time(), 'the server counts its 15 minutes again from that call')''')

    def test_another_addons_call_during_our_scan_moves_the_window(self):
        run(BASE + MANY + '''assert(S.start()); fire('REPLICATE_ITEM_LIST_UPDATE'); run(0.05)
        now=now+6
        S.onOtherScan() -- while our answer is read
        local other=time()
        while S.busy() do run(0.05) end
        assert(F.db.lastScan==other, 'our next call waits for the window of that call')
        -- an unanswered call of ours, and another addon's call a minute later
        run(S.cooldown()+1)
        replicateIgnored=true
        assert(S.start()); run(60)
        S.onOtherScan(); other=time()
        while S.busy() do run(1) end
        assert(F.db.scanLog[1].outcome=='no answer' and F.db.lastScan==other, 'giving up keeps the later call')''')

    def test_a_late_answer_to_a_call_at_another_house_is_not_read_here(self):
        run(BASE + '''addItem(10,'Linen Cloth',0,'commodity')
        for i=1,300 do addAuction(10,100+(i%9),1,'S'..(i%50)) end
        replicateIgnored=true -- the answer is slow
        assert(S.start()); run(30)
        fire('AUCTION_HOUSE_CLOSED')
        now=now+180
        F.Engine.detectHouse=function() return 'Neutral' end
        fire('AUCTION_HOUSE_SHOW')
        local neutral=F.Engine.scope()
        assert(neutral=='Realm-Neutral' and not S.busy())
        -- the answer to the call at the Alliance house comes now
        replicateIgnored=false
        C_AuctionHouse.ReplicateItems()
        fire('REPLICATE_ITEM_LIST_UPDATE')
        while S.busy() do run(0.05) end
        assert(not (S.last and S.last.scope==neutral), 'the Alliance list is not the neutral house')
        assert(not F.Data.market(F.db,neutral).history['c:10'])''')

    def test_the_automatic_scan_starts_while_the_throttle_is_stuck(self):
        run(SETUP + '''local F=ForeverFlip
        F.db.settings.autoScan=true
        throttleReady=false -- the client's throttle stuck on "not ready"
        calls={}
        run(21)
        local n=0
        for _,c in ipairs(calls) do if c[1]=='ReplicateItems' then n=n+1 end end
        assert(n==1, 'the stuck allowance goes to the scan itself: '..n)''')


class ReadingTests(unittest.TestCase):
    def test_rows_read_after_their_item_data_keep_scan_order(self):
        run(BASE + '''enableTimeLeft()
        addItem(10,'Linen Cloth',0,'commodity')
        addItem(11,'Filler',0,'commodity')
        addAuction(10,60,20,'Bob') -- a stack of 20, later a remainder of 7
        for i=1,1500 do addAuction(11,100+(i%7),1,'Other'..(i%13)) end
        addAuction(10,60,7,'Bob')
        fullScan()
        local h=F.Data.market(F.db,F.Engine.scope()).history['c:10']
        assert(h.lots=='60:20:3,60:7:3', h.lots)
        -- 15 minutes later nothing changed; the cloth's data loads while the list is read
        now=now+921; F.db.lastScan=0
        items[10].cached=false
        assert(S.start()); fire('REPLICATE_ITEM_LIST_UPDATE'); run(0.05)
        items[10].cached=true
        while S.busy() do run(0.05) end
        assert(h.lots=='60:20:3,60:7:3', h.lots)
        assert((h.sales and h.sales.sure or 0)==0 and (M.demandAt(h,60).sold or 0)==0, 'nothing was sold')''')

    def test_an_item_whose_rows_were_not_read_is_not_unlisted(self):
        run(SETUP + '''local F,S=ForeverFlip,ForeverFlip.Scan
        addAuction(30,25000,1,'Rival')
        items[30].cached=false -- its data does not load within the recovery
        fullScan()
        assert(S.last.skipped>0)
        items[30].cached=true
        assert(not S.notListed('i:30') and S.listedUnits('i:30')==nil, 'the scan does not know')
        assert(not F.Trade.noSellers('i:30') and not F.Trade.alone('i:30'))
        assert(S.listedUnits('c:10')==35 and not S.notListed('c:10'))''')

    def test_closing_while_the_scan_is_finished_books_it_once(self):
        run(BASE + '''enableTimeLeft()
        addItem(10,'Linen Cloth',0,'commodity')
        local a=addAuction(10,60,5,'Seller1')
        addAuction(10,70,5,'Seller2')
        for id=1,700 do addItem(1000+id,'Thing '..id,0,'commodity'); addAuction(1000+id,100,1,'X') end
        fullScan()
        local h=F.Data.market(F.db,F.Engine.scope()).history['c:10']
        -- Seller1 cancels the 60c lot: it vanishes whole, a suspect until the next scan
        for i=#auctions,1,-1 do if auctions[i]==a then table.remove(auctions,i) end end
        now=now+921; F.db.lastScan=0
        assert(S.start()); fire('REPLICATE_ITEM_LIST_UPDATE')
        while S.job and S.job.state~='finishing' do run(0.05) end
        run(0.05)
        assert(h.pending and S.job and S.job.state=='finishing')
        AuctionHouseFrame:Hide(); fire('AUCTION_HOUSE_CLOSED')
        now=now+120
        AuctionHouseFrame:Show(); fire('AUCTION_HOUSE_SHOW')
        while S.busy() do run(0.05) end
        assert(h.pending, 'still a suspect')
        assert(not (h.sales and h.sales.log and h.sales.log[1]), 'no sale booked')
        assert(S.last.total==#auctions and F.db.scanPending==nil)''')

    def test_a_scan_finished_after_moving_to_another_house_stays_with_its_own(self):
        run(BASE + MANY + '''assert(S.start()); fire('REPLICATE_ITEM_LIST_UPDATE')
        while S.job and S.job.state~='finishing' do run(0.05) end
        local alliance=F.Engine.scope()
        AuctionHouseFrame:Hide(); fire('AUCTION_HOUSE_CLOSED')
        F.Engine.detectHouse=function() return 'Neutral' end
        AuctionHouseFrame:Show(); fire('AUCTION_HOUSE_SHOW')
        while S.busy() do run(0.05) end
        local saved=F.Data.market(F.db,alliance).last
        assert(saved and saved.total==2000, 'the list read is finished and kept for its house')
        assert(S.last==nil and F.Deals.scope==F.Engine.scope(), 'the neutral house shows its own scan')''')

    def test_a_reload_while_the_scan_is_finished_does_not_read_it_again(self):
        run(BASE + MANY + '''assert(S.start()); fire('REPLICATE_ITEM_LIST_UPDATE')
        while S.job and S.job.state~='finishing' do run(0.05) end
        S.job=nil -- /reload: the work in memory is gone, the saved data stays
        fire('AUCTION_HOUSE_CLOSED'); fire('AUCTION_HOUSE_SHOW')
        assert(not S.busy() and F.db.scanPending==nil, 'its history is written in part: not read again')
        assert(F.db.scanLog[1].outcome=='read')''')

    def test_a_late_vendor_price_prices_no_resale_from_the_kept_rows(self):
        run(BASE + '''addItem(40,'Elixir',500,'commodity') -- a merchant pays 5s
        addAuction(40,300,1,'A'); addAuction(40,320,1,'B'); addAuction(40,340,1,'C')
        addAuction(40,510,1,'D')
        for p=700,1000,40 do addAuction(40,p,1,'E'..p) end
        for i=1,20 do addAuction(40,2000,5,'Wall'..i) end
        local hist=F.Data.market(F.db,F.Engine.scope()).history
        local h={}; M.recordSales(h,{[2000]=4},24*3600,now-60); h.sales.pairs=4
        hist['c:40']=h
        F.db.vendor[40]=nil
        assert(S.start()); fire('REPLICATE_ITEM_LIST_UPDATE')
        while S.job and S.job.state~='finishing' do run(0.05) end
        items[40].cached=false; F.db.vendor[40]=nil -- no vendor price when the item is evaluated
        while S.busy() do run(0.05) end
        local d=F.Deals.get('c:40')
        assert(d and d.mode=='flip' and d.exit<510 and S.last.waitVendor[40], 'a resale below the 5s10 lot')
        items[40].cached=true
        fire('ITEM_DATA_LOAD_RESULT',40,true)
        d=F.Deals.get('c:40')
        assert(d.mode=='vendor' and d.qty==3 and d.cost==960 and d.profit==540, d.mode..' '..tostring(d.exit))''')

    def test_lot_tracking_writes_no_global(self):
        run(SETUP + '''local F=ForeverFlip
        enableTimeLeft()
        local writes, shadow = 0, nil
        rawset(_G,'_',nil)
        setmetatable(_G,{
            __newindex=function(t,k,v)
                if k~='_' then return rawset(t,k,v) end
                shadow=v -- kept aside, so every write is seen
                if debug.getinfo(2,'f').func==F.Scan.trackLots then writes=writes+1 end
            end,
            __index=function(_,k) if k=='_' then return shadow end end})
        fullScan()
        now=now+16*60; addAuction(10,70,5); fullScan()
        setmetatable(_G,nil)
        assert(writes==0, writes)''')


class OwnLotsTests(unittest.TestCase):
    def test_a_scan_naming_sellers_knows_the_player_had_no_lot(self):
        run(SETUP + '''local F,S,T=ForeverFlip,ForeverFlip.Scan,ForeverFlip.Trade
        for i=#auctions,1,-1 do if auctions[i].owner=='Me' then table.remove(auctions,i) end end
        addItem(60,'Heavy Hide',100,'item')
        for i=1,3 do addAuction(60,4000,1,'Rival') end
        fullScan()
        assert(S.last.own==0 and S.last.ownersKnown and next(S.last.ownUnits)==nil)
        -- after the scan the player posts 3 hides at 50s, dearer than the rival's 40s
        owned={}
        for i=1,3 do
            owned[i]={auctionID=900+i,itemKey={itemID=60},itemLink=link(60),quantity=1,buyoutAmount=5000,
                status=0,timeLeftSeconds=40000}
        end
        fire('OWNED_AUCTIONS_UPDATED')
        assert(not T.alone('i:60'), 'the 3 units of the scan are the rival\\'s')''')

    def test_own_units_of_the_scan_are_kept_with_it(self):
        run(SETUP + '''local F,S,U=ForeverFlip,ForeverFlip.Scan,ForeverFlip.Util
        fullScan()
        local sword=U.key('gear',20,'Northern Shortsword of Healing')
        assert(S.last.ownersKnown and S.last.ownUnits[sword]==1 and S.listedUnits(sword)==2)
        fire('PLAYER_LOGOUT'); S.last=nil; now=now+60
        fire('AUCTION_HOUSE_SHOW')
        assert(S.last.ownersKnown and S.last.ownUnits[sword]==1, 'restored with the saved scan')''')

    def test_a_scan_naming_no_sellers_takes_the_auction_list(self):
        run(SETUP + '''local F,S=ForeverFlip,ForeverFlip.Scan
        for _,a in ipairs(auctions) do a.owner='' end
        owned={{auctionID=9,itemKey={itemID=30},quantity=1,buyoutAmount=30000,status=0,timeLeftSeconds=7200}}
        fire('OWNED_AUCTIONS_UPDATED')
        fullScan()
        assert(not S.last.ownersKnown and S.last.own==0)
        assert(S.last.ownUnits['i:30']==1, 'the lots the player had listed when the scan was read')''')


OWN_BOUGHT = BASE + '''enableTimeLeft()
addItem(10,'Linen Cloth',0,'commodity')
local a=addAuction(10,60,20,'Seller1')
addAuction(10,70,5,'Seller2')
fullScan()
local scope=F.Engine.scope()
a.count=12; a.buyout=60*12 -- 8 of the 20 were bought
local function bought(owner, house)
    local c=F.Data.char(F.db,owner)
    c.journal[#c.journal+1]={at=now+300,kind='buy',key='c:10',name='Linen Cloth',qty=8,amount=480,scope=house}
end
'''


class OwnPurchaseTests(unittest.TestCase):
    def sold(self, purchases):
        return run(OWN_BOUGHT + purchases + '''
        now=now+921; F.db.lastScan=0; fullScan()
        local h=F.Data.market(F.db,scope).history['c:10']
        return h.sales and h.sales.sure or 0''')

    def test_purchases_at_other_houses_took_none_of_these_lots(self):
        self.assertEqual(self.sold("bought('OtherRealm-Alt')"), 8)
        self.assertEqual(self.sold("bought('Realm-Me','Realm-Neutral')"), 8)
        self.assertEqual(self.sold("bought('Realm-Me','Realm-Horde')"), 8)

    def test_purchases_at_this_house_are_no_demand(self):
        self.assertEqual(self.sold("bought('Realm-Me',scope)"), 0)
        self.assertEqual(self.sold("bought('Realm-Alt')"), 0)  # booked before houses were


class RawTests(unittest.TestCase):
    def capture(self, slice_lines):
        lua = runtime()
        lua.execute(SETUP + '''enableTimeLeft()
        local F,S=ForeverFlip,ForeverFlip.Scan
        F.db.settings.rawScans=true
        F.Raw.SLICE=%d
        for i=1,13 do addAuction(10,60+i,1) end
        assert(S.start()); fire('REPLICATE_ITEM_LIST_UPDATE')
        most=0
        while S.busy() do
            if S.job.raw then most=math.max(most,#S.job.raw) end
            run(0.05)
        end''' % slice_lines)
        s = lua.eval('ForeverFlipRaw.scans[1]')
        return lua.eval('most'), (s.count, s.seal, s.rows)

    def test_lines_are_joined_in_slices_while_read(self):
        most, sliced = self.capture(4)
        self.assertLess(most, 4)
        _, whole = self.capture(1000000)
        self.assertEqual(sliced, whole)
        self.assertEqual(sliced[0], 23)
        self.assertEqual(len(sliced[2].split('\n')), 23)

    def test_own_uploaded_scans_are_not_merged_as_community_data(self):
        lua = runtime()
        lua.execute(RAW)
        scan = ffscan.scans_from_saved_variables(saved_variables(lua))[0]
        text = ffscan.encode_summary(scan.scope, scan.at, ffscan.summarize(scan))
        lua.execute(ffscan.lua_data_file([text], time.time(), [f'{scan.scope}@{scan.at}']))
        lua.execute('ForeverFlip.Scan.last=nil')  # at login: the last scan is not restored yet
        self.assertEqual(lua.eval('ForeverFlip.Raw.importCommunity()'), 0)
        self.assertIsNone(lua.eval("ForeverFlip.Data.market(ForeverFlip.db,'Realm-Alliance').history['c:10'].shared"))


if __name__ == '__main__':
    unittest.main()
