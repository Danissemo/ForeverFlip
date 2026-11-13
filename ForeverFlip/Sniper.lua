-- Fast sniper. A browse query with an empty search returns every item of the auction house with
-- its lowest price (7718 items in 8.5 seconds over 16 requests, seen on WoW Forever); a key query
-- (SearchForItemKeys) returns the same for up to 100 chosen items in one request. Items whose
-- lowest price may be a deal become candidates; each candidate is then read with an exact search
-- and evaluated with the full deal rules (F.Deals) before anything can be bought.
--
-- One round: the whole house page by page, then a pause. During the pause, the hot items of the
-- last scan and the shopping list are re-read in batches of 100 keys. Exact checks of candidates
-- come first: no browse request is sent while candidates wait.
local F = ForeverFlip
local U = F.Util
local S = {}
F.Sniper = S

S.PAUSE = 2.5 -- seconds between two rounds of the whole house
S.KEYS = 100 -- items per key query
S.TIMEOUT = 10 -- seconds without an answer before a query is given up
S.REJUDGE = 120 -- seconds before an unchanged lowest price is judged again
S.BUDGET = 3 -- milliseconds of browse rows read per frame
S.PER_FRAME = 300 -- browse rows read per frame where the game has no profiler to time them

-- Browses other addons (or the player) send are read too, but only their new rows, a few per
-- frame: re-reading every row at each page froze the game while another addon browsed the whole
-- house (ForeverForge Auction 2.1.14 fixed the same freeze). A frame is bounded by time, not rows:
-- a row of gear is judged for every known ending of its item ID, and 300 such rows took 35 ms.
S.backlog, S.backlogAt, S.outsideRead = {}, 1, 0

S.candidates = {} -- keys waiting for an exact check, best first: { key, score }
S.judged = {} -- key -> { price, at } of the last judgement
S.rounds, S.items, S.found = 0, 0, 0

local function now()
    return GetTime and GetTime() or F.Engine.clock()
end

function S.supported()
    return F.AH.canBrowse()
end

-- Running: the sniper is on and the game offers browse queries.
function S.active()
    return F.db and F.db.settings.sniper and S.supported() or false
end

-- Gear keys by item ID: one item ID covers several endings, told apart only by the exact search.
local gearKeys, gearStamp
local function gearFor(id)
    local last = F.Scan.last
    local stamp = F.Engine.scope() .. ":" .. tostring(last and last.at)
    if gearStamp ~= stamp then
        gearKeys, gearStamp = {}, stamp
        for key in pairs(F.Data.market(F.db, F.Engine.scope()).history) do
            local item = U.parseKey(key)
            if item and item.kind == "gear" then
                gearKeys[item.id] = gearKeys[item.id] or {}
                table.insert(gearKeys[item.id], key)
            end
        end
    end
    return gearKeys[id]
end

-- The part of a threshold that comes from the item's history alone: the exit price (sale price,
-- else usual price, a legal step) and whether 0.5 units a day sell there. Every browse row asked
-- for it again (at every known ending, for gear) though it changes only with the history: kept per
-- history entry until a full scan writes a new h.scan or moves h.sales.at or h.flow.at, a shared
-- scan writes a new h.shared, or the sales model reset drops them. Weak keys: an entry goes with
-- its history (another house, an item pruned). The vendor price, deposit, cut, settings, the
-- disenchant value and the shopping price change without the history (item data that loads, a
-- merchant seen): they are read at every row.
local exits = setmetatable({}, { __mode = "k" })
local function exitOf(h, kind)
    local scan, shared, sales, flow = h.scan, h.shared, h.sales, h.flow
    local salesAt = type(sales) == "table" and sales.at or nil
    local flowAt = type(flow) == "table" and flow.at or nil
    local c = exits[h]
    if
        c
        and c[1] == scan
        and c[2] == shared
        and c[3] == sales
        and c[4] == flow
        and c[5] == salesAt
        and c[6] == flowAt
    then
        return c[7], c[8]
    end
    local exit, sells = nil, false
    local market = F.Market.usual(h)
    if U.finite(market) and market > 0 then
        exit = U.stepDown(F.Market.salePrice(h) or market, kind)
        local d = F.Market.saleability(h, exit, F.Engine.clock())
        sells = d.known and d.perDay >= 0.5
    end
    exits[h] = { scan, shared, sales, flow, salesAt, flowAt, exit, sells }
    return exit, sells
