-- Auction-house styled window: a top bar, a category list on the left and a
-- results table on the right, action buttons at the bottom. Only templates and atlases of the
-- auction house that are known to exist on WoW Forever are used.
local F = ForeverFlip
local U = F.Util
local L = function(s)
    return F.Locale.text(s)
end
local UI = {}
F.UI = UI

local ROW = 20
local LEFT_WIDTH = 194

local MESSAGES = {
    nothing_to_post = "Nothing bought for resale is waiting in the bags.",
    nothing_undercut = "No undercut auction worth reposting. Press Check prices first.",
    bid_placed = "Bid placed. If nobody bids more, the item arrives by mail when the auction ends.",
    bid_won = "Auction won: the item is booked as stock.",
    hidden = "The item is hidden: it is no longer offered for sale.",
    unhidden = "The item is back in the list for sale.",
    share_queued = "Sending the scan...",
    share_sent = "Scan sent.",
    share_received = "A shared scan was added to the price history.",
    share_invalid = "This text is not a ForeverFlip scan.",
    other_realm = "The shared scan is from another realm.",
    old = "The shared scan is more than 7 days old.",
    duplicate = "This scan is already in the history.",
    no_guild = "You are not in a guild.",
    no_group = "You are not in a group.",
    no_scan = "Make a full scan first.",
    combat = "Key bindings cannot change in combat.",
    unknown_item = "Unknown item. Shift-click its link, or type its exact name once the game knows it.",
    checking = "Reading the current prices of the items to post (one per second); press again to post the next one.",
    mail_done = "Auction mail taken.",
    mail_closed = "The mailbox was closed.",
    bags_full = "The bags are full.",
    scan_done = "Full scan processed.",
    scan_empty = "The auction house returned an empty scan. Try again later.",
    scan_timeout = "The server sent no full scan in 5 minutes (the list stayed empty; another addon or another character of the account may have used the 15-minute window). Next try in a minute.",
    scan_unsettled = "The full scan list kept changing for 5 minutes and was not read. Next try in a minute.",
    scan_dropped = "The server threw the full scan request away (too many requests). Next try in 10 seconds.",
    scan_paused = "The auction house closed while waiting for the full scan: the wait goes on when you open it again.",
    scan_paused_reading = "The auction house closed during the full scan: it is read again when you open it.",
    scan_resumed = "Waiting again for the full scan sent before.",
    scan_other = "Another addon requested a full scan: ForeverFlip reads it too.",
    quote_ready = "Price confirmed. Press Confirm purchase.",
    price_changed = "The price changed. The deal is checked again.",
    quote_expired = "The price offer expired. Press Buy again.",
    requote = "The price offer was about to expire; a new one was asked. Press Confirm when it arrives.",
    bought = "Purchase recorded.",
    buy_failed = "The purchase failed (someone was faster). The deal is checked again.",
    buy_unknown = "No answer from the auction house. Settle the purchase in the Journal.",
    posted = "Auction created.",
    sold = "Sale recorded.",
    verify_first = "Checking the current price first...",
    no_money = "Not enough money.",
    busy = "Wait for the current action.",
    closed = "Open the auction house.",
    cooldown = "A full scan is allowed once per 15 minutes.",
    throttled = "The auction house is busy. Try again in a moment.",
    error = "The game refused the action.",
    values = "Check the quantity and the price.",
    confirm = "The game asks for a confirmation: press Post again.",
    cancelled = "Auction cancelled. The item comes back by mail; the deposit is lost.",
    spend_limit = "The spending limit of this auction house visit is reached (Settings, Safety tab).",
    no_deal = "No deal to buy right now.",
    bought_elsewhere = "A purchase made outside ForeverFlip was booked from its mail.",
}

-- Widgets ---------------------------------------------------------------------------------------------
local function text(parent, font)
    local t = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    t:SetJustifyH("LEFT")
    return t
end

local function button(parent, label, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 110, 22)
    b:SetText(L(label))
    b:SetScript("OnClick", onClick)
    return b
end

local function editbox(parent, width)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width or 80, 20)
    e:SetAutoFocus(false)
    e:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    e:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    return e
end

local function inset(parent, atlas)
    local f = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
    local art = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    art:SetAtlas(atlas)
    art:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
    art:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
    return f
end

-- Entry of the left list, styled like the auction house category list.
local function category(parent, label, onClick)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(21)
    local normal = row:CreateTexture(nil, "BACKGROUND")
    normal:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-FilterBg")
    normal:SetTexCoord(0, 0.53125, 0, 0.625)
    normal:SetPoint("TOPLEFT", row, "TOPLEFT", -2, 0)
    normal:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 2, 1)
    local selected = row:CreateTexture(nil, "ARTWORK")
    selected:SetAtlas("auctionhouse-nav-button-select")
    selected:SetBlendMode("ADD")
    selected:SetAllPoints(normal)
    selected:Hide()
    row.selected = selected
    row:SetHighlightTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight", "ADD")
    local t = text(row, "GameFontNormalSmall")
    t:SetPoint("LEFT", row, "LEFT", 8, 0)
    t:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    t:SetText(L(label))
    row.label = t
    row:SetScript("OnClick", onClick)
    return row
end

local function icon(id)
    if C_Item and C_Item.GetItemIconByID then
        return C_Item.GetItemIconByID(id)
    end
    return 134400
end

local function nameOf(key, link)
    if link then
        return link
    end
    local item = U.parseKey(key)
    if item then
        local name, itemLink = U.itemInfo(item.id)
        return itemLink or name or ("item:" .. item.id)
    end
    return key
end

local function showTooltip(owner, key, link)
    if not GameTooltip then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if link then
        GameTooltip:SetHyperlink(link)
    else
        local item = U.parseKey(key)
        if item then
            GameTooltip:SetItemByID(item.id)
        end
    end
    GameTooltip:Show()
end

-- A results table: header buttons and rows. `columns` = { {label, width, align}, ... }; the first
-- column is the item (icon and name) and takes the remaining width.
local function table_(parent, columns, rows, onClick, onSort)
    local t = { rows = {}, headers = {} }
    if not onSort then
        -- Built-in sorting: a header click sorts by that column, a second click reverses it. Names
        -- start A to Z, numbers start with the largest.
        onSort = function(index)
            if t.sortIndex == index then
                t.descending = not t.descending
            else
                t.sortIndex, t.descending = index, index ~= 1
            end
            UI.refresh()
        end
    end
    local header = CreateFrame("Frame", nil, parent)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -4)
    header:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, -4)
    header:SetHeight(20)
    local function headerCell(label, width, align, index)
        local h = CreateFrame("Button", nil, header, "AuctionHouseTableHeaderStringTemplate")
        h:SetHeight(20)
        if width then
            h:SetWidth(width)
        end
        h:SetText(L(label))
        local fs = h.GetFontString and h:GetFontString()
        if fs then
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", h, "LEFT", 6, 0)
            fs:SetPoint("RIGHT", h, "RIGHT", -16, 0)
            fs:SetJustifyH(align or "RIGHT")
            fs:SetWordWrap(false)
        end
        -- The template's native handler expects a Blizzard owner; use our view instead.
        h:SetScript("OnClick", onSort and function()
            onSort(index)
        end or nil)
        h:SetEnabled(onSort ~= nil)
        h.Arrow:ClearAllPoints()
        h.Arrow:SetPoint("RIGHT", h, "RIGHT", -3, 0)
        h.Arrow:SetSize(8, 8)
        h.Arrow:Hide()
        t.headers[index] = h
        return h
    end
    -- Right-aligned fixed columns, laid out from the right edge.
    local cells, x = {}, 0
    for i = #columns, 2, -1 do
        local c = columns[i]
        local h = headerCell(c[1], c[2], c[3], i)
        h:SetPoint("TOPRIGHT", header, "TOPRIGHT", -x, 0)
        cells[i] = { x = x, width = c[2], align = c[3] }
        x = x + c[2]
    end
    local first = headerCell(columns[1][1], nil, "LEFT", 1)
    first:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
    first:SetPoint("TOPRIGHT", header, "TOPRIGHT", -x, 0)
    -- A sorted copy of `list` by the chosen column. `value(entry, column)` returns a number, a
    -- string or nil; nil sorts last in both directions, equal values keep the list's order.
    function t.sort(list, value)
        local index = t.sortIndex
        t.setSort(index, t.descending)
        local out = {}
        for i, e in ipairs(list) do
            out[i] = e
        end
        if not index then
            return out
        end
        local keys, order = {}, {}
        for i, e in ipairs(out) do
            local v = value(e, index)
            if type(v) == "string" then
                v = string.lower(v:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
            end
            keys[e], order[e] = v, i
        end
        table.sort(out, function(a, b)
            local va, vb = keys[a], keys[b]
            if va == nil or vb == nil or type(va) ~= type(vb) or va == vb then
                if (va == nil) ~= (vb == nil) then
                    return vb == nil
                end
                return order[a] < order[b]
            end
            if t.descending then
                return va > vb
            end
            return va < vb
        end)
        return out
    end
    function t.setSort(index, descending)
        for i, h in ipairs(t.headers) do
            if i == index then
                h.Arrow:Show()
            else
                h.Arrow:Hide()
            end
            h.Arrow:SetTexCoord(0, 1, descending and 0 or 1, descending and 1 or 0)
        end
    end
    for i = 1, rows do
        local r = CreateFrame("Button", nil, parent)
        r:SetHeight(ROW)
        r:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -(i - 1) * ROW)
        r:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -(i - 1) * ROW)
        if i % 2 == 0 then
            local stripe = r:CreateTexture(nil, "BACKGROUND")
            stripe:SetAtlas("auctionhouse-rowstripe-1")
            stripe:SetAllPoints()
        end
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAtlas("auctionhouse-ui-row-highlight")
        hl:SetAllPoints()
        hl:SetBlendMode("ADD")
        r.selected = r:CreateTexture(nil, "ARTWORK")
        r.selected:SetAtlas("auctionhouse-ui-row-select")
        r.selected:SetAllPoints()
        r.selected:SetBlendMode("ADD")
        r.selected:Hide()
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(ROW - 4, ROW - 4)
        r.icon:SetPoint("LEFT", r, "LEFT", 4, 0)
        r.name = text(r, "GameFontHighlightSmall")
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
        r.name:SetPoint("RIGHT", r, "RIGHT", -x - 4, 0)
        r.name:SetWordWrap(false)
        r.cols = {}
        for n = 2, #columns do
            local c = text(r, "GameFontHighlightSmall")
            c:SetPoint("RIGHT", r, "RIGHT", -cells[n].x - 6, 0)
            c:SetWidth(cells[n].width - 10)
            c:SetJustifyH(cells[n].align or "RIGHT")
            c:SetWordWrap(false)
            r.cols[n - 1] = c
        end
        if r.RegisterForClicks then
            r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        end
        r:SetScript("OnClick", function(self, mouse)
            if mouse == "RightButton" and self.key then
                UI.showHistory(self.key, self.link)
                return
            end
            onClick(self)
        end)
        r:SetScript("OnEnter", function(self)
            if self.key then
                showTooltip(self, self.key, self.link)
            end
        end)
        r:SetScript("OnLeave", function()
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)
        r:Hide()
        t.rows[i] = r
    end
    t.empty = text(parent, "GameFontHighlight")
    t.empty:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 10, -20)
    t.empty:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -10, -20)
    t.empty:SetSpacing(4)
    return t
end

-- Main frame --------------------------------------------------------------------------------------
function UI.create()
    local f = CreateFrame("Frame", "ForeverFlipFrame", AuctionHouseFrame or UIParent)
    if AuctionHouseFrame then
        f:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 4, -60)
        f:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -4, 26)
    else
        f:SetSize(800, 500)
    end
    f:Hide()
    f:SetScript("OnShow", function()
        F.Engine.changed()
        UI.refresh()
    end)
    UI.frame = f

    -- Top bar: scan, sniper and bulk check buttons, status text.
    UI.scanButton = button(f, "Full scan", 150, function()
        local ok, why = F.Scan.start()
        if not ok then
            F.Engine.notify(why)
        end
    end)
    UI.scanButton:SetPoint("TOPLEFT", f, "TOPLEFT", 96, 30)
    UI.sniperButton = button(f, "Sniper: ON", 116, function()
        F.Deals.setSniper(not F.db.settings.sniper)
        UI.refresh()
    end)
    UI.sniperButton:SetPoint("LEFT", UI.scanButton, "RIGHT", 6, 0)
    -- Check all: every entry of the open page is searched on the auction house again (one search
    -- after another), and the page shows what was found.
    UI.bulkButton = button(f, "Check all", 160, function()
        UI.checkStatuses()
    end)
    UI.bulkButton:SetPoint("LEFT", UI.sniperButton, "RIGHT", 6, 0)
    -- Which auction house this is (its own prices; a neutral one takes 15%): in the middle of the
    -- bar beside the money display (UI.placeHouse), else in the top right corner.
    UI.houseBadge = text(f, "GameFontNormal")
    UI.status = text(f, "GameFontNormal")
    UI.placeHouse()
    UI.status:SetWordWrap(false)
    UI.progress = CreateFrame("StatusBar", nil, f)
    UI.progress:SetHeight(3)
    UI.progress:SetPoint("TOPLEFT", f, "TOPLEFT", 4, 4)
    UI.progress:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, 4)
    UI.progress:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    UI.progress:SetStatusBarColor(1, 0.82, 0)
    UI.progress:SetMinMaxValues(0, 1)
    UI.progress:SetValue(0)

    -- Left: categories and the last scan in short.
    local left = inset(f, "auctionhouse-background-categories")
    left:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    left:SetWidth(LEFT_WIDTH)
    UI.categories = {}
    for i, group in ipairs(UI.GROUPS) do
        local c = category(left, group.label, function()
            UI.show(group.current or group.pages[1][1])
        end)
        c:SetPoint("TOPLEFT", left, "TOPLEFT", 8, -8 - (i - 1) * 23)
        c:SetPoint("TOPRIGHT", left, "TOPRIGHT", -8, -8 - (i - 1) * 23)
        c.group = group
        UI.categories[i] = c
    end
    UI.summary = text(left, "GameFontHighlightSmall")
    UI.summary:SetPoint("TOPLEFT", left, "TOPLEFT", 12, -8 - #UI.GROUPS * 23 - 12)
    UI.summary:SetPoint("TOPRIGHT", left, "TOPRIGHT", -10, -8 - #UI.GROUPS * 23 - 12)
    UI.summary:SetSpacing(4)

    -- Right: one page per category.
    local right = inset(f, "auctionhouse-background-index")
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 4, 0)
    right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    UI.right = right
    UI.pages = {}
    for _, id in ipairs({
        "deals",
        "shop",
        "bids",
        "sell",
        "auctions",
        "stats",
        "analytics",
        "crafting",
        "journal",
        "settings",
    }) do
        local page = CreateFrame("Frame", nil, right)
        page:SetPoint("TOPLEFT", right, "TOPLEFT", 3, -3)
        page:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -3, 3)
        page:Hide()
        UI.pages[id] = page
    end
    -- Tabs of the pages of a group, above the page.
    UI.groupTabs = {}
    for _, group in ipairs(UI.GROUPS) do
        if #group.pages > 1 then
            local width = math.floor(math.min(150, 590 / #group.pages))
            local tabs = {}
            for i, entry in ipairs(group.pages) do
                local b = button(right, entry[2], width - 4, function()
                    UI.show(entry[1])
                end)
                b:SetPoint("TOPLEFT", right, "TOPLEFT", 6 + (i - 1) * width, -4)
                b.id = entry[1]
                b:Hide()
                tabs[#tabs + 1] = b
            end
            UI.groupTabs[group] = tabs
        end
    end
    UI.createDeals(UI.pages.deals)
    UI.createShop(UI.pages.shop)
    UI.createBids(UI.pages.bids)
    UI.createSell(UI.pages.sell)
    UI.createAuctions(UI.pages.auctions)
    UI.createStats(UI.pages.stats)
    UI.createAnalytics(UI.pages.analytics)
    UI.createCrafting(UI.pages.crafting)
    UI.createJournal(UI.pages.journal)
    UI.createSettings(UI.pages.settings)
    UI.show(F.db.ui and F.db.ui.section or "deals:all")
end

-- Six entries on the left, in the order of a session: find and buy, sell, plan purchases, craft,
-- look at the results. A group of several pages shows them as tabs above the page. The page ids
-- (UI.show) stay the same. Groups remember the page shown last.
UI.GROUPS = {
    {
        label = "Deals",
        pages = {
            { "deals:all", "All" },
            { "deals:vendor", "To vendor" },
            { "deals:flip", "Resale" },
            { "deals:shop", "From the list" },
            { "bids", "Bids" },
        },
    },
    { label = "Selling", pages = { { "sell", "My items" }, { "auctions", "My auctions" } } },
    { label = "Shopping list", pages = { { "shop", "Shopping list" } } },
    { label = "Crafting", pages = { { "crafting", "Crafting" } } },
    {
        label = "Analytics",
        pages = { { "analytics", "Overview" }, { "stats", "By item" }, { "journal", "Journal and profit" } },
    },
    { label = "Settings", pages = { { "settings", "Settings" } } },
}

function UI.groupOf(id)
    for _, group in ipairs(UI.GROUPS) do
        for _, entry in ipairs(group.pages) do
            if entry[1] == id then
                return group
            end
        end
    end
    return UI.GROUPS[1]
end

function UI.show(id)
    local page, filter = id:match("^(%a+):?(%a*)$")
    if not page or not UI.pages[page] then
        page, filter, id = "deals", "all", "deals:all"
    end
    UI.section = page
    if page == "deals" then
        UI.filter = filter ~= "" and filter or "all"
        UI.dealPage = 1
        local d = UI.selected and F.Deals.get(UI.selected)
        if d and UI.filter ~= "all" and d.mode ~= UI.filter then
            UI.selected = nil
        end
    end
    F.db.ui = F.db.ui or {}
    F.db.ui.section = id
    local group = UI.groupOf(id)
    group.current = id
    local tabbed = #group.pages > 1
    for key, p in pairs(UI.pages) do
        if key == page then
            -- A page of a group with tabs starts below them.
            p:ClearAllPoints()
            p:SetPoint("TOPLEFT", UI.right, "TOPLEFT", 3, tabbed and -32 or -3)
            p:SetPoint("BOTTOMRIGHT", UI.right, "BOTTOMRIGHT", -3, 3)
            p:Show()
        else
            p:Hide()
        end
    end
    for g, tabs in pairs(UI.groupTabs) do
        for _, b in ipairs(tabs) do
            if g == group then
                b:Show()
            else
                b:Hide()
            end
            b:SetEnabled(b.id ~= id)
        end
    end
    for _, c in ipairs(UI.categories) do
        if c.group == group then
            c.selected:Show()
        else
            c.selected:Hide()
        end
    end
    UI.refresh()
end

-- Bottom bar of a page: explanation text on the left, buttons on the right.
local function footer(page, height, font)
    local bar = CreateFrame("Frame", nil, page)
    bar:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    bar:SetHeight(height)
    local line = bar:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.25)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", bar, "TOPLEFT", 4, 0)
    line:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -4, 0)
    bar.text = text(bar, font or "GameFontHighlight")
    bar.text:SetPoint("TOPLEFT", bar, "TOPLEFT", 8, -6)
    bar.text:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -8, -6)
    bar.text:SetSpacing(2)
    return bar
