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
-- The Buy tab's category list (AuctionHouseFrame.CategoriesList) is 168 wide: its art (138) and a
-- scroll bar beside it. ForeverFlip's menu has no scroll bar, so the list ends with the art.
local LEFT_WIDTH = 144

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
    scan_timeout = "The server sent no full scan in 5 minutes (the list stayed empty; another addon or another character of the account may have used the 15-minute window). Next try 15 minutes after this one: an earlier call would start the server's wait again.",
    scan_unsettled = "The full scan list kept changing for 5 minutes and was not read. Next try 15 minutes after this one.",
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
    b:SetScript("OnClick", function(...)
        F.Engine.input()
        return onClick(...)
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
    for _, region in ipairs({ frame.GetRegions and frame:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "FontString" and region.GetFont and region:GetFont() then
            local shown = region.GetText and region:GetText()
            if shown and shown ~= "" then
                return region
            end
        end
    end
    for _, child in ipairs({ frame.GetChildren and frame:GetChildren() }) do
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
        for _, child in ipairs({ target and target.GetChildren and target:GetChildren() }) do
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
    if C_Item and C_Item.GetItemIconByID then
        return C_Item.GetItemIconByID(id)
    end
    return 134400
end

local function nameOf(key, link)
    -- A link with an empty name (the item not loaded yet) would show as "|...".
    local shown = U.linkName(link)
    if shown and shown ~= "" then
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
        state.thumb = math.max(23, math.floor(trackHeight * visible / total))
        thumb:SetHeight(state.thumb)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -math.floor((trackHeight - state.thumb) * offset / state.max + 0.5))
        thumb:Show()
    end
    bar.thumb, bar.track = thumb, track
    return bar
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
        if not index then
            return t.window(out)
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
        first:SetText(string.format("%s |cff999999(%d-%d / %d)|r", label, t.offset + 1, t.offset + t.size, total))
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
        -- Hovering a row shows the item, and below it every column of the row in full: names
        -- and states cut short in the narrow columns can be read there.
        r:SetScript("OnEnter", function(self)
            if not GameTooltip then
                return
            end
            if self.key then
                showTooltip(self, self.key, self.link)
            else
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.name:GetText() or "", 1, 1, 1)
            end
            GameTooltip:AddLine(" ")
            for n = 2, #columns do
                local value = self.cols[n - 1]:GetText()
                if value and value ~= "" then
                    GameTooltip:AddDoubleLine(L(columns[n][1]), value, 1, 0.82, 0, 1, 1, 1)
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
    return t
end

-- Main frame --------------------------------------------------------------------------------------
function UI.create()
    local f = CreateFrame("Frame", "ForeverFlipFrame", AuctionHouseFrame or UIParent)
    if AuctionHouseFrame then
        f:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 4, -73)
        f:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -4, 27)
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
    UI.scanButton:SetPoint("TOPLEFT", f, "TOPLEFT", 82, 35)
    UI.sniperButton = button(f, "Sniper: ON", 116, function()
        F.Deals.setSniper(not F.db.settings.sniper)
        UI.refresh()
    end)
    UI.sniperButton:SetPoint("LEFT", UI.scanButton, "RIGHT", 6, 0)
    -- Check all: every entry of the open page is searched on the auction house again (one search
    -- after another), and the page shows what was found.
    -- Check all, or Stop while anything runs (F.Deals.busy): one click ends all work.
    UI.bulkButton = button(f, "Check all", 110, function()
        if F.Deals.busy() then
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
        if #group.pages > 1 then
            for _, entry in ipairs(group.pages) do
                local sub = category(left, entry[2], function()
                    UI.show(entry[1])
                end, true)
                sub.id, sub.isSub = entry[1], true
                sub:Hide()
                c.subs[#c.subs + 1] = sub
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
        pages = {
            { "deals:all", "All" },
            { "deals:flip", "Resale" },
            { "deals:vendor", "To vendor" },
            { "bids", "Bids" },
        },
    },
    { label = "Shopping list", pages = { { "shop", "My list" }, { "deals:shop", "Deals from the list" } } },
    { label = "Crafting", pages = { { "crafting", "Crafting" } } },
    {
        label = "Selling",
        pages = { { "sell", "My items" }, { "auctions", "My auctions" }, { "undercuts", "Undercuts" } },
    },
    {
        label = "Analytics",
        pages = { { "analytics", "Overview" }, { "stats", "By item" }, { "journal", "Journal and profit" } },
    },
    {
        label = "Settings",
        pages = {
            { "settings", "General" },
            { "settings:keys", "Key bindings" },
            { "settings:share", "Sharing" },
            { "settings:safety", "Safety" },
        },
    },
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
                if sub.id == id then
                    sub.selected:Show()
                else
                    sub.selected:Hide()
                end
                sub:Show()
            else
                sub:Hide()
            end
        end
    end
    UI.summary:ClearAllPoints()
    UI.summary:SetPoint("TOPLEFT", left, "TOPLEFT", 9, y - 8)
    UI.summary:SetPoint("TOPRIGHT", left, "TOPRIGHT", -4, y - 8)
end

-- The tabs of the shown group share the page's width; before the window is laid out the width is
-- unknown, so the first refresh after that lays them out again. With the pages in the menu
-- (UI.layoutMenu) the tabs stay hidden: they are kept for their state (the open page disabled).
function UI.layoutTabs(group, id)
    UI.tabsShown = { group = group, id = id }
    for g, tabs in pairs(UI.groupTabs) do
        local width = UI.right and UI.right.GetWidth and UI.right:GetWidth()
        local each = U.finite(width) and width > 100 and math.floor((width - 12 - (#tabs - 1) * 4) / #tabs) or nil
        if each and g == group then
            UI.tabsSized = true
        end
        for i, b in ipairs(tabs) do
            if g == group and each then
                b:SetWidth(each)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", UI.right, "TOPLEFT", 6 + (i - 1) * (each + 4), -4)
            end
            b:Hide()
            b:SetEnabled(b.id ~= id)
        end
    end
end

function UI.show(id)
    local page, filter = id:match("^(%a+):?(%a*)$")
    if not page or not UI.pages[page] then
        page, filter, id = "deals", "all", "deals:all"
    end
    UI.section = page
    if page ~= "deals" then
        UI.buyHoverKey = nil
    end
    if page == "settings" then
        UI.setSettingsFrame(filter ~= "" and filter or "general")
    end
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
    UI.layoutTabs(group, id)
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
    collecting = "%d have no sales measured yet (two full scans at least 5 minutes apart)",
    not_selling = "%d are not bought at the price they would resell at",
    small = "%d would earn less than your minimum (%s and %d%% return, Settings)",
    budget = "%d cost more than your budget allows (%s; one item at most %s)",
    enough_stock = "%d: you already hold a day of their sales",
    blocked = "%d are on your ignore list",
}
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
                U.money(s.minProfit or 100),
                math.floor((s.minROI or 0.2) * 100 + 0.5)
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
        U.money(s.minProfit or 100)
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

-- Deals page -------------------------------------------------------------------------------------
local DEAL_ROWS = 13
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
            { "Qty", 50 },
            { "Buy at", 80 },
            { "Sells at", 80 },
            { "Profit", 80 },
            { "Est./day", 74 },
            { "Status", 100, "LEFT" },
        },
        DEAL_ROWS,
        function(row)
            UI.selectDeal(row.key)
        end,
        function(index)
            if UI.dealSort == index then
                UI.dealDescending = not UI.dealDescending
            else
                UI.dealSort, UI.dealDescending = index, index == 5 or index == 6
            end
            UI.dealPage = 1
            UI.refresh()
        end
    )
    -- Header tooltips: what Sells at and Est./day are made of.
    local function headerTip(header, title, body)
        header:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(L(title) .. "\n\n" .. L(body), 1, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        header:SetScript("OnLeave", function()
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)
    end
    headerTip(
        UI.dealTable.headers[4],
        "Sells at",
        "The price to sell one unit at: list it at this price on the auction house (a vendor deal: what a merchant pays for one). For a resale it is just below the next other seller, at most the usual price and at most what a quarter of the sales seen reached; only as many units as sell in a day at that price are bought. Profit counts the 5% cut and the deposits. * means no sales were seen yet: the price is only the asking price (vendor deal: not yet confirmed at a merchant)."
    )
    headerTip(
        UI.dealTable.headers[3],
        "Buy at",
        "The price of one unit: what the deal pays on average for each (several lots may have different prices). Qty times this is the whole cost."
    )
    headerTip(
        UI.dealTable.headers[6],
        "Est./day",
        "Units bought per day at 85% of the Sells at price or more, not a sale probability. Counted from lots seen bought between full scans: a lot that got smaller is a sure sale; a lot that vanished whole counts only when the next scan shows its seller did not post the item again. Expired/cancelled lots, reposts at any price, your own purchases and one-off sweeps (above three times the usual scan pair) are left out.\n\nTwo usable full scans are required. Zero means none was bought; '-' means unknown. Orange: only whole lots were seen, no lot bought in part. Vendor deals need no auction-house resale.\n\nGrey estimates use data older than 3 hours. Checking a current price does not refresh sale history. Short observations are smoothed: one unit bought in 15 minutes counts as about 5-6 a day, not 96."
    )
    -- The deals scroll like every table (the scrollbar on the right); the line below counts them.
    UI.pageText = text(p, "GameFontHighlightSmall")
    UI.pageText:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 8, -20)

    local bar = footer(p, 92, "GameFontHighlightSmall")
    UI.dealText = bar.text
    UI.dealText:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 8, 28)
    UI.dealText:SetJustifyV("TOP")
    UI.cancelButton = button(bar, "Cancel", 96, function()
        F.Trade.cancel()
    end)
    UI.cancelButton:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -6, 4)
    -- One button buys: gear and items in one click; a commodity in two, as the game wants (the
    -- first click asks the price of the whole quantity, the same button then shows "Confirm" and the
    -- total, and the second click buys). UI.confirmButton stays for older key bindings, hidden.
    local function buyClick()
        local op = F.Trade.op
        if op and UI.selected and op.key ~= UI.selected and (op.state == "quote" or op.state == "quoted") then
            F.Trade.cancel()
            return
        end
        if op and op.state == "quoted" then
            F.Trade.confirm()
            return
        end
        if UI.selected then
            local ok, why = F.Trade.buy(UI.selected)
            if not ok then
                if why == "verify_first" then
                    F.Deals.verify(UI.selected)
                end
                F.Engine.notify(why)
            end
        end
    end
    UI.confirmButton = button(bar, "Confirm purchase", 150, function()
        F.Trade.confirm()
    end)
    UI.confirmButton:Hide()
    UI.buyButton = button(bar, "Buy", 170, buyClick)
    UI.buyButton:SetMotionScriptsWhileDisabled(true)
    UI.buyButton:SetScript("OnEnter", function()
        UI.buyHoverKey = UI.selected
        if UI.selected then
            F.Trade.prepareBuy(UI.selected)
        end
        F.Engine.changed()
        UI.refresh()
    end)
    local function leaveBuy()
        UI.buyHoverKey = nil
        F.Engine.changed()
    end
    UI.buyButton:SetScript("OnLeave", leaveBuy)
    UI.buyButton:SetScript("OnHide", leaveBuy)
    UI.buyButton:SetPoint("RIGHT", UI.cancelButton, "LEFT", -4, 0)
    UI.checkButton = button(bar, "Check price", 116, function()
        if UI.selected then
            F.Engine.message = nil -- the status shows this check, not an older message
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
    F.Engine.input()
    local op = F.Trade.op
    if op and op.key ~= key and (op.state == "quote" or op.state == "quoted") then
        F.Trade.cancel() -- Confirm must never buy an item other than the selected one
    end
    UI.selected, UI.selectedAt, UI.buyHoverKey = key, F.Engine.clock(), nil
    if key then
        F.Trade.prepareBuy(key)
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
    if d.mode == "shop" and d.resell then
        return string.format(
            L("Bought out against an undercut, resold at %s with your auction. %d left to buy, one auction per click."),
            U.money(d.resell),
            d.wanted or d.qty
        )
    elseif d.mode == "shop" then
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

-- What the deal sells at, per unit: the vendor price, or the resale price the deal counts on (the
-- usual asking price, at most what a quarter of the sales seen reached). A resale price with no
-- sales seen yet is only the asking price: marked with "*".
-- Buy at and Sells at are prices of ONE unit, as the game's own lists and the tooltips show them
-- (in game, totals of several units next to a per-unit "sold at" price read as selling far above
-- the market). Profit stays the deal's whole profit.
local function unitCost(d)
    return math.floor((d.cost or 0) / math.max(1, d.qty or 1) + 0.5)
end

-- The price one unit is listed at (a vendor deal: what a merchant pays); "*" when the price is not
-- backed by sales seen (a resale) or by a merchant (a vendor deal).
local function unitExit(d)
    if U.finite(d.exit) and d.exit > 0 then
        return math.floor(d.exit)
    end
    return math.floor(((d.cost or 0) + (d.profit or 0)) / math.max(1, d.qty or 1) + 0.5)
end

local function sellsAtText(d, history)
    local unsure = d.mode == "vendor" and d.vendorHow and d.vendorHow ~= "seen"
        or d.mode == "flip" and F.Market.saleCap(history[d.key]) == nil
    -- The mark goes in front: the sums stay aligned on the right edge.
    return (unsure and "|cff999999*|r " or "") .. U.money(unitExit(d))
end

local MODE_LABELS = { vendor = "vendor", shop = "shopping list", disenchant = "disenchant", bid = "bid" }
-- Est./day: grey when the data is old, orange when no lot was seen bought in part at the price
-- (only whole lots that vanished, confirmed by the next scan: the weaker evidence).
local function estimateText(d, estimate, h)
    if d.mode ~= "flip" then
        return L(MODE_LABELS[d.mode] or d.mode)
    elseif not estimate.known then
        return "-"
    end
    local value = estimate.perDay == 0 and "0" or string.format("%.1f", estimate.perDay)
    if estimate.stale then
        return "|cff999999" .. value .. "|r"
    end
    local e = h and U.finite(d.exit) and F.Market.saleEvidence(h, 0.85 * d.exit)
    if e and e.sure == 0 then
        return "|cffffa040" .. value .. "|r"
    end
    return value
end

-- The sales an estimate rests on, in words: units, buys, how sure, prices (UI.saleEvidenceLine).
function UI.saleEvidenceLine(h, floor)
    local e = F.Market.saleEvidence(h, floor)
    if not e then
        return L("No purchase seen at this price yet.")
    end
    local line = string.format(
        L("Seen bought: %d in %d buys (%d from lots bought in part, %d whole lots), %s to %s, median %s."),
        math.floor(e.units + 0.5),
        e.buys,
        math.floor(e.sure + 0.5),
        math.floor(e.lots + 0.5),
        U.money(e.low),
        U.money(e.high),
        U.money(e.median)
    )
    if e.sweeps > 0 then
        line = line .. " " .. string.format(L("%d one-off sweeps counted at a ceiling."), e.sweeps)
    end
    return line
end

local function estimateSentence(estimate, h, exit)
    if not estimate.known then
        return L("Sale estimate unavailable: collect two full scans with usable price data.")
    end
    local value = estimate.perDay == 0 and "0" or string.format("~%.1f", estimate.perDay)
    local floor = U.finite(exit) and math.floor(0.85 * exit) or nil
    local sentence = floor and string.format(L("Bought per day at %s or more: %s."), U.money(floor), value)
        or string.format(L("Estimated disappeared/day: %s."), value)
    if estimate.age then
        sentence = sentence
            .. " "
            .. string.format(L("Data %d min old"), math.floor(estimate.age / 60))
            .. (estimate.stale and L(" (old data).") or ".")
    end
    if h then
        sentence = sentence .. "\n" .. UI.saleEvidenceLine(h, floor)
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
            return d.qty
        elseif field == 3 then
            return unitCost(d)
        elseif field == 4 then
            return unitExit(d)
        elseif field == 5 then
            return d.profit
        elseif field == 6 then
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
        if UI.dealSort == 6 and (av == nil) ~= (bv == nil) then
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
    if UI.dealPage == 1 then
        UI.dealTable.offset, UI.dealPage = 0, nil -- a new filter or sort starts at the top
    end
    local shown = UI.dealTable.window(list)
    for i, r in ipairs(UI.dealTable.rows) do
        local d = shown[i]
        if d then
            r.key, r.link = d.key, d.link
            r.icon:SetTexture(icon(d.id))
            r.name:SetText(nameOf(d.key, d.link))
            r.cols[1]:SetText(d.qty)
            r.cols[2]:SetText(U.money(unitCost(d)))
            r.cols[3]:SetText(sellsAtText(d, history))
            r.cols[4]:SetText(U.money(d.profit))
            r.cols[5]:SetText(estimateText(d, estimates[d.key], history[d.key]))
            r.cols[6]:SetText(dealStatus(d))
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
    local cost, profit = 0, 0
    for _, d in ipairs(list) do
        cost, profit = cost + d.cost, profit + d.profit
    end
    UI.pageText:SetText(
        string.format(L("Deals: %d"), #list)
            .. (
                #list > 0
                    and (L("  ·  ") .. string.format(L("all: cost %s, profit %s"), U.money(cost), U.money(profit)))
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
            empty:SetText(UI.noResaleText(F.Scan.last.stats))
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
            lines[#lines + 1] =
                estimateSentence(estimates[d.key] or saleEstimate(d, history, now), history[d.key], d.exit)
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
    UI.ignoreButton:SetEnabled(d ~= nil)
    UI.confirmButton:SetEnabled(op ~= nil and op.state == "quoted")
    UI.cancelButton:SetEnabled(op ~= nil and (op.state == "quote" or op.state == "quoted"))
    if op and op.state == "quoted" then
        UI.buyButton:SetText(L("Confirm") .. " " .. U.money(op.cost))
        UI.buyButton:SetEnabled(true)
    elseif op and op.state == "quote" then
        UI.buyButton:SetText(L("Asking the price..."))
        UI.buyButton:SetEnabled(false)
    else
        local ready = d and F.Trade.readyToBuy(d)
        UI.buyButton:SetText(
            d and F.Deals.pending(d.key) and L("checking...")
                or d and F.Trade.canBuy(d) and not ready and L("queued")
                or d and d.kind == "commodity" and L("Buy (2 clicks)")
                or L("Buy")
        )
        UI.buyButton:SetEnabled(ready and true or false)
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
    local list = UI.bidTable.sort(F.Bids.current(), function(c, column)
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
        -- Why the page is empty: no scan yet, or the bid auctions of the last one have ended.
        local last = F.Scan.last
        local age = last and last.at and math.floor((F.Engine.clock() - last.at) / 60)
        if not age then
            empty:SetText(
                L(
                    "Auctions with a bid that end within 2 hours and whose next bid is well below the item's worth appear here after a full scan."
                )
            )
        else
            empty:SetText(
                string.format(
                    L(
                        "No bid is worth it now. The last full scan was %d min ago: its auctions ending soon are over or were not worth a bid. A new full scan finds new ones."
                    ),
                    age
                )
            )
        end
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
local SELL_ROWS = 12
function UI.createSell(p)
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 112)
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
    local noteHeader = UI.sellTable.headers[6]
    noteHeader:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L("Note"), 1, 0.82, 0, 1, true)
            GameTooltip:AddLine(
                L("resale: bought for resale. vendor deal: bought to sell to a vendor. other: bought elsewhere."),
                1,
                1,
                1,
                true
            )
            GameTooltip:Show()
        end
    end)
    noteHeader:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

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
    -- Rule of the selected item (minimum and maximum price, units kept in the bags), in a panel over
    -- the bottom of the list, opened with "Rule..." beside Hide. Most items need none.
    local panel = CreateFrame("Frame", nil, p)
    panel:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 4, 32)
    panel:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -4, 32)
    panel:SetHeight(64)
    if panel.SetFrameLevel and list.GetFrameLevel then
        panel:SetFrameLevel((list:GetFrameLevel() or 1) + 20)
    end
    local back = panel:CreateTexture(nil, "BACKGROUND")
    back:SetColorTexture(0.05, 0.05, 0.05, 0.95)
    back:SetAllPoints()
    local edge = panel:CreateTexture(nil, "BORDER")
    edge:SetColorTexture(1, 0.82, 0, 0.4)
    edge:SetHeight(1)
    edge:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    edge:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    panel:Hide()
    UI.rulePanel = panel
    local help = text(panel, "GameFontHighlightSmall")
    help:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 8)
    help:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 8)
    help:SetText(
        L("min: never post below this price. max: sellers asking more are ignored. keep: units that stay in the bags.")
    )
    local ruleLabel = text(panel, "GameFontNormal")
    ruleLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -10)
    ruleLabel:SetText(L("Rule: min"))
    UI.ruleMin = editbox(panel, 70)
    UI.ruleMin:SetPoint("LEFT", ruleLabel, "RIGHT", 8, 0)
    local maxLabel = text(panel, "GameFontNormal")
    maxLabel:SetPoint("LEFT", UI.ruleMin, "RIGHT", 10, 0)
    maxLabel:SetText(L("max"))
    UI.ruleMax = editbox(panel, 70)
    UI.ruleMax:SetPoint("LEFT", maxLabel, "RIGHT", 8, 0)
    local keepLabel = text(panel, "GameFontNormal")
    keepLabel:SetPoint("LEFT", UI.ruleMax, "RIGHT", 10, 0)
    keepLabel:SetText(L("keep"))
    UI.ruleKeep = editbox(panel, 40)
    UI.ruleKeep:SetPoint("LEFT", keepLabel, "RIGHT", 8, 0)
    UI.ruleSave = button(panel, "Save rule", 95, function()
        local item = UI.sellSelected
        if item then
            F.Trade.setRule(item.key, {
                min = U.parseMoney(UI.ruleMin:GetText()),
                max = U.parseMoney(UI.ruleMax:GetText()),
                keep = tonumber(UI.ruleKeep:GetText()),
            })
            F.Engine.notify("saved")
            panel:Hide()
        end
    end)
    UI.ruleSave:SetPoint("LEFT", UI.ruleKeep, "RIGHT", 10, 0)
    UI.ruleToggle = button(p, "Rule...", 90, function()
        if panel:IsShown() then
            panel:Hide()
        elseif UI.sellSelected then
            panel:Show()
        end
    end)
    UI.ruleToggle:SetPoint("RIGHT", UI.sellHide, "LEFT", -4, 0)

    local bar = footer(p, 108, "GameFontHighlightSmall")
    UI.sellText = bar.text
    local priceLabel = text(bar, "GameFontNormal")
    priceLabel:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 8, 36)
    priceLabel:SetText(L("Price each"))
    UI.sellPrice = editbox(bar, 100)
    UI.sellPrice:SetScript("OnTextChanged", function(self, userInput)
        if self:GetText() == "" then
            UI.sellPriceAuto = nil
        elseif userInput then
            UI.sellPriceAuto = nil -- typed by the player: kept as it is
        end
        F.Engine.changed()
    end)
    UI.sellPrice:SetPoint("LEFT", priceLabel, "RIGHT", 10, 0)
    local qtyLabel = text(bar, "GameFontNormal")
    qtyLabel:SetPoint("LEFT", UI.sellPrice, "RIGHT", 40, 0) -- room for the Check price button
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
    -- Auto explains itself: the deposits each duration is expected to lose for the selected item.
    UI.durations[4]:SetScript("OnEnter", function(self)
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L("Automatic duration"), 1, 0.82, 0)
        GameTooltip:AddLine(
            L(
                "The deposit comes back when the lot sells and is lost only when it expires. Auto picks the duration that loses the least deposit per sale; when two are close (or cost the same), the longer one."
            ),
            1,
            1,
            1,
            true
        )
        local item = UI.sellSelected
        local qty = item and tonumber(UI.sellQty:GetText())
        local price = item and U.parseMoney(UI.sellPrice:GetText())
        local costs, choice, hours = nil, nil, nil
        if item then
            costs, choice, hours = F.Trade.durationCosts(item.key, qty or 1, price)
        end
        if costs then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format(L("Expected to sell in about %.1f h."), hours), 0.8, 0.8, 0.8)
            for d = 1, 3 do
                local lost = costs[d] == math.huge and "-" or U.money(math.floor(costs[d] + 0.5))
                GameTooltip:AddDoubleLine(
                    string.format(
                        L("%d h: deposit %s, lost per sale"),
                        F.Trade.DURATION_HOURS[d],
                        U.money(F.Trade.depositFor(item.key, qty or 1, d) or 0)
                    ),
                    lost,
                    d == choice and 0.25 or 1,
                    d == choice and 1 or 1,
                    d == choice and 0.25 or 1,
                    1,
                    1,
                    1
                )
            end
        elseif item then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L("Sales of this item are not measured yet: 24 hours."), 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    UI.durations[4]:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    UI.postButton = button(bar, "Post", 100, function()
        local item = UI.sellSelected
        if not item then
            return
        end
        local price = U.parseMoney(UI.sellPrice:GetText())
        local qty = tonumber(UI.sellQty:GetText())
        local ok, why = F.Trade.post(item, qty, price, F.Trade.durationFor(item.key, qty, price))
        F.Engine.notify(why)
        if ok and why == "post_sent" then
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
    for b, tip in pairs({
        [UI.postAll] = "Posts all available units of the next item for sale per click.",
        [UI.postAuction] = "Posts all available units of one item per click, only when the auction house pays more than a vendor, after the cut and the deposits (Best column). Items a vendor pays as much for stay in the bags for the merchant.",
    }) do
        b:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(L(tip), 1, 1, 1, 1, true)
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
    -- Check price: reads the selected item's listings again (selecting it already does once).
    UI.sellCheck = CreateFrame("Button", nil, bar)
    UI.sellCheck:SetSize(22, 22)
    UI.sellCheck:SetPoint("LEFT", UI.sellPrice, "RIGHT", 6, 0)
    if UI.sellCheck.SetNormalTexture then
        UI.sellCheck:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
        UI.sellCheck:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    end
    UI.sellCheck:SetScript("OnClick", function()
        if UI.sellSelected then
            F.Engine.message = nil
            F.Trade.checkPrice(UI.sellSelected.key)
            F.Engine.changed()
            UI.refresh()
        end
    end)
    UI.sellCheck:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L("Check price"), 1, 1, 1)
            GameTooltip:AddLine(L("Reads the item's current listings again."), 1, 0.82, 0, true)
            GameTooltip:Show()
        end
    end)
    UI.sellCheck:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
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
    ---@type boolean|fun(key: string, complete: function): boolean
    local verifyDeals = false
    local keys, scope = {}, UI.section
    if UI.section == "deals" then
        scope, verifyDeals = "deals:" .. UI.filter, true
        for _, d in ipairs(F.Deals.visible(UI.filter)) do
            keys[#keys + 1] = d.key
        end
    elseif UI.section == "sell" then
        for _, item in ipairs(sellItems()) do
            keys[#keys + 1] = item.key
        end
    elseif UI.section == "auctions" or UI.section == "undercuts" then
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
            local name, value, quote = F.Trade.bestWay(item.key, item.id)
            w = { name = name, value = value, quote = quote }
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
    if UI.sellSelected then
        local found
        for _, it in ipairs(sellItems(hiddenView)) do
            if it.key == UI.sellSelected.key then
                found = it
                break
            end
        end
        if not found then
            UI.sellPrice:SetText("")
        end
        UI.sellSelected = found
    end
    local hiddenCount = #F.Trade.hiddenItems()
    UI.sellSaleTab:SetText(L("For sale") .. " (" .. #sellItems(false) .. ")")
    UI.sellHiddenTab:SetText(L("Hidden") .. " (" .. hiddenCount .. ")")
    UI.sellSaleTab:SetEnabled(hiddenView)
    UI.sellHiddenTab:SetEnabled(not hiddenView)
    UI.sellHide:SetText(L(hiddenView and "Return to sale" or "Hide"))
    UI.sellHide:SetEnabled(UI.sellSelected ~= nil)
    UI.ruleToggle:SetEnabled(UI.sellSelected ~= nil and not hiddenView)
    local rule = UI.sellSelected and F.Trade.rule(UI.sellSelected.key)
    UI.ruleToggle:SetText(L("Rule...") .. (rule and " |cff40ff40*|r" or ""))
    if not UI.sellSelected or hiddenView then
        UI.rulePanel:Hide()
    end
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
                -- One word in the narrow column; the header's tooltip says what each means.
                local note = p
                    and (p.mode == "vendor" and L("vendor deal") or p.mode == "other" and L("other") or L("resale"))
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
    -- One sum for the page, the tooltip and the Best column (F.Trade.quote); read first, it also
    -- takes the prices of a full scan up to 5 minutes old.
    local quote = F.Trade.quote(item.key, item.id)
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
        local suggested = U.plainMoney(math.max(price, floor or 0))
        local typing = UI.sellPrice.HasFocus and UI.sellPrice:HasFocus()
        local shown = UI.sellPrice:GetText()
        if not typing and (shown == "" or shown == UI.sellPriceAuto) and shown ~= suggested then
            UI.sellPrice:SetText(suggested)
            UI.sellPriceAuto = suggested
        end
        if F.Deals.pending(item.key) then
            -- A check is on the way: the price shown is the last one known.
            lines[#lines + 1] = "|cffffd100" .. L("Reading current listings...") .. "|r"
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
                        U.money(math.max(price, floor or 0))
                    )
                or L("Nobody else sells it now. Suggested: the usual asking price.")
        end
        if quote and quote.net then
            local line = UI.netLabel(quote) .. ": " .. U.money(quote.net)
            if quote.profit then
                line = line .. "; " .. L("profit each") .. " " .. UI.signed(quote.profit)
            end
            lines[#lines + 1] = line .. "."
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
    -- What buyers really paid (sales seen between full scans), and how much sells a day at the price.
    local sale = h and F.Market.salePrice(h)
    local demand = price and h and F.Market.saleability(h, price, F.Engine.clock())
    local market = {}
    if sale then
        market[#market + 1] = string.format(L("buyers paid about %s lately"), U.money(sale))
    end
    if demand and demand.known then
        market[#market + 1] = string.format(
            L("at %s about %s a day sell"),
            U.money(price),
            demand.perDay == 0 and "0" or string.format("%.1f", demand.perDay)
        )
    end
    if #market > 0 then
        lines[#lines + 1] = L("Market") .. ": " .. table.concat(market, "; ") .. "."
    end
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
    -- Centered on top, as in Auctionator's Cancelling tab: what is on sale and what is on its way.
    UI.auctionTotal = text(bar, "GameFontHighlight") -- white, as in Auctionator
    UI.auctionTotal:SetPoint("TOP", bar, "TOP", 0, -6)
    UI.auctionText = bar.text
    UI.auctionText:ClearAllPoints()
    UI.auctionText:SetPoint("TOPLEFT", bar, "TOPLEFT", 8, -20)
    UI.auctionText:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -8, -20)
    UI.auctionText:SetWordWrap(false)
    UI.cancelAuction = button(bar, "Cancel auction", 140, function()
        for _, a in ipairs(F.Trade.owned) do
            if a.auctionID == UI.ownedSelected then
                F.Trade.cancelAuction(a)
            end
        end
    end)
    UI.cancelAuction:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -6, 4)
    UI.refreshOwned = button(bar, "Refresh", 100, function()
        F.Trade.ownedDue = 0
    end)
    UI.refreshOwned:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 6, 4)
    UI.checkOwned = button(bar, "Check prices", 130, function()
        F.Trade.checkOwned()
        UI.refreshAuctions()
    end)
    UI.checkOwned:SetPoint("LEFT", UI.refreshOwned, "RIGHT", 4, 0)
    -- The undercut advice and the cancel cost sit between the buttons, never over them.
    UI.auctionText:ClearAllPoints()
    UI.auctionText:SetPoint("LEFT", UI.checkOwned, "RIGHT", 8, 0)
    UI.auctionText:SetPoint("RIGHT", UI.cancelAuction, "LEFT", -8, 0)
end

-- Selling, Undercuts (anti-undercut): every undercut auction, the advice, and every option priced
-- (T.fightPlan); the player picks one with its button.
local OPTION = {
    wait = { "|cffffd100", "wait" },
    undercut = { "|cff40ff40", "undercut" },
    buyout = { "|cff66ccff", "buy out" },
    raise = { "|cffcc99ff", "raise" },
    vendor = { "|cffff9933", "to a vendor" },
}

function UI.createUndercuts(p)
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 150)
    UI.undercutTable = table_(
        list,
        {
            { "Name" },
            { "Qty", 40 },
            { "My price", 80 },
            { "Cheaper", 80 },
            { "Ahead", 50 },
            { "Advice", 96, "LEFT" },
        },
        10,
        function(row)
            UI.fightSelected = row.plan and row.plan.auction.auctionID
            F.Engine.changed()
            UI.refresh()
        end
    )
    local bar = footer(p, 146, "GameFontHighlightSmall")
    UI.fightText = bar.text
    UI.fightButtons = {}
    local last
    for _, id in ipairs({ "wait", "undercut", "buyout", "raise", "vendor" }) do
        local b = button(bar, OPTION[id][2], 96, function()
            for _, plan in ipairs(F.Trade.fightPlans()) do
                if plan.auction.auctionID == UI.fightSelected then
                    F.Trade.fight(plan, id)
                    if id == "buyout" or id == "raise" then
                        UI.show("deals:shop")
                    end
                end
            end
            UI.refresh()
        end)
        if last then
            b:SetPoint("LEFT", last, "RIGHT", 4, 0)
        else
            b:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 6, 4)
        end
        UI.fightButtons[id] = b
        last = b
    end
    UI.fightNext = button(bar, "Answer next", 130, function()
        local _, why = F.Trade.fightNext()
        F.Engine.notify(why)
    end)
    UI.fightNext:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -6, 4)
