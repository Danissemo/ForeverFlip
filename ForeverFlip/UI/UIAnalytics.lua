-- ForeverFlip window: Statistics, Analytics and KPI pages.
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
local table_ = S.table_
local footer = S.footer
local gold = S.gold

-- Statistics page ----------------------------------------------------------------------------------
function UI.createStats(p)
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 60)
    -- Each header explains its column when hovered.
    UI.statsTable = table_(list, {
        { "Name", nil, nil, "The item. Click a header to sort by it, click again to reverse." },
        { "Bought", 66, nil, "Units you bought, all time." },
        { "Sold", 60, nil, "Units you sold: on the auction house and to merchants." },
        {
            "In stock",
            70,
            nil,
            "Units bought and not sold yet: in the bags or on sale. Red: not one sold for 3 days or more.",
        },
        {
            "Profit",
            104,
            nil,
            "What the sold units brought after the auction house cut, minus what they cost (lost deposits included). Red: a loss. Units still in stock do not count yet.",
        },
        {
            "Days to sell",
            90,
            nil,
            "How many days a unit took on average from purchase to sale. Lower is better.",
        },
        {
            "Posts sold",
            96,
            nil,
            "Of your posts of the item, the share that sold; the rest expired or were cancelled (lost deposit). Shown after 3 posts.",
        },
    }, 16, function() end)
    UI.statsText = footer(p, 56).text
end

