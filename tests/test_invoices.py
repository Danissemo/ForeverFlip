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

    def test_each_mail_is_booked_once(self):
        run(MAIL + '''inbox={{subject='Auction expired: Linen Bag (5)',items=1}}
        fire('MAIL_SHOW');fire('MAIL_INBOX_UPDATE');F.Mail.record(1);F.Mail.record(1)
        assert(c.rates['linen bag'].failed==5)''')

    def test_neutral_cut_is_learned_from_an_invoice(self):
        run(MAIL + '''inbox={{subject='Auction successful: X',money=8500,invoice={kind='seller',item='X',bid=10000,cut=1500,count=1}}}
        fire('MAIL_SHOW');F.Mail.record(1)
        assert(math.abs(F.db.cuts['Realm-Neutral']-0.15)<1e-9 and not F.db.cuts['Realm-Alliance'])''')


if __name__ == '__main__':
    unittest.main()
