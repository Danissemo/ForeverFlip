import unittest
from test_controller import controller_runtime
from test_ui import ui_runtime


class SalesStatsTests(unittest.TestCase):
    def test_stats_cover_periods_hold_time_best_items_and_tips(self):
        controller_runtime().execute('''local D=86400
        db.ledger={
          {uid='b1',kind='buy',owner='owner',scope='scope',key='1:0:0:0',qty=2,total=100,at=now-3*D},
          {uid='s1',kind='sell',owner='owner',scope='scope',key='1:0:0:0',qty=2,total=300,fee=15,at=now-D},
          {uid='b2',kind='buy',owner='owner',scope='scope',key='2:0:0:0',qty=1,total=500,at=now-5*D},
          {uid='s2',kind='sell',owner='owner',scope='scope',key='2:0:0:0',qty=1,total=400,fee=20,at=now-60},
          {uid='b3',kind='buy',owner='owner',scope='scope',key='3:0:0:0',qty=1,total=70,at=now-4*D}}
        local st=ForeverFlip.Stats.compute(c,now)
        local week=st.periods[2]
        assert(week.sales==2 and week.revenue==700 and week.profit==65 and week.cost==600)
        assert(math.abs(week.roi-65/600)<1e-9)
        assert(math.abs(week.heldDays-(2*2+5)/3)<0.01)
        assert(st.top[1].key=='1:0:0:0' and st.top[1].profit==185 and st.worst[1].key=='2:0:0:0')
        assert(st.stale==1 and st.staleValue==70 and #st.tips>=3)
        local today=st.periods[1];assert(today.sales<=2 and today.spent==0)''')

    def test_stats_page_and_empty_state_tip(self):
        ui_runtime().execute('''u:show('workbench','stats');u:refresh()
        assert(u.sections.workbench.split.pages.stats:IsShown() and u.statRows[3].cells[2]:GetText()=='0')
        assert(u.statTips:GetText()~='' and not u.statTop[1]:IsShown())''')

    def test_owned_listings_show_undercut_cheapest_and_sold(self):
        ui_runtime().execute('''queried=0;api.queryOwned=function()queried=queried+1 end
        c.candidates={{key={itemID=1},rows={{qty=1,unit=90,cost=90,auctionID=5},{qty=1,unit=120,cost=120,auctionID=6}},at=now,scope='scope'}}
        u:show('portfolio','auctions');u.actions.ownedRefresh:Click();assert(queried==1 and spent==0)
        api.owned=function()return {
          {auctionID=7,key={itemID=1},qty=2,buyout=200},{auctionID=8,key={itemID=1},qty=1,buyout=80},
          {auctionID=9,key={itemID=1},qty=1,buyout=50,sold=true},{auctionID=10,key={itemID=4},qty=1,buyout=50}}end
        c:event('OWNED_AUCTIONS_UPDATED');u:refresh()
        local s,p=c:ownedStatus(c.owned[1]);assert(s=='undercut' and p==90)
        assert(c:ownedStatus(c.owned[2])=='cheapest' and c:ownedStatus(c.owned[3])=='sold')
        assert(c:ownedStatus(c.owned[4])=='unknown')
        assert(u.ownedRows[1]:IsShown() and u.ownedRows[4]:IsShown() and not u.ownedRows[5]:IsShown())
        assert(u.ownedRows[1].advice:GetText()==ForeverFlip.Locale.text('No lower legal price — review market','No lower legal price — review market'))''')

    def test_live_search_skips_listings_checked_since_last_data(self):
        controller_runtime().execute('''db.lastReplicate=now;c.candidates={}
        for i=1,3 do c.candidates[i]={key={itemID=i},rows=rows,kind='commodity',family=false,at=now-10,scope='scope'}end
        c.radar=nil;assert(c:radarStart());c.radar.checkedAt={['1:0:0:0']=now-5,['2:0:0:0']=now-20}
        for _=1,20 do c:tick()end
        local queued={};for _,k in ipairs(c.radar.queue)do queued[k.itemID]=true end
        assert(not queued[1] and queued[2] and queued[3])''')
    def test_sale_invoices_are_recorded_once_and_feed_statistics(self):
        controller_runtime().execute('''db.listings={{owner='owner',scope='scope',key='1:0:0:0',name='Cloth',qty=5,price=100}}
        db.ledger={{uid='b',kind='buy',owner='owner',scope='scope',key='1:0:0:0',qty=5,total=300,at=now-86400}}
        local mail={{kind='seller',name='Cloth',qty=5,amount=520,deposit=40,fingerprint='f1'},
          {kind='seller',name='Other',qty=1,amount=100,deposit=0,fingerprint='f2'},
          {kind='buyer',name='Cloth',qty=5,amount=0,deposit=0,fingerprint='f3'}}
        api.mail=function()return mail end
        c:event('MAIL_INBOX_UPDATE');assert(#db.ledger==2 and db.ledger[2].kind=='sell' and db.ledger[2].total==480)
        c:event('MAIL_INBOX_UPDATE');assert(#db.ledger==2 and c.mailRecorded==0)
        local st=ForeverFlip.Stats.compute(c,now);assert(st.periods[1].sales==1 and st.periods[1].profit==180)
        db.settings.autoMail=false;mail[2].name='Cloth';mail[2].fingerprint='f4';db.listings[1].qty=1;mail[2].qty=1
        c:event('MAIL_INBOX_UPDATE');assert(#db.ledger==2)''')


if __name__ == '__main__':
    unittest.main()
