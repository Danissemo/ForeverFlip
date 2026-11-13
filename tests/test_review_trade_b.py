"""Review fixes in Trade.lua: merchant sales, anti-undercut marks, posting quantities and own auctions."""

import unittest

import test_audit
from test_addon import SETUP, run
from test_selling_rules import SELL

BASE = SETUP + '''local F = ForeverFlip
local T, D, UI = F.Trade, F.Deals, F.UI
local c = F.Data.char(F.db, F.Engine.owner())
c.recount, c.returnsMarked = T.RECOUNT, true -- no journal recount in these synthetic states
local function market(key, price)
    F.Data.market(F.db, F.Engine.scope()).history[key] = { scan = { at = now, market = price } }
end
'''

# A stack sent to the merchant whose answer is slow: it stays in its slot until the test empties it.
SLOW = BASE + '''addItem(71, 'Murloc Fin', 28, 'commodity'); putBag(0, 1, 71, 1)
F.Data.addPosition(c, 'c:71', 'Murloc Fin', 1, 10, 'vendor', 28, now)
local sent = 0
C_Container.UseContainerItem = function() sent = sent + 1 end
T.VENDOR_WAIT = 0.1 -- a try counts as unanswered before the next batch may go (T.VENDOR_GAP)
MerchantFrame:Show(); fire('MERCHANT_SHOW')
T.sellAllToVendor(); assert(sent == 1)
now = now + 0.15; T.stepVendor()
assert(#T.vendorJob.queue == 1, 'queued to be sent again')
bags[0][1] = nil -- the answer to the first try comes now
'''

# Gear a druid cannot use (test_audit.GearSellTests), and twenty more axes.
GEAR = test_audit.GearSellTests.GEAR + '''local instant = C_Item.GetItemInfoInstant
C_Item.GetItemInfoInstant = function(id)
    if id > 100 then return id, '', '', 'INVTYPE_2HWEAPON', 0, 2, 1 end
    return instant(id)
end
for i = 1, 20 do
    addItem(100 + i, 'Axe ' .. i, 500, 'gear'); putBag(1 + math.floor((i - 1) / 16), (i - 1) % 16 + 1, 100 + i, 1)
end
'''

POST = SELL + '''F.db.settings.maxPricePercent = 0
T.prices['c:10'] = { at = now, rows = { { unit = 150, qty = 100 } } }
'''


class VendorStockTests(unittest.TestCase):
    """V4-a, V4-c: vendor-deal stock is only the units bought, also in a stack of looted ones."""

    def test_only_the_stacks_holding_the_bought_units_go_to_the_merchant(self):
        run(BASE + '''addItem(71, 'Murloc Fin', 28, 'commodity'); market('c:71', 5000)
        putBag(0, 1, 71, 22); putBag(0, 2, 71, 20); putBag(0, 3, 71, 21)
        assert(T.bestWay('c:71', 71) == 'auction' and #T.vendorSellList() == 0)
        F.Data.addPosition(c, 'c:71', 'Murloc Fin', 2, 40, 'vendor', 28, now) -- 2 bought as a vendor deal
        local list = T.vendorSellList()
        assert(#list == 1 and list[1].slot == 2 and list[1].count == 20, 'the smallest stack holds them: ' .. #list)''')

    def test_a_sale_books_only_the_stock_in_its_stack(self):
        run(BASE + '''addItem(71, 'Murloc Fin', 28, 'commodity'); putBag(0, 1, 71, 20)
        F.Data.addPosition(c, 'c:71', 'Murloc Fin', 5, 100, 'vendor', 28, now) -- 5 bought, 15 looted
        MerchantFrame:Show(); fire('MERCHANT_SHOW')
        T.sellAllToVendor()
        for _ = 1, 100 do run(0.1); if not T.sellingToVendor() then break end end
        local s, j = c.stats['c:71'], c.journal[#c.journal]
        assert(s.sold == 5 and s.earned == 140, s.sold .. ' sold for ' .. s.earned)
        assert(j.kind == 'vendor' and j.qty == 5 and j.amount == 140 and j.profit == 40, j.qty .. ' ' .. j.amount)''')


