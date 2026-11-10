local F = ForeverFlip
local N = {}
F.NativeLayout = N
local L = F.Locale.text
local function owner(frame)
    while frame do
        local ui = rawget(frame, "ffNativeOwner")
        if ui then
            return ui
        end
        frame = frame.GetParent and frame:GetParent()
    end
end
local function apply(e)
    local ratio = e.parent:GetWidth() / (e.reference or 840)
    e.widget:ClearAllPoints()
    e.widget:SetPoint("TOPLEFT", e.parent, "TOPLEFT", e.x * ratio, -e.y)
    if e.width then
        e.widget:SetWidth(math.max(1, e.width * ratio))
    end
    if e.height then
        e.widget:SetHeight(e.height)
    end
    if e.widget.GetFontString then
        local label = e.widget:GetFontString()
        if label and type(label) ~= "function" then
            label:SetWidth(math.max(1, e.widget:GetWidth() - 12))
            label:SetWordWrap(true)
        end
    end
    if rawget(e.widget, "LayoutColumns") then
        e.widget:LayoutColumns(e.widget:GetWidth())
    end
end
-- Expert-only blocks: in simple mode controls whose original y falls in [from, to) are hidden and
-- everything below moves up, so the page stays compact without gaps.
function N.collapsible(ui, parent, from, to)
    local list = ui.nativeLayout.collapsible or {}
    ui.nativeLayout.collapsible = list
    list[#list + 1] = { parent = parent, from = from, to = to }
end
local function collapse(ui, e)
    e.baseY = e.baseY or e.y
    local simple = N.simple(ui)
    local shift, hidden = 0, false
    for _, r in ipairs(ui.nativeLayout.collapsible or {}) do
        if simple and r.parent == e.parent then
            if e.baseY >= r.from and e.baseY < r.to then
                hidden = true
            elseif e.baseY >= r.to then
                shift = shift + r.to - r.from
            end
        end
    end
    e.y = e.baseY - shift
    if hidden then
        e.widget:Hide()
        e.collapsed = true
    elseif e.collapsed then
        e.widget:Show()
        e.collapsed = nil
    end
end
function N.place(widget, parent, x, y, width, height)
    local ui = owner(parent)
    local entry = { widget = widget, parent = parent, x = x, y = y, width = width, height = height }
    if ui then
        table.insert(ui.nativeLayout.controls, entry)
    end
    apply(entry)
    return widget
end
function N.container(frame, parent, padding)
    local ui = owner(parent)
    if ui then
        table.insert(ui.nativeLayout.containers, { frame = frame, parent = parent, padding = padding or 0 })
    end
    frame:SetWidth(math.max(1, parent:GetWidth() - (padding or 0)))
end
function N.resizeTab(tab)
    F.Locale.font(tab:GetFontString(), 11)
    local width = rawget(tab, "ffNativeWidth") or 90
    if PanelTemplates_TabResize then
        PanelTemplates_TabResize(tab, 0, width)
    else
        tab:SetWidth(width)
    end
end
function N.tab(parent, title, callback)
    local b = CreateFrame("Button", nil, parent, "PanelTopTabButtonTemplate")
    b:SetText(title)
    F.Locale.font(b:GetFontString(), 11)
    b:SetSize(90, 26)
    b.ffNativeWidth = 90
    b:SetScript("OnShow", N.resizeTab)
    b:SetScript("OnEvent", function(tab, event)
        if event == "DISPLAY_SIZE_CHANGED" then
            N.resizeTab(tab)
        end
    end)
    b:SetScript("OnClick", callback)
    return b
end
-- One set of tabs for everyone. Every tab is a split page like the Auction tab: a category list
-- on the left and one compact panel on the right, so nothing needs scrolling.
local TABS = { "overview", "deals", "trade", "portfolio", "workbench", "tools", "settings" }
local CONTROL_RESERVE = 76
local LIST_WIDTH = 190
-- Kept for callers: the former "simple" layout is now the only layout.
function N.simple()
    return true
end
function N.visibleTabs(ui)
    local byId = {}
    for _, t in ipairs(ui.nativeLayout.tabs) do
        byId[t[1]] = t
    end
    local list = {}
    for _, id in ipairs(TABS) do
        list[#list + 1] = byId[id]
    end
    return list
end
local function reload()
    local fn = (C_UI and C_UI.Reload) or ReloadUI
    if fn then
        fn()
    end
end
function N.chooseLanguage(ui, code)
    if not F.Locale.choose(code) then
        if ui.c and ui.c.notify then
            ui.c:notify(
                L("Language saved. Use /reload to apply.", "Language saved. Use /reload to apply.")
            )
        end
        return false
    end
    reload()
    return true
end
function N.labels(ui)
    local controls = ui.nativeLayout.controls_
    if not controls then
        return
    end
    local current = F.Locale.current()
    local ukrainian = current == "ukUA" or current == "uk"
    controls.en:SetEnabled(ukrainian)
    controls.ua:SetEnabled(not ukrainian)
    if ui.actions and ui.actions.quickPlan then
        ui.actions.quickPlan:Hide()
    end
end
-- Category entry styled like the native auction filter list.
function N.category(parent)
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
    function row:SetSelected(on)
        if on then
            self.selected:Show()
            self.label:SetTextColor(1, 1, 1)
        else
            self.selected:Hide()
            self.label:SetTextColor(1, 0.82, 0)
        end
    end
    return row
end
function N.backdrop(frame, atlas)
    local t = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    t:SetAtlas(atlas)
    t:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
    t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
    return t
end
-- Moves already placed controls of `source` whose original y is in [from, to) onto `page`,
-- shifting them so `from` lands at `offset`. Logic and callbacks of the controls are untouched.
function N.migrate(ui, page, source, from, to, offset)
    for _, e in ipairs(ui.nativeLayout.controls) do
        local y = e.baseY or e.y
        if e.parent == source and y >= from and y < to then
            e.parent = page
            e.baseY = y - from + (offset or 0)
            e.y = e.baseY
            e.reference = 810
            e.widget:SetParent(page)
            e.widget:Show()
        end
    end
end
-- Attaches a whole frame (card, list) to a page at `y`.
function N.attach(ui, page, frame, y, height)
    frame:SetParent(page)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(y or 0))
    frame:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -(y or 0))
    if height then
        frame:SetHeight(height)
    end
    for _, c in ipairs(ui.nativeLayout.containers) do
        if c.frame == frame then
            c.parent, c.padding = page, 0
        end
    end
    frame:Show()
