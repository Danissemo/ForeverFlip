"""The Sell page says why its Best route won, and a post the game restricts neither goes out nor
locks the posting buttons."""

import unittest

from test_addon import SETUP, run
from test_hidden_items import HIDE
from test_quote import plain

READY = HIDE + """local function count() local n = 0 for _, c in ipairs(calls) do if c[1] == 'PostItem' or c[1] == 'PostCommodity' then n = n + 1 end end return n end
local function ready()
    T.postAll()
    local n = 0
    while F.Deals.search or #F.Deals.requests > 0 do
        if F.Deals.search then answer() end
        run(1.1); n = n + 1; assert(n < 50)
    end
end
Enum.AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 }
Enum.AuctionHouseError = { NotEnoughMoney = 0, HasRestriction = 6, BoundItem = 17 }
local active = {}
C_RestrictedActions = { IsAddOnRestrictionActive = function(t) return active[t] == true end }
"""


class BestRouteTests(unittest.TestCase):
    def test_the_footer_names_the_route_and_lists_each_one(self):
        out = run(HIDE + """F.db.settings.vendorMargin = 0
        F.Data.market(F.db, F.Engine.scope()).history['i:30'] = { scan = { at = now, market = 5000 } }
        T.prices['i:30'] = { rows = { { unit = 4500, qty = 1 } }, at = now }
        UI.refresh(); row('i:30'):Click(); UI.refresh()
        local undecided = UI.sellBox.full()
        -- Both routes pay here: the player chooses (the undecided footer is checked below).
        local w = { T.bestWay('i:30', 30) }
        T.setRouteChoice('i:30', w[1]); UI.refresh()
        return w[1] .. ' @@ ' .. UI.sellBox.full() .. ' @@ ' .. undecided""")
        best, text, undecided = out.split(' @@ ', 2)
        self.assertTrue(plain(undecided.split('\n')[0]).startswith('Best not decided'), undecided)
        lines = [plain(x) for x in text.split('\n')]
        verdict = [x for x in lines if x.startswith('Best ')]
        self.assertEqual(len(verdict), 1, text)
        self.assertTrue(lines[0].startswith('Best ') and lines[1].startswith('Why '), 'Best and why come first')
        chosen = [x for x in lines if x.startswith('> ')]
        self.assertEqual(len(chosen), 1, 'one route is marked')
        self.assertIn('(best)', chosen[0])
        self.assertTrue(chosen[0][2:].startswith({'auction': 'AH', 'vendor': 'Vendor'}[best]), chosen[0])
        self.assertTrue(any(x.lstrip('> ').startswith('AH') for x in lines), 'the auction route is listed')
        self.assertTrue(any(x.lstrip('> ').startswith('Vendor') for x in lines), 'the vendor route is listed')
        self.assertTrue(any('posted at' in x and 'cut' in x for x in lines), 'the auction sum is explained')

    def test_a_doubtful_item_asks_for_a_route_and_reset_asks_again(self):
        out = run(HIDE + """F.db.settings.vendorMargin = 0
        F.Data.market(F.db, F.Engine.scope()).history['i:30'] = { scan = { at = now, market = 5000 } }
        T.prices['i:30'] = { rows = { { unit = 4500, qty = 1 } }, at = now }
        UI.refresh(); row('i:30'):Click(); UI.refresh()
        local r = row('i:30')
        assert(r.bestWay.name == 'undecided', r.bestWay.name)
        local note = r.cols[5]:GetText()
        assert(note:find('|cffff6060', 1, true) and note:find('Choose', 1, true), note)
        local profit = r.cols[3]:GetText()
        assert(profit:find(' / ', 1, true) and not profit:find('AH', 1, true), 'both profits, no labels: ' .. profit)
        assert(UI.chooseAH:IsShown() and UI.chooseVendor:IsShown())
        assert(not UI.sellSureReset:IsEnabled(), 'nothing to reset yet')
        UI.chooseVendor:Click()
        assert(T.routeChoice('i:30') == 'vendor')
        r = row('i:30')
        assert(r.cols[4]:GetText() == '-', 'a vendor has no Sure')
        assert(r.cols[5]:GetText():find('your choice', 1, true), 'the Note says it is your choice')
        assert(UI.sellSureReset:IsEnabled(), 'the choice of a doubtful item can be reset')
        local chosen = r.cols[2]:GetText()
        UI.sellSureReset:Click()
        assert(T.routeChoice('i:30') == nil and row('i:30').bestWay.name == 'undecided')
        return chosen .. ' @@ ' .. row('i:30').cols[2]:GetText() .. ' @@ ' .. UI.ruleToggle:GetText()""")
        chosen, best, rule = (plain(x) for x in out.split(' @@ '))
        self.assertEqual(chosen, 'Vendor')
        self.assertEqual(best, 'AH / V')
        self.assertEqual(rule, 'Rule')

    def test_the_verdict_is_translated(self):
        out = run(HIDE + """F.Locale.apply('uk')
        T.prices['i:30'] = { rows = { { unit = 4500, qty = 1 } }, at = now }
        UI.refresh(); row('i:30'):Click(); UI.refresh()
        return UI.sellBox.full()""")
        self.assertIn('Найкраще', plain(out))


