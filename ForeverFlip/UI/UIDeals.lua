-- ForeverFlip window: Deals, Shopping list, Bids and My bids pages.
-- Moved from UI.lua as it was and loaded after it (ForeverFlip.toc); locals of the
-- earlier UI files come through UI.shared.
local UI = ForeverFlip.UI
local S = UI.shared
local F = S.F
local U = S.U
local L = S.L
local text = S.text
local button = S.button
local editbox = S.editbox
local hint = S.hint
local icon = S.icon
local nameOf = S.nameOf
local table_ = S.table_
local dropSelection = S.dropSelection
local footer = S.footer

-- Deals page -------------------------------------------------------------------------------------
local DEAL_ROWS = 13
function UI.createDeals(p)
    UI.filter, UI.dealPage = "all", 1
    UI.dealSort, UI.dealDescending = 5, true
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 120)
    -- The columns every deal shares. A vendor deal is sure money and is read on its own figures:
    -- Qty and Cost are the whole offer on the shelf (an offer too dear to buy is still shown), Buy
    -- at and Sells at are prices of one unit, and Profit is what the deal brings once it is sold.
    local DEAL_COLUMNS = {
        { "Name" },
        { "Qty", 50 },
        { "Buy at", 80 },
        { "Sells at", 80 },
        { "Profit", 80 },
        { "Est./day", 66 },
        { "Sure", 60 },
        { "Status", 92, "LEFT" },
    }
    -- To vendor: the same figures without the resale ones (a vendor deal has no Est./day and no
    -- Sure, it is paid at once) and with Cost, the money the whole lot asks for.
    local VENDOR_COLUMNS = {
        { "Name" },
        { "Qty", 50 },
        { "Buy at", 80 },
        { "Sells at", 80 },
        { "Cost", 86 },
        { "Profit", 86 },
        { "Status", 92, "LEFT" },
    }
    -- A column click sorts by that column, a second click on the same one reverses it. Names start A
    -- to Z; the figures that mean "the bigger the better" start with the largest (Profit, Est./day
    -- and Sure on the general page; Cost and Profit on the vendor page). Status starts with the
    -- actionable deals (its own order, see sortValue). The two layouts number their columns
    -- differently (the vendor page has Cost where the other has Est./day and Sure), so the filter is
    -- remembered with the index.
    local BIG_FIRST = { all = { 5, 6, 7 }, vendor = { 5, 6 } }
    local function onSort(index)
        if UI.dealSort == index and UI.dealSortView == UI.filter then
            UI.dealDescending = not UI.dealDescending
        else
            UI.dealSort, UI.dealSortView = index, UI.filter
            UI.dealDescending = false
            for _, column in ipairs(BIG_FIRST[UI.filter] or BIG_FIRST.all) do
                if index == column then
                    UI.dealDescending = true
                end
            end
        end
        UI.dealPage = 1
        UI.refresh()
    end
    UI.dealTables = {}
    UI.dealTable = table_(list, DEAL_COLUMNS, DEAL_ROWS, function(row)
        UI.selectDeal(row.key)
    end, onSort)
    UI.dealTables.all = UI.dealTable
    UI.vendorTable = table_(list, VENDOR_COLUMNS, DEAL_ROWS, function(row)
        UI.selectDeal(row.key)
    end, onSort)
    UI.dealTables.vendor = UI.vendorTable
    -- Which table is on screen for the chosen filter.
    function UI.dealView()
        return UI.filter == "vendor" and UI.vendorTable or UI.dealTable
    end
    -- Moving between the tables: the one in view shows, the other hides.
    function UI.showDealTable()
        for _, t in pairs(UI.dealTables) do
            t.show(t == UI.dealView())
        end
    end
    UI.showDealTable()
    -- Header tooltips: what Sells at and Est./day are made of. `values` (optional) gives the numbers
    -- of a body written as a format, read when the tooltip opens (the cut depends on the house).
    local function headerTip(header, title, body, values)
        header:SetScript("OnEnter", function(self)
            if GameTooltip then
                local shown = values and string.format(L(body), values()) or L(body)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(L(title) .. "\n\n" .. shown, 1, 1, 1, 1, true)
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
        "The price to sell one unit at: list it at this price on the auction house (a vendor deal: what a merchant pays for one). For a resale it is just below the next other seller, at most the usual price and at most what a quarter of the sales seen reached; only as many units as sell in a day at that price are bought. Profit counts the %d%% cut and the deposits. * means no sales were seen yet: the price is only the asking price (vendor deal: the price less the safety margin).",
        function()
            return UI.pct(F.Market.CUT)
        end
    )
    headerTip(
        UI.dealTable.headers[3],
        "Buy at",
        "The price of one unit: what the deal pays on average for each (several lots may have different prices). Qty times this is the whole cost."
    )
    headerTip(
        UI.dealTable.headers[5],
        "Profit",
        "What the deal earns once every unit sells at its Sells at price, after the cut and the deposits. Sorting by it puts the largest profit first; to weigh it by the chance of a sale, sort by Sure. The line under the table adds the expected sum."
    )
    headerTip(
        UI.dealTable.headers[6],
        "Est./day",
        "Units bought per day at 85% of the Sells at price or more, not a sale probability. Counted from lots seen bought between full scans: a lot that got smaller is a sure sale; a lot that vanished whole counts only when the next scan shows its seller did not post the item again. Expired/cancelled lots, reposts at any price, your own purchases and one-off sweeps (above three times the usual scan pair) are left out.\n\nTwo usable full scans are required. Zero means none was bought; '-' means unknown. Orange: only whole lots were seen, no lot bought in part. Vendor deals need no auction-house resale.\n\nGrey estimates use data older than 3 hours. Checking a current price does not refresh sale history. Short observations are smoothed: one unit bought in 15 minutes counts as about 5-6 a day, not 96."
    )
    headerTip(
        UI.dealTable.headers[7],
        "Sure",
        "How sure the deal is to pay back at its Sells at price: the chance that real buyers take its units at that price within 2 days, while your lot is the cheapest.\n\nFrom the sales seen at 95% of the price or more. Few sales give a low number even when they came fast (four sales in one hour are no promise). A whole lot that vanished counts half (often another reseller, not a buyer); shelves cleared in one go, a rival who undercuts often, stock of the item that did not sell and old sales data lower it.\n\nGreen 70% and more, yellow 40%, red below. Vendor deals: 100% (a merchant pays at once)."
    )
    -- The vendor page has its own headers (Cost in place of Est./day and Sure).
    headerTip(
        UI.vendorTable.headers[5],
        "Cost",
        "The money the whole offer asks for: Qty times Buy at, every lot on the shelf below the vendor price added up. A vendor deal is sure money, so an offer is listed even when the purse cannot pay for all of it; the Status column says so, and Buy then takes the part the money covers."
    )
    headerTip(
        UI.vendorTable.headers[6],
        "Profit",
        "What one unit brings once a merchant has bought it: Sells at less Buy at. No auction house cut and no deposit are counted (a merchant pays at once). The line under the table adds up the whole offers."
    )
    -- The deals scroll like every table (the scrollbar on the right); the line below counts them.
    UI.pageText = text(p, "GameFontHighlightSmall")
    UI.pageText:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 8, -20)

    local bar = footer(p, 92, "GameFontHighlightSmall")
    -- Selected deal details can be longer than the footer. Use the shared scrolling
    -- text block so every line remains reachable.
    UI.dealBox = UI.scrollText(bar, 4, 6, 26)
    UI.dealText = UI.dealBox.text
    UI.cancelButton = button(bar, "Cancel", 96, function()
        F.Trade.cancel()
    end)
    UI.cancelButton:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -6, 4)
    -- One button buys: gear and items in one click; a commodity in two, as the game wants (the
    -- first click asks the price of the whole quantity, the same button then shows "Confirm" and the
    -- total, and the second click buys). UI.confirmButton stays for older key bindings, hidden.
    local function buyClick()
        local op = F.Trade.op
        if op and op.key ~= UI.selected and (op.state == "quote" or op.state == "quoted") then
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
            dropSelection()
            UI.refresh()
        end
    end)
    UI.ignoreButton:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 6, 4)
    -- To vendor: every deal bought click after click (F.Trade.runClick). Each click buys one lot
    -- (a commodity: one click asks the price, the next confirms); the next is checked meanwhile.
    UI.runButton = button(bar, "Buy first", 170, function()
        F.Engine.input()
        local ok, why = F.Trade.runClick()
        if not ok and why and why ~= "run_checking" then
            F.Engine.notify(why)
        end
        UI.refresh()
    end)
    -- On the line above the footer, at the right of "Deals: N": the footer row has no room left.
    UI.runButton:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", -6, 3)
    UI.runStop = button(bar, "Stop", 70, function()
        F.Trade.runStop()
        UI.refresh()
    end)
    UI.runStop:SetPoint("RIGHT", UI.runButton, "LEFT", -4, 0)
    -- A sell price of the player's own for the selected resale, on the same line (the To vendor
    -- page has the Buy first buttons there instead): Check Sure recomputes Sells at, Profit, Est./day
    -- and Sure at that price (F.Deals.checkDeal), Reset brings the deal's own figures back.
    UI.dealCheckReset = button(bar, "Reset", 70, function()
        UI.dealCheck, UI.dealCheckFor = nil, nil
        UI.refresh()
    end)
    UI.dealCheckReset:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", -6, 3)
    UI.dealCheckButton = button(bar, "Check Sure", 110, function()
        UI.checkDeal(UI.dealCheckPrice:GetText())
    end)
    UI.dealCheckButton:SetPoint("RIGHT", UI.dealCheckReset, "LEFT", -4, 0)
    UI.dealCheckPrice = editbox(bar, 90)
    UI.dealCheckPrice:SetPoint("RIGHT", UI.dealCheckButton, "LEFT", -8, 0)
    UI.dealCheckLabel = text(bar, "GameFontNormalSmall")
    UI.dealCheckLabel:SetPoint("RIGHT", UI.dealCheckPrice, "LEFT", -8, 0)
    UI.dealCheckLabel:SetText(L("Sell at"))
    UI.createMedianControls(bar)
