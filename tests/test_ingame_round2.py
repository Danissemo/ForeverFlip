"""Fixes from in-game checks: own auctions without competitors, sniper summary, Buy tab marks."""

import unittest

from test_addon import SETUP, run

OWN = SETUP + '''local F=ForeverFlip
local T,UI=F.Trade,F.UI
-- a recipe only the player sells: the scan sees one unit and does not name sellers
addItem(70,'Recipe: Crispy Bat Wing',25,'item')
for i=#auctions,1,-1 do if auctions[i].owner=='Me' then table.remove(auctions,i) end end
addAuction(70,108000,1,'Unknown')
fullScan()
owned={{auctionID=9,itemKey={itemID=70},quantity=1,buyoutAmount=108000,status=0,timeLeftSeconds=7200}}
fire('OWNED_AUCTIONS_UPDATED')
'''


class OwnAuctionTests(unittest.TestCase):
    def test_item_only_the_player_sells_is_alone_without_a_search(self):
        run(OWN + '''assert(not F.Scan.last.ownersKnown)
        assert(T.ownedStatus(T.owned[1])=='alone')
        assert(T.checkOwned()==0,'no search for an item nobody else sells')''')

    def test_scan_naming_owners_counts_other_units(self):
        run(SETUP + '''local F=ForeverFlip;local T=F.Trade;fullScan();assert(F.Scan.last.ownersKnown)
        owned={{auctionID=6,itemKey={itemID=30},quantity=1,buyoutAmount=25000,status=0}}
        fire('OWNED_AUCTIONS_UPDATED');assert(T.ownedStatus(T.owned[1])==nil,'another seller lists it')''')

    def test_no_answer_is_shown(self):
        run(SETUP + '''local F=ForeverFlip;local T=F.Trade;fullScan()
        owned={{auctionID=6,itemKey={itemID=30},quantity=1,buyoutAmount=25000,status=0}}
        fire('OWNED_AUCTIONS_UPDATED');T.checkOwned();run(0.1);assert(F.Deals.search);run(11)
        assert(T.ownedStatus(T.owned[1])=='no_answer')''')

    def test_page_shows_only_yours(self):
        run(OWN + '''UI.show('auctions');UI.refresh()
        assert(UI.auctionTable.rows[1].cols[4]:GetText():find('only yours',1,true))''')


class SummaryTests(unittest.TestCase):
    def test_sniper_figures_are_in_the_summary(self):
        run(SETUP + '''local F=ForeverFlip;enableBrowse();fullScan();F.db.settings.sniper=true
        F.Sniper.rounds,F.Sniper.items=3,900;F.UI.refresh()
        local s=F.UI.summary:GetText();assert(s:find('Sniper: 3 rounds',1,true) and s:find('Prices read: 900',1,true),s)
        assert(not F.UI.status:GetText():find('sniper',1,true),F.UI.status:GetText())''')


class MarkTests(unittest.TestCase):
    def test_marks_in_the_auction_list_of_an_item(self):
        run(SETUP + '''local F=ForeverFlip;fullScan()
        local function row(data) local r=CreateFrame('Button');r.rowData=data;return r end
        local cheap=row({itemID=10,unitPrice=60,quantity=5,numOwnerItems=0})
        local dear=row({itemID=10,unitPrice=150,quantity=5,numOwnerItems=0})
        local list={ScrollBox={ForEachFrame=function(_,fn) fn(cheap);fn(dear) end}}
        AuctionHouseFrame.CommoditiesBuyFrame=CreateFrame('Frame');AuctionHouseFrame.CommoditiesBuyFrame.ItemList=list
        run(0.6)
        assert(rawget(cheap,'ffMark') and cheap.ffMark:IsShown(),'60c is below the 100c vendor price')
        assert(rawget(dear,'ffMark') and not dear.ffMark:IsShown())''')


if __name__ == '__main__':
    unittest.main()
