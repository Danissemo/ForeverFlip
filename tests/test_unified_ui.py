import unittest
from test_ui import ui_runtime
from test_controller import controller_runtime
from test_domain import ROOT


class UnifiedUITests(unittest.TestCase):
    def test_one_set_of_seven_aligned_tabs_without_modes(self):
        ui_runtime().execute('''AuctionHouseFrame:SetSize(800,538);u:layout()
        assert(u.nativeLayout.controls_.mode==nil and u.nav.history==nil and u.nav.watch==nil)
        local y,last
        for _,id in ipairs({'overview','deals','trade','portfolio','workbench','tools','settings'})do
          local tab=u.nav[id];assert(tab:IsShown())
          local p,a,r,x,dy=tab:GetPoint();if y then assert(y==dy and x>last)else y=dy end;last=x
        end
        assert(7*u.nav.overview.ffNativeWidth+6<=792-70)
        assert(not u.actions.quickPlan:IsShown())
        u:show('history');assert(u.nav.workbench and u.section=='history')''')

    def test_every_tab_is_a_split_page_whose_controls_fit_without_scrolling(self):
        ui_runtime().execute('''AuctionHouseFrame:SetSize(800,538);u:layout();local bad={}
        for _,id in ipairs({'overview','trade','portfolio','workbench','watch','history','tools','settings'})do
          local split=u.sections[id].split;assert(split and #split.rows>0 and not u.sections[id].viewport:IsShown(),id)
          for pid,page in pairs(split.pages)do
            for _,e in ipairs(u.nativeLayout.controls)do
              if e.parent==page and (e.widget.kind=='Button' or e.widget.kind=='EditBox') then
                if e.y+(e.height or 24)>345 then bad[#bad+1]=id..'/'..pid..' y='..e.y..' '..tostring(e.widget.text) end
              end
            end
          end
        end
        assert(#bad==0,table.concat(bad,'; '))''')

    def test_category_list_switches_pages_and_links_analytics_sections(self):
        ui_runtime().execute('''u:show('settings')
        local split=u.sections.settings.split;assert(u.pages.settings=='main' and split.pages.main:IsShown())
        split.rows[2]:Click();assert(u.pages.settings=='rules' and split.pages.rules:IsShown() and not split.pages.main:IsShown())
        assert(split.rows[2].selected:IsShown() and not split.rows[1].selected:IsShown())
        assert(u.actions.settingsSaveRules:GetParent()==split.pages.rules)
        u:show('settings');assert(u.pages.settings=='rules')
        local a=u.sections.workbench.split;a.rows[8]:Click();assert(u.section=='history' and u.pages.history=='chart')
        assert(u.sections.history.split.rows[8].selected:IsShown())
        u.sections.history.split.rows[6]:Click();assert(u.section=='watch' and u.pages.watch=='list')
        assert(u.fields.removeWatch:GetParent()==u.sections.watch.split.pages.list)''')

    def test_guide_buttons_route_without_spending(self):
        ui_runtime().execute('''u.actions.guideNPC:Click()
        assert(u.section=='deals' and u.liveOnly and u.filterMode=='vendor' and u.sort=='profit')
        assert(spent==0 and quoted==0)
        u:show('overview');u.actions.guideSell:Click();assert(u.section=='portfolio')
        u:show('overview');u.actions.guideScan:Click();assert(u.section=='deals' and spent==0)''')

    def test_language_buttons_save_choice_and_reload(self):
        l=controller_runtime()
        l.execute((ROOT/'tests/wow_mock.lua').read_text())
        for name in ['UI','Core']:l.execute((ROOT/'ForeverFlip'/(name+'.lua')).read_text(encoding='utf-8-sig'))
        l.execute('''reloads=0;C_UI={Reload=function()reloads=reloads+1 end}
        ForeverFlip.boot('ForeverFlip');ForeverFlip.attach()
        local u=ForeverFlip.ui;local ctl=u.nativeLayout.controls_
        ctl.ua:Click();assert(ForeverFlip.db.ui.language=='ukUA' and reloads==1)
        ForeverFlip.NativeLayout.labels(u);assert(not ctl.ua:IsEnabled() and ctl.en:IsEnabled())
        ctl.en:Click();assert(ForeverFlip.db.ui.language=='enUS' and reloads==2)
        ForeverFlip.NativeLayout.labels(u);assert(ctl.ua:IsEnabled() and not ctl.en:IsEnabled())
        u.actions.languageauto:Click();assert(ForeverFlip.db.ui.language==nil and reloads==3)
        assert(ForeverFlip.db.settings.fee==.05)''')

    def test_auction_page_has_native_list_and_actionable_empty_state(self):
        ui_runtime().execute('''c.candidates={};u:show('deals')
        local st=u.shopping;assert(st.leftArt and st.rightArt and st.empty.title:IsShown())
        assert(u.actions.emptyStart:IsShown() and u.actions.emptyScan:IsShown())
        assert(st.listRows[1].selected and not st.listRows[1].selected:IsShown())
        assert(u.actions.filterMode:GetText()~='NPC' and u.sort=='profit')
        u.actions.emptyStart:Click();assert(u.liveOnly and c.smallNPCActive and spent==0)
        assert(st.listRows[1].selected:IsShown() and not u.actions.emptyStart:IsShown())''')


if __name__ == '__main__':
    unittest.main()
