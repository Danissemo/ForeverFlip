"""Checking the bags: every row gets a price, and items nobody sells do not hold the check up.

A bag item without a usual price of the last scan takes the item's older market data (its days,
its sales between scans, the prices buyers paid), then the usual price of other versions of the
item. A merchant price is the best way while the auction house has only a guess. A full scan
restored after a reload still tells which items nobody sells (Scan.notListed with an age)."""

import unittest

from test_addon import SETUP, run

BASE = SETUP + '''local F=ForeverFlip
local T,S=F.Trade,F.Scan
local history=F.Data.market(F.db,F.Engine.scope()).history
'''


class HistoryPriceTests(unittest.TestCase):
    def test_days_then_flow_then_sales(self):
        run(BASE + '''local h={days={{d=1,m=500},{d=2,m=700}},flow={market=900},
            sales={b={0,3,100,1,300,5,200}}}
        assert(T.historyPrice(h)==700,'the newest day first')
        h.days=nil;assert(T.historyPrice(h)==900,'then the sales between scans')
        h.flow=nil;assert(T.historyPrice(h)==200,'then the median unit sold: '..tostring(T.historyPrice(h)))
        assert(T.historyPrice({})==nil and T.historyPrice(nil)==nil)''')


class FallbackTests(unittest.TestCase):
    def test_the_items_history_and_then_its_other_versions(self):
        run(BASE + '''history['i:30']={days={{d=1,m=4000}}}
        local p,why=T.fallbackPrice({key='i:30',id=30,kind='item'})
        assert(p==4000 and why=='history',tostring(why))
        history['i:30']=nil
        history['i:30:1']={scan={at=now,market=6000}}
        history['i:30:2']={scan={at=now,market=8000}}
        history['i:30:3']={scan={at=now,market=9000}}
        local q,how=T.fallbackPrice({key='i:30',id=30,kind='item'})
        assert(q==8000 and how=='similar',tostring(q)..' '..tostring(how))''')

    def test_a_row_without_an_auction_price_still_shows_a_route_and_profit(self):
        run(BASE + '''putBag(0,1,30,1);F.UI.show('sell')
        assert(T.bestWay('i:30',30)=='unknown','the merchant list never acts on a guess')
        local r;for _,x in ipairs(F.UI.sellTable.rows) do if x.key=='i:30' and x:IsShown() then r=x end end
        assert(r and r.cols[2]:GetText():find('?',1,true),'a greyed likely route: '..tostring(r and r.cols[2]:GetText()))
        assert(r.cols[3]:GetText()~='-','a guessed profit: '..r.cols[3]:GetText())''')


class NotListedTests(unittest.TestCase):
    def test_a_restored_scan_tells_with_an_age(self):
        run(BASE + '''fullScan()
        local at=S.last.at
        S.last.listed=nil -- restored after a reload: no list of what it saw
        history['c:10']={scan={at=at,market=100}}
        assert(not S.notListed('i:70'),'without an age the old rule: the scan cannot tell')
        assert(S.notListed('i:70',7200),'not in the scan: nobody sells it')
        assert(not S.notListed('c:10',7200),'seen by the scan')
        now=now+7300;assert(not S.notListed('i:70',7200),'too old to tell')''')


if __name__ == "__main__":
    unittest.main()