end

-- The highest lowest-price at which an item can still hold a deal; nil when it cannot.
function S.threshold(key, id, history)
    local item = U.parseKey(key)
    local s = F.db.settings
    local limit
    local vendor = F.AH.vendorPrice(id)
    if vendor then
        limit = vendor - math.max(1, s.vendorMinProfit or 10)
    end
    local h = history[key]
    local exit, sells
    if type(h) == "table" then
        exit, sells = exitOf(h, item and item.kind)
    end
    if sells then
        local deposit = F.Market.deposit(F.AH.clientVendorPrice(id), 1)
        local buy = (F.Market.net(exit, 1) - deposit) / (1 + (s.minROI or 0.2))
        limit = math.max(limit or 0, math.floor(buy))
    end
    if item and item.kind == "gear" and F.Disenchant.active() then
        local value = F.Disenchant.value(id)
        if value then
            limit = math.max(limit or 0, value - (s.minProfit or 100))
        end
    end
    local wanted = F.Shopping and F.Shopping.maxPrice(key)
    if wanted then
        limit = math.max(limit or 0, wanted)
    end
    if limit and limit > 0 then
        return limit
    end
end

local function enqueue(key, score)
    for _, c in ipairs(S.candidates) do
        if c.key == key then
            c.score = math.max(c.score, score)
            return
        end
    end
    local pos = #S.candidates + 1
    for i, c in ipairs(S.candidates) do
        if score > c.score then
            pos = i
            break
        end
    end
    table.insert(S.candidates, pos, { key = key, score = score })
    while #S.candidates > 200 do
        table.remove(S.candidates)
    end
end

-- Judges one lowest price. Also used for prices the player's own browsing shows.
function S.judge(key, id, price, history)
    if F.Shopping and F.Shopping.blocked(key) then
        return false
    end
    local limit = S.threshold(key, id, history)
    if not limit or price > limit then
        return false
    end
    local seen = S.judged[key]
    local t = F.Engine.clock()
    if seen and price >= seen.price and t - seen.at < S.REJUDGE then
        return false
    end
    local d = F.Deals.get(key)
    if d and d.verified and t - d.verified < 60 and price >= (d.maxUnit or 0) then
        return false
    end
    S.judged[key] = { price = price, at = t }
    enqueue(key, (limit - price) / limit)
    S.found = S.found + 1
    return true
end

local function listed(keys, key)
    for _, k in ipairs(keys or {}) do
        if k == key then
            return true
        end
    end
    return false
end

