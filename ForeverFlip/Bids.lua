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
            local most = value and B.maxBid(value * c.count)
            if profit and profit >= minProfit and most and c.bid <= most then
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
            local most = B.maxBid(unitValue * r.qty)
            if
                profit >= (F.db.settings.minProfit or 100)
                and most
                and r.bid <= most
                and (not best or profit > best.profit)
            then
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
    local name = (item and item.name) or (c and U.itemInfo(c.id)) or key
    local bids = char()
    bids.bids = bids.bids or {}
    bids.bids[o.auctionID] = {
        key = key,
        name = name,
        qty = o.qty,
        amount = o.bid,
        value = c and c.value or nil,
        at = F.Engine.clock(),
        ends = c and c.ends or nil,
    }
    B.liveDue = F.Engine.clock() + 2
    B.offers[key] = nil
    F.Engine.notify("bid_placed")
    F.Engine.changed()
    return true
end

-- The open bid of an item by name; a bid still running before one the player was outbid on.
local function openBid(name, outbidFirst)
    local c = char()
    local found, foundBid
    for id, b in pairs(c.bids or {}) do
        if string.lower(b.name or "") == string.lower(name or "") then
            local better = not found
                or (outbidFirst and not foundBid.outbid and b.outbid)
                or (not outbidFirst and foundBid.outbid and not b.outbid)
            if better then
                found, foundBid = id, b
            end
        end
    end
    return found, foundBid
end

-- Finished bids, newest last: { auctionID, key, name, qty, amount, value, outcome = won | lost, at, ended }.
B.LOG = 40
local function finishBid(id, b, outcome)
    local c = char()
    c.bids[id] = nil
    c.bidLog = type(c.bidLog) == "table" and c.bidLog or {}
    c.bidLog[#c.bidLog + 1] = {
        auctionID = id,
        key = b.key,
        name = b.name,
        qty = b.qty,
        amount = b.amount,
        value = b.value,
        outcome = outcome,
        at = b.at,
        ended = F.Engine.clock(),
    }
    while #c.bidLog > B.LOG do
        table.remove(c.bidLog, 1)
    end
end

-- "You won an auction for X" or the "Auction won" mail of a bid: the item becomes stock.
function B.won(name, fromInvoice)
    local id, b = openBid(name)
    if not id then
        return false
    end
    local c = char()
    finishBid(id, b, "won")
    if not fromInvoice then
        F.Trade.awaitBuyerInvoice(b.name, b.qty)
    end
    local vendor = F.AH.vendorPrice((U.parseKey(b.key) or {}).id or 0)
    local mode = vendor and b.value and vendor * b.qty >= b.value and "vendor" or "flip"
    F.Data.addPosition(c, b.key, b.name, b.qty, b.amount, mode, nil, F.Engine.clock())
    F.Data.log(c, { at = F.Engine.clock(), kind = "buy", key = b.key, name = b.name, qty = b.qty, amount = b.amount })
    F.Engine.notify("bid_won")
    F.Engine.changed()
    return true
end

-- "You have been outbid on X" or its mail: the money comes back at once, while the auction still
-- runs and can be bid on again. The bid stays listed as outbid until the auction ends (then lost).
function B.outbid(name)
    local id, b = openBid(name, false)
    if id then
        b.outbid = b.outbid or F.Engine.clock()
        B.liveDue = 0 -- the next bid the house takes is asked for at once
        F.Engine.changed()
        return true
    end
    return false
end

-- My bids -----------------------------------------------------------------------------------------
-- The game's Bids list is asked for every minute while the auction house is open and a bid runs
-- (or My bids is shown), and read on BIDS_UPDATED. It tells for each auction whether the player
-- leads and the next bid the house takes. Bids placed in the game's own window are tracked too.
B.LIVE_EVERY = 60
B.BAND_MAX = { [0] = 1800, [1] = 7200, [2] = 43200, [3] = 172800 }

function B.step()
    if not F.AH.isOpen() or F.Engine.clock() < (B.liveDue or 0) then
        return
    end
    local bids = char().bids
    local running = bids ~= nil and next(bids) ~= nil
    local shown = F.UI and F.UI.section == "mybids"
    if
        (running or shown)
        and F.AH.ready()
        and not F.Deals.searching()
        and not F.Scan.blocking()
        and not F.Trade.busy()
    then
        B.liveDue = F.Engine.clock() + B.LIVE_EVERY
        pcall(F.AH.queryBids)
    end
end

function B.onLive()
    local ok, list = pcall(F.AH.bids)
    if not ok or type(list) ~= "table" then
        return
    end
    local c = char()
    c.bids = c.bids or {}
    local now = F.Engine.clock()
    local seen = {}
    for _, r in ipairs(list) do
        seen[r.auctionID] = true
        local b = c.bids[r.auctionID]
        if not b and r.id then
            -- A bid placed in the game's own window: its worth is reckoned like any bid's.
            local key = F.AH.keyFor(r.id, r.link)
            b = {
                key = key,
                name = U.linkName(r.link) or U.itemInfo(r.id) or key,
                qty = 1,
                amount = r.bid,
                at = now,
                native = true,
            }
            c.bids[r.auctionID] = b
        end
        if b then
            local leading = r.leading
            if leading == nil then
                -- The highest bidder is not named: the player leads while the highest bid is still
                -- the amount the player bid (never advise bidding against yourself).
                leading = not U.finite(r.bid) or not U.finite(b.amount) or r.bid <= b.amount
            end
            b.next, b.buyout, b.band = r.minBid, r.buyout, r.band
            b.outbid = not leading and (b.outbid or now) or nil
            b.seen = now
            local latest = now + (B.BAND_MAX[r.band] or B.BAND_MAX[3])
            b.ends = math.min(b.ends or latest, latest)
        end
    end
    -- A bid gone from the list has ended: lost when someone else led it; one the player led waits
    -- for its "won" line or mail (B.won).
    for id, b in pairs(c.bids) do
        if not seen[id] and now - (b.at or 0) > 10 and b.outbid then
            finishBid(id, b, "lost")
        end
    end
    B.liveAt = now
    F.Engine.changed()
