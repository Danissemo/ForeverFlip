"""T07: the price of an item over time in the price history window.

F.Market.priceSeries turns the daily history and the raw full scans into points in time order with
the stretches without data marked as gaps; F.Raw.pricePoints reads the cheapest unit of an item from
each raw scan; the window draws a line of textures above its daily bars."""

import unittest

from test_addon import SETUP, run

BASE = SETUP + '''local F, M = ForeverFlip, ForeverFlip.Market
local today = math.floor(now / 86400)
'''


class SeriesTests(unittest.TestCase):
    def test_days_and_scans_in_time_order_within_the_span(self):
        run(BASE + '''local days = {
            { d = today - 20, m = 999999, min = 1 },
            { d = today - 2, m = 1200, min = 900 },
            { d = today - 1, m = 1000, min = 800 },
            { d = today, m = 1100, min = 700 } }
        local scans = { { at = now - 60, unit = 650, n = 4 }, { at = now - 3600, unit = 600, n = 9 } }
        local s = M.priceSeries(days, scans, now)
        assert(not s.empty and #s.usual == 3, 'a day older than 14 days is left out')
        assert(s.usual[1].v == 1200 and s.usual[3].v == 1100 and s.usual[3].t <= now)
        assert(#s.cheap == 3 and s.cheap[3].v == 700)
        assert(#s.scans == 2 and s.scans[1].v == 600 and s.scans[1].n == 9, 'scans sorted by time')
        assert(s.low == 600 and s.high == 1200, s.low .. ' ' .. s.high)''')

    def test_stretches_without_data_are_gaps(self):
        run(BASE + '''local days = { { d = today - 10, m = 500 }, { d = today - 9, m = 520 }, { d = today - 2, m = 510 } }
        local s = M.priceSeries(days, {}, now)
        local inner
        for _, g in ipairs(s.gaps) do
            if g.from == s.usual[2].t and g.to == s.usual[3].t then inner = g end
        end
        assert(inner, 'seven days without a price are a gap')
        assert(s.gaps[1].from == s.from, 'the days before the first price are a gap')
        assert(s.gaps[#s.gaps].to == now, 'and the time since the last')
        assert(M.seriesJoined(s, s.usual[1].t, s.usual[2].t), 'neighbouring days are joined')
        assert(not M.seriesJoined(s, s.usual[2].t, s.usual[3].t), 'the line does not cross a gap')''')

    def test_no_data_is_empty(self):
        run(BASE + '''local s = M.priceSeries(nil, nil, now)
        assert(s.empty and s.low == nil and #s.gaps == 1)
        s = M.priceSeries({ { d = today, m = 0 } }, { { at = now, unit = 0 } }, now)
        assert(s.empty, 'zero prices are no data')''')


RAW = BASE + '''ForeverFlipRaw = { scans = {
    { scope = F.Engine.scope(), at = now - 900, rows = '10,5,500,,,3,0,c,\\n20,1,900,,,3,0,g,Northern Shortsword of Healing\\n10,2,300,,,3,1,c,\\n10,4,480,,,3,0,c,' },
    { scope = F.Engine.scope(), at = now - 1800, rows = '30,1,7000,,,3,0,i,\\n10,1,200,,,3,0,c,' },
    { scope = 'Other-Horde', at = now - 60, rows = '10,1,1,,,3,0,c,' },
} }
'''


class RawTests(unittest.TestCase):
    def test_the_cheapest_unit_of_each_scan_without_own_lots(self):
        run(RAW + '''local p = F.Raw.pricePoints(F.Engine.scope(), 10)
        assert(#p == 2, #p)
        assert(p[1].at == now - 1800 and p[1].unit == 200 and p[1].n == 1)
        assert(p[2].unit == 100 and p[2].n == 9, 'own lot left out: ' .. p[2].unit .. ' ' .. p[2].n)
        local gear = F.Raw.pricePoints(F.Engine.scope(), 20, 'northern shortsword of healing')
        assert(#gear == 1 and gear[1].unit == 900)
        assert(#F.Raw.pricePoints(F.Engine.scope(), 20, 'another name') == 0)''')

    def test_the_window_draws_the_line(self):
        run(RAW + '''local h = F.Data.market(F.db, F.Engine.scope()).history
        h['c:10'] = { days = { { d = today - 3, m = 120, min = 100, n = 5, s = 1 },
            { d = today - 2, m = 130, min = 110, n = 5, s = 1 }, { d = today, m = 125, min = 100, n = 5, s = 1 } } }
        F.UI.showHistory('c:10')
        local chart = F.UI.historyFrame.chart
        assert(chart.used > 10, 'a line of textures: ' .. chart.used)
        assert(not chart.empty:IsShown())
        h['c:30'] = { days = {} }
        ForeverFlipRaw = nil
        F.UI.showHistory('c:30')
        assert(chart.used == 0 and chart.empty:IsShown(), 'no prices: the chart says so')''')


if __name__ == '__main__':
    unittest.main()