end

-- Deals page -------------------------------------------------------------------------------------
local DEAL_ROWS = 14
function UI.createDeals(p)
    UI.filter, UI.dealPage = "all", 1
    UI.dealSort, UI.dealDescending = 5, true
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 120)
    UI.dealTable = table_(
        list,
        {
            { "Name" },
            { "Price", 76 },
            { "Qty", 50 },
            { "Cost", 76 },
            { "Profit", 76 },
            { "Status", 88, "LEFT" },
            { "Est./day", 68 },
        },
        DEAL_ROWS,
        function(row)
            UI.selectDeal(row.key)
        end,
        function(index)
            if UI.dealSort == index then
                UI.dealDescending = not UI.dealDescending
            else
                UI.dealSort, UI.dealDescending = index, index == 5 or index == 7
            end
            UI.dealPage = 1
            UI.refresh()
        end
    )
    local estimateHeader = UI.dealTable.headers[7]
    estimateHeader:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(
                L("Est./day")
                    .. "\n\n"
                    .. L(
                        "Estimated units that disappeared per day near the resale price, not a sale probability. Expired/cancelled lots can count.\n\nTwo usable full scans are required. Zero means none disappeared; '-' means unknown. Vendor deals need no auction-house resale.\n\nGrey estimates use data older than 3 hours. Checking a current price does not refresh sale history. Short observations are smoothed: one unit gone in 15 minutes counts as about 5-6 a day, not 96."
                    ),
                1,
                1,
                1,
                1,
                true
            )
            GameTooltip:Show()
        end
    end)
    estimateHeader:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    UI.prev = button(p, "<", 26, function()
        UI.dealPage = math.max(1, UI.dealPage - 1)
        UI.refresh()
    end)
    UI.prev:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 6, -26)
    UI.next = button(p, ">", 26, function()
        UI.dealPage = UI.dealPage + 1
        UI.refresh()
    end)
    UI.next:SetPoint("LEFT", UI.prev, "RIGHT", 4, 0)
    UI.pageText = text(p, "GameFontHighlightSmall")
    UI.pageText:SetPoint("LEFT", UI.next, "RIGHT", 8, 0)

    local bar = footer(p, 92, "GameFontHighlightSmall")
    UI.dealText = bar.text
    UI.dealText:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 8, 28)
    UI.dealText:SetJustifyV("TOP")
    UI.cancelButton = button(bar, "Cancel", 96, function()
        F.Trade.cancel()
    end)
    UI.cancelButton:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -6, 4)
    UI.confirmButton = button(bar, "Confirm purchase", 150, function()
        F.Trade.confirm()
    end)
    UI.confirmButton:SetPoint("RIGHT", UI.cancelButton, "LEFT", -4, 0)
    UI.buyButton = button(bar, "Buy", 86, function()
        if UI.selected then
            local ok, why = F.Trade.buy(UI.selected)
            if not ok then
                if why == "verify_first" then
                    F.Deals.verify(UI.selected)
                end
                F.Engine.notify(why)
            end
        end
    end)
    UI.buyButton:SetPoint("RIGHT", UI.confirmButton, "LEFT", -4, 0)
    UI.checkButton = button(bar, "Check price", 116, function()
        if UI.selected then
            F.Deals.verify(UI.selected)
            F.Engine.changed()
            UI.refresh()
        end
    end)
    UI.checkButton:SetPoint("RIGHT", UI.buyButton, "LEFT", -4, 0)
    UI.ignoreButton = button(bar, "Ignore item", 100, function()
        local d = UI.selected and F.Deals.get(UI.selected)
        if d then
            F.Shopping.block(d.key, U.linkName(d.link) or d.key)
            UI.selected = nil
            UI.refresh()
        end
    end)
    UI.ignoreButton:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 6, 4)
end

function UI.selectDeal(key)
    UI.selected = key
    local d = key and F.Deals.get(key)
    if d and (not d.verified or F.Engine.clock() - d.verified > F.Deals.FRESH) then
        F.Deals.verify(key)
    end
    F.Engine.changed()
    UI.refresh()
end

local function dealStatus(d)
    local now = F.Engine.clock()
    if d.cost > F.Engine.wallet() then
        return "|cffff6060" .. L("not enough money") .. "|r"
    end
    if F.Deals.search and F.Deals.search.key == d.key then
        return "|cffffd100" .. L("checking...") .. "|r"
    end
    if F.Deals.pending(d.key) then
        return "|cffffd100" .. L("queued") .. "|r"
    end
    if d.verified and now - d.verified <= F.Deals.FRESH then
        return "|cff40ff40" .. L("ready") .. "|r"
    end
    if d.verified then
        return "|cff999999" .. L("check again") .. "|r"
    end
    if now - (d.found or now) > 1200 then
        return "|cff777777" .. L("old scan") .. "|r"
    end
    return "|cff999999" .. L("from scan") .. "|r"
end

-- Return on the money and, for resale, how long the bought units take to sell at the estimate.
local function dealOutlook(d, estimate)
    local roi = d.cost > 0 and d.profit / d.cost or 0
    if d.mode == "shop" then
        return L("Bought for your own use: it stays out of Post next bought.")
    elseif d.mode == "disenchant" then
        return L("Estimate from the Classic disenchanting table and the usual material prices.")
    end
    if d.mode == "vendor" then
        return string.format(L("Return %d%%; sold to a vendor at once, no risk."), math.floor(roi * 100 + 0.5))
    end
    local perDay = estimate and estimate.known and estimate.perDay or d.perDay
    if perDay and perDay > 0 then
        return string.format(
            L("Return %d%%; at ~%.1f a day the %d units sell in about %.1f days."),
            math.floor(roi * 100 + 0.5),
            perDay,
            d.qty,
            d.qty / perDay
        )
    end
    return string.format(L("Return %d%%."), math.floor(roi * 100 + 0.5))
end

local function saleEstimate(d, history, now)
    if d.mode ~= "flip" then
        return { known = false }
    end
    return F.Market.saleability(history[d.key], d.exit, now)
end

local MODE_LABELS = { vendor = "vendor", shop = "shopping list", disenchant = "disenchant", bid = "bid" }
local function estimateText(d, estimate)
    if d.mode == "vendor" and d.vendorHow and d.vendorHow ~= "seen" then
        -- The server may pay less than the client says until a merchant confirmed the price.
        return L("vendor") .. " |cffffd100*|r"
    elseif d.mode ~= "flip" then
        return L(MODE_LABELS[d.mode] or d.mode)
    elseif not estimate.known then
        return "-"
    end
    local value = estimate.perDay == 0 and "0" or string.format("~%.1f", estimate.perDay)
    return estimate.stale and "|cff999999" .. value .. "|r" or value
end

local function estimateSentence(estimate)
    if not estimate.known then
        return L("Sale estimate unavailable: collect two full scans with usable price data.")
    end
    local value = estimate.perDay == 0 and "0" or string.format("~%.1f", estimate.perDay)
    local sentence = string.format(L("Estimated disappeared/day: %s."), value)
    if estimate.age then
        sentence = sentence
            .. " "
            .. string.format(L("Data %d min old"), math.floor(estimate.age / 60))
            .. (estimate.stale and L(" (old data).") or ".")
    end
    return sentence
end

local function dealSentence(d)
    if d.mode == "disenchant" then
        return string.format(
            L("Buy %d for %s and disenchant: the materials fetch about %s each. Profit: %s."),
            d.qty,
            U.money(d.cost),
            U.money(d.exit),
            U.money(d.profit)
        )
    end
    if d.mode == "shop" then
        return string.format(
            L("Buy %d for %s; your shopping list allows up to %s each (saving %s)."),
            d.qty,
            U.money(d.cost),
            U.money(d.exit),
            U.money(d.profit)
        )
    end
    if d.mode == "vendor" then
        return string.format(
            L("Buy %d for %s and sell to any vendor for %s. Profit: %s."),
            d.qty,
            U.money(d.cost),
            U.money(d.exit * d.qty),
            U.money(d.profit)
        )
    end
    return string.format(
        L("Buy %d for %s; list at %s each. Profit after the %d%% cut: +%s."),
        d.qty,
        U.money(d.cost),
        U.money(d.exit),
        math.floor(F.Market.CUT * 100 + 0.5),
        U.money(d.profit)
    )
end

function UI.refreshDeals()
    local list = F.Deals.visible(UI.filter)
    local now = F.Engine.clock()
    local history = F.Data.market(F.db, F.Engine.scope()).history
    local estimates = {}
    for _, d in ipairs(list) do
        estimates[d.key] = saleEstimate(d, history, now)
    end
    local function sortValue(d)
        local field = UI.dealSort
        if field == 1 then
            local name = nameOf(d.key, d.link)
            return string.lower(U.linkName(name) or name)
        elseif field == 2 then
            return d.maxUnit or 0
        elseif field == 3 then
            return d.qty
        elseif field == 4 then
            return d.cost
        elseif field == 5 then
            return d.profit
        elseif field == 7 then
            return estimates[d.key].perDay
        end
        if F.Deals.search and F.Deals.search.key == d.key then
            return 0
        elseif F.Deals.pending(d.key) then
            return 1
        elseif d.verified and now - d.verified <= F.Deals.FRESH then
            return 2
        elseif d.verified then
            return 3
        end
        return 4
    end
    local values = {}
    for _, d in ipairs(list) do
        values[d.key] = sortValue(d)
    end
    table.sort(list, function(a, b)
        local av, bv = values[a.key], values[b.key]
        if UI.dealSort == 7 and (av == nil) ~= (bv == nil) then
            return av ~= nil
        end
        if av == bv then
            return a.key < b.key
        end
        if UI.dealDescending then
            return av > bv
        end
        return av < bv
    end)
    UI.dealTable.setSort(UI.dealSort, UI.dealDescending)
    local pages = math.max(1, math.ceil(#list / DEAL_ROWS))
    UI.dealPage = math.min(UI.dealPage or 1, pages)
    for i, r in ipairs(UI.dealTable.rows) do
        local d = list[(UI.dealPage - 1) * DEAL_ROWS + i]
        if d then
            r.key, r.link = d.key, d.link
            r.icon:SetTexture(icon(d.id))
            r.name:SetText(nameOf(d.key, d.link))
            r.cols[1]:SetText(U.money(d.maxUnit or 0))
            r.cols[2]:SetText(d.qty)
            r.cols[3]:SetText(U.money(d.cost))
            r.cols[4]:SetText(U.money(d.profit))
            r.cols[5]:SetText(dealStatus(d))
            r.cols[6]:SetText(estimateText(d, estimates[d.key]))
            if d.key == UI.selected then
                r.selected:Show()
            else
                r.selected:Hide()
            end
            r:Show()
        else
            r.key = nil
            r:Hide()
        end
    end
    UI.prev:SetEnabled(UI.dealPage > 1)
    UI.next:SetEnabled(UI.dealPage < pages)
    local cost, profit = 0, 0
    for _, d in ipairs(list) do
        cost, profit = cost + d.cost, profit + d.profit
    end
    UI.pageText:SetText(
        string.format(L("Page %d / %d · deals: %d"), UI.dealPage, pages, #list)
            .. (
                #list > 0
                    and ("  ·  " .. string.format(L("all: cost %s, profit %s"), U.money(cost), U.money(profit)))
                or ""
            )
    )
    local empty = UI.dealTable.empty
    if #list == 0 then
        if F.Scan.busy() then
            empty:SetText(L("The full scan is being processed. Deals appear when it ends."))
        elseif not F.Scan.last then
            empty:SetText(
                L(
                    "Press Full scan. The addon reads every auction of the house (once per 15 minutes) and lists:\n- lots cheaper than a vendor pays for them (no risk);\n- lots far below the next seller of an item that really sells (resale)."
                )
            )
        elseif UI.filter == "flip" then
            empty:SetText(
                L(
                    "No resale yet. Resale needs sales data from 2 full scans (15 minutes apart; the automatic scan does it). Until a third scan at most 2 units are bought."
                )
            )
        else
            empty:SetText(
                L(
                    "No lot below the vendor price right now. Vendor prices load during the first minutes after a scan; deals appear here as soon as they are found."
                )
            )
        end
        empty:Show()
    else
        empty:Hide()
    end
    local d = UI.selected and F.Deals.get(UI.selected)
    local op = F.Trade.op
    if d then
        local lines = { dealSentence(d), dealOutlook(d, estimates[d.key]) }
        if d.mode == "flip" then
            lines[#lines + 1] = estimateSentence(estimates[d.key] or saleEstimate(d, history, now))
        end
        if d.kind ~= "commodity" then
            lines[#lines + 1] =
                L("Items are bought one auction per click; the next lot is checked after each purchase.")
        end
        UI.dealText:SetText(table.concat(lines, "\n"))
    else
        UI.dealText:SetText(L("Select a deal. Its price is checked on the auction house before you can buy."))
    end
    UI.checkButton:SetEnabled(d ~= nil and not F.Deals.pending(d.key) and not F.Trade.busy() and not F.Scan.blocking())
    UI.buyButton:SetEnabled(d ~= nil and F.Trade.canBuy(d) and true or false)
    UI.ignoreButton:SetEnabled(d ~= nil)
    UI.confirmButton:SetEnabled(op ~= nil and op.state == "quoted")
    UI.cancelButton:SetEnabled(op ~= nil and (op.state == "quote" or op.state == "quoted"))
    if op and op.state == "quoted" then
        UI.confirmButton:SetText(L("Confirm") .. " " .. U.money(op.cost))
    else
        UI.confirmButton:SetText(L("Confirm purchase"))
    end
end

-- Shopping list page -------------------------------------------------------------------------------
local SHOP_ROWS = 10
function UI.createShop(p)
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 150)
    UI.shopTable = table_(
        list,
        {
            { "Name" },
            { "Up to", 90 },
            { "Qty", 50 },
            { "Cheapest today", 100 },
            { "Status", 110, "LEFT" },
        },
        SHOP_ROWS,
        function(row)
            UI.shopSelected = row.key
            UI.refresh()
        end
    )
    local bar = footer(p, 146)
    UI.shopText = bar.text
    local itemLabel = text(bar, "GameFontNormal")
    itemLabel:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 8, 66)
    itemLabel:SetText(L("Item (Shift-click a link or type a name)"))
    UI.shopItem = editbox(bar, 220)
    UI.shopItem:SetPoint("LEFT", itemLabel, "RIGHT", 8, 0)
    local maxLabel = text(bar, "GameFontNormal")
    maxLabel:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 8, 36)
    maxLabel:SetText(L("Up to, each"))
    UI.shopMax = editbox(bar, 90)
    UI.shopMax:SetPoint("LEFT", maxLabel, "RIGHT", 8, 0)
    local qtyLabel = text(bar, "GameFontNormal")
    qtyLabel:SetPoint("LEFT", UI.shopMax, "RIGHT", 12, 0)
    qtyLabel:SetText(L("Quantity (empty: any)"))
    UI.shopQty = editbox(bar, 50)
    UI.shopQty:SetPoint("LEFT", qtyLabel, "RIGHT", 8, 0)
    UI.shopAdd = button(bar, "Add", 90, function()
        local key, name = F.Shopping.resolve(UI.shopItem:GetText())
        local max = U.parseMoney(UI.shopMax:GetText())
        if not key then
            F.Engine.notify("unknown_item")
        elseif not max or max <= 0 then
            F.Engine.notify("values")
        else
            F.Shopping.add(key, max, tonumber(UI.shopQty:GetText()), name)
            UI.shopItem:SetText("")
            F.Engine.notify("saved")
        end
    end)
    UI.shopAdd:SetPoint("LEFT", UI.shopQty, "RIGHT", 10, 0)
    UI.shopRemove = button(bar, "Remove", 100, function()
        if UI.shopSelected then
            if F.Shopping.entry(UI.shopSelected) then
                F.Shopping.remove(UI.shopSelected)
            else
                F.Shopping.unblock(UI.shopSelected)
            end
            UI.shopSelected = nil
        end
    end)
    UI.shopRemove:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -6, 4)
    if hooksecurefunc and ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", function(link)
            if UI.shopItem and UI.shopItem.HasFocus and UI.shopItem:HasFocus() then
                UI.shopItem:SetText(link)
            end
        end)
    end
