"""Read-only reproductions against the reviewed working tree; no WoW API calls.

Run with C:/FF/.tools/python/Scripts/python.exe <this file>.
BUG_REPRODUCED describes current defects, not passing production acceptance.
"""
from pathlib import Path
import json
import os
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tests"))
from test_controller import controller_runtime
from test_domain import runtime
from test_ui import ui_runtime

observations = []


def record(name, expected, actual):
    observations.append({"case": name, "expected": expected, "actual": actual,
                         "status": "BUG_REPRODUCED" if expected != actual else "NOT_REPRODUCED"})


l = controller_runtime()
l.execute("""C_AuctionHouse={};days=29.9
GetInboxNumItems=function()return 1 end
GetInboxInvoiceInfo=function()return 'seller','Cloth','Buyer',100,100,0,5,0,nil,nil,1 end
GetInboxHeaderInfo=function()return nil,nil,'AH','Sale',95,nil,days end
api.mail=ForeverFlip.Adapters.native(db).mail
db.listings={{owner='owner',scope='scope',key='1:0:0:0',name='Cloth',qty=1,price=100}}
c:event('MAIL_INBOX_UPDATE');days=days-1/1440;c:event('MAIL_INBOX_UPDATE')""")
record("one_mail_after_one_minute", 1, l.eval("#db.ledger"))

l = runtime()
l.execute("""p=ForeverFlip.Market.plan({{qty=1,unit=100,cost=100},
{qty=10,unit=1000,cost=10000},{qty=10,unit=1100,cost=11000}}, {},
{mode='flip',wallet=1000000,minROI=.25,minProfit=0,maxShare=1,maxQty=1,sellPrice=120,buyLimit=50})""")
record("explicit_buy_limit_50", False, l.eval("p.canBuy"))
observations[-1]["details"] = {k: l.globals().p[k] for k in ("cost", "target", "buyLimit")}

try:
    l.execute("""ForeverFlip.Market.plan({{qty=1,unit=100,cost=100},
    {qty=10,unit=1000,cost=10000},{qty=10,unit=1100,cost=11000}}, {},
    {mode='flip',wallet=1000000,minROI=10,minProfit=0,maxShare=1,maxQty=1,vendor=1})""")
    error = None
except Exception as exc:
    error = str(exc)
record("valid_roi_1000_percent_must_not_crash", None, error)

l = controller_runtime()
l.execute("""db.ledger={{uid='b',kind='buy',owner='owner',scope='scope',key='1:0:0:0',qty=1,total=100,at=now}}
ForeverFlip.Ledger.correct(db,'b','owner',now)
st=ForeverFlip.Stats.compute(c,now)""")
record("void_buy_statistics", 0, l.eval("st.periods[1].spent"))

l = controller_runtime()
l.execute("""for i=1,10000 do db.ledger[i]={uid='e'..i,kind='expense',owner='owner',scope='scope',key='2:0:0:0',qty=1,total=0,at=now} end
c:search({itemID=1});c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
c:requestBuy();c:event('COMMODITY_PRICE_UPDATED',100,1000);c:confirmBuy()
uid=c.active and c.active.uid
c:event('COMMODITY_PURCHASED',1,10)
reconciled=c:reconcile(uid,true)""")
record("full_ledger_must_block_spend", 0, l.eval("spent"))
observations[-1]["details"] = {"ledger_entries": l.eval("#db.ledger"),
                                "reconciliation_succeeded": l.globals().reconciled}

l = controller_runtime()
l.execute("""db.listings={{owner='owner',scope='scope',key='1:0:0:0',name='Cloth',qty=1,price=100}}
api.mail=function()return {
{index=1,kind='seller',name='Cloth',qty=1,amount=95,deposit=0,fingerprint='same'},
{index=2,kind='seller',name='Cloth',qty=1,amount=95,deposit=0,fingerprint='same'}}end
c:event('MAIL_INBOX_UPDATE')""")
record("two_identical_distinct_sale_invoices", 2, l.eval("#db.ledger"))

l = runtime()
for key in ("0:0:0:0", "1:1000000001:0:0"):
    try:
        l.globals().ForeverFlip.Store.importGroup("FFG2|Bad|" + key + "|25|1|100|10")
        error = None
    except Exception as exc:
        error = str(exc)
    record("invalid_group_key_" + key, None, error)

l = runtime()
l.execute("""price=ForeverFlip.Market.salePrice({minimum=1200,avgBuy=1000,feeRate=.05,reserveRate=0,minFee=500})
net=price-ForeverFlip.Market.fee(price,.05,500)-1000""")
record("suggested_sale_protects_cost_with_minimum_fee", True, l.eval("net>=0"))
observations[-1]["details"] = {"price": l.globals().price, "net_profit": l.globals().net}

l = ui_runtime()
l.execute("""c.candidates={{key={itemID=1},rows={{qty=1,unit=900,cost=900,auctionID=8}},at=now,scope='scope'}}
c.owned={{auctionID=9,key={itemID=1},qty=1,buyout=1000}};c.ownedAt=now
u:show('portfolio','auctions');advice=u.ownedRows[1].advice:GetText()
c.plan={key={itemID=1},complete=true,scope='scope',at=now,kind='commodity'}
accepted=c:post({key={itemID=1},qty=1},1,899,2)""")
record("owned_undercut_advice_899_is_postable", True, l.globals().accepted)
observations[-1]["details"] = {"advice": l.globals().advice, "controller_message": l.eval("c.message")}

l = controller_runtime()
l.execute("""db.markets.scope={};local rows={}
for j=1,64 do rows[j]={qty=1,unit=100+j,cost=100+j}end
for i=1,2000 do db.markets.scope[i..':0:0:0']={latest={at=now,family=false,rows=rows}}end""")
times = []
for _ in range(5):
    l.execute("c.candidates={}")
    start = time.perf_counter()
    restored = l.eval("c:restoreCandidates()")
    times.append(round((time.perf_counter() - start) * 1000, 3))
observations.append({"case": "synchronous_restore", "restored": restored, "ms": times,
                     "status": "MEASURED_EXTERNAL_LUA_NOT_NATIVE_FPS"})
workspace = ROOT.parent.parent
observations.append({"case": "register_skill_source_equals_destination",
                     "same_file": os.path.samefile(workspace / "setup/skills/wow-forever-addons/SKILL.md",
                     Path.home() / ".codex/skills/wow-forever-addons/SKILL.md"),
                     "status": "READ_ONLY_SETUP_PRECONDITION"})
print(json.dumps(observations, ensure_ascii=True, indent=2))
