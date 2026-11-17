"""Best when both the auction house and a vendor pay: F.Market.routeVerdict.

A vendor that pays no less wins; the auction house wins when it is expected to bring clearly more
and nothing makes it doubtful, or when it is doubtful but the vendor pays too little to fall back
on. Doubtful (low Sure, too few sales, a price war) with a fair vendor price: the player chooses."""

import unittest

from test_addon import SETUP, run

VERDICT = SETUP + '''local F=ForeverFlip;local M=F.Market
local function routes(vendor, revenue)
    local cut=math.floor(revenue*0.05)
    return {both=true, vendor={revenue=vendor,cost=0,cut=0,lost=0,profit=vendor},
        auction={revenue=revenue,cost=0,cut=cut,lost=0,profit=revenue-cut}}
end
'''


class RouteVerdictTests(unittest.TestCase):
    def test_a_vendor_paying_more_wins(self):
        # The case from the game: a vendor pays 8s, the auction house 7s52 after the cut.
        run(VERDICT + '''local r={both=true,vendor={revenue=800,cost=0,cut=0,lost=0,profit=800},
            auction={revenue=792,cost=0,cut=40,lost=0,profit=752}}
        local v=M.routeVerdict(r,{sure=0.95,reliable=true})
        assert(v.way=='vendor' and v.why=='vendor_more', v.why)''')

    def test_a_small_gain_is_not_worth_the_wait(self):
        run(VERDICT + '''local v=M.routeVerdict(routes(1000,1150),{sure=0.95,reliable=true})
        assert(v.way=='vendor' and v.why=='small_gain', v.why)
        assert(v.gain>0 and v.gain<100, v.gain)''')

    def test_a_clear_gain_without_doubts_is_the_auction_house(self):
        run(VERDICT + '''local v=M.routeVerdict(routes(1000,3000),{sure=0.9,reliable=true})
        assert(v.way=='auction' and v.why=='ah_more' and #v.doubts==0, v.why)''')

    def test_doubtful_but_a_poor_vendor_price_is_still_the_auction_house(self):
        run(VERDICT + '''local v=M.routeVerdict(routes(500,3000),{sure=0.3,reliable=true})
        assert(v.way=='auction' and v.why=='vendor_poor', v.why)
        assert(v.doubts[1]=='sure')''')

    def test_doubtful_with_a_fair_vendor_price_is_the_players_call(self):
        out = run(VERDICT + '''local r=routes(1500,3000)
        local v=M.routeVerdict(r,{sure=0.9,reliable=false,war=true})
        assert(v.way=='undecided' and v.why=='doubtful', v.why)
        assert(table.concat(v.doubts,',')=='sales,war', table.concat(v.doubts,','))
        local unknown=M.routeVerdict(r,{})
        assert(unknown.way=='undecided' and unknown.doubts[1]=='sure', 'no Sure is a doubt')
        r.sure=0.9
        return F.UI.verdictReason(v,r)''')
        self.assertIn('price war', out)
        self.assertIn('too few sales', out)
        self.assertIn('Choose AH or Vendor', out)

    def test_only_when_both_routes_pay(self):
        run(VERDICT + '''local r=routes(1000,3000);r.both=false
        assert(M.routeVerdict(r,{sure=1})==nil)''')


if __name__ == '__main__':
    unittest.main()