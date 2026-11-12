-- Bids. Items (not commodities) can carry a bid. An auction that ends within 2 hours and whose
-- next bid is well below what the item is worth (the vendor price, or the usual auction price
-- after the cut for an item that sells) is a bid candidate. The full scan finds candidates; an
-- exact search reads the auction itself before a bid is placed with a click. A won auction is
-- booked as stock when the "You won" line or mail arrives; an outbid mail closes the bid.
local F = ForeverFlip
local U = F.Util
local B = {}
F.Bids = B

B.MAX = 100 -- candidates kept from a scan
B.FRESH = 60 -- seconds an exact read of a bid auction stays valid

B.candidates = {} -- best first: { key, id, kind, bid, count, value, profit, band }
B.offers = {} -- key -> { auctionID, bid, qty, at } from the last exact read

local function char()
    return F.Data.char(F.db, F.Engine.owner())
end

-- What one unit is worth: the vendor price, or the usual price after the cut when it sells.
function B.value(key, id, history)
    local vendor = F.AH.vendorPrice(id)
    local value = vendor or 0
    local h = history[key]
    local market = h and F.Market.usual(h)
    if U.finite(market) and market > 0 then
        local s = F.Market.saleability(h, market, F.Engine.clock())
        if s.known and s.perDay >= 0.5 then
            local item = U.parseKey(key)
            local net = F.Market.net(U.stepDown(market, item and item.kind), 1)
                - F.Market.deposit(F.AH.clientVendorPrice(id), 1)
            value = math.max(value, net)
        end
    end
    return value > 0 and value or nil
end

-- Full scan row with a bid ending soon: time band 0 = under 30 minutes, 1 = up to 2 hours (only
-- 30 minutes left every candidate of a scan gone half an hour later, and the page stayed empty).
-- `ends` is the latest time the auction can end.
B.BAND_END = { [0] = 1800, [1] = 7200 }
function B.consider(j, key, kind, r)
    local left = B.BAND_END[r.band]
    if kind == "commodity" or not left or (r.minBid or 0) <= 0 then
        return
    end
    j.bids = j.bids or {}
    j.bids[#j.bids + 1] = {
        key = key,
        id = r.id,
        kind = kind,
        bid = r.minBid,
        count = math.max(1, r.count or 1),
        band = r.band,
        ends = F.Engine.clock() + left,
    }
end

