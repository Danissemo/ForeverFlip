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
function S.create(ui, warning)
    local c = ui.c
    local page = ui.sections.deals
    page.viewport:Hide()
    local host = page.scroll
    local left = CreateFrame("Frame", nil, host, "InsetFrameTemplate")
    local right = CreateFrame("Frame", nil, host, "InsetFrameTemplate")
    local state = { left = left, right = right, headers = {}, listRows = {} }
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
    local empty = right:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOP", right, "TOP", 0, -70)
    empty:SetWidth(320)
    empty:SetWordWrap(true)
    F.Locale.font(empty, 12)
    empty:SetText(
        L(
            "Scan the auction house or search for an item.",
            "Scan the auction house or search for an item."
        )
    )
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
    ui.actions.filterMode = button(host, L("All strategies", "All strategies"), function(b)
        ui.filterMode = ui.filterMode == "all" and "vendor" or ui.filterMode == "vendor" and "flip" or "all"
        b:SetText(
            ui.filterMode == "all" and L("All strategies", "All strategies")
                or ui.filterMode == "vendor" and "NPC"
                or L("Resale", "Resale")
        )
        ui.dealPage = 1
        ui:refresh()
    end)
    ui.actions.dealSort = button(host, L("Risk / capital", "Risk / capital"), function()
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
            ui.fields.item:SetText(U.key(p.key))
            c:stop("manual")
            c.mode = p.mode
            if c:search(p.key) then
                ui:show("trade")
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
            b:SetWidth(lw - 35)
        end
        for i, b in ipairs({ lists, plan, clear }) do
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 5 + (i - 1) * (lw - 10) / 3, 5)
            b:SetWidth((lw - 16) / 3)
        end
        local buttons = { ui.actions.filterMode, ui.actions.dealSort, previous, nextPage }
        local widths = { 115, 110, 25, 25 }
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
            { title = L("All items", "All items"), kind = "all" },
            { title = L("Watchlist", "Watchlist"), kind = "watch" },
        }
        for _, g in ipairs(c.db.groups or {}) do
            data[#data + 1] = { title = g.name, kind = "group" }
        end
        data[#data + 1] = { title = L("Live opportunities", "Live opportunities"), kind = "live" }
        for i, entry in ipairs(data) do
            if not state.listRows[i] then
                local row = CreateFrame("Button", nil, listBody)
                row:SetPoint("TOPLEFT", listBody, "TOPLEFT", 0, -(i - 1) * 25)
                row:SetSize(listBody:GetWidth(), 24)
                row:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight", "ADD")
                local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                label:SetPoint("LEFT", row, "LEFT", 7, 0)
                label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                label:SetJustifyH("LEFT")
                F.Locale.font(label, 12)
                row.label = label
                row:SetScript("OnClick", function(b)
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
                or (entry.kind == "live" and ui.liveOnly)
                or (entry.kind == "all" and not ui.liveOnly and not ui.watchOnly and not ui.groupFilter)
            row.label:SetTextColor(1, selected and 0.82 or 1, selected and 0 or 1)
            row:Show()
        end
        for i = #data + 1, #state.listRows do
            state.listRows[i]:Hide()
        end
        listBody:SetHeight(math.max(1, #data * 25))
    end
    ui.refreshers.deals = function()
        refreshLists()
        local all = ui.liveOnly and F.Radar.list(c) or c:rank()
        local out = {}
        local query = ui.fields.dealFilter:GetText():lower()
        local watch = {}
        for _, v in ipairs(c.db.watchlist or {}) do
            watch[tostring(v)] = true
        end
        for _, p in ipairs(all) do
            local name = F.ItemDisplay.metadata(p.key, p.link, p.family).name
            local group = c:rule(p.key).group or ""
            if
                (ui.filterMode == "all" or p.mode == ui.filterMode)
                and (not ui.groupFilter or ui.groupFilter == group)
                and (not ui.watchOnly or watch[tostring(p.key.itemID)] or watch[U.key(p.key)])
                and (query == "" or (name .. " " .. p.key.itemID .. " " .. group):lower():find(query, 1, true))
            then
                out[#out + 1] = p
            end
        end
        table.sort(out, function(a, b)
            local x, y
            if ui.sort == "profit" then
                x, y = a.profit, b.profit
            elseif ui.sort == "price" then
                x, y = a.minimum or math.huge, b.minimum or math.huge
            elseif ui.sort == "quantity" then
                x, y = a.totalQty or 0, b.totalQty or 0
            elseif ui.sort == "itemName" then
                x, y = U.name(a.key.itemID), U.name(b.key.itemID)
            else
                x, y = a.score or -math.huge, b.score or -math.huge
            end
            if x == y then
                return U.key(a.key) < U.key(b.key)
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
            empty:SetText(
                ui.liveOnly
                        and L(
                            "Live is looking for eligible deals. Resale needs price history; add items to your watchlist.",
                            "Live is looking for eligible deals. Resale needs price history; add items to your watchlist."
                        )
                    or L(
                        "Scan the auction house or search for an item.",
                        "Scan the auction house or search for an item."
                    )
            )
            empty:Show()
        else
            empty:Hide()
        end
        for i, row in ipairs(ui.dealRows) do
            local p = out[(ui.dealPage - 1) * PAGE_SIZE + i]
            row:SetItem(p, p and (p.canBuy and L("Verify", "Verify") or warning(p)))
            row:SetEnabled(p ~= nil)
            if p then
                row.quantity:SetText(p.totalQty or 0)
                row.price:SetText(F.ItemDisplay.money(p.minimum))
            end
        end
    end
    state.layout(ui.canvas:GetWidth(), ui.canvas:GetHeight() - 68 - 44)
end
