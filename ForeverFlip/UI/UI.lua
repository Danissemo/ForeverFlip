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

-- The colours of the window, by meaning: every page paints with these, not with raw |cff codes,
-- so one meaning has one shade. good: profit, ready, the auction route; bad: loss, a problem;
-- gold: titles and things in progress; dim: secondary text; soft: indented detail lines; warn:
-- thin data, lost deposits; vendor and purple: the vendor and disenchant routes; info: a price or
-- a check the player asked for; head: a section heading in a tooltip.
UI.C = {
    good = "|cff40ff40",
    bad = "|cffff6060",
    gold = "|cffffd100",
    dim = "|cff999999",
    soft = "|cffaaaaaa",
    warn = "|cffffa040",
    vendor = "|cffffb84d",
    purple = "|cffb070ff",
    info = "|cff66ccff",
    head = "|cff8fb8ff",
    white = "|cffffffff",
}
function UI.paint(kind, text)
    return UI.C[kind] .. tostring(text) .. "|r"
end

-- The sell routes, one colour and name each: the Best columns, the item tooltip and Crafting.
UI.ROUTE = {
    auction = { UI.C.good, "AH" },
    vendor = { UI.C.vendor, "Vendor" },
    disenchant = { UI.C.purple, "Disenchant" },
}

-- Tooltip blocks that weigh options (the routes of an item, the moves on an own auction): each
-- option a head line, the chosen one marked with ">" and a green word after it, then its detail
-- indented in grey.
function UI.optionHead(best, color, label)
    return (best and "> " or "   ") .. color .. L(label) .. "|r"
end
function UI.optionMark(best, word)
    return best and ("  " .. UI.C.good .. L(word) .. "|r") or ""
end
function UI.optionDetail(s)
    -- Money ends its colour with |r: the grey is taken up again after each amount.
    return "      " .. UI.C.soft .. s:gsub("|r", "|r" .. UI.C.soft) .. "|r"
end

-- A share as a whole percent, rounded half up: one rule for every ROI, Sure and return shown.
function UI.pct(x)
    return math.floor((x or 0) * 100 + 0.5)
end
function UI.pctText(x)
    return string.format("%d%%", UI.pct(x))
end

-- The services never reach into UI: they read what the window shows through Engine.screen and
-- select a row through Engine.emit("select", key).
local screen = {}
F.Engine.screenReader = function()
    local f = UI.frame
    screen.frame = f and true or false
    screen.shown = f and f.IsShown and f:IsShown() and true or false
    screen.section, screen.filter, screen.selected = UI.section, UI.filter, UI.selected
    screen.selectedAt, screen.buyHoverKey, screen.vendorOrder = UI.selectedAt, UI.buyHoverKey, UI.vendorOrder
    screen.order = UI.order
    return screen
end

