"""T20: the Today analytics period (the local calendar day) and KPI text that fits its block."""

import unittest

from test_addon import SETUP, run

BASE = SETUP + '''local F = ForeverFlip
local A, UI = F.Analytics, F.UI
local c = F.Data.char(F.db, F.Engine.owner())
local function sell(at, profit, key)
    F.Data.log(c, { at = at, kind = 'sell', key = key or 'c:10', name = 'Linen Cloth', qty = 1,
        amount = profit + 100, profit = profit })
end
'''


class TodayTests(unittest.TestCase):
    def test_the_day_starts_at_local_midnight(self):
        run(BASE + '''local start, stop = A.dayStart(now)
        local t = date('*t', start)
        assert(t.hour == 0 and t.min == 0 and t.sec == 0, 'midnight on the local clock')
        assert(start <= now and now < stop and stop - start >= 23 * 3600 and stop - start <= 25 * 3600)
        assert(date('*t', stop).hour == 0 and date('*t', stop).day ~= t.day, 'the next local day')''')

    def test_today_counts_only_what_came_after_midnight(self):
        run(BASE + '''local start = A.dayStart(now)
        sell(start - 1, 500)           -- one second before midnight: yesterday
        sell(start + 1, 300, 'c:20')   -- one second after: today
        local r = A.results(1, now)
        assert(r.profit == 300 and r.sales == 1 and r.earned == 400, r.profit .. ' ' .. r.sales)
        assert(#r.days == 1 and r.days[1].profit == 300)
        assert(#r.best == 1 and r.best[1].key == 'c:20', 'yesterday is not among today\\'s best')
        -- Just after the next midnight the same sales are yesterday's.
        local _, stop = A.dayStart(now)
        local later = A.results(1, stop + 1)
        assert(later.profit == 0 and later.sales == 0, later.profit)''')

    def test_today_is_split_by_the_hour_for_the_chart(self):
        run(BASE + '''local start = A.dayStart(now)
        sell(start + 60, 300, 'c:20')            -- 00:01
        sell(start + 3 * 3600 + 5, 200, 'c:30')  -- 03:00
        sell(start + 3 * 3600 + 900, 100, 'c:30')
        local r = A.results(1, now)
        assert(#r.hours == 24 and r.hours[1].hour == 0 and r.hours[24].hour == 23)
        assert(r.hours[1].profit == 300 and r.hours[4].profit == 300 and r.hours[2].profit == 0,
            r.hours[1].profit .. ' ' .. r.hours[4].profit)
        local sum = 0
        for _, h in ipairs(r.hours) do sum = sum + h.profit end
        assert(sum == r.profit, 'the hours add up to the day')
        UI = ForeverFlip.UI
        UI.show('analytics'); UI.analyticsDays = 1; UI.refreshAnalytics()
        local shown = 0
        for _, bar in ipairs(UI.bars) do if bar:IsShown() then shown = shown + 1 end end
        assert(shown == 24, 'a bar an hour, not one block: ' .. shown)
        assert(A.results(7, now).hours == nil, 'longer periods stay a bar a day')''')

    def test_the_local_day_is_not_the_utc_day(self):
        # A player three hours east of UTC: their midnight is 21:00 UTC of the day before.
        run(BASE + '''date = function(fmt, t)
            if fmt == '*t' then return os.date('!*t', (t or now) + 3 * 3600) end
            return os.date(fmt, t)
        end
        local start = A.dayStart(now)
        local shifted = now + 3 * 3600
        assert(start == shifted - shifted % 86400 - 3 * 3600, start)
        assert(start % 86400 == 86400 - 3 * 3600, 'not a UTC midnight')
        sell(start + 60, 700)          -- after the player's midnight, before the UTC one when now is late
        local r = A.results(1, now)
        assert(r.profit == 700, r.profit)''')

    def test_the_today_button_shows_the_period(self):
        run(BASE + '''fullScan(); sell(now - 10, 250)
        UI.show('analytics'); UI.periodButtons[1]:Click()
        assert(UI.analyticsDays == 1 and #UI.bars >= 1 and UI.bars[1]:IsShown())
        assert(UI.resultsHead:GetText():find('today', 1, true), UI.resultsHead:GetText())
        assert(UI.chartTitle:GetText() == 'Profit today, by hour', UI.chartTitle:GetText())
        assert(not UI.periodButtons[1]:IsEnabled() and UI.periodButtons[7]:IsEnabled())''')


class FitTests(unittest.TestCase):
    def test_compact_money_keeps_the_coin(self):
        run(BASE + '''local function plain(x) return (x:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')) end
        local money = UI.compactMoney
        UI.compactMoney = function(...) return plain(money(...)) end
        local big = 1234567 * 10000 + 4500
        assert(UI.compactMoney(big, 1) == plain(F.Util.money(big)))
        assert(UI.compactMoney(big, 2) == '1234567g', UI.compactMoney(big, 2))
        assert(UI.compactMoney(big, 3) == '1.2Mg', UI.compactMoney(big, 3))
        assert(UI.compactMoney(45678 * 10000, 3) == '45.6kg', UI.compactMoney(45678 * 10000, 3))
        assert(UI.compactMoney(-2000 * 10000, 3) == '-2kg', UI.compactMoney(-2000 * 10000, 3))
        assert(UI.compactMoney(5050, 3) == plain(F.Util.money(5050)), 'under a gold nothing is shortened')''')

    def test_every_kpi_line_fits_with_huge_numbers(self):
        run(BASE + '''fullScan()
        for i = 1, 3 do sell(now - i, 987654321098 + i, 'c:' .. (100 + i)) end
        F.Data.log(c, { at = now - 5, kind = 'buy', key = 'c:9', name = 'Wool', qty = 1, amount = 876543210987 })
        c.positions['c:9'] = { qty = 1, cost = 765432109876, mode = 'flip', since = now - 5 * 86400 }
        UI.show('analytics')
        for _, n in ipairs({ 1, 7, 30 }) do
            UI.periodButtons[n]:Click()
            local W = UI.kpiWidth
            assert(UI.textWidth(UI.resultsHead, UI.resultsHead:GetText()) <= W, UI.resultsHead:GetText())
            for line in (UI.resultsText:GetText() .. '\\n'):gmatch('(.-)\\n') do
                assert(UI.textWidth(UI.resultsText, line) <= W, n .. ': ' .. line)
            end
            for id, pair in pairs(UI.resultsPairs) do
                local v = pair.value:GetText()
                assert(UI.textWidth(pair.value, v) <= 2 * (W - 100), id .. ': ' .. v)
            end
            local shown = UI.resultsText:GetText():gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')
            assert(shown:find('Spent on purchases: [%d%.]+[kM]?g'), shown)
        end''')

    def test_the_font_shrinks_when_no_abbreviation_is_enough(self):
        run(BASE + '''local fs = UI.frame:CreateFontString()
        local size = 14
        rawset(fs, 'GetFont', function() return 'Fonts\\\\FRIZQT__.TTF', size, '' end)
        rawset(fs, 'SetFont', function(_, _, s) size = s end)
        local long = string.rep('x', 40)          -- 40 letters: 280 px at 14, 200 px at 10
        local used = UI.fitText(fs, function() return { long } end, 200)
        assert(used[1] == 3 and size == 10, 'shrunk to ' .. size)
        UI.fitText(fs, function() return { 'short' } end, 200)
        assert(size == 14, 'the font comes back when the text fits again')''')


if __name__ == '__main__':
    unittest.main()
