"""The Sell page says what its next click does, and shows names of items still loading."""

import unittest

from test_hidden_items import HIDE
from test_addon import run


class PostLabelTests(unittest.TestCase):
    def test_without_prices_the_posting_buttons_say_they_check_them(self):
        # The game takes a post only from a click: the first click reads the prices and the next
        # one posts. "Post AH-worthy" on both clicks looked like a button that needs two presses.
        run(HIDE + """T.prices={}
        UI.refresh()
        assert(UI.postAll:GetText():find('^Check prices'),UI.postAll:GetText())
        T.prices['c:10']={at=F.Engine.clock(),rows={{unit=150,qty=100}}}
        UI.refresh()
        assert(UI.postAll:GetText():find('^Post all'),UI.postAll:GetText())""")

    def test_an_item_link_without_a_name_shows_the_items_name(self):
        # While a scan runs the client drops items from its cache, and Retail's bag link reads
        # "[]": put as it was, the row showed "|...".
        run(HIDE + """bags[0][2].hyperlink='|cnIQ1:|Hitem:10::::::::::::|h[]|h|r'
        UI.refresh()
        local r=row('c:10')
        assert(r,'the row is there')
        local text=r.name:GetText()
        assert(not text:find('%[%]'),'no empty link: '..text)""")


if __name__ == '__main__':
    unittest.main()
