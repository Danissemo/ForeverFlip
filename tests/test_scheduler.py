import unittest

from test_addon import SETUP, SNIPE, run


BACKGROUND = SNIPE + '''
ForeverFlip.db.settings.sniper=false;fullScan()
ForeverFlip.db.settings.sniper=true;ForeverFlip.db.settings.autoVerify=true
run(1.1)
assert(ForeverFlip.Deals.search.key=='c:40')
'''


class SchedulerTests(unittest.TestCase):
    def test_manual_sell_check_goes_before_the_sniper(self):
        run(BACKGROUND + '''local D,T=ForeverFlip.Deals,ForeverFlip.Trade
        assert(T.checkPrice('c:10'),'busy manual check must be accepted')
        assert(D.pending('c:10') and D.search.key=='c:40','the sent sniper query retains its answer')
        answer();run(1.1)
        assert(D.search.key=='c:10' and D.search.source=='manual')
        answer();assert(T.prices['c:10'] and not D.pending('c:10'))''')

    def test_owned_checks_drain_before_more_background_searches(self):
        run(BACKGROUND + '''local D,T=ForeverFlip.Deals,ForeverFlip.Trade
        owned={{auctionID=1,itemKey={itemID=10},quantity=1,buyoutAmount=150,status=0},
          {auctionID=2,itemKey={itemID=40},quantity=1,buyoutAmount=400,status=0}}
        fire('OWNED_AUCTIONS_UPDATED');assert(T.checkOwned()==2)
        answer();run(1.1);assert(D.search.key=='c:10');answer()
        run(1.1);assert(D.search.key=='c:40' and D.search.source=='manual');answer()
        assert(#T.checkQueue==0 and T.prices['c:10'] and T.prices['c:40'])''')

    def test_dropped_sniper_cannot_replace_manual_verification(self):
        run(BACKGROUND + '''local D=ForeverFlip.Deals;local replies=0
        D.verify('c:10',function() replies=replies+1 end)
        fire('AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED');run(2.2)
        assert(D.search.key=='c:10','foreground must win over a dropped sniper')
        answer();assert(replies==1 and not D.pending('c:10'))''')

    def test_manual_requests_remain_fifo_and_duplicate_callbacks_run_once(self):
        run(SETUP + '''fullScan();local D=ForeverFlip.Deals;throttleReady=false
        local first,second,order=0,0,{}
        local callback=function() first=first+1;order[#order+1]='first' end
        D.verify('c:10',callback);D.verify('c:10',callback)
        D.verify('i:30',function() second=second+1;order[#order+1]='second' end)
        assert(D.pending('c:10') and D.pending('i:30') and not D.search)
        throttleReady=true;run(0.1);assert(D.search.key=='c:10');answer()
        assert(not D.search,'no burst: the next search waits a moment')
        run(0.25);assert(D.search.key=='i:30');answer()
        assert(first==1 and second==1 and table.concat(order,',')=='first,second')''')

    def test_multiple_callbacks_share_one_active_manual_query(self):
        run(SETUP + '''fullScan();local D=ForeverFlip.Deals;local a,b=0,0
        D.verify('c:10',function() a=a+1 end)
        local before=#calls;D.verify('c:10',function() b=b+1 end)
        assert(#calls==before);answer();fire('COMMODITY_SEARCH_RESULTS_UPDATED',10)
        assert(a==1 and b==1 and not D.pending('c:10'))''')

    def test_switch_off_keeps_inflight_work_and_suppresses_sniper_retry(self):
        run(BACKGROUND + '''local D,T=ForeverFlip.Deals,ForeverFlip.Trade
        T.checkPrice('c:10');D.setSniper(false)
        assert(not ForeverFlip.db.settings.sniper and D.search.key=='c:40','an already sent query is drained')
        answer();run(1.1)
        assert(D.search.key=='c:10');answer();run(3)
        assert(not D.search and T.prices['c:10'],'manual work survives switching sniper off')''')

    def test_switch_off_discards_an_already_scheduled_sniper_retry(self):
        run(BACKGROUND + '''local D=ForeverFlip.Deals
        fire('AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED');D.setSniper(false)
        run(3);assert(not D.search and not (D.requests[1] or D.backgroundRetry))''')

    def test_manual_check_promotes_matching_background_retry_without_duplicate_query(self):
        run(BACKGROUND + '''local D,T=ForeverFlip.Deals,ForeverFlip.Trade
        fire('AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED');T.checkPrice('c:40')
        assert(D.pending('c:40'));ForeverFlip.Scan.hot={};run(2.2)
        assert(D.search.key=='c:40' and D.search.source=='manual');answer()
        run(1.1)
        assert(T.prices['c:40'] and not D.search and not (D.requests[1] or D.backgroundRetry))''')

    def test_sniper_switch_works_without_automatic_deal_verification(self):
        run(SNIPE + '''ForeverFlip.db.settings.sniper=false;fullScan()
        ForeverFlip.Deals.setSniper(true);run(1.1)
        assert(not ForeverFlip.db.settings.autoVerify and ForeverFlip.Deals.search.key=='c:40')''')

    def test_house_close_clears_manual_queue_and_finishes_callbacks_once(self):
        run(SETUP + '''fullScan();local D=ForeverFlip.Deals;local a,b=0,0
        D.verify('c:10',function() a=a+1 end)
        D.verify('i:30',function() b=b+1 end)
        fire('AUCTION_HOUSE_CLOSED')
        assert(not D.search and not (D.requests[1] or D.backgroundRetry) and not D.pending('i:30'))
        assert(a==1 and b==1);fire('COMMODITY_SEARCH_RESULTS_UPDATED',10)
        run(2);assert(a==1 and b==1 and not D.search)''')

    def test_timeout_releases_manual_queue_and_ignores_old_other_item_reply(self):
        run(SETUP + '''fullScan();local D=ForeverFlip.Deals;local failed,done=0,0
        D.verify('c:10',function(d,why) if not d and why=='search_failed' then failed=failed+1 end end)
        D.verify('i:30',function() done=done+1 end)
        run(12);assert(failed==1 and D.search.key=='i:30')
        fire('COMMODITY_SEARCH_RESULTS_UPDATED',10)
        assert(done==0 and D.search.key=='i:30');answer();assert(done==1)''')

    def test_sync_results_are_not_lost_or_replaced_by_outer_request(self):
        run(SETUP + '''fullScan();local D=ForeverFlip.Deals;local replies=0
        local send=ForeverFlip.AH.search
        ForeverFlip.AH.search=function(item) send(item);D.onResults(item.id) end
        assert(D.verify('c:10',function(d) assert(d and d.verified);replies=replies+1 end))
        assert(replies==1 and not D.search and D.get('c:10').verified)''')

    def test_manual_requests_go_during_a_full_scan_but_wait_for_a_purchase(self):
        run(SETUP + '''local D,T=ForeverFlip.Deals,ForeverFlip.Trade
        assert(ForeverFlip.Scan.start());T.checkPrice('c:10',function() end,true)
        assert(not D.search and D.pending('c:10'),'Check all waits for the scan')
        ForeverFlip.Engine.input();T.checkPrice('i:30') -- the click
        assert(D.search and D.search.key=='i:30','a click goes during the scan');answer()
        assert(T.prices['i:30'])
        T.op={state='quote',at=now};T.checkPrice('i:30')
        run(1);assert(not (D.search and D.search.key=='i:30') and D.pending('i:30'),'waits for the purchase')
        T.op=nil;for _=1,30 do if D.search and D.search.key=='i:30' then break end;if D.search then answer() end;run(0.1) end
        assert(D.search and D.search.key=='i:30')''')

    def test_fresh_selected_deal_keeps_buy_available_for_a_moment(self):
        run(SETUP + '''fullScan();local D,T=ForeverFlip.Deals,ForeverFlip.Trade
        local UI=ForeverFlip.UI;UI.selected='c:10';D.verify('c:10');answer()
        ForeverFlip.db.settings.autoVerify=true;ForeverFlip.db.settings.sniper=true
        run(2);assert(not D.search and T.canBuy(D.get('c:10')),'background must leave time to click Buy')
        run(D.SELECTED_HOLD);assert(D.search,'background resumes: a deal only looked at does not stop it')''')

    def test_replace_keeps_pending_foreground_requests(self):
        run(SETUP + '''fullScan();local D=ForeverFlip.Deals;throttleReady=false
        D.verify('c:10');D.replace(D.list,D.scope);throttleReady=true
        run(0.1);assert(D.search.key=='c:10');answer();assert(D.get('c:10').verified)''')


if __name__ == '__main__':
    unittest.main()
