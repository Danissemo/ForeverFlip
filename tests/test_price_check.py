"""T17: My items views in the menu, and Check Sure at a sell price of the player's own.

For sale and Hidden are the two views of Selling -> My items in the menu; Hide and Rule... sit at
the bottom left. On Deals -> Resale (and My items) a price typed next to the summary line is
checked: Sells at, Profit, Est./day and Sure are recomputed at it, the market data stays as it was,
Reset brings the deal's own figures back, and the check stays through a sort and a refresh. When
too few sales were seen, the result says so."""

import re
import unittest

from test_addon import SETUP, run
from test_independent_routes import DEALS


def clean(text):
    return re.sub(r'\|c[0-9a-fA-F]{8}|\|r', '', text)


# DEALS: c:10, a resale (2 at 8c, the next lot at 50s, 30 sold a day just below 50s).
RESALE = DEALS + '''local UI,U=F.UI,F.Util
local function clean(t) return (t:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')) end
local function snapshot(t) local out={} for k,v in pairs(t) do out[#out+1]=tostring(k)..'='..tostring(v) end
    table.sort(out) return table.concat(out,',') end
local function row(key) for _,r in ipairs(UI.dealTable.rows) do if r.key==key and r:IsShown() then return r end end end
UI.show('deals:flip')
UI.selectDeal('c:10')
'''


class DealCheckTests(unittest.TestCase):
    def test_the_check_at_the_deal_price_matches_its_sure(self):
        run(RESALE + '''local d=D.get('c:10')
        local c=D.checkDeal(d,d.exit,now)
        assert(c.sure==D.sure(d,now), 'the same price, the same Sure')
        assert(math.abs(c.profit-d.profit)<=1, c.profit..' vs '..d.profit)''')

    def test_a_higher_price_recomputes_without_touching_the_market_data(self):
        run(RESALE + '''local d=D.get('c:10')
        local before=snapshot(h.sales)..'|'..d.exit..'|'..d.profit
        assert(UI.checkDeal('80s'))
        local r=row('c:10')
        assert(clean(r.cols[3]:GetText())=='80s 00c', r.cols[3]:GetText())
        assert(D.checkDeal(d,8000,now).profit>d.profit, 'a higher price, a higher profit')
        assert(snapshot(h.sales)..'|'..d.exit..'|'..d.profit==before, 'market data and deal unchanged')
        assert(UI.dealBox.full():find('Check'), UI.dealBox.full())''')

    def test_the_check_stays_through_a_sort_and_a_refresh_and_reset_restores(self):
        run(RESALE + '''UI.checkDeal('80s')
        UI.dealSort=1;UI.refresh();F.Engine.changed();UI.refresh()
        assert(UI.selected=='c:10' and UI.dealCheck and UI.dealCheck.price==8000)
        assert(clean(row('c:10').cols[3]:GetText())=='80s 00c')
        UI.dealCheckReset:Click()
        assert(UI.dealCheck==nil)
        assert(clean(row('c:10').cols[3]:GetText())~='80s 00c')
        assert(UI.dealCheckPrice:GetText()==U.plainMoney(D.get('c:10').exit), UI.dealCheckPrice:GetText())''')

    def test_another_deal_or_the_vendor_page_drops_the_check(self):
        run(RESALE + '''UI.checkDeal('80s');UI.selectDeal(nil)
        assert(UI.dealCheck==nil)
        UI.show('deals:vendor')
        assert(not UI.dealCheckButton:IsShown(), 'the To vendor page has Buy first there')''')

    def test_too_few_sales_say_so(self):
        run(RESALE + '''h.sales.pairs=1;D.sureCache={}
        UI.checkDeal('80s')
        local c=D.checkDeal(D.get('c:10'),8000,now)
        assert(c.thin)
        assert(UI.dealBox.full():find('Too few sales'), UI.dealBox.full())''')


