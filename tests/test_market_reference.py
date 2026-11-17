"""T24: the market reference of an item, from ForeverFlip's own data.

Three sources, never mixed: the player's own full scans (the only source of what was listed at a
scan), shared community scans (observations) and an external slot that stays empty (Undermine
Exchange documents no API for WoW Forever). F.Market.marketReference gives the 14-day median and
mean per source, the trend over 3, 7 and 14 days with its sample size, and an undervalued flag that
is never raised from too few days, unreliable sales data or sources that disagree. The tooltip and
the history window show it for the open house only."""

import re
import unittest

from test_addon import SETUP, run

BASE = SETUP + '''local F, M = ForeverFlip, ForeverFlip.Market
local today = math.floor(now / 86400)
-- A reliable sales sample: pairs and hours above the thresholds, measured now.
local function reliable(h)
    M.recordSales(h, { [1000] = 5 }, 24 * 3600, now)
    h.sales.pairs = 8
    return h
end
-- `n` days of prices ending today, `own` / `shared` write the per-source fields too.
local function days(n, price, own, shared)
    local out = {}
    for i = n - 1, 0, -1 do
        local v = type(price) == 'function' and price(i) or price
        out[#out + 1] = { d = today - i, m = v, min = v, lm = own and v or nil, cm = shared and v or nil }
    end
    return out
end
'''


def clean(text):
    return re.sub(r'\|c[0-9a-fA-F]{8}|\|r', '', text)


class StatsTests(unittest.TestCase):
    def test_median_mean_and_the_window(self):
        run(BASE + '''local d = { { d = today - 20, m = 99999 }, { d = today - 3, m = 100 }, { d = today - 2, m = 300 },
            { d = today - 1, m = 200 }, { d = today, m = 0 }, { d = today + 1, m = 5 } }
        local s = M.priceStats(M.dayPrices(d, now, 14, 'm'))
        assert(s.n == 3, 'older than 14 days, zero and future days are left out: ' .. s.n)
        assert(s.median == 200 and s.mean == 200 and s.low == 100 and s.high == 300)
        s = M.priceStats(M.dayPrices({ { d = today - 1, m = 100 }, { d = today, m = 201 } }, now, 14, 'm'))
        assert(s.median == 151 and s.mean == 151, s.median)
        assert(M.priceStats({}).n == 0 and M.priceStats({}).median == nil)''')

    def test_trend_with_its_sample_size(self):
        run(BASE + '''local pts = M.dayPrices(days(14, function(i) return 1000 + (13 - i) * 10 end), now, 14, 'm')
        local t = M.trend(pts, now, 14)
        assert(t.n == 14 and math.abs(t.change - 0.13) < 1e-9, t.change)
        assert(t.slope > 0, 'rising prices: positive slope')
        local t3 = M.trend(pts, now, 3)
        assert(t3.n == 3 and math.abs(t3.change - (1130 / 1110 - 1)) < 1e-9)
        local down = M.trend(M.dayPrices(days(7, function(i) return 1000 + i * 50 end), now, 7, 'm'), now, 7)
        assert(down.change < 0 and down.slope < 0)
        local none, n = M.trend(M.dayPrices(days(2, 1000), now, 14, 'm'), now, 7)
        assert(none == nil and n == 2, 'two days are no trend')''')


class SourceTests(unittest.TestCase):
    def test_own_and_community_apart(self):
        run(BASE + '''local h = { days = {} }
        for i = 6, 0, -1 do
            h.days[#h.days + 1] = { d = today - i, m = 1000, lm = 1000, cm = i < 4 and 1100 or nil }
        end
        h.scan = { at = now - 600, market = 1000, low = 700 }
        h.units = 42
        h.shared = { at = now - 3600, m = 1100, min = 900, n = 30, from = 'community' }
        local r = M.marketReference(h, now)
        assert(r.own.n == 7 and r.own.median == 1000 and r.own.seen == now - 600)
        assert(r.community.n == 4 and r.community.median == 1100 and r.community.seen == now - 3600)
        assert(r.community.cheapest == 900 and r.community.units == 30)
        assert(r.combined.n == 7 and r.combined.median == 1000)
        assert(r.current.price == 700 and r.current.units == 42 and r.current.at == now - 600)
        assert(math.abs(r.current.vsMedian + 0.3) < 1e-9)
        assert(r.external.available == false and r.external.reason == 'no_api')
        assert(math.abs(r.gap - 0.1) < 1e-9 and not r.disagree)''')

    def test_legacy_days_count_only_combined(self):
        run(BASE + '''local r = M.marketReference({ days = days(6, 500) }, now)
        assert(r.combined.n == 6 and r.own.n == 0 and r.community.n == 0)
        assert(r.current == nil and r.under.reason == 'no_current', 'no own scan: nothing is current')''')

    def test_scans_write_the_own_and_shared_fields(self):
        run(BASE + '''fullScan()
        local h = F.Data.market(F.db, F.Engine.scope()).history['c:10']
        local d = h.days[#h.days]
        assert(d.lm and d.lm == d.m and d.lmin == 60 and h.scan.low == 60, tostring(d.lm))
        assert(d.cm == nil)
        F.Share.mergeDay(h, today - 1, { m = 77, min = 50, n = 3 })
        F.Share.mergeDay(h, today, { m = 88, min = 40, n = 3 })
        assert(h.days[#h.days - 1].cm == 77 and h.days[#h.days - 1].lm == nil)
        d = h.days[#h.days]
        assert(d.cm == 88 and d.cmin == 40 and d.lmin == 60, 'shared fields beside the own ones')''')


