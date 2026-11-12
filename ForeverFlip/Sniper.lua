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
S.PER_FRAME = 300 -- browse rows of other addons' searches read per frame

-- Browses other addons (or the player) send are read too, but only their new rows, a few hundred
-- per frame: re-reading every row at each page froze the game while another addon browsed the
-- whole house (ForeverForge Auction 2.1.14 fixed the same freeze).
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
    local market = h and F.Market.usual(h)
    if U.finite(market) and market > 0 then
        local exit = U.stepDown(F.Market.salePrice(h) or market, item and item.kind)
        local d = F.Market.saleability(h, exit, F.Engine.clock())
        if d.known and d.perDay >= 0.5 then
            local deposit = F.Market.deposit(F.AH.clientVendorPrice(id), 1)
            local buy = (F.Market.net(exit, 1) - deposit) / (1 + (s.minROI or 0.2))
            limit = math.max(limit or 0, math.floor(buy))
        end
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

-- Lowest prices of browse or key queries: { id, minPrice, qty }.
function S.read(rows)
    local history = F.Data.market(F.db, F.Engine.scope()).history
    for _, r in ipairs(rows) do
        S.items = S.items + 1
        if F.Market.learnLow then
            F.Market.learnLow(history, r, F.Engine.clock())
        end
        local kind = F.AH.kindOf(r.id)
        if kind == "gear" then
            for _, key in ipairs(gearFor(r.id) or {}) do
                S.judge(key, r.id, r.minPrice, history)
            end
        elseif kind then
            S.judge(U.key(kind, r.id), r.id, r.minPrice, history)
        end
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
        and #S.candidates == 0
        and not D.holding()
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

local function readBacklog()
    local stop = math.min(#S.backlog, S.backlogAt + S.PER_FRAME - 1)
    if stop < S.backlogAt then
        return
    end
    local part = {}
    for i = S.backlogAt, stop do
        part[#part + 1] = S.backlog[i]
    end
    S.backlogAt = stop + 1
    if S.backlogAt > #S.backlog then
        S.backlog, S.backlogAt = {}, 1
    end
    S.read(part)
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
        if q.more and F.AH.ready() and #S.candidates == 0 and not F.Deals.holding() and not F.Scan.blocking() then
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
    S.read(fresh)
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

-- The auction house closed or the sniper was switched off.
function S.reset()
    S.query, S.candidates, S.nextRound = nil, {}, nil
    S.backlog, S.backlogAt, S.outsideRead = {}, 1, 0
end