end

function UI.duration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    if seconds >= 86400 then
        return string.format(L("%.1f days"), seconds / 86400)
    end
    if seconds >= 3600 then
        return string.format("%d h", math.floor(seconds / 3600))
    end
    return string.format("%d min", math.max(1, math.floor(seconds / 60)))
end

local function percent(p)
    return string.format("%d%%", math.floor((p or 0) * 100 + 0.5))
end

-- One line per option: what it does, its chance and its expected money; the advice is marked.
local function optionLine(plan, o)
    local a = plan.auction
    local v = OPTION[o.id]
    local head = (plan.best == o and "> " or "   ") .. v[1] .. L(v[2]) .. "|r: "
    if o.blocked == "floor" then
        return head
            .. string.format(L("not offered: %s is below your floor of %s."), U.money(plan.new), U.money(plan.floor))
    elseif o.blocked == "many" then
        return head .. string.format(L("not offered: %d cheaper units are too many to buy."), o.units)
    elseif o.blocked == "money" then
        return head
            .. string.format(L("not offered: the cheaper units cost %s, more than one deal may use."), U.money(o.cost))
    end
    local function sells(units)
        return string.format(L("sells %.1f of %d"), units or 0, o.id == "raise" and a.qty + o.units or a.qty)
    end
    local value = o.ev and U.money(math.floor(math.max(0, o.ev))) or "?"
    if o.id == "wait" then
        if o.unknown then
            return head .. L("keep it. How soon it sells is unknown: no sales were measured yet.")
        end
        return head
            .. string.format(
                L("keep it behind %d cheaper units: %s chance all of yours sell in the %s left (%s); expected %s."),
                plan.ahead + (plan.ownAhead or 0),
                percent(o.p),
                UI.duration(a.timeLeft or 0),
                sells(o.units),
                value
            )
    elseif o.id == "undercut" then
        if o.guess then
            return head
                .. string.format(
                    L("cancel (about %s lost) and post at %s; brings %s if it sells (chance unknown)."),
                    U.money(plan.cancel),
                    U.money(plan.new),
                    value
                )
        end
        return head
            .. string.format(
                L(
                    "cancel (about %s lost) and post at %s for %d h: %s chance to sell, %s chance a rival answers first (%s); expected %s."
                ),
                U.money(plan.cancel),
                U.money(plan.new),
                o.hours,
                percent(o.p),
                percent(o.answered),
                sells(o.units),
                value
            )
    elseif o.id == "buyout" then
        if o.unknown then
            return head
                .. string.format(
                    L("buy the %d cheaper units for %s and sell them at your price; chance unknown."),
                    o.units,
                    U.money(o.cost)
                )
        end
        return head
            .. string.format(
                L("buy the %d cheaper units for %s, sell them and yours at your price; expected %s after the purchase."),
                o.units,
                U.money(o.cost),
                value
            )
    elseif o.id == "raise" then
        return head
            .. string.format(
                L(
                    "buy the %d units below %s for %s, cancel yours and post all at %s: %s chance all sell in a day (%s); expected %s."
                ),
                o.units,
                U.money(o.target),
                U.money(o.cost),
                U.money(o.target),
                percent(o.p),
                sells(o.expect),
                value
            )
    end
    return head .. string.format(L("cancel and sell to a merchant: %s."), value)