class VendorMarkTests(unittest.TestCase):
    """V4-b, V25-a: an anti-undercut 'to a vendor' mark ends with its units and does not last for good."""

    def test_a_sale_by_hand_ends_the_mark_also_without_stock(self):
        run(BASE + '''F.db.toVendor = { ['i:30'] = now }
        putBag(0, 1, 30, 1)
        local bb = {}
        GetNumBuybackItems = function() return #bb end
        GetBuybackItemLink = function(i) return bb[i].link end
        GetBuybackItemInfo = function(i) return 'Linen Bag', nil, bb[i].price, bb[i].qty end
        MerchantFrame:Show(); fire('MERCHANT_SHOW')
        local v = bags[0][1]; bags[0][1] = nil; bb[#bb + 1] = { link = v.hyperlink, price = 2000, qty = 1 }
        fire('MERCHANT_UPDATE')
        assert(not F.db.toVendor['i:30'], 'sold by hand: later stock of the item is judged on its own')''')

    def test_an_old_mark_no_longer_sends_resale_stock_to_the_merchant(self):
        run(BASE + '''market('i:30', 26000)
        F.Data.addPosition(c, 'i:30', 'Linen Bag', 1, 15000, 'flip', 25000, now); putBag(0, 1, 30, 1)
        assert(T.bestWay('i:30', 30) == 'auction')
        F.db.toVendor = { ['i:30'] = now - 3600 }
        assert(#T.vendorSellList() == 1, 'a fresh mark sends the item to the merchant')
        F.db.toVendor['i:30'] = now - (T.VENDOR_MARK_DAYS + 1) * 86400
        assert(#T.vendorSellList() == 0 and not F.db.toVendor['i:30'], 'an old one is dropped')''')

    def test_posting_the_item_again_ends_its_mark(self):
        run(BASE + '''F.db.toVendor = { ['i:30'] = now }
        putBag(0, 1, 30, 1)
        local ok, why = T.post(F.AH.bagItems()[1], 1, 29900, 3)
        assert(ok and why == 'post_sent', tostring(why))
        fire('AUCTION_HOUSE_AUCTION_CREATED', 77)
        assert(not F.db.toVendor['i:30'], 'the player chose the auction house')''')


class GearSaleTests(unittest.TestCase):
    """V4-d, V4-e: Gear I can't use keeps kept items and sells through the paced merchant job."""

    def test_kept_gear_stays(self):
        run(test_audit.GearSellTests.GEAR + '''local key = F.AH.keyFor(81, bags[0][1].hyperlink)
        T.setRule(key, { keep = 1 })
        for _, v in ipairs(T.unusableGearList()) do assert(v.id ~= 81, 'the kept axe is not sold') end''')

    def test_gear_is_sold_in_paced_batches_and_the_chat_tells_what_sold(self):
        run(GEAR + '''local listed = #T.unusableGearList()
        assert(listed == 22, listed)
        local use, n = C_Container.UseContainerItem, 0
        C_Container.UseContainerItem = function(bag, slot)
            n = n + 1
            if n % 3 ~= 0 or n > listed then use(bag, slot) end -- every third first try is dropped
        end
        MerchantFrame:Show(); fire('MERCHANT_SHOW')
        assert(T.sellUnusableGear() == listed and T.sellingToVendor() and n == T.VENDOR_BATCH)
        assert(T.sellAllToVendor() == 0 and T.sellUnusableGear() == 0, 'one merchant sale at a time')
        for _ = 1, 100 do run(0.1); if not T.sellingToVendor() then break end end
        assert(#soldToVendor == listed and #T.unusableGearList() == 0, #soldToVendor .. ' of ' .. listed)
        assert(printed[#printed]:find('sold ' .. listed .. ' pieces of gear', 1, true), printed[#printed])''')


