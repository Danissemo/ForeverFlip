"""Fast sniper: browse rounds over the whole house, key batches and exact checks of candidates."""

import unittest

from test_addon import SETUP, runtime

FAST = SETUP + '''
enableBrowse(2)
fullScan()
ForeverFlip.Engine.autoVerify=false;ForeverFlip.db.settings.sniper=true
local Sn,D=ForeverFlip.Sniper,ForeverFlip.Deals
D.list={}
'''


class FastSniperTests(unittest.TestCase):
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
