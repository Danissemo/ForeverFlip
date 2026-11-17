"""The item tooltip in the player's layout: FOREVER FLIP and the house, then Selling, Demand and
References, then the situational parts (yours, a deal now). The lowest price is the newer of the
full scan's cheapest and the quick scan's (a browse of the whole house)."""

import re
import unittest

from test_addon import SETUP, run

TIP = """
    tooltipLines = {}
    GameTooltip.itemLink = link(10)
    for _, fn in ipairs(tooltipCalls) do fn(GameTooltip) end
    return table.concat(tooltipLines, ' ## ')"""


def clean(text):
    return re.sub(r'\|c[0-9a-fA-F]{8}|\|r', '', text)


def tip(code):
    return clean(run(SETUP + code + TIP))


class LayoutTests(unittest.TestCase):
    def test_the_sections_come_in_the_layout_order(self):
        text = tip('fullScan()')
        order = ['FOREVER FLIP: ALLIANCE AH', 'Selling', 'Vendor price', 'Lowest AH price',
                 'Median AH price', 'Recommendation', 'Demand', 'Your last scan', 'Estimated sales / day',
                 'Recent sales', 'Sure = Sells at', 'References', 'Community data', '14-day median / mean',
                 'Trend 3d / 7d / 14d']
        at = [text.find(part) for part in order]
        self.assertNotIn(-1, at, text)
        self.assertEqual(at, sorted(at), text)

    def test_a_newer_quick_scan_gives_the_lowest_price(self):
        text = tip('''fullScan()
        local F = ForeverFlip
        F.Sniper.lows = { scope = F.Engine.scope(), [10] = { price = 45, qty = 3, at = F.Engine.clock() + 60 } }''')
        self.assertIn('Lowest AH price', text)
        self.assertIn('ago)  45c', text.split('Lowest AH price')[1].split('##')[0])

    def test_an_older_quick_scan_or_another_house_is_not_used(self):
        text = tip('''fullScan()
        local F = ForeverFlip
        F.Sniper.lows = { scope = 'Elsewhere-Horde', [10] = { price = 45, qty = 3, at = F.Engine.clock() + 60 } }''')
        self.assertIn('ago)  60c', text.split('Lowest AH price')[1].split('##')[0])


    def test_a_deal_now_is_in_selling_after_the_recommendation(self):
        text = tip('''fullScan(); local F = ForeverFlip
        F.Deals.get = function() return { key = 'c:10', mode = 'flip', qty = 2, exit = 75, profit = 30 } end
        F.Deals.sure = function() return 0.5 end''')
        self.assertIn('Deal now', text)
        self.assertLess(text.find('Deal now'), text.find('Demand'), text)


class ExitWhyTests(unittest.TestCase):
    def test_the_resale_panel_says_why_it_sells_at_its_price(self):
        out = run(SETUP + '''local F, UI = ForeverFlip, ForeverFlip.UI
        F.Market.usual = function() return 13474 end
        F.Market.saleCap = function() return 6950 end
        local capped = UI.exitWhy({ mode = 'flip', kind = 'gear', exit = 6900, exitNext = 13474 }, {})
        local nextLot = UI.exitWhy({ mode = 'flip', kind = 'gear', exit = 13400, exitNext = 13474 }, {})
        local vendor = UI.exitWhy({ mode = 'vendor', exit = 100 }, {})
        return capped .. ' @@ ' .. nextLot .. ' @@ ' .. tostring(vendor)''')
        capped, next_lot, vendor = [clean(x) for x in out.split(' @@ ')]
        self.assertIn('Why 69s', capped)
        self.assertIn('really paid', capped)
        self.assertIn('69s 50c', capped)
        self.assertIn('next lot', next_lot)
        self.assertEqual(vendor, 'nil')


if __name__ == '__main__':
    unittest.main()