-- Every bulk button (Check all, Post all, Post AH-worthy, Post next bought, Check prices, Answer
-- next, Cancel next undercut) works down its list as the player sorted it, top to bottom. A page's
-- list: the table that shows it, and the keys of one row (an item key; an auction's ID as well, for
-- the buttons that act per auction; a recipe's product and its materials).
local ORDER_TABLES = {
    sell = "sellTable",
    auctions = "auctionTable",
    undercuts = "undercutTable",
    shop = "shopTable",
    bids = "bidTable",
    crafting = "craftTable",
    journal = "lotTable",
}
local ORDER_KEYS = {
    auctions = function(a)
        return { a.key, a.auctionID }
    end,
    undercuts = function(plan)
        local a = plan.auction or {}
        return { a.key, a.auctionID }
    end,
    crafting = function(e)
        local keys = { e.out and F.AH.keyFor(e.out) }
        for _, m in ipairs(e.reagents or {}) do
            keys[#keys + 1] = F.AH.keyFor(m[1])
        end
        return keys
    end,
}
local orderCache = {}
-- { [key] = row } of the list `name` (deals, sell, auctions, undercuts, shop, bids, crafting,
-- journal) as last drawn; nil before the page was drawn.
function UI.order(name)
    local list
    if name == "deals" then
        list = UI.dealSorted
    else
        local t = ORDER_TABLES[name] and UI[ORDER_TABLES[name]]
        list = t and t.sorted
    end
    if type(list) ~= "table" then
        return nil
    end
    local cached = orderCache[name]
    if cached and cached.list == list then
        return cached.rank
    end
    local rank, n = {}, 0
    local keysOf = ORDER_KEYS[name]
    for _, e in ipairs(list) do
        local keys = keysOf and keysOf(e) or { e.key }
        for i = 1, table.maxn(keys) do
            local k = keys[i]
            if k ~= nil and rank[k] == nil then
                n = n + 1
                rank[k] = n
            end
        end
    end
    orderCache[name] = { list = list, rank = rank }
    return rank
end
F.Engine.listen("select", function(key)
    UI.selected = key
end)

local ROW = 20
-- The Buy tab's category list (AuctionHouseFrame.CategoriesList) is 168 wide: its art (138) and a
-- scroll bar beside it. ForeverFlip's menu has no scroll bar, so the list ends with the art.
local LEFT_WIDTH = 144

local MESSAGES = {
    nothing_to_post = "Nothing bought for resale is waiting in the bags.",
    nothing_undercut = "No undercut auction worth reposting. Press Check prices first.",
    bid_placed = "Bid placed. If nobody bids more, the item arrives by mail when the auction ends.",
    bid_won = "Auction won: the item is booked as stock.",
    bid_bought = "Bought out: the item arrives by mail.",
    nothing_to_bid = "That bid is no longer open.",
    hidden = "The item is hidden: it is no longer offered for sale.",
    unhidden = "The item is back in the list for sale.",
    share_queued = "Sending the scan...",
    share_sent = "Scan sent.",
    share_received = "A shared scan was added to the price history.",
    share_invalid = "This text is not a ForeverFlip scan.",
    share_too_large = "The scan is too large to share: receivers take at most 5000 parts.",
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
    scan_empty = "The server answered the full scan with an empty list: it sends one list per 15 minutes, counted from the last call (by this or another addon, or another character of the account), and refuses calls in between. The Full scan button counts down to the next one; Quick scan reads the lowest prices meanwhile.",
    quick_done = "Quick scan done: the lowest prices of the whole house are read and the deals among them checked. The full scan is still needed for quantities and sales.",
    quick_timeout = "The quick scan took over 3 minutes and was stopped: the server answers slowly. What it read is kept.",
    quick_stopped = "Quick scan stopped. What it read is kept.",
    scan_timeout = "The server sent no full scan in 10 minutes (it is busy, or another addon or character of the account used the 15-minute window). The next try waits 5 minutes longer for each call left unanswered: an earlier call would start the server's wait again.",
    scan_unsettled = "The full scan list kept changing for 5 minutes and was not read. Next try 15 minutes after this one.",
    scan_partial = "The server sent only a part of the full scan list and stopped. A part is not used (its missing lots would read as bought): the deals and sales of the last complete scan stay. Next try 15 minutes after this one.",
    scan_dropped = "The server threw the full scan request away (too many requests). Next try in 10 seconds.",
    stopped = "Stopped: no check, scan or sale is running now.",
    scan_paused = "The auction house closed while waiting for the full scan: the wait goes on when you open it again.",
    scan_paused_reading = "The auction house closed during the full scan: it is read again when you open it.",
    scan_resumed = "Waiting again for the full scan sent before.",
    scan_other = "Another addon requested a full scan: ForeverFlip reads it too.",
    quote_ready = "Price confirmed. Press Confirm purchase.",
    price_changed = "The price changed. The deal is checked again.",
    quote_expired = "The price offer expired. Press Buy again.",
    mail_stuck = "The game kept refusing an auction mail: taking mail stopped. Take it by hand.",
    requote = "The price offer was about to expire; a new one was asked. Press Confirm when it arrives.",
    nothing_to_fight = "No undercut auction is worth answering now.",
    bought = "Purchase recorded.",
    bought_more = "Bought one lot. The resale price counts on the other cheap lots too: press Buy again.",
    buy_failed = "The auction house reported a purchase failure. The deal is checked again.",
    buy_unknown = "No answer from the auction house. Settle the purchase in the Journal.",
    buy_busy = "The auction house is still answering a search: press Buy again in a moment.",
    buy_recheck = "Another item was searched since this lot was read, and the auction house would not sell it: reading it again. Press Buy once more.",
    buy_no_answer = "No answer to the purchase in 30 seconds (no money spent yet). If the money leaves later it is booked then; check before buying the same lot again.",
    bought_late = "The purchase went through after all: booked now.",
    posted = "Auction created.",
    post_sent = "Posting... waiting for the auction house to confirm.",
    buy_dropped = "The auction house threw the purchase away (too many messages): press Buy again.",
    post_busy = "The auction house is busy: press again in a moment.",
    post_dropped = "The auction house threw the post away (too many messages): press again.",
    post_unconfirmed = "The auction house did not confirm the post: check My auctions, then press again.",
    restricted = "The game does not let addons post, buy or cancel right now (combat, a boss, a keystone or a PvP match). Try again once it ends.",
    post_restricted = 'The auction house answered "That action is currently restricted" and did not post. The game reports no combat or other addon restriction: try the same item from the game\'s Sell tab.',
    craft_saved = "The materials of the plan are on the shopping list, each at its price limit.",
    craft_nothing = "Nothing to buy: the plan holds no craft, or the bags already hold its materials.",
    post_refused = "The auction house refused the post (the game said why). The item is skipped until the auction house is opened again.",
    sold = "Sale recorded.",
    verify_first = "Checking the current price first...",
    no_money = "Not enough money.",
    busy = "Wait for the current action.",
    rebuilding = "ForeverFlip is rebuilding its sales statistics from the kept scans: a full scan waits until it ends.",
    closed = "Open the auction house.",
    cooldown = "A full scan is allowed once per 15 minutes.",
    unavailable = "This game client offers no full scan of the auction house.",
    throttled = "The auction house is busy. Try again in a moment.",
    error = "The game refused the action.",
    values = "Check the quantity and the price.",
    not_number = "A box did not hold a number and kept its old value; the others were saved.",
    confirm = "The game asks for a confirmation: press Post again.",
    cancelled = "Auction cancelled. The item comes back by mail; the deposit is lost.",
    spend_limit = "The spending limit of this auction house visit is reached (Settings, General, Limits).",
    no_deal = "No deal to buy right now.",
    run_done = "Buy first: nothing left to buy. Sell the items at any merchant (Sell all there).",
    run_checking = "Checking the current price first: press again when it is ready.",
    bought_elsewhere = "A purchase made outside ForeverFlip was booked from its mail.",
    older_lot = "An older purchase of this item is still open: mark that one first (sales are booked oldest first).",
}

-- Widgets ---------------------------------------------------------------------------------------------
local function text(parent, font)
    local t = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    t:SetJustifyH("LEFT")
    return t
end

-- Widens a button whose label does not fit `width`. The game lets a button's text spill past its
-- frame and never cuts it, so a longer translation ran out of a right-anchored button and off the
-- window (the Ukrainian "Sell gear I can't use" needs about 210 px against 180). The text is
-- measured once the button has a font; without one the label's own length is the fallback.
function UI.fitButton(b, width)
    local function fit()
        if b.resetLabel then
            b:resetLabel() -- measured in the normal font, unclipped
        end
        local fs = b.GetFontString and b:GetFontString()
        local text = (b.GetText and b:GetText()) or ""
        -- GetStringWidth is clipped to the font string's width once one has been set (the frame
        -- grows, the string does not): the unbounded measure is the one that answers the question.
        local need
        if fs and fs.GetUnboundedStringWidth then
            need = fs:GetUnboundedStringWidth()
        elseif fs and fs.GetStringWidth then
            need = fs:GetStringWidth()
        end
        if not need or need <= 0 then
            need = #text * 7 -- letterfont: about 7 px a character, one line
        end
        b:SetSize(math.max(width or 0, math.ceil(need) + 20), 22)
        if b.fitLabel then
            b:fitLabel() -- the label in the grown button: back to the normal font if it fits now
        end
    end
    fit()
    -- A label set later (the counts of the merchant buttons) is measured then.
    b.fitWidth = fit
    return b
end

-- A label set after the button was laid out ("Rebuilding sales statistics...", "Post AH-worthy
-- (24)", "Buy (2 clicks)") cannot widen the button without pushing its neighbours, so it ran past
-- the frame. Every later label is measured against the button's own width: one that does not fit
-- takes the small font, and one that still does not fit is cut with "..." and shown whole on hover.
-- The wrapper sits on our own button only; the game's frames are never touched.
local SMALL = { "GameFontNormalSmall", "GameFontHighlightSmall", "GameFontDisableSmall" }
local NORMAL = { "GameFontNormal", "GameFontHighlight", "GameFontDisable" }
function UI.labelWidth(b)
    local fs = b.GetFontString and b:GetFontString()
    local need = fs and fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()
    if not need or need <= 0 then
        need = fs and fs.GetStringWidth and fs:GetStringWidth()
    end
    if not need or need <= 0 then
        need = #((b.GetText and b:GetText()) or "") * 7
    end
    return need, fs
end
local function fonts(b, set)
    local normal, highlight, disabled = _G[set[1]], _G[set[2]], _G[set[3]]
    if normal and b.SetNormalFontObject then
        b:SetNormalFontObject(normal)
        b:SetHighlightFontObject(highlight or normal)
        b:SetDisabledFontObject(disabled or normal)
    end
end
function UI.keepLabelInside(b)
    b.resetLabel = function(self)
        fonts(self, NORMAL)
        local fs = self.GetFontString and self:GetFontString()
        if fs and fs.SetWidth then
            fs:SetWidth(0) -- unbounded again, so the measure is the label's own
        end
        self.labelCut = nil
    end
    b.fitLabel = function(self)
        local width = (self.GetWidth and self:GetWidth()) or 0
        if width <= 0 then
            return
        end
        local room = width - 14
        self:resetLabel()
        local need, fs = UI.labelWidth(self)
        if need > room then
            fonts(self, SMALL)
            need, fs = UI.labelWidth(self)
            if need > room and fs and fs.SetWidth then
                if fs.SetWordWrap then
                    fs:SetWordWrap(false)
                end
                fs:SetWidth(room)
                self.labelCut = (self.GetText and self:GetText()) or ""
            end
        end
        if self.labelCut and not self.labelTip then
            -- The whole label on hover, unless the button already explains itself.
            self.labelTip = true
            self:HookScript("OnEnter", function(own)
                if own.labelCut and not GameTooltip:IsOwned(own) then
                    GameTooltip:SetOwner(own, "ANCHOR_TOP")
                    GameTooltip:SetText(own.labelCut, 1, 1, 1, 1, true)
                    GameTooltip:Show()
                end
            end)
            self:HookScript("OnLeave", function(own)
                if GameTooltip:IsOwned(own) then
                    GameTooltip:Hide()
                end
            end)
        end
    end
    local setText = b.SetText
    b.SetText = function(self, value)
        setText(self, value)
        self:fitLabel()
    end
end

local function button(parent, label, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 110, 22)
    b:SetText(L(label))
    -- A label longer than the width would run out of the button: with a right-anchored button it
    -- ran off the window (the Ukrainian "Sell gear I can't use" is 30 letters against 180 px). The
    -- button takes the wider of the two, so a translation never overflows.
    UI.fitButton(b, width or 110)
    UI.keepLabelInside(b)
    b:SetScript("OnClick", function(self, ...)
        F.Engine.input()
        return F.Log.action("click " .. tostring(self:GetText() or label), onClick, self, ...)
    end)
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
    f.art = art
    return f
end

-- Entry of the left list, styled like the auction house category list.
-- The side menu entries look like the auction house's own category buttons (the Buy tab's Weapons,
-- Armor ...): the same art at the same size, 136 by 20.
local NAV_WIDTH, NAV_HEIGHT, NAV_STEP = 137, 21, 21
local NAV_X, NAV_Y = 6, -6 -- the list's ScrollBox (3, -6) and its ScrollTarget (3, 0)

local function atlasExists(name)
    if C_Texture and C_Texture.GetAtlasInfo then
        local ok, info = pcall(C_Texture.GetAtlasInfo, name)
        return ok and info ~= nil
    end
    return true
end

local function place(texture, atlas, fallback, width, height, point, x, y)
    texture:SetAtlas(atlasExists(atlas) and atlas or fallback)
    texture:ClearAllPoints()
    texture:SetSize(width, height)
    texture:SetPoint(point, x, y)
end

-- A top entry: the art of the Buy tab's Weapons, Armor ...; a sub-entry: that of One-Handed,
-- Two-Handed ... (white text, the art moved right).
local function styleEntry(row, sub)
    if sub then
        place(row.normal, "auctionhouse-nav-button-secondary", "auctionhouse-nav-button", 133, 32, "TOPLEFT", 1, 0)
        place(
            row.selected,
            "auctionhouse-nav-button-secondary-select",
            "auctionhouse-nav-button-select",
            122,
            21,
            "TOPLEFT",
            10,
            0
        )
        place(
            row.highlight,
            "auctionhouse-nav-button-select",
            "auctionhouse-nav-button-highlight",
            122,
            21,
            "TOPLEFT",
            10,
            0
        )
        row.highlight:SetBlendMode("ADD")
        row.label:SetFontObject(GameFontHighlightSmall)
        row.label:SetPoint("LEFT", row, "LEFT", 18, 0)
    else
        place(row.normal, "auctionhouse-nav-button", "auctionhouse-nav-button", 136, 32, "TOPLEFT", -2, 0)
        place(row.selected, "auctionhouse-nav-button-select", "auctionhouse-nav-button-select", 132, 21, "LEFT", 0, 0)
        place(
            row.highlight,
            "auctionhouse-nav-button-highlight",
            "auctionhouse-nav-button-highlight",
            132,
            21,
            "LEFT",
            0,
            0
        )
        row.highlight:SetBlendMode("BLEND")
        row.label:SetFontObject(GameFontNormalSmall)
        row.label:SetPoint("LEFT", row, "LEFT", 8, 0)
    end
end

-- A third-level entry: that of One-Handed Axes under One-Handed (a thin line at the left, no art
-- of its own, the row highlight of the results list), as in the Buy tab.
local function styleTertiary(row)
    row.normal:SetAlpha(0)
    row.lines = row:CreateTexture(nil, "BACKGROUND")
    place(
        row.lines,
        "auctionhouse-nav-button-tertiary-filterline",
        "auctionhouse-nav-button-secondary",
        5,
        11,
        "LEFT",
        18,
        3
    )
    for _, t in ipairs({ row.selected, row.highlight }) do
        t:ClearAllPoints()
        t:SetSize(116, 18)
        t:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -2)
        t:SetBlendMode("ADD")
    end
    row.selected:SetAtlas(
        atlasExists("auctionhouse-ui-row-select") and "auctionhouse-ui-row-select"
            or "auctionhouse-nav-button-secondary-select"
    )
    row.highlight:SetAtlas(
        atlasExists("auctionhouse-ui-row-highlight") and "auctionhouse-ui-row-highlight"
            or "auctionhouse-nav-button-select"
    )
    row.label:SetFontObject(GameFontHighlightSmall)
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", 26, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
end

