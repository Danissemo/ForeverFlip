local F = ForeverFlip
local U = F.Util
local M = {}
F.Market = M

M.CUT = 0.05 -- auction house cut on a sale; set per auction house by F.Engine (15% on a neutral house)
M.BUCKET = math.log(1.02)
-- Sale levels relative to the scan market value (see recordFlow).
M.LEVELS = { 0.6, 0.75, 0.9, 1.05 }
-- Units per day are smoothed as if PRIOR_HOURS more hours had been watched with no sale: one unit
-- gone in a 15-minute pair is ~5.6 a day, not 96. The prior fades as hours of data add up.
M.PRIOR_HOURS = 4

-- What Market needs to know from the rest of the addon, handed in by Core (Engine.wireMarket), so
-- Market itself reaches no game-facing module. Unwired (Market loaded alone), each answers
-- "unknown": no item kind, no vendor price, no sale rate, Auto's duration unknown, the clock at 0.
M.env = {
    kindOf = function() end, -- AH.kindOf(id)
    vendorPrice = function() end, -- AH.vendorPrice(id, true)
    clientVendorPrice = function() end, -- AH.clientVendorPrice(id)
    depositFn = function() end, -- AH.depositFn(id, kind, d)
    saleRate = function() end, -- Trade.rate(name)
    durationFor = function() end, -- Trade.durationFor(key, qty, price)
    durationHours = function() end, -- Trade.DURATION_HOURS[d]
    durationSetting = function() end, -- the duration setting
    canDisenchant = function() end, -- Disenchant.canDisenchant()
    disenchantValue = function() end, -- Disenchant.value(id)
    clock = function()
        return 0
    end,
}

function M.use(env)
    for k, fn in pairs(env) do
        M.env[k] = fn
    end
end

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

-- The profit thresholds of the settings, each with its default when unset: the one place the rest
-- of the addon reads minProfit, minROI and vendorMinProfit from. Data.DEFAULTS takes its defaults
-- from here (Market reaches no other module).
M.THRESHOLDS = {
    minProfit = 100, -- copper per resale deal
    minROI = 0.2, -- resale return on the money spent
    vendorMinProfit = 10, -- copper per unit of a vendor deal
}
function M.thresholds(s)
    s = s or {}
    local d = M.THRESHOLDS
    return {
        minProfit = s.minProfit or d.minProfit,
        minROI = s.minROI or d.minROI,
        vendorMinProfit = s.vendorMinProfit or d.vendorMinProfit,
    }
end

