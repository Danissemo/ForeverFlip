"""Recipe key resolution and page events must not stall unrelated price checks."""

import unittest

from test_addon import SETUP, run


BASE = SETUP + '''local F=ForeverFlip;local D,T=F.Deals,F.Trade
F.db.settings.autoScan=false;F.db.settings.sniper=false;F.db.settings.autoVerify=false
'''


class SearchStallTests(unittest.TestCase):
    def test_owned_gear_key_does_not_replace_discovery_of_other_versions(self):
        run(BASE + '''enableBrowse()
        owned={{auctionID=70,itemKey={itemID=20,itemLevel=1,itemSuffix=0},
            itemLink=link(20,'Northern Shortsword of Healing'),quantity=1,buyoutAmount=9800,status=0}}
        fire('OWNED_AUCTIONS_UPDATED')
        T.checkPrice('g:20:northern shortsword of healing')
        assert(D.search.phase=='browse','one owned gear key does not reveal every version of the ending')
        ''')

    def test_intentional_pause_between_versions_does_not_use_reply_budget(self):
        run(BASE + '''enableBrowse();local completed=0
        F.AH.gearKeys=function() return {{itemID=20,itemLevel=1}} end
        F.AH.rows=function() return {{unit=500,qty=1}},true end
        D.enqueue('g:20:northern shortsword of healing',function(_,rows,full) assert(full);completed=completed+1 end,'paused',true)
        D.onBrowse();assert(D.search.waitKey)
        F.AH.nativeShown=function() return true end
        run(120);assert(D.search and completed==0,'native UI pause is not a network failure')
        F.AH.nativeShown=function() return false end
        run(0.3);fire('ITEM_SEARCH_RESULTS_UPDATED',{itemID=20,itemLevel=1})
        assert(completed==1 and not D.search)
        ''')

    def test_late_browse_after_timeout_cannot_prove_next_item_is_absent(self):
        run(BASE + '''enableBrowse();local answered,complete
        D.byName[30]=true
        D.enqueue('g:20:northern shortsword of healing',function() end,'first',true)
        D.enqueue('i:30',function(_,rows,full) answered,complete=rows,full end,'next',true)
        run(12);assert(D.search and D.search.key=='i:30')
        F.AH.gearKeys=function() return {} end;F.AH.browseFull=function() return true end
        D.onBrowse()
        assert(answered==nil and complete==false,'a late reply from the timed-out browse is not proof of no sellers')
        ''')

    def test_slow_versions_cannot_hold_every_other_item_for_minutes(self):
        run(BASE + '''enableBrowse();local complete;local finished=0
        local key='g:20:northern shortsword of healing'
        F.AH.gearKeys=function() local keys={} for i=1,60 do keys[i]={itemID=20,itemLevel=i} end return keys end
        F.AH.rows=function() return {{unit=500,qty=1}},true end
        D.enqueue(key,function(_,rows,full) finished=finished+1;complete=full end,'slow',true)
        T.checkPrice('c:10',function() end,true);D.onBrowse()
        local started=now
        for i=1,5 do
            if not D.search or D.search.key~=key then break end
            run(0.3);run(9)
            if D.search and D.search.key==key then fire('ITEM_SEARCH_RESULTS_UPDATED',D.search.keys[D.search.keyIndex]) end
        end
        assert(finished==1 and not complete,'bounded total wait returns an unknown result, never a verified deal')
        assert(now-started<50 and D.search and D.search.key=='c:10','unrelated checks get the connection back')
        ''')

    def test_timed_out_cached_key_is_forgotten_before_a_later_retry(self):
        run(BASE + '''enableBrowse();F.db.itemKeys={[30]={at=now,list={{l=5,s=0}}}}
        D.byName[30]=true
        T.checkPrice('i:30',function() end,true);run(0.3);run(11)
        assert(not F.AH.cachedKeys(F.Util.parseKey('i:30')),'a silent stale key must not be reused forever')
        ''')

    def test_owned_recipe_uses_its_real_key_without_plain_search_timeout(self):
        run(BASE + '''enableBrowse()
        addItem(12226,'Recipe: Crispy Bat Wing',10,'item');addAuction(12226,9799,1)
        local info=C_AuctionHouse.GetItemKeyInfo
        C_AuctionHouse.GetItemKeyInfo=function(key)
            if key.itemID==12226 and key.itemLevel~=1 then return nil end
            return info(key)
        end
        owned={{auctionID=70,itemKey={itemID=12226,itemLevel=1,itemSuffix=0},quantity=1,buyoutAmount=9800,status=0}}
        fire('OWNED_AUCTIONS_UPDATED')
        assert(T.owned[1].key=='i:12226','the exact key also supplies classification when the zero key is unknown')
        local sent={};C_AuctionHouse.SendSearchQuery=function(key) sent[#sent+1]=key end
        T.checkPrice('i:12226')
        assert(#sent==1 and sent[1].itemLevel==1,'use the exact owned recipe key immediately')
        fire('ITEM_SEARCH_RESULTS_UPDATED',{itemID=12226,itemLevel=1,itemSuffix=0})
        assert(T.prices['i:12226'] and T.prices['i:12226'].rows[1].unit==9799)
        assert(not D.pending('i:12226'))
        ''')

    def test_recipe_browse_key_is_reused_for_the_next_check(self):
        run(BASE + '''enableBrowse();addItem(12226,'Recipe: Crispy Bat Wing',10,'item')
        C_AuctionHouse.GetBrowseResults=function() return {{itemKey={itemID=12226,itemLevel=1,itemSuffix=0}}} end
        F.AH.learnKeys()
        local sent;C_AuctionHouse.SendSearchQuery=function(key) sent=key end
        T.checkPrice('i:12226')
        assert(sent and sent.itemLevel==1,'ordinary item keys learned from browsing are reusable')
        ''')

    def test_item_added_page_completes_price_check_and_releases_next_item(self):
        run(BASE + '''local full=false;local completed=0;local more=0
        C_AuctionHouse.RequestMoreItemSearchResults=function() more=more+1 end
        F.AH.rows=function(item) return {{unit=300,qty=1,auctionID=1}},full end
        T.checkPrice('i:30',function() completed=completed+1 end,true)
        T.checkPrice('c:10',function() end,true)
        fire('ITEM_SEARCH_RESULTS_UPDATED',{itemID=30})
        assert(more==1 and completed==0)
        full=true;fire('ITEM_SEARCH_RESULTS_ADDED',{itemID=30})
        assert(completed==1,'ADDED is the reply to RequestMoreItemSearchResults')
        run(0.3);assert(D.search and D.search.key=='c:10','the next item is not held for ten seconds')
        ''')

    def test_commodity_added_page_completes_price_check(self):
        run(BASE + '''local full=false;local completed=0
        C_AuctionHouse.RequestMoreCommoditySearchResults=function() end
        F.AH.rows=function() return {{unit=300,qty=1}},full end
        T.checkPrice('c:10',function() completed=completed+1 end,true)
        fire('COMMODITY_SEARCH_RESULTS_UPDATED',10)
        full=true;fire('COMMODITY_SEARCH_RESULTS_ADDED',10)
        assert(completed==1 and not D.search,'commodity page additions complete the request')
        ''')


if __name__ == '__main__':
    unittest.main()
