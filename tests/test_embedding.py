import unittest
from test_ui import ui_runtime
from test_controller import controller_runtime
from test_domain import ROOT


class EmbeddingTests(unittest.TestCase):
    def test_content_is_bounded_inside_auction_frame_without_detached_controls(self):
        ui_runtime().execute('''local point,parent,relative,x,y=u.frame:GetPoint(1)
        assert(point=='TOPLEFT' and parent==AuctionHouseFrame and x==4 and y==-34)
        local p,a,r,dx,dy=u.frame:GetPoint(2)
        assert(p=='BOTTOMRIGHT' and a==AuctionHouseFrame and dx==-4 and dy==28)
        assert(not u.frame.movable and not u.frame.resizable and u.frame.strata~='HIGH')
        assert(u.canvas and u.canvas:GetParent()==u.frame and not u.canvas.scripts.OnDragStart)''')
    def test_logical_canvas_fits_native_dimensions_and_ignores_old_window_size(self):
        ui_runtime().execute('''db.ui.width=1600;db.ui.height=1000
        AuctionHouseFrame:SetSize(800,538);u:layout()
        assert(u.canvas:GetWidth()*u.canvas:GetScale()<=792.01)
        assert(u.canvas:GetHeight()*u.canvas:GetScale()<=476.01)
        AuctionHouseFrame:SetSize(1000,700);u:layout()
        assert(u.canvas:GetWidth()*u.canvas:GetScale()<=992.01)''')
    def test_selecting_library_tab_keeps_canvas_visible_and_switching_hides_root(self):
        l=controller_runtime()
        l.execute((ROOT/'tests/wow_mock.lua').read_text())
        l.execute('''lib={DoesIDExist=function()return false end,
          CreateTab=function(self,id,f)self.content=f;f:Hide()end,
          SetSelected=function(self,id)self.selected=id;self.content:Show()end}
          LibStub=function(name)if name=='LibAHTab-1-0'then return lib end end''')
        for module in ['UI','Core']:l.execute((ROOT/'ForeverFlip'/(module+'.lua')).read_text(encoding='utf-8-sig'))
        l.execute('''ForeverFlip.boot('ForeverFlip');ForeverFlip.attach()
        SlashCmdList.FOREVERFLIP('');local u=ForeverFlip.ui
        assert(lib.selected=='ForeverFlip' and u.frame:IsShown() and u.canvas:IsShown())
        lib.content:Hide();assert(not u.frame:IsShown())''')
    def test_fallback_selects_native_empty_display_before_showing_content(self):
        l=controller_runtime();l.execute((ROOT/'tests/wow_mock.lua').read_text())
        l.execute('''LibStub=nil;AuctionHouseFrame.Tabs={CreateFrame('Button',nil,AuctionHouseFrame)}
        AuctionHouseFrame.SetDisplayMode=function(self,mode)self.lastMode=mode end''')
        for module in ['UI','Core']:l.execute((ROOT/'ForeverFlip'/(module+'.lua')).read_text(encoding='utf-8-sig'))
        l.execute('''ForeverFlip.boot('ForeverFlip');ForeverFlip.attach();ForeverFlip.entry:Click()
        assert(type(AuctionHouseFrame.lastMode)=='table' and #AuctionHouseFrame.lastMode==0)
        assert(ForeverFlip.ui.frame:IsShown())''')

if __name__=='__main__':unittest.main()
