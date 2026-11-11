-- Full scan: ReplicateItems returns every auction of the house (often 200 000 and more) once
-- per 15 minutes. The rows are read in small steps per frame, grouped per item key, and every
-- item is evaluated for a vendor deal and a resale from the scan data. Found deals are then
-- verified one by one with an exact search (F.Deals).
local F = ForeverFlip
local U = F.Util
local M = F.Market
local S = {}
F.Scan = S

S.COOLDOWN = 900
S.ROWS = 40 -- cheapest auctions kept per item
S.RECOVER = 30 -- seconds to wait for item data of rows the game had not loaded
S.DAYS = 14 -- daily records kept per item (price, cheapest, units listed and sold)
-- Seconds to wait for the server's answer to a full scan. Since WoW Forever launched the answer
-- can take minutes (ForeverForge waits 2, auxForever 0.8.2 waits 10), but a call refused by the
-- 15-minute account limit (another addon used the window) is never answered: waiting 10 minutes
-- for it was too long in game. 3 minutes, then a new try a minute later.
S.ANSWER_WAIT = 180

local function clock()
    return F.Engine.clock()
end

-- Time budget for one frame: milliseconds with the profiler, else a fixed amount of work.
local function budget(ms, fallback)
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

-- Does the scan hold back searches and posts? While it is read and evaluated, and in the first
-- S.QUIET seconds of waiting for the answer (usually enough). After that searches go on while it
-- waits: a request the account's 15-minute limit refused is never answered, and the sniper would
-- otherwise stand still for the whole S.ANSWER_WAIT.
S.QUIET = 60
function S.blocking()
    local j = S.job
    if not j then
        return false
    end
    return j.state ~= "waiting" or clock() - (j.at or 0) < S.QUIET
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
    if not F.AH.ready(true) then
        return false, "throttled"
    end
    -- The job exists before the request: the answer event may come during the call itself.
    local base = F.AH.replicateCount()
    S.job = { state = "waiting", at = clock(), scope = F.Engine.scope(), base = base, last = -1 }
    local before = F.db.lastScan
    F.db.lastScan = clock()
    local ok = pcall(F.AH.replicate)
    if not ok then
        F.db.lastScan = before -- nothing reached the server
        S.job = nil
        return false, "error"
    end
    F.Engine.changed()
    return true
end

-- WoW Forever does not always send REPLICATE_ITEM_LIST_UPDATE (seen in game): the scan is
-- also taken once the number of replicated auctions changed and stopped growing for a second.
local function polled(j, now)
    if now - (j.polled or 0) < 1 then
        return false
    end
    j.polled = now
    local n = F.AH.replicateCount()
    local ready = n > 0 and n ~= j.base and n == j.last
    j.last = n
    return ready
end

local function beginReading(j, total)
    j.state, j.total, j.index = "reading", total, 0
    j.groups, j.order, j.deferred = {}, {}, {}
    j.read, j.skipped, j.own = 0, 0, 0
    F.AH.refreshPlayer()
    j.lots = F.AH.canTrackLots()
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
        and not F.Deals.searching()
        and F.AH.ready(true)
    then
        S.start()
    end
end

function S.stop()
    S.job = nil
end

-- AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED right after our own request: the server threw the request
-- away, so nothing will answer it. The next try is allowed in 10 seconds.
function S.onDropped()
    local j = S.job
    if j and j.state == "waiting" and not j.other and clock() - (j.at or 0) <= 3 then
        S.job = nil
        F.db.lastScan = clock() - S.COOLDOWN + 10
        F.Engine.notify("scan_timeout")
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
        last = -1,
        other = true,
    }
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
    if not U.finite(total) or total <= 0 then
        S.job = nil
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
    if (r.minBid or 0) > 0 and r.band == 0 and not mine then
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
            M.recordFlow(h, g.buckets, value, now)
            h.units = g.units
            if j.lots then
                soldToday = S.trackLots(h, g.seq or {}, now)
            end
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
        if deal then
            deals[#deals + 1] = deal
        elseif reason == "collecting" then
            stats.collecting = stats.collecting + 1
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
    if j.lots and not j.swept then
        -- Items that vanished from the house since the last scan: all their lots are gone. Not
        -- when rows could not be read at all, or when the scan is far smaller than the house's
        -- last one (a partial answer): then a missing item proves nothing.
        j.swept = true
        local previous = F.Data.market(F.db, j.scope).last
        local partial = (j.unreadable or 0) > j.total * 0.005
            or (type(previous) == "table" and (previous.total or 0) > 0 and j.total < previous.total * 0.6)
        for key, h in pairs(partial and {} or history) do
            local item = U.parseKey(key)
            if
                type(h) == "table"
                and h.lots
                and not j.groups[key]
                and (h.lotsAt or now) < now
                and not (item and j.unread and j.unread[item.id])
            then
                local sold = S.trackLots(h, {}, now)
                local today = h.days and h.days[#h.days]
                if sold > 0 and today and today.d == math.floor(now / 86400) then
                    today.s = (today.s or 0) + sold
                end
                h.lots, h.lotsAt = nil, nil
            end
        end
    end
    return true
end

-- Compares an item's lots with those of the previous scan and records the sales; keeps this scan's
-- lots for the next comparison. Returns the units sold.
function S.trackLots(h, seq, now)
    local sold = 0
    local dt = now - (h.lotsAt or 0)
    if h.lots and dt >= 300 and dt <= 3 * 3600 then
        local _, byPrice = M.trackSales(M.unpackLots(h.lots), seq, dt)
        sold = M.recordSales(h, byPrice, dt, now)
    end
    if #seq > 0 then
        h.lots, h.lotsAt = M.packLots(seq), now
    end
    return sold
end

-- Units of every item listed in the scan, by key (kept in memory only). On WoW Forever the scan does
-- not name sellers, so the player's own lots may be counted too.
function S.listedKeys(j)
    local listed = {}
    for key, g in pairs(j.groups or {}) do
        listed[key] = g.units or 1
    end
    return listed
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

-- Called every frame while a scan runs.
function S.step()
    local j = S.job
    if not j then
        return
    end
    if j.scope ~= F.Engine.scope() or not F.AH.isOpen() then
        S.job = nil
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
            -- No answer: try again in a minute instead of waiting the whole 15 minutes.
            S.job = nil
            F.db.lastScan = now - S.COOLDOWN + 60
            F.Engine.notify("scan_timeout")
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
        -- Rows of items the game had not loaded: read again once their data arrived.
        local left, done = {}, budget(4, 200)
        for n, i in ipairs(j.deferred) do
            if done() then
                for m = n, #j.deferred do
                    left[#left + 1] = j.deferred[m]
                end
                break
            end
            if not ingest(j, i) then
                left[#left + 1] = i
            end
        end
        j.deferred = left
        if #left == 0 or now >= j.recoverUntil then
            j.skipped = j.skipped + #left
            -- Items whose rows never loaded are still on the house: they must not count as gone.
            j.unread = j.unread or {}
            for _, i in ipairs(left) do
                local ok, r = pcall(F.AH.replicateRow, i)
                if ok and r and r.id then
                    j.unread[r.id] = true
                end
            end
            j.state, j.cursor, j.finishAt = "finishing", 1, now
            j.deals, j.waitVendor, j.hot = {}, {}, {}
            j.stats = { items = 0, vendorKnown = 0, belowVendor = 0, collecting = 0 }
        end
        return
    end
    if j.state == "finishing" then
        if not finish(j, budget(6, 300)) then
            return
        end
        S.last = {
            at = j.finishAt,
            scope = j.scope,
            total = j.total,
            read = j.read,
            skipped = j.skipped,
            own = j.own,
            stats = j.stats,
            waitVendor = j.waitVendor,
            listed = S.listedKeys(j),
            -- The scan named the player's own lots (and left them out of `listed`).
            ownersKnown = j.own > 0,
        }
        S.job, S.finishedAt = nil, clock()
        F.Raw.finish(j)
        S.setHot(j.hot)
        if F.Analytics then
            F.Analytics.invalidate()
        end
        F.Deals.replace(j.deals, j.scope)
        F.Bids.finish(j, F.Data.market(F.db, j.scope).history)
        S.prune(j.scope, j.finishAt)
        S.save()
        F.Engine.notify("scan_done")
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
    S.last = {
        at = saved.at,
        scope = scope,
        total = saved.total or 0,
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

-- Forgets items not seen in a full scan for 14 days, so the saved file does not grow forever.
function S.prune(scope, now)
    local history = F.Data.market(F.db, scope).history
    for key, h in pairs(history) do
        local seen = type(h) == "table"
                and math.max(h.scan and h.scan.at or 0, type(h.shared) == "table" and h.shared.at or 0)
            or 0
        if now - seen > 14 * 86400 then
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
    elseif j.state == "recovering" then
        return "scan_recovering", j.total - #j.deferred, j.total
    end
    return "scan_finishing", j.cursor - 1, #j.order
end
