"""Per-purchase movement history survives the global journal and keeps its intent."""
import unittest
from test_addon import SETUP, run

EVENTS = SETUP + '''local F, D, UI = ForeverFlip, ForeverFlip.Data, ForeverFlip.UI
local c = D.char(F.db, F.Engine.owner())
local function buy(key, qty, cost, at, mode, bid)
    D.addPosition(c,key,'Linen Cloth',qty,cost,mode or 'flip',nil,at,bid)
    D.log(c,{kind='buy',key=key,qty=qty,amount=cost,at=at,mode=mode or 'flip',bid=bid})
end
'''

class JournalEventTests(unittest.TestCase):
    def test_fifo_sales_keep_actual_exit_and_original_intent(self):
        run(EVENTS + '''buy('c:10',2,200,now-3600,'vendor'); buy('c:10',3,450,now,'flip',true)
        D.sale(c,'c:10','Linen Cloth',3,601,now+1)
        D.log(c,{kind='vendor',key='c:10',qty=3,amount=601,at=now+1})
        local a,b=c.lots[1],c.lots[2]
        assert(#a.events==2 and #b.events==2,'one purchase and one partial sale each')
        assert(a.events[1].mode=='vendor' and b.events[1].bid)
        assert(a.events[2].kind=='vendor' and a.events[2].qty==2 and a.events[2].amount==400)
        assert(b.events[2].qty==1 and b.events[2].amount==201,'allocated money must sum exactly')
        assert(b.mode=='flip' and b.bid,'actual exit must not rewrite purchase intent')''')

    def test_listing_and_loss_events_do_not_duplicate_accounting(self):
        run(EVENTS + '''buy('c:10',4,400,now)
        D.log(c,{kind='post',key='c:10',qty=4,amount=800,deposit=20,at=now+1})
        D.addCost(c,'c:10',20,now+2,4)
        D.log(c,{kind='cancel',key='c:10',qty=4,amount=20,at=now+2,estimated=true})
        D.log(c,{kind='return',key='c:10',qty=4,amount=0,at=now+3,accounted=true})
        local lot=c.lots[1]
        assert(#lot.events==4 and lot.events[2].kind=='post' and lot.events[2].deposit==20)
        assert(lot.events[3].kind=='cancel' and lot.events[3].estimated and lot.events[4].kind=='return')
        assert(lot.lost==20 and c.positions['c:10'].cost==420 and c.daily[math.floor(now/86400)].spent==400)''')

    def test_history_survives_global_journal_retention_and_is_bounded(self):
        run(EVENTS + '''buy('c:10',1,100,now)
        for i=1,510 do D.log(c,{kind='post',key='c:10',qty=1,amount=200,at=now+i}) end
        local lot=c.lots[1]
        assert(#c.journal==500 and #lot.events<=300)
        assert(lot.historyIncomplete and lot.events[#lot.events].at==now+510)
        assert(lot.events[1].kind=='buy','purchase origin survives event eviction')''')

    def test_old_lots_are_never_rebuilt_from_a_truncated_journal(self):
        run(EVENTS + '''c.lots={{id=7,key='c:10',at=now-9999,qty=50,cost=5000,left=10,sold=40,received=8000,lost=20}}
        c.lotsJoined=1; c.lotSeq=7
        c.journal={{kind='sell',key='c:10',qty=1,amount=200,at=now}}
        local lot=D.lots(c)[1]
        assert(lot.qty==50 and lot.sold==40 and lot.received==8000)
        assert(lot.historyIncomplete and #lot.events==0,'do not fabricate a purchase or attribute an ambiguous sale')''')

    def test_selection_survives_sort_and_scroll_but_clears_for_other_filter(self):
        run(EVENTS + '''for i=1,25 do buy('c:'..(100+i),1,100,now+i*1000) end
        UI.show('journal'); UI.refreshJournal()
        UI.lotTable.rows[1]:Click(); local id=UI.journalSelected.id
        assert(#UI.journalHistory.lines>=2)
        UI.lotTable.scroll(1); assert(UI.journalSelected.id==id and UI.lotTable.offset==3)
        UI.lotTable.headers[4]:Click(); assert(UI.journalSelected.id==id)
        UI.show('journal:vendor'); assert(UI.journalSelected==nil and #UI.journalHistory.lines==0)
        for _,r in ipairs(UI.lotTable.rows) do assert(not r:IsShown()) end''')

    def test_history_scrolls_independently_without_covering_table(self):
        run(EVENTS + '''buy('c:10',1,100,now)
        for i=1,8 do D.log(c,{kind='post',key='c:10',qty=1,amount=200,at=now+i}) end
        UI.show('journal'); UI.lotTable.rows[1]:Click()
        local box=UI.journalHistory
        assert(#box.lines>box.rows and box.rows==3)
        local before=box.text:GetText()
        UI.journalHistoryFrame.scripts.OnMouseWheel(UI.journalHistoryFrame,-1)
        assert(box.offset==1 and box.text:GetText()~=before and UI.lotTable.offset==0)
        UI.refreshJournal(); assert(box.offset==1,'refresh preserves selected history scroll')
        assert(UI.lotTable.size<16,'reserve table rows for the history panel')''')

if __name__ == '__main__': unittest.main()
