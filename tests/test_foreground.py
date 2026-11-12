"""Interactive requests take safe boundaries ahead of automatic and batch work."""

import unittest

from test_addon import SETUP, run


BASE = SETUP + '''local F = ForeverFlip
local D, T, S = F.Deals, F.Trade, F.Sniper
fullScan()
'''


class ForegroundTests(unittest.TestCase):
    def test_post_next_uses_a_fresh_scan_price_in_the_same_click(self):
        run(BASE + '''local c = F.Data.char(F.db, F.Engine.owner())
        F.Data.addPosition(c,'i:30','Linen Bag',1,1000,'flip',50000,now-100)
        putBag(0,1,30,1); T.prices = {}
        local ok, why = T.postNext()
        assert(ok and why=='post_sent', 'reuse local scan data before asking for a second click: '..tostring(why))
        assert(not D.search, 'a recent scan needs no network check')''')

    def test_post_next_does_not_check_other_items_before_posting_a_ready_item(self):
        run(SETUP + '''local F = ForeverFlip; local T = F.Trade
        local c = F.Data.char(F.db, F.Engine.owner())
        F.Data.addPosition(c,'i:30','Linen Bag',1,1000,'flip',5000,now-100)
        F.Data.addPosition(c,'c:10','Linen Cloth',1,60,'flip',150,now)
        putBag(0,1,30,1);putBag(0,2,10,1)
        T.prices['i:30']={rows={{unit=5000,qty=1}},at=now}
        local ok, why = T.postNext()
        assert(ok and why=='post_sent', 'a read-ahead search must not block the chosen post: '..tostring(why))
        assert(not F.Deals.search, 'no unrelated query before posting completes')''')

    def test_post_confirmation_status_precedes_waiting_price_checks(self):
        run(BASE + '''T.lastPost = {at=now,ids={},auctions=1}
        T.checkPrice('c:10')
        F.UI.refreshStatus()
        assert(F.UI.status:GetText():find('Posting'), 'show the active post instead of a waiting query')''')

    def test_click_promotes_matching_queued_batch_without_duplicate(self):
        run(BASE + '''throttleReady = false
        local a, b = 0, 0
        D.enqueue('i:30', function() end, 'bulk1', true)
        D.enqueue('c:10', function() a = a + 1 end, 'bulk2', true)
        T.checkPrice('c:10', function() b = b + 1 end)
        assert(#D.requests == 2 and D.requests[1].key == 'c:10', 'matching batch query promoted')
        throttleReady = true; run(0.1)
        assert(D.search and D.search.key == 'c:10'); answer()
        assert(a == 1 and b == 1, 'shared result completes both callers exactly once')''')

    def test_click_does_not_discard_background_request_already_on_the_wire(self):
        run(BASE + '''D.request('i:30', function() end, 'auto', true)
        local first = D.search
        T.checkPrice('c:10')
        assert(D.search == first and not D.backgroundRetry, 'retain ownership until reply')
        answer(); run(1.1)
        assert(D.search.key == 'c:10', 'interactive check starts at next safe boundary')''')

    def test_sniper_waits_for_manual_search_before_sending_more_pages(self):
        run(BASE + '''enableBrowse(); F.db.settings.sniper = true
        S.query = { kind = 'browse', at = GetTime(), more = true, answered = true }
        T.checkPrice('c:10')
        local more = 0; F.AH.browseMore = function() more = more + 1 end
        S.step()
        assert(more == 0, 'no browse page while the manual search owns the connection')''')

    def test_owned_batch_cannot_push_a_new_single_check_back(self):
        run(BASE + '''throttleReady = false
        T.checkQueue = { 'i:30', 'c:10' }
        T.stepChecks(); T.checkPrice('c:10')
        assert(D.requests[1].key == 'c:10', 'owned checks are bulk work')''')

    def test_gear_batch_pauses_between_versions_then_resumes_without_restarting(self):
        run(BASE + '''local key = F.Util.key('gear', 20, 'Northern Shortsword of Healing')
        local done = 0
        assert(D.enqueue(key, function() done = done + 1 end, 'gearbulk', true))
        local gear = D.search
        assert(gear)
        gear.phase, gear.waitKey = 'keys', true
        gear.keys, gear.keyIndex = { { itemID = 20, itemSuffix = 1 } }, 1
        gear.found, gear.foundIDs, gear.allComplete = {}, {}, true
        T.checkPrice('c:10'); run(1.1)
        assert(D.search and D.search.key == 'c:10', 'yield at unsent version')
        answer(); run(1.1)
        assert(D.search == gear and not gear.waitKey, 'resume same partial request')
        assert(done == 0, 'paused work is not reported as failed')
        fire('AUCTION_HOUSE_CLOSED'); assert(done == 1, 'closing completes it once')''')

    def test_foreign_sniper_browse_is_drained_before_an_exact_request(self):
        run(BASE + '''enableBrowse(); F.db.settings.sniper = true
        S.query = { kind = 'browse', at = GetTime(), read = 0 }
        T.checkPrice('c:10')
        assert(not D.search and D.pending('c:10'), 'a sent browse still owns its response')
        S.onResults(true); run(1.1)
        assert(D.search and D.search.key == 'c:10')''')

    def test_purchase_or_post_waits_for_full_scan_and_browse_ownership(self):
        run(BASE + '''F.Scan.job = { state = 'waiting' }
        assert(T.wayFree(), 'a click of the player goes while a full scan waits for its answer')
        F.Scan.job = nil; enableBrowse()
        S.query = { kind = 'browse', at = GetTime(), read = 0 }
        assert(not T.wayFree(), 'a browse already sent still owns the connection')''')

    def test_post_and_bid_do_not_compete_with_an_unresolved_purchase(self):
        run(BASE + '''T.op = { state = 'awaiting', kind = 'item', key = 'i:30', at = now }
        putBag(0, 1, 30, 1)
        assert(not T.post(F.AH.bagItems()[1], 1, 50000, 3), 'a deposit must not be mistaken for purchase money')
        F.Bids.offers['i:30'] = { auctionID = 42, qty = 1, bid = 100, at = now }
        assert(not F.Bids.place('i:30'), 'a second outgoing trade cannot confirm the first')''')

    def test_foreground_status_is_not_hidden_by_a_paused_batch(self):
        run(BASE + '''F.UI.show('deals')
        D.batch = { active = true, scope = 'deals:all', total = 10, done = 1 }
        T.op = { key = 'c:10', kind = 'commodity', state = 'quote' }
        F.UI.refreshStatus()
        assert(F.UI.status:GetText():find('Asking'), 'show the purchase before batch progress')
        T.op = nil; throttleReady = false; T.checkPrice('c:10')
        F.UI.refreshStatus()
        assert(F.UI.status:GetText():find('queued'), 'show that the explicit request is queued')''')


if __name__ == '__main__':
    unittest.main()
