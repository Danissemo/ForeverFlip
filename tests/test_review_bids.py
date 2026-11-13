"""Review fixes of Bids.lua: candidates per house, placing and answering bids, the game's Bids list."""

import unittest

from test_addon import SETUP, run

# A Linen Bag (vendor 20s) with a 5s bid, ending within 30 minutes, no buyout (as in test_bids.py).
BIDS = SETUP + '''enableTimeLeft()
local F=ForeverFlip
local B=F.Bids
local c=F.Data.char(F.db,F.Engine.owner())
local a=addAuction(30,0,1);a.buyout=0;a.minBid=500;a.timeLeft=1
fullScan()
local function row(id) for _,r in ipairs(B.mine()) do if r.auctionID==id then return r end end end
local function sent(name) for _,call in ipairs(calls) do if call[1]==name then return true end end return false end
'''

# The player's bid on auction 77, a Linen Bag (as in test_my_bids.py).
MY_BIDS = SETUP + '''local F, B = ForeverFlip, ForeverFlip.Bids
local c = F.Data.char(F.db, F.Engine.owner())
local function live(minBid, bid, bidder, buyout, band)
    myBids = { { auctionID = 77, itemKey = { itemID = 30 }, itemLink = '[Linen Bag]', minBid = minBid,
        bidAmount = bid, buyoutAmount = buyout or 0, timeLeft = band or 1, bidder = bidder } }
    fire('BIDS_UPDATED')
end
local function row() for _, r in ipairs(B.mine()) do if r.auctionID == 77 then return r end end end
local function sent(name) for _, call in ipairs(calls) do if call[1] == name then return true end end return false end
c.bids = { [77] = { key = 'i:30', name = 'Linen Bag', qty = 1, amount = 500, at = now - 60 } }
'''


# A Silk Bag bid placed in the game's own window, first read while the item is not loaded: the
# row's link (a Lua expression) can be missing too.
def native(link):
    return SETUP + '''local F, B = ForeverFlip, ForeverFlip.Bids
local c = F.Data.char(F.db, F.Engine.owner())
addItem(40, 'Silk Bag', 500, 'item'); items[40].cached = false
myBids = { { auctionID = 88, itemKey = { itemID = 40 }, itemLink = %s, minBid = 600, bidAmount = 500,
    buyoutAmount = 0, timeLeft = 1, bidder = 'Player-1' } }
fire('BIDS_UPDATED')
assert(c.bids[88] and not c.bids[88].key, 'no key before the item is loaded')
''' % link


class CandidateTests(unittest.TestCase):
    def test_each_house_lists_its_own_candidates(self):
        run(BIDS + '''assert(#B.current() == 1)
        fire('AUCTION_HOUSE_CLOSED'); now = now + 600
        function GetSubZoneText() return 'Gadgetzan' end
        fire('AUCTION_HOUSE_SHOW')
        assert(F.Engine.scope() == 'Realm-Neutral')
        assert(#B.current() == 0 and not B.get('i:30'), 'the neutral house was not scanned')
        fire('AUCTION_HOUSE_CLOSED'); now = now + 600
        function GetSubZoneText() return 'Ironforge' end
        fire('AUCTION_HOUSE_SHOW')
        assert(#B.current() == 1 and B.current()[1].key == 'i:30', 'back at the faction house')''')

    def test_a_candidate_a_check_drops_stays_dropped_after_reload(self):
        run(SETUP + '''enableTimeLeft()
        local F, B = ForeverFlip, ForeverFlip.Bids
        addItem(40, 'Small Bag', 3000, 'item')
        local x = addAuction(30, 0, 1); x.buyout = 0; x.minBid = 500; x.timeLeft = 1 -- ends within 30 min
        local y = addAuction(40, 0, 1); y.buyout = 0; y.minBid = 500; y.timeLeft = 2 -- within 2 hours
        fullScan()
        now = now + 1900
        assert(#B.current() == 1 and B.current()[1].key == 'i:40', 'the first auction is over')
        y.minBid = 2900 -- bid up past its worth meanwhile
        B.check('i:40'); run(0.1); answer()
        assert(#B.current() == 0)
        B.candidates, B.scope, B.at, B.offers = {}, nil, nil, {} -- /reload
        assert(#B.current() == 0, 'the saved list lost it too')''')

    def test_scan_end_reckons_an_items_worth_once_and_keeps_the_best(self):
        run(SETUP + '''local F, B = ForeverFlip, ForeverFlip.Bids
        local bids = {}
        for i = 1, 150 do
            addItem(1000 + i, 'Ring ' .. i, 1000 + i * 10, 'item')
            for k = 1, 3 do
                bids[#bids + 1] = { key = 'i:' .. (1000 + i), id = 1000 + i, kind = 'item', bid = 100 + k, count = 1,
                    band = 0, ends = now + 1800 }
            end
        end
        local value, calls = B.value, 0
        B.value = function(...) calls = calls + 1; return value(...) end
        B.finish({ scope = F.Engine.scope(), bids = bids }, F.Data.market(F.db, F.Engine.scope()).history)
        B.value = value
        assert(calls == 150, 'once per item: ' .. calls)
        local list = B.current()
        assert(#list == B.MAX, #list)
        -- the most valuable rings first, each with its lowest bid first: 33 rings, then the best of a 34th
        assert(list[1].key == 'i:1150' and list[1].bid == 101 and list[1].profit == 2500 - 101)
        assert(list[99].key == 'i:1118' and list[99].bid == 103)
        assert(list[100].key == 'i:1117' and list[100].bid == 101)
        for i = 2, #list do assert(list[i - 1].profit >= list[i].profit) end''')


