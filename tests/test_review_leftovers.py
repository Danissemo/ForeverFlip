"""Code review leftovers: one merchant sale at a time in the interface, and Stop ends a merchant sale."""

import unittest

from test_addon import SETUP
from test_review_trade_b import GEAR, SLOW, run


class GearButtonTests(unittest.TestCase):
    """UI.merchant: the gear buttons wait while a merchant sale goes; the chat tells only what sold."""

    def test_the_buttons_wait_for_the_sale_and_the_click_prints_nothing_yet(self):
        run(GEAR + '''MerchantFrame:Show(); fire('MERCHANT_SHOW')
        local before = #printed
        UI.gearButton:Click()
        assert(T.sellingToVendor(), 'the sale goes in paced batches')
        assert(#printed == before, 'nothing printed before anything sold: ' .. tostring(printed[#printed]))
        assert(not UI.gearButton:IsEnabled() and not UI.merchantView.sellGear:IsEnabled())
        assert(not UI.merchantView.sellAll:IsEnabled())
        for _ = 1, 100 do run(0.1); if not T.sellingToVendor() then break end end
        UI.merchant(true)
        assert(printed[#printed]:find('pieces of gear', 1, true), printed[#printed])
        assert(#printed == before + 1, 'one line, from the end of the sale')
        assert(UI.gearButton:IsEnabled(), 'free again once the sale ended')''')


class StopVendorTests(unittest.TestCase):
    """D.stopAll ends a merchant sale through Trade.stopVendor, which settles the stacks it drops."""

    def test_stop_drops_what_is_not_sent_and_the_sale_ends(self):
        run(GEAR + '''MerchantFrame:Show(); fire('MERCHANT_SHOW')
        local listed = #T.unusableGearList()
        T.sellUnusableGear()
        local sent = #soldToVendor
        assert(sent > 0 and sent < listed)
        D.stopAll()
        for _ = 1, 20 do run(0.1); if not T.sellingToVendor() then break end end
        assert(not T.sellingToVendor(), 'the sale ended')
        assert(#soldToVendor == sent, 'nothing more sent after Stop: ' .. #soldToVendor)''')

    def test_a_queued_stack_whose_late_answer_sold_it_is_booked(self):
        run(SLOW + '''D.stopAll()
        assert(not T.vendorJob, 'nothing left to wait for')
        assert(c.stats['c:71'].sold == 1 and not c.positions['c:71'], 'booked as sold')''')

    def test_a_queued_stack_still_in_the_bags_is_no_longer_expected(self):
        run(SLOW + '''putBag(0, 1, 71, 1) -- the late answer did not sell it after all
        local cancelled = 0
        local cancel = F.Merchant.cancelExpectedSale
        F.Merchant.cancelExpectedSale = function(...) cancelled = cancelled + 1; return cancel(...) end
        D.stopAll()
        assert(not T.vendorJob and cancelled == 1, 'the merchant watch stops expecting it')
        assert(c.positions['c:71'], 'still in stock')''')


MERCHANT = SETUP + '''local F = ForeverFlip
local c = F.Data.char(F.db, F.Engine.owner())
addItem(70, 'Weighted Throwing Axe', 50, 'item'); merchantItems = { { id = 70, price = 270 } }
local offer = { index = 1, key = 'i:70', link = link(70), unit = 270, qty = 3, exit = 900 }
'''


class MerchantPurchaseTests(unittest.TestCase):
    """V14-b: a merchant purchase is booked as its units reach the bags, never what was refused."""

    def test_a_refused_purchase_books_nothing(self):
        run(MERCHANT + '''merchantRefuses = true
        assert(F.Merchant.buy(offer), 'the calls were sent')
        assert(not c.positions['i:70'], 'nothing came: nothing booked')
        now = now + F.Merchant.BUY_WAIT + 1; fire('BAG_UPDATE_DELAYED')
        assert(#F.Merchant.waiting == 0 and not c.positions['i:70'], 'given up after the wait')''')

    def test_units_that_come_late_are_booked_when_the_bags_settle(self):
        run(MERCHANT + '''merchantRefuses = true
        F.Merchant.buy(offer)
        merchantReceived[70] = 2 -- two of the three reach the bags a moment later
        fire('BAG_UPDATE_DELAYED')
        assert(c.positions['i:70'].qty == 2 and c.positions['i:70'].cost == 540, 'only what came')
        local e = c.journal[#c.journal]
        assert(e.kind == 'buy' and e.qty == 2 and e.amount == 540 and e.merchant)
        fire('BAG_UPDATE_DELAYED')
        assert(c.positions['i:70'].qty == 2, 'booked once')''')


if __name__ == "__main__":
    unittest.main()