class LateVendorAnswerTests(unittest.TestCase):
    """V4-f: a stack queued to be sent again whose late answer emptied its slot is booked."""

    def test_at_the_next_batch(self):
        run(SLOW + '''now = now + 0.2; T.stepVendor()
        assert(not T.vendorJob and sent == 1, 'not sent again')
        assert(c.stats['c:71'].sold == 1 and not c.positions['c:71'], 'booked as sold')
        assert(printed[#printed]:find('sold 1 stacks', 1, true), tostring(printed[#printed]))''')

    def test_when_the_merchant_closes(self):
        run(SLOW + '''MerchantFrame:Hide(); T.stepVendor()
        assert(not T.vendorJob and c.stats['c:71'].sold == 1, 'booked as sold')''')


class PostNextTests(unittest.TestCase):
    """V22-c, V27-b: Post next bought posts the bought units not on sale yet, within the keep rule."""

    def test_units_already_on_sale_are_not_posted_again(self):
        run(POST + '''putBag(0, 1, 10, 20) -- 5 bought units and 15 looted ones
        C_AuctionHouse.GetAvailablePostCount = function() return 20 end
        F.Data.addPosition(c, 'c:10', 'Linen Cloth', 20, 1000, 'flip', 150, now - 3600)
        c.listings[#c.listings + 1] = { key = 'c:10', name = 'Linen Cloth', qty = 15, price = 150, at = now - 600,
            ids = { 999 }, open = 15, auctions = 1 }
        assert(T.postNext())
        assert(lastCall('PostCommodity')[4] == 5, lastCall('PostCommodity')[4])''')

    def test_the_keep_rule_stays_in_the_bags(self):
        run(POST + '''putBag(0, 1, 10, 10); putBag(0, 2, 10, 20)
        C_AuctionHouse.GetAvailablePostCount = function() return 30 end
        F.Data.addPosition(c, 'c:10', 'Linen Cloth', 30, 1000, 'flip', 150, now)
        T.setRule('c:10', { keep = 20 })
        assert(T.postNext())
        assert(lastCall('PostCommodity')[4] == 10, lastCall('PostCommodity')[4])
        T.lastPost = nil; T.setRule('c:10', { keep = 30 })
        local ok, why = T.postNext()
        assert(#T.toPost() == 0 and not ok and why == 'nothing_to_post', 'all of it is kept')''')


class OwnStockTests(unittest.TestCase):
    """V14-d: shopping-list and disenchant purchases are for the player's own use, not for sale."""

    def test_they_are_never_stale(self):
        run(BASE + '''F.Data.addPosition(c, 'c:10', 'Linen Cloth', 20, 2000, 'shop', 100, now - 4 * 86400, nil, 'addon')
        F.Data.addPosition(c, 'i:30', 'Linen Bag', 1, 15000, 'flip', 25000, now - 4 * 86400, nil, 'addon')
        local stale = {}
        for _, s in ipairs(T.itemStats()) do stale[s.key] = s.stale end
        assert(stale['c:10'] == false and stale['i:30'] == true)''')

    def test_post_all_leaves_them_in_the_bags(self):
        run(BASE + '''addItem(71, 'Murloc Fin', 28, 'commodity')
        F.Data.addPosition(c, 'c:10', 'Linen Cloth', 20, 2000, 'shop', 100, now)
        F.Data.addPosition(c, 'i:30', 'Linen Bag', 1, 15000, 'disenchant', nil, now)
        putBag(0, 1, 10, 20); putBag(0, 2, 30, 1); putBag(0, 3, 71, 5)
        local keys = {}
        for _, b in ipairs(T.toPostAll()) do keys[b.key] = true end
        assert(keys['c:71'] and not keys['c:10'] and not keys['i:30'])''')


