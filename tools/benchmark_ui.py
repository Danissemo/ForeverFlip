"""Synthetic Lua5.1 UI cost; this is not an in-client FPS measurement."""
import json
from pathlib import Path
import statistics
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tests'))
from test_ui import ui_runtime

l=ui_runtime()
l.execute('''c.candidates={};local book={};for i=1,64 do book[i]={qty=1,unit=100+i,cost=100+i}end
for i=1,2000 do c.candidates[i]={key={itemID=i},rows=book,kind='commodity',family=false,scope='scope',at=now}end
plans=0;metadata=0;info=0;local p=ForeverFlip.Market.plan
ForeverFlip.Market.plan=function(...)plans=plans+1;return p(...)end
local d=ForeverFlip.ItemDisplay.metadata
ForeverFlip.ItemDisplay.metadata=function(...)metadata=metadata+1;return d(...)end
local g=GetItemInfo;GetItemInfo=function(...)info=info+1;return g(...)end''')

def measure(code):
    l.execute('plans=0;metadata=0;info=0')
    start=time.perf_counter();l.execute(code)
    return dict(ms=round((time.perf_counter()-start)*1000,3),
                plans=l.eval('plans'),metadata=l.eval('metadata'),item_info=l.eval('info'))

result={'candidates':2000,'rows_per_candidate':64,'cold_open':measure("u:show('deals')")}
steps=[]
for i in range(2500):
    start=time.perf_counter();l.execute('ForeverFlip.DealCache.tick(c)')
    steps.append((time.perf_counter()-start)*1000)
    if l.eval('not c.dealCache.job'): break
result['preparation']=dict(updates=len(steps),total_ms=round(sum(steps),3),
    median_ms=round(statistics.median(steps),3),max_ms=round(max(steps),3))
result['first_paint']=measure('u:refresh()')
result['warm_open']=measure("u:show('deals')")
result['refresh']=measure('u:refresh()')
print(json.dumps(result,indent=2))
