"""T32: derived sales statistics rebuilt from the raw full scans (Scan.rebuildStep, Data.commitStats,
Data.rollbackStats), the bias fixes (unknown-seller reprice, whole lots at half weight) and the
sample quality functions (Market.quality, sureLimits, calibration, rateCheck)."""

import unittest

from test_addon import SETUP, run

BASE = SETUP + '''local F, M, D, S, R = ForeverFlip, ForeverFlip.Market, ForeverFlip.Data, ForeverFlip.Scan, ForeverFlip.Raw
local scope = F.Engine.scope()
local market = D.market(F.db, scope)
local function seq(t) local s={} for _,l in ipairs(t) do s[#s+1]=l[1];s[#s+1]=l[2];s[#s+1]=l[3] end return s end
-- A raw scan of cloth (item 10): `lots` = { {unit, count}, ... }, all with more than 12 hours left.
local function rawScan(sc, at, lots, extra)
    local rows = {}
    for _, l in ipairs(lots) do rows[#rows+1] = '10,' .. l[2] .. ',' .. (l[1]*l[2]) .. ',,,3,0,c,' end
    for _, line in ipairs(extra or {}) do rows[#rows+1] = line end
    return { scope = sc, at = at, count = #rows, rows = table.concat(rows, '\\n') }
end
local function dump(v)
    if type(v) ~= 'table' then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys+1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, k in ipairs(keys) do out[#out+1] = tostring(k) .. '=' .. dump(v[k]) end
    return '{' .. table.concat(out, ',') .. '}'
end
local function rebuild()
    S.rebuild, S.rebuildChecked = nil, nil
    S.planRebuild(now)
    local n = 0
    while S.rebuild do
        S.rebuildStep(function() return false end)
        n = n + 1; assert(n < 10000, 'rebuild never ends')
    end
end
local t0 = now - 7200
-- Ten lots of five; a quarter-hour later one lot is bought in part (3 units) and one whole.
local A = {} for i = 1, 10 do A[i] = {20, 5} end
local B = {{20, 2}} for i = 1, 8 do B[#B+1] = {20, 5} end
local function standard()
    return { rawScan(scope, t0, A), rawScan(scope, t0 + 900, B), rawScan(scope, t0 + 1800, B) }
end
market.history['c:10'] = { sales = { pairs = 99, hours = 50, b = { [20] = 500 }, at = now }, days = { { d = math.floor(t0 / 86400), s = 77 } } }
market.statsVersion = nil
F.db.chars['Me-Realm'] = { journal = { { at = now, kind = 'buy', key = 'c:10', qty = 1, amount = 10 } } }
'''


