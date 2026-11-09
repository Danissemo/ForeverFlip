local ADDON=... or 'ForeverFlip'
local F=ForeverFlip
local frame=CreateFrame('Frame');F.eventFrame=frame
function F.boot(name)
    if name~=ADDON or F.controller then return end
    local db,backup=F.Store.open(ForeverFlipDB)
    if F.Store.writable(db) then
        if backup and not ForeverFlipLegacyDB then ForeverFlipLegacyDB=backup end
        ForeverFlipDB=db
    end
    F.db=db
    F.controller=F.Controller.new(db,F.Adapters.native(db))
    F.controller.alert=function(message)
        print('|cff6dd7bdForeverFlip|r · '..message)
        if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.READY_CHECK or 8960,'Master')end
    end
    local c=F.controller
    c.changed=function()
        if F.ui and F.ui.frame:IsShown()then F.ui:refresh()end
    end
    local elapsed,paint=0,0
    frame:SetScript('OnUpdate',function(_,dt)
        elapsed=elapsed+dt;paint=paint+dt
        if elapsed>=.05 then elapsed=0;c:tick()end
        if paint>=1 then
            paint=0
            if F.ui and F.ui.frame:IsShown()and F.ui.section=='trade'then F.ui:refresh()end
        end
    end)
    print('|cff6dd7bdForeverFlip 5|r · /ff · PREVIEW · '..('Open from the auction window. Legacy data retained.'))
end
function F.attach()
    if not F.controller or not AuctionHouseFrame then return end
    if not F.ui then
        -- Unsupported future data stays untouched; only a read-only message is shown.
        if not F.Store.writable(F.db)then
            print('ForeverFlip: unsupported SavedVariables schema; restore a supported backup.');return
        end
        F.ui=F.UI.create(F.controller)
    end
    if not F.entry then
        local attached=false
        if LibStub then
            local ok,lib=pcall(function()return LibStub('LibAHTab',true)end)
            if ok and lib and lib.CreateTab then
                local made=pcall(function()
                    if not lib:DoesIDExist('ForeverFlip')then lib:CreateTab('ForeverFlip',F.ui.frame,'ForeverFlip','ForeverFlip 5')end
                end)
                if made then F.tabLibrary=lib;F.entry=lib;attached=true end
            end
        end
        if not attached then
            local b=CreateFrame('Button',nil,AuctionHouseFrame,'UIPanelButtonTemplate')
            b:SetSize(125,25);b:SetPoint('TOPRIGHT',AuctionHouseFrame,'TOPRIGHT',-45,-8);b:SetText('ForeverFlip 5')
            b:SetScript('OnClick',function()F.ui:show(F.db.ui.section or 'overview')end);F.entry=b
        end
    end
end
frame:RegisterEvent('ADDON_LOADED')
for _,event in ipairs({'AUCTION_HOUSE_SHOW','AUCTION_HOUSE_CLOSED','COMMODITY_SEARCH_RESULTS_UPDATED',
    'COMMODITY_SEARCH_RESULTS_ADDED','ITEM_SEARCH_RESULTS_UPDATED','ITEM_SEARCH_RESULTS_ADDED',
    'COMMODITY_PRICE_UPDATED','COMMODITY_PRICE_UNAVAILABLE','COMMODITY_PURCHASED',
    'COMMODITY_PURCHASE_FAILED','ITEM_PURCHASED','REPLICATE_ITEM_LIST_UPDATE','MAIL_INBOX_UPDATE'})do frame:RegisterEvent(event)end
frame:SetScript('OnEvent',function(_,event,...)
    if event=='ADDON_LOADED'then F.boot(...);return end
    if not F.controller then return end
    if event=='AUCTION_HOUSE_SHOW'then
        if C_Timer then C_Timer.After(0,F.attach)else F.attach()end
    else F.controller:event(event,...) end
    if event=='AUCTION_HOUSE_CLOSED'and F.ui then F.ui.frame:Hide()end
end)
SLASH_FOREVERFLIP1='/ff';SLASH_FOREVERFLIP2='/foreverflip'
SlashCmdList.FOREVERFLIP=function(message)
    if not F.controller then return end
    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown()then print('ForeverFlip: '..('Open an auction house first.'));return end
    F.attach();if not F.ui then return end
    local id=tonumber(message)
    if id then F.ui.fields.item:SetText(tostring(id))end
    F.ui:show(id and 'trade' or F.db.ui.section or 'overview')
    if F.tabLibrary and F.tabLibrary.SetSelected then pcall(function()F.tabLibrary:SetSelected('ForeverFlip')end)end
end
