"""Purchase lots: what each purchase cost, lost on reposts and sold for; the floor counts it all."""
import unittest

from test_addon import SETUP, run

LOTS = SETUP + '''local F, T, UI = ForeverFlip, ForeverFlip.Trade, ForeverFlip.UI
local c = F.Data.char(F.db, F.Engine.owner())
'''


class PurchaseLotTests(unittest.TestCase):
    def test_sales_take_the_oldest_lot_first(self):
        run(LOTS + '''F.Data.addPosition(c, 'c:10', 'Linen Cloth', 2, 200, 'flip', 150, now - 3600) -- an hour apart: two lots
        F.Data.addPosition(c, 'c:10', 'Linen Cloth', 3, 450, 'flip', 150, now)
        F.Data.sale(c, 'c:10', 'Linen Cloth', 3, 600, now)
        local a, b = c.lots[1], c.lots[2]
        assert(a.sold == 2 and a.left == 0 and a.received == 400, 'the first lot sold out')
        assert(b.sold == 1 and b.left == 2 and b.received == 200)''')

    def test_a_lost_deposit_joins_the_lot_and_the_stock_cost(self):
        run(LOTS + '''F.Data.addPosition(c, 'i:30', 'Linen Bag', 1, 20000, 'flip', 29900, now)
        F.Data.addCost(c, 'i:30', 500, now)
        assert(c.positions['i:30'].cost == 20500 and c.positions['i:30'].lost == 500)
        assert(c.lots[1].lost == 500)
        F.Data.sale(c, 'i:30', 'Linen Bag', 1, 28405, now)
        local row = UI.lotRow(c.lots[1])
        assert(row.closed and row.profit == 28405 - 20000 - 500, tostring(row.profit))''')

    def test_an_expired_post_books_its_deposit(self):
        run(LOTS + '''F.Data.addPosition(c, 'i:30', 'Linen Bag', 1, 20000, 'flip', 29900, now)
        c.listings = { { key = 'i:30', name = 'Linen Bag', ids = { 7 }, open = 1, qty = 1, deposit = 300, at = now } }
        T.onFailedPost('Linen Bag', 1)
        assert(c.positions['i:30'].lost == 300 and c.journal[#c.journal].amount == 300)''')

    def test_the_floor_counts_lost_deposits_and_the_margin(self):
        run(LOTS + '''F.Data.addPosition(c, 'i:30', 'Linen Bag', 1, 20000, 'flip', 29900, now)
        F.Data.addCost(c, 'i:30', 1000, now)
        F.db.settings.sellMinReturn = 0.1
        local floor = T.floorFor({ key = 'i:30', kind = 'item' })
        assert(floor == F.Market.breakEven(21000 * 1.1, 1, 'item'), tostring(floor))
        assert(F.Market.net(floor, 1) >= 21000 * 1.1)''')

    def test_old_trades_become_lots_from_the_journal(self):
        run(LOTS + '''c.lots = nil
        c.journal = {
            { at = now - 50, kind = 'buy', key = 'c:10', name = 'Linen Cloth', qty = 4, amount = 400 },
            { at = now - 40, kind = 'expired', key = 'c:10', name = 'Linen Cloth', qty = 4, amount = 100 },
            { at = now - 30, kind = 'sell', key = 'c:10', name = 'Linen Cloth', qty = 4, amount = 760, profit = 360 },
        }
        local lot = F.Data.lots(c)[1]
        assert(lot and lot.sold == 4 and lot.received == 760 and lot.lost == 100)
        assert(UI.lotRow(lot).profit == 260)''')

    def test_the_journal_page_lists_the_lots(self):
        run(LOTS + '''F.Data.addPosition(c, 'i:30', 'Linen Bag', 1, 20000, 'flip', 29900, now)
        UI.show('journal'); UI.refresh()
        local r = UI.lotTable.rows[1]
        assert(r:IsShown() and r.cols[1]:GetText() == '0/1', r.cols[1]:GetText())
        assert(r.cols[6]:GetText():find('1 in stock'), r.cols[6]:GetText())''')


    def test_purchases_close_together_are_one_lot(self):
        run(LOTS + '''for i = 1, 6 do F.Data.addPosition(c, 'c:10', 'Linen Cloth', 104, 21657, 'flip', 300, now + i) end
        F.Data.addPosition(c, 'c:10', 'Linen Cloth', 2, 100, 'flip', 300, now + 3 * 3600)
        assert(#c.lots == 2 and c.lots[1].qty == 624 and c.lots[1].cost == 6 * 21657 and c.lots[1].left == 624)''')

    def test_saved_lots_bought_close_together_are_joined(self):
        run(LOTS + '''c.lotsJoined = nil
        c.lots = {
            { id = 1, key = 'c:10', at = now, qty = 4, cost = 400, left = 0, sold = 4, received = 600, lost = 10 },
            { id = 2, key = 'c:10', at = now + 9, qty = 4, cost = 400, left = 4, sold = 0, received = 0, lost = 0 },
            { id = 3, key = 'c:10', at = now + 7200, qty = 1, cost = 100, left = 1, sold = 0, received = 0, lost = 0 },
        }
        local lots = F.Data.lots(c)
        assert(#lots == 2 and lots[1].qty == 8 and lots[1].left == 4 and lots[1].received == 600 and lots[1].lost == 10)''')


if __name__ == '__main__':
    unittest.main()