class RebuildTests(unittest.TestCase):
    def test_rebuild_measures_from_raw_and_leaves_raw_journals_and_settings_alone(self):
        run(BASE + '''ForeverFlipRaw = { format = R.FORMAT, scans = standard() }
        local rawBefore, journalBefore, settingsBefore = dump(ForeverFlipRaw), dump(F.db.chars), dump(F.db.settings)
        rebuild()
        local h = market.history['c:10']
        assert(market.statsVersion == D.STATS_VERSION and market.statsBuilt.scans == 3)
        assert(h.sales and h.sales.pairs == 2, dump(h.sales))
        local part, lot = M.soldAbove(h.sales, 1)
        assert(math.abs(part - 3) < 0.01 and math.abs(lot - 5) < 0.01, part .. ' ' .. lot)
        assert(h.days[1].s == nil or h.days[1].s ~= 77, 'the old daily count is replaced')
        assert(market.statsBackup.items['c:10'].sales.pairs == 99, 'the old tables are kept')
        assert(dump(ForeverFlipRaw) == rawBefore and dump(F.db.chars) == journalBefore and dump(F.db.settings) == settingsBefore)''')

    def test_rebuild_is_idempotent(self):
        run(BASE + '''ForeverFlipRaw = { format = R.FORMAT, scans = standard() }
        rebuild()
        local first = dump(market.history['c:10'].sales) .. dump(market.history['c:10'].days)
        market.statsVersion = 0
        rebuild()
        local second = dump(market.history['c:10'].sales) .. dump(market.history['c:10'].days)
        assert(first == second, first .. ' / ' .. second)''')

    def test_a_scan_saved_twice_counts_once(self):
        run(BASE + '''ForeverFlipRaw = { format = R.FORMAT, scans = standard() }
        rebuild()
        local once = dump(market.history['c:10'].sales)
        local scans = standard(); scans[#scans+1] = rawScan(scope, t0 + 900, B)
        ForeverFlipRaw.scans = scans; market.statsVersion = 0
        rebuild()
        assert(dump(market.history['c:10'].sales) == once)''')

    def test_scans_of_another_realm_never_mix(self):
        run(BASE + '''ForeverFlipRaw = { format = R.FORMAT, scans = standard() }
        rebuild()
        local alone = dump(market.history['c:10'].sales)
        local scans = standard()
        scans[#scans+1] = rawScan('Other Realm-Horde', t0 + 2700, {{20, 1}})
        scans[#scans+1] = rawScan('Other Realm-Horde', t0 + 3600, {})
        ForeverFlipRaw.scans = scans; market.statsVersion = 0
        rebuild()
        assert(dump(market.history['c:10'].sales) == alone)
        assert(F.db.markets['Other Realm-Horde'] == nil, 'no house is made for raw scans alone')''')

    def test_an_item_no_raw_scan_covers_keeps_its_sales_marked_legacy(self):
        run(BASE + '''market.history['i:30'] = { sales = { pairs = 12, hours = 6, b = {}, at = now }, days = { { d = math.floor(now / 86400), s = 3 } } }
        M.bucketAdd(market.history['i:30'].sales.b, 2000, 3)
        ForeverFlipRaw = { format = R.FORMAT, scans = standard() }
        rebuild()
        local h = market.history['i:30']
        assert(h.sales.pairs == 12 and h.sales.legacy and h.days[1].s == 3, dump(h))
        assert(market.history['c:10'].sales.pairs == 2 and not market.history['c:10'].sales.legacy)
        local q = M.quality(h, 2000, now)
        assert(q.reason == 'legacy' and q.legacy and not q.reliable and q.perDay > 0, dump(q))
        assert(D.rollbackStats(market) and not h.sales.legacy and h.sales.pairs == 12, 'rollback clears the mark')
        h.sales.legacy = true
        for i = 1, M.RELIABLE_PAIRS do M.recordSales(h, {}, 900, now) end
        assert(not h.sales.legacy, 'measured again by the new formulas')''')

    def test_a_house_without_raw_scans_is_only_stamped(self):
        run(BASE + '''ForeverFlipRaw = nil
        local before = dump(market.history)
        rebuild()
        assert(dump(market.history) == before, dump(market.history))
        assert(market.statsVersion == D.STATS_VERSION and market.statsBackup == nil and S.rebuild == nil)''')

    def test_a_scan_with_unreadable_rows_takes_nothing_off_the_house(self):
        run(BASE + '''local junk = {} for i = 1, 20 do junk[i] = '' end
        ForeverFlipRaw = { format = R.FORMAT, scans = { rawScan(scope, t0, A), rawScan(scope, t0 + 900, B), rawScan(scope, t0 + 1800, {}, junk) } }
        rebuild()
        local part, lot = M.soldAbove(market.history['c:10'].sales, 1)
        assert(math.abs(part - 3) < 0.01 and lot == 0, part .. ' ' .. lot)''')

    def test_rollback_puts_back_the_old_tables_and_holds_them(self):
        run(BASE + '''ForeverFlipRaw = { format = R.FORMAT, scans = standard() }
        rebuild()
        assert(D.rollbackStats(market))
        local h = market.history['c:10']
        assert(h.sales.pairs == 99 and h.days[1].s == 77)
        assert(not h.sales.legacy)
        assert(D.statsCurrent(market), 'a rolled back house is not rebuilt again')
        S.rebuild, S.rebuildChecked = nil, nil; S.planRebuild(now); assert(S.rebuild == nil)
        assert(not D.rollbackStats(market), 'one generation only')''')

    def test_backups_go_after_a_week(self):
        run(BASE + '''ForeverFlipRaw = { format = R.FORMAT, scans = standard() }
        rebuild()
        D.dropStatsBackups(F.db, now + D.STATS_KEEP - 1); assert(market.statsBackup)
        D.dropStatsBackups(F.db, now + D.STATS_KEEP + 1); assert(market.statsBackup == nil)''')

    def test_full_scans_wait_for_the_rebuild_and_a_new_house_needs_none(self):
        run(BASE + '''ForeverFlipRaw = { format = R.FORMAT, scans = standard() }
        S.rebuild, S.rebuildChecked = nil, nil; S.planRebuild(now)
        assert(S.rebuilding())
        local ok, why = S.canStart(); assert(not ok and why == 'rebuilding')
        ok, why = S.start(); assert(not ok and why == 'rebuilding')
        assert(D.market(F.db, 'Fresh-Alliance').statsVersion == D.STATS_VERSION)''')

    def test_a_failed_rebuild_keeps_the_old_tables(self):
        run(BASE + '''ForeverFlipRaw = { format = R.FORMAT, scans = standard() }
        local trackLots = S.trackLots
        S.trackLots = function() error('boom') end
        rebuild()
        S.trackLots = trackLots
        assert(market.history['c:10'].sales.pairs == 99 and market.statsError and market.statsVersion == nil)''')