end
-- entries: { { title, section = id, page = pageId }, ... } shared by every section of one tab.
function N.split(ui, sectionId, entries)
    local s = ui.sections[sectionId]
    s.viewport:Hide()
    local left = CreateFrame("Frame", nil, s.scroll, "InsetFrameTemplate")
    local right = CreateFrame("Frame", nil, s.scroll, "InsetFrameTemplate")
    N.backdrop(left, "auctionhouse-background-categories")
    left:SetPoint("TOPLEFT", s.scroll, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", s.scroll, "BOTTOMLEFT", 0, 0)
    left:SetWidth(LIST_WIDTH)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
    right:SetPoint("BOTTOMRIGHT", s.scroll, "BOTTOMRIGHT", 0, 0)
    local split = { left = left, right = right, pages = {}, rows = {}, entries = entries }
    s.split = split
    for i, entry in ipairs(entries) do
        local row = N.category(left)
        row:SetPoint("TOPLEFT", left, "TOPLEFT", 8, -8 - (i - 1) * 23)
        row:SetPoint("TOPRIGHT", left, "TOPRIGHT", -8, -8 - (i - 1) * 23)
        row.label:SetText(entry[1])
        row.entry = entry
        row:SetScript("OnClick", function()
            ui:show(entry.section, entry.page)
        end)
        split.rows[i] = row
        if entry.section == sectionId and not split.pages[entry.page] then
            local page = CreateFrame("Frame", nil, right)
            page:SetPoint("TOPLEFT", right, "TOPLEFT", 10, -10)
            page:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -10, 8)
            page:SetSize(560, 340)
            page:Hide()
            split.pages[entry.page] = page
            split.first = split.first or entry.page
        end
    end
    return split
