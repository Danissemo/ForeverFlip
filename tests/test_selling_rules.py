"""Posting rules, Post all, cancelling undercut auctions and the automatic duration."""

import unittest

from test_addon import SETUP, run

SELL = SETUP + '''local F=ForeverFlip
local T=F.Trade
local c=F.Data.char(F.db,F.Engine.owner())
fullScan()
'''


class RuleTests(unittest.TestCase):
    def test_percent_undercut(self):
        run(SELL + '''F.db.settings.undercutPercent=0.1
        assert(T.undercut(1000,'commodity')==900 and T.undercut(30000,'item')==27000)
        F.db.settings.undercutPercent=0;assert(T.undercut(1000,'commodity')==999)''')

    def test_rule_minimum_is_the_floor(self):
        run(SELL + '''T.setRule('i:30',{min=50000,keep=0})
        assert(T.rule('i:30').min==50000 and T.rule('i:30').keep==nil)
        assert(T.floorFor({key='i:30',kind='item'})==50000)
        T.setRule('i:30',{});assert(T.rule('i:30')==nil)''')

    def test_seller_far_above_the_maximum_is_ignored(self):
        run(SELL + '''putBag(0,1,30,1);local item=F.AH.bagItems()[1]
        T.prices['i:30']={at=now,rows={{unit=500000,qty=1}}}
        T.setRule('i:30',{normal=40000,max=60000})
        local price,_,cheapest,why=T.suggest(item)
        assert(price==40000 and why=='normal' and cheapest==500000,price)''')

    def test_hold_keeps_items_below_the_floor(self):
        run(SELL + '''F.db.settings.belowMin='hold'
        putBag(0,1,30,1);T.setRule('i:30',{min=50000})
        T.prices['i:30']={at=now,rows={{unit=30000,qty=1}}}
        local ok,why=T.postAll();assert(not ok and why=='nothing_to_post',why)
        assert(not lastCall('PostItem'))''')

    def test_post_all_posts_any_bag_item_and_respects_keep(self):
        run(SELL + '''putBag(0,1,30,1);putBag(0,2,10,20)
        T.setRule('c:10',{keep=20})
        local ok,why=T.postAll();assert(ok and why=='checking');run(1.1);answer()
        ok,why=T.postAll();assert(ok and why=='post_sent',why)
        local post=lastCall('PostItem');assert(post and post[6]==29900,post and post[6])
        assert(not lastCall('PostCommodity'),'cloth is kept in the bags')''')


class UndercutTests(unittest.TestCase):
    def test_cancel_next_undercut_auction(self):
        run(SELL + '''owned={{auctionID=5,itemKey={itemID=10},quantity=20,buyoutAmount=150,status=0,timeLeftSeconds=7200},
          {auctionID=6,itemKey={itemID=30},quantity=1,buyoutAmount=25000,status=0}}
        fire('OWNED_AUCTIONS_UPDATED');T.checkOwned();run(0.1);answer();run(1.2);answer()
        local list=T.undercutList();assert(#list==1 and list[1].auctionID==5,#list)
        assert(T.cancelNextUndercut() and lastCall('CancelAuction')[2]==5)''')

    def test_undercut_below_cost_is_not_cancelled(self):
        run(SELL + '''F.Data.addPosition(c,'c:10','Linen Cloth',20,2000,'flip',150,now)
        owned={{auctionID=5,itemKey={itemID=10},quantity=20,buyoutAmount=150,status=0}}
        fire('OWNED_AUCTIONS_UPDATED');T.checkOwned();run(0.1);answer()
        assert(#T.undercutList()==0,'reposting at 59c would lose money')''')


class DurationTests(unittest.TestCase):
    def test_auto_duration_holds_three_times_the_time_to_sell_the_queue(self):
        run(SELL + '''F.db.settings.duration=0
        local h=F.Data.market(F.db,F.Engine.scope()).history['c:10']
        h.sales={hours=24,pairs=5,at=now,b={}};F.Market.bucketAdd(h.sales.b,150,240)
        h.scan.market=150;h.units=0
        local per=F.Market.saleability(h,150,now).perDay
        local function units(hours) return math.max(1,math.floor(per*hours/24)) end
        -- nobody ahead: the time is only our units
        assert(T.durationFor('c:10',units(0.5),150)==1,'sold in 30 minutes: 2 hours hold three times that')
        assert(T.durationFor('c:10',units(2),150)==2,'sold in 2 hours: 8 hours')
        assert(T.durationFor('c:10',units(3),150)==3,'sold in 3 hours: 8 hours are not three times that')
        -- other sellers' lots at or below the price are ahead in the queue
        T.prices['c:10']={rows={{unit=140,qty=units(1)},{unit=200,qty=9999}},at=now}
        assert(T.durationFor('c:10',units(0.5),150)==2,'an hour of others ahead: not 2 hours')
        -- old or thin data: 24 hours
        T.prices['c:10']=nil;h.sales.at=now-4*3600
        assert(T.durationFor('c:10',1,150)==3,'sales older than 3 hours')
        h.sales.at=now;h.sales.pairs=1
        assert(T.durationFor('c:10',1,150)==3,'one pair of scans is too thin')
        -- the player's own sales win once 3 units were sold
        local c=F.Data.char(F.db,F.Engine.owner())
        c.stats['c:10']={sold=4,days=4*0.01,bought=4,spent=0,earned=0,profit=0}
        assert(T.durationFor('c:10',1,150)==1,'own sales: about 15 minutes each')
        F.db.settings.duration=2;assert(T.durationFor('c:10',500,150)==2,'a fixed duration stays')''')

if __name__ == '__main__':
    unittest.main()
