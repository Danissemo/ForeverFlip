local F = ForeverFlip
local U = F.Util
local L = F.Locale.text
local S = {}
local PAGE_SIZE = 20
F.NativeShopping = S
local function button(parent, title, fn)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(90, 22)
    b:SetText(title)
    F.Locale.font(b:GetFontString(), 11)
    b:SetScript("OnClick", fn)
    return b
end
-- Category entry styled like the native auction filter list (no dependency on Blizzard templates).
local function category(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(21)
    local normal = row:CreateTexture(nil, "BACKGROUND")
    normal:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-FilterBg")
    normal:SetTexCoord(0, 0.53125, 0, 0.625)
    normal:SetPoint("TOPLEFT", row, "TOPLEFT", -2, 0)
    normal:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 2, 1)
    row.normal = normal
    local selected = row:CreateTexture(nil, "ARTWORK")
    selected:SetAtlas("auctionhouse-nav-button-select")
    selected:SetBlendMode("ADD")
    selected:SetAllPoints(normal)
    selected:Hide()
    row.selected = selected
    row:SetHighlightTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight", "ADD")
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", row, "LEFT", 8, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    label:SetJustifyH("LEFT")
    F.Locale.font(label, 12)
    row.label = label
    return row
end
local function backdrop(frame, atlas)
    local t = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    t:SetAtlas(atlas)
    t:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
    t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
    return t
end
-- One plain sentence that tells the player how this deal turns into gold.
function S.how(p)
    local qty = p.qty or 0
    if qty <= 0 then
        return L("Good to buy", "Good to buy")
    end
    if p.mode == "vendor" then
        return string.format(
            L(
                "Buy %d for %s and sell to any vendor for %s. Net: %s.",
                "Buy %d for %s and sell to any vendor for %s. Net: %s."
            ),
            qty,
            U.money(p.cost),
            U.money(math.floor(qty * (p.target or 0))),
            U.money(p.profit)
        )
    end
    return string.format(
        L(
            "Buy %d for %s and list at %s each. After the fee: +%s.",
            "Buy %d for %s and list at %s each. After the fee: +%s."
        ),
        qty,
        U.money(p.cost),
        U.money(p.target),
        U.money(p.profit)
    )
