-- ForeverFlip window: item tooltips and the post price reasons.
-- Moved from UI.lua as it was and loaded after it (ForeverFlip.toc); locals of the
-- earlier UI files come through UI.shared.
local UI = ForeverFlip.UI
local S = UI.shared
local F = S.F
local U = S.U
local L = S.L
local text = S.text
local slotName = S.slotName

local QUOTE_WHY = {
    undercut = "one step below the cheapest seller %s",
    normal = "normal price: the cheapest seller %s asks too much",
    estimate = "usual price; the AH check gives the exact one",
    sales = "what buyers really paid lately; asking prices above it rarely sell",
    median = "bought for a market reset: the median price",
    last = "your last price",
    aux = "auxForever's usual price",
    history = "the item's older market price",
    similar = "the usual price of other versions of the item",
    cost = "guess: your cost plus 25%",
    vendor = "guess: 1.5 x the vendor price",
}
-- "Why <price>: <reason>", grey: the one argument for a sell price, on the tooltip and the Resale
-- panel alike. how: Market.postPrice's reason ("undercut", "sales", "usual"; "normal" and
-- "estimate" read as "usual"); cheapest: the lot undercut; h: the item's history.
function UI.priceWhy(price, how, cheapest, h)
    if not U.finite(price) then
        return nil
    end
    local usual, cap = F.Market.usual(h), F.Market.saleCap(h)
    local text
    if how == "undercut" and U.finite(cheapest) then
        text =
            string.format(L("Why %s: just under the next lot still on sale (%s)."), U.money(price), U.money(cheapest))
    elseif how == "sales" and cap and U.finite(usual) and cap < usual then
        text = string.format(
            L("Why %s: what buyers really paid lately reaches %s; the median asking price %s rarely sells."),
            U.money(price),
            U.money(cap),
            U.money(usual)
        )
    elseif how == "sales" and cap then
        text = string.format(L("Why %s: what buyers really paid lately reaches %s."), U.money(price), U.money(cap))
    elseif (how == "usual" or how == "normal" or how == "estimate") and U.finite(usual) then
        text = string.format(L("Why %s: just under the usual price (%s)."), U.money(price), U.money(usual))
    end
    return text and (UI.C.dim .. text .. "|r") or nil
end

function UI.quoteWhy(q)
    if q.belowFloor then
        return string.format(L("the market %s is below your minimum"), U.money(q.market))
    end
    -- The normal price also stands when nobody else sells the item: there is no seller to name.
    if q.why == "normal" and not q.cheapest then
        return L("normal price: nobody else sells it now")
    end
    local text = L(QUOTE_WHY[q.why] or QUOTE_WHY.estimate)
    if text:find("%%s") then
        return string.format(text, U.money(q.cheapest))
    end
    return text
end

-- "You get each, after the 5% cut" (and the deposits expected to be lost, when there are any).
function UI.netLabel(q)
    local cut = UI.pct(F.Market.CUT)
    if (q.lost or 0) > 0 then
        return string.format(L("You get each, after the %d%% cut and %s lost deposits"), cut, U.money(q.lost))
    end
    return string.format(L("You get each, after the %d%% cut"), cut)
end

-- Money with a sign, green when it gains and red when it loses.
function UI.signed(copper)
    if copper >= 0 then
        return UI.C.good .. "+" .. U.money(copper) .. "|r"
    end
    return UI.C.bad .. U.money(copper) .. "|r"
end

