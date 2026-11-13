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


    def test_returns_booked_as_purchases_are_recounted(self):
        run(LOTS + '''c.journal = {
            { at = now - 100, kind = 'buy', key = 'c:10', name = 'Linen Cloth', qty = 10, amount = 1000 },
            { at = now - 50, kind = 'buy', key = 'c:10', name = 'Linen Cloth', qty = 20, amount = 4000 },
            { at = now - 45, kind = 'buy', key = 'c:10', name = 'Linen Cloth', qty = 20, amount = 4000 },
            { at = now - 30, kind = 'sell', key = 'c:10', name = 'Linen Cloth', qty = 5, amount = 900, profit = 0 },
            { at = now - 20, kind = 'expired', name = 'Linen Cloth', qty = 5, amount = 0 },
        }
        c.lots, c.positions, c.stats, c.recount, c.returnsMarked = nil, {}, {}, nil, nil
        T.recount()
        assert(c.journal[2].kind == 'return' and c.journal[3].kind == 'return' and c.journal[1].kind == 'buy')
        assert(c.journal[2].posted == 4000 and c.journal[2].amount > 0, 'the deposit lost')
        local p = c.positions['c:10']
        assert(p.qty == 5, 'only the real purchase is stock: ' .. p.qty)
        local s = c.stats['c:10']
        assert(s.bought == 10 and s.spent == 1000 and s.lost > 0, s.spent)
        -- the real price (500 for 5) plus a share of the deposits the returned posts lost
        assert(c.journal[4].profit < 400 and c.journal[4].profit > 0, 'profit at the real cost: ' .. c.journal[4].profit)
        local lot = F.Data.lots(c)[1]
        assert(#F.Data.lots(c) == 1 and lot.qty == 10 and lot.lost == s.lost)
        assert(c.recount == T.RECOUNT)''')

    def test_items_the_journal_never_mentions_are_kept(self):
        run(LOTS + '''c.journal = {}
        c.positions = { ['i:30'] = { qty = 2, cost = 500, name = 'Linen Bag' } }
        c.stats = { ['i:30'] = { name = 'Linen Bag', bought = 2, spent = 500, sold = 0, earned = 0, profit = 0, days = 0 } }
        c.recount = nil
        T.recount()
        assert(c.positions['i:30'].qty == 2 and c.stats['i:30'].spent == 500)''')


    def test_the_journal_has_a_view_per_way_of_dealing(self):
        run(LOTS + '''F.Data.addPosition(c, 'i:30', 'Linen Bag', 1, 20000, 'flip', 29900, now - 7200)
        F.Data.addPosition(c, 'c:10', 'Linen Cloth', 5, 100, 'vendor', nil, now - 3600)
        F.Data.addPosition(c, 'i:31', 'Silk Bag', 1, 500, 'flip', nil, now)
        c.lots[#c.lots].bid = true
        local function shown()
            local n = 0
            for _, r in ipairs(UI.lotTable.rows) do if r:IsShown() then n = n + 1 end end
            return n
        end
        UI.show('journal'); UI.refresh(); assert(shown() == 3 and UI.journalFilter == 'all')
        UI.show('journal:flip'); UI.refresh(); assert(shown() == 1, shown())
        UI.show('journal:vendor'); UI.refresh(); assert(shown() == 1)
        UI.show('journal:bid'); UI.refresh(); assert(shown() == 1)
        assert(UI.groupOf('journal:bid').label == 'Analytics')''')


    def test_different_purchase_methods_keep_separate_lots(self):
        run(LOTS + '''F.Data.addPosition(c, 'i:30', 'Linen Bag', 1, 3000, 'flip', nil, now)
        F.Data.addPosition(c, 'i:30', 'Linen Bag', 1, 1000, 'vendor', nil, now + 1)
        F.Data.addPosition(c, 'i:30', 'Linen Bag', 1, 500, 'vendor', nil, now + 2, true)
        assert(#c.lots == 3, 'purchase methods must stay separate')
        assert(UI.lotKind(c.lots[1]) == 'flip' and UI.lotKind(c.lots[2]) == 'vendor'
            and UI.lotKind(c.lots[3]) == 'bid')''')

    def test_recount_preserves_each_purchases_own_bid_and_mode(self):
        run(LOTS + '''c.lots = {
            {key='i:30', at=now-7200, mode='flip'},
            {key='i:30', at=now-3600, mode='vendor', bid=true},
            {key='i:30', at=now, mode='vendor'},
        }
        c.journal = {
            {at=now-7200, kind='buy', key='i:30', qty=1, amount=3000},
            {at=now-3600, kind='buy', key='i:30', qty=1, amount=500, mode='vendor', bid=true},
            {at=now, kind='buy', key='i:30', qty=1, amount=1000, mode='vendor'},
        }
        assert(F.Data.recount(c, function() return 0 end))
        assert(UI.lotKind(c.lots[1]) == 'flip', 'resale must not become a bid')
        assert(UI.lotKind(c.lots[2]) == 'bid')
        assert(UI.lotKind(c.lots[3]) == 'vendor', 'vendor must not become a bid')''')

    def test_lots_rebuilt_from_journal_keep_purchase_classification(self):
        run(LOTS + '''c.lots = nil
        c.journal = {
            {at=now, kind='buy', key='i:30', qty=1, amount=3000, mode='flip'},
            {at=now+1, kind='buy', key='i:30', qty=1, amount=500, mode='vendor', bid=true},
            {at=now+2, kind='buy', key='i:30', qty=1, amount=1000, mode='vendor'},
        }
        local lots=F.Data.lots(c)
        assert(#lots == 3 and UI.lotKind(lots[1]) == 'flip'
            and UI.lotKind(lots[2]) == 'bid' and UI.lotKind(lots[3]) == 'vendor')''')

    def test_a_won_bid_is_marked_when_another_items_lot_is_last(self):
        run(LOTS + '''F.Data.addPosition(c, 'i:30', 'Linen Bag', 1, 500, 'vendor', nil, now-10, true)
        F.Data.addPosition(c, 'c:10', 'Linen Cloth', 1, 50, 'vendor', nil, now-5)
        c.bids = {[77]={key='i:30',name='Linen Bag',qty=1,amount=500,value=2000,at=now-20}}
        assert(F.Bids.won('Linen Bag', true))
        assert(#c.lots == 2 and c.lots[1].qty == 2 and c.lots[1].bid)
        local e=c.journal[#c.journal]
        assert(e.bid and e.mode == 'vendor')''')


    def test_recount_does_not_confuse_same_second_purchases(self):
        run(LOTS + '''c.lots = {
            {key='i:30', at=now, mode='flip'},
            {key='i:30', at=now, mode='vendor', bid=true},
        }
        c.journal = {
            {at=now, kind='buy', key='i:30', qty=1, amount=3000, mode='flip'},
            {at=now, kind='buy', key='i:30', qty=1, amount=500, mode='vendor', bid=true},
        }
        assert(F.Data.recount(c, function() return 0 end))
        assert(#c.lots == 2 and UI.lotKind(c.lots[1]) == 'flip' and UI.lotKind(c.lots[2]) == 'bid')''')

    def test_old_bid_log_recovers_exact_purchase_only(self):
        run(LOTS + '''F.Data.addPosition(c,'i:30','Linen Bag',1,1900,'other',nil,now)
        F.Data.addPosition(c,'i:30','Linen Bag',1,2000,'other',nil,now+3600)
        c.bidLog={{outcome='won',key='i:30',qty=1,amount=1900,ended=now}}
        local lots=F.Data.lots(c)
        assert(lots[1].bid and not lots[2].bid,'historical bid must use amount, units and time')''')

    def test_loss_is_shared_by_affected_units_across_lots(self):
        run(LOTS + '''F.Data.addPosition(c,'i:30','Linen Bag',1,100,'flip',nil,now-7200)
        F.Data.addPosition(c,'i:30','Linen Bag',3,600,'flip',nil,now)
        F.Data.addCost(c,'i:30',300,now,3)
        assert(c.lots[1].lost==100 and c.lots[2].lost==200,'only three returned units lost this deposit')''')

    def test_loss_evidence_separates_estimates_and_missing_events(self):
        run(LOTS + '''c.stats['i:30']={lost=500}
        c.journal={{kind='expired',key='i:30',amount=100},
            {kind='expired',key='i:30',amount=200,estimated=true}}
        local e=F.Data.lossEvidence(c,'i:30')
        assert(e.recorded==100 and e.estimated==200 and e.unattributed==200)''')

    def test_absent_vendor_stock_has_unknown_outcome(self):
        run(LOTS + '''F.Data.addPosition(c,'i:30','Linen Bag',1,100,'vendor',nil,now)
        UI.show('journal:vendor');UI.refreshJournal()
        assert(UI.lotTable.rows[1].cols[6]:GetText():find('Unconfirmed'), 'absence is not proof of a sale')''')

    def test_estimated_losses_mark_the_profit_as_estimated(self):
        run(LOTS + '''F.Data.addPosition(c,'i:30','Linen Bag',1,100,'flip',nil,now)
        F.Data.addCost(c,'i:30',100,now,1)
        F.Data.log(c,{kind='expired',key='i:30',qty=1,amount=100,estimated=true,at=now})
        F.Data.sale(c,'i:30','Linen Bag',1,500,now)
        UI.show('journal');UI.refreshJournal()
        local r=UI.lotTable.rows[1]
        assert(r.cols[4]:GetText():find('~') and r.cols[6]:GetText():find('~'))''')

    def test_ambiguous_old_bid_matches_stay_unclassified(self):
        run(LOTS + '''c.lotsJoined=1
        c.lots={{key='i:30',at=now,qty=1,cost=1900},{key='i:30',at=now,qty=1,cost=1900}}
        c.bidLog={{outcome='won',key='i:30',qty=1,amount=1900,ended=now}}
        F.Data.lots(c);assert(not c.lots[1].bid and not c.lots[2].bid)''')


if __name__ == '__main__':
    unittest.main()
