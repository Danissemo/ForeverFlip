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
    local s = type(h) == "table" and h.sales
    if type(s) == "table" and (s.pairs or 0) >= 1 and U.finite(price) and price > 0 then
        local d = M.lotDemand(h, price)
        out.pairs, out.at, out.hours = s.pairs, s.at, s.hours
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

local function compatible(prev, i, cur, k)
    local a, b = 3 * i - 2, 3 * k - 2
    return prev[a] == cur[b] and cur[b + 1] <= prev[a + 1] and cur[b + 2] <= prev[a + 2]
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
        if k <= nc and compatible(prev, i, cur, k) then
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
                if compatible(prev, i, cur, c) then
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
    for i = 1, np do
        local price, count, band = prev[3 * i - 2], prev[3 * i - 1], prev[3 * i]
        if not match[i] then
            local key = price .. ":" .. count
            local o = prevOwners and prevOwners[i] or 0
            if (reposted[key] or 0) > 0 then
                reposted[key] = reposted[key] - 1
            elseif o > 0 and (sellers[o] or 0) > 0 then
                sellers[o] = sellers[o] - 1 -- the same seller posted again: a repost
            elseif (M.BAND_MIN[band] or 0) >= dt and price <= cheapest then
                add(price, count)
                gone[#gone + 1] = price
                gone[#gone + 1] = count
                gone[#gone + 1] = o
            end
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
-- One-off sweeps: a pair that saw more than M.SWEEP times the median of the pairs before it (at
-- least 3) is counted at that ceiling: one buyer clearing a shelf (often another reseller) is no
-- daily demand, and counting it whole let one scan pair decide a day of buying.
M.SALE_LOG = 30
M.SWEEP = 3
-- `undercuts` (optional): new lots posted below the cheapest lot of the scan before, kept decayed
-- in s.cuts like the sales (M.undercutRate).
function M.recordSales(h, byPrice, dt, now, lots, undercuts)
    local s = type(h.sales) == "table" and h.sales or { hours = 0, pairs = 0, at = now, b = {} }
    s.b = type(s.b) == "table" and s.b or {}
    local total = 0
    for price, units in pairs(byPrice) do
        if price > 0 and units > 0 then
            total = total + units
        end
    end
    local scale = 1
    s.recent = type(s.recent) == "table" and s.recent or {}
    if dt > 0 then
        if #s.recent >= 3 then
            local sorted = {}
            for i, v in ipairs(s.recent) do
                sorted[i] = v
            end
            table.sort(sorted)
            local median = sorted[math.floor((#sorted + 1) / 2)]
            local ceiling = math.max(5, M.SWEEP * median)
            if total > ceiling then
                scale = ceiling / total
                s.sweeps = (s.sweeps or 0) + 1
            end
        end
        s.recent[#s.recent + 1] = total * scale
        while #s.recent > 12 do
            table.remove(s.recent, 1)
        end
    end
    local decay = 0.5 ^ (math.max(0, now - (s.at or now)) / M.SALE_HALF_LIFE)
    s.sure = (s.sure or 0) * decay
    s.lots = (s.lots or 0) * decay
    s.cuts = (s.cuts or 0) * decay + (dt > 0 and undercuts or 0)
    s.log = type(s.log) == "table" and s.log or {}
    s.hours = (s.hours or 0) * decay + dt / 3600
    for b, units in pairs(s.b) do
        if b % 2 == 0 then
            if units * decay < 0.01 then
                s.b[b], s.b[b + 1] = nil, nil
            else
                s.b[b] = units * decay
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
            s.sure = s.sure + (units - whole) * scale
            if whole > 0 then
                s.log[#s.log + 1] = string.format("%d:%.0f:%d:l", now, price, whole)
            end
            if units - whole > 0 then
                s.log[#s.log + 1] = string.format("%d:%.0f:%d:p", now, price, units - whole)
            end
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

-- Units per day sold at or above 85% of `price` from the lot-tracked sales; nil without data.
local function lotDemand(h, price)
    local s = type(h) == "table" and h.sales
    if type(s) ~= "table" or (s.pairs or 0) < 1 or not U.finite(s.hours) or s.hours <= 0 then
        return nil
    end
    local floor, units = 0.85 * price, 0
    for b, n in pairs(s.b or {}) do
        if b % 2 == 0 and s.b[b + 1] >= floor then
            units = units + n
        end
    end
    return { pairs = s.pairs, perDay = units / (s.hours + M.PRIOR_HOURS) * 24, sold = units, hours = s.hours }
end
M.lotDemand = lotDemand

-- Undercuts of an item per hour: new lots posted below the cheapest lot, over the hours its lots
-- were watched (with the same prior hours as the sales, so one scan pair does not decide it).
-- { perHour, cuts, hours }; nil before the first scan pair.
function M.undercutRate(h)
    local s = type(h) == "table" and h.sales
    if type(s) ~= "table" or (s.pairs or 0) < 1 or not U.finite(s.hours) then
        return nil
    end
    local cuts = U.finite(s.cuts) and s.cuts or 0
    return { perHour = cuts / (s.hours + M.PRIOR_HOURS), cuts = cuts, hours = s.hours }
end

-- Lowest prices seen outside full scans (the sniper's browse rounds, the player's searches) lower
-- today's cheapest price of an item. `r` = { id, minPrice }.
function M.learnLow(history, r, now)
    local kind = F.AH and F.AH.kindOf and F.AH.kindOf(r.id)
    if not kind or kind == "gear" then
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
M.STACK = 20
-- `post` (optional): the price each to post at (F.Trade.quote); without it the usual price.
function M.advice(id, key, h, post)
    local item = U.parseKey(key)
    if not item then
        return nil
    end
    local vendor, vendorHow = F.AH.vendorPrice(id, true)
    local out = { vendor = vendor, vendorHow = vendorHow }
    local price = post or (h and M.usual(h))
    price = U.finite(price) and U.stepDown(price, item.kind) or 0
    if price > 0 then
        local depositFn = F.AH.depositFn(id, item.kind, F.Trade.durationFor and F.Trade.durationFor() or 3)
        -- Commodities are posted as a stack and pay one deposit for it: per unit it is the deposit
        -- of a stack of M.STACK, divided. Other items pay a deposit each.
        local units = item.kind == "commodity" and M.STACK or 1
        local stack = depositFn and depositFn(units) or M.deposit(F.AH.clientVendorPrice(id), units)
        local one = stack / units
        local name = U.itemInfo(id)
        local rate = name and F.Trade.rate(name)
        local tries = M.POSTINGS
        if rate and rate > 0 then
            tries = math.ceil(1 / rate)
        elseif h then
            local s = M.saleability(h, price, F.Engine and F.Engine.clock and F.Engine.clock() or 0)
            if s.known and s.perDay and s.perDay > 0 then
                tries = math.ceil(1 / s.perDay)
                out.perDay = s.perDay
            end
        end
        out.tries = math.max(1, math.min(5, tries))
        out.lost = math.floor((out.tries - 1) * one + 0.5)
        out.post = price
        out.auction = M.net(price, 1) - out.lost
    end
    if item.kind == "gear" and F.Disenchant.canDisenchant() then
        out.disenchant = F.Disenchant.value(id)
    end
    for _, k in ipairs({ "vendor", "auction", "disenchant" }) do
        local v = out[k]
        if U.finite(v) and v > 0 and (not out.value or v > out.value) then
            out.best, out.value = k, v
        end
    end
    return out.best and out or nil
end

function M.deposit(vendor, units)
    return math.max(100, math.floor((vendor or 0) * 0.15 * (units or 1)))
end

-- Deposits a resale of `qty` units puts at risk: one auction for a commodity stack, one per item.
-- `deposit` (optional) is the game's deposit for a stack of n units (see F.AH.depositFn).
function M.depositRisk(kind, vendor, qty, deposit)
    if kind == "commodity" then
        return deposit and deposit(qty) or M.deposit(vendor, qty)
    end
    return qty * (deposit and deposit(1) or M.deposit(vendor, 1))
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
        -- Setting leaveLots: the priciest units below the vendor price stay listed for others.
        local cheap, leave = 0, math.max(0, math.floor(s.leaveLots or 0))
        for _, r in ipairs(rows) do
            if r.unit >= ctx.vendor then
                break
            end
            cheap = cheap + r.qty
        end
        local allowed = cheap - leave
        for _, r in ipairs(rows) do
            if r.unit >= ctx.vendor or qty >= allowed then
                break
            end
            local take = math.min(r.qty, allowed - qty)
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
    -- Watched and never seen sold: the asking prices are no price to resell at (in game, gear
    -- bought at 27 silver to resell at the 94 silver others asked, and nobody paid that).
    if ctx.noResale then
        return best, best and nil or (reason == "no_gap" and "not_selling" or reason)
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
        local exit = nextUnit and U.below(nextUnit, kind) or U.stepDown(market or 0, kind)
        if U.finite(market) and market > 0 then
            exit = math.min(exit, U.stepDown(market, kind))
        end
        local profit = exit > r.unit
                and M.net(exit, qty) - cost - M.depositRisk(kind, ctx.depositVendor or ctx.vendor, qty, ctx.deposit)
            or 0
        if profit > 0 then
            local d = M.demandAt(ctx.history, exit)
            -- Own results: stock of this item that did not sell lowers the scan estimate.
            d.perDay = d.perDay * (ctx.trust or 1)
            if d.pairs < 1 then
                reason = "collecting"
                break
            end
            local roi = profit / cost
            -- One pair of scans (15 minutes) is a thin sample: at most 2 units until a second.
            local cap = math.max(1, math.floor(d.perDay))
            local thin = false
            if d.pairs < 2 and cap > 2 then
                cap, thin = 2, true
            end
            -- No more units than were ever seen bought at the price: a day rate made of one or two
            -- purchases is no promise of more (seen in game: a few sales read as 20 a day).
            local seen = U.finite(d.sold) and math.floor(d.sold + 0.5) or nil
            if seen and seen < cap then
                cap, thin = math.max(1, seen), true
            end
            if d.perDay < 0.5 or qty + held > cap then
                if reason ~= "small" then
                    -- "thin": it sells, but too few purchases were seen yet to buy this many.
                    reason = held > 0 and d.perDay >= 0.5 and "enough_stock"
                        or (thin and d.perDay >= 0.5) and "thin"
                        or "not_selling"
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
