local ADDON = ... or "ForeverFlip"
local F = ForeverFlip
local frame = CreateFrame("Frame")
F.eventFrame = frame
function F.boot(name)
    if name ~= ADDON or F.controller then
        return
    end
    local db, backup = F.Store.open(ForeverFlipDB)
    if F.Store.writable(db) then
        if backup and not ForeverFlipLegacyDB then
            ForeverFlipLegacyDB = backup
        end
        ForeverFlipDB = db
    end
    F.db = db
    F.controller = F.Controller.new(db, F.Adapters.native(db))
    F.controller.alert = function(message)
        print("|cff6dd7bdForeverFlip|r · " .. message)
        if PlaySound and SOUNDKIT then
            PlaySound(SOUNDKIT.READY_CHECK or 8960, "Master")
        end
    end
    local c = F.controller
    c.changed = function()
        if F.ui and F.ui.frame:IsShown() then
            F.ui:refresh()
        end
    end
    local elapsed, paint = 0, 0
    frame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        paint = paint + dt
        if elapsed >= 0.05 then
            elapsed = 0
            c:tick()
        end
        if paint >= 1 then
            paint = 0
            if F.ui and F.ui.frame:IsShown() and (F.ui.section == "trade" or F.itemDataDirty) then
                F.itemDataDirty = false
                F.ui:refresh()
            end
        end
    end)
    print(
        "|cff6dd7bdForeverFlip 5|r · /ff · PREVIEW · "
            .. (
                "Open from the auction window. Legacy data retained."
            )
    )
end
function F.attach()
    if not F.controller or not AuctionHouseFrame then
        return
    end
    if not F.ui then
        -- Unsupported future data stays untouched; only a read-only message is shown.
        if not F.Store.writable(F.db) then
            print("ForeverFlip: unsupported SavedVariables schema; restore a supported backup.")
            return
        end
        F.ui = F.UI.create(F.controller)
    end
    if not F.entry then
        local attached = false
        if LibStub then
            local ok, lib = pcall(function()
                return LibStub("LibAHTab-1-0", true) or LibStub("LibAHTab", true)
            end)
            if ok and lib and lib.CreateTab then
                local made = pcall(function()
                    if not lib:DoesIDExist("ForeverFlip") then
                        lib:CreateTab("ForeverFlip", F.ui.frame, "ForeverFlip", "ForeverFlip 5")
                    end
                end)
                if made then
                    F.tabLibrary = lib
                    F.entry = lib
                    attached = true
                end
            end
        end
        if not attached then
            local b = CreateFrame("Button", nil, AuctionHouseFrame, "AuctionHouseFrameDisplayModeTabTemplate")
            b:SetText("ForeverFlip")
            if PanelTemplates_TabResize then
                PanelTemplates_TabResize(b, 20, nil, 70)
            end
            local tabs = AuctionHouseFrame.Tabs
            if tabs and #tabs > 0 then
                b:SetPoint("TOPLEFT", tabs[#tabs], "TOPRIGHT", 3, 0)
            else
                b:SetPoint("TOPLEFT", AuctionHouseFrame, "BOTTOMLEFT", 20, 0)
            end
            b:SetScript("OnClick", function()
                F.open(F.db.ui.section or "overview")
            end)
            if hooksecurefunc then
                hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", function(_, mode)
                    if type(mode) == "table" and #mode > 0 then
                        F.ui.frame:Hide()
                        if PanelTemplates_DeselectTab then
                            PanelTemplates_DeselectTab(b)
                        end
                    end
                end)
            end
            F.entry = b
        end
    end
end
function F.open(section)
    F.attach()
    if not F.ui then
        return
    end
    if F.tabLibrary then
        local ok = pcall(function()
            F.tabLibrary:SetSelected("ForeverFlip")
        end)
        if not ok then
            F.controller:notify("tab_error")
            return
        end
    else
        AuctionHouseFrame:SetDisplayMode({})
        AuctionHouseFrame.displayMode = nil
        if PanelTemplates_DeselectTab then
            for _, tab in ipairs(AuctionHouseFrame.Tabs or {}) do
                PanelTemplates_DeselectTab(tab)
            end
        end
        if PanelTemplates_SelectTab then
            PanelTemplates_SelectTab(F.entry)
        end
        AuctionHouseFrame:SetTitle("ForeverFlip")
    end
    F.ui:show(section or F.db.ui.section or "overview")
end
frame:RegisterEvent("ADDON_LOADED")
for _, event in ipairs({
    "GET_ITEM_INFO_RECEIVED",
    "AUCTION_HOUSE_SHOW",
    "AUCTION_HOUSE_CLOSED",
    "COMMODITY_SEARCH_RESULTS_UPDATED",
    "COMMODITY_SEARCH_RESULTS_ADDED",
    "ITEM_SEARCH_RESULTS_UPDATED",
    "ITEM_SEARCH_RESULTS_ADDED",
    "COMMODITY_PRICE_UPDATED",
    "COMMODITY_PRICE_UNAVAILABLE",
    "COMMODITY_PURCHASED",
    "COMMODITY_PURCHASE_FAILED",
    "ITEM_PURCHASED",
    "REPLICATE_ITEM_LIST_UPDATE",
    "MAIL_INBOX_UPDATE",
}) do
    frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        F.boot(...)
        return
    end
    if not F.controller then
        return
    end
    if event == "GET_ITEM_INFO_RECEIVED" then
        F.itemDataDirty = true
        return
    end
    if event == "AUCTION_HOUSE_SHOW" then
        if C_Timer then
            C_Timer.After(0, F.attach)
        else
            F.attach()
        end
    else
        F.controller:event(event, ...)
    end
    if event == "AUCTION_HOUSE_CLOSED" and F.ui then
        F.ui.frame:Hide()
    end
end)
SLASH_FOREVERFLIP1 = "/ff"
SLASH_FOREVERFLIP2 = "/foreverflip"
SlashCmdList.FOREVERFLIP = function(message)
    if not F.controller then
        return
    end
    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
        print(
            "ForeverFlip: "
                .. (
                    "Open an auction house first."
                )
        )
        return
    end
    F.attach()
    if not F.ui then
        return
    end
    local id = tonumber(message)
    if id then
        F.ui.fields.item:SetText(tostring(id))
    end
    F.open(id and "trade" or F.db.ui.section or "overview")
end
