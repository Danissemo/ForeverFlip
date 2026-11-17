-- ForeverFlip window: status line, refresh, Buy tab marks and the price history window.
-- Moved from UI.lua as it was and loaded after it (ForeverFlip.toc); locals of the
-- earlier UI files come through UI.shared.
local UI = ForeverFlip.UI
local S = UI.shared
local F = S.F
local U = S.U
local L = S.L
local MESSAGES = S.MESSAGES
local text = S.text
local button = S.button
local place = S.place
local nameOf = S.nameOf

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
    ["deals:median"] = "Market reset",
    ["deals:shop"] = "Shopping deals",
    sell = "Bags",
    auctions = "My auctions",
    undercuts = "Undercuts",
    shop = "Shopping list",
    bids = "Bids",
    crafting = "Crafting",
}

-- A newer ForeverFlip, from the helper's data (Raw.update): put before the idle status line, which
-- does not wrap and is cut at its end.
function UI.updateNote()
    local latest = F.Raw.update()
    return latest and ("|cff40ff40" .. string.format(L("Update %s available"), tostring(latest.version)) .. "|r · ")
        or ""
end

function UI.refreshStatus()
    UI.refreshHouse()
    UI.sniperButton:SetText(L(F.db.settings.sniper and "Sniper: ON" or "Sniper: OFF"))
    UI.sniperBox:SetChecked(F.db.settings.sniper)
    local scope, keys = UI.statusTargets()
    local batchDone, batchTotal, batchActive, batchFailed = F.Deals.batchProgress()
    if F.Deals.stoppingWork() then
        UI.bulkButton:SetText(L("Stop"))
        UI.bulkButton:SetEnabled(true)
    else
        -- During a full scan this reads Check all (pressable: the checks wait for the scan) rather
        -- than Stop, which used to end the scan the player was waiting for.
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
        -- The scan's own Stop: the button beside the progress offers it while a scan runs (Check
        -- all no longer does, since it means "check the page" during one). Its tooltip says so.
        UI.scanButton:SetText(L("Stop scan"))
        UI.scanButton:Enable()
        return
    end
    UI.progress:SetValue(0)
    local cooldown = math.floor(F.Scan.cooldown())
    local Sn = F.Sniper
    -- While the full scan waits for the server's 15 minutes, the same button offers a quick scan
    -- (one browse of the whole house's lowest prices) and still shows when the full one is free.
    local quickOffer = (cooldown > 0 or not F.Compat.caps.fullScan) and Sn.canQuick()
    -- T06/T08: pressable only when the scan would be sent (S.canStart runs Scan.start's checks).
    UI.scanButton:SetEnabled(quickOffer or Sn.quick ~= nil or cooldown == 0 and F.Scan.canStart())
    UI.scanButton:SetText(
        F.Scan.rebuilding() and L("Rebuilding sales statistics…")
            or Sn.quick and L("Stop quick scan")
            or quickOffer and cooldown > 0 and string.format(
                L("Quick scan (full %d:%02d)"),
                math.floor(cooldown / 60),
                cooldown % 60
            )
            or quickOffer and L("Quick scan")
            or not F.Compat.caps.fullScan and L("No full scan")
            or cooldown > 0 and string.format(L("Full scan in %d:%02d"), math.floor(cooldown / 60), cooldown % 60)
            or L("Full scan")
    )
    local quickItems, quickFound, quickLeft = Sn.quickProgress()
    if quickLeft then
        UI.status:SetText(string.format(L("Quick scan: %d found · checking, %d left"), quickFound, quickLeft))
        UI.progress:SetValue(0)
        return
    elseif quickItems then
        UI.status:SetText(string.format(L("Quick scan: %d items read · %d found"), quickItems, quickFound))
        UI.progress:SetValue(0)
        return
    end
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
    elseif F.Sniper.paused() then
        UI.status:SetText(L(F.Sniper.paused()))
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
            UI.updateNote()
                .. string.format(
                    L("Deals: %d · checked: %d · from the scan %s"),
                    all,
                    checked,
                    UI.age(F.Scan.last.at)
                )
        )
    else
        UI.status:SetText(UI.updateNote() .. L("Press Full scan to read the whole auction house."))
    end
end

-- The open auction house in short, and its colour: Alliance blue, Horde red, neutral gold, the
-- server's house of both factions (Retail) white.
local HOUSES = {
    Neutral = { "Neutral AH, 15% cut", "ffd100" },
    Server = { "Server AH", "ffffff" },
    Horde = { "Horde AH", "ff5050" },
    Alliance = { "Alliance AH", "4fa3ff" },
}
function UI.houseName()
    local h = HOUSES[F.Engine.side()] or HOUSES.Alliance
    return L(h[1]), h[2]
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
        badge:SetPoint("RIGHT", UI.corner, "LEFT", 0, 0)
        badge:SetJustifyH("RIGHT")
        UI.status:SetPoint("RIGHT", badge, "LEFT", -12, 0)
        UI.status:SetWordWrap(false)
        return
    end
    badge:SetJustifyH("CENTER")
    UI.status:SetPoint("RIGHT", UI.corner, "LEFT", 0, 0)
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
    UI.fitSummary()
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
                L("Scan: %s\nAuctions: %d\nItems: %d\nVendor price: %d\nBelow vendor: %d\nSales data: %d"),
                UI.age(last.at),
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
    if F.Sniper.paused() then
        return "\n\n" .. L(F.Sniper.paused())
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
    local f = UI.frame
    if not f then
        return
    end
    -- IsVisible also counts the parents: the window keeps its own shown flag inside the auction
    -- house frame after the auction house closes, and a page nobody sees is not drawn (OnShow draws
    -- it when it comes back). Frames without a real IsVisible answer nil: IsShown is asked then.
    local visible = f.IsVisible and f:IsVisible()
    if visible == nil then
        visible = f:IsShown()
    end
    if not visible then
        return
    end
    F.Engine.urgent, F.Engine.dirty = false, false
    if not UI.nativeLook then
        pcall(UI.copyNativeLook)
    end
    if not UI.nativeRows then
        pcall(UI.copyNativeRows)
    end
    UI.refreshStatus()
    UI.refreshSummary()
    if UI.section == "deals" then
        UI.refreshDeals()
    elseif UI.section == "shop" then
        UI.refreshShop()
    elseif UI.section == "bids" then
        UI.refreshBids()
    elseif UI.section == "mybids" then
        UI.refreshMyBids()
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
        elseif UI.settingsTab == "messages" then
            UI.refreshMessages()
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

-- The game's row -> its mark texture. Kept here from the first line that uses it: highlightBrowse
-- runs from the update loop before this section is read.
local marks = setmetatable({}, { __mode = "k" })

function UI.highlightBrowse()
    if not AuctionHouseFrame or not F.db then
        return
    end
    -- Off: the game's rows are not looked at at all. The marks of the rows seen before the switch
    -- were turned off are hidden here, once (hideMarks empties the table), and not twice a second.
    if not F.db.settings.highlight then
        if next(marks) then
            UI.hideMarks()
        end
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

-- The marks in the game's Buy tab must leave its code untouched: the game blames an addon for any
-- protected action (a purchase) whose code read a value the addon wrote or made. Calling the list's
-- own Lua methods (ForEachFrame, GetElementData, GetItemID) or writing a field into its rows did
-- both, twice a second, and a new player buying in the Buy tab saw "ForeverFlip has been blocked
-- from an action only available to the Blizzard UI". Now the rows come from the game's own method
-- ScrollBox:GetFrames() (the view's list; the widget is not a Lua table, so not ScrollTarget),
-- their data is only read (rawget), and the marks are kept here (in `marks`, above highlightBrowse).

-- Walk the rows of a shared ScrollBox. It is a frame of the client, not a Lua table: a field read
-- with rawget returns nothing, so it is only asked for its own method (tests pass plain tables).
local function eachRow(box, fn)
    local get = rawget(box, "GetFrames")
    if type(get) ~= "function" then
        return
    end
    local ok, frames = pcall(get, box)
    if not ok or type(frames) ~= "table" then
        return
    end
    for _, row in ipairs(frames) do
        fn(row)
    end
end

-- `button.rowData` and `button.elementData`, as the game's own row code reads them (the shared ScrollBox
-- view stores the element data where the frames it made keep their data).
local function rowData(row)
    local data = rawget(row, "rowData")
    if type(data) ~= "table" then
        data = rawget(row, "elementData")
    end
    return data
end

-- The mark of a row of the game's Buy tab (tests and the off switch).
function UI.markOf(row)
    return marks[row]
end

function UI.hideMarks()
    for row, mark in pairs(marks) do
        mark:Hide()
        marks[row] = nil
    end
end

function UI.markRows(box, perRow, frame)
    local on = F.db.settings.highlight
    eachRow(box, function(row)
        local data = rowData(row)
        local id, price, link
        if type(data) == "table" then
            local key = rawget(data, "itemKey")
            id = type(key) == "table" and rawget(key, "itemID") or rawget(data, "itemID")
            if not id and frame then
                local itemKey = rawget(frame, "itemKey")
                id = type(itemKey) == "table" and rawget(itemKey, "itemID") or rawget(frame, "itemID")
            end
            price = data.minPrice or data.buyoutAmount or data.unitPrice
            link = data.itemLink
            if data.containsOwnerItem or (data.numOwnerItems or 0) >= (data.quantity or 1) then
                id = nil
            end
        end
        local mark = marks[row]
        if not mark and not on then
            return
        end
        -- One look at the price per row: the cost (the deals list, then the sniper's market history)
        -- is too high to pay twice a second for the same row.
        local deal = on and id and dealItem(id, price, link, perRow)
        if not mark and deal then
            mark = row:CreateTexture(nil, "OVERLAY")
            marks[row] = mark
            mark:SetColorTexture(0.25, 1, 0.25, 0.9)
            mark:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            mark:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            mark:SetWidth(4)
        end
        if mark then
            mark:SetShown(not not deal)
        end
    end)
end

-- Price history window -------------------------------------------------------------------------------
local HISTORY_DAYS = 14

-- T24: the market reference of the window, one row a line; with the house's scan data a day old
-- (UI.staleData), only that.
function UI.referenceText(key, h, now)
    local lines = { UI.C.head .. L("Market reference (14 days)") .. "|r" }
    if UI.staleData(now) ~= nil then
        lines[#lines + 1] = UI.C.warn .. L("data out of date, not shown") .. "|r"
        return table.concat(lines, "\n")
    end
    for _, row in ipairs(UI.referenceRows(UI.referenceFor(key, h, now))) do
        lines[#lines + 1] = row.left .. (row.right ~= "" and (": " .. row.right) or "")
    end
    return table.concat(lines, "\n")
end
function UI.showHistory(key, link)
    local h = F.Data.market(F.db, F.Engine.scope()).history[key]
    local w = UI.historyFrame
    if not w then
        w = CreateFrame("Frame", "ForeverFlipHistory", UIParent)
        w:SetSize(520, 550)
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
        -- T24: the market reference, under the title.
        w.reference = text(w, "GameFontHighlightSmall")
        w.reference:SetPoint("TOPLEFT", w, "TOPLEFT", 12, -32)
        w.reference:SetPoint("TOPRIGHT", w, "TOPRIGHT", -12, -32)
        w.reference:SetJustifyH("LEFT")
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
        UI.createPriceChart(w)
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
            -- d.d counts UTC days (floor(time / 86400)): its UTC date, not the local one, which
            -- west of UTC is the day before.
            bar.label:SetText(date and date("!%d.%m", d.d * 86400) or tostring(d.d))
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
    w.reference:SetText(UI.referenceText(key, h, F.Engine.clock()))
    local item = U.parseKey(key)
    UI.drawPriceChart(
        w,
        F.Market.priceSeries(
            days,
            item and F.Raw.pricePoints(F.Engine.scope(), item.id, item.kind == "gear" and item.name or nil) or {},
            F.Engine.clock()
        )
    )
    w:Show()
end

-- T07: the price over time above the daily bars, drawn with plain textures: the usual price of each
-- day as a yellow line, the cheapest unit of each raw full scan as blue dots, and grey bands where
-- no data came (no scan ran). F.Market.priceSeries makes the points.
UI.CHART = { x = 14, y = 240, width = 492, height = 120, dot = 3 }

function UI.createPriceChart(w)
    local c = UI.CHART
    local frame = CreateFrame("Frame", nil, w)
    frame:SetSize(c.width, c.height)
    frame:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", c.x, c.y)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(1, 1, 1, 0.04)
    bg:SetAllPoints()
    frame.textures = {}
    frame.used = 0
    frame.high = text(frame, "GameFontDisableSmall")
    frame.high:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    frame.low = text(frame, "GameFontDisableSmall")
    frame.low:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 2, 2)
    frame.legend = text(frame, "GameFontDisableSmall")
    frame.legend:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 4)
    frame.legend:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 4)
    frame.legend:SetJustifyH("LEFT")
    frame.empty = text(frame, "GameFontDisable")
    frame.empty:SetPoint("CENTER", frame, "CENTER", 0, 0)
    w.chart = frame
end

-- A texture of the chart's pool at (x, y) from its bottom left, `width` by `height`.
local function chartTexture(frame, x, y, width, height, r, g, b, a)
    frame.used = frame.used + 1
    local t = frame.textures[frame.used]
    if not t then
        t = frame:CreateTexture(nil, "ARTWORK")
        frame.textures[frame.used] = t
    end
    t:ClearAllPoints()
    t:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, y)
    t:SetSize(math.max(1, width), math.max(1, height))
    t:SetColorTexture(r, g, b, a)
    t:Show()
    return t
