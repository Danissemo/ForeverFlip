"""Shopping list, ignored items, learning from the player's searches, key bindings."""

import pathlib
import unittest

from test_addon import SETUP, run

SHOP = SETUP + '''local F=ForeverFlip
local Sh,D,T=F.Shopping,F.Deals,F.Trade
'''


class ShoppingTests(unittest.TestCase):
    def test_lot_at_or_below_the_wanted_price_is_a_shop_deal(self):
        run(SHOP + '''Sh.add('i:30',35000,nil,'Linen Bag');fullScan()
        local d=D.get('i:30');assert(d and d.mode=='shop' and d.cost==30000 and d.profit==5000,d and d.mode)''')

    def test_shop_quantity_limits_the_deal(self):
        run(SHOP + '''addItem(40,'Wool Cloth',0,'commodity');addAuction(40,100,50);Sh.add('c:40',120,7);fullScan()
        local d=D.get('c:40');assert(d and d.qty==7 and d.cost==700)''')

    def test_vendor_or_resale_deal_wins_over_the_shopping_entry(self):
        run(SHOP + '''Sh.add('c:10',200);fullScan();assert(D.get('c:10').mode=='vendor')''')

    def test_shop_purchase_is_not_posted_again(self):
        run(SHOP + '''local c=F.Data.char(F.db,F.Engine.owner())
        F.Data.addPosition(c,'i:30','Linen Bag',1,30000,'shop',35000,now);putBag(0,1,30,1)
        assert(#T.toPost()==0)''')

    def test_ignored_item_never_becomes_a_deal(self):
        run(SHOP + '''Sh.block('c:10','Linen Cloth');fullScan();assert(not D.get('c:10'))
        Sh.unblock('c:10');now=now+901;F.db.lastScan=0;fullScan();assert(D.get('c:10'))''')

    def test_shopping_page_adds_an_item_from_a_link(self):
        run(SHOP + '''local UI=F.UI;UI.show('shop')
        UI.shopItem:SetText(link(30));UI.shopMax:SetText('3g');UI.shopAdd:Click()
        assert(Sh.entry('i:30') and Sh.entry('i:30').max==30000)
        UI.refresh();assert(UI.shopTable.rows[1].key=='i:30')
        UI.shopTable.rows[1]:Click();UI.shopRemove:Click();assert(not Sh.entry('i:30'))''')

    def test_ignore_button_on_a_deal(self):
        run(SHOP + '''fullScan();local UI=F.UI;UI.show('deals:all');UI.selectDeal('c:10')
        UI.ignoreButton:Click();assert(Sh.blocked('c:10') and not D.get('c:10'))''')


class LearningTests(unittest.TestCase):
    def test_player_search_verifies_a_deal_at_once(self):
        run(SHOP + '''fullScan();D.list={}
        fire('COMMODITY_SEARCH_RESULTS_UPDATED',10)
        local d=D.get('c:10');assert(d and d.verified==time() and T.canBuy(d))''')

    def test_learning_can_be_switched_off(self):
        run(SHOP + '''fullScan();D.list={};F.db.settings.learnBrowsing=false
        fire('COMMODITY_SEARCH_RESULTS_UPDATED',10);assert(not D.get('c:10'))''')


class BindingTests(unittest.TestCase):
    def test_bindings_file_calls_existing_functions(self):
        xml = (pathlib.Path(__file__).resolve().parent.parent / 'ForeverFlip' / 'Bindings.xml').read_text(encoding='utf-8')
        for name in ('keyBuy', 'keyPost', 'keyCancel', 'keyScan'):
            self.assertIn('ForeverFlip.Engine.%s()' % name, xml)
        run(SHOP + '''for _,n in ipairs({'keyBuy','keyPost','keyCancel','keyScan'}) do assert(type(F.Engine[n])=='function') end
        assert(BINDING_NAME_FOREVERFLIP_BUY=='Buy or confirm the selected deal')''')

    def test_buy_key_buys_then_confirms(self):
        run(SHOP + '''fullScan();local UI=F.UI;UI.show('deals:all');UI.selectDeal('c:10');answer()
        F.Engine.keyBuy();assert(lastCall('StartCommoditiesPurchase'))
        fire('COMMODITY_PRICE_UPDATED',60,900);F.Engine.keyBuy();assert(lastCall('ConfirmCommoditiesPurchase'))''')


if __name__ == '__main__':
    unittest.main()
