"""Retail's Fated Fortune Cards: the unread card (194829) is priced by the item data but no merchant
buys it, so it is never offered to one; a read card is soulbound and good only to a merchant, so Sell
all takes it although it is bound."""

import unittest

from test_addon import SETUP, run
import test_audit

CARDS = test_audit.BASE + '''local T = F.Trade
F.db.settings.vendorMargin = 0
addItem(194829, 'Fated Fortune Card', 230000, 'item'); addItem(199118, 'Fated Fortune Card', 10000, 'item')
addItem(199132, 'Fated Fortune Card', 10000, 'item'); addItem(91, 'Bound Trinket', 5000, 'item')
putBag(0, 1, 194829, 3); putBag(0, 2, 199118, 1); putBag(0, 3, 199132, 1); putBag(0, 4, 91, 1)
bags[0][2].isBound = true; bags[0][3].isBound = true; bags[0][4].isBound = true
'''


class FortuneCardTests(unittest.TestCase):
    def test_the_unread_card_is_never_offered_to_a_merchant(self):
        run(CARDS + '''assert(F.AH.vendorPrice(194829) == nil, 'no merchant buys it')
        for _, v in ipairs(T.vendorSellList()) do assert(v.id ~= 194829, 'not in Sell all') end''')

    def test_read_cards_are_sold_although_bound(self):
        run(CARDS + '''MerchantFrame:Show(); fire('MERCHANT_SHOW')
        local ids = {}
        for _, v in ipairs(T.vendorSellList()) do ids[#ids + 1] = v.id end
        table.sort(ids)
        assert(table.concat(ids, ',') == '199118,199132', table.concat(ids, ','))''')

    def test_a_read_card_the_auction_house_does_not_know_is_still_sold(self):
        run(CARDS + '''local keyInfo = C_AuctionHouse.GetItemKeyInfo
        C_AuctionHouse.GetItemKeyInfo = function(key)
            if key.itemID == 199121 then return nil end
            return keyInfo(key)
        end
        C_AuctionHouse.GetItemCommodityStatus = function() return 0 end
        addItem(199121, 'Fated Fortune Card', 10000, 'item'); putBag(1, 1, 199121, 1); bags[1][1].isBound = true
        MerchantFrame:Show(); fire('MERCHANT_SHOW')
        local found
        for _, v in ipairs(T.vendorSellList()) do found = found or v.id == 199121 end
        assert(found, 'the card is read from the bag and sold')''')

    def test_the_tooltip_says_merchants_do_not_buy_the_unread_card(self):
        text = run(SETUP + """addItem(194829, 'Fated Fortune Card', 230000, 'commodity')
        addAuction(194829, 124100, 5); fullScan()
        tooltipLines = {}
        GameTooltip.itemLink = link(194829)
        for _, fn in ipairs(tooltipCalls) do fn(GameTooltip, { lines = { { type = 11, price = 230000 } } }) end
        return table.concat(tooltipLines, ' ## ')""")
        self.assertIn('not bought by merchants', text)

    def test_the_tooltip_follows_a_merchant_seen_refusing_an_item(self):
        text = run(SETUP + """addItem(194830, 'Odd Trinket', 50000, 'commodity')
        addAuction(194830, 124100, 5); fullScan()
        local db = ForeverFlip.db
        db.vendorSeen = db.vendorSeen or {}
        db.vendorSeen[194830] = { p = 0 }
        tooltipLines = {}
        GameTooltip.itemLink = link(194830)
        for _, fn in ipairs(tooltipCalls) do fn(GameTooltip, { lines = {} }) end
        return table.concat(tooltipLines, ' ## ')""")
        self.assertIn('not bought by merchants', text)
        self.assertNotIn('5g', text)
        self.assertNotIn('23g', text)

    def test_only_cards_are_junk(self):
        run(CARDS + '''assert(F.AH.vendorJunk(199114) and F.AH.vendorJunk(199170))
        assert(not F.AH.vendorJunk(199115) and not F.AH.vendorJunk(194829) and not F.AH.vendorJunk(91))''')


if __name__ == '__main__':
    unittest.main()
