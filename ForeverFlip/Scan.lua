-- Full scan: ReplicateItems returns every auction of the house (often 200 000 and more) once
-- per 15 minutes. The rows are read in small steps per frame, grouped per item key, and every
-- item is evaluated for a vendor deal and a resale from the scan data. Found deals are then
-- verified one by one with an exact search (F.Deals).
local F = ForeverFlip
local U = F.Util
local M = F.Market
local S = {}
F.Scan = S

-- The server allows one full scan per 15 minutes, counted from each call, answered or not: a call
-- sooner is not answered and starts the 15 minutes again. In game, retries a minute after an
-- unanswered call kept the scan away (04:08, 04:14, 04:23 unanswered, 04:38 read), and a call
-- exactly 15:00 after the last one was not answered while 15:02 was. Hence 15 minutes and 20 seconds.
S.COOLDOWN = 920
S.ROWS = 40 -- cheapest auctions kept per item
S.RECOVER = 30 -- seconds to wait for item data of rows the game had not loaded
S.DAYS = 14 -- daily records kept per item (price, cheapest, units listed and sold)
-- Seconds to wait for the server's answer to a full scan. Since WoW Forever launched the answer
-- can take minutes (ForeverForge waits 2, auxForever 0.8.2 waits 10), but a call refused by the
-- 15-minute account limit (another addon used the window) is never answered. 5 minutes, then the
-- next try once 15 minutes passed since that call (S.COOLDOWN), never sooner.
S.ANSWER_WAIT = 300

local function clock()
    return F.Engine.clock()
end

-- Time budget for one frame: milliseconds with the profiler, else a fixed amount of work.
local function budget(ms, fallback)
    ms = F.Engine.workSlice(ms)
    local start = debugprofilestop and debugprofilestop()
    local n = 0
    return function()
        n = n + 1
        if start then
            return n % 10 == 0 and debugprofilestop() - start >= ms
        end
        return n >= fallback
    end
end

function S.cooldown()
    return math.max(0, S.COOLDOWN - (clock() - (F.db.lastScan or 0)))
end

function S.busy()
    return S.job ~= nil
end

-- Does the scan hold back searches and posts? While it waits for the server's answer: letting the
-- sniper go on during the wait was tried, and in game the answer then did not come at all
-- (auxForever holds its sniper back for the same reason). Reading the answer is local work.
function S.blocking()
    return S.job ~= nil and S.job.state == "waiting"
end

-- The scan log: the last 20 requests and how each ended (shown by /ff diag).
function S.log(outcome, count)
    local p = F.db.scanPending
    F.db.scanLog = type(F.db.scanLog) == "table" and F.db.scanLog or {}
    table.insert(F.db.scanLog, 1, {
        at = p and p.at or clock(),
        ended = clock(),
        outcome = outcome,
        count = count or F.AH.replicateCount(),
        other = p and p.other or nil,
    })
    while #F.db.scanLog > 20 do
        table.remove(F.db.scanLog)
    end
end

-- The request is over (read, given up or thrown away): nothing to wait for after a reopen.
local function settle(outcome, count)
    if F.db.scanPending then
        S.log(outcome, count)
    end
    F.db.scanPending = nil
end

local function remember(j)
    F.db.scanPending = { at = j.at, scope = j.scope, base = j.base, baseMark = j.baseMark, other = j.other }
end

function S.start()
    if S.job then
        return false, "busy"
    end
    if not F.AH.isOpen() then
        return false, "closed"
    end
    if S.cooldown() > 0 then
        return false, "cooldown"
    end
    if F.Trade.busy() or F.Trade.postingNow() or F.Deals.searching() or F.Sniper.inFlight() then
        return false, "busy"
    end
    -- Not a peek: a throttle stuck on "not ready" is released after a few seconds (AH.ready).
    if not F.AH.ready() then
        return false, "throttled"
    end
    -- The job exists before the request: the answer event may come during the call itself.
    local base = F.AH.replicateCount()
    S.job = {
        state = "waiting",
        at = clock(),
        scope = F.Engine.scope(),
        base = base,
        baseMark = F.AH.replicateMark(),
        last = -1,
    }
    local before = F.db.lastScan
    F.db.lastScan = clock()
    local ok = pcall(F.AH.replicate)
    if not ok then
        F.db.lastScan = before -- nothing reached the server
        S.job = nil
        return false, "error"
    end
    remember(S.job)
    F.Engine.changed()
    return true
end

