"""Resale distinguishes observed sales data from missing data and updates after money gains."""

import unittest

from test_addon import SETUP, run


RESALE = SETUP + '''local F = ForeverFlip
local D, M, S = F.Deals, F.Market, F.Scan
addItem(40,'Resale Test Item',0,'item')
addAuction(40,1000,1); addAuction(40,5000,10)
local history = F.Data.market(F.db,F.Engine.scope()).history
history['i:40'] = {}
M.recordSales(history['i:40'],{[5000]=10},3600,now-60)
money=606
fullScan()
'''


class ResaleDiagnosticTests(unittest.TestCase):
    def test_unaffordable_first_lot_reports_budget_instead_of_no_price_gap(self):
        run('''local deal, why = ForeverFlip.Market.evaluate({{unit=1000,qty=1},{unit=5000,qty=10}},
            {kind='item',budget=484,itemBudget=181,market=5000,history={},settings={}})
        assert(not deal and why=='budget', 'the first lot cannot fit the spending limit')''')

    def test_sales_data_counter_counts_observations_not_rejected_candidates(self):
        run(RESALE + '''assert(not D.get('i:40'), 'no affordable resale at 606 copper')
        assert(S.last.stats.salesReady and S.last.stats.salesReady>0, 'there are measured sales despite no offer')
        assert(S.last.stats.reasons.budget>0, 'budget exclusions are accounted for')
        F.UI.refreshSummary()
        assert(F.UI.summary:GetText():find('Sales data: '..S.last.stats.salesReady,1,true))''')

    def test_empty_resale_shows_current_limits_instead_of_promising_two_scans(self):
        run(RESALE + '''F.UI.show('deals:flip')
        local message=F.UI.dealTable.empty:GetText()
        assert(message:find('Budget',1,true) and message:find('1s',1,true), message)
        assert(not message:find('needs sales data from 2 full scans',1,true), message)''')

    def test_restoring_an_older_snapshot_rebuilds_missing_sales_counter(self):
        run(RESALE + '''S.save()
        F.Data.market(F.db,F.Engine.scope()).last.stats.salesReady=nil
        S.last=nil
        assert(S.restore(F.Engine.scope()))
        assert(S.last.stats.salesReady and S.last.stats.salesReady>0, 'old saved scan gets an accurate counter')''')


class WalletReevaluationTests(unittest.TestCase):
    def test_money_gain_cannot_resurrect_a_lot_disproved_by_a_newer_exact_check(self):
        run(SETUP + '''local F,D=ForeverFlip,ForeverFlip.Deals
        fullScan();assert(D.get('c:10'))
        for i=#auctions,1,-1 do
            if auctions[i].item==10 and auctions[i].buyout<500 then table.remove(auctions,i) end
        end
        D.verify('c:10');answer();assert(not D.get('c:10'))
        money=money+10000;fire('PLAYER_MONEY');run(1)
        assert(not D.get('c:10'), 'newer negative verification supersedes old scan rows')''')

    def test_budget_only_rejection_can_use_newer_exact_rows_after_money_gain(self):
        run(RESALE + '''D.verify('i:40');answer();assert(not D.get('i:40'))
        money=100000;fire('PLAYER_MONEY');run(1)
        assert(D.get('i:40') and not D.get('i:40').verified, 'affordability can change even after a check')''')

    def test_money_gain_reevaluates_cached_scan_without_another_server_search(self):
        run(RESALE + '''assert(not D.get('i:40'))
        local sent=0; F.AH.search=function() sent=sent+1 end
        money=100000; fire('PLAYER_MONEY'); run(1)
        local deal=D.get('i:40')
        assert(deal and deal.mode=='flip' and not deal.verified, 'newly affordable leads appear and still require verification')
        assert(sent==0, 're-evaluation is local')''')

    def test_old_scan_does_not_replace_live_verified_results_on_money_gain(self):
        run(RESALE + '''local live={key='i:40',id=40,kind='item',mode='flip',qty=1,cost=1200,profit=100,
            exit=1500,verified=now,found=now}
        D.add(live,F.Engine.scope())
        money=100000; fire('PLAYER_MONEY'); run(1)
        assert(D.get('i:40')==live, 'keep the newer verified result')''')

    def test_consumed_item_is_not_resurrected_from_old_scan_on_money_gain(self):
        run(RESALE + '''D.afterPurchase({key='i:40',kind='item',qty=1,auctionID=42})
        D.clear(); D.list={}
        money=100000; fire('PLAYER_MONEY'); run(1)
        assert(not D.get('i:40'), 'a bought key is not reintroduced by the stale full scan')''')


if __name__ == '__main__':
    unittest.main()
