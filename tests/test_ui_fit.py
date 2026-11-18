"""Buttons fit their labels: a translation longer than the width widens the button instead of
running past its frame (the Ukrainian "Sell gear I can't use" ran off the merchant window)."""

import unittest

from test_addon import run

BASE = "local F=ForeverFlip;local UI=F.UI\n"
MERCHANT = "addItem(2589,'Linen Cloth',100000,'commodity')\nputBag(0,1,2589,20)\nMerchantFrame:Show()\nUI.merchant(true)\n"


class FitButtonTests(unittest.TestCase):
    def test_a_button_grows_for_a_label_longer_than_its_width(self):
        run(BASE + """local b=UI.fitButton(CreateFrame('Button',nil,UIParent),100)
        b:SetText('short')
        b.fitWidth()
        local short=b.width
        b:SetText('Продати непридатне спорядження')
        b.fitWidth()
        assert(b.width>short,'a longer label widens the button')
        assert(b.width>=100,'never narrower than the width asked for')""")

    def test_the_gear_button_fits_its_ukrainian_label(self):
        run(BASE + """F.db.settings.language='uk'
        """ + MERCHANT + """
        local b=UI.merchantView.sellGear
        assert(b and b:GetText()~='','the gear button exists with its label')
        assert(b.width>=#b:GetText()*7,'the button is at least as wide as its label needs')""")

    def test_the_merchant_button_fits_a_long_total(self):
        run(BASE + """F.db.settings.language='uk'
        """ + MERCHANT + """
        local b=UI.merchantButton
        assert(b,'the merchant button exists')
        b:SetText('Продати торговцю (12): 1 234 56 78')
        b.fitWidth()
        assert(b.width>=#b:GetText()*7,'the count and total are not cut off')""")


    def test_the_merchant_button_moves_off_the_class_filter(self):
        # Retail shows a class filter at the top right of a merchant with class goods, where the
        # button stood: the two covered each other. While the filter shows, the button stands left
        # of the player's money at the bottom (above the frame it left the window).
        run(BASE + """MerchantFrame.FilterDropdown=CreateFrame('Frame',nil,MerchantFrame)
        MerchantMoneyInset=CreateFrame('Frame',nil,MerchantFrame)
        MerchantFrame.FilterDropdown:Hide()
        """ + MERCHANT + """
        local b=UI.merchantButton
        local where
        b.SetPoint=function(_,point,_,rel) where=point..'>'..rel end
        b.ClearAllPoints=function() where=nil end
        UI.placeMerchantButton()
        MerchantFrame.FilterDropdown:Show()
        b:GetScript('OnUpdate')(b,0.3)
        assert(where=='RIGHT>LEFT','left of the money while the filter shows: '..tostring(where))
        MerchantFrame.FilterDropdown:Hide()
        b:GetScript('OnUpdate')(b,0.3)
        assert(where=='TOPRIGHT>TOPRIGHT','back under the title without it: '..tostring(where))""")

    def test_the_merchant_button_is_short_small_and_says_what_it_is(self):
        # "Sell to vendor (14): 2700g 97s" in the normal font ran past the merchant window.
        run(BASE + """F.db.settings.vendorMargin = 0
        addItem(71, 'Murloc Fin', 28, 'commodity'); putBag(0, 1, 71, 4)
        F.Data.market(F.db, F.Engine.scope()).history['c:71'] = { scan = { at = now, market = 20 } }
        MerchantFrame:Show(); fire('MERCHANT_SHOW')
        local b=UI.merchantButton
        assert(b:GetText():find('^Sell %(1%): '),b:GetText())
        assert(b.height==20,'a little lower than the game buttons: '..tostring(b.height))
        b:GetScript('OnEnter')(b)
        assert(GameTooltip:IsShown(),'the hover says it is ForeverFlip')
        b:GetScript('OnLeave')(b)""")


if __name__ == '__main__':
    unittest.main()
