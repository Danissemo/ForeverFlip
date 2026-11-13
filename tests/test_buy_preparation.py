"""Prepare the server context before Buy and keep background queries out of its way."""

import unittest

from test_addon import SETUP, run


BASE = SETUP + '''local F=ForeverFlip;local D,T,UI=F.Deals,F.Trade,F.UI
F.db.settings.autoScan=false;F.db.settings.sniper=false;F.db.settings.autoVerify=false
local key='g:20:northern shortsword of nature protection'
fullScan();D.verify(key);answer();UI.show('deals:all')
local function buys() local n=0 for _,c in ipairs(calls) do if c[1]=='PlaceBid' then n=n+1 end end return n end
'''


class BuyPreparationTests(unittest.TestCase):
    def test_owned_refresh_waits_while_buy_is_hovered(self):
        run(BASE + '''UI.selectDeal(key);UI.buyButton.scripts.OnEnter(UI.buyButton)
        local queries=0;F.AH.queryOwned=function() queries=queries+1 end;T.ownedDue=0
        run(D.SELECTED_HOLD+2)
        assert(queries==0,'owned-auction refresh cannot occupy the server before the purchase')
        UI.buyButton.scripts.OnLeave(UI.buyButton);run(0.3)
        assert(queries==1,'the deferred refresh resumes afterwards')
        ''')

    def test_buy_availability_preserves_existing_stuck_throttle_recovery(self):
        run(BASE + '''UI.selectDeal(key);T.ownedDue=now+1000
        local forced=F.AH.forced or 0
        C_AuctionHouse.IsThrottledMessageSystemReady=function() return false end
        UI.refresh();assert(not UI.buyButton:IsEnabled())
        run(7)
        for i=1,10 do UI.refresh() end
        assert(UI.buyButton:IsEnabled(),'the existing recovery allowance must remain reachable by a click')
        assert((F.AH.forced or 0)==forced,'rendering availability never consumes the allowance')
        UI.buyButton:Click()
        assert(buys()==1 and F.AH.forced==forced+1,'only the hardware click consumes it')
        ''')

    def test_selecting_fresh_gear_restores_context_before_the_buy_click(self):
        run(BASE + '''F.AH.noteItemSearch({itemID=30})
        UI.selectDeal(key)
        assert(D.pending(key),'a fresh price with a different last search still needs preparation')
        assert(not UI.buyButton:IsEnabled(),'do not offer a buy click that can only recheck')
        run(0.3);answer();UI.refresh()
        assert(buys()==0,'search completion cannot purchase outside a hardware callback')
        assert(UI.buyButton:IsEnabled() and F.AH.searchedLast(20))
        UI.buyButton:Click();assert(buys()==1,'the first enabled Buy click sends the purchase')
        ''')

    def test_buy_button_waits_for_an_inflight_search(self):
        run(BASE + '''UI.selectDeal(key);run(0.3);T.checkPrice('i:30')
        assert(D.search and D.search.key=='i:30')
        UI.refresh();assert(not UI.buyButton:IsEnabled(),'no pointless Buy while another query is on the wire')
        UI.buyButton.scripts.OnEnter(UI.buyButton)
        assert(D.pending(key) and buys()==0)
        answer();run(0.3);answer();UI.refresh()
        assert(UI.buyButton:IsEnabled() and buys()==0)
        UI.buyButton:Click();assert(buys()==1,'the first enabled click buys after the inflight query drains')
        ''')

    def test_hover_protects_purchase_beyond_the_brief_selection_hold(self):
        run(BASE + '''UI.selectDeal(key)
        assert(UI.buyButton.scripts.OnEnter,'hover prepares and reserves the purchase')
        UI.buyButton.scripts.OnEnter(UI.buyButton)
        F.db.settings.autoVerify=true;F.db.settings.sniper=true
        run(D.SELECTED_HOLD+3)
        assert(D.holding() and not D.search,'background must not replace the lot while the cursor is on Buy')
        UI.buyButton.scripts.OnLeave(UI.buyButton)
        assert(not D.holding(),'background resumes after the cursor leaves')
        ''')

    def test_hover_restores_context_without_buying_automatically(self):
        run(BASE + '''UI.selectDeal(key);now=now+D.SELECTED_HOLD+1
        F.AH.noteItemSearch({itemID=30})
        assert(UI.buyButton.scripts.OnEnter)
        UI.buyButton.scripts.OnEnter(UI.buyButton)
        assert(D.pending(key));run(0.3);answer();UI.refresh()
        assert(buys()==0 and UI.buyButton:IsEnabled())
        UI.buyButton:Click();assert(buys()==1)
        ''')

    def test_failed_preparation_does_not_leave_old_price_buyable(self):
        run(BASE + '''F.AH.noteItemSearch({itemID=30});UI.selectDeal(key)
        run(12);UI.refresh()
        assert(not UI.buyButton:IsEnabled() and buys()==0,'a failed recheck cannot reuse the earlier ready mark')
        ''')


if __name__ == '__main__':
    unittest.main()