class BiasTests(unittest.TestCase):
    def test_an_unknown_seller_reposting_a_lot_at_a_new_price_did_not_sell(self):
        run(BASE + '''local n = M.trackSales(seq{{100,5,3},{150,1,3}}, seq{{150,1,3},{120,5,3}}, 900)
        assert(n == 0, n)''')

    def test_a_whole_lot_counts_half_in_est_per_day(self):
        run(BASE + '''local h = {}
        M.recordSales(h, {[100] = 4}, 3600, now, {[100] = 4})
        local d = M.lotDemand(h, 100)
        assert(d.units == 4 and d.sold == 2 and d.lots == 4, dump(d))''')


class QualityTests(unittest.TestCase):
    def test_one_pair_is_no_reliable_data(self):
        run(BASE + '''local h = {}
        M.recordSales(h, {[100] = 3}, 900, now)
        local q = M.quality(h, 100, now)
        assert(not q.reliable and q.reason == 'few_pairs' and q.perDay > 0 and q.perDayLow < q.perDay and q.perDayHigh > q.perDay)''')

    def test_enough_pairs_and_hours_are_reliable_even_with_no_sale(self):
        run(BASE + '''local h = {}
        for i = 1, 8 do M.recordSales(h, {}, 900, now) end
        local q = M.quality(h, 100, now)
        assert(q.reliable and q.level == 'ok' and q.perDay == 0 and q.perDayLow == 0 and q.perDayHigh > 0, dump(q))''')

    def test_old_sales_data_is_stale(self):
        run(BASE + '''local h = {}
        for i = 1, 8 do M.recordSales(h, {[100] = 1}, 900, now - 4 * 86400) end
        local q = M.quality(h, 100, now)
        assert(q.stale and not q.reliable and q.reason == 'stale')''')

    def test_disappearances_alone_are_low_quality(self):
        run(BASE + '''local q = M.quality({ flow = { pairs = 5 } }, 100, now)
        assert(q.level == 'low' and q.reason == 'flow_only' and q.inferred)''')

    def test_sure_limits_bracket_sure(self):
        run(BASE + '''local h = {}
        for i = 1, 8 do M.recordSales(h, {[100] = 2}, 900, now) end
        local sure, low, high = M.sureLimits(h, 100, 1, now)
        assert(sure and low <= sure and sure <= high and low >= 0 and high <= 1, tostring(sure) .. ' ' .. tostring(low) .. ' ' .. tostring(high))''')

    def test_calibration_and_rate_check(self):
        run(BASE + '''local c = M.calibration({ { p = 0.9, ok = true }, { p = 0.9, ok = false }, { p = 0.1, ok = false } })
        assert(c.n == 3 and c.bins[5].n == 2 and c.bins[5].observed == 0.5 and c.bins[1].observed == 0)
        assert(math.abs(c.brier - (0.01 + 0.81 + 0.01) / 3) < 1e-9)
        assert(M.calibration({}) == nil)
        local r = M.rateCheck({ { perDay = 2, days = 3, sold = 3 }, { perDay = 1, days = 2, sold = 1 } })
        assert(r.n == 2 and r.predicted == 8 and r.observed == 4 and r.ratio == 0.5)
        assert(math.abs(M.poissonTail(2, 1) - (1 - math.exp(-2))) < 1e-9 and M.poissonTail(0, 1) == 0)''')


if __name__ == "__main__":
    unittest.main()