-- The auction house opened again (also after /reload): a request sent before, not answered or not
-- read yet, is waited for again. An answer that came meanwhile is in the client's list.
function S.resume(scope)
    local p = F.db.scanPending
    if S.job or type(p) ~= "table" then
        return false
    end
    local age = clock() - (p.at or 0)
    if p.scope ~= scope or age > S.ANSWER_WAIT + (p.answered and 600 or 0) or age < 0 then
        settle(p.answered and "closed while reading" or "closed while waiting")
        return false
    end
    S.job = {
        state = "waiting",
        at = p.at,
        scope = scope,
        base = p.base,
        -- An answer that already arrived is read at once (any list differs from this mark).
        baseMark = p.answered and "resumed" or p.baseMark,
        last = -1,
        other = p.other,
        resumed = true,
    }
    F.Engine.notify("scan_resumed")
    return true
end

-- WoW Forever does not always send REPLICATE_ITEM_LIST_UPDATE (seen in game): the scan is
-- also taken once the number of replicated auctions changed and stopped growing for a second.
-- The server sends the list in parts (1024, 2048, 24576 ... auctions), with pauses between them
-- that can last seconds: reading after one quiet second read a part (in game: 1024 of 300 000).
-- The answer is taken once the list differs from the one before the request and has not changed
-- for S.SETTLE seconds; a list far smaller than the house's last full scan waits longer (S.SHORT
-- quiet seconds, or the end of the wait).
S.SETTLE = 5
S.SHORT = 60

-- The size of a complete list of this house: the largest complete scan of the last day (saved as
-- `peak`), else the last scan. Measuring against the last scan alone let partial answers pass once
-- one had been taken (in game: 28 672, 30 720, 73 728 of about 250 000 auctions, read one after the
-- other).
S.PEAK_AGE = 86400
function S.reference(scope)
    local market = F.Data.market(F.db, scope)
    local best = 0
    local peak = market.peak
    if type(peak) == "table" and U.finite(peak.total) and clock() - (peak.at or 0) <= S.PEAK_AGE then
        best = peak.total
    end
    local last = S.last and S.last.scope == scope and S.last or market.last
    local total = type(last) == "table" and not last.partial and last.total or nil
    if U.finite(total) and total > best then
        best = total
    end
    return best
end

-- A list far smaller than a complete one of this house: a part of the answer.
function S.isShort(scope, n)
    local ref = S.reference(scope)
    return ref > 0 and U.finite(n) and n < ref * 0.6
end

local function polled(j, now)
    if now - (j.polled or 0) < 1 then
        return false
    end
    j.polled = now
    local n = F.AH.replicateCount()
    local mark = F.AH.replicateMark()
    if mark ~= j.lastMark then
        j.quietSince = now
    end
    j.last, j.lastMark = n, mark
    j.seen = math.max(j.seen or 0, n)
    if n <= 0 or mark == j.baseMark then
        return false
    end
    local quiet = now - (j.quietSince or now)
    if quiet < S.SETTLE then
        return false
    end
    return not S.isShort(j.scope, n) or quiet >= S.SHORT or now - j.at >= S.ANSWER_WAIT - 5
end

local function beginReading(j, total)
    if F.db.scanPending then
        F.db.scanPending.answered = true
    end
    j.state, j.total, j.index = "reading", total, 0
    j.groups, j.order, j.deferred = {}, {}, {}
    j.read, j.skipped, j.own = 0, 0, 0
    F.AH.refreshPlayer()
    j.partial = S.isShort(j.scope, total) or nil
    j.lots = F.AH.canTrackLots() and not j.partial
    j.raw = F.Raw.active() and {} or nil
end

-- Automatic full scan: as soon as the 15-minute cooldown ends while the auction house is open
-- and nothing else talks to it. Regular scans are what measures sales for resale.
function S.auto()
    if
        F.db.settings.autoScan
        and not S.job
        and F.AH.isOpen()
        and S.cooldown() <= 0
        and not F.Trade.busy()
        and not F.Trade.postingNow()
        and not F.Deals.holding()
        and not F.Deals.pending()
        and not F.Deals.searching()
        and not (F.Sniper and F.Sniper.query)
        and F.AH.ready()
    then
        S.start()
    end
end

-- The auction house closed: the scan stops, but its request stays remembered (S.resume).
function S.stop()
    if S.job then
        F.Engine.notify(S.job.state == "waiting" and "scan_paused" or "scan_paused_reading")
    end
    S.job = nil
end

-- AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED right after our own request: the server threw the request
-- away, so nothing will answer it. The next try is allowed in 10 seconds.
function S.onDropped()
    local j = S.job
    if j and j.state == "waiting" and not j.other and clock() - (j.at or 0) <= 3 then
        S.job = nil
        F.db.lastScan = clock() - S.COOLDOWN + 10
        settle("dropped by the server")
        F.Engine.notify("scan_dropped")
    end
