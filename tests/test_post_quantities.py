"""Posting uses the client's whole-item availability, rather than the first bag stack."""
import unittest
from test_addon import run
from test_selling_rules import SELL


class PostingQuantityTests(unittest.TestCase):
    def test_ah_worthy_posts_all_commodity_stacks_in_one_request(self):
        run(SELL + """putBag(0,1,10,10);putBag(0,2,10,10);putBag(1,1,10,20)
        C_AuctionHouse.GetAvailablePostCount=function() return 40 end
        T.prices['c:10']={at=now,rows={{unit=150,qty=100}}}
        local ok,why=T.postAll(true);assert(ok and why=='post_sent',why)
        assert(lastCall('PostCommodity')[4]==40,'all 40 units, not the first stack of 10')
        assert(T.lastPost.qty==40 and T.lastPost.auctions==1)
        """)

    def test_keep_rule_applies_to_total_across_stacks(self):
        run(SELL + """putBag(0,1,10,10);putBag(0,2,10,10);putBag(1,1,10,20)
        C_AuctionHouse.GetAvailablePostCount=function() return 40 end
        T.setRule('c:10',{keep=25})
        T.prices['c:10']={at=now,rows={{unit=150,qty=100}}}
        assert(T.postAll(true))
        assert(lastCall('PostCommodity')[4]==15,'leave 25, post the other 15')
        """)

    def test_client_availability_caps_quantity_and_manual_posts(self):
        run(SELL + """putBag(0,1,10,10);putBag(0,2,10,20)
        C_AuctionHouse.GetAvailablePostCount=function() return 12 end
        T.prices['c:10']={at=now,rows={{unit=150,qty=100}}}
        local item=F.AH.bagItems()[1]
        local ok,why=T.post(item,13,149,3);assert(not ok and why=='values')
        assert(T.postAll(true));assert(lastCall('PostCommodity')[4]==12)
        """)

    def test_bought_queue_posts_all_available_units_of_its_position(self):
        run(SELL + """putBag(0,1,10,10);putBag(0,2,10,20)
        C_AuctionHouse.GetAvailablePostCount=function() return 30 end
        F.Data.addPosition(c,'c:10','Linen Cloth',25,1000,'flip',150,now)
        T.prices['c:10']={at=now,rows={{unit=150,qty=100}}}
        assert(T.postNext());assert(lastCall('PostCommodity')[4]==25)
        """)

    def test_manual_post_accepts_multiple_stacks_but_not_more_than_available(self):
        run(SELL + """putBag(0,1,10,10);putBag(0,2,10,20)
        C_AuctionHouse.GetAvailablePostCount=function() return 30 end
        local item=F.AH.bagItems()[1]
        local ok,why=T.post(item,31,149,3);assert(not ok and why=='values')
        assert(T.post(item,30,149,3));assert(lastCall('PostCommodity')[4]==30)
        """)

    def test_item_posts_are_capped_to_matching_bag_units(self):
        run(SELL + """putBag(0,1,30,1);putBag(1,1,30,1);putBag(1,2,10,20)
        C_AuctionHouse.GetAvailablePostCount=function() return 99 end
        T.prices['i:30']={at=now,rows={{unit=30000,qty=10}}}
        assert(T.postAll(true));assert(lastCall('PostItem')[4]==2)
        assert(T.lastPost.auctions==2,'wait for both item auction confirmations')
        """)

    def test_no_second_post_before_confirmation_or_without_another_click(self):
        run(SELL + """putBag(0,1,10,10);putBag(0,2,30,1)
        C_AuctionHouse.GetAvailablePostCount=function(loc) return loc.slot==1 and 10 or 1 end
        T.prices['c:10']={at=now,rows={{unit=150,qty=100}}}
        T.prices['i:30']={at=now,rows={{unit=30000,qty=1}}}
        assert(T.postAll(true));assert(not lastCall('PostItem'))
        local ok,why=T.postAll(true);assert(not ok and why=='busy')
        fire('AUCTION_HOUSE_AUCTION_CREATED',123);run(0.2)
        assert(not lastCall('PostItem'),'confirmation cannot trigger an unattended post')
        """)


if __name__ == '__main__':
    unittest.main()