-- Gear keys of the shopping list and of buy-out orders by item ID, those the history does not list
-- (gearFor): an ending no full scan has seen yet is in no history, and its lots, read by every
-- key query of the shopping list, were never judged (a plain item on the list is).
local function shoppingGear()
    local out = {}
    if not F.Shopping then
        return out
    end
    local keys = F.Shopping.keys()
    for key in pairs(F.Shopping.orders or {}) do
        keys[#keys + 1] = key
    end
    for _, key in ipairs(keys) do
        local item = U.parseKey(key)
        if item and item.kind == "gear" and not listed(gearFor(item.id), key) and not listed(out[item.id], key) then
            out[item.id] = out[item.id] or {}
            table.insert(out[item.id], key)
        end
    end
    return out
end

-- One lowest price of a browse or key query: { id, minPrice, qty }. `ctx` keeps what the rows read
-- together share: the history and the shopping list's gear (built at the first gear row).
local function readRow(r, ctx)
    local history = ctx.history
    S.items = S.items + 1
    if F.Market.learnLow then
        F.Market.learnLow(history, r, F.Engine.clock())
    end
    local kind = F.AH.kindOf(r.id)
    if kind == "gear" then
        for _, key in ipairs(gearFor(r.id) or {}) do
            S.judge(key, r.id, r.minPrice, history)
        end
        ctx.shopping = ctx.shopping or shoppingGear()
        for _, key in ipairs(ctx.shopping[r.id] or {}) do
            S.judge(key, r.id, r.minPrice, history)
        end
    elseif kind then
        S.judge(U.key(kind, r.id), r.id, r.minPrice, history)
    end
end

local function readContext()
    return { history = F.Data.market(F.db, F.Engine.scope()).history }
end

-- Lowest prices of browse or key queries: { id, minPrice, qty }.
function S.read(rows)
    local ctx = readContext()
    for _, r in ipairs(rows) do
        readRow(r, ctx)
    end
end

-- The next candidate for an exact check (F.Deals.snipe).
function S.next()
    local c = table.remove(S.candidates, 1)
    return c and c.key
end

-- A candidate whose search could not start (the request budget): first again next time.
function S.putBack(key)
    table.insert(S.candidates, 1, { key = key, score = math.huge })
end

local function idle()
    local D = F.Deals
    return F.AH.isOpen()
        and not F.Scan.blocking()
        and not F.Trade.busy()
        and not D.search
        and #D.requests == 0
        and not D.backgroundRetry
        and #S.backlog == 0
        and #S.candidates == 0
        and not D.holding()
        -- The game's own Buy or Sell page is shown: a browse now would replace what it shows
        -- (D.holding is false once ForeverFlip's frame is hidden for it).
        and not (F.AH.nativeShown and F.AH.nativeShown())
        and F.AH.ready()
end

-- Item IDs re-read between rounds: the sniper list of the last scan and the shopping list.
local function watchIDs()
    local ids, seen = {}, {}
    local function add(key)
        local item = U.parseKey(key)
        if item and not seen[item.id] then
            seen[item.id] = true
            ids[#ids + 1] = item.id
        end
    end
    for _, key in ipairs(F.Scan.hot or {}) do
        add(key)
    end
    if F.Shopping then
        for _, key in ipairs(F.Shopping.keys()) do
            add(key)
        end
    end
    return ids
end

local function send(kind, ids)
    local q = { kind = kind, at = now(), read = 0 }
    S.query = q
    local ok
    if kind == "browse" then
        ok = pcall(F.AH.browse)
    else
        ok = pcall(F.AH.searchKeys, ids)
    end
    if not ok and S.query == q then
        S.query = nil
    end
end

-- A query of the sniper sent and not answered yet: a gear search waits for it (Deals).
function S.inFlight()
    return S.query ~= nil and not S.query.more and not S.query.answered
end

-- A gear search needs the browse: the round in flight gives way and starts again after a pause.
function S.yield()
    if S.query then
        S.query = nil
        S.nextRound = now() + S.PAUSE
    end
end

-- The rows of the backlog that S.BUDGET milliseconds allow (S.PER_FRAME without the profiler).
local function readBacklog()
    local backlog, ctx = S.backlog, readContext()
    local ms = F.Engine.workSlice(S.BUDGET)
    local start = debugprofilestop and debugprofilestop()
    local n = 0
    while S.backlogAt <= #backlog do
        local r = backlog[S.backlogAt]
        S.backlogAt = S.backlogAt + 1
        n = n + 1
        readRow(r, ctx)
        if S.backlog ~= backlog then
            return -- reset meanwhile (S.reset): a new backlog starts at its own row 1
        end
        if start and debugprofilestop() - start >= ms or not start and n >= S.PER_FRAME then
            break
        end
    end
    if S.backlogAt > #backlog then
        S.backlog, S.backlogAt = {}, 1
    end
end

-- Called every frame.
function S.step()
    if #S.backlog > 0 and F.db then
        readBacklog()
    end
    if not S.active() then
        S.query = nil
        return
    end
    local t = now()
    local q = S.query
    if q and t - q.at > S.TIMEOUT then
        S.query, q = nil, nil
        S.nextRound = t + S.PAUSE
    end
    if q then
        -- No next page while a full scan waits for its answer: any query then can keep it away.
        -- ready() comes last: with the throttle stuck it lets one message through, and a gate that
        -- failed after it wasted that one (the Buy button waited 5 seconds more for the next).
        if
            q.more
            and not F.Deals.search
            and not F.Deals.pending()
            and #S.backlog == 0
            and not F.Trade.busy()
            and not F.Trade.postingNow()
            and #S.candidates == 0
            and not F.Deals.holding()
            and not F.Scan.blocking()
            and not (F.AH.nativeShown and F.AH.nativeShown())
            and F.AH.ready()
        then
            q.more, q.at, q.answered = false, t, false
            pcall(F.AH.browseMore)
        end
        return
    end
    if not idle() then
        return
    end
    if t >= (S.nextRound or 0) then
        send("browse")
        return
    end
    -- Pause between rounds: the watched items, a batch of keys per second.
    if t - (S.lastKeys or 0) >= 1 then
        local ids = watchIDs()
        if #ids > 0 then
            local from = ((S.keyIndex or 0) % #ids) + 1
            local batch = {}
            for i = from, math.min(#ids, from + S.KEYS - 1) do
                batch[#batch + 1] = ids[i]
            end
            S.keyIndex = from + #batch - 1
            S.lastKeys = t
            send("keys", batch)
        end
    end
end

-- AUCTION_HOUSE_BROWSE_RESULTS_UPDATED / _ADDED. Results of a query the player sent in the game's
-- own Buy tab are read too (lowest prices and candidates), without changing the round.
function S.onResults(first)
    local q = S.query
    local rows = F.AH.browseResults()
    if not q then
        if first or #rows < S.outsideRead then
            S.outsideRead = 0
        end
        for i = S.outsideRead + 1, #rows do
            S.backlog[#S.backlog + 1] = rows[i]
        end
        S.outsideRead = #rows
        return
    end
    q.answered = true
    local fresh = {}
    for i = q.read + 1, #rows do
        fresh[#fresh + 1] = rows[i]
    end
    q.read = #rows
    -- Judge our own large pages under the same per-frame bound as other addons' pages.
    for _, row in ipairs(fresh) do
        S.backlog[#S.backlog + 1] = row
    end
    if q.kind == "browse" and not F.AH.browseFull() then
        q.more, q.at = true, now()
        return
    end
    if q.kind == "browse" then
        S.rounds = S.rounds + 1
        S.nextRound = now() + S.PAUSE
    end
    S.query = nil
    F.Engine.changed()
end

function S.onFailure()
    if S.query then
        S.query = nil
        S.nextRound = now() + S.PAUSE
    end
end

-- AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED, heard before the other handlers (Core): a query of the
-- sniper sent just before was thrown away, and nothing answers it. Searches, purchases, posts
-- and the full scan wait while it is in flight (S.inFlight), and they waited out S.TIMEOUT: 10
-- seconds of a dead auction house. An exact search, a purchase or a full scan request still
-- waiting for its answer owns the drop instead (Deals, Trade and Scan handle it).
S.DROP_WINDOW = 3 -- seconds after sending in which a drop is taken for the sniper's
function S.onDropped()
    local q = S.query
    if
        not S.inFlight()
        or now() - q.at > S.DROP_WINDOW
        or F.Deals.searching()
        or F.Trade.busy()
        or F.Scan.blocking()
    then
        return
    end
    S.query = nil
    S.nextRound = now() + S.PAUSE
    -- Should an answer come after all, a gear search must not take it for its own browse
    -- (AH.foreignRecent): key queries are answered as browse results too.
    F.AH.foreignAt = F.Engine.clock()
    F.Engine.changed()
end

-- The auction house closed or the sniper was switched off.
function S.reset()
    S.query, S.candidates, S.nextRound = nil, {}, nil
    S.backlog, S.backlogAt, S.outsideRead = {}, 1, 0
end
