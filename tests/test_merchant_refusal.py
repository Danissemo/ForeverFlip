"""Items the item data prices but a merchant refuses (poisons): never offered as a vendor deal
without a warning, never offered on the Merchant tab, and learned from a sale the merchant refuses."""

import unittest

from test_addon import run

BASE = '''local F=ForeverFlip;local T,UI=F.Trade,F.UI
F.db.settings.autoScan=false;F.db.settings.sniper=false;F.db.settings.autoVerify=false
F.db.settings.vendorMargin=0
addItem(2930,'Instant Poison',28,'commodity')
putBag(0,1,2930,20)
F.Data.market(F.db,F.Engine.scope()).history['c:2930']={scan={at=now,market=20}}
'''


class RefusedByMerchantTests(unittest.TestCase):
    def test_a_refused_item_is_not_offered_the_second_time(self):
        run(BASE + '''merchantWontBuy[2930]=true
        MerchantFrame:Show()
        assert(#T.vendorSellList()==1,'offered while nothing is known')
        T.sellAllToVendor()
        for _=1,200 do run(0.1);if not T.sellingToVendor() then break end end
        assert(F.AH.refused[2930],'the refusal is learned')
        assert(#T.vendorSellList()==0,'no longer offered')
        local last=printed[#printed]
        assert(last:find('does not buy',1,true),last)''')

    def test_the_refusal_drops_its_vendor_deal_and_marks_a_new_one(self):
        run(BASE + '''local D,AH=F.Deals,F.AH
        local d=D.evaluate({key='c:2930',kind='commodity',id=2930,rows={{unit=10,qty=20}}},28,{},now)
        assert(d and d.mode=='vendor' and not d.refused)
        D.replace({d},F.Engine.scope())
        assert(D.get('c:2930'))
        AH.noteRefused(2930)
        assert(not D.get('c:2930'),'the deal goes when the merchant refuses')
        local again=D.evaluate({key='c:2930',kind='commodity',id=2930,rows={{unit=10,qty=20}}},28,{},now)
        assert(again and again.refused,'a later deal keeps the warning')''')

    def test_the_deal_lines_say_the_merchant_refuses_it(self):
        run(BASE + '''F.AH.noteRefused(2930)
        local d=F.Deals.evaluate({key='c:2930',kind='commodity',id=2930,rows={{unit=10,qty=20},link='|cffffffff|Hitem:2930|h[Instant Poison]|h|r'}},28,{},now)
        local lines=F.UI.dealDetail(d,nil,{},now)
        assert(table.concat(lines,' '):find('refused this item',1,true),table.concat(lines,' | '))''')

    def test_the_game_flag_alone_keeps_it_off_the_list(self):
        run(BASE + '''bags[0][1].hasNoValue=true
        MerchantFrame:Show()
        assert(#T.vendorSellList()==0,'flagged by the game')
        assert(T.refusedInBags()==1)''')


if __name__ == '__main__':
    unittest.main()
