"""Review fixes in Data.lua: a recount corrects the books and never rebuilds them from the journal;
purchase lots, losses and purchase records."""
import unittest

from test_addon import SETUP, run

DATA = SETUP + '''local F, D, T = ForeverFlip, ForeverFlip.Data, ForeverFlip.Trade
local c = D.char(F.db, F.Engine.owner())
c.journal, c.positions, c.stats, c.lots, c.daily = {}, {}, {}, nil, nil
local today = math.floor(now / 86400)
-- Books an entry as the addon did when it happened: stock, statistics, lots, daily totals, journal.
local function book(e)
    if e.kind == 'buy' then
        local mode = e.mode or (e.merchant and 'flip') or 'other'
        D.addPosition(c, e.key, e.name, e.qty, e.amount, mode, nil, e.at, e.bid)
    elseif e.kind == 'sell' or e.kind == 'vendor' then
        e.profit = e.amount - D.sale(c, e.key, e.name, e.qty, e.amount, e.at)
    end
    D.log(c, e)
    return e
end
-- An entry of Linen Cloth; a buy without a mode is what a buyer invoice booked.
local function cloth(at, kind, qty, amount, mode)
    return book({ at = at, kind = kind, key = 'c:10', name = 'Linen Cloth', qty = qty, amount = amount, mode = mode })
end
-- A busy trader: 520 later purchases of another item push the oldest entries out of the journal.
local function busy(from)
    for i = 1, 520 do
        book({ at = from + i * 60, kind = 'buy', key = 'i:31', name = 'Silk Bag', qty = 1, amount = 100, mode = 'flip' })
    end
end
local function recount(deposit)
    D.markReturns(c.journal)
    return D.recount(c, deposit or function(_, qty) return 10 * qty end)
end
local function lotsOf(key)
    local out = {}
    for _, lot in ipairs(c.lots) do
        if lot.key == key then
            out[#out + 1] = lot
        end
    end
    return out
end
'''


