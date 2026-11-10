import unittest
from test_controller import controller_runtime


class AuditRadarRecovery(unittest.TestCase):
    def test_failed_search_bookkeeping_is_bounded(self):
        controller_runtime().execute('''c.radar={enabled=true,opportunities={}}
        for i=1,5001 do c.radar.current={itemID=i};ForeverFlip.Radar.failed(c)end
        local checks,retries=0,0;for _ in pairs(c.radar.checkedAt)do checks=checks+1 end
        for _ in pairs(c.radar.retryAt)do retries=retries+1 end
        assert(checks<=4000 and retries<=4000 and c.radar.checkedCount==checks)''')
    def test_snapshot_failure_does_not_starve_exact_checks(self):
        controller_runtime().execute('''db.lastReplicate=now-901;replicas=0
        api.replicate=function()replicas=replicas+1;error('temporary outage')end
        c.candidates={{key={itemID=1},rows=rows,kind='commodity',family=false,at=now,scope='scope'}}
        c:radarStart();for _=1,40 do c:tick()end
        assert(calls>0 and replicas==1,'exact checks must continue during snapshot backoff')''')
    def test_temporary_failure_retries_after_bounded_backoff(self):
        l=controller_runtime()
        l.execute('''db.lastReplicate=now
        c.candidates={{key={itemID=1},rows=rows,kind='commodity',family=false,at=now,scope='scope'}}
        c:radarStart();for _=1,20 do c:tick()end;assert(calls==1)
        now=now+21;c:tick();assert(not c.job)
        local n=calls;for _=1,20 do c:tick()end;assert(calls==n)
        now=now+61;for _=1,40 do c:tick()end;assert(calls>n)''')

    def test_discovery_rotation_does_not_starve_below_top_120(self):
        l=controller_runtime()
        l.execute('''db.lastReplicate=now;c.candidates={}
        for i=1,200 do c.candidates[i]={key={itemID=i},rows=rows,kind='commodity',family=false,at=now,scope='scope'}end
        c:radarStart();local all={}
        for cycle=1,12 do
          now=now+1
          c.radar.queue={};c.radar.index=1;c.radar.build=nil;c.job=nil;c.radar.nextAt=now;c.radar.idleInputs=nil
          for _=1,100 do c:tick();if not c.radar.build and #c.radar.queue>0 then break end end
          for _,k in ipairs(c.radar.queue)do all[k.itemID]=true end
        end
        assert(all[99],'low-ranked key must receive a discovery slot')''')

if __name__=='__main__':unittest.main()
