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


    def test_retail_durations_are_twelve_twenty_four_and_forty_eight_hours(self):
        # Retail lists for 12, 24 and 48 hours: the buttons said 2/8/24 and Auto weighed the
        # deposits over WoW Forever's hours.
        run(HIDE + """assert(UI.durations[1]:GetText()=='2' and UI.durations[3]:GetText()=='24')
        GetBuildInfo=function() return '12.0.1','1','Nov 1 2026',120001 end
        F.Trade.readDurations()
        UI.refresh()
        local H=F.Trade.DURATION_HOURS
        assert(H[1]==12 and H[2]==24 and H[3]==48,table.concat(H,','))
        assert(UI.durations[1]:GetText()=='12',UI.durations[1]:GetText())
        assert(UI.durations[3]:GetText()=='48',UI.durations[3]:GetText())
        assert(UI.durations[4]:GetText()=='Auto',UI.durations[4]:GetText())""")


if __name__ == '__main__':
    unittest.main()
