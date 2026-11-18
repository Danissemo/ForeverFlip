"""Est./day of a plain item or commodity leans on similar items: the same key type at about its usual
price with about as many units listed (Market.peerCell, Deals.peerRate). One sale in a few hours
read as several a day and none as 0; the similar items' geometric mean fills in, never past the
upper limit of the item's own sales."""

import unittest

from test_addon import SETUP, run

# Five commodities that sold 2 units each in 6 hours at their usual price 1000, 10 units listed:
# 2 / (6 + 4) * 24 = 4.8 a day each. c:99 is like them and sold none.
BASE = SETUP + r'''local F, M, D = ForeverFlip, ForeverFlip.Market, ForeverFlip.Deals
local history = F.Data.market(F.db, F.Engine.scope()).history
local function item(sold)
    local s = { hours = 6, watched = 6, pairs = 24, at = now, b = sold > 0 and { [10] = sold, [11] = 1000 } or {} }
    return { scan = { at = now, market = 1000, above = { 10, 10, 8, 4 } }, sales = s }
end
for id = 101, 105 do history['c:' .. id] = item(2) end
history['c:99'] = item(0)
local function near(a, b) return math.abs(a - b) < 1e-9 end
'''


class PeerRateTests(unittest.TestCase):
    def test_similar_items_are_averaged_geometrically(self):
        run(SETUP + r'''local M = ForeverFlip.Market
        local sum = 4 * M.peerValue(0) + M.peerValue(99.9)
        local rate = M.peerRate(sum, 5)
        assert(math.abs(rate - 0.298) < 0.001, 'one fast seller does not make four slow ones fast: ' .. rate)
        assert(M.peerRate(sum, 4) == nil, 'fewer than M.PEER_MIN similar items: none')
        local band, listed = M.peerCell({ scan = { above = { 7 } } }, 1000)
        assert(band == 10 and listed == 3, band .. ' ' .. listed)
        assert(M.peerCell({}, nil) == nil)
        assert(M.withPeers(0, 0, 6) == 6, 'nothing watched: the similar items')
        assert(math.abs(M.withPeers(0, 8, 6) - 3) < 1e-9, 'M.PEER_HOURS watched with none sold: half')''')

    def test_an_item_with_no_sale_yet_reads_what_its_own_hours_allow(self):
        run(BASE + r'''local before = M.saleability(history['c:99'], 1000, now)
        assert(before.known and before.perDay == 0, 'its own sales alone: 0')
        local peer, n = D.peerRate('c:99', history['c:99'])
        assert(n == 5 and near(peer, 4.8), n .. ' ' .. tostring(peer))
        local sale = D.saleability('c:99', history['c:99'], 1000, now)
        local _, high = M.rateRange(0, 6)
        assert(high < 4.8 and near(sale.prior, high), 'capped at its own upper limit: ' .. sale.prior)
        assert(near(sale.perDay, M.withPeers(0, 6, high)) and sale.perDay > 0, sale.perDay)
        local dear = D.saleability('c:99', history['c:99'], 2000, now)
        assert(near(dear.prior, 2.4), 'at twice the usual price they count half: ' .. dear.prior)''')

    def test_an_item_does_not_count_itself_and_needs_five_others(self):
        run(BASE + r'''local _, n = D.peerRate('c:101', history['c:101'])
        assert(n == 5, 'four others and c:99: ' .. tostring(n))
        history['c:99'] = nil
        history['c:106'] = { scan = { at = now + 1, market = 1000, above = { 10, 10, 8, 4 } } }
        F.Scan.last = { at = now + 1 }
        assert(D.peerRate('c:101', history['c:101']) == nil, 'four others: nothing')
        local own = M.saleability(history['c:101'], 1000, now)
        assert(D.saleability('c:101', history['c:101'], 1000, now).perDay == own.perDay, 'unchanged')''')

    def test_other_kinds_and_far_cells_are_not_similar(self):
        run(BASE + r'''local far = { scan = { at = now, market = 1000, above = { 500, 500, 400, 200 } },
            sales = { hours = 6, watched = 6, pairs = 24, at = now, b = {} } }
        history['c:200'] = far
        assert(D.peerRate('c:200', far) == nil, 'fifty times as many listed: not alike')
        history['i:99'] = history['c:99']
        assert(D.peerRate('i:99', history['i:99']) == nil, 'items are not commodities')
        assert(D.peerRate('g:99:sword', history['c:99']) == nil, 'gear leans on its own kind')''')


if __name__ == '__main__':
    unittest.main()
