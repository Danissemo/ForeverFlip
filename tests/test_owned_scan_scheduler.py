"""Own-auction checks must keep moving beside paused work from other pages."""
import unittest

from test_addon import SETUP, run

BASE = SETUP + '''local F=ForeverFlip;local D,T=F.Deals,F.Trade
F.db.settings.autoScan=false;F.db.settings.sniper=false;F.Engine.autoVerify=false
'''


class OwnedScanSchedulerTests(unittest.TestCase):
    def test_owned_check_promotes_a_shared_key_from_a_paused_batch(self):
        run(BASE + '''throttleReady=false
        D.startBatch('deals:all',{'c:10','i:30'},false)
        F.UI.show('auctions')
        owned={{auctionID=1,itemKey={itemID=10},quantity=1,buyoutAmount=150,status=0}}
        fire('OWNED_AUCTIONS_UPDATED');assert(T.checkOwned()==1)
        run(0.1);throttleReady=true;run(0.3)
        assert(D.search and D.search.key=='c:10','owned checks may share a paused batch key')
        answer();assert(T.checksRemaining()==0 and D.queued['i:30'])
        ''')

    def test_paused_gear_between_versions_does_not_block_owned_checks(self):
        run(BASE + '''enableBrowse();addItem(40,'Wool Cloth',300,'commodity');addAuction(40,200,1)
        local key='g:20:northern shortsword of healing'
        D.startBatch('deals:all',{key},false)
        browseAnswer();assert(D.search and D.search.waitKey)
        F.UI.show('auctions')
        owned={{auctionID=1,itemKey={itemID=40},quantity=1,buyoutAmount=400,status=0}}
        fire('OWNED_AUCTIONS_UPDATED');assert(T.checkOwned()==1)
        run(0.4)
        assert(D.search and D.search.key=='c:40','a paused gear continuation must release the connection')
        answer();assert(T.checksRemaining()==0)
        assert(D.queued[key] and D.queued[key].waitKey,'the gear continuation remains intact')
        ''')

    def test_paused_deal_batch_does_not_block_owned_checks(self):
        run(BASE + '''addItem(40,'Wool Cloth',300,'commodity');addAuction(40,200,1)
        throttleReady=false
        D.startBatch('deals:all',{'c:10','i:30'},false)
        F.UI.show('auctions')
        owned={{auctionID=1,itemKey={itemID=40},quantity=1,buyoutAmount=400,status=0}}
        fire('OWNED_AUCTIONS_UPDATED');assert(T.checkOwned()==1)
        run(0.1);assert(D.queued['c:40'])
        throttleReady=true;run(0.3)
        assert(D.search and D.search.key=='c:40','own auctions must run while another page batch is paused')
        answer();assert(T.checksRemaining()==0)
        assert(D.queued['c:10'] and D.queued['i:30'],'the other page keeps its paused work')
        F.UI.show('deals');run(0.3)
        assert(D.search and D.search.key=='c:10','the paused batch resumes in its original order')
        ''')


if __name__ == '__main__':
    unittest.main()


