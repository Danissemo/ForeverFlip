"""External Lua5.1 planner scheduling benchmark, not native WoW FPS."""
import sys
from pathlib import Path
import statistics
import time
import json
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tests'))
from test_controller import controller_runtime
l=controller_runtime();l.execute('''c.candidates={};local rows={}
for i=1,64 do rows[i]={qty=1,unit=100+i,cost=100+i}end
for i=1,2000 do c.candidates[i]={key={itemID=i},rows=rows,kind='commodity',family=false,scope='scope',at=now}end''')
t=time.perf_counter();l.execute("expected=c:recommend('balanced')");sync=(time.perf_counter()-t)*1000
t=time.perf_counter();l.execute("ForeverFlip.Planner.start(c,'balanced',nil,function(r)actual=r end)");start=(time.perf_counter()-t)*1000
times=[]
for i in range(10000):
    t=time.perf_counter();l.execute('ForeverFlip.Planner.tick(c)');times.append((time.perf_counter()-t)*1000)
    if l.eval('not c.planning'):break
l.execute('assert(actual and actual.cost==expected.cost and actual.profit==expected.profit and actual.loss==expected.loss)')
print(json.dumps(dict(candidates=2000,rows_per_candidate=64,synchronous_ms=round(sync,3),start_ms=round(start,3),
    ticks=len(times),total_ms=round(sum(times),3),median_tick_ms=round(statistics.median(times),3),max_tick_ms=round(max(times),3)),indent=2))
