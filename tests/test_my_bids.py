"""Shopping list, My bids: every bid of the player, won or lost, and whether to bid again."""
import unittest

from test_addon import SETUP, run

BIDS = SETUP + '''local F, B, UI = ForeverFlip, ForeverFlip.Bids, ForeverFlip.UI
ERR_AUCTION_OUTBID_S = "You have been outbid on %s."
local c = F.Data.char(F.db, F.Engine.owner())
local worth = B.value('i:30', 30, F.Data.market(F.db, F.Engine.scope()).history)
local max = B.maxBid(worth)
local function live(minBid, bid, bidder, buyout, band)
    myBids = { { auctionID = 77, itemKey = { itemID = 30 }, itemLink = '[Linen Bag]', minBid = minBid,
        bidAmount = bid, buyoutAmount = buyout or 0, timeLeft = band or 1, bidder = bidder } }
    fire('BIDS_UPDATED')
end
local function row()
    for _, r in ipairs(B.mine()) do if r.auctionID == 77 then return r end end
end
c.bids = { [77] = { key = 'i:30', name = 'Linen Bag', qty = 1, amount = 500, at = now - 60 } }
'''


class MyBidsTests(unittest.TestCase):
    def test_the_highest_bid_worth_placing_keeps_the_minimum_profit_and_return(self):
        run(SETUP + '''local B = ForeverFlip.Bids
        local s = ForeverFlip.db.settings
        s.minProfit, s.minROI = 100, 0.2
        assert(B.maxBid(2000) == 1666, tostring(B.maxBid(2000)))
        s.minROI = 0
        assert(B.maxBid(2000) == 1900)''')

    def test_a_leading_bid_is_kept(self):
        run(BIDS + '''live(600, 500, 'Player-1')
        local r = row()
        assert(r.status == 'leading' and r.advice == 'hold', r.status .. ' ' .. tostring(r.advice))''')

    def test_an_outbid_bid_is_answered_while_it_still_pays(self):
        run(BIDS + '''live(700, 650, 'Player-2')
        local r = row()
        assert(r.status == 'outbid' and r.advice == 'rebid' and r.price == 700, tostring(r.advice))
        assert(r.profit == worth - 700)
        assert(B.answer(77, 'rebid'))
        local call = lastCall('PlaceBid')
        assert(call[2] == 77 and call[3] == 700, 'bids the next amount the house takes')
        assert(c.bids[77].amount == 700 and not c.bids[77].outbid)''')

    def test_an_outbid_past_its_worth_is_let_go(self):
        run(BIDS + '''live(max + 1, max, 'Player-2')
        assert(row().advice == 'let_go', tostring(row().advice))''')

    def test_a_buyout_that_pays_ends_a_long_auction_now(self):
        run(BIDS + '''live(700, 650, 'Player-2', 900, 3)
        local r = row()
        assert(r.advice == 'buyout' and r.price == 900, tostring(r.advice))
        assert(B.answer(77, 'buyout') and lastCall('PlaceBid')[3] == 900)''')

    def test_not_enough_money_is_said(self):
        run(BIDS + '''live(700, 650, 'Player-2'); money = 600
        assert(row().advice == 'no_money')
        assert(not B.answer(77, 'rebid'))''')

    def test_outbid_keeps_the_bid_open_and_its_end_makes_it_lost(self):
        run(BIDS + '''live(600, 500, 'Player-1')
        fire('CHAT_MSG_SYSTEM', 'You have been outbid on Linen Bag.')
        assert(c.bids[77] and row().status == 'outbid', 'still running: it can be answered')
        myBids = {}; fire('BIDS_UPDATED')
        assert(not c.bids[77] and c.bidLog[#c.bidLog].outcome == 'lost')
        assert(row().status == 'lost')''')

    def test_a_won_bid_is_listed_as_won_with_its_profit(self):
        run(BIDS + '''c.bids[77].value = 2000
        fire('CHAT_MSG_SYSTEM', 'You won an auction for Linen Bag')
        local r = row()
        assert(r and r.status == 'won' and r.profit == 1500, tostring(r and r.status))''')

    def test_a_bid_from_the_game_window_is_tracked(self):
        run(BIDS + '''c.bids = {}
        live(700, 650, 'Player-1')
        assert(c.bids[77] and c.bids[77].key == 'i:30' and c.bids[77].native)''')

    def test_the_page_lists_the_bids_and_answers_the_selected(self):
        run(BIDS + '''live(700, 650, 'Player-2')
        UI.show('mybids'); UI.refresh()
        local r = UI.myBidTable.rows[1]
        assert(r:IsShown() and r.cols[5]:GetText():find('outbid'), r.cols[5]:GetText())
        r.scripts.OnClick(r); UI.refresh()
        assert(UI.myBidAgain:IsEnabled() and UI.myBidText:GetText():find('Worth bidding up to'))
        UI.myBidAgain:Click()
        assert(lastCall('PlaceBid')[3] == 700)''')

    def test_the_bids_list_is_asked_for_while_a_bid_runs(self):
        run(BIDS + '''calls = {}
        run(1)
        local asked = false
        for _, call in ipairs(calls) do if call[1] == 'QueryBids' then asked = true end end
        assert(asked)''')


if __name__ == '__main__':
    unittest.main()