end

function UI.refreshShop()
    local history = F.Data.market(F.db, F.Engine.scope()).history
    local rows = {}
    for _, key in ipairs(F.Shopping.keys()) do
        local e = F.Shopping.entry(key)
        rows[#rows + 1] = { key = key, name = e.name, max = e.max, qty = e.qty }
    end
    for _, b in ipairs(F.Shopping.blockedKeys()) do
        rows[#rows + 1] = { key = b.key, name = b.name, blocked = true }
    end
    for _, e in ipairs(rows) do
        local h = history[e.key]
        local today = h and h.days and h.days[#h.days]
        local d = F.Deals.get(e.key)
        e.cheap = today and today.min or nil
        e.state = e.blocked and 3 or (d and d.mode == "shop") and 1 or 2
    end
    rows = UI.shopTable.sort(rows, function(e, column)
        return ({ e.name or e.key, e.max, e.qty, e.cheap, e.state })[column]
    end)
    for i, r in ipairs(UI.shopTable.rows) do
        local e = rows[i]
        if e then
            local item = U.parseKey(e.key)
            local h = history[e.key]
            local today = h and h.days and h.days[#h.days]
            local d = F.Deals.get(e.key)
            r.key = e.key
            r.icon:SetTexture(icon(item and item.id))
            r.name:SetText(e.name or nameOf(e.key))
            r.cols[1]:SetText(e.max and U.money(e.max) or "-")
            r.cols[2]:SetText(e.qty or (e.blocked and "" or L("any")))
            r.cols[3]:SetText(today and today.min and U.money(today.min) or "-")
            r.cols[4]:SetText(
                e.blocked and "|cff999999" .. L("ignored") .. "|r"
                    or d and d.mode == "shop" and "|cff40ff40" .. L("for sale now") .. "|r"
                    or L("watching")
            )
            if e.key == UI.shopSelected then
                r.selected:Show()
            else
                r.selected:Hide()
            end
            r:Show()
        else
            r.key = nil
            r:Hide()
        end
    end
    local empty = UI.shopTable.empty
    if #rows == 0 then
        empty:SetText(
            L(
                "Add items you want to buy and the most you pay for one. The scan, the sniper and your own searches find lots at or below that price; they appear under Shopping deals."
            )
        )
        empty:Show()
    else
        empty:Hide()
    end
    UI.shopText:SetText(
        L(
            "Ignored items (Ignore item on a deal) are listed here too: they never become deals. Select one and press Remove to stop ignoring it."
        )
    )
    UI.shopRemove:SetEnabled(UI.shopSelected ~= nil)
end

-- Bids page ----------------------------------------------------------------------------------------
local BID_ROWS = 13
function UI.createBids(p)
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 96)
    UI.bidTable = table_(
        list,
        {
            { "Name" },
            { "Next bid", 86 },
            { "Worth", 86 },
            { "Profit", 86 },
            { "Status", 110, "LEFT" },
        },
        BID_ROWS,
        function(row)
            UI.bidSelected = row.key
            if row.key and not F.Bids.offer(row.key) then
                F.Bids.check(row.key)
            end
            UI.refresh()
        end
    )
    local bar = footer(p, 92, "GameFontHighlightSmall")
    UI.bidText = bar.text
    UI.bidButton = button(bar, "Place bid", 130, function()
        if UI.bidSelected then
            local ok, why = F.Bids.place(UI.bidSelected)
            if not ok then
                if why == "verify_first" then
                    F.Bids.check(UI.bidSelected)
                end
                F.Engine.notify(why)
            end
        end
    end)
    UI.bidButton:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -6, 4)
    UI.bidCheck = button(bar, "Check price", 120, function()
        if UI.bidSelected then
            F.Bids.check(UI.bidSelected)
        end
    end)
    UI.bidCheck:SetPoint("RIGHT", UI.bidButton, "LEFT", -4, 0)
end

function UI.refreshBids()
    local list = UI.bidTable.sort(F.Bids.candidates, function(c, column)
        local o = F.Bids.offer(c.key)
        return ({
            nameOf(c.key),
            o and o.bid or c.bid,
            c.value,
            o and o.profit or c.profit,
            o and 1 or F.Deals.pending(c.key) and 2 or 3,
        })[column]
    end)
    for i, r in ipairs(UI.bidTable.rows) do
        local c = list[i]
        if c then
            local o = F.Bids.offer(c.key)
            r.key = c.key
            r.icon:SetTexture(icon(c.id))
            r.name:SetText(nameOf(c.key))
            r.cols[1]:SetText(U.money(o and o.bid or c.bid))
            r.cols[2]:SetText(U.money(c.value))
            r.cols[3]:SetText(U.money(o and o.profit or c.profit))
            r.cols[4]:SetText(
                o and "|cff40ff40" .. L("ready") .. "|r"
                    or F.Deals.pending(c.key) and "|cffffd100" .. L("checking...") .. "|r"
                    or L("from scan")
            )
            if c.key == UI.bidSelected then
                r.selected:Show()
            else
                r.selected:Hide()
            end
            r:Show()
        else
            r.key = nil
            r:Hide()
        end
    end
    local empty = UI.bidTable.empty
    if #list == 0 then
        empty:SetText(
            L(
                "Auctions with a bid that end within 30 minutes and whose next bid is well below the item's worth appear here after a full scan."
            )
        )
        empty:Show()
    else
        empty:Hide()
    end
    local open = F.Bids.open()
    local lines = {
        L(
            "Worth: the vendor price, or the usual auction price after the cut for an item that sells. Another player can still outbid you; the money then comes back by mail."
        ),
    }
    if #open > 0 then
        lines[#lines + 1] =
            string.format(L("Your open bids: %d (latest: %s, %s)."), #open, open[1].name, U.money(open[1].amount))
    end
    UI.bidText:SetText(table.concat(lines, "\n"))
    local selected = UI.bidSelected
    UI.bidButton:SetEnabled(selected ~= nil and F.Bids.offer(selected) ~= nil)
    UI.bidCheck:SetEnabled(selected ~= nil and not F.Deals.pending(selected))
end

-- Sell page --------------------------------------------------------------------------------------
-- Where a suggested price comes from when nobody else sells the item.
UI.FALLBACK_TEXT = {
    last = "Nobody else sells it now. Suggested: your last price %s.",
    aux = "Nobody else sells it now. Suggested: auxForever's usual price %s.",
    cost = "Nobody sells it and there is no price history. Suggested: your cost plus 25%%, %s.",
    vendor = "Nobody sells it and there is no price history. Suggested: 1.5 x the vendor price, %s.",
}
local SELL_ROWS = 11
function UI.createSell(p)
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 142)
    UI.sellTable = table_(
        list,
        {
            { "Name" },
            { "Qty", 50 },
            { "Cost each", 80 },
            { "Listed", 60 },
            { "Best", 110 },
            { "Note", 110, "LEFT" },
        },
        SELL_ROWS,
        function(row)
            UI.sellSelected = row.item
            UI.sellPrice:SetText("")
            if row.item and UI.sellView == "hidden" then
                F.Engine.changed()
                UI.refresh()
                return
            end
            if row.item then
                -- An item a fresh full scan did not see has no lots: a search would get no answer.
                if not F.Scan.notListed(row.item.key) then
                    F.Trade.checkPrice(row.item.key)
                end
                UI.sellQty:SetText(row.item.count)
                local rule = F.Trade.rule(row.item.key) or {}
                UI.ruleMin:SetText(rule.min and U.plainMoney(rule.min) or "")
                UI.ruleMax:SetText(rule.max and U.plainMoney(rule.max) or "")
                UI.ruleKeep:SetText(rule.keep and tostring(rule.keep) or "")
            end
            F.Engine.changed()
            UI.refresh()
        end
    )

    UI.sellView = "sale"
    UI.sellSaleTab = button(p, "For sale", 130, function()
        UI.sellView, UI.sellSelected = "sale", nil
        UI.sellPrice:SetText("")
        UI.refresh()
    end)
    UI.sellSaleTab:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 6, 6)
    UI.sellHiddenTab = button(p, "Hidden", 130, function()
        UI.sellView, UI.sellSelected = "hidden", nil
        UI.sellPrice:SetText("")
        UI.refresh()
    end)
    UI.sellHiddenTab:SetPoint("LEFT", UI.sellSaleTab, "RIGHT", 4, 0)
    UI.sellHide = button(p, "Hide", 130, function()
        local item = UI.sellSelected
        if not item then
            return
        end
        if UI.sellView == "hidden" then
            F.Trade.unhide(item.key)
            F.Engine.notify("unhidden")
        else
            F.Trade.hide(item.key, item.name or U.linkName(item.link) or nameOf(item.key))
            F.Engine.notify("hidden")
        end
        UI.sellSelected = nil
        UI.sellPrice:SetText("")
        UI.refresh()
    end)
    UI.sellHide:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -6, 6)

    local bar = footer(p, 138)
    UI.sellText = bar.text
    local priceLabel = text(bar, "GameFontNormal")
    priceLabel:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 8, 36)
    priceLabel:SetText(L("Price each"))
    UI.sellPrice = editbox(bar, 110)
    UI.sellPrice:SetPoint("LEFT", priceLabel, "RIGHT", 10, 0)
    local qtyLabel = text(bar, "GameFontNormal")
    qtyLabel:SetPoint("LEFT", UI.sellPrice, "RIGHT", 14, 0)
    qtyLabel:SetText(L("Quantity"))
    UI.sellQty = editbox(bar, 50)
    UI.sellQty:SetPoint("LEFT", qtyLabel, "RIGHT", 10, 0)
    local durationLabel = text(bar, "GameFontNormal")
    durationLabel:SetPoint("LEFT", UI.sellQty, "RIGHT", 14, 0)
    durationLabel:SetText(L("Duration"))
    UI.durations = {}
    local labels = { "2", "8", "24", "Auto" }
    local values = { 1, 2, 3, 0 }
    for i = 1, 4 do
        local b = button(bar, labels[i], i == 4 and 50 or 34, function()
            F.db.settings.duration = values[i]
            F.Engine.changed()
            UI.refresh()
        end)
        b.value = values[i]
        b:SetPoint("LEFT", i == 1 and durationLabel or UI.durations[i - 1], "RIGHT", i == 1 and 8 or 2, 0)
        UI.durations[i] = b
    end
    -- Rule of the selected item: minimum and maximum price, units kept in the bags.
    local ruleLabel = text(bar, "GameFontNormal")
    ruleLabel:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 8, 66)
    ruleLabel:SetText(L("Rule: min"))
    UI.ruleMin = editbox(bar, 70)
    UI.ruleMin:SetPoint("LEFT", ruleLabel, "RIGHT", 8, 0)
    local maxLabel = text(bar, "GameFontNormal")
    maxLabel:SetPoint("LEFT", UI.ruleMin, "RIGHT", 10, 0)
    maxLabel:SetText(L("max"))
    UI.ruleMax = editbox(bar, 70)
    UI.ruleMax:SetPoint("LEFT", maxLabel, "RIGHT", 8, 0)
    local keepLabel = text(bar, "GameFontNormal")
    keepLabel:SetPoint("LEFT", UI.ruleMax, "RIGHT", 10, 0)
    keepLabel:SetText(L("keep"))
    UI.ruleKeep = editbox(bar, 40)
    UI.ruleKeep:SetPoint("LEFT", keepLabel, "RIGHT", 8, 0)
    UI.ruleSave = button(bar, "Save rule", 95, function()
        local item = UI.sellSelected
        if item then
            F.Trade.setRule(item.key, {
                min = U.parseMoney(UI.ruleMin:GetText()),
                max = U.parseMoney(UI.ruleMax:GetText()),
                keep = tonumber(UI.ruleKeep:GetText()),
            })
            F.Engine.notify("saved")
        end
    end)
    UI.ruleSave:SetPoint("LEFT", UI.ruleKeep, "RIGHT", 10, 0)
    UI.postButton = button(bar, "Post", 100, function()
        local item = UI.sellSelected
        if not item then
            return
        end
        local price = U.parseMoney(UI.sellPrice:GetText())
        local qty = tonumber(UI.sellQty:GetText())
        local ok, why = F.Trade.post(item, qty, price, F.Trade.durationFor(item.key, qty))
        F.Engine.notify(why)
        if ok and why == "posted" then
            UI.sellSelected = nil
            UI.sellPrice:SetText("")
        end
    end)
    UI.postButton:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -6, 4)
    UI.postNext = button(bar, "Post next bought", 165, function()
        local _, why = F.Trade.postNext()
        F.Engine.notify(why)
    end)
    UI.postNext:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 6, 4)
    UI.postAll = button(bar, "Post all", 105, function()
        local _, why = F.Trade.postAll()
        F.Engine.notify(why)
    end)
    UI.postAll:SetPoint("LEFT", UI.postNext, "RIGHT", 4, 0)
    -- Post all, except what a merchant pays at least as much for (the Best column says "Vendor").
    UI.postAuction = button(bar, "Post AH-worthy", 150, function()
        local _, why = F.Trade.postAll(true)
        F.Engine.notify(why)
    end)
    UI.postAuction:SetPoint("LEFT", UI.postAll, "RIGHT", 4, 0)
    for b, text in pairs({
        [UI.postAll] = "Posts every item for sale, one per click.",
        [UI.postAuction] = "Posts only items the auction house pays more for than a vendor, after the cut and the deposits (Best column). Items a vendor pays as much for stay in the bags for the merchant.",
    }) do
        b:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(L(text), 1, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function()
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)
    end
    -- The bottom row holds the posting buttons; checking the selected item's price sits at the end
    -- of the rule row above.
    UI.sellCheck = button(bar, "Check price", 100, function()
        if UI.sellSelected then
            F.Trade.checkPrice(UI.sellSelected.key)
            F.Engine.changed()
            UI.refresh()
        end
    end)
    UI.sellCheck:SetPoint("TOP", UI.ruleSave, "TOP", 0, 0)
    UI.sellCheck:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
end

