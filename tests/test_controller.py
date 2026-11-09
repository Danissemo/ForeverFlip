import unittest
from test_domain import runtime, ROOT

def controller_runtime():
    lua=runtime()
    for name in ['Adapters','Controller','Radar','DealCache']:
        file=ROOT/'ForeverFlip'/(name+'.lua')
        assert file.exists(), 'Missing controller module: '+name
        lua.execute(file.read_text(encoding='utf-8-sig'))
    lua.execute('''now=1000000; spent=0; quoted=0; calls=0; open=true; full=true
    rows={{qty=10,unit=100,cost=1000,auctionID=123}}
    api={clock=function() return now end,wallet=function() return 100000 end,
    owner=function() return 'owner' end,scope=function() return 'scope' end,
    isOpen=function() return open end,ready=function() return true end,
    search=function() calls=calls+1 end,
    rows=function() return rows,full,'commodity' end,
    quote=function() quoted=quoted+1 end,confirm=function() spent=spent+1 end,
    cancelQuote=function() end,buyItem=function() spent=spent+1 end,
    vendor=function() return 1000 end,quoteRemaining=function() return 20 end}
    db=ForeverFlip.Store.open(nil); db.settings.minProfit=0; db.settings.maxQty=10
    c=ForeverFlip.Controller.new(db,api); c.mode='vendor'
    ''')
    return lua

class ControllerTests(unittest.TestCase):
    def check_lua(self,body): controller_runtime().execute(body)
    def test_partial_cannot_buy(self):
        self.check_lua('''assert(c:search({itemID=1})); full=false; c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        assert(not c:requestBuy() and quoted==0 and spent==0)''')
    def test_foreign_search_result_ignored(self):
        self.check_lua('''c:search({itemID=1}); c:event('COMMODITY_SEARCH_RESULTS_UPDATED',2)
        assert(not c.plan and not c:requestBuy())''')
    def test_separate_quote_confirmation_and_deduplicated_receipt(self):
        self.check_lua('''c:search({itemID=1}); c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1)
        assert(c:requestBuy() and spent==0 and quoted==1)
        c:event('COMMODITY_PRICE_UPDATED',100,1000); assert(spent==0)
        assert(c:confirmBuy() and spent==1)
        c:event('COMMODITY_PURCHASED',1,10); c:event('COMMODITY_PURCHASED',1,10)
        assert(#db.ledger==1 and db.ledger[1].total==1000)''')
    def test_price_increase_cancels_quote(self):
        self.check_lua('''c:search({itemID=1}); c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1); c:requestBuy()
        c:event('COMMODITY_PRICE_UPDATED',120,1200); assert(not c:confirmBuy() and spent==0)''')
    def test_close_after_quote_never_buys(self):
        self.check_lua('''c:search({itemID=1}); c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1); c:requestBuy()
        c:event('COMMODITY_PRICE_UPDATED',100,1000); open=false; c:event('AUCTION_HOUSE_CLOSED')
        assert(not c:confirmBuy() and spent==0)''')
    def test_timeout_preserves_unknown_reservation_after_reload(self):
        self.check_lua('''c:search({itemID=1}); c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1); c:requestBuy()
        c:event('COMMODITY_PRICE_UPDATED',100,1000); c:confirmBuy(); now=now+100; c:tick()
        assert(c:reserved()==1000); local d=ForeverFlip.Controller.new(db,api)
        assert(d:reserved()==1000 and not d:requestBuy())''')
    def test_wrong_purchase_does_not_enter_ledger(self):
        self.check_lua('''c:search({itemID=1}); c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1); c:requestBuy()
        c:event('COMMODITY_PRICE_UPDATED',100,1000); c:confirmBuy()
        c:event('COMMODITY_PURCHASED',2,10); assert(#db.ledger==0 and c:reserved()==1000)''')
    def test_stale_plan_blocked(self):
        self.check_lua('''c:search({itemID=1}); c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1); now=now+31
        assert(not c:requestBuy() and quoted==0)''')
    def test_readonly_future_schema_no_search(self):
        self.check_lua('''local d=ForeverFlip.Controller.new({schemaVersion=99},api)
        assert(not d:search({itemID=1}) and calls==0)''')
    def test_throttle_does_not_send_search(self):
        self.check_lua('''api.ready=function() return false end; assert(not c:search({itemID=1})); assert(calls==0)''')
    def test_watch_stops_at_ten_minutes(self):
        self.check_lua('''db.watchlist={1}; c:watchStart(); now=now+601; c:tick(); assert(not c.watching)''')
    def test_full_scan_chunked_for_100000_rows(self):
        self.check_lua('''api.replicate=function() calls=calls+1 end
        api.replicateCount=function() return 100000 end
        api.replicateRow=function(i) return {id=i%100+1,qty=1,buyout=100,key={itemID=i%100+1},complete=true} end
        assert(c:fullScan()); c:event('REPLICATE_ITEM_LIST_UPDATE'); c:tick()
        assert(c.fullJob and c.fullJob.index<100000)
        for i=1,600 do c:tick() end
        assert(not c.fullJob and #c.candidates==100 and spent==0)''')

if __name__=='__main__': unittest.main()
