-- ForeverFlip window: merchant window tab.
-- Moved from UI.lua as it was and loaded after it (ForeverFlip.toc); locals of the
-- earlier UI files come through UI.shared.
local UI = ForeverFlip.UI
local S = UI.shared
local F = S.F
local U = S.U
local L = S.L
local text = S.text
local button = S.button
local icon = S.icon

-- Merchant window ----------------------------------------------------------------------------------
-- A ForeverFlip tab beside Merchant and Buyback: what to sell to this merchant (one button sells it
-- all) and what to buy here for the auction house. The Merchant tab gets a button that sells the
-- same list at once.
local MERCHANT_SELL_ROWS, MERCHANT_BUY_ROWS = 5, 4
local MERCHANT_BUY_HEIGHT = 44

-- Sets one line of a buy row: `full` when it fits beside the Buy button, else `short` (a large
-- price ran onto a second line, over the next row).
local function fitLine(fs, full, short)
    fs:SetText(full)
    local room = fs:GetWidth() or 0
    local need = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth() or 0
    if room > 0 and need > room then
        fs:SetText(short)
    end
end

local function merchantRow(parent, y, withButton)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(withButton and 28 or 18)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, y)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(withButton and 22 or 16, withButton and 22 or 16)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.text = text(row, "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(withButton and true or false)
    row.value = text(row, "GameFontHighlightSmall")
    row.value:SetJustifyH("RIGHT")
    if row.EnableMouse then
        row:EnableMouse(true)
    end
    row:SetScript("OnEnter", function(self)
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.bag and GameTooltip.SetBagItem then
            GameTooltip:SetBagItem(self.bag, self.slot)
        elseif self.index and GameTooltip.SetMerchantItem then
            GameTooltip:SetMerchantItem(self.index)
        elseif self.link and GameTooltip.SetHyperlink then
            GameTooltip:SetHyperlink(self.link)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    if withButton then
        row:SetHeight(MERCHANT_BUY_HEIGHT - 2)
        row.icon:SetSize(32, 32)
        row.icon:ClearAllPoints()
        row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
        local frameBorder = row:CreateTexture(nil, "BORDER")
        frameBorder:SetColorTexture(0.55, 0.45, 0.25, 0.8)
        frameBorder:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -1, 1)
        frameBorder:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 1, -1)
        row.buy = button(row, "Buy", 74, function(self)
            local ok, why = F.Merchant.buy(self.offer)
            if not ok and why then
                F.Engine.notify(why)
            end
            UI.merchant(true)
        end)
        row.buy:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -2)
        row.cost = text(row, "GameFontHighlightSmall")
        row.cost:SetPoint("TOP", row.buy, "BOTTOM", 0, -2)
        row.text:ClearAllPoints()
        row.text:SetFontObject(GameFontNormal)
        row.text:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1)
        row.text:SetPoint("RIGHT", row.buy, "LEFT", -6, 0)
        row.text:SetWordWrap(false)
        row.prices = text(row, "GameFontHighlightSmall")
        row.prices:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -1)
        row.prices:SetPoint("RIGHT", row.buy, "LEFT", -6, 0)
        row.prices:SetJustifyH("LEFT")
        row.prices:SetWordWrap(false)
        row.gain = text(row, "GameFontHighlightSmall")
        row.gain:SetPoint("TOPLEFT", row.prices, "BOTTOMLEFT", 0, -1)
        row.gain:SetPoint("RIGHT", row.buy, "LEFT", -6, 0)
        row.gain:SetJustifyH("LEFT")
        row.gain:SetWordWrap(false)
        local line = row:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 0.82, 0, 0.12)
        line:SetHeight(1)
        line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, -2)
        line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, -2)
    else
        row.value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.text:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
    end
    return row
end

-- The sale goes in paced batches (Trade.stepVendor), which prints what really sold at the end.
local function sellAll()
    F.Trade.sellAllToVendor()
    UI.merchant(true)
end

-- Gear goes the same paced way: the chat says what really sold once the sale ends (Trade).
local function sellGear()
    F.Trade.sellUnusableGear()
    UI.merchant(true)
end