end

function UI.drawPriceChart(w, series)
    local frame, c = w.chart, UI.CHART
    for _, t in ipairs(frame.textures) do
        t:Hide()
    end
    frame.used = 0
    frame.legend:SetText(
        L("Price over 14 days: yellow line usual price, blue dots cheapest of each scan, grey no data")
    )
    if series.empty then
        frame.empty:SetText(L("No prices in the last 14 days."))
        frame.empty:Show()
        frame.high:SetText("")
        frame.low:SetText("")
        return frame.used
    end
    frame.empty:Hide()
    local low, high = series.low, series.high
    if high <= low then
        low, high = math.max(0, low - 1), high + 1
    end
    frame.high:SetText(U.money(high))
    frame.low:SetText(U.money(low))
    local span = math.max(1, series.to - series.from)
    local function px(t)
        return (t - series.from) / span * (c.width - c.dot)
    end
    local function py(v)
        return (v - low) / (high - low) * (c.height - c.dot)
    end
    for _, g in ipairs(series.gaps) do
        chartTexture(frame, px(g.from), 0, px(g.to) - px(g.from), c.height, 0.5, 0.5, 0.5, 0.25)
    end
    -- The line: dots a few pixels apart between two days' points, never across a gap.
    local prev
    for _, p in ipairs(series.usual) do
        local x, y = px(p.t), py(p.v)
        if prev and F.Market.seriesJoined(series, prev.t, p.t) then
            local x0, y0 = px(prev.t), py(prev.v)
            local steps = math.max(1, math.floor(math.max(math.abs(x - x0), math.abs(y - y0)) / 2))
            for i = 1, steps - 1 do
                local f = i / steps
                chartTexture(frame, x0 + (x - x0) * f, y0 + (y - y0) * f, 2, 2, 1, 0.82, 0, 0.9)
            end
        end
        chartTexture(frame, x - 1, y - 1, c.dot + 1, c.dot + 1, 1, 0.82, 0, 1)
        prev = p
    end
    -- One dot per scan; at most 300, evenly picked.
    local scans = series.scans
    local every = math.max(1, math.ceil(#scans / 300))
    for i = 1, #scans, every do
        local p = scans[i]
        chartTexture(frame, px(p.t), py(p.v), c.dot, c.dot, 0.25, 0.75, 1, 0.9)
    end
    return frame.used
end
