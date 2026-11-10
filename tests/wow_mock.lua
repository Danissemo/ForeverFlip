widgets={}
local methods={}
local meta={__index=function(t,k) return methods[k] or function() end end}
local function widget(kind,name,parent)
    local w=setmetatable({kind=kind,name=name,parent=parent,scripts={},shown=false,enabled=true,text='',width=1000,height=640},meta)
    widgets[#widgets+1]=w; return w
end
function methods:SetScript(k,fn) self.scripts[k]=fn end
function methods:HookScript(k,fn)
    local previous=self.scripts[k]
    self.scripts[k]=function(...)if previous then previous(...)end;fn(...)end
end
function methods:Show() self.shown=true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
function methods:Hide() self.shown=false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
function methods:IsShown() return self.shown end
function methods:IsVisible()
    if not self.shown then return false end
    local parent=rawget(self,'parent')
    return not parent or parent:IsVisible()
end
function methods:SetText(v) self.text=tostring(v or '') end
function methods:GetText() return self.text end
function methods:GetNumber() return tonumber(self.text) or 0 end
function methods:SetEnabled(v) self.enabled=not not v end
function methods:IsEnabled() return self.enabled end
function methods:Enable() self.enabled=true end
function methods:Disable() self.enabled=false end
function methods:SetChecked(v) self.checked=v end
function methods:GetChecked() return self.checked end
function methods:SetSize(w,h) self.width=w; self.height=h end
function methods:SetWidth(w) self.width=w end
function methods:SetHeight(h) self.height=h end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:GetFrameLevel() return 1 end
function methods:GetStringHeight() return 30 end
function methods:GetVerticalScrollRange() return 300 end
function methods:CreateFontString() return widget('FontString',nil,self) end
function methods:CreateTexture() return widget('Texture',nil,self) end
function methods:CreateLine() return widget('Line',nil,self) end
function methods:GetParent() return self.parent end
function methods:SetParent(p) self.parent=p end
function methods:SetPoint(...) self.points=rawget(self,'points') or {};table.insert(self.points,{...}) end
function methods:ClearAllPoints() self.points={} end
function methods:GetPoint(i) local p=rawget(self,'points') and self.points[i or 1];if p then return unpack(p)end;return 'TOPLEFT',nil,'TOPLEFT',0,0 end
function methods:SetScale(s) self.scale=s end
function methods:GetScale() return rawget(self,'scale') or 1 end
function methods:SetMovable(v) self.movable=v end
function methods:SetResizable(v) self.resizable=v end
function methods:SetFrameStrata(v) self.strata=v end
function methods:Click()
    if STRICT_MOCK_CLICKS and not self:IsVisible()then return end
    if self.enabled and self.scripts.OnClick then self.scripts.OnClick(self) end
end
function CreateFrame(kind,name,parent,template) local w=widget(kind,name,parent);w.template=template or '';return w end
function GetLocale() return 'enUS' end
function GetTime() return now end
function date(fmt,t) return os.date(fmt,t) end
function GetMoney() return 100000 end
function GetRealmName() return 'Test' end
function UnitFactionGroup() return 'Alliance' end
function UnitGUID() return 'Player-1' end
function InCombatLockdown() return false end
function GetItemInfo(id) return 'Item '..tostring(id),nil,1,1,1,nil,nil,20,nil,nil,1000 end
UIParent=widget('Frame','UIParent'); AuctionHouseFrame=widget('Frame','AuctionHouseFrame'); AuctionHouseFrame.Tabs={}; AuctionHouseFrame:Show()
GameTooltip=widget('Frame','GameTooltip'); SlashCmdList={}; UISpecialFrames={}
SOUNDKIT={}; C_Timer={After=function(_,fn) fn() end}
