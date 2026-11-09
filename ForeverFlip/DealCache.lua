local F = ForeverFlip
local D = {}
F.DealCache = D
local function inputs(c)
    return {
        candidates = c.candidates,
        count = #c.candidates,
        revision = c.candidateVersion or 0,
        rules = c.ruleVersion,
        settings = c.db.settings,
        groups = c.db.groups,
        overrides = c.overrides,
        advisor = c.advisorProfile,
        wallet = c.api.wallet(),
        reserved = c:reserved(),
        ledger = c.db.ledger,
        entries = #c.db.ledger,
        sequence = c.db.sequence,
        scope = c.api.scope(),
        owner = c.api.owner(),
        npcBudget = c:npcRemaining(),
    }
end
local function same(a, b, quotesMayAdvance)
    if not a or not b then
        return false
    end
    for k, v in pairs(a) do
        if b[k] ~= v and not (quotesMayAdvance and k == "revision") then
            return false
        end
    end
    for k, v in pairs(b) do
        if a[k] ~= v and not (quotesMayAdvance and k == "revision") then
            return false
        end
    end
    return true
end
local function order(a, b)
    if a.canBuy ~= b.canBuy then
        return a.canBuy
    end
    if (a.score or -math.huge) ~= (b.score or -math.huge) then
        return (a.score or -math.huge) > (b.score or -math.huge)
    end
    return a.identity < b.identity
end
function D.tick(c)
    local cache = c.dealCache
    local j = cache and cache.job
    if not j then
        return false
    end
    if not same(j.inputs, inputs(c), true) then
        cache.job = nil
        cache.inputs = nil
        return true
    end
    c.cachedSummary = j.summary
    c.salesByKey = j.summary.salesByKey
    local start = debugprofilestop and debugprofilestop()
    for _ = 1, 4 do
        local row = j.candidates[j.index]
        if not row then
            break
        end
        local p = c:rankCandidate(row)
        if p then
            j.rows[#j.rows + 1] = p
        end
        j.index = j.index + 1
        if start and debugprofilestop() - start >= 2 then
            break
        end
    end
    c.cachedSummary, c.salesByKey = nil, nil
    if j.index <= j.inputs.count then
        return false
    end
    table.sort(j.rows, order)
    -- Keep the revision actually visited, then coalesce newer quotes into a
    -- follow-up. Newer quotes must not be stamped as already processed.
    cache.inputs = j.inputs
    cache.rows, cache.job, cache.at = j.rows, nil, c.api.clock()
    cache.generation = cache.generation + 1
    return true
end
function D.get(c)
    local state = inputs(c)
    local cache = c.dealCache
    if not cache then
        cache = { rows = {}, generation = 0 }
        c.dealCache = cache
    end
    -- Quote updates must not restart a long market pass every3 seconds. Each
    -- discovery row retains its own timestamp; trading always runs a new search.
    if cache.job and same(cache.inputs, state, true) then
        if #cache.rows > 0 and c.api.clock() - (cache.at or 0) > 30 then
            cache.rows = {}
            cache.generation = cache.generation + 1
        end
        return cache.rows
    end
    if not same(cache.inputs, state) or (not cache.job and c.api.clock() - (cache.at or 0) > 30) then
        local reusable = same(cache.inputs, state, true) and c.api.clock() - (cache.at or 0) <= 30
        cache.inputs = state
        if not reusable then
            cache.rows = {}
        end
        local candidates = {}
        for i, row in ipairs(c.candidates) do
            candidates[i] = row
        end
        cache.job = { inputs = state, candidates = candidates, index = 1, rows = {}, summary = c:summary() }
        cache.generation = cache.generation + 1
        -- Tiny books are cheap and retain immediate feedback; large books never
        -- run their model loop inside OnShow/filter/scroll callbacks.
        if state.count <= 4 then
            D.tick(c)
        end
    end
    return cache.rows
end
function D.poll(c)
    local previous = c.dealCache and c.dealCache.generation or -1
    D.get(c)
    return c.dealCache.generation ~= previous
end
