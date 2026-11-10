-- Bids. Items (not commodities) can carry a bid. An auction that ends within 30 minutes and whose
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
    local market = h and h.scan and h.scan.market
    if U.finite(market) and market > 0 then
        local s = F.Market.saleability(h, market, F.Engine.clock())
        if s.known and s.perDay >= 0.5 then
            local item = U.parseKey(key)
            local net = F.Market.net(U.stepDown(market, item and item.kind), 1) - F.Market.deposit(vendor, 1)
            value = math.max(value, net)
        end
    end
    return value > 0 and value or nil
end

-- Full scan row with a bid ending soon (time band 0 = under 30 minutes).
function B.consider(j, key, kind, r)
    if kind == "commodity" or r.band ~= 0 or (r.minBid or 0) <= 0 then
        return
    end
    j.bids = j.bids or {}
    j.bids[#j.bids + 1] = { key = key, id = r.id, kind = kind, bid = r.minBid, count = r.count or 1 }
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
    B.candidates, B.at = out, F.Engine.clock()
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
function B.check(key)
    return F.Deals.enqueue(key, function(k)
        local c = B.get(k)
        local item = U.parseKey(k)
        local ok, rows = pcall(F.AH.bidRows, item)
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
    end, "bid:" .. key)
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