function UI.refreshStats()
    local all = F.Trade.itemStats()
    local stats = UI.statsTable.sort(all, function(s, column)
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
            r.cols[3]:SetText(s.stock > 0 and (s.stale and UI.C.bad .. s.stock .. "|r" or s.stock) or "-")
            if s.sold > 0 then
                r.cols[4]:SetText((s.profit < 0 and UI.C.bad .. "-|r" or "") .. U.money(math.abs(s.profit)))
            else
                r.cols[4]:SetText("-")
            end
            r.cols[5]:SetText(s.days and string.format("%.1f", s.days) or "-")
            r.cols[6]:SetText(s.rate and UI.pctText(s.rate) or "-")
            r.selected:Hide()
            r:Show()
        else
            r.key = nil
            r:Hide()
        end
    end
    -- Every item counts, not only the rows in view (sort returns the scrolled window).
    for _, s in ipairs(all) do
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
-- The market lists, each with a name anyone understands and one line on what to do with it.
local MARKET_VIEWS = {
    { "gaps", "Bargains", "Selling today far below their usual price: click one to check it and buy." },
    { "liquid", "Popular", "Bought the most every day: the easiest to resell." },
    { "falling", "Cheaper", "Their price is dropping: wait before buying, sell yours soon." },
    { "rising", "Dearer", "Their price is rising: a good time to sell what you hold." },
    { "cheapNow", "Buy now", "Usually cheapest at this time of the week: buy now, sell at the time shown." },
    { "sellNow", "Sell now", "Usually dearest at this time of the week: sell now, buy at the time shown." },
    {
        "results",
        "My results",
        "What each item earned or lost in the period chosen above: profit, money in, units sold and return.",
    },
}
-- The list buttons share the row's width: seven at a fixed 96 px ran past the window's edge.
UI.VIEW_GAP = 3
function UI.layoutViewButtons()
    local row = UI.viewRow
    if not row then
        return
    end
    local total = tonumber(row.GetWidth and row:GetWidth() or 0) or 0
    local n = #MARKET_VIEWS
    local width = 96
    if total > 0 then
        width = math.floor((total - 12 - UI.VIEW_GAP * (n - 1)) / n)
    end
    for i, v in ipairs(MARKET_VIEWS) do
        local b = UI.viewButtons[v[1]]
        b:ClearAllPoints()
        b:SetWidth(width)
        b:SetPoint("LEFT", row, "LEFT", 6 + (i - 1) * (width + UI.VIEW_GAP), 0)
        if b.fitLabel then
            b:fitLabel()
        end
    end
end

-- The column names of the market lists and of My results (the table is the same).
local MARKET_HEADERS = { "Usual price", "Cheapest", "Change", "Sells/day" }
local RESULT_HEADERS = { "Profit", "Earned", "Sold", "Return" }

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
    top:SetHeight(196)
    -- Left: the headline (did I earn?), the plain-word lines, a rule, then the items that earned
    -- and lost most and what to do, each label with its text indented beside it. Right: the
    -- chart's title with the period buttons, the chart under them. A rule above the tabs.
    local LEFT_W, LABEL_W = 400, 96
    UI.resultsHead = text(top, "GameFontNormal")
    UI.resultsHead:SetPoint("TOPLEFT", top, "TOPLEFT", 10, -8)
    UI.resultsHead:SetWidth(LEFT_W)
    UI.resultsHead:SetJustifyH("LEFT")
    UI.resultsText = text(top, "GameFontHighlightSmall")
    UI.resultsText:SetPoint("TOPLEFT", UI.resultsHead, "BOTTOMLEFT", 0, -6)
    UI.resultsText:SetWidth(LEFT_W)
    UI.resultsText:SetJustifyH("LEFT")
    UI.resultsText:SetSpacing(3)
    local rule = top:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(1, 0.82, 0, 0.25)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", UI.resultsText, "BOTTOMLEFT", 0, -5)
    rule:SetWidth(LEFT_W)
    UI.resultsPairs = {}
    local above = rule
    -- The labels share one column; each text starts at the same x and wraps under itself, at most
    -- two lines (the block must not run into the tabs).
    for _, id in ipairs({ "best", "worst", "todo" }) do
        local label = text(top, "GameFontHighlightSmall")
        -- Under the rule, then under the text above (which starts LABEL_W + 4 further right).
        label:SetPoint("TOPLEFT", above, "BOTTOMLEFT", id == "best" and 0 or -(LABEL_W + 4), id == "best" and -5 or -3)
        label:SetWidth(LABEL_W)
        label:SetJustifyH("LEFT")
        local value = text(top, "GameFontHighlightSmall")
        value:SetPoint("TOPLEFT", label, "TOPRIGHT", 4, 0)
        value:SetPoint("RIGHT", top, "LEFT", 10 + LEFT_W, 0)
        value:SetJustifyH("LEFT")
        value:SetSpacing(2)
        if value.SetMaxLines then
            value:SetMaxLines(2)
        end
        UI.resultsPairs[id] = { label = label, value = value }
        above = value
    end
    -- KPI lines are fitted to LEFT_W (UI.fitText); the hidden probe measures them.
    UI.kpiWidth = LEFT_W
    UI.kpiProbe = top:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.kpiProbe:Hide()
    UI.periodButtons = {}
    -- Today is the local calendar day so far (Analytics.results with 1 day).
    local PERIODS = { { 1, "Today" }, { 7, "7 days" }, { 30, "30 days" } }
    for i, period in ipairs(PERIODS) do
        local n = period[1]
        local b = button(top, period[2], 64, function()
            UI.analyticsDays = n
            UI.refresh()
        end)
        b:SetPoint("TOPRIGHT", top, "TOPRIGHT", -8 - (#PERIODS - i) * 68, -6)
        UI.periodButtons[n] = b
    end
    -- Profit per day: bars above (profit) or below (loss) a zero line placed so the bars use the
    -- whole height (UI.refreshAnalytics).
    local chart = CreateFrame("Frame", nil, top)
    chart:SetPoint("TOPLEFT", top, "TOPLEFT", 20 + LEFT_W, -50)
    chart:SetPoint("BOTTOMRIGHT", top, "BOTTOMRIGHT", -8, 22)
    -- T32: how well Sure foretold the player's own posts (Analytics.calibration), under the chart.
    UI.calibrationText = text(top, "GameFontDisableSmall")
    UI.calibrationText:SetPoint("BOTTOMLEFT", top, "BOTTOMLEFT", 20 + LEFT_W, 6)
    UI.calibrationText:SetPoint("BOTTOMRIGHT", top, "BOTTOMRIGHT", -8, 6)
    UI.calibrationText:SetJustifyH("LEFT")
    UI.calibrationText:SetWordWrap(false)
    local zero = chart:CreateTexture(nil, "ARTWORK")
    zero:SetColorTexture(1, 1, 1, 0.25)
    zero:SetHeight(1)
    UI.chart, UI.bars, UI.chartZero = chart, {}, zero
    UI.chartTitle = text(top, "GameFontNormalSmall")
    -- Under the period buttons, the chart's whole width: beside them the room was so narrow that
    -- only ".." was left of the title.
    UI.chartTitle:SetPoint("TOPLEFT", top, "TOPLEFT", 20 + LEFT_W, -34)
    UI.chartTitle:SetPoint("RIGHT", top, "RIGHT", -8, 0)
    UI.chartTitle:SetJustifyH("LEFT")
    UI.chartTitle:SetWordWrap(false)
    local tabsRule = top:CreateTexture(nil, "ARTWORK")
    tabsRule:SetColorTexture(1, 0.82, 0, 0.25)
    tabsRule:SetHeight(1)
    tabsRule:SetPoint("BOTTOMLEFT", top, "BOTTOMLEFT", 6, 0)
    tabsRule:SetPoint("BOTTOMRIGHT", top, "BOTTOMRIGHT", -6, 0)

    local views = CreateFrame("Frame", nil, p)
    views:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, 0)
    views:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, 0)
    views:SetHeight(26)
    UI.viewButtons = {}
    UI.viewRow = views
    for _, v in ipairs(MARKET_VIEWS) do
        UI.viewButtons[v[1]] = button(views, v[2], 96, function()
            UI.marketView = v[1]
            UI.refresh()
        end)
    end
    views:SetScript("OnSizeChanged", UI.layoutViewButtons)
    UI.layoutViewButtons()
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", views, "BOTTOMLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 22)
    UI.marketTable = table_(
        list,
        {
            { "Name" },
            -- Cheapest holds "sell: Wed evening" on the timing lists: the widest column.
            { "Usual price", 96 },
            { "Cheapest", 124 },
            { "Change", 64 },
            { "Sells/day", 72 },
        },
        8,
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

-- KPI text that fits its block -------------------------------------------------------------------
-- `shown` gold in U.money's own look (its colour and letter, or the coin picture), no silver.
local function goldOnly(shown)
    local token = U.money(10000):match("^(%S+)") or "1g"
    local color, rest = token:match("^(|c%x%x%x%x%x%x%x%x)(.*)$")
    if color then
        return color .. rest:gsub("^1", shown, 1)
    end
    return (token:gsub("^1", shown, 1))
end

-- A sum shorter at each level, always with its coin: 1 as U.money (1234g 56s), 2 gold only
-- (1234g), 3 thousands (1.2kg) and millions (3.4Mg) once that is shorter.
function UI.compactMoney(copper, level)
    if not U.finite(copper) then
        return "?"
    end
    level = level or 1
    local sign, abs = copper < 0 and "-" or "", math.abs(copper)
    if level <= 1 or abs < 10000 then
        return U.money(copper)
    end
    local gold = math.floor(abs / 10000)
    if level == 2 or gold < 1000 then
        return sign .. goldOnly(tostring(gold))
    end
    local n, unit = gold / 1000, "k"
    if gold >= 1000000 then
        n, unit = gold / 1000000, "M"
    end
    local shown = n >= 100 and tostring(math.floor(n)) or string.format("%.1f", math.floor(n * 10) / 10)
    shown = shown:gsub("%.0$", "")
    return sign .. goldOnly(shown .. unit)
end

-- How wide `line` is drawn in `fs`'s font. The client measures it (GetUnboundedStringWidth on a
-- probe font string of ours); without that answer it is estimated from the letters.
function UI.textWidth(fs, line)
    local probe = UI.kpiProbe
    if probe and fs.GetFont and probe.SetFont then
        local font, size, flags = fs:GetFont()
        if font and size then
            probe:SetFont(font, size, flags)
        end
    end
    if probe and probe.GetUnboundedStringWidth then
        probe:SetText(line)
        local w = probe:GetUnboundedStringWidth()
        if type(w) == "number" and w > 0 then
            return w
        end
    end
    local size = 12
    if fs.GetFont then
        local _, s = fs:GetFont()
        size = tonumber(s) or size
    end
    local plain = tostring(line):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local icons = 0
    plain = plain:gsub("|T.-|t", function()
        icons = icons + 1
        return ""
    end)
    local letters = #plain:gsub("[\128-\191]", "")
    return letters * size * 0.5 + icons * size
