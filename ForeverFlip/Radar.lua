local F = ForeverFlip
local U = F.Util
local L = F.Locale.text
local R = {}
F.Radar = R
-- SendSearchQuery is not a whole-market scanner. ReplicateItems discovers the
-- market; only a bounded shortlist is rechecked with throttled exact queries.
local LIMIT, INTERVAL, SNAPSHOT = 80, 3, 900
local function better(a, b)
    if a.score == b.score then
        return U.key(a.key) < U.key(b.key)
    end
    return (a.score or 0) > (b.score or 0)
end
local function evaluate(c, key, rows, kind)
    local best
    for _, mode in ipairs({ "vendor", "flip" }) do
        local o = c:options(key, mode, nil, true)
        o.complete = true
        o.commodity = kind == "commodity"
        if not o.commodity then
            o.vendor = c:variantVendor(rows, key) or o.vendor
        end
        local p = F.Market.plan(rows, F.Market.evidence(c:history(key)), o)
        if p.canBuy and (not best or (p.score or 0) > (best.score or 0)) then
            best = p
            best.group = o.group
        end
    end
    if best then
        best.key = U.copy(key)
        best.identity = U.key(key)
        best.kind = kind
        best.link = rows[1] and rows[1].link
        best.source = "radar"
        best.family = false
    end
    return best
