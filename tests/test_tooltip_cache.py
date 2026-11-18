"""The game draws an item tooltip again several times a second while it is shown: the lines worked
out for the item are written again until the data changes or UI.TIP_KEEP passes."""

import unittest

from test_addon import SETUP, run

HOVER = SETUP + r'''fullScan()
local F, UI = ForeverFlip, ForeverFlip.UI
local quotes = 0
local quote = F.Trade.quote
F.Trade.quote = function(...) quotes = quotes + 1; return quote(...) end
GameTooltip.itemLink = link(10)
local function hover()
    tooltipLines = {}
    tooltipCalls[1](GameTooltip)
    return table.concat(tooltipLines, '\n')
end
'''


class TooltipCacheTests(unittest.TestCase):
    def test_drawing_the_same_tooltip_again_works_nothing_out(self):
        run(HOVER + r'''local first = hover()
        assert(first:find('FOREVER FLIP') and quotes == 1, quotes)
        local again = hover()
        assert(again == first and quotes == 1, 'the same lines without working them out: ' .. quotes)''')

    def test_changed_data_or_time_works_the_lines_out_again(self):
        run(HOVER + r'''hover()
        F.Engine.changed()
        hover()
        assert(quotes == 2, 'new data: ' .. quotes)
        now = now + UI.TIP_KEEP
        hover()
        assert(quotes == 3, 'old lines: ' .. quotes)''')


if __name__ == '__main__':
    unittest.main()
