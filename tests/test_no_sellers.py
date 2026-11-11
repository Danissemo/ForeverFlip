"""Posting an item nobody sells on the auction house and ForeverFlip has no price for."""

import unittest

from test_addon import SETUP, run

NONE = SETUP + '''local F=ForeverFlip
local T,UI=F.Trade,F.UI
fullScan()
-- a recipe nobody sells, never seen in a scan; a vendor pays 25c for it
addItem(70,'Recipe: Crispy Bat Wing',25,'item')
putBag(0,1,70,1)
local function item() for _,b in ipairs(F.AH.bagItems()) do if b.id==70 then return b end end end
'''


class NoSellerTests(unittest.TestCase):
    def test_empty_check_suggests_a_marked_guess(self):
        run(NONE + '''T.checkPrice('i:70');run(1.1);answer()
        assert(T.prices['i:70'] and #T.prices['i:70'].rows==0,'the empty result is remembered')
        local price,_,cheapest,why=T.suggest(item())
        assert(price==100 and cheapest==nil and why=='vendor',tostring(price)..' '..tostring(why))''')

    def test_sell_page_explains_and_fills_the_price(self):
        run(NONE + '''UI.show('sell');for _,r in ipairs(UI.sellTable.rows) do if r.key=='i:70' then r:Click() end end
        run(1.1);answer();UI.refresh()
        assert(UI.sellPrice:GetText()~='','price filled in')
        assert(UI.sellText:GetText():find('guess',1,true),UI.sellText:GetText())
        assert(UI.postButton:IsEnabled())''')

    def test_last_posted_price_is_reused(self):
        run(NONE + '''T.checkPrice('i:70');run(1.1);answer()
        T.post(item(),1,250000,3)
        local price,_,_,why=T.suggest(item());assert(price==250000 and why=='last',why)''')

    def test_queues_skip_a_guessed_price(self):
        run(NONE + '''T.checkPrice('i:70');run(1.1);answer()
        local list={item()};local n=#calls
        local ok,why=T.postAll()
        for i=n+1,#calls do assert(calls[i][1]~='PostItem','a guess is never posted by the queue') end''')

    def test_item_missing_from_a_fresh_scan_gets_a_price_without_a_check(self):
        run(NONE + '''assert(F.Scan.notListed('i:70') and not F.Scan.notListed('c:10'))
        local price,_,_,why=T.suggest(item());assert(price==100 and why=='vendor',why)
        UI.show('sell');for _,r in ipairs(UI.sellTable.rows) do if r.key=='i:70' then UI.sellSelected=r.item end end
        UI.refresh();assert(UI.sellText:GetText():find('last full scan',1,true),UI.sellText:GetText())
        assert(UI.sellPrice:GetText()~='')''')

    def test_no_answer_counts_as_no_sellers(self):
        run(NONE + '''now=now+1300 -- the scan is too old to tell
        assert(not F.Scan.notListed('i:70') and T.suggest(item())==nil)
        T.checkPrice('i:70');run(1.1);assert(F.Deals.search);run(11)
        assert(T.noAnswer['i:70'] and not T.prices['i:70'])
        local price,_,_,why=T.suggest(item());assert(price==100 and why=='vendor',why)
        UI.show('sell');for _,r in ipairs(UI.sellTable.rows) do if r.key=='i:70' then UI.sellSelected=r.item end end
        UI.refresh();assert(UI.sellText:GetText():find('did not answer',1,true),UI.sellText:GetText())''')

    def test_no_answer_for_a_listed_item_is_not_trusted(self):
        run(NONE + '''T.checkPrice('c:10');run(1.1);assert(F.Deals.search);run(11)
        assert(T.noAnswer['c:10'] and not T.noSellers('c:10'),'the scan saw cloth listed')''')

    def test_aux_price_is_preferred_over_a_guess(self):
        run(NONE + '''AuxForeverAPI={IsReady=function() return true end,GetUsualPrice=function(id) return id==70 and 54321 or nil end}
        T.checkPrice('i:70');run(1.1);answer()
        local price,_,_,why=T.suggest(item());assert(price==54300 and why=='aux',why)''')


if __name__ == '__main__':
    unittest.main()