-- Bag items for sale, or (hidden = true) the hidden items, also those no longer in the bags.
local function sellItems(hidden)
    local positions = F.Data.char(F.db, F.Engine.owner()).positions
    local items, byKey = {}, {}
    for _, b in ipairs(F.AH.bagItems()) do
        if F.Trade.hidden(b.key) == (hidden and true or false) then
            local merged = byKey[b.key]
            if merged then
                merged.count = merged.count + b.count
            else
                b.position = positions[b.key]
                items[#items + 1] = b
                byKey[b.key] = b
            end
        end
    end
    if hidden then
        for _, h in ipairs(F.Trade.hiddenItems()) do
            if not byKey[h.key] then
                local item = U.parseKey(h.key)
                items[#items + 1] = { key = h.key, id = item and item.id, count = 0, name = h.name, away = true }
            end
        end
    end
    table.sort(items, function(a, b)
        if (a.position ~= nil) ~= (b.position ~= nil) then
            return a.position ~= nil
        end
        return a.key < b.key
    end)
    return items
end

-- Capture every item in the selected category, independently of pagination and later updates.
function UI.statusTargets()
    local keys, scope, verifyDeals = {}, UI.section, false
    if UI.section == "deals" then
        scope, verifyDeals = "deals:" .. UI.filter, true
        for _, d in ipairs(F.Deals.visible(UI.filter)) do
            keys[#keys + 1] = d.key
        end
    elseif UI.section == "sell" then
        for _, item in ipairs(sellItems()) do
            keys[#keys + 1] = item.key
        end
    elseif UI.section == "auctions" then
        local seen = {}
        for _, a in ipairs(F.Trade.owned or {}) do
            if a.key and not a.sold and not seen[a.key] then
                seen[a.key] = true
                keys[#keys + 1] = a.key
            end
        end
    elseif UI.section == "shop" then
        -- The items on the shopping list are checked as deals: a lot under the list's maximum
        -- price becomes a shopping deal, one no longer there is dropped.
        verifyDeals = true
        for _, key in ipairs(F.Shopping.keys()) do
            keys[#keys + 1] = key
        end
    elseif UI.section == "bids" then
        verifyDeals = function(key, complete)
            return F.Bids.check(key, complete)
        end
        for _, c in ipairs(F.Bids.candidates) do
            keys[#keys + 1] = c.key
        end
    elseif UI.section == "crafting" then
        keys = F.Crafting.keys()
    else
        return nil, keys, false
    end
    return scope, keys, verifyDeals
end

function UI.checkStatuses()
    local scope, keys, verifyDeals = UI.statusTargets()
    if not scope or #keys == 0 then
        return
    end
    F.Deals.startBatch(scope, keys, verifyDeals)
    F.Engine.changed()
    UI.refresh()
end

function UI.refreshSell()
    local hiddenView = UI.sellView == "hidden"
    local listedNow = {}
    for _, l in ipairs(F.Data.char(F.db, F.Engine.owner()).listings) do
        listedNow[l.key] = (listedNow[l.key] or 0) + l.open
    end
    local ways = {}
    local function way(item)
        local w = ways[item.key]
        if not w then
            local name, value = F.Trade.bestWay(item.key, item.id)
            w = { name = name, value = value }
            ways[item.key] = w
        end
        return w
    end
    local items = UI.sellTable.sort(sellItems(hiddenView), function(item, column)
        local p = item.position
        if column == 5 then
            return way(item).value
        end
        return ({
            item.name or U.linkName(item.link) or nameOf(item.key),
            item.count,
            p and p.qty > 0 and p.cost / p.qty or nil,
            listedNow[item.key],
            nil,
            p and p.mode or nil,
        })[column]
    end)
    local hiddenCount = #F.Trade.hiddenItems()
    UI.sellSaleTab:SetText(L("For sale") .. " (" .. #sellItems(false) .. ")")
    UI.sellHiddenTab:SetText(L("Hidden") .. " (" .. hiddenCount .. ")")
    UI.sellSaleTab:SetEnabled(hiddenView)
    UI.sellHiddenTab:SetEnabled(not hiddenView)
    UI.sellHide:SetText(L(hiddenView and "Return to sale" or "Hide"))
    UI.sellHide:SetEnabled(UI.sellSelected ~= nil)
    local listings = {}
    for _, l in ipairs(F.Data.char(F.db, F.Engine.owner()).listings) do
        listings[l.key] = (listings[l.key] or 0) + l.open
    end
    for i, r in ipairs(UI.sellTable.rows) do
        local item = items[i]
        if item then
            r.item, r.key, r.link = item, item.key, item.link
            r.icon:SetTexture(icon(item.id))
            r.name:SetText(item.link or item.name or nameOf(item.key))
            r.cols[1]:SetText(item.away and "-" or item.count)
            local p = item.position
            r.cols[2]:SetText(p and p.qty > 0 and U.money(p.cost / p.qty) or "-")
            r.cols[3]:SetText(listings[item.key] or "-")
            r.cols[4]:SetText(UI.bestText(way(item)))
            if hiddenView then
                r.cols[5]:SetText(item.away and L("not in the bags") or L("hidden"))
            else
                local note = p
                    and (
                        p.mode == "vendor" and L("sell to a vendor")
                        or p.mode == "other" and L("bought elsewhere")
                        or L("bought for resale")
                    )
                r.cols[5]:SetText(note or "")
            end
            if UI.sellSelected and UI.sellSelected.key == item.key then
                r.selected:Show()
                UI.sellSelected = item
            else
                r.selected:Hide()
            end
            r:Show()
        else
            r.item, r.key = nil, nil
            r:Hide()
        end
    end
    local empty = UI.sellTable.empty
    if #items == 0 then
        empty:SetText(
            hiddenView
                    and L(
                        "No hidden items. Select an item under For sale and press Hide to keep it out of the list and out of Post all."
                    )
                or L("No items in your bags can be sold on the auction house.")
        )
        empty:Show()
    else
        empty:Hide()
    end
    if hiddenView then
        UI.sellText:SetText(
            UI.sellSelected and L("Return to sale puts the item back in the list and in Post all.")
                or L(
                    "Hidden items are not shown for sale and Post all and Post next bought skip them. Select one to return it."
                )
        )
        UI.postButton:Disable()
        UI.sellCheck:Disable()
        UI.ruleSave:Disable()
        UI.refreshPostNext()
        UI.refreshPostAll()
        return
    end
    for _, b in ipairs(UI.durations) do
        b:SetEnabled(F.db.settings.duration ~= b.value)
    end
    UI.refreshPostAll()
    UI.ruleSave:SetEnabled(UI.sellSelected ~= nil)
    local item = UI.sellSelected
    if not item then
        UI.sellText:SetText(L("Select an item. Its current listings are read to suggest a price."))
        UI.postButton:Disable()
        UI.refreshPostNext()
        UI.sellCheck:Disable()
        return
    end
    UI.sellCheck:SetEnabled(not F.Deals.pending(item.key) and not F.Trade.busy() and not F.Scan.blocking())
    local price, floor, cheapest, why = F.Trade.suggest(item)
    local lines = {}
    if item.position and item.position.mode == "vendor" then
        lines[#lines + 1] = L("Bought as a vendor deal: sell it to any vendor (button at the merchant).")
    end
    if price and not F.Trade.prices[item.key] and F.Scan.notListed(item.key) then
        lines[#lines + 1] = string.format(
            L("Nobody listed it at the last full scan (%d min ago)."),
            math.floor((F.Engine.clock() - F.Scan.last.at) / 60)
        )
    elseif price and F.Trade.noAnswer[item.key] and not F.Trade.prices[item.key] then
        lines[#lines + 1] = L("The auction house did not answer the check: nobody seems to sell it.")
    end
    if price then
        if UI.sellPrice:GetText() == "" then
            UI.sellPrice:SetText(U.plainMoney(math.max(price, floor or 0)))
        end
        if F.Trade.GUESSES[why] and UI.sellPrice.SetTextColor then
            UI.sellPrice:SetTextColor(1, 0.82, 0)
        elseif UI.sellPrice.SetTextColor then
            UI.sellPrice:SetTextColor(1, 1, 1)
        end
        if why == "normal" and cheapest then
            lines[#lines + 1] = string.format(
                L("The cheapest other seller asks %s, above the maximum. Suggested: the normal price %s."),
                U.money(cheapest),
                U.money(price)
            )
        elseif UI.FALLBACK_TEXT[why] then
            lines[#lines + 1] = string.format(L(UI.FALLBACK_TEXT[why]), U.money(price))
            if F.Trade.GUESSES[why] then
                lines[#lines + 1] = "|cffffd100"
                    .. L(
                        "This is a guess: check the price, change it if needed and press Post. Post next bought and Post all skip guessed prices."
                    )
                    .. "|r"
            end
        else
            lines[#lines + 1] = cheapest
                    and string.format(
                        L("Cheapest other seller: %s each. Suggested: %s."),
                        U.money(cheapest),
                        U.money(price)
                    )
                or L("Nobody else sells it now. Suggested: the usual asking price.")
        end
    elseif F.Deals.search and F.Deals.search.key == item.key then
        lines[#lines + 1] = L("Reading current listings...")
    elseif F.Deals.pending(item.key) then
        lines[#lines + 1] = L("queued")
    elseif F.Trade.prices[item.key] and F.Engine.clock() - F.Trade.prices[item.key].at <= 300 then
        lines[#lines + 1] = L(
            "Nobody sells it on the auction house now and ForeverFlip knows no price for it. Type a price and press Post; it is remembered for the next time."
        )
    elseif F.Trade.noAnswer[item.key] and F.Engine.clock() - F.Trade.noAnswer[item.key] <= 300 then
        lines[#lines + 1] =
            L("The auction house did not answer the check. Press Check price again, or type a price and press Post.")
    else
        lines[#lines + 1] = L("Press Check price to read the current listings.")
    end
    local h = F.Data.market(F.db, F.Engine.scope()).history[item.key]
    local timing = h and F.Market.timing(h, F.Engine.clock())
    if timing and timing.ready and timing.now <= 0.95 and timing.spread >= 0.08 then
        lines[#lines + 1] = string.format(
            L("Prices for it are usually %d%% higher on %s: posting then may pay more."),
            math.floor((timing.high.f / timing.now - 1) * 100 + 0.5),
            UI.slotName(timing.high)
        )
    end
    if floor then
        lines[#lines + 1] = string.format(
            L("Break-even after the %d%% cut: %s each."),
            math.floor(F.Market.CUT * 100 + 0.5),
            U.money(floor)
        )
        if price and price < floor then
            lines[#lines + 1] = "|cffff6060" .. L("The market is below your cost: wait or sell at a loss.") .. "|r"
        end
    end
    UI.sellText:SetText(table.concat(lines, "\n"))
    UI.postButton:SetEnabled(UI.sellPrice:GetText() ~= "")
    UI.refreshPostNext()
    UI.postButton:SetText(F.Trade.pendingPost and L("Confirm post") or L("Post"))
end

-- My auctions page ---------------------------------------------------------------------------------
local function timeLeft(seconds)
    if not seconds then
        return "-"
    end
    if seconds >= 3600 then
        return string.format("%d h", math.floor(seconds / 3600))
    end
    return string.format("%d min", math.floor(seconds / 60))
end

function UI.createAuctions(p)
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 60)
    UI.auctionTable = table_(
        list,
        {
            { "Name" },
            { "Qty", 50 },
            { "My price", 86 },
            { "Cheapest other", 104 },
            { "Status", 126, "LEFT" },
            { "Time left", 70 },
        },
        16,
        function(row)
            UI.ownedSelected = row.auction and row.auction.auctionID
            F.Engine.changed()
            UI.refresh()
        end
    )
    local bar = footer(p, 56)
    UI.auctionText = bar.text
    UI.cancelAuction = button(bar, "Cancel auction", 140, function()
        for _, a in ipairs(F.Trade.owned) do
            if a.auctionID == UI.ownedSelected then
                F.Trade.cancelAuction(a)
            end
        end
    end)
    UI.cancelAuction:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -6, 4)
    UI.cancelUndercut = button(bar, "Cancel undercut", 170, function()
        local _, why = F.Trade.cancelNextUndercut()
        F.Engine.notify(why)
    end)
    UI.cancelUndercut:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 6, 4)
    UI.checkOwned = button(bar, "Check prices", 130, function()
        F.Trade.checkOwned()
        UI.refreshAuctions()
    end)
    UI.checkOwned:SetPoint("RIGHT", UI.cancelAuction, "LEFT", -4, 0)
    UI.refreshOwned = button(bar, "Refresh", 100, function()
        F.Trade.ownedDue = 0
    end)
    UI.refreshOwned:SetPoint("RIGHT", UI.checkOwned, "LEFT", -4, 0)
end

function UI.refreshAuctions()
    local owned = UI.auctionTable.sort(F.Trade.owned or {}, function(a, column)
        local status, cheapest = F.Trade.ownedStatus(a)
        local rank = status == "sold" and 1
            or status == "undercut" and 2
            or (status == "cheapest" or status == "alone") and 3
            or 4
        return ({ nameOf(a.key or "", a.link), a.qty, a.price, cheapest, rank, a.timeLeft })[column]
    end)
    local undercutN = #F.Trade.undercutList()
    UI.cancelUndercut:SetText(L("Cancel undercut") .. " (" .. undercutN .. ")")
    UI.cancelUndercut:SetEnabled(undercutN > 0 and F.AH.isOpen())
    local selected, undercut = nil, 0
    for i, r in ipairs(UI.auctionTable.rows) do
        local a = owned[i]
        if a then
            r.auction, r.key, r.link = a, a.key, a.link
            r.icon:SetTexture(icon(a.id))
            r.name:SetText(a.link or nameOf(a.key or ("i:" .. a.id)))
            r.cols[1]:SetText(a.qty)
            r.cols[2]:SetText(U.money(a.price or 0))
            local status, cheapest = F.Trade.ownedStatus(a)
            r.cols[3]:SetText(cheapest and U.money(cheapest) or "-")
            if status == "sold" then
                r.cols[4]:SetText("|cff40ff40" .. L("sold, gold in the mail") .. "|r")
            elseif status == "undercut" then
                undercut = undercut + 1
                r.cols[4]:SetText("|cffff6060" .. L("undercut") .. "|r")
            elseif status == "cheapest" then
                r.cols[4]:SetText("|cff40ff40" .. L("cheapest") .. "|r")
            elseif status == "alone" then
                r.cols[4]:SetText("|cff40ff40" .. L("only yours") .. "|r")
            elseif status == "no_answer" then
                r.cols[4]:SetText("|cffffd100" .. L("no answer") .. "|r")
            else
                r.cols[4]:SetText("|cff999999" .. L("not checked") .. "|r")
            end
            r.cols[5]:SetText(a.sold and "" or timeLeft(a.timeLeft))
            if a.auctionID == UI.ownedSelected then
                r.selected:Show()
                selected = a
            else
                r.selected:Hide()
            end
            r:Show()
        else
            r.auction, r.key = nil, nil
            r:Hide()
        end
    end
    local empty = UI.auctionTable.empty
    if #owned == 0 then
        empty:SetText(L("You have no auctions, or the list has not loaded yet (press Refresh)."))
        empty:Show()
    else
        empty:Hide()
    end
    local queue = F.Trade.checksRemaining()
    local lines = {}
    if queue > 0 then
        lines[#lines + 1] = string.format(L("Checking prices: %d left."), queue)
    elseif undercut > 0 then
        lines[#lines + 1] = string.format(
            L("Undercut: %d. Cancel and post again a bit cheaper, or wait: cancelling loses the deposit."),
            undercut
        )
    else
        lines[#lines + 1] = L("Check prices to see which of your auctions are undercut.")
    end
    if selected and not selected.sold then
        local cost = F.AH.cancelCost(selected.auctionID)
        lines[#lines + 1] = string.format(L("Cancel cost besides the deposit: %s."), U.money(cost or 0))
    end
    UI.auctionText:SetText(table.concat(lines, "\n"))
    UI.cancelAuction:SetEnabled(selected ~= nil and not selected.sold)
    UI.checkOwned:SetEnabled(#owned > 0 and queue == 0)
end

-- Statistics page ----------------------------------------------------------------------------------
function UI.createStats(p)
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 60)
    UI.statsTable = table_(list, {
        { "Name" },
        { "Bought (col)", 52 },
        { "Sold (col)", 52 },
        { "Stock (col)", 52 },
        { "Profit", 90 },
        { "Days (col)", 52 },
        { "Sell %", 56 },
    }, 16, function() end)
    UI.statsText = footer(p, 56).text
end

function UI.refreshStats()
    local stats = UI.statsTable.sort(F.Trade.itemStats(), function(s, column)
        return ({ s.name, s.bought, s.sold, s.stock, s.sold > 0 and s.profit or nil, s.days, s.rate })[column]
    end)
    local stale = 0
    for i, r in ipairs(UI.statsTable.rows) do
        local s = stats[i]
        if s then
            local item = U.parseKey(s.key)
            r.key, r.link = s.key, nil
            r.icon:SetTexture(item and icon(item.id) or 134400)
            r.name:SetText(s.name)
            r.cols[1]:SetText(s.bought > 0 and s.bought or "-")
            r.cols[2]:SetText(s.sold > 0 and s.sold or "-")
            -- Stock that has not sold for 3 days or more is red.
            r.cols[3]:SetText(s.stock > 0 and (s.stale and "|cffff6060" .. s.stock .. "|r" or s.stock) or "-")
            if s.sold > 0 then
                r.cols[4]:SetText((s.profit < 0 and "|cffff6060-|r" or "") .. U.money(math.abs(s.profit)))
            else
                r.cols[4]:SetText("-")
            end
            r.cols[5]:SetText(s.days and string.format("%.1f", s.days) or "-")
            r.cols[6]:SetText(s.rate and string.format("%d%%", math.floor(s.rate * 100 + 0.5)) or "-")
            r.selected:Hide()
            r:Show()
        else
            r.key = nil
            r:Hide()
        end
    end
    for _, s in ipairs(stats) do
        if s.stale then
            stale = stale + 1
        end
    end
    local empty = UI.statsTable.empty
    if #stats == 0 then
        empty:SetText(L("No trades yet. Items appear here after the first purchase."))
        empty:Show()
    else
        empty:Hide()
    end
    local sum = F.Trade.summary(7)
    UI.statsText:SetText(
        string.format(
            L("7 days: profit of closed sales %s · in stock %s · stale items (3+ days without a sale): %d"),
            U.money(sum.profit),
            U.money(sum.held),
            stale
        )
    )
end

-- Analytics page -----------------------------------------------------------------------------------
local MARKET_VIEWS = {
    { "gaps", "Below usual" },
    { "liquid", "Sells most" },
    { "falling", "Falling" },
    { "rising", "Rising" },
    { "cheapNow", "Cheap now" },
    { "sellNow", "Sell now" },
}

local DAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local PARTS = { "night", "morning", "day", "evening" }
local function slotName(s)
    return L(DAYS[s.w]) .. " " .. L(PARTS[s.p])
end
UI.slotName = slotName

function UI.createAnalytics(p)
    UI.analyticsDays, UI.marketView = 7, "gaps"
    local top = CreateFrame("Frame", nil, p)
    top:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, 0)
    top:SetHeight(176)
    UI.resultsText = text(top, "GameFontHighlightSmall")
    UI.resultsText:SetPoint("TOPLEFT", top, "TOPLEFT", 10, -8)
    UI.resultsText:SetWidth(300)
    UI.resultsText:SetSpacing(3)
    UI.periodButtons = {}
    for i, n in ipairs({ 7, 30 }) do
        local b = button(top, n == 7 and "7 days" or "30 days", 70, function()
            UI.analyticsDays = n
            UI.refresh()
        end)
        b:SetPoint("TOPRIGHT", top, "TOPRIGHT", -8 - (2 - i) * 74, -6)
        UI.periodButtons[n] = b
    end
    -- Profit per day: bars above (profit) or below (loss) a zero line.
    local chart = CreateFrame("Frame", nil, top)
    chart:SetPoint("TOPRIGHT", top, "TOPRIGHT", -8, -34)
    chart:SetSize(300, 120)
    local zero = chart:CreateTexture(nil, "ARTWORK")
    zero:SetColorTexture(1, 1, 1, 0.25)
    zero:SetHeight(1)
    zero:SetPoint("LEFT", chart, "LEFT", 0, 10)
    zero:SetPoint("RIGHT", chart, "RIGHT", 0, 10)
    UI.chart, UI.bars = chart, {}
    UI.chartTitle = text(top, "GameFontNormalSmall")
    UI.chartTitle:SetPoint("BOTTOMLEFT", chart, "TOPLEFT", 0, 2)

    local views = CreateFrame("Frame", nil, p)
    views:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, 0)
    views:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, 0)
    views:SetHeight(26)
    UI.viewButtons = {}
    for i, v in ipairs(MARKET_VIEWS) do
        local b = button(views, v[2], 92, function()
            UI.marketView = v[1]
            UI.refresh()
        end)
        b:SetPoint("LEFT", views, "LEFT", 6 + (i - 1) * 95, 0)
        UI.viewButtons[v[1]] = b
    end
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", views, "BOTTOMLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 22)
    UI.marketTable = table_(
        list,
        {
            { "Name" },
            { "Usual price", 84 },
            { "Cheapest today", 92 },
            { "Change", 60 },
            { "Est./day", 64 },
        },
        9,
        function(row)
            if row.key then
                F.Deals.verify(row.key)
                F.Engine.notify("verify_first")
            end
        end
    )
    UI.marketText = text(p, "GameFontHighlightSmall")
    UI.marketText:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 8, 6)
    UI.marketText:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -8, 6)
end

local function percent(x)
    if not x then
        return "-"
    end
    local v = x * 100
    v = v >= 0 and math.floor(v + 0.5) or -math.floor(-v + 0.5)
    return string.format("%+d%%", v)
end

function UI.refreshAnalytics()
    local days = UI.analyticsDays or 7
    for n, b in pairs(UI.periodButtons) do
        b:SetEnabled(n ~= days)
    end
    local r = F.Analytics.results(days)
    local lines = {
        string.format(L("Profit: %s (%s a day)"), U.money(r.profit), U.money(math.floor(r.perDay))),
        string.format(L("Auction resale: %s · vendor: %s"), U.money(r.auction), U.money(r.vendor)),
        string.format(
            L("Sales: %d · profitable: %s · return on cost: %s"),
            r.sales,
            r.hitRate and string.format("%d%%", math.floor(r.hitRate * 100 + 0.5)) or "-",
            r.roi and string.format("%d%%", math.floor(r.roi * 100 + 0.5)) or "-"
        ),
        string.format(L("Bought: %d for %s"), r.buys, U.money(r.spent)),
        string.format(
            L("In stock: %s · stale 3+ days: %s"),
            U.money(r.held),
            r.stale > 0 and ("|cffff6060" .. U.money(r.stale) .. "|r") or U.money(0)
        ),
        string.format(
            L("Days to sell: %s · stock turns over %s a day"),
            r.avgDays and string.format("%.1f", r.avgDays) or "-",
            r.turnover and string.format("%d%%", math.floor(r.turnover * 100 + 0.5)) or "-"
        ),
    }
    local realm = F.Analytics.realm(UI.analyticsDays or 7)
    if realm.chars > 0 then
        lines[#lines + 1] = string.format(
            L("All characters of the realm (%d): gold %s (%s over the period) · stock at cost %s"),
            realm.chars,
            U.money(realm.gold),
            (realm.gold >= realm.before and "+" or "") .. U.money(realm.gold - realm.before),
            U.money(realm.stock)
        )
    end
    if #r.best > 0 then
        local names = {}
        for _, item in ipairs(r.best) do
            names[#names + 1] = (item.name or item.key) .. " " .. U.money(item.profit)
        end
        lines[#lines + 1] = "|cff40ff40" .. L("Best:") .. "|r " .. table.concat(names, ", ")
    end
    if #r.worst > 0 then
        local names = {}
        for _, item in ipairs(r.worst) do
            names[#names + 1] = (item.name or item.key) .. " " .. U.money(item.profit)
        end
        lines[#lines + 1] = "|cffff6060" .. L("Worst:") .. "|r " .. table.concat(names, ", ")
    end
    UI.resultsText:SetText(table.concat(lines, "\n"))
    -- Chart.
    UI.chartTitle:SetText(string.format(L("Profit per day, last %d days"), days))
    local maxAbs = 1
    for _, d in ipairs(r.days) do
        maxAbs = math.max(maxAbs, math.abs(d.profit))
    end
    local width = math.floor(300 / #r.days)
    for i, d in ipairs(r.days) do
        local bar = UI.bars[i]
        if not bar then
            bar = UI.chart:CreateTexture(nil, "ARTWORK")
            UI.bars[i] = bar
        end
        local h = math.max(1, math.floor(math.abs(d.profit) / maxAbs * 50))
        bar:ClearAllPoints()
        bar:SetWidth(math.max(2, width - 2))
        bar:SetHeight(h)
        if d.profit >= 0 then
            bar:SetColorTexture(0.25, 0.85, 0.35, 0.9)
            bar:SetPoint("BOTTOMLEFT", UI.chart, "LEFT", (i - 1) * width, 10)
        else
            bar:SetColorTexture(0.9, 0.3, 0.3, 0.9)
            bar:SetPoint("TOPLEFT", UI.chart, "LEFT", (i - 1) * width, 10)
        end
        bar:Show()
    end
    for i = #r.days + 1, #UI.bars do
        UI.bars[i]:Hide()
    end
    -- Market lists.
    for id, b in pairs(UI.viewButtons) do
        b:SetEnabled(id ~= UI.marketView)
    end
    local m = F.Analytics.market()
    local timingView = UI.marketView == "cheapNow" or UI.marketView == "sellNow"
    local list = UI.marketTable.sort(m[UI.marketView] or {}, function(e, column)
        if column == 1 then
            return nameOf(e.key)
        elseif column == 2 then
            return e.market
        elseif column == 3 then
            return timingView and e.timing and e.timing.now or e.cheap
        elseif column == 4 then
            return timingView and e.timing and e.timing.now or e.change
        end
        return e.perDay
    end)
    for i, row in ipairs(UI.marketTable.rows) do
        local e = list[i]
        if e then
            local item = U.parseKey(e.key)
            row.key, row.link = e.key, nil
            row.icon:SetTexture(item and icon(item.id) or 134400)
            row.name:SetText(nameOf(e.key))
            row.cols[1]:SetText(U.money(e.market))
            if (UI.marketView == "cheapNow" or UI.marketView == "sellNow") and e.timing then
                -- Timing views: when it is cheapest/dearest and how now compares.
                local s = UI.marketView == "cheapNow" and e.timing.high or e.timing.low
                row.cols[2]:SetText((UI.marketView == "cheapNow" and L("sell: ") or L("buy: ")) .. slotName(s))
                row.cols[3]:SetText(percent(e.timing.now - 1))
            else
                row.cols[2]:SetText(e.cheap and U.money(e.cheap) or "-")
                row.cols[3]:SetText(percent(e.change))
            end
            row.cols[4]:SetText(e.perDay and string.format("~%.1f", e.perDay) or "-")
            row.selected:Hide()
            row:Show()
        else
            row.key = nil
            row:Hide()
        end
    end
    local empty = UI.marketTable.empty
    if #list == 0 then
        empty:SetText(
            L("No data yet. Market lists fill in after a few full scans; price moves need scans on two different days.")
        )
        empty:Show()
    else
        empty:Hide()
    end
    UI.marketText:SetText(
        string.format(L("%d items with history · click a row to check it on the auction house now"), m.items)
    )
end

-- Crafting page ------------------------------------------------------------------------------------
local CRAFT_ROWS = 15
function UI.createCrafting(p)
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 76)
    UI.craftTable = table_(
        list,
        {
            { "Name" },
            { "Materials", 86 },
            { "Product", 86 },
            { "Profit", 86 },
            { "Est./day", 64 },
            { "Sell to", 70, "LEFT" },
        },
        CRAFT_ROWS,
        function(row)
            UI.craftSelected = row.recipe
            UI.refresh()
        end
    )
    local bar = footer(p, 72)
    UI.craftText = bar.text
    UI.craftShop = button(bar, "Shop materials", 150, function()
        local r = UI.craftSelected
        if r then
            local count = math.max(1, math.floor(r.perDay or 1))
            local n = F.Crafting.shopMaterials(r.id, count)
            F.Engine.notify(n > 0 and "saved" or "values")
        end
    end)
    UI.craftShop:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -6, 4)
end

function UI.refreshCrafting()
    local rows = UI.craftTable.sort(F.Crafting.profits(), function(e, column)
        return ({ e.name, e.cost, e.value, e.profit, e.perDay, e.route })[column]
    end)
    for i, r in ipairs(UI.craftTable.rows) do
        local e = rows[i]
        if e then
            r.recipe, r.key = e, nil
            r.icon:SetTexture(icon(e.out))
            r.name:SetText(e.name or ("#" .. e.id))
            r.cols[1]:SetText(e.cost and U.money(e.cost) or "?")
            r.cols[2]:SetText(e.value and U.money(e.value) or "?")
            if e.profit then
                r.cols[3]:SetText((e.profit < 0 and "|cffff6060" or "|cff40ff40") .. U.money(e.profit) .. "|r")
            else
                r.cols[3]:SetText("-")
            end
            r.cols[4]:SetText(e.perDay and string.format("~%.1f", e.perDay) or "-")
            r.cols[5]:SetText(e.route and L(e.route == "vendor" and "vendor" or "auction") or "")
            if UI.craftSelected and UI.craftSelected.id == e.id then
                r.selected:Show()
                UI.craftSelected = e
            else
                r.selected:Hide()
            end
            r:Show()
        else
            r.recipe = nil
            r:Hide()
        end
    end
    local empty = UI.craftTable.empty
    if #rows == 0 then
        empty:SetText(
            L(
                "Open each of your profession windows once: ForeverFlip reads the recipes and prices them here with the auction prices of the materials and the product."
            )
        )
        empty:Show()
    else
        empty:Hide()
    end
    local s = UI.craftSelected
    if s and s.missing then
        UI.craftText:SetText(
            L("A material of this recipe has no price yet: it needs a full scan or a merchant that sells it.")
        )
    elseif s then
        UI.craftText:SetText(
            string.format(
                L(
                    "Materials %s, product %s (%s): profit %s per craft. Shop materials puts one day of crafts on the shopping list."
                ),
                U.money(s.cost),
                U.money(s.value or 0),
                L(s.route == "vendor" and "vendor" or "auction"),
                U.money(s.profit or 0)
            )
        )
    else
        UI.craftText:SetText(L("Material prices: the cheaper of the usual auction price and a merchant's price."))
    end
    UI.craftShop:SetEnabled(s ~= nil and not s.missing)
end

-- Journal page -------------------------------------------------------------------------------------
function UI.createJournal(p)
    UI.journalSummary = text(p, "GameFontHighlight")
    UI.journalSummary:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -10)
    UI.journalSummary:SetPoint("TOPRIGHT", p, "TOPRIGHT", -10, -10)
    UI.journalSummary:SetSpacing(4)
    UI.unknownText = text(p, "GameFontNormal")
    UI.unknownText:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -64)
    UI.unknownText:SetPoint("TOPRIGHT", p, "TOPRIGHT", -10, -64)
    UI.unknownYes = button(p, "It was bought", 130, function()
        F.Trade.settle(1, true)
    end)
    UI.unknownYes:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -84)
    UI.unknownNo = button(p, "Not bought", 130, function()
        F.Trade.settle(1, false)
    end)
    UI.unknownNo:SetPoint("LEFT", UI.unknownYes, "RIGHT", 6, 0)
    UI.exportButton = button(p, "Export CSV", 120, function()
        UI.showExport()
    end)
    UI.exportButton:SetPoint("TOPRIGHT", p, "TOPRIGHT", -10, -84)
    UI.journalLines = text(p, "GameFontHighlightSmall")
    UI.journalLines:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -116)
    UI.journalLines:SetPoint("TOPRIGHT", p, "TOPRIGHT", -10, -116)
    UI.journalLines:SetSpacing(4)
end

function UI.refreshJournal()
    local s = F.Trade.summary(7)
    UI.journalSummary:SetText(
        string.format(
            L("Last 7 days: spent %s · received %s · profit of closed sales %s\nIn stock (bought, not sold yet): %s"),
            U.money(s.spent),
            U.money(s.earned),
            U.money(s.profit),
            U.money(s.held)
        )
    )
    local c = F.Data.char(F.db, F.Engine.owner())
    local u = c.unknown and c.unknown[1]
    if u then
        UI.unknownText:SetText(
            string.format(
                L('Unconfirmed purchase: %d x %s for %s. Check the chat for "You won an auction".'),
                u.qty,
                u.name,
                U.money(u.cost)
            )
        )
        UI.unknownYes:Show()
        UI.unknownNo:Show()
    else
        UI.unknownText:SetText("")
        UI.unknownYes:Hide()
        UI.unknownNo:Hide()
    end
    local lines = {}
    local kinds = {
        buy = "bought",
        sell = "sold",
        vendor = "sold to vendor",
        expired = "came back unsold",
        fail = "purchase failed",
    }
    for i = #c.journal, math.max(1, #c.journal - 16), -1 do
        local e = c.journal[i]
        lines[#lines + 1] = string.format(
            "%s  %s  %d x %s  %s%s",
            date("%d.%m %H:%M", e.at),
            L(kinds[e.kind] or e.kind),
            e.qty or 0,
            e.name or "?",
            U.money(e.amount or 0),
            e.profit and ("  (" .. L("profit") .. " " .. U.money(e.profit) .. ")") or ""
        )
    end
    UI.journalLines:SetText(#lines > 0 and table.concat(lines, "\n") or L("No trades yet."))
end

-- CSV export: the journal of the character in a text box to copy (Ctrl+A, Ctrl+C).
function UI.showExport()
    UI.showText(L("Journal as CSV: press Ctrl+A, then Ctrl+C to copy."), F.Analytics.csv())
end

-- A window with a text to copy, or (with onImport) a box to paste into and an Import button.
function UI.showText(title, value, onImport)
    local w = UI.exportFrame
    if not w then
        w = CreateFrame("Frame", "ForeverFlipExport", UIParent)
        w:SetSize(640, 420)
        w:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        w:SetFrameStrata("DIALOG")
        local bg = w:CreateTexture(nil, "BACKGROUND")
        bg:SetColorTexture(0.05, 0.05, 0.06, 0.95)
        bg:SetAllPoints()
        w.title = text(w, "GameFontNormal")
        w.title:SetPoint("TOPLEFT", w, "TOPLEFT", 12, -10)
        w.title:SetText(L("Journal as CSV: press Ctrl+A, then Ctrl+C to copy."))
        w.close = button(w, "X", 24, function()
            w:Hide()
        end)
        w.close:SetPoint("TOPRIGHT", w, "TOPRIGHT", -6, -6)
        local scroll = CreateFrame("ScrollFrame", nil, w, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", w, "TOPLEFT", 12, -34)
        scroll:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -32, 12)
        w.box = CreateFrame("EditBox", nil, scroll)
        w.box:SetMultiLine(true)
        w.box:SetAutoFocus(false)
        w.box:SetFontObject(ChatFontNormal or "GameFontHighlightSmall")
        w.box:SetWidth(580)
        w.box:SetScript("OnEscapePressed", function()
            w:Hide()
        end)
        scroll:SetScrollChild(w.box)
        UI.exportFrame = w
    end
    if not rawget(w, "import") then
        w.import = button(w, "Import", 110, function()
            if w.onImport and w.onImport(w.box:GetText()) then
                w:Hide()
            end
        end)
        w.import:SetPoint("TOPRIGHT", w.close, "TOPLEFT", -6, 0)
    end
    w.title:SetText(title)
    w.onImport = onImport
    if onImport then
        w.import:Show()
    else
        w.import:Hide()
    end
    w.box:SetText(value or "")
    w:Show()
    w.box:SetFocus()
    w.box:HighlightText()
end

-- Settings page ------------------------------------------------------------------------------------
-- Four tabs: General, Key bindings, Sharing, Safety.
function UI.createSettings(p)
    UI.settingTabs, UI.settingFrames = {}, {}
    local tabs = {
        { "general", "General" },
        { "keys", "Key bindings" },
        { "share", "Sharing" },
        { "safety", "Safety" },
    }
    for i, t in ipairs(tabs) do
        local frame = CreateFrame("Frame", nil, p)
        frame:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -30)
        frame:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
        UI.settingFrames[t[1]] = frame
        local b = button(p, t[2], 140, function()
            UI.showSettingsTab(t[1])
        end)
        b:SetPoint("TOPLEFT", p, "TOPLEFT", 8 + (i - 1) * 146, -4)
        UI.settingTabs[t[1]] = b
    end
    UI.createGeneralSettings(UI.settingFrames.general)
    UI.createKeySettings(UI.settingFrames.keys)
    UI.createShareSettings(UI.settingFrames.share)
    UI.createSafetySettings(UI.settingFrames.safety)
    UI.showSettingsTab("general")
end

-- Safety: the vendor price margin, the spending limit, lots left for others, and what was learned.
function UI.createSafetySettings(p)
    local fields = {
        { "vendorMargin", "Vendor prices not yet confirmed at a merchant count less, %" },
        { "spendLimit", "Gold one auction house visit may spend on deals (0 = no limit)" },
        { "leaveLots", "Cheap units of a vendor deal left for other buyers" },
    }
    UI.safetyBoxes = {}
    for i, f in ipairs(fields) do
        local label = text(p, "GameFontNormal")
        label:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -6 - (i - 1) * 23)
        label:SetWidth(380)
        label:SetText(L(f[2]))
        local e = editbox(p, 80)
        e:SetPoint("LEFT", label, "RIGHT", 10, 0)
        e.field = f
        UI.safetyBoxes[i] = e
    end
    UI.safetySave = button(p, "Save", 110, function()
        for _, e in ipairs(UI.safetyBoxes) do
            local v = tonumber(e:GetText())
            if v and v >= 0 then
                if e.field[1] == "vendorMargin" then
                    v = U.clamp(math.floor(v), 0, 90)
                end
                F.db.settings[e.field[1]] = math.floor(v)
            end
        end
        UI.loadSafety()
        F.Engine.notify("saved")
    end)
    UI.safetySave:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -6 - #fields * 23 - 4)
    UI.safetyText = text(p, "GameFontHighlightSmall")
    UI.safetyText:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -6 - #fields * 23 - 40)
    UI.safetyText:SetPoint("TOPRIGHT", p, "TOPRIGHT", -12, -6 - #fields * 23 - 40)
    UI.safetyText:SetSpacing(3)
    UI.loadSafety()
end

function UI.loadSafety()
    for _, e in ipairs(UI.safetyBoxes or {}) do
        e:SetText(tostring(F.db.settings[e.field[1]] or 0))
    end
end

function UI.refreshSafety()
    if not UI.safetyText then
        return
    end
    local lines = {}
    local seen = 0
    for _ in pairs(F.db.vendorSeen or {}) do
        seen = seen + 1
    end
    local differ = F.Merchant.differences()
    lines[#lines + 1] = string.format(
        L("Vendor prices confirmed at merchants: %d; different from the game's item data: %d."),
        seen,
        #differ
    )
    for i = 1, math.min(5, #differ) do
        local d = differ[i]
        local name = U.itemInfo(d.id) or ("item " .. d.id)
        lines[#lines + 1] = string.format("  %s: %s (%s %s)", name, U.money(d.seen), L("game says"), U.money(d.client))
    end
    lines[#lines + 1] = L("Sell an item to any merchant once and its real price is used from then on.")
    local bands, learned = 0, 0
    for _, b in pairs(F.db.deSeen or {}) do
        bands = bands + 1
        if (b.n or 0) >= F.Disenchant.LEARN then
            learned = learned + 1
        end
    end
    lines[#lines + 1] = string.format(
        L("Own disenchants: %d item bands seen, %d used instead of the table (from %d disenchants each)."),
        bands,
        learned,
        F.Disenchant.LEARN
    )
    local limit = tonumber(F.db.settings.spendLimit) or 0
    if limit > 0 then
        lines[#lines + 1] = string.format(
            L("Spent on deals this visit: %s of %s."),
            U.money(F.Engine.spent or 0),
            U.money(limit * 10000)
        )
    end
    if (F.AH.forced or 0) > 0 then
        lines[#lines + 1] = string.format(
            L("The auction house throttle was stuck %d times; ForeverFlip went on after 5 seconds."),
            F.AH.forced
        )
    end
    UI.safetyText:SetText(table.concat(lines, "\n"))
end

-- The client did not hand over any saved data. On a first install that is normal; otherwise the
-- file was not read, and playing on would overwrite it at logout. The player decides.
function UI.noSavedData()
    if not StaticPopupDialogs or not StaticPopup_Show then
        print("ForeverFlip: " .. L("No saved data was loaded. If you used ForeverFlip before, type /reload now."))
        return
    end
    StaticPopupDialogs.FOREVERFLIP_NO_DATA = {
        text = L(
            "ForeverFlip found no saved data.\n\nFirst time? Press Continue.\n\nUsed it before? The game did not read the file: press Reload. Playing on would replace your history at logout."
        ),
        button1 = L("Reload"),
        button2 = L("Continue"),
        OnAccept = function()
            if ReloadUI then
                ReloadUI()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = false,
    }
    StaticPopup_Show("FOREVERFLIP_NO_DATA")
end

function UI.showSettingsTab(id)
    UI.settingsTab = id
    for key, frame in pairs(UI.settingFrames) do
        if key == id then
            frame:Show()
        else
            frame:Hide()
        end
        UI.settingTabs[key]:SetEnabled(key ~= id)
    end
    UI.refresh()
end

-- Key bindings: click a button, press the key. Right-click clears; Escape cancels.
UI.BINDINGS = {
    { "FOREVERFLIP_BUY", "Buy or confirm the selected deal" },
    { "FOREVERFLIP_BUY_NEXT", "Buy the next best deal (check, buy, confirm)" },
    { "FOREVERFLIP_POST", "Post next bought (then Post all)" },
    { "FOREVERFLIP_CANCEL", "Cancel the next undercut auction" },
    { "FOREVERFLIP_SCAN", "Full scan" },
}
local MODIFIER_KEYS = {
    LSHIFT = true,
    RSHIFT = true,
    LCTRL = true,
    RCTRL = true,
    LALT = true,
    RALT = true,
    UNKNOWN = true,
}

function UI.bindingKey(command)
    return GetBindingKey and GetBindingKey(command) or nil
end

-- Binds `key` to `command` in the character's (or account's) binding set; nil key clears it.
function UI.setBinding(command, key)
    if InCombatLockdown and InCombatLockdown() then
        F.Engine.notify("combat")
        return false
    end
    local old = UI.bindingKey(command)
    while old do
        SetBinding(old)
        local again = UI.bindingKey(command)
        if again == old then
            break
        end
        old = again
    end
    if key then
        SetBinding(key, command)
    end
    if SaveBindings and GetCurrentBindingSet then
        SaveBindings(GetCurrentBindingSet())
    end
    F.Engine.changed()
    return true
end

-- A key press as the game names it in bindings: "CTRL-SHIFT-B".
function UI.keyName(key)
    local prefix = ""
    if IsAltKeyDown and IsAltKeyDown() then
        prefix = prefix .. "ALT-"
    end
    if IsControlKeyDown and IsControlKeyDown() then
        prefix = prefix .. "CTRL-"
    end
    if IsShiftKeyDown and IsShiftKeyDown() then
        prefix = prefix .. "SHIFT-"
    end
    return prefix .. key
end

function UI.captureKey(command)
    UI.capturing = command
    local c = UI.keyCatcher
    if not c then
        c = CreateFrame("Frame", nil, UIParent)
        c:SetAllPoints(UIParent)
        c:SetFrameStrata("TOOLTIP")
        if c.EnableKeyboard then
            c:EnableKeyboard(true)
        end
        if c.SetPropagateKeyboardInput then
            c:SetPropagateKeyboardInput(false)
        end
        c:SetScript("OnKeyDown", function(_, key)
            UI.onCapturedKey(key)
        end)
        UI.keyCatcher = c
    end
    c:Show()
    UI.refresh()
end

function UI.onCapturedKey(key)
    local command = UI.capturing
    if not command or MODIFIER_KEYS[key] then
        return
    end
    UI.capturing = nil
    if UI.keyCatcher then
        UI.keyCatcher:Hide()
    end
    if key ~= "ESCAPE" then
        UI.setBinding(command, UI.keyName(key))
    end
    UI.refresh()
end

function UI.createKeySettings(p)
    UI.keyButtons = {}
    for i, b in ipairs(UI.BINDINGS) do
        local label = text(p, "GameFontNormal")
        label:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -14 - (i - 1) * 34)
        label:SetWidth(300)
        label:SetText(L(b[2]))
        local key = button(p, "", 170, function()
            UI.captureKey(b[1])
        end)
        key:SetPoint("LEFT", label, "RIGHT", 10, 0)
        if key.RegisterForClicks then
            key:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        end
        key:SetScript("OnClick", function(_, mouse)
            if mouse == "RightButton" then
                UI.setBinding(b[1], nil)
            else
                UI.captureKey(b[1])
            end
        end)
        key.command = b[1]
        UI.keyButtons[i] = key
    end
    UI.keyText = text(p, "GameFontHighlightSmall")
    UI.keyText:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -14 - #UI.BINDINGS * 34 - 10)
    UI.keyText:SetPoint("TOPRIGHT", p, "TOPRIGHT", -12, -14 - #UI.BINDINGS * 34 - 10)
    UI.keyText:SetText(
        L(
            "Click a button, then press the key (with Shift, Ctrl or Alt if you like). Right-click clears a key; Escape cancels. The same keys are in the game's Key Bindings window under AddOns."
        )
    )
end

function UI.refreshKeys()
    for _, b in ipairs(UI.keyButtons or {}) do
        if UI.capturing == b.command then
            b:SetText("|cffffd100" .. L("Press a key...") .. "|r")
        else
            b:SetText(UI.bindingKey(b.command) or L("Not bound"))
        end
    end
end

-- Sharing full scans with other players.
function UI.createShareSettings(p)
    local function toggle(y, setting, label)
        local box = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
        box:SetPoint("TOPLEFT", p, "TOPLEFT", 8, y)
        box:SetScript("OnClick", function(self)
            F.db.settings[setting] = self:GetChecked() and true or false
        end)
        box:SetChecked(F.db.settings[setting])
        local t = text(p, "GameFontHighlight")
        t:SetPoint("LEFT", box, "RIGHT", 4, 0)
        t:SetText(L(label))
        return box
    end
    toggle(-8, "shareReceive", "Accept full scans shared by guild and group members")
    toggle(-36, "shareAuto", "Send my full scans to the guild after each scan")
    toggle(-64, "rawScans", "Keep my full scans for the ForeverFlip Sync helper (community data)")
    local channel = toggle(-92, "shareChannel", "Share full scans with every ForeverFlip user of the realm")
    channel:HookScript("OnClick", function(self)
        if self:GetChecked() then
            F.Share.join()
        else
            F.Share.leave()
        end
    end)
    local send = text(p, "GameFontNormal")
    send:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -132)
    send:SetText(L("Send my last scan to:"))
    UI.shareGuild = button(p, "Guild", 100, function()
        local _, why = F.Share.send("GUILD")
        F.Engine.notify(why)
    end)
    UI.shareGuild:SetPoint("LEFT", send, "RIGHT", 10, 0)
    UI.shareGroup = button(p, "Group", 100, function()
        local _, why = F.Share.send((IsInRaid and IsInRaid()) and "RAID" or "PARTY")
        F.Engine.notify(why)
    end)
    UI.shareGroup:SetPoint("LEFT", UI.shareGuild, "RIGHT", 4, 0)
    local whisper = text(p, "GameFontNormal")
    whisper:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -164)
    whisper:SetText(L("Player:"))
    UI.shareName = editbox(p, 140)
    UI.shareName:SetPoint("LEFT", whisper, "RIGHT", 10, 0)
    UI.shareWhisper = button(p, "Send", 100, function()
        local _, why = F.Share.send("WHISPER", UI.shareName:GetText())
        F.Engine.notify(why)
    end)
    UI.shareWhisper:SetPoint("LEFT", UI.shareName, "RIGHT", 8, 0)
    UI.shareExport = button(p, "Export as text", 150, function()
        local snap = F.Share.snapshot()
        if not snap then
            F.Engine.notify("no_scan")
            return
        end
        UI.showText(
            L("Last full scan as text: press Ctrl+A, then Ctrl+C, and send it to a friend."),
            F.Share.encode(snap)
        )
    end)
    UI.shareExport:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -198)
    UI.shareImport = button(p, "Import text", 150, function()
        UI.showText(L("Paste a shared scan (Ctrl+V), then press Import."), "", function(textValue)
            local merged, why = F.Share.import(textValue)
            F.Engine.notify(merged and "share_received" or why)
            return merged ~= nil
        end)
    end)
    UI.shareImport:SetPoint("LEFT", UI.shareExport, "RIGHT", 6, 0)
    UI.shareText = text(p, "GameFontHighlightSmall")
    UI.shareText:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -236)
    UI.shareText:SetPoint("TOPRIGHT", p, "TOPRIGHT", -12, -236)
    UI.shareText:SetSpacing(3)
end

function UI.refreshShare()
    local lines = {
        L(
            "A shared scan adds other players' prices of your realm to the history: more days, the weekly pattern, and a fresh usual price when your own scan is older. It never creates deals by itself, and the other player needs ForeverFlip too."
        ),
    }
    local s = F.Share.sending
    if #F.Share.outbox > 0 and s then
        lines[#lines + 1] = string.format(L("Sending %d items: %d messages left."), s.items, #F.Share.outbox)
    end
    local community = F.Raw.community
    if community and community.generated then
        lines[#lines + 1] =
            string.format(L("Community data: %d scans, updated %s."), community.scans, UI.age(community.generated))
    else
        lines[#lines + 1] = L("Community data: none. Run the ForeverFlip Sync helper to get it.")
    end
    if F.db.settings.rawScans then
        local saved = F.Raw.saved()
        lines[#lines + 1] = string.format(L("Full scans kept for the helper: %d."), #saved)
    end
    if #F.Share.received > 0 then
        lines[#lines + 1] = L("Received:")
        for i = 1, math.min(5, #F.Share.received) do
            local r = F.Share.received[i]
            lines[#lines + 1] = string.format("  %s: %d, %s", r.from, r.items, UI.age(r.at))
        end
    else
        lines[#lines + 1] = L("No shared scan received yet.")
    end
    UI.shareText:SetText(table.concat(lines, "\n"))
    local busy = #F.Share.outbox > 0
    UI.shareGuild:SetEnabled(not busy and F.Scan.last ~= nil)
    UI.shareGroup:SetEnabled(not busy and F.Scan.last ~= nil)
    UI.shareWhisper:SetEnabled(not busy and F.Scan.last ~= nil)
    UI.shareExport:SetEnabled(F.Scan.last ~= nil)
end

function UI.createGeneralSettings(p)
    local fields = {
        { "vendorMinProfit", "Minimum profit of a vendor deal", "money" },
        { "minProfit", "Minimum profit of a resale", "money" },
        { "minROI", "Minimum resale return, %", "percent" },
        { "spendShare", "Money one deal may use, %", "percent" },
        { "itemShare", "Money one item may hold (stock and new resale), %", "percent" },
        { "alertMinProfit", "Smallest profit with a sound notice", "money" },
        { "undercutPercent", "Undercut, % (0 = one price step)", "percent" },
        { "minPricePercent", "Never post below, % of the usual price", "percent" },
        { "maxPricePercent", "Ignore sellers above, % of the usual price", "percent+" },
    }
    UI.settingBoxes = {}
    for i, f in ipairs(fields) do
        local label = text(p, "GameFontNormal")
        label:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -6 - (i - 1) * 23)
        label:SetWidth(300)
        label:SetText(L(f[2]))
        local e = editbox(p, 110)
        e:SetPoint("LEFT", label, "RIGHT", 10, 0)
        e.field = f
        UI.settingBoxes[i] = e
    end
    local y = -6 - #fields * 23
    UI.saveButton = button(p, "Save", 110, function()
        for _, e in ipairs(UI.settingBoxes) do
            local key, kind = e.field[1], e.field[3]
            local v = kind == "money" and U.parseMoney(e:GetText()) or tonumber(e:GetText())
            if v and v >= 0 then
                if kind == "percent" then
                    v = U.clamp(v / 100, 0, 1)
                elseif kind == "percent+" then
                    v = U.clamp(v / 100, 0, 10)
                end
                F.db.settings[key] = v
            end
        end
        UI.loadSettings()
        F.Engine.notify("saved")
    end)
    UI.saveButton:SetPoint("TOPLEFT", p, "TOPLEFT", 12, y)
    local presetLabel = text(p, "GameFontNormal")
    presetLabel:SetPoint("LEFT", UI.saveButton, "RIGHT", 16, 0)
    presetLabel:SetText(L("Presets:"))
    local last = presetLabel
    for _, name in ipairs({ "careful", "balanced", "aggressive" }) do
        local b = button(p, UI.PRESET_LABELS[name], 110, function()
            UI.applyPreset(name)
        end)
        b:SetPoint("LEFT", last, "RIGHT", 6, 0)
        last = b
        UI["preset_" .. name] = b
    end
    local auto = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    auto:SetPoint("TOPLEFT", p, "TOPLEFT", 8, y - 30)
    auto:SetScript("OnClick", function(self)
        F.Engine.autoVerify = self:GetChecked() and true or false
    end)
    auto:SetChecked(F.Engine.autoVerify)
    local autoText = text(p, "GameFontHighlightSmall")
    autoText:SetPoint("LEFT", auto, "RIGHT", 2, 0)
    autoText:SetWidth(250)
    autoText:SetText(L("Check found deals on the auction house automatically (one search per second)"))
    local scan = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    scan:SetPoint("TOPLEFT", p, "TOPLEFT", 300, y - 30)
    scan:SetScript("OnClick", function(self)
        F.db.settings.autoScan = self:GetChecked() and true or false
    end)
    scan:SetChecked(F.db.settings.autoScan)
    local scanText = text(p, "GameFontHighlightSmall")
    scanText:SetPoint("LEFT", scan, "RIGHT", 2, 0)
    scanText:SetWidth(250)
    scanText:SetText(L("Full scan every 15 minutes while the auction house is open"))
    -- Two columns of checkboxes, 28 pixels apart.
    local slots = 2
    local function toggle(setting, label)
        local box = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
        local column, row = slots % 2, math.floor(slots / 2)
        slots = slots + 1
        box:SetPoint("TOPLEFT", p, "TOPLEFT", column == 0 and 8 or 300, y - 30 - row * 28)
        box:SetScript("OnClick", function(self)
            if setting == "sniper" then
                F.Deals.setSniper(self:GetChecked() and true or false)
            elseif setting == "belowMin" then
                F.db.settings.belowMin = self:GetChecked() and "hold" or "min"
            else
                F.db.settings[setting] = self:GetChecked() and true or false
            end
            UI.refresh()
        end)
        if setting == "belowMin" then
            box:SetChecked(F.db.settings.belowMin == "hold")
        else
            box:SetChecked(F.db.settings[setting])
        end
        local t = text(p, "GameFontHighlightSmall")
        t:SetPoint("LEFT", box, "RIGHT", 2, 0)
        t:SetWidth(250)
        t:SetText(L(label))
        return box
    end
    UI.sniperBox = toggle("sniper", "Sniper: between scans, re-read the items most often near a deal")
    toggle("alerts", "Sound and screen notice when a deal can be bought")
    toggle("tooltipPrices", "Price history from the scans in item tooltips")
    toggle("belowMin", "Keep items in the bags when the market is below their floor")
    toggle("learnBrowsing", "Learn prices and deals from my own searches in the Buy tab")
    toggle("highlight", "Mark deals in the game's Buy tab")
    toggle("disenchant", "Disenchant deals (for a character who knows Disenchant)")
    local lang = text(p, "GameFontNormal")
    lang:SetPoint("TOPLEFT", p, "TOPLEFT", 12, y - 30 - math.ceil(slots / 2) * 28 - 8)
    lang:SetText(L("Language (applies after /reload)"))
    local en = button(p, "English", 90, function()
        F.db.settings.language = "en"
        F.Engine.notify("reload")
    end)
    en:SetPoint("LEFT", lang, "RIGHT", 10, 0)
    local uk = button(p, "Українська", 110, function()
        F.db.settings.language = "uk"
        F.Engine.notify("reload")
    end)
    uk:SetPoint("LEFT", en, "RIGHT", 6, 0)
    UI.loadSettings()
end

-- Presets set the money and profit thresholds in one click.
UI.PRESET_LABELS = { careful = "Careful", balanced = "Balanced", aggressive = "Aggressive" }
UI.PRESETS = {
    careful = {
        minROI = 0.35,
        minProfit = 500,
        vendorMinProfit = 50,
        spendShare = 0.5,
        itemShare = 0.15,
        alertMinProfit = 100,
    },
    balanced = {
        minROI = 0.2,
        minProfit = 100,
        vendorMinProfit = 10,
        spendShare = 0.8,
        itemShare = 0.3,
        alertMinProfit = 50,
    },
    aggressive = {
        minROI = 0.1,
        minProfit = 50,
        vendorMinProfit = 5,
        spendShare = 0.95,
        itemShare = 0.5,
        alertMinProfit = 20,
    },
}
function UI.applyPreset(name)
    for key, value in pairs(UI.PRESETS[name] or {}) do
        F.db.settings[key] = value
    end
    UI.loadSettings()
    F.Engine.notify("saved")
end

function UI.loadSettings()
    for _, e in ipairs(UI.settingBoxes) do
        local key, kind = e.field[1], e.field[3]
        local v = F.db.settings[key]
        if kind == "money" then
            e:SetText(U.plainMoney(v))
        else
            e:SetText(tostring(math.floor(v * 100 + 0.5)))
        end
    end
end

-- Status -------------------------------------------------------------------------------------------
local PROGRESS = {
    scan_waiting = "Waiting for the full scan: %d / %d s",
    scan_reading = "Reading auctions %d / %d",
    scan_recovering = "Loading item data for the remaining auctions %d / %d",
    scan_finishing = "Evaluating items %d / %d",
}

local BATCH_SCOPES = {
    ["deals:all"] = "All deals",
    ["deals:vendor"] = "Vendor deals",
    ["deals:flip"] = "Resale",
    ["deals:shop"] = "Shopping deals",
    sell = "Bags",
    auctions = "My auctions",
    shop = "Shopping list",
    bids = "Bids",
    crafting = "Crafting",
}

function UI.refreshStatus()
    UI.refreshHouse()
    UI.sniperButton:SetText(L(F.db.settings.sniper and "Sniper: ON" or "Sniper: OFF"))
    UI.sniperBox:SetChecked(F.db.settings.sniper)
    UI.bulkButton:SetText(L("Check all"))
    local scope, keys = UI.statusTargets()
    local batchDone, batchTotal, batchActive, batchFailed = F.Deals.batchProgress()
    UI.bulkButton:SetEnabled(
        scope ~= nil
            and #keys > 0
            and F.AH.isOpen()
            and not batchActive
            and not F.Trade.busy()
            and not F.Scan.blocking()
    )
    local key, done, total = F.Scan.progress()
    if key then
        local line = string.format(L(PROGRESS[key]), done, total)
        if key == "scan_waiting" then
            -- What the server has sent so far: 0 means no answer yet.
            line = line .. " (" .. string.format(L("server list: %d"), F.AH.replicateCount()) .. ")"
        end
        UI.status:SetText(line)
        UI.progress:SetValue(total > 0 and done / total or 0)
        UI.scanButton:SetText(L("Full scan"))
        UI.scanButton:Disable()
        return
    end
    UI.progress:SetValue(0)
    local cooldown = math.floor(F.Scan.cooldown())
    UI.scanButton:SetEnabled(cooldown == 0)
    UI.scanButton:SetText(
        cooldown > 0 and string.format(L("Full scan in %d:%02d"), math.floor(cooldown / 60), cooldown % 60)
            or L("Full scan")
    )
    local batch = F.Deals.batch
    if batchActive then
        UI.status:SetText(
            string.format(L("Checking %s: %d/%d"), L(BATCH_SCOPES[batch.scope] or batch.scope), batchDone, batchTotal)
        )
        UI.progress:SetValue(batchTotal > 0 and batchDone / batchTotal or 0)
        return
    elseif batch and batchTotal > 0 and UI.completedBatch ~= batch then
        UI.completedBatch, UI.batchSummaryAt = batch, F.Engine.clock()
    end
    local msg = F.Engine.message
    if msg and F.Engine.clock() - (F.Engine.messageAt or 0) < 20 then
        UI.status:SetText(L(MESSAGES[msg] or msg))
        return
    end
    if batch and UI.completedBatch == batch and F.Engine.clock() - (UI.batchSummaryAt or 0) < 20 then
        local summary =
            string.format(L("Checked %s: %d/%d"), L(BATCH_SCOPES[batch.scope] or batch.scope), batchDone, batchTotal)
        if batchFailed > 0 then
            summary = summary .. string.format(L(" (%d failed)"), batchFailed)
        end
        UI.status:SetText(summary)
        return
    end
    local checked, all = F.Deals.progress()
    local hot = F.Scan.hot and #F.Scan.hot or 0
    if UI.selected and F.Deals.pending(UI.selected) then
        UI.status:SetText(L(F.Deals.search and F.Deals.search.key == UI.selected and "checking..." or "queued"))
    elseif F.Sniper.active() and F.Sniper.rounds > 0 then
        UI.status:SetText(string.format(L("Deals: %d · checked: %d"), all, checked))
    elseif F.Scan.last and F.db.settings.sniper and hot > 0 then
        UI.status:SetText(
            string.format(
                L("Deals: %d · checked: %d · sniper watches %d items, %d checks"),
                all,
                checked,
                hot,
                F.Deals.snipes or 0
            )
        )
    elseif F.Deals.search then
        UI.status:SetText(string.format(L("Checking deals on the auction house: %d / %d"), checked, all))
    elseif F.Scan.last then
        UI.status:SetText(
            string.format(
                L("Deals: %d · checked: %d · from the scan %d min ago"),
                all,
                checked,
                math.floor((F.Engine.clock() - F.Scan.last.at) / 60)
            )
        )
    else
        UI.status:SetText(L("Press Full scan to read the whole auction house."))
    end
end

-- The open auction house in short, and its colour: Alliance blue, Horde red, neutral gold.
function UI.houseName()
    if F.Engine.house == "Neutral" then
        return L("Neutral AH, 15% cut"), "ffd100"
    end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    if faction == "Horde" then
        return L("Horde AH"), "ff5050"
    end
    return L("Alliance AH"), "4fa3ff"
end

-- The house name sits in the middle of the auction house's bottom bar, right of the money display.
-- The money display is looked up among the auction frame's fields (its name differs between client
-- versions); without it the name goes to the bar's usual place: the bar is the 26 points under
-- ForeverFlip's frame, and the money display takes about its first 165 points.
local function moneyDisplay(ah)
    if type(ah) ~= "table" then
        return nil
    end
    for _, name in ipairs({ "MoneyFrameBorder", "MoneyFrameInset", "MoneyFrame" }) do
        local f = ah[name]
        if type(f) == "table" and type(f.GetRight) == "function" then
            return f
        end
    end
    for name, f in pairs(ah) do
        if type(name) == "string" and name:find("Money") and type(f) == "table" and type(f.GetRight) == "function" then
            return f
        end
    end
end

function UI.placeHouse()
    local badge, f = UI.houseBadge, UI.frame
    local ah = AuctionHouseFrame
    local money = moneyDisplay(ah)
    local moneyRight = money and tonumber(money:GetRight())
    local ahRight = money and type(ah.GetRight) == "function" and tonumber(ah:GetRight())
    local place = (moneyRight and ahRight and ahRight > moneyRight + 100) and "money" or (ah and "bar" or "corner")
    if UI.housePlaced == place then
        return
    end
    UI.housePlaced = place
    badge:ClearAllPoints()
    UI.status:ClearAllPoints()
    UI.status:SetPoint("LEFT", UI.bulkButton, "RIGHT", 10, 0)
    if place == "money" then
        badge:SetPoint("CENTER", money, "RIGHT", (ahRight - moneyRight) / 2, 0)
    elseif place == "bar" then
        badge:SetPoint("CENTER", f, "BOTTOM", 85, -13)
    else
        badge:SetPoint("RIGHT", f, "TOPRIGHT", -12, 19)
        badge:SetJustifyH("RIGHT")
        UI.status:SetPoint("RIGHT", badge, "LEFT", -12, 0)
        UI.status:SetWordWrap(false)
        return
    end
    badge:SetJustifyH("CENTER")
    UI.status:SetPoint("RIGHT", f, "TOPRIGHT", -12, 19)
    UI.status:SetWordWrap(false)
end

function UI.refreshHouse()
    if UI.houseBadge then
        UI.placeHouse()
        local name, color = UI.houseName()
        UI.houseBadge:SetText("|cff" .. color .. name .. "|r")
    end
end

-- Which auction house the scans and prices belong to: a neutral house (goblin town) keeps its own
-- history and a 15% cut, so the player must see when ForeverFlip thinks it is open.
function UI.houseLine()
    if F.Engine.house == "Neutral" then
        return "|cffffd100" .. L("Neutral auction house (15% cut)") .. "|r\n"
    end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    return string.format(L("Auction house: %s"), L(faction or "?")) .. "\n"
end

function UI.refreshSummary()
    local last = F.Scan.last
    if not last then
        UI.summary:SetText(UI.houseLine())
        return
    end
    local s = last.stats
    -- One figure per line: with six menu entries the panel has room for them.
    UI.summary:SetText(
        UI.houseLine()
            .. string.format(
                L(
                    "Last scan %d min ago\nAuctions: %d\nItems: %d\nVendor price known: %d\nBelow vendor price: %d\nCollecting sales data: %d"
                ),
                math.floor((F.Engine.clock() - last.at) / 60),
                last.total,
                s.items,
                s.vendorKnown,
                s.belowVendor,
                s.collecting
            )
            .. UI.sniperSummary()
    )
end

-- Sniper figures for the summary on the left.
function UI.sniperSummary()
    if not F.db.settings.sniper then
        return "\n\n" .. L("Sniper: off")
    end
    if not F.Sniper.active() then
        return "\n\n" .. string.format(L("Sniper: %d checks"), F.Deals.snipes or 0)
    end
    return "\n\n"
        .. string.format(
            L("Sniper: %d rounds\nPrices read: %d\nCandidates: %d\nChecks: %d"),
            F.Sniper.rounds,
            F.Sniper.items,
            F.Sniper.found,
            F.Deals.snipes or 0
        )
end

function UI.refresh()
    pcall(UI.highlightBrowse)
    if not UI.frame or not UI.frame:IsShown() then
        return
    end
    UI.refreshStatus()
    UI.refreshSummary()
    if UI.section == "deals" then
        UI.refreshDeals()
    elseif UI.section == "shop" then
        UI.refreshShop()
    elseif UI.section == "bids" then
        UI.refreshBids()
    elseif UI.section == "sell" then
        UI.refreshSell()
    elseif UI.section == "auctions" then
        UI.refreshAuctions()
    elseif UI.section == "stats" then
        UI.refreshStats()
    elseif UI.section == "analytics" then
        UI.refreshAnalytics()
    elseif UI.section == "crafting" then
        UI.refreshCrafting()
    elseif UI.section == "journal" then
        UI.refreshJournal()
    elseif UI.section == "settings" then
        if UI.settingsTab == "keys" then
            UI.refreshKeys()
        elseif UI.settingsTab == "share" then
            UI.refreshShare()
        elseif UI.settingsTab == "safety" then
            UI.refreshSafety()
        end
    end
end

-- Deals in the game's Buy tab ------------------------------------------------------------------------
-- Rows of the game's browse results get a green mark when the item has a deal now, or when its
-- lowest price is at or below what the sniper would check. Only reads what the game shows.
-- A row is marked when its price is at or below what can still hold a deal (the sniper's threshold:
-- vendor price, resale, shopping list, disenchant), or, in the item list, when the item has a deal.
local function dealItem(id, price, link, perRow)
    if not id then
        return false
    end
    if not perRow then
        for _, d in ipairs(F.Deals.list) do
            if d.id == id then
                return true
            end
        end
    end
    if not price or price <= 0 then
        return false
    end
    local key = F.AH.keyFor(id, link)
    if not key and F.AH.kindOf(id) ~= "gear" then
        key = U.key(F.AH.kindOf(id) or "item", id)
    end
    local limit = key and F.Sniper.threshold(key, id, F.Data.market(F.db, F.Engine.scope()).history)
    return limit ~= nil and price <= limit
end

-- The game's lists: browse results (one row per item), the auctions of an item, the price tiers of
-- a commodity.
local BUY_LISTS = {
    { "BrowseResultsFrame", false },
    { "ItemBuyFrame", true },
    { "CommoditiesBuyFrame", true },
}

function UI.highlightBrowse()
    if not AuctionHouseFrame or not F.db then
        return
    end
    for _, spec in ipairs(BUY_LISTS) do
        local frame = rawget(AuctionHouseFrame, spec[1])
        local list = type(frame) == "table" and rawget(frame, "ItemList")
        local box = type(list) == "table" and rawget(list, "ScrollBox")
        if type(box) == "table" and frame:IsShown() then
            UI.markRows(box, spec[2], frame)
        end
    end
end

local function eachRow(box, fn)
    if box.ForEachFrame then
        box:ForEachFrame(fn)
    elseif box.GetFrames then
        for _, row in ipairs(box:GetFrames() or {}) do
            fn(row)
        end
    end
end

function UI.markRows(box, perRow, frame)
    local on = F.db.settings.highlight
    eachRow(box, function(row)
        local data = row.rowData or (row.GetElementData and row:GetElementData())
        local id, price, link
        if type(data) == "table" then
            id = data.itemKey and data.itemKey.itemID or data.itemID
            if not id and frame and frame.GetItemID then
                local ok, frameID = pcall(frame.GetItemID, frame)
                id = ok and frameID or nil
            end
            price = data.minPrice or data.buyoutAmount or data.unitPrice
            link = data.itemLink
            if data.containsOwnerItem or (data.numOwnerItems or 0) >= (data.quantity or 1) then
                id = nil
            end
        end
        local mark = rawget(row, "ffMark")
        if not mark then
            mark = row:CreateTexture(nil, "OVERLAY")
            rawset(row, "ffMark", mark)
            mark:SetColorTexture(0.25, 1, 0.25, 0.9)
            mark:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            mark:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            mark:SetWidth(4)
        end
        if on and id and dealItem(id, price, link, perRow) then
            mark:Show()
        else
            mark:Hide()
        end
    end)
end

-- Price history window -------------------------------------------------------------------------------
local HISTORY_DAYS = 14
function UI.showHistory(key, link)
    local h = F.Data.market(F.db, F.Engine.scope()).history[key]
    local w = UI.historyFrame
    if not w then
        w = CreateFrame("Frame", "ForeverFlipHistory", UIParent)
        w:SetSize(520, 260)
        w:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        w:SetFrameStrata("DIALOG")
        if w.EnableMouse then
            w:EnableMouse(true)
        end
        local bg = w:CreateTexture(nil, "BACKGROUND")
        bg:SetColorTexture(0.05, 0.05, 0.06, 0.95)
        bg:SetAllPoints()
        w.title = text(w, "GameFontNormal")
        w.title:SetPoint("TOPLEFT", w, "TOPLEFT", 12, -10)
        w.title:SetPoint("TOPRIGHT", w, "TOPRIGHT", -40, -10)
        w.close = button(w, "X", 24, function()
            w:Hide()
        end)
        w.close:SetPoint("TOPRIGHT", w, "TOPRIGHT", -6, -6)
        w.summary = text(w, "GameFontHighlightSmall")
        w.summary:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 12, 10)
        w.summary:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -12, 10)
        w.bars = {}
        for i = 1, HISTORY_DAYS do
            local x = 14 + (i - 1) * 35
            local price = w:CreateTexture(nil, "ARTWORK")
            price:SetColorTexture(1, 0.82, 0, 0.8)
            price:SetWidth(14)
            price:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", x, 110)
            local cheap = w:CreateTexture(nil, "ARTWORK")
            cheap:SetColorTexture(0.25, 0.75, 1, 0.8)
            cheap:SetWidth(14)
            cheap:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", x + 15, 110)
            local sold = w:CreateTexture(nil, "ARTWORK")
            sold:SetColorTexture(0.3, 0.9, 0.3, 0.8)
            sold:SetWidth(29)
            sold:SetPoint("TOPLEFT", w, "BOTTOMLEFT", x, 104)
            local label = text(w, "GameFontDisableSmall")
            label:SetPoint("TOP", w, "BOTTOMLEFT", x + 15, 52)
            w.bars[i] = { price = price, cheap = cheap, sold = sold, label = label }
        end
        UI.historyFrame = w
    end
    w.key = key
    w.title:SetText(nameOf(key, link))
    local days = h and h.days or {}
    local top, most = 1, 0
    for _, d in ipairs(days) do
        top = math.max(top, d.m or 0, d.min or 0)
        most = math.max(most, d.s or 0)
    end
    local first = #days - HISTORY_DAYS
    for i, bar in ipairs(w.bars) do
        local d = days[first + i]
        if d then
            bar.price:SetHeight(math.max(1, 100 * (d.m or 0) / top))
            bar.cheap:SetHeight(math.max(1, 100 * (d.min or 0) / top))
            bar.sold:SetHeight(math.max(1, 40 * (d.s or 0) / math.max(1, most)))
            bar.label:SetText(date and date("%d.%m", d.d * 86400) or tostring(d.d))
            bar.price:Show()
            bar.cheap:Show()
            bar.sold:Show()
        else
            bar.price:Hide()
            bar.cheap:Hide()
            bar.sold:Hide()
            bar.label:SetText("")
        end
    end
    local sale = F.Market.salePrice(h)
    local s = h and h.scan and F.Market.saleability(h, h.scan.market, F.Engine.clock()) or {}
    w.summary:SetText(
        #days == 0 and L("No history yet: the item has not been seen in a full scan.")
            or string.format(
                L(
                    "Yellow: usual price · blue: cheapest · green: units sold per day.\nUsual %s · sells at %s · ~%s a day · top of the chart %s"
                ),
                h.scan and h.scan.market and U.money(h.scan.market) or "-",
                sale and U.money(sale) or "-",
                s.known and string.format("%.1f", s.perDay) or "-",
                U.money(top)
            )
    )
    w:Show()
end

-- Auction house tab ---------------------------------------------------------------------------------
function UI.attach()
    if UI.tab or not AuctionHouseFrame then
        return
    end
    UI.create()
    local lib = LibStub and LibStub("LibAHTab-1-0", true)
    if lib and lib.CreateTab then
        local ok = pcall(function()
            lib:CreateTab("ForeverFlip", UI.frame, "ForeverFlip", "ForeverFlip")
        end)
        if ok then
            UI.tab = lib
            return
        end
    end
    local tabs = AuctionHouseFrame.Tabs
    local b = CreateFrame("Button", "ForeverFlipTab", AuctionHouseFrame, "AuctionHouseFrameDisplayModeTabTemplate")
    b:SetText("ForeverFlip")
    if PanelTemplates_TabResize then
        PanelTemplates_TabResize(b, 20, nil, 70)
    end
    if tabs and #tabs > 0 then
        b:SetPoint("TOPLEFT", tabs[#tabs], "TOPRIGHT", 3, 0)
    else
        b:SetPoint("TOPLEFT", AuctionHouseFrame, "BOTTOMLEFT", 20, 0)
    end
    b:SetScript("OnClick", function()
        AuctionHouseFrame:SetDisplayMode({})
        if PanelTemplates_DeselectTab then
            for _, t in ipairs(tabs or {}) do
                PanelTemplates_DeselectTab(t)
            end
        end
        if PanelTemplates_SelectTab then
            PanelTemplates_SelectTab(b)
        end
        if AuctionHouseFrame.SetTitle then
            AuctionHouseFrame:SetTitle("ForeverFlip: " .. UI.houseName())
        end
        UI.frame:Show()
    end)
    if hooksecurefunc then
        hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", function(_, mode)
            if type(mode) == "table" and #mode > 0 then
                UI.frame:Hide()
                if PanelTemplates_DeselectTab then
                    PanelTemplates_DeselectTab(b)
                end
            end
        end)
    end
    UI.tab = b
end

function UI.refreshPostAll()
    local all, worthy = #F.Trade.toPostAll(), #F.Trade.toPostAll(true)
    UI.postAll:SetText(L("Post all") .. " (" .. all .. ")")
    UI.postAll:SetEnabled(all > 0 and not F.Trade.posting)
    UI.postAuction:SetText(L("Post AH-worthy") .. " (" .. worthy .. ")")
    UI.postAuction:SetEnabled(worthy > 0 and not F.Trade.posting)
end

-- The Best column of the Sell page: where one unit brings the most, and how much.
local BEST = { vendor = "Vendor", auction = "AH", disenchant = "Disenchant" }
function UI.bestText(w)
    if w.name == "unknown" then
        return "|cff999999" .. L("AH: no price yet") .. "|r"
    end
    local color = w.name == "vendor" and "|cffffb84d" or w.name == "auction" and "|cff40ff40" or "|cffb070ff"
    return color .. L(BEST[w.name]) .. " " .. U.money(w.value) .. "|r"
end

function UI.refreshPostNext()
    local n = #F.Trade.toPost()
    UI.postNext:SetText(L("Post next bought") .. " (" .. n .. ")")
    UI.postNext:SetEnabled(n > 0 and not F.Trade.posting)
end

-- Mailbox: one button takes all auction house mail (paced).
function UI.mail(open)
    if not MailFrame then
        return
    end
    if not UI.mailButton then
        UI.mailButton = button(MailFrame, "Take auction mail", 190, function()
            F.Mail.start()
            UI.mail(true)
        end)
        UI.mailButton:SetPoint("TOPRIGHT", MailFrame, "TOPRIGHT", -40, -28)
    end
    local n = open and F.Mail.count() or 0
    if n > 0 or F.Mail.job then
        UI.mailButton:SetText(L("Take auction mail") .. " (" .. n .. ")")
        UI.mailButton:SetEnabled(not F.Mail.job)
        UI.mailButton:Show()
    else
        UI.mailButton:Hide()
    end
end

-- How long ago a time was: "5 min ago", "3 h ago", "2 d ago".
function UI.age(at)
    if not U.finite(at) then
        return "?"
    end
    local s = math.max(0, F.Engine.clock() - at)
    if s < 3600 then
        return string.format(L("%d min ago"), math.floor(s / 60))
    elseif s < 2 * 86400 then
        return string.format(L("%d h ago"), math.floor(s / 3600))
    end
    return string.format(L("%d d ago"), math.floor(s / 86400))
end

-- Item tooltips: the item's prices from the full scans.
local ADVICE = {
    vendor = "Best: sell to a vendor",
    auction = "Best: post on the auction house",
    disenchant = "Best: disenchant",
}

-- Item tooltips: what ForeverFlip knows about the item, for the auction house shown in the header.
-- Each line says where its number comes from, so nothing reads as more certain than it is:
--   prices        usual price (and its age), cheapest seen today, units listed at the last scan
--   sales         units sold per day and the median price of sales seen, once measured
--   yours         stock you bought (and what it cost), your auctions on sale now
--   selling one   the vendor price (confirmed at a merchant or not), the auction house after the cut
--                 and the deposits of the tries it takes to sell, and which pays more
local function tipLine(tooltip, left, right, r, g, b)
    tooltip:AddDoubleLine(left, right or "", r or 0.6, g or 0.6, b or 0.6, 1, 1, 1)
end

local function ownSelling(key)
    local units, price = 0, nil
    for _, a in ipairs(F.Trade.owned or {}) do
        if a.key == key and not a.sold then
            units = units + (a.qty or 1)
            if a.price and a.qty and a.qty > 0 then
                local each = a.price / a.qty
                price = price and math.min(price, each) or each
            end
        end
    end
    return units, price
end

local function tooltipLines(tooltip)
    if not F.db or not F.db.settings.tooltipPrices or not tooltip.GetItem then
        return
    end
    local _, link = tooltip:GetItem()
    local id = link and tonumber(link:match("item:(%d+)"))
    local key = id and F.AH.keyFor(id, link)
    if not key then
        return
    end
    local h = F.Data.market(F.db, F.Engine.scope()).history[key]
    if type(h) ~= "table" then
        h = nil
    end
    local position = F.Data.char(F.db, F.Engine.owner()).positions[key]
    local onSale, onSalePrice = ownSelling(key)
    local usual, usualAt, sharer = F.Market.usual(h)
    local advice = F.Market.advice(id, key, h)
    if not usual and not position and onSale == 0 and not advice then
        return
    end
    local houseName = UI.houseName()
    tooltip:AddLine("ForeverFlip: " .. houseName, 1, 0.82, 0)
    if usual and h then
        tipLine(
            tooltip,
            L("Usual price")
                .. " |cff999999("
                .. UI.age(usualAt)
                .. (sharer and (", " .. L("shared by") .. " " .. sharer) or "")
                .. ")|r",
            U.money(usual),
            0.43,
            0.84,
            0.74
        )
        local today = h.days and h.days[#h.days]
        if today and today.d == math.floor(F.Engine.clock() / 86400) and today.min then
            tipLine(
                tooltip,
                string.format(L("Cheapest today (%d listed at the last scan)"), h.units or today.n or 0),
                U.money(today.min)
            )
        end
        local sale = F.Market.salePrice(h)
        local s = F.Market.saleability(h, usual, F.Engine.clock())
        if s.known then
            tipLine(
                tooltip,
                L("Sold per day (measured between scans)"),
                string.format("~%.1f", s.perDay) .. (sale and (" " .. L("at") .. " " .. U.money(sale)) or "")
            )
        else
            tipLine(tooltip, L("Sales"), L("not measured yet (needs two scans)"))
        end
        local timing = F.Market.timing(h, F.Engine.clock())
        if timing.ready and timing.spread >= 0.05 then
            tipLine(
                tooltip,
                L("cheapest / dearest time"),
                slotName(timing.low)
                    .. " / "
                    .. slotName(timing.high)
                    .. string.format(" (+%d%%)", math.floor(timing.spread * 100 + 0.5))
            )
        end
    end
    if position and position.qty > 0 then
        tipLine(
            tooltip,
            L("You hold"),
            string.format(L("%d, paid %s each"), position.qty, U.money(math.floor(position.cost / position.qty))),
            0.5,
            0.8,
            1
        )
    end
    if onSale > 0 then
        tipLine(
            tooltip,
            L("On sale by you"),
            string.format(L("%d at %s"), onSale, onSalePrice and U.money(math.floor(onSalePrice)) or "?"),
            0.5,
            0.8,
            1
        )
    end
    local deal = F.Deals.get(key)
    if deal then
        tipLine(tooltip, L("Deal now"), string.format("%s %s", L("profit"), U.money(deal.profit)), 0.25, 1, 0.25)
    end
    if advice then
        if advice.vendor then
            tipLine(
                tooltip,
                L("Vendor pays")
                    .. (
                        advice.vendorHow == "seen" and ""
                        or (" |cff999999(" .. L("not confirmed at a merchant") .. ")|r")
                    ),
                U.money(advice.vendor)
            )
        end
        if advice.auction then
            tipLine(
                tooltip,
                string.format(
                    L("Auction house, after the %d%% cut and %d deposits"),
                    math.floor(F.Market.CUT * 100 + 0.5),
                    advice.tries
                ),
                U.money(advice.auction)
            )
        end
        if advice.disenchant then
            tipLine(tooltip, L("Disenchant (materials after the cut)"), U.money(advice.disenchant))
        end
        tipLine(tooltip, L(ADVICE[advice.best]), "", 1, 0.82, 0)
    end
    tooltip:Show()
end

function UI.tooltips()
    if UI.tooltipHooked then
        return
    end
    UI.tooltipHooked = true
    local function safe(tooltip)
        local ok, err = pcall(tooltipLines, tooltip)
        if not ok and F.Engine.report then
            F.Engine.report("tooltip: " .. tostring(err))
        end
    end
    if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
            if tooltip == GameTooltip or tooltip == ItemRefTooltip then
                safe(tooltip)
            end
        end)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", safe)
    end
end

-- Merchant panel: items this vendor sells below their auction house value (vendor -> AH).
function UI.merchantOffers(open)
    if not MerchantFrame then
        return
    end
    local panel = UI.offerPanel
    if not panel then
        panel = CreateFrame("Frame", nil, MerchantFrame)
        panel:SetSize(320, 250)
        panel:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 4, -30)
        local bg = panel:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.05, 0.05, 0.06, 0.92)
        panel.title = text(panel, "GameFontNormal")
        panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
        panel.title:SetText(L("ForeverFlip: buy here, sell on the auction house"))
        panel.rows = {}
        for i = 1, 7 do
            local row = CreateFrame("Frame", nil, panel)
            row:SetSize(304, 30)
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -28 - (i - 1) * 31)
            row.text = text(row, "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
            row.text:SetWidth(220)
            row.text:SetWordWrap(true)
            row.buy = button(row, "Buy", 80, function(self)
                local ok, why = F.Merchant.buy(self.offer)
                if not ok and why then
                    F.Engine.notify(why)
                end
                UI.merchantOffers(true)
            end)
            row.buy:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            panel.rows[i] = row
        end
        UI.offerPanel = panel
    end
    local offers = open and F.Merchant.offers() or {}
    for i, row in ipairs(panel.rows) do
        local o = offers[i]
        if o then
            row.text:SetText(
                string.format(
                    L("%s: %s here, %s on AH, +%s each, ~%.1f/day"),
                    o.link or o.name,
                    U.money(o.unit),
                    U.money(o.exit),
                    U.money(math.floor(o.each)),
                    o.perDay
                )
            )
            row.buy.offer = o
            row.buy:SetText(L("Buy") .. " " .. o.qty)
            row:Show()
        else
            row:Hide()
        end
    end
    if #offers > 0 then
        panel:Show()
    else
        panel:Hide()
    end
end

-- Merchant: one button sells every item bought as a vendor deal.
function UI.merchant(open)
    if not MerchantFrame then
        return
    end
    if not UI.merchantButton then
        UI.merchantButton = button(MerchantFrame, "Sell vendor deals", 190, function()
            local n = F.Trade.sellToVendor()
            print("ForeverFlip: " .. string.format(L("sold %d stacks to the vendor"), n))
            UI.merchant(true)
        end)
        UI.merchantButton:SetPoint("TOPRIGHT", MerchantFrame, "TOPRIGHT", -40, -28)
    end
    local n = open and #F.Trade.vendorItems() or 0
    if n > 0 then
        UI.merchantButton:SetText(L("Sell vendor deals") .. " (" .. n .. ")")
        UI.merchantButton:Show()
    else
        UI.merchantButton:Hide()
    end
end
