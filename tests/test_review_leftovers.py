"""Code review leftovers: one merchant sale at a time in the interface, and Stop ends a merchant sale."""

import unittest

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


if __name__ == "__main__":
    unittest.main()
