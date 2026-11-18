"""T32 on the pages: sample quality next to Est./day and Sure (tooltip, Check Sure, deal detail),
"No reliable data" and the reason below the thresholds, the prediction kept on a post, the Sure
check on Analytics, the log defaults, /ff stats rollback and the Scan button during a rebuild."""

import re
import unittest

from test_addon import SETUP, run


def clean(text):
    return re.sub(r'\|c[0-9a-fA-F]{8}|\|r', '', text)


BASE = SETUP + '''local F, M, D, UI = ForeverFlip, ForeverFlip.Market, ForeverFlip.Deals, ForeverFlip.UI
local market = F.Data.market(F.db, F.Engine.scope())
-- Sales of item 10 at 100c: `pairs` scan pairs of 15 minutes, two units bought in part in each.
local function sales(pairs)
    local h = { days = {} }
    for i = 1, pairs do M.recordSales(h, {[100] = 2}, 900, now) end
    market.history['c:10'] = h
    D.sureCache = {}
    return h
end
'''


class CheckLinesTests(unittest.TestCase):
    def test_a_reliable_sample_shows_one_rate_and_the_sample(self):
        text = clean(run(BASE + '''sales(8)
        local c = D.checkAt('c:10', 100, 1, nil, 0, 0, now)
        assert(c.quality.reliable, c.quality.reason)
        return table.concat(UI.checkLines(c), ' ## ')'''))
        self.assertRegex(text, r'Est\./day [\d.]+')
        self.assertNotIn('80%', text)
        self.assertIn('8 scan pairs, 2.0 hours: reliable', text)
        self.assertNotIn('No reliable data', text)

    def test_one_pair_says_no_reliable_data_and_why_instead_of_numbers(self):
        text = clean(run(BASE + '''sales(1)
        local c = D.checkAt('c:10', 100, 1, nil, 0, 0, now)
        return table.concat(UI.checkLines(c), ' ## ')'''))
        # Sure and Est./day are shown with a question mark (a guess from too few pairs): the
        # same numbers as the Deals columns.
        self.assertRegex(text, r'Sure \d+%\?, about ~[\d.]+ a day sell')
        self.assertIn('No reliable data: too few scan pairs compared yet', text)

    def test_legacy_sales_say_an_older_version_measured_them(self):
        text = clean(run(BASE + '''local h = sales(8); h.sales.legacy = true
        return table.concat(UI.checkLines(D.checkAt('c:10', 100, 1, nil, 0, 0, now)), ' ## ')'''))
        self.assertIn('measured by an older version; new scans will update it', text)

    def test_sure_limits_text(self):
        text = clean(run(BASE + 'return UI.sureLimitsText(0.64, 0.41, 0.8)'))
        self.assertEqual(text, 'Sure 64%')


class TooltipTests(unittest.TestCase):
    TIP = '''
    tooltipLines = {}
    GameTooltip.itemLink = link(10)
    for _, fn in ipairs(tooltipCalls) do fn(GameTooltip) end
    return table.concat(tooltipLines, ' ## ')'''

    def test_few_pairs_in_the_tooltip_give_the_number_marked_and_the_reason(self):
        text = clean(run(BASE + '''fullScan()
        local h = market.history['c:10']
        h.sales = nil; M.recordSales(h, {[100] = 2}, 900, now); D.sureCache = {}''' + self.TIP))
        # The same Est./day as the Deals column, marked "~", and why it is thin.
        self.assertRegex(text, r'Estimated sales / day = ~[\d.]+')
        self.assertIn('too few scan pairs compared yet', text)
        self.assertNotIn('Sure to sell one', text)


class PostJournalTests(unittest.TestCase):
    def test_a_post_keeps_its_sure_and_est_per_day(self):
        run(SETUP + '''local F = ForeverFlip
        local c = F.Data.char(F.db, F.Engine.owner())
        F.Data.addPosition(c, 'i:30', 'Linen Bag', 1, 20000, 'flip', 29900)
        local h = F.Data.market(F.db, F.Engine.scope()).history
        h['i:30'] = h['i:30'] or { days = {} }
        for i = 1, 8 do F.Market.recordSales(h['i:30'], {[29900] = 1}, 900, now) end
        putBag(0,1,30,1)
        local item = F.AH.bagItems()[1]
        assert(F.Trade.checkPrice('i:30')); answer()
        assert(F.Trade.post(item, 1, 29900, 3))
        fire('AUCTION_HOUSE_AUCTION_CREATED', 777)
        local e = c.journal[#c.journal]
        assert(e.kind == 'post' and e.sure and e.sure >= 0 and e.sure <= 1, tostring(e.sure))
        assert(e.perDay and e.perDay > 0, tostring(e.perDay))''')


