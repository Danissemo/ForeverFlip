"""A general auction error must not turn a successful item purchase into a lost race."""

import unittest

from test_addon import SETUP, run


BUY = SETUP + '''local F = ForeverFlip
local T, D = F.Trade, F.Deals
local key = F.Util.key('gear', 20, 'Northern Shortsword of Nature Protection')
C_AuctionHouse.PlaceBid = function() end -- asynchronous server response supplied by each test
fullScan(); D.verify(key); answer(); assert(T.buy(key))
local op = T.op
local c = F.Data.char(F.db, F.Engine.owner())
'''


class PurchaseConfirmationTests(unittest.TestCase):
    def test_general_error_keeps_purchase_pending_until_matching_success(self):
        run(BUY + '''fire('AUCTION_HOUSE_SHOW_ERROR', 999)
        assert(T.op == op and T.busy(), 'a general error cannot establish who bought the lot')
        assert(not T.buy(key), 'no second purchase while the first is unresolved')
        fire('AUCTION_HOUSE_PURCHASE_COMPLETED', op.auctionID + 1)
        assert(T.op == op, 'a different auction cannot confirm this purchase')
        fire('AUCTION_HOUSE_PURCHASE_COMPLETED', op.auctionID)
        assert(not T.op and c.positions[key].qty == 1)
        fire('AUCTION_HOUSE_PURCHASE_COMPLETED', op.auctionID)
        money = money - op.cost; fire('PLAYER_MONEY')
        assert(c.positions[key].qty == 1 and F.Engine.spent == op.cost, 'booked once')''')

    def test_money_after_general_error_confirms_the_purchase(self):
        run(BUY + '''fire('AUCTION_HOUSE_SHOW_ERROR', 999)
        money = money - op.cost; fire('PLAYER_MONEY')
        assert(not T.op and c.positions[key] and c.positions[key].qty == 1,
            'the server accepted the purchase despite the general error')''')

    def test_general_error_checks_money_already_spent(self):
        run(BUY + '''money = money - op.cost
        fire('AUCTION_HOUSE_SHOW_ERROR', 999)
        assert(not T.op and c.positions[key] and c.positions[key].qty == 1,
            'money already spent confirms success before reporting any error')''')

    def test_won_chat_after_general_error_confirms_the_purchase(self):
        run(BUY + '''fire('AUCTION_HOUSE_SHOW_ERROR', 999)
        fire('CHAT_MSG_SYSTEM', 'You won an auction for Northern Shortsword of Nature Protection')
        assert(not T.op and c.positions[key] and c.positions[key].qty == 1)''')

    def test_general_error_without_success_still_times_out_and_can_recover(self):
        run(BUY + '''fire('AUCTION_HOUSE_SHOW_ERROR', 999); run(31)
        assert(not T.op and not c.positions[key], 'an unconfirmed purchase is not booked')
        assert(F.Engine.message == 'buy_no_answer' and T.late, 'report no answer, not a lost race')
        money = money - op.cost; fire('PLAYER_MONEY')
        assert(c.positions[key].qty == 1 and F.Engine.message == 'bought_late')''')


if __name__ == '__main__':
    unittest.main()
