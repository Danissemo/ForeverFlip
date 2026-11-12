"""Confirmed sales drive today's estimates; flow-only history remains a compatibility fallback."""

import unittest

from test_addon import ADDON, lupa


class FlowFallbackTests(unittest.TestCase):
    """Older flow-only records still work; these are not the current scan's primary sales model."""
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        for name in ('Util.lua', 'Market.lua'):
            self.lua.execute((ADDON / name).read_text(encoding='utf-8'))
        self.assertIsNotNone(
            self.lua.eval('ForeverFlip.Market.saleability'),
            'missing saleability API: unknown demand must not look like observed zero',
        )

    def test_unknown_has_no_numeric_rate_but_an_observed_zero_does(self):
        self.lua.execute('''
        local M=ForeverFlip.Market
        local unknown=M.saleability(nil,100,1000)
        assert(not unknown.known and unknown.perDay==nil and unknown.pairs==0)
        assert(unknown.at==nil and unknown.hours==nil and unknown.age==nil and not unknown.stale)
        local h={flow={hours=12,sold={0,0,0,0},pairs=0,at=1000,market=100}}
        local collecting=M.saleability(h,100,1000)
        assert(not collecting.known and collecting.perDay==nil)
        h.flow.pairs=1
        local zero=M.saleability(h,100,1000)
        assert(zero.known and zero.perDay==0 and zero.pairs==1 and zero.hours==12)
        ''')

    def test_rate_uses_the_requested_exit_price_level(self):
        self.lua.execute('''
        local M=ForeverFlip.Market
        local h={flow={hours=12,sold={24,12,6,3},pairs=4,at=1000,market=100}}
        local cheap=M.saleability(h,60,1000)
        local exit=M.saleability(h,100,1000)
        local high=M.saleability(h,120,1000)
        assert(cheap.known and cheap.perDay==36)
        assert(exit.known and exit.perDay==9 and exit.pairs==4)
        assert(high.known and high.perDay==4.5)
        ''')

    def test_age_uses_last_usable_pair_and_marks_old_estimates_without_zeroing(self):
        self.lua.execute('''
        local M=ForeverFlip.Market
        local h={scan={at=20000,market=100},flow={hours=12,sold={24,12,6,3},pairs=4,at=1000,market=100}}
        local edge=M.saleability(h,100,11800)
        assert(edge.at==1000 and edge.age==10800 and not edge.stale)
        local old=M.saleability(h,100,11801)
        assert(old.known and old.perDay==9 and old.at==1000 and old.age==10801 and old.stale)
        local future=M.saleability(h,100,999)
        assert(future.age==0 and not future.stale)
        local noClock=M.saleability(h,100)
        assert(noClock.known and noClock.at==1000 and noClock.age==nil and not noClock.stale)
        ''')

    def test_price_above_recorded_support_is_unknown(self):
        self.lua.execute('''
        local M=ForeverFlip.Market
        local h={flow={hours=12,sold={24,12,6,3},pairs=4,at=1000,market=170}}
        local supported=M.saleability(h,210,1000)
        assert(supported.known and supported.perDay==4.5)
        local unsupported=M.saleability(h,211,1000)
        assert(not unsupported.known and unsupported.perDay==nil and unsupported.pairs==4)
        ''')

    def test_invalid_price_or_history_does_not_invent_a_rate(self):
        self.lua.execute('''
        local M=ForeverFlip.Market
        local h={flow={hours=12,sold={24,12,6,3},pairs=4,at=1000,market=100}}
        for _,price in ipairs({0,-1,math.huge,0/0,'100'}) do
            local d=M.saleability(h,price,1000)
            assert(not d.known and d.perDay==nil)
        end
        for _,history in ipairs({false,'bad',{}, {flow=false}, {flow={pairs=1,hours=0,market=100,sold={1}}},
            {flow={pairs=1,hours=12,market=100,sold={1}}},
            {flow={pairs=1,hours=12,market=100,sold={1,1,'bad',1}}}}) do
            local d=M.saleability(history,100,1000)
            assert(not d.known and d.perDay==nil)
        end
        ''')

    def test_reading_metadata_is_pure_and_cannot_change_trading_demand(self):
        self.lua.execute('''
        local M=ForeverFlip.Market
        local function frozen(values)
            return setmetatable({}, {__index=values,__newindex=function() error('saleability mutated history') end})
        end
        local h=frozen({scan=frozen({at=20000,market=100}),flow=frozen({hours=12,sold=frozen({24,12,6,3}),pairs=4,at=1000,market=100})})
        local d=M.saleability(h,100,20000)
        assert(d.known and d.perDay==9 and d.stale)
        d.perDay=999;d.pairs=999
        local again=M.saleability(h,100,20000)
        assert(again.perDay==9 and again.pairs==4)
        local trading=M.demandAt(h,100,20000)
        assert(trading.perDay==9 and trading.pairs==4 and trading.hours==12)
        local unsupportedTrading=M.demandAt(h,200,20000)
        assert(unsupportedTrading.perDay==4.5 and unsupportedTrading.pairs==4)
        ''')


    def test_a_short_observation_is_smoothed(self):
        self.lua.execute('''
        local M=ForeverFlip.Market
        local h={flow={hours=0.25,sold={1,1,1,1},pairs=1,at=1000,market=100}}
        local d=M.saleability(h,100,1000)
        assert(d.known and d.perDay>5 and d.perDay<6,d.perDay)
        h.flow.hours,h.flow.sold=96,{96,96,96,96}
        d=M.saleability(h,100,1000);assert(d.perDay>23 and d.perDay<24,'long data stays near the measured 24')
        ''')