end

-- Sets `fs` to the lines `build(level)` gives, each at the first level that fits `width` (times
-- `rows` for text allowed to wrap). When even the shortest is too wide, the font goes down a
-- point at a time to 8, unless `sameSize` keeps the font (lines that sit beside others of the same
-- size, cut at their last row instead). Returns the levels used, for a test.
local baseFonts = setmetatable({}, { __mode = "k" })
function UI.fitText(fs, build, width, rows, levels, sameSize)
    levels, rows = levels or 3, rows or 1
    if fs.GetFont and not baseFonts[fs] then
        local font, size, flags = fs:GetFont()
        if font and size then
            baseFonts[fs] = { font, size, flags }
        end
    end
    local base = baseFonts[fs]
    if base then
        fs:SetFont(base[1], base[2], base[3])
    end
    local built = {}
    for level = 1, levels do
        built[level] = build(level)
    end
    local out, used, tooWide = {}, {}, false
    for i = 1, #built[1] do
        local chosen
        for level = 1, levels do
            if UI.textWidth(fs, built[level][i]) <= width * rows then
                chosen = level
                break
            end
        end
        if not chosen then
            chosen, tooWide = levels, true
        end
        out[i], used[i] = built[chosen][i], chosen
    end
    fs.fitSize = base and base[2]
    if tooWide and base and not sameSize then
        local size = base[2]
        while size > 8 do
            size = size - 1
            fs:SetFont(base[1], size, base[3])
            fs.fitSize = size
            local fits = true
            for i = 1, #out do
                fits = fits and UI.textWidth(fs, out[i]) <= width * rows
            end
            if fits then
                break
            end
        end
    end
    fs:SetText(table.concat(out, "\n"))
    fs.fitLevels = used
    return used
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
    local W = UI.kpiWidth or 400
    if UI.calibrationText then
        local cal, n = F.Analytics.calibration()
        UI.calibrationText:SetText(
            cal
                    and string.format(
                        L("Sure check: %d%% of %d posts sold within 2 days, Sure predicted %d%%"),
                        UI.pct(cal.observed),
                        cal.n,
                        UI.pct(cal.predicted)
                    )
                or string.format(L("Sure check: not enough posts yet (%d of %d)"), n or 0, F.Analytics.CALIBRATION_MIN)
        )
    end
    -- The headline: what the period earned, in green or red.
    UI.fitText(UI.resultsHead, function(level)
        local function M(c)
            return UI.compactMoney(c, level)
        end
        local result = r.profit >= 0 and (UI.C.good .. L("Earned") .. " " .. M(r.profit) .. "|r")
            or (UI.C.bad .. L("Lost") .. " " .. M(-r.profit) .. "|r")
        if days == 1 then
            return { string.format(L("%s today"), result) }
        end
        return {
            string.format(L("%s in %d days (%s a day)"), result, days, M(math.floor(math.abs(r.perDay)))),
        }
    end, W)
    local realm = F.Analytics.realm(days)
    UI.fitText(UI.resultsText, function(level)
        local function M(c)
            return UI.compactMoney(c, level)
        end
        local lines = {
            string.format(L("Spent on purchases: %s (%d buys)"), M(r.spent), r.buys),
            string.format(
                L("Sold: %d times, %s of them with a profit"),
                r.sales,
                r.hitRate and UI.pctText(r.hitRate) or "-"
            ),
        }
        if r.roi then
            lines[#lines + 1] =
                string.format(L("Each 1g you spent brought back %s profit"), M(math.floor(r.roi * 10000 + 0.5)))
        end
        lines[#lines + 1] = string.format(
            L("Still to sell: %s at what it cost%s"),
            M(r.held),
            r.avgDays and string.format(L(", items sell in about %s"), UI.duration(r.avgDays * 86400)) or ""
        )
        if realm.chars > 1 then
            lines[#lines + 1] = string.format(
                L("All %d characters: %s gold (%s in the period)"),
                realm.chars,
                M(realm.gold),
                (realm.gold >= realm.before and "+" or "-") .. M(math.abs(realm.gold - realm.before))
            )
        end
        return lines
    end, W)
    local function names(list, level)
        local out = {}
        for _, item in ipairs(list) do
            out[#out + 1] = (item.name or item.key) .. " " .. UI.compactMoney(math.abs(item.profit), level)
        end
        return table.concat(out, ", ")
    end
    -- What to do now: the one thing that matters most.
    local function tip(level)
        if r.stale > 0 then
            return string.format(
                L("%s of stock unsold for 3+ days: repost it (Selling, Undercuts) or sell to a merchant."),
                UI.compactMoney(r.stale, level)
            )
        elseif r.sales == 0 and r.buys == 0 then
            return L("Nothing bought yet: open Deals, pick a deal with a green Sure, Check price, then Buy.")
        elseif r.profit < 0 then
            return L("You are losing money: buy only deals with a green Sure, and skip the red ones.")
        end
        return L("All good: keep buying deals with a green Sure and post them from Selling, My items.")
    end
    local pairsText = {
        best = {
            UI.C.good .. L("Earned most:") .. "|r",
            function(level)
                return { #r.best > 0 and names(r.best, level) or "-" }
            end,
        },
        worst = {
            UI.C.bad .. L("Lost most:") .. "|r",
            function(level)
                return { #r.worst > 0 and names(r.worst, level) or "-" }
            end,
        },
        todo = {
            UI.C.gold .. L("What to do:") .. "|r",
            function(level)
                return { tip(level) }
            end,
        },
    }
    -- Each value wraps to at most two lines beside its label (LABEL_W 96 + 4), in the font of the
    -- lines above it: a long list of names is cut at the second line rather than shrunk (Lost most
    -- read smaller than the rest).
    for id, pair in pairs(UI.resultsPairs) do
        pair.label:SetText(pairsText[id][1])
        UI.fitText(pair.value, pairsText[id][2], W - 100, 2, nil, true)
    end
    -- Chart.
    UI.chartTitle:SetText(
        days == 1 and L("Profit today, by hour") or string.format(L("Profit a day, last %d days"), days)
    )
    -- Today: a bar an hour (one bar for the whole day filled the chart); longer periods: a bar a day.
    local series = days == 1 and r.hours or r.days
    -- The zero line sits where the gains and losses of the period split the height, so the bars
    -- use all of it.
    local up, down = 0, 0
    for _, d in ipairs(series) do
        up, down = math.max(up, d.profit), math.max(down, -d.profit)
    end
    local height = (UI.chart.GetHeight and UI.chart:GetHeight() or 0)
    height = height > 20 and height or 140
    local range = math.max(1, up + down)
    local zeroY = math.floor(height * down / range + 0.5)
    UI.chartZero:ClearAllPoints()
    UI.chartZero:SetPoint("BOTTOMLEFT", UI.chart, "BOTTOMLEFT", 0, zeroY)
    UI.chartZero:SetPoint("BOTTOMRIGHT", UI.chart, "BOTTOMRIGHT", 0, zeroY)
    local chartWidth = (UI.chart.GetWidth and UI.chart:GetWidth() or 0)
    chartWidth = chartWidth > 20 and chartWidth or 300
    local width = math.floor(chartWidth / #series)
    for i, d in ipairs(series) do
        local bar = UI.bars[i]
        if not bar then
            bar = UI.chart:CreateTexture(nil, "ARTWORK")
            UI.bars[i] = bar
        end
        local h = math.max(1, math.floor(math.abs(d.profit) / range * height))
        bar:ClearAllPoints()
        bar:SetWidth(math.max(2, width - 2))
        bar:SetHeight(h)
        if d.profit >= 0 then
            bar:SetColorTexture(0.25, 0.85, 0.35, 0.9)
            bar:SetPoint("BOTTOMLEFT", UI.chart, "BOTTOMLEFT", (i - 1) * width, zeroY)
        else
            bar:SetColorTexture(0.9, 0.3, 0.3, 0.9)
            bar:SetPoint("TOPLEFT", UI.chart, "BOTTOMLEFT", (i - 1) * width, zeroY)
        end
        bar:Show()
    end
    for i = #series + 1, #UI.bars do
        UI.bars[i]:Hide()
    end
    -- Market lists.
    for id, b in pairs(UI.viewButtons) do
        b:SetEnabled(id ~= UI.marketView)
    end
    if UI.marketView == "results" then
        UI.refreshResults(r)
        return
    end
    for i, label in ipairs(MARKET_HEADERS) do
        UI.marketTable.headers[i + 1]:SetText(L(label))
    end
    local m, working = F.Analytics.market()
    m = m or {}
    local timingView = UI.marketView == "cheapNow" or UI.marketView == "sellNow"
    -- The third column holds the lowest price today, or the best time on the timing lists.
    UI.marketTable.headers[3]:SetText(L(timingView and "Best time" or "Cheapest"))
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
    local about
    for _, v in ipairs(MARKET_VIEWS) do
        if v[1] == UI.marketView then
            about = L(v[3])
        end
    end
    UI.marketText:SetText(
        (about or "") .. "  " .. UI.C.dim .. string.format(L("(%d items watched)"), m.items or 0) .. "|r"
    )
end

-- My results: every item the period's journal names (Analytics.results), in the market table.
function UI.refreshResults(r)
    for i, label in ipairs(RESULT_HEADERS) do
        UI.marketTable.headers[i + 1]:SetText(L(label))
    end
    local list = UI.marketTable.sort(r.items or {}, function(e, column)
        if column == 1 then
            return e.name or nameOf(e.key)
        elseif column == 2 then
            return e.profit
        elseif column == 3 then
            return e.earned
        elseif column == 4 then
            return e.sales
        end
        return e.roi or -math.huge
    end)
    for i, row in ipairs(UI.marketTable.rows) do
        local e = list[i]
        if e then
            local item = U.parseKey(e.key)
            row.key, row.link = e.key, nil
            row.icon:SetTexture(item and icon(item.id) or 134400)
            row.name:SetText(nameOf(e.key))
            row.cols[1]:SetText((e.profit < 0 and UI.C.bad .. "-" .. U.money(-e.profit) .. "|r") or U.money(e.profit))
            row.cols[2]:SetText(e.earned > 0 and U.money(e.earned) or "-")
            row.cols[3]:SetText(e.sales > 0 and tostring(e.sales) or "-")
            row.cols[4]:SetText(e.roi and percent(e.roi) or "-")
            row.selected:Hide()
            row:Show()
        else
            row.key = nil
            row:Hide()
        end
    end
    local empty = UI.marketTable.empty
    if #list == 0 then
        empty:SetText(L("No sales or losses in this period yet."))
        empty:Show()
    else
        empty:Hide()
    end
    local about
    for _, v in ipairs(MARKET_VIEWS) do
        if v[1] == "results" then
            about = L(v[3])
        end
    end
    UI.marketText:SetText(about .. "  " .. UI.C.dim .. string.format(L("(%d items)"), #list) .. "|r")
end

-- Locals later UI files share.
S.slotName = slotName
