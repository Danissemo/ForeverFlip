"""Commodity prices go to the copper on WoW Forever and to whole silver on Retail, where the server
drops a copper price without an answer (the post is never confirmed)."""
import unittest
from test_addon import run
from test_post_quantities import POST

RETAIL = "C_AuctionHouse.SupportsCopperValues=function() return false end;F.AH.readPriceStep();"


class PriceGridTests(unittest.TestCase):
    def test_forever_undercuts_commodities_by_one_copper(self):
        run(POST + """F.AH.readPriceStep();local U=F.Util
        assert(U.commodityStep==1 and U.below(20400,'commodity')==20399)
        assert(U.below(20400,'gear')==20300)
        """)

    def test_retail_undercuts_commodities_by_whole_silver(self):
        run(POST + RETAIL + """local U=F.Util
        assert(U.commodityStep==100)
        assert(U.below(20400,'commodity')==20300 and U.below(20399,'commodity')==20300)
        assert(U.stepDown(20399,'commodity')==20300 and U.stepUp(20301,'commodity')==20400)
        """)

    def test_retail_commodity_post_is_sent_in_whole_silver(self):
        run(POST + RETAIL + """putBag(0,1,10,10)
        C_AuctionHouse.GetAvailablePostCount=function() return 10 end
        local item=F.AH.bagItems()[1]
        assert(T.post(item,10,20399,3))
        assert(lastCall('PostCommodity')[5]==20300,tostring(lastCall('PostCommodity')[5]))
        """)

    def test_retail_commodity_post_below_one_silver_is_refused(self):
        run(POST + RETAIL + """putBag(0,1,10,10)
        C_AuctionHouse.GetAvailablePostCount=function() return 10 end
        local item=F.AH.bagItems()[1]
        local ok,why=T.post(item,10,99,3);assert(not ok and why=='values')
        """)

    def test_auto_posts_on_retail_stay_on_the_silver_grid(self):
        run(POST + RETAIL + """putBag(0,1,10,10)
        C_AuctionHouse.GetAvailablePostCount=function() return 10 end
        T.prices['c:10']={at=now,rows={{unit=15050,qty=100}}}
        F.db.settings.maxPricePercent=0
        assert(T.postAll(true))
        assert(lastCall('PostCommodity')[5]%100==0,tostring(lastCall('PostCommodity')[5]))
        """)


if __name__ == "__main__":
    unittest.main()
