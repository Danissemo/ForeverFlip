import unittest
from test_controller import controller_runtime
from test_domain import ROOT

def ui_runtime():
    lua=controller_runtime()
    lua.execute((ROOT/'tests/wow_mock.lua').read_text())
    path=ROOT/'ForeverFlip/UI.lua'
    assert path.exists(), 'Missing auction-window UI'
    lua.execute(path.read_text(encoding='utf-8-sig'))
    lua.execute('u=ForeverFlip.UI.create(c)')
    return lua

class UITests(unittest.TestCase):
    def test_all_sections_and_profession_modes_open(self):
        l=ui_runtime()
        l.execute('''for _,s in ipairs({'overview','deals','trade','watch','portfolio','history','tools','settings'}) do
        assert(u.sections[s]); u:show(s); u:refresh() end
        assert(u.fields.materials and u.fields.yields and u.fields.vendorCost)''')
    def test_search_uses_entered_id(self):
        ui_runtime().execute('''u.fields.item:SetText('2589'); u.actions.search:Click()
        assert(c.job and c.job.key.itemID==2589 and calls==1)''')
    def test_buy_controls_start_disabled(self):
        ui_runtime().execute('''u:show('trade'); u:refresh()
        assert(not u.actions.buy:IsEnabled() and not u.actions.confirm:IsEnabled())''')
    def test_library_can_show_initialized_default_page(self):
        ui_runtime().execute("assert(u.sections.overview.scroll:IsShown())")
    def test_watchlist_and_rule_group_import(self):
        ui_runtime().execute('''u.fields.item:SetText('2589'); u.actions.watchAdd:Click(); assert(db.watchlist[1]==2589)
        u.fields.exchange:SetText('FFG1|Cloth|2589,2592|30|1|50|10'); u.actions.groupImport:Click()
        assert(#db.groups==1 and db.groups[1].rule.minROI==.30)''')
    def test_profession_calculator_and_save(self):
        ui_runtime().execute('''u.fields.materials:SetText('2589*3@0.01'); u.fields.outputQty:SetText('2'); u.fields.outputPrice:SetText('1')
        u.fields.recipeName:SetText('test'); u.actions.craftCalc:Click(); u.actions.recipeSave:Click()
        assert(u.toolResult.complete and u.toolResult.cost==300 and db.recipes.test)''')
    def test_settings_invalidate_quoted_plan(self):
        ui_runtime().execute('''c:search({itemID=1}); c:event('COMMODITY_SEARCH_RESULTS_UPDATED',1); c:requestBuy()
        u.fields.roi:SetText('40'); u.actions.settingsSave:Click(); assert(not c.plan and not c.active and db.settings.minROI==.40)''')

if __name__=='__main__': unittest.main()
