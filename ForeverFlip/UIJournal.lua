-- ForeverFlip window: Journal page.
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
local nameOf = S.nameOf
local atlas = S.atlas
local table_ = S.table_
local footer = S.footer

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
    -- Every purchase and what became of it: what it cost, what its posts lost, what it sold for.
    UI.journalList = CreateFrame("Frame", nil, p)
    UI.lotTable = table_(
        UI.journalList,
        {
            { "Name" },
            { "Sold", 86 }, -- "4878/5148" fits
            { "Buy at", 80 },
            { "Cost", 76 },
            {
                "Lost",
                64,
                nil,
                "Lost deposits and cancellation fees. ~ includes estimates or charges without a surviving journal entry.",
            },
            { "Sold for", 80 },
            {
                "Profit",
                96,
                nil,
                "Unconfirmed: some vendor stock is absent from bags, but no sale was recorded. It may be elsewhere; no revenue is invented.",
            },
        },
        12,
        function(r)
            if r.lotID and r.key then
                UI.journalSelected = { id = r.lotID, key = r.key }
                UI.refreshJournal()
            end
        end
    )
    -- Use the same standard footer block as Deals/Selling: one separator line, the addon font
    -- and the existing scrollbar, without inventing a second visual style for history.
    UI.journalHistoryFrame = footer(p, 104, "GameFontHighlightSmall")
    UI.journalHistoryFrame.text:Hide()
    UI.journalHistory = UI.scrollText(UI.journalHistoryFrame, 3, 6, 26, 72)
    UI.journalResolve = {}
    local lastResolve
    local function resolve(state)
        local pick = UI.journalSelected
        if not pick then
            return
        end
        local c = F.Data.char(F.db, F.Engine.owner())
        local lot, older
        for _, candidate in ipairs(F.Data.lots(c)) do
            if candidate.id == pick.id and candidate.key == pick.key then
                lot = candidate
                break
            end
            if candidate.key == pick.key and (candidate.left or 0) > 0 then
                older = candidate
            end
        end
        -- A lot is resolved once: a second Vendor sold would book its units again.
        if not lot or lot.reconciled then
            return
        end
        if state == "vendor" then
            -- The sale is booked on the item's oldest open lots first (F.Data.sale): with an older
            -- purchase still open it would empty that one, not the lot chosen here.
            if older then
                F.Engine.notify("older_lot")
                return
            end
            local item = U.parseKey(lot.key)
            -- What a merchant really paid (buyback list), else the client's price without the
            -- safety margin of deal estimates: the money that came in.
            local price = item and F.AH.vendorPrice(item.id, true)
            if not price or lot.left <= 0 then
                return
            end
            F.Trade.onVendorSale(lot.key, lot.left, price)
        end
        lot.reconciled = state
        F.Engine.changed()
        UI.refreshJournal()
    end
    for _, spec in ipairs({
        { "Vendor sold", "vendor" },
        { "Still held", "held" },
        { "Sold outside addon", "external" },
    }) do
        local b = button(UI.journalHistoryFrame, spec[1], 130, function()
            resolve(spec[2])
        end)
        b:SetPoint(
            lastResolve and "LEFT" or "BOTTOMLEFT",
            lastResolve or UI.journalHistoryFrame,
            lastResolve and "RIGHT" or "BOTTOMLEFT",
            lastResolve and 4 or 6,
            lastResolve and 0 or 4
        )
        UI.journalResolve[spec[2]] = b
        lastResolve = b
    end
    UI.placeJournalLines(false)
end

function UI.placeJournalLines(ask)
    local y = ask and JOURNAL_BELOW_ASK or JOURNAL_TOP
    UI.journalList:ClearAllPoints()
    UI.journalList:SetPoint("TOPLEFT", UI.journalPage, "TOPLEFT", 0, y)
    UI.journalList:SetPoint("BOTTOMRIGHT", UI.journalPage, "BOTTOMRIGHT", 0, 106)
end