-- The candidates of the last scan of this auction house whose auctions can still be running, kept
-- in the saved data so a /reload keeps them.
function B.current()
    local scope = F.Engine.scope()
    if #B.candidates == 0 and B.scope ~= scope then
        local saved = F.db.bidCandidates and F.db.bidCandidates[scope]
        B.candidates = type(saved) == "table" and type(saved.list) == "table" and saved.list or {}
        B.at, B.scope = type(saved) == "table" and saved.at or nil, scope
    end
    local now, live = F.Engine.clock(), {}
    for _, c in ipairs(B.candidates) do
        if not c.ends or c.ends > now then
            live[#live + 1] = c
        end
    end
    if #live < #B.candidates then
        B.candidates = live
    end
    return B.candidates
end

-- End of a scan: candidates with enough profit, best first.
function B.finish(j, history)
    local out = {}
    local minProfit = F.db.settings.minProfit or 100
    for _, c in ipairs(j.bids or {}) do
        if not F.Shopping.blocked(c.key) then
            local value = B.value(c.key, c.id, history)
            local profit = value and value * c.count - c.bid
            if profit and profit >= minProfit then
                c.value, c.profit = value * c.count, profit
                out[#out + 1] = c
            end
        end
    end
    table.sort(out, function(a, b)
        if a.profit ~= b.profit then
            return a.profit > b.profit
        end
        return a.key < b.key
    end)
    for i = #out, B.MAX + 1, -1 do
        out[i] = nil
    end
    B.candidates, B.at, B.scope = out, F.Engine.clock(), j.scope
    F.db.bidCandidates = type(F.db.bidCandidates) == "table" and F.db.bidCandidates or {}
    F.db.bidCandidates[j.scope] = { at = B.at, list = out }
    F.Engine.changed()
end

function B.get(key)
    for _, c in ipairs(B.candidates) do
        if c.key == key then
            return c
        end
    end
end

-- Exact read of a candidate: the auction with the lowest next bid still worth it.
function B.check(key, done)
    return F.Deals.enqueue(key, function(k, rows, ...)
        if rows ~= nil then
            B.read(k)
        end
        if done then
            done(k, rows, ...)
        end
    end, done and ("bidall:" .. key) or ("bid:" .. key))
end

-- The answer of a candidate's search: its best bid, or the candidate is dropped.
function B.read(k)
    do
        local c = B.get(k)
        local item = U.parseKey(k)
        -- Gear was searched version by version: read the bids of every version searched (also
        -- versions whose auctions are all bid-only).
        local keys = F.Deals.versions or {}
        local ok, rows = true, {}
        if #keys == 0 then
            ok, rows = pcall(F.AH.bidRows, item)
        else
            for _, sk in ipairs(keys) do
                local got, part = pcall(F.AH.bidRows, item, sk)
                ok = ok and got
                for _, r in ipairs(got and part or {}) do
                    rows[#rows + 1] = r
                end
            end
        end
        B.offers[k] = nil
        if not ok or not c then
            return
        end
        local unitValue = c.value / c.count
        local best
        for _, r in ipairs(rows or {}) do
            local profit = unitValue * r.qty - r.bid
            if profit >= (F.db.settings.minProfit or 100) and (not best or profit > best.profit) then
                best = { auctionID = r.auctionID, bid = r.bid, qty = r.qty, profit = profit, at = F.Engine.clock() }
            end
        end
        B.offers[k] = best
        if not best then
            for i, x in ipairs(B.candidates) do
                if x.key == k then
                    table.remove(B.candidates, i)
                    break
                end
            end
        end
        F.Engine.changed()
    end
end

function B.offer(key)
    local o = B.offers[key]
    if o and F.Engine.clock() - o.at <= B.FRESH then
        return o
    end
end

-- A click places the bid read by the last check.
function B.place(key)
    local o = B.offer(key)
    if not o then
        return false, "verify_first"
    end
    if o.bid > F.Engine.wallet() then
        return false, "no_money"
    end
    if not F.Trade.wayFree() then
        return false, "buy_busy"
    end
    if not pcall(F.AH.bid, o.auctionID, o.bid) then
        return false, "error"
    end
    local c = B.get(key)
    local item = U.parseKey(key)
    local name = c and U.itemInfo(c.id) or (item and item.name) or key
    local bids = char()
    bids.bids = bids.bids or {}
    bids.bids[o.auctionID] = {
        key = key,
        name = name,
        qty = o.qty,
        amount = o.bid,
        value = c and c.value or nil,
        at = F.Engine.clock(),
    }
    B.offers[key] = nil
    F.Engine.notify("bid_placed")
    F.Engine.changed()
    return true
end

local function openBid(name)
    local c = char()
    for id, b in pairs(c.bids or {}) do
        if string.lower(b.name or "") == string.lower(name or "") then
            return id, b
        end
    end
end

-- "You won an auction for X" or the "Auction won" mail of a bid: the item becomes stock.
function B.won(name)
    local id, b = openBid(name)
    if not id then
        return false
    end
    local c = char()
    c.bids[id] = nil
    local vendor = F.AH.vendorPrice((U.parseKey(b.key) or {}).id or 0)
    local mode = vendor and b.value and vendor * b.qty >= b.value and "vendor" or "flip"
    F.Data.addPosition(c, b.key, b.name, b.qty, b.amount, mode, nil, F.Engine.clock())
    F.Data.log(c, { at = F.Engine.clock(), kind = "buy", key = b.key, name = b.name, qty = b.qty, amount = b.amount })
    F.Engine.notify("bid_won")
    F.Engine.changed()
    return true
end

-- "Outbid on X": the money comes back by mail; the bid is closed.
function B.outbid(name)
    local id = openBid(name)
    if id then
        char().bids[id] = nil
        F.Engine.changed()
        return true
    end
    return false
end

function B.open()
    local out = {}
    for id, b in pairs(char().bids or {}) do
        out[#out + 1] = { auctionID = id, key = b.key, name = b.name, amount = b.amount, at = b.at }
    end
    table.sort(out, function(a, b)
        return a.at > b.at
    end)
    return out
end

-- Bids older than two days are forgotten (the mail was missed).
function B.prune()
    local c = char()
    for id, b in pairs(c.bids or {}) do
        if F.Engine.clock() - (b.at or 0) > 2 * 86400 then
            c.bids[id] = nil
        end
    end
end