class PlaceTests(unittest.TestCase):
    def test_a_bid_waits_for_a_new_check_after_another_item_was_searched(self):
        run(SETUP + '''enableTimeLeft()
        local F, B = ForeverFlip, ForeverFlip.Bids
        addItem(40, 'Small Bag', 3000, 'item')
        local x = addAuction(30, 0, 1); x.buyout = 0; x.minBid = 500; x.timeLeft = 1
        local y = addAuction(40, 0, 1); y.buyout = 0; y.minBid = 500; y.timeLeft = 1
        fullScan()
        B.check('i:30'); run(0.1); answer()
        B.check('i:40'); run(0.5); answer()
        assert(B.offer('i:30') and not F.AH.searchedLast(30))
        calls = {}
        local ok, why = B.place('i:30')
        assert(not ok and why == 'buy_recheck' and not lastCall('PlaceBid'), 'the server would drop it')
        assert(not B.offer('i:30'), 'Place bid waits for the new check')
        run(0.5); answer()
        assert(lastCall('SendSearchQuery')[2] == 30 and B.offer('i:30'))
        assert(B.place('i:30') and lastCall('PlaceBid')[2] == x.id)''')

    def test_a_check_offers_no_bid_against_yourself(self):
        run(BIDS + '''B.check('i:30'); run(0.1); answer()
        assert(B.place('i:30'))
        a.minBid = 525 -- the next bid the house takes: the player leads
        calls = {}
        B.check('i:30'); run(0.5); answer()
        assert(not B.offer('i:30') and not sent('PlaceBid'))''')

    def test_an_auction_you_were_outbid_on_is_offered_again(self):
        run(BIDS + '''B.check('i:30'); run(0.1); answer()
        assert(B.place('i:30'))
        assert(B.outbid('Linen Bag'))
        a.minBid = 700
        B.check('i:30'); run(0.5); answer()
        local o = B.offer('i:30')
        assert(o and o.auctionID == a.id and o.bid == 700)''')

    def test_a_bid_keeps_to_the_spending_limit_of_the_visit(self):
        run(BIDS + '''F.db.settings.spendLimit = 1 -- one gold a visit
        F.Engine.spent = 9600 -- 96s spent: 4s left
        B.check('i:30'); run(0.1); answer()
        calls = {}
        local ok, why = B.place('i:30')
        assert(not ok and why == 'spend_limit' and not sent('PlaceBid'))
        F.Engine.spent = 0
        assert(B.place('i:30') and F.Engine.spent == 500, 'the bid counts toward the limit')''')

    def test_a_buyout_of_a_bid_keeps_to_the_spending_limit_of_the_visit(self):
        run(MY_BIDS + '''F.db.settings.spendLimit = 1
        F.Engine.spent = 9600
        live(700, 650, 'Player-2', 900, 3)
        calls = {}
        local ok, why = B.answer(77, 'buyout')
        assert(not ok and why == 'spend_limit' and not sent('PlaceBid'))
        F.Engine.spent = 0
        assert(B.answer(77, 'buyout') and F.Engine.spent == 900)''')


