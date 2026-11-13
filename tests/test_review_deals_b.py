"""Review fixes in Deals.lua, AH.lua and Core.lua (second pass): result pages told apart by the
results the answer holds, and a new browse list learned from its first row."""
import unittest

from test_addon import SETUP, run

# Searches answered in pages of two results: `shown` of them have arrived, `asked` counts the next
# pages requested. No deal is listed, so only a complete answer ends a search before three pages.
PAGES = SETUP + '''local F = ForeverFlip
local D, T, U = F.Deals, F.Trade, F.Util
fullScan()
T.ownedDue = now + 1000 -- no own-auction refresh in between
D.list = {}
local AH = C_AuctionHouse
local results, shown, asked, got = {}, 0, 0, nil
local function done(_, rows, complete) got = { rows = rows and #rows, complete = complete } end
'''

ITEM = PAGES + '''local function lot(price, id, extra)
    local r = { itemKey = { itemID = 30 }, itemLink = link(30), quantity = 1, buyoutAmount = price, auctionID = id }
    for k, v in pairs(extra or {}) do r[k] = v end
    results[#results + 1] = r
end
local num, info, full = AH.GetNumItemSearchResults, AH.GetItemSearchResultInfo, AH.HasFullItemSearchResults
AH.GetNumItemSearchResults = function(key) if key.itemID == 30 then return shown end return num(key) end
AH.GetItemSearchResultInfo = function(key, i) if key.itemID == 30 then return results[i] end return info(key, i) end
AH.HasFullItemSearchResults = function(key) if key.itemID == 30 then return shown >= #results end return full(key) end
AH.RequestMoreItemSearchResults = function() asked = asked + 1 end
'''

COMMODITY = PAGES + '''local function lot(price, id, own)
    results[#results + 1] =
        { itemID = 10, unitPrice = price, quantity = 5, numOwnerItems = own and 5 or 0, auctionID = id }
end
local num, info = AH.GetNumCommoditySearchResults, AH.GetCommoditySearchResultInfo
local full = AH.HasFullCommoditySearchResults
AH.GetNumCommoditySearchResults = function(id) if id == 10 then return shown end return num(id) end
AH.GetCommoditySearchResultInfo = function(id, i) if id == 10 then return results[i] end return info(id, i) end
AH.HasFullCommoditySearchResults = function(id) if id == 10 then return shown >= #results end return full(id) end
AH.RequestMoreCommoditySearchResults = function() asked = asked + 1 end
'''

GEAR = PAGES + '''local key = U.key('gear', 20, 'Northern Shortsword of Nature Protection')
local version = { itemID = 20, itemLevel = 18, itemSuffix = 14320, battlePetSpeciesID = 0 }
F.db.itemKeys = { [20] = { at = F.Engine.clock(), list = { { l = 18, s = 14320 } } } } -- its ending not known yet
local function lot(price, id, name)
    results[#results + 1] =
        { itemKey = version, itemLink = link(20, name), quantity = 1, buyoutAmount = price, auctionID = id }
end
local num, info, full = AH.GetNumItemSearchResults, AH.GetItemSearchResultInfo, AH.HasFullItemSearchResults
AH.GetNumItemSearchResults = function(k) if k.itemID == 20 then return shown end return num(k) end
AH.GetItemSearchResultInfo = function(k, i) if k.itemID == 20 then return results[i] end return info(k, i) end
AH.HasFullItemSearchResults = function(k) if k.itemID == 20 then return shown >= #results end return full(k) end
AH.RequestMoreItemSearchResults = function() asked = asked + 1 end
'''


