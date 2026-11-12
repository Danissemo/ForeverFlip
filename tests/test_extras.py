"""Public API, aux prices, CSV export, gold tracking and presets."""

import unittest

from test_addon import SETUP, run

EXTRA = SETUP + '''local F=ForeverFlip
fullScan()
'''


class ApiTests(unittest.TestCase):
    def test_undercut_scan_notification_uses_selected_locale(self):
        run(EXTRA + '''F.Locale.apply('uk');F.Trade.fightCount=function() return 1 end
        F.Trade.toldFights=nil;F.Trade.afterScan()
        assert(printed[#printed]:find(F.Locale.text('%d of your auctions were undercut and are worth answering: Selling, Undercuts.'):format(1),1,true))
        ''')

    def test_cheapest_today_does_not_return_yesterdays_price(self):
        run(EXTRA + '''local h=F.Data.market(F.db,F.Engine.scope()).history['c:10']
        h.days={{d=math.floor(now/86400)-1,min=1,m=100,n=10}}
        local usual,cheap=ForeverFlipAPI.GetPrice(10)
        assert(usual and cheap==nil,'historical daily minimum is not today')
        h.days[1].d=math.floor(now/86400)
        local _,today=ForeverFlipAPI.GetPrice(10);assert(today==1)
        ''')

    def test_get_price_and_deal(self):
        run(EXTRA + '''assert(ForeverFlipAPI.IsReady() and ForeverFlipAPI.version==1)
        local usual,cheap,_,_,age=ForeverFlipAPI.GetPrice(link(10))
        assert(usual and cheap==60 and age and age<5,usual)
        assert(ForeverFlipAPI.GetPrice(10)==usual and ForeverFlipAPI.GetPrice('item:10::::')==usual)
        local mode,profit,_,qty=ForeverFlipAPI.GetDeal(10);assert(mode=='vendor' and profit==600 and qty==15)
        assert(ForeverFlipAPI.GetPrice(99999)==nil and ForeverFlipAPI.GetPrice({})==nil)''')

    def test_aux_price_is_a_fallback(self):
        run(EXTRA + '''assert(F.Engine.auxPrice(51)==nil)
        AuxForeverAPI={IsReady=function() return true end,GetUsualPrice=function(id) return id==51 and 77 or nil end}
        assert(F.Engine.auxPrice(51)==77)''')


class ExportTests(unittest.TestCase):
    def test_journal_as_csv(self):
        run(EXTRA + '''local c=F.Data.char(F.db,F.Engine.owner())
        F.Data.log(c,{at=now,kind='sell',name='Linen "Bag"',qty=1,amount=28500,profit=8500})
        local csv=F.Analytics.csv()
        assert(csv:find('date,kind,item',1,true) and csv:find('"Linen ""Bag""",1,28500,8500',1,true),csv)
        local UI=F.UI;UI.show('journal');UI.exportButton:Click()
        assert(UI.exportFrame:IsShown() and UI.exportFrame.box:GetText()==csv)''')


class GoldTests(unittest.TestCase):
    def test_gold_of_realm_characters(self):
        run(EXTRA + '''money=50000;fire('PLAYER_MONEY')
        F.db.gold['Realm-Alt']={[math.floor(now/86400)-10]=10000,[math.floor(now/86400)]=30000}
        F.db.gold['Other-Char']={[math.floor(now/86400)]=999999}
        local c=F.Data.char(F.db,'Realm-Alt');F.Data.addPosition(c,'c:10','Linen Cloth',5,300,'flip',100,now)
        local r=F.Analytics.realm(7);assert(r.chars==2 and r.gold==80000 and r.before==60000 and r.stock==300,r.before)''')


class PresetTests(unittest.TestCase):
    def test_presets_set_thresholds(self):
        run(EXTRA + '''local UI=F.UI;UI.show('settings');UI.preset_careful:Click()
        assert(F.db.settings.minROI==0.35 and F.db.settings.spendShare==0.5)
        UI.preset_balanced:Click();assert(F.db.settings.minROI==0.2 and F.db.settings.minProfit==100)''')


if __name__ == '__main__':
    unittest.main()
