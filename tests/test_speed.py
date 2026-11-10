import unittest
from test_controller import controller_runtime


class SpeedTests(unittest.TestCase):
    def test_full_scan_uses_time_budget_and_never_skips_rows(self):
        controller_runtime().execute('''local seen={};clockms=0
        debugprofilestop=function()return clockms end
        api.replicate=function()end;api.replicateCount=function()return 5000 end
        api.replicateRow=function(i)seen[i]=(seen[i] or 0)+1;clockms=clockms+0.001
          return {id=1,key={itemID=1},qty=1,buyout=100,complete=true,family=false}end
        assert(c:fullScan());c:event('REPLICATE_ITEM_LIST_UPDATE');c:tick()
        assert(c.fullJob.index==3000)
        clockms=0;api.replicateRow=function(i)seen[i]=(seen[i] or 0)+1;clockms=clockms+1
          return {id=1,key={itemID=1},qty=1,buyout=100,complete=true,family=false}end
        c:tick();assert(c.fullJob.index==3049)
        for _=1,200 do if c.fullJob then clockms=0;c:tick()end end
        for i=0,4999 do assert(seen[i]==1,'row '..i)end''')

    def test_live_checks_one_listing_per_second(self):
        controller_runtime().execute('''db.lastReplicate=now;c.candidates={}
        for i=1,5 do c.candidates[i]={key={itemID=i},rows=rows,kind='commodity',family=false,at=now,scope='scope'}end
        assert(c:radarStart());for _=1,20 do c:tick()end;assert(calls==1)
        c:event('COMMODITY_SEARCH_RESULTS_UPDATED',c.job.key.itemID);now=now+1;c:tick();assert(calls==2)
        c:event('COMMODITY_SEARCH_RESULTS_UPDATED',c.job.key.itemID);now=now+1;c:tick();assert(calls==3)''')

    def test_scan_keeps_the_64_cheapest_listings_per_item(self):
        controller_runtime().execute('''local j={groups={},groupsCount=0,at=now}
        for i=1,500 do local price=((i*7919)%500)+1
          c:ingestReplica(j,{key={itemID=1},qty=1,buyout=price,family=false},now)end
        local g=j.groups['1:0:0:0'];assert(#g.rows==64 and g.depth==500)
        local units={};for _,r in ipairs(g.rows)do units[#units+1]=r.unit end;table.sort(units)
        for i=1,64 do assert(units[i]==i,'unit '..i..'='..units[i])end''')


if __name__ == '__main__':
    unittest.main()
