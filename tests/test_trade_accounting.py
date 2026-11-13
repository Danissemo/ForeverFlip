"""Regression cases for purchase, invoice and merchant event accounting."""

import unittest

from test_addon import SETUP, run

BASE = SETUP + '''local F=ForeverFlip;local T=F.Trade;local c=F.Data.char(F.db,F.Engine.owner())\n'''


class AccountingTests(unittest.TestCase):
    def check(self, code):
        run(BASE + code)

    def test_bid_chat_invoice_once(self):
        self.check(
            '''
            c.bids={[7]={key='i:30',name='Linen Bag',qty=1,amount=500,value=2000,at=now}}
            assert(F.Bids.won('Linen Bag'));T.onBuyerInvoice({item='Linen Bag',count=1,bid=500},link(30,'Linen Bag'))
            assert(c.positions['i:30'].qty==1 and c.stats['i:30'].spent==500)
            '''
        )

    def test_bid_invoice_does_not_suppress_future_purchase(self):
        self.check(
            '''
            c.bids={[7]={key='i:30',name='Linen Bag',qty=1,amount=500,value=2000,at=now}}
            T.onBuyerInvoice({item='Linen Bag',count=1,bid=500},link(30,'Linen Bag'))
            T.onBuyerInvoice({item='Linen Bag',count=1,bid=600},link(30,'Linen Bag'))
            assert(c.positions['i:30'].qty==2 and c.stats['i:30'].spent==1100)
            '''
        )

    def test_bid_invoice_matches_chat_win_before_other_open_bid(self):
        self.check(
            '''
            c.bids={[7]={key='i:30',name='Linen Bag',qty=1,amount=500,value=2000,at=now}}
            assert(F.Bids.won('Linen Bag'));c.bids[8]={key='i:30',name='Linen Bag',qty=1,amount=600,value=2000,at=now}
            T.onBuyerInvoice({item='Linen Bag',count=1,bid=500},link(30,'Linen Bag'))
            assert(c.bids[8] and c.positions['i:30'].qty==1)
            '''
        )

    def test_gear_bid_exact_name(self):
        self.check(
            '''
            local key='g:20:northern shortsword of healing'
            F.Bids.candidates={{key=key,id=20,kind='gear',value=1070,count=1}}
            F.Bids.offers[key]={auctionID=77,bid=100,qty=1,at=now}
            assert(F.Bids.place(key));assert(F.Bids.won('Northern Shortsword of Healing'))
            '''
        )

    def test_settle_invoice_once_and_spend(self):
        self.check(
            '''
            c.unknown={{at=now,key='i:30',name='Linen Bag',qty=1,cost=500,mode='flip'}}
            T.settle(1,true);T.onBuyerInvoice({item='Linen Bag',count=1,bid=500},link(30,'Linen Bag'))
            assert(c.positions['i:30'].qty==1 and F.Engine.spent==500)
            '''
        )

    def test_owned_uses_exact_total(self):
        self.check(
            '''
            F.Data.addPosition(c,'c:10','Linen Cloth',3,30,'flip',nil,now)
            c.listings={{key='c:10',name='Linen Cloth',qty=3,price=34,at=now,ids={7},open=3}}
            owned={{auctionID=7,itemKey={itemID=10},quantity=3,buyoutAmount=101,status=1}}
            fire('OWNED_AUCTIONS_UPDATED');assert(c.stats['c:10'].earned==F.Market.net(101,1))
            '''
        )

    def test_invoice_consumes_multiple_listings(self):
        self.check(
            '''
            F.Data.addPosition(c,'i:30','Linen Bag',3,1500,'flip',nil,now)
            c.listings={{key='i:30',name='Linen Bag',open=1},{key='i:30',name='Linen Bag',open=2}}
            T.onInvoice({item='Linen Bag',count=3,bid=9000,cut=450})
            assert(not c.positions['i:30'] and c.stats['i:30'].sold==3 and c.stats['i:30'].earned==8550)
            '''
        )

    def test_closed_listing_allows_external_sale(self):
        self.check(
            '''
            F.Data.addPosition(c,'i:30','Linen Bag',2,1000,'flip',nil,now)
            c.listings={{key='i:30',name='Linen Bag',open=0}}
            T.onInvoice({item='Linen Bag',count=1,bid=3000,cut=150})
            assert(c.positions['i:30'].qty==1 and c.stats['i:30'].sold==1)
            '''
        )

    def test_mail_snapshot_keeps_recorded(self):
        self.check(
            '''
            inbox={{subject='Auction expired: Linen Bag',items=1}}
            fire('MAIL_SHOW');F.Mail.record(1);fire('MAIL_INBOX_UPDATE');F.Mail.record(1)
            assert(c.rates['linen bag'].failed==1)
            '''
        )

    def test_identical_mail_after_removal_is_new(self):
        self.check(
            '''
            inbox={{subject='Auction expired: Linen Bag',items=1},{subject='Auction expired: Linen Bag',items=1}}
            fire('MAIL_SHOW');F.Mail.record(1);table.remove(inbox,1);fire('MAIL_INBOX_UPDATE');F.Mail.record(1)
            assert(c.rates['linen bag'].failed==2)
            '''
        )

    def test_vendor_buyback_before_frame(self):
        self.check(
            '''
            F.Data.addPosition(c,'i:30','Linen Bag',2,1000,'vendor',nil,now)
            putBag(0,1,30,1,'Linen Bag');MerchantFrame:Show()
            local bb={};GetNumBuybackItems=function()return #bb end;GetBuybackItemLink=function(i)return bb[i].link end
            GetBuybackItemInfo=function(i)return 'Linen Bag',nil,bb[i].price,bb[i].qty end;F.Merchant.watchBuyback(true)
            C_Container.UseContainerItem=function(bag,slot)local v=bags[bag][slot];bags[bag][slot]=nil;bb[#bb+1]={link=v.hyperlink,price=2000,qty=1} end
            T.sellAllToVendor();fire('MERCHANT_UPDATE');T.stepVendor()
            assert(c.positions['i:30'].qty==1 and c.stats['i:30'].sold==1 and c.stats['i:30'].earned==2000)
            '''
        )

    def test_vendor_refusal_clears_suppression(self):
        self.check(
            '''
            F.Data.addPosition(c,'i:30','Linen Bag',2,1000,'vendor',nil,now)
            putBag(0,1,30,1,'Linen Bag');MerchantFrame:Show();C_Container.UseContainerItem=function()end
            T.sellAllToVendor();for i=1,4 do now=now+3;T.stepVendor() end
            assert(not T.vendorJob and (F.Merchant.expected[30] or 0)==0 and c.positions['i:30'].qty==2)
            '''
        )

    def test_vendor_frame_before_buyback(self):
        self.check(
            '''
            F.Data.addPosition(c,'i:30','Linen Bag',2,1000,'vendor',nil,now)
            putBag(0,1,30,1,'Linen Bag');MerchantFrame:Show()
            local bb={};GetNumBuybackItems=function()return #bb end;GetBuybackItemLink=function(i)return bb[i].link end
            GetBuybackItemInfo=function(i)return 'Linen Bag',nil,bb[i].price,bb[i].qty end;F.Merchant.watchBuyback(true)
            C_Container.UseContainerItem=function(bag,slot)local v=bags[bag][slot];bags[bag][slot]=nil;bb[#bb+1]={link=v.hyperlink,price=2000,qty=1} end
            T.sellAllToVendor();T.stepVendor();fire('MERCHANT_UPDATE')
            assert(c.positions['i:30'].qty==1 and c.stats['i:30'].sold==1 and (F.Merchant.expected[30] or 0)==0)
            '''
        )

    def test_vendor_close_clears_unsold_expectation(self):
        self.check(
            '''
            F.Data.addPosition(c,'i:30','Linen Bag',2,1000,'vendor',nil,now)
            putBag(0,1,30,1,'Linen Bag');MerchantFrame:Show();C_Container.UseContainerItem=function()end
            T.sellAllToVendor();MerchantFrame:Hide();T.stepVendor()
            assert(not T.vendorJob and (F.Merchant.expected[30] or 0)==0 and c.positions['i:30'].qty==2)
            '''
        )

    def test_full_identical_buyback_uses_bags_and_money(self):
        self.check('''F.Data.addPosition(c,'i:30','Linen Bag',3,1500,'vendor',nil,now)
        putBag(0,1,30,3,'Linen Bag');MerchantFrame:Show()
        GetNumBuybackItems=function() return 12 end
        GetBuybackItemLink=function() return link(30,'Linen Bag') end
        GetBuybackItemInfo=function() return 'Linen Bag',nil,2000,1 end
        local cash=10000;GetMoney=function() return cash end
        F.Merchant.watchBuyback(true)
        putBag(0,1,30,1,'Linen Bag');cash=cash+4000
        F.Merchant.watchBuyback(false)
        assert(c.stats['i:30'].sold==2 and c.stats['i:30'].earned==4000,'two invisible buyback entries')
        F.Merchant.watchBuyback(false);assert(c.stats['i:30'].sold==2,'only once')''')

    def test_missing_bags_without_payment_are_not_vendor_sales(self):
        self.check('''F.Data.addPosition(c,'i:30','Linen Bag',1,500,'vendor',nil,now)
        putBag(0,1,30,1,'Linen Bag');MerchantFrame:Show()
        GetNumBuybackItems=function() return 12 end
        GetBuybackItemLink=function() return link(30,'Linen Bag') end
        GetBuybackItemInfo=function() return 'Linen Bag',nil,2000,1 end
        F.Merchant.watchBuyback(true);bags[0][1]=nil;F.Merchant.watchBuyback(false)
        assert(c.positions['i:30'].qty==1,'moving stock is not selling it')''')


if __name__ == '__main__':
    unittest.main()
