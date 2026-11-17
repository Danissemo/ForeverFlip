"""The saved trace: events, searches with what held them back, Check all batches and their stalls."""

import unittest

from test_addon import SETUP, run

TRACE = SETUP + '''local F=ForeverFlip
local D,Log=F.Deals,F.Log
fullScan()
Log.clearTrace()
local function has(pattern)
    for _, line in ipairs(F.db.trace or {}) do
        if line:find(pattern) then return line end
    end
end
'''


class TraceTests(unittest.TestCase):
    def test_a_check_all_is_traced_from_start_to_end_with_its_times(self):
        run(TRACE + '''assert(D.startBatch('sell',{'c:10','i:30'},false)==2)
        for _=1,2 do
            if not D.search then run(0.5) end
            answer()
        end
        assert(has('batch%.start sell 2 items'),'batch start')
        assert(has('search%.start c:10 source manual'),'search start')
        assert(has('search%.end c:10 [%d%.]+s complete'),'search end')
        assert(has('batch%.item i:30 2/2 ok'),'item done')
        assert(has('batch%.end sell 2 items in'),'batch end')
        assert(F.db.traceStats['search.batch.s'].n==2,'search time counted')
        assert(F.db.traceStats['batch.sell.s'].n==1,'batch time counted')''')

    def test_a_stuck_batch_says_what_holds_it(self):
        run(TRACE + '''throttleReady=false
        assert(D.startBatch('sell',{'c:10','i:30'},false)==2)
        run(D.STALL_TRACE+1)
        local stall=has('batch%.stall')
        assert(stall and stall:find('sell 0/2') and stall:find('search c:10') and stall:find('queue 1 head i:30'),stall)
        answer()
        local done=has('search%.end c:10')
        assert(done and done:find('sent 1'),done)''')

    def test_the_time_a_request_is_held_is_counted_by_reason(self):
        run(TRACE + '''F.Trade.busy=function() return true end
        assert(D.enqueue('c:10',function() end))
        run(3)
        assert(has('search%.held c:10 trade_busy'),'the reason it waits')
        F.Trade.busy=function() return false end
        run(0.1);answer()
        assert(F.db.traceStats['wait.trade_busy.s'].total>=2.9,'time held counted')
        local done=has('search%.end c:10')
        assert(done and done:find('waited: trade_busy'),done)''')

    def test_slow_searches_are_kept_slowest_first(self):
        run(TRACE + '''Log.slow(6000,'c:10','a');Log.slow(9000,'i:30','b');Log.slow(7000,'c:10','c')
        local s=F.db.traceSlow
        assert(#s==3 and s[1].ms==9000 and s[3].ms==6000)
        Log.SLOW_KEEP=2;Log.slow(1000,'c:10','d');assert(#F.db.traceSlow==3,'too fast for a full list')
        Log.slow(8000,'c:10','e');assert(#F.db.traceSlow==2 and F.db.traceSlow[2].ms==8000)''')

    def test_events_and_messages_are_traced_and_repeats_counted(self):
        run(TRACE + '''F.db.settings.dev=true
        fire('AUCTION_HOUSE_THROTTLED_SYSTEM_READY')
        fire('AUCTION_HOUSE_THROTTLED_SYSTEM_READY')
        local line=has('event AUCTION_HOUSE_THROTTLED_SYSTEM_READY')
        assert(line and line:find('%(x2%)'),line)
        fire('CHAT_MSG_SYSTEM','private text')
        assert(has('event CHAT_MSG_SYSTEM') and not has('private text'),'chat text stays out')
        Log.add('scan','hello');assert(has('log%.scan hello'))''')

    def test_the_trace_is_bounded_and_can_be_turned_off(self):
        run(TRACE + '''Log.TRACE_KEEP=50
        for i=1,120 do Log.trace('x','%d',i) end
        assert(#F.db.trace<=50 and F.db.trace[#F.db.trace]:find('x 120'))
        local out=Log.traceCommand('off');assert(F.db.settings.trace==false,out[1])
        Log.trace('y');assert(not has(' y$'),'off writes nothing')
        Log.traceCommand('on');assert(F.db.settings.trace==nil)
        Log.traceCommand('clear');assert(#F.db.trace==0)''')

    def test_slash_command_shows_times_slowest_and_last_lines(self):
        run(TRACE + '''Log.stat('search.batch.s',2);Log.slow(6000,'c:10','why')
        Log.trace('hello')
        printed={}
        SlashCmdList.FOREVERFLIP('trace')
        local all=table.concat(printed,'\\n')
        assert(all:find('search%.batch%.s: 1 times') and all:find('6000 ms') and all:find('hello'),all)''')

    def test_events_wait_for_dev_mode_and_dev_traces_clicks_and_pages(self):
        run(TRACE + '''fire('AUCTION_HOUSE_THROTTLED_SYSTEM_READY')
        assert(not has('event '),'events only in DEV mode')
        printed={}
        SlashCmdList.FOREVERFLIP('dev')
        assert(F.db.settings.dev==true,'dev on');assert(table.concat(printed):find('DEV mode on'),table.concat(printed))
        fire('AUCTION_HOUSE_THROTTLED_SYSTEM_READY');assert(has('event AUCTION'))
        AuctionHouseFrame:Show(); fire('AUCTION_HOUSE_SHOW'); F.UI.show('settings:messages')
        assert(has('show settings:messages'))
        assert(F.UI.devBox:GetChecked() and F.UI.traceBox:GetChecked(),'boxes')
        F.UI.traceClearButton:Click()
        assert(has('action click Clear trace'),'a click and its time')
        F.UI.devBox:SetChecked(false);F.UI.devBox:Click()
        assert(F.db.settings.dev==nil and not F.Log.dev(),'dev off')
        F.UI.traceBox:SetChecked(false);F.UI.traceBox:Click()
        assert(F.db.settings.trace==false and not F.Log.tracing(),'trace off')
        assert(not printed[#printed+1])''')

    def test_a_slow_action_is_traced_even_without_dev(self):
        run(TRACE + '''local t=0
        Log.ms=function() return t end
        Log.action('slow thing',function() t=t+200 end)
        Log.action('quick thing',function() t=t+1 end)
        assert(has('slowaction slow thing 200 ms') and not has('quick thing'))
        assert(F.db.traceStats['slowaction.ms'].max==200)''')

    def test_a_check_whose_answer_is_lost_gives_it_up_and_finishes(self):
        run(TRACE + '''local calls=0
        assert(D.startBatch('sell',{'c:10','i:30'},function(key,complete)
            calls=calls+1
            if key=='c:10' then complete(key,{},true) end
            return true
        end)==2)
        run(D.STALL_GIVEUP-1);assert(D.batch.active,'not yet')
        run(2)
        assert(has('batch%.giveup i:30 lost'),'traced')
        run(1)
        local done,total,active=D.batchProgress('sell')
        assert(done==2 and total==2 and not active,done..' '..tostring(active))''')

    def test_a_queued_search_held_for_good_is_given_up_with_its_reason(self):
        run(TRACE + '''local hold=true
        local refuse=F.AH.ready
        F.AH.ready=function(peek) if hold then return false end return refuse(peek) end
        F.AH.available=function() return not hold end
        assert(D.startBatch('sell',{'c:10'},false)==1)
        for _=1,4 do run(D.STALL_GIVEUP/2); if D.search then answer() end end
        local line=has('batch%.giveup c:10')
        assert(line,'given up')
        assert(not D.batch.active,'the batch ended')''')

    def test_a_purchase_or_post_is_not_a_stall(self):
        run(TRACE + '''assert(D.startBatch('sell',{'i:30'},function() return true end)==1)
        F.Trade.busy=function() return true end
        run(D.STALL_GIVEUP*2)
        assert(D.batch.active and not has('batch%.giveup'),'buying holds it on purpose')
        F.Trade.busy=function() return false end
        run(D.STALL_GIVEUP+1)
        assert(not D.batch.active and has('batch%.giveup i:30 lost'))''')


if __name__ == '__main__':
    unittest.main()