end

function UI.refreshUndercuts()
    local plans = F.Trade.fightPlans()
    local act, selected = 0, nil
    for i, r in ipairs(UI.undercutTable.rows) do
        local plan = plans[i]
        if plan then
            local a = plan.auction
            if plan.verdict == "undercut" or plan.verdict == "vendor" then
                act = act + 1
            end
            r.plan, r.key, r.link = plan, a.key, a.link
            r.icon:SetTexture(icon(a.id))
            r.name:SetText(nameOf(a.key or ("i:" .. a.id), a.link))
            r.cols[1]:SetText(a.qty)
            r.cols[2]:SetText(U.money(a.price or 0))
            r.cols[3]:SetText(U.money(plan.cheapest))
            r.cols[4]:SetText(plan.ahead)
            local v = OPTION[plan.verdict]
            r.cols[5]:SetText(v[1] .. L(v[2]) .. "|r" .. (plan.war and " |cffff6060!|r" or ""))
            if a.auctionID == UI.fightSelected then
                r.selected:Show()
                selected = plan
            else
                r.selected:Hide()
            end
            r:Show()
        else
            r.plan, r.key = nil, nil
            r:Hide()
        end
    end
    local empty = UI.undercutTable.empty
    if #plans == 0 then
        empty:SetText(
            L(
                "None of your checked auctions is undercut. Check prices on My auctions, or wait for the next full scan: it checks them by itself."
            )
        )
        empty:Show()
    else
        empty:Hide()
    end
    local lines = {}
    if selected then
        if selected.rate then
            lines[#lines + 1] = string.format(
                L(
                    "Sales at your price: about %.1f a day (%.0f units seen sold in %d h of scans)%s. Values are expected money; an unsold unit is worth %s posting again."
                ),
                selected.rate,
                selected.sold or 0,
                math.floor(selected.hours or 0),
                selected.thin and L("; few sales seen, so the chances are kept wide") or "",
                U.money(math.floor(selected.fallback / math.max(1, selected.auction.qty or 1)))
            )
        end
        if (selected.answers or 0) >= 0.5 then
            lines[#lines + 1] = string.format(
                L("Rivals answer about %.1f times a day here: a step down lasts until the next answer."),
                selected.answers
            )
        end
        if selected.war then
            lines[#lines + 1] = "|cffff6060"
                .. string.format(
                    L("Price war: you answered %d times in a day and were undercut again; each round costs a deposit."),
                    selected.rounds
                )
                .. "|r"
        end
        for _, o in ipairs(selected.options) do
            lines[#lines + 1] = optionLine(selected, o)
        end
    elseif #plans > 0 then
        lines[#lines + 1] = string.format(
            L(
                "Undercut: %d; acting pays on %d. Click a row: every way out is priced (wait, undercut, buy out the cheaper lots, raise, a merchant) and you choose."
            ),
            #plans,
            act
        )
    else
        lines[#lines + 1] = L(
            "Anti-undercut: when another seller lists your item cheaper, every way out is priced from the measured sales (wait, undercut, buy out the cheaper lots, raise, a merchant), the best is advised, and you choose."
        )
    end
    UI.fightText:SetText(table.concat(lines, "\n"))
    for id, b in pairs(UI.fightButtons) do
        local o = selected and selected[id]
        b:SetEnabled(o ~= nil and not o.blocked and F.AH.isOpen())
    end
    UI.fightNext:SetText(L("Answer next") .. " (" .. act .. ")")
    UI.fightNext:SetEnabled(act > 0 and F.AH.isOpen())
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
    local selected, undercut = nil, 0
    for i, r in ipairs(UI.auctionTable.rows) do
        local a = owned[i]
        if a then
            r.auction, r.key, r.link = a, a.key, a.link
            r.icon:SetTexture(icon(a.id))
            r.name:SetText(nameOf(a.key or ("i:" .. a.id), a.link))
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
    -- Total on sale (price of one unit x quantity of every auction still listed) and pending
    -- (sold, the gold on its way by mail), centered as in Auctionator's Cancelling tab.
    local onSale, pending = 0, 0
    for _, a in ipairs(F.Trade.owned or {}) do
        local value = a.total or (a.price or 0) * (a.qty or 1)
        if a.sold then
            pending = pending + value
        else
            onSale = onSale + value
        end
    end
    UI.auctionTotal:SetText(
        #(F.Trade.owned or {}) > 0
                and string.format(L("Total on sale: %s (%s pending)"), U.money(onSale), U.money(pending))
            or ""
    )
    local lines = {}
    if queue == 0 and undercut > 0 then
        lines[#lines + 1] = string.format(L("Undercut: %d"), undercut)
    end
    if selected and not selected.sold then
        local cost = F.AH.cancelCost(selected.auctionID)
        lines[#lines + 1] = string.format(L("Cancel cost besides the deposit: %s."), U.money(cost or 0))
    end
    UI.auctionText:SetText(table.concat(lines, "  ·  "))
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
    local m, working = F.Analytics.market()
    m = m or {}
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
            working and L("Working out the market lists...")
                or L(
                    "No data yet. Market lists fill in after a few full scans; price moves need scans on two different days."
                )
        )
        empty:Show()
    else
        empty:Hide()
    end
    UI.marketText:SetText(
        string.format(L("%d items with history · click a row to check it on the auction house now"), m.items or 0)
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
-- Top: the week's summary with Export CSV beside it; under it an unconfirmed purchase (up to two
-- lines) with its two buttons on a row of their own; then the journal, moved up when there is none.
local JOURNAL_TOP, JOURNAL_BELOW_ASK = -56, -126
function UI.createJournal(p)
    UI.journalPage = p
    UI.exportButton = button(p, "Export CSV", 120, function()
        UI.showExport()
    end)
    UI.exportButton:SetPoint("TOPRIGHT", p, "TOPRIGHT", -10, -8)
    UI.journalSummary = text(p, "GameFontHighlight")
    UI.journalSummary:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -10)
    UI.journalSummary:SetPoint("TOPRIGHT", p, "TOPRIGHT", -140, -10)
    UI.journalSummary:SetSpacing(4)
    UI.unknownText = text(p, "GameFontNormal")
    UI.unknownText:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -58)
    UI.unknownText:SetPoint("TOPRIGHT", p, "TOPRIGHT", -10, -58)
    UI.unknownText:SetSpacing(2)
    UI.unknownYes = button(p, "It was bought", 130, function()
        F.Trade.settle(1, true)
    end)
    UI.unknownYes:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -94)
    UI.unknownNo = button(p, "Not bought", 130, function()
        F.Trade.settle(1, false)
    end)
    UI.unknownNo:SetPoint("LEFT", UI.unknownYes, "RIGHT", 6, 0)
    UI.journalLines = text(p, "GameFontHighlightSmall")
    UI.journalLines:SetSpacing(4)
    UI.placeJournalLines(false)