-- The merchant's item pages (buttons, page arrows, repair buttons) are drawn above the ForeverFlip
-- view: they are hidden while it is open and shown again when it goes (another tab, the merchant
-- closed); the game's update then hides what its tab does not use.
local MERCHANT_PARTS = {
    "MerchantPrevPageButton",
    "MerchantNextPageButton",
    "MerchantPageText",
    "MerchantRepairItemButton",
    "MerchantRepairAllButton",
    "MerchantGuildBankRepairButton",
    "MerchantRepairText",
    "MerchantBuyBackItem",
    "MerchantSellAllJunkButton",
}
local function merchantPages(show, closing)
    local names = {}
    for i = 1, (MERCHANT_ITEMS_PER_PAGE or 12) do
        names[#names + 1] = "MerchantItem" .. i
    end
    for _, name in ipairs(MERCHANT_PARTS) do
        names[#names + 1] = name
    end
    for _, name in ipairs(names) do
        local f = _G[name]
        if f and f.Hide then
            if show then
                f:Show()
            else
                f:Hide()
            end
        end
    end
    -- The game decides again what its tab shows; a closing merchant needs nothing decided now.
    if show and not closing and MerchantFrame_Update then
        pcall(MerchantFrame_Update)
    end
end

function UI.merchantSelect(on, closing)
    local view, tab = UI.merchantView, UI.merchantTab
    if not view then
        return
    end
    if on then
        merchantPages(false)
    elseif view:IsShown() then
        -- Closing on this tab shows the pages again too: the game's update shows only the item
        -- buttons inside MerchantItem1..10, never those frames, so every later merchant would
        -- open with an empty list.
        merchantPages(true, closing)
    end
    if on then
        view:Show()
    else
        view:Hide()
    end
    if PanelTemplates_SelectTab and PanelTemplates_DeselectTab and tab then
        if on then
            PanelTemplates_SelectTab(tab)
            for i = 1, 2 do
                local t = _G["MerchantFrameTab" .. i]
                if t then
                    PanelTemplates_DeselectTab(t)
                end
            end
        else
            PanelTemplates_DeselectTab(tab)
            local selected = rawget(MerchantFrame, "selectedTab") or 1 -- set by the game's tab code
            for i = 1, 2 do
                local t = _G["MerchantFrameTab" .. i]
                if t then
                    if i == selected then
                        PanelTemplates_SelectTab(t)
                    else
                        PanelTemplates_DeselectTab(t)
                    end
                end
            end
        end
    end
    if not closing then
        UI.merchant(true)
    end
end

local function createMerchantTab()
    local ok, tab = pcall(CreateFrame, "Button", "ForeverFlipMerchantTab", MerchantFrame, "PanelTabButtonTemplate")
    if not ok then
        tab = CreateFrame("Button", "ForeverFlipMerchantTab", MerchantFrame, "CharacterFrameTabButtonTemplate")
    end
    tab:SetText("ForeverFlip")
    local last = _G["MerchantFrameTab2"] or _G["MerchantFrameTab1"]
    if last then
        tab:SetPoint("LEFT", last, "RIGHT", ok and 3 or -16, 0)
    else
        tab:SetPoint("TOPLEFT", MerchantFrame, "BOTTOMLEFT", 180, 2)
    end
    if PanelTemplates_TabResize then
        pcall(PanelTemplates_TabResize, tab, 0)
    end
    if PanelTemplates_DeselectTab then
        PanelTemplates_DeselectTab(tab)
    end
    tab:SetScript("OnClick", function()
        UI.merchantSelect(true)
    end)
    for i = 1, 2 do
        local t = _G["MerchantFrameTab" .. i]
        if t and t.HookScript then
            t:HookScript("OnClick", function()
                UI.merchantSelect(false)
            end)
        end
    end
    UI.merchantTab = tab

    -- The view covers the merchant's item pages while the tab is selected.
    local view = CreateFrame("Frame", nil, MerchantFrame)
    view:SetPoint("TOPLEFT", MerchantFrame, "TOPLEFT", 8, -60)
    view:SetPoint("BOTTOMRIGHT", MerchantFrame, "BOTTOMRIGHT", -8, 30)
    if view.SetFrameLevel and MerchantFrame.GetFrameLevel then
        view:SetFrameLevel((MerchantFrame:GetFrameLevel() or 1) + 30)
    end
    if view.EnableMouse then
        view:EnableMouse(true)
    end
    local bg = view:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.05, 0.04, 0.97)
    view:Hide()
    UI.merchantView = view

    local sellTitle = text(view, "GameFontNormal")
    sellTitle:SetPoint("TOPLEFT", view, "TOPLEFT", 8, -8)
    sellTitle:SetText(L("Sell to this merchant"))
    view.sellRows = {}
    for i = 1, MERCHANT_SELL_ROWS do
        view.sellRows[i] = merchantRow(view, -26 - (i - 1) * 18, false)
    end
    local below = -30 - MERCHANT_SELL_ROWS * 18
    view.sellAll = button(view, "Sell all", 160, sellAll)
    view.sellAll:SetPoint("TOPRIGHT", view, "TOPRIGHT", -8, below)
    -- Gear the class cannot use: its own button (bound pieces are never on the list above).
    view.sellGear = button(view, "Sell gear I can't use", 140, sellGear)
    view.sellGear:SetPoint("TOPLEFT", view, "TOPLEFT", 8, below)
    view.sellNote = text(view, "GameFontDisableSmall")
    view.sellNote:SetJustifyH("LEFT")
    view.sellNote:SetWordWrap(true)
    local line = view:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.25)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", view, "TOPLEFT", 6, below - 28)
    line:SetPoint("TOPRIGHT", view, "TOPRIGHT", -6, below - 28)
    local buyTitle = text(view, "GameFontNormal")
    local buyTop = below - 34
    view.noteBelow = below
    buyTitle:SetPoint("TOPLEFT", view, "TOPLEFT", 8, buyTop)
    buyTitle:SetText(L("Buy here, sell on the auction house"))
    view.buyTitle = buyTitle
    local offers = { rows = {} }
    for i = 1, MERCHANT_BUY_ROWS do
        offers.rows[i] = merchantRow(view, buyTop - 20 - (i - 1) * MERCHANT_BUY_HEIGHT, true)
    end
    view.buyNote = text(view, "GameFontDisableSmall")
    view.buyNote:SetPoint("TOPLEFT", view, "TOPLEFT", 8, buyTop - 24)
    UI.offerPanel = view -- the buy rows (UI.offerPanel.rows)
    view.rows = offers.rows
    -- More offers than rows: the mouse wheel over the buy list scrolls it.
    view.buyOffset = 0
    local function wheel(_, delta)
        view.buyOffset = math.max(0, (view.buyOffset or 0) - delta)
        UI.merchant(true)
    end
    for _, row in ipairs(view.rows) do
        if row.EnableMouseWheel then
            row:EnableMouseWheel(true)
            row:SetScript("OnMouseWheel", wheel)
        end
    end
    view.buyWheel = wheel

    -- The Merchant tab: one button sells the list at once. Gear the class cannot use is sold from
    -- the ForeverFlip tab only: a second button over the game's tabs covered their items.
    UI.merchantButton = button(MerchantFrame, "Sell to vendor", 180, sellAll)
    UI.placeMerchantButton()
    -- The game shows and hides its filter as the merchant's goods change: looked at on our own
    -- button's clock, nothing is hooked on the game's frames.
    local since = 0
    UI.merchantButton:SetScript("OnUpdate", function(_, elapsed)
        since = since + (elapsed or 0)
        if since >= 0.2 then
            since = 0
            UI.placeMerchantButton()
        end
    end)
