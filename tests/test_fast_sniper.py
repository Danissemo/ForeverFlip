"""Fast sniper: browse rounds over the whole house, key batches and exact checks of candidates."""

import unittest

from test_addon import SETUP, runtime

FAST = SETUP + '''
enableBrowse(2)
fullScan()
ForeverFlip.db.settings.autoVerify=false;ForeverFlip.db.settings.sniper=true
local Sn,D=ForeverFlip.Sniper,ForeverFlip.Deals
D.list={}
'''


class FastSniperTests(unittest.TestCase):
    def test_quick_scan_reads_one_round_checks_its_candidates_and_ends(self):
        lua = runtime()
        lua.execute(FAST + '''
        ForeverFlip.db.settings.sniper=false
        assert(not Sn.active() and ForeverFlip.Scan.cooldown()>0,'full scan waits')
        assert(Sn.canQuick() and Sn.startQuick() and Sn.active())
        assert(not Sn.canQuick(),'one at a time')
        run(0.1);assert(lastCall('SendBrowseQuery'),'the browse starts')
        local guard=0
        while Sn.quick do
            if D.searching() then answer() elseif browsePendingNow() then browseAnswer() end
            run(0.5);guard=guard+1;assert(guard<300,'quick scan never ended')
        end
        assert(Sn.rounds==1,'one round only')
        assert(ForeverFlip.Engine.message=='quick_done',ForeverFlip.Engine.message)
        assert(D.get('c:10') and D.get('c:10').verified,'its candidate was checked')
        assert(Sn.low(10) and Sn.low(10).price==60,'the lowest price is kept')
        assert(Sn.lastQuick and Sn.lastQuick.items>=3)
        run(30);assert(Sn.rounds==1 and not Sn.active(),'no further rounds')''')

    def test_quick_scan_checks_its_candidates_on_a_house_without_a_saved_scan(self):
        lua = runtime()
        lua.execute(FAST + '''
        ForeverFlip.db.settings.sniper=false
        D.scope=nil
        assert(Sn.startQuick())
        local guard=0
        while Sn.quick do
            if D.searching() then answer() elseif browsePendingNow() then browseAnswer() end
            run(0.5);guard=guard+1;assert(guard<300,'quick scan never ended')
        end
        assert(ForeverFlip.Engine.message=='quick_done',ForeverFlip.Engine.message)''')

    def test_quick_scan_reads_every_page_before_checking_and_reads_each_row_once(self):
        lua = runtime()
        lua.execute(FAST + '''
        ForeverFlip.db.settings.sniper=false
        local get, reads = C_AuctionHouse.GetBrowseResults, 0
        C_AuctionHouse.GetBrowseResults = function() reads = reads + 1 return get() end
        assert(Sn.startQuick())
        local searchedEarly, guard = false, 0
        while Sn.quick do
            if D.searching() then
                if not Sn.quick.done then searchedEarly = true end
                answer()
            elseif browsePendingNow() then browseAnswer() end
            run(0.5);guard=guard+1;assert(guard<300,'quick scan never ended')
        end
        assert(not searchedEarly, 'no exact check before the last page')
        assert(ForeverFlip.Engine.message=='quick_done',ForeverFlip.Engine.message)
        assert(D.get('c:10') and D.get('c:10').verified,'its candidate was checked')
        assert(reads == 1, 'the whole list read once, at the first page: ' .. reads)''')

    def test_quick_scan_lists_its_finds_before_the_house_is_read(self):
        lua = runtime()
        lua.execute(FAST + '''
        local F, UI = ForeverFlip, ForeverFlip.UI
        F.db.settings.sniper=false
        assert(Sn.startQuick())
        local listedEarly, statusEarly, guard = false, nil, 0
        while Sn.quick do
            local d = D.get('c:10')
            if d and d.quick and not Sn.quick.done and not listedEarly then
                listedEarly = true
                UI.show('deals'); UI.refresh()
                for _, r in ipairs(UI.dealTable.rows) do
                    if r:IsShown() and r.key == 'c:10' then statusEarly = r.cols[7]:GetText() end
                end
                assert(not D.searching(), 'listed without a search')
            end
            if D.searching() then answer() elseif browsePendingNow() then browseAnswer() end
            run(0.5);guard=guard+1;assert(guard<300,'quick scan never ended')
        end
        assert(listedEarly, 'the find is in Deals while the house is still read')
        assert(statusEarly and statusEarly:find('from quick scan'), tostring(statusEarly))
        local d = D.get('c:10')
        assert(d and d.verified and not d.quick, 'its check replaced the unchecked row')''')

    def test_quick_scan_lists_one_row_for_all_endings_of_one_gear_item(self):
        lua = runtime()
        lua.execute('''addItem(80,'Giant Club',1,'gear')''' + FAST + '''
        local F = ForeverFlip
        F.db.settings.sniper=false
        local endings = { 'g:80:giant club of the bear', 'g:80:giant club of the monkey', 'g:80:giant club of the tiger' }
        for _, key in ipairs(endings) do F.Shopping.add(key, 100000, 1, 'Giant Club') end
        assert(Sn.startQuick())
        local found = Sn.found
        Sn.read({{id=80,minPrice=50000,qty=1}})
        local rows = 0
        for _, d in ipairs(D.list) do if d.id == 80 then rows = rows + 1 end end
        assert(rows == 1, 'one browse row, one Deals row, not ' .. rows)
        assert(Sn.found == found + 1, 'counted once')
        for _, key in ipairs(endings) do assert(Sn.judged[key], 'every ending still checked: ' .. key) end''')

    def test_quick_scan_status_says_what_is_left_to_check(self):
        lua = runtime()
        lua.execute(FAST + '''
        local F, UI = ForeverFlip, ForeverFlip.UI
        F.db.settings.sniper=false
        assert(Sn.startQuick())
        UI.show('deals')
        run(0.1); UI.refresh()
        assert(UI.status:GetText():find('items read'), UI.status:GetText())
        Sn.quick.done = true
        Sn.candidates = { { key = 'c:10', score = 1 }, { key = 'c:11', score = 0.5 } }
        UI.refresh()
        assert(UI.status:GetText():find('2 left'), UI.status:GetText())''')

    def test_the_player_can_stop_a_quick_scan(self):
        lua = runtime()
        lua.execute(FAST + '''
        local F, UI = ForeverFlip, ForeverFlip.UI
        F.db.settings.sniper=false
        assert(Sn.startQuick())
        run(0.1); browseAnswer(); run(0.2)
        UI.show('deals'); UI.refresh()
        assert(UI.scanButton:GetText()=='Stop quick scan', UI.scanButton:GetText())
        assert(UI.scanButton:IsEnabled())
        UI.scanButton:Click()
        assert(not Sn.quick and F.Engine.message=='quick_stopped', tostring(F.Engine.message))
        local kept = 0
        for id in pairs(Sn.lows) do if type(id) == 'number' then kept = kept + 1 end end
        assert(kept > 0, 'what it read is kept')
        run(5); assert(not Sn.active(), 'nothing more is sent')''')

    def test_a_checked_deal_stays_ready_for_five_minutes(self):
        lua = runtime()
        lua.execute(FAST + '''
        local F = ForeverFlip
        local d = { key = 'c:10', id = 10, kind = 'commodity', mode = 'flip', qty = 1, cost = 10, profit = 50,
            exit = 60, maxUnit = 10, roi = 5, verified = F.Engine.clock() - 200, found = F.Engine.clock() - 200 }
        D.replace({ d }, F.Engine.scope())
        local h = F.Data.market(F.db, F.Engine.scope()).history
        Sn.judged = {}
        assert(not Sn.judge('c:10', 10, 10, h), 'checked 200 s ago: not queued again')
        assert(Sn.judge('c:10', 10, 5, h) or true)
        F.UI.show('deals'); F.UI.refresh()
        local status
        for _, r in ipairs(F.UI.dealTable.rows) do if r:IsShown() and r.key == 'c:10' then status = r.cols[7]:GetText() end end
        assert(status and status:find('ready'), tostring(status))''')

    def test_quick_scan_runs_its_own_round_while_the_sniper_runs(self):
        lua = runtime()
        lua.execute(FAST + '''
        run(0.1);assert(Sn.query and Sn.query.kind=='browse','the sniper reads a round')
        assert(Sn.canQuick() and Sn.startQuick(),'offered with the sniper on')
        local guard=0
        while Sn.quick do
            if D.searching() then answer() elseif browsePendingNow() then browseAnswer() end
            run(0.5);guard=guard+1;assert(guard<300,'quick scan never ended')
        end
        assert(Sn.rounds>=2,'the round under way, then its own: '..Sn.rounds)
        assert(ForeverFlip.Engine.message=='quick_done',ForeverFlip.Engine.message)
        assert(D.get('c:10'),'its find is listed')
        assert(ForeverFlip.db.settings.sniper and Sn.active(),'the sniper goes on')''')

    def test_switching_the_sniper_off_keeps_a_quick_scan(self):
        lua = runtime()
        lua.execute(FAST + '''
        assert(Sn.startQuick())
        D.setSniper(false)
        assert(Sn.quick and Sn.active(),'the quick scan goes on')''')

    def test_a_round_reads_every_page_and_queues_a_cheap_item(self):
        lua = runtime()
        lua.execute(FAST + '''
        assert(Sn.active())
        run(0.1);assert(lastCall('SendBrowseQuery'),'round starts when idle')
        browseAnswer();assert(Sn.query and Sn.query.more,'first page only')
        -- the cheap cloth (60c, vendor pays 100c) is a candidate and is checked before the next page
        run(0.5);assert(not lastCall('RequestMoreBrowseResults'),'candidates first')
        assert(D.searching() and D.search.source=='sniper')
        local n=0
        while not (D.get('c:10') and D.get('c:10').verified) do
            if D.searching() then answer() end
            run(0.5);n=n+1;assert(n<20,'cloth never checked')
        end
        -- Then the round goes on: the next page, or (a gear check needed the browse) a new round.
        run(3);assert(lastCall('RequestMoreBrowseResults') or browsePendingNow(),'the round goes on')
        local guard=0
        while browsePendingNow() or D.searching() do
            if D.searching() then answer() else browseAnswer() end
            run(0.1);guard=guard+1;assert(guard<200)
        end
        assert(Sn.rounds==1 and Sn.items>=3,Sn.items)''')

    def test_unchanged_price_is_not_checked_again_right_away(self):
        lua = runtime()
        lua.execute(FAST + '''
        assert(Sn.judge('c:10',10,60,ForeverFlip.Data.market(ForeverFlip.db,ForeverFlip.Engine.scope()).history))
        Sn.candidates={}
        assert(not Sn.judge('c:10',10,60,ForeverFlip.Data.market(ForeverFlip.db,ForeverFlip.Engine.scope()).history))
        assert(Sn.judge('c:10',10,50,ForeverFlip.Data.market(ForeverFlip.db,ForeverFlip.Engine.scope()).history),
          'a lower price is judged again')''')

    def test_expensive_items_are_not_candidates(self):
        lua = runtime()
        lua.execute(FAST + '''
        local h=ForeverFlip.Data.market(ForeverFlip.db,ForeverFlip.Engine.scope()).history
        assert(not Sn.judge('c:10',10,150,h),'150c is above the 100c vendor price')
        assert(not Sn.judge('i:30',30,30000,h))''')

    def test_hot_items_are_read_in_key_batches_during_the_pause(self):
        lua = runtime()
        lua.execute(FAST + '''
        ForeverFlip.Scan.hot={'c:10','i:30'}
        Sn.nextRound=GetTime()+60;run(1.1)
        local c=lastCall('SearchForItemKeys');assert(c and c[2]==2,'two keys in one query')
        browseAnswer();assert(not Sn.query and #Sn.candidates>=0)''')

    def test_switching_the_sniper_off_stops_the_rounds(self):
        lua = runtime()
        lua.execute(FAST + '''
        D.setSniper(false);local n=#calls;run(3)
        for i=n+1,#calls do assert(calls[i][1]~='SendBrowseQuery') end''')

    def test_player_browsing_feeds_the_candidates(self):
        lua = runtime()
        lua.execute(FAST + '''
        D.setSniper(false);ForeverFlip.db.settings.sniper=true;Sn.reset()
        C_AuctionHouse.SendBrowseQuery({});browseAnswer();run(0.1)
        local found=false;for _,c in ipairs(Sn.candidates) do if c.key=='c:10' then found=true end end
        assert(found,'a browse of the game UI is read too')''')


if __name__ == '__main__':
    unittest.main()
