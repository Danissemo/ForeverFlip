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

-- Quick scan: one round of the whole house asked by the player, the way TSM scans (a browse gives
-- every item's lowest price in about 16 requests, against one full scan per 15 minutes). It runs
-- with the sniper off: its candidates get the same exact check before anything can be bought, and
-- it ends once the round is read and they are checked. { at, items, found, done } while it runs.
S.quick = nil
S.QUICK_MAX = 180 -- seconds a quick scan may take before it is given up
-- Lowest prices the browse rounds read, by item ID, for the house in `scope`:
-- { price, qty, at, own } (own: the lowest may be the player's own lot). Kept for the session.
S.lows = { scope = nil }

-- Running: the sniper is on (or a quick scan runs) and the game offers browse queries.
function S.active()
    return F.db and (F.db.settings.sniper or S.quick ~= nil) and S.supported() or false
end

-- A quick scan can start: the game offers browse queries, the auction house is open, and no full
-- scan runs. With the sniper on too: the quick scan then reads one whole round of its own and lists
-- what it finds, which the sniper's rounds do not (it only checks its candidates).
function S.canQuick()
    return F.db ~= nil
        and S.supported()
        and F.AH.isOpen()
        and not S.quick
        and not F.Scan.busy()
        and not F.Scan.rebuilding()
end

function S.startQuick()
    if not S.canQuick() then
        return false
    end
    -- A round of the sniper already under way began before the quick scan: the quick scan's own
    -- round is the next one, sent right after it (S.onResults).
    S.quick = { at = now(), items = S.items, found = S.found, after = S.query }
    -- Deals check candidates for the house of its list; with no saved scan here there is none
    -- yet, and the candidates would wait until the quick scan gave up.
    if not F.Deals.scope then
        F.Deals.replace({}, F.Engine.scope())
    end
    S.nextRound = 0
    F.Engine.changed()
    return true
end

-- The quick scan running: items read and candidates found so far, or nil; once the house is read,
-- also the candidates still waiting for their exact check (only the best 200 are kept).
function S.quickProgress()
    local q = S.quick
    if not q then
        return nil
    end
    return S.items - q.items, S.found - q.found, q.done and #S.candidates or nil
end

local function endQuick(message)
    local q = S.quick
    if not q then
        return
    end
    S.quick = nil
    S.lastQuick = { at = F.Engine.clock(), items = S.items - q.items, found = S.found - q.found }
    if not F.db.settings.sniper then
        S.query, S.candidates = nil, {}
    end
    F.Engine.notify(message)
end

-- The player stops the quick scan (the scan button reads Stop quick scan while it runs). What
-- it read is kept.
function S.stopQuick()
    if not S.quick then
        return false
    end
    endQuick("quick_stopped")
    return true
end

-- The lowest price the last browse read for an item of this house, or nil: { price, qty, at, own }.
function S.low(id)
    local lows = S.lows
    if lows.scope ~= F.Engine.scope() then
        return nil
    end
    return lows[id]
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
        limit = F.Market.maxBuy(vendor, "vendor", s)
    end
    local h = history[key]
    local exit, sells
    if type(h) == "table" then
        exit, sells = exitOf(h, item and item.kind)
    end
    if sells then
        local buy = F.Market.maxBuy(F.Market.unitNet(id, item and item.kind, key, exit), "auction", s, true)
        limit = math.max(limit or 0, buy or 0)
    end
    if item and item.kind == "gear" and F.Disenchant.active() then
        local value = F.Disenchant.value(id)
        if value then
            limit = math.max(limit or 0, F.Market.maxBuy(value, "disenchant", s) or 0)
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

-- Judges one lowest price. Also used for prices the player's own browsing shows. `gear`: one key
-- of several endings priced by one browse row; readRow lists and counts them together.
function S.judge(key, id, price, history, gear)
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
    -- A deal checked in the last D.FRESH seconds keeps its "ready" for that long: the next browse
    -- round queued it again after a minute, and the list showed it queued and checking all the
    -- time. A lower price than the deal's own is news and is checked at once.
    local d = F.Deals.get(key)
    if d and d.verified and t - d.verified < F.Deals.FRESH and price >= (d.maxUnit or 0) then
        return false
    end
    S.judged[key] = { price = price, at = t }
    local score = (limit - price) / limit
    if gear then
        enqueue(key, score)
        return true
    end
    -- A quick scan lists its find in Deals at once; the finds that already make a deal are
    -- checked first once the house is read.
    local listed = S.quick ~= nil and F.Deals.addFound(key, price, t)
    enqueue(key, score + (listed and 1 or 0))
    S.found = S.found + 1
    return true
end

-- The endings of one piece of gear that one browse row priced (S.judge with `gear`): one find, one
-- row in Deals, its listed ending checked first.
local function judgeGear(keys, id, price, history)
    local hits = {}
    for _, key in ipairs(keys) do
        if S.judge(key, id, price, history, true) then
            hits[#hits + 1] = key
        end
    end
    if #hits == 0 then
        return
    end
    S.found = S.found + 1
    local listed = S.quick ~= nil and F.Deals.addFound(hits, price, F.Engine.clock())
    if listed then
        enqueue(listed, 1)
    end
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
    local lows = S.lows
    if lows.scope ~= ctx.scope then
        lows = { scope = ctx.scope }
        S.lows = lows
    end
    lows[r.id] = { price = r.minPrice, qty = r.qty, at = F.Engine.clock(), own = r.containsOwnerItem or nil }
    if F.Market.learnLow then
        F.Market.learnLow(history, r, F.Engine.clock())
    end
    local kind = F.AH.kindOf(r.id)
    if kind == "gear" then
        ctx.shopping = ctx.shopping or shoppingGear()
        local keys = {}
        for _, key in ipairs(gearFor(r.id) or {}) do
            keys[#keys + 1] = key
        end
        for _, key in ipairs(ctx.shopping[r.id] or {}) do
            keys[#keys + 1] = key
        end
        judgeGear(keys, r.id, r.minPrice, history)
    elseif kind then
        S.judge(U.key(kind, r.id), r.id, r.minPrice, history)
    end
end

local function readContext()
    local scope = F.Engine.scope()
    return { history = F.Data.market(F.db, scope).history, scope = scope }
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
        and not D.preFlight()
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

-- The player uses the game's own Buy tab (AH.playerUse): a query of the sniper still in flight gives
-- way for good. Kept, it took the player's own browse answer for its own and asked for its next
-- pages, which changed the list the player was reading. Its own answer, should it still come, is
-- read as somebody else's (S.onResults) and a gear search does not take it for its browse.
local function abandon()
    if S.query then
        S.query = nil
        S.nextRound = now() + S.PAUSE
        F.AH.foreignAt = F.Engine.clock()
    end
end

-- AH.hookBrowse: the player sent a search of their own.
function S.onPlayerQuery()
    abandon()
end

-- Why the sniper waits for the player, as the text the status shows, or nil.
local PAUSED = {
    purchase = "Sniper paused: a purchase page is open",
    buy = "Sniper paused: you are using the Buy tab",
    sell = "Sniper paused: you are using the Sell tab",
}
function S.paused()
    if not S.active() or not F.AH.isOpen() then
        return nil
    end
    local why = F.AH.playerUse and F.AH.playerUse()
    return why and PAUSED[why] or nil
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
    local quick = S.quick
    if quick then
        -- Done once the last candidate's check is answered too: the end of a quick scan says
        -- its deals are checked.
        if quick.done and #S.backlog == 0 and #S.candidates == 0 and not F.Deals.search and #F.Deals.requests == 0 then
            endQuick("quick_done")
            return
        elseif t - quick.at > S.QUICK_MAX then
            endQuick("quick_timeout")
            return
        end
    end
    if F.AH.playerUse and F.AH.playerUse() then
        abandon()
        return
    end
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
            -- A quick scan reads every page first and checks its candidates after (D.snipe holds
            -- them): checking each page's before asking for the next made the round crawl.
            and (#S.candidates == 0 or quick and not quick.done)
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
    if not idle() or quick and quick.done then
        return
    end
    if t >= (S.nextRound or 0) then
        send("browse")
        return
    end
    -- Pause between rounds: the watched items, a batch of keys per second (not for a quick scan,
    -- whose one round is its whole work).
    if not quick and t - (S.lastKeys or 0) >= 1 then
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
-- rows: what the event brought (AH.browseAnswer), the whole list when `whole`; without them the
-- whole list is read here.
function S.onResults(first, rows, whole)
    local q = S.query
    if not rows then
        rows, whole = F.AH.browseResults(), true
    end
    local from, total = 1, nil
    if not q then
        if whole then
            if first or #rows < S.outsideRead then
                S.outsideRead = 0
            end
            from, total = S.outsideRead + 1, #rows
        else
            total = S.outsideRead + #rows
        end
        for i = from, #rows do
            S.backlog[#S.backlog + 1] = rows[i]
        end
        S.outsideRead = total
        return
    end
    q.answered = true
    if whole then
        from, total = q.read + 1, #rows
    else
        total = q.read + #rows
    end
    q.read = total
    -- Judge our own large pages under the same per-frame bound as other addons' pages.
    for i = from, #rows do
        S.backlog[#S.backlog + 1] = rows[i]
    end
    if q.kind == "browse" and not F.AH.browseFull() then
        q.more, q.at = true, now()
        return
    end
    if q.kind == "browse" then
        S.rounds = S.rounds + 1
        S.nextRound = now() + S.PAUSE
        if S.quick and S.quick.after == q then
            S.quick.after = nil
            S.nextRound = now() -- the sniper's round ended: the quick scan's own goes next
        elseif S.quick then
            -- Read: its candidates are checked next (S.step ends it), with time of their own.
            S.quick.done, S.quick.at = true, now()
        end
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
    S.quick = nil
    S.query, S.candidates, S.nextRound = nil, {}, nil
    S.backlog, S.backlogAt, S.outsideRead = {}, 1, 0
end