-- Item tooltips: what ForeverFlip knows about the item, for the auction house shown in the header.
-- Each line says where its number comes from, so nothing reads as more certain than it is:
--   prices        usual price (and its age), cheapest seen today, units listed at the last scan
--   sales         units sold per day and the median price of sales seen, once measured
--   yours         stock you bought (and what it cost), your auctions on sale now
--   selling one   the vendor price (the client's Sell Price), the auction house after the cut
--                 and the deposits of the tries it takes to sell, and which pays more
local function tipLine(tooltip, left, right, r, g, b)
    UI.tipPair(tooltip, left, right, r or 0.6, g or 0.6, b or 0.6)
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

-- T31: ForeverFlip's tooltip block is replaced by a short warning once the house's scan data
-- are a day old. Fresh data come either way, and either is enough: a complete full scan in the
-- game (scannedAt; older saved data: peak.at) or a scan of the house brought by the Sync helper
-- (syncScanAt, Raw.importCommunity). Sync is optional. Prices, Sure, Est/day, analytics and advice
-- all come from those data. The game's own lines and other addons' lines are left alone.
UI.STALE_AFTER = 24 * 3600

-- The time of the newest scan data of this house, by whichever way they came; nil when none.
function UI.scanDataAt()
    local market = F.Data.market(F.db, F.Engine.scope())
    local best
    for _, at in ipairs({
        market.scannedAt or (type(market.peak) == "table" and market.peak.at) or false,
        market.syncScanAt or false,
    }) do
        if U.finite(at) and (not best or at > best) then
            best = at
        end
    end
    return best
end

-- nil while the data are fresh; otherwise their time (false when there are none).
function UI.staleData(now)
    local at = UI.scanDataAt()
    if not at then
        return false
    end
    if now - at >= UI.STALE_AFTER then
        return at
    end
    return nil
end

-- The rules around ForeverFlip's part of a tooltip: "=== FOREVER FLIP: <HOUSE> ===" above and
-- "=== X ===" below, so it stands apart from the game's lines and other addons'. Both are centred:
-- ForeverFlip's lines are collected first (UI.tipRecorder), then each rule gets as many "=" on
-- either side as make it as wide as the widest line of the tooltip (the game's lines read through
-- the widget API, ours measured on a hidden font string of our own). Without a measure (no font)
-- the fixed counts below are used.
UI.TIP_RULE = string.rep("=", 11)
UI.TIP_END = string.rep("=", 19) .. " X " .. string.rep("=", 18)
UI.TIP_RULE_MIN = 3 -- "=" on each side at least
UI.TIP_PAIR_GAP = 40 -- pixels between the two halves of a double line (TextRight is anchored 40 px
-- after TextLeft in SharedTooltipTemplates.xml)
UI.TIP_WIDTH_MAX = 420 -- a game line wider than this is wrapping text, not a width to match

-- A stand-in tooltip that only records AddLine and AddDoubleLine, to be replayed on the real one.
function UI.tipRecorder()
    local r = { calls = {} }
    function r.AddLine(self, ...)
        self.calls[#self.calls + 1] = { "AddLine", n = select("#", ...), ... }
    end
    function r.AddDoubleLine(self, ...)
        self.calls[#self.calls + 1] = { "AddDoubleLine", n = select("#", ...), ... }
    end
    return r
end

-- The width of a text in the tooltip's font, nil without a measure.
function UI.tipTextWidth(text)
    if not UI.tipMeter then
        local frame = CreateFrame("Frame")
        frame:Hide()
        UI.tipMeter = frame:CreateFontString(nil, "OVERLAY", "GameTooltipText")
    end
    local meter = UI.tipMeter
    meter:SetText(text or "")
    local w = meter.GetUnboundedStringWidth and meter:GetUnboundedStringWidth() or meter:GetStringWidth()
    if not U.finite(w) then
        return nil
    end
    -- A coin icon is written "|T...:0:0:2:0|t": moved 2 px right, which the measure of a hidden
    -- string leaves out. A price line has up to three of them: the rules came out a sign short.
    for x in tostring(text or ""):gmatch("|T[^|]-:%-?%d+:%-?%d+:(%-?%d+):%-?%d+|t") do
        w = w + math.max(0, tonumber(x) or 0)
    end
    return w
end

-- The widest line already in the tooltip (the game's), read through the widget API only.
local function shownWidth(tooltip)
    local name = tooltip.GetName and tooltip:GetName()
    local count = tooltip.NumLines and tooltip:NumLines()
    local widest = 0
    if type(name) ~= "string" or type(count) ~= "number" then
        return widest
    end
    for i = 1, count do
        local left, right = _G[name .. "TextLeft" .. i], _G[name .. "TextRight" .. i]
        local w = 0
        -- A wrapping line (an item's "Use:" text) reports its unwrapped width and takes whatever
        -- width the tooltip gets: it must not decide the width, or the rules stretch it across
        -- the screen. The same for any line wider than a tooltip ever is.
        local wraps = left and left.CanWordWrap and left:CanWordWrap()
        if left and left:IsShown() and not wraps then
            w = tonumber(left:GetStringWidth()) or 0
        end
        if not wraps and right and right:IsShown() and (right:GetText() or "") ~= "" then
            w = w + UI.TIP_PAIR_GAP + (tonumber(right:GetStringWidth()) or 0)
        end
        if w <= UI.TIP_WIDTH_MAX then
            widest = math.max(widest, w)
        end
    end
    return widest
end

-- A rule: `middle` between "=" signs, as near `target` pixels as the font allows. Signs come in
-- whole widths: the same count on both sides moved the width two signs at a time, so the header and
-- the footer ("X" is narrower than the house name) came out up to a sign apart. Now the right side
-- may hold one sign more than the left, and up to UI.TIP_RULE_PAD spaces around the middle take
-- up what a sign cannot. Returns the "=" on the left and right, the spaces before and after the
-- middle, and the width it measures.
UI.TIP_RULE_PAD = 4
local fits = {}
local function rule(middle, target, eq)
    local id = (UI.tipFont or "") .. "@" .. middle .. "@" .. math.floor(target * 4 + 0.5)
    local f = fits[id]
    if f then
        return f[1], f[2], f[3], f[4], f[5]
    end
    local plain = UI.tipTextWidth(middle) or 0
    local min = 2 * UI.TIP_RULE_MIN
    local base = math.max(min, math.floor((target - plain) / eq))
    local best, gap
    -- Fewer spaces first: they fill only what the signs leave.
    for pad = 0, UI.TIP_RULE_PAD do
        for n = math.max(min, base - 2), base + 2 do
            local l = math.floor(n / 2)
            local before = math.floor(pad / 2)
            local text = string.rep("=", l)
                .. string.rep(" ", before)
                .. middle
                .. string.rep(" ", pad - before)
                .. string.rep("=", n - l)
            local w = UI.tipTextWidth(text) or 0
            if not gap or math.abs(w - target) < gap - 0.01 then
                best, gap = { l, n - l, before, pad - before, w }, math.abs(w - target)
            end
        end
    end
    fits[id] = best
    return best[1], best[2], best[3], best[4], best[5]
end

-- The measure takes the font the tooltip's own lines are drawn in, read through the widget API:
-- measured in the font object GameTooltipText, "=", spaces and letters kept other proportions than
-- in the game's lines, and the header and the X line came out a sign apart however they were fitted.
local function lineOf(tooltip, i)
    local name = tooltip.GetName and tooltip:GetName()
    return type(name) == "string" and _G[name .. "TextLeft" .. i] or nil
end
local function useFontOf(tooltip)
    local line = lineOf(tooltip, 2)
    if not (line and line.GetFont) then
        return
    end
    local ok, font, size, flags = pcall(line.GetFont, line)
    if not ok or type(font) ~= "string" or type(size) ~= "number" then
        return
    end
    UI.tipTextWidth("") -- the meter exists
    local id = font .. ":" .. size .. ":" .. tostring(flags or "")
    if UI.tipFont ~= id and pcall(UI.tipMeter.SetFont, UI.tipMeter, font, size, flags) then
        UI.tipFont = id
    end
end
-- The drawn width of the tooltip's last line, or nil.
local function lastWidth(tooltip)
    local n = tooltip.NumLines and tooltip:NumLines()
    local line = type(n) == "number" and lineOf(tooltip, n)
    local w = line and line.GetStringWidth and line:GetStringWidth()
    return U.finite(w) and w or nil
end

-- How much wider than the header, against the meter, the game draws the X line in the tooltip's
-- font: learned from each tooltip drawn (the widths read back through the widget API) and kept
-- per font between sessions. 0 until a tooltip was drawn.
UI.TIP_SKEW_MAX = 20
function UI.tipSkew()
    local skews = F.db and F.db.tipSkew
    local v = type(skews) == "table" and skews[UI.tipFont or ""]
    return U.finite(v) and v or 0
end
function UI.learnTipSkew(seen)
    if not (F.db and U.finite(seen)) or math.abs(seen) > UI.TIP_SKEW_MAX then
        return
    end
    if type(F.db.tipSkew) ~= "table" then
        F.db.tipSkew = {}
    end
    local font = UI.tipFont or ""
    local old = F.db.tipSkew[font]
    -- Smoothed: one tooltip's rounding does not move the next one's rule.
    F.db.tipSkew[font] = U.finite(old) and old * 0.7 + seen * 0.3 or seen
end

-- Writes ForeverFlip's block into the tooltip: the header, the recorded lines, the footer.
function UI.tipBlock(tooltip, calls, house, colour)
    local head = " FOREVER FLIP: " .. house:upper() .. " "
    local width
    useFontOf(tooltip)
    local eq = UI.tipTextWidth("=")
    if eq and eq > 0 then
        width = shownWidth(tooltip)
        for _, c in ipairs(calls) do
            local w
            if c[1] == "AddDoubleLine" then
                w = (UI.tipTextWidth(c[2]) or 0) + UI.TIP_PAIR_GAP + (UI.tipTextWidth(c[3]) or 0)
            elseif not c[6] then -- a wrapped line takes the width it is given
                w = UI.tipTextWidth(c[2]) or 0
            end
            width = math.max(width, w or 0)
        end
        local headPlain = UI.tipTextWidth(head) or 0
        width = math.max(width, headPlain + 2 * UI.TIP_RULE_MIN * eq)
    end
    local bottom = UI.TIP_END
    local hl, hr, hb, ha = 11, 11, 0, 0
    if width then
        -- Both rules aimed at the lines' width; then both at the wider of the two, so neither
        -- stands out past the other.
        local w1, w2
        hl, hr, hb, ha, w1 = rule(head, width, eq)
        local fl, fr, fb, fa
        fl, fr, fb, fa, w2 = rule(" X ", width, eq)
        local target = math.max(w1, w2)
        -- The game draws the X line wider than the meter says, by more than the header (5 to 6
        -- px in FRIZQT 12, in the trace): the difference learned from the tooltips drawn before
        -- is taken off the X line's aim.
        local skew = UI.tipSkew()
        hl, hr, hb, ha, w1 = rule(head, target, eq)
        fl, fr, fb, fa, w2 = rule(" X ", target - skew, eq)
        UI.tipFit = { head = w1, foot = w2, skew = skew }
        bottom = string.rep("=", fl) .. string.rep(" ", fb) .. " X " .. string.rep(" ", fa) .. string.rep("=", fr)
    end
    tooltip:AddLine(
        UI.C.gold
            .. string.rep("=", hl)
            .. string.rep(" ", hb)
            .. " FOREVER FLIP:|r |cff"
            .. (colour or "ffffff")
            .. house:upper()
            .. "|r "
            .. string.rep(" ", ha)
            .. UI.C.gold
            .. string.rep("=", hr)
            .. "|r"
    )
    local drawnHead = lastWidth(tooltip)
    for _, c in ipairs(calls) do
        tooltip[c[1]](tooltip, unpack(c, 2, c.n + 1))
    end
    tooltip:AddLine(UI.C.gold .. bottom .. "|r")
    local fit, drawnFoot = width and UI.tipFit, lastWidth(tooltip)
    if fit and drawnHead and drawnFoot then
        UI.learnTipSkew((drawnFoot - fit.foot) - (drawnHead - fit.head))
        -- DEV: what the meter expected against what the game drew, header and X line.
        F.Log.trace(
            "tooltip.rules",
            "font %s: header %.1f drawn %.1f, X line %.1f drawn %.1f, skew %.1f",
            tostring(UI.tipFont),
            fit.head,
            drawnHead,
            fit.foot,
            drawnFoot,
            fit.skew
        )
    end
    tooltip:Show()
end

local function staleWarning(tooltip, at)
    local orange = function(text)
        tooltip:AddLine("  " .. text, 1, 0.6, 0.3, true)
    end
    tooltip:AddLine(UI.C.gold .. "ForeverFlip|r  " .. UI.C.warn .. L("data out of date, not shown") .. "|r")
    orange(
        at and string.format(L("Last auction scan data: %s."), UI.age(at))
            or L("No auction scan data of this house yet.")
    )
    orange(L("Run a Full scan, or ForeverFlip Sync and then /reload."))
end

-- T31: the production chain of the item: sell it on the auction house, to a vendor, disenchant it
-- or craft it into something (F.Market.chainRoutes). Kept per item until the next scan data (or
-- UI.CHAIN_KEEP seconds: a merchant's price or a recipe can come meanwhile).
UI.CHAIN_KEEP = 300
UI.chainCache = {}

-- The lowest price of an item on this house now: the newer of the cheapest of today's full scan and
-- the quick scan or sniper browse (Sniper.low, which reads the whole house in a minute). Returns
-- price, time, own (the lowest may be the player's own lot); nil when neither has one.
function UI.lowestFor(history, key, id, now)
    local price, at, own
    local h = key and history[key]
    if type(h) == "table" then
        local today = h.days and h.days[#h.days]
        if today and today.d == math.floor(now / 86400) and U.finite(today.min) and today.min > 0 then
            local market = F.Data.market(F.db, F.Engine.scope())
            price, at = today.min, type(h.scan) == "table" and h.scan.at or market.scannedAt
        end
    end
    local kind = id and F.AH.kindOf(id)
    local low = kind and kind ~= "gear" and F.Sniper.low(id)
    if low and U.finite(low.price) and low.price > 0 and (not U.finite(at) or low.at >= at) then
        price, at, own = low.price, low.at, low.own
    end
    return price, at, own
end

-- The lowest price of a plain (not gear) item by its ID alone.
local function lowestOf(history, id, now)
    local kind = F.AH.kindOf(id)
    if not kind or kind == "gear" then
        return nil
    end
    return UI.lowestFor(history, U.key(kind, id), id, now)
end

-- The recipes the item is a material of (learned, every material priced), best first: { value,
-- name, low } per unit of the item; low counts the product at its lowest auction house price now
-- instead of its usual one (nil when it has none). At most `limit` of them.
function UI.craftRoutes(id, limit, now)
    local history = F.Data.market(F.db, F.Engine.scope()).history
    local unit = F.Crafting.materialCost(history, id)
    now = now or F.Engine.clock()
    local list = {}
    for _, row in ipairs(F.Crafting.profits()) do
        if row.learned and not row.missing then
            local value = F.Market.craftValue(row, id, unit)
            if value and value > 0 then
                local lowValue
                local low = row.out and lowestOf(history, row.out, now)
                if low then
                    local atLow = { value = F.Market.net(low, row.n or 1), cost = row.cost, reagents = row.reagents }
                    lowValue = F.Market.craftValue(atLow, id, unit)
                end
                list[#list + 1] = { value = value, name = row.name, low = lowValue }
            end
        end
    end
    table.sort(list, function(a, b)
        return a.value > b.value
    end)
    for i = #list, (limit or #list) + 1, -1 do
        list[i] = nil
    end
    return list
end

-- The best recipe the item is a material of: { value, name }, or nil.
function UI.craftRoute(id)
    return UI.craftRoutes(id, 1)[1]
end

-- What disenchanting one brings with each material at its lowest auction house price now (after
-- the cut); nil when it cannot be disenchanted or a likely material has no lowest price.
function UI.disenchantLow(id, now)
    local _, _, quality, level, _, _, _, _, _, _, _, classID = U.itemInfo(id)
    local outcomes = F.Disenchant.outcomes(quality, level, classID)
    if not outcomes then
        return nil
    end
    local history = F.Data.market(F.db, F.Engine.scope()).history
    local total = 0
    for _, o in ipairs(outcomes) do
        local price = lowestOf(history, o[1], now)
        if price then
            total = total + F.Market.net(price, 1) * o[2]
        elseif o[2] >= 0.1 then
            return nil
        end
    end
    return math.floor(total)
end

function UI.chainFor(key, id, advice, now, qty)
    local stamp = tostring(UI.scanDataAt())
    local c = UI.chainCache[key]
    local net = advice and (advice.belowFloor and advice.marketNet or advice.net)
    qty = qty or F.Deals.sellQty(nil, key)
    if c and c.stamp == stamp and c.net == net and c.qty == qty and now - c.at < UI.CHAIN_KEEP then
        return c.chain
    end
    -- The one Sure of the item: the units to sell at the price to post (Deals.sellQty), as the
    -- Demand line, the deal line and Selling -> My items.
    local sure
    if advice and U.finite(advice.post) then
        sure = F.Deals.sureAt(key, advice.post, qty, now)
    end
    -- A minimum above the market only lifts the price posted: the route is judged at the market
    -- (as Market.sellRoutes and the Best column), or a vendor item would read as an auction one.
    local chain = F.Market.chainRoutes({
        auction = net,
        sure = sure,
        post = advice and advice.post,
        vendor = advice and advice.vendor,
        disenchant = advice and advice.disenchant,
        craft = UI.craftRoute(id),
    })
    UI.chainCache[key] = { stamp = stamp, at = now, net = net, qty = qty, chain = chain }
    return chain
end

local CHAIN_LABELS = {
    auction = "Auction house, after the cut",
    vendor = "Vendor",
    disenchant = "Disenchant (materials)",
    craft = "Craft",
}

local function chainLabel(r)
    local label = L(CHAIN_LABELS[r.route])
    if r.route == "craft" and r.name then
        label = label .. ": " .. r.name
    elseif r.route == "auction" then
        local sure = U.finite(r.sure) and string.format(L("Sure %d%%"), UI.pct(r.sure))
        if U.finite(r.post) then
            -- The price to post and, on the right, what it brings after the cut.
            label = string.format(L("Auction house at %s, after the cut"), U.money(r.post))
        end
        label = label .. " (" .. (sure or L("Sure unknown")) .. ")"
    end
    return label
end

function UI.chainLines(tooltip, key, id, advice, now, section, grey)
    section("Production chain")
    local chain = UI.chainFor(key, id, advice, now)
    if not chain then
        tooltip:AddLine("  " .. grey(L("No prices for any route yet: run a Full scan.")), 1, 1, 1, true)
        return
    end
    for i, r in ipairs(chain.routes) do
        if i == 1 then
            tipLine(tooltip, "> " .. L("Best") .. ": " .. chainLabel(r), U.money(r.value), 1, 0.82, 0)
        else
            tipLine(tooltip, "  " .. chainLabel(r), U.money(r.value))
        end
    end
end

-- T24: the market reference of an item (F.Market.marketReference): its prices of the last 14 days
-- from the player's own scans and from shared (community) scans, apart, with the cheapest of the
-- last own scan. Only the open house's history is read. Kept per item until the house's scan data,
-- the item's last scans or the day change, or UI.REFERENCE_KEEP seconds pass (the age of the last
-- scan decides whether its cheapest says anything of now).
UI.REFERENCE_KEEP = 300
UI.referenceCache = {}

function UI.referenceFor(key, h, now)
    local scope = F.Engine.scope()
    local stamp = table.concat({
        tostring(scope),
        tostring(UI.scanDataAt()),
        tostring(math.floor(now / 86400)),
        tostring(type(h) == "table" and type(h.scan) == "table" and h.scan.at),
        tostring(type(h) == "table" and type(h.shared) == "table" and h.shared.at),
    }, "|")
    local c = UI.referenceCache[key]
    if c and c.stamp == stamp and now - c.at < UI.REFERENCE_KEEP then
        return c.ref
    end
    local ref = F.Market.marketReference(h, now)
    UI.referenceCache[key] = { stamp = stamp, at = now, ref = ref }
    return ref
end

local function refPercent(x)
    local p = UI.pct(math.abs(x))
    return (x < 0 and "-" or "+") .. p .. "%"
end

local function sourceText(s)
    if (s.n or 0) == 0 then
        return s.seen and string.format(L("no daily prices yet, seen %s"), UI.age(s.seen)) or L("no data")
    end
    return string.format(
        L("median %s · mean %s · %d d · seen %s"),
        U.money(s.median),
        U.money(s.mean),
        s.n,
        s.seen and UI.age(s.seen) or "-"
    )
end

local UNDER_REASONS = {
    no_current = "Undervalued check: no own scan with a price of the item",
    old_scan = "Undervalued check: your last scan of the item is too old",
    no_reliable = "Undervalued check: no reliable sales data",
}

-- The reference as lines { left, right, r, g, b } (colour of the left text; nil = grey).
function UI.referenceRows(ref)
    local rows = {}
    local function add(left, right, r, g, b)
        rows[#rows + 1] = { left = left, right = right or "", r = r, g = g, b = b }
    end
    local c = ref.current
    if c then
        local right = U.money(c.price)
        if c.units then
            right = right .. " · " .. string.format(L("%d listed"), c.units)
        end
        add(string.format(L("Cheapest in your last scan (%s)"), UI.age(c.at)), right, 0.85, 0.85, 0.85)
        if c.vsMedian then
            add(L("against the 14-day median / mean"), refPercent(c.vsMedian) .. " / " .. refPercent(c.vsMean))
        end
    end
    add(L("Your scans"), sourceText(ref.own))
    add(L("Community"), sourceText(ref.community))
    add(L("External: not available (Undermine Exchange has no documented API for WoW Forever)"), "")
    local parts = {}
    for _, t in ipairs(ref.trends) do
        parts[#parts + 1] = string.format(L("%d d %s (%d)"), t.span, t.change and refPercent(t.change) or "-", t.n or 0)
    end
    add(L("Trend (days with a price)"), table.concat(parts, " · "))
    if ref.disagree then
        add(
            string.format(L("Your scans and the community differ by %d%%: the median is uncertain"), UI.pct(ref.gap)),
            "",
            1,
            0.6,
            0.25
        )
    end
    local u = ref.under
    if u.flagged then
        add(string.format(L("%d%% below the 14-day median (information only)"), UI.pct(1 - u.ratio)), "", 0.25, 1, 0.25)
    elseif u.reason == "few_days" then
        add(string.format(L("Undervalued check: needs %d days of prices, has %d"), u.need, u.days), "")
    elseif UNDER_REASONS[u.reason] then
        add(L(UNDER_REASONS[u.reason]), "")
    end
    return rows
end

function UI.referenceLines(tooltip, key, h, now, section, grey)
    section("Market reference (14 days)")
    for _, row in ipairs(UI.referenceRows(UI.referenceFor(key, h, now))) do
        if row.r then
            tipLine(tooltip, "  " .. row.left, row.right, row.r, row.g, row.b)
        else
            tipLine(tooltip, "  " .. grey(row.left), row.right)
        end
    end
end

local function joinMoney(values)
    local parts = {}
    for _, v in ipairs(values) do
        parts[#parts + 1] = U.money(math.floor(v + 0.5))
    end
    return table.concat(parts, " " .. L("or") .. " ")
end

-- A route in a few words: "Auction at 5g", "Vendor at 75c", "Craft: Smelt Silver".
local function shortLabel(r)
    if r.route == "auction" and U.finite(r.post) then
        return string.format(L("Auction at %s"), U.money(r.post))
    elseif r.route == "vendor" and U.finite(r.value) then
        return string.format(L("Vendor at %s"), U.money(math.floor(r.value + 0.5)))
    end
    return chainLabel(r)
end

-- The recommendation: the best route of the production chain, and the routes within 3% of it
-- ("A or B": either is as good; then the item is a close call and the reason is shown).
local function recommendation(chain)
    local best = chain and chain.routes[1]
    if not best or best.unlikely then
        -- Only the auction house is left, and it is unlikely to sell: nothing to recommend.
        return nil, nil, best and best.route, best
    end
    local names = { shortLabel(best) }
    for i = 2, #chain.routes do
        local r = chain.routes[i]
        if r.value >= best.value * 0.97 then
            names[#names + 1] = shortLabel(r)
        end
    end
    return table.concat(names, " " .. L("or") .. " "), best.value, best.route, best, #names > 1
end

-- How many items the tooltip is for: the game's own Sell Price line is for the whole stack
-- (tooltip data, read only); 1 when there is none.
local SELL_PRICE_LINE = 11 -- Enum.TooltipDataLineType.SellPrice
local function stackOf(data, id)
    -- A row of My items shows the units it holds, as the bag's own tooltip of the stack does.
    if U.finite(UI.tooltipCount) and UI.tooltipCount > 1 then
        return math.floor(UI.tooltipCount)
    end
    local kind = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.SellPrice or SELL_PRICE_LINE
    for _, l in ipairs(type(data) == "table" and type(data.lines) == "table" and data.lines or {}) do
        if type(l) == "table" and l.type == kind and U.finite(l.price) and l.price > 0 then
            local unit = F.AH.clientVendorPrice(id) or select(11, U.itemInfo(id))
            if U.finite(unit) and unit > 0 then
                return math.max(1, math.floor(l.price / unit + 0.5))
            end
        end
    end
    return 1
end

-- Item tooltip, in this order (each part only when it has something to say):
--   header       FOREVER FLIP: the house the prices are for
--   Selling      vendor, lowest and median auction prices, craft and disenchant values (and what
--                they bring at the lowest prices now), the best and worst time to buy, and the
--                recommendation (the production chain's best route), then a deal on the list now
--   Demand       the last scan, sales a day, purchases seen, Sure at the post price
--   References   community data, the 14-day median / mean, trends
--   situational  your stock and auctions
local function tooltipLines(tooltip, data)
    if not F.db or not F.db.settings.tooltipPrices or not tooltip.GetItem then
        return
    end
    local _, link = tooltip:GetItem()
    -- Retail 12 hides some tooltips' items (in combat, among others): a secret link cannot be read.
    if F.Compat.secret(link) or type(link) ~= "string" then
        return
    end
    local id = tonumber(link:match("item:(%d+)"))
    local key = id and F.AH.keyFor(id, link)
    if not key then
        return
    end
    local market = F.Data.market(F.db, F.Engine.scope())
    local h = market.history[key]
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
    local now = F.Engine.clock()
    local stale = UI.staleData(now)
    if stale ~= nil then
        staleWarning(tooltip, stale or nil)
        return
    end
    -- The lines are collected first and written by UI.tipBlock, between rules sized to them.
    local target = tooltip
    tooltip = UI.tipRecorder()
    local function section(title)
        tooltip:AddLine(UI.C.head .. L(title) .. "|r")
    end
    local function grey(s)
        return UI.C.dim .. s .. "|r"
    end
    -- The name on the left, everything about it on the right (a note in grey before the value).
    local function line(label, right, note)
        right = right or ""
        if note and note ~= "" then
            right = grey("(" .. note .. ")") .. (right ~= "" and ("  " .. right) or "")
        end
        tipLine(tooltip, "  " .. L(label), right, 0.85, 0.85, 0.85)
    end
    local house, colour = UI.houseName()

    section("Selling")
    local vendor, vendorHow = advice and advice.vendor, advice and advice.vendorHow
    if not vendor then
        local sell = select(11, U.itemInfo(id))
        vendor = U.finite(sell) and sell > 0 and sell or nil
    end
    if vendor then
        -- The client's item data is what merchants pay (AH.vendorPrice); a note only when a merchant
        -- was seen paying another price for it.
        local client = vendorHow == "seen" and F.AH.clientVendorPrice(id)
        -- For the whole stack, as the game's Sell Price line.
        local count = stackOf(data, id)
        local notes = {}
        if count > 1 then
            notes[#notes + 1] = string.format("%d x %s", count, U.money(vendor))
        end
        if client and client ~= vendor then
            notes[#notes + 1] = string.format(L("a merchant paid this; item data says %s"), U.money(client))
        end
        line("Vendor price", U.money(vendor * count), #notes > 0 and table.concat(notes, ", ") or nil)
    end
    local low, lowAt, lowOwn = UI.lowestFor(market.history, key, id, now)
    if low then
        line("Lowest AH price", U.money(low), UI.age(lowAt) .. (lowOwn and (", " .. L("yours")) or ""))
    end
    if usual then
        line(
            "Median AH price",
            U.money(usual),
            UI.age(usualAt) .. (sharer and (", " .. L("shared by") .. " " .. sharer) or "")
        )
        -- What buyers really paid, when it is well under the asking prices: a resale on Deals
        -- counts on this one (Deals.resaleCap), not on the median.
        local cap = F.Market.saleCap(h)
        if cap and cap < usual * 0.9 then
            line("Sales reach", U.money(cap), L("what buyers paid; asking prices are higher"))
        end
    elseif advice and advice.why == "similar" and U.finite(advice.post) then
        -- No price of its own: the one its other versions sell at, as the Sell page suggests.
        line("Median AH price", U.money(advice.post), L("other versions"))
    end
    local crafts = UI.craftRoutes(id, 3, now)
    if #crafts > 0 then
        local values, lows, lower = {}, {}, false
        for _, c in ipairs(crafts) do
            values[#values + 1] = c.value
            if c.low then
                lows[#lows + 1] = c.low
                lower = lower or c.low < c.value
            end
        end
        line("Craft", joinMoney(values), #crafts == 1 and crafts[1].name or nil)
        if lower then
            tipLine(tooltip, "    " .. grey(L("AH lower price")), joinMoney(lows))
        end
    end
    local de = advice and advice.disenchant
    if de then
        line("Disenchant", U.money(de))
        local deLow = UI.disenchantLow(id, now)
        if deLow and deLow < de then
            tipLine(tooltip, "    " .. grey(L("AH lower price")), U.money(deLow))
        end
    end
    local timing = h and F.Market.timing(h, now)
    if timing and timing.ready and timing.spread >= 0.05 then
        tooltip:AddLine(" ")
        line("Best time for buy", slotName(timing.low))
        line("Worst time for buy", slotName(timing.high) .. string.format(" (+%d%%)", UI.pct(timing.spread)))
    end
    -- The deal list is the last open house's (as ForeverFlipAPI.GetDeal): once a neutral house
    -- closes, its deals are not on sale at the faction house the prices above come from.
    local sameHouse = not F.Deals.scope or F.Deals.scope == F.Engine.scope()
    local deal = sameHouse and F.Deals.get(key) or nil
    -- One recommendation, with its reason. A resale on Deals sets the auction price: once its lots
    -- are bought, its exit is what the Sell page will suggest (both Market.postPrice).
    local flip = deal and (deal.mode == "flip" and deal or deal.alt and deal.alt.mode == "flip" and deal.alt) or nil
    local chainAdvice, why = advice, nil
    if flip and U.finite(flip.exit) then
        local at = F.Market.advice(id, key, h, flip.exit)
        if at and advice then
            chainAdvice = setmetatable({ net = at.auction, post = flip.exit, belowFloor = false }, { __index = advice })
        end
        why = UI.exitWhy(flip, h)
    elseif advice and advice.post then
        if advice.belowFloor then
            why = UI.C.dim .. UI.quoteWhy(advice) .. "|r"
        else
            why = UI.priceWhy(advice.post, advice.why, advice.cheapest, h)
                or (advice.why and UI.C.dim .. UI.quoteWhy(advice) .. "|r")
        end
    end
    local sellQty = F.Deals.sellQty(flip, key)
    local best, _, bestRoute, bestEntry, close = recommendation(UI.chainFor(key, id, chainAdvice, now, sellQty))
    if best then
        -- "Auction at 5g"; the reason only when another route pays nearly as much.
        tipLine(tooltip, "  " .. L("Recommendation"), UI.C.gold .. best .. "|r", 1, 0.82, 0)
        if close and bestRoute == "auction" and why then
            tooltip:AddLine("    " .. why, 1, 1, 1, true)
        end
    elseif bestEntry and bestEntry.unlikely then
        tipLine(tooltip, "  " .. L("Recommendation"), UI.C.gold .. L("hold, nothing sells now") .. "|r", 1, 0.82, 0)
        tooltip:AddLine(
            "    "
                .. grey(
                    string.format(
                        L("At %s the auction house is unlikely to sell (Sure %d%%): wait for buyers or a lower price."),
                        U.money(bestEntry.post or 0),
                        UI.pct(bestEntry.sure or 0)
                    )
                ),
            1,
            1,
            1,
            true
        )
    end
    if deal then
        -- T17: this Sure is for every unit the deal leaves you holding (bought now plus held) at
        -- the deal's exit price (Deals.sure); the Demand one is for one unit at the post price.
        local sure = F.Deals.sure(deal, now)
        local right = ""
        if sure and deal.mode == "flip" then
            local held = F.Data.char(F.db, F.Engine.owner()).positions[key]
            right = string.format(
                L("Sure %s to sell all %d at %s"),
                UI.sureText(sure),
                (deal.qty or 1) + (held and held.qty or 0),
                U.money(deal.exit)
            )
        elseif sure then
            right = L("Sure") .. " " .. UI.sureText(sure)
        end
        tipLine(
            tooltip,
            "  " .. string.format(L("Deal now: buy %d, profit %s"), deal.qty or 1, U.money(deal.profit)),
            right,
            0.25,
            1,
            0.25
        )
    end

    if h then
        section("Demand")
        line("Your last scan", U.finite(market.scannedAt) and UI.age(market.scannedAt) or L("none yet"))
        local at = chainAdvice and chainAdvice.net and chainAdvice.post or usual
        if at then
            local s = F.Market.saleability(h, at, now)
            -- T32: the sample behind Est./day and Sure; below the thresholds the reason, not a number.
            local q = F.Market.quality(h, at, now)
            if s.known and not q.reliable then
                line("Estimated sales / day", UI.C.warn .. L("No reliable data") .. "|r")
                tipLine(tooltip, " ", grey(UI.qualityReason(q)))
            elseif s.known then
                line("Estimated sales / day", UI.estimateLimits(q) or string.format("~%.1f", s.perDay))
            else
                line("Estimated sales / day", L("not measured yet (needs two scans)"))
            end
            local e = F.Market.saleEvidence(h, math.floor(at * 0.85))
            line(
                "Recent sales",
                e and string.format(L("%d (%d units)"), e.buys, math.floor(e.units + 0.5)) or L("none seen")
            )
            -- The one Sure of the item: the units to sell (Deals.sellQty) at the recommended price.
            local sure = F.Deals.sureAt(key, at, sellQty, now)
            line(
                "Sure",
                string.format(
                    L("Sells at %s - %s"),
                    U.money(at),
                    sure and (L("Sure") .. " " .. UI.sureText(sure)) or L("Sure unknown")
                )
            )
        end

        section("References")
        local ref = UI.referenceFor(key, h, now)
        local c = ref.community
        line(
            "Community data",
            (c.n or 0) > 0 and string.format(L("median %s · %d d"), U.money(c.median), c.n) or L("no data")
        )
        local all = ref.combined
        if (all.n or 0) > 0 then
            line("14-day median / mean", U.money(all.median) .. " / " .. U.money(all.mean))
        end
        local parts = {}
        for _, t in ipairs(ref.trends) do
            parts[#parts + 1] = t.change and refPercent(t.change) or "-"
        end
        line("Trend 3d / 7d / 14d", table.concat(parts, " / "))
        if ref.disagree then
            tipLine(
                tooltip,
                "  "
                    .. string.format(
                        L("Your scans and the community differ by %d%%: the median is uncertain"),
                        UI.pct(ref.gap)
                    ),
                "",
                1,
                0.6,
                0.25
            )
        end
        if ref.under.flagged then
            tipLine(
                tooltip,
                "  " .. string.format(L("%d%% below the 14-day median (information only)"), UI.pct(1 - ref.under.ratio)),
                "",
                0.25,
                1,
                0.25
            )
        end
    end
    if not h then
        -- Gear with no scan data of its own (one ending nobody sells now): Est./day and Sure of its
        -- other endings, else of gear of about the same price, as My items shows them (~).
        local item = U.parseKey(key)
        local at = chainAdvice and chainAdvice.post or advice and advice.post
        local qty = math.max(1, sellQty or 1)
        local other = item and item.kind == "gear" and F.Deals.siblingEstimate(key, qty, now)
        if not other and item and item.kind == "gear" and U.finite(at) and at > 0 then
            other = F.Deals.peerEstimate(at, qty, now)
        end
        if other then
            section("Demand")
            line("Your last scan", U.finite(market.scannedAt) and UI.age(market.scannedAt) or L("none yet"))
            local from = other.peers and string.format(L("%d gear items of about this price"), other.n or 0)
                or string.format(L("%d other versions"), other.n or 0)
            line("Estimated sales / day", string.format("~%.1f", other.perDay or 0), from)
            if U.finite(at) then
                line(
                    "Sure",
                    string.format(
                        L("Sells at %s - %s"),
                        U.money(at),
                        U.finite(other.sure) and (L("Sure") .. " ~" .. UI.pct(other.sure) .. "%") or L("Sure unknown")
                    ),
                    from
                )
            end
        end
    end
    if (position and position.qty > 0) or onSale > 0 then
        section("Yours")
        if position and position.qty > 0 then
            tipLine(
                tooltip,
                "  " .. L("You hold"),
                string.format(L("%d, paid %s each"), position.qty, U.money(math.floor(position.cost / position.qty)))
                    .. (
                        (position.lost or 0) > 0
                            and (" " .. string.format(L("(%s lost on reposts)"), U.money(position.lost)))
                        or ""
                    ),
                0.5,
                0.8,
                1
            )
        end
        if onSale > 0 then
            tipLine(
                tooltip,
                "  " .. L("On sale by you"),
                string.format(L("%d at %s"), onSale, onSalePrice and U.money(math.floor(onSalePrice)) or "?"),
                0.5,
                0.8,
                1
            )
        end
    end
    UI.tipBlock(target, tooltip.calls, house, colour)
end

function UI.tooltips()
    if UI.tooltipHooked then
        return
    end
    UI.tooltipHooked = true
    local function safe(tooltip, data)
        local ok, err = pcall(tooltipLines, tooltip, data)
        if not ok and F.Engine.report then
            F.Engine.report("tooltip: " .. tostring(err))
        end
    end
    if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if tooltip == GameTooltip or tooltip == ItemRefTooltip then
                safe(tooltip, data)
            end
        end)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", safe)
    end
end
