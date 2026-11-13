"""V15-a/b/c: one deposit model for advice, deals, the sniper, merchant offers, crafting, bids, posts,
cancels and the anti-undercut plan (Market.postDeposit)."""

import unittest

from test_addon import SETUP, run
import test_audit

BASE = SETUP + '''local F = ForeverFlip
local M, T = F.Market, F.Trade
'''


class DepositModelTests(unittest.TestCase):
    def test_posts_and_estimates_agree_and_count_the_duration(self):
        # Linen Bag, vendor 20s: the game takes 3s / 6s / 12s for the three durations.
        run(BASE + '''addItem(40, 'Linen Bag', 2000, 'item')
        for d, want in ipairs({ 300, 600, 1200 }) do
            assert(T.depositFor('i:40', 1, d) == want, d .. ': ' .. T.depositFor('i:40', 1, d))
            assert(M.postDeposit(40, 'item', 1, d) == want and M.unitDeposit(40, 'item', d) == want)
        end
        F.db.settings.duration = 3
        assert(M.depositRisk('item', 2000, 1) == 1200, 'the risk counts the duration posts go for')''')

    def test_items_pay_the_minimum_per_auction_and_a_commodity_stack_once(self):
        run(BASE + '''addItem(41, 'Cheap Ring', 3, 'gear'); addItem(42, 'Cheap Dust', 3, 'commodity')
        assert(T.depositFor('g:41', 5, 3) == 500, 'five auctions, 1 silver each: ' .. T.depositFor('g:41', 5, 3))
        assert(T.depositFor('c:42', 5, 3) == 100, 'one stack, one deposit')
        assert(M.unitDeposit(42, 'commodity', 3) == 5, 'a stack of 20 shares 1 silver: ' .. M.unitDeposit(42, 'commodity', 3))''')

    def test_the_games_own_deposit_wins(self):
        run(BASE + '''addItem(43, 'Copper Bar', 50, 'commodity')
        C_AuctionHouse.CalculateCommodityDeposit = function(id, d, qty) return 7 * qty end
        F.AH.resetDeposits()
        assert(T.depositFor('c:43', 20, 3) == 140 and M.unitDeposit(43, 'commodity', 3) == 7)''')

    def test_a_cheap_commodity_is_judged_by_the_sniper(self):
        # V15-a: 1 silver a unit took the whole margin of a 80c commodity; one deposit per stack does not.
        run(BASE + '''addItem(44, 'Cheap Herb', 3, 'commodity')
        local h = F.Data.market(F.db, F.Engine.scope()).history
        h['c:44'] = { flow = { hours = 24, sold = { 34, 34, 34, 34 }, pairs = 4, at = now, market = 80 },
            scan = { at = now, market = 80 } }
        local limit = F.Sniper.threshold('c:44', 44, h)
        assert(limit and limit > 40, 'a 40c unit is worth sniping: ' .. tostring(limit))''')


class FightPlanDepositTests(unittest.TestCase):
    """V15-c: the plan gives up on a cancel what the cancel books."""

    def test_the_plans_cancel_is_what_the_cancel_books(self):
        run(test_audit.AntiUndercutTests.PLAN + '''local plan = T.fightPlans()[1]
        local a
        for _, o in ipairs(T.owned) do if o.auctionID == 6 then a = o end end
        assert(T.cancelAuction(a))
        local rec = F.Data.char(F.db, F.Engine.owner()).cancels[6]
        assert(rec and rec.lost == plan.cancel, rec and rec.lost .. ' vs ' .. plan.cancel)''')


if __name__ == "__main__":
    unittest.main()
