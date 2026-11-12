"""One price model (F.Trade.quote) behind the tooltip, the Sell page and its Best column."""
import re
import unittest

from test_addon import run
from test_hidden_items import HIDE


def plain(text):
    return re.sub(r'\|c[0-9a-fA-F]{8}|\|r|\|T[^|]*\|t', '', text)


class QuoteTests(unittest.TestCase):
    SETUP = HIDE + """F.db.settings.vendorMargin = 0
    local history = F.Data.market(F.db, F.Engine.scope()).history
    history['i:30'] = { scan = { at = now, market = 5000 } }
    F.Data.addPosition(c or F.Data.char(F.db, F.Engine.owner()), 'i:30', 'Linen Bag', 1, 3000, 'flip', 4900, now)
    T.prices['i:30'] = { rows = { { unit = 4500, qty = 1 } }, at = now }
    """

    def test_tooltip_price_box_and_best_column_agree(self):
        out = run(self.SETUP + """local q = T.quote('i:30', 30)
        assert(q.why == 'undercut' and q.live and q.post == 4400, tostring(q.post))
        assert(q.net == F.Market.net(q.post, 1) - q.lost, 'net = post - cut - lost deposits')
        assert(q.profit == q.net - 3000, 'profit against what the stock cost')
        UI.show('sell'); UI.refresh()
        local r = row('i:30'); r:Click(); UI.refresh()
        assert(UI.sellPrice:GetText() == U.plainMoney(q.post), UI.sellPrice:GetText())
        tooltipLines = {}
        GameTooltip.itemLink = link(30)
        for _, fn in ipairs(tooltipCalls) do fn(GameTooltip) end
        return r.cols[4]:GetText() .. ' @@ ' .. table.concat(tooltipLines, ' ## ') .. ' @@ ' .. UI.sellText:GetText()
            .. ' @@ ' .. U.money(q.post) .. ' @@ ' .. U.money(q.net)""".replace('U.', 'F.Util.'))
        best, tip, sell, post, net = (plain(x) for x in out.split(' @@ '))
        self.assertIn(post, best, 'Best column shows the post price')
        self.assertIn('Post at', tip)
        self.assertIn(post, tip.split('Post at')[1].split('##')[0], 'tooltip posts at the same price')
        self.assertIn(net, tip, 'tooltip shows what it brings')
        self.assertIn(net, sell, 'Sell page shows what it brings')
        self.assertIn('Profit each', tip)

    def test_deposit_comes_back_with_a_sale(self):
        run(self.SETUP + """F.Data.char(F.db, F.Engine.owner()).rates = { ['linen bag'] = { sold = 10, failed = 0 } }
        local q = T.quote('i:30', 30)
        assert(q.tries == 1 and q.lost == 0, 'sells on the first post: no deposit lost')
        F.Data.char(F.db, F.Engine.owner()).rates['linen bag'] = { sold = 1, failed = 3 }
        q = T.quote('i:30', 30)
        assert(q.tries == 4 and q.lost > 0, 'three expired posts lose three deposits')""")

    def test_without_a_check_the_usual_price_is_an_estimate(self):
        run(self.SETUP + """T.prices['i:30'] = nil
        local q = T.quote('i:30', 30)
        assert(q.why == 'estimate' and not q.live and q.post == 5000, tostring(q.why) .. ' ' .. tostring(q.post))""")

    def test_post_never_goes_below_break_even(self):
        run(self.SETUP + """T.prices['i:30'] = { rows = { { unit = 2000, qty = 1 } }, at = now }
        local q = T.quote('i:30', 30)
        assert(q.belowFloor and q.market == 1900, tostring(q.market))
        assert(q.post >= q.breakEven and q.post == q.floor, q.post .. ' ' .. tostring(q.floor))""")


if __name__ == '__main__':
    unittest.main()