end
function S.create(ui, warning)
    local c = ui.c
    local page = ui.sections.deals
    page.viewport:Hide()
    local host = page.scroll
    local left = CreateFrame("Frame", nil, host, "InsetFrameTemplate")
    local right = CreateFrame("Frame", nil, host, "InsetFrameTemplate")
    local state = { left = left, right = right, headers = {}, listRows = {} }
    state.leftArt = backdrop(left, "auctionhouse-background-categories")
    state.rightArt = backdrop(right, "auctionhouse-background-index")
    ui.shopping = state
    local listScroll = CreateFrame("ScrollFrame", nil, left, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", left, "TOPLEFT", 7, -9)
    listScroll:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -27, 32)
    local listBody = CreateFrame("Frame", nil, listScroll)
    listBody:SetSize(220, 400)
    listScroll:SetScrollChild(listBody)
    local resultScroll = CreateFrame("ScrollFrame", nil, right, "UIPanelScrollFrameTemplate")
    resultScroll:SetPoint("TOPLEFT", right, "TOPLEFT", 4, -5)
    resultScroll:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -27, 5)
    local resultBody = CreateFrame("Frame", nil, resultScroll)
    resultBody:SetSize(480, PAGE_SIZE * 20)
    resultScroll:SetScrollChild(resultBody)
    local emptyIcon = right:CreateTexture(nil, "ARTWORK")
    emptyIcon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    emptyIcon:SetSize(44, 44)
    emptyIcon:SetPoint("TOP", right, "TOP", 0, -48)
    local emptyTitle = right:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    emptyTitle:SetPoint("TOP", emptyIcon, "BOTTOM", 0, -10)
    emptyTitle:SetWidth(380)
    F.Locale.font(emptyTitle, 15)
    local empty = right:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    empty:SetPoint("TOP", emptyTitle, "BOTTOM", 0, -8)
    empty:SetWidth(360)
    empty:SetWordWrap(true)
    F.Locale.font(empty, 12)
    local emptyStart = button(right, L("Sell to vendors", "Sell to vendors"), function()
        ui:startNPC()
        ui:refresh()
    end)
    emptyStart:SetSize(150, 24)
    emptyStart:SetPoint("TOPRIGHT", empty, "BOTTOM", -6, -16)
    local emptyScan = button(right, L("Scan the auction house", "Scan the auction house"), function()
        c:fullScan()
        ui:refresh()
    end)
    emptyScan:SetSize(170, 24)
    emptyScan:SetPoint("TOPLEFT", empty, "BOTTOM", 6, -16)
    state.empty = { icon = emptyIcon, title = emptyTitle, text = empty, start = emptyStart, scan = emptyScan }
    ui.actions.emptyStart, ui.actions.emptyScan = emptyStart, emptyScan
    local function showEmpty(shown)
        for _, region in pairs(state.empty) do
            if shown then
                region:Show()
            else
                region:Hide()
            end
        end
    end
    for _, v in ipairs({
        { "price", L("Price", "Price") },
        { "itemName", L("Name", "Name") },
        { "quantity", L("Available", "Available") },
        { "profit", L("Profit", "Profit") },
    }) do
        local sort = v[1]
        state.headers[sort] = F.NativeLayout.header(host, v[2], function()
            if ui.sort == sort then
                ui.sortDescending = not ui.sortDescending
            else
                ui.sort = sort
                ui.sortDescending = sort == "profit" or sort == "quantity"
            end
            ui.dealPage = 1
            ui:refresh()
        end)
    end
    ui.fields.dealFilter = CreateFrame("EditBox", nil, host, "InputBoxTemplate")
    ui.fields.dealFilter:SetText("")
    ui.fields.dealFilter:Hide()
    ui.actions.filterApply = button(host, "", function()
        ui.dealPage = 1
        ui:refresh()
    end)
    ui.actions.filterApply:Hide()
    local lists = button(left, L("Lists", "Lists"), function()
        ui:show("watch")
    end)
    local plan = button(left, L("Planner", "Planner"), function()
        ui.actions.easyBuild:Click()
    end)
    local clear = button(left, L("All", "All"), function()
        ui.groupFilter = nil
        ui.watchOnly = false
        ui.liveOnly = false
        ui.fields.dealFilter:SetText("")
        ui.dealPage = 1
        ui:refresh()
    end)
    local function strategyLabel()
        return ui.filterMode == "vendor" and L("Show: sell to vendor", "Show: sell to vendor")
            or ui.filterMode == "flip" and L("Show: resell", "Show: resell")
            or L("Show: everything", "Show: everything")
    end
    local function sortLabel()
        return ui.sort == "score" and L("Sort: safest", "Sort: safest")
            or L("Sort: profit", "Sort: profit")
    end
    ui.actions.filterMode = button(host, "", function(b)
        ui.filterMode = ui.filterMode == "all" and "vendor" or ui.filterMode == "vendor" and "flip" or "all"
        b:SetText(strategyLabel())
        ui.dealPage = 1
        ui:refresh()
    end)
    ui.actions.dealSort = button(host, "", function()
        ui.sort = ui.sort == "score" and "profit" or "score"
        ui.sortDescending = true
        ui:refresh()
    end)
    local previous = button(host, "<", function()
        ui.dealPage = math.max(1, ui.dealPage - 1)
        ui:refresh()
    end)
    local nextPage = button(host, ">", function()
        ui.dealPage = ui.dealPage + 1
        ui:refresh()
    end)
    local pages = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.dealRows = {}
    for i = 1, PAGE_SIZE do
        local index = i
        local r = F.ItemDisplay.row(resultBody, 0, (i - 1) * 20, 480, function()
            local p = ui.visibleDeals and ui.visibleDeals[(ui.dealPage - 1) * PAGE_SIZE + index]
            if not p then
                return
            end
            if c:openDeal(p) then
                ui.fields.item:SetText(U.key(c.selection.key))
                ui:show("trade", "deal")
            end
        end)
        r.background:SetAtlas("auctionhouse-rowstripe-1")
        r.background:SetBlendMode("ADD")
        r.background:SetVertexColor(1, 1, 1, 1)
        r.background:SetAlpha(i % 2 == 0 and 0.8 or 0.25)
        r.nativeCompact = true
        ui.dealRows[i] = r
    end
    state.layout = function(width, height)
        local lw = math.min(280, math.max(220, math.floor(width * 0.34)))
        local rx = lw + 8
        local rw = math.max(1, width - rx)
        left:ClearAllPoints()
        left:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -24)
        left:SetSize(lw, math.max(1, height - 24))
        right:ClearAllPoints()
        right:SetPoint("TOPLEFT", host, "TOPLEFT", rx, -24)
        right:SetSize(rw, math.max(1, height - 54))
        listBody:SetWidth(math.max(1, lw - 35))
        resultBody:SetWidth(math.max(1, rw - 31))
        local x, w = F.ItemDisplay.columns(rw - 31, true)
        for name, h in pairs(state.headers) do
            h:ClearAllPoints()
            local hx = x[name]
            local hw = w[name]
            if name == "itemName" then
                hx = x.icon
                hw = w.itemName + x.itemName - x.icon
            end
            h:SetPoint("TOPLEFT", host, "TOPLEFT", rx + 4 + hx, 0)
            h:SetSize(hw, 23)
        end
        for i, r in ipairs(ui.dealRows) do
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", resultBody, "TOPLEFT", 0, -(i - 1) * 20)
            r:SetSize(rw - 31, 20)
            r:LayoutColumns(rw - 31, true)
        end
        for i, b in ipairs(state.listRows) do
            b:SetWidth(lw - 39)
        end
        for i, b in ipairs({ lists, plan, clear }) do
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 5 + (i - 1) * (lw - 10) / 3, 5)
            b:SetWidth((lw - 16) / 3)
        end
        local buttons = { ui.actions.filterMode, ui.actions.dealSort, previous, nextPage }
        local widths = { 170, 140, 25, 25 }
        local cursor = rx
        for i, b in ipairs(buttons) do
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", cursor, 2)
            b:SetWidth(widths[i])
            cursor = cursor + widths[i] + 5
        end
        pages:ClearAllPoints()
        pages:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -4, 6)
    end
    local function refreshLists()
        local data = {
            {
                title = L("Sell to vendors (no risk)", "Sell to vendors (no risk)"),
                kind = "starter",
            },
            { title = L("Live bargain hunt", "Live bargain hunt"), kind = "live" },
            { title = L("All found deals", "All found deals"), kind = "all" },
            { title = L("My watchlist", "My watchlist"), kind = "watch" },
        }
        for _, g in ipairs(c.db.groups or {}) do
            data[#data + 1] = { title = g.name, kind = "group" }
        end
        for i, entry in ipairs(data) do
            if not state.listRows[i] then
                local row = category(listBody)
                row:SetPoint("TOPLEFT", listBody, "TOPLEFT", 2, -(i - 1) * 23)
                row:SetWidth(listBody:GetWidth() - 4)
                row:SetScript("OnClick", function(b)
                    if b.entry.kind == "starter" then
                        ui:startNPC()
                        ui:refresh()
                        return
                    end
                    if b.entry.kind == "live" then
                        c:radarAll()
                        ui.filterMode = "all"
                        ui.sort, ui.sortDescending = "profit", true
                    end
                    ui.groupFilter = b.entry.kind == "group" and b.entry.title or nil
                    ui.watchOnly = b.entry.kind == "watch"
                    ui.liveOnly = b.entry.kind == "live"
                    ui.dealPage = 1
                    ui:refresh()
                end)
                state.listRows[i] = row
            end
            local row = state.listRows[i]
            row.entry = entry
            row.label:SetText(entry.title)
            local selected = (entry.kind == "group" and ui.groupFilter == entry.title)
                or (entry.kind == "watch" and ui.watchOnly)
                or (entry.kind == "starter" and ui.liveOnly and c.smallNPCActive)
                or (entry.kind == "live" and ui.liveOnly and not c.smallNPCActive)
                or (entry.kind == "all" and not ui.liveOnly and not ui.watchOnly and not ui.groupFilter)
            if selected then
                row.selected:Show()
                row.label:SetTextColor(1, 1, 1)
            else
                row.selected:Hide()
                row.label:SetTextColor(1, 0.82, 0)
            end
            row:Show()
        end
        for i = #data + 1, #state.listRows do
            state.listRows[i]:Hide()
        end
        listBody:SetHeight(math.max(1, #data * 23))
    end
    ui.refreshers.deals = function()
        ui.actions.filterMode:SetText(strategyLabel())
        ui.actions.dealSort:SetText(sortLabel())
        local simple = F.NativeLayout.simple(ui)
        for _, b in ipairs({ lists, plan }) do
            if simple then
                b:Hide()
            else
                b:Show()
            end
        end
        refreshLists()
        local all = ui.liveOnly and F.Radar.list(c) or F.DealCache.get(c)
        local out = {}
        local query = F.Locale.fold(ui.fields.dealFilter:GetText())
        local watch = {}
        for _, v in ipairs(c.db.watchlist or {}) do
            watch[tostring(v)] = true
        end
        for _, p in ipairs(all) do
            local name = query ~= "" and F.ItemDisplay.name(p.key, p.link) or ""
            local group = p.group or ""
            if
                (ui.filterMode == "all" or p.mode == ui.filterMode)
                and (not ui.groupFilter or ui.groupFilter == group)
                and (not ui.watchOnly or watch[tostring(p.key.itemID)] or watch[U.key(p.key)])
                and (query == "" or F.Locale.fold(name .. " " .. p.key.itemID .. " " .. group):find(query, 1, true))
            then
                out[#out + 1] = p
            end
        end
        local names = {}
        if ui.sort == "itemName" then
            for _, p in ipairs(out) do
                names[p] = F.ItemDisplay.name(p.key, p.link)
            end
        end
        table.sort(out, function(a, b)
            if (a.canBuy and true or false) ~= (b.canBuy and true or false) then
                return a.canBuy and true or false
            end
            local x, y
            if ui.sort == "profit" then
                x, y = a.profit, b.profit
            elseif ui.sort == "price" then
                x, y = a.minimum or math.huge, b.minimum or math.huge
            elseif ui.sort == "quantity" then
                x, y = a.totalQty or 0, b.totalQty or 0
            elseif ui.sort == "itemName" then
                x, y = names[a], names[b]
            else
                x, y = a.score or -math.huge, b.score or -math.huge
            end
            if x == y then
                return a.identity < b.identity
            end
            if ui.sortDescending then
                return x > y
            end
            return x < y
        end)
        ui.visibleDeals = out
        local count = math.max(1, math.ceil(#out / PAGE_SIZE))
        ui.dealPage = math.max(1, math.min(count, ui.dealPage))
        local signature = table.concat({
            ui.dealPage,
            #out,
            query,
            tostring(ui.groupFilter),
            tostring(ui.watchOnly),
            ui.sort,
            tostring(ui.sortDescending),
        }, "|")
        if state.signature ~= signature then
            resultScroll:SetVerticalScroll(0)
            state.signature = signature
        end
        pages:SetText(ui.dealPage .. " / " .. count .. "  " .. #out)
        previous:SetEnabled(ui.dealPage > 1)
        nextPage:SetEnabled(ui.dealPage < count)
        if #out == 0 then
            local searching = ui.liveOnly
            emptyTitle:SetText(
                searching and L("Looking for bargains…", "Looking for bargains…")
                    or L("No deals yet", "No deals yet")
            )
            empty:SetText(
                searching
                        and c.smallNPCActive
                        and L(
                            "Checking lots that a vendor buys for more than their auction price. Finds appear here. If it stays empty, there are simply no bargains right now.",
                            "Checking lots that a vendor buys for more than their auction price. Finds appear here. If it stays empty, there are simply no bargains right now."
                        )
                    or searching and L(
                        "Looking for lots below their usual price. The longer you scan the market, the better the addon knows normal prices.",
                        "Looking for lots below their usual price. The longer you scan the market, the better the addon knows normal prices."
                    )
                    or L(
                        "Start with the safe vendor route or scan the whole auction house — the addon will list items cheaper than usual.",
                        "Start with the safe vendor route or scan the whole auction house — the addon will list items cheaper than usual."
                    )
            )
            showEmpty(true)
            if searching then
                emptyStart:Hide()
                emptyScan:Hide()
            end
        else
            showEmpty(false)
        end
        for i, row in ipairs(ui.dealRows) do
            local p = out[(ui.dealPage - 1) * PAGE_SIZE + i]
            local note = p and (p.canBuy and S.how(p) or warning(p))
            if p and p.source == "radar" and p.at then
                note = note
                    .. "\n"
                    .. string.format(
                        L(
                            "Found %d min ago — the price is re-checked before buying.",
                            "Found %d min ago — the price is re-checked before buying."
                        ),
                        math.floor(math.max(0, c.api.clock() - p.at) / 60)
                    )
            end
            row:SetItem(p, note)
            row:SetEnabled(p ~= nil)
            if p then
                row.quantity:SetText(p.totalQty or 0)
                row.price:SetText(F.ItemDisplay.money(p.minimum))
            end
        end
    end
    state.layout(ui.canvas:GetWidth(), ui.canvas:GetHeight() - 68 - 44)
end