class RecountTests(unittest.TestCase):
    def test_a_recount_keeps_what_the_journal_no_longer_holds(self):
        run(DATA + '''local t0 = now - 20 * 86400
        cloth(t0, 'buy', 200, 12000, 'flip')
        cloth(t0 + 86400, 'sell', 50, 7500)
        busy(t0 + 2 * 86400)
        local sale = cloth(now - 50, 'sell', 20, 3000)
        assert(c.journal[1].key == 'i:31', 'the cloth purchase left the journal')
        local function books()
            local p, s, days = c.positions['c:10'], c.stats['c:10'], 0
            for _ in pairs(c.daily) do days = days + 1 end
            return string.format('stock %s/%s bought %d spent %d profit %d lots %d days %d',
                tostring(p and p.qty), tostring(p and p.cost), s.bought, s.spent, s.profit, #c.lots, days)
        end
        local before = books()
        assert(recount())
        assert(books() == before, before .. ' became ' .. books())
        assert(sale.profit == 1800, 'the sale keeps its real cost')
        local lots = lotsOf('c:10')
        assert(#lots == 1 and lots[1].left == 130 and lots[1].sold == 70, 'the old purchase keeps its lot')
        assert(c.daily[math.floor(t0 / 86400)].spent == 12000, 'days before the journal stay')''')

    def test_returns_leave_the_books_and_the_sales_since_get_their_real_cost(self):
        # The cloth was bought before the journal's window; inside it, 40 of it were posted and the
        # cancelled posts' mail booked as two purchases (2.0.0-beta.1); 30 sold after that.
        for kept in ('true', 'false'):
            with self.subTest(lots_and_days_kept=kept):
                run(DATA + '''local kept = ''' + kept + '''
                cloth(now - 20 * 86400, 'buy', 200, 12000, 'flip')
                busy(now - 19 * 86400)
                cloth(now - 90, 'post', 40, 8000)
                local r1, r2 = cloth(now - 50, 'buy', 20, 4000), cloth(now - 45, 'buy', 20, 4000)
                local sale = cloth(now - 30, 'sell', 30, 6000)
                assert(sale.profit == 3500 and c.positions['c:10'].qty == 210)
                if not kept then
                    c.lots, c.daily = nil, nil -- a character saved before lots and daily totals existed
                end
                -- No deposit estimate yet: the returns leave the books at once, the estimates wait.
                assert(not recount(function() return nil end))
                local p, s = c.positions['c:10'], c.stats['c:10']
                assert(r1.kind == 'return' and r2.kind == 'return' and r1.posted == 4000 and r1.amount == 0)
                assert(p.qty == 170 and p.cost == 10200, p.qty .. ' for ' .. p.cost)
                assert(s.bought == 200 and s.spent == 12000 and (s.lost or 0) == 0)
                assert(sale.profit == 4200 and s.profit == 4200, 'sold at the real cost: ' .. sale.profit)
                assert(D.recount(c, function(_, qty) return 10 * qty end), 'the estimates are booked')
                assert(r1.amount == 200 and r1.estimated and r2.amount == 200)
                assert(p.qty == 170 and p.cost == 10600 and s.lost == 400 and s.bought == 200, p.cost)
                local d = D.daily(c)[today]
                assert(d.spent == 0 and d.buys == 0 and d.profit == 4200 and d.cost == 1800, d.spent .. ' ' .. d.profit)
                local lots = lotsOf('c:10')
                if kept then
                    assert(#lots == 1 and lots[1].qty == 200 and lots[1].left == 170 and lots[1].lost == 400)
                else
                    assert(#lots == 0, 'lots built from the journal hold no returns')
                end
                assert(D.recount(c, function(_, qty) return 10 * qty end))
                assert(p.qty == 170 and p.cost == 10600 and s.lost == 400, 'once')''')

    def test_sales_given_to_returned_units_move_to_the_next_lot(self):
        run(DATA + '''cloth(now - 3000, 'buy', 10, 1000, 'flip')
        cloth(now - 2000, 'post', 30, 6000)
        cloth(now - 1000, 'buy', 10, 2000)
        cloth(now - 995, 'buy', 10, 2000)
        cloth(now - 50, 'buy', 10, 1000, 'flip')
        local sale = cloth(now - 20, 'sell', 15, 3000)
        assert(#lotsOf('c:10') == 3 and lotsOf('c:10')[2].sold == 5, 'first in, first out took returned units')
        assert(recount())
        local lots = lotsOf('c:10')
        local a, b = lots[1], lots[2]
        assert(#lots == 2 and a.sold == 10 and a.left == 0, 'the returns had a lot of their own')
        assert(b.qty == 10 and b.sold == 5 and b.left == 5 and a.received + b.received == 3000)
        local p = c.positions['c:10']
        assert(p.qty == 5 and p.cost == 500 + 200 and sale.profit == 1500, p.cost .. ' ' .. sale.profit)''')

    def test_a_returns_estimate_is_not_booked_twice_for_a_cancel_outside_the_journal(self):
        run(DATA + '''cloth(now - 100, 'buy', 40, 4000, 'flip')
        cloth(now - 90, 'post', 40, 8000)
        D.addCost(c, 'c:10', 250, now - 80, 40) -- a cancel made before cancels were logged
        cloth(now - 50, 'buy', 20, 4000)
        cloth(now - 45, 'buy', 20, 4000)
        assert(recount())
        local p, s = c.positions['c:10'], c.stats['c:10']
        assert(c.journal[3].amount == 200 and c.journal[4].amount == 200, 'each return shows its estimate')
        assert(s.lost == 400 and p.cost == 4400 and p.qty == 40, 'only 150 beyond that cancel: ' .. s.lost)''')

    def test_a_recount_keeps_each_purchases_own_mode(self):
        # An invoice purchase ('other'), then one from a merchant for resale 10 minutes later: both
        # journal entries were logged without a mode.
        run(DATA + '''book({ at = now - 700, kind = 'buy', key = 'i:30', name = 'Linen Bag', qty = 1, amount = 25000 })
        book({ at = now - 100, kind = 'buy', key = 'i:30', name = 'Linen Bag', qty = 1, amount = 15000, merchant = true })
        assert(c.positions['i:30'].mode == 'flip')
        local lots = #c.lots
        assert(recount())
        assert(c.positions['i:30'].mode == 'flip', 'resale stock must stay resale stock')
        assert(#c.lots == lots and c.lots[1].mode == 'other')''')

    def test_returns_an_older_recount_took_out_are_not_taken_out_again(self):
        # A recount of an earlier version found this return and left the books without it.
        run(DATA + '''cloth(now - 100, 'buy', 10, 1000, 'flip')
        cloth(now - 90, 'post', 40, 8000)
        local r = cloth(now - 50, 'buy', 20, 4000)
        r.kind, r.posted, r.amount, r.estimated = 'return', r.amount, 150, true
        local p, s = c.positions['c:10'], c.stats['c:10']
        p.qty, p.cost, s.bought, s.spent = 10, 1000, 10, 1000
        assert(recount())
        assert(c.positions['c:10'] == p and p.qty == 10 and p.cost == 1000 and s.bought == 10 and s.spent == 1000)''')


