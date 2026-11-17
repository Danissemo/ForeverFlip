"""Every auction house the addon may stand at: Alliance, Horde and the neutral goblin houses of WoW
Forever, the hardcore realms' own houses, the houses connected realms share, and Retail's one
server house. Each keeps its own prices, cut and tooltip header."""

import re
import unittest

from test_addon import SETUP, run

TIP = """
    tooltipLines = {}
    GameTooltip.itemLink = link(10)
    for _, fn in ipairs(tooltipCalls) do fn(GameTooltip) end
    return table.concat(tooltipLines, ' ## ')"""

# Retail: no Forever experience presets, so one house serves both factions.
RETAIL = "Enum.ForeverExperiencePreset = nil; C_GameRules = nil\n"


def clean(text):
    return re.sub(r'\|c[0-9a-fA-F]{8}|\|r', '', text)


def tip(code):
    return clean(run(SETUP + code + TIP))


class ScopeTests(unittest.TestCase):
    def test_each_side_has_its_own_scope_and_cut(self):
        run(SETUP + '''local E = ForeverFlip.Engine
        assert(E.scope() == 'Realm-Alliance' and E.cutFor(E.scope()) == 0.05)
        UnitFactionGroup = function() return 'Horde' end
        assert(E.scope() == 'Realm-Horde', E.scope())
        E.house = 'Neutral'
        assert(E.scope() == 'Realm-Neutral' and E.cutFor(E.scope()) == 0.15)
        E.house = nil
        assert(E.scope() == 'Realm-Horde')''')

    def test_retail_has_one_server_house_for_both_factions(self):
        run(SETUP + RETAIL + '''local E = ForeverFlip.Engine
        assert(E.homeSide() == 'Server' and E.scope() == 'Realm-Server', E.scope())
        C_Map = { GetBestMapForUnit = function() return 1434 end } -- Booty Bay is no other house there
        assert(E.detectHouse() == nil)
        assert(E.cutFor(E.scope()) == 0.05)''')

    def test_hardcore_houses_are_apart_on_every_side(self):
        run(SETUP + '''local E = ForeverFlip.Engine
        Enum.GameRule = { HardcoreRuleset = 7 }
        C_GameRules = { IsGameRuleActive = function(rule) return rule == 7 end }
        assert(E.scope() == 'Realm (HC)-Alliance')
        E.house = 'Neutral'
        assert(E.scope() == 'Realm (HC)-Neutral')
        assert(E.sameHouseRealm('Realm (HC)') and not E.sameHouseRealm('Realm'), 'normal and hardcore differ')''')

    def test_connected_realms_share_a_house_and_their_scans_join_it(self):
        run(SETUP + '''local F = ForeverFlip
        local E, Sh = F.Engine, F.Share
        GetAutoCompleteRealms = function() return { 'Realm', "Twin-Peak's" } end
        assert(E.sameHouseRealm("Twin-Peak's") and E.sameHouseRealm('TwinPeaks'), 'connected')
        assert(not E.sameHouseRealm('Elsewhere'))
        fullScan()
        local h = F.Data.market(F.db, 'Realm-Alliance').history['c:10']
        local merged = Sh.merge({ scope = "Twin-Peak's-Alliance", at = now + 300,
            items = { { key = 'c:10', m = h.scan.market * 2, min = 50, n = 30 } } }, 'Friend', 'GUILD')
        assert(merged == 1, 'a connected realm scan is merged')
        assert(F.Data.market(F.db, "Twin-Peak's-Alliance").history['c:10'] == nil, 'no table of its own')
        assert(select(3, F.Market.usual(h)) == 'Friend', 'it joined the shared house')
        local _, why = Sh.merge({ scope = 'Realm-Server', at = now + 400,
            items = { { key = 'c:10', m = 100, min = 90, n = 5 } } }, 'Friend', 'GUILD')
        assert(why == nil or why ~= 'other_realm', 'a server house scan is a house of the realm')''')


