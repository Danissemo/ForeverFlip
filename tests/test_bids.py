"""Bid candidates from the full scan, the exact check, placing a bid and booking a won auction."""

import unittest

from test_addon import SETUP, run

BIDS = SETUP + '''enableTimeLeft()
local F=ForeverFlip
local B=F.Bids
-- a Linen Bag (vendor 20s) with a 5s bid, ending within 30 minutes, no buyout
local a=addAuction(30,0,1);a.buyout=0;a.minBid=500;a.timeLeft=1
fullScan()
'''


class BidTests(unittest.TestCase):
    def test_scan_finds_a_bid_ending_soon(self):
        run(BIDS + '''local c=B.get('i:30');assert(c and c.bid==500 and c.value==2000 and c.profit==1500,c and c.profit)''')

    def test_long_auction_is_not_a_candidate(self):
        run(SETUP + '''enableTimeLeft();local a=addAuction(30,0,1);a.buyout=0;a.minBid=500;a.timeLeft=3
        fullScan();assert(not ForeverFlip.Bids.get('i:30'))''')

    def test_check_then_place_the_bid(self):
        run(BIDS + '''assert(B.place('i:30')==false)
        B.check('i:30');run(0.1);answer()
        local o=B.offer('i:30');assert(o and o.auctionID==a.id and o.bid==500)
        assert(B.place('i:30'));local call=lastCall('PlaceBid');assert(call[2]==a.id and call[3]==500)
        assert(#B.open()==1)''')

    def test_won_auction_becomes_stock(self):
        run(BIDS + '''B.check('i:30');run(0.1);answer();B.place('i:30')
        fire('CHAT_MSG_SYSTEM','You won an auction for Linen Bag')
        local c=F.Data.char(F.db,F.Engine.owner())
        assert(c.positions['i:30'] and c.positions['i:30'].mode=='vendor' and #B.open()==0)''')

    def test_outbid_mail_closes_the_bid(self):
        run(BIDS + '''AUCTION_OUTBID_MAIL_SUBJECT='Outbid on %s'
        B.check('i:30');run(0.1);answer();B.place('i:30')
        inbox={{subject='Outbid on Linen Bag',money=500}};fire('MAIL_SHOW');F.Mail.record(1)
        assert(#B.open()==0 and not F.Data.char(F.db,F.Engine.owner()).positions['i:30'])''')

    def test_bids_page_lists_the_candidate(self):
        run(BIDS + '''local UI=F.UI;UI.show('bids');assert(UI.bidTable.rows[1].key=='i:30')
        UI.bidTable.rows[1]:Click();run(0.1);answer();UI.refresh();assert(UI.bidButton:IsEnabled())''')


if __name__ == '__main__':
    unittest.main()
