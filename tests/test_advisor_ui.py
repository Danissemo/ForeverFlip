import unittest
from test_ui import ui_runtime


class AdvisorUITests(unittest.TestCase):
    def test_quick_plan_uses_defaults_without_money_fields(self):
        ui_runtime().execute('''c.candidates={{key={itemID=1},rows=rows,at=now,scope='scope',family=false,kind='commodity'}}
        u.actions.easyBuild:Click();assert(u.allocation.profile=='balanced' and #u.allocation.lines==1)
        assert(u.section=='workbench' and u.pages.workbench=='pick' and spent==0 and quoted==0)''')
    def test_clickable_recommendation_opens_fresh_search_without_index(self):
        ui_runtime().execute('''c.candidates={{key={itemID=1},rows=rows,at=now,scope='scope',family=false,kind='commodity'}}
        u.actions.easyBuild:Click();u.actions.adviceRow1:Click()
        assert(c.job and c.key.itemID==1 and u.section=='trade' and spent==0 and quoted==0)''')
    def test_advice_pagination_exposes_all_rows(self):
        ui_runtime().execute('''u.allocation={budget=1000,cost=9,profit=18,stressed=18,loss=0,lines={}}
        for i=1,9 do u.allocation.lines[i]={key={itemID=i},qty=1,cost=1,profit=2,mode='vendor'}end
        u:show('workbench');u.actions.adviceNext:Click();u.actions.adviceRow1:Click()
        assert(c.key.itemID==9 and spent==0)''')
    def test_advanced_controls_optional_and_manual_mode_clears_advisor(self):
        ui_runtime().execute('''u:show('workbench','manual');assert(u.sections.workbench.split.pages.manual:IsShown() and u.advancedPlan:GetParent()==u.sections.workbench.split.pages.manual)
        c.advisorProfile='safe';u.actions.planBuild:Click();assert(not c.advisorProfile)''')
    def test_busy_or_readonly_advice_does_not_replace_existing_plan(self):
        ui_runtime().execute('''u.allocation={marker=1};c:search({itemID=1});u.actions.easyBuild:Click()
        assert(c.job and u.allocation.marker==1 and not c.advisorProfile)''')
    def test_conservative_profile_is_explicit_and_remembered_as_ui_preference(self):
        ui_runtime().execute('''u.actions.easySafe:Click();assert(c.advisorProfile=='safe' and db.ui.advisorProfile=='safe')
        assert(db.settings.maxWallet==.1 and spent==0)''')
    def test_new_formula_sources_can_be_saved_and_missing_data_stays_unknown(self):
        ui_runtime().execute('''u.fields.sellFormula:SetText('min(ewma, pricefloor)')
        u.actions.settingsSave:Click();assert(db.settings.sellFormula=='min(ewma, pricefloor)')
        assert(ForeverFlip.Expr.eval('pricefloor',{})==nil)''')

if __name__=='__main__':unittest.main()
