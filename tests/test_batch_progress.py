import unittest

from test_addon import run


BATCH = '''
local F=ForeverFlip
local D,T,UI=F.Deals,F.Trade,F.UI
F.db.settings.autoVerify=false;F.db.settings.autoScan=false;F.db.settings.sniper=false
owned={}
for id=10,29 do
    addItem(id,'Owned item '..id,100,'commodity');addAuction(id,200,1)
    owned[#owned+1]={auctionID=id,itemKey={itemID=id},quantity=1,buyoutAmount=300,status=0}
end
fire('OWNED_AUCTIONS_UPDATED');UI.show('auctions')
UI.checkOwned:Click();run(1.2);UI.refreshAuctions()
'''


class BatchProgressTests(unittest.TestCase):
    def test_owned_progress_counts_accepted_queue_and_active_request_until_completion(self):
        run(BATCH + '''
        assert(#T.checkQueue==0 and D.search and #D.requests==19)
        for remaining=20,1,-1 do
            UI.refreshAuctions()
            UI.refreshStatus()
            assert(UI.status:GetText():find('Checking prices of your auctions: '..(20-remaining)..'/20',1,true),UI.status:GetText())
            assert(not UI.auctionText:GetText():find('Checking prices:'), 'progress belongs in the status bar')
            assert(not UI.checkOwned:IsEnabled(),'batch cannot restart while accepted requests remain')
            local waiting=#D.requests
            UI.checkOwned:Click();assert(#D.requests==waiting)
            answer();if remaining>1 then run(1.1) end
        end
        UI.refreshAuctions()
        assert(UI.checkOwned:IsEnabled() and not UI.auctionText:GetText():find('Checking prices:'))
        ''')

    def test_closing_house_clears_batch_progress_before_a_new_batch(self):
        run(BATCH + '''
        fire('AUCTION_HOUSE_CLOSED');UI.refreshAuctions()
        assert(UI.checkOwned:IsEnabled() and not UI.auctionText:GetText():find('Checking prices:'))
        assert(not D.search and #D.requests==0)
        fire('AUCTION_HOUSE_SHOW');UI.show('auctions');UI.checkOwned:Click();run(0.1);UI.refreshAuctions()
        UI.refreshStatus()
        assert(not UI.checkOwned:IsEnabled() and UI.status:GetText():find('Checking prices of your auctions: 0/20',1,true),UI.status:GetText())
        ''')


if __name__ == '__main__':
    unittest.main()