class PageTests(unittest.TestCase):
    """V19-d: a next page whose results are all left out (own lots, bids, other endings) is a page."""

    def test_a_page_of_only_own_lots_and_bids_is_a_page(self):
        run(ITEM + '''lot(20001, 101); lot(20002, 102)
        lot(21001, 201, { containsOwnerItem = true }); lot(21002, 202, { buyoutAmount = 0, minBid = 21002 })
        lot(22001, 301); lot(22002, 302)
        T.checkPrice('i:30', done)
        assert(D.search and D.search.key == 'i:30' and not D.search.phase)
        shown = 2; fire('ITEM_SEARCH_RESULTS_UPDATED', { itemID = 30 })
        assert(asked == 1, 'page 2 asked')
        fire('ITEM_SEARCH_RESULTS_UPDATED', { itemID = 30 })
        assert(asked == 1 and not got, 'the same results again are no page')
        shown = 4; fire('ITEM_SEARCH_RESULTS_ADDED', { itemID = 30 })
        assert(asked == 2, 'page 2 came, of the player\\'s lot and a bid only: page 3 asked, not the timeout')
        shown = 6; fire('ITEM_SEARCH_RESULTS_ADDED', { itemID = 30 })
        assert(got and got.rows == 4 and got.complete and not D.search, 'answered complete at once')
        assert(not D.byName[30], 'no search by name for an item that answered')''')

    def test_a_commodity_page_of_only_own_units_is_a_page(self):
        run(COMMODITY + '''lot(60, 1); lot(61, 2); lot(62, 3, true); lot(63, 4, true); lot(64, 5); lot(65, 6)
        T.checkPrice('c:10', done)
        assert(D.search and D.search.key == 'c:10')
        shown = 2; fire('COMMODITY_SEARCH_RESULTS_UPDATED', 10)
        assert(asked == 1, 'page 2 asked')
        shown = 4; fire('COMMODITY_SEARCH_RESULTS_ADDED', 10)
        assert(asked == 2, 'a page of the player\\'s own units: page 3 asked')
        shown = 6; fire('COMMODITY_SEARCH_RESULTS_ADDED', 10)
        assert(got and got.rows == 4 and got.complete and not D.search)''')

    def test_a_gear_version_page_of_another_ending_is_a_page(self):
        run(GEAR + '''local NP, HE = 'Northern Shortsword of Nature Protection', 'Northern Shortsword of Healing'
        lot(801, 101, NP); lot(802, 102, NP)
        lot(901, 201, HE); lot(902, 202, HE) -- page 2: another ending only
        lot(1001, 301, NP); lot(1002, 302, NP)
        T.checkPrice(key, done)
        assert(D.search and D.search.phase == 'keys' and not D.search.waitKey, 'the cached version is searched')
        shown = 2; fire('ITEM_SEARCH_RESULTS_UPDATED', version)
        assert(asked == 1, 'page 2 of the version asked')
        shown = 4; fire('ITEM_SEARCH_RESULTS_ADDED', version)
        assert(asked == 2, 'a page of another ending only: page 3 asked')
        shown = 6; fire('ITEM_SEARCH_RESULTS_ADDED', version)
        assert(got and got.rows == 4 and got.complete and not D.search, 'answered complete at once')
        assert(F.db.itemKeys[20], 'the version is kept: it answered')''')


class BrowseLearnTests(unittest.TestCase):
    """The Core part of V20-f: AUCTION_HOUSE_BROWSE_RESULTS_UPDATED is a new list for AH.learnKeys."""

    def test_a_new_browse_list_is_learned_from_its_first_row(self):
        run(SETUP + '''local F = ForeverFlip
        local list = {}
        local function fill(first)
            list = {}
            for i = 1, 3 do list[i] = { itemKey = { itemID = first + i, itemLevel = 0, itemSuffix = 0 } } end
        end
        C_AuctionHouse.GetBrowseResults = function() return list end
        fill(1000); fire('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
        assert(F.db.itemKeys[1001] and F.db.itemKeys[1003])
        -- A list as long as the last one, of a browse no hook told about (the tests have no hooks).
        fill(2000); fire('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
        assert(F.db.itemKeys[2001] and F.db.itemKeys[2003], 'a new list is read from its first row')''')


if __name__ == '__main__':
    unittest.main()
