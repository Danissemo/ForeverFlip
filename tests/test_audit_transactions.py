import unittest
from test_controller import controller_runtime

class AuditTransactions(unittest.TestCase):
 def check(self,s): controller_runtime().execute(s)
 def test_invalid_imports(self):
  self.check("for _,k in ipairs({'0:0:0:0','1:1000000001:0:0'}) do local ok,v=pcall(ForeverFlip.Store.importGroup,'FFG2|Bad|'..k..'|25|1|100|10'); assert(ok and not v) end")
 def test_nested_schema_readonly(self):
  self.check("local cases={function(d)d.pending.bad={owner='owner',status='unknown',total='oops'}end,function(d)d.ledger={{kind='buy',owner='owner',scope='scope',key={},qty=1,total=1}}end,function(d)d.groups={4}end,function(d)d.markets.scope={['1:0:0:0']={samples={3}}}end}; for _,breakit in ipairs(cases)do local d=ForeverFlip.Store.open(nil);breakit(d);assert(ForeverFlip.Store.open(d)==d);assert(not ForeverFlip.Store.writable(d))end")
 def test_effective_void_owner_and_duplicates(self):
  self.check("local es={{uid='a',kind='buy',owner='owner'},{uid='a',kind='buy',owner='owner'},{uid='v',kind='void',target='a',owner='other'}}; assert(#ForeverFlip.Ledger.effective(es,'owner')==1); es[3].owner='owner';assert(#ForeverFlip.Ledger.effective(es,'owner')==0)")
 def test_full_preflight_and_pending_recovery(self):
  self.check("for i=1,10000 do db.ledger[i]={kind='expense',key='1:0:0:0',qty=1,total=0,owner='owner',scope='scope'} end; c:search({itemID=1});c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1);assert(not c:requestBuy() and quoted==0); db.pending.old={uid='old',owner='owner',scope='scope',key='1:0:0:0',id=1,qty=1,total=100,status='unknown'};assert(c:reconcile('old',true));assert(#db.ledger==10001)")
 def test_mail_multiplicity_scope_and_reload(self):
  self.check("db.listings={{owner='owner',scope='scope',name='A',key='1:0:0:0',qty=1}};local m={kind='seller',name='A',qty=1,amount=100,deposit=0,fingerprint='content',arrivalBucket=10}; c.mail={ForeverFlip.Util.copy(m),ForeverFlip.Util.copy(m)}; c:mailProposals();assert(#db.ledger==2); c=ForeverFlip.Controller.new(db,api);c.mail={m};c:mailProposals();assert(#db.ledger==2); db.listings[2]={owner='owner',scope='Neutral',name='A',key='1:0:0:0',qty=1}; m.fingerprint='new';c:mailProposals();assert(#db.ledger==2)")
 def test_restore_yields(self):
  self.check("for i=1,500 do db.markets.scope=db.markets.scope or {};db.markets.scope[i..':0:0:0']={latest={rows={{qty=1,unit=10}},at=now}} end; c:restoreCandidates();assert(#c.candidates==0 and c.restoreJob);c:tick();assert(#c.candidates<=25 and c.restoreJob)")

 def test_auctionator_age_missing_stale_and_throwing(self):
  self.check("Auctionator={API={v1={GetAuctionPriceByItemID=function()return 100 end}}}; local A=ForeverFlip.Adapters;assert(A.prices(1)[1].age==nil); Auctionator.API.v1.GetAuctionAgeByItemID=function(c,id)assert(c=='ForeverFlip' and id==1);return 2 end;assert(A.prices(1)[1].age==172800); Auctionator.API.v1.GetAuctionAgeByItemID=function()error('bad')end;assert(A.prices(1)[1].age==nil)")

 def test_native_mail_age_and_collected_money(self):
  self.check("time=function()return now end;local days=29.5;GetInboxNumItems=function()return 2 end;GetInboxInvoiceInfo=function()return 'seller','A','Buyer',100,100,0,0,0,nil,nil,1 end;local money=100;GetInboxHeaderInfo=function()return nil,nil,'AH','Sold',money,nil,days end;local a=ForeverFlip.Adapters.native(db);local first=a.mail();now=now+120;days=days-120/86400;local second=a.mail();assert(first[1].fingerprint==second[1].fingerprint and first[1].arrivalBucket==second[1].arrivalBucket);db.listings={{owner='owner',scope='scope',name='A',key='1:0:0:0',qty=1}};c.mail=first;c:mailProposals();assert(#db.ledger==2);c.mail=second;c:mailProposals();assert(#db.ledger==2);money=0;c.mail=a.mail();c:mailProposals();assert(#db.ledger==2)")
 def test_capacity_reserves_pending_and_void_budgets(self):
  self.check("db.settings.npcDailyShare=0.25;for i=1,9999 do db.ledger[i]={kind='expense',key='1:0:0:0',qty=1,total=0,owner='owner',scope='scope'}end;c.key={itemID=1};local op=c:newOperation('commodity',1,100);assert(op);assert(not ForeverFlip.Ledger.append(db,{kind='expense',key='1:0:0:0',qty=1,total=0,owner='owner',scope='scope'}));assert(not c:newOperation('commodity',1,100));db.ledger={};db.pending={};c.active=nil;c.materialRequest={first=0,owner='owner',scope='scope',itemID=1,qty=10,cost=1000,price=100};c.smallNPCActive=true;db.ui.npcTrials={owner={first=0,owner='owner'}};assert(ForeverFlip.Ledger.append(db,{uid='buy',kind='buy',owner='owner',scope='scope',key='1:0:0:0',qty=10,total=1000,at=now}));assert(ForeverFlip.Ledger.correct(db,'buy','owner',now));local o=c:options({itemID=1},'material');assert(o.materialQty==10 and o.materialBudget==1000);assert(c:npcRemaining()==25000)")
 def test_legacy_mail_receipt_is_retained_and_not_rebooked(self):
  self.check("db.ledger={{uid='mail:owner:old|minute',kind='sell',source='mail',owner='owner',scope='scope',key='1:0:0:0',qty=1,total=100}};local original=db.ledger[1];db.listings={{owner='owner',scope='scope',name='A',key='1:0:0:0',qty=1}};c.mail={{kind='seller',name='A',qty=1,amount=100,deposit=0,fingerprint='new',arrivalBucket=10}};c:mailProposals();assert(#db.ledger==1 and db.ledger[1]==original)")
