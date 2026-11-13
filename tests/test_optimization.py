"""Work budgets and user input responsiveness, tested against real addon modules."""

import unittest

from test_addon import SETUP, run


class LotWorkTests(unittest.TestCase):
    def test_incompatible_stacks_do_not_consume_a_quadratic_frame_budget(self):
        run('''local prev, cur = {}, {}
        for i = 1, 300 do
            prev[#prev+1]=100; prev[#prev+1]=1; prev[#prev+1]=3
            cur[#cur+1]=100; cur[#cur+1]=2; cur[#cur+1]=3
        end
        local instructions = 0
        debug.sethook(function() instructions = instructions + 100 end, '', 100)
        local sold, prices, gone, fresh = ForeverFlip.Market.trackSales(prev, cur, 900)
        debug.sethook()
        assert(sold == 300 and prices[100] == 300 and #gone == 900 and fresh['100:2'] == 300)
        assert(instructions < 200000, 'incompatible stacks used '..instructions..' Lua instructions')''')


class InputWorkTests(unittest.TestCase):
    def test_opening_the_sell_page_does_not_search_all_bag_items(self):
        run(SETUP + '''putBag(0,1,30,1); putBag(0,2,10,20)
        local F = ForeverFlip
        F.UI.show('sell')
        assert(not F.Deals.search and not F.Deals.pending(), 'rendering a page must not start a bag-wide job')''')

    def test_background_slice_shrinks_while_a_user_action_is_pending(self):
        run('''local F = ForeverFlip
        local saved, profile = debugprofilestop, 0
        debugprofilestop = function() return profile end
        F.Engine.input()
        local done = F.Share.budget(6, 400)
        profile = 3
        local exhausted = false
        for i=1,50 do exhausted = done() or exhausted end
        debugprofilestop = saved
        assert(exhausted, 'interactive work limits a background slice to two milliseconds')''')

    def test_button_feedback_is_painted_on_the_next_frame(self):
        run(SETUP + '''fullScan();local F, UI = ForeverFlip, ForeverFlip.UI
        UI.show('deals'); F.Deals.verify('c:10'); answer(); UI.selectDeal('c:10')
        F.Engine.update(0.3)
        local paints = 0; UI.refresh = function() paints = paints + 1 end
        UI.buyButton:Click()
        F.Engine.update(0.001)
        assert(paints == 1, 'a click must not wait for the normal 250ms paint interval')''')

    def test_auto_scan_does_not_start_while_a_ready_purchase_is_selected(self):
        run(SETUP + '''fullScan(); local F = ForeverFlip
        F.db.lastScan = 0; F.db.settings.autoScan = true
        F.Deals.get('c:10').verified = now
        F.UI.show('deals'); F.UI.selectDeal('c:10')
        F.Scan.auto()
        assert(not F.Scan.job, 'do not occupy the server just before the player buys')''')


class AnalyticsWorkTests(unittest.TestCase):
    def test_first_medium_history_result_is_built_between_frames(self):
        run('''local F = ForeverFlip
        local history = F.Data.market(F.db, F.Engine.scope()).history
        for i=1,1000 do history['c:'..i]={scan={at=now,market=1000}} end
        local result, pending = F.Analytics.market(now)
        assert(not result and pending, 'opening the page must not compute a medium history synchronously')
        for i=1,20 do F.Analytics.step() end
        result, pending = F.Analytics.market(now)
        assert(result and result.items==1000 and not pending, 'the local job completes between frames')''')

    def test_rankings_sort_only_the_top_fifty_and_keep_ties_deterministic(self):
        run('''local F = ForeverFlip
        local history = F.Data.market(F.db, F.Engine.scope()).history
        for i=1, 100 do
            history[string.format('c:%03d', i)] = {scan={at=now, market=1000},
                flow={hours=24, sold={i,i,i,i}, pairs=3, at=now, market=1000}}
        end
        local largest, sort = 0, table.sort
        table.sort = function(rows, ...) largest=math.max(largest,#rows); return sort(rows, ...) end
        local result = F.Analytics.market(now)
        table.sort = sort
        assert(result.items==100 and #result.liquid==50)
        assert(result.liquid[1].key=='c:100' and result.liquid[50].key=='c:051')
        assert(largest<=50, 'ranking sorted '..largest..' rows just to show fifty')
        for _, h in pairs(history) do h.flow.sold={1,1,1,1} end
        F.Analytics.invalidate(); result=F.Analytics.market(now)
        assert(result.liquid[1].key=='c:001' and result.liquid[50].key=='c:050', 'stable ties')''')


class BrowseWorkTests(unittest.TestCase):
    def test_large_sniper_reply_is_judged_in_slices_instead_of_one_event(self):
        run(SETUP + '''enableBrowse(); fullScan(); local F = ForeverFlip
        local S = F.Sniper; F.db.settings.sniper = true
        local rows = {}; for i=1,1000 do rows[i]={id=10,minPrice=150,qty=1} end
        F.AH.browseResults = function() return rows end
        F.AH.browseFull = function() return true end
        S.query={kind='browse',at=GetTime(),read=0}; S.items=0
        S.onResults(true)
        assert(S.items==0, 'the event only captures the rows')
        S.step(); assert(S.items==S.PER_FRAME, 'bounded local work on the first frame')
        for i=1,4 do S.step() end
        assert(S.items==1000, 'every captured row is processed once')''')


class RecoveryWorkTests(unittest.TestCase):
    def test_unloaded_rows_at_the_front_do_not_starve_loaded_rows_at_the_tail(self):
        run(SETUP + '''local F = ForeverFlip
        local deferred = {}; for i=1,350 do deferred[i]=i end
        local j = {state='recovering',scope=F.Engine.scope(),recoverUntil=now+30,
            deferred=deferred,groups={},order={},read=0,skipped=0,own=0}
        F.Scan.job = j
        F.AH.replicateRow = function(i)
            if i<=300 then return {id=10,complete=false} end
            return {id=30,complete=true,buyout=30000,count=1,owner='Seller',link=link(30)}
        end
        for i=1,4 do F.Scan.step() end
        assert(j.read==50, 'later loaded rows must be read exactly once despite the unloaded prefix')''')


class OwnedWorkTests(unittest.TestCase):
    def test_alone_compares_with_the_own_units_saved_with_the_scan(self):
        run('''local F = ForeverFlip; local T = F.Trade
        local reads = 0
        T.owned = {}
        local own = {}
        for i=1,150 do
            local key = 'i:'..i
            T.owned[i] = setmetatable({qty=1}, {__index=function(_, field)
                if field=='key' then reads=reads+1; return key end
            end})
            own[key] = 1
        end
        F.Scan.last = { ownersKnown=false, ownUnits=own }
        F.Scan.listedUnits = function() return 1 end
        for i=1,150 do assert(T.alone('i:'..i)) end
        assert(reads==0, 'each row read the own-auction snapshot '..reads..' times')
        T.owned = {{key='i:1',qty=2}}
        F.Scan.listedUnits = function() return 2 end
        assert(not T.alone('i:1'), 'a lot posted after the scan is not in its count')''')


if __name__ == '__main__':
    unittest.main()