class HeaderTests(unittest.TestCase):
    def test_the_header_names_the_house_and_the_footer_closes_it(self):
        for code, house in (('', 'ALLIANCE AH'),
                            ("UnitFactionGroup = function() return 'Horde' end\n", 'HORDE AH'),
                            ("ForeverFlip.Engine.house = 'Neutral'\n", 'NEUTRAL AH, 15% CUT'),
                            (RETAIL, 'SERVER AH')):
            with self.subTest(house=house):
                text = tip(code + 'fullScan()')
                first = text.split(' ## ')[0]
                self.assertEqual(first, '=' * 11 + ' FOREVER FLIP: ' + house + ' ' + '=' * 11, text)
                self.assertEqual(text.split(' ## ')[-1], '=' * 19 + ' X ' + '=' * 18, text)

    def test_the_header_and_footer_are_centred_and_as_wide_as_the_lines(self):
        for code in ('', RETAIL):
            with self.subTest(retail=bool(code)):
                text = tip(code + 'measureText = true\nfullScan()')
                lines = text.split(' ## ')
                first, last = lines[0], lines[-1]
                for rule, middle in ((first, first.strip('=').strip()), (last, 'X')):
                    left = len(rule) - len(rule.lstrip('='))
                    right = len(rule) - len(rule.rstrip('='))
                    self.assertIn(right - left, (0, 1), rule)  # one sign more on the right at most
                    self.assertGreaterEqual(left, 3, rule)
                    self.assertEqual(rule[left:len(rule) - right].strip(), middle, rule)
                widest = max(len(x.replace(' = ', ' ' * 7)) for x in lines[1:-1])
                for rule in (first, last):
                    self.assertLessEqual(abs(len(rule) - widest), 3, (rule, widest))

    def test_a_long_wrapping_game_line_does_not_stretch_the_rules(self):
        game = """
        GameTooltip.GetName = function() return 'GameTooltip' end
        GameTooltip.NumLines = function() return 2 end
        local function line(width, wraps)
            return { IsShown = function() return true end, GetText = function() return 'x' end,
                GetStringWidth = function() return width end, CanWordWrap = function() return wraps end }
        end
        GameTooltipTextLeft1 = line(1800, true)   -- an item's "Use:" text, unwrapped width
        GameTooltipTextLeft2 = line(2000, false)  -- wider than any tooltip
        """
        plain = tip('measureText = true\nfullScan()').split(' ## ')
        stretched = tip('measureText = true\nfullScan()\n' + game).split(' ## ')
        self.assertEqual(stretched[0], plain[0])
        self.assertEqual(stretched[-1], plain[-1])

    def test_the_rules_are_never_a_sign_short_of_the_lines(self):
        # In the game font "=" is wider than a letter: counted from one sign and rounded down, the
        # header came out a sign or two short of the lines below it.
        meter = """
        ForeverFlip.UI.tipTextWidth = function(text)
            local plain = tostring(text or ''):gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')
            local _, signs = plain:gsub('=', '')
            local _, letters = plain:gsub('[^=\\128-\\191]', '')
            return signs * 9 + letters * 6
        end
        """

        def width(text):
            return sum(9 if ch == '=' else 6 for ch in text)

        for code in ('', "UnitFactionGroup = function() return 'Horde' end\n", RETAIL):
            with self.subTest(code=code):
                lines = tip(meter + code + 'fullScan()').split(' ## ')
                widest = max(width(a) + 40 + width(b) if ' = ' in x else width(x)
                             for x in lines[1:-1] for a, _, b in [x.partition(' = ')])
                for rule in (lines[0], lines[-1]):
                    self.assertGreater(width(rule) + 9, widest, (rule, widest))
                    self.assertLessEqual(width(rule), widest + 2 * 9, (rule, widest))

    def test_the_header_and_footer_are_as_wide_as_each_other(self):
        # In the game font "=" is wider than a letter and a space narrower: the header and the
        # footer came out up to a sign apart, the footer standing out past the header.
        meter = """
        ForeverFlip.UI.tipTextWidth = function(text)
            local plain = tostring(text or ''):gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')
            local _, signs = plain:gsub('=', '')
            local _, spaces = plain:gsub(' ', '')
            local _, letters = plain:gsub('[^= \\128-\\191]', '')
            return signs * 9 + spaces * 3 + letters * 7
        end
        """

        def width(text):
            return sum(9 if ch == '=' else 3 if ch == ' ' else 7 for ch in text)

        for code in ('', "UnitFactionGroup = function() return 'Horde' end\n", RETAIL):
            with self.subTest(code=code):
                lines = tip(meter + code + 'fullScan()').split(' ## ')
                self.assertLessEqual(abs(width(lines[0]) - width(lines[-1])), 3, (lines[0], lines[-1]))

    def test_the_rules_are_measured_in_the_tooltips_own_font(self):
        text = tip('''measureText = true
        local used
        GameTooltip.GetName = function() return 'GameTooltip' end
        GameTooltip.NumLines = function() return 2 end
        GameTooltipTextLeft2 = { IsShown = function() return false end, GetText = function() return '' end,
            GetStringWidth = function() return 0 end,
            GetFont = function() return 'Fonts\\\\FRIZQT__.TTF', 13, '' end }
        ForeverFlip.UI.tipTextWidth('')
        ForeverFlip.UI.tipMeter.SetFont = function(_, font, size) used = font .. size end
        fullScan()
        GameTooltip.itemLink = link(10)
        for _, fn in ipairs(tooltipCalls) do fn(GameTooltip) end
        assert(used == 'Fonts\\\\FRIZQT__.TTF13', tostring(used))''')
        self.assertIn('FOREVER FLIP', text)

    def test_the_x_line_is_aimed_short_by_the_learned_skew(self):
        # The trace showed the game drawing the X line about 6 px wider than the meter, the header
        # as measured: that difference is learned and taken off the X line.
        plain = tip('measureText = true\nfullScan()').split(' ## ')
        skewed = tip('''measureText = true
        local UI = ForeverFlip.UI
        UI.learnTipSkew(18); UI.learnTipSkew(18)
        assert(math.abs(UI.tipSkew() - 18) < 0.01, UI.tipSkew())
        UI.learnTipSkew(500)
        assert(math.abs(UI.tipSkew() - 18) < 0.01, 'a broken reading is not learned')
        fullScan()''').split(' ## ')
        self.assertEqual(skewed[0], plain[0])
        self.assertLess(len(skewed[-1]), len(plain[-1]), (skewed[-1], plain[-1]))
        self.assertIn(' X ', skewed[-1])

    def test_a_coin_icon_counts_its_two_pixel_shift(self):
        run(SETUP + r'''measureText = true
        local UI = ForeverFlip.UI
        local plain = UI.tipTextWidth('4 58')
        local coins = UI.tipTextWidth('4 58'
            .. '|TInterface\MoneyFrame\UI-SilverIcon:0:0:2:0|t|TInterface\MoneyFrame\UI-CopperIcon:0:0:2:0|t')
        assert(coins >= plain + 4, plain .. ' ' .. coins)''')

    def test_a_secret_item_link_shows_nothing(self):
        text = tip('''fullScan()
        issecretvalue = function(v) return v == GameTooltip.itemLink end''')
        self.assertNotIn('FOREVER FLIP', text)


if __name__ == '__main__':
    unittest.main()
