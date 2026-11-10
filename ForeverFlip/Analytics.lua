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
local cache
function A.market(now)
    now = now or F.Engine.clock()
    local scope = F.Engine.scope()
    local last = F.Scan.last
    local stamp = scope .. ":" .. tostring(last and last.at)
    if cache and cache.stamp == stamp then
        return cache
    end
    local history = F.Data.market(F.db, scope).history
    local rows = {}
    for key, h in pairs(history) do
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
    cache = {
        stamp = stamp,
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
    return cache
end

function A.invalidate()
    cache = nil
end
