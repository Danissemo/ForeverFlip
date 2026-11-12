import unittest

from test_addon import SETUP, run


BATCH = '''
local F=ForeverFlip
local D,T=F.Deals,F.Trade
F.Engine.autoVerify=false;F.db.settings.autoScan=false;F.db.settings.sniper=false
local keys={}
for id=101,220 do
    addItem(id,'Batch item '..id,100,'commodity');addAuction(id,60,1)
    keys[#keys+1]='c:'..id
end
local function sends()
    local n=0
    for _,c in ipairs(calls) do if c[1]=='SendSearchQuery' then n=n+1 end end
    return n
end
'''


class StatusBatchTests(unittest.TestCase):
    def test_snapshot_deduplicates_keys_and_counts_removed_deals(self):
        run(SETUP + '''fullScan();local D=ForeverFlip.Deals
        local keys={'c:10','c:10','i:30'}
        assert(D.startBatch('deals:vendor',keys,true)==2)
        keys[2]='g:20:unwanted';keys[4]='c:999'
        assert(D.startBatch('sell',{'i:30'},false)==false)
        D.remove('c:10');answer()
        local done,total,active,failed=D.batchProgress('deals:vendor')
        assert(done==1 and total==2 and active and failed==0)
        run(0.45);assert(D.search.key=='i:30');answer()
        done,total,active,failed=D.batchProgress()
        assert(done==2 and total==2 and not active and failed==0)
        assert(not D.get('i:30') and not D.pending(),'non-deal completion must still count')
        run(2);assert(not D.search,'completed batch must never refill itself')
        ''')

    def test_fast_batch_finishes_five_quick_replies_under_three_seconds(self):
        run(BATCH + '''local started=now
        assert(D.startBatch('sell',{keys[1],keys[2],keys[3],keys[4],keys[5]},false)==5)
        for i=1,5 do
            if not D.search then run(0.5) end
            assert(D.search and D.search.key==keys[i]);answer()
            assert(T.prices[keys[i]],'selling prices must refresh')
        end
        assert(now-started<3,'old one-second scheduler takes at least four seconds')
        local done,total,active,failed=D.batchProgress('sell')
        assert(done==5 and total==5 and not active and failed==0 and sends()==5)
        ''')

    def test_ready_gate_blocks_batch_and_price_check_uses_fresh_results(self):
        run(BATCH + '''throttleReady=false
        T.prices[keys[1]]={at=now,rows={{unit=999,qty=1}}}
        assert(D.startBatch('sell',{keys[1],keys[2]},false)==2)
        run(3);assert(not D.search and sends()==0)
        throttleReady=true;run(0.05);answer()
        assert(T.prices[keys[1]].rows[1].unit==60,'explicit status check cannot skip fresh cache')
        throttleReady=false;run(3);assert(not D.search and sends()==1)
        throttleReady=true;run(0.05);answer();assert(sends()==2)
        ''')

    def test_active_and_queued_manual_keys_share_batch_searches(self):
        run(BATCH + '''local callbacks=0
        T.checkPrice(keys[1],function() callbacks=callbacks+1 end)
        T.checkPrice(keys[2],function() callbacks=callbacks+1 end)
        assert(D.startBatch('sell',{keys[1],keys[2],keys[1]},false)==2)
        assert(#D.requests==1 and sends()==1)
        answer();run(0.5);answer()
        assert(sends()==2 and callbacks==2)
        local done,total,active,failed=D.batchProgress()
        assert(done==2 and total==2 and not active and failed==0)
        ''')

    def test_rolling_search_cap_holds_at_one_hundred_and_resumes(self):
        run(BATCH + '''assert(D.startBatch('sell',keys,false)==120)
        local started=now
        for i=1,100 do
            if not D.search then run(0.5) end
            assert(D.search);answer()
        end
        assert(sends()==100)
        run(1);assert(not D.search and sends()==100)
        local done,total,active=D.batchProgress();assert(done==100 and total==120 and active)
        now=started+59.95;F.Engine.update(0.05);assert(sends()==100)
        run(0.1);assert(D.search and sends()==101)
        ''')

    def test_drop_retries_wait_two_seconds_then_eventually_fail_once(self):
        run(BATCH + '''D.startBatch('sell',{keys[1],keys[2]},false)
        for attempt=1,3 do
            assert(D.search);D.onDropped()
            if attempt<3 then
                run(1.8);assert(not D.search,'dropped request keeps its two-second backoff')
                run(0.4)
            end
        end
        local done,total,active,failed=D.batchProgress()
        assert(done==1 and total==2 and active and failed==1)
        run(0.5);assert(D.search.key==keys[2]);answer()
        done,total,active,failed=D.batchProgress()
        assert(done==1 and total==2 and active and failed==0,'the dropped key gets a second try')
        run(1.1);assert(D.search and D.search.key==keys[1]);answer()
        done,total,active,failed=D.batchProgress()
        assert(done==2 and total==2 and not active and failed==0 and sends()==5)
        ''')

    def test_timeout_and_transport_exception_finish_instead_of_requeue_forever(self):
        run(BATCH + '''D.startBatch('sell',{keys[1],keys[2]},false)
        F.AH.search=function() error('transport failed') end
        run(12)
        local done,total,active,failed=D.batchProgress()
        assert(done==2 and total==2 and not active and failed==2)
        assert(not D.search and not D.pending() and #D.requests==0)
        run(12);done,total,active,failed=D.batchProgress();assert(done==2 and failed==2)
        ''')

    def test_a_long_list_gives_its_cheapest_price(self):
        run(BATCH + '''local old={at=now-100,rows={{unit=500,qty=1}}}
        T.prices[keys[1]]=old
        F.AH.rows=function() return {{unit=60,qty=1}},false end
        D.startBatch('sell',{keys[1]},false);D.search.pages=3;answer()
        local done,total,active,failed=D.batchProgress()
        assert(done==1 and total==1 and not active and failed==0,'more lots than the pages read is no failure')
        assert(T.prices[keys[1]]~=old and T.prices[keys[1]].rows[1].unit==60,'the cheapest lots are the price')''')

    def test_a_deal_check_still_needs_the_whole_list(self):
        run(BATCH + '''F.AH.rows=function() return {{unit=60,qty=1}},false end
        D.startBatch('deals:all',{keys[1]},true);D.search.pages=3;answer()
        run(1.1);D.search.pages=3;answer()
        local done,total,active,failed=D.batchProgress()
        assert(done==1 and not active and failed==1)
        ''')

    def test_deal_evaluation_error_counts_a_failure_and_releases_batch(self):
        run(BATCH + '''D.verifyCallback=function() error('evaluation failed') end
        D.startBatch('deals:all',{keys[1]},true);answer()
        run(1.1);answer() -- the second try fails the same way
        local done,total,active,failed=D.batchProgress()
        assert(done==1 and total==1 and not active and failed==1 and not D.pending())
        assert(#F.db.errors==1,'the same error is logged once')
        ''')

    def test_house_close_clears_batch_and_cannot_replay_cancelled_work(self):
        run(BATCH + '''D.startBatch('sell',{keys[1],keys[2],keys[3]},false)
        fire('AUCTION_HOUSE_CLOSED');AuctionHouseFrame:Hide()
        local done,total,active=D.batchProgress();assert(done==0 and total==0 and not active)
        assert(not D.search and #D.requests==0 and not D.pending())
        assert(D.startBatch('sell',{keys[1]},false)==false)
        AuctionHouseFrame:Show();fire('AUCTION_HOUSE_SHOW');run(3)
        assert(sends()==1 and not D.search,'reopen cannot restart cancelled batch')
        assert(D.startBatch('sell',{},false)==0)
        ''')

    def test_owned_footer_reports_active_batch_without_duplicate_queue(self):
        run(BATCH + '''owned={{auctionID=1,itemKey={itemID=101},quantity=1,buyoutAmount=60,status=0}}
        fire('OWNED_AUCTIONS_UPDATED')
        D.startBatch('auctions',{keys[1],keys[2]},false)
        assert(T.checksRemaining()==2 and T.checkOwned()==2)
        assert(not T.checkQueue or #T.checkQueue==0)
        answer();assert(T.checksRemaining()==1);run(0.5);answer()
        assert(T.checksRemaining()==0 and sends()==2)
        ''')

    def test_synchronous_answers_cannot_recurse_or_burst_all_batch_queries(self):
        run(BATCH + '''local send=F.AH.search
        F.AH.search=function(item) send(item);D.onResults(item.id) end
        assert(D.startBatch('sell',{keys[1],keys[2],keys[3]},false)==3)
        assert(sends()==1 and not D.search and #D.requests==2)
        run(0.2);assert(sends()==1)
        run(1);local done,total,active=D.batchProgress()
        assert(done==3 and total==3 and not active and sends()==3)
        ''')




class BatchRetryTests(unittest.TestCase):
    def test_an_unanswered_search_succeeds_on_the_second_try(self):
        run(BATCH + '''local oldRows=F.AH.rows
        F.AH.rows=function() error('no answer this time') end
        D.startBatch('sell',{keys[1]},false);answer()
        assert(select(3,D.batchProgress()),'still running: the second try is due')
        F.AH.rows=oldRows
        run(1.1);answer()
        local done,total,active,failed=D.batchProgress()
        assert(done==1 and total==1 and not active and failed==0)''')

    def test_a_fresh_scan_without_lots_needs_no_search(self):
        run(BATCH + '''F.Scan.notListed=function() return true end
        D.startBatch('sell',{keys[1]},false)
        local done,total,active,failed=D.batchProgress()
        assert(done==1 and not active and failed==0 and not D.search,'nobody else sells it: no search')
        assert(#T.prices[keys[1]].rows==0)''')


if __name__ == '__main__':
    unittest.main()
