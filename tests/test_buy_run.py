"""Buy all to vendor: every vendor deal bought click after click, each checked just before."""
import unittest

from test_addon import SETUP, run

RUN = SETUP + '''local F, T, D, UI = ForeverFlip, ForeverFlip.Trade, ForeverFlip.Deals, ForeverFlip.UI
F.Engine.autoVerify = false
fullScan()
UI.show('deals:vendor'); UI.refresh()
local function purchases()
    local n = 0
    for _, c in ipairs(calls) do
        if c[1] == 'StartCommoditiesPurchase' or c[1] == 'PlaceBid' then n = n + 1 end
    end
    return n
end
'''


class BuyRunTests(unittest.TestCase):
    def test_the_first_click_checks_the_best_vendor_deal_and_the_next_buys_it(self):
        run(RUN + '''assert(#T.runTargets() > 0)
        local ok, why = T.runClick()
        assert(not ok and why == 'run_checking' and T.run and D.pending(T.run.key), tostring(why))
        answer(); run(0.1)
        assert(T.runState() == 'ready', tostring(T.runState()))
        assert(T.runClick() and purchases() == 1)''')

    def test_a_commodity_is_confirmed_with_the_next_click(self):
        run(RUN + '''T.runStart()
        for _, x in ipairs(D.list) do if x.key ~= 'c:10' then T.run.skipped[x.key] = true end end
        T.run.key = nil; D.requests, D.queued = {}, {}; D.search = nil
        T.runStep(); run(0.5); answer(); run(0.1)
        local d = D.get(T.run.key)
        assert(d and d.kind == 'commodity', tostring(T.run.key))
        T.runClick()
        fire('COMMODITY_PRICE_UPDATED', d.cost / d.qty, d.cost)
        assert(T.runState() == 'confirm')
        local ok, what = T.runClick()
        assert(ok and what == 'confirm' and lastCall('ConfirmCommoditiesPurchase'))''')

    def test_check_all_and_the_sniper_rest_during_the_run(self):
        run(RUN + '''T.runStart(); run(0.1)
        assert(D.holding(), 'background work waits')
        T.runStop(); assert(not T.run)''')

    def test_the_page_button_says_what_the_next_click_does(self):
        run(RUN + '''assert(UI.runButton:IsShown() and UI.runButton:GetText():find('Buy all to vendor'))
        UI.runButton:Click(); answer(); run(0.1); UI.refresh()
        assert(UI.runButton:GetText():find('Buy next'), UI.runButton:GetText())
        assert(UI.runStop:IsShown())
        UI.show('deals:flip'); UI.refresh()
        assert(not UI.runButton:IsShown(), 'only on To vendor')''')

    def test_a_busy_moment_does_not_skip_a_checked_deal(self):
        run(RUN + '''T.runClick(); answer(); run(0.1)
        local key = T.run.key
        throttleReady = false
        for _ = 1, 5 do T.runStep() end
        throttleReady = true
        assert(T.run.key == key and not T.run.skipped[key], 'still the deal to buy')''')

    def test_the_run_ends_when_the_page_is_left_or_no_click_comes(self):
        run(RUN + '''T.runStart(); assert(T.run)
        UI.show('deals:flip'); T.runStep()
        assert(not T.run, 'left the page')
        UI.show('deals:vendor'); T.runStart()
        now = now + T.RUN_IDLE + 1; T.runStep()
        assert(not T.run, 'no click for a minute')''')

    def test_a_deal_that_stays_unconfirmed_is_skipped(self):
        run(RUN + '''T.runStart()
        local first = T.run.key
        for _ = 1, 3 do
            if D.search then D.search = nil end
            D.requests, D.queued = {}, {}
            T.runStep()
        end
        assert(T.run == nil or T.run.key ~= first, 'left out after two checks')''')


class BuyoutFigureTests(unittest.TestCase):
    def test_a_buyout_deal_shows_the_resale_profit_not_a_saving(self):
        run(SETUP + '''local UI, M = ForeverFlip.UI, ForeverFlip.Market
        local d = { mode = 'shop', key = 'i:30', qty = 1, cost = 1900, exit = 9900, resell = 9900,
            profit = M.net(9900, 1) - 1900 }
        local text = table.concat(UI.dealDetail(d, nil, nil, now), ' ')
        assert(text:find('resell at') and text:find('75s') and not text:find('saving'), text)''')


class ScrollTextTests(unittest.TestCase):
    def test_the_undercuts_text_scrolls_like_the_tables(self):
        run(SETUP + '''local UI = ForeverFlip.UI
        UI.show('undercuts')
        local lines = {}
        for i = 1, 12 do lines[i] = 'line ' .. i end
        UI.fightBox.set(lines)
        assert(UI.fightText:GetText():find('line 7') and not UI.fightText:GetText():find('line 8'), 'seven shown')
        UI.fightBox.bar.forward:Click()
        local shown = UI.fightText:GetText()
        assert(shown:find('line 8') and shown:sub(1, 6) == 'line 2', shown)
        assert(UI.fightBox.full():find('line 12'), 'the whole text stays readable')''')


class UndercutsHoldTests(unittest.TestCase):
    def test_background_searches_rest_on_the_undercuts_page(self):
        run(SETUP + '''local UI = ForeverFlip.UI
        UI.show('undercuts')
        assert(ForeverFlip.Deals.holding())''')


if __name__ == '__main__':
    unittest.main()
