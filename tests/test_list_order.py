"""Bulk buttons work down the list as the player sorted it: Check all, Post all, Post AH-worthy."""

import unittest

from test_addon import SETUP, run

ORDER = SETUP + '''local F=ForeverFlip
local T,UI,U=F.Trade,F.UI,F.Util
fullScan()
F.Scan.last.groups=nil
putBag(0,1,30,1);putBag(0,2,10,20)
UI.show('sell')
local function shown()
    local out={}
    for _,r in ipairs(UI.sellTable.rows) do if r.key and r:IsShown() then out[#out+1]=r.key end end
    return out
end
local function sortBy(column,descending)
    UI.sellTable.setSort(column,descending);UI.refresh()
end
'''


class ListOrderTests(unittest.TestCase):
    def test_in_order_puts_the_shown_rows_first_and_keeps_the_rest(self):
        run(SETUP + '''local U=ForeverFlip.Util
        local out=U.inOrder({'a','b','c','d'},{c=1,a=2})
        assert(table.concat(out)=='cabd',table.concat(out))
        assert(table.concat(U.inOrder({'a','b'},nil))=='ab')''')

    def test_check_all_on_my_items_goes_down_the_list_both_ways(self):
        run(ORDER + '''for _,desc in ipairs({false,true}) do
            sortBy(1,desc)
            local rows=shown();assert(#rows==2)
            local _,keys=UI.statusTargets()
            assert(keys[1]==rows[1] and keys[2]==rows[2],table.concat(keys,',')..' vs '..table.concat(rows,','))
        end''')

    def test_post_all_posts_the_top_row_first(self):
        run(ORDER + '''for _,desc in ipairs({false,true}) do
            sortBy(1,desc)
            local top=shown()[1]
            T.posting=nil;T.lastPost=nil
            for k in pairs(calls) do calls[k]=nil end
            T.postAll()
            local n=0
            while F.Deals.search or #F.Deals.requests>0 do
                if F.Deals.search then answer() end
                run(1.1);n=n+1;assert(n<50)
            end
            T.postAll()
            local first
            for _,c in ipairs(calls) do
                if c[1]=='PostItem' then first=first or 'i:30' elseif c[1]=='PostCommodity' then first=first or 'c:10' end
            end
            assert(first==top,tostring(first)..' posted, top row '..top)
            fire('AUCTION_HOUSE_AUCTION_CREATED',1);run(11)
            putBag(0,1,30,1);putBag(0,2,10,20)
        end''')

    def test_check_all_on_deals_follows_the_sorted_page(self):
        run(SETUP + '''local F=ForeverFlip;local UI=F.UI
        fullScan();UI.show('deals:all')
        local list=F.Deals.visible('all');assert(#list>=2,'deals to sort')
        for _,desc in ipairs({false,true}) do
            UI.dealSort,UI.dealDescending=1,desc;UI.refresh()
            local _,keys=UI.statusTargets()
            assert(keys[1]==UI.dealSorted[1].key and keys[#keys]==UI.dealSorted[#UI.dealSorted].key)
        end''')


if __name__ == '__main__':
    unittest.main()