class ConfirmedSaleabilityTests(unittest.TestCase):
    """Small examples using the same sales records that complete scans produce."""

    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        for name in ('Util.lua', 'Market.lua'):
            self.lua.execute((ADDON / name).read_text(encoding='utf-8'))
        self.lua.execute("""
        function observedSales(hours, soldAtPrice, pairs, at)
            local history={}
            ForeverFlip.Market.recordSales(history, soldAtPrice, hours*3600, at)
            history.sales.pairs=pairs
            return history
        end
        """)

    def test_no_observation_is_unknown_but_an_observed_empty_record_is_zero(self):
        self.lua.execute("""
        local M=ForeverFlip.Market
        local h=observedSales(12,{},0,1000)
        assert(not M.saleability(h,100,1000).known, 'no scan pair means unknown')
        h.sales.pairs=1
        local rate=M.saleability(h,100,1000)
        assert(rate.known and rate.lots and rate.perDay==0, 'watched, but no sales means zero')
        """)

    def test_only_sales_near_the_requested_price_contribute_to_the_rate(self):
        self.lua.execute("""
        local M=ForeverFlip.Market
        -- Twelve sold at 60, six at 90 and three at 110, over twelve hours.
        local h=observedSales(12,{[60]=12,[90]=6,[110]=3},4,1000)
        assert(M.saleability(h,60,1000).perDay==31.5, 'all 21 sales count at the cheap price')
        assert(M.saleability(h,100,1000).perDay==13.5, 'only nine sales reach 85% of 100')
        assert(M.saleability(h,120,1000).perDay==4.5, 'only three reach 85% of 120')
        """)

    def test_no_sales_at_a_high_price_is_zero_for_confirmed_sales_not_unknown(self):
        self.lua.execute("""
        local h=observedSales(12,{[100]=3},4,1000)
        local rate=ForeverFlip.Market.saleability(h,1000,1000)
        assert(rate.known and rate.lots and rate.perDay==0,
            'a valid observed record can contain no sales near this high price')
        """)

    def test_age_comes_from_the_sales_record_and_does_not_clear_its_rate(self):
        self.lua.execute("""
        local M=ForeverFlip.Market
        local h=observedSales(12,{[100]=6},4,1000);h.scan={at=20000}
        local edge=M.saleability(h,100,11800)
        assert(edge.age==10800 and not edge.stale)
        local old=M.saleability(h,100,11801)
        assert(old.age==10801 and old.stale and old.perDay==9)
        assert(M.saleability(h,100,999).age==0, 'clock differences cannot make a negative age')
        """)

    def test_short_observations_are_smoothed_for_confirmed_sales_too(self):
        self.lua.execute("""
        local M=ForeverFlip.Market
        local h=observedSales(0.25,{[100]=1},1,1000)
        local short=M.saleability(h,100,1000)
        assert(short.perDay>5 and short.perDay<6, 'one sale in 15 minutes is not 96 per day')
        h=observedSales(96,{[100]=96},1,1000)
        local long=M.saleability(h,100,1000)
        assert(long.perDay>23 and long.perDay<24, 'longer history stays near its measured rate')
        """)

    def test_confirmed_sales_override_an_inflated_flow_fallback(self):
        self.lua.execute("""
        local M=ForeverFlip.Market
        local h=observedSales(12,{[100]=6},4,1000)
        h.flow={hours=12,pairs=99,at=2000,market=100,sold={999,999,999,999}}
        local shown=M.saleability(h,100,1000)
        local trading=M.demandAt(h,100,1000)
        assert(shown.lots and shown.perDay==9 and shown.pairs==4 and shown.at==1000)
        assert(trading.perDay==9 and trading.sold==6, 'trading must use the same confirmed sales')
        """)

    def test_reading_a_rate_does_not_change_the_saved_sales(self):
        self.lua.execute("""
        local M=ForeverFlip.Market
        local h=observedSales(12,{[100]=6},4,1000)
        local saved=ForeverFlip.Util.copy(h)
        local shown=M.saleability(h,100,1000)
        shown.perDay,shown.pairs=999,999
        local again=M.saleability(h,100,1000)
        assert(again.perDay==9 and again.pairs==4)
        assert(h.sales.hours==12 and h.sales.pairs==4 and h.sales.at==1000)
        for key,value in pairs(saved.sales.b) do
            assert(h.sales.b[key]==value, 'displaying a rate must not rewrite history')
        end
        """)


if __name__ == '__main__':
    unittest.main()
