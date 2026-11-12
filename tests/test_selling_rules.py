"""Posting rules, Post all, cancelling undercut auctions and the automatic duration."""

import unittest

from test_addon import SETUP, run

SELL = SETUP + '''local F=ForeverFlip
local T=F.Trade
local c=F.Data.char(F.db,F.Engine.owner())
fullScan()
F.Scan.last.groups=nil -- these tests read prices by search (T.scanPrice is tested on its own)
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
    AUTO = SELL + """F.db.settings.duration=0
    local h=F.Data.market(F.db,F.Engine.scope()).history['c:10']
    h.sales={hours=24,pairs=5,at=now,b={}};F.Market.bucketAdd(h.sales.b,150,240)
    h.scan.market=150;h.units=0
    local per=F.Market.saleability(h,150,now).perDay
    local function units(hours) return math.max(1,math.floor(per*hours/24)) end
    """

    def test_equal_deposits_post_for_24_hours(self):
        run(self.AUTO + """-- the game asks the same 1 silver for every duration (as on WoW Forever)
        F.AH.resetDeposits();C_AuctionHouse.CalculateCommodityDeposit=function() return 100 end
        assert(T.durationFor('c:10',units(0.5),150)==3,'sold in 30 minutes, same deposit: 24 hours')
        assert(T.durationFor('c:10',units(20),150)==3)""")

    def test_the_deposit_comes_back_with_a_sale_so_24_hours_win(self):
        run(self.AUTO + """-- 2 h costs 1g, 8 h 2g, 24 h 4g per stack (the usual multiples): per hour 24 h is cheapest,
        -- and a lot that sells gets its deposit back whatever the duration
        F.AH.resetDeposits();C_AuctionHouse.CalculateCommodityDeposit=function(_,d,q) return ({10000,20000,40000})[d] end
        assert(T.durationFor('c:10',units(0.5),150)==3,'sells in 30 minutes: nothing is lost either way')
        assert(T.durationFor('c:10',units(20),150)==3,'sells in 20 hours: 24 hours lose the least')
        local costs=T.durationCosts('c:10',units(20),150)
        assert(costs[3]<costs[2] and costs[2]<costs[1],costs[1]..' '..costs[2]..' '..costs[3])""")

    def test_a_far_dearer_long_post_is_avoided_for_slow_items(self):
        run(self.AUTO + """-- a house that asks 1s for 2 and 8 hours but 10g for 24 hours
        F.AH.resetDeposits();C_AuctionHouse.CalculateCommodityDeposit=function(_,d) return ({100,100,100000})[d] end
        assert(T.durationFor('c:10',units(20),150)==2,'slow item: 8 hours, the 24-hour deposit would be lost')
        assert(T.durationFor('c:10',units(0.5),150)==3,'fast item: it sells, the deposit comes back')""")

    def test_unknown_sales_and_fixed_setting(self):
        run(self.AUTO + """F.AH.resetDeposits();C_AuctionHouse.CalculateCommodityDeposit=function(_,d) return ({100,200,400})[d] end
        h.sales.at=now-4*3600
        assert(T.durationFor('c:10',1,150)==3,'sales older than 3 hours: 24 hours')
        h.sales.at=now;h.sales.pairs=1
        assert(T.durationFor('c:10',1,150)==3,'one pair of scans is too thin')
        F.db.settings.duration=2;assert(T.durationFor('c:10',500,150)==2,'a fixed duration stays')""")

    def test_own_sales_decide_once_three_were_sold(self):
        run(self.AUTO + """F.AH.resetDeposits();C_AuctionHouse.CalculateCommodityDeposit=function(_,d) return ({100,100,100000})[d] end
        local c=F.Data.char(F.db,F.Engine.owner())
        c.stats['c:10']={sold=4,days=4*2,bought=4,spent=0,earned=0,profit=0} -- two days per unit
        assert(T.expectedHours('c:10',1,150)==48,'own sales: two days each')
        assert(T.durationFor('c:10',1,150)==2,'slow by own sales, dear 24 hours: 8 hours')""")


if __name__ == '__main__':
    unittest.main()