class UndervaluedTests(unittest.TestCase):
    def test_flagged_with_enough_days_and_reliable_data(self):
        run(BASE + '''local h = reliable({ days = days(7, 1000, true) })
        h.scan = { at = now - 600, market = 1000, low = 600 }
        local r = M.marketReference(h, now)
        assert(r.under.flagged and math.abs(r.under.ratio - 0.6) < 1e-9, tostring(r.under.reason))
        h.scan.low = 900
        r = M.marketReference(h, now)
        assert(not r.under.flagged and r.under.reason == 'no_gap')''')

    def test_never_from_too_few_days(self):
        run(BASE + '''local h = reliable({ days = days(4, 1000, true) })
        h.scan = { at = now - 600, market = 1000, low = 100 }
        local r = M.marketReference(h, now)
        assert(not r.under.flagged and r.under.reason == 'few_days' and r.under.days == 4 and r.under.need == 5)''')

    def test_never_without_reliable_data_or_with_an_old_scan(self):
        run(BASE + '''local h = { days = days(10, 1000, true) }
        h.scan = { at = now - 600, market = 1000, low = 100 }
        local r = M.marketReference(h, now)
        assert(not r.under.flagged and r.under.reason == 'no_reliable', r.under.reason)
        reliable(h)
        h.scan.at = now - 3 * 3600
        r = M.marketReference(h, now)
        assert(not r.under.flagged and r.under.reason == 'old_scan', r.under.reason)''')

    def test_sources_that_disagree_are_no_signal_and_stop_the_median_strategy(self):
        run(BASE + '''local h = reliable({ days = {} })
        for i = 6, 0, -1 do
            h.days[#h.days + 1] = { d = today - i, m = 1000, lm = 1000, cm = 2000 }
        end
        h.scan = { at = now - 600, market = 1000, low = 500 }
        local r = M.marketReference(h, now)
        assert(r.disagree and math.abs(r.gap - 1) < 1e-9)
        assert(not r.under.flagged and r.under.reason == 'disagree')
        assert(M.sourcesDisagree(h, now))
        local d, why = M.evaluateMedian({ { unit = 300, qty = 2 } }, { kind = 'commodity', history = h, now = now,
            budget = 1000000, settings = { minProfit = 1, minROI = 0 } })
        assert(not d and why == 'sources_disagree', tostring(why))
        for _, day in ipairs(h.days) do day.cm = 1050 end
        assert(not M.sourcesDisagree(h, now))''')


TIP = '''
tooltipLines = {}
GameTooltip.itemLink = link(10)
for _, fn in ipairs(tooltipCalls) do fn(GameTooltip) end
return table.concat(tooltipLines, ' ## ')'''


class TooltipTests(unittest.TestCase):
    def test_the_tooltip_lines(self):
        text = clean(run(BASE + '''fullScan()
        local h = F.Data.market(F.db, F.Engine.scope()).history['c:10']
        local keep = h.days[#h.days]
        h.days = days(7, 100, true, true)
        h.days[#h.days].lmin = keep.lmin
        h.shared = { at = now - 3600, m = 100, min = 90, n = 12, from = 'community' }
        F.UI.referenceCache = {}''' + TIP))
        self.assertIn('References', text)
        self.assertIn('Community data = median 1s 00c · 7 d', text)
        self.assertIn('14-day median / mean = 1s 00c / 1s 00c', text)
        self.assertIn('Trend 3d / 7d / 14d = +0% / +0% / +0%', text)
        self.assertNotIn('available now', text)

    def test_other_houses_are_ignored(self):
        text = clean(run(BASE + '''fullScan()
        local other = F.Data.market(F.db, 'Elsewhere-Horde').history
        other['c:10'] = { days = days(10, 777777, true, true), scan = { at = now, market = 777777, low = 777777 },
            shared = { at = now, m = 777777, min = 777777, n = 5 } }
        F.UI.referenceCache = {}''' + TIP))
        self.assertIn('References', text)
        self.assertNotIn('77g', text)
        self.assertIn('Community data = no data', text)

    def test_out_of_date_data_show_no_reference(self):
        text = clean(run(BASE + '''fullScan()
        F.Data.market(F.db, F.Engine.scope()).scannedAt = F.Engine.clock() - 24 * 3600''' + TIP))
        self.assertIn('data out of date, not shown', text)
        self.assertNotIn('Market reference', text)

    def test_cached_per_item_until_the_scan_data_change(self):
        run(BASE + '''fullScan()
        local h = F.Data.market(F.db, F.Engine.scope()).history['c:10']
        local a = F.UI.referenceFor('c:10', h, now)
        assert(F.UI.referenceFor('c:10', h, now) == a, 'the same table while nothing changed')
        F.Data.market(F.db, F.Engine.scope()).scannedAt = now + 1
        assert(F.UI.referenceFor('c:10', h, now) ~= a, 'new scan data: built again')''')

    def test_the_history_window_shows_the_reference(self):
        text = clean(run(BASE + '''fullScan()
        F.UI.showHistory('c:10')
        return F.UI.historyFrame.reference:GetText()'''))
        self.assertIn('Market reference (14 days)', text)
        self.assertIn('Your scans: ', text)
        self.assertIn('Community: no data', text)
        self.assertIn('External: not available', text)


if __name__ == '__main__':
    unittest.main()
