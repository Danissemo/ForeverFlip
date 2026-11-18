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
        # button stood: the two covered each other. While the filter shows, the button goes above.
        run(BASE + """MerchantFrame.FilterDropdown=CreateFrame('Frame',nil,MerchantFrame)
        MerchantFrame.FilterDropdown:Hide()
        """ + MERCHANT + """
        local b=UI.merchantButton
        local where
        b.SetPoint=function(_,point,_,rel) where=point..'>'..rel end
        b.ClearAllPoints=function() where=nil end
        UI.placeMerchantButton()
        MerchantFrame.FilterDropdown:Show()
        b:GetScript('OnUpdate')(b,0.3)
        assert(where=='BOTTOMRIGHT>TOPRIGHT','above the frame while the filter shows: '..tostring(where))
        MerchantFrame.FilterDropdown:Hide()
        b:GetScript('OnUpdate')(b,0.3)
        assert(where=='TOPRIGHT>TOPRIGHT','back under the title without it: '..tostring(where))""")


if __name__ == '__main__':
    unittest.main()