class MarkReturnsTests(unittest.TestCase):
    def test_only_invoice_purchases_of_own_posts_are_returns(self):
        run(DATA + '''local post = { at = now - 300, kind = 'post', key = 'c:10', qty = 40, amount = 8000 }
        local function marked(extra, first)
            local a = { at = now - 100, kind = 'buy', key = 'c:10', qty = 20, amount = 4000 }
            local b = { at = now - 99.6, kind = 'buy', key = 'c:10', qty = 20, amount = 4000 }
            for k, v in pairs(extra or {}) do
                a[k], b[k] = v, v
            end
            return #D.markReturns({ first or post, a, b })
        end
        assert(marked() == 2, 'the mail of two cancelled posts')
        assert(marked({ merchant = true }) == 0, 'bought from a merchant')
        assert(marked({ mode = 'flip' }) == 0, 'bought by ForeverFlip')
        assert(marked({ bid = true, mode = 'flip' }) == 0, 'won bids')
        assert(marked(nil, { at = now - 300, kind = 'sell', key = 'c:10', qty = 40, amount = 8000 }) == 0,
            'two buyer invoices of an item never posted')
        assert(marked(nil, { at = now - 300, kind = 'post', key = 'c:10', qty = 40, amount = 6000 }) == 0,
            'posted at another price')
        assert(marked(nil, { at = now - 300, kind = 'post', key = 'c:10', qty = 10, amount = 2000 }) == 0,
            'fewer units posted')''')