end

-- Another addon called ReplicateItems (Core: E.hookReplicate). The answer comes later, and the
-- event may never come: the scan waits for the number of auctions to change and settle.
function S.onOtherScan()
    if S.job or not F.AH.isOpen() then
        return
    end
    F.db.lastScan = clock()
    S.job = {
        state = "waiting",
        at = clock(),
        scope = F.Engine.scope(),
        base = F.AH.replicateCount(),
        baseMark = F.AH.replicateMark(),
        last = -1,
        other = true,
    }
    remember(S.job)
    F.Engine.notify("scan_other")
end

function S.onReplicate()
    local j = S.job
    local total = F.AH.replicateCount()
    if not j then
        -- Another addon (Auctionator, TSM, ...) asked for a full scan: use it too. The
        -- server allows one per 15 minutes for the account, so ours waits for the next window.
        -- A late event for the scan just read (it was taken by polling) is not a new scan.
        local last = S.last
        if last and last.total == total and clock() - (S.finishedAt or 0) < 300 then
            return
        end
        if F.AH.isOpen() and U.finite(total) and total > 0 then
            F.db.lastScan = clock()
            S.job = { state = "waiting", at = clock(), scope = F.Engine.scope() }
            beginReading(S.job, total)
            F.Engine.notify("scan_other")
        end
        return
    end
    if j.state ~= "waiting" then
        return
    end
    if U.finite(total) and total > 0 and S.isShort(j.scope, total) then
        -- The event also comes for a part of the answer: the polling waits for the rest.
        return
    end
    if not U.finite(total) or total <= 0 then
        S.job = nil
        settle("empty list", 0)
        F.Engine.notify("scan_empty")
        return
    end
    beginReading(j, total)
end