class WrapTests(unittest.TestCase):
    def test_a_long_line_goes_on_in_the_next_rows_with_its_colour(self):
        run(HIDE + """local box = UI.sellBox
        local long = '|cffaaaaaa' .. string.rep('word ', 40) .. 'end|r'
        box.set({ 'short', long, 'after' }, 'wrap')
        assert(#box.wrapped > 3, 'the long line takes more than one row: ' .. #box.wrapped)
        assert(box.wrapped[2]:sub(-2) == '|r', 'the first piece closes its colour')
        assert(box.wrapped[3]:find('^%s+|cffaaaaaa'), 'the next piece is indented and grey again: ' .. box.wrapped[3])
        assert(box.wrapped[#box.wrapped] == 'after')
        assert(box.full() == table.concat({ 'short', long, 'after' }, '\\n'), 'the text itself is kept whole')""")


class RestrictionTests(unittest.TestCase):
    def test_a_restricted_post_is_not_sent_and_says_why(self):
        run(READY + """ready()
        active[Enum.AddOnRestrictionType.Combat] = true
        assert(F.AH.restricted() == 'Combat')
        assert(not T.wayReady(), 'the posting buttons are off')
        local before = count()
        local ok, why = T.postAll()
        assert(not ok and why == 'restricted', tostring(why))
        assert(count() == before, 'nothing sent to the server')
        active[Enum.AddOnRestrictionType.Combat] = nil
        assert(F.AH.restricted() == nil and T.wayReady())""")

    def test_a_post_the_server_restricts_frees_the_buttons_at_once(self):
        run(READY + """ready()
        local ok, why = T.postAll()
        assert(ok and why == 'post_sent', tostring(why))
        assert(T.postingNow(), 'waiting for the auction house')
        fire('AUCTION_HOUSE_SHOW_ERROR', Enum.AuctionHouseError.HasRestriction)
        assert(not T.postingNow(), 'no ten-second wait')
        assert(F.Engine.message == 'post_restricted', tostring(F.Engine.message))
        assert(not next(T.held), 'a restriction holds no item')""")

    def test_an_item_the_server_refuses_is_skipped_for_the_visit(self):
        run(READY + """ready()
        T.postAll()
        local key = T.lastPost.key
        fire('AUCTION_HOUSE_SHOW_ERROR', Enum.AuctionHouseError.BoundItem)
        assert(not T.postingNow() and T.held[key], 'held: Post all goes on to the next item')
        assert(F.Engine.message == 'post_refused', tostring(F.Engine.message))
        T.postAll()
        assert(T.lastPost and T.lastPost.key ~= key, 'the next item is posted')""")

    def test_a_client_without_restrictions_posts_as_before(self):
        run(HIDE + """C_RestrictedActions = nil
        assert(F.AH.restricted() == nil)""")



class VendorProfitTests(unittest.TestCase):
    def test_profit_on_to_vendor_is_one_unit(self):
        run(SETUP + """local F, UI, U = ForeverFlip, ForeverFlip.UI, ForeverFlip.Util
        fullScan()
        UI.show('deals:vendor'); UI.refresh()
        local checked = 0
        for _, r in ipairs(UI.vendorTable.rows) do
            local d = r:IsShown() and r.key and F.Deals.get(r.key)
            if d then
                local buy = math.floor((d.cost or 0) / math.max(1, d.qty or 1) + 0.5)
                local sells = d.exit and math.floor(d.exit)
                    or math.floor(((d.cost or 0) + (d.profit or 0)) / math.max(1, d.qty or 1) + 0.5)
                assert(r.cols[5]:GetText() == U.money(sells - buy), r.cols[5]:GetText() .. ' vs ' .. U.money(sells - buy))
                checked = checked + 1
            end
        end
        assert(checked > 0, 'a vendor deal is listed')""")


if __name__ == '__main__':
    unittest.main()
