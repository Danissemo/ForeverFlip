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

    def test_the_refusal_drops_its_vendor_deal_and_no_scan_puts_it_back(self):
        run(BASE + '''local D,AH=F.Deals,F.AH
        local g={key='c:2930',kind='commodity',id=2930,rows={{unit=10,qty=20}}}
        local d=D.evaluate(g,28,{},now)
        assert(d and d.mode=='vendor' and not d.refused)
        D.replace({d},F.Engine.scope())
        assert(D.get('c:2930'))
        AH.noteRefused(2930)
        assert(not D.get('c:2930'),'the deal goes when the merchant refuses')
        -- The refusal lasts the session: a scan (or a check) that evaluates the item again
        -- returns no deal at all, so D.replace/D.add cannot put it back on the list.
        local again,why=D.evaluate(g,28,{},now)
        assert(not again and why=='refused','a rescan finds no vendor deal: '..tostring(why))
        D.replace({},F.Engine.scope())
        assert(not D.get('c:2930'),'still gone after a rescan')''')

    def test_clearing_the_refusals_brings_the_deal_back(self):
        run(BASE + '''local D,AH=F.Deals,F.AH
        local g={key='c:2930',kind='commodity',id=2930,rows={{unit=10,qty=20}}}
        AH.noteRefused(2930)
        assert(not D.evaluate(g,28,{},now))
        AH.refused[2930]=nil -- /ff refused clear
        local d=D.evaluate(g,28,{},now)
        assert(d and d.mode=='vendor' and not d.refused,'a forgotten refusal lists it again')''')

    def test_a_sale_cut_short_by_the_closed_merchant_proves_nothing(self):
        run(BASE + '''local AH=F.AH
        -- onGiveUp with closing=true is a sale the window ended, not a refusal; the guard in
        -- sendStack only asks noteRefused while the merchant is open and the slot still holds it.
        assert(not AH.refused[2930],'nothing is refused before a sale is tried')''')

    def test_the_deal_lines_say_the_merchant_refuses_it(self):
        run(BASE + '''local AH=F.AH
        -- An entry built before the refusal keeps its warning (the flag is set before the deal is
        -- dropped): dealDetail still explains it for a list that predates the refusal.
        local d={key='c:2930',kind='commodity',id=2930,mode='vendor',refused=true,qty=1,cost=10,
          exit=28,profit=18,lots={{unit=10,qty=1}},offer={qty=1,cost=10,lots={{unit=10,qty=1}}}}
        local lines=F.UI.dealDetail(d,nil,{},now)
        assert(table.concat(lines,' '):find('refused this item',1,true),table.concat(lines,' | '))''')

    def test_the_game_flag_alone_keeps_it_off_the_list(self):
        run(BASE + '''bags[0][1].hasNoValue=true
        MerchantFrame:Show()
        assert(#T.vendorSellList()==0,'flagged by the game')
        assert(T.refusedInBags()==1)''')




class RefusedCommandTests(unittest.TestCase):
    """/ff refused names the session's refusals and can forget them."""

    def test_the_command_lists_and_clears(self):
        run(BASE + '''F.AH.noteRefused(2930);F.AH.noteRefused(2589)
        printed={}
        SlashCmdList.FOREVERFLIP('refused')
        local text=table.concat(printed,' | ')
        assert(text:find('2',1,true),text)
        SlashCmdList.FOREVERFLIP('refused clear')
        assert(F.AH.refused[2930]==nil and F.AH.refused[2589]==nil,'both are forgotten')
        ''')

    def test_a_forgotten_refusal_lists_the_item_again(self):
        run(BASE + '''local T=F.Trade
        F.AH.noteRefused(2930)
        MerchantFrame:Show()
        assert(#T.vendorSellList()==0,'refused: not offered')
        SlashCmdList.FOREVERFLIP('refused clear')
        assert(#T.vendorSellList()==1,'forgotten: offered again')
        ''')


if __name__ == '__main__':
    unittest.main()