end
function N.page(ui, sectionId, pageId)
    return ui.sections[sectionId].split.pages[pageId]
end
function N.selectPage(ui, sectionId, pageId)
    local split = ui.sections[sectionId].split
    if not split then
        return
    end
    pageId = split.pages[pageId] and pageId or ui.pages[sectionId] or split.first
    ui.pages[sectionId] = pageId
    for id, page in pairs(split.pages) do
        if id == pageId then
            page:Show()
        else
            page:Hide()
        end
    end
    for _, row in ipairs(split.rows) do
        row:SetSelected(row.entry.section == sectionId and row.entry.page == pageId)
    end
end
local function controlButton(ui, host, width, title, tooltip, callback)
    local b = CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(title)
    F.Locale.font(b:GetFontString(), 11)
    b:SetScript("OnClick", callback)
    b:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    return b
end
function N.shell(ui)
    local root = ui.frame
    ui.nativeLayout = { controls = {}, containers = {} }
    root.ffNativeOwner = ui
    local host = CreateFrame("Frame", nil, root)
    host:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    ui.canvas = host
    ui.nav = {}
    local tabs = {
        { "overview", L("Start", "Start") },
        { "deals", L("Auction", "Auction") },
        { "trade", L("Trading", "Trading") },
        { "portfolio", L("Portfolio", "Portfolio") },
        { "workbench", L("Analytics", "Analytics") },
        { "tools", L("Professions", "Professions") },
        { "settings", L("Settings", "Settings") },
    }
    ui.pages = {}
    ui.nativeLayout.tabs = tabs
    ui.nativeLayout.controls_ = {
        en = controlButton(ui, host, 30, "EN", "English (UI reload)", function()
            N.chooseLanguage(ui, "en")
        end),
        ua = controlButton(ui, host, 30, "UA", "Українська (перезавантаження UI)", function()
            N.chooseLanguage(ui, "uk")
        end),
    }
    for _, t in ipairs(tabs) do
        local id = t[1]
        ui.nav[id] = N.tab(host, t[2], function()
            ui:show(id)
        end)
    end
    for _, id in ipairs({
        "overview",
        "deals",
        "workbench",
        "trade",
        "watch",
        "portfolio",
        "history",
        "tools",
        "settings",
    }) do
        local pane = CreateFrame("Frame", nil, host, id ~= "deals" and "InsetFrameTemplate" or nil)
        if id ~= "deals" then
            -- Same backdrop as the native auction lists, so every tab looks like one addon.
            local art = pane:CreateTexture(nil, "BACKGROUND", nil, 1)
            art:SetAtlas("auctionhouse-background-index")
            art:SetPoint("TOPLEFT", pane, "TOPLEFT", 3, -3)
            art:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -3, 3)
            pane.ffArt = art
        end
        local scroll = CreateFrame("ScrollFrame", nil, pane, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", pane, "TOPLEFT", 8, -10)
        scroll:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -26, 8)
        local body = CreateFrame("Frame", nil, scroll)
        body:SetSize(750, 1200)
        body.ffNativeOwner = ui
        scroll:SetScrollChild(body)
        ui.sections[id] = { scroll = pane, viewport = scroll, body = body }
        pane:Hide()
    end
    ui.header = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.header:Hide()
    ui.status = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    F.Locale.font(ui.status, 11)
    ui.status:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 8, 5)
    ui.status:SetJustifyH("LEFT")
    ui.status:SetWordWrap(false)
    F.Progress.create(ui)
    N.reflow(ui)
    host:Show()
    return host