end

-- Highest bid on `qty` units worth `value` (money they bring, B.value x qty) that still leaves the
-- minimum profit and return of Settings: a bid costs nothing when outbid (the money comes back), so
-- bidding again pays whenever winning at that price would.
function B.maxBid(value)
    local s = F.db.settings
    if not U.finite(value) or value <= 0 then
        return nil
    end
    local roi = math.max(0, s.minROI or 0.2)
    return math.floor(math.min(value - (s.minProfit or 100), value / (1 + roi)))
end

-- Every bid of the player with its state and the advice:
--   status   leading | outbid | ended (led when last seen; the mail tells) | won | lost
--   advice   rebid    outbid, and the next bid still leaves the minimum profit
--            buyout   outbid or leading with hours left, and the buyout still leaves it: other
--                     bidders get hours to come back, the buyout ends the auction now
--            hold     leading: nothing to do
--            let_go   outbid past what the item is worth to you
--            no_money the next bid is more than you have
function B.mine()
    local c = char()
    local history = F.Data.market(F.db, F.Engine.scope()).history
    local wallet = F.Engine.wallet()
    local minProfit = F.db.settings.minProfit or 100
    local out = {}
    for id, b in pairs(c.bids or {}) do
        local item = U.parseKey(b.key or "")
        local unit = item and B.value(b.key, item.id, history)
        local value = unit and unit * (b.qty or 1) or b.value
        local row = {
            auctionID = id,
            key = b.key,
            id = item and item.id,
            name = b.name,
            qty = b.qty or 1,
            mine = b.amount,
            next = b.next,
            buyout = b.buyout,
            band = b.band,
            value = value,
            at = b.at,
            live = true,
        }
        row.maxBid = B.maxBid(value)
        if b.outbid then
            row.status = "outbid"
        elseif b.seen and B.liveAt and b.seen < B.liveAt then
            row.status = "ended"
        else
            row.status = "leading"
        end
        local buyoutPays = b.buyout and row.maxBid and b.buyout <= row.maxBid
        if row.status == "outbid" then
            if buyoutPays and (b.band or 3) >= 2 then
                row.advice, row.price = "buyout", b.buyout
            elseif b.next and row.maxBid and b.next <= row.maxBid then
                row.advice, row.price = b.next > wallet and "no_money" or "rebid", b.next
            elseif buyoutPays then
                row.advice, row.price = "buyout", b.buyout
            elseif b.next then
                row.advice = "let_go"
            end
        elseif row.status == "leading" then
            row.advice = buyoutPays and (b.band or 0) >= 2 and "buyout" or "hold"
            row.price = row.advice == "buyout" and b.buyout or b.amount
        end
        if row.advice == "buyout" and b.buyout > wallet then
            row.advice = "no_money"
        end
        row.profit = value and row.price and value - row.price or nil
        if row.profit and row.profit < minProfit and row.advice == "hold" then
            row.thin = true
        end
        out[#out + 1] = row
    end
    for i = #(c.bidLog or {}), 1, -1 do
        local l = c.bidLog[i]
        if F.Engine.clock() - (l.ended or 0) <= 2 * 86400 then
            local item = U.parseKey(l.key or "")
            out[#out + 1] = {
                auctionID = l.auctionID,
                key = l.key,
                id = item and item.id,
                name = l.name,
                qty = l.qty or 1,
                mine = l.amount,
                value = l.value,
                status = l.outcome,
                profit = l.outcome == "won" and l.value and l.amount and l.value - l.amount or nil,
                at = l.ended,
            }
        end
    end
    return out
end

-- The answer to an outbid: bid the next amount the house takes, or buy the auction out.
function B.answer(auctionID, how)
    local c = char()
    local b = c.bids and c.bids[auctionID]
    if not b then
        return false, "nothing_to_bid"
    end
    local amount = how == "buyout" and b.buyout or b.next
    if not amount then
        return false, "verify_first"
    end
    if amount > F.Engine.wallet() then
        return false, "no_money"
    end
    if not F.AH.isOpen() or not F.Trade.wayFree() then
        return false, "buy_busy"
    end
    if not pcall(F.AH.bid, auctionID, amount) then
        return false, "error"
    end
    b.amount, b.at, b.outbid, b.seen = amount, F.Engine.clock(), nil, nil
    b.next = nil
    B.liveDue = F.Engine.clock() + 2
    F.Engine.notify(how == "buyout" and "bid_bought" or "bid_placed")
    F.Engine.changed()
    return true
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

-- Bids older than two days are closed (the mail was missed): lost when outbid, else forgotten.
function B.prune()
    local c = char()
    for id, b in pairs(c.bids or {}) do
        if F.Engine.clock() - (b.at or 0) > 2 * 86400 then
            if b.outbid then
                finishBid(id, b, "lost")
            else
                c.bids[id] = nil
            end
        end
    end
end