end
local function beginBuild(c)
    local r = c.radar
    local now, alerts = c.api.clock(), {}
    for id, v in pairs(r.opportunities) do
        if v.at > now or now - v.at > 30 then
            r.opportunities[id] = nil
        end
    end
    for id, v in pairs(r.alerts) do
        alerts[#alerts + 1] = { id = id, at = v.at }
    end
    table.sort(alerts, function(a, b)
        return a.at > b.at
    end)
    for i = 1921, #alerts do
        r.alerts[alerts[i].id] = nil
    end
    local b = {
        index = 1,
        pending = {},
        cursor = 1,
        queue = {},
        seen = {},
        promising = {},
        candidates = c.candidates,
        summary = c:summary(),
    }
    r.build = b
    -- Watch entries get a rotating share, so a large list cannot starve deals.
    local watch = c.db.watchlist or {}
    for i = 1, math.min(40, #watch) do
        local index = ((r.watchOffset or 0) + i - 1) % #watch + 1
        local value = watch[index]
        local key = type(value) == "string" and U.fromKey(value) or { itemID = value }
        local id = key and U.key(key)
        if id and not b.seen[id] then
            b.queue[#b.queue + 1] = key
            b.seen[id] = true
        end
    end
    r.watchOffset = #watch > 0 and ((r.watchOffset or 0) + 40) % #watch or 0
end
local function buildStep(c)
    local r, now = c.radar, c.api.clock()
    if not r.build then
        beginBuild(c)
    end
    local b = r.build
    c.cachedSummary = b.summary
    -- Four exact variants per frame; family resolution itself is at most64 rows.
    for _ = 1, 4 do
        if b.cursor > #b.pending then
            local v = b.candidates[b.index]
            if not v then
                break
            end
            b.index = b.index + 1
            b.pending, b.cursor = {}, 1
            if v.scope == r.scope and v.at <= now and now - v.at <= 1800 then
                if v.family then
                    local groups = {}
                    for i = 1, math.min(64, #v.rows) do
                        local row = v.rows[i]
                        local key = row.link and F.Adapters.keyFromInput(row.link)
                        local id = key and U.key(key)
                        if id and key.itemID == v.key.itemID then
                            groups[id] = groups[id] or { key = key, rows = {}, kind = "item" }
                            table.insert(groups[id].rows, row)
                        end
                    end
                    for _, id in ipairs(U.sortedKeys(groups)) do
                        b.pending[#b.pending + 1] = groups[id]
                    end
                else
                    b.pending[1] =
                        { key = v.key, rows = v.rows, kind = v.kind or (v.family == false and "commodity" or "item") }
                end
            end
        end
        local v = b.pending[b.cursor]
        b.cursor = b.cursor + 1
        if v then
            local p = evaluate(c, v.key, v.rows, v.kind)
            if p then
                b.promising[#b.promising + 1] = p
                if #b.promising > 160 then
                    table.sort(b.promising, better)
                    for i = #b.promising, LIMIT + 1, -1 do
                        b.promising[i] = nil
                    end
                end
            end
        end
    end
    c.cachedSummary = nil
    if b.index <= #b.candidates or b.cursor <= #b.pending then
        return false
    end
    table.sort(b.promising, better)
    for _, p in ipairs(b.promising) do
        local id = U.key(p.key)
        if not b.seen[id] and #b.queue < LIMIT then
            b.queue[#b.queue + 1] = U.copy(p.key)
            b.seen[id] = true
        end
    end
    r.queue, r.index, r.checked = b.queue, 1, 0
    r.build = nil
    r.cycle = r.cycle + 1
    c.radarDirty = true
    return true
end
function R.pause(c)
    local r = c.radar
    if not r or not r.enabled then
        return
    end
    r.paused = true
    r.current = nil
    if c.job and c.job.origin == "radar" then
        c.plan = nil
    end
    c.radarDirty = true
end
function R.start(c)
    if not c:allowed() or c.active or c.postPending or c.reviewRequest then
        return false
    end
    if c.job and c.job.origin ~= "radar" then
        c:notify("search_busy")
        return false
    end
    local r = c.radar
    if not r or not r.enabled or r.scope ~= c.api.scope() or r.owner ~= c.api.owner() then
        r = {
            enabled = true,
            scope = c.api.scope(),
            owner = c.api.owner(),
            queue = {},
            index = 1,
            checked = 0,
            cycle = 0,
            opportunities = {},
            alerts = {},
            nextAt = 0,
        }
        c.radar = r
    end
    r.paused = false
    if #c.candidates == 0 then
        for id, history in pairs(c.db.markets[r.scope] or {}) do
            local v, key = history.latest, U.fromKey(id)
            if key and v and v.rows and v.at <= c.api.clock() and c.api.clock() - v.at <= 1800 then
                c.candidates[#c.candidates + 1] = {
                    key = key,
                    rows = U.copy(v.rows),
                    at = v.at,
                    scope = r.scope,
                    family = v.family,
                    kind = v.family == false and "commodity" or "item",
                    complete = true,
                }
                if #c.candidates >= 2000 then
                    break
                end
            end
        end
    end
    r.nextAt = c.api.clock()
    r.queue = {}
    c.watching = false
    if c.fullJob then
        c.fullJob.origin = "radar"
    end
    c:notify("live")
    c.radarDirty = true
    return true
end
function R.stop(c)
    R.pause(c)
    if c.radar then
        c.radar.enabled = false
        c.radar.opportunities = {}
        c.radar.build = nil
    end
end
function R.failed(c)
    local r = c.radar
    if r and r.enabled then
        if r.current then
            r.opportunities[U.key(r.current)] = nil
        end
        r.current = nil
        r.nextAt = c.api.clock() + 30
        c.radarDirty = true
    end
end
function R.invalidate(c, key)
    local r = c.radar
    if not r then
        return
    end
    for id, v in pairs(r.opportunities) do
        if (type(key) == "number" and v.key.itemID == key) or (type(key) == "table" and U.key(key) == id) then
            r.opportunities[id] = nil
            c.radarDirty = true
        end
    end
end
function R.results(c, j, rows, complete, kind)
    local r = c.radar
    if j.origin ~= "radar" or not r or not r.enabled then
        return
    end
    r.pageWaiting = false
    if r.paused then
        return
    end
    if not complete then
        return
    end
    local id, now = U.key(j.key), c.api.clock()
    r.current = nil
    r.checked = r.checked + 1
    local p = evaluate(c, j.key, rows, kind)
    r.opportunities[id] = p and { key = U.copy(j.key), rows = U.copy(rows), kind = kind, at = now } or nil
    if p then
        local signature = table.concat({ p.mode, p.cost, p.qty, p.target or 0 }, ":")
        local a = r.alerts[id]
        if not a or (a.signature ~= signature and now - a.at >= 60) then
            r.alerts[id] = { signature = signature, at = now }
            if c.alert then
                c.alert(
                    U.name(j.key.itemID)
                        .. " · "
                        .. (p.mode == "vendor" and "NPC" or L("Resale", "Resale"))
                        .. " · "
                        .. U.money(p.profit)
                )
            end
        end
    end
    r.nextAt = math.max(r.nextAt, c.lastRequest + INTERVAL)
    c.radarDirty = true
end
function R.list(c)
    local r, out = c.radar, {}
    if not r or not r.enabled or r.scope ~= c.api.scope() or r.owner ~= c.api.owner() then
        return out
    end
    c.cachedSummary = c:summary()
    for id, v in pairs(r.opportunities) do
        local age = c.api.clock() - v.at
        if age < 0 or age > 30 then
            r.opportunities[id] = nil
        else
            local p = evaluate(c, v.key, v.rows, v.kind)
            if p then
                p.at = v.at
                out[#out + 1] = p
            end
        end
    end
    c.cachedSummary = nil
    return out
end
function R.tick(c)
    local r, now = c.radar, c.api.clock()
    if not r or not r.enabled or r.paused then
        return
    end
    if c.active or c.postPending then
        R.pause(c)
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    if not c.job and now - (c.db.lastReplicate or 0) >= SNAPSHOT then
        if now < (r.snapshotRetry or 0) or not c.api.ready() then
            return
        end
        r.snapshotRetry = now + 30
        r.nextAt = r.snapshotRetry
        if c:fullScan("radar") then
            r.queue = {}
            r.nextAt = now
        end
        return
    end
    if now < r.nextAt or not c.api.ready() then
        return
    end
    if c.job then
        if
            c.job.origin == "radar"
            and c.plan
            and not c.plan.complete
            and not r.pageWaiting
            and now - c.lastRequest >= INTERVAL
        then
            r.pages = (r.pages or 0) + 1
            if r.pages <= 3 and c:more() then
                r.pageWaiting = true
                c.lastRequest = now
                r.nextAt = now + INTERVAL
            else
                c.job, c.plan = nil, nil
                R.failed(c)
            end
        end
        return
    end
    if now - c.lastRequest < INTERVAL then
        return
    end
    if #r.queue == 0 or r.index > #r.queue then
        if not buildStep(c) then
            return
        end
        if #r.queue == 0 then
            r.nextAt = now + 15
            return
        end
    end
    local key = r.queue[r.index]
    r.index = r.index + 1
    r.pages = 0
    r.pageWaiting = false
    if c:search(key, "radar") then
        r.current = key
        r.nextAt = now + INTERVAL
    else
        R.failed(c)
    end
end