-- Each line is one observed movement, with the purchase's original intent kept on the buy.
-- Old aggregate totals are never presented as invented historical transactions.
function UI.lotHistory(lot)
    local lines = { lot.name or nameOf(lot.key or "") }
    if lot.historyIncomplete then
        lines[#lines + 1] = L("History incomplete: older movements were not retained; totals may include them.")
    end
    local labels = {
        sell = "Auction sale",
        vendor = "Vendor sale",
        post = "Listed",
        cancel = "Cancelled",
        expired = "Expired",
        ["return"] = "Returned",
        loss = "Holding loss",
        disenchant = "Disenchanted",
        craft = "Used in a craft",
    }
    local chains = {}
    if lot.chain then
        chains[1] = lot.chain
    end
    for _, e in ipairs(lot.events or {}) do
        local label = L(labels[e.kind] or "Purchase")
        if e.chain and e.chain ~= chains[#chains] then
            chains[#chains + 1] = e.chain
        end
        if e.kind == "buy" and (e.source == "disenchant" or e.source == "craft") then
            label = L(e.source == "disenchant" and "Made by disenchanting" or "Made by crafting")
        elseif e.kind == "buy" then
            label = L(e.source == "buyer_invoice" and "Purchase confirmed by mail" or e.bid and "Bid won" or "Buyout")
                .. " · "
                .. L(
                    e.mode == "vendor" and "intended for vendor"
                        or e.mode == "flip" and lot.strategy == "median" and "intended for a market reset"
                        or e.mode == "flip" and "intended for resale"
                        or e.mode == "disenchant" and "intended for disenchanting"
                        or e.mode == "shop" and "from the shopping list"
                        or "purchase intent unknown"
                )
        end
        local detail = string.format(
            "%s · %s · %d × · %s%s",
            e.at and date("%d.%m %H:%M", e.at) or "?",
            label,
            e.qty or 0,
            e.estimated and "~" or "",
            U.money(e.amount or 0)
        )
        if e.kind == "post" and e.deposit then
            detail = detail .. " · " .. string.format(L("deposit %s (held)"), U.money(e.deposit))
        elseif e.kind == "return" and e.accounted then
            detail = detail .. " · " .. L("loss already recorded")
        end
        lines[#lines + 1] = detail
    end
    if lot.reconciled then
        local label = lot.reconciled == "vendor" and "Vendor sold"
            or lot.reconciled == "held" and "Still held"
            or "Sold outside addon"
        lines[#lines + 1] = L(label)
    end
    local c = F.Data.char(F.db, F.Engine.owner())
    for _, id in ipairs(chains) do
        lines[#lines + 1] = UI.chainSummary(c, id)
    end
    return lines
end

-- T21: one line on a chain purchase -> craft or disenchant -> sale: what the materials cost, what
-- the products brought so far and the profit (final once every product is sold).
function UI.chainSummary(char, id)
    local p = F.Data.chainProfit(char, id)
    if not p then
        return L("Chain no longer kept.")
    end
    return string.format(
        L(
            p.done and "Chain (%s): cost %s, products brought %s, profit %s"
                or "Chain (%s): cost %s, products brought %s so far, profit %s (%d unsold)"
        ),
        L(p.op == "disenchant" and "disenchant" or "craft"),
        U.money(p.cost),
        U.money(p.received - p.lost),
        U.money(p.profit),
        p.left
    )
end

-- One purchase lot as the table shows it: profit only once every unit is sold (else what came
-- back so far), the money its sold units brought each.
function UI.lotRow(lot)
    local soldEach = lot.sold > 0 and math.floor(lot.received / lot.sold + 0.5) or nil
    local closed = lot.left <= 0
    -- Units made into other items (T21) took their cost along to the chain's products.
    local profit = closed and (lot.received + (lot.convertedCost or 0) - lot.cost - (lot.lost or 0)) or nil
    return {
        sold = string.format("%d/%d", lot.sold, lot.qty),
        each = math.floor(lot.cost / math.max(lot.qty, 1) + 0.5),
        soldEach = soldEach,
        profit = profit,
        closed = closed,
    }
end

-- The way a lot came and is dealt, as the Journal's views name it: "craft" or "disenchant" (the
-- products of a chain, T21, or stock bought to disenchant), "bid" (won with a bid), "median" (a
-- market reset), "vendor" (bought for a merchant) or "flip" (bought for resale; also purchases
-- made elsewhere).
function UI.lotKind(lot)
    if lot.chain then
        local first = lot.events and lot.events[1]
        return first and first.source == "disenchant" and "disenchant" or "craft"
    end
    if lot.bid then
        return "bid"
    end
    if lot.strategy == "median" then
        return "median"
    end
    if lot.mode == "disenchant" then
        return "disenchant"
    end
    return lot.mode == "vendor" and "vendor" or "flip"
end

-- The lots the Journal page lists, for the view chosen under it (UI.lotKind). Shared with the Check all of that page, so both read the same rows.
function UI.journalLots()
    local view = UI.journalFilter or "all"
    local out = {}
    local c = F.Data.char(F.db, F.Engine.owner())
    for _, lot in ipairs(F.Data.lots(c)) do
        if view == "all" or UI.lotKind(lot) == view then
            out[#out + 1] = lot
        end
    end
    return out
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
    -- The view chosen under Journal and profit: all purchases, or those of one way of dealing.
    local lots, held, pending = {}, {}, {}
    for _, item in ipairs(F.AH.merchantItems()) do
        held[item.key] = (held[item.key] or 0) + item.count
    end
    for _, lot in ipairs(F.Data.lots(c)) do
        -- A lot the player resolved (held, sold elsewhere) is accounted for: its units are not
        -- expected in the bags.
        if lot.mode == "vendor" and not lot.reconciled then
            pending[lot.key] = (pending[lot.key] or 0) + lot.left
        end
    end
    lots = UI.journalLots()
    local selected
    for _, lot in ipairs(lots) do
        local pick = UI.journalSelected
        if pick and lot.id == pick.id and lot.key == pick.key then
            selected = lot
        end
    end
    if not selected then
        UI.journalSelected = nil
    end
    UI.journalHistory.set(
        selected and UI.lotHistory(selected) or {},
        selected and (selected.key .. ":" .. selected.id) or ""
    )
    for _, b in pairs(UI.journalResolve or {}) do
        b:SetEnabled(selected ~= nil and not selected.reconciled)
    end
    table.sort(lots, function(a, b)
        return (a.at or 0) > (b.at or 0)
    end)
    lots = UI.lotTable.sort(lots, function(lot, column)
        local row = UI.lotRow(lot)
        return ({ lot.name or "", lot.sold, row.each, lot.cost, lot.lost or 0, lot.received, row.profit })[column]
    end)
    -- lots is already the part the rows show (sort windows it): windowing it again reset the scroll.
    for i, r in ipairs(UI.lotTable.rows) do
        local lot = lots[i]
        if lot then
            local row = UI.lotRow(lot)
            local item = U.parseKey(lot.key or "")
            r.key = lot.key
            r.lotID = lot.id
            r.icon:SetTexture(icon(item and item.id))
            r.name:SetText(date("%d.%m ", lot.at or 0) .. (lot.name or nameOf(lot.key or "")))
            r.cols[1]:SetText(row.sold)
            r.cols[2]:SetText(U.money(row.each))
            r.cols[3]:SetText(U.money(lot.cost))
            local evidence = F.Data.lossEvidence(c, lot.key)
            local approximate = evidence.estimated > 0 or evidence.unattributed > 0
            r.cols[4]:SetText(
                (lot.lost or 0) > 0 and (UI.C.warn .. (approximate and "~" or "") .. U.money(lot.lost) .. "|r") or "-"
            )
            r.cols[5]:SetText(
                lot.sold > 0 and (U.money(lot.received) .. (row.soldEach and lot.sold > 1 and "" or "")) or "-"
            )
            if row.profit then
                r.cols[6]:SetText((approximate and (lot.lost or 0) > 0 and "~" or "") .. UI.signed(row.profit))
            elseif lot.reconciled then
                local label = lot.reconciled == "vendor" and "Vendor sold"
                    or lot.reconciled == "held" and "Still held"
                    or "Sold outside addon"
                r.cols[6]:SetText(UI.C.info .. L(label) .. "|r")
            elseif lot.mode == "vendor" and (held[lot.key] or 0) < (pending[lot.key] or 0) then
                r.cols[6]:SetText(UI.C.warn .. L("Unconfirmed") .. "|r")
            else
                r.cols[6]:SetText(UI.C.dim .. string.format(L("%d in stock"), lot.left) .. "|r")
            end
            r.selected:SetShown(selected == lot)
            r:Show()
        else
            r.key = nil
            r.lotID = nil
            r:Hide()
        end
    end
    local empty = UI.lotTable.empty
    if #lots == 0 then
        empty:SetText(L("No trades yet."))
        empty:Show()
    else
        empty:Hide()
    end
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
