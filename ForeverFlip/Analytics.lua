-- Analytics for speculation: own results (profit per day, return, hit rate, turnover) and the
-- market seen by the full scans (liquid items, gaps below the usual price, price moves).
local F = ForeverFlip
local U = F.Util
local A = {}
F.Analytics = A

local DAY = 86400

-- Positions bought for the player's own use: shopping-list items (crafting materials) and gear
-- bought to disenchant. Post next bought never offers them and only a sale takes a position out,
-- so once used they would stay "stock" for good.
local OWN_USE = { shop = true, disenchant = true }

local function char()
    return F.Data.char(F.db, F.Engine.owner())
end

-- Journal kinds of a post that came back: `amount` is the deposit (and cancel fee) lost.
local LOSS = { expired = true, cancel = true, ["return"] = true }

-- Own results over `days` days: totals, per-day profit, return, hit rate and the best and worst
-- items. Profit is booked when a sale is recorded (cost of the units sold is subtracted), and when
-- a deposit or fee is lost with none of the item in stock.
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
    -- Totals from the daily records (they outlive the 500-entry journal); the best and worst items
    -- from the journal, which is all that names them.
    local daily = F.Data.daily(c)
    for i, d in ipairs(r.days) do
        local t = daily[d.day]
        if t then
            r.spent, r.buys = r.spent + t.spent, r.buys + t.buys
            r.earned, r.profit, r.sales = r.earned + t.earned, r.profit + t.profit, r.sales + t.sales
            r.cost, r.wins = r.cost + t.cost, r.wins + t.wins
            r.vendor, r.auction = r.vendor + t.vendor, r.auction + t.auction
            d.profit, d.earned, d.spent = t.profit, t.earned, t.spent
        end
        r.days[i] = d
    end
    local byItem = {}
    for _, e in ipairs(c.journal) do
        local index = math.floor((e.at or 0) / DAY) - (today - days)
        local d = r.days[index]
        if d then
            local sale = e.kind == "sell" or e.kind == "vendor"
            local profit = sale and (e.profit or 0) or nil
            if LOSS[e.kind] and e.key and U.finite(e.profit) then
                -- A deposit or fee lost while none of the item was held left its profit at once
                -- (Data.addCost) and the entry carries that as its profit; one lost on stock joined
                -- the stock's cost and counts with the sale.
                profit = e.profit
            end
            if profit then
                local item = byItem[e.key]
                if not item then
                    item = { key = e.key, name = e.name, profit = 0, sales = 0 }
                    byItem[e.key] = item
                end
                item.profit, item.sales = item.profit + profit, item.sales + (sale and (e.qty or 1) or 0)
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
        if not OWN_USE[p.mode] then
            held = held + p.cost
            local s = c.stats[key]
            if p.since and now - p.since > 3 * DAY and not (s and s.lastSale and s.lastSale >= p.since) then
                stale = stale + p.cost
            end
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
A.SYNC = 200

-- `lastAt`: the time of the last complete full scan, which every item it listed carries as
-- h.scan.at (Market.recordFlow); nil when there is none to tell.
local function rowOf(key, h, now, lastAt)
    local market = type(h) == "table" and type(h.scan) == "table" and h.scan.market
    if U.finite(market) and market > 0 then
        local s = F.Market.saleability(h, market, now)
        local days = type(h.days) == "table" and h.days or {}
        local today = days[#days]
        -- The last daily record is an earlier day's while no scan has listed the item today.
        local cheap = today and today.d == math.floor(now / DAY) and today.min or nil
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
            listed = not lastAt or h.scan.at == lastAt,
        }
        if cheap and cheap < market * 0.95 then
            r.gap = market * 0.95 - cheap
            r.score = r.gap * math.min(r.perDay or 0, 10)
        end
        return r
    end
end

-- A bounded worst-first heap keeps only the fifty rows the page can show. Sorting the whole
-- history in six different ways used to make the final, unsliced build step the most expensive.
local VIEWS = { "liquid", "gaps", "falling", "rising", "cheapNow", "sellNow" }
local function better(a, b)
    return a.value > b.value or a.value == b.value and a.row.key < b.row.key
end

local function ranked(heap, row, value)
    if not value then
        return
    end
    local entry = { row = row, value = value }
    if #heap < 50 then
        local i = #heap + 1
        heap[i] = entry
        while i > 1 do
            local parent = math.floor(i / 2)
            if not better(heap[parent], entry) then
                break
            end
            heap[i], heap[parent] = heap[parent], entry
            i = parent
        end
    elseif better(entry, heap[1]) then
        heap[1] = entry
        local i = 1
        while i * 2 <= #heap do
            local child = i * 2
            if child < #heap and better(heap[child], heap[child + 1]) then
                child = child + 1
            end
            if not better(heap[i], heap[child]) then
                break
            end
            heap[i], heap[child] = heap[child], heap[i]
            i = child
        end
    end
end

local function collect(b, r)
    b.items = b.items + 1
    -- An item the last full scan did not list (bought out, no longer sold) keeps its last figures
    -- in the history for 14 days (F.Scan.stale): it is nothing to buy now and no current price
    -- move. Selling own stock needs no other seller.
    if r.listed then
        ranked(b.top.liquid, r, r.perDay and r.perDay > 0 and r.perDay)
        ranked(b.top.gaps, r, r.score and r.score > 0 and r.score)
        ranked(b.top.falling, r, r.change and r.change < -0.05 and -r.change)
        ranked(b.top.rising, r, r.change and r.change > 0.05 and r.change)
        ranked(b.top.cheapNow, r, r.timing and r.timing.now <= 0.93 and (r.perDay or 0) >= 0.5 and -r.timing.now)
    end
    ranked(b.top.sellNow, r, r.timing and r.timing.now >= 1.07 and b.positions[r.key] ~= nil and r.timing.now)
end

local function summarize(b)
    local result = { stamp = b.stamp, scope = b.scope, items = b.items }
    for _, view in ipairs(VIEWS) do
        local heap, rows = b.top[view], {}
        table.sort(heap, better)
        for i, entry in ipairs(heap) do
            rows[i] = entry.row
        end
        result[view] = rows
    end
    return result
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
        local row = rowOf(key, history[key], b.now, b.lastAt)
        if row then
            collect(b, row)
        end
        if done and done() then
            return false
        end
    end
    building = nil
    cache = summarize(b)
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
    local stamp = scope .. ":" .. tostring(last and last.at) .. ":" .. math.floor(now / 60)
    if cache and cache.stamp == stamp then
        return cache
    end
    if not building or building.stamp ~= stamp then
        local keys = {}
        for key in pairs(F.Data.market(F.db, scope).history) do
            keys[#keys + 1] = key
        end
        local top = {}
        for _, view in ipairs(VIEWS) do
            top[view] = {}
        end
        building = {
            stamp = stamp,
            scope = scope,
            keys = keys,
            i = 1,
            items = 0,
            top = top,
            now = now,
            positions = char().positions,
            -- A partial scan left items out that are still listed.
            lastAt = last and last.scope == scope and not last.partial and last.at or nil,
        }
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
                if not OWN_USE[p.mode] then
                    out.stock = out.stock + (p.cost or 0)
                end
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
