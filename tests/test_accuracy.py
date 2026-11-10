"""Deposits from the game, neutral auction houses and fresh commodity quotes."""

import unittest

from test_addon import SETUP, run, runtime


class DepositTests(unittest.TestCase):
    def test_commodity_deal_uses_the_deposit_the_game_charges(self):
        run('''local M=ForeverFlip.Market
        C_AuctionHouse.CalculateCommodityDeposit=function(id,duration,qty) return 300*qty end
        local fn=ForeverFlip.AH.depositFn(10,'commodity',100,3);assert(fn(1)==300 and fn(4)==1200)
        local rows={{unit=100,qty=4},{unit=1000,qty=50}}
        local h={flow={hours=24,sold={90,90,90,90},pairs=4,at=now,market=1000}}
        local ctx={kind='commodity',vendor=10,budget=1e6,history=h,market=1000,now=now,deposit=fn,
          settings={minProfit=1,minROI=0}}
        local d=M.evaluate(rows,ctx);assert(d and d.profit==M.net(999,4)-400-1200,d and d.profit)''')

    def test_item_deposit_is_learned_when_posting(self):
        run(SETUP + '''C_AuctionHouse.CalculateItemDeposit=function() return 250 end
        assert(ForeverFlip.AH.depositFn(30,'item',2000,3)==nil)
        putBag(0,1,30,1);local item=ForeverFlip.AH.bagItems()[1]
        ForeverFlip.Trade.post(item,1,40000,3)
        local fn=ForeverFlip.AH.depositFn(30,'item',2000,3);assert(fn and fn(2)==500)''')


class NeutralHouseTests(unittest.TestCase):
    def test_neutral_house_has_its_own_scope_and_a_15_percent_cut(self):
        lua = runtime(open_ah=False)
        lua.execute('''function GetSubZoneText() return "Booty Bay" end
        fire('AUCTION_HOUSE_SHOW')
        local E,M=ForeverFlip.Engine,ForeverFlip.Market
        assert(E.scope()=='Realm-Neutral' and M.CUT==0.15)
        fire('AUCTION_HOUSE_CLOSED');assert(E.scope()=='Realm-Alliance' and M.CUT==0.05)
        ForeverFlip.db.cuts={['Realm-Neutral']=0.1}
        fire('AUCTION_HOUSE_SHOW');assert(M.CUT==0.1)''')

class QuoteTests(unittest.TestCase):
    def test_stale_quote_is_asked_again_instead_of_confirmed(self):
        run(SETUP + '''fullScan();local D,T=ForeverFlip.Deals,ForeverFlip.Trade
        D.verify('c:10');answer();T.buy('c:10');fire('COMMODITY_PRICE_UPDATED',60,900)
        local left=1;C_AuctionHouse.GetQuoteDurationRemaining=function() return left end
        local starts=0;for _,c in ipairs(calls) do if c[1]=='StartCommoditiesPurchase' then starts=starts+1 end end
        assert(not T.confirm() and T.op.state=='quote' and not lastCall('ConfirmCommoditiesPurchase'))
        local again=0;for _,c in ipairs(calls) do if c[1]=='StartCommoditiesPurchase' then again=again+1 end end
        assert(again==starts+1 and lastCall('CancelCommoditiesPurchase'))
        fire('COMMODITY_PRICE_UPDATED',60,900);left=20
        assert(T.confirm() and lastCall('ConfirmCommoditiesPurchase'))''')


if __name__ == '__main__':
    unittest.main()
