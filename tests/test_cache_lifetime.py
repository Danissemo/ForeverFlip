"""Retention boundaries for shared history and scan/analytics caches."""

import unittest

from test_addon import SETUP, run


class CacheLifetimeTests(unittest.TestCase):
    def test_historical_only_shared_item_survives_scan_tidy_then_expires(self):
        run(SETUP + '''local F=ForeverFlip;local S=F.Share
        local snap=S.decode('FF3|'..F.Engine.scope()..'|'..S.enc(now-600)..'|c:99,0,0,0,1.2s.2s.a.1')
        assert(S.merge(snap,'Friend','import')==1)
        local history=F.Data.market(F.db,F.Engine.scope()).history
        local h=history['c:99'];assert(h and not h.scan and not h.shared)
        fullScan()
        assert(history['c:99']==h,'a current historical day survives scan tidy')
        assert(F.Scan.stale(h,now+15*86400),'history still expires after its retention window')''')

    def test_scan_groups_release_after_consumers_expire(self):
        run(SETUP + '''fullScan();local F=ForeverFlip;local last=F.Scan.last
        local listed,history=last.listed,F.Data.market(F.db,last.scope).history
        last.checkedGroups={['c:10']=last.groups['c:10']}
        local groups=last.groups
        now=last.at+300;F.Scan.step()
        assert(last.groups==groups and F.Trade.scanPrice('c:10'),'300-second boundary is usable')
        now=last.at+301;F.Scan.step()
        assert(not last.groups and not last.checkedGroups,'expired listing copies are released')
        assert(last.listed==listed and history['c:10'],'summary counts and market history remain')''')

    def test_market_cache_refreshes_time_dependent_timing(self):
        run('''local F=ForeverFlip;local M=F.Market
        local h={scan={at=now,market=1000},flow={hours=24,sold={2,2,2,2},pairs=3,at=now,market=1000},
          t={w={1,1,1,1,1,1,1},wn={1,1,1,1,1,1,1},p={0.8,1,1.2,1},pn={2,2,2,2}}}
        F.Data.market(F.db,F.Engine.scope()).history['c:10']=h
        local first=F.Analytics.market(now)
        assert(F.Analytics.market(now+1)==first,'same-minute reads reuse the cache')
        local later=F.Analytics.market(now+6*3600)
        assert(later.liquid[1].timing.now==M.timing(h,now+6*3600).now,'timing follows current time')
        assert(later.liquid[1].timing.now~=first.liquid[1].timing.now,'a new timing slot is recalculated')''')


if __name__ == '__main__':
    unittest.main()