-- A cell of a table row with a tooltip of its own: it takes the hover only, so a click on it still
-- selects the row under it (EnableMouse took the clicks too, and a row could not be picked through
-- its Best or Note cell). Every tooltip region inside a row goes through here.
function UI.hoverOnly(region)
    if region.EnableMouseMotion then
        region:EnableMouseMotion(true)
    elseif region.EnableMouse then
        region:EnableMouse(true)
    end
    if region.SetMouseClickEnabled then
        region:SetMouseClickEnabled(false)
    end
    if region.SetPropagateMouseClicks then
        region:SetPropagateMouseClicks(true)
    end
end

-- A tooltip line of a label and a value. A double line never wraps, so a long one (a long
-- recommendation, Ukrainian text) widened the tooltip past the screen and every wrapped line with
-- it: past UI.TIP_PAIR_MAX letters it becomes one wrapped line, the value after the label.
UI.TIP_PAIR_MAX = 60
-- Letters as shown: colour codes are not shown, and a coin icon (|T...|t) takes about two.
local function letters(s)
    s = tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "  ")
    return select(2, s:gsub("[^\128-\191]", ""))
end
function UI.tipPair(tip, left, right, lr, lg, lb, rr, rg, rb)
    right = right or ""
    if letters(left) + letters(right) <= UI.TIP_PAIR_MAX then
        tip:AddDoubleLine(left, right, lr, lg, lb, rr or 1, rg or 1, rb or 1)
    else
        tip:AddLine(left .. (right ~= "" and ("  " .. UI.C.white .. right .. "|r") or ""), lr, lg, lb, true)
    end
end

-- The tooltip of a frame: a gold title and a white body (no title: the body alone), to the right
-- unless `anchor` says otherwise. Every fixed explanation on a button, a box or a column header
-- goes through here, so they all look alike.
function UI.tip(frame, title, body, anchor)
    frame:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
            if title then
                GameTooltip:SetText(L(title), 1, 0.82, 0, 1, true)
                GameTooltip:AddLine(L(body), 1, 1, 1, true)
            else
                GameTooltip:SetText(L(body), 1, 1, 1, 1, true)
            end
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
end

local function category(parent, label, onClick, sub)
    -- Built from the art itself: the game's filter-button template carries clear buttons and
    -- arrows of its own on WoW Forever.
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(NAV_WIDTH, NAV_HEIGHT)
    row.normal = row:CreateTexture(nil, "BACKGROUND")
    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.selected = row:CreateTexture(nil, "ARTWORK")
    row.selected:Hide()
    local t = text(row, "GameFontNormalSmall")
    t:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    t:SetJustifyH("LEFT")
    t:SetText(L(label))
    row.label = t
    styleEntry(row, sub)
    row:SetScript("OnClick", onClick)
    return row
end

-- The auction house's own look, copied at run time from its Buy tab (AuctionHouseFrame): the
-- category buttons' textures, size and font, and the frames (NineSlice) and backgrounds of the
-- category list and of the results list. WoW Forever's client may differ from the usual one, so
-- nothing is guessed: what the game shows is what is copied. Tried on each refresh until the Buy
-- tab's buttons exist.
local NINE = {
    "TopLeftCorner",
    "TopRightCorner",
    "BottomLeftCorner",
    "BottomRightCorner",
    "TopEdge",
    "BottomEdge",
    "LeftEdge",
    "RightEdge",
    "Center",
}

local function copyTexture(dst, src)
    if not dst or not src or not src.GetTexture then
        return false
    end
    local atlas = src.GetAtlas and src:GetAtlas()
    if atlas then
        dst:SetAtlas(atlas)
    else
        local file = src:GetTexture()
        if not file then
            return false
        end
        dst:SetTexture(file)
        if src.GetTexCoord and dst.SetTexCoord then
            dst:SetTexCoord(src:GetTexCoord())
        end
    end
    if src.GetVertexColor and dst.SetVertexColor then
        dst:SetVertexColor(src:GetVertexColor())
    end
    if src.GetBlendMode and dst.SetBlendMode then
        dst:SetBlendMode(src:GetBlendMode())
    end
    return true
end

local function copyPanel(dst, src)
    if not dst or not src then
        return
    end
    local dstNine, srcNine = rawget(dst, "NineSlice"), rawget(src, "NineSlice")
    if type(dstNine) == "table" and type(srcNine) == "table" then
        for _, piece in ipairs(NINE) do
            copyTexture(rawget(dstNine, piece), rawget(srcNine, piece))
        end
    end
    if type(dst.art) == "table" and type(src.Background) == "table" then
        copyTexture(dst.art, src.Background)
    end
end

local function nativeTexture(frame, kind)
    local field = rawget(frame, kind .. "Texture")
    if type(field) == "table" and field.GetTexture then
        return field
    end
    local get = frame["Get" .. kind .. "Texture"]
    if type(get) == "function" then
        local ok, t = pcall(get, frame)
        if ok and type(t) == "table" then
            return t
        end
    end
end

local function nativeCategoryButton()
    local list = AuctionHouseFrame and rawget(AuctionHouseFrame, "CategoriesList")
    if type(list) ~= "table" then
        return nil, nil
    end
    local box = rawget(list, "ScrollBox")
    local target = type(box) == "table" and rawget(box, "ScrollTarget") or nil
    if not target or not target.GetChildren then
        return nil, list
    end
    for _, child in ipairs({ target:GetChildren() }) do
        ---@cast child Button
        if nativeTexture(child, "Normal") then
            return child, list
        end
    end
    return nil, list
end

-- The first FontString with text inside a frame (a row of the results list keeps its texts in cells).
local function firstText(frame, depth)
    if not frame or depth > 3 then
        return nil
    end
    -- `{ a and f() }` would keep only f's first result: the table is built from the call itself.
    local regions = frame.GetRegions and { frame:GetRegions() } or {}
    for _, region in ipairs(regions) do
        if region.GetObjectType and region:GetObjectType() == "FontString" and region.GetFont and region:GetFont() then
            local shown = region.GetText and region:GetText()
            if shown and shown ~= "" then
                return region
            end
        end
    end
    local children = frame.GetChildren and { frame:GetChildren() } or {}
    for _, child in ipairs(children) do
        local found = firstText(child, depth + 1)
        if found then
            return found
        end
    end
end

-- Rows of the Buy tab's results list exist once a search was made there: their look is copied
-- onto every row of every ForeverFlip table (background, highlight, the font of the text).
function UI.copyNativeRows()
    if UI.nativeRows then
        return true
    end
    local browse = AuctionHouseFrame and rawget(AuctionHouseFrame, "BrowseResultsFrame")
    local list = type(browse) == "table" and rawget(browse, "ItemList") or nil
    local box = type(list) == "table" and rawget(list, "ScrollBox") or nil
    local target = type(box) == "table" and rawget(box, "ScrollTarget") or nil
    if not target or not target.GetChildren then
        return false
    end
    local native
    for _, child in ipairs({ target:GetChildren() }) do
        ---@cast child Button
        if nativeTexture(child, "Normal") and firstText(child, 0) then
            native = child
            break
        end
    end
    if not native then
        return false
    end
    ---@cast native Button
    local font = firstText(native, 0)
    local path, size, flags
    if font then
        path, size, flags = font:GetFont()
    end
    for _, t in ipairs(UI.tables) do
        for _, r in ipairs(t.rows) do
            if copyTexture(r.back, nativeTexture(native, "Normal")) then
                r.back:Show()
                if r.stripe then
                    r.stripe:Hide()
                end
            end
            copyTexture(r.hl, nativeTexture(native, "Highlight"))
            if path then
                r.name:SetFont(path, size, flags)
                for _, c in ipairs(r.cols) do
                    c:SetFont(path, size, flags)
                end
            end
        end
    end
    UI.nativeRows = true
    return true
end