class MyBidsTests(unittest.TestCase):
    def test_a_bid_the_bids_list_never_shows_does_not_lead(self):
        run(BIDS + '''B.check('i:30'); run(0.1); answer()
        assert(B.place('i:30'))
        now = now + 61; myBids = {}; fire('BIDS_UPDATED') -- the server did not take it
        local r = row(a.id)
        assert(r.status == 'ended' and not r.advice, r.status .. ' ' .. tostring(r.advice))
        now = now + 6 * 3600; fire('BIDS_UPDATED') -- its auction is long over
        assert(not c.bids[a.id] and not row(a.id) and #B.open() == 0)''')

    def test_a_bid_not_read_while_its_auction_ran_waits_for_its_mail(self):
        run(BIDS + '''B.check('i:30'); run(0.1); answer()
        assert(B.place('i:30'))
        fire('AUCTION_HOUSE_CLOSED') -- at once: the next visit is after the auction's end
        now = now + 6 * 3600
        fire('AUCTION_HOUSE_SHOW'); myBids = {}; fire('BIDS_UPDATED')
        assert(c.bids[a.id] and row(a.id).status == 'ended')
        fire('CHAT_MSG_SYSTEM', 'You won an auction for Linen Bag')
        assert(c.positions['i:30'] and not c.bids[a.id])''')

    def test_an_ended_bid_is_not_answered(self):
        run(MY_BIDS + '''live(600, 500, 'Player-1', 900, 3)
        assert(row().status == 'leading')
        now = now + 3600; myBids = {}; fire('BIDS_UPDATED') -- the auction is over
        assert(row().status == 'ended')
        calls = {}
        local ok, why = B.answer(77, 'buyout')
        assert(not ok and why == 'nothing_to_bid' and not sent('PlaceBid'))
        assert(c.bids[77].amount == 500, 'the won mail is booked with what was bid')''')

    def test_a_bid_from_the_game_window_gets_its_name_and_key_once_the_item_loads(self):
        run(native('nil') + '''items[40].cached = true; myBids[1].itemLink = link(40)
        fire('BIDS_UPDATED')
        assert(c.bids[88].key == 'i:40' and c.bids[88].name == 'Silk Bag')''')

    def test_a_won_bid_from_the_game_window_is_booked_once_its_key_is_known(self):
        run(native('link(40)') + '''assert(c.bids[88].name == 'Silk Bag')
        fire('CHAT_MSG_SYSTEM', 'You won an auction for Silk Bag')
        assert(c.bids[88] and not c.positions['i:40'], 'nothing to book it under yet')
        items[40].cached = true -- loaded, but the auction is over: no read fills the key in
        now = now + 1800; myBids = {}; fire('BIDS_UPDATED')
        assert(not c.bids[88].key)
        assert(B.won('Silk Bag', true), 'the mail books it')
        assert(c.positions['i:40'] and c.positions['i:40'].qty == 1 and not c.bids[88])''')

    def test_the_bids_list_waits_for_a_sniper_browse_and_a_post(self):
        run(MY_BIDS + '''local inFlight = F.Sniper.inFlight
        F.Sniper.inFlight = function() return true end
        calls = {}; run(1)
        assert(not sent('QueryBids'), 'a sniper browse waits for its answer')
        F.Sniper.inFlight = inFlight
        F.Trade.lastPost = { ids = {}, auctions = 1, at = now }
        run(1)
        assert(not sent('QueryBids'), 'a post waits for AUCTION_CREATED')
        F.Trade.lastPost = nil
        run(1)
        assert(sent('QueryBids'))''')


if __name__ == '__main__':
    unittest.main()
