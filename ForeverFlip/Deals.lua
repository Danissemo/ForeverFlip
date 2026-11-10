-- Found deals and their exact verification. A deal from the full scan is only a lead: before it
-- can be bought, an exact search reads the item's current listings and the deal is evaluated
-- again with them. Searches run one at a time; explicit batches may use the faster server gate.
local F = ForeverFlip
local U = F.Util
local D = {}
F.Deals = D

D.list = {} -- deals of the current scope, best first
D.FRESH = 45 -- seconds a verification stays valid for buying
D.KEEP = 900 -- seconds an unverified scan deal stays listed

local function clock()
    return F.Engine.clock()
end

local function settings()
    return F.db.settings
end

function D.budget()
    local s = settings()
    return math.floor(F.Engine.wallet() * (s.spendShare or 0.8))
end

-- Evaluates a scan group or live listings. `g` has key, kind, id, rows, market, link.
-- One item may hold at most this share of the money (in stock plus the new purchase).
local function itemRoom(key)
    local p = F.Data.char(F.db, F.Engine.owner()).positions[key]
    local share = settings().itemShare or 0.3
    return math.max(0, math.floor(F.Engine.wallet() * share) - (p and p.cost or 0)), p and p.qty or 0
end

-- How far the scan estimate of sales is trusted for an item, from own results: stock bought a
-- day ago and not sold since halves it, three days quarter it.
function D.trust(key, now)
    local c = F.Data.char(F.db, F.Engine.owner())
    local named = c.stats[key] and c.stats[key].name or c.positions[key] and c.positions[key].name
    local rate = named and F.Trade.rate(named)
    local factor = rate and math.max(0.25, math.min(1, rate / 0.5)) or 1
    return factor * D.ownTrust(c, key, now)
end

function D.ownTrust(c, key, now)
    local p = c.positions[key]
    if not p or not p.since or p.qty <= 0 then
        return 1
    end
    local s = c.stats[key]
    if s and s.lastSale and s.lastSale >= p.since then
        return 1
    end
    local held = (now or clock()) - p.since
    if held > 3 * 86400 then
        return 0.25
    elseif held > 86400 then
        return 0.5
    end
    return 1
end

-- The usual asking price, capped by what sales actually reached once enough were seen.
function D.resaleCap(market, history)
    local cap = F.Market.saleCap(history)
    if cap and U.finite(market) then
        return math.min(market, cap)
    end
    return market or cap
end

function D.evaluate(g, vendor, history, now)
    if F.Shopping.blocked(g.key) then
        return nil, "blocked"
    end
    local room, held = itemRoom(g.key)
    local deal, reason = F.Market.evaluate(g.rows, {
        kind = g.kind,
        vendor = vendor,
        held = held,
        itemBudget = room,
        trust = D.trust(g.key, now),
        budget = D.budget(),
        deposit = F.AH.depositFn(g.id, g.kind, vendor, F.Trade.durationFor and F.Trade.durationFor() or 3),
        history = history,
        market = D.resaleCap(g.market, history),
        now = now or clock(),
        settings = settings(),
    })
    if not deal and F.Shopping.entry(g.key) then
        deal = F.Shopping.evaluate(g.rows, g.key, D.budget())
    end
    if g.kind == "gear" and F.Disenchant.active() then
        local de = F.Disenchant.evaluate(g.rows, g.id, D.budget())
        if de and (not deal or de.profit > deal.profit) then
            deal, reason = de, nil
        end
    end
    if deal then
        deal.key, deal.kind, deal.id, deal.link = g.key, g.kind, g.id, g.link
        deal.market, deal.vendor = g.market, vendor
        deal.found = now or clock()
    end
    return deal, reason
end

local function order(a, b)
    if (a.verified ~= nil) ~= (b.verified ~= nil) then
        return a.verified ~= nil
    end
    if a.profit ~= b.profit then
        return a.profit > b.profit
    end
    return a.key < b.key
end