class CalibrationTests(unittest.TestCase):
    def test_too_few_posts_say_so_and_enough_compare_predicted_with_observed(self):
        text = clean(run(BASE + '''local A = F.Analytics
        local c = F.Data.char(F.db, F.Engine.owner())
        c.journal = {}
        local old = now - 3 * 86400
        for i = 1, 9 do c.journal[#c.journal+1] = { at = old + i, kind = 'post', key = 'c:' .. i, qty = 1, sure = 0.8 } end
        UI.show('analytics'); UI.refresh()
        local before = UI.calibrationText:GetText()
        assert(A.calibration(now) == nil)
        c.journal[#c.journal+1] = { at = old + 10, kind = 'post', key = 'c:10', qty = 2, sure = 0.5 }
        -- Four of the ten sell in time (c:10 needs both of its units), one only after 2 days.
        for i = 1, 3 do c.journal[#c.journal+1] = { at = old + 3600 + i, kind = 'sell', key = 'c:' .. i, qty = 1 } end
        c.journal[#c.journal+1] = { at = old + 7200, kind = 'sell', key = 'c:10', qty = 2 }
        c.journal[#c.journal+1] = { at = old + 2.5 * 86400, kind = 'sell', key = 'c:5', qty = 1 }
        -- A post younger than the horizon is not judged yet.
        c.journal[#c.journal+1] = { at = now - 60, kind = 'post', key = 'c:6', qty = 1, sure = 0.9 }
        local cal, n = A.calibration(now)
        assert(cal and n == 10 and cal.n == 10, tostring(n))
        assert(math.abs(cal.observed - 0.4) < 1e-9 and math.abs(cal.predicted - 0.77) < 1e-9, cal.observed .. ' ' .. cal.predicted)
        UI.refresh()
        return before .. ' ## ' .. UI.calibrationText:GetText()'''))
        self.assertIn('Sure check: not enough posts yet (9 of 10)', text)
        self.assertIn('Sure check: 40% of 10 posts sold within 2 days, Sure predicted 77%', text)


class SettingsAndCommandTests(unittest.TestCase):
    def test_log_defaults_and_a_copy_per_profile(self):
        run(SETUP + '''local D = ForeverFlip.Data
        local db = D.open(nil)
        assert(db.settings.logEcho.error == true and db.settings.logSound == true and db.settings.logTabMade == false)
        db.settings.logEcho.error = false
        assert(D.DEFAULTS.logEcho.error == true, 'the default is not changed by a profile')
        local kept = D.open({ settings = { logSound = false, logEcho = { trade = true } } })
        assert(kept.settings.logSound == false and kept.settings.logEcho.trade and kept.settings.logEcho.error == nil)''')

    def test_stats_rollback_answers_in_the_log(self):
        text = run(BASE + '''SlashCmdList.FOREVERFLIP('stats rollback')
        local first = F.Log.last('info')
        local h = sales(8)
        market.statsBackup = { items = { ['c:10'] = { sales = { pairs = 99, hours = 50, b = {}, at = now } } } }
        SlashCmdList.FOREVERFLIP('stats rollback')
        assert(market.history['c:10'].sales.pairs == 99)
        return tostring(first and (first.text or first)) .. ' ## ' .. tostring(F.Log.last('info').text or F.Log.last('info'))''')
        self.assertIn('No earlier sales statistics are kept', text)
        self.assertIn('back as before the rebuild', text)

    def test_the_scan_button_reads_rebuilding(self):
        run(SETUP + '''local F, UI = ForeverFlip, ForeverFlip.UI
        F.Scan.rebuild = { scopes = {} }
        local start = F.Scan.rebuildStep; F.Scan.rebuildStep = function() end
        UI.refresh()
        assert(UI.scanButton:GetText() == 'Rebuilding sales statistics…', UI.scanButton:GetText())
        assert(not UI.scanButton:IsEnabled())
        local ok, why = F.Scan.start(); assert(not ok and why == 'rebuilding')''')


if __name__ == '__main__':
    unittest.main()