end

-- Where the Sell to vendor button stands. Its place under the title is where the game puts the
-- class filter of a merchant with class goods (MerchantFrame.FilterDropdown, 152 wide at the top
-- right): over it on Retail the two covered each other. While the filter shows, the button stands
-- above the frame's top edge, where the whole label still fits. The filter is only read.
local placedHigh
function UI.placeMerchantButton()
    local b = UI.merchantButton
    if not b then
        return
    end
    local filter = MerchantFrame and MerchantFrame.FilterDropdown
    local high = type(filter) == "table" and type(filter.IsShown) == "function" and filter:IsShown() == true
    if placedHigh == high then
        return
    end
    placedHigh = high
    b:ClearAllPoints()
    if high then
        b:SetPoint("BOTTOMRIGHT", MerchantFrame, "TOPRIGHT", -8, 2)
    else
        b:SetPoint("TOPRIGHT", MerchantFrame, "TOPRIGHT", -40, -28)
    end
end

function UI.merchantOffers(open)
    -- Part of the ForeverFlip tab (UI.merchant).
    if open then
        UI.merchant(true)
    end
end

function UI.merchant(open)
    if not MerchantFrame then
        return
    end
    if not UI.merchantTab then
        createMerchantTab()
    end
    if not open then
        UI.merchantSelect(false, true)
        UI.merchantButton:Hide()
        return
    end
    local gear = F.Trade.unusableGearList()
    -- One merchant sale at a time: while one goes, the gear button waits for it.
    local selling = F.Trade.sellingToVendor and F.Trade.sellingToVendor()
    local function busy(text)
        return selling and L("Selling...") or text
    end
    UI.merchantView.sellGear:SetText(
        busy(#gear > 0 and string.format(L("Gear I can't use (%d)"), #gear) or L("No unusable gear"))
    )
    UI.merchantView.sellGear:SetEnabled(#gear > 0 and not selling)
    local list = F.Trade.vendorSellList()
    local total = 0
    for _, v in ipairs(list) do
        total = total + v.price
    end
    -- Items a merchant does not buy, though the item data prices them: said on the page, since
    -- they drop out of the list without a word otherwise. Counted by the list's own bag read
    -- (T.vendorRefusedCount), so the merchant page scans the bags once.
    local refused = F.Trade.vendorRefusedCount or 0
    local view = UI.merchantView
    if #list > 0 and not view:IsShown() then
        UI.merchantButton:SetText(string.format(L("Sell to vendor (%d): %s"), #list, U.money(total)))
        if UI.merchantButton.fitWidth then
            UI.merchantButton.fitWidth()
        end
        UI.merchantButton:Show()
    else
        UI.merchantButton:Hide()
    end
    view.sellNote:ClearAllPoints()
    if #list == 0 then
        view.sellNote:SetPoint("TOPLEFT", view, "TOPLEFT", 8, -30)
        view.sellNote:SetPoint("TOPRIGHT", view, "TOPRIGHT", -8, -30)
    end
    for i, row in ipairs(view.sellRows) do
        local v = list[i]
        if v then
            row.icon:SetTexture(icon(v.id))
            row.bag, row.slot = v.bag, v.slot
            local name = v.link and v.link:gsub("|h%[(.-)%]|h", "|h%1|h") or (v.id and U.itemInfo(v.id)) or v.key
            row.text:SetText(name .. (v.count > 1 and (" x" .. v.count) or ""))
            row.value:SetText(U.money(v.price))
            row:Show()
        else
            row:Hide()
        end
    end
    if #list == 0 then
        view.sellNote:SetText(
            L(
                "Nothing to sell here: no item in the bags is worth more to a merchant (hidden items and items with a keep rule are left out)."
            )
        )
    else
        view.sellNote:SetText("")
    end
    if refused > 0 then
        local note = string.format(L("%d item(s) here are not bought by merchants and are left out."), refused)
        -- Retail's GetText gives nil for an empty string.
        local prev = view.sellNote:GetText() or ""
        view.sellNote:SetText(prev ~= "" and (prev .. " " .. note) or note)
    end
    view.sellAll:SetText(
        busy(#list > 0 and string.format(L("Sell all (%d): %s"), #list, U.money(total)) or L("Sell all"))
    )
    view.sellAll:SetEnabled(#list > 0 and not selling)
    local offers = F.Merchant.offers()
    view.buyOffset = math.max(0, math.min(view.buyOffset or 0, #offers - MERCHANT_BUY_ROWS))
    view.buyTitle:SetText(
        L("Buy here, sell on the auction house")
            .. (
                #offers > MERCHANT_BUY_ROWS
                    and string.format(
                        " " .. UI.C.dim .. "(%d-%d / %d)|r",
                        view.buyOffset + 1,
                        view.buyOffset + MERCHANT_BUY_ROWS,
                        #offers
                    )
                or ""
            )
    )
    for i, row in ipairs(view.rows) do
        local o = offers[view.buyOffset + i]
        if o then
            local id = tonumber(o.link and o.link:match("item:(%d+)"))
            row.icon:SetTexture(icon(id or 0))
            row.text:SetText(U.linkName(o.link) or o.name or "?")
            local quality = id and select(3, U.itemInfo(id))
            local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
            if color then
                row.text:SetTextColor(color.r, color.g, color.b)
            else
                row.text:SetTextColor(1, 1, 1)
            end
            local dot = " " .. UI.C.dim .. L("·") .. "|r "
            fitLine(
                row.prices,
                UI.C.soft
                    .. L("Vendor")
                    .. "|r "
                    .. U.money(o.unit)
                    .. dot
                    .. UI.C.soft
                    .. L("AH")
                    .. "|r "
                    .. U.money(o.exit),
                U.money(o.unit) .. " " .. UI.C.dim .. "->|r " .. U.money(o.exit)
            )
            local gain = UI.C.good .. "+" .. U.money(math.floor(o.each)) .. "|r"
            local perDay = string.format("~%.1f/%s", o.perDay, L("day"))
            fitLine(row.gain, gain .. " " .. UI.C.soft .. L("each") .. "|r" .. dot .. perDay, gain .. dot .. perDay)
            row.cost:SetText(L("Cost") .. ": " .. U.money(math.ceil(o.unit * o.qty)))
            row.buy.offer = o
            row.index, row.link = o.index, o.link
            row.buy:SetText(L("Buy") .. " " .. o.qty)
            row:Show()
        else
            row:Hide()
        end
    end
    if #offers == 0 then
        view.buyNote:Show()
    else
        view.buyNote:Hide()
    end
    view.buyNote:SetText(L("Nothing here sells for more on the auction house."))
end
