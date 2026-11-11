-- Analytics for speculation: own results (profit per day, return, hit rate, turnover) and the
-- market seen by the full scans (liquid items, gaps below the usual price, price moves).
local F = ForeverFlip
local U = F.Util
local A = {}
F.Analytics = A

local DAY = 86400

local function char()
    return F.Data.char(F.db, F.Engine.owner())
end

-- Own results over `days` days: totals, per-day profit, return, hit rate and the best and worst
-- items. Profit is booked when a sale is recorded (cost of the units sold is subtracted).
function A.results(days, now)
    days = days or 7
    now = now or F.Engine.clock()
    local c = char()
    local today = math.floor(now / DAY)
    local r = {
        days = {},
        spent = 0,
        earned = 0,
        profit = 0,
        cost = 0,
        sales = 0,
        wins = 0,
        buys = 0,
        vendor = 0,
        auction = 0,
    }
    for i = 1, days do
        r.days[i] = { day = today - days + i, profit = 0, earned = 0, spent = 0 }
    end
    local byItem = {}
    for _, e in ipairs(c.journal) do
        local index = math.floor((e.at or 0) / DAY) - (today - days)
        local d = r.days[index]
        if d then
            if e.kind == "buy" then
                r.spent, r.buys, d.spent = r.spent + e.amount, r.buys + 1, d.spent + e.amount
            elseif e.kind == "sell" or e.kind == "vendor" then
                local profit = e.profit or 0
                r.earned, r.profit, r.sales = r.earned + e.amount, r.profit + profit, r.sales + 1
                r.cost = r.cost + (e.amount - profit)
                r.wins = r.wins + (profit > 0 and 1 or 0)
                if e.kind == "vendor" then
                    r.vendor = r.vendor + profit
                else
                    r.auction = r.auction + profit
                end
                d.profit, d.earned = d.profit + profit, d.earned + e.amount
                local item = byItem[e.key]
                if not item then
                    item = { key = e.key, name = e.name, profit = 0, sales = 0 }
                    byItem[e.key] = item
                end
                item.profit, item.sales = item.profit + profit, item.sales + (e.qty or 1)
            end
        end
    end
    r.roi = r.cost > 0 and r.profit / r.cost or nil
    r.hitRate = r.sales > 0 and r.wins / r.sales or nil
    r.perDay = r.profit / days
    local items = {}
    for _, item in pairs(byItem) do
        items[#items + 1] = item
    end
    table.sort(items, function(a, b)
        if a.profit ~= b.profit then
            return a.profit > b.profit
        end
        return a.key < b.key
    end)
    r.best, r.worst = {}, {}
    for i = 1, math.min(3, #items) do
        if items[i].profit > 0 then
            r.best[#r.best + 1] = items[i]
        end
    end
    for i = #items, math.max(1, #items - 2), -1 do
        if items[i].profit < 0 then
            r.worst[#r.worst + 1] = items[i]
        end
    end
    -- Money in stock and how long sold items took to sell (from the item statistics).
    local held, stale, daysSum, sold = 0, 0, 0, 0
    for key, p in pairs(c.positions) do
        held = held + p.cost
        local s = c.stats[key]
        if p.since and now - p.since > 3 * DAY and not (s and s.lastSale and s.lastSale >= p.since) then
            stale = stale + p.cost
        end
    end
    for _, s in pairs(c.stats) do
        daysSum, sold = daysSum + (s.days or 0), sold + (s.sold or 0)
    end
    r.held, r.stale = held, stale
    r.avgDays = sold > 0 and daysSum / sold or nil
    -- Turnover: money returned by sales per day against the money in stock.
    r.turnover = held > 0 and (r.earned / days) / held or nil
    return r
end

-- The market of the current auction house from the saved scan history.
--   liquid:   most units gone per day near the usual price
--   gaps:     today's cheapest far below the usual price, weighted by how much sells
--   falling:  usual price dropped most against the 5-day average (possible buys)
--   rising:   usual price rose most (possible sells of own stock)
-- A large history is worked out a slice per frame (A.step): 20 000 items took about 150 ms in one
-- go. Meanwhile the page shows the previous result (or "working out"); a small one is done at once.
local cache, building
A.SYNC = 2000

local function rowOf(rows, key, h, now)
    local market = type(h) == "table" and type(h.scan) == "table" and h.scan.market
    if U.finite(market) and market > 0 then
        local s = F.Market.saleability(h, market, now)
        local days = type(h.days) == "table" and h.days or {}
        local today = days[#days]
        local cheap = today and today.min
        local sum, n = 0, 0
        for i = math.max(1, #days - 5), #days - 1 do
            if U.finite(days[i].m) then
                sum, n = sum + days[i].m, n + 1
            end
        end
        local avg = n > 0 and sum / n or nil
        local timing = F.Market.timing(h, now)
        local r = {
            timing = timing.ready and timing or nil,
            key = key,
            market = market,
            cheap = cheap,
            perDay = s.known and s.perDay or nil,
            units = h.units,
            change = avg and avg > 0 and (market - avg) / avg or nil,
        }
        if cheap and cheap < market * 0.95 then
            r.gap = market * 0.95 - cheap
            r.score = r.gap * math.min(r.perDay or 0, 10)
        end
        rows[#rows + 1] = r
    end
end

local function summarize(stamp, scope, rows)
    local function top(filter, value, limit)
        local out = {}
        for _, r in ipairs(rows) do
            if filter(r) then
                out[#out + 1] = r
            end
        end
        table.sort(out, function(a, b)
            local x, y = value(a), value(b)
            if x ~= y then
                return x > y
            end
            return a.key < b.key
        end)
        for i = #out, (limit or 50) + 1, -1 do
            out[i] = nil
        end
        return out
    end
    return {
        stamp = stamp,
        scope = scope,
        items = #rows,
        liquid = top(function(r)
            return r.perDay and r.perDay > 0
        end, function(r)
            return r.perDay
        end),
        gaps = top(function(r)
            return r.score and r.score > 0
        end, function(r)
            return r.score
        end),
        falling = top(function(r)
            return r.change and r.change < -0.05
        end, function(r)
            return -r.change
        end),
        rising = top(function(r)
            return r.change and r.change > 0.05
        end, function(r)
            return r.change
        end),
        -- Time of the week: usually cheap right now (buy), usually dear right now (sell stock).
        cheapNow = top(function(r)
            return r.timing and r.timing.now <= 0.93 and (r.perDay or 0) >= 0.5
        end, function(r)
            return -r.timing.now
        end),
        sellNow = top(function(r)
            return r.timing and r.timing.now >= 1.07 and F.Data.char(F.db, F.Engine.owner()).positions[r.key] ~= nil
        end, function(r)
            return r.timing.now
        end),
    }
end

-- Works on the result being built until `done()`; true when it is ready.
function A.build(done)
    local b = building
    if not b then
        return true
    end
    local history = F.Data.market(F.db, b.scope).history
    while b.i <= #b.keys do
        local key = b.keys[b.i]
        b.i = b.i + 1
        rowOf(b.rows, key, history[key], b.now)
        if done and done() then
            return false
        end
    end
    building = nil
    cache = summarize(b.stamp, b.scope, b.rows)
    F.Engine.changed()
    return true
end

-- Called every frame (Core): goes on with a result being built, about 4 ms a frame.
function A.step()
    if building and F.Share and F.Share.budget then
        A.build(F.Share.budget(4, 300))
    end
end

-- The market lists; nil while the first result is worked out (the second value is then true).
function A.market(now)
    now = now or F.Engine.clock()
    local scope = F.Engine.scope()
    local last = F.Scan.last
    local stamp = scope .. ":" .. tostring(last and last.at)
    if cache and cache.stamp == stamp then
        return cache
    end
    if not building or building.stamp ~= stamp then
        local keys = {}
        for key in pairs(F.Data.market(F.db, scope).history) do
            keys[#keys + 1] = key
        end
        building = { stamp = stamp, scope = scope, keys = keys, i = 1, rows = {}, now = now }
    end
    if #building.keys <= A.SYNC then
        A.build()
        return cache
    end
    local old = cache and cache.scope == scope and cache or nil
    return old, true
end

-- Journal of the character as CSV (date, kind, item, quantity, amount, profit in copper).
function A.csv()
    local lines = { "date,kind,item,quantity,amount_copper,profit_copper" }
    for _, e in ipairs(char().journal) do
        local name = tostring(e.name or e.key or ""):gsub('"', '""')
        lines[#lines + 1] = string.format(
            '%s,%s,"%s",%d,%d,%s',
            date("%Y-%m-%d %H:%M", e.at or 0),
            tostring(e.kind),
            name,
            e.qty or 0,
            math.floor(e.amount or 0),
            e.profit and tostring(math.floor(e.profit)) or ""
        )
    end
    return table.concat(lines, "\n")
end

-- Gold of each character, one value per day (kept 60 days).
function A.recordGold(now)
    if not F.db then
        return
    end
    now = now or F.Engine.clock()
    F.db.gold = type(F.db.gold) == "table" and F.db.gold or {}
    local owner = F.Engine.owner()
    local days = type(F.db.gold[owner]) == "table" and F.db.gold[owner] or {}
    F.db.gold[owner] = days
    local day = math.floor(now / DAY)
    days[day] = F.Engine.wallet()
    for d in pairs(days) do
        if d < day - 60 then
            days[d] = nil
        end
    end
end

-- Characters of this realm: gold now and `back` days ago, stock at cost.
function A.realm(back, now)
    now = now or F.Engine.clock()
    local realm = tostring(GetRealmName and GetRealmName() or "?")
    local today = math.floor(now / DAY)
    local out = { gold = 0, before = 0, stock = 0, chars = 0 }
    for owner, days in pairs(F.db.gold or {}) do
        if owner:sub(1, #realm + 1) == realm .. "-" then
            local latest, latestDay, past, pastDay
            for d, v in pairs(days) do
                if not latestDay or d > latestDay then
                    latest, latestDay = v, d
                end
                if d <= today - back and (not pastDay or d > pastDay) then
                    past, pastDay = v, d
                end
            end
            out.chars = out.chars + 1
            out.gold = out.gold + (latest or 0)
            out.before = out.before + (past or latest or 0)
        end
    end
    for owner, c in pairs(F.db.chars or {}) do
        if owner:sub(1, #realm + 1) == realm .. "-" and type(c.positions) == "table" then
            for _, p in pairs(c.positions) do
                out.stock = out.stock + (p.cost or 0)
            end
        end
    end
    return out
end

function A.invalidate()
    -- The previous result stays on screen until the new one is ready (A.market).
    if cache then
        cache.stamp = nil
    end
    building = nil
end
