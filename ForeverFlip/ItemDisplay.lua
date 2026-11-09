local F = ForeverFlip
local U = F.Util
local D = { requested = {}, requestCount = 0 }
F.ItemDisplay = D
local function L(source, en)
    return en or source
end
local function validLink(key, link)
    if type(link) ~= "string" then
        return nil
    end
    local id = tonumber(link:match("|Hitem:(%d+)") or link:match("^item:(%d+)"))
    if id == key.itemID then
        return link
    end
    local species = tonumber(link:match("|Hbattlepet:(%d+)") or link:match("^battlepet:(%d+)"))
    if species and species == key.battlePetSpeciesID then
        return link
    end
end
function D.metadata(key, link, family)
    local id = key.itemID
    link = validLink(key, link)
    local name, cachedLink, quality, icon
    local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    if getInfo then
        local ok, n, l, q, _, _, _, _, _, _, tex = pcall(getInfo, link or id)
        if ok then
            name = n
            cachedLink = l
            quality = q
            icon = tex
        end
    end
    local base = not family
        and (key.itemLevel or 0) == 0
        and (key.itemSuffix or 0) == 0
        and (key.battlePetSpeciesID or 0) == 0
    if not link and base then
        link = validLink(key, cachedLink)
    end
    if C_AuctionHouse and C_AuctionHouse.GetItemKeyInfo then
        local ok, info = pcall(C_AuctionHouse.GetItemKeyInfo, key)
        if ok and info then
            name = name or info.itemName
            icon = icon or info.iconFileID
        end
    end
    if not icon and C_Item and C_Item.GetItemIconByID then
        icon = C_Item.GetItemIconByID(id)
    end
    if
        not cachedLink
        and C_Item
        and C_Item.RequestLoadItemDataByID
        and not D.requested[id]
        and D.requestCount < 500
    then
        D.requested[id] = true
        D.requestCount = D.requestCount + 1
        C_Item.RequestLoadItemDataByID(id)
    end
    return {
        key = key,
        name = name or ("Item " .. tostring(id)),
        link = link,
        quality = quality,
        icon = icon or 134400,
        exact = not not (link or base),
        base = base,
    }
end
function D.money(value)
    if not U.finite(value) then
        return "-"
    end
    if GetMoneyString then
        local prefix = value < 0 and "-" or ""
        if value % 1 ~= 0 then
            prefix = "~" .. prefix
        end
        return prefix .. GetMoneyString(math.floor(math.abs(value) + 0.5), true)
    end
    return U.money(value)
end
local function label(parent, x, y, w, title)
    local f = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    f:SetWidth(w)
    f:SetJustifyH("LEFT")
    f:SetWordWrap(false)
    f:SetText(title or "")
    return f
end
function D.headers(parent, x, y)
    label(parent, x + 40, y, 245, L("Item", "Item"))
    label(parent, x + 292, y, 48, L("Qty", "Qty"))
    label(parent, x + 345, y, 145, L("Unit price", "Unit price"))
    label(parent, x + 500, y, 140, L("Potential P/L", "Potential P/L"))
    label(parent, x + 650, y, 150, L("Route / status", "Route / status"))
end
function D.row(parent, x, y, width, onClick)
    local r = CreateFrame("Button", nil, parent)
    r:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    r:SetSize(width, 30)
    local bg = r:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.12, 0.14, 0.16, 0.8)
    r:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight", "ADD")
    r.qualityBorder = r:CreateTexture(nil, "ARTWORK")
    r.qualityBorder:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.qualityBorder:SetSize(28, 28)
    r.icon = r:CreateTexture(nil, "OVERLAY")
    r.icon:SetPoint("LEFT", r, "LEFT", 6, 0)
    r.icon:SetSize(24, 24)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.itemName = label(r, 40, 9, 245)
    r.quantity = label(r, 292, 9, 48)
    r.price = label(r, 345, 9, 145)
    r.profit = label(r, 500, 9, 140)
    r.detail = label(r, 650, 9, 150)
    r:SetScript("OnEnter", function(row)
        local m = row.metadata
        if not m or not GameTooltip then
            return
        end
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        if m.link then
            GameTooltip:SetHyperlink(m.link)
        elseif m.base and GameTooltip.SetItemByID then
            GameTooltip:SetItemByID(m.key.itemID)
        else
            GameTooltip:AddLine(m.name)
            GameTooltip:AddLine(
                L(
                    "Exact variant tooltip requires an exact search.",
                    "Exact variant tooltip requires an exact search."
                ),
                1,
                0.8,
                0.2,
                true
            )
        end
        if row.note and row.note ~= "" then
            GameTooltip:AddLine(row.note, 1, 0.8, 0.2, true)
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    r:SetScript("OnHide", function()
        if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == r then
            GameTooltip:Hide()
        end
    end)
    r:SetScript("OnClick", function(row)
        if
            row.metadata
            and row.metadata.link
            and HandleModifiedItemClick
            and HandleModifiedItemClick(row.metadata.link)
        then
            return
        end
        if onClick then
            onClick(row)
        end
    end)
    function r:SetItem(p, note)
        if not p or not p.key then
            self.metadata = nil
            self:Hide()
            return
        end
        local link = p.link or (p.rows and p.rows[1] and p.rows[1].link)
        self.metadata = D.metadata(p.key, link, p.family)
        self.note = note
        local m = self.metadata
        self.icon:SetTexture(m.icon)
        local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[m.quality]
        local red, green, blue = c and c.r or 0.8, c and c.g or 0.8, c and c.b or 0.8
        self.qualityBorder:SetColorTexture(red, green, blue, 1)
        self.itemName:SetTextColor(red, green, blue)
        self.itemName:SetText(m.name)
        self.quantity:SetText(p.qty and p.qty > 0 and p.qty or p.totalQty or 0)
        self.price:SetText(D.money(p.qty and p.qty > 0 and p.cost and p.cost / p.qty or p.minimum))
        self.profit:SetText(D.money(p.profit))
        self.profit:SetTextColor((p.profit or 0) < 0 and 1 or 0.4, (p.profit or 0) < 0 and 0.3 or 1, 0.4)
        self.detail:SetText((p.mode == "vendor" and "NPC" or "AH") .. " " .. (note or ""))
        self:Show()
    end
    return r
end