function D.replace(deals, scope)
    D.scope = scope
    -- Keep deals verified a moment ago; the scan may be older than that check.
    local keep = {}
    for _, d in ipairs(D.list) do
        if d.verified and clock() - d.verified < D.FRESH then
            keep[d.key] = d
        end
    end
    D.list = {}
    for _, d in ipairs(deals) do
        D.list[#D.list + 1] = keep[d.key] or d
        keep[d.key] = nil
    end
    for _, d in pairs(keep) do
        D.list[#D.list + 1] = d
    end
    table.sort(D.list, order)
    F.Engine.changed()
end

function D.add(deal, scope)
    if scope ~= D.scope then
        return
    end
    for i, d in ipairs(D.list) do
        if d.key == deal.key then
            D.list[i] = deal
            table.sort(D.list, order)
            F.Engine.changed()
            return
        end
    end
    D.list[#D.list + 1] = deal
    table.sort(D.list, order)
    F.Engine.changed()
end

function D.remove(key)
    for i, d in ipairs(D.list) do
        if d.key == key then
            table.remove(D.list, i)
            F.Engine.changed()
            return
        end
    end
end

function D.get(key)
    for _, d in ipairs(D.list) do
        if d.key == key then
            return d
        end
    end
end

function D.visible(filter)
    local out, now = {}, clock()
    for _, d in ipairs(D.list) do
        -- Deals of the last scan stay listed until the next one; buying checks them first.
        if not filter or filter == "all" or d.mode == filter then
            out[#out + 1] = d
        end
    end
    return out
end

-- Exact search -------------------------------------------------------------------------------------
-- D.search = { key, item, at, pages, source, callbacks }. Foreground work is FIFO;
-- a background retry has its own slot and can never replace a player's request.
D.requests = {}
D.queued = {} -- queued key -> request; batch setup remains linear even for a whole category
D.sent = {} -- successful or attempted new searches during the last rolling minute
function D.searching()
    return D.search ~= nil
end

local function precise()
    return GetTime and GetTime() or clock()
end

local function retryChanged()
    -- Kept for callers that used this to tell whether a recheck is waiting.
    D.retry = D.requests[1] or D.backgroundRetry
end

function D.pending(key)
    if D.search and (key and D.search.key == key or not key and D.search.source == "manual") then
        return true
    end
    if key and D.queued[key] or not key and #D.requests > 0 then
        return true
    end
    for _, queued in ipairs(F.Trade.checkQueue or {}) do
        if not key or queued == key then
            return true
        end
    end
    return false
end

local function addCallback(r, callback, identity)
    if not callback then
        return
    end
    identity = identity or callback
    for _, cb in ipairs(r.callbacks) do
        if cb.identity == identity then
            return
        end
    end
    r.callbacks[#r.callbacks + 1] = { run = callback, identity = identity }
end

local function newRequest(key, callback, source, identity, fast)
    local item = U.parseKey(key)
    if not item then
        return nil
    end
    local r = { key = key, item = item, source = source or "manual", callbacks = {}, readyAt = precise(), fast = fast }
    addCallback(r, callback, identity)
    return r
end

local function completeRequest(r, rows, complete)
    if not r or r.completed then
        return
    end
    r.completed = true
    for _, cb in ipairs(r.callbacks or {}) do
        local ok, err = pcall(cb.run, r.key, rows, complete)
        if not ok then
            F.Engine.report(err)
        end
    end
end

local function startRequest(r)
    local now = precise()
    while D.sent[1] and now - D.sent[1] >= 60 do
        table.remove(D.sent, 1)
    end
    if
        D.clearing
        or D.search
        or not F.AH.isOpen()
        or F.Trade.busy()
        or F.Scan.busy()
        or not F.AH.ready()
        or now - (D.lastRequest or -10) < (r.fast and 0.4 or 1)
        or #D.sent >= 100
    then
        return false
    end
    -- Cached answers and dropped-message events may fire inside the API call.
    r.at, r.pages = clock(), 0
    D.search, D.lastRequest = r, now
    D.sent[#D.sent + 1] = now
    r.attempts = (r.attempts or 0) + 1
    local ok = pcall(F.AH.search, r.item)
    if not ok and D.search == r then
        D.search = nil
        if r.fast then
            completeRequest(r, nil, false)
            F.Engine.changed()
            return true
        end
        return false
    end
    F.Engine.changed()
    return true
end

-- Immediate API, retained for background work and callers that need a started/not-started answer.
function D.request(key, callback, source, fast)
    if D.pending() then
        return false
    end
    local r = newRequest(key, callback, source, nil, fast)
    return r and startRequest(r) or false
end

-- Manual requests are accepted even while throttled or another search is in flight. A repeated
-- key shares that query; each distinct callback is retained and completed once.
function D.enqueue(key, callback, identity, fast)
    if D.clearing or not F.AH.isOpen() then
        return false
    end
    local r, promoted
    if D.search and D.search.key == key then
        r = D.search
    else
        r = D.queued[key]
    end
    local background = D.backgroundRetry
    if background and background.key == key then
        D.backgroundRetry = nil
        if r then
            for _, cb in ipairs(background.callbacks) do
                addCallback(r, cb.run, cb.identity)
            end
        else
            r, promoted = background, true
        end
    end
    if r then
        r.source = "manual"
        r.fast = r.fast or fast
        addCallback(r, callback, identity)
        if not promoted then
            retryChanged()
            F.Engine.changed()
            return true
        end
    else
        r = newRequest(key, callback, "manual", identity, fast)
        if not r then
            return false
        end
    end
    D.requests[#D.requests + 1] = r
    D.queued[key] = r
    if #D.requests == 1 and precise() >= r.readyAt then
        table.remove(D.requests, 1)
        D.queued[key] = nil
        if not startRequest(r) then
            table.insert(D.requests, 1, r)
            D.queued[key] = r
        end
    end
    retryChanged()
    F.Engine.changed()
    return true
end

local function finishSearch(rows, complete)
    local s = D.search
    D.search = nil
    completeRequest(s, rows, complete)
    F.Engine.changed()
end

-- Search results arrived (commodity: itemID; item or gear: item key table).
function D.onResults(itemID, searchKey)
    local s = D.search
    if not s or s.item.id ~= itemID then
        D.learn(itemID, searchKey)
        return
    end
    local ok, rows, complete = pcall(F.AH.rows, s.item)
    if not ok then
        finishSearch(nil, false)
        return
    end
    -- Enough when complete, or when the cheapest page already reaches past every deal price.
    local d = D.get(s.key)
    local last = rows[#rows]
    local enough = complete or (d and last and last.unit > (d.exit or 0) * 1.2)
    if not enough and s.pages < 3 and F.AH.ready() then
        s.pages, s.at = s.pages + 1, clock()
        pcall(F.AH.more, s.item)
        return
    end
    finishSearch(rows, complete or enough)
end

-- The player searched an item in the game's own Buy tab: its listings are a fresh check of the item,
-- so a deal found in them can be bought at once, and a listed deal that is gone disappears.
function D.learn(itemID, searchKey)
    if not F.db or not F.db.settings.learnBrowsing or not D.scope or type(itemID) ~= "number" then
        return
    end
    local kind = F.AH.kindOf(itemID)
    if not kind then
        return
    end
    local keys = {}
    if kind == "gear" then
        for key in pairs(F.Data.market(F.db, D.scope).history) do
            local item = U.parseKey(key)
            if item and item.id == itemID and item.kind == "gear" then
                keys[#keys + 1] = key
            end
        end
    else
        keys[1] = U.key(kind, itemID)
    end
    for _, key in ipairs(keys) do
        local ok, rows, complete = pcall(F.AH.rows, U.parseKey(key), searchKey)
        if ok and rows and #rows > 0 then
            D.verifyCallback(key, rows, complete or #rows >= 40)
        end
    end
end

function D.onDropped()
    local s = D.search
    if s then
        D.search = nil
        s.readyAt = precise() + 2
        if s.fast and (s.attempts or 0) >= 3 then
            completeRequest(s, nil, false)
        elseif s.source == "manual" then
            table.insert(D.requests, 1, s)
            D.queued[s.key] = s
        elseif s.source ~= "sniper" or settings().sniper then
            D.backgroundRetry = s
        else
            completeRequest(s, nil, false)
        end
        retryChanged()
        F.Engine.changed()
    end
end

function D.setSniper(enabled)
    settings().sniper = enabled and true or false
    if not enabled then
        F.Sniper.reset()
    end
    local r = D.backgroundRetry
    if not enabled and r and r.source == "sniper" then
        D.backgroundRetry = nil
        completeRequest(r, nil, false)
        retryChanged()
    end
    F.Engine.changed()
end

-- Closing the house cancels queued work too, so reopening cannot replay old selections.
function D.clear()
    D.clearing = true
    local active, requests, background = D.search, D.requests, D.backgroundRetry
    D.search, D.requests, D.queued, D.backgroundRetry, D.retry = nil, {}, {}, nil, nil
    completeRequest(active, nil, false)
    for _, r in ipairs(requests) do
        completeRequest(r, nil, false)
    end
    completeRequest(background, nil, false)
    D.batch = nil
    D.clearing = nil
    F.Engine.changed()
end

-- A click captures the complete current category before sending anything. Each accepted key has
-- one completion callback, including a vanished deal, a timeout, and a cancelled request.
function D.startBatch(scope, keys, verifyDeals)
    if D.clearing or not F.AH.isOpen() or D.batch and D.batch.active then
        return false
    end
    local snapshot, seen = {}, {}
    for _, key in ipairs(keys or {}) do
        if not seen[key] and U.parseKey(key) then
            seen[key] = true
            snapshot[#snapshot + 1] = key
        end
    end
    local batch = { scope = scope, keys = snapshot, total = #snapshot, done = 0, failed = 0, active = #snapshot > 0 }
    D.batch = batch
    for _, key in ipairs(snapshot) do
        if D.batch ~= batch then
            break -- a synchronous close can cancel the whole batch while sending its first key
        end
        local finished = false
        local function complete(_, rows, completeRows)
            if finished then
                return
            end
            finished = true
            local success = rows ~= nil and completeRows
            if verifyDeals then
                local ok, err = pcall(D.verifyCallback, key, rows, completeRows)
                if not ok then
                    F.Engine.report(err)
                    success = false
                end
            end
            batch.done = batch.done + 1
            batch.failed = batch.failed + (success and 0 or 1)
            batch.active = batch.done < batch.total
            F.Engine.changed()
        end
        local accepted
        if verifyDeals then
            accepted = D.enqueue(key, complete, complete, true)
        else
            accepted = F.Trade.checkPrice(key, complete, true)
        end
        if not accepted then
            complete(key, nil, false)
        end
    end
    F.Engine.changed()
    return #snapshot
end

function D.batchProgress(scope)
    local batch = D.batch
    if not batch or scope and batch.scope ~= scope then
        return 0, 0, false, 0
    end
    return batch.done, batch.total, batch.active, batch.failed
end

-- A manual verification is queued; automatic deal checks only attempt an idle slot.
function D.verify(key, callback, source)
    local done = function(k, rows, complete)
        D.verifyCallback(k, rows, complete, callback)
    end
    if source == "auto" then
        -- Found deals are checked at the faster pace; the sniper keeps one search per second.
        return D.request(key, done, source, true)
    end
    return D.enqueue(key, done, callback or D.verifyCallback)
end

function D.verifyCallback(k, rows, complete, callback)
    local d = D.get(k)
    if rows and complete then
        local item = U.parseKey(k)
        local history = F.Data.market(F.db, F.Engine.scope()).history[k]
        local g = {
            key = k,
            kind = item.kind,
            id = item.id,
            rows = rows,
            market = d and d.market or (history and history.scan and history.scan.market),
            link = d and d.link or (rows[1] and rows[1].link),
        }
        local live, reason = D.evaluate(g, F.AH.vendorPrice(item.id), history, clock())
        if live then
            live.verified = clock()
            live.rows = rows
            D.add(live, D.scope)
            D.alert(live)
        else
            D.remove(k)
        end
        if callback then
            callback(live, reason)
        end
    elseif callback then
        callback(nil, "search_failed")
    end
end

-- Called every frame: timeouts, retries, and automatic verification of the best unverified deals.
function D.step()
    local now = clock()
    local s = D.search
    if s and now - s.at > 10 then
        finishSearch(nil, false)
    end
    if D.search or F.Trade.busy() or F.Scan.busy() or not F.AH.isOpen() then
        return
    end
    local r = D.requests[1]
    if r then
        if precise() >= r.readyAt then
            table.remove(D.requests, 1)
            D.queued[r.key] = nil
            if not startRequest(r) then
                table.insert(D.requests, 1, r)
                D.queued[r.key] = r
            end
            retryChanged()
        end
        return
    end
    -- Owned-auction checks enter this same FIFO before any new background work.
    if F.Trade.checkQueue and #F.Trade.checkQueue > 0 then
        return
    end
    -- Leave the player time to click Buy on the selected, freshly checked deal.
    local ui = F.UI
    local selected = ui and ui.section == "deals" and ui.frame:IsShown() and D.get(ui.selected)
    if selected and selected.verified and now - selected.verified <= D.FRESH then
        return
    end
    r = D.backgroundRetry
    if r then
        if r.source == "sniper" and not settings().sniper or r.source == "auto" and not F.Engine.autoVerify then
            D.backgroundRetry = nil
            completeRequest(r, nil, false)
            retryChanged()
        elseif precise() >= r.readyAt then
            D.backgroundRetry = nil
            if not startRequest(r) then
                D.backgroundRetry = r
            end
            retryChanged()
            return
        else
            return
        end
    end
    if F.Engine.autoVerify then
        for _, d in ipairs(D.list) do
            if (not d.verified or now - d.verified > 300) and now - (d.tried or 0) > 120 then
                if D.verify(d.key, nil, "auto") then
                    d.tried = now
                end
                return
            end
        end
    end
    D.snipe()
end

-- Sniper: between full scans, the items most often near a deal are read again one by one (one
-- search per second), so a cheap lot is seen seconds after it is listed, not up to 15 minutes later.
function D.snipe()
    local hot = F.Scan.hot
    if not F.db.settings.sniper or not D.scope then
        return false
    end
    if F.Sniper.active() then
        -- Fast sniper: exact checks of the candidates its browse rounds found.
        if precise() - (D.lastRequest or -10) < 0.4 or not F.AH.ready() then
            return false
        end
        local key = F.Sniper.next()
        if key and D.request(key, D.verifyCallback, "sniper", true) then
            D.snipes = (D.snipes or 0) + 1
            return true
        end
        return false
    end
    if not hot or #hot == 0 then
        return false
    end
    if precise() - (D.lastRequest or -10) < 1 or not F.AH.ready() then
        return false
    end
    D.snipeIndex = (D.snipeIndex or 0) % #hot + 1
    local key = hot[D.snipeIndex]
    local d = D.get(key)
    if d and d.verified and clock() - d.verified < 60 then
        return false
    end
    if D.request(key, D.verifyCallback, "sniper") then
        D.snipes = (D.snipes or 0) + 1
        return true
    end
    return false
end

-- Sound, screen and chat notice for a deal that can be bought now. Once per item, again only
-- after 10 minutes or when the profit grew by a fifth.
D.alerted = {}
function D.alert(d)
    local s = settings()
    if not s.alerts or d.profit < (s.alertMinProfit or 0) then
        return false
    end
    local last = D.alerted[d.key]
    if last and clock() - last.at < 600 and d.profit <= last.profit * 1.2 then
        return false
    end
    D.alerted[d.key] = { at = clock(), profit = d.profit }
    local L = F.Locale.text
    local name = d.link or d.key
    local msg = string.format(
        L("ForeverFlip: deal %s · profit %s (%s)"),
        name,
        U.money(d.profit),
        L(d.mode == "vendor" and "vendor" or "resale")
    )
    if PlaySound then
        pcall(PlaySound, SOUNDKIT and SOUNDKIT.AUCTION_WINDOW_OPEN or 5274)
    end
    if FlashClientIcon then
        pcall(FlashClientIcon)
    end
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(msg, 1, 0.82, 0)
    end
    print(msg)
    F.Engine.alerts = (F.Engine.alerts or 0) + 1
    return true
end

function D.progress()
    local total, done = 0, 0
    for _, d in ipairs(D.list) do
        total = total + 1
        if d.verified then
            done = done + 1
        end
    end
    return done, total
end