class LotTests(unittest.TestCase):
    def test_open_lots_are_never_dropped_past_the_cap(self):
        run(DATA + '''local t0 = now - 400 * 3600
        D.addPosition(c, 'i:30', 'Linen Bag', 10, 1000, 'flip', nil, t0)
        local slow = c.lots[1]
        for i = 1, 300 do
            local key = 'c:' .. (1000 + i)
            D.addPosition(c, key, 'Item ' .. i, 1, 50, 'flip', nil, t0 + i * 3600)
            if i <= 150 then
                D.sale(c, key, 'Item ' .. i, 1, 80, t0 + i * 3600 + 60)
            end
        end
        assert(#c.lots == D.LOTS and c.lots[1] == slow, 'the slow seller still in stock keeps its lot')
        assert(c.lots[2].key == 'c:1002', 'the oldest sold-out lot went')
        D.sale(c, 'i:30', 'Linen Bag', 10, 2000, now)
        assert(slow.left == 0 and slow.sold == 10 and slow.received == 2000)''')

    def test_lot_repairs_run_once_per_lots_table(self):
        run(DATA + '''D.addPosition(c, 'i:30', 'Linen Bag', 1, 1900, 'other', nil, now)
        local reads = 0
        local won = { outcome = 'won', key = 'i:30', qty = 1, amount = 1900, ended = now }
        c.bidLog = { setmetatable({}, { __index = function(_, k) reads = reads + 1 return won[k] end }) }
        D.lots(c)
        assert(c.lots[1].bid, 'an old win marks its lot')
        local first = reads
        for _ = 1, 5 do D.lots(c) end
        assert(reads == first, 'checked again on every call: ' .. (reads - first))
        D.addPosition(c, 'i:30', 'Linen Bag', 1, 1900, 'vendor', nil, now + 9)
        c.bidLog[2] = { outcome = 'won', key = 'i:30', qty = 1, amount = 1900, ended = now + 9 }
        D.lots(c)
        assert(c.lots[2].bid, 'a win logged later is looked at')
        c.lots = { c.lots[1], { id = 9, key = 'i:30', at = now - 99, qty = 1, cost = 5, left = 1, sold = 0 } }
        c.lots[1].bid = nil
        D.lots(c)
        assert(c.lots[1].bid and c.lots[2].events and c.lots[2].historyIncomplete, 'a new lots table is checked')''')


class LossTests(unittest.TestCase):
    def test_an_infinite_cost_is_no_cost(self):
        run(DATA + '''D.addPosition(c, 'i:30', 'Linen Bag', 1, 20000, 'flip', nil, now)
        D.addCost(c, 'i:30', math.huge, now, 1)
        D.addCost(c, 'i:30', -math.huge, now, 1)
        assert(c.positions['i:30'].cost == 20000 and not c.stats['i:30'].lost)''')

    def test_a_loss_without_stock_reaches_the_days_profit_once(self):
        run(DATA + '''-- a looted bag posted and expired: no stock, so its deposit left the profit at once
        D.addCost(c, 'i:30', 100, now, 1)
        local e = book({ at = now, kind = 'expired', key = 'i:30', name = 'Linen Bag', qty = 1, amount = 100 })
        assert(e.profit == -100 and c.stats['i:30'].profit == -100 and D.daily(c)[today].profit == -100)
        assert(F.Analytics.results(7, now).profit == -100, 'the overview counts it')
        -- a loss on stock joins its cost: the day counts it with the sale
        cloth(now, 'buy', 1, 1000, 'flip')
        D.addCost(c, 'c:10', 50, now, 1)
        local x = cloth(now, 'expired', 1, 50)
        assert(x.profit == nil and c.daily[today].profit == -100, 'not twice')
        cloth(now, 'sell', 1, 1200)
        assert(c.daily[today].profit == -100 + 150)
        -- a post that expired before deposits were booked, of an item no longer held
        local old = book({ at = now, kind = 'expired', key = 'i:32', name = 'Wool Bag', qty = 2, amount = 0 })
        assert(recount())
        assert(old.amount == 20 and old.profit == -20 and c.daily[today].profit == 30, c.daily[today].profit)
        local live = c.daily[today].profit
        c.daily = nil
        assert(D.daily(c)[today].profit == live, 'daily totals built from the journal agree')''')


class JournalTests(unittest.TestCase):
    def test_purchases_name_their_auction_house(self):
        run(DATA + '''local e = cloth(now, 'buy', 1, 100, 'flip')
        assert(e.scope == F.Engine.scope(), tostring(e.scope))
        local sold = cloth(now, 'sell', 1, 200)
        assert(sold.scope == nil, 'only purchases')
        local kept = { at = now, kind = 'buy', key = 'c:10', qty = 1, amount = 1, scope = 'Elsewhere-Horde' }
        D.log(c, kept)
        assert(kept.scope == 'Elsewhere-Horde')''')


if __name__ == '__main__':
    unittest.main()