end
function N.reflow(ui)
    if not ui.nativeLayout then
        return
    end
    local parent = ui.frame:GetParent()
    local width = math.max(1, parent:GetWidth() - 8)
    local height = math.max(1, parent:GetHeight() - 62)
    ui.canvas:SetSize(width, height)
    local visible = N.visibleTabs(ui)
    local tabWidth = math.min(110, (width - 12 - CONTROL_RESERVE) / #visible)
    for _, t in ipairs(ui.nativeLayout.tabs) do
        ui.nav[t[1]]:Hide()
    end
    for i, t in ipairs(visible) do
        local tab = ui.nav[t[1]]
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", ui.canvas, "TOPLEFT", 6 + (i - 1) * tabWidth, -38)
        tab.ffNativeWidth = tabWidth
        tab:SetHeight(26)
        tab:Show()
        N.resizeTab(tab)
    end
    local controls = ui.nativeLayout.controls_
    controls.ua:ClearAllPoints()
    controls.ua:SetPoint("TOPRIGHT", ui.canvas, "TOPRIGHT", -4, -40)
    controls.en:ClearAllPoints()
    controls.en:SetPoint("TOPRIGHT", ui.canvas, "TOPRIGHT", -36, -40)
    N.labels(ui)
    for id, s in pairs(ui.sections) do
        local top = 68
        s.scroll:ClearAllPoints()
        s.scroll:SetPoint("TOPLEFT", ui.canvas, "TOPLEFT", 0, -top)
        s.scroll:SetPoint("BOTTOMRIGHT", ui.canvas, "BOTTOMRIGHT", 0, 44)
        s.scroll:SetSize(width, math.max(1, height - top - 44))
        s.body:SetWidth(math.max(1, width - 42))
    end
    for _, c in ipairs(ui.nativeLayout.containers) do
        c.frame:SetWidth(math.max(1, c.parent:GetWidth() - c.padding))
    end
    for _, e in ipairs(ui.nativeLayout.controls) do
        collapse(ui, e)
        apply(e)
    end
    N.fitScrolling(ui)
    ui.status:SetWidth(math.max(1, width - 20))
    F.Progress.layout(ui, width)
    if ui.shopping and ui.shopping.layout then
        ui.shopping.layout(width, math.max(1, height - 68 - 44))
    end
end
function N.select(ui, id)
    local active = (id == "watch" or id == "history") and "workbench" or id
    for _, t in ipairs(ui.nativeLayout.tabs) do
        local b = ui.nav[t[1]]
        if t[1] == active and PanelTemplates_SelectTab then
            PanelTemplates_SelectTab(b)
        elseif PanelTemplates_DeselectTab then
            PanelTemplates_DeselectTab(b)
        end
        N.resizeTab(b)
    end
    N.reflow(ui)
end
function N.header(parent, title, callback)
    local b = CreateFrame("Button", nil, parent, "AuctionHouseTableHeaderStringTemplate")
    b:SetText(title)
    F.Locale.font(b:GetFontString(), 11)
    if b.Arrow and type(b.Arrow) ~= "function" then
        b.Arrow:Hide()
    end
    b:SetScript("OnClick", callback or function() end)
    return b
end

-- Long history and group summaries retain their full content inside a bounded viewport.
function N.scrolling(ui, page)
    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -24, 0)
    local content = CreateFrame("Frame", nil, scroll)
    scroll:SetScrollChild(content)
    page.ffScroll, page.ffContent = scroll, content
    ui.nativeLayout.scrolling = ui.nativeLayout.scrolling or {}
    table.insert(ui.nativeLayout.scrolling, page)
    for _, e in ipairs(ui.nativeLayout.controls) do
        if e.parent == page then
            e.parent = content
            e.widget:SetParent(content)
        end
    end
    scroll:Show()
    content:Show()
    N.fitScrolling(ui)
end
function N.fitScrolling(ui)
    for _, page in ipairs(ui.nativeLayout.scrolling or {}) do
        local content = page.ffContent
        content:SetWidth(math.max(1, page:GetWidth() - 24))
        local bottom = math.max(page:GetHeight(), rawget(page, "ffMinHeight") or 0)
        for _, e in ipairs(ui.nativeLayout.controls) do
            if e.parent == content then
                apply(e)
                local h = e.height or (e.widget.GetStringHeight and e.widget:GetStringHeight()) or 24
                bottom = math.max(bottom, e.y + h + 16)
            end
        end
        content:SetHeight(bottom)
    end
end
