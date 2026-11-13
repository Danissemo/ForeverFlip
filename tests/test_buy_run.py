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


PRIORITY = SETUP + '''local F, T, D = ForeverFlip, ForeverFlip.Trade, ForeverFlip.Deals
F.UI.show('deals:vendor')
local function deal(key, kind, exit, lots, verified)
    local qty, cost = 0, 0
    for _, l in ipairs(lots) do qty = qty + l.qty; cost = cost + l.qty * l.unit end
    return {key=key, id=tonumber(key:match(':(%d+)')), kind=kind, mode='vendor',
        exit=exit, qty=qty, cost=cost, profit=qty*exit-cost, roi=(qty*exit-cost)/cost,
        lots=lots, verified=verified}
end
'''


class VendorClickPriorityTests(unittest.TestCase):
    def test_ranks_single_item_auction_profit_above_aggregate_and_roi(self):
        run(PRIORITY + '''D.replace({
            deal('i:20', 'item', 100, {{unit=80, qty=100, auctionID=101}}, now),
            deal('c:10', 'commodity', 100, {{unit=60, qty=10}}, nil),
            deal('i:30', 'item', 1000, {{unit=500, qty=1, auctionID=102}}, nil)
        }, F.Engine.scope())
        local targets = T.runTargets()
        assert(targets[1].key == 'i:30', '500 profit from one auction beats 400 commodity and 20 item profit')
        assert(targets[2].key == 'c:10')
        assert(T.runTargets(true)[1].key == 'i:30')''')

    def test_commodity_priority_uses_affordable_units_after_wallet_shrinks(self):
        run(PRIORITY + '''D.replace({
            deal('c:10', 'commodity', 100, {{unit=60, qty=100}}, now),
            deal('i:30', 'item', 1000, {{unit=500, qty=1, auctionID=102}}, now)
        }, F.Engine.scope())
        money=600
        local targets = T.runTargets()
        assert(#targets == 2 and targets[1].key == 'i:30', '500 beats ten affordable cloth yielding 400')
        assert(targets[2].key == 'c:10', 'affordable commodity subset remains eligible')''')

    def test_item_buy_affordability_uses_one_auction_when_bucket_exceeds_wallet(self):
        run(PRIORITY + '''D.replace({
            deal('i:30', 'item', 1000, {{unit=500, qty=100, auctionID=102}}, now)
        }, F.Engine.scope())
        money=500
        assert(T.runClick(), 'one auction affordable even though the bucket costs 50000')
        assert(T.op and T.op.cost == 500 and T.op.qty == 1)
        assert(lastCall('PlaceBid')[2] == 102 and lastCall('PlaceBid')[3] == 500)''')

    def test_next_click_reselects_when_another_deal_pays_more(self):
        run(PRIORITY + '''local a=deal('i:20','item',1000,{{unit=100,qty=1,auctionID=101}},now)
        local b=deal('i:30','item',1000,{{unit=500,qty=1,auctionID=102}},now)
        D.replace({a,b}, F.Engine.scope()); T.runStart()
        assert(T.run.key == 'i:20')
        a.lots[1].unit=900; a.cost=900; a.profit=100
        assert(T.runClick())
        assert(T.op.key == 'i:30' and T.op.auctionID == 102, 'rerank before spending')''')

    def test_a_queued_batch_check_is_promoted_for_the_buy_run(self):
        run(RUN + '''local key=T.runTargets(true)[1].key
        throttleReady=false
        assert(D.startBatch(F.Engine.scope(), {key}, true))
        assert(D.pending(key))
        T.runStart(); throttleReady=true; run(0.5)
        assert(D.search and D.search.key == key, 'run check must escape the background hold')
        answer(); run(0.1)
        assert(T.runState() == 'ready', tostring(T.runState()))
        assert(purchases() == 0, 'preparation never purchases automatically')''')

    def test_a_fresh_deal_with_queued_recheck_does_not_hold_its_own_buy_button(self):
        run(RUN + '''local d=T.runTargets(true)[1]
        d.verified=now
        throttleReady=false
        assert(D.startBatch(F.Engine.scope(), {d.key}, true))
        T.runStart(); throttleReady=true; run(0.5)
        assert(D.search and D.search.key == d.key, 'fresh deal still promotes its pending recheck')
        answer(); run(0.1)
        assert(T.runState() == 'ready', tostring(T.runState()))''')

    def test_completed_item_purchase_reranks_the_actual_next_auction(self):
        run(PRIORITY + '''D.replace({},F.Engine.scope())
        D.verifyCallback('i:30', {
            {unit=500,qty=1,auctionID=102,link=link(30)},
            {unit=1900,qty=1,auctionID=103,link=link(30)}
        },true)
        D.add(deal('c:10','commodity',100,{{unit=60,qty=10}},now),F.Engine.scope())
        assert(T.runClick() and T.op.auctionID == 102)
        money=money-500; fire('PLAYER_MONEY')
        assert(not T.op and D.get('i:30').lots[1].auctionID == 103)
        local ok, why=T.runClick()
        assert(ok and T.op.key == 'c:10' and T.op.qty == 10,
            '400 commodity profit beats remaining auction: '..tostring(why)..' '..tostring(T.run and T.run.key)..' '..tostring(T.op and T.op.key))''')

    def test_spend_limit_fits_commodity_to_one_click_budget(self):
        run(PRIORITY + '''D.replace({deal('c:10','commodity',100,{{unit=60,qty=100}},now)},F.Engine.scope())
        F.db.settings.spendLimit=0.1; F.Engine.spent=400
        assert(T.runClick(), 'remaining visit budget buys ten units')
        assert(T.op.qty == 10 and T.op.cost == 600)
        local n=0
        for _, c in ipairs(calls) do
            if c[1]=='StartCommoditiesPurchase' or c[1]=='ConfirmCommoditiesPurchase' or c[1]=='PlaceBid' then n=n+1 end
        end
        assert(n == 1, 'only one protected action from the hardware click')''')


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
        assert(UI.fightBox.full():find('line 12'), 'the whole text stays readable')
        assert(UI.fightBox.rowTexts[1]:GetText() == 'line 2' and UI.fightBox.rowTexts[7]:GetText() == 'line 8',
            'one line on each row: the block is filled')''')


class UndercutsHoldTests(unittest.TestCase):
    def test_background_searches_rest_on_the_undercuts_page(self):
        run(SETUP + '''local UI = ForeverFlip.UI
        UI.show('undercuts')
        assert(ForeverFlip.Deals.holding())''')


if __name__ == '__main__':
    unittest.main()
