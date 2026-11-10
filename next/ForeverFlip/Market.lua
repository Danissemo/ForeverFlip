local F = ForeverFlip
local U = F.Util
local M = {}
F.Market = M

M.CUT = 0.05 -- auction house cut on a sale (faction house)
M.BUCKET = math.log(1.02)
-- Sale levels relative to the scan market value (see recordFlow).
M.LEVELS = { 0.6, 0.75, 0.9, 1.05 }
-- Units per day are smoothed as if PRIOR_HOURS more hours had been watched with no sale: one unit
-- gone in a 15-minute pair is ~5.6 a day, not 96. The prior fades as hours of data add up.
M.PRIOR_HOURS = 4

-- Price histogram of every listing of an item in a full scan, stored flat without a table per
-- bucket: [2b] = units, [2b + 1] = cheapest unit price of bucket b (2% wide buckets).
function M.bucketAdd(buckets, unit, qty)
    local b = 2 * math.floor(math.log(unit) / M.BUCKET)
    local q = buckets[b]
    if q then
        buckets[b] = q + qty
        if unit < buckets[b + 1] then
            buckets[b + 1] = unit
        end
    else
        buckets[b], buckets[b + 1] = qty, unit
    end
end

-- Typical asking price: the price at 30% of the listed volume. Skips the few cheapest units
-- (bargains) and never reaches the expensive tail.
function M.bucketValue(buckets)
    local keys, total = {}, 0
    for b, q in pairs(buckets) do
        if b % 2 == 0 then
            keys[#keys + 1] = b
            total = total + q
        end
    end
    if total == 0 then
        return nil, 0
    end
    table.sort(keys)
    local seen = 0
    for _, b in ipairs(keys) do
        seen = seen + buckets[b]
        if seen >= total * 0.3 then
            return math.floor(buckets[b + 1]), total
        end
    end
end

local function qtyAbove(buckets, price)
    local qty = 0
    for b, q in pairs(buckets) do
        if b % 2 == 0 and buckets[b + 1] >= price then
            qty = qty + q
        end
    end
    return qty
end

-- Sales between two full scans, per price level. Units priced at or above LEVELS[i] x market that
-- left the auction house between two scans (up to 3 hours apart) count as sold at that level.
-- Cheap lots bought by other resellers do not raise the higher levels; expired or cancelled
-- auctions count too (an upper bound) and new listings hide sales (a lower bound). Decays with a
-- 2-day half-life. `h` is the item's saved history table and is updated in place.
function M.recordFlow(h, buckets, market, now)
    local prev = h.scan
    if
        type(prev) == "table"
        and U.finite(prev.at)
        and prev.at < now
        and now - prev.at <= 3 * 3600
        and U.finite(prev.market)
        and type(prev.above) == "table"
    then
        local hours = (now - prev.at) / 3600
        local f = h.flow
        if type(f) ~= "table" or type(f.sold) ~= "table" then
            f = { hours = 0, sold = { 0, 0, 0, 0 }, pairs = 0, at = now }
        end
        local decay = 0.5 ^ (math.max(0, now - (f.at or now)) / (48 * 3600))
        f.hours = f.hours * decay + hours
        for i, level in ipairs(M.LEVELS) do
            local gone = math.max(0, (prev.above[i] or 0) - qtyAbove(buckets, level * prev.market))
            f.sold[i] = (f.sold[i] or 0) * decay + gone
        end
        f.pairs, f.at, f.market = math.min(99, (f.pairs or 0) + 1), now, market
        h.flow = f
    end
    local above = {}
    for i, level in ipairs(M.LEVELS) do
        above[i] = U.finite(market) and qtyAbove(buckets, level * market) or 0
    end
    h.scan = { at = now, market = market, above = above }
end

-- Estimated units per day sold at or above 85% of `price`, rounded to the level that does not
-- overcount. pairs = 0 means not enough scans yet (two scans make one pair).
function M.demandAt(h, price, now)
    local f = h and h.flow
    if
        type(f) ~= "table"
        or type(f.sold) ~= "table"
        or not U.finite(f.market)
        or f.market <= 0
        or not U.finite(price)
        or not U.finite(f.hours)
        or f.hours <= 0
    then
        return { pairs = 0, perDay = 0 }
    end
    local want, level = 0.85 * price / f.market, #M.LEVELS
    for i, x in ipairs(M.LEVELS) do
        if x >= want then
            level = i
            break
        end
    end
    local sold = f.sold[level] or 0
    return { pairs = f.pairs or 0, perDay = sold / (f.hours + M.PRIOR_HOURS) * 24, sold = sold, hours = f.hours }
end

-- Time of the week. Each scan's usual price is compared with the item's long-run baseline; the
-- ratio is averaged per weekday (7) and per part of the day (4: night, morning, day, evening)
-- as two separate factors, so a few weeks of scans are enough. price ~ base x day[w] x part[p].
-- Stored compactly in h.t = { b = baseline, w = {7}, wn = {7}, p = {4}, pn = {4} }.
local function slot(now)
    local t = date("*t", now)
    return t.wday, math.floor(t.hour / 6) + 1
end
M.slot = slot

function M.recordTiming(h, market, now)
    if not U.finite(market) or market <= 0 then
        return
    end
    local t = type(h.t) == "table" and h.t or { w = {}, wn = {}, p = {}, pn = {} }
    h.t = t
    if not U.finite(t.b) or t.b <= 0 then
        t.b = market
        return
    end
    local ratio = math.max(0.2, math.min(5, market / t.b))
    local w, p = slot(now)
    local function add(values, counts, i)
        local n = math.min((counts[i] or 0) + 1, 20)
        values[i] = (values[i] or 1) + (ratio - (values[i] or 1)) / n
        counts[i] = n
    end
    add(t.w, t.wn, w)
    add(t.p, t.pn, p)
    t.b = t.b + (market - t.b) * 0.05
end

-- Pattern of an item: ready when four weekdays and three parts of the day have data. Returns the
-- factor now, the cheapest and dearest slot and the spread between them.
function M.timing(h, now)
    local t = type(h) == "table" and h.t
    if type(t) ~= "table" or type(t.w) ~= "table" or type(t.p) ~= "table" then
        return { ready = false }
    end
    local days, parts = 0, 0
    for i = 1, 7 do
        if (t.wn[i] or 0) >= 1 then
            days = days + 1
        end
    end
    for i = 1, 4 do
        if (t.pn[i] or 0) >= 2 then
            parts = parts + 1
        end
    end
    if days < 4 or parts < 3 then
        return { ready = false, days = days, parts = parts }
    end
    local low, high
    for w = 1, 7 do
        for p = 1, 4 do
            if (t.wn[w] or 0) >= 1 and (t.pn[p] or 0) >= 2 then
                local f = (t.w[w] or 1) * (t.p[p] or 1)
                if not low or f < low.f then
                    low = { f = f, w = w, p = p }
                end
                if not high or f > high.f then
                    high = { f = f, w = w, p = p }
                end
            end
        end
    end
    local w, p = slot(now)
    local current = (t.w[w] or 1) * (t.p[p] or 1)
    return {
        ready = true,
        now = current,
        low = low,
        high = high,
        spread = high.f / low.f - 1,
    }
end

-- Display metadata for the existing demand model. Unknown is not an observed zero; old
-- estimates stay numeric but carry the age of the last usable full-scan pair.
function M.saleability(h, price, now)
    local out = { known = false, pairs = 0, stale = false }
    local f = type(h) == "table" and h.flow
    if type(f) ~= "table" then
        return out
    end
    out.pairs = U.finite(f.pairs) and math.max(0, f.pairs) or 0
    out.at = U.finite(f.at) and f.at or nil
    out.hours = U.finite(f.hours) and f.hours > 0 and f.hours or nil
    if out.at and U.finite(now) then
        out.age = math.max(0, now - out.at)
        out.stale = out.age > 3 * 3600
    end
    if
        out.pairs < 1
        or not out.hours
        or type(f.sold) ~= "table"
        or not U.finite(f.market)
        or f.market <= 0
        or not U.finite(price)
        or price <= 0
        or 0.85 * price / f.market > M.LEVELS[#M.LEVELS]
    then
        return out
    end
    for i = 1, #M.LEVELS do
        if not U.finite(f.sold[i]) or f.sold[i] < 0 then
            return out
        end
    end
    local demand = M.demandAt(h, price, now)
    if U.finite(demand.perDay) and demand.perDay >= 0 then
        out.known, out.perDay = true, demand.perDay
    end
    return out
end

-- Deposit of one auction: the game charges at least 1 silver (seen on WoW Forever); it is returned
-- on a sale and lost when the auction expires. Estimated from the vendor price (Classic rule).
function M.deposit(vendor, units)
    return math.max(100, math.floor((vendor or 0) * 0.15 * (units or 1)))
end

-- Deposits a resale of `qty` units puts at risk: one auction for a commodity stack, one per item.
function M.depositRisk(kind, vendor, qty)
    if kind == "commodity" then
        return M.deposit(vendor, qty)
    end
    return qty * M.deposit(vendor, 1)
end

-- Money left after selling `qty` units at `price` each on the auction house.
function M.net(price, qty)
    local gross = price * qty
    return gross - math.floor(gross * M.CUT + 0.5)
end

-- Lowest legal listing price that returns `cost` for `qty` units after the cut.
function M.breakEven(cost, qty, kind)
    local price = U.stepUp(cost / qty / (1 - M.CUT), kind)
    while M.net(price, qty) < cost do
        price = price + (kind == "commodity" and 1 or 100)
    end
    return price
end

-- Evaluates one item's listings (sorted cheapest first: {unit, qty, ...}).
-- ctx: kind, vendor (vendor sell price or nil), budget (copper), history (saved table or nil),
-- market (typical asking price or nil), now, settings {vendorMinProfit, minProfit, minROI}.
-- Returns the best deal or nil and a short reason.
--
-- Vendor deal: every unit priced below the vendor price, sold to any vendor right away. No cut,
-- no waiting, no market risk.
--
-- Resale: buy every unit below the exit price; the exit is one legal step below the cheapest unit
-- left after buying (a resale above it would not sell before that cheaper lot), never above the
-- typical asking price, and it needs measured sales near the exit price. At most one day of those
-- sales is bought.
function M.evaluate(rows, ctx)
    local s = ctx.settings or {}
    local kind = ctx.kind
    local budget = ctx.budget or 0
    local best, reason = nil, "no_gap"

    if U.finite(ctx.vendor) and ctx.vendor > 0 then
        local qty, cost, used = 0, 0, {}
        for _, r in ipairs(rows) do
            if r.unit >= ctx.vendor then
                break
            end
            local take = r.qty
            if kind == "commodity" then
                take = math.min(take, math.floor((budget - cost) / r.unit))
            elseif cost + r.unit * take > budget then
                take = math.floor((budget - cost) / r.unit)
            end
            if take < 1 then
                reason = "budget"
                break
            end
            qty, cost = qty + take, cost + take * r.unit
            used[#used + 1] = { unit = r.unit, qty = take, auctionID = r.auctionID }
        end
        local profit = qty * ctx.vendor - cost
        if qty > 0 and profit >= (s.vendorMinProfit or 10) then
            best = {
                mode = "vendor",
                qty = qty,
                cost = cost,
                exit = ctx.vendor,
                profit = profit,
                roi = profit / cost,
                maxUnit = used[#used].unit,
                lots = used,
            }
        elseif qty > 0 then
            reason = "small"
        end
    end

    if ctx.vendorOnly then
        return best, best and nil or reason
    end

    -- Resale: try every prefix of the cheapest listings. Each prefix has its own exit price and
    -- needs measured sales at that price; at most one day of those sales is held (units already in
    -- stock count). The deposits are counted as a cost: they are lost if the lots do not sell.
    local market = ctx.market
    local held = ctx.held or 0
    local flipBudget = math.min(budget, ctx.itemBudget or budget)
    local flip
    local qty, cost, used = 0, 0, {}
    for i, r in ipairs(rows) do
        local take = r.qty
        if cost + r.unit * take > flipBudget then
            take = math.floor((flipBudget - cost) / r.unit)
        end
        if take < 1 then
            break
        end
        qty, cost = qty + take, cost + take * r.unit
        used[#used + 1] = { unit = r.unit, qty = take, auctionID = r.auctionID }
        local nextUnit = take < r.qty and r.unit or (rows[i + 1] and rows[i + 1].unit)
        local exit = nextUnit and U.below(nextUnit, kind) or U.stepDown(market or 0, kind)
        if U.finite(market) and market > 0 then
            exit = math.min(exit, U.stepDown(market, kind))
        end
        local profit = exit > r.unit and M.net(exit, qty) - cost - M.depositRisk(kind, ctx.vendor, qty) or 0
        if profit > 0 then
            local d = M.demandAt(ctx.history, exit, ctx.now)
            -- Own results: stock of this item that did not sell lowers the scan estimate.
            d.perDay = d.perDay * (ctx.trust or 1)
            if d.pairs < 1 then
                reason = "collecting"
                break
            end
            local roi = profit / cost
            -- One pair of scans (15 minutes) is a thin sample: at most 2 units until a second.
            local cap = math.max(1, math.floor(d.perDay))
            if d.pairs < 2 then
                cap = math.min(cap, 2)
            end
            if d.perDay < 0.5 or qty + held > cap then
                if reason ~= "small" then
                    reason = held > 0 and d.perDay >= 0.5 and "enough_stock" or "not_selling"
                end
            elseif profit >= (s.minProfit or 100) and roi >= (s.minROI or 0.2) then
                if not flip or profit > flip.profit then
                    flip = {
                        mode = "flip",
                        qty = qty,
                        cost = cost,
                        exit = exit,
                        profit = profit,
                        roi = roi,
                        maxUnit = r.unit,
                        lots = U.copy(used),
                        perDay = d.perDay,
                    }
                end
            else
                reason = "small"
            end
        end
        if take < r.qty or i >= 40 then
            break
        end
    end
    if flip and (not best or flip.profit > best.profit) then
        best = flip
    end
    return best, best and nil or reason
end