end

-- T25: Deals -> Market reset. The strategy's money limits, on the line above the footer: gold an
-- item may take, gold a day, share of the money on hand (0 in either of the last two turns it off).
-- The ordinary limits (spending share, item share, per visit) still apply.
UI.MEDIAN_FIELDS = {
    { "medianItemGold", "Per item, g", "Gold one item may take in this strategy", 1 },
    { "medianDayGold", "Per day, g", "Gold this strategy may spend in a day (0 turns it off)", 1 },
    { "medianShare", "% of gold", "Share of the money on hand this strategy may use, % (0 turns it off)", 100 },
}

local function saveMedianField(box)
    local f = box.field
    local value = tonumber(box:GetText() or "")
    if value and value >= 0 and (f[4] ~= 100 or value <= 100) then
        F.db.settings[f[1]] = value / f[4]
        F.Engine.changed()
    end
    local saved = (tonumber(F.db.settings[f[1]]) or 0) * f[4]
    box:SetText(tostring(math.floor(saved * 100 + 0.5) / 100))
end

function UI.createMedianControls(bar)
    UI.medianWidgets, UI.medianBoxes = {}, {}
    local right = bar
    local anchor = "TOPRIGHT"
    for i = #UI.MEDIAN_FIELDS, 1, -1 do
        local f = UI.MEDIAN_FIELDS[i]
        local e = editbox(bar, i == 3 and 36 or 50)
        e:SetJustifyH("RIGHT")
        e.field = f
        if anchor == "TOPRIGHT" then
            e:SetPoint("BOTTOMRIGHT", right, "TOPRIGHT", -8, 3)
        else
            e:SetPoint("RIGHT", right, "LEFT", -10, 0)
        end
        e:SetScript("OnEnterPressed", function(self)
            saveMedianField(self)
            self:ClearFocus()
            UI.refresh()
        end)
        e:SetScript("OnEditFocusLost", function(self)
            saveMedianField(self)
        end)
        hint(e, f[2], f[3])
        local label = text(bar, "GameFontNormalSmall")
        label:SetPoint("RIGHT", e, "LEFT", -6, 0)
        label:SetText(L(f[2]))
        UI.medianBoxes[i] = e
        UI.medianWidgets[#UI.medianWidgets + 1] = e
        UI.medianWidgets[#UI.medianWidgets + 1] = label
        right, anchor = label, "LEFT"
    end
end

-- Shows the Market reset limits on their page and fills the boxes (not while one is typed in). The
-- page has no switch: 0 in "% of gold" or "Per day" turns it off (Deals.medianOff).
function UI.refreshMedianControls(shown)
    for _, w in ipairs(UI.medianWidgets or {}) do
        w:SetShown(shown)
    end
    if not shown then
        return
    end
    for _, e in ipairs(UI.medianBoxes) do
        if not (e.HasFocus and e:HasFocus()) then
            local saved = (tonumber(F.db.settings[e.field[1]]) or 0) * e.field[4]
            e:SetText(tostring(math.floor(saved * 100 + 0.5) / 100))
        end
    end
end

-- Why the Disenchant page has no deal, and what to do about it (F.Disenchant.status).
local NO_DISENCHANT = {
    unlearned = "This character has not learned Disenchant (Enchanting), so no disenchant deal is looked for. Log in with your enchanter, or learn Enchanting from a trainer.",
    noscan = "No full scan of this auction house yet. Press Full scan: disenchant deals are found in it.",
    noprices = "No disenchanting material has a known price yet (dusts, essences, shards). They are learned from full scans: run one with the materials on the auction house.",
}
function UI.noDisenchantText()
    local why = F.Disenchant.status(F.Scan.last ~= nil)
    if why then
        return L(NO_DISENCHANT[why])
    end
    return string.format(
        L(
            "No gear on the auction house sells now below what its materials bring after the cut, less your minimum profit (%s). Deals appear here after a full scan finds one."
        ),
        U.money(F.Market.thresholds(F.db.settings).minProfit)
    )
end

-- Check Sure on the selected resale at the price typed (`price`, as the price boxes read it).
function UI.checkDeal(price)
    local d = UI.selected and F.Deals.get(UI.selected)
    local value = U.parseMoney(price or "")
    if not d or d.mode ~= "flip" or not value or value <= 0 then
        return false
    end
    UI.dealCheck = { key = d.key, price = value }
    F.Engine.changed()
    UI.refresh()
    return true
end

-- The Buy first button: what the next click does, and how many deals are left.
function UI.refreshRun()
    local shown = UI.filter == "vendor"
    UI.runButton:SetShown(shown)
    UI.runStop:SetShown(shown and F.Trade.run ~= nil)
    if not shown then
        return
    end
    local left = #F.Trade.runTargets()
    local state = F.Trade.runState()
    local op = F.Trade.op
    if state == "confirm" then
        UI.runButton:SetText(L("Confirm") .. " " .. U.money(op.cost))
        UI.runButton:SetEnabled(true)
    elseif state == "ready" then
        UI.runButton:SetText(string.format(L("Buy next (%d left)"), left))
        UI.runButton:SetEnabled(true)
    elseif state == "checking" or state == "busy" then
        UI.runButton:SetText(L("checking..."))
        UI.runButton:SetEnabled(false)
    else
        UI.runButton:SetText(string.format(L("Buy first (%d)"), left))
        UI.runButton:SetEnabled(left > 0 and F.AH.isOpen() and not F.Trade.busy())
    end
end

function UI.selectDeal(key)
    F.Engine.input()
    local op = F.Trade.op
    if op and op.key ~= key and (op.state == "quote" or op.state == "quoted") then
        F.Trade.cancel() -- Confirm must never buy an item other than the selected one
    end
    UI.selected, UI.selectedAt, UI.buyHoverKey = key, F.Engine.clock(), nil
    -- A checked price belongs to its deal: another deal starts from its own figures.
    if UI.dealCheck and UI.dealCheck.key ~= key then
        UI.dealCheck = nil
    end
    if key then
        F.Trade.prepareBuy(key)
    end
    F.Engine.changed()
    UI.refresh()
end

-- Why a resale sells at its price, one line for the Resale panel and the tooltip: the reason
-- Market.postPrice gave (d.exitWhy), the same rule as the Sell page's suggested price.
function UI.exitWhy(d, h)
    if d.mode ~= "flip" or not U.finite(d.exit) then
        return nil
    end
    local how = d.exitWhy
    if not how then
        -- An entry made before exitWhy was kept: read the reason from the prices.
        local usual, cap = F.Market.usual(h), F.Market.saleCap(h)
        how = U.finite(d.exitNext) and U.below(d.exitNext, d.kind) <= d.exit and "undercut"
            or cap and U.finite(usual) and cap < usual and "sales"
            or "usual"
    end
    return UI.priceWhy(d.exit, how, d.exitNext, h)
end

local function dealStatus(d)
    local now = F.Engine.clock()
    F.Deals.fitWallet(d)
    -- A vendor deal is listed as the whole offer even when no part of it fits the purse: the status
    -- says what the click does (Buy then takes the part the money covers, as many units as it buys).
    if d.mode == "vendor" and d.short then
        return UI.C.bad .. L("cannot afford it yet") .. "|r"
    end
    if d.cost > F.Engine.wallet() then
        return UI.C.bad .. L("not enough money") .. "|r"
    end
    -- A check of the last D.FRESH seconds holds: "ready" stays while the background (sniper,
    -- auto check) checks the deal again. A check the player asked for is shown as such.
    local fresh = d.verified and now - d.verified <= F.Deals.FRESH
    local asked = F.Deals.queued[d.key] or F.Deals.search and F.Deals.search.key == d.key and F.Deals.search
    if asked and (asked.source == "manual" or asked.source == nil) then
        fresh = false
    end
    if F.Deals.search and F.Deals.search.key == d.key and not fresh then
        return UI.C.gold .. L("checking...") .. "|r"
    end
    if F.Deals.pending(d.key) and not fresh then
        return UI.C.gold .. L("queued") .. "|r"
    end
    if fresh then
        return UI.C.good .. L("ready") .. "|r"
    end
    if d.verified then
        return UI.C.dim .. L("check again") .. "|r"
    end
    if now - (d.found or now) > 1200 then
        return UI.C.dim .. L("old scan") .. "|r"
    end
    if d.quick then
        return UI.C.dim .. L("from quick scan") .. "|r"
    end
    if d.weak then
        return UI.C.warn .. L("few sales data") .. "|r"
    end
    return UI.C.dim .. L("from scan") .. "|r"
end

-- Return on the money and, for resale, how long the bought units take to sell at the estimate.
-- The second line of a deal UI.dealDetail does not lay out itself (shopping list, disenchant).
local function dealOutlook(d)
    local roi = d.cost > 0 and d.profit / d.cost or 0
    if d.mode == "shop" and d.resell then
        return string.format(
            L(
                "Bought out against an undercut (Selling, Undercuts): with the cheaper lot gone, yours is first again. %d left to buy."
            ),
            d.wanted or d.qty
        )
    elseif d.mode == "shop" then
        return L("Bought for your own use: it stays out of Post next bought.")
    elseif d.mode == "disenchant" then
        return L("Estimate from the Classic disenchanting table and the usual material prices.")
    end
    return string.format(L("Return %d%%."), UI.pct(roi))
end

local function saleEstimate(d, history, now)
    if d.mode ~= "flip" then
        return { known = false }
    end
    local e = F.Deals.saleability(d.key, history[d.key], d.exit, now, F.Deals.sellQty(d))
    if not e.known then
        -- No figure of its own: the item's other endings (gear), marked as an approximation.
        local other = F.Deals.siblingEstimate(d.key, F.Deals.sellQty(d), now)
        if other then
            e.known, e.perDay, e.sibling = true, other.perDay, other.n
        end
    end
    return e
end

-- The deal's Sure, or the one of the item's other endings when it has none (approx = true).
function UI.dealSure(d, now)
    local sure = F.Deals.sure(d, now)
    if U.finite(sure) or not d or (d.mode ~= "flip" and d.mode ~= "median") then
        return sure, false
    end
    local other = F.Deals.siblingEstimate(d.key, F.Deals.sellQty(d), now)
    return other and other.sure, other ~= nil and U.finite(other.sure)
end

-- Sure as the pages show it: an approximation from other endings greyed, with "~".
function UI.dealSureText(d, now)
    local sure, approx = UI.dealSure(d, now)
    if approx then
        return UI.C.dim .. "~" .. UI.pct(sure) .. "%|r"
    end
    return UI.sureText(sure)
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
    local unsure = d.mode == "vendor" and d.vendorHow == "estimate"
        or d.mode == "flip" and F.Market.saleCap(history[d.key]) == nil
    -- The mark goes in front: the sums stay aligned on the right edge.
    return (unsure and UI.C.dim .. "*|r " or "") .. U.money(unitExit(d))
end

-- Sure (Deals.sure) as a percentage: green from 70%, yellow from 40%, red below.
function UI.sureText(sure)
    if not U.finite(sure) then
        return "-"
    end
    local pct = UI.pct(sure)
    local color = sure >= 0.7 and UI.C.good or sure >= 0.4 and UI.C.gold or UI.C.bad
    return color .. pct .. "%|r"
end

-- Sample quality (T32, F.Market.quality): what an Est./day or a Sure rests on. Below the
-- thresholds the pages show "No reliable data" and the reason instead of the number.
local QUALITY_REASONS = {
    no_data = "no lots compared yet: two full scans are needed",
    flow_only = "only lots that disappeared were seen (expired and cancelled lots look the same)",
    few_pairs = "too few scan pairs compared yet",
    few_hours = "too few hours watched yet",
    stale = "the sales data is more than three days old",
    legacy = "measured by an older version; new scans will update it",
}
function UI.qualityReason(q)
    return L(QUALITY_REASONS[q and q.reason or "no_data"] or QUALITY_REASONS.no_data)
end

function UI.noReliable(q)
    return UI.C.warn .. L("No reliable data") .. "|r: " .. UI.qualityReason(q)
end

local function rate(v)
    if not U.finite(v) then
        return "-"
    end
    return v < 0.05 and "0" or string.format("%.1f", v)
end

-- Est./day as every page shows it: the same number (F.Deals.saleability at the price, one
-- formula; thin gear data leans on similar gear), the same format, and "~" before it while the sample is below the T32 thresholds
-- (UI.noReliable says why). A thin sample still gives the best estimate there is (sales over the
-- hours watched plus M.PRIOR_HOURS, which pulls a few early sales towards 0); hiding it on one page
-- and showing it on another made two answers to one question.
function UI.perDayText(perDay, q)
    if not U.finite(perDay) then
        return "-"
    end
    if q and not q.reliable then
        return UI.C.warn .. "~|r" .. rate(perDay)
    end
    return rate(perDay)
end

-- "Est./day 3.2", units a day sold near the price; nil without a figure at the price. The 80%
-- limits are not shown: two more numbers to read for no decision of the player's.
function UI.estimateLimits(q)
    if not q or not U.finite(q.perDay) then
        return nil
    end
    return string.format(L("Est./day %s"), rate(q.perDay))
end

-- "Sure 64%": one number, the same on every page (its 80% limits are no longer shown).
function UI.sureLimitsText(sure)
    if not U.finite(sure) then
        return "-"
    end
    return string.format(L("Sure %d%%"), UI.pct(sure))
end

-- "6 scan pairs, 2.5 hours: reliable" or the reason it is not.
function UI.sampleLine(q)
    if not q then
        return nil
    end
    return string.format(
        L("%d scan pairs, %s hours: %s"),
        q.pairs or 0,
        string.format("%.1f", U.finite(q.watched) and q.watched or 0),
        q.reliable and L("reliable") or UI.qualityReason(q)
    )
end

-- What the Sure number of a resale is made of, in one line.
function UI.sureSentence(d, now)
    local sure, parts = F.Deals.sure(d, now)
    if not sure or type(parts) ~= "table" then
        return nil
    end
    if parts.flow then
        return string.format(
            L(
                "|cffffd100Sure|r %s: only lots that disappeared are known yet (%d near this price in %.1f h), no purchase confirmed: at most %d%% until two full scans track the lots."
            ),
            UI.sureText(sure),
            math.floor(parts.units + 0.5),
            parts.hours,
            UI.pct(F.Market.FLOW_SURE_MAX)
        )
    end
    local line = string.format(
        L(
            "|cffffd100Sure|r %s: chance real buyers take %d at this price in %d h (%d bought at 95%% of it or more in %.1f h watched; %d%% real buyers)."
        ),
        UI.sureText(sure),
        d.qty,
        math.floor(parts.selling + 0.5),
        math.floor(parts.units + 0.5),
        parts.hours,
        UI.pct(parts.real)
    )
    local extra = {}
    if parts.rival > 0 and parts.selling < F.Market.SURE_HOURS - 0.5 then
        extra[#extra + 1] =
            string.format(L("a rival undercuts about every %d h"), math.max(1, math.floor(1 / parts.rival + 0.5)))
    end
    if parts.sweep < 1 then
        extra[#extra + 1] = L("shelves cleared in one go lower it")
    end
    if parts.fresh < 0.95 then
        extra[#extra + 1] = string.format(L("sales data %d h old"), math.floor(parts.age / 3600))
    end
    if extra[1] then
        line = line .. " " .. table.concat(extra, "; ") .. "."
    end
    return line
end

local MODE_LABELS = { vendor = "vendor", shop = "shopping list", disenchant = "disenchant", bid = "bid" }
-- The cheap column's word: a vendor deal carries its warning there, so the warning is seen in the
-- list itself rather than only in the selected deal's lines.
local function modeText(d)
    if d.mode == "vendor" and d.refused then
        return L("vendor, refuses")
    end
    return L(MODE_LABELS[d.mode] or d.mode)
end
-- Est./day: grey when the data is old, orange when no lot was seen bought in part at the price
-- (only whole lots that vanished, confirmed by the next scan: the weaker evidence).
local function estimateText(d, estimate, h, price, now)
    if d.mode ~= "flip" then
        return modeText(d)
    elseif not estimate.known then
        return "-"
    end
    price = price or d.exit
    local value = rate(estimate.perDay)
    if estimate.sibling then
        return UI.C.dim .. "~" .. value .. "|r"
    end
    local q = h and U.finite(price) and F.Market.quality(h, price, now) or nil
    local mark = q and not q.reliable and "~" or ""
    if estimate.stale then
        return UI.C.dim .. mark .. value .. "|r"
    end
    local e = h and U.finite(price) and F.Market.saleEvidence(h, 0.85 * price)
    if e and e.sure == 0 then
        return UI.C.warn .. mark .. value .. "|r"
    end
    return (mark ~= "" and UI.C.warn .. mark .. "|r" or "") .. value
end

-- The sales an estimate rests on, in words: units, buys, how sure, prices (UI.saleEvidenceLine).
function UI.saleEvidenceLine(h, floor)
    local seen = UI.C.gold .. L("Seen") .. "|r"
    local e = h and F.Market.saleEvidence(h, floor)
    if not e then
        return seen .. " " .. L("No purchase seen at this price yet.")
    end
    local line = string.format(
        L("%s %d purchases, %d units (%d from lots bought in part, %d whole lots)  ·  paid %s - %s, median %s"),
        seen,
        e.buys,
        math.floor(e.units + 0.5),
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
    if d.mode == "shop" and d.resell then
        -- The same figure as the buy out on Undercuts: what the units bring once resold, after the cut.
        return string.format(
            L("Buy %d for %s and resell at %s with your auction: %s after the %d%% cut once they sell."),
            d.qty,
            U.money(d.cost),
            U.money(d.resell),
            UI.signed(d.profit),
            UI.pct(F.Market.CUT)
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
    return string.format(
        L("Buy %d for %s; list at %s each. Profit after the %d%% cut: +%s."),
        d.qty,
        U.money(d.cost),
        U.money(d.exit),
        UI.pct(F.Market.CUT),
        U.money(d.profit)
    )
end

-- A span of time in words: "40 min", "3.5 h", "2.1 days".
function UI.duration(seconds)
    if not U.finite(seconds) or seconds < 0 then
        return "?"
    end
    local hours = seconds / 3600
    if hours < 1 then
        return string.format(L("%d min"), math.max(1, math.floor(hours * 60 + 0.5)))
    elseif hours < 48 then
        return string.format(L("%.1f h"), hours)
    end
    return string.format(L("%.1f days"), hours / 24)
end

-- The lines of a Check Sure (F.Deals.checkAt): what the price gives, and a plain warning when too
-- few sales were seen to judge it, instead of a figure that reads as certain.
function UI.checkLines(c)
    -- T32: below the sample thresholds the figures are not shown as numbers.
    local q = c.quality
    local unreliable = q and not q.reliable
    local perDay = c.sale and c.sale.known and UI.perDayText(c.sale.perDay, q) or "-"
    local line = UI.C.info
        .. L("Check")
        .. "|r "
        .. string.format(
            L("at %s each: Sure %s, about %s a day sell, %s after the cut"),
            U.money(c.price),
            -- Too few sales to trust: the figure is still shown, marked "?", so a new price visibly
            -- moves it.
            unreliable and (U.finite(c.sure) and UI.sureText(c.sure) .. "?" or "-") or UI.sureText(c.sure),
            perDay,
            U.money(c.net)
        )
    if c.profit then
        line = line .. L("  ·  ") .. L("Profit") .. " " .. UI.signed(math.floor(c.profit + 0.5))
    end
    local lines = { line }
    if unreliable then
        lines[#lines + 1] = UI.noReliable(q)
    elseif q then
        local shown = {}
        shown[#shown + 1] = UI.estimateLimits(q)
        if U.finite(c.sure) then
            shown[#shown + 1] = UI.sureLimitsText(c.sure)
        end
        shown[#shown + 1] = UI.sampleLine(q)
        lines[#lines + 1] = UI.C.dim .. table.concat(shown, "  ·  ") .. "|r"
    end
    if c.thin then
        lines[#lines + 1] = UI.C.warn
            .. L("Too few sales were seen at this price to judge it: these figures are a guess, not a promise.")
            .. "|r"
    end
    lines[#lines + 1] =
        L("Only this check uses the price: market data and the deal stay as they were. Reset goes back.")
    return lines
end

local function gold(s)
    return UI.C.gold .. L(s) .. "|r"
end

-- The selected deal under the table, one subject per line, each line led by its subject:
--   Buy / Sell / Profit   what it costs, where it goes, what it brings
--   Demand                buyers a day at the price, how long the units take, how old the data is
--   Seen                  the purchases the demand rests on
--   Sure                  how sure the resale is to pay back (UI.sureSentence)
-- What a resale is worth on average (Market.expectedProfit: its profit times Sure, less the
-- deposits lost when it does not sell) and the return a day on the money it ties up until its
-- units sell at `perDay` (Market.dayReturn). nil without a Sure.
function UI.expectedLine(d, perDay)
    if not U.finite(d.ev) or not U.finite(d.profit) then
        return nil
    end
    local line = string.format(
        L("%s %s on average (profit times Sure, less lost deposits)"),
        gold("Expected"),
        UI.signed(math.floor(d.ev + 0.5))
    )
    local daily, days = F.Market.dayReturn(d.ev, d.cost, d.qty, perDay)
    if daily then
        line = line
            .. "  ·  "
            .. string.format(
                L("%s%% a day on the money over %s"),
                string.format("%.1f", daily * 100),
                UI.duration(days * 86400)
            )
    end
    return line
end

-- T25: a resale below the median: what it buys, the median it relists at, the profit after the
-- cut and the deposits, and its risk (Sure with its limits, the sales sample behind them).
function UI.medianDetail(d, roi, each)
    local lines = {
        string.format(
            L("%s %d x %s = %s  ·  %s at %s each (usual price of %d days)"),
            gold("Buy"),
            d.qty,
            U.money(each),
            U.money(d.cost),
            gold("Relist"),
            U.money(d.exit),
            d.days or 0
        ),
        string.format(
            L("%s %s (%d%%) after the %d%% cut and %s of deposits at risk"),
            gold("Profit"),
            UI.signed(d.profit),
            roi,
            UI.pct(F.Market.CUT),
            U.money(d.risk or 0)
        ),
    }
    lines[#lines + 1] = UI.expectedLine(d, d.perDay)
    local risk = gold("Risk") .. " " .. UI.sureLimitsText(d.sure)
    if not U.finite(d.sure) then
        local other = F.Deals.siblingEstimate(d.key, d.qty, F.Engine.clock())
        if other then
            risk = gold("Risk")
                .. " "
                .. string.format(
                    other.peers and L("about Sure %s, Est./day %.1f from %d gear items of about this price")
                        or L("about Sure %s, Est./day %.1f from %d other endings of the item"),
                    U.finite(other.sure) and (UI.pct(other.sure) .. "%") or "-",
                    other.perDay,
                    other.n
                )
        end
    end
    local limits = UI.estimateLimits(d.quality)
    if limits then
        risk = risk .. "  ·  " .. limits
    end
    lines[#lines + 1] = risk
    if d.quality then
        lines[#lines + 1] = UI.C.dim .. UI.sampleLine(d.quality) .. "|r"
    end
    if d.weak then
        lines[#lines + 1] = UI.C.warn
            .. L(
                "Few sales data: the item's sales are not measured reliably yet (two scan pairs and enough hours). Reset only when every lot under the price is at most a day of sales."
            )
            .. "|r"
    end
    lines[#lines + 1] = string.format(
        L(
            "Market reset: every lot under the usual price is bought (%d lots, the cheapest up to %s), so your relist is the cheapest left. All or nothing: at most three days of the item's sales and %d lots. Others can list under you later: the risk is the range above."
        ),
        d.lots and #d.lots or 0,
        U.money(d.maxUnit or d.exit or 0),
        F.Market.RESET_MAX_LOTS
    )
    return lines
end

function UI.dealDetail(d, estimate, h, now)
    local roi = d.cost > 0 and UI.pct(d.profit / d.cost) or 0
    local each = math.floor(d.cost / math.max(1, d.qty) + 0.5)
    if d.strategy == "median" then
        return UI.medianDetail(d, roi, each)
    end
    if d.mode == "vendor" then
        local offer = d.offer or d
        local lines = {
            string.format(
                L("%s %d x %s = %s  ·  %s %s each  ·  %s %s (%d%%), no risk"),
                gold("Offer"),
                offer.qty or 0,
                U.money(math.floor((offer.cost or 0) / math.max(1, offer.qty or 1) + 0.5)),
                U.money(offer.cost or 0),
                gold("Merchant pays"),
                U.money(d.exit),
                gold("Profit"),
                UI.signed(offer.profit or d.profit),
                offer.cost and offer.cost > 0 and UI.pct((offer.profit or 0) / offer.cost) or 0
            ),
        }
        -- What this click buys, when it is not the whole offer (the money in the bags, or a limit).
        if d.short then
            lines[#lines + 1] = string.format(
                L(
                    "The money in the bags cannot buy any of it yet: %s is needed. The offer stays listed; press Check price later."
                ),
                U.money(offer.cost or 0)
            )
        elseif (offer.qty or 0) > (d.qty or 0) then
            lines[#lines + 1] = string.format(
                L("%s buys the %d units the money covers now (of %d on the shelf): %s. The rest needs %s more."),
                gold("Buy"),
                d.qty or 0,
                offer.qty or 0,
                U.money(d.cost or 0),
                U.money(math.max(0, (offer.cost or 0) - (d.cost or 0)))
            )
        end
        if d.vendorHow == "estimate" then
            lines[#lines + 1] = L("The vendor price counts the safety margin of Settings → Safety.")
        end
        if d.refused then
            lines[#lines + 1] = L("A merchant has refused this item before: check that it can be sold before buying.")
        end
        if d.kind ~= "commodity" then
            lines[#lines + 1] = L("Items are bought one auction per click; the next lot is checked ahead.")
        end
        return lines
    end
    if d.mode ~= "flip" then
        return { dealSentence(d), dealOutlook(d) }
    end
    local lines = {
        string.format(
            L("%s %d x %s = %s  ·  %s at %s each  ·  %s %s (%d%%) after the %d%% cut"),
            gold("Buy"),
            d.qty,
            U.money(each),
            U.money(d.cost),
            gold("Sell"),
            U.money(d.exit),
            gold("Profit"),
            UI.signed(d.profit),
            roi,
            UI.pct(F.Market.CUT)
        ),
    }
    lines[#lines + 1] = UI.expectedLine(d, estimate and estimate.known and estimate.perDay)
    local why = UI.exitWhy(d, h)
    if why then
        lines[#lines + 1] = why
    end
    local floor = U.finite(d.exit) and math.floor(0.85 * d.exit) or nil
    -- T32: the sample behind Demand and Sure. Below the thresholds the same numbers as the columns,
    -- Demand marked "~" (Sure "?"), and the reason under them.
    local q = U.finite(d.exit) and F.Market.quality(h, d.exit, now) or nil
    local thin = q and not q.reliable and (q.reason ~= "no_data" or (estimate and estimate.known))
    if estimate and estimate.known then
        local line = string.format(
            L("%s %s a day at %s or more"),
            gold("Demand"),
            UI.perDayText(estimate.perDay, thin and q or nil),
            U.money(floor or 0)
        )
        if estimate.perDay > 0 then
            line = line
                .. "  ·  "
                .. string.format(L("%d sell in about %s"), d.qty, UI.duration(d.qty / estimate.perDay * 86400))
        end
        if estimate.age then
            line = line
                .. "  ·  "
                .. string.format(L("data %s old"), UI.duration(estimate.age))
                .. (estimate.stale and L(" (old data)") or "")
        end
        lines[#lines + 1] = line
    elseif not thin then
        lines[#lines + 1] = gold("Demand")
            .. " "
            .. L("Sale estimate unavailable: collect two full scans with usable price data.")
    end
    if thin then
        lines[#lines + 1] = UI.noReliable(q)
        if q.watched then
            lines[#lines + 1] = UI.C.dim .. UI.sampleLine(q) .. "|r"
        end
    end
    lines[#lines + 1] = UI.saleEvidenceLine(h, floor)
    local sure = UI.sureSentence(d, now)
    if sure then
        lines[#lines + 1] = sure
    end
    if q and q.reliable then
        local shown = {}
        shown[#shown + 1] = UI.estimateLimits(q)
        local s = F.Deals.sure(d, now)
        if s then
            shown[#shown + 1] = UI.sureLimitsText(s)
        end
        shown[#shown + 1] = UI.sampleLine(q)
        lines[#lines + 1] = UI.C.dim .. table.concat(shown, "  ·  ") .. "|r"
    end
    return lines
end

function UI.refreshDeals()
    local list = F.Deals.visible(UI.filter)
    local now = F.Engine.clock()
    local history = F.Data.market(F.db, F.Engine.scope()).history
    -- The vendor filter has its own columns (Cost instead of Est./day and Sure), so the page uses
    -- one table at a time and the sort and window work on that one.
    UI.showDealTable()
    local view = UI.dealView()
    local vendor = view == UI.vendorTable
    local estimates, sures = {}, {}
    -- Sure is costly (a confidence model per deal): every deal needs it only to sort by it; else
    -- the rows in view ask for theirs below (and the selected deal's details for its own).
    local bySure = not vendor and UI.dealSort == 7
    for _, d in ipairs(list) do
        estimates[d.key] = saleEstimate(d, history, now)
        if bySure then
            sures[d.key] = UI.dealSure(d, now)
        end
    end
    -- The figures the two layouts share. The general page keeps the columns it always had (Status,
    -- the last one, falls through to the state ranking below); the vendor page has one column fewer
    -- and its fifth is the collection cost, its sixth the profit of one unit (Sells at - Buy at).
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
            -- The profit the column shows: sorting by the expected value (profit times Sure) put a
            -- 271g row above a 580g one, and the column looked unsorted. Sure has its own column.
            return vendor and (d.offer and d.offer.cost or d.cost) or d.profit
        elseif field == 6 then
            return vendor and (unitExit(d) - unitCost(d)) or estimates[d.key].perDay
        elseif field == 7 and not vendor then
            return sures[d.key]
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
        if (not vendor and (UI.dealSort == 6 or UI.dealSort == 7)) and (av == nil) ~= (bv == nil) then
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
    view.setSort(UI.dealSort, UI.dealDescending)
    UI.dealSorted = list -- Check all goes down the page as sorted (UI.order)
    -- Buy first takes the top row of the To vendor table as it is sorted now (F.Trade.runTargets).
    if vendor then
        local order = {}
        for i, d in ipairs(list) do
            order[d.key] = i
        end
        UI.vendorOrder = order
    end
    if UI.dealPage == 1 then
        view.offset, UI.dealPage = 0, nil -- a new filter or sort starts at the top
    end
    -- Check Sure: the selected resale at a price of the player's own. The check is kept by key, so
    -- it stays through a sort and a refresh; it goes with the selection, or when the deal is gone.
    local check
    local selectedDeal = UI.selected and F.Deals.get(UI.selected)
    if UI.dealCheck and (not selectedDeal or selectedDeal.key ~= UI.dealCheck.key) then
        UI.dealCheck = nil
    end
    if UI.dealCheck and not vendor and selectedDeal.mode == "flip" then
        local result = F.Deals.checkDeal(selectedDeal, UI.dealCheck.price, now)
        if result then
            check = { key = selectedDeal.key, price = UI.dealCheck.price, result = result }
        end
    end
    local shown = view.window(list)
    for i, r in ipairs(view.rows) do
        local d = shown[i]
        if d then
            r.key, r.link = d.key, d.link
            r.icon:SetTexture(icon(d.id))
            local name = nameOf(d.key, d.link)
            -- All lists a lot that pays both ways once, by its better route: the other one is named
            -- beside it (the Resale and To vendor pages each list it with its own figures).
            if (UI.filter or "all") == "all" and d.alt then
                name = name .. " " .. UI.C.good .. L(d.alt.mode == "vendor" and "+ vendor" or "+ resale") .. "|r"
            end
            r.name:SetText(name)
            if vendor then
                -- The whole offer on the shelf, its price a unit, and the money it asks for: a deal
                -- too dear for the purse is still read here (the money of the click is in Cost).
                local o = d.offer or d
                r.cols[1]:SetText(o.qty or 0)
                r.cols[2]:SetText(U.money(unitCost(d)))
                r.cols[3]:SetText(sellsAtText(d, history))
                r.cols[4]:SetText(U.money(o.cost or 0))
                -- One unit, the difference of the two price columns; the line under the table adds
                -- up the whole offers.
                r.cols[5]:SetText(U.money(unitExit(d) - unitCost(d)))
                r.cols[6]:SetText(dealStatus(d))
            elseif check and check.key == d.key then
                -- The selected resale at the price checked (blue), its figures from F.Deals.checkDeal.
                r.cols[1]:SetText(d.qty)
                r.cols[2]:SetText(U.money(unitCost(d)))
                r.cols[3]:SetText(UI.C.info .. U.money(check.price) .. "|r")
                r.cols[4]:SetText(U.money(math.floor(check.result.profit + 0.5)))
                r.cols[5]:SetText(estimateText(d, check.result.sale, history[d.key], check.price, now))
                r.cols[6]:SetText(UI.sureText(check.result.sure) .. (check.result.thin and UI.C.warn .. "?|r" or ""))
                r.cols[7]:SetText(dealStatus(d))
            else
                r.cols[1]:SetText(d.qty)
                r.cols[2]:SetText(U.money(unitCost(d)))
                r.cols[3]:SetText(sellsAtText(d, history))
                r.cols[4]:SetText(U.money(d.profit))
                r.cols[5]:SetText(estimateText(d, estimates[d.key], history[d.key], d.exit, now))
                r.cols[6]:SetText(UI.dealSureText(d, now))
                r.cols[7]:SetText(dealStatus(d))
            end
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
    -- The totals: the vendor page counts the whole offers on the shelf (what is on offer, not only
    -- what the purse covers), every other page the deals as its rows buy them.
    local cost, profit, expected = 0, 0, 0
    for _, d in ipairs(list) do
        local o = vendor and (d.offer or d) or d
        cost, profit = cost + (o.cost or 0), profit + (o.profit or 0)
        expected = expected + (not vendor and U.finite(d.ev) and d.ev or (o.profit or 0))
    end
    local totals = ""
    if #list > 0 then
        totals = L("  ·  ") .. string.format(L("all: cost %s, profit %s"), U.money(cost), U.money(profit))
        if not vendor and math.floor(expected) < profit then
            totals = totals
                .. string.format(
                    L(", expected %s"),
                    (expected < 0 and "-" or "") .. U.money(math.abs(math.floor(expected + 0.5)))
                )
        end
    end
    UI.pageText:SetText(string.format(L("Deals: %d"), #list) .. totals)
    local empty = view.empty
    if #list == 0 then
        if UI.filter == "disenchant" and (not F.Scan.busy() or F.Disenchant.status(true)) then
            empty:SetText(UI.noDisenchantText())
        elseif UI.filter == "median" and F.Deals.medianOff() then
            empty:SetText(UI.noMedianText())
        elseif F.Scan.busy() then
            empty:SetText(L("The full scan is being processed. Deals appear when it ends."))
        elseif not F.Scan.last then
            empty:SetText(
                L(
                    "Press Full scan. The addon reads every auction of the house (once per 15 minutes) and lists:\n- lots cheaper than a vendor pays for them (no risk);\n- lots far below the next seller of an item that really sells (resale)."
                )
            )
        elseif UI.filter == "median" then
            empty:SetText(UI.noMedianText(F.Scan.last.stats))
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
        local lines = UI.dealDetail(d, estimates[d.key] or saleEstimate(d, history, now), history[d.key], now)
        if check and check.key == d.key then
            local first = UI.checkLines(check.result)
            for _, line in ipairs(lines) do
                first[#first + 1] = line
            end
            lines = first
        end
        UI.dealBox.set(lines, d.key)
    else
        UI.dealBox.set({ L("Select a deal. Its price is checked on the auction house before you can buy.") }, "")
    end
    UI.checkButton:SetEnabled(d ~= nil and not F.Deals.pending(d.key) and not F.Trade.busy() and not F.Scan.blocking())
    UI.ignoreButton:SetEnabled(d ~= nil)
    -- The price box starts at the deal's own Sells at; Reset puts it back.
    local canCheck = not vendor and d ~= nil and d.mode == "flip"
    local disenchant = UI.filter == "disenchant"
    -- Market reset checks Sure as Resale does; its money limits are on Settings -> General.
    for _, w in ipairs({ UI.dealCheckLabel, UI.dealCheckPrice, UI.dealCheckButton, UI.dealCheckReset }) do
        w:SetShown(not vendor and not disenchant)
    end
    UI.refreshMedianControls(false)
    local typing = UI.dealCheckPrice.HasFocus and UI.dealCheckPrice:HasFocus()
    if not canCheck then
        if not typing then
            UI.dealCheckPrice:SetText("")
        end
        UI.dealCheckFor = nil
    elseif not check and UI.dealCheckFor ~= d.key and not typing then
        UI.dealCheckPrice:SetText(U.plainMoney(unitExit(d)))
        UI.dealCheckFor = d.key
    end
    UI.dealCheckButton:SetEnabled(canCheck)
    UI.dealCheckReset:SetEnabled(check ~= nil)
    UI.refreshRun()
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
local SHOP_ROWS = 15 -- 24 + 15 x 20 = 324 of the 332 px above the 100 px footer area (page 432)
function UI.createShop(p)
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 100)
    UI.shopTable = table_(
        list,
        {
            { "Name" },
            { "Up to", 90 },
            { "Qty", 50 },
            { "Cheapest", 100, nil, "The cheapest lot seen today; - when the item was not scanned today." },
            { "Status", 120, "LEFT" },
        },
        SHOP_ROWS,
        function(row)
            UI.shopSelected = row.key
            UI.refresh()
        end
    )
    -- T26: compact. The two-line note on top, the item row right under it, and the price, quantity,
    -- Add and Remove on one row (Remove had a row of its own, with an empty band above the inputs).
    local bar = footer(p, 96)
    UI.shopText = bar.text
    local itemLabel = text(bar, "GameFontNormal")
    itemLabel:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 8, 38)
    itemLabel:SetText(L("Item (Shift-click a link or type a name)"))
    UI.shopItem = editbox(bar, 220)
    UI.shopItem:SetPoint("LEFT", itemLabel, "RIGHT", 8, 0)
    local maxLabel = text(bar, "GameFontNormal")
    maxLabel:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 8, 10)
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
            if F.Shopping.saved(UI.shopSelected) then
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
        local e = F.Shopping.saved(key)
        rows[#rows + 1] = { key = key, name = e.name, max = e.max, qty = e.qty }
    end
    for _, b in ipairs(F.Shopping.blockedKeys()) do
        rows[#rows + 1] = { key = b.key, name = b.name, blocked = true }
    end
    local day = math.floor(F.Engine.clock() / 86400)
    for _, e in ipairs(rows) do
        local h = history[e.key]
        local last = h and h.days and h.days[#h.days]
        local d = F.Deals.get(e.key)
        -- The last daily record is the item's last day seen, maybe days ago: today's only by its day.
        e.cheap = last and last.d == day and last.min or nil
        e.state = e.blocked and 3 or (d and d.mode == "shop") and 1 or 2
    end
    rows = UI.shopTable.sort(rows, function(e, column)
        return ({ e.name or e.key, e.max, e.qty, e.cheap, e.state })[column]
    end)
    for i, r in ipairs(UI.shopTable.rows) do
        local e = rows[i]
        if e then
            local item = U.parseKey(e.key)
            local d = F.Deals.get(e.key)
            r.key = e.key
            r.icon:SetTexture(icon(item and item.id))
            r.name:SetText(e.name or nameOf(e.key))
            r.cols[1]:SetText(e.max and U.money(e.max) or "-")
            r.cols[2]:SetText(e.qty or (e.blocked and "" or L("any")))
            r.cols[3]:SetText(e.cheap and U.money(e.cheap) or "-")
            r.cols[4]:SetText(
                e.blocked and UI.C.dim .. L("ignored") .. "|r"
                    or d and d.mode == "shop" and UI.C.good .. L("for sale now") .. "|r"
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
local BID_ROWS = 15 -- 24 + 15 x 20 = 324 of the 336 px above the 96 px footer area (page 432)
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
            { "Sure", 60 },
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
    -- Check Sure for the selected bid at a sell price of the player's own, as on Resale: the price
    -- box starts at the item's usual price, Reset brings the bid's own figures back.
    UI.bidCheckLabel = text(bar, "GameFontNormalSmall")
    UI.bidCheckLabel:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 8, 9)
    UI.bidCheckLabel:SetText(L("Sell at"))
    UI.bidCheckPrice = editbox(bar, 90)
    UI.bidCheckPrice:SetPoint("LEFT", UI.bidCheckLabel, "RIGHT", 8, 0)
    UI.bidCheckButton = button(bar, "Check Sure", 110, function()
        UI.checkBid(UI.bidCheckPrice:GetText())
    end)
    UI.bidCheckButton:SetPoint("LEFT", UI.bidCheckPrice, "RIGHT", 6, 0)
    UI.bidCheckPrice:SetScript("OnEnterPressed", function(self)
        UI.checkBid(self:GetText())
        self:ClearFocus()
    end)
    UI.bidCheckReset = button(bar, "Reset", 70, function()
        UI.bidChecked, UI.bidCheckFor = nil, nil
        UI.refresh()
    end)
    UI.bidCheckReset:SetPoint("LEFT", UI.bidCheckButton, "RIGHT", 4, 0)
end

local function bidOf(key)
    for _, c in ipairs(F.Bids.current()) do
        if c.key == key then
            return c
        end
    end
end

-- One unit of a bid at the item's usual price (the price box's start), or its worth.
local function bidUnitPrice(c)
    local item = U.parseKey(c.key)
    local h = F.Data.market(F.db, F.Engine.scope()).history[c.key]
    local usual = h and F.Market.usual(h)
    if U.finite(usual) and usual > 0 then
        return U.stepDown(usual, item and item.kind)
    end
    return math.floor((c.value or 0) / math.max(1, c.count or 1))
end

-- Sure, sales and profit of the selected bid sold again at `price` (one unit, as typed).
function UI.checkBid(price)
    local c = UI.bidSelected and bidOf(UI.bidSelected)
    local value = U.parseMoney(price or "")
    if not c or not value or value <= 0 then
        return false
    end
    UI.bidChecked = { key = c.key, price = value }
    F.Engine.changed()
    UI.refresh()
    return true
end

function UI.bidCheckResult(c, now)
    local check = UI.bidChecked
    if not check or not c or check.key ~= c.key then
        return nil
    end
    local o = F.Bids.offer(c.key)
    local p = F.Data.char(F.db, F.Engine.owner()).positions[c.key]
    return F.Deals.checkAt(c.key, check.price, c.count or 1, o and o.bid or c.bid, 0, p and p.qty or 0, now)
end

function UI.refreshBids()
    local now = F.Engine.clock()
    local list = UI.bidTable.sort(F.Bids.current(), function(c, column)
        local o = F.Bids.offer(c.key)
        if column == 5 then
            return F.Bids.sure(c, now) or -1
        end
        return ({
            nameOf(c.key),
            o and o.bid or c.bid,
            c.value,
            o and o.profit or c.profit,
            nil,
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
            local sure, approx = F.Bids.sure(c, now)
            r.cols[4]:SetText(approx and (UI.C.dim .. "~" .. UI.pct(sure) .. "%|r") or UI.sureText(sure))
            r.cols[5]:SetText(
                o and UI.C.good .. L("ready") .. "|r"
                    or F.Deals.pending(c.key) and UI.C.gold .. L("checking...") .. "|r"
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
        local age = last and last.at and UI.age(last.at)
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
                        "No bid is worth it now. The last full scan was %s: its auctions ending soon are over or were not worth a bid. A new full scan finds new ones."
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
        -- A bid placed in the game's own window may have no name yet (its item data not loaded).
        local latest = open[1].name or open[1].key and nameOf(open[1].key) or "?"
        lines[#lines + 1] =
            string.format(L("Your open bids: %d (latest: %s, %s)."), #open, latest, U.money(open[1].amount))
    end
    -- Check Sure: the selected bid at the player's price, above the explanation it replaces.
    local selectedBid = UI.bidSelected and bidOf(UI.bidSelected)
    if UI.bidChecked and (not selectedBid or UI.bidChecked.key ~= selectedBid.key) then
        UI.bidChecked = nil
    end
    local result = UI.bidCheckResult(selectedBid, now)
    if result then
        local checked = UI.checkLines(result)
        for i = 2, #lines do
            checked[#checked + 1] = lines[i]
        end
        lines = checked
    end
    UI.bidText:SetText(table.concat(lines, "\n"))
    local typing = UI.bidCheckPrice.HasFocus and UI.bidCheckPrice:HasFocus()
    if not selectedBid then
        if not typing then
            UI.bidCheckPrice:SetText("")
        end
        UI.bidCheckFor = nil
    elseif not result and UI.bidCheckFor ~= selectedBid.key and not typing then
        UI.bidCheckPrice:SetText(U.plainMoney(bidUnitPrice(selectedBid)))
        UI.bidCheckFor = selectedBid.key
    end
    UI.bidCheckButton:SetEnabled(selectedBid ~= nil)
    UI.bidCheckReset:SetEnabled(result ~= nil)
    local selected = UI.bidSelected
    UI.bidButton:SetEnabled(selected ~= nil and F.Bids.offer(selected) ~= nil)
    UI.bidCheck:SetEnabled(selected ~= nil and not F.Deals.pending(selected))
end

-- My bids page (Shopping list) -------------------------------------------------------------------
-- Every bid of the player: leading, outbid (with the next bid the house takes), won or lost, and
-- whether answering an outbid pays (F.Bids.mine, F.Bids.maxBid).
local MY_BID_STATUS = {
    leading = { UI.C.good, "leading" },
    outbid = { UI.C.bad, "outbid" },
    ended = { UI.C.gold, "ended" },
    won = { UI.C.good, "won" },
    lost = { UI.C.dim, "lost" },
}
local MY_BID_ADVICE = {
    rebid = { UI.C.good, "bid %s" },
    buyout = { UI.C.info, "buy out %s" },
    hold = { UI.C.white, "keep" },
    let_go = { UI.C.dim, "let it go" },
    no_money = { UI.C.warn, "not enough money" },
}
local MY_BID_ROWS = 15 -- as the Bids page: 324 of 336 px
function UI.createMyBids(p)
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 96)
    UI.myBidTable = table_(
        list,
        {
            { "Name" },
            { "Qty", 50 },
            { "My bid", 80 },
            { "Next bid", 80 },
            { "Worth", 80 },
            { "Status", 70, "LEFT" },
            { "Advice", 110, "LEFT" },
        },
        MY_BID_ROWS,
        function(row)
            UI.myBidSelected = row.auctionID
            UI.refresh()
        end
    )
    local bar = footer(p, 92, "GameFontHighlightSmall")
    UI.myBidText = bar.text
    local function answer(how)
        if UI.myBidSelected then
            local ok, why = F.Bids.answer(UI.myBidSelected, how)
            if not ok then
                F.Engine.notify(why)
            end
        end
    end
    UI.myBidBuyout = button(bar, "Buy out", 110, function()
        answer("buyout")
    end)
    UI.myBidBuyout:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -6, 4)
    UI.myBidAgain = button(bar, "Bid again", 120, function()
        answer("rebid")
    end)
    UI.myBidAgain:SetPoint("RIGHT", UI.myBidBuyout, "LEFT", -4, 0)
    UI.myBidRefresh = button(bar, "Refresh", 100, function()
        F.Bids.liveDue = 0
    end)
    UI.myBidRefresh:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 6, 4)
end

function UI.refreshMyBids()
    local order = { outbid = 1, leading = 2, ended = 3, won = 4, lost = 5 }
    local list = UI.myBidTable.sort(F.Bids.mine(), function(b, column)
        return ({ b.name or "", b.qty, b.mine, b.next, b.value, order[b.status] or 9, b.profit })[column]
    end)
    local selected
    for i, r in ipairs(UI.myBidTable.rows) do
        local b = list[i]
        if b then
            r.auctionID, r.key = b.auctionID, b.key
            r.icon:SetTexture(icon(b.id))
            r.name:SetText(b.name or nameOf(b.key or ""))
            r.cols[1]:SetText(b.qty)
            r.cols[2]:SetText(b.mine and U.money(b.mine) or "-")
            r.cols[3]:SetText(b.next and U.money(b.next) or "-")
            r.cols[4]:SetText(b.value and U.money(b.value) or "-")
            local st = MY_BID_STATUS[b.status] or { "", b.status or "" }
            r.cols[5]:SetText(st[1] .. L(st[2]) .. "|r")
            local ad = b.advice and MY_BID_ADVICE[b.advice]
            r.cols[6]:SetText(ad and ad[1] .. string.format(L(ad[2]), b.price and U.money(b.price) or "") .. "|r" or "")
            if b.auctionID == UI.myBidSelected and b.live then
                r.selected:Show()
                selected = b
            else
                r.selected:Hide()
            end
            r:Show()
        else
            r.auctionID, r.key = nil, nil
            r:Hide()
        end
    end
    local empty = UI.myBidTable.empty
    if #list == 0 then
        empty:SetText(
            L(
                "Your bids appear here while the auction house is open: those placed from Deals, Bids and those placed in the game's own window."
            )
        )
        empty:Show()
    else
        empty:Hide()
    end
    local lines = {}
    if selected then
        local s = F.db.settings
        if selected.value and selected.maxBid then
            lines[#lines + 1] = string.format(
                L(
                    "Worth to you %s (what %d brings: the vendor price, or the usual price after the cut and deposit). Worth bidding up to %s: that keeps your minimum profit %s and return %d%%."
                ),
                U.money(selected.value),
                selected.qty,
                U.money(math.max(0, selected.maxBid)),
                U.money(F.Market.thresholds(s).minProfit),
                UI.pct(F.Market.thresholds(s).minROI)
            )
        end
        if selected.advice == "rebid" then
            lines[#lines + 1] = string.format(
                L("Outbid. Bidding %s again brings %s if you win; if you are outbid again the money comes back."),
                U.money(selected.price),
                U.money(selected.profit or 0)
            )
        elseif selected.advice == "buyout" then
            lines[#lines + 1] = string.format(
                L("Buying out for %s ends it now with %s profit: hours are left for others to bid more."),
                U.money(selected.price),
                U.money(selected.profit or 0)
            )
        elseif selected.advice == "let_go" then
            lines[#lines + 1] = string.format(
                L(
                    "Outbid past its worth: the next bid %s leaves less than your minimum. Let it go; your money is back by mail."
                ),
                U.money(selected.next or 0)
            )
        elseif selected.advice == "hold" then
            lines[#lines + 1] =
                L("You lead. If someone bids more, your money comes back and this page shows whether to answer.")
        end
    else
        lines[#lines + 1] =
            L("Select a bid: an outbid one shows whether bidding again still pays, from what the item brings you.")
    end
    UI.myBidText:SetText(table.concat(lines, "\n"))
    -- Only a bid still on the house can be answered: an ended one (gone from the list, its mail not
    -- read yet) has no auction left to bid on or buy out.
    local open = selected ~= nil and (selected.status == "leading" or selected.status == "outbid")
    UI.myBidAgain:SetEnabled(open and selected.status == "outbid" and selected.next ~= nil and F.AH.isOpen())
    UI.myBidBuyout:SetEnabled(open and selected.buyout ~= nil and F.AH.isOpen())
    UI.myBidRefresh:SetEnabled(F.AH.isOpen())
end

-- Locals later UI files share.
S.gold = gold