end

function UI.placeJournalLines(ask)
    local y = ask and JOURNAL_BELOW_ASK or JOURNAL_TOP
    UI.journalLines:ClearAllPoints()
    UI.journalLines:SetPoint("TOPLEFT", UI.journalPage, "TOPLEFT", 10, y)
    UI.journalLines:SetPoint("TOPRIGHT", UI.journalPage, "TOPRIGHT", -10, y)
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
    UI.placeJournalLines(u ~= nil)
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

-- /ff dump: how the auction house window is built, frame by frame: name, type, size, anchors,
-- strata and level, and every texture (atlas or file, coordinates, colour, layer, size, anchors)
-- and text (font, size, colour, justification, anchors). Shown in a box to copy, to rebuild
-- ForeverFlip's window with the same sizes, distances, fonts and colours.
local function num(v)
    v = tonumber(v)
    if not v then
        return "?"
    end
    if v == math.floor(v) then
        return tostring(v)
    end
    return string.format("%.2f", v)
end

local function pointsOf(region)
    local out = {}
    if not region.GetNumPoints then
        return ""
    end
    for i = 1, region:GetNumPoints() do
        local ok, point, rel, relPoint, x, y = pcall(region.GetPoint, region, i)
        if ok and point then
            local relName = rel and (rel.GetDebugName and rel:GetDebugName() or rel.GetName and rel:GetName())
                or "parent"
            out[#out + 1] =
                string.format("%s>%s.%s(%s,%s)", point, tostring(relName), tostring(relPoint), num(x), num(y))
        end
    end
    return table.concat(out, " ")
end

local function regionLine(region, indent)
    local kind = region.GetObjectType and region:GetObjectType()
    local name = region.GetDebugName and region:GetDebugName() or "?"
    name = name:gsub("^AuctionHouseFrame%.?", "AH.")
    local w, h = 0, 0
    if region.GetSize then
        w, h = region:GetSize()
    end
    local parts = { indent .. kind .. " " .. name, "size " .. num(w) .. "x" .. num(h) }
    if region.IsShown and not region:IsShown() then
        parts[#parts + 1] = "hidden"
    end
    if kind == "Texture" then
        local atlas = region.GetAtlas and region:GetAtlas()
        parts[#parts + 1] = atlas and ("atlas " .. atlas) or ("file " .. tostring(region:GetTexture()))
        local c = { region:GetTexCoord() }
        for i, v in ipairs(c) do
            c[i] = num(v)
        end
        parts[#parts + 1] = "coords " .. table.concat(c, ",")
        local layer, sub = region:GetDrawLayer()
        parts[#parts + 1] = "layer " .. tostring(layer) .. ":" .. tostring(sub)
        local r, g, b, a = region:GetVertexColor()
        parts[#parts + 1] = "color " .. num(r) .. "," .. num(g) .. "," .. num(b) .. "," .. num(a)
        parts[#parts + 1] = "blend " .. tostring(region:GetBlendMode())
    elseif kind == "FontString" then
        local path, size, flags = region:GetFont()
        local r, g, b, a = region:GetTextColor()
        local object = region.GetFontObject and region:GetFontObject()
        parts[#parts + 1] = string.format("text '%s'", tostring(region:GetText()))
        parts[#parts + 1] = "font "
            .. tostring(object and object.GetName and object:GetName() or "")
            .. " "
            .. tostring(path)
            .. " "
            .. num(size)
            .. " "
            .. tostring(flags)
        parts[#parts + 1] = "color " .. num(r) .. "," .. num(g) .. "," .. num(b) .. "," .. num(a)
        parts[#parts + 1] = "justify " .. tostring(region:GetJustifyH()) .. "/" .. tostring(region:GetJustifyV())
        local layer = region:GetDrawLayer()
        parts[#parts + 1] = "layer " .. tostring(layer)
    end
    parts[#parts + 1] = "at " .. pointsOf(region)
    return table.concat(parts, " | ")
end

local function dumpFrame(frame, depth, out, limit)
    if #out >= limit or depth > 7 then
        return
    end
    local indent = string.rep("  ", depth)
    local w, h = frame:GetSize()
    local name = (frame.GetDebugName and frame:GetDebugName() or "?"):gsub("^AuctionHouseFrame%.?", "AH.")
    out[#out + 1] = string.format(
        "%s%s %s | size %sx%s | %s | strata %s level %s | at %s",
        indent,
        tostring(frame:GetObjectType()),
        name,
        num(w),
        num(h),
        frame:IsShown() and "shown" or "hidden",
        tostring(frame:GetFrameStrata()),
        num(frame:GetFrameLevel()),
        pointsOf(frame)
    )
    if not frame:IsShown() and depth > 1 then
        return -- hidden branches (other tabs) only by their own line
    end
    for _, region in ipairs({ frame:GetRegions() }) do
        if #out >= limit then
            return
        end
        local ok, line = pcall(regionLine, region, indent .. "  ")
        out[#out + 1] = ok and line or (indent .. "  ? " .. tostring(line))
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        dumpFrame(child, depth + 1, out, limit)
    end
end

function UI.dumpAuctionHouse()
    local out = {}
    local root = AuctionHouseFrame
    if type(root) ~= "table" or not root.GetChildren then
        return "The auction house window is not open."
    end
    out[#out + 1] = string.format(
        "ForeverFlip %s dump of the auction house window (UI scale %s)",
        F.version,
        num(UIParent and UIParent:GetEffectiveScale() or 1)
    )
    local ok, err = pcall(dumpFrame, root, 0, out, 4000)
    if not ok then
        out[#out + 1] = "error: " .. tostring(err)
    end
    if #out >= 4000 then
        out[#out + 1] = "(cut at 4000 lines)"
    end
    return table.concat(out, "\n")
end

function UI.showDump()
    UI.showText(L("Auction house window: press Ctrl+C to copy, then paste it into the message."), UI.dumpAuctionHouse())
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
-- Settings pages share one look: a gold heading with a thin line under it per section, white
-- labels, fields and buttons aligned on the right edge, and the full explanation in tooltips.
local function hint(frame, title, body)
    frame:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L(title), 1, 0.82, 0, 1, true)
            GameTooltip:AddLine(L(body), 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
end

-- A section heading at (x, y); `width` nil spans to the right edge of the page.
local function heading(p, label, x, y, width)
    local t = text(p, "GameFontNormal")
    t:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
    t:SetText(L(label))
    local line = p:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.25)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", p, "TOPLEFT", x, y - 16)
    if width then
        line:SetWidth(width)
    else
        line:SetPoint("TOPRIGHT", p, "TOPRIGHT", -12, y - 16)
    end
    return t
end

-- A row's faint stripe, as the auction house's lists have.
local function stripe(p, y, height)
    local t = p:CreateTexture(nil, "BACKGROUND")
    t:SetAtlas("auctionhouse-rowstripe-1")
    t:SetPoint("TOPLEFT", p, "TOPLEFT", 6, y)
    t:SetPoint("TOPRIGHT", p, "TOPRIGHT", -6, y)
    t:SetHeight(height)
    return t
end

-- A check box with a one-line label; the setting's long text is its tooltip.
local function checkRow(p, x, y, label, body, checked, onClick)
    local box = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    box:SetSize(26, 26)
    box:SetPoint("TOPLEFT", p, "TOPLEFT", x - 4, y)
    box:SetChecked(checked)
    box:SetScript("OnClick", onClick)
    local t = text(p, "GameFontHighlight")
    t:SetPoint("LEFT", box, "RIGHT", 2, 1)
    t:SetWordWrap(false)
    t:SetText(L(label))
    box.label = t
    if body then
        hint(box, label, body)
    end
    return box
end

function UI.createSettings(p)
    UI.settingTabs, UI.settingFrames = {}, {}
    local tabs = {
        { "general", "General" },
        { "keys", "Key bindings" },
        { "share", "Sharing" },
        { "safety", "Safety" },
    }
    for _, t in ipairs(tabs) do
        local frame = CreateFrame("Frame", nil, p)
        frame:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
        frame:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
        UI.settingFrames[t[1]] = frame
        local b = button(p, t[2], 140, function()
            UI.showSettingsTab(t[1])
        end)
        b:Hide()
        UI.settingTabs[t[1]] = b
    end
    UI.createGeneralSettings(UI.settingFrames.general)
    UI.createKeySettings(UI.settingFrames.keys)
    UI.createShareSettings(UI.settingFrames.share)
    UI.createSafetySettings(UI.settingFrames.safety)
    UI.setSettingsFrame("general")
end

-- Safety: the vendor price margin, the spending limit, lots left for others, and what was learned.
function UI.createSafetySettings(p)
    local fields = {
        {
            "vendorMargin",
            "Unconfirmed vendor prices count less, %",
            "Vendor prices not yet confirmed at a merchant count less, %",
        },
        {
            "spendLimit",
            "Gold one visit may spend (0 = no limit)",
            "Gold one auction house visit may spend on deals (0 = no limit)",
        },
        { "leaveLots", "Cheap units left for other buyers", "Cheap units of a vendor deal left for other buyers" },
    }
    heading(p, "Limits", 12, -6)
    UI.safetyBoxes = {}
    for i, f in ipairs(fields) do
        local y = -28 - (i - 1) * 28
        if i % 2 == 1 then
            stripe(p, y + 2, 28)
        end
        local label = text(p, "GameFontHighlight")
        label:SetPoint("TOPLEFT", p, "TOPLEFT", 14, y - 6)
        label:SetWordWrap(false)
        label:SetText(L(f[2]))
        local e = editbox(p, 86)
        e:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, y - 2)
        e:SetJustifyH("RIGHT")
        e.field = f
        hint(e, f[2], f[3])
        UI.safetyBoxes[i] = e
    end
    local below = -28 - #fields * 28
    UI.safetySave = button(p, "Save", 90, function()
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
    UI.safetySave:SetPoint("TOPRIGHT", p, "TOPRIGHT", -12, below - 6)
    heading(p, "What ForeverFlip learned", 12, below - 40)
    UI.safetyText = text(p, "GameFontHighlight")
    UI.safetyText:SetPoint("TOPLEFT", p, "TOPLEFT", 14, below - 64)
    UI.safetyText:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, below - 64)
    UI.safetyText:SetSpacing(4)
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

-- Which Settings page shows (general, keys, share, safety); UI.show calls it for settings:<page>.
function UI.setSettingsFrame(id)
    if not UI.settingFrames or not UI.settingFrames[id] then
        id = "general"
    end
    UI.settingsTab = id
    for key, frame in pairs(UI.settingFrames or {}) do
        if key == id then
            frame:Show()
        else
            frame:Hide()
        end
        UI.settingTabs[key]:SetEnabled(key ~= id)
    end
end

function UI.showSettingsTab(id)
    UI.show(id == "general" and "settings" or ("settings:" .. id))
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
    heading(p, "Key bindings", 12, -6)
    UI.keyButtons = {}
    for i, b in ipairs(UI.BINDINGS) do
        local y = -28 - (i - 1) * 30
        if i % 2 == 1 then
            stripe(p, y + 2, 30)
        end
        local label = text(p, "GameFontHighlight")
        label:SetPoint("TOPLEFT", p, "TOPLEFT", 14, y - 7)
        label:SetWordWrap(false)
        label:SetText(L(b[2]))
        local key = button(p, "", 170, function()
            UI.captureKey(b[1])
        end)
        key:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, y - 2)
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
    local below = -28 - #UI.BINDINGS * 30
    heading(p, "How to set a key", 12, below - 14)
    UI.keyText = text(p, "GameFontHighlight")
    UI.keyText:SetPoint("TOPLEFT", p, "TOPLEFT", 14, below - 38)
    UI.keyText:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, below - 38)
    UI.keyText:SetSpacing(4)
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
    heading(p, "Automatic", 12, -6)
    local function toggle(row, setting, label)
        return checkRow(p, 14, -26 - row * 26, label, nil, F.db.settings[setting], function(self)
            F.db.settings[setting] = self:GetChecked() and true or false
        end)
    end
    toggle(0, "shareReceive", "Accept full scans shared by guild and group members")
    toggle(1, "shareAuto", "Send my full scans to the guild after each scan")
    toggle(2, "rawScans", "Keep my full scans for the ForeverFlip Sync helper (community data)")
    local channel = toggle(3, "shareChannel", "Share full scans with every ForeverFlip user of the realm")
    channel:HookScript("OnClick", function(self)
        if self:GetChecked() then
            F.Share.join()
        else
            F.Share.leave()
        end
    end)

    heading(p, "Send my price history", 12, -140)
    local to = text(p, "GameFontHighlight")
    to:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -168)
    to:SetText(L("Send to:"))
    UI.shareGuild = button(p, "Guild", 90, function()
        local _, why = F.Share.send("GUILD")
        F.Engine.notify(why)
    end)
    UI.shareGuild:SetPoint("LEFT", to, "RIGHT", 10, 0)
    UI.shareGroup = button(p, "Group", 90, function()
        local _, why = F.Share.send((IsInRaid and IsInRaid()) and "RAID" or "PARTY")
        F.Engine.notify(why)
    end)
    UI.shareGroup:SetPoint("LEFT", UI.shareGuild, "RIGHT", 4, 0)
    UI.shareWhisper = button(p, "Send", 80, function()
        local _, why = F.Share.send("WHISPER", UI.shareName:GetText())
        F.Engine.notify(why)
    end)
    UI.shareWhisper:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, -163)
    UI.shareName = editbox(p, 120)
    UI.shareName:SetPoint("RIGHT", UI.shareWhisper, "LEFT", -8, 0)
    local whisper = text(p, "GameFontHighlight")
    whisper:SetPoint("RIGHT", UI.shareName, "LEFT", -10, 0)
    whisper:SetText(L("Player:"))
    UI.shareExport = button(p, "Export as text", 140, function()
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
    UI.shareExport:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -194)
    UI.shareImport = button(p, "Import text", 140, function()
        UI.showText(L("Paste a shared scan (Ctrl+V), then press Import."), "", function(textValue)
            local merged, why = F.Share.import(textValue)
            F.Engine.notify(merged and "share_received" or why)
            return merged ~= nil
        end)
    end)
    UI.shareImport:SetPoint("LEFT", UI.shareExport, "RIGHT", 4, 0)

    heading(p, "State", 12, -232)
    UI.shareText = text(p, "GameFontHighlightSmall")
    UI.shareText:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -256)
    UI.shareText:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, -256)
    UI.shareText:SetSpacing(4)
end

function UI.refreshShare()
    local lines = {
        L(
            "What is shared is your price history of the last 7 days (every full scan of those days, by day: cheapest and usual price, units listed and seen sold) and the prices of your last scan. Received history fills the other player's days and sales data and gives a fresh usual price when theirs is older. It never creates deals by itself, and the other player needs ForeverFlip too."
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
    -- { setting, short label, kind, column, full explanation (tooltip) }
    local fields = {
        { "vendorMinProfit", "Vendor deal", "money", 1, "Minimum profit of a vendor deal" },
        { "minProfit", "Resale", "money", 1, "Minimum profit of a resale" },
        { "minROI", "Resale return, %", "percent", 1, "Minimum resale return, %" },
        { "spendShare", "One deal, % of money", "percent", 2, "Money one deal may use, %" },
        { "itemShare", "One item, % of money", "percent", 2, "Money one item may hold (stock and new resale), %" },
        { "alertMinProfit", "Sound notice from", "money", 1, "Smallest profit with a sound notice" },
        { "undercutPercent", "Undercut, %", "percent", 2, "Undercut, % (0 = one price step)" },
        { "minPricePercent", "Never post below, %", "percent", 2, "Never post below, % of the usual price" },
        { "maxPricePercent", "Ignore sellers above, %", "percent+", 2, "Ignore sellers above, % of the usual price" },
    }
    local COL = { 12, 326 }
    local WIDTH = 296
    heading(p, "Minimum profit", COL[1], -6, WIDTH)
    heading(p, "Money and prices", COL[2], -6, WIDTH)
    local rows = { 0, 0 }
    UI.settingBoxes = {}
    for i, f in ipairs(fields) do
        local col = f[4]
        local y = -30 - rows[col] * 26
        rows[col] = rows[col] + 1
        local label = text(p, "GameFontHighlight")
        label:SetPoint("TOPLEFT", p, "TOPLEFT", COL[col], y - 4)
        label:SetWidth(WIDTH - 100)
        label:SetWordWrap(false)
        label:SetText(L(f[2]))
        local e = editbox(p, 86)
        e:SetPoint("TOPRIGHT", p, "TOPLEFT", COL[col] + WIDTH, y)
        e:SetJustifyH("RIGHT")
        e.field = f
        hint(e, f[2], f[5])
        UI.settingBoxes[i] = e
    end

    -- Options: two columns of check boxes, one short line each.
    local top = -30 - math.max(rows[1], rows[2]) * 26 - 14
    heading(p, "Options", COL[1], top, COL[2] + WIDTH - COL[1])
    local slots = 0
    local function check(label, body, checked, onClick)
        local column, row = slots % 2 + 1, math.floor(slots / 2)
        slots = slots + 1
        local box = checkRow(p, COL[column], top - 22 - row * 26, label, body, checked, onClick)
        box.label:SetWidth(WIDTH - 30)
        return box
    end
    local function toggle(setting, label, body)
        local checked
        if setting == "belowMin" then
            checked = F.db.settings.belowMin == "hold"
        else
            checked = F.db.settings[setting]
        end
        return check(label, body, checked, function(self)
            if setting == "sniper" then
                F.Deals.setSniper(self:GetChecked() and true or false)
            elseif setting == "belowMin" then
                F.db.settings.belowMin = self:GetChecked() and "hold" or "min"
            else
                F.db.settings[setting] = self:GetChecked() and true or false
            end
            UI.refresh()
        end)
    end
    check(
        "Check deals automatically",
        "Check found deals on the auction house automatically (one search per second)",
        F.Engine.autoVerify,
        function(self)
            F.Engine.autoVerify = self:GetChecked() and true or false
            F.db.settings.autoVerify = F.Engine.autoVerify
        end
    )
    toggle("autoScan", "Full scan every 15 minutes", "Full scan every 15 minutes while the auction house is open")
    UI.sniperBox =
        toggle("sniper", "Sniper between scans", "Sniper: between scans, re-read the items most often near a deal")
    toggle("alerts", "Sound for a buyable deal", "Sound and screen notice when a deal can be bought")
    toggle("tooltipPrices", "Prices in item tooltips", "Price history from the scans in item tooltips")
    toggle("highlight", "Mark deals in the Buy tab", "Mark deals in the game's Buy tab")
    toggle("learnBrowsing", "Learn from my searches", "Learn prices and deals from my own searches in the Buy tab")
    toggle("belowMin", "Keep items below their floor", "Keep items in the bags when the market is below their floor")
    toggle("disenchant", "Disenchant deals", "Disenchant deals (for a character who knows Disenchant)")

    -- Bottom: Save and the presets on the left, the language on the right.
    local bar = CreateFrame("Frame", nil, p)
    bar:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
    bar:SetHeight(34)
    local line = bar:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.25)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", bar, "TOPLEFT", 4, 0)
    line:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -4, 0)
    UI.saveButton = button(bar, "Save", 90, function()
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
    UI.saveButton:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 8, 6)
    local last = UI.saveButton
    for i, name in ipairs({ "careful", "balanced", "aggressive" }) do
        local b = button(bar, UI.PRESET_LABELS[name], 86, function()
            UI.applyPreset(name)
        end)
        b:SetPoint("LEFT", last, "RIGHT", i == 1 and 14 or 4, 0)
        hint(b, "Presets:", "Set the money and profit thresholds in one click.")
        last = b
        UI["preset_" .. name] = b
    end
    local uk = button(bar, "Українська", 90, function()
        F.db.settings.language = "uk"
        F.Engine.notify("reload")
    end)
    uk:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -8, 6)
    local en = button(bar, "English", 70, function()
        F.db.settings.language = "en"
        F.Engine.notify("reload")
    end)
    en:SetPoint("RIGHT", uk, "LEFT", -4, 0)
    hint(en, "Language (applies after /reload)", "Language (applies after /reload)")
    hint(uk, "Language (applies after /reload)", "Language (applies after /reload)")
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
    local scope, keys = UI.statusTargets()
    local batchDone, batchTotal, batchActive, batchFailed = F.Deals.batchProgress()
    if F.Deals.busy() then
        UI.bulkButton:SetText(L("Stop"))
        UI.bulkButton:SetEnabled(true)
    else
        UI.bulkButton:SetText(L("Check all"))
        UI.bulkButton:SetEnabled(
            scope ~= nil and #keys > 0 and F.AH.isOpen() and not F.Trade.busy() and not F.Scan.blocking()
        )
    end
    local op = F.Trade.op
    if op and (op.state == "quote" or op.state == "quoted" or op.state == "awaiting") then
        UI.scanButton:Disable()
        UI.progress:SetValue(0)
        UI.status:SetText(
            op.state == "quoted" and string.format(L("Price offer ready: press Confirm (%s)."), U.money(op.cost))
                or op.state == "quote" and L("Asking the auction house for the price of the purchase...")
                or L("Buying: waiting for the auction house...")
        )
        return
    end
    if F.Trade.postingNow() then
        UI.scanButton:Disable()
        UI.progress:SetValue(0)
        UI.status:SetText(L(MESSAGES.post_sent))
        return
    end
    local foreground, active = F.Deals.foreground()
    if foreground and not F.Scan.blocking() then
        UI.scanButton:Disable()
        UI.progress:SetValue(0)
        UI.status:SetText(L(active and "checking..." or "queued"))
        return
    end
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
        local line =
            string.format(L("Checking %s: %d/%d"), L(BATCH_SCOPES[batch.scope] or batch.scope), batchDone, batchTotal)
        if F.Deals.batchPaused() then
            line = line .. " · " .. L("paused while you sell or use the game's own page")
        end
        UI.status:SetText(line)
        UI.progress:SetValue(batchTotal > 0 and batchDone / batchTotal or 0)
        return
    elseif batch and batchTotal > 0 and UI.completedBatch ~= batch then
        UI.completedBatch, UI.batchSummaryAt = batch, F.Engine.clock()
    end
    -- Check prices of My auctions: its progress belongs up here, with the other running work.
    local ownedLeft = F.Trade.checksRemaining()
    if ownedLeft > 0 then
        local ownedTotal = math.max(F.Trade.checkTotal or ownedLeft, ownedLeft)
        UI.status:SetText(
            string.format(L("Checking prices of your auctions: %d/%d"), ownedTotal - ownedLeft, ownedTotal)
        )
        UI.progress:SetValue((ownedTotal - ownedLeft) / ownedTotal)
        return
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
            -- Still unanswered after the automatic second try (the chat names them).
            summary = summary .. string.format(L(" (%d without an answer)"), batchFailed)
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
        badge:SetPoint("RIGHT", f, "TOPRIGHT", -12, 24)
        badge:SetJustifyH("RIGHT")
        UI.status:SetPoint("RIGHT", badge, "LEFT", -12, 0)
        UI.status:SetWordWrap(false)
        return
    end
    badge:SetJustifyH("CENTER")
    UI.status:SetPoint("RIGHT", f, "TOPRIGHT", -12, 24)
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
-- The open auction house is named in the bottom bar (UI.houseName); the summary does not repeat it.
function UI.houseLine()
    return ""
end

function UI.refreshSummary()
    local last = F.Scan.last
    if not last then
        UI.summary:SetText(UI.houseLine())
        return
    end
    local s = last.stats
    -- One short line per figure, so none wraps in the narrow menu.
    UI.summary:SetText(
        UI.houseLine()
            .. string.format(
                L("Scan: %d min ago\nAuctions: %d\nItems: %d\nVendor price: %d\nBelow vendor: %d\nSales data: %d"),
                math.floor((F.Engine.clock() - last.at) / 60),
                last.total,
                s.items,
                s.vendorKnown,
                s.belowVendor,
                s.salesReady or 0
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
            L("Sniper: %d rounds\nRead %d · found %d\nChecks: %d"),
            F.Sniper.rounds,
            F.Sniper.items,
            F.Sniper.found,
            F.Deals.snipes or 0
        )
end

function UI.refresh()
    if not UI.frame or not UI.frame:IsShown() then
        return
    end
    F.Engine.urgent, F.Engine.dirty = false, false
    if not UI.nativeLook then
        pcall(UI.copyNativeLook)
    end
    if not UI.nativeRows then
        pcall(UI.copyNativeRows)
    end
    if not UI.tabsSized and UI.tabsShown then
        UI.layoutTabs(UI.tabsShown.group, UI.tabsShown.id)
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
    elseif UI.section == "undercuts" then
        UI.refreshUndercuts()
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
    -- Without LibAHTab (it comes with Auctionator or TSM) the tab is built the way LibAHTab builds
    -- it: the button sits on a plain frame after the game's last tab, not on AuctionHouseFrame.
    -- Any step that fails falls back to a plain button, so the page stays reachable.
    local tabs = AuctionHouseFrame.Tabs
    local root = CreateFrame("Frame", nil, AuctionHouseFrame)
    root:SetSize(10, 10)
    if tabs and #tabs > 0 then
        root:SetPoint("TOPLEFT", tabs[#tabs], "TOPRIGHT")
    else
        root:SetPoint("TOPLEFT", AuctionHouseFrame, "BOTTOMLEFT", 20, 0)
    end
    local function call(f, ...)
        if f then
            pcall(f, ...)
        end
    end
    local ok, b = pcall(function()
        local tab = CreateFrame("Button", "ForeverFlipTab", root, "AuctionHouseFrameDisplayModeTabTemplate")
        tab:SetText("ForeverFlip")
        if PanelTemplates_TabResize then
            PanelTemplates_TabResize(tab, 20, nil, 70)
        end
        return tab
    end)
    if not ok or not b then
        F.Engine.report("AH tab: " .. tostring(b))
        b = CreateFrame("Button", "ForeverFlipTabButton", root, "UIPanelButtonTemplate")
        b:SetSize(100, 22)
        b:SetText("ForeverFlip")
    end
    b:SetPoint("TOPLEFT", root, "TOPLEFT", 3, 0)
    call(PanelTemplates_DeselectTab, b)
    UI.frame:Hide()
    b:SetScript("OnClick", function()
        call(AuctionHouseFrame.SetDisplayMode, AuctionHouseFrame, {})
        AuctionHouseFrame.displayMode = nil
        for _, t in ipairs(tabs or {}) do
            call(PanelTemplates_DeselectTab, t)
        end
        call(PanelTemplates_SelectTab, b)
        call(AuctionHouseFrame.SetTitle, AuctionHouseFrame, "ForeverFlip: " .. UI.houseName())
        UI.frame:Show()
    end)
    if hooksecurefunc and AuctionHouseFrame.SetDisplayMode then
        pcall(hooksecurefunc, AuctionHouseFrame, "SetDisplayMode", function(_, mode)
            if type(mode) == "table" and #mode > 0 then
                UI.frame:Hide()
                call(PanelTemplates_DeselectTab, b)
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
    -- The auction house shows the price to post at, the same as the price box of the Sell page; it
    -- turns red when that price loses money on what the stock cost. Sorting uses what it brings.
    local q = w.quote
    if w.name == "auction" and q and q.post then
        local money = U.money(q.post)
        if q.profit and q.profit < 0 then
            money = "|cffff6060" .. money .. "|r"
        end
        return color .. L(BEST[w.name]) .. "|r " .. money
    end
    return color .. L(BEST[w.name]) .. "|r " .. U.money(w.value)
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

-- One way to say where a post price (F.Trade.quote) comes from, on the tooltip and the Sell page.
local QUOTE_WHY = {
    undercut = "one step below the cheapest seller %s",
    normal = "normal price: the cheapest seller %s asks too much",
    estimate = "usual price; the AH check gives the exact one",
    last = "your last price",
    aux = "auxForever's usual price",
    cost = "guess: your cost plus 25%",
    vendor = "guess: 1.5 x the vendor price",
}
function UI.quoteWhy(q)
    if q.belowFloor then
        return string.format(L("the market %s is below your minimum"), U.money(q.market))
    end
    local text = L(QUOTE_WHY[q.why] or QUOTE_WHY.estimate)
    if text:find("%%s") then
        return string.format(text, U.money(q.cheapest))
    end
    return text
end

-- "You get each, after the 5% cut" (and the deposits expected to be lost, when there are any).
function UI.netLabel(q)
    local cut = math.floor(F.Market.CUT * 100 + 0.5)
    if (q.lost or 0) > 0 then
        return string.format(L("You get each, after the %d%% cut and %s lost deposits"), cut, U.money(q.lost))
    end
    return string.format(L("You get each, after the %d%% cut"), cut)
end

-- Money with a sign, green when it gains and red when it loses.
function UI.signed(copper)
    if copper >= 0 then
        return "|cff40ff40+" .. U.money(copper) .. "|r"
    end
    return "|cffff6060" .. U.money(copper) .. "|r"
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
            if a.price then
                price = price and math.min(price, a.price) or a.price -- the price of one unit
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
    -- The same sum as the Sell page and its Best column (F.Trade.quote).
    local quote = F.Trade.quote(key, id)
    local advice = quote and quote.best and quote or nil
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
        if sale then
            tipLine(tooltip, L("Buyers paid lately (median of sales seen)"), U.money(sale))
        end
        local at = advice and advice.net and advice.post or usual
        local s = F.Market.saleability(h, at, F.Engine.clock())
        if s.known then
            tipLine(
                tooltip,
                string.format(L("Sold per day at %s or more"), U.money(math.floor(at * 0.85))),
                string.format("~%.1f", s.perDay)
            )
            local e = F.Market.saleEvidence(h, math.floor(at * 0.85))
            if e then
                tipLine(
                    tooltip,
                    string.format(L("  seen: %d buys, %d in part / %d whole lots"), e.buys, e.sure, e.lots),
                    U.money(e.low) .. " - " .. U.money(e.high)
                )
            end
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
        if advice.net then
            tipLine(
                tooltip,
                L("Post at") .. " |cff999999(" .. UI.quoteWhy(advice) .. ")|r",
                U.money(advice.post),
                1,
                1,
                1
            )
            tipLine(tooltip, UI.netLabel(advice), U.money(advice.net))
            if advice.profit then
                tipLine(tooltip, L("Profit each"), UI.signed(advice.profit))
            end
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

-- Merchant window ----------------------------------------------------------------------------------
-- A ForeverFlip tab beside Merchant and Buyback: what to sell to this merchant (one button sells it
-- all) and what to buy here for the auction house. The Merchant tab gets a button that sells the
-- same list at once.
local MERCHANT_SELL_ROWS, MERCHANT_BUY_ROWS = 5, 4
local MERCHANT_BUY_HEIGHT = 44

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
        row.gain = text(row, "GameFontHighlightSmall")
        row.gain:SetPoint("TOPLEFT", row.prices, "BOTTOMLEFT", 0, -1)
        row.gain:SetPoint("RIGHT", row.buy, "LEFT", -6, 0)
        row.gain:SetJustifyH("LEFT")
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

local function sellGear()
    local stacks, money = F.Trade.sellUnusableGear()
    if stacks > 0 then
        print(
            "ForeverFlip: " .. string.format(L("sold %d pieces of gear you cannot use for %s"), stacks, U.money(money))
        )
    end
    UI.merchant(true)
end

-- The merchant's item pages (buttons, page arrows, repair buttons) are drawn above the ForeverFlip
-- view: they are hidden while it is open, and the game shows them again on its own tabs.
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
local function merchantPages(show)
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
    if show and MerchantFrame_Update then
        pcall(MerchantFrame_Update) -- the game decides again what its tab shows
    end
end

function UI.merchantSelect(on, closing)
    local view, tab = UI.merchantView, UI.merchantTab
    if not view then
        return
    end
    if on then
        merchantPages(false)
    elseif view:IsShown() and not closing then
        merchantPages(true)
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

    -- The Merchant tab: one button sells the list at once.
    UI.merchantButton = button(MerchantFrame, "Sell to vendor", 180, sellAll)
    UI.merchantButton:SetPoint("TOPRIGHT", MerchantFrame, "TOPRIGHT", -40, -28)
    UI.gearButton = button(MerchantFrame, "Sell gear I can't use", 180, sellGear)
    UI.gearButton:SetPoint("TOPRIGHT", UI.merchantButton, "BOTTOMRIGHT", 0, -2)
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
        UI.gearButton:Hide()
        return
    end
    local gear = F.Trade.unusableGearList()
    local gearTotal = 0
    for _, v in ipairs(gear) do
        gearTotal = gearTotal + v.price
    end
    local gearText = #gear > 0 and string.format(L("Gear I can't use (%d): %s"), #gear, U.money(gearTotal))
        or L("Sell gear I can't use")
    UI.gearButton:SetText(gearText)
    UI.merchantView.sellGear:SetText(
        #gear > 0 and string.format(L("Gear I can't use (%d)"), #gear) or L("No unusable gear")
    )
    UI.merchantView.sellGear:SetEnabled(#gear > 0)
    if #gear > 0 and not UI.merchantView:IsShown() then
        UI.gearButton:Show()
    else
        UI.gearButton:Hide()
    end
    local list = F.Trade.vendorSellList()
    local total = 0
    for _, v in ipairs(list) do
        total = total + v.price
    end
    local view = UI.merchantView
    if #list > 0 and not view:IsShown() then
        UI.merchantButton:SetText(string.format(L("Sell to vendor (%d): %s"), #list, U.money(total)))
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
    local selling = F.Trade.sellingToVendor and F.Trade.sellingToVendor()
    view.sellAll:SetText(
        selling and L("Selling...")
            or (#list > 0 and string.format(L("Sell all (%d): %s"), #list, U.money(total)) or L("Sell all"))
    )
    view.sellAll:SetEnabled(#list > 0 and not selling)
    local offers = F.Merchant.offers()
    view.buyOffset = math.max(0, math.min(view.buyOffset or 0, #offers - MERCHANT_BUY_ROWS))
    view.buyTitle:SetText(
        L("Buy here, sell on the auction house")
            .. (
                #offers > MERCHANT_BUY_ROWS
                    and string.format(
                        " |cff999999(%d-%d / %d)|r",
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
            row.prices:SetText(
                "|cffb0b0b0"
                    .. L("Vendor")
                    .. "|r "
                    .. U.money(o.unit)
                    .. "  |cff808080"
                    .. L("·")
                    .. "|r  |cffb0b0b0"
                    .. L("AH")
                    .. "|r "
                    .. U.money(o.exit)
            )
            row.gain:SetText(
                "|cff40ff40+"
                    .. U.money(math.floor(o.each))
                    .. "|r |cffb0b0b0"
                    .. L("each")
                    .. "|r  |cff808080"
                    .. L("·")
                    .. "|r  "
                    .. string.format("~%.1f/%s", o.perDay, L("day"))
            )
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
