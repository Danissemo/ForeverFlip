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
function N.shell(ui)
    local root = ui.frame
    ui.nativeLayout = { controls = {}, containers = {} }
    root.ffNativeOwner = ui
    local host = CreateFrame("Frame", nil, root)
    host:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    ui.canvas = host
    ui.nav = {}
    local tabs = {
        { "deals", L("Auction", "Auction") },
        { "trade", L("Trading", "Trading") },
        { "portfolio", L("Portfolio", "Portfolio") },
        { "history", L("History", "History") },
        { "tools", L("Professions", "Professions") },
        { "settings", L("Settings", "Settings") },
        { "overview", L("Overview", "Overview") },
    }
    ui.nativeLayout.tabs = tabs
    for _, t in ipairs(tabs) do
        local id = t[1]
        ui.nav[id] = N.tab(host, t[2], function()
            ui:show(id)
        end)
    end
    for _, t in ipairs({
        { "deals", L("Deals", "Deals") },
        { "workbench", L("Planner", "Planner") },
        { "watch", L("Lists", "Lists") },
    }) do
        local id = t[1]
        local b = N.tab(host, t[2], function()
            ui:show(id)
        end)
        ui.nativeLayout["sub_" .. id] = b
        if id ~= "deals" then
            ui.nav[id] = b
        end
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
    local tabWidth = math.min(110, (width - 12) / 7)
    for i, t in ipairs(ui.nativeLayout.tabs) do
        local tab = ui.nav[t[1]]
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", ui.canvas, "TOPLEFT", 6 + (i - 1) * tabWidth, -38)
        tab.ffNativeWidth = tabWidth
        tab:SetHeight(26)
        N.resizeTab(tab)
    end
    local auction = ui.section == "deals" or ui.section == "workbench" or ui.section == "watch"
    for i, id in ipairs({ "deals", "workbench", "watch" }) do
        local b = ui.nativeLayout["sub_" .. id]
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", ui.canvas, "TOPLEFT", 4 + (i - 1) * 84, -66)
        b.ffNativeWidth = 84
        b:SetHeight(24)
        N.resizeTab(b)
        if auction then
            b:Show()
        else
            b:Hide()
        end
        if id == ui.section and PanelTemplates_SelectTab then
            PanelTemplates_SelectTab(b)
        elseif PanelTemplates_DeselectTab then
            PanelTemplates_DeselectTab(b)
        end
        N.resizeTab(b)
    end
    for id, s in pairs(ui.sections) do
        local top = (id == "workbench" or id == "watch") and 94 or 68
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
        apply(e)
    end
    ui.status:SetWidth(math.max(1, width - 20))
    F.Progress.layout(ui, width)
    if ui.shopping and ui.shopping.layout then
        ui.shopping.layout(width, math.max(1, height - 68 - 44))
    end
end
function N.select(ui, id)
    local active = (id == "workbench" or id == "watch") and "deals" or id
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
