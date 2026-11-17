"""The sniper and other background work give way while the player uses the game's own Buy tab."""

import unittest

from test_addon import SETUP, runtime

# The player is on the game's Buy tab: ForeverFlip's page is hidden. The hooks listen for real
# (enableHooks) and are installed again over the browse API the mock adds after loading.
BUY = SETUP + '''
enableBrowse(2)
fullScan()
ForeverFlip.db.settings.autoVerify=false;ForeverFlip.db.settings.sniper=true
local F=ForeverFlip
local Sn,D,A=F.Sniper,F.Deals,F.AH
D.list={}
enableHooks();A.browseHooked=false;A.hookBrowse()
local QUERIES={SendBrowseQuery=true,SearchForItemKeys=true,SendSearchQuery=true,SendSellSearchQuery=true,
  RequestMoreBrowseResults=true,RequestMoreItemSearchResults=true,RequestMoreCommoditySearchResults=true}
function queriesSince(n)
  local out={}
  for i=n+1,#calls do if QUERIES[calls[i][1]] then out[#out+1]=calls[i][1] end end
  return out
end
function playerBrowse(text)
  F.UI.frame:Hide()
  C_AuctionHouse.SendBrowseQuery({searchString=text or '',sorts={},filters={},itemClassFilters={}})
end
'''


class PlayerBuyTabTests(unittest.TestCase):
    def test_a_manual_browse_stops_the_sniper(self):
        lua = runtime()
        lua.execute(BUY + '''
        playerBrowse('');browseAnswer()
        assert(A.playerAt,'the player search is heard')
        local n=#calls;run(30)
        assert(#queriesSince(n)==0,table.concat(queriesSince(n),','))
        assert(Sn.paused()=='Sniper paused: you are using the Buy tab',tostring(Sn.paused()))
        assert(#Sn.candidates>0 and not D.search,'candidates found in the player browse wait')''')

    def test_a_sniper_query_in_flight_does_not_page_the_player_browse(self):
        lua = runtime()
        lua.execute(BUY + '''
        F.UI.frame:Hide();run(0.1)
        assert(Sn.query and lastCall('SendBrowseQuery'),'the sniper round starts')
        playerBrowse('')
        assert(not Sn.query,'the sniper query gives way')
        local n=#calls;browseAnswer();run(10)
        assert(#queriesSince(n)==0,table.concat(queriesSince(n),','))''')

    def test_a_purchase_page_stops_the_sniper(self):
        lua = runtime()
        lua.execute(BUY + '''
        for _,name in ipairs({'ItemBuyFrame','CommoditiesBuyFrame'}) do
          F.UI.frame:Hide()
          local page=CreateFrame('Frame');AuctionHouseFrame[name]=page
          local n=#calls;run(90)
          assert(#queriesSince(n)==0,name..': '..table.concat(queriesSince(n),','))
          assert(Sn.paused()=='Sniper paused: a purchase page is open')
          page:Hide();run(3)
          assert(lastCall('SendBrowseQuery') and #queriesSince(n)>0,'resumes once the page is closed')
          while browsePendingNow() do browseAnswer();run(0.1) end
          Sn.reset()
        end''')

    def test_the_sniper_resumes_after_the_player_is_idle(self):
        lua = runtime()
        lua.execute(BUY + '''
        playerBrowse('Linen');browseAnswer()
        Sn.candidates={}
        local n=#calls;run(55)
        assert(#queriesSince(n)==0)
        run(10)
        assert(#queriesSince(n)>0,'resumes after a minute without a search of the player')
        assert(not Sn.paused())''')

    def test_back_on_foreverflip_or_off_the_buy_tab_resumes_at_once(self):
        lua = runtime()
        lua.execute(BUY + '''
        playerBrowse('Linen');browseAnswer();Sn.candidates={}
        F.UI.frame:Show();local n=#calls;run(3)
        assert(#queriesSince(n)>0,'ForeverFlip page shown: the sniper goes on')
        while browsePendingNow() do browseAnswer();run(0.1) end
        Sn.reset()
        -- The game's Buy list reads as hidden (another tab of the game): the player left it.
        local browse=CreateFrame('Frame');AuctionHouseFrame.BrowseResultsFrame=browse
        playerBrowse('Linen');browseAnswer();Sn.candidates={}
        n=#calls;run(3);assert(#queriesSince(n)==0,'Buy list shown')
        browse:Hide();run(3)
        assert(#queriesSince(n)>0,'Buy list hidden: the sniper goes on')''')

    def test_foreverflip_own_queries_are_not_the_players(self):
        lua = runtime()
        lua.execute(BUY + '''
        F.UI.frame:Hide()
        F.Scan.hot={'c:10','i:30'}
        local guard=0
        while Sn.rounds<1 do
          if D.searching() then answer() elseif browsePendingNow() then browseAnswer() end
          run(0.2);guard=guard+1;assert(guard<300,'round never ends')
        end
        Sn.nextRound=GetTime()+60;run(1.1)
        assert(lastCall('SearchForItemKeys'),'a key batch')
        browseAnswer()
        assert(lastCall('SendSearchQuery'),'an exact check of a candidate')
        assert(A.playerAt==nil,'no own query taken for the player')
        assert(not Sn.paused())''')

    def test_the_status_shows_the_pause(self):
        lua = runtime()
        lua.execute(BUY + '''
        run(21) -- the scan's message has had its time
        playerBrowse('');F.UI.refreshStatus()
        assert(F.UI.status:GetText():find('Sniper paused'),F.UI.status:GetText())
        assert(F.UI.sniperSummary():find('Sniper paused'))''')


if __name__ == '__main__':
    unittest.main()