SELL = SETUP + '''local F=ForeverFlip;local UI=F.UI;local U=F.Util
fullScan()
putBag(0,1,30,1)
UI.show('sell:sale')
local function row(key) for _,r in ipairs(UI.sellTable.rows) do if r.key==key and r:IsShown() then return r end end end
row('i:30'):Click();run(1.1);answer();UI.refresh()
'''


class MyItemsTests(unittest.TestCase):
    def test_for_sale_and_hidden_are_menu_views(self):
        run(SELL + '''local kids=UI.menuKids
        assert(kids['sell:sale'] and kids['sell:hidden'])
        assert(kids['sell:sale'].label:GetText()=='For sale (1)', kids['sell:sale'].label:GetText())
        assert(kids['sell:sale']:IsShown() and kids['sell:sale'].selected:IsShown())
        kids['sell:hidden']:Click()
        assert(UI.sellView=='hidden' and UI.sellSelected==nil)
        UI.show('sell');assert(UI.sellView=='sale', 'My items opens For sale')''')

    def test_check_sure_on_my_items(self):
        text = run(SELL + '''local posting=UI.sellPrice:GetText()
        assert(not UI.sellSureButton:IsEnabled(), 'nothing typed in the Check Sure box')
        UI.sellCheckPrice:SetText('5g');UI.refresh()
        assert(UI.sellSureButton:IsEnabled())
        UI.sellSureButton:Click()
        assert(UI.sellSureCheck and UI.sellSureCheck.price==50000)
        assert(UI.sellPrice:GetText()==posting, 'the posting price is left alone')
        local r=row('i:30')
        assert(r.cols[5]:GetText():find('5g'), 'the row shows the price checked')
        local full=UI.sellBox.full()
        UI.sellSureReset:Click()
        assert(UI.sellSureCheck==nil and not UI.sellBox.full():find('Check'))
        assert(UI.sellCheckPrice:GetText()=='')
        UI.sellCheckPrice:SetText('6g');UI.sellCheckPrice.scripts.OnEnterPressed(UI.sellCheckPrice)
        assert(UI.sellSureCheck and UI.sellSureCheck.price==60000, 'Enter checks too')
        UI.menuKids['sell:hidden']:Click()
        assert(not UI.sellCheckPrice:IsShown() and not UI.sellSureButton:IsShown())
        return full''')
        text = clean(text)
        self.assertIn('Check at 5g 00s each', text)
        self.assertIn('Too few sales were seen', text)



class MarketResetCheckTests(unittest.TestCase):
    def test_market_reset_has_check_sure_and_no_money_boxes(self):
        run(RESALE + '''UI.show('deals:median')
        assert(UI.dealCheckButton:IsShown() and UI.dealCheckReset:IsShown() and UI.dealCheckPrice:IsShown())
        for _,e in ipairs(UI.medianBoxes) do assert(not e:IsShown(), 'the limits live on Settings') end
        for _,w in ipairs(UI.medianWidgets) do assert(not w:IsShown()) end''')


class BidCheckTests(unittest.TestCase):
    def test_a_selected_bid_is_checked_at_a_typed_price_and_reset(self):
        from test_bids import BIDS
        run(BIDS + '''local UI=F.UI;UI.show('bids')
        assert(not UI.bidCheckButton:IsEnabled(), 'nothing selected')
        UI.bidTable.rows[1]:Click();UI.refresh()
        assert(UI.bidCheckButton:IsEnabled() and UI.bidCheckPrice:GetText()~='', 'the box starts at a price')
        assert(UI.checkBid('30s') and UI.bidChecked.price==3000)
        UI.refresh()
        assert(UI.bidText:GetText():find('Check'), UI.bidText:GetText())
        assert(UI.bidCheckReset:IsEnabled())
        UI.bidCheckReset:Click()
        assert(UI.bidChecked==nil and not UI.bidText:GetText():find('Check|r',1,true))''')

if __name__ == '__main__':
    unittest.main()
