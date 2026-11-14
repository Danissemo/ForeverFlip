"""Accounting from auction mail: invoices, failed posts, sale rate and the learned cut."""

import unittest

from test_addon import SETUP, run

MAIL = SETUP + '''local F=ForeverFlip
local c=F.Data.char(F.db,F.Engine.owner())
'''


class InvoiceTests(unittest.TestCase):
    def test_invoice_books_a_sale_posted_outside_the_addon(self):
        run(MAIL + '''F.Data.addPosition(c,'i:30','Linen Bag',1,20000,'flip',29900,now-3600)
        inbox={{sender='Auction House',subject='Auction successful: Linen Bag',money=28500,
          invoice={kind='seller',item='Linen Bag',bid=30000,cut=1500,deposit=100,count=1}}}
        fire('MAIL_SHOW');fire('MAIL_INBOX_UPDATE');F.Mail.start();for _=1,10 do run(0.1) end
        assert(not c.positions['i:30'],'stock sold')
        local e=c.journal[#c.journal];assert(e.kind=='sell' and e.amount==28500 and e.profit==8500,e.amount)
        assert(c.rates['linen bag'].sold==1)''')

    def test_invoice_does_not_book_twice_after_the_auction_list(self):
        run(MAIL + '''F.Data.addPosition(c,'i:30','Linen Bag',1,20000,'flip',29900,now-3600)
        c.listings={{key='i:30',name='Linen Bag',qty=1,price=30000,at=now,ids={7},open=1,auctions=1}}
        owned={{auctionID=7,itemKey={itemID=30},quantity=1,buyoutAmount=30000,status=1}}
        fire('OWNED_AUCTIONS_UPDATED');assert(not c.positions['i:30'])
        local n=#c.journal
        inbox={{subject='Auction successful: Linen Bag',money=28500,
          invoice={kind='seller',item='Linen Bag',bid=30000,cut=1500,count=1}}}
        fire('MAIL_SHOW');F.Mail.record(1);assert(#c.journal==n,'already booked')''')

    def test_expired_mail_lowers_the_sale_rate_and_the_trust(self):
        run(MAIL + '''F.Data.addPosition(c,'i:30','Linen Bag',1,20000,'flip',29900,now)
        inbox={}
        for i=1,3 do inbox[i]={subject='Auction expired: Linen Bag',items=1} end
        inbox[4]={subject='Auction successful: Linen Bag',money=100,invoice={kind='seller',item='Linen Bag',bid=100,count=1}}
        fire('MAIL_SHOW');for i=1,4 do F.Mail.record(i) end
        local rate=F.Trade.rate('Linen Bag');assert(rate==0.25,rate)
        local t=F.Deals.trust('i:30',now);assert(t==0.5,t)''')

    def test_count_is_the_eleventh_value_and_a_stack_sale_books_every_unit(self):
        run(MAIL + '''F.Data.addPosition(c,'c:2592','Wool Cloth',5,300,'flip',103,now-3600)
        inbox={{subject='Auction successful: Wool Cloth (5)',money=490,
          invoice={kind='seller',item='Wool Cloth',bid=515,cut=25,count=5}}}
        fire('MAIL_SHOW');F.Mail.record(1)
        assert(not c.positions['c:2592'] and c.rates['wool cloth'].sold==5)
        assert(c.invoices[1].qty==5)''')

    def test_missing_count_comes_from_the_subject(self):
        run(MAIL + '''F.Data.addPosition(c,'c:2592','Wool Cloth',5,300,'flip',103,now-3600)
        inbox={{subject='Auction successful: Wool Cloth (5)',money=490,
          invoice={kind='seller',item='Wool Cloth',bid=515,cut=25,count=0}}}
        fire('MAIL_SHOW');F.Mail.record(1)
        assert(c.rates['wool cloth'].sold==5 and not c.positions['c:2592'])''')

    def test_invoices_saved_without_a_count_are_booked_once(self):
        run(MAIL + '''F.Data.addPosition(c,'g:9781:bandit pants of the monkey','Bandit Pants of the Monkey',1,3400,'flip',8800,now-86400)
        F.Data.addPosition(c,'c:2593','Flask of Stormwind Tawny',3,300,'flip',198,now-86400)
        c.listings={{key='g:9781:bandit pants of the monkey',name='Bandit Pants of the Monkey',qty=1,price=8800,at=now-80000,ids={1},open=1,auctions=1},
          {key='c:2593',name='Flask of Stormwind Tawny',qty=3,price=198,at=now-80000,ids={2},open=3,auctions=1}}
        c.invoices={{at=now-100,item='Bandit Pants of the Monkey',qty=0,net=8360,cut=440},
          {at=now-200,item='Flask of Stormwind Tawny',qty=0,net=565,cut=29}}
        assert(F.Trade.repairInvoices()==2)
        assert(not c.positions['g:9781:bandit pants of the monkey'] and not c.positions['c:2593'])
        local s=c.stats['g:9781:bandit pants of the monkey'];assert(s.sold==1 and s.profit==4960,s.profit)
        assert(c.rates['flask of stormwind tawny'].sold==3 and c.invoices[2].qty==3)
        local n=#c.journal;assert(F.Trade.repairInvoices()==0 and #c.journal==n,'once')''')

    def test_each_mail_is_booked_once(self):
        run(MAIL + '''inbox={{subject='Auction expired: Linen Bag (5)',items=1}}
        fire('MAIL_SHOW');fire('MAIL_INBOX_UPDATE');F.Mail.record(1);F.Mail.record(1)
        assert(c.rates['linen bag'].failed==5)''')

    def test_neutral_cut_is_learned_from_an_invoice(self):
        run(MAIL + '''inbox={{subject='Auction successful: X',money=8500,invoice={kind='seller',item='X',bid=10000,cut=1500,count=1}}}
        fire('MAIL_SHOW');F.Mail.record(1)
        assert(math.abs(F.db.cuts['Realm-Neutral']-0.15)<1e-9 and not F.db.cuts['Realm-Alliance'])''')


    def test_a_cancelled_auction_mailed_with_a_buyer_invoice_is_no_purchase(self):
        run(MAIL + '''local me = UnitName('player')
        F.Data.addPosition(c,'i:30','Linen Bag',3,3000,'flip',1500,now-3600)
        inbox={{sender='Auction House',subject='Linen Bag',items=1,
          invoice={kind='buyer',item='Linen Bag',player=me,bid=4500,count=3}}}
        local n = #c.journal
        fire('MAIL_SHOW');fire('MAIL_INBOX_UPDATE');F.Mail.start();for _=1,10 do run(0.1) end
        assert(c.positions['i:30'].qty == 3, 'no units added: ' .. c.positions['i:30'].qty)
        for i = n + 1, #c.journal do assert(c.journal[i].kind ~= 'buy', 'booked as a purchase') end''')


    def test_a_buyer_invoice_after_the_sale_is_no_second_purchase(self):
        # Bought, sold; the sale's mail read before the purchase's own mail (the seller invoice is
        # the one that arrives first). That mail must not book the purchase a second time: it used
        # to add stock that was never paid for, a lot that stayed open for good and a duplicate row.
        run(MAIL + '''F.Trade.awaitBuyerInvoice('Linen Bag', 1)
        F.Data.addPosition(c,'i:30','Linen Bag',1,20000,'flip',29900,now-3600)
        F.Data.log(c,{at=now-3600,kind='buy',key='i:30',name='Linen Bag',qty=1,amount=20000,mode='flip'})
        assert(c.awaitMail['linen bag'].n == 1, 'the purchase waits for its mail')
        inbox={{sender='Auction House',subject='Auction successful: Linen Bag',money=28500,
          invoice={kind='seller',item='Linen Bag',bid=30000,cut=1500,count=1}}}
        fire('MAIL_SHOW');F.Mail.record(1)
        assert(not c.positions['i:30'] and c.awaitMail['linen bag'].n == 0, 'the sale settles the purchase')
        local n = #c.journal
        F.Trade.onBuyerInvoice({item='Linen Bag',count=1,bid=20000}, link(30,'Linen Bag'))
        assert(not c.positions['i:30'], 'no stock from an already sold purchase')
        assert(#c.journal == n, 'no second purchase row')
        local lots = F.Data.lots(c)
        assert(#lots == 1 and lots[1].left == 0, 'one lot, fully sold')''')

    def test_a_purchase_still_waiting_is_matched_not_booked_again(self):
        # The other side of the same rule: a purchase whose sale has not happened yet, still waiting
        # for its own mail, is matched by that mail — not booked a second time.
        run(MAIL + '''F.Trade.awaitBuyerInvoice('Linen Bag', 1)
        F.Data.addPosition(c,'i:30','Linen Bag',1,20000,'flip',29900,now-3600)
        F.Data.log(c,{at=now-3600,kind='buy',key='i:30',name='Linen Bag',qty=1,amount=20000,mode='flip'})
        local n = #c.journal
        F.Trade.onBuyerInvoice({item='Linen Bag',count=1,bid=20000}, link(30,'Linen Bag'))
        assert(#c.journal == n, 'its own mail books nothing: the purchase already was')
        assert(c.positions['i:30'].qty == 1, 'stock unchanged')''')


if __name__ == '__main__':
    unittest.main()
