"""Sharing full scans, key bindings in the settings, statistics display."""

import unittest

from test_addon import SETUP, run

SHARE = SETUP + '''local F=ForeverFlip
local Sh=F.Share
sentMessages={}
C_ChatInfo={RegisterAddonMessagePrefix=function() end,
  SendAddonMessage=function(prefix,text,channel,target) sentMessages[#sentMessages+1]={prefix,text,channel,target} end}
function IsInGuild() return true end
function IsInGroup() return true end
fullScan()
'''


class ShareTests(unittest.TestCase):
    def test_encode_and_decode_keep_every_item(self):
        run(SHARE + '''local snap=Sh.snapshot();assert(snap and #snap.items>0)
        local back=Sh.decode(Sh.encode(snap));assert(back.scope==snap.scope and back.at==snap.at and #back.items==#snap.items)
        for i,it in ipairs(snap.items) do
            local b=back.items[i];assert(b.key==it.key and b.m==math.floor(it.m) and b.n==it.n,it.key)
        end''')

    def test_gear_names_with_separators_survive(self):
        run(SHARE + '''local snap={scope='Realm-Alliance',at=now,items={{key='g:20:odd, name;x|y%',m=1000,min=900,n=2}}}
        local back=Sh.decode(Sh.encode(snap));assert(back.items[1].key=='g:20:odd, name;x|y%')''')

    def test_sending_paces_messages_and_receiving_merges(self):
        run(SHARE + '''assert(Sh.send('GUILD'));local n=#Sh.outbox;assert(n>=1)
        run(0.1);assert(#sentMessages==1);run(n*0.35+0.5);assert(#sentMessages==n and #Sh.outbox==0)
        -- another player of the realm receives it a day later
        now=now+86400;local at=Sh.decode(table.concat((function()
            local parts={} for _,m in ipairs(sentMessages) do parts[#parts+1]=m[2]:match('^%w+:%w+:%w+:(.*)$') end return parts end)())).at
        F.Scan.last=nil
        for _,m in ipairs(sentMessages) do Sh.onMessage('ForeverFlip',m[2],'GUILD','Friend-Realm') end
        local h=F.Data.market(F.db,F.Engine.scope()).history['c:10']
        assert(h.shared and h.shared.from=='Friend-Realm' and h.shared.at==at,'merged')
        assert(#Sh.received==1 and Sh.received[1].items>0)''')

    def test_newer_shared_price_becomes_the_usual_price(self):
        run(SHARE + '''local h=F.Data.market(F.db,F.Engine.scope()).history['c:10']
        local own=h.scan.market
        local merged=Sh.merge({scope=F.Engine.scope(),at=now+300,items={{key='c:10',m=own*2,min=50,n=30}}},'Friend','GUILD')
        assert(merged==1);local usual,at,from=F.Market.usual(h);assert(usual==own*2 and from=='Friend')
        assert(h.days[#h.days].min==50,'the day record takes the lower price')''')

    def test_rejects_duplicates_other_realms_and_old_scans(self):
        run(SHARE + '''local items={{key='c:10',m=100,min=90,n=5}}
        local _,why=Sh.merge({scope='Other-Alliance',at=now,items=items},'X');assert(why=='other_realm')
        _,why=Sh.merge({scope='Realm-Alliance',at=now-8*86400,items=items},'X');assert(why=='old')
        _,why=Sh.merge({scope='Realm-Alliance',at=F.Scan.last.at,items=items},'X');assert(why=='duplicate','own scan')
        assert(Sh.merge({scope='Realm-Alliance',at=now+300,items=items},'X')==1)
        _,why=Sh.merge({scope='Realm-Alliance',at=now+300,items=items},'X');assert(why=='duplicate')
        _,why=Sh.merge({scope='Realm-Alliance',at=now+3600,items=items},'X');assert(why=='old','a scan from the future')''')

    def test_own_messages_and_disabled_receiving_are_ignored(self):
        run(SHARE + '''Sh.send('GUILD');run(5)
        for _,m in ipairs(sentMessages) do Sh.onMessage('ForeverFlip',m[2],'GUILD','Me') end
        assert(#Sh.received==0)
        F.db.settings.shareReceive=false
        for _,m in ipairs(sentMessages) do Sh.onMessage('ForeverFlip',m[2],'GUILD','Friend') end
        assert(#Sh.received==0)''')

    def test_import_text(self):
        run(SHARE + '''local text=Sh.encode({scope='Realm-Alliance',at=now+600,items={{key='i:30',m=31000,min=30000,n=3}}})
        assert(Sh.import(text)==1);local _,why=Sh.import('hello');assert(why=='share_invalid')''')

    def test_auto_share_after_a_scan(self):
        run(SHARE + '''F.db.settings.shareAuto=true;now=now+901;F.db.lastScan=0;fullScan()
        assert((#Sh.outbox>0 and Sh.outbox[1].channel=='GUILD') or (sentMessages[1] and sentMessages[1][3]=='GUILD'))''')

    def test_sharing_tab(self):
        run(SHARE + '''local UI=F.UI;UI.show('settings');UI.settingTabs.share:Click()
        assert(UI.settingFrames.share:IsShown() and not UI.settingFrames.general:IsShown())
        UI.shareGuild:Click();assert(#Sh.outbox>0)
        UI.shareExport:Click();assert(UI.exportFrame.box:GetText():sub(1,4)=='FF1|')''')


class KeyTests(unittest.TestCase):
    def test_key_is_captured_and_saved(self):
        run(SETUP + '''local F=ForeverFlip;local UI=F.UI
        bound={};saved=0
        function GetBindingKey(cmd) for k,c in pairs(bound) do if c==cmd then return k end end end
        function SetBinding(key,cmd) bound[key]=cmd end
        function SaveBindings() saved=saved+1 end
        function GetCurrentBindingSet() return 2 end
        function IsShiftKeyDown() return true end
        UI.show('settings');UI.settingTabs.keys:Click()
        UI.keyButtons[1]:Click();assert(UI.capturing=='FOREVERFLIP_BUY')
        UI.onCapturedKey('LSHIFT');assert(UI.capturing,'modifiers alone wait')
        UI.onCapturedKey('B');assert(bound['SHIFT-B']=='FOREVERFLIP_BUY' and saved==1)
        UI.refresh();assert(UI.keyButtons[1]:GetText()=='SHIFT-B')
        UI.keyButtons[1].scripts.OnClick(UI.keyButtons[1],'RightButton');assert(not GetBindingKey('FOREVERFLIP_BUY'))''')


class StatisticsDisplayTests(unittest.TestCase):
    def test_unsold_items_show_dashes(self):
        run(SETUP + '''local F=ForeverFlip;local UI=F.UI;local c=F.Data.char(F.db,F.Engine.owner())
        F.Data.addPosition(c,'i:30','Linen Bag',1,20000,'flip',29900,now)
        UI.show('stats');local r=UI.statsTable.rows[1]
        assert(r.cols[2]:GetText()=='-' and r.cols[4]:GetText()=='-' and r.cols[5]:GetText()=='-')''')


if __name__ == '__main__':
    unittest.main()
