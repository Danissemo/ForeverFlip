"""Column sorting of every table that has no sorting of its own."""

import unittest

from test_addon import SETUP, run

SORT = SETUP + '''local F=ForeverFlip
local UI=F.UI
local function header(t,label)
    for i,h in pairs(t.headers) do if h:GetText()==label then return h end end
    error('no header '..label)
end
local function names(t)
    local out={} for _,r in ipairs(t.rows) do if r:IsShown() then out[#out+1]=r.name:GetText() end end return out
end
'''


class SortingTests(unittest.TestCase):
    def test_crafting_sorts_by_profit_both_ways(self):
        run(SORT + '''local c=F.Data.char(F.db,F.Engine.owner())
        c.recipes={[1]={name='A',out=10,n=1,r={{10,1}}},[2]={name='B',out=10,n=1,r={{10,3}}},[3]={name='C',out=10,n=1,r={{10,2}}}}
        fullScan();UI.show('crafting')
        local h=header(UI.craftTable,'Profit');h:Click()
        local n=names(UI.craftTable);assert(n[1]=='A' and n[2]=='C' and n[3]=='B',table.concat(n,','))
        assert(h.Arrow:IsShown())
        h:Click();n=names(UI.craftTable);assert(n[1]=='B' and n[3]=='A',table.concat(n,','))''')

    def test_name_column_sorts_a_to_z_first(self):
        run(SORT + '''local c=F.Data.char(F.db,F.Engine.owner())
        c.recipes={[1]={name='Zeta',out=10,n=1,r={{10,1}}},[2]={name='alpha',out=10,n=1,r={{10,1}}}}
        fullScan();UI.show('crafting');header(UI.craftTable,'Name'):Click()
        local n=names(UI.craftTable);assert(n[1]=='alpha' and n[2]=='Zeta',table.concat(n,','))''')

    def test_sell_page_sorts_by_quantity(self):
        run(SORT + '''putBag(0,1,30,1);putBag(0,2,10,20);fullScan();UI.show('sell')
        header(UI.sellTable,'Qty'):Click()
        assert(UI.sellTable.rows[1].key=='c:10' and UI.sellTable.rows[2].key=='i:30')
        header(UI.sellTable,'Qty'):Click();assert(UI.sellTable.rows[1].key=='i:30')''')

    def test_statistics_sorts_by_profit(self):
        run(SORT + '''local c=F.Data.char(F.db,F.Engine.owner());local D=F.Data
        D.addPosition(c,'c:10','Linen Cloth',2,100,'flip',100,now);D.sale(c,'c:10','Linen Cloth',2,500,now)
        D.addPosition(c,'i:30','Linen Bag',1,100,'flip',100,now);D.sale(c,'i:30','Linen Bag',1,9000,now)
        UI.show('stats');header(UI.statsTable,'Profit'):Click()
        assert(UI.statsTable.rows[1].name:GetText()=='Linen Bag')''')

    def test_market_list_is_sorted_as_a_copy(self):
        run(SORT + '''fullScan();UI.show('analytics')
        local m=F.Analytics.market();local view=m[UI.marketView] or {};local first=view[1]
        header(UI.marketTable,'Usual price'):Click();header(UI.marketTable,'Usual price'):Click()
        assert(F.Analytics.market()[UI.marketView][1]==first,'the cached list keeps its order')''')


if __name__ == '__main__':
    unittest.main()
