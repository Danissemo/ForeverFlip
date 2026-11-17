"""T26: list pages use the height they have: no whole empty row above the bottom panel."""

import re
import unittest
from pathlib import Path

from test_addon import SETUP, run

# UI.lua and its page files (UI*.lua): the window's whole source.
ADDON = Path(__file__).resolve().parent.parent / 'ForeverFlip'
UI = ''.join(path.read_text(encoding='utf-8') for path in sorted(ADDON.glob('UI*.lua')))
PAGE = 432  # height of a page (the Crafting page's note: 432 - 108 = 324 = 24 + 15 x 20)
HEADER, ROW = 24, 20

# (rows constant, the function creating the page)
PAGES = [
    ('SHOP_ROWS', 'createShop'),
    ('BID_ROWS', 'createBids'),
    ('MY_BID_ROWS', 'createMyBids'),
    ('DEAL_ROWS', 'createDeals'),
    ('CRAFT_ROWS', 'createCrafting'),
]


def rows_of(name):
    return int(re.search(r'^local %s = (\d+)' % name, UI, re.M).group(1))


def bottom_of(function):
    body = UI[UI.index('function UI.%s(p)' % function):]
    return int(re.search(r'list:SetPoint\("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, (\d+)\)', body).group(1))


class CompactListTests(unittest.TestCase):
    def test_the_rows_fit_the_list_and_leave_no_empty_row(self):
        for name, function in PAGES:
            with self.subTest(page=function):
                room = PAGE - bottom_of(function)
                used = HEADER + rows_of(name) * ROW
                self.assertLessEqual(used, room, '%s: %d rows need %d of %d px' % (name, rows_of(name), used, room))
                if name != 'DEAL_ROWS':  # Deals keeps a filter bar between its list and the footer
                    self.assertLess(room - used, ROW, '%s leaves a whole row empty' % name)

    def test_the_tables_have_the_rows(self):
        run(SETUP + '''local UI = ForeverFlip.UI
        assert(#UI.shopTable.rows == 15, #UI.shopTable.rows)
        assert(#UI.bidTable.rows == 15 and #UI.myBidTable.rows == 15, #UI.bidTable.rows)''')


if __name__ == '__main__':
    unittest.main()
