import unittest
from test_ui import ui_runtime


class NativeLayoutTests(unittest.TestCase):
    def test_primary_navigation_is_native_horizontal_tabs_without_global_scale(self):
        ui_runtime().execute('''assert(u.nativeLayout)
        AuctionHouseFrame:SetSize(800,538);u:layout()
        assert(u.canvas:GetScale()==1 and u.canvas:GetWidth()==792)
        local y
        for _,id in ipairs({'deals','trade','portfolio','history','tools','settings','overview'})do
          local tab=u.nav[id];assert(tab.template=='PanelTopTabButtonTemplate')
          local p,a,r,x,dy=tab:GetPoint();if y then assert(y==dy)else y=dy end
        end
        assert(u.section=='deals')''')
    def test_shopping_has_native_split_panes_and_price_first_headers(self):
        ui_runtime().execute('''u:show('deals');u:layout()
        assert(u.shopping.left.template=='InsetFrameTemplate' and u.shopping.right.template=='InsetFrameTemplate')
        assert(u.shopping.left:GetWidth()>=220 and u.shopping.right:GetWidth()>400)
        assert(u.shopping.headers.price.template=='AuctionHouseTableHeaderStringTemplate')
        local p,a,r,priceX=u.shopping.headers.price:GetPoint()
        local p2,b,r2,nameX=u.shopping.headers.itemName:GetPoint();assert(priceX<nameX)
        assert(u.nav.workbench and u.nav.watch)''')
    def test_resize_changes_column_width_without_scaling_fonts(self):
        ui_runtime().execute('''AuctionHouseFrame:SetSize(800,538);u:layout()
        local small=u.shopping.right:GetWidth()
        AuctionHouseFrame:SetSize(1100,700);u:layout()
        assert(u.shopping.right:GetWidth()>small and u.canvas:GetScale()==1)
        for _,r in ipairs(u.dealRows)do assert(r:GetWidth()<=u.shopping.right:GetWidth())end''')
    def test_native_row_click_keeps_exact_search_and_no_purchase(self):
        ui_runtime().execute('''c.candidates={{key={itemID=1},rows=rows,at=now,scope='scope',family=false,kind='commodity'}}
        u:show('deals');u.dealRows[1]:Click()
        assert(c.job and c.key.itemID==1 and spent==0 and quoted==0 and u.section=='trade')''')
    def test_native_list_selection_filters_groups_without_spending(self):
        ui_runtime().execute('''db.groups={{name='Cloth',items={[1]=true},rule={}}}
        c.candidates={{key={itemID=1},rows=rows,at=now,scope='scope',family=false,kind='commodity'},
          {key={itemID=2},rows=rows,at=now,scope='scope',family=false,kind='commodity'}}
        u:show('deals');u.shopping.listRows[3]:Click()
        assert(#u.visibleDeals==1 and u.visibleDeals[1].key.itemID==1 and spent==0)''')
    def test_history_chart_and_latest_point_fit_the_actual_native_width(self):
        ui_runtime().execute('''AuctionHouseFrame:SetSize(800,538);u:layout()
        u.chart.CreateLine=function()
          return {Hide=function()end,Show=function()end,SetThickness=function()end,SetColorTexture=function()end,
            SetStartPoint=function()end,SetEndPoint=function(_,point,region,x,y)assert(x<region:GetWidth())end}
        end
        db.markets.scope={['1:0:0:0']={samples={},days={{day=1,price=100,qty=1},{day=2,price=200,qty=1}}}}
        u.fields.item:SetText('1');u:show('history')
        assert(u.chart:GetWidth()<=u.sections.history.body:GetWidth())''')
    def test_native_tab_onshow_cannot_restore_auto_width_and_overlap_neighbors(self):
        ui_runtime().execute('''local tab=u.nav.deals;tab:SetWidth(500)
        tab.scripts.OnShow(tab);assert(tab:GetWidth()<=110)''')
    def test_selected_ukrainian_tab_restores_supported_font_after_native_selection(self):
        ui_runtime().execute('''GetLocale=function()return 'ukUA'end
        local current='';local fs={SetFont=function(_,path)current=path end}
        u.nav.deals.GetFontString=function()return fs end
        PanelTemplates_SelectTab=function(tab)if tab==u.nav.deals then current='native'end end
        ForeverFlip.NativeLayout.select(u,'deals');assert(current==ForeverFlip.Locale.fontPath)''')

if __name__=='__main__':unittest.main()