local function ingest(j, i)
    local ok, r = pcall(F.AH.replicateRow, i)
    if not ok or not r then
        j.skipped = j.skipped + 1
        j.unreadable = (j.unreadable or 0) + 1
        return true
    end
    if not r.complete then
        F.AH.requestItem(r.id)
        return false
    end
    local mine = F.AH.isPlayer(r.owner)
    if (r.minBid or 0) > 0 and r.band and r.band <= 1 and not mine then
        local key, kind = F.AH.keyFor(r.id, r.link)
        if key then
            F.Bids.consider(j, key, kind, r)
        end
    end
    if r.buyout <= 0 or r.count <= 0 then
        return true -- bid only
    end
    if mine then
        j.own = j.own + 1
        return true
    end
    local key, kind = F.AH.keyFor(r.id, r.link)
    if not key then
        return false
    end
    local g = j.groups[key]
    if not g then
        g = { key = key, kind = kind, id = r.id, link = r.link, rows = {}, buckets = {}, units = 0 }
        j.groups[key] = g
        j.order[#j.order + 1] = key
    end
    local unit = r.buyout / r.count
    M.bucketAdd(g.buckets, unit, r.count)
    if j.lots and r.band then
        -- Scan order is creation order: the sequence is what lot-by-lot sales tracking compares.
        local seq = g.seq or {}
        g.seq = seq
        if #seq < 3 * M.LOTS then
            seq[#seq + 1] = math.floor(unit + 0.5)
            seq[#seq + 1] = r.count
            seq[#seq + 1] = r.band
            g.owners = g.owners or {}
            g.owners[#g.owners + 1] = M.ownerTag(r.owner)
        end
    end
    g.units = g.units + r.count
    local row = { unit = unit, qty = r.count }
    local rows = g.rows
    if #rows < S.ROWS then
        rows[#rows + 1] = row
        g.worst = nil
    else
        if not g.worst then
            local w, at = -1, nil
            for n, v in ipairs(rows) do
                if v.unit > w then
                    w, at = v.unit, n
                end
            end
            g.worst, g.worstUnit = at, w
        end
        if unit < g.worstUnit then
            rows[g.worst] = row
            g.worst = nil
        end
    end
    j.read = j.read + 1
    return true
end

local function finish(j, done)
    local market = F.Data.market(F.db, j.scope)
    local history = market.history
    local now = j.finishAt
    local deals, stats = j.deals, j.stats
    while j.cursor <= #j.order do
        local key = j.order[j.cursor]
        j.cursor = j.cursor + 1
        local g = j.groups[key]
        table.sort(g.rows, function(a, b)
            return a.unit < b.unit
        end)
        local value = M.bucketValue(g.buckets)
        local h = history[key]
        if not h and g.units >= 2 then
            h = {}
            history[key] = h
        end
        local day, low = math.floor(now / 86400), g.rows[1] and g.rows[1].unit
        local soldToday = 0
        if h then
            -- Lots first: when they cover the whole item, the flow counts only confirmed sales.
            local confirmed
            if j.lots then
                soldToday, confirmed = S.trackLots(h, g.seq or {}, now, g.owners, key)
            end
            M.recordFlow(h, g.buckets, value, now, confirmed)
            h.units = g.units
            -- Weekly pattern only for items traded often enough to have one.
            if g.units >= 10 or h.t then
                M.recordTiming(h, value, now)
            end
            h.days = type(h.days) == "table" and h.days or {}
            if not h.days[1] and (h.hits or 0) <= 0 and g.units < 10 then
                h.days = nil -- a rarely traded item: no daily history kept
            end
        end
        if h and h.days then
            local last = h.days[#h.days]
            if last and last.d == day then
                if low and (not last.min or low < last.min) then
                    last.min = low
                end
                last.m = value or last.m
                last.n = g.units
                last.s = (last.s or 0) + soldToday
            else
                h.days[#h.days + 1] = { d = day, min = low, m = value, n = g.units, s = soldToday }
                while #h.days > S.DAYS do
                    table.remove(h.days, 1)
                end
            end
        end
        g.market = value
        g.buckets = nil
        j.listed[key] = g.units or 1
        stats.items = stats.items + 1
        local vendor = F.AH.vendorPrice(g.id)
        if vendor then
            stats.vendorKnown = stats.vendorKnown + 1
            if g.rows[1] and g.rows[1].unit < vendor then
                stats.belowVendor = stats.belowVendor + 1
            end
        elseif g.rows[1] and not F.AH.vendorKnown(g.id) then
            -- Re-evaluated when the item's data loads (F.Scan.itemLoaded); items a vendor does
            -- not buy (price 0) never wait. The waiting copy keeps its 3 cheapest rows (a vendor
            -- deal needs no more); the resale evaluation below still sees every row.
            local waiting = { key = g.key, kind = g.kind, id = g.id, link = g.link, market = value, rows = {} }
            for n = 1, math.min(3, #g.rows) do
                waiting.rows[n] = g.rows[n]
            end
            j.waitVendor[g.id] = j.waitVendor[g.id] or {}
            table.insert(j.waitVendor[g.id], waiting)
        end
        local deal, reason = F.Deals.evaluate(g, vendor, h, now)
        if h and M.saleability(h, value, now).known then
            stats.salesReady = (stats.salesReady or 0) + 1
        end
        -- Sales measured from one pair of scans only: resale buys at most 2 of them until a second.
        if h and type(h.sales) == "table" and (h.sales.pairs or 0) == 1 then
            stats.onePair = (stats.onePair or 0) + 1
        end
        if deal then
            deals[#deals + 1] = deal
        elseif reason == "collecting" then
            stats.collecting = stats.collecting + 1
        end
        if not deal and reason then
            stats.reasons = stats.reasons or {}
            stats.reasons[reason] = (stats.reasons[reason] or 0) + 1
        end
        local cheap = g.rows[1] and g.rows[1].unit
        local near = deal ~= nil
            or (cheap and vendor and cheap < vendor * 1.25)
            or (cheap and value and cheap < value * 0.7 and g.units >= 3)
        if h then
            h.hits = (h.hits or 0) * 0.9 + (near and 1 or 0)
        end
        if near then
            S.hotInsert(j.hot, { key = key, score = (h and h.hits or 1) + (deal and 5 or 0) })
        end
        if done() then
            return false
        end
    end
    if not j.tidyKeys then
        -- One pass over the whole history, a slice per frame: items that vanished from the house
        -- since the last scan (all their lots are gone), and items not seen for 14 days (forgotten,
        -- so the saved file does not grow forever). The keys are taken first, so nothing added
        -- meanwhile upsets the walk.
        local previous = S.last and S.last.scope == j.scope and S.last or market.last
        j.sweep = j.lots
            and not (
                (j.unreadable or 0) > j.total * 0.005
                or (type(previous) == "table" and (previous.total or 0) > 0 and j.total < previous.total * 0.6)
                or S.isShort(j.scope, j.total)
            )
        j.tidyKeys, j.tidyAt = {}, 1
        for key in pairs(history) do
            j.tidyKeys[#j.tidyKeys + 1] = key
        end
        if done() then
            return false
        end
    end
    local keys = j.tidyKeys
    while j.tidyAt <= #keys do
        local key = keys[j.tidyAt]
        j.tidyAt = j.tidyAt + 1
        local h = history[key]
        if
            type(h) == "table"
            and j.sweep
            and (h.lots or h.pending)
            and not j.groups[key]
            and (h.lotsAt or h.pendingAt or now) < now
        then
            -- Not when rows could not be read at all, or the scan is far smaller than the house's
            -- last one (a partial answer): then a missing item proves nothing.
            local item = U.parseKey(key)
            if not (item and j.unread and j.unread[item.id]) then
                local sold = S.trackLots(h, {}, now, {}, key)
                local today = h.days and h.days[#h.days]
                if sold > 0 and today and today.d == math.floor(now / 86400) then
                    today.s = (today.s or 0) + sold
                end
                h.lots, h.lotsAt = nil, nil
                if h.pending then
                    h.lotsAt = h.pendingAt -- kept for the suspects only, until the next scan
                end
            end
        end
        if h ~= nil and S.stale(h, now) then
            history[key] = nil
        end
        if done() then
            return false
        end
    end
    return true
end

-- Compares an item's lots with those of the previous scan and records the sales; keeps this scan's
-- lots for the next comparison. Two steps protect every figure built on sales (sold per day, sale
-- prices, the flow, the daily history and what is shared) from reposts: a lot that got smaller is
-- sold at once; a lot that vanished whole is a suspect (h.pending) and sold only when the next scan
-- shows no new lot of its price and count (M.confirmGone). Returns the units sold, and the confirmed
-- sales by price when the lots cover the whole item (nil otherwise).
-- Units of `key` the player's characters bought on this auction house after `since` and up to
-- `now`: their purchases took lots too, and are no demand of the market.
function S.ownBought(key, since, now)
    local units = 0
    if not F.db or type(F.db.chars) ~= "table" or not key then
        return units
    end
    for _, c in pairs(F.db.chars) do
        local journal = type(c) == "table" and c.journal
        for i = #(journal or {}), 1, -1 do
            local e = journal[i]
            if type(e) == "table" and (e.at or 0) <= since then
                break
            end
            if type(e) == "table" and e.kind == "buy" and e.key == key and not e.merchant and (e.at or 0) <= now then
                units = units + (e.qty or 0)
            end
        end
    end
    return units
end

-- Takes `units` out of a sale map ({ [price] = units }), cheapest first (purchases take the
-- cheapest lots); returns what is left to take.
local function takeCheapest(map, units)
    local prices = {}
    for price in pairs(map) do
        prices[#prices + 1] = price
    end
    table.sort(prices)
    for _, price in ipairs(prices) do
        if units <= 0 then
            break
        end
        local take = math.min(units, map[price])
        map[price], units = map[price] - take, units - take
        if map[price] <= 0 then
            map[price] = nil
        end
    end
    return units
end

-- Lots that vanished whole, less the player's own purchases (cheapest first).
local function takeOwnFromGone(gone, units)
    if units <= 0 or not gone[1] then
        return gone, units
    end
    local lots = {}
    for i = 1, #gone - 2, 3 do
        lots[#lots + 1] = { gone[i], gone[i + 1], gone[i + 2] }
    end
    table.sort(lots, function(a, b)
        return a[1] < b[1]
    end)
    local out = {}
    for _, lot in ipairs(lots) do
        local take = math.min(units, lot[2])
        units = units - take
        if lot[2] - take > 0 then
            out[#out + 1], out[#out + 2], out[#out + 3] = lot[1], lot[2] - take, lot[3]
        end
    end
    return out, units
end

function S.trackLots(h, seq, now, owners, key)
    local sold, byPrice, confirmed, fresh, sellers, gone, complete = 0, {}, {}, nil, nil, nil, false
    local dt = now - (h.lotsAt or 0)
    local compared = h.lots and dt >= 300 and dt <= 3 * 3600
    owners = owners or {}
    if compared then
        local prev = M.unpackLots(h.lots)
        local all, reposted
        _, all, gone, reposted, sellers = M.trackSales(prev, seq, dt, M.unpackOwners(h.lotOwners), owners)
        for i = 1, #gone - 2, 3 do
            all[gone[i]] = all[gone[i]] - gone[i + 1]
        end
        for price, units in pairs(all) do
            if units > 0 then
                byPrice[price] = units
            end
        end
        -- The player's own purchases since the last scan are no market demand: they come out of
        -- the lots that vanished first (bought whole), then of the lots bought in part.
        local own = S.ownBought(key, h.lotsAt or 0, now)
        gone, own = takeOwnFromGone(gone, own)
        takeCheapest(byPrice, own)
        fresh = reposted
        complete = #prev < 3 * M.LOTS and #seq < 3 * M.LOTS
    else
        fresh = M.lotKeys(seq)
        sellers = M.lotSellers(owners)
    end
    if h.pending then
        if now - (h.pendingAt or 0) <= M.CONFIRM_WITHIN and now > (h.pendingAt or now) then
            M.confirmGone(M.unpackPending(h.pending), fresh, confirmed, sellers)
        end
        h.pending, h.pendingAt = nil, nil
    end
    for price, units in pairs(confirmed) do
        byPrice[price] = (byPrice[price] or 0) + units
    end
    if gone and gone[1] then
        h.pending, h.pendingAt = M.packPending(gone), now
    end
    if compared or next(byPrice) then
        sold = M.recordSales(h, byPrice, compared and dt or 0, now, confirmed)
    end
    if #seq > 0 then
        h.lots, h.lotsAt = M.packLots(seq), now
        h.lotOwners = M.packOwners(owners)
    else
        h.lotOwners = nil
    end
    return sold, complete and byPrice or nil
end

-- Units of an item in a recent full scan (up to 20 minutes old) of this auction house; nil when
-- there is no such scan.
function S.listedUnits(key)
    local last = S.last
    if not last or not last.listed or last.scope ~= F.Engine.scope() or F.Engine.clock() - (last.at or 0) > 1200 then
        return nil
    end
    return last.listed[key] or 0
end

-- True when a recent full scan (up to 20 minutes old) of this auction house saw no lot of the item
-- from another player: nobody sells it, whether or not an exact search answers.
function S.notListed(key)
    local last = S.last
    return last ~= nil
        and last.listed ~= nil
        and last.scope == F.Engine.scope()
        and F.Engine.clock() - (last.at or 0) <= 1200
        and not last.listed[key]
end

local function beginFinish(j, now)
    j.state, j.cursor, j.finishAt = "finishing", 1, now
    j.deals, j.waitVendor, j.hot, j.listed = {}, {}, {}, {}
    j.stats = { items = 0, vendorKnown = 0, belowVendor = 0, collecting = 0, salesReady = 0, reasons = {} }
end

-- A money gain can make leads affordable without another server scan. Reuse only the short-lived
-- local rows, in slices; live-verified results and items already bought from this scan stay intact.
function S.onMoney()
    local last = S.last
    if not last or not last.groups then
        return
    end
    local wallet, previous = F.Engine.wallet(), last.wallet
    last.wallet = wallet
    S.repricing = nil
    if S.job or not previous or wallet <= previous or clock() - last.at > 300 then
        return
    end
    S.repricing = { last = last, cursor = nil }
end

local function reprice()
    local work = S.repricing
    if not work then
        return
    end
    local last = work.last
    if last ~= S.last or not last.groups or last.scope ~= F.Engine.scope() or clock() - last.at > 300 then
        S.repricing = nil
        return
    end
    local history = F.Data.market(F.db, last.scope).history
    local done = budget(2, 100)
    while true do
        local key, group = next(last.groups, work.cursor)
        if not key then
            S.repricing = nil
            return
        end
        work.cursor = key
        local live = F.Deals.get(key)
        if not (live and live.verified) and not (last.purchased and last.purchased[key]) then
            group = last.checkedGroups and last.checkedGroups[key] or group
            local deal = F.Deals.evaluate(group, F.AH.vendorPrice(group.id), history[key], last.at)
            if deal then
                F.Deals.add(deal, last.scope)
            elseif live and live.found == last.at then
                F.Deals.remove(key)
            end
        end
        if done() then
            return
        end
    end
end

-- Called every frame while a scan runs.
function S.step()
    local j = S.job
    if not j then
        reprice()
        return
    end
    S.repricing = nil
    if j.scope ~= F.Engine.scope() or not F.AH.isOpen() then
        S.stop()
        return
    end
    local now = clock()
    if j.state == "waiting" and now ~= j.painted then
        j.painted = now -- the seconds on the status line, and the end of the quiet minute
        F.Engine.changed()
    end
    if j.state == "waiting" then
        if polled(j, now) then
            beginReading(j, j.last)
        elseif now - j.at > S.ANSWER_WAIT then
            -- No answer: the next try waits the whole window counted from this call. Trying sooner
            -- starts the server's 15 minutes again and keeps the answer away. Whether the server
            -- sent nothing or a list that kept changing tells the two cases apart.
            S.job = nil
            F.db.lastScan = j.at
            local seen = j.seen or 0
            settle(seen > 0 and "list kept changing" or "no answer", seen)
            F.Engine.notify(seen > 0 and "scan_unsettled" or "scan_timeout")
        end
        return
    end
    if j.state == "reading" then
        local done = budget(6, 400)
        while j.index < j.total do
            local i = j.index
            j.index = i + 1
            F.Raw.capture(j, i)
            if not ingest(j, i) then
                j.deferred[#j.deferred + 1] = i
            end
            if done() then
                return
            end
        end
        j.state, j.recoverUntil = "recovering", now + S.RECOVER
        return
    end
    if j.state == "recovering" then
        -- Keep the cursor across frames. Recopying the tail and starting again at row one both
        -- cost O(n) per frame and starved loaded rows behind a long uncached prefix.
        j.recoverLeft = j.recoverLeft or {}
        j.recoverIndex = j.recoverIndex or 1
        local done = budget(4, 200)
        while j.recoverIndex <= #j.deferred do
            local i = j.deferred[j.recoverIndex]
            j.recoverIndex = j.recoverIndex + 1
            if not ingest(j, i) then
                j.recoverLeft[#j.recoverLeft + 1] = i
            end
            if done() then
                return
            end
        end
        j.deferred, j.recoverLeft, j.recoverIndex = j.recoverLeft, nil, nil
        if #j.deferred == 0 then
            beginFinish(j, now)
        elseif now >= j.recoverUntil then
            j.skipped = j.skipped + #j.deferred
            j.state, j.unreadIndex, j.unread = "unread", 1, {}
        end
        return
    end
    if j.state == "unread" then
        -- Missing rows must not count as sales. Even this final pass is bounded for a large
        -- scan whose item information never loaded.
        local done = budget(4, 200)
        while j.unreadIndex <= #j.deferred do
            local i = j.deferred[j.unreadIndex]
            j.unreadIndex = j.unreadIndex + 1
            local ok, r = pcall(F.AH.replicateRow, i)
            if ok and r and r.id then
                j.unread[r.id] = true
            end
            if done() then
                return
            end
        end
        beginFinish(j, now)
        return
    end
    if j.state == "finishing" then
        if not finish(j, budget(6, 300)) then
            return
        end
        if not j.partial then
            F.Data.market(F.db, j.scope).peak = { total = j.total, at = j.finishAt }
        end
        S.last = {
            at = j.finishAt,
            wallet = F.Engine.wallet(),
            scope = j.scope,
            total = j.total,
            partial = j.partial,
            read = j.read,
            skipped = j.skipped,
            own = j.own,
            stats = j.stats,
            waitVendor = j.waitVendor,
            -- Units of every item listed in the scan, by key (kept in memory only).
            listed = j.listed,
            -- Every item's cheapest lots, for 5 minutes: they stand for a price search of an item
            -- to post (T.scanPrice).
            groups = not j.partial and j.groups or nil,
            -- The scan named the player's own lots (and left them out of `listed`).
            ownersKnown = j.own > 0,
        }
        S.job, S.finishedAt = nil, clock()
        settle(j.partial and "read, partial" or "read", j.total)
        F.Raw.finish(j)
        S.setHot(j.hot)
        if F.Analytics then
            F.Analytics.invalidate()
        end
        F.Deals.replace(j.deals, j.scope)
        F.Bids.finish(j, F.Data.market(F.db, j.scope).history)
        -- The scan is put into the saved data on logout and when another house opens (S.save), not
        -- here: the game writes saved data only then, and copying it is the costliest end step.
        F.Engine.notify("scan_done")
        if F.Trade.afterScan then
            pcall(F.Trade.afterScan)
        end
        F.Share.afterScan()
    end
end

-- The last scan, its deals and the items waiting for a vendor price are saved, so a /reload or a
-- new login shows them until the next full scan. Their prices are checked again before buying.
local POOL = 6000
-- The sniper's list: items most often near a deal, best first.
S.HOT = 150
local function hotBefore(a, b)
    if a.score ~= b.score then
        return a.score > b.score
    end
    return a.key < b.key
end

-- Keeps the best HOT entries sorted while a scan is evaluated (no sort of every item at the end).
function S.hotInsert(list, entry)
    local n = #list
    if n >= S.HOT and not hotBefore(entry, list[n]) then
        return
    end
    local lo, hi = 1, n + 1
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        if hotBefore(entry, list[mid]) then
            hi = mid
        else
            lo = mid + 1
        end
    end
    table.insert(list, lo, entry)
    if #list > S.HOT then
        list[#list] = nil
    end
end

function S.setHot(list)
    table.sort(list, hotBefore)
    S.hot = {}
    for i = 1, math.min(S.HOT, #list) do
        S.hot[i] = list[i].key
    end
end

function S.save()
    local last = S.last
    if not last or not F.db then
        return
    end
    local pool = {}
    for _, list in pairs(last.waitVendor or {}) do
        for _, g in ipairs(list) do
            if #pool < POOL then
                pool[#pool + 1] =
                    { key = g.key, kind = g.kind, id = g.id, link = g.link, market = g.market, rows = g.rows }
            end
        end
    end
    local deals = {}
    for _, d in ipairs(F.Deals.list) do
        local copy = U.copy(d)
        copy.rows = nil
        deals[#deals + 1] = copy
    end
    F.Data.market(F.db, last.scope).last = {
        at = last.at,
        total = last.total,
        partial = last.partial,
        read = last.read,
        skipped = last.skipped,
        own = last.own,
        stats = U.copy(last.stats),
        deals = deals,
        pool = pool,
        hot = S.hot,
    }
end

function S.restore(scope)
    if S.job or not F.db or (S.last and S.last.scope == scope) then
        return false
    end
    if S.last then
        -- Another house was open before (a faction house, then a neutral one): its scan, deals
        -- and sniper list must not stay on screen here.
        S.save()
        S.last, S.hot = nil, {}
        F.Deals.replace({}, scope)
    end
    local saved = F.Data.market(F.db, scope).last
    if type(saved) ~= "table" or type(saved.stats) ~= "table" then
        return false
    end
    local waitVendor = {}
    for _, g in ipairs(saved.pool or {}) do
        waitVendor[g.id] = waitVendor[g.id] or {}
        table.insert(waitVendor[g.id], g)
    end
    if saved.stats.salesReady == nil then
        local ready = 0
        for _, h in pairs(F.Data.market(F.db, scope).history) do
            if
                type(h) == "table"
                and type(h.scan) == "table"
                and h.scan.at == saved.at
                and M.saleability(h, h.scan.market, saved.at).known
            then
                ready = ready + 1
            end
        end
        saved.stats.salesReady = ready
    end
    S.last = {
        at = saved.at,
        scope = scope,
        total = saved.total or 0,
        partial = saved.partial,
        read = saved.read or 0,
        skipped = saved.skipped or 0,
        own = saved.own or 0,
        stats = saved.stats,
        waitVendor = waitVendor,
    }
    S.hot = type(saved.hot) == "table" and saved.hot or {}
    local deals = {}
    for _, d in ipairs(saved.deals or {}) do
        -- A check from an earlier session says nothing about the lots now.
        d.verified, d.tried = nil, nil
        deals[#deals + 1] = d
    end
    F.Deals.replace(deals, scope)
    return true
end

-- An item not seen in a full scan (or a shared one) for 14 days is forgotten.
function S.stale(h, now)
    local seen = type(h) == "table"
            and math.max(h.scan and h.scan.at or 0, type(h.shared) == "table" and h.shared.at or 0)
        or 0
    return now - seen > 14 * 86400
end

-- Forgets every stale item at once (the end of a scan does it a slice per frame).
function S.prune(scope, now)
    local history = F.Data.market(F.db, scope).history
    for key, h in pairs(history) do
        if S.stale(h, now) then
            history[key] = nil
        end
    end
end

-- Item data arrived: an item of the last scan without a known vendor price may be a vendor deal.
function S.itemLoaded(id)
    local last = S.last
    local list = last and last.waitVendor and last.waitVendor[id]
    if not list then
        return
    end
    last.waitVendor[id] = nil
    local vendor = F.AH.vendorPrice(id)
    if not vendor then
        return
    end
    last.stats.vendorKnown = last.stats.vendorKnown + 1
    local history = F.Data.market(F.db, last.scope).history
    for _, g in ipairs(list) do
        if g.rows[1] and g.rows[1].unit < vendor then
            last.stats.belowVendor = last.stats.belowVendor + 1
            local deal = F.Deals.evaluate(g, vendor, history[g.key], last.at)
            if deal then
                F.Deals.add(deal, last.scope)
            end
        end
    end
end

-- Progress for the status bar: text key, done, total.
function S.progress()
    local j = S.job
    if not j then
        return nil
    end
    if j.state == "waiting" then
        return "scan_waiting", math.floor(clock() - j.at), S.ANSWER_WAIT
    elseif j.state == "reading" then
        return "scan_reading", j.index, j.total
    elseif j.state == "recovering" or j.state == "unread" then
        return "scan_recovering", j.total - #j.deferred, j.total
    end
    return "scan_finishing", j.cursor - 1, #j.order
end