-- The most to pay for what is worth `value` once bought (money it brings: a merchant's price, the
-- auction net after the cut and the deposit, a disenchant value), the one rule of Bids, Sniper,
-- Disenchant and the vendor deals:
--   vendor        value - vendorMinProfit (at least 1c): the setting is per unit
--   other routes  both the minimum profit and the minimum return: min(value - minProfit,
--                 value / (1 + minROI))
-- `perUnit`: `value` is one unit of a deal whose size is not known yet (the Sniper's filter), so
-- only the return is asked here; the minimum profit is judged on the whole deal later.
function M.maxBuy(value, route, s, perUnit)
    if not U.finite(value) or value <= 0 then
        return nil
    end
    local t = M.thresholds(s)
    if route == "vendor" then
        return value - math.max(1, t.vendorMinProfit)
    end
    local byReturn = value / (1 + math.max(0, t.minROI))
    if perUnit then
        return math.floor(byReturn)
    end
    return math.floor(math.min(value - t.minProfit, byReturn))
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
-- `sold` ({ [price] = units }, optional): the sales the lot comparison confirmed for this pair of
-- scans. When given, units sold above each level come from it instead of the units that went
-- missing, which also counts auctions cancelled, expired or moved to another price.
function M.recordFlow(h, buckets, market, now, sold)
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
        -- Hours watched, not decayed: what a level that never saw a unit go was watched for (the
        -- unseen-sales chance of M.advice). Saves from before it start from the decayed hours.
        f.watched = (U.finite(f.watched) and f.watched or f.hours) + hours
        f.hours = f.hours * decay + hours
        for i, level in ipairs(M.LEVELS) do
            local gone
            if sold then
                gone = 0
                for price, units in pairs(sold) do
                    if price >= level * prev.market then
                        gone = gone + units
                    end
                end
            else
                gone = math.max(0, (prev.above[i] or 0) - qtyAbove(buckets, level * prev.market))
            end
            f.sold[i] = (f.sold[i] or 0) * decay + gone
        end
        -- The levels were measured against the market of the scan before (prev.market), and
        -- demandAt maps a price to a level through f.market, so it keeps that one. With the new
        -- market, once the cheap units sold and the usual price doubled, units gone at the old
        -- price read as sold at nearly twice it.
        f.pairs, f.at, f.market = math.min(99, (f.pairs or 0) + 1), now, prev.market
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
function M.demandAt(h, price)
    local lots = U.finite(price) and M.lotDemand(h, price)
    if lots then
        return lots
    end
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
    local want, level = 0.85 * price / f.market, nil
    for i, x in ipairs(M.LEVELS) do
        if x >= want then
            level = i
            break
        end
    end
    -- Above the highest level nothing was measured: sales below it are not sales at this price.
    local sold = level and f.sold[level] or 0
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
-- `quiet`: the hours watched, not decayed, since the last sale counted at the price (nil in saves
-- from before that count); `hours` decays with the sales.
local quietHours -- with M.recordSales, below
function M.saleability(h, price, now)
    local out = { known = false, pairs = 0, stale = false }
    local s = type(h) == "table" and h.sales
    if type(s) == "table" and (s.pairs or 0) >= 1 and U.finite(price) and price > 0 then
        local d = M.lotDemand(h, price)
        out.pairs, out.at, out.hours = s.pairs, s.at, s.hours
        out.quiet = quietHours(s, 0.85 * price)
        if out.at and U.finite(now) then
            out.age = math.max(0, now - out.at)
            out.stale = out.age > 3 * 3600
        end
        if d then
            out.known, out.perDay, out.lots = true, d.perDay, true
        end
        return out
    end
    local f = type(h) == "table" and h.flow
    if type(f) ~= "table" then
        return out
    end
    out.pairs = U.finite(f.pairs) and math.max(0, f.pairs) or 0
    out.at = U.finite(f.at) and f.at or nil
    out.hours = U.finite(f.hours) and f.hours > 0 and f.hours or nil
    -- A level's units gone only decay and never reach 0 again: none seen there is none in all the
    -- hours watched.
    out.quiet = U.finite(f.watched) and f.watched or nil
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
    local demand = M.demandAt(h, price)
    if U.finite(demand.perDay) and demand.perDay >= 0 then
        out.known, out.perDay = true, demand.perDay
    end
    return out
end

-- Usual price of an item and when it was measured: the player's own last scan, or a scan another
-- player shared (F.Share) when that one is newer. Returns price, time, sharer (nil when own).
function M.usual(h)
    if type(h) ~= "table" then
        return nil
    end
    local own = type(h.scan) == "table" and U.finite(h.scan.market) and h.scan.market > 0 and h.scan or nil
    local shared = type(h.shared) == "table" and U.finite(h.shared.m) and h.shared.m > 0 and h.shared or nil
    if shared and (not own or (shared.at or 0) > (own.at or 0)) then
        return shared.m, shared.at, shared.from or "?"
    end
    if own then
        return own.market, own.at
    end
end

-- Sales tracked auction by auction ----------------------------------------------------------------
-- A full scan lists the auctions of an item in the order they were created, with a time-left band
-- (0 = under 30 minutes, 1 = up to 2 hours, 2 = up to 12 hours, 3 = longer). Comparing two scans
-- lot by lot tells sales apart from expiry and cancelling:
--  * a lot that got smaller was partly bought (an auction can only be cancelled as a whole);
--  * a lot that disappeared counts as sold only if it could not have expired in between (its band
--    guaranteed more time than passed) and no cheaper lot of the item survived (buyers take the
--    cheapest first, so a vanished lot above a surviving cheaper one was cancelled or reposted).
-- Lots are stored as flat triples {price, count, band, price, count, band, ...}.
M.BAND_MIN = { [0] = 0, [1] = 1800, [2] = 7200, [3] = 43200 }
M.LOTS = 300 -- lots kept per item between scans (the oldest, which is where sales are seen)
M.SALE_HALF_LIFE = 3 * 86400

-- The seller of a lot as a short number, so lots can be told apart by seller without keeping
-- names: 0 = unknown (no owner in the scan). Two sellers can share a tag (1 in 16 million).
function M.ownerTag(owner)
    if type(owner) ~= "string" or owner == "" then
        return 0
    end
    local h = 5381
    for i = 1, #owner do
        h = (h * 33 + owner:byte(i)) % 16777213
    end
    return h + 1
end

function M.packOwners(owners)
    local parts = {}
    for i = 1, math.min(#owners, M.LOTS) do
        parts[i] = string.format("%d", owners[i] or 0)
    end
    return parts[1] and table.concat(parts, ",") or nil
end

function M.unpackOwners(text)
    local out = {}
    if type(text) == "string" then
        for n in text:gmatch("%d+") do
            out[#out + 1] = tonumber(n)
        end
    end
    return out
end

local function compatible(prev, i, cur, k, po, co)
    local a, b = 3 * i - 2, 3 * k - 2
    if prev[a] ~= cur[b] or cur[b + 1] > prev[a + 1] or cur[b + 2] > prev[a + 2] then
        return false
    end
    -- Both sellers known and different: not the same lot (one taken down, another posted).
    local o1, o2 = po and po[i] or 0, co and co[k] or 0
    return o1 == 0 or o2 == 0 or o1 == o2
end

-- Takes one new lot of `count` units, at any price, out of `fresh` ({ ["price:count"] = lots });
-- true when there was one. A lot of an unknown seller that vanished while a new lot of the same
-- count appeared was most likely repriced (cancelled and posted again), not bought. Without seller
-- names (raw scans, a list that does not name them) this is the only sign of it, and counting such
-- a lot as sold read every undercut as a sale (T32). It errs towards fewer sales.
local function takeCount(fresh, count)
    local tail = ":" .. count
    for key, n in pairs(fresh) do
        if n > 0 and key:sub(-#tail) == tail then
            fresh[key] = n - 1
            return true
        end
    end
    return false
end

-- Units sold between two scans `dt` seconds apart: total and { [price] = units }, then the whole
-- lots that vanished among them ({ price, count, owner, ... }: sales only once a later scan shows
-- they were not posted again, see M.confirmGone), the new lots of `cur` that are not the repost of
-- a lot that vanished ({ ["price:count"] = lots }) and the sellers of those new lots
-- ({ [owner tag] = lots }). `prevOwners`/`curOwners` (optional): the seller tag of each lot
-- (M.ownerTag). A lot that vanished while its seller posted a new lot of the item, at any price or
-- count, was taken down and posted again (undercutting), not sold: seen in game as sales that
-- never happened, which made an item look ten times as wanted as it was.
function M.trackSales(prev, cur, dt, prevOwners, curOwners)
    local np, nc = math.floor(#prev / 3), math.floor(#cur / 3)
    local match, used = {}, {}
    local k = 1
    for i = 1, np do
        if k <= nc and compatible(prev, i, cur, k, prevOwners, curOwners) then
            match[i], used[k] = k, true
            k = k + 1
        end
    end
    local free, minimum = {}, {}
    for n = 1, nc do
        if not used[n] then
            local p = cur[3 * n - 2]
            free[p] = free[p] or {}
            table.insert(free[p], n)
            -- A conservative lower bound per price/time band rejects whole incompatible buckets.
            -- It stays valid after removals: an old minimum may cause extra work, never a miss.
            minimum[p] = minimum[p] or {}
            local qty, band = cur[3 * n - 1], cur[3 * n]
            for b = band, 3 do
                minimum[p][b] = math.min(minimum[p][b] or math.huge, qty)
            end
        end
    end
    for i = 1, np do
        local price, qty, band = prev[3 * i - 2], prev[3 * i - 1], prev[3 * i]
        local bound = minimum[price] and minimum[price][band]
        local list = not match[i] and bound and bound <= qty and free[price]
        if list then
            for n, c in ipairs(list) do
                if compatible(prev, i, cur, c, prevOwners, curOwners) then
                    match[i] = c
                    table.remove(list, n)
                    break
                end
            end
        end
    end
    local sold, byPrice, cheapest = 0, {}, math.huge
    local function add(price, units)
        sold = sold + units
        byPrice[price] = (byPrice[price] or 0) + units
    end
    for i, c in pairs(match) do
        local price = prev[3 * i - 2]
        cheapest = math.min(cheapest, price)
        local bought = prev[3 * i - 1] - cur[3 * c - 1]
        if bought > 0 then
            add(price, bought)
        end
    end
    -- A lot that vanished while a new lot of the same price and count appeared was posted again
    -- (cancelled and reposted, or expired and reposted), not sold: the new one runs longer, so it
    -- does not match as the same lot. In game one seller's 65-80 silver bracers were read as sales
    -- this way while the item sold at 3-4 silver, and resale prices came out ten times too high.
    local reposted, gone, sellers = {}, {}, {}
    -- New lots posted below the cheapest lot of the scan before: undercuts, the measure of how
    -- quickly the item's sellers answer each other (see F.Trade.fightPlan).
    local before, undercuts = math.huge, 0
    for i = 1, np do
        before = math.min(before, prev[3 * i - 2])
    end
    for _, list in pairs(free) do
        for _, n in ipairs(list) do
            if cur[3 * n - 2] < before then
                undercuts = undercuts + 1
            end
            local key = cur[3 * n - 2] .. ":" .. cur[3 * n - 1]
            reposted[key] = (reposted[key] or 0) + 1
            local o = curOwners and curOwners[n] or 0
            if o > 0 then
                sellers[o] = (sellers[o] or 0) + 1
            end
        end
    end
    -- Two passes: a lot's own repost (same price and count, or the same seller) first, so that
    -- another lot of the same count cannot take it as its repost at a new price.
    local left = {}
    for i = 1, np do
        local price, count = prev[3 * i - 2], prev[3 * i - 1]
        if not match[i] then
            local key = price .. ":" .. count
            local o = prevOwners and prevOwners[i] or 0
            if (reposted[key] or 0) > 0 then
                reposted[key] = reposted[key] - 1
            elseif o > 0 and (sellers[o] or 0) > 0 then
                sellers[o] = sellers[o] - 1 -- the same seller posted again: a repost
            else
                left[#left + 1] = i
            end
        end
    end
    for _, i in ipairs(left) do
        local price, count, band = prev[3 * i - 2], prev[3 * i - 1], prev[3 * i]
        local o = prevOwners and prevOwners[i] or 0
        if o == 0 and takeCount(reposted, count) then
            -- an unknown seller's lot posted again at a new price: not a sale
        elseif (M.BAND_MIN[band] or 0) >= dt and price <= cheapest then
            add(price, count)
            gone[#gone + 1] = price
            gone[#gone + 1] = count
            gone[#gone + 1] = o
        end
    end
    return sold, byPrice, gone, reposted, sellers, undercuts
end

-- New lots of a scan as { ["price:count"] = lots }: every lot, when there is nothing to compare with.
function M.lotKeys(seq)
    local keys = {}
    for i = 1, #seq - 2, 3 do
        local key = seq[i] .. ":" .. seq[i + 1]
        keys[key] = (keys[key] or 0) + 1
    end
    return keys
end

-- Sellers of a scan's lots as { [owner tag] = lots } (unknown sellers left out).
function M.lotSellers(owners)
    local out = {}
    for _, o in ipairs(owners or {}) do
        if o > 0 then
            out[o] = (out[o] or 0) + 1
        end
    end
    return out
end

-- Whole lots that vanished are only suspected sales: the seller may have cancelled the auction and
-- post it again later (the price and count come back as a new lot), and the time-left bands cannot
-- tell that apart. A suspect is confirmed by the next scan of the item (up to M.CONFIRM_WITHIN
-- later) when no new lot of the same price and count appeared there, or when the item is gone from
-- the house altogether. A lot that only got smaller is a sure sale at once: an auction can be
-- cancelled only as a whole. `fresh` is the new lots of that next scan (taken as they are used);
-- adds the confirmed units to byPrice and returns how many lots turned out to be reposts.
-- `sellers` (optional, { [owner tag] = lots } of that next scan's new lots): a suspect whose seller
-- posted the item again is a repost too, whatever the new price or count. Suspects are
-- { price, count, owner, ... } (owner 0 = unknown).
M.CONFIRM_WITHIN = 3 * 3600
function M.confirmGone(pending, fresh, byPrice, sellers)
    local reposts = 0
    for i = 1, #pending - 2, 3 do
        local price, count, o = pending[i], pending[i + 1], pending[i + 2] or 0
        local key = price .. ":" .. count
        if (fresh[key] or 0) > 0 then
            fresh[key] = fresh[key] - 1
            reposts = reposts + 1
        elseif o > 0 and sellers and (sellers[o] or 0) > 0 then
            sellers[o] = sellers[o] - 1
            reposts = reposts + 1
        elseif o == 0 and takeCount(fresh, count) then
            reposts = reposts + 1 -- an unknown seller's lot back at a new price (see M.trackSales)
        else
            byPrice[price] = (byPrice[price] or 0) + count
        end
    end
    return reposts
end

function M.packPending(gone)
    local parts = {}
    for i = 1, math.min(#gone, 3 * M.LOTS) - 2, 3 do
        parts[#parts + 1] = string.format("%.0f:%d:%d", gone[i], gone[i + 1], gone[i + 2] or 0)
    end
    return parts[1] and table.concat(parts, ",") or nil
end

-- Suspects as { price, count, owner, ... }; older saves without the owner read as owner 0.
function M.unpackPending(text)
    local list = {}
    if type(text) == "string" then
        for entry in text:gmatch("[^,]+") do
            local p, c, o = entry:match("^([%d%.]+):(%d+):?(%d*)$")
            if p then
                list[#list + 1] = tonumber(p)
                list[#list + 1] = tonumber(c)
                list[#list + 1] = tonumber(o) or 0
            end
        end
    end
    return list
end

function M.packLots(seq)
    local n = math.min(#seq, 3 * M.LOTS)
    local parts = {}
    for i = 1, n, 3 do
        parts[#parts + 1] = string.format("%.0f:%d:%d", seq[i], seq[i + 1], seq[i + 2])
    end
    return table.concat(parts, ",")
end

function M.unpackLots(text)
    local seq = {}
    if type(text) ~= "string" then
        return seq
    end
    for p, c, b in text:gmatch("([%d%.]+):(%d+):(%d)") do
        seq[#seq + 1] = tonumber(p)
        seq[#seq + 1] = tonumber(c)
        seq[#seq + 1] = tonumber(b)
    end
    return seq
end

-- Adds the sales seen between two scans to the item's decayed sale distribution h.sales =
-- { hours, pairs, at, b = price histogram of sold units, sure, lots, log, recent }. Returns the
-- units added. `lots` (optional, { [price] = units }): the part of byPrice that are whole lots
-- confirmed gone; the rest are lots bought in part (sure sales). What each figure is made of:
--   sure / lots   decayed units of each kind, for the evidence shown with every estimate
--   log           the last M.SALE_LOG sales: "time:price:units:kind" (p = part of a lot, l = lot)
--   recent        units seen per scan pair, the last 12 pairs
--   watched       hours watched, not decayed; soldAt: when the last sale at each price was (below)
-- One-off sweeps: a pair that saw more than M.SWEEP times the median of the pairs before it (at
-- least 3) is counted at that ceiling: one buyer clearing a shelf (often another reseller) is no
-- daily demand, and counting it whole let one scan pair decide a day of buying.
M.SALE_LOG = 30
M.SWEEP = 3

-- The unseen-sales chance of M.advice needs the hours an item was watched since its last sale at
-- a price. s.hours decays (3-day half-life): it levels off near 104 hours, and stays under a day
-- for a player who scans a few hours a day, so months without a sale read as four days at most.
-- Kept beside it: s.watched, the hours of scan pairs without decay, and s.soldAt = { price,
-- watched, ... }, the last sale at each price as s.watched was then: prices rising, those hours
-- falling (a sale also answers for every price below it, so the older ones it covers go).
M.SOLD_AT = 8
local function noteSold(s, price)
    local list = {}
    for i = 1, #s.soldAt - 1, 2 do
        if s.soldAt[i] > price then
            list[#list + 1], list[#list + 2] = s.soldAt[i], s.soldAt[i + 1]
        end
    end
    if not list[2] or list[2] < s.watched then
        table.insert(list, 1, s.watched)
        table.insert(list, 1, price)
    end
    -- Over M.SOLD_AT the dearest, oldest sale is forgotten: as if nothing sold that high.
    while #list > 2 * M.SOLD_AT do
        list[#list], list[#list - 1] = nil, nil
    end
    s.soldAt = list
end

-- Hours watched since the last sale at or above `price`; nil for sales saved before the count.
function quietHours(s, price)
    if not U.finite(s.watched) then
        return nil
    end
    local list = type(s.soldAt) == "table" and s.soldAt or {}
    for i = 1, #list - 1, 2 do
        if list[i] >= price then
            return math.max(0, s.watched - list[i + 1])
        end
    end
    return s.watched
end

-- `undercuts` (optional): new lots posted below the cheapest lot of the scan before, kept decayed
-- in s.cuts like the sales (M.undercutRate).
function M.recordSales(h, byPrice, dt, now, lots, undercuts)
    local s = type(h.sales) == "table" and h.sales or { hours = 0, pairs = 0, at = now, b = {} }
    s.b = type(s.b) == "table" and s.b or {}
    -- The units of s.b that came from whole lots that vanished (M.LOT_WEIGHT), by price.
    s.bl = type(s.bl) == "table" and s.bl or {}
    local total = 0
    for price, units in pairs(byPrice) do
        if price > 0 and units > 0 then
            total = total + units
        end
    end
    local scale = 1
    local decay = 0.5 ^ (math.max(0, now - (s.at or now)) / M.SALE_HALF_LIFE)
    s.rates = type(s.rates) == "table" and s.rates or {}
    s.recent = nil -- counts per pair of the older model: pairs of different lengths are not alike
    s.sweeps = (s.sweeps or 0) * decay
    -- Sales kept from older formulas (F.Data.commitStats) count as measured again after as many
    -- new pairs as a reliable sample needs; what they held decays meanwhile.
    if s.legacy and dt > 0 then
        s.newPairs = (s.newPairs or 0) + 1
        if s.newPairs >= M.RELIABLE_PAIRS then
            s.legacy, s.newPairs = nil, nil
        end
    end
    if dt > 0 then
        local hours = dt / 3600
        local swept = false
        if #s.rates >= 3 then
            local sorted = {}
            for i, v in ipairs(s.rates) do
                sorted[i] = v
            end
            table.sort(sorted)
            local median = sorted[math.floor((#sorted + 1) / 2)]
            local ceiling = math.max(5, M.SWEEP * median * hours)
            if total > ceiling then
                scale, swept = ceiling / total, true
            end
        end
        s.sweeps = s.sweeps + (swept and 1 or 0)
        s.pairsSeen = (s.pairsSeen or s.pairs or 0) * decay + 1
        s.rates[#s.rates + 1] = total * scale / math.max(hours, 1 / 60)
        while #s.rates > 12 do
            table.remove(s.rates, 1)
        end
    end
    s.sure = (s.sure or 0) * decay
    s.lots = (s.lots or 0) * decay
    s.cuts = (s.cuts or 0) * decay + (dt > 0 and undercuts or 0)
    s.log = type(s.log) == "table" and s.log or {}
    -- Saves from before s.watched start it from their decayed hours (the measure used until then).
    s.watched = (U.finite(s.watched) and s.watched or U.finite(s.hours) and s.hours or 0) + dt / 3600
    s.soldAt = type(s.soldAt) == "table" and s.soldAt or {}
    s.hours = (s.hours or 0) * decay + dt / 3600
    for _, hist in ipairs({ s.b, s.bl }) do
        for b, units in pairs(hist) do
            if b % 2 == 0 then
                if units * decay < 0.01 then
                    hist[b], hist[b + 1] = nil, nil
                else
                    hist[b] = units * decay
                end
            end
        end
    end
    local sold = 0
    for price, units in pairs(byPrice) do
        if price > 0 and units > 0 then
            local counted = units * scale
            M.bucketAdd(s.b, price, counted)
            sold = sold + counted
            local whole = math.min(units, lots and lots[price] or 0)
            s.lots = s.lots + whole * scale
            if whole > 0 then
                M.bucketAdd(s.bl, price, whole * scale)
            end
            s.sure = s.sure + (units - whole) * scale
            if whole > 0 then
                s.log[#s.log + 1] = string.format("%d:%.0f:%d:l", now, price, whole)
            end
            if units - whole > 0 then
                s.log[#s.log + 1] = string.format("%d:%.0f:%d:p", now, price, units - whole)
            end
            noteSold(s, price)
        end
    end
    while #s.log > M.SALE_LOG do
        table.remove(s.log, 1)
    end
    if dt > 0 then
        s.pairs = math.min(99, (s.pairs or 0) + 1)
    end
    s.at = now
    h.sales = s
    return sold
end

-- What the sales of an item rest on, for the evidence shown with Est./day and Sells at:
-- { units, sure, lots, hours, pairs, buys, low, median, high, sweeps, at } from the sales at or
-- above `floor` (all with nil); nil without any sale seen.
function M.saleEvidence(h, floor)
    local s = type(h) == "table" and h.sales
    if type(s) ~= "table" or type(s.log) ~= "table" or not s.log[1] then
        return nil
    end
    local prices, units, buys, sure, lots, at = {}, 0, 0, 0, 0, nil
    for _, entry in ipairs(s.log) do
        local t, price, n, kind = entry:match("^(%d+):([%d%.]+):(%d+):(%a)$")
        price, n = tonumber(price), tonumber(n)
        if price and n and (not floor or price >= floor) then
            buys, units = buys + 1, units + n
            if kind == "l" then
                lots = lots + n
            else
                sure = sure + n
            end
            for _ = 1, math.min(n, 50) do
                prices[#prices + 1] = price
            end
            at = math.max(at or 0, tonumber(t) or 0)
        end
    end
    if buys == 0 then
        return nil
    end
    table.sort(prices)
    return {
        units = units,
        sure = sure,
        lots = lots,
        buys = buys,
        hours = s.hours,
        pairs = s.pairs,
        low = prices[1],
        median = prices[math.floor((#prices + 1) / 2)],
        high = prices[#prices],
        sweeps = s.sweeps or 0,
        at = at,
    }
end

-- Price at `share` of the sold units (cheapest first); nil with fewer than `need` units sold.
local function soldQuantile(h, share, need)
    local s = type(h) == "table" and h.sales
    if type(s) ~= "table" or type(s.b) ~= "table" then
        return nil
    end
    local keys, total = {}, 0
    for b, units in pairs(s.b) do
        if b % 2 == 0 then
            keys[#keys + 1] = b
            total = total + units
        end
    end
    if total < (need or 3) then
        return nil
    end
    table.sort(keys)
    local seen = 0
    for _, b in ipairs(keys) do
        seen = seen + s.b[b]
        if seen >= total * share then
            return math.floor(s.b[b + 1])
        end
    end
end

-- True when the item's lots were watched long enough (an hour of scan pairs) to have seen a sale.
M.WATCHED_HOURS = 1
function M.watched(h)
    local s = type(h) == "table" and h.sales
    return type(s) == "table" and U.finite(s.hours) and s.hours >= M.WATCHED_HOURS
end

-- Typical price of the units seen sold (median), or nil without at least 3 sales.
function M.salePrice(h)
    return soldQuantile(h, 0.5, 3)
end

-- Highest price a resale may count on: the price that a quarter of the sales reached, but at most
-- M.CAP_SPREAD times the typical (median) sale: a few sales far above the rest are rare luck, or
-- reposts read as sales, not a price to count on.
M.CAP_SPREAD = 3
-- One or two confirmed sales already cap it: their price is what a buyer really paid.
function M.saleCap(h)
    local cap = soldQuantile(h, 0.75, 0.5)
    local median = soldQuantile(h, 0.5, 0.5)
    if cap and median then
        cap = math.min(cap, math.floor(median * M.CAP_SPREAD))
    end
    return cap
end

-- The one price to sell at, the same on every page (the tooltip's recommendation, the Sell page,
-- the Resale exit), and why:
--   "undercut"  one step under the cheapest lot others leave on sale (o.cheapest), unless it asks
--               more than o.limit (the maximum share of the usual price): such a lot is ignored
--   "sales"     at most what buyers really paid (o.cap, M.saleCap): asking prices above it do not sell
--   "usual"     one step under the usual price, when no lot is to undercut
-- o: kind, usual (the usual price, or the player's normal price), cap, cheapest, limit, undercut
-- (function(price, kind), U.below by default). Returns price, why; nil without any price.
function M.postPrice(o)
    local kind = o.kind
    local cap = U.finite(o.cap) and o.cap > 0 and o.cap or nil
    local sells, sellsWhy = U.finite(o.usual) and o.usual > 0 and o.usual or nil, "usual"
    if cap and (not sells or cap < sells) then
        sells, sellsWhy = cap, "sales"
    end
    local price, why
    if U.finite(o.cheapest) and not (sells and U.finite(o.limit) and o.cheapest > o.limit) then
        price, why = (o.undercut or U.below)(o.cheapest, kind), "undercut"
    elseif sells then
        price, why = U.stepDown(sells, kind), sellsWhy
    end
    if price and cap and price > U.stepDown(cap, kind) then
        price, why = U.stepDown(cap, kind), "sales"
    end
    return price, why
end

-- Units per day sold at or above 85% of `price` from the lot-tracked sales; nil without data.
-- Units of the sold-units histogram at or above `floor`, split into units bought out of a lot in
-- part (sure) and units of whole lots that vanished (inferred: M.LOT_WEIGHT). Saves without the
-- split (s.bl) count every unit as sure, as before.
local function soldAbove(s, floor)
    local all = qtyAbove(type(s.b) == "table" and s.b or {}, floor)
    local lots = type(s.bl) == "table" and math.min(all, qtyAbove(s.bl, floor)) or 0
    return all - lots, lots
end
M.soldAbove = soldAbove

-- A whole lot that vanished is no purchase seen: it may be a cancel the next scan did not expose
-- (posted again later, elsewhere, or by a seller the list does not name), or another reseller.
-- It counts as this share of a sale in Est./day and Sure alike (T32; Sure counted it half already,
-- Est./day counted it whole).
M.LOT_WEIGHT = 0.5

-- Units per day sold at or above 85% of `price` from the lot-tracked sales; nil without data.
-- sold = effective units (part-lot units + M.LOT_WEIGHT x whole-lot units), units = all units
-- seen gone, lots = the whole-lot units among them.
local function lotDemand(h, price)
    local s = type(h) == "table" and h.sales
    if type(s) ~= "table" or (s.pairs or 0) < 1 or not U.finite(s.hours) or s.hours <= 0 then
        return nil
    end
    local sure, lots = soldAbove(s, 0.85 * price)
    local units = sure + M.LOT_WEIGHT * lots
    return {
        pairs = s.pairs,
        perDay = units / (s.hours + M.PRIOR_HOURS) * 24,
        sold = units,
        units = sure + lots,
        lots = lots,
        hours = s.hours,
    }
end
M.lotDemand = lotDemand

-- Undercuts of an item per hour: new lots posted below the cheapest lot, over the hours its lots
-- were watched (with the same prior hours as the sales, so one scan pair does not decide it).
-- { perHour, cuts, hours }; nil before the first scan pair.
-- The median number of units of the item's lots at the last scan (1 when unknown).
function M.medianLot(h)
    local seq = M.unpackLots(type(h) == "table" and h.lots or nil)
    local counts = {}
    for i = 2, #seq, 3 do
        counts[#counts + 1] = seq[i]
    end
    if #counts == 0 then
        return 1
    end
    table.sort(counts)
    return math.max(1, counts[math.floor((#counts + 1) / 2)])
end

-- Chances of sales -------------------------------------------------------------------------------
-- The negative binomial behind Sure and the anti-undercut plan (Trade.fightPlan): see the
-- Anti-undercut comment in Trade.lua for the model.
-- The error function (Abramowitz and Stegun 7.1.26), for the normal approximation of the chances
-- of many units (M.saleChances).
local function erf(x)
    local sign = x < 0 and -1 or 1
    x = math.abs(x)
    local t = 1 / (1 + 0.3275911 * x)
    local y = 1
        - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592)
            * t
            * math.exp(-x * x)
    return sign * y
end

-- Chances of the units sold in `t` hours when n units sold in h hours watched (M.saleChances):
-- the negative binomial of a Gamma(n + 1/2, (h + M.PRIOR_HOURS) / 24) rate. Returns tail(k) =
-- P(N >= k); a normal approximation beyond M.CHANCE_TERMS units.
M.CHANCE_TERMS = 20000
function M.saleChances(sold, hours, t, prior, priorHours)
    local shape = math.max(0, U.finite(sold) and sold or 0) + (U.finite(prior) and prior > 0 and prior or 0.5)
    local exposure = (
        math.max(0, U.finite(hours) and hours or 0) + (U.finite(priorHours) and priorHours or M.PRIOR_HOURS)
    ) / 24
    local days = math.max(0, U.finite(t) and t or 0) / 24
    if days <= 0 then
        return function(k)
            return k <= 0 and 1 or 0
        end
    end
    local p = exposure / (exposure + days) -- the chance of "no sale" in each step of the mixture
    local mean = shape * (1 - p) / p
    local sd = math.sqrt(mean / p)
    local tails = { [0] = 1 }
    local log1p = math.log(1 - p)
    -- log P(N = n), stepped n by n: kept as a log, a term too small for a number is still exact.
    local logTerm = shape * math.log(p)
    local below, n = 0, 0
    return function(k)
        if k <= 0 then
            return 1
        end
        if k > M.CHANCE_TERMS then
            local z = (k - 0.5 - mean) / math.max(sd, 1e-9)
            return math.max(0, math.min(1, 1 - 0.5 * (1 + erf(z / math.sqrt(2)))))
        end
        while n < k do
            below = below + math.exp(logTerm)
            logTerm = logTerm + math.log((n + shape) / (n + 1)) + log1p
            n = n + 1
            tails[n] = math.max(0, math.min(1, 1 - below))
        end
        return tails[k]
    end
end

-- Expected units of a lot of `qty` sold behind `ahead` units, with tail(k) = P(N >= k):
-- sum over j = 1..qty of P(N >= ahead + j).
function M.expectedSold(tail, ahead, qty)
    local units = 0
    for j = 1, math.max(0, qty or 0) do
        local p = tail(ahead + j)
        units = units + p
        if p < 1e-6 then
            break
        end
    end
    return units
end

-- How sure a resale is to pay back at its Sells at price: a number from 0 to 1, the chance that
-- real buyers take the units at that price within M.SURE_HOURS while the lot is first in line,
-- discounted for evidence that is speculation or old.
--   n     units seen bought at or above 95% of the price (decayed, lot-tracked full scans), in
--         h hours watched
--   real  share of real buyers: units bought out of a lot in part are sure purchases; a whole lot
--         that vanished may be a reseller clearing it (or a repost), and counts half:
--         real = (sure + lots / 2) / (sure + lots)
--   trust own results of the item (stock that did not sell lowers it, Deals.trust)
--   m     units per purchase at the price (the sale log: units / buys, at least 1): four units
--         bought at once are one buyer, not four. Purchases are what is uncertain, so the chance
--         is that of ceil(qty / m) purchases from n / m seen
--   ahead units buyers take before yours: those listed below the price at the last scan
--         (M.listedBelow). So a lower price raises Sure twice (more buyers at 95% of it and up,
--         fewer units before it) and a higher one lowers it twice
--   rival rivals who undercut later take a share of the buyers: their lots (c undercuts an hour,
--         M.undercutRate, x the item's median lot, M.medianLot) against the units bought an hour
--         (n x real / (h + 4)), at most half: share = min(1/2, c x lot / rate). Many undercuts
--         are the same sellers reposting lower, not new stock, so they never take every buyer
--         (counting each as a new lot for 48 hours put a thousand units ahead of an ore that
--         sells three hundred a day, and its Sure read 0%)
--   P     P(B >= ceil((qty + ahead) / m)) for B, the purchases in H hours, a negative binomial with a
--         Gamma(n x real x trust x (1 - share) + 0.1, (h + 24) / 24 days) rate: a quiet day is assumed until
--         the scans show sales, so few sales give a modest number however fast they came, and
--         many sales a high one (M.saleChances). With no sale seen at the price it stays
--         below 10%; one whole lot vanished in an hour and a half gives about half
--   sweep one buyer clearing a shelf is counted at a ceiling (M.SWEEP); items where that happens
--         often are speculation: x (1 - min(1, sweeps / pairs) / 2)
--   fresh sales data older than 6 hours loses half its weight every 2 days:
--         0.5 ^ (max(0, age - 6 h) / 48 h)
--   sure  = P x sweep x fresh
-- Returns sure, and its parts for the explanation.
M.SURE_HOURS = 48
M.SURE_PRIOR = 0.1
-- The most of the buyers rivals' later undercuts are counted to take.
M.RIVAL_SHARE = 0.5
-- Lots of the last scan older than this say nothing of the queue in front of a new lot.
M.LISTED_AGE = 24 * 3600

-- Units other lots offered strictly below `price` at the last scan (h.lots), or 0 when the scan is
-- older than M.LISTED_AGE. Buyers take the cheapest lot first, so these units sell before a lot
-- posted at `price` (the queue, below): posting cheaper jumps them, posting dearer adds them.
function M.listedBelow(h, price, now)
    if type(h) ~= "table" or not U.finite(price) or price <= 0 then
        return 0
    end
    if U.finite(now) and U.finite(h.lotsAt) and now - h.lotsAt > M.LISTED_AGE then
        return 0
    end
    local seq, units = M.unpackLots(h.lots), 0
    for i = 1, #seq, 3 do
        if seq[i] < price then
            units = units + seq[i + 1]
        end
    end
    return units
end
M.SURE_PRIOR_HOURS = 24
-- Weight of sales data `age` seconds old: whole for 6 hours, then half every 2 days.
function M.freshness(age)
    return 0.5 ^ (math.max(0, (age or 0) - 6 * 3600) / (48 * 3600))
end

-- Before lots were tracked over two scans, only the older measure is there: units that
-- disappeared near the price (h.flow), which also counts expired, cancelled and reposted lots.
-- It gives a number too, with every unit counted as a whole lot (real = 1/2), never above
-- M.FLOW_SURE_MAX: a disappearance is no purchase seen.
M.FLOW_SURE_MAX = 0.5
local function flowConfidence(h, price, qty, now, trust)
    local f = type(h) == "table" and h.flow
    if type(f) ~= "table" or (f.pairs or 0) < 1 or not U.finite(price) or price <= 0 then
        return nil
    end
    -- M.demandAt counts at 85% of the price it is given: asked at price x 95/85, it counts at 95%.
    local d = M.demandAt({ flow = f }, price * 0.95 / 0.85)
    if not U.finite(d.sold) or not U.finite(d.hours) then
        return nil
    end
    trust = U.finite(trust) and math.max(0, trust) or 1
    local tail = M.saleChances(d.sold * 0.5 * trust, d.hours, M.SURE_HOURS, M.SURE_PRIOR, M.SURE_PRIOR_HOURS)
    local listed = M.listedBelow(h, price, now)
    local p = tail(math.max(1, (qty or 1) + listed))
    local age = U.finite(now) and U.finite(f.at) and math.max(0, now - f.at) or 0
    local fresh = M.freshness(age)
    return math.min(M.FLOW_SURE_MAX, p * fresh),
        {
            p = p,
            units = d.sold,
            perBuy = 1,
            real = 0.5,
            hours = d.hours,
            selling = M.SURE_HOURS,
            rival = 0,
            listed = listed,
            ahead = listed,
            sweep = 1,
            fresh = fresh,
            age = age,
            flow = true,
        }
end

function M.confidence(h, price, qty, now, trust)
    local s = type(h) == "table" and h.sales
    if type(s) ~= "table" or (s.pairs or 0) < 1 then
        return flowConfidence(h, price, qty, now, trust)
    end
    if not U.finite(price) or price <= 0 then
        return nil
    end
    local floor = 0.95 * price
    local partUnits, lotUnits = soldAbove(s, floor)
    local units = partUnits + lotUnits
    -- Sales at the price only, like n: purchases far below it say nothing of buyers at this price.
    local seen = M.saleEvidence(h, floor)
    local sure = seen and seen.sure or math.max(0, s.sure or 0)
    local lots = seen and seen.lots or math.max(0, s.lots or 0)
    local real = (sure + lots) > 0 and (sure + lots * M.LOT_WEIGHT) / (sure + lots) or 1
    if type(s.bl) == "table" and units > 0 then
        -- The split by price is kept (s.bl): the share at this price exactly, not from the log.
        real = (partUnits + lotUnits * M.LOT_WEIGHT) / units
    end
    trust = U.finite(trust) and math.max(0, trust) or 1
    local hours = M.SURE_HOURS
    local cut = M.undercutRate(h)
    local c = cut and cut.perHour or 0
    -- The queue in front of a lot at `price`: the units already listed below it (buyers take the
    -- cheapest first). A lower price counts more buyers (sales at 95% of it and up) and fewer units
    -- before it, so Sure rises as the price falls; a higher price counts fewer buyers and more units
    -- before it. Rivals undercutting later take a share of the buyers, at most half.
    local lot = M.medianLot(h)
    local listed = M.listedBelow(h, price, now)
    local ahead = listed
    local bought = units * real / ((s.hours or 0) + M.PRIOR_HOURS)
    local share = bought > 0 and math.min(M.RIVAL_SHARE, c * lot / bought) or (c > 0 and M.RIVAL_SHARE or 0)
    local e = seen
    local m = e and e.buys > 0 and math.max(1, e.units / e.buys) or 1
    local tail =
        M.saleChances(units * real * trust * (1 - share) / m, s.hours or 0, hours, M.SURE_PRIOR, M.SURE_PRIOR_HOURS)
    local p = tail(math.max(1, math.ceil(((qty or 1) + ahead) / m)))
    local sweep = 1 - math.min(1, (s.sweeps or 0) / math.max(1, s.pairsSeen or s.pairs or 1)) / 2
    local age = U.finite(now) and U.finite(s.at) and math.max(0, now - s.at) or 0
    local fresh = M.freshness(age)
    return p * sweep * fresh,
        {
            p = p,
            units = units,
            perBuy = m,
            real = real,
            hours = s.hours or 0,
            selling = hours,
            rival = c,
            share = share,
            listed = listed,
            ahead = ahead,
            sweep = sweep,
            fresh = fresh,
            age = age,
        }
end

function M.undercutRate(h)
    local s = type(h) == "table" and h.sales
    if type(s) ~= "table" or (s.pairs or 0) < 1 or not U.finite(s.hours) then
        return nil
    end
    local cuts = U.finite(s.cuts) and s.cuts or 0
    return { perHour = cuts / (s.hours + M.PRIOR_HOURS), cuts = cuts, hours = s.hours }
end

-- Sample quality and confidence limits (T32) --------------------------------------------------------
-- What an Est./day or a Sure rests on, so a page can show "no reliable data" instead of a number
-- made of one scan pair, and limits around the number otherwise. See docs/analytics-model.md.
M.RELIABLE_PAIRS = 4 -- scan pairs compared lot by lot (an hour of 15-minute scans)
M.RELIABLE_HOURS = 2 -- hours of those pairs, not decayed
M.RELIABLE_AGE = 3 * 86400 -- sales data older than this says nothing reliable of today
M.LIMIT_Z = 1.2816 -- 80% two-sided limits (10% below, 10% above)

-- Quantile of a Gamma(a, 1) variable at standard normal `z` (Wilson-Hilferty; within a few
-- percent from a = 0.5 up, which is all limits shown as whole units need).
local function gammaQuantile(a, z)
    if a <= 0 then
        return 0
    end
    local c = 1 / (9 * a)
    local x = 1 - c + z * math.sqrt(c)
    return x > 0 and a * x * x * x or 0
end
M.gammaQuantile = gammaQuantile

-- Limits of a rate per day from `units` seen in `hours` (Jeffreys prior: shape units + 1/2), with
-- the same smoothing hours as the estimate itself. No unit seen: the lower limit is 0.
function M.rateRange(units, hours, priorHours, z)
    units, hours = math.max(0, units or 0), math.max(0, hours or 0)
    local days = (hours + (priorHours or M.PRIOR_HOURS)) / 24
    if days <= 0 then
        return nil
    end
    z = z or M.LIMIT_Z
    local low = units > 0 and gammaQuantile(units + 0.5, -z) / days or 0
    local high = gammaQuantile(units + 0.5, z) / days
    return low, high
end

-- Standard normal distribution function (Abramowitz-Stegun 7.1.26, error under 1.5e-7).
local function normal(z)
    local x = math.abs(z) / math.sqrt(2)
    local t = 1 / (1 + 0.3275911 * x)
    local y = 1
        - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592)
            * t
            * math.exp(-x * x)
    return z >= 0 and 0.5 * (1 + y) or 0.5 * (1 - y)
end

-- P(N >= k) for N ~ Poisson(lambda).
function M.poissonTail(lambda, k)
    if k <= 0 then
        return 1
    end
    if not U.finite(lambda) or lambda <= 0 then
        return 0
    end
    if lambda > 500 then
        return math.max(0, math.min(1, 1 - normal((k - 0.5 - lambda) / math.sqrt(lambda))))
    end
    local term, sum = math.exp(-lambda), 0
    for j = 0, k - 1 do
        sum = sum + term
        term = term * lambda / (j + 1)
        if sum >= 1 then
            return 0
        end
    end
    return math.max(0, math.min(1, 1 - sum))
end

-- How good the sales sample of an item is at `price`. `own` (optional): the player's own results of
-- the item, { sold = units sold by invoice, failed = units back unsold } (F.Trade.rate's record).
-- { level = "none" | "low" | "ok", reliable, reason, pairs, watched, hours, age, stale, inferred,
--   partUnits, lotUnits, effective, perDay, perDayLow, perDayHigh, ownSold, ownFailed }
-- reason: "legacy" (measured by older formulas, kept by a rebuild that had no raw scan of the
-- item), "no_data" (nothing compared yet), "flow_only" (only units that disappeared, which counts
-- expired, cancelled and moved lots too), "few_pairs", "few_hours", "stale". Zero sales over enough
-- hours is reliable data: Est./day 0 with an upper limit.
function M.quality(h, price, now, own)
    local q = { level = "none", reliable = false, reason = "no_data", pairs = 0 }
    if type(own) == "table" then
        q.ownSold, q.ownFailed = own.sold or 0, own.failed or 0
    end
    local s = type(h) == "table" and h.sales
    if type(s) ~= "table" or (s.pairs or 0) < 1 or not U.finite(s.hours) or s.hours <= 0 then
        local f = type(h) == "table" and h.flow
        if type(f) == "table" and (f.pairs or 0) >= 1 then
            q.level, q.reason, q.inferred, q.pairs = "low", "flow_only", true, f.pairs
        end
        return q
    end
    q.pairs = s.pairs
    q.watched = U.finite(s.watched) and s.watched or s.hours
    q.hours = s.hours
    if U.finite(now) and U.finite(s.at) then
        q.age = math.max(0, now - s.at)
    end
    if U.finite(price) and price > 0 then
        local sure, lots = soldAbove(s, 0.85 * price)
        q.partUnits, q.lotUnits = sure, lots
        q.effective = sure + M.LOT_WEIGHT * lots
        q.perDay = q.effective / (s.hours + M.PRIOR_HOURS) * 24
        q.perDayLow, q.perDayHigh = M.rateRange(q.effective, s.hours)
    end
    q.level, q.reliable, q.reason = "ok", true, nil
    q.legacy = s.legacy and true or nil
    if q.age and q.age > M.RELIABLE_AGE then
        q.level, q.reliable, q.reason, q.stale = "low", false, "stale", true
    elseif q.pairs < M.RELIABLE_PAIRS then
        q.level, q.reliable, q.reason = "low", false, "few_pairs"
    elseif q.watched < M.RELIABLE_HOURS then
        q.level, q.reliable, q.reason = "low", false, "few_hours"
    elseif q.legacy then
        q.level, q.reliable, q.reason = "low", false, "legacy"
    end
    return q
end

-- Sure with its limits: the chance computed at the lower and upper 80% limits of the purchase rate
-- (Poisson at that rate over M.SURE_HOURS, the same queue, sweep and freshness as M.confidence).
-- Returns sure, low, high, parts; nil when M.confidence gives nothing.
function M.sureLimits(h, price, qty, now, trust)
    local sure, parts = M.confidence(h, price, qty, now, trust)
    if not sure or not parts then
        return nil
    end
    local m = parts.perBuy or 1
    local need = math.max(1, math.ceil(((qty or 1) + (parts.ahead or 0)) / m))
    trust = U.finite(trust) and math.max(0, trust) or 1
    local buys = (parts.units or 0) * (parts.real or 1) * trust / m
    local low, high = M.rateRange(buys, parts.hours or 0, M.SURE_PRIOR_HOURS)
    if not low then
        return sure, sure, sure, parts
    end
    local factor = (parts.sweep or 1) * (parts.fresh or 1)
    local days = M.SURE_HOURS / 24
    local lo = M.poissonTail(low * days, need) * factor
    local hi = M.poissonTail(high * days, need) * factor
    if parts.flow then
        lo, hi = math.min(lo, M.FLOW_SURE_MAX), math.min(hi, M.FLOW_SURE_MAX)
    end
    return sure, math.min(lo, sure), math.max(hi, sure), parts
end

-- Predictions against what happened. `records`: { { p = predicted chance (Sure), ok = sold within
-- the horizon }, ... }. Returns { n, brier, bins = { { from, to, n, predicted, observed }, ... } }
-- (5 bins of 20%); nil without records.
function M.calibration(records)
    local bins, n, brier = {}, 0, 0
    for i = 1, 5 do
        bins[i] = { from = (i - 1) / 5, to = i / 5, n = 0, predicted = 0, observed = 0 }
    end
    for _, r in ipairs(records or {}) do
        if type(r) == "table" and U.finite(r.p) then
            local p = math.max(0, math.min(1, r.p))
            local b = bins[math.min(5, math.floor(p * 5) + 1)]
            local hit = r.ok and 1 or 0
            b.n, b.predicted, b.observed = b.n + 1, b.predicted + p, b.observed + hit
            n, brier = n + 1, brier + (p - hit) ^ 2
        end
    end
    if n == 0 then
        return nil
    end
    for _, b in ipairs(bins) do
        if b.n > 0 then
            b.predicted, b.observed = b.predicted / b.n, b.observed / b.n
        else
            b.predicted, b.observed = nil, nil
        end
    end
    return { n = n, brier = brier / n, bins = bins }
end

-- Est./day against the units really sold: `records` = { { perDay, days, sold }, ... } (a
-- prediction, the days it covered, the units the player's invoices then showed). Returns
-- { n, predicted, observed, ratio = observed / predicted }; nil without records.
function M.rateCheck(records)
    local n, predicted, observed = 0, 0, 0
    for _, r in ipairs(records or {}) do
        if type(r) == "table" and U.finite(r.perDay) and U.finite(r.days) and r.days > 0 then
            n = n + 1
            predicted = predicted + r.perDay * r.days
            observed = observed + math.max(0, r.sold or 0)
        end
    end
    if n == 0 then
        return nil
    end
    return {
        n = n,
        predicted = predicted,
        observed = observed,
        ratio = predicted > 0 and observed / predicted or nil,
    }
end

-- Lowest prices seen outside full scans (the sniper's browse rounds, the player's searches) lower
-- today's cheapest price of an item. `r` = { id, minPrice, containsOwnerItem }. Only a commodity's
-- lowest price is a buyout (of other items it may be a bid), and a row with the player's own
-- units may show their price: full scans leave both out of the cheapest, and the player's own 40c
-- cloth read as a bargain below the usual 1 silver (Analytics, shared scans).
function M.learnLow(history, r, now)
    local kind = M.env.kindOf(r.id)
    if kind ~= "commodity" or r.containsOwnerItem then
        return
    end
    local h = history[U.key(kind, r.id)]
    if type(h) ~= "table" or type(h.days) ~= "table" then
        return
    end
    local today = h.days[#h.days]
    local day = math.floor(now / 86400)
    if today and today.d == day and (not today.min or r.minPrice < today.min) then
        today.min = r.minPrice
    end
end

-- Deposit of one auction: the game charges at least 1 silver (seen on WoW Forever); it is returned
-- on a sale and lost when the auction expires. Estimated from the vendor price (Classic rule).
--
-- What one unit of an item brings, the single sum every page shows (the tooltip, the Sell page and
-- its Best column, the posting queues through F.Trade.quote):
--   auction    = post price - the house cut - the deposits expected to be lost
--   lost       = (tries - 1) x deposit per unit: the deposit comes back with the sale, so only the
--                posts that expire before it cost money
--   tries      = posts it takes to sell one unit: from your own sale rate of the item once known,
--                else from the units measured sold per day at the post price (1 a day or more: one
--                post), else M.POSTINGS
-- and compares it with the vendor price and disenchanting (a character who can).
-- { best, value, post, vendor, vendorHow, auction, tries, lost, disenchant }; nil when nothing is known.
M.POSTINGS = 2
M.MAX_FAILED = 20
M.STACK = 20
-- `post` (optional): the price each to post at (F.Trade.quote); without it the usual price.
M.UNSEEN_SALES = 0.5
function M.advice(id, key, h, post)
    local item = U.parseKey(key)
    if not item then
        return nil
    end
    local vendor, vendorHow = M.env.vendorPrice(id, true)
    local out = { vendor = vendor, vendorHow = vendorHow }
    local price = post or (h and M.usual(h))
    price = U.finite(price) and U.stepDown(price, item.kind) or 0
    if price > 0 then
        local d = M.duration(key, item.kind == "commodity" and M.STACK or 1, price)
        local one = M.unitDeposit(id, item.kind, d)
        -- Sale rates are kept by the name of the mail or invoice: for gear the full name with its
        -- ending, which the key carries ("of Healing"); the item's own name lacks the ending.
        local name = item.kind == "gear" and item.name ~= "" and item.name or U.itemInfo(id)
        local rate = name and M.env.saleRate(name)
        -- s = the chance one post sells: your own share of posts that sold, else from the units
        -- sold a day over the post's duration (one unit, Poisson). Posts that expire before the
        -- sale lose their deposit: E[failed] = (1 - s) / s, at most M.MAX_FAILED. A known share of
        -- 0 (3 posts or more, none sold) is that worst case, not unknown: read as unknown, 0 of 50
        -- posted again with no deposit counted lost, while 1 of 20 counted 19.
        local success = 1 / M.POSTINGS
        if rate then
            success = rate
        elseif h then
            local s = M.saleability(h, price, M.env.clock() or 0)
            if s.known and s.perDay then
                -- No sale seen is no proof that none comes: over the hours the item was watched
                -- since its last sale at the price it counts as half a sale (Jeffreys), so a short
                -- watch leaves a fair chance and a long one nearly none. Taken as zero, a day
                -- without sales of a 28-silver glove booked 20 lost deposits against its post and
                -- sent it to a merchant for 3 silver. The hours are not decayed (s.quiet): the
                -- decayed ones level off near four days, and stay under one for a player who scans
                -- a few hours a day, so months without a sale kept a chance of 11-39% a post.
                local perDay = s.perDay
                if perDay <= 0 then
                    local watched = U.finite(s.quiet) and s.quiet or U.finite(s.hours) and s.hours or 24
                    perDay = M.UNSEEN_SALES / math.max(1, watched / 24)
                end
                local hours = M.env.durationHours(d) or 24
                success = 1 - math.exp(-perDay * hours / 24)
                out.perDay = s.perDay
            end
        end
        local failed = success > 0 and math.min(M.MAX_FAILED, (1 - success) / success) or M.MAX_FAILED
        out.tries = 1 + failed
        out.lost = math.floor(failed * one + 0.5)
        out.post = price
        out.auction = M.net(price, 1) - out.lost
    end
    if item.kind == "gear" and M.env.canDisenchant() then
        out.disenchant = M.env.disenchantValue(id)
    end
    for _, k in ipairs({ "vendor", "auction", "disenchant" }) do
        local v = out[k]
        if U.finite(v) and v > 0 and (not out.value or v > out.value) then
            out.best, out.value = k, v
        end
    end
    return out.best and out or nil
end

-- Held stock judged on each route apart (T11): the auction house and a vendor are two separate
-- tests, so a lot that passes one is not dropped from the other. `q` is a sell quote (F.Trade.quote:
-- post, net, lost, tries, perDay, vendor, vendorHow, cost, guess, belowFloor and its market*
-- fields), `count` the units, `s` the settings. Each route reads, for all `count` units:
--   revenue  what the buyers pay (the post price, or the vendor price)
--   cost     what the stock cost (0 when unknown)
--   cut      the house cut (auction only)
--   lost     the deposits expected to be lost before it sells (auction only)
--   profit   revenue - cut - lost - cost
--   threshold  the minimum profit (auction: minProfit and minROI; vendor: vendorMinProfit)
--   pass     the route clears its threshold
-- `both` is true when the two routes pass. nil fields mean the route cannot be judged.
function M.sellRoutes(q, count, s)
    q, s = q or {}, s or {}
    count = math.max(1, math.floor(tonumber(count) or 1))
    local each = U.finite(q.cost) and q.cost > 0 and q.cost or 0
    local cost = each * count
    local out = {}
    if U.finite(q.vendor) and q.vendor > 0 then
        local revenue = q.vendor * count
        local min = M.thresholds(s).vendorMinProfit
        out.vendor = {
            revenue = revenue,
            cost = cost,
            cut = 0,
            lost = 0,
            profit = revenue - cost,
            threshold = min,
            confirmed = q.vendorHow ~= "estimate",
            pass = revenue - cost >= min,
        }
    end
    -- The route is judged at the market price; a minimum above it only lifts the price posted.
    local post = q.belowFloor and q.marketPost or q.post
    local net = q.belowFloor and q.marketNet or q.net
    if not q.guess and U.finite(post) and post > 0 and U.finite(net) then
        local revenue = post * count
        local cut = revenue - M.net(post, count)
        local lost = ((q.belowFloor and q.marketLost or q.lost) or 0) * count
        local profit = revenue - cut - lost - cost
        local min, minROI = M.thresholds(s).minProfit, M.thresholds(s).minROI
        local roi = cost > 0 and profit / cost or nil
        out.auction = {
            revenue = revenue,
            cost = cost,
            cut = cut,
            lost = lost,
            profit = profit,
            roi = roi,
            threshold = min,
            minROI = minROI,
            tries = q.belowFloor and q.marketTries or q.tries,
            perDay = q.belowFloor and q.marketPerDay or q.perDay,
            pass = profit >= min and (roi == nil or roi >= minROI),
        }
    end
    out.both = (out.vendor and out.vendor.pass and out.auction and out.auction.pass) and true or false
    return out
end

-- Which route sells held stock when both pay (M.sellRoutes: `both`). The player is asked only when
-- the choice is really open; an obvious one is made here:
--   1. a vendor pays at least the auction house's profit (A) -> vendor: at once, nothing at risk;
--   2. the auction house, counting the chance it does not sell (E, below), adds less than
--      ROUTE_GAIN of the vendor's profit (V), and at least vendorMinProfit -> vendor: not worth
--      the wait;
--   3. nothing makes the auction house doubtful -> auction;
--   4. something does (Sure under ROUTE_SURE, too few sales to trust the figures, a price war on
--      the item) but a vendor pays under ROUTE_FAIR of A -> auction anyway: the vendor price is
--      too poor to fall back on;
--   5. otherwise -> undecided: the auction house likely pays more but may not, and a vendor pays
--      a fair price. The player chooses.
-- E = S x (AH revenue - cut) + (1 - S) x vendor revenue - lost deposits - cost: an unsold lot still
-- goes to a vendor afterwards. Without a Sure, E is the auction house's profit and the chance is
-- counted as a doubt. `info` = { sure, reliable, war }. Returns
-- { way = "vendor" | "auction" | "undecided", why, expected, gain, doubts = { "sure" | "sales" |
-- "war" } }, or nil when the two routes do not both pay.
M.ROUTE_GAIN = U.TUNING.routeGain
M.ROUTE_SURE = U.TUNING.routeSure
M.ROUTE_FAIR = U.TUNING.routeFair

function M.routeVerdict(routes, info, s)
    local a, v = routes and routes.auction, routes and routes.vendor
    if not (routes and routes.both and a and v) then
        return nil
    end
    info, s = info or {}, s or {}
    local out = { doubts = {} }
    local sure = U.finite(info.sure) and info.sure or nil
    if sure then
        out.expected = sure * (a.revenue - a.cut) + (1 - sure) * v.revenue - a.lost - a.cost
    else
        out.expected = a.profit
    end
    out.gain = out.expected - v.profit
    if v.profit >= a.profit then
        out.way, out.why = "vendor", "vendor_more"
        return out
    end
    if out.gain < math.max(M.ROUTE_GAIN * math.max(0, v.profit), M.thresholds(s).vendorMinProfit) then
        out.way, out.why = "vendor", "small_gain"
        return out
    end
    if not sure or sure < M.ROUTE_SURE then
        out.doubts[#out.doubts + 1] = "sure"
    end
    if info.reliable == false then
        out.doubts[#out.doubts + 1] = "sales"
    end
    if info.war then
        out.doubts[#out.doubts + 1] = "war"
    end
    if #out.doubts == 0 then
        out.way, out.why = "auction", "ah_more"
    elseif v.profit < M.ROUTE_FAIR * a.profit then
        out.way, out.why = "auction", "vendor_poor"
    else
        out.way, out.why = "undecided", "doubtful"
    end
    return out
end

-- Every deposit ForeverFlip counts comes from here, so advice, deals, the sniper, merchant offers,
-- crafting, bids, posts, cancels and the anti-undercut plan agree. The game's own deposit is used
-- when known (F.AH.depositFn); else it is estimated from the vendor price: 15% of it per unit for
-- the shortest duration, twice that for the middle one and four times for the longest, and at
-- least 1 silver per auction. A commodity stack is one auction and pays one deposit; other items
-- are one auction each.
M.DEPOSIT_TIMES = { 1, 2, 4 }

-- The duration a post of `qty` units of `key` at `price` goes for (1 to 3): the setting, or Auto's
-- choice for the item (Trade.durationFor: the deposits expected lost before it sells, the longer
-- duration when two are close, 24 hours while its sales are not known). Without a key: the
-- setting, or 24 hours.
function M.duration(key, qty, price)
    return M.env.durationFor(key, qty, price) or 3
end

-- Estimated deposit of one auction of `units` units of an item the vendor buys at `vendor`, posted
-- for duration `d` (default: the shortest).
function M.deposit(vendor, units, d)
    local times = M.DEPOSIT_TIMES[d or 1] or 1
    return math.max(100, math.floor((vendor or 0) * 0.15 * (units or 1)) * times)
end

-- Deposits a resale of `qty` units puts at risk: one auction for a commodity stack, one per item.
-- `deposit` (optional) is the game's deposit for a stack of n units (see F.AH.depositFn); the
-- estimate is for duration `d` (default: the duration posts go for now).
function M.depositRisk(kind, vendor, qty, deposit, d)
    d = d or M.duration()
    if kind == "commodity" then
        return deposit and deposit(qty) or M.deposit(vendor, qty, d)
    end
    return qty * (deposit and deposit(1) or M.deposit(vendor, 1, d))
end

-- The deposit of posting `qty` units of item `id` (kind "commodity", "gear" or "item", default:
-- the auction house's) for duration `d` (default: the duration posts go for now).
function M.postDeposit(id, kind, qty, d)
    d = d or M.duration()
    kind = kind or M.env.kindOf(id)
    return M.depositRisk(kind, M.env.clientVendorPrice(id), qty or 1, M.env.depositFn(id, kind, d), d)
end

-- The deposit per unit of a resale of `key` at `price`: a commodity goes as a stack of M.STACK
-- (one deposit shared by its units), other items one a post; for duration `d`, else the duration
-- the post would go for (M.duration). The sniper asks for it at every browse row: kept per item for
-- a minute (M.resetUnitDeposits when the game's deposits are read again).
local unitDeposits, unitDepositsAt = {}, nil
function M.resetUnitDeposits()
    unitDeposits, unitDepositsAt = {}, nil
end
function M.unitDeposit(id, kind, d, key, price)
    local minute = math.floor(M.env.clock() / 60)
    if minute ~= unitDepositsAt then
        unitDeposits, unitDepositsAt = {}, minute
    end
    -- Auto's choice is kept apart from a duration asked for, and apart for each duration setting.
    local slot = d or ("auto" .. tostring(M.env.durationSetting()))
    local byId = unitDeposits[slot]
    if not byId then
        byId = {}
        unitDeposits[slot] = byId
    end
    local v = byId[id]
    if not v then
        kind = kind or M.env.kindOf(id)
        local units = kind == "commodity" and M.STACK or 1
        v = M.postDeposit(id, kind, units, d or M.duration(key, units, price)) / units
        byId[id] = v
    end
    return v
end

-- T07: the price of an item over time, for the chart of the price history window. Built from the
-- daily history (`days`: { d = UTC day, m = usual price, min = cheapest }) and the raw full scans
-- (`scans`: { { at, unit = cheapest unit price, n = units listed }, ... }, Raw.pricePoints).
-- Returns { from, to, usual = { {t, v} }, cheap = { {t, v} }, scans = { {t, v, n} },
-- gaps = { {from, to} }, low, high, empty }: points in time order inside the last `span` days
-- (default M.SERIES_DAYS), and the stretches longer than M.SERIES_GAP seconds without any point
-- (no scan ran then: the line is not drawn across them).
M.SERIES_DAYS = 14
M.SERIES_GAP = 36 * 3600

function M.priceSeries(days, scans, now, span)
    span = span or M.SERIES_DAYS
    local from = (math.floor(now / 86400) - span + 1) * 86400
    local out = { from = from, to = now, usual = {}, cheap = {}, scans = {}, gaps = {} }
    local times = {}
    local function keep(list, t, v, n)
        if U.finite(t) and U.finite(v) and v > 0 and t >= from and t <= now then
            list[#list + 1] = { t = t, v = v, n = n }
            times[#times + 1] = t
            out.low = math.min(out.low or v, v)
            out.high = math.max(out.high or v, v)
        end
    end
    for _, d in ipairs(type(days) == "table" and days or {}) do
        if type(d) == "table" and U.finite(d.d) then
            -- A day's point at its middle, or now for today.
            local t = math.min(now, d.d * 86400 + 43200)
            keep(out.usual, t, d.m)
            keep(out.cheap, t, d.min)
        end
    end
    for _, s in ipairs(type(scans) == "table" and scans or {}) do
        if type(s) == "table" then
            keep(out.scans, s.at, s.unit, s.n)
        end
    end
    local function byTime(a, b)
        return a.t < b.t
    end
    table.sort(out.usual, byTime)
    table.sort(out.cheap, byTime)
    table.sort(out.scans, byTime)
    table.sort(times)
    out.empty = #times == 0
    local last = from
    for _, t in ipairs(times) do
        if t - last > M.SERIES_GAP then
            out.gaps[#out.gaps + 1] = { from = last, to = t }
        end
        last = t
    end
    if now - last > M.SERIES_GAP then
        out.gaps[#out.gaps + 1] = { from = last, to = now }
    end
    return out
end

-- True when no gap lies between times `a` and `b` (a <= b): the line may join the two points.
function M.seriesJoined(series, a, b)
    for _, g in ipairs(series.gaps or {}) do
        if a <= g.from and b >= g.to then
            return false
        end
    end
    return true
end

-- T31: the production chain of one unit of an item, for its tooltip. Four routes compared:
--   auction     net after the cut and the deposits expected lost (M.advice), with Sure
--   vendor      what a merchant pays
--   disenchant  the expected value of the materials after the cut (Disenchant.value)
--   craft       the item's worth as a material of the best recipe (M.craftValue)
-- `r`: { auction, sure, vendor, disenchant, craft = { value, name } } (nil: the route has no
-- figure). Returns { best = route, routes = { { route, value, sure, name }, ... } } with the routes
-- best first, or nil when no route has a figure.
M.SURE_UNLIKELY = 0.1
function M.chainRoutes(r)
    r = r or {}
    local routes = {}
    local function add(route, value, extra)
        if U.finite(value) and value > 0 then
            local x = { route = route, value = math.floor(value + 0.5) }
            for k, v in pairs(extra or {}) do
                x[k] = v
            end
            routes[#routes + 1] = x
        end
    end
    -- The auction house is ranked by what it is likely to bring (net x Sure), shown at its net;
    -- below M.SURE_UNLIKELY it is "unlikely to sell" and never recommended over another route.
    local sure = U.finite(r.sure) and math.max(0, math.min(1, r.sure)) or nil
    add("auction", r.auction, {
        sure = r.sure,
        post = r.post,
        score = sure and r.auction and r.auction * sure or nil,
        unlikely = sure ~= nil and sure < M.SURE_UNLIKELY or nil,
    })
    add("vendor", r.vendor)
    add("disenchant", r.disenchant)
    if type(r.craft) == "table" then
        add("craft", r.craft.value, { name = r.craft.name })
    end
    if #routes == 0 then
        return nil
    end
    local order = { auction = 1, vendor = 2, disenchant = 3, craft = 4 }
    table.sort(routes, function(a, b)
        if (a.unlikely or false) ~= (b.unlikely or false) then
            return not a.unlikely
        end
        local x, y = a.score or a.value, b.score or b.value
        if x ~= y then
            return x > y
        end
        return order[a.route] < order[b.route]
    end)
    return { best = routes[1].route, routes = routes }
end

-- What one unit of material `id` is worth crafted by a recipe row (Crafting.profits: value = what
-- the products bring, cost = every material at its price): the products' value less the other
-- materials, shared over the units of `id` the recipe takes. `unitCost` is the price of `id` that
-- row.cost counted. nil when the recipe does not take it or has no value.
function M.craftValue(row, id, unitCost)
    if type(row) ~= "table" or not U.finite(row.value) or not U.finite(row.cost) then
        return nil
    end
    local count = 0
    for _, m in ipairs(row.reagents or {}) do
        if m[1] == id then
            count = count + (m[2] or 0)
        end
    end
    if count <= 0 then
        return nil
    end
    local others = row.cost - (U.finite(unitCost) and unitCost or 0) * count
    return (row.value - others) / count
end

-- Money left after selling `qty` units at `price` each on the auction house.
function M.net(price, qty)
    local gross = price * qty
    return gross - math.floor(gross * M.CUT + 0.5)
end

-- What one unit sold at `price` brings after the cut and its share of the deposit (M.unitDeposit):
-- the per-unit value of a resale, as Bids, Sniper and the merchant's resale judge it.
function M.unitNet(id, kind, key, price)
    return M.net(price, 1) - M.unitDeposit(id, kind, nil, key, price)
end

-- What a post of `units` at `price` brings after the cut and the deposit, for the duration it would
-- go for (M.duration): net minus deposit, the net and the deposit.
function M.auctionNet(id, kind, key, price, units)
    units = math.max(1, units or 1)
    local deposit = M.postDeposit(id, kind, units, M.duration(key, units, price))
    local net = M.net(price, units)
    return net - deposit, net, deposit
end

-- Lowest legal listing price that returns `cost` for `qty` units after the cut.
function M.breakEven(cost, qty, kind)
    -- Not below the cost itself. The cut is rounded, so the price that returns the cost can be a
    -- step or two below cost / (1 - CUT): from there, down while a step lower still returns it,
    -- then up until it does (net only grows with the price). Stepping up from the cost took half
    -- a million steps for a 1000-gold commodity.
    local step = kind == "commodity" and 1 or 100
    local low = math.max(step, U.stepUp(cost / qty, kind))
    local price = math.max(low, U.stepUp(cost / qty / (1 - M.CUT), kind))
    while price - step >= low and M.net(price - step, qty) >= cost do
        price = price - step
    end
    while M.net(price, qty) < cost do
        price = price + step
    end
    return price
end

-- T25: resale below the median ("Below median" on the Deals page, opt-in). Lots priced under the
-- item's median of the last M.MEDIAN_DAYS daily usual prices are bought and relisted at that
-- median. It is a strategy of its own, with its own money limits. An item whose sales sample is
-- not reliable (M.quality) is offered `weak` (greyed in Deals, "few sales data"): at most a day of
-- its measured sales, one unit when none is measured. Hidden, the page stayed empty for every player
-- without two scan pairs of an item, and nobody could tell why.
M.MEDIAN_DAYS = 7 -- daily usual prices the median is taken over
M.MEDIAN_MIN_DAYS = 3 -- fewer days of prices give no median
M.MEDIAN_HOLD_DAYS = 3 -- at most this many days of the item's sales are bought
M.MEDIAN_WEAK_DAYS = 1 -- a weak find: at most this many days of its sales (at least one unit)
M.RESET_MAX_LOTS = 40 -- a market reset of more lots than this is too much to buy in clicks

-- The median of an item's daily usual prices over the last `span` days before `now` (today
-- included); nil and the days found when fewer than M.MEDIAN_MIN_DAYS have a price.
function M.medianTarget(h, now, span)
    span = span or M.MEDIAN_DAYS
    local days = type(h) == "table" and type(h.days) == "table" and h.days or {}
    local today = math.floor((now or 0) / 86400)
    local values = {}
    for _, d in ipairs(days) do
        if type(d) == "table" and U.finite(d.m) and d.m > 0 and U.finite(d.d) then
            if d.d <= today and d.d > today - span then
                values[#values + 1] = d.m
            end
        end
    end
    if #values < M.MEDIAN_MIN_DAYS then
        return nil, #values
    end
    table.sort(values)
    local n = #values
    local median = n % 2 == 1 and values[(n + 1) / 2] or math.floor((values[n / 2] + values[n / 2 + 1]) / 2 + 0.5)
    return median, n
end

-- The usual price the strategy relists at: the 7-day median when there are M.MEDIAN_MIN_DAYS days
-- of prices; otherwise the lowest of what is known (the days there are, the last usual price,
-- the measured market price), marked `short` so the find is offered weak. The page was empty
-- for nearly every item ("19464 have fewer than 3 days of prices"): a day of scans is enough now.
-- Returns price, days of prices, short; nil when nothing at all is known.
function M.usualTarget(h, now)
    local median, n = M.medianTarget(h, now)
    if median then
        return median, n, false
    end
    if type(h) ~= "table" then
        return nil, 0
    end
    local values = {}
    local today = math.floor((now or 0) / 86400)
    for _, d in ipairs(type(h.days) == "table" and h.days or {}) do
        if type(d) == "table" and U.finite(d.m) and d.m > 0 and U.finite(d.d) then
            if d.d <= today and d.d > today - M.MEDIAN_DAYS then
                values[#values + 1] = d.m
            end
        end
    end
    local usual = M.usual(h)
    if usual then
        values[#values + 1] = usual
    end
    if type(h.flow) == "table" and U.finite(h.flow.market) and h.flow.market > 0 then
        values[#values + 1] = h.flow.market
    end
    if #values == 0 then
        return nil, n or 0
    end
    -- The lowest of them: with this little data the target stays cautious.
    table.sort(values)
    return values[1], n or 0, true
end

-- Evaluates one item's listings (cheapest first) for a market reset (Deals -> Market reset): every
-- lot under the item's usual price bought at once, to relist alone at that price.
-- ctx: kind, history, now, market (the resale cap, D.resaleCap, or nil), held (units in stock),
-- budget (copper this item may take: the smallest of the strategy's limits), trust, deposit,
-- depositVendor, duration, settings {minProfit, minROI}.
-- Returns the deal { mode = "flip", strategy = "median", qty, cost, exit, median, days, profit,
-- roi, maxUnit, lots, perDay, quality, sure, sureLow, sureHigh, weak } or nil and a reason:
-- "no_median" (too few days of prices), "sources_disagree"
-- (own and shared medians far apart, M.sourcesDisagree), "no_gap",
-- "budget", "enough_stock", "small", "too_much" (more on sale under the price than sells in a few
-- days, or more lots than M.RESET_MAX_LOTS).
function M.evaluateMedian(rows, ctx)
    local s = ctx.settings or {}
    local kind = ctx.kind
    local h = ctx.history
    local now = ctx.now or 0
    local median, days, short = M.usualTarget(h, now)
    if not median then
        return nil, "no_median"
    end
    local target = median
    if U.finite(ctx.market) and ctx.market > 0 then
        target = math.min(target, ctx.market)
    end
    local exit = U.stepDown(target, kind)
    if not U.finite(exit) or exit <= 0 then
        return nil, "no_median"
    end
    local q = M.quality(h, exit, now)
    local weak = not q.reliable or short
    -- T24: own scans and shared scans far apart: the combined median mixes two different pictures.
    if M.sourcesDisagree(h, now) then
        return nil, "sources_disagree"
    end
    local trust = U.finite(ctx.trust) and ctx.trust or 1
    local perDay = (q.perDay or 0) * trust
    local held = ctx.held or 0
    -- A market reset buys EVERY unit listed under the price it relists at, or nothing: a seller
    -- left below it would sell first and the reset would be a plain resale (Deals -> Resale buys
    -- part of the listings under a higher price that stays). Units at or above the relist price
    -- are no competition and stay.
    local qty, cost, used, maxUnit = 0, 0, {}, 0
    for _, r in ipairs(rows) do
        if r.unit >= exit then
            break
        end
        qty, cost = qty + r.qty, cost + r.qty * r.unit
        used[#used + 1] = { unit = r.unit, qty = r.qty, auctionID = r.auctionID }
        maxUnit = r.unit
    end
    if qty < 1 then
        return nil, "no_gap"
    end
    if #used > M.RESET_MAX_LOTS then
        return nil, "too_much"
    end
    -- The whole supply must sell in a few days of the item's sales (a day with weak data). One
    -- unit on trust only while its sales are not measured well: a reliable sample with no sale is
    -- an item nobody buys at that price, however few days its price is known (a 5g lot offered to
    -- relist at an asking price of 990g that never sold, Sure 4%, Est./day 0).
    local cap = math.floor(perDay * (weak and M.MEDIAN_WEAK_DAYS or M.MEDIAN_HOLD_DAYS)) - held
    if weak and not (q.reliable and perDay <= 0) then
        cap = math.max(cap, 1 - held)
    end
    if cap < 1 then
        return nil, held > 0 and "enough_stock" or "not_selling"
    end
    if qty > cap then
        return nil, "too_much"
    end
    if cost > (ctx.budget or 0) then
        return nil, "budget"
    end
    local risk = M.depositRisk(kind, ctx.depositVendor, qty, ctx.deposit, ctx.duration)
    local profit = M.net(exit, qty) - cost - risk
    local roi = cost > 0 and profit / cost or 0
    if profit < M.thresholds(s).minProfit or roi < M.thresholds(s).minROI then
        return nil, profit > 0 and "small" or "no_gap"
    end
    local best = {
        mode = "flip",
        strategy = "median",
        qty = qty,
        cost = cost,
        exit = exit,
        median = median,
        days = days,
        profit = profit,
        roi = roi,
        risk = risk,
        maxUnit = maxUnit,
        lots = used,
        perDay = perDay,
        reset = true,
    }
    best.quality, best.weak = q, weak or nil
    local sure, low, high = M.sureLimits(h, exit, best.qty + held, now, trust)
    -- Measured well and unlikely to sell in its days: the profit is only on paper.
    if q.reliable and U.finite(sure) and sure < M.SURE_UNLIKELY then
        return nil, "not_selling"
    end
    best.sure, best.sureLow, best.sureHigh = sure, low, high
    return best
end

-- T24: market reference -----------------------------------------------------------------------------
-- What an item's price has been, by source, for its tooltip and its history window. Only the
-- history of the open house is read (it is kept per house and faction), so houses never mix:
--   own        the player's own full scans; the only source of what was listed at a scan (the
--              cheapest unit and the units of the last scan, h.scan.low and h.units)
--   community  scans shared by other players (guild, realm channel, the Sync helper's community
--              data): observations of the market, never a listing
--   external   reserved and empty: Undermine Exchange documents no API for WoW Forever
-- Each day record keeps the combined usual price and cheapest (m, min: what the median strategy
-- reads) and, per source, lm/lmin (own scans) and cm/cmin (shared scans). Older records without
-- them count in the combined figures only.
M.REF_DAYS = 14
M.REF_MIN_DAYS = 5 -- days of prices before an item can be called undervalued
M.REF_UNDER = 0.75 -- the cheapest at most this share of the median is undervalued
M.REF_SPLIT_DAYS = 3 -- days each source needs before the two are compared
M.REF_DISAGREE = 0.25 -- own and community medians further apart than this disagree
M.REF_CURRENT_AGE = 2 * 3600 -- an own scan older than this says nothing of the cheapest now
M.TREND_SPANS = { 3, 7, 14 }
M.TREND_MIN_DAYS = 3

-- The day records' `field` prices of the last `span` days before `now` (today included), oldest
-- first: { { d, v }, ... }.
function M.dayPrices(days, now, span, field)
    local today = math.floor((now or 0) / 86400)
    local out = {}
    for _, d in ipairs(type(days) == "table" and days or {}) do
        local v = type(d) == "table" and d[field]
        if U.finite(v) and v > 0 and U.finite(d.d) and d.d <= today and d.d > today - span then
            out[#out + 1] = { d = d.d, v = v }
        end
    end
    table.sort(out, function(a, b)
        return a.d < b.d
    end)
    return out
end

-- { n, median, mean, low, high, first, last (day numbers) } of the points' prices; { n = 0 } without.
function M.priceStats(points)
    local values, sum = {}, 0
    for _, p in ipairs(points or {}) do
        values[#values + 1] = p.v
        sum = sum + p.v
    end
    local n = #values
    if n == 0 then
        return { n = 0 }
    end
    table.sort(values)
    local median = n % 2 == 1 and values[(n + 1) / 2] or (values[n / 2] + values[n / 2 + 1]) / 2
    return {
        n = n,
        median = math.floor(median + 0.5),
        mean = math.floor(sum / n + 0.5),
        low = values[1],
        high = values[n],
        first = points[1].d,
        last = points[n].d,
    }
end

-- The price trend over the last `span` days: { span, n = days with a price, change = last / first
-- - 1, slope = least-squares change a day as a share of the mean }; nil and n with fewer than
-- M.TREND_MIN_DAYS days.
function M.trend(points, now, span)
    local today = math.floor((now or 0) / 86400)
    local pts = {}
    for _, p in ipairs(points or {}) do
        if p.d <= today and p.d > today - span then
            pts[#pts + 1] = p
        end
    end
    local n = #pts
    if n < M.TREND_MIN_DAYS then
        return nil, n
    end
    local sx, sy, sxx, sxy = 0, 0, 0, 0
    for _, p in ipairs(pts) do
        local x = p.d - today
        sx, sy, sxx, sxy = sx + x, sy + p.v, sxx + x * x, sxy + x * p.v
    end
    local denom = n * sxx - sx * sx
    local slope = denom > 0 and (n * sxy - sx * sy) / denom or 0
    local mean = sy / n
    return { span = span, n = n, change = pts[n].v / pts[1].v - 1, slope = mean > 0 and slope / mean or 0 }
end

-- How far apart the own and the community medians are, as a share of the lower; nil while either
-- has fewer than M.REF_SPLIT_DAYS days.
function M.sourceGap(own, community)
    if
        not own
        or not community
        or (own.n or 0) < M.REF_SPLIT_DAYS
        or (community.n or 0) < M.REF_SPLIT_DAYS
        or not U.finite(own.median)
        or not U.finite(community.median)
    then
        return nil
    end
    local low = math.min(own.median, community.median)
    if low <= 0 then
        return nil
    end
    return math.abs(own.median - community.median) / low
end

-- True (and the gap) when the item's own and community prices of the last M.REF_DAYS disagree by
-- more than M.REF_DISAGREE: the combined median is then no target to buy below (T25 risk).
function M.sourcesDisagree(h, now)
    local days = type(h) == "table" and h.days or nil
    local gap = M.sourceGap(
        M.priceStats(M.dayPrices(days, now, M.REF_DAYS, "lm")),
        M.priceStats(M.dayPrices(days, now, M.REF_DAYS, "cm"))
    )
    return gap ~= nil and gap > M.REF_DISAGREE, gap
end

-- Whether the cheapest of the last own scan is well below the combined median (information only).
-- { flagged, reason, ratio, days, need }; reason when not flagged: "no_current" (no own scan with a
-- price), "old_scan" (older than M.REF_CURRENT_AGE), "few_days" (fewer than M.REF_MIN_DAYS days of
-- prices), "no_reliable" (M.quality `q` not reliable), "disagree" (own and community medians far
-- apart), "no_gap".
function M.undervalued(ref, q)
    local c, med = ref.current, ref.combined
    local u = { flagged = false, days = med.n, need = M.REF_MIN_DAYS }
    if not c then
        u.reason = "no_current"
    elseif c.age > M.REF_CURRENT_AGE then
        u.reason = "old_scan"
    elseif med.n < M.REF_MIN_DAYS then
        u.reason = "few_days"
    elseif not (q and q.reliable) then
        u.reason = "no_reliable"
    elseif ref.disagree then
        u.reason = "disagree"
    else
        u.ratio = c.price / med.median
        if u.ratio <= M.REF_UNDER then
            u.flagged = true
        else
            u.reason = "no_gap"
        end
    end
    return u
end

-- The market reference of one item (its history `h` of the open house) at `now`:
-- { combined, own, community = M.priceStats + seen (time of the last scan of that source),
--   current = { price, at, age, units, vsMedian, vsMean } (the last own scan) or nil,
--   community.cheapest/units (its last shared scan), external = { available = false, reason },
--   trends = { { span, n, change, slope } or { span, n }, ... }, gap, disagree, under }.
function M.marketReference(h, now)
    h = type(h) == "table" and h or {}
    local days = h.days
    local all = M.dayPrices(days, now, M.REF_DAYS, "m")
    local ref = {
        combined = M.priceStats(all),
        own = M.priceStats(M.dayPrices(days, now, M.REF_DAYS, "lm")),
        community = M.priceStats(M.dayPrices(days, now, M.REF_DAYS, "cm")),
        external = { available = false, reason = "no_api" },
        trends = {},
    }
    local scan = type(h.scan) == "table" and h.scan or nil
    if scan and U.finite(scan.at) then
        ref.own.seen = scan.at
        if U.finite(scan.low) and scan.low > 0 then
            local c = { price = scan.low, at = scan.at, age = math.max(0, now - scan.at) }
            c.units = U.finite(h.units) and h.units or nil
            if U.finite(ref.combined.median) and ref.combined.median > 0 then
                c.vsMedian = c.price / ref.combined.median - 1
                c.vsMean = c.price / ref.combined.mean - 1
            end
            ref.current = c
        end
    end
    local shared = type(h.shared) == "table" and h.shared or nil
    if shared and U.finite(shared.at) then
        ref.community.seen = shared.at
        ref.community.cheapest = U.finite(shared.min) and shared.min or nil
        ref.community.units = U.finite(shared.n) and shared.n or nil
    end
    for _, span in ipairs(M.TREND_SPANS) do
        local t, n = M.trend(all, now, span)
        ref.trends[#ref.trends + 1] = t or { span = span, n = n }
    end
    ref.gap = M.sourceGap(ref.own, ref.community)
    ref.disagree = ref.gap ~= nil and ref.gap > M.REF_DISAGREE
    ref.under = M.undervalued(ref, M.quality(h, ref.combined.median, now))
    return ref
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
        -- A vendor deal is sure money (a merchant pays at once). The offer is what the shelf holds
        -- below the vendor price; `qty` and `cost` are the part the bags can pay for now
        -- (ctx.vendorBudget, else the ordinary budget of ctx.budget), and `offer` is every unit: a
        -- lot too dear for the purse is still worth seeing, so the table shows the whole offer with
        -- the money it needs (F.Deals.fitWallet splits it against the wallet on every refresh).
        local money = ctx.vendorBudget or budget
        local qty, cost, used = 0, 0, {}
        -- Setting vendorMinProfit is per unit: only lots that each earn it are taken. Counted on
        -- the whole deal, 3 units at 7c passed a 15c minimum, and the page showed profits of 7c.
        local limit = M.maxBuy(ctx.vendor, "vendor", s)
        local below = rows[1] ~= nil and rows[1].unit < ctx.vendor
        -- Setting leaveLots: the priciest units below the vendor price stay listed for others.
        local cheap, leave = 0, math.max(0, math.floor(s.leaveLots or 0))
        for _, r in ipairs(rows) do
            if r.unit > limit then
                break
            end
            cheap = cheap + r.qty
        end
        local allowed = cheap - leave
        local offerQty, offerCost, offerLots = 0, 0, {}
        for _, r in ipairs(rows) do
            if r.unit > limit or offerQty >= allowed then
                break
            end
            local take = math.min(r.qty, allowed - offerQty)
            offerQty, offerCost = offerQty + take, offerCost + take * r.unit
            offerLots[#offerLots + 1] = { unit = r.unit, qty = take, auctionID = r.auctionID }
            -- What the money covers, cheapest lots first, for the part that can be bought now.
            -- A commodity takes part of a lot; an item row is a bucket of identical auctions and
            -- takes as many whole ones as the money buys.
            local fits = take
            if U.finite(money) then
                fits = math.max(0, math.min(take, math.floor((money - cost) / r.unit)))
            end
            if fits >= 1 then
                qty, cost = qty + fits, cost + fits * r.unit
                used[#used + 1] = { unit = r.unit, qty = fits, auctionID = r.auctionID }
            end
        end
        -- The offer as found: it is what the row shows, and the lots the affordable part is taken
        -- from (Fit to wallet re-splits it whenever the purse changes).
        local offer = {
            qty = offerQty,
            cost = offerCost,
            profit = offerQty * ctx.vendor - offerCost,
            roi = offerCost > 0 and (offerQty * ctx.vendor - offerCost) / offerCost or 0,
            lots = offerLots,
        }
        local profit = qty * ctx.vendor - cost
        if qty > 0 then
            best = {
                mode = "vendor",
                qty = qty,
                cost = cost,
                exit = ctx.vendor,
                profit = profit,
                roi = profit / cost,
                maxUnit = used[#used].unit,
                lots = used,
                offer = offer,
            }
        elseif offerQty > 0 then
            -- Nothing fits the purse, but the offer is real: it is listed with no money of its own
            -- (qty 0), so the player sees the deal and the money it needs. `short` marks it.
            best = {
                mode = "vendor",
                qty = 0,
                cost = 0,
                exit = ctx.vendor,
                profit = offer.profit,
                roi = offer.roi,
                maxUnit = offerCost > 0 and math.floor(offerCost / math.max(1, offerQty) + 0.5) or nil,
                lots = {},
                offer = offer,
                short = true,
            }
        elseif below then
            reason = "small"
        end
    end

    -- A deal is returned alone: `best and nil or reason` is always `reason`.
    if ctx.vendorOnly then
        if best then
            return best
        end
        return nil, reason
    end
    -- Watched and never seen sold: the asking prices are no price to resell at (in game, gear
    -- bought at 27 silver to resell at the 94 silver others asked, and nobody paid that).
    if ctx.noResale then
        if best then
            return best
        end
        return nil, reason == "no_gap" and "not_selling" or reason
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
            if cost == 0 then
                reason = "budget"
            end
            break
        end
        qty, cost = qty + take, cost + take * r.unit
        used[#used + 1] = { unit = r.unit, qty = take, auctionID = r.auctionID }
        local nextUnit = take < r.qty and r.unit or (rows[i + 1] and rows[i + 1].unit)
        -- The prices this prefix may sell at: one step under the next lot left (the highest; within
        -- the player's maximum share of the usual price), and below it what buyers really paid
        -- (M.saleCap). The median is Market reset's price, not Resale's. Each is judged by the sales seen at it (Est./day caps
        -- the units, Sure weighs the money): the one expected to bring the most wins, so Resale
        -- sells where it is bought, and buys only what sells there.
        local prices = {}
        local function add(price, why)
            if U.finite(price) and price > r.unit then
                for _, x in ipairs(prices) do
                    if x.price == price then
                        return
                    end
                end
                prices[#prices + 1] = { price = price, why = why }
            end
        end
        local top, topWhy
        if U.finite(ctx.usual) then
            top, topWhy = M.postPrice({
                kind = kind,
                usual = ctx.usual,
                cheapest = nextUnit,
                limit = ctx.limit,
                undercut = ctx.undercut,
            })
        else
            top, topWhy = M.postPrice({ kind = kind, usual = market, cap = market, cheapest = nextUnit })
        end
        add(top, topWhy)
        if U.finite(top) then
            if U.finite(ctx.saleCap) and ctx.saleCap > 0 and U.stepDown(ctx.saleCap, kind) < top then
                add(U.stepDown(ctx.saleCap, kind), "sales")
            end
        end
        local risk = M.depositRisk(kind, ctx.depositVendor or ctx.vendor, qty, ctx.deposit, ctx.duration)
        local stop = false
        for _, candidate in ipairs(prices) do
            local exit, exitWhy = candidate.price, candidate.why
            local profit = M.net(exit, qty) - cost - risk
            if profit > 0 then
                local d = M.demandAt(ctx.history, exit)
                -- Own results: stock of this item that did not sell lowers the scan estimate.
                d.perDay = d.perDay * (ctx.trust or 1)
                if d.pairs < 1 then
                    reason, stop = "collecting", true
                    break
                end
                local roi = profit / cost
                -- One pair of scans (15 minutes) is a thin sample: at most 2 units until a second.
                local cap = math.max(1, math.floor(d.perDay))
                local thin = false
                if d.pairs < 2 and cap > 2 then
                    cap, thin = 2, true
                end
                -- No more units than were ever seen bought at the price: a day rate made of one or
                -- two purchases is no promise of more (seen in game: a few sales read as 20 a day).
                local seen = U.finite(d.sold) and math.floor(d.sold + 0.5) or nil
                if seen and seen < cap then
                    cap, thin = math.max(1, seen), true
                end
                if d.perDay < 0.5 or qty + held > cap then
                    if reason ~= "small" then
                        -- "thin": it sells, but too few purchases were seen yet to buy this many.
                        reason = held > 0 and d.perDay >= 0.5 and "enough_stock"
                            or (thin and d.perDay >= 0.5) and "thin"
                            -- Under an hour of scans (a fresh start) proves nothing about the
                            -- price: the item is still being learned, not refused.
                            or not M.watched(ctx.history) and not M.watched({
                                sales = type(ctx.history) == "table" and ctx.history.flow,
                            }) and "collecting"
                            or "not_selling"
                    end
                elseif profit >= M.thresholds(s).minProfit and roi >= M.thresholds(s).minROI then
                    -- Sure of selling them at the price: the money expected, not hoped for.
                    local sure = M.confidence(ctx.history, exit, qty + held, ctx.now, ctx.trust)
                    if U.finite(sure) then
                        sure = math.max(0, math.min(1, sure))
                    else
                        -- No Sure yet: only a price buyers were seen paying counts as safe.
                        local paid = U.finite(ctx.saleCap) and ctx.saleCap > 0 and ctx.saleCap or nil
                        sure = (not paid or exit <= paid) and 1 or 0
                    end
                    local expected = sure * M.net(exit, qty) - cost - risk
                    if not flip or expected > flip.expected then
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
                            expected = expected,
                            -- Where the exit price came from (M.postPrice; the Resale panel and
                            -- the tooltip say why): the next lot left on sale, or what sells.
                            exitNext = nextUnit,
                            exitWhy = exitWhy,
                        }
                    end
                else
                    reason = "small"
                end
            end
        end
        if stop then
            break
        end
        if take < r.qty or i >= 40 then
            break
        end
    end
    -- The two routes are judged on their own: a lot that passes both is a vendor deal and a resale.
    -- The one that pays more leads (the All list, the tooltip); the other rides along as `alt`, so
    -- the Resale and To vendor lists each still show it.
    if flip and best then
        if flip.profit > best.profit then
            flip.alt, best = best, flip
        else
            best.alt = flip
        end
    elseif flip then
        best = flip
    end
    if best then
        return best
    end
    return nil, reason
end