-- /ff look: what the Buy tab's first category button is made of (each texture layer, the font)
-- and what the copy did, to match it exactly.
local function describeTexture(t)
    if not t or not t.GetTexture then
        return "none"
    end
    local parts = {}
    local atlas = t.GetAtlas and t:GetAtlas()
    parts[#parts + 1] = atlas and ("atlas " .. tostring(atlas)) or ("file " .. tostring(t:GetTexture()))
    if t.GetTexCoord then
        local c = { t:GetTexCoord() }
        for i, v in ipairs(c) do
            c[i] = string.format("%.3f", tonumber(v) or 0)
        end
        parts[#parts + 1] = "coords " .. table.concat(c, ",")
    end
    if t.GetDrawLayer then
        local layer, sub = t:GetDrawLayer()
        parts[#parts + 1] = "layer " .. tostring(layer) .. ":" .. tostring(sub)
    end
    if t.GetVertexColor then
        local r, g, b, a = t:GetVertexColor()
        parts[#parts + 1] = string.format(
            "color %.2f,%.2f,%.2f,%.2f",
            tonumber(r) or 1,
            tonumber(g) or 1,
            tonumber(b) or 1,
            tonumber(a) or 1
        )
    end
    if t.GetSize then
        local w, h = t:GetSize()
        parts[#parts + 1] = string.format("size %.0fx%.0f", tonumber(w) or 0, tonumber(h) or 0)
    end
    if t.IsShown then
        parts[#parts + 1] = t:IsShown() and "shown" or "hidden"
    end
    return table.concat(parts, "; ")
end

function UI.lookReport()
    local out = {}
    local native, list = nativeCategoryButton()
    out[#out + 1] = "category list: " .. tostring(list ~= nil) .. ", button: " .. tostring(native ~= nil)
    if list and not native then
        local box = rawget(list, "ScrollBox")
        local target = type(box) == "table" and rawget(box, "ScrollTarget") or nil
        local kinds = {}
        local children = target and target.GetChildren and { target:GetChildren() } or {}
        for _, child in ipairs(children) do
            local keys = {}
            for k, v in pairs(child) do
                if type(k) == "string" and type(v) == "table" then
                    keys[#keys + 1] = k
                end
            end
            kinds[#kinds + 1] = tostring(child.GetObjectType and child:GetObjectType())
                .. "{"
                .. table.concat(keys, ",")
                .. "}"
            if #kinds >= 2 then
                break
            end
        end
        out[#out + 1] = "list elements: " .. table.concat(kinds, " ")
    end
    if native then
        ---@cast native Button
        local w, h = native:GetSize()
        out[#out + 1] = string.format(
            "button size %.0fx%.0f, type %s",
            w or 0,
            h or 0,
            tostring(native.GetObjectType and native:GetObjectType())
        )
        out[#out + 1] = "normal: " .. describeTexture(nativeTexture(native, "Normal"))
        out[#out + 1] = "highlight: " .. describeTexture(nativeTexture(native, "Highlight"))
        out[#out + 1] = "selected: " .. describeTexture(nativeTexture(native, "Selected"))
        for i, region in ipairs({ native:GetRegions() }) do
            local kind = region.GetObjectType and region:GetObjectType()
            if kind == "Texture" then
                ---@cast region Texture
                out[#out + 1] = "region "
                    .. i
                    .. " "
                    .. tostring(region.GetDebugName and region:GetDebugName() or "")
                    .. ": "
                    .. describeTexture(region)
            elseif kind == "FontString" then
                ---@cast region FontString
                local path, size, flags = region:GetFont()
                local r, g, b = region:GetTextColor()
                out[#out + 1] = string.format(
                    "region %d text '%s': font %s %s %s, color %.2f,%.2f,%.2f",
                    i,
                    tostring(region:GetText()),
                    tostring(path),
                    tostring(size),
                    tostring(flags),
                    tonumber(r) or 1,
                    tonumber(g) or 1,
                    tonumber(b) or 1
                )
            end
        end
    end
    local ours = UI.categories and UI.categories[1]
    if ours then
        local w, h = ours:GetSize()
        out[#out + 1] = string.format(
            "ours: size %.0fx%.0f, copied: %s",
            tonumber(w) or 0,
            tonumber(h) or 0,
            tostring(UI.nativeLook)
        )
        out[#out + 1] = "ours normal: " .. describeTexture(ours.normal)
    end
    return out
end

function UI.copyNativeLook()
    if UI.nativeLook then
        return true
    end
    local native, list = nativeCategoryButton()
    if not native then
        return false
    end
    ---@cast native Button
    for _, c in ipairs(UI.categories or {}) do
        copyTexture(c.normal, nativeTexture(native, "Normal"))
        copyTexture(c.highlight, nativeTexture(native, "Highlight"))
        local nativeSelected = rawget(native, "SelectedTexture")
        if nativeSelected then
            copyTexture(c.selected, nativeSelected)
        end
    end
    copyPanel(UI.leftPanel, list)
    local browse = rawget(AuctionHouseFrame, "BrowseResultsFrame")
    local results = type(browse) == "table" and rawget(browse, "ItemList") or nil
    if type(results) == "table" then
        copyPanel(UI.right, results)
    end
    UI.nativeLook = true
    return true
end

local function icon(id)
    return F.Compat.itemIcon(id)
end

-- The last name a row showed, per key. While a quick scan checks its finds the client drops items
-- from its cache and loads them again: their names were "item:12047" for a moment, then came back.
UI.shownNames = {}

local function nameOf(key, link)
    -- A link with an empty name (the item not loaded yet) would show as "|...".
    local shown = U.linkName(link)
    if shown and shown ~= "" then
        UI.shownNames[key] = link
        return link
    end
    local item = U.parseKey(key)
    if item then
        local name, itemLink = U.itemInfo(item.id)
        local found = itemLink or name
        if found and U.linkName(found) ~= "" then
            UI.shownNames[key] = found
            return found
        end
        return UI.shownNames[key] or ("item:" .. item.id)
    end
    return key
end

-- count: the units a row holds (My items), so its tooltip counts the stack as the bag's does.
local function showTooltip(owner, key, link, count)
    if not GameTooltip then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    UI.tooltipCount = count
    local ok, err = pcall(function()
        if link then
            GameTooltip:SetHyperlink(link)
        else
            local item = U.parseKey(key)
            if item then
                GameTooltip:SetItemByID(item.id)
            end
        end
    end)
    UI.tooltipCount = nil
    if not ok then
        error(err, 0)
    end
    GameTooltip:Show()
end

-- Room on the right of a table for its scrollbar, as in the game's own lists (26 px).
local SCROLL_WIDTH = 22

-- A scrollbar like the auction house's own (MinimalScrollBar): an 8 px track with rounded ends,
-- a three-part thumb sized to the share of the list shown, and an arrow above and below, built
-- from the same atlases, 9 px to the right of the rows. The track and arrows always show; the
-- thumb only when the list is longer than the rows. Dragging the thumb, clicking the track (a
-- page) or an arrow (one row) and the mouse wheel scroll. `onScroll(offset)` gets the new first
-- row; `bar.update(offset, total, visible)` places the thumb.
local ARROW_W, ARROW_H, TRACK_GAP, CAP = 17, 11, 19, 8
local function atlas(texture, name)
    if texture.SetAtlas then
        texture:SetAtlas(name)
    end
end
local function threePart(frame, prefix, layer)
    local top = frame:CreateTexture(nil, layer)
    top:SetSize(CAP, CAP)
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    atlas(top, prefix .. "top")
    local bottom = frame:CreateTexture(nil, layer)
    bottom:SetSize(CAP, CAP)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    atlas(bottom, prefix .. "bottom")
    local middle = frame:CreateTexture(nil, layer)
    middle:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, 0)
    middle:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT", 0, 0)
    atlas(middle, prefix .. "middle")
    return { top, middle, bottom }
end
function UI.scrollBar(parent, anchor, height, onScroll, wheel)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(CAP, height)
    bar:SetPoint("TOPLEFT", anchor, "BOTTOMRIGHT", 9, 0)
    local trackHeight = height - 2 * TRACK_GAP
    local track = CreateFrame("Button", nil, bar)
    track:SetPoint("TOP", bar, "TOP", 0, -TRACK_GAP)
    track:SetSize(CAP, trackHeight)
    local trackParts = threePart(track, "minimal-scrollbar-track-", "ARTWORK")
    atlas(trackParts[2], "!minimal-scrollbar-track-middle")
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(CAP)
    thumb:SetPoint("TOP", track, "TOP", 0, 0)
    local thumbParts = threePart(thumb, "minimal-scrollbar-small-thumb-", "ARTWORK")
    local state = { offset = 0, total = 0, visible = 1, max = 0, thumb = 0 }
    local function light(on)
        for _, part in ipairs(thumbParts) do
            if part.SetVertexColor then
                part:SetVertexColor(on and 1.25 or 1, on and 1.25 or 1, on and 1.25 or 1)
            end
        end
    end
    local function scrollTo(offset)
        offset = math.max(0, math.min(state.max, math.floor(offset + 0.5)))
        if offset ~= state.offset then
            onScroll(offset)
        end
    end
    local function arrow(direction)
        local b = CreateFrame("Button", nil, bar)
        b:SetSize(ARROW_W, ARROW_H)
        b:SetPoint(direction, bar, direction, 0, 0)
        local tex = b:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints()
        local name = direction == "TOP" and "minimal-scrollbar-arrow-top" or "minimal-scrollbar-arrow-bottom"
        atlas(tex, name)
        b:SetScript("OnEnter", function()
            atlas(tex, name .. "-over")
        end)
        b:SetScript("OnLeave", function()
            atlas(tex, name)
        end)
        b:SetScript("OnMouseDown", function()
            atlas(tex, name .. "-down")
        end)
        b:SetScript("OnMouseUp", function()
            atlas(tex, name .. "-over")
        end)
        b:SetScript("OnClick", function()
            scrollTo(state.offset + (direction == "TOP" and -1 or 1))
        end)
        return b
    end
    bar.back, bar.forward = arrow("TOP"), arrow("BOTTOM")
    -- Dragging: the cursor's travel over the free track maps onto the offsets.
    local function cursorY()
        local _, y = GetCursorPosition()
        local scale = bar.GetEffectiveScale and bar:GetEffectiveScale() or 1
        return (y or 0) / ((scale and scale > 0) and scale or 1)
    end
    thumb:SetScript("OnMouseDown", function()
        state.drag = { y = cursorY(), offset = state.offset }
        light(true)
        thumb:SetScript("OnUpdate", function()
            local free = trackHeight - state.thumb
            if not state.drag or free <= 0 then
                return
            end
            local moved = state.drag.y - cursorY()
            scrollTo(state.drag.offset + moved / free * state.max)
        end)
    end)
    thumb:SetScript("OnMouseUp", function()
        state.drag = nil
        thumb:SetScript("OnUpdate", nil)
        light(false)
    end)
    thumb:SetScript("OnEnter", function()
        light(true)
    end)
    thumb:SetScript("OnLeave", function()
        if not state.drag then
            light(false)
        end
    end)
    -- A click on the track pages toward the click.
    track:SetScript("OnMouseDown", function()
        local top = track.GetTop and track:GetTop()
        if not top then
            return
        end
        local y = cursorY()
        local thumbTop = top - (trackHeight - state.thumb) * (state.max > 0 and state.offset / state.max or 0)
        if y > thumbTop then
            scrollTo(state.offset - state.visible)
        elseif y < thumbTop - state.thumb then
            scrollTo(state.offset + state.visible)
        end
    end)
    for _, f in ipairs({ bar, track, thumb, bar.back, bar.forward }) do
        if f.EnableMouseWheel then
            f:EnableMouseWheel(true)
            f:SetScript("OnMouseWheel", wheel)
        end
    end
    function bar.update(offset, total, visible)
        state.offset, state.total, state.visible = offset, total, visible
        state.max = math.max(0, total - visible)
        bar.back:SetEnabled(offset > 0)
        bar.forward:SetEnabled(offset < state.max)
        if state.max <= 0 then
            thumb:Hide()
            return
        end
        -- The thumb is at least 23 px, but shorter than the track, so it can move: the text boxes'
        -- 22 px track gets a 16 px thumb (its two 8 px caps) with room left to drag and page.
        state.thumb = math.max(math.min(23, trackHeight - 6), math.floor(trackHeight * visible / total))
        thumb:SetHeight(state.thumb)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -math.floor((trackHeight - state.thumb) * offset / state.max + 0.5))
        thumb:Show()
    end
    bar.thumb, bar.track = thumb, track
    return bar
end

-- A block of text lines that scrolls like the tables: the same scrollbar on the right, the mouse
-- wheel, one line per step. A line wider than the block goes on in the next rows, indented, its
-- colour carried over; hovering shows the whole block. box.set(lines) replaces them and keeps the
-- place when the text stays alike.
function UI.scrollText(parent, rows, top, bottom, height)
    local LINE = 14
    local box = { offset = 0, lines = {}, rows = rows, shown = "" }
    -- One text line per row: a single string that does not wrap shows only its first line in game.
    box.rowTexts = {}
    for i = 1, rows do
        local t = text(parent, "GameFontHighlightSmall")
        t:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -(top or 6) - (i - 1) * LINE)
        t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(8 + SCROLL_WIDTH), -(top or 6) - (i - 1) * LINE)
        t:SetJustifyH("LEFT")
        t:SetWordWrap(false)
        box.rowTexts[i] = t
    end
    -- What the rows show now, as one text (the tests and the hover read it).
    box.text = {
        GetText = function()
            return box.shown
        end,
    }
    local anchor = CreateFrame("Frame", nil, parent)
    anchor:SetSize(1, 1)
    anchor:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", -(SCROLL_WIDTH + 4), -(top or 6))
    -- Moves the block's first row to `y` below the parent's top (the rows and the scrollbar with it),
    -- when the line above the block is hidden and its place can be used.
    function box.moveTop(y)
        if box.top == y then
            return
        end
        box.top = y
        for i, t in ipairs(box.rowTexts) do
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -y - (i - 1) * LINE)
            t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(8 + SCROLL_WIDTH), -y - (i - 1) * LINE)
        end
        anchor:ClearAllPoints()
        anchor:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", -(SCROLL_WIDTH + 4), -y)
    end
    box.top = top or 6
    -- Does `s` fit one row? Measured by the game's font once the rows have a width; before that
    -- (and in a client without the measure) about WRAP_CHARS letters a row.
    local WRAP_CHARS = 110
    local probe = box.rowTexts[1]
    local function fits(s, width)
        if width and probe.GetUnboundedStringWidth then
            probe:SetText(s)
            local w = probe:GetUnboundedStringWidth()
            if w and w > 0 then
                return w <= width
            end
        end
        local plain = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "  ")
        local _, letters = plain:gsub("[^\128-\191]", "") -- UTF-8: one count per letter
        return letters <= WRAP_CHARS
    end
    -- The colour still open at the end of `s` (its last |c code with no |r after it), or nil.
    local function openColour(s)
        local last, at
        for p, code in s:gmatch("()(|c%x%x%x%x%x%x%x%x)") do
            last, at = code, p
        end
        if last and not s:find("|r", at, true) then
            return last
        end
        return nil
    end
    local cache, cached = {}, 0
    local function wrap(line, width)
        local key = tostring(width) .. "\1" .. line
        if cache[key] then
            return cache[key]
        end
        local out = {}
        if fits(line, width) then
            out[1] = line
        else
            local indent = (line:match("^(%s*)") or "") .. "   "
            local current
            for word in line:gmatch("%S+") do
                if not current then
                    current = (line:match("^(%s*)") or "") .. word
                elseif fits(current .. " " .. word, width) then
                    current = current .. " " .. word
                else
                    local colour = openColour(current)
                    out[#out + 1] = current .. (colour and "|r" or "")
                    current = indent .. (colour or "") .. word
                end
            end
            out[#out + 1] = current or line
        end
        if cached > 300 then
            cache, cached = {}, 0
        end
        cache[key], cached = out, cached + 1
        return out
    end
    local function rowsOf(lines)
        local width = probe.GetWidth and probe:GetWidth() or 0
        width = width > 0 and width or nil
        local out = {}
        for _, line in ipairs(lines) do
            for _, piece in ipairs(wrap(line, width)) do
                out[#out + 1] = piece
            end
        end
        return out
    end
    local function render()
        local shown = {}
        for i = 1, rows do
            local line = box.wrapped[box.offset + i]
            box.rowTexts[i]:SetText(line or "")
            shown[#shown + 1] = line
        end
        box.shown = table.concat(shown, "\n")
        box.bar.update(box.offset, #box.wrapped, rows)
    end
    local function scrollTo(offset)
        box.offset = math.max(0, math.min(math.max(0, #box.wrapped - rows), offset))
        render()
    end
    box.wrapped = {}
    local function wheel(_, delta)
        scrollTo(box.offset - (delta or 0))
    end
    local scrollHeight = height or math.max(ARROW_H * 2 + TRACK_GAP * 2, rows * LINE - (bottom or 0))
    box.bar = UI.scrollBar(parent, anchor, scrollHeight, scrollTo, wheel)
    if parent.EnableMouseWheel then
        parent:EnableMouseWheel(true)
        parent:SetScript("OnMouseWheel", wheel)
    end
    if parent.EnableMouse then
        parent:EnableMouse(true)
    end
    parent:SetScript("OnEnter", function(self)
        if GameTooltip and #box.wrapped > rows then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(table.concat(box.lines, "\n"), 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    parent:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    -- `key` names the subject (the selected auction): another subject starts at the top, the
    -- same one keeps its place while its numbers change.
    function box.set(lines, key)
        key = key or lines[1] or ""
        if key ~= box.key then
            box.key, box.offset = key, 0
        end
        box.lines = lines
        box.wrapped = rowsOf(lines)
        scrollTo(box.offset)
    end
    function box.full()
        return table.concat(box.lines, "\n")
    end
    return box
end

-- A results table: header buttons and rows. `columns` = { {label, width, align}, ... }; the first
-- column is the item (icon and name) and takes the remaining width.
UI.tables = {}
local function table_(parent, columns, rows, onClick, onSort)
    local t = { rows = {}, headers = {} }
    UI.tables[#UI.tables + 1] = t
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
    -- Room on the right for the scrollbar.
    header:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4 - SCROLL_WIDTH, -4)
    header:SetHeight(20)
    -- A column's fourth field (optional) explains it in a tooltip over its header.
    local function headerCell(label, width, align, index, tip)
        local h = CreateFrame("Button", nil, header, "AuctionHouseTableHeaderStringTemplate")
        if tip then
            UI.tip(h, label, tip, "ANCHOR_TOP")
        end
        h:SetHeight(20)
        if width then
            h:SetWidth(width)
        end
        h.columnWidth = width -- for a test: does the name fit?
        h:SetText(L(label))
        local fs = h.GetFontString and h:GetFontString()
        if fs then
            fs:ClearAllPoints()
            -- The sort arrow takes the right 11 px; narrow columns (Qty, Sure) keep their names
            -- whole with the rest (the padding was 6 and 16, and "Qty" became "...").
            fs:SetPoint("LEFT", h, "LEFT", 2, 0)
            fs:SetPoint("RIGHT", h, "RIGHT", -11, 0)
            fs:SetJustifyH(align or "RIGHT")
            fs:SetWordWrap(false)
            -- A name that still does not fit (a long translation) is cut with "...": the header
            -- then names its column in full when hovered.
            local measure = fs.GetUnboundedStringWidth or fs.GetStringWidth
            local room = width and width - 13
            if not tip and room and measure and (measure(fs) or 0) > room then
                UI.tip(h, nil, label, "ANCHOR_TOP")
            end
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
        local h = headerCell(c[1], c[2], c[3], i, c[4])
        h:SetPoint("TOPRIGHT", header, "TOPRIGHT", -x, 0)
        cells[i] = { x = x, width = c[2], align = c[3] }
        x = x + c[2]
    end
    local first = headerCell(columns[1][1], nil, "LEFT", 1, columns[1][4])
    first:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
    first:SetPoint("TOPRIGHT", header, "TOPRIGHT", -x, 0)
    -- Scrolling: a list longer than the rows is scrolled with the mouse wheel or the scrollbar on
    -- the right; the first header says which entries are shown.
    t.offset, t.size = 0, rows
    function t.scroll(steps)
        t.offset = math.max(0, (t.offset or 0) + steps * 3)
        UI.refresh()
    end
    local function wheel(_, delta)
        t.scroll(-delta)
    end
    if header.EnableMouseWheel then
        header:EnableMouseWheel(true)
        header:SetScript("OnMouseWheel", wheel)
    end
    t.wheel = wheel
    local bar = UI.scrollBar(parent, header, rows * ROW, function(offset)
        if offset ~= t.offset then
            t.offset = offset
            UI.refresh()
        end
    end, wheel)
    t.bar = bar
    -- A sorted copy of `list` by the chosen column. `value(entry, column)` returns a number, a
    -- string or nil; nil sorts last in both directions, equal values keep the list's order.
    function t.sort(list, value)
        local index = t.sortIndex
        t.setSort(index, t.descending)
        local out = {}
        for i, e in ipairs(list) do
            out[i] = e
        end
        t.sorted = out -- the whole list as shown, for the bulk buttons (UI.order)
        if not index then
            return t.window(out)
        end
        local keys, order = {}, {}
        for i, e in ipairs(out) do
            local v = value(e, index)
            if type(v) == "string" then
                -- An item link sorts by the name it shows, not by its "|Hitem:<id>:..." text.
                local shown = U.linkName(v)
                if shown and shown ~= "" then
                    v = shown
                end
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
        t.sorted = out
        return t.window(out)
    end
    -- The part of a sorted list the rows show, from the scroll offset; the first header counts.
    function t.window(list)
        local total = #list
        local label = L(columns[1][1])
        if total <= t.size then
            t.offset = 0
            first:SetText(label)
            bar.update(0, total, t.size)
            return list
        end
        t.offset = math.max(0, math.min(t.offset or 0, total - t.size))
        bar.update(t.offset, total, t.size)
        first:SetText(
            string.format("%s " .. UI.C.dim .. "(%d-%d / %d)|r", label, t.offset + 1, t.offset + t.size, total)
        )
        local out = {}
        for i = 1, t.size do
            out[i] = list[t.offset + i]
        end
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
        r.back = r:CreateTexture(nil, "BACKGROUND", nil, -1)
        r.back:SetAllPoints()
        r.back:Hide()
        if i % 2 == 0 then
            r.stripe = r:CreateTexture(nil, "BACKGROUND")
            r.stripe:SetAtlas("auctionhouse-rowstripe-1")
            r.stripe:SetAllPoints()
        end
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAtlas("auctionhouse-ui-row-highlight")
        hl:SetAllPoints()
        hl:SetBlendMode("ADD")
        r.hl = hl
        r.selected = r:CreateTexture(nil, "ARTWORK")
        r.selected:SetAtlas("auctionhouse-ui-row-select")
        r.selected:SetAllPoints()
        r.selected:SetBlendMode("ADD")
        r.selected:Hide()
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(ROW - 4, ROW - 4)
        r.icon:SetPoint("LEFT", r, "LEFT", 4, 0)
        r.name = text(r, "GameFontHighlight")
        local setName = r.name.SetText
        r.name.SetText = function(self, value)
            if type(value) == "string" then
                value = value:gsub("|h%[(.-)%]|h", "|h%1|h")
            end
            return setName(self, value)
        end
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
        r.name:SetPoint("RIGHT", r, "RIGHT", -x - 4, 0)
        r.name:SetWordWrap(false)
        r.cols = {}
        for n = 2, #columns do
            local c = text(r, "GameFontHighlight")
            c:SetPoint("RIGHT", r, "RIGHT", -cells[n].x - 6, 0)
            c:SetWidth(cells[n].width - 10)
            c:SetJustifyH(cells[n].align or "RIGHT")
            c:SetWordWrap(false)
            r.cols[n - 1] = c
        end
        if r.RegisterForClicks then
            r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        end
        if r.EnableMouseWheel then
            r:EnableMouseWheel(true)
            r:SetScript("OnMouseWheel", t.wheel)
        end
        r:SetScript("OnClick", function(self, mouse)
            F.Engine.input()
            if IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
                local item = self.key and U.parseKey(self.key)
                local itemLink = self.link or (item and select(2, U.itemInfo(item.id)))
                if itemLink and ChatEdit_InsertLink(itemLink) then
                    return -- Shift-click: the item's link into the chat line
                end
            end
            if mouse == "RightButton" and self.key then
                UI.showHistory(self.key, self.link)
                return
            end
            onClick(self)
        end)
        -- Hovering a row shows the item with ForeverFlip's own block, which already says the price,
        -- profit, Est./day and Sure: the row's columns are not repeated under it (they were seven
        -- extra lines: Qty, Buy at, Sells at, Profit, Est./day, Sure, Status). A row without an item
        -- lists its columns in full, so text cut short in a narrow column can still be read.
        r:SetScript("OnEnter", function(self)
            if not GameTooltip then
                return
            end
            -- A table with a tooltip of its own for its rows (Crafting: UI.craftTooltip).
            if t.rowTooltip and t.rowTooltip(self) then
                return
            end
            if self.key then
                showTooltip(self, self.key, self.link, t == UI.sellTable and self.item and self.item.count or nil)
                GameTooltip:Show()
                return
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.name:GetText() or "", 1, 1, 1)
            GameTooltip:AddLine(" ")
            for n = 2, #columns do
                local value = self.cols[n - 1]:GetText()
                if value and value ~= "" then
                    UI.tipPair(GameTooltip, L(columns[n][1]), value, 1, 0.82, 0)
                end
            end
            GameTooltip:Show()
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
    -- Two tables share one page (the Deals page swaps its columns for the vendor filter): the one
    -- not in use hides every region of its own, header, rows, scrollbar and empty text included.
    t.frame = header
    function t.show(shown)
        header:SetShown(shown)
        for _, r in ipairs(t.rows) do
            r:SetShown(shown and r.key ~= nil)
        end
        if not shown then
            t.empty:Hide()
        end
        t.bar:SetShown(shown)
    end
    return t
end

-- Main frame --------------------------------------------------------------------------------------
-- The window's size (Settings, Display): its contents drawn smaller or larger inside the auction
-- house window. The frame's anchors are in its own scale, so the offsets are divided by it to keep
-- the frame where it was. Only our own frame is scaled.
UI.SCALES = { 0.9, 1, 1.1 }
function UI.windowScale()
    local s = F.db and F.db.settings and tonumber(F.db.settings.windowScale) or 1
    return math.max(0.8, math.min(1.25, s))
end
function UI.applyScale()
    local f = UI.frame
    if not f then
        return
    end
    local scale = UI.windowScale()
    if f.SetScale then
        f:SetScale(scale)
    end
    f:ClearAllPoints()
    if AuctionHouseFrame then
        f:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 4 / scale, -73 / scale)
        f:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -4 / scale, 27 / scale)
    else
        f:SetSize(800, 500)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    UI.shownScale = scale
end

function UI.create()
    local f = CreateFrame("Frame", "ForeverFlipFrame", AuctionHouseFrame or UIParent)
    UI.frame = f
    UI.applyScale()
    f:Hide()
    f:SetScript("OnShow", function()
        F.Engine.changed()
        UI.refresh()
    end)

    -- Top bar: scan, sniper and bulk check buttons, status text.
    UI.scanButton = button(f, "Full scan", 150, function()
        -- The same button stops a scan it started: it reads Stop scan while one runs. Scan.stop
        -- says what became of the request (the answer may still come and be read on reopening).
        if F.Scan.busy() then
            F.Scan.stop()
            UI.refresh()
            return
        end
        if F.Sniper.stopQuick() then
            UI.refresh()
            return
        end
        -- During the full scan's 15-minute wait the button offers a quick scan (UIStatus says so).
        if (F.Scan.cooldown() > 0 or not F.Compat.caps.fullScan) and F.Sniper.startQuick() then
            UI.refresh()
            return
        end
        local ok, why = F.Scan.start()
        if not ok then
            F.Engine.notify(why)
        end
    end)
    UI.scanButton:SetPoint("TOPLEFT", f, "TOPLEFT", 82, 35)
    UI.sniperButton = button(f, "Sniper: ON", 116, function()
        F.Deals.setSniper(not F.db.settings.sniper)
        UI.refresh()
    end)
    UI.sniperButton:SetPoint("LEFT", UI.scanButton, "RIGHT", 6, 0)
    -- Check all: every entry of the open page is searched on the auction house again (one search
    -- after another), and the page shows what was found.
    -- It reads Stop only while checks, a sale or a purchase run, which is what it ends. A full scan
    -- is not one of them: it runs on its own and the checks wait for it (Deals.startBatch holds
    -- them, Deals.startRequest lets none go meanwhile), so a button that read Stop during the six
    -- minutes of a scan only ended the scan the player was waiting for.
    UI.bulkButton = button(f, "Check all", 110, function()
        if F.Deals.stoppingWork() then
            F.Deals.stopAll()
            UI.refresh()
        else
            UI.checkStatuses()
        end
    end)
    UI.bulkButton:SetPoint("LEFT", UI.sniperButton, "RIGHT", 6, 0)
    -- Which auction house this is (its own prices; a neutral one takes 15%): in the middle of the
    -- bar beside the money display (UI.placeHouse), else in the top right corner.
    UI.houseBadge = text(f, "GameFontNormal")
    -- The top right corner the status line and the house badge end at (the Messages button was
    -- here; the messages are a chat tab now, Log.lua).
    UI.corner = CreateFrame("Frame", nil, f)
    UI.corner:SetSize(1, 1)
    UI.corner:SetPoint("RIGHT", f, "TOPRIGHT", -12, 24)
    UI.status = text(f, "GameFontNormal")
    UI.placeHouse()
    UI.status:SetWordWrap(false)
    -- The status line is cut to one line: hovering it shows all of it.
    UI.statusHover = CreateFrame("Frame", nil, f)
    UI.statusHover:SetAllPoints(UI.status)
    if UI.statusHover.EnableMouse then
        UI.statusHover:EnableMouse(true)
    end
    UI.statusHover:SetScript("OnEnter", function(self)
        local shown = UI.status:GetText()
        if GameTooltip and shown and shown ~= "" then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(shown, 1, 0.82, 0, 1, true)
            if F.Deals.busy() then
                GameTooltip:AddLine(L("Stop ends all running checks, the scan and the merchant sale."), 1, 1, 1, true)
            end
            GameTooltip:Show()
        end
    end)
    UI.statusHover:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
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
    local marble = rawget(left, "Bg")
    if type(marble) == "table" and marble.Hide then
        marble:Hide()
    end
    UI.leftPanel = left
    UI.categories = {}
    for i, group in ipairs(UI.GROUPS) do
        local c = category(left, group.label, function()
            UI.show(group.current or group.pages[1][1])
        end)
        c:SetPoint("TOPLEFT", left, "TOPLEFT", NAV_X, NAV_Y - (i - 1) * NAV_STEP)
        c.group = group
        UI.categories[i] = c
        c.subs = {}
        UI.menuKids = UI.menuKids or {}
        if #group.pages > 1 then
            for _, entry in ipairs(group.pages) do
                local sub = category(left, entry[2], function()
                    UI.show(entry[1])
                end, true)
                sub.id, sub.isSub = entry[1], true
                sub:Hide()
                c.subs[#c.subs + 1] = sub
                -- A page with views of its own (entry.kids) opens them under its entry.
                sub.kids = {}
                for _, kid in ipairs(entry.kids or {}) do
                    local k = category(left, kid[2], function()
                        UI.show(kid[1])
                    end, true)
                    styleTertiary(k)
                    k.id = kid[1]
                    UI.menuKids[kid[1]] = k
                    k:Hide()
                    sub.kids[#sub.kids + 1] = k
                end
            end
        end
    end
    UI.summary = text(left, "GameFontHighlightSmall")
    UI.summary:SetSpacing(1)

    -- Right: one page per category.
    local right = inset(f, "auctionhouse-background-index")
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    UI.right = right
    UI.pages = {}
    for _, id in ipairs({
        "deals",
        "shop",
        "mybids",
        "bids",
        "sell",
        "auctions",
        "undercuts",
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
    UI.createDeals(UI.pages.deals)
    UI.createShop(UI.pages.shop)
    UI.createBids(UI.pages.bids)
    UI.createMyBids(UI.pages.mybids)
    UI.createSell(UI.pages.sell)
    UI.createAuctions(UI.pages.auctions)
    UI.createUndercuts(UI.pages.undercuts)
    UI.createStats(UI.pages.stats)
    UI.createAnalytics(UI.pages.analytics)
    UI.createCrafting(UI.pages.crafting)
    UI.createJournal(UI.pages.journal)
    UI.createSettings(UI.pages.settings)
    UI.show(F.db.ui and F.db.ui.section or "deals:all")
end

-- Six entries on the left, in the order of the work: buy, plan what to buy, craft, sell, look at the
-- results, set up. Deals go from all of them to each way of buying (resale, vendor, bids); the deals
-- of the shopping list sit with the list. A group of several pages opens them under it. The page ids
-- (UI.show) stay the same. Groups remember the page shown last.
UI.GROUPS = {
    {
        label = "Deals",
        pages = {}, -- All, then the bought strategies of F.STRATEGIES (below)
    },
    {
        label = "Shopping list",
        -- Saved intent and the live deals it produces share one view. Keep the old
        -- deals:shop id as a compatibility alias in UI.show, but hide duplicate navigation.
        pages = { { "shop", "My list" }, { "mybids", "My bids" } },
    },
    -- Crafting and disenchanting: both turn bought items into something else with a profession, so
    -- the group is named for both. The Disenchant page is the deals page shown with the disenchant
    -- deals (its own reasons, see refreshDeals).
    { label = "Professions", pages = { { "crafting", "Crafting" }, { "deals:disenchant", "Disenchant" } } },
    {
        label = "Selling",
        pages = {
            -- My items holds two views, the items for sale and the hidden ones (sell:sale, sell:hidden).
            { "sell", "My items", kids = { { "sell:sale", "For sale" }, { "sell:hidden", "Hidden" } } },
            { "auctions", "My auctions" },
            { "undercuts", "Undercuts" },
        },
    },
    {
        label = "Analytics",
        pages = {
            { "analytics", "Overview" },
            { "stats", "By item" },
            {
                "journal",
                "Journal and profit",
                kids = {}, -- All, then every strategy of F.STRATEGIES (below)
            },
        },
    },
    {
        label = "Settings",
        pages = {
            { "settings", "General" },
            { "settings:auto", "Automation" },
            { "settings:display", "Display" },
            { "settings:keys", "Key bindings" },
            { "settings:share", "Sharing" },
            { "settings:messages", "Messages" },
            { "settings:data", "Data" },
        },
    },
}
-- Deals and Journal list the strategies in the order of F.STRATEGIES: one table, so the two
-- cannot drift apart.
do
    local deals, journal = { { "deals:all", "All" } }, { { "journal:all", "All" } }
    for _, st in ipairs(F.STRATEGIES) do
        if st.page then
            deals[#deals + 1] = { st.page, st.label }
        end
        journal[#journal + 1] = { "journal:" .. st.id, st.label }
    end
    UI.GROUPS[1].pages = deals
    for _, g in ipairs(UI.GROUPS) do
        for _, page in ipairs(g.pages) do
            if page[1] == "journal" then
                page.kids = journal
            end
        end
    end
end

function UI.groupOf(id)
    for _, group in ipairs(UI.GROUPS) do
        for _, entry in ipairs(group.pages) do
            if entry[1] == id then
                return group
            end
            for _, kid in ipairs(entry.kids or {}) do
                if kid[1] == id then
                    return group
                end
            end
        end
    end
    return UI.GROUPS[1]
end

-- The summary under the menu: the height of a line, and the room kept for the money at the bottom.
UI.SUMMARY_LINE, UI.SUMMARY_BOTTOM = 12, 28

function UI.layoutMenu(group, id)
    local left = UI.leftPanel
    local y = NAV_Y
    for _, c in ipairs(UI.categories) do
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", left, "TOPLEFT", NAV_X, y)
        y = y - NAV_STEP
        if c.group == group then
            c.selected:Show()
        else
            c.selected:Hide()
        end
        for _, sub in ipairs(c.subs) do
            if c.group == group then
                sub:ClearAllPoints()
                sub:SetPoint("TOPLEFT", left, "TOPLEFT", NAV_X, y)
                y = y - NAV_STEP
                -- A view ("journal:flip") opens its page's entry; a page id that only starts the same
                -- way ("settings:keys" under "settings") is an entry of its own.
                local open = sub.id == id or #(sub.kids or {}) > 0 and id:sub(1, #sub.id + 1) == sub.id .. ":"
                if open then
                    sub.selected:Show()
                else
                    sub.selected:Hide()
                end
                sub:Show()
                for i, k in ipairs(sub.kids or {}) do
                    if open then
                        k:ClearAllPoints()
                        k:SetPoint("TOPLEFT", left, "TOPLEFT", NAV_X, y)
                        y = y - NAV_STEP
                        -- The page itself (no view chosen) is its first view.
                        if k.id == id or (i == 1 and id == sub.id) then
                            k.selected:Show()
                        else
                            k.selected:Hide()
                        end
                        k:Show()
                    else
                        k:Hide()
                    end
                end
            else
                sub:Hide()
                for _, k in ipairs(sub.kids or {}) do
                    k:Hide()
                end
            end
        end
    end
    UI.summary:ClearAllPoints()
    UI.summary:SetPoint("TOPLEFT", left, "TOPLEFT", 9, y - 8)
    UI.summary:SetPoint("TOPRIGHT", left, "TOPRIGHT", -4, y - 8)
    UI.summaryTop = y - 8
    UI.fitSummary()
end

-- A long menu (Analytics with its views open) leaves less room: the summary keeps only the lines
-- that fit above the money at the bottom, or none, rather than run out of the window. Asked again
-- at each refresh of the summary: the panel measured while the window was still being laid out
-- was short, and the summary stayed cut to four lines until another page was opened.
function UI.fitSummary()
    local left, top = UI.leftPanel, UI.summaryTop
    local height = left and top and left:GetHeight()
    if type(height) == "number" and height > 0 then
        local lines = math.floor((height + top - UI.SUMMARY_BOTTOM) / UI.SUMMARY_LINE)
        UI.summaryLines = math.max(0, lines)
        if lines >= 1 then
            UI.summary:SetMaxLines(lines)
            UI.summary:Show()
        else
            UI.summary:Hide()
        end
    end
end

-- The selected deal leaves the page (ignored, or hidden by the page's filter): a price quote asked
-- for it goes with it, else the Buy button's Confirm would buy an item that is no longer selected.
local function dropSelection()
    local op = F.Trade.op
    if op and op.key == UI.selected and (op.state == "quote" or op.state == "quoted") then
        F.Trade.cancel()
    end
    UI.selected = nil
end

function UI.show(id)
    if id == "deals:shop" then
        id = "shop"
    end
    -- The Safety page joined General (its Limits section); a saved page or an old link still opens.
    if id == "settings:safety" then
        id = "settings"
    end
    if F.Log.dev() then
        F.Log.trace("show", "%s", tostring(id))
    end
    local page, filter = id:match("^(%a+):?(%a*)$")
    if not page or not UI.pages[page] then
        page, filter, id = "deals", "all", "deals:all"
    end
    UI.section = page
    if page ~= "deals" then
        UI.buyHoverKey = nil
    end
    -- Another page: a key capture still waiting ends (in the game the catcher's OnHide does it too).
    if UI.capturing and id ~= "settings:keys" then
        UI.cancelCapture()
    end
    if page == "settings" then
        UI.setSettingsFrame(filter ~= "" and filter or "general")
    end
    if page == "journal" then
        UI.journalFilter = filter ~= "" and filter or "all"
        if UI.lotTable then
            UI.lotTable.offset = 0
        end
    end
    if page == "sell" then
        -- The view of My items comes with the id; the page itself opens its first view, For sale.
        local view = filter == "hidden" and "hidden" or "sale"
        if view ~= UI.sellView then
            UI.sellView, UI.sellSelected, UI.sellSureCheck = view, nil, nil
            if UI.sellPrice then
                UI.sellPrice:SetText("")
            end
        end
    end
    if page == "deals" then
        UI.filter = filter ~= "" and filter or "all"
        UI.dealPage = 1
        -- A lot that pays both ways answers with the route of the page shown (Deals.get).
        F.Deals.view = UI.filter
        local d = UI.selected and F.Deals.get(UI.selected, "all")
        if d and not F.Deals.route(d, UI.filter) then
            dropSelection()
        end
    else
        F.Deals.view = nil
    end
    F.db.ui = F.db.ui or {}
    F.db.ui.section = id
    local group = UI.groupOf(id)
    group.current = id
    for key, p in pairs(UI.pages) do
        if key == page then
            p:ClearAllPoints()
            p:SetPoint("TOPLEFT", UI.right, "TOPLEFT", 3, -3)
            p:SetPoint("BOTTOMRIGHT", UI.right, "BOTTOMRIGHT", -3, 3)
            p:Show()
        else
            p:Hide()
        end
    end
    UI.layoutMenu(group, id)
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

-- Why the Resale page is empty: what the last scan rejected its items for, the most common first,
-- each with what would change it.
local NO_RESALE = {
    thin = "%d sell, but too few purchases were seen yet to buy enough of them",
    collecting = "%d are still being learned: under an hour of full scans has seen no sale yet (each scan adds to it)",
    not_selling = "%d are not bought at the price they would resell at",
    small = "%d would earn less than your minimum (%s and %d%% return, Settings)",
    budget = "%d cost more than your budget allows (%s; one item at most %s)",
    enough_stock = "%d: you already hold a day of their sales",
    blocked = "%d are on your ignore list",
}
-- T25: why the Market reset page is empty: off, no sales measured yet, or what the last scan
-- turned its items down for, the most common first, each with what would change it (the old text
-- named the rules but never which one stopped this house's items).
local NO_MEDIAN = {
    no_median = "%d have no known price yet (a full scan gives one)",
    no_gap = "%d have no lot cheap enough: under the usual price after the 5%% cut",
    small = "%d would earn less than your minimum (%s and %d%% return, Settings)",
    budget = "%d cost more than the money left for this page (%s; per item %s)",
    not_selling = "%d are not bought at their usual price",
    enough_stock = "%d: you already hold three days of their sales",
    too_much = "%d have more under the price than sells in three days (or over %d lots): no reset",
    sources_disagree = "%d: your scans and the community's disagree on the usual price",
    blocked = "%d are on your ignore list",
}
function UI.noMedianText(stats)
    local s = F.db.settings
    if F.Deals.medianOff() then
        return L(
            "Market reset is off: its Per day or % of gold below the list is 0. Set both above 0: items whose every lot under the usual price (its median of the last 7 days, or its last market price) can be bought are offered, to relist alone at that price."
        )
    end
    local lines = {}
    stats = stats or {}
    if (stats.salesReady or 0) == 0 then
        lines[#lines + 1] = L(
            "No sales measured yet: two full scans at least 5 minutes apart measure them. Until then a reset is offered (few sales data) only when the lots under the price are a day of sales."
        )
    end
    lines[#lines + 1] = L("No market reset right now. Why, for the items of the last scan:")
    local order = {}
    for reason, n in pairs(stats.medianReasons or {}) do
        if NO_MEDIAN[reason] and n > 0 then
            order[#order + 1] = { reason = reason, n = n }
        end
    end
    table.sort(order, function(x, y)
        return x.n > y.n
    end)
    for i = 1, math.min(5, #order) do
        local r = order[i]
        local line
        if r.reason == "small" then
            line = string.format(
                L(NO_MEDIAN.small),
                r.n,
                U.money(F.Market.thresholds(s).minProfit),
                UI.pct(F.Market.thresholds(s).minROI)
            )
        elseif r.reason == "budget" then
            line = string.format(
                L(NO_MEDIAN.budget),
                r.n,
                U.money(F.Deals.medianRoom()),
                U.money(math.floor((tonumber(s.medianItemGold) or 0) * 10000))
            )
        elseif r.reason == "too_much" then
            line = string.format(L(NO_MEDIAN.too_much), r.n, F.Market.RESET_MAX_LOTS)
        else
            line = string.format(L(NO_MEDIAN[r.reason]), r.n)
        end
        lines[#lines + 1] = "- " .. line
    end
    if not order[1] then
        lines[#lines + 1] = "- " .. L("no full scan has been read yet")
    end
    lines[#lines + 1] = string.format(L("Left to spend on this page today: %s."), U.money(F.Deals.medianRoom()))
    return table.concat(lines, "\n")
end

function UI.noResaleText(stats)
    stats = stats or {}
    local s = F.db.settings
    local lines = { L("No resale right now. Why, for the items of the last scan:") }
    local order = {}
    for reason, n in pairs(stats.reasons or {}) do
        if NO_RESALE[reason] and n > 0 then
            order[#order + 1] = { reason = reason, n = n }
        end
    end
    table.sort(order, function(a, b)
        return a.n > b.n
    end)
    for i = 1, math.min(5, #order) do
        local r = order[i]
        local line
        if r.reason == "small" then
            line = string.format(
                L(NO_RESALE.small),
                r.n,
                U.money(F.Market.thresholds(s).minProfit),
                UI.pct(F.Market.thresholds(s).minROI)
            )
        elseif r.reason == "budget" then
            line = string.format(
                L(NO_RESALE.budget),
                r.n,
                U.money(F.Deals.budget()),
                U.money(math.floor(F.Engine.wallet() * (s.itemShare or 0.3)))
            )
        else
            line = string.format(L(NO_RESALE[r.reason]), r.n)
        end
        lines[#lines + 1] = "- " .. line
    end
    if not order[1] then
        lines[#lines + 1] = "- " .. L("no item has a price gap to resell into")
    end
    lines[#lines + 1] = string.format(
        L("Budget: %s; one item at most %s; minimum profit %s."),
        U.money(F.Deals.budget()),
        U.money(math.floor(F.Engine.wallet() * (s.itemShare or 0.3))),
        U.money(F.Market.thresholds(s).minProfit)
    )
    local onePair = stats.onePair or 0
    if onePair > 0 and onePair * 2 >= (stats.salesReady or 0) then
        local cooldown = F.Scan.cooldown and F.Scan.cooldown() or 0
        lines[#lines + 1] = ""
        lines[#lines + 1] = string.format(
            L(
                "Sales data is being collected: %d items were measured over one pair of scans, and resale buys at most 2 of each until a second pair. The next full scan (%s) adds it."
            ),
            onePair,
            cooldown > 0 and string.format(L("in %d:%02d"), math.floor(cooldown / 60), cooldown % 60) or L("now")
        )
    end
    return table.concat(lines, "\n")
end

-- Locals the page files (UI*.lua, loaded after this file) share.
UI.shared = {}
UI.shared.F = F
UI.shared.U = U
UI.shared.L = L
UI.shared.MESSAGES = MESSAGES
UI.shared.text = text
UI.shared.button = button

-- A Duration button's label: its hours on this client (Trade.DURATION_HOURS), or Auto.
function UI.durationLabel(d)
    return d == 0 and "Auto" or tostring(F.Trade.DURATION_HOURS[d])
end
UI.shared.editbox = editbox
UI.shared.place = place
UI.shared.hint = UI.tip
UI.shared.icon = icon
UI.shared.nameOf = nameOf
UI.shared.atlas = atlas
UI.shared.table_ = table_
UI.shared.dropSelection = dropSelection
UI.shared.footer = footer
