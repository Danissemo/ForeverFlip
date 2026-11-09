local F = ForeverFlip
local U = F.Util
local D = { requested = {}, requestCount = 0 }
F.ItemDisplay = D
local L = F.Locale.text
local cache, cacheCount = {}, 0
local validLink
local function bucket(id)
    if cacheCount >= 2048 then
        cache, cacheCount = {}, 0
    end
    if not cache[id] then
        cache[id] = { metadata = {}, names = {} }
    end
    return cache[id]
end
function D.invalidate(id)
    local relevant = cache[id] ~= nil or D.requested[id] == true
    cache[id] = nil
    return relevant
end
function D.name(key, link)
    link = validLink(key, link)
    local b = bucket(key.itemID)
    local signature = F.Util.key(key) .. (link or "")
    if b.names[signature] then
        return b.names[signature]
    end
    local name = type(link) == "string" and link:match("|h%[(.-)%]|h")
    if not name and (not C_Item or not C_Item.IsItemDataCachedByID or C_Item.IsItemDataCachedByID(key.itemID)) then
        local get = C_Item and C_Item.GetItemInfo or GetItemInfo
        if get then
            local ok, value = pcall(get, link or key.itemID)
            if ok then
                name = value
            end
        end
    end
    if not name and C_AuctionHouse and C_AuctionHouse.GetItemKeyInfo then
        local ok, info = pcall(C_AuctionHouse.GetItemKeyInfo, key)
        if ok and info then
            name = info.itemName
        end
    end
    name = name or (L("Item", "Item") .. " " .. key.itemID)
    b.names[signature] = name
    cacheCount = cacheCount + 1
    return name
end
validLink = function(key, link)
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
    local b = bucket(id)
    local signature = U.key(key) .. (link or "") .. tostring(family)
    if b.metadata[signature] then
        return b.metadata[signature]
    end
    local name, cachedLink, quality, icon, level
    local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    if getInfo then
        local ok, n, l, q, itemLevel, _, _, _, _, _, tex = pcall(getInfo, link or id)
        if ok then
            name = n
            cachedLink = l
            quality = q
            icon = tex
            level = itemLevel
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
    local result = {
        key = key,
        name = name or (L("Item", "Item") .. " " .. tostring(id)),
        link = link,
        quality = quality,
        level = (key.itemLevel or 0) > 0 and key.itemLevel or ((link or base) and level or nil),
        icon = icon or 134400,
        exact = not not (link or base),
        base = base,
    }
    b.metadata[signature] = result
    cacheCount = cacheCount + 1
    return result
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
    F.Locale.font(f, 11)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    f:SetWidth(w)
    f:SetJustifyH("LEFT")
    f:SetWordWrap(false)
    f:SetText(title or "")
    return f
end
function D.columns(width, compact)
    compact = compact or width < 600
    if compact then
        return { price = 0, icon = 104, itemName = 130, quantity = width - 145, profit = width - 88, detail = width }, {
            price = 100,
            itemName = math.max(20, width - 275),
            quantity = 55,
            profit = 88,
            detail = 0,
        }
    end
    return { price = 0, icon = 118, itemName = 148, quantity = width - 260, profit = width - 200, detail = width - 95 }, {
        price = 110,
        itemName = math.max(20, width - 408),
        quantity = 50,
        profit = 100,
        detail = 95,
    }
end
function D.headers(parent, x, y)
    local frame = CreateFrame("Frame", nil, parent)
    local headings = {
        price = L("Unit price", "Unit price"),
        itemName = L("Item", "Item"),
        quantity = L("Qty", "Qty"),
        profit = L("Potential P/L", "Potential P/L"),
        detail = L("Route / status", "Route / status"),
    }
    local labels = {}
    for name, title in pairs(headings) do
        labels[name] = F.NativeLayout.header(frame, title)
    end
    function frame:LayoutColumns(width)
        local x, w = D.columns(width)
        for name, h in pairs(labels) do
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", self, "TOPLEFT", x[name], 0)
            h:SetSize(math.max(1, w[name]), 22)
            if w[name] == 0 then
                h:Hide()
            else
                h:Show()
            end
        end
    end
    F.NativeLayout.place(frame, parent, x, y, 810, 22)
    frame:LayoutColumns(frame:GetWidth())
    return frame
end
function D.row(parent, x, y, width, onClick)
    local r = CreateFrame("Button", nil, parent)
    r:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    r:SetSize(width, 30)
    local bg = r:CreateTexture(nil, "BACKGROUND")
    r.background = bg
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.12)
    local highlight = r:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAtlas("auctionhouse-ui-row-highlight")
    highlight:SetAllPoints()
    highlight:SetBlendMode("ADD")
    r:SetHighlightTexture(highlight, "ADD")
    r.qualityBorder = r:CreateTexture(nil, "ARTWORK")
    r.qualityBorder:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.qualityBorder:SetSize(22, 22)
    r.icon = r:CreateTexture(nil, "OVERLAY")
    r.icon:SetPoint("LEFT", r, "LEFT", 6, 0)
    r.icon:SetSize(20, 20)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.itemName = label(r, 40, 9, 245)
    r.quantity = label(r, 292, 9, 48)
    r.price = label(r, 345, 9, 145)
    r.profit = label(r, 500, 9, 140)
    r.detail = label(r, 650, 9, 150)
    function r:LayoutColumns(width, compact)
        local xs, ws = D.columns(width, compact or self.nativeCompact)
        for _, name in ipairs({ "itemName", "quantity", "price", "profit", "detail" }) do
            local f = self[name]
            f:ClearAllPoints()
            f:SetPoint("LEFT", self, "LEFT", xs[name], 0)
            f:SetWidth(math.max(1, ws[name]))
            if ws[name] == 0 then
                f:Hide()
            else
                f:Show()
            end
        end
        local small = compact or self.nativeCompact
        self.icon:SetSize(small and 16 or 20, small and 16 or 20)
        self.qualityBorder:SetSize(small and 18 or 22, small and 18 or 22)
        self.price:SetJustifyH("RIGHT")
        self.quantity:SetJustifyH("CENTER")
        self.profit:SetJustifyH("RIGHT")
        self.icon:ClearAllPoints()
        self.icon:SetPoint("LEFT", self, "LEFT", xs.icon + 2, 0)
        self.qualityBorder:ClearAllPoints()
        self.qualityBorder:SetPoint("LEFT", self, "LEFT", xs.icon + 1, 0)
    end
    F.NativeLayout.place(r, parent, x, y, width, 30)
    r:LayoutColumns(r:GetWidth())
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
        self.itemName:SetText(m.name .. (U.finite(m.level) and m.level > 0 and (" (" .. m.level .. ")") or ""))
        self.quantity:SetText(p.qty and p.qty > 0 and p.qty or p.totalQty or 0)
        self.price:SetText(D.money(p.qty and p.qty > 0 and p.cost and p.cost / p.qty or p.minimum))
        self.profit:SetText(D.money(p.profit))
        self.profit:SetTextColor((p.profit or 0) < 0 and 1 or 0.4, (p.profit or 0) < 0 and 0.3 or 1, 0.4)
        self.detail:SetText((p.mode == "vendor" and "NPC" or "AH") .. " " .. (note or ""))
        self:Show()
    end
    return r
end