class OwnAuctionTests(unittest.TestCase):
    """V12-c: an item is alone only when the scan saw no more units than the player had listed then."""

    def test_lots_posted_after_the_scan_do_not_hide_other_sellers(self):
        run(BASE + '''addItem(60, 'Heavy Hide', 100, 'item')
        for i = #auctions, 1, -1 do if auctions[i].owner == 'Me' then table.remove(auctions, i) end end
        for _ = 1, 3 do addAuction(60, 4000, 1, 'Rival') end
        for _, a in ipairs(auctions) do a.owner = '' end -- the scan names no sellers
        fullScan()
        assert(not F.Scan.last.ownersKnown and F.Scan.last.listed['i:60'] == 3)
        owned = {}
        for i = 1, 3 do -- posted after the scan: as many lots as the scan saw
            owned[i] = { auctionID = 900 + i, itemKey = { itemID = 60 }, itemLink = link(60), quantity = 1,
                buyoutAmount = 5000, status = 0, timeLeftSeconds = 40000 }
        end
        fire('OWNED_AUCTIONS_UPDATED')
        assert(not T.alone('i:60'), 'the three lots of the scan are another seller\\'s')''')


class ScanPriceTests(unittest.TestCase):
    """V12-d: after a purchase, the scan's lots stand for a price only through a check made since."""

    def test_the_lots_just_bought_are_not_a_price_to_undercut(self):
        run(BASE + '''addItem(70, 'Silk Cloth', 10, 'commodity')
        for _ = 1, 3 do addAuction(70, 1000, 1, 'Rival') end
        for _ = 1, 5 do addAuction(70, 3000, 1, 'Rival') end
        fullScan()
        assert(T.scanPrice('c:70').rows[1].unit == 1000)
        D.afterPurchase({ key = 'c:70', kind = 'commodity', qty = 3 }) -- the three at 10s
        for i = #auctions, 1, -1 do
            if auctions[i].item == 70 and auctions[i].buyout == 1000 then table.remove(auctions, i) end
        end
        assert(T.scanPrice('c:70') == nil, 'no price until a check')
        run(0.3); answer()
        local p = T.scanPrice('c:70')
        assert(p and p.rows[1].unit == 3000, 'the check after the purchase: ' .. tostring(p and p.rows[1].unit))''')


class UndercutCountTests(unittest.TestCase):
    """V24-c: the Undercuts page counts the plans it built instead of building them again."""

    def test_the_plans_given_are_counted(self):
        run(test_audit.AntiUndercutTests.PLAN + '''local built, fightPlans = 0, T.fightPlans
        T.fightPlans = function() built = built + 1; return fightPlans() end
        local plans = fightPlans()
        assert(#plans == 1 and T.fightCount(plans) == 1 and built == 0, 'built again: ' .. built)''')


class BuyRunBucketTests(unittest.TestCase):
    """The buy run waits for the check of a bucket's other auctions after buying one of them."""

    def test_the_run_goes_on_after_the_check(self):
        run(BASE + '''for i = #auctions, 1, -1 do table.remove(auctions, i) end
        addItem(40, 'Heavy Box', 2000, 'item')
        for _ = 1, 3 do addAuction(40, 1000, 1) end
        fullScan(); D.verify('i:40'); answer()
        assert(D.get('i:40').qty == 3 and #D.get('i:40').rows == 1, 'one row of three auctions')
        UI.show('deals:vendor'); UI.refresh()
        assert(T.runClick(), 'bought one auction of three')
        local bought = lastCall('PlaceBid')[2]
        for i, a in ipairs(auctions) do if a.id == bought then table.remove(auctions, i) break end end
        money = money - 1000; fire('PLAYER_MONEY')
        assert(D.pending('i:40'), 'the other two are read again')
        run(0.3)
        assert(T.run and F.Engine.message ~= 'run_done', 'the run waits for that check')
        answer(); run(0.1)
        assert(T.run and T.runState() == 'ready', tostring(T.runState()))''')


if __name__ == '__main__':
    unittest.main()
