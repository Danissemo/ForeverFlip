local F = ForeverFlip
local U = F.Util
local C = {}
-- Minimum seconds between auction queries; the server throttle gate (api.ready) still applies.
C.REQUEST_GAP = 1
F.Controller = C
C.__index = C
function C.new(db, api)
    local self = setmetatable({
        db = db,
        api = api,
        mode = "flip",
        candidates = {},
        message = "ready",
        serial = 0,
        lastRequest = 0,
        bidRows = {},
        mail = {},
        ruleVersion = 0,
    }, C)
    if F.Store.writable(db) then
        for _, op in pairs(db.pending) do
            if op.status ~= "done" then
                if op.status == "awaiting" or op.status == "bid" then
                    op.status = "unknown"
                elseif op.status == "quote" or op.status == "quoted" then
                    op.status = "cancelled"
                end
            end
        end
    end
    return self
end
function C:notify(msg)
    if msg then
        self.message = msg
    end
    if self.changed then
        self.changed()
    end
end
function C:allowed()
    if not F.Store.writable(self.db) then
        self:notify("readonly")
        return false
    end
    if not self.api.isOpen() then
        self:notify("auction_closed")
        return false
    end
    local scope, owner = self.api.scope(), self.api.owner()
    if
        type(scope) ~= "string"
        or scope == ""
        or scope:find("?", 1, true)
        or type(owner) ~= "string"
        or owner == ""
        or owner:find(":nil", 1, true)
    then
        self:notify("scope_unknown")
        return false
    end
    return true
end
function C:reserved()
    if not F.Store.writable(self.db) then
        return 0
    end
    local n = 0
    for _, op in pairs(self.db.pending or {}) do
        if
            op.owner == self.api.owner()
            and (
                op.status == "quote"
                or op.status == "quoted"
                or op.status == "awaiting"
                or op.status == "unknown"
                or op.status == "bid"
            )
        then
            n = n + (op.total or 0)
        end
    end
    return n
end
function C:summary()
    if not F.Store.writable(self.db) then
        return F.Ledger.summary({})
    end
    if self.cachedSummary then
        return self.cachedSummary
    end
    local entries, owner, scope = self.db.ledger, self.api.owner(), self.api.scope()
    local m = self.summaryMemo
    if
        not m
        or m.entries ~= entries
        or m.count ~= #entries
        or m.sequence ~= self.db.sequence
        or m.owner ~= owner
        or m.scope ~= scope
    then
        local value = F.Ledger.summary(entries, owner, scope)
        value.positionByKey, value.salesByKey = {}, {}
        for _, p in ipairs(value.positions) do
            value.positionByKey[p.key] = p
        end
        for _, s in ipairs(value.salesHistory) do
            value.salesByKey[s.key] = value.salesByKey[s.key] or {}
            table.insert(value.salesByKey[s.key], s)
        end
        m = {
            entries = entries,
            count = #entries,
            sequence = self.db.sequence,
            owner = owner,
            scope = scope,
            value = value,
        }
        self.summaryMemo = m
    end
    return m.value
end
function C:rule(value)
    if not F.Store.writable(self.db) then
        return U.copy(F.Store.defaults)
    end
    local key = type(value) == "table" and value or { itemID = value }
    local id = key.itemID
    local out = U.copy(self.db.settings or F.Store.defaults)
    for _, g in ipairs(self.db.groups or {}) do
        if (g.items and g.items[id]) or (g.keys and g.keys[U.key(key)]) then
            for k, v in pairs(g.rule or {}) do
                out[k] = v
            end
            out.group = g.name
            out.groupDefinition = g
            break
        end
    end
    -- An explicit group minimum is the player's own choice and is kept as is.
    local groupMinimum = out.groupDefinition and out.groupDefinition.rule and out.groupDefinition.rule.minProfit
    out.adaptiveProfit = out.adaptiveProfit ~= false and not groupMinimum
    return out
end
function C:options(key, mode, ownOp, ignoreOverrides)
    if not F.Store.writable(self.db) then
        return U.copy(F.Store.defaults)
    end
    local o = self:rule(key)
    local summary = self:summary()
    local identity = U.key(key)
    if o.groupDefinition and o.budget then
        local exposure = 0
        local g = o.groupDefinition
        local function matches(k)
            local data = U.fromKey(k)
            return (g.keys and g.keys[k]) or (data and g.items and g.items[data.itemID])
        end
        for _, p in ipairs(summary.positions) do
            if matches(p.key) then
                exposure = exposure + p.cost
            end
        end
        for _, op in pairs(self.db.pending or {}) do
            if
                op.owner == self.api.owner()
                and op.scope == self.api.scope()
                and matches(op.key)
                and (
                    op.status == "awaiting"
                    or op.status == "unknown"
                    or op.status == "bid"
                    or op.status == "quote"
                    or op.status == "quoted"
                )
            then
                exposure = exposure + op.total
            end
        end
        o.groupExposure = exposure
        o.groupBudget = o.budget
        o.budget = math.max(0, o.budget - exposure)
    end
    o.stock = summary.stock
    o.exposure = 0
    o.ownedQty = 0
    local position = summary.positionByKey and summary.positionByKey[identity]
    if position then
        o.exposure, o.ownedQty = position.cost, position.qty
    end
    o.velocity = F.Market.velocity(
        (self.salesByKey or summary.salesByKey) and ((self.salesByKey or summary.salesByKey)[identity] or {})
            or summary.salesHistory,
        identity,
        self.api.clock()
    )
    o.avgBuy = o.ownedQty > 0 and o.exposure / o.ownedQty or nil
    if (key.itemLevel or 0) == 0 and (key.itemSuffix or 0) == 0 and (key.battlePetSpeciesID or 0) == 0 then
        for _, source in ipairs(F.Adapters.prices(key.itemID)) do
            if source.age and source.age >= 0 and source.age <= 86400 then
                if source.source == "auxForever" then
                    o.aux = source.price
                elseif source.source == "TSM" then
                    o.tsm = source.price
                end
            end
        end
    end
    o.legacyUnresolved = false
    if o.safe ~= false and not self.db.legacyAssigned then
        for _, e in ipairs(self.db.legacyLedger or {}) do
            if e.id == key.itemID then
                o.legacyUnresolved = true
                break
            end
        end
    end
    o.wallet = self.api.wallet()
    o.reserved = self:reserved()
    o.now = self.api.clock()
    o.mode = mode or self.mode
    o.vendor = self.api.vendor and self.api.vendor(key.itemID)
    if self.advisorProfile and o.mode == "flip" then
        local activity = summary.activity and summary.activity[identity]
        local held = o.ownedQty
        for _, op in pairs(self.db.pending or {}) do
            if
                op ~= ownOp
                and op.owner == self.api.owner()
                and op.scope == self.api.scope()
                and op.key == identity
                and (
                    op.status == "quote"
                    or op.status == "quoted"
                    or op.status == "awaiting"
                    or op.status == "unknown"
                    or op.status == "bid"
                )
            then
                held = held + math.ceil(U.number(op.qty, 1, 1, 100000))
            end
        end
        o.advice = F.Advisor.parameters(
            F.Market.evidence(self:history(key)),
            (self.salesByKey or summary.salesByKey) and ((self.salesByKey or summary.salesByKey)[identity] or {})
                or summary.salesHistory,
            activity and activity.since,
            o.now,
            self.advisorProfile,
            o.wallet,
            held,
            identity
        )
        o.velocity = { known = o.advice.rateKnown, lower = o.advice.trades.rateLower }
        o.minROI = math.max(o.minROI or 0, o.advice.minROI)
        o.budget = math.min(o.budget or math.huge, o.advice.maxBudget)
    end
    -- Vendor value is per item ID; only random suffixes and pets need the exact per-listing value.
    if (key.itemSuffix or 0) ~= 0 or (key.battlePetSpeciesID or 0) ~= 0 then
        o.vendor = nil
    end
    local npcBudget = self:npcRemaining(ownOp)
    if npcBudget then
        o.budget = math.min(o.budget or math.huge, npcBudget)
        o.absoluteCap = math.min(o.absoluteCap or math.huge, npcBudget)
        if o.mode == "vendor" then
            o.minProfit = 1
            o.minROI = 0.05
        end
    end
    if o.mode == "material" then
        local request = self.materialRequest
        if
            request
            and request.owner == self.api.owner()
            and request.scope == self.api.scope()
            and request.itemID == key.itemID
        then
            local used, spent = 0, 0
            local effective, indexes = F.Ledger.effective(self.db.ledger, request.owner, request.scope)
            for _, entry in ipairs(effective) do
                local item = U.fromKey(entry.key)
                if
                    indexes[entry] > request.first
                    and entry.kind == "buy"
                    and entry.owner == request.owner
                    and entry.scope == request.scope
                    and item
                    and item.itemID == request.itemID
                then
                    used, spent = used + entry.qty, spent + entry.total
                end
            end
            for _, op in pairs(self.db.pending) do
                if
                    op ~= ownOp
                    and op.owner == request.owner
                    and op.scope == request.scope
                    and op.id == request.itemID
                    and (
                        op.status == "quote"
                        or op.status == "quoted"
                        or op.status == "awaiting"
                        or op.status == "unknown"
                        or op.status == "bid"
                    )
                then
                    used, spent = used + op.qty, spent + op.total
                end
            end
            o.materialPrice = request.price
            o.materialQty = math.max(0, request.qty - used)
            o.materialBudget = math.max(0, request.cost - spent)
            o.budget = math.min(o.budget or math.huge, o.materialBudget)
        end
    end
    for k, v in pairs(not ignoreOverrides and self.overrides or {}) do
        if k == "budget" or k == "maxQty" then
            o[k] = math.min(o[k] or math.huge, v)
        else
            o[k] = v
        end
    end
    return o
end
function C:variantVendor(rows, key)
    local vendor
    if #rows == 0 then
        return nil
    end
    for _, r in ipairs(rows) do
        if not r.link then
            return nil
        end
        local p = self.api.vendor and self.api.vendor(r.link)
        if not U.finite(p) or p <= 0 then
            return nil
        end
        vendor = math.min(vendor or p, p)
    end
    return vendor
end
function C:history(key)
    if not F.Store.writable(self.db) then
        return nil
    end
    local h = self.db.markets and self.db.markets[self.api.scope()]
    return h and h[U.key(key)]
end
function C:npcRemaining(ownOp)
    local run = self.smallNPCActive and self.db.ui.npcTrials and self.db.ui.npcTrials[self.api.owner()]
    if not run or run.owner ~= self.api.owner() then
        return nil
    end
    -- Vendor resale has a known exit price, so the limit is a rolling 24-hour spend that grows with
    -- the wallet: at least 1g, otherwise a share of current money (default 25%).
    local now = self.api.clock()
    local share = U.number(self.db.settings and self.db.settings.npcDailyShare, 0.25, 0, 1)
    local limit = math.max(10000, math.floor(U.number(self.api.wallet(), 0, 0) * share))
    local spent = 0
    local effective, indexes = F.Ledger.effective(self.db.ledger, run.owner)
    for _, e in ipairs(effective) do
        if indexes[e] > run.first and e.owner == run.owner and e.kind == "buy" and (e.at or now) > now - 86400 then
            spent = spent + e.total
        end
    end
    for _, op in pairs(self.db.pending) do
        if
            op ~= ownOp
            and op.owner == run.owner
            and (
                op.status == "quote"
                or op.status == "quoted"
                or op.status == "awaiting"
                or op.status == "unknown"
                or op.status == "bid"
            )
        then
            spent = spent + op.total
        end
    end
    return math.max(0, limit - spent)
end
-- A full scan builds price history, which resale deals need. Start one automatically when the
-- 15-minute server cooldown has passed, the window is open and nothing else is running.
function C:autoScanDue()
    local settings = self.db.settings or {}
    return settings.autoScan ~= false
        and self:allowed()
        and not self.job
        and not self.fullJob
        and not self.active
        and not self.reviewRequest
        and not (self.radar and self.radar.enabled and not self.radar.paused)
        and self.api.ready()
        and self.api.clock() - (self.db.lastReplicate or 0) >= 905
end
function C:easyNPC()
    if not self:allowed() or self.active then
        return false
    end
    self.db.ui.npcTrials = self.db.ui.npcTrials or {}
    local run = self.db.ui.npcTrials[self.api.owner()]
    if not run then
        self.db.ui.npcTrials[self.api.owner()] = { first = #self.db.ledger, owner = self.api.owner() }
    end
    self.smallNPCActive = true
    self.mode = "vendor"
    self.overrides = nil
    self:invalidate()
    return self:radarStart()
end
function C:openDeal(p)
    if not self:allowed() or not p or not U.key(p.key) then
        return false
    end
    if
        self.active
        and (self.active.status == "awaiting" or self.active.status == "unknown" or self.active.status == "bid")
    then
        self:notify("resolve_pending")
        return false
    end
    self:stop("manual")
    self.mode = p.mode or self.mode
    if self.mode ~= "material" then
        self.materialRequest = nil
    end
    self.selection = {
        key = U.copy(p.key),
        link = p.link or (p.rows and p.rows[1] and p.rows[1].link),
        family = p.family,
        mode = self.mode,
        totalQty = p.totalQty,
        minimum = p.minimum,
    }
    local key = p.key
    if p.family then
        key = self.selection.link and F.Adapters.keyFromInput(self.selection.link)
        if not key then
            F.Adapters.requestData(p.key.itemID)
            self.selectionRequest = {
                at = self.api.clock(),
                scope = self.api.scope(),
                owner = self.api.owner(),
                input = self.selection.link or tostring(p.key.itemID),
            }
            self:notify("item_loading")
            return true
        end
    end
    self.selection.key = U.copy(key)
    if
        not self.api.ready()
        or self.api.clock() - self.lastRequest < C.REQUEST_GAP
        or (self.api.keyReady and not self.api.keyReady(key))
    then
        self.reviewRequest =
            { key = U.copy(key), at = self.api.clock(), scope = self.api.scope(), owner = self.api.owner() }
        self:notify("review_wait")
        return true
    end
    return self:search(key)
end
function C:searchInput(value)
    local id = tonumber(value)
    if id then
        local best
        for _, row in ipairs(self.candidates) do
            if
                row.scope == self.api.scope()
                and row.key.itemID == id
                and row.rows[1]
                and (not best or row.rows[1].unit < best.rows[1].unit)
            then
                best = row
            end
        end
        if best then
            return self:openDeal({ key = best.key, family = best.family, rows = best.rows, mode = self.mode })
        end
    end
    local key, err = F.Adapters.keyFromInput(value)
    local linkedID = tostring(value):match("item:(%d+)")
    if not key and linkedID then
        return self:openDeal({ key = { itemID = tonumber(linkedID) }, family = true, mode = self.mode, link = value })
    end
    if not key and id then
        return self:openDeal({ key = { itemID = id }, family = true, mode = self.mode })
    end
    if not key then
        self:notify(err)
        return false
    end
    return self:openDeal({ key = key, mode = self.mode, link = tostring(value):find("item:", 1, true) and value or nil })
end
function C:radarStart()
    return F.Radar.start(self)
end
-- Requests the player's own listings; the answer arrives as OWNED_AUCTIONS_UPDATED.
function C:refreshOwned()
    if not self:allowed() or not self.api.queryOwned or not self.api.ready() then
        self:notify("throttled")
        return false
    end
    local ok = pcall(self.api.queryOwned)
    return ok
end
-- Compares one own listing with the latest known competitor prices for the same item.
-- Returns "sold", "cheapest", "undercut" (with the competitor's unit price) or "unknown".
function C:ownedStatus(a)
    if a.sold then
        return "sold"
    end
    local unit = a.qty > 0 and (a.buyout or 0) / a.qty or 0
    if unit <= 0 then
        return "unknown"
    end
    local id = U.key(a.key)
    local rows
    for _, candidate in ipairs(self.candidates or {}) do
        if U.key(candidate.key) == id then
            rows = candidate.rows
        end
    end
    if not rows then
        local h = self:history(a.key)
        rows = h and h.latest and h.latest.rows
    end
    if not rows then
        return "unknown"
    end
    local cheapest
    for _, r in ipairs(rows) do
        if r.auctionID ~= a.auctionID and U.finite(r.unit) and r.unit > 0 and r.unit < unit then
            cheapest = math.min(cheapest or r.unit, r.unit)
        end
    end
    if cheapest then
        return "undercut", cheapest
    end
    return "cheapest"
end
-- After /reload or reopening the auction house the in-memory scan is gone. Rebuild the candidate
-- list from saved scans up to 2 hours old so live search covers the whole market immediately;
-- every deal is still re-checked with an exact search before buying.
function C:restoreCandidates()
    if not F.Store.writable(self.db) then
        return 0
    end
    local scope = self.api.scope()
    if not self.restoreJob or self.restoreJob.scope ~= scope then
        self.restoreJob = { scope = scope, histories = self.db.markets and self.db.markets[scope] or {} }
    end
    return 0
end
function C:advanceRestoreCandidates(limit)
    local job = self.restoreJob
    if not job then
        return 0
    end
    if job.scope ~= self.api.scope() then
        self.restoreJob = nil
        return 0
    end
    local added, now, present = 0, self.api.clock(), {}
    for _, row in ipairs(self.candidates) do
        present[U.key(row.key)] = true
    end
    for _ = 1, limit or 25 do
        local ok, id, history = pcall(next, job.histories, job.cursor)
        if not ok then
            self.restoreJob = nil
            break
        end
        if not id or #self.candidates >= 2000 then
            self.restoreJob = nil
            break
        end
        job.cursor = id
        local v, key = history.latest, U.fromKey(id)
        if key and v and v.rows and not present[id] and v.at <= now and now - v.at <= 7200 then
            self.candidates[#self.candidates + 1] = {
                key = key,
                rows = U.copy(v.rows),
                at = v.at,
                scope = job.scope,
                family = v.family,
                kind = v.family == false and "commodity" or "item",
                complete = true,
            }
            present[id], added = true, added + 1
        end
    end
    if added > 0 then
        self.candidateVersion = (self.candidateVersion or 0) + 1
    end
    return added
end
-- Live search for every kind of deal: leaves the vendor-only route and rebuilds the shortlist.
function C:radarAll()
    if self.smallNPCActive then
        self.smallNPCActive = false
        self.mode = "flip"
        self:invalidate()
    end
    if self.radar then
        self.radar.queue, self.radar.index, self.radar.build = {}, 1, nil
    end
    return self:radarStart()
end
function C:radarPause(byUser)
    F.Radar.pause(self)
    if byUser and self.radar then
        self.radar.userPaused = true
    end
end
-- Live search pauses itself for an exact check or a purchase. Resume it once that is over, unless
-- the player pressed Pause or is looking at a deal on the Trading tab.
function C:radarShouldResume(section)
    local r = self.radar
    return r
            and r.enabled
            and r.paused
            and not r.userPaused
            and section ~= "trade"
            and not self.job
            and not self.fullJob
            and not self.active
            and not self.reviewRequest
            and not self.postPending
            and self:allowed()
        or false
end
function C:search(key, origin)
    if origin ~= "radar" then
        self:radarPause()
    end
    if not self:allowed() or not U.key(key) then
        return false
    end
    if self.api.keyReady and not self.api.keyReady(key) then
        self:notify("item_loading")
        return false
    end
    if
        self.active
        and (self.active.status == "awaiting" or self.active.status == "unknown" or self.active.status == "bid")
    then
        self:notify("resolve_pending")
        return false
    end
    if self.active then
        self:cancelQuote()
    end
    if
        origin ~= "radar"
        and self.radar
        and self.radar.enabled
        and self.radar.paused
        and (
            (self.job and self.job.origin == "radar")
            or (self.fullJob and self.fullJob.origin == "radar")
            or self.api.clock() - self.lastRequest < C.REQUEST_GAP
        )
    then
        self.reviewRequest =
            { key = U.copy(key), scope = self.api.scope(), owner = self.api.owner(), at = self.api.clock() }
        self.plan = nil
        self:notify("review_wait")
        return true
    end
    -- Processing a received scan is local work; only the server request itself blocks searching.
    if self.job or (self.fullJob and self.fullJob.waiting) then
        self:notify("search_busy")
        return false
    end
    if not self.api.ready() or self.api.clock() - self.lastRequest < C.REQUEST_GAP then
        self:notify("throttled")
        return false
    end
    self.serial = self.serial + 1
    self.key = U.copy(key)
    self.plan = nil
    self.job = {
        key = U.copy(key),
        scope = self.api.scope(),
        at = self.api.clock(),
        token = self.serial,
        tries = 0,
        origin = origin,
    }
    local ok, err = pcall(self.api.search, key)
    if not ok then
        self.job = nil
        self:notify("search_error: " .. tostring(err))
        return false
    end
    self.lastRequest = self.api.clock()
    self:notify("searching")
    return true
end
function C:results(kind, key)
    local j = self.job
    if not j or j.scope ~= self.api.scope() or U.key(key) ~= U.key(j.key) then
        return
    end
    local ok, rows, complete, resultKind, bids = pcall(self.api.rows, key, kind)
    if not ok then
        self:notify("results_error")
        return
    end
    local o = self:options(key)
    o.complete = complete
    o.commodity = (resultKind or kind) == "commodity"
    if not o.commodity then
        o.vendor = self:variantVendor(rows, key) or o.vendor
    end
    local h = self:history(key)
    self.plan = F.Market.plan(rows, F.Market.evidence(h), o)
    self.plan.key = U.copy(key)
    self.plan.kind = resultKind or kind
    self.plan.at = self.api.clock()
    self.plan.scope = j.scope
    self.plan.ruleVersion = self.ruleVersion
    self.plan.token = j.token
    self.plan.origin = j.origin
    self.bidRows = bids or {}
    self.planMode = self.mode
    if complete then
        self.job = nil
        self.candidateVersion = (self.candidateVersion or 0) + 1
        if self.plan.minimum then
            local snap = F.Market.snapshot(rows)
            F.Store.observe(self.db, j.scope, U.key(key), {
                at = self.api.clock(),
                price = snap.price,
                qty = self.plan.totalQty,
                complete = true,
                token = tostring(j.token) .. ":" .. self.api.clock(),
                source = "exact",
                rows = rows,
            })
            local found = false
            for _, r in ipairs(self.candidates) do
                if U.key(r.key) == U.key(key) then
                    r.rows = {}
                    for i = 1, math.min(64, #rows) do
                        r.rows[i] = U.copy(rows[i])
                    end
                    r.at = self.api.clock()
                    r.exactAt = self.api.clock()
                    r.family = false
                    r.scope = j.scope
                    r.kind = resultKind or kind
                    found = true
                end
            end
            if not found then
                if #self.candidates >= 2000 then
                    table.remove(self.candidates, 1)
                end
                local displayRows = {}
                for i = 1, math.min(64, #rows) do
                    displayRows[i] = U.copy(rows[i])
                end
                self.candidates[#self.candidates + 1] = {
                    key = U.copy(key),
                    rows = displayRows,
                    at = self.api.clock(),
                    exactAt = self.api.clock(),
                    complete = true,
                    scope = j.scope,
                    kind = resultKind or kind,
                    family = false,
                }
            end
        elseif #rows == 0 then
            for i = #self.candidates, 1, -1 do
                local r = self.candidates[i]
                if r.scope == j.scope and U.key(r.key) == U.key(key) then
                    table.remove(self.candidates, i)
                end
            end
        end
        F.Radar.results(self, j, rows, true, resultKind or kind)
        if #rows == 0 and (resultKind or kind) ~= "commodity" and (key.itemLevel or 0) ~= 0 and j.origin ~= "radar" then
            -- Equipment found by the full scan may be listed under a base key without item level.
            -- Retry once with that key instead of showing an empty deal.
            local base = U.copy(key)
            base.itemLevel = 0
            if self.selection and U.key(self.selection.key) == U.key(key) then
                self.selection.key = U.copy(base)
            end
            self.plan = nil
            self.reviewRequest = { key = base, at = self.api.clock(), scope = j.scope, owner = self.api.owner() }
            self:notify("review_wait")
            return
        end
        self:notify(self.plan.canBuy and "plan_ready" or "plan_review")
        if self.watching and self.plan.canBuy and self.plan.cost > 0 then
            local signature = U.key(key) .. ":" .. self.plan.cost
            if self.alerts[signature] ~= true then
                self.alerts[signature] = true
                if self.alert then
                    self.alert(U.name(key.itemID) .. " " .. U.money(self.plan.profit))
                end
            end
        end
    else
        self:notify("partial")
    end
end
-- A repeated result event that carries exactly the rows the current plan was built from is an
-- echo of our own search, not new market data; anything else (partial, changed) invalidates.
function C:echo(kind)
    local p = self.plan
    local ok, rows, complete = pcall(self.api.rows, p.key, p.kind or kind)
    if not ok or not complete or type(rows) ~= "table" or #rows ~= #(p.rows or {}) then
        return false
    end
    local sorted = {}
    for i, r in ipairs(rows) do
        sorted[i] = r
    end
    table.sort(sorted, function(a, b)
        if a.unit == b.unit then
            return (a.auctionID or 0) < (b.auctionID or 0)
        end
        return (a.unit or 0) < (b.unit or 0)
    end)
    for i, r in ipairs(sorted) do
        local q = p.rows[i]
        if r.unit ~= q.unit or r.qty ~= q.qty or r.auctionID ~= q.auctionID then
            return false
        end
    end
    return true
end
function C:fresh()
    local p = self.plan
    return p
        and p.origin ~= "radar"
        and not self.reviewRequest
        and p.complete
        and p.scope == self.api.scope()
        and p.at <= self.api.clock()
        and self.api.clock() - p.at <= 30
        and p.ruleVersion == self.ruleVersion
        and self.planMode == self.mode
        and not self.job
end
function C:invalidate()
    self:radarPause()
    self.ruleVersion = self.ruleVersion + 1
    self.plan = nil
    self:cancelQuote()
    self:notify("rescan")
end
function C:newOperation(kind, qty, total, auctionID)
    if not F.Ledger.capacity(self.db) then
        self:notify("ledger_full")
        return nil
    end
    self.db.sequence = (self.db.sequence or 0) + 1
    local id = "op:" .. self.api.owner() .. ":" .. self.db.sequence
    local op = {
        uid = id,
        owner = self.api.owner(),
        scope = self.api.scope(),
        key = U.key(self.key),
        id = self.key.itemID,
        qty = qty,
        total = total,
        status = "quote",
        kind = kind,
        at = self.api.clock(),
        auctionID = auctionID,
    }
    self.db.pending[id] = op
    self.active = op
    return op
end
function C:requestBuy()
    if not self:allowed() or not self:fresh() or not self.plan.canBuy or self.active then
        self:notify("buy_blocked")
        return false
    end
    if self:reserved() > 0 then
        self:notify("resolve_pending")
        return false
    end
    local p = self.plan
    if not self:budgetStillValid(p) then
        self:invalidate()
        return false
    end
    if p.kind == "commodity" then
        local op = self:newOperation("commodity", p.qty, p.cost)
        if not op then
            return false
        end
        local ok = pcall(self.api.quote, op.id, op.qty)
        if not ok then
            op.status = "cancelled"
            self.active = nil
            self:notify("quote_error")
            return false
        end
        self:notify("quote_wait")
        return true
    end
    local lot = p.lots[1]
    if not lot or not lot.auctionID then
        return false
    end
    local ok, rows, complete = pcall(self.api.rows, self.key, "item")
    local current
    if ok and complete then
        for _, r in ipairs(rows) do
            if r.auctionID == lot.auctionID and r.cost == lot.cost and r.qty == lot.qty then
                current = r
            end
        end
    end
    if not current then
        self:invalidate()
        return false
    end
    local op = self:newOperation("item", lot.qty, lot.cost, lot.auctionID)
    if not op then
        return false
    end
    op.status = "awaiting"
    local sent = pcall(self.api.buyItem, lot.auctionID, lot.cost)
    if not sent then
        op.status = "unknown"
        self:notify("unknown")
        return false
    end
    self.plan = nil
    self:notify("await_receipt")
    return true
end
function C:confirmBuy()
    local op = self.active
    if not self:allowed() or not op or op.status ~= "quoted" or not self:fresh() then
        return false
    end
    if not F.Ledger.capacity(self.db, op) or not self:budgetStillValid(self.plan, op) then
        self:cancelQuote()
        self:invalidate()
        return false
    end
    local remaining = self.api.quoteRemaining and self.api.quoteRemaining()
    if
        (remaining and remaining <= 0)
        or self.api.clock() - op.at > 30
        or op.quoted > op.total
        or op.quoted > self.api.wallet()
    then
        self:cancelQuote()
        return false
    end
    op.total = op.quoted
    op.status = "awaiting"
    op.at = self.api.clock()
    local ok = pcall(self.api.confirm, op.id, op.qty)
    self.plan = nil
    if not ok then
        op.status = "unknown"
        self:notify("unknown")
        return false
    end
    self:notify("await_receipt")
    return true
end
function C:cancelQuote()
    local op = self.active
    if op and (op.status == "quote" or op.status == "quoted") then
        if self.api.cancelQuote then
            pcall(self.api.cancelQuote)
        end
        op.status = "cancelled"
        self.active = nil
    end
end
function C:receipt(kind, id, qty, auctionID)
    local op = self.active
    -- The auction-ID event is exact, so it also settles an item purchase already marked unknown,
    -- including one restored after /reload.
    if kind == "item" and auctionID and not (op and op.kind == "item" and op.auctionID == auctionID) then
        op = nil
        for _, v in pairs(self.db.pending or {}) do
            if v.kind == "item" and v.auctionID == auctionID and v.owner == self.api.owner() then
                op = v
            end
        end
    end
    local exact = kind == "item" and auctionID and op and op.kind == "item" and op.auctionID == auctionID
    if exact and (op.status == "awaiting" or op.status == "unknown") then
        id, qty = op.id, op.qty
    elseif not op or op.status ~= "awaiting" or op.kind ~= kind or op.id ~= id then
        return
    end
    if kind == "item" and not exact then
        op.status = "unknown"
        self.plan = nil
        self:notify("unknown")
        return
    end
    if not U.finite(qty) or qty ~= op.qty then
        return
    end
    local ok = F.Ledger.append(self.db, {
        uid = op.uid,
        kind = "buy",
        owner = op.owner,
        scope = op.scope,
        key = op.key,
        qty = op.qty,
        total = op.total,
        at = self.api.clock(),
        source = "game",
        auctionID = op.auctionID,
    })
    if not ok then
        op.status = "unknown"
        self:notify("ledger_full")
        return
    end
    op.status = "done"
    if self.active == op then
        self.active = nil
    end
    self.plan = nil
    self.lastPurchase = { key = U.fromKey(op.key), qty = op.qty, total = op.total, at = self.api.clock() }
    self:notify("purchase_recorded")
end
function C:reconcile(uid, success)
    local op = self.db.pending and self.db.pending[uid]
    if not op or op.owner ~= self.api.owner() or (op.status ~= "unknown" and op.status ~= "bid") then
        return false
    end
    if success then
        local ok = F.Ledger.append(self.db, {
            uid = op.uid,
            kind = "buy",
            owner = op.owner,
            scope = op.scope,
            key = op.key,
            qty = op.qty,
            total = op.total,
            at = self.api.clock(),
            source = "manual-reconciled",
        })
        if not ok then
            return false
        end
    end
    op.status = success and "done" or "cancelled"
    if self.active == op then
        self.active = nil
    end
    self:notify("reconciled")
    return true
end
function C:stop(reason)
    self.planning = nil
    if reason == "manual" then
        self:radarPause()
    else
        F.Radar.stop(self)
    end
    self.watching = false
    self.job = reason == "manual" and self.job and self.job.origin == "radar" and self.job or nil
    -- Opening a deal keeps a scan that is already being processed: the server cooldown is spent.
    self.fullJob = reason == "manual"
            and self.fullJob
            and (self.fullJob.origin == "radar" or not self.fullJob.waiting)
            and self.fullJob
        or nil
    self.reviewRequest = nil
    self.selectionRequest = nil
    if reason ~= "manual" then
        self.planning = nil
        self.smallNPCActive = false
        self.replicaRecovery = nil
        self.materialRequest = nil
    end
    self.plan = nil
    self.postPending = nil
    self:cancelQuote()
    self:notify("stopped")
end
function C:watchStart()
    if not self:allowed() or #(self.db.watchlist or {}) == 0 then
        return false
    end
    self:radarPause()
    self.watching = true
    self.watchUntil = self.api.clock() + 600
    self.watchIndex = 0
    self.alerts = {}
    self:notify("watching")
    return true
end
function C:fullScan(origin)
    if origin ~= "radar" then
        self:radarPause()
    end
    if not self:allowed() then
        return false
    end
    if self.job or self.fullJob or self.active then
        self:notify("search_busy")
        return false
    end
    if not self.api.ready() then
        self:notify("throttled")
        return false
    end
    if self.api.clock() - (self.db.lastReplicate or 0) < 900 then
        self:notify("replicate_cooldown")
        return false
    end
    self.watching = false
    self.replicaRecovery = nil
    self.fullJob = {
        waiting = true,
        at = self.api.clock(),
        scope = self.api.scope(),
        owner = self.api.owner(),
        origin = origin,
        deferred = {},
        deferredCount = 0,
        readyData = {},
    }
    local ok = pcall(self.api.replicate)
    if not ok then
        self.fullJob = nil
        self:notify("replicate_error")
        return false
    end
    self.db.lastReplicate = self.api.clock()
    self:notify("replicate_wait")
    return true
end
function C:ingestReplica(j, r, now)
    local k = U.key(r.key)
    local g = j.groups[k]
    if g and g.exactAt and g.exactAt >= j.at then
        return nil
    end
    if not g and j.groupsCount < 2000 then
        g = { key = r.key, rows = {}, at = now, family = r.family, complete = true }
        j.groups[k] = g
        j.groupsCount = j.groupsCount + 1
    end
    if g then
        local price = r.buyout / r.qty
        g.depth = (g.depth or 0) + r.qty
        -- Bounded discovery ladder; exact search always replaces it before trading.
        local row = { qty = r.qty, unit = price, cost = r.buyout, link = r.link }
        -- Keeps the 64 cheapest listings. The most expensive kept row is cached, so a scan of
        -- 100k+ listings costs one comparison per row; a rescan happens only on replacement.
        if #g.rows < 64 then
            g.rows[#g.rows + 1] = row
            g.worstIndex = nil
        else
            if not g.worstIndex then
                local worst, index = -1, nil
                for n, v in ipairs(g.rows) do
                    if v.unit > worst then
                        worst, index = v.unit, n
                    end
                end
                g.worstIndex, g.worstUnit = index, worst
            end
            if price < g.worstUnit then
                g.rows[g.worstIndex] = row
                g.worstIndex = nil
            end
        end
    end
    return g, k
end
function C:itemDataLoaded(id, success)
    local j = self.fullJob or self.replicaRecovery
    if not j or not j.deferred or j.scope ~= self.api.scope() or j.owner ~= self.api.owner() then
        return
    end
    local entry = j.deferred[id]
    if not entry then
        return
    end
    if success == false then
        j.deferredCount = j.deferredCount - (#entry.indexes - entry.cursor + 1)
        j.deferred[id] = nil
    else
        j.readyData[id] = true
    end
end
function C:recoverReplica(now)
    local j = self.replicaRecovery
    if not j or self.fullJob then
        return
    end
    if j.scope ~= self.api.scope() or j.owner ~= self.api.owner() or now - j.at > 180 then
        self.replicaRecovery = nil
        return
    end
    local changed = false
    for _ = 1, 4 do
        local id = next(j.readyData)
        if not id then
            break
        end
        local entry = j.deferred[id]
        if not entry then
            j.readyData[id] = nil
        else
            local index = entry.indexes[entry.cursor]
            local ok, r = pcall(self.api.replicateRow, index)
            if
                ok
                and r
                and r.complete
                and r.key
                and U.finite(r.qty)
                and r.qty > 0
                and U.finite(r.buyout)
                and r.buyout > 0
            then
                local g, key = self:ingestReplica(j, r, now)
                if g then
                    if not g.scope then
                        if #self.candidates >= 2000 then
                            table.remove(self.candidates, 1)
                        end
                        self.candidates[#self.candidates + 1] = g
                    end
                    g.scope, g.at = j.scope, now
                    table.sort(g.rows, function(a, b)
                        return a.unit < b.unit
                    end)
                    local price = F.Market.snapshot(g.rows).price
                    F.Store.observe(self.db, j.scope, key, {
                        at = now,
                        price = price,
                        qty = g.depth,
                        complete = true,
                        source = "replicate",
                        token = "replicate:" .. j.at,
                        rows = g.rows,
                        family = g.family,
                    })
                    changed = true
                end
                entry.tries = 3
                j.skipped = math.max(0, j.skipped - 1)
            else
                entry.tries = (entry.tries or 0) + 1
            end
            if entry.tries >= 3 then
                entry.cursor = entry.cursor + 1
                entry.tries = 0
                j.deferredCount = j.deferredCount - 1
                if entry.cursor > #entry.indexes then
                    j.deferred[id] = nil
                    j.readyData[id] = nil
                end
            end
        end
    end
    if j.deferredCount <= 0 then
        self.replicaRecovery = nil
    end
    if changed then
        self.candidateVersion = (self.candidateVersion or 0) + 1
        if self.radar then
            self.radar.dataDirty = true
            self.radar.nextAt = math.min(self.radar.nextAt, now)
        end
        if self.db.lastScan and self.db.lastScan.scope == j.scope then
            self.db.lastScan.skipped = j.skipped
        end
        self:notify()
    end
end
function C:tick()
    if not F.Store.writable(self.db) then
        return
    end
    self:advanceRestoreCandidates(25)
    local now = self.api.clock()
    local resolved = {}
    for id, op in pairs(self.db.pending or {}) do
        if op.status == "done" or op.status == "cancelled" then
            resolved[#resolved + 1] = id
        end
    end
    if #resolved > 100 then
        table.sort(resolved, function(a, b)
            return (self.db.pending[a].at or 0) < (self.db.pending[b].at or 0)
        end)
        for i = 1, #resolved - 100 do
            self.db.pending[resolved[i]] = nil
        end
    end
    if self.active and self.active.status == "awaiting" and now - self.active.at > 90 then
        self.active.status = "unknown"
        self:notify("unknown")
    end
    if
        self.active
        and (self.active.status == "quote" or self.active.status == "quoted")
        and now - self.active.at > 30
    then
        self:cancelQuote()
        self:notify("quote_expired")
    end
    if
        self.radar
        and self.radar.enabled
        and (self.radar.scope ~= self.api.scope() or self.radar.owner ~= self.api.owner())
    then
        self:stop()
        return
    end
    if not self.api.isOpen() then
        if
            self.watching
            or self.job
            or self.fullJob
            or self.reviewRequest
            or self.selectionRequest
            or (self.radar and self.radar.enabled)
        then
            self:stop()
        end
        return
    end
    F.Adapters.pumpData(GetTime and GetTime() or now)
    self:recoverReplica(now)
    local selection = self.selectionRequest
    if selection then
        if selection.scope ~= self.api.scope() or selection.owner ~= self.api.owner() or now - selection.at > 15 then
            self.selectionRequest = nil
            self:notify("item_unavailable")
        else
            local key = F.Adapters.keyFromInput(selection.input)
            if key then
                self.selectionRequest = nil
                self.selection.key = U.copy(key)
                self.reviewRequest = { key = key, at = selection.at, scope = selection.scope, owner = selection.owner }
            end
        end
    end
    if self.job and now - self.job.at > 20 then
        if self.job.origin == "radar" then
            F.Radar.failed(self)
        end
        self.job = nil
        self.plan = nil
        self:notify("search_timeout")
    end
    local j = self.fullJob
    if j then
        if j.scope ~= self.api.scope() then
            self:stop()
            return
        end
        if j.waiting then
            if now - j.at > 35 then
                self.fullJob = nil
                self:notify("replicate_timeout")
            end
            return
        end
        -- Up to 1500 rows per update within a ~4 ms budget; a fixed 220 when the profiler is absent.
        local budgetStart = debugprofilestop and debugprofilestop()
        local stop = math.min(j.index + (budgetStart and 1500 or 220), j.total)
        for i = j.index, stop - 1 do
            if budgetStart and (i - j.index) % 50 == 49 and debugprofilestop() - budgetStart >= 4 then
                stop = i
                break
            end
            local ok, r = pcall(self.api.replicateRow, i)
            if
                ok
                and r
                and r.complete
                and r.key
                and U.finite(r.buyout)
                and r.buyout > 0
                and U.finite(r.qty)
                and r.qty > 0
            then
                self:ingestReplica(j, r, now)
            else
                j.skipped = j.skipped + 1
                if ok and r and r.id and not r.complete and (j.deferredCount or 0) < 4096 then
                    j.deferred = j.deferred or {}
                    j.readyData = j.readyData or {}
                    j.owner = j.owner or self.api.owner()
                    j.deferred[r.id] = j.deferred[r.id] or { indexes = {}, cursor = 1 }
                    table.insert(j.deferred[r.id].indexes, i)
                    j.deferredCount = (j.deferredCount or 0) + 1
                    F.Adapters.requestData(r.id)
                end
            end
        end
        j.index = stop
        if stop >= j.total then
            self.candidates = {}
            for k, g in pairs(j.groups) do
                table.sort(g.rows, function(a, b)
                    return a.unit < b.unit
                end)
                g.scope = j.scope
                self.candidates[#self.candidates + 1] = g
                local qty = 0
                for _, r in ipairs(g.rows) do
                    qty = qty + r.qty
                end
                local price = F.Market.snapshot(g.rows).price
                if price then
                    F.Store.observe(self.db, j.scope, k, {
                        at = now,
                        price = price,
                        qty = g.depth or qty,
                        complete = true,
                        source = "replicate",
                        token = "replicate:" .. j.at,
                        rows = U.copy(g.rows),
                        family = g.family,
                    })
                end
            end
            self.db.lastScan = { at = now, total = j.total, skipped = j.skipped, scope = j.scope }
            self.candidateVersion = (self.candidateVersion or 0) + 1
            if (j.deferredCount or 0) > 0 then
                self.replicaRecovery = j
            end
            self.fullJob = nil
            self:notify("replicate_done")
        end
        return
    end
    local review = self.reviewRequest
    if review then
        if review.scope ~= self.api.scope() or review.owner ~= self.api.owner() or now - review.at > 90 then
            self.reviewRequest = nil
            self:notify("search_timeout")
        elseif
            not self.job
            and not self.fullJob
            and not self.active
            and self.api.ready()
            and now - self.lastRequest >= C.REQUEST_GAP
            and (not self.api.keyReady or self.api.keyReady(review.key))
        then
            self.reviewRequest = nil
            self:search(review.key)
        end
        return
    end
    F.Radar.tick(self)
    if self.watching then
        if now >= self.watchUntil then
            self.watching = false
            self:notify("watch_finished")
            return
        end
        if not self.job and not self.active and now - self.lastRequest >= 3 and self.api.ready() then
            self.watchIndex = self.watchIndex % #self.db.watchlist + 1
            local value = self.db.watchlist[self.watchIndex]
            self:search(type(value) == "string" and U.fromKey(value) or { itemID = value })
        end
    end
end
function C:event(event, ...)
    if not F.Store.writable(self.db) then
        return
    end
    if event == "AUCTION_HOUSE_CLOSED" then
        self:stop()
        return
    end
    if event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED" then
        local id = ...
        if not self.job or self.job.key.itemID ~= id then
            F.Radar.invalidate(self, id, "commodity")
        end
        if self.job and id == self.job.key.itemID then
            self:results("commodity", self.job.key)
        elseif
            self.plan
            and self.plan.origin ~= "radar"
            and self.plan.key.itemID == id
            and not self:echo("commodity")
        then
            self:invalidate()
        end
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED" then
        local key = ...
        if type(key) == "table" then
            if not self.job or U.key(self.job.key) ~= U.key(key) then
                F.Radar.invalidate(self, key, "item")
            end
            if self.job then
                self:results("item", key)
            elseif
                self.plan
                and self.plan.origin ~= "radar"
                and U.key(self.plan.key) == U.key(key)
                and not self:echo("item")
            then
                self:invalidate()
            end
        end
    elseif event == "COMMODITY_PRICE_UPDATED" then
        local unit, total = ...
        local op = self.active
        if op and (op.status == "quote" or op.status == "quoted") then
            if
                U.finite(total)
                and total > 0
                and total <= op.total
                and self.plan
                and U.finite(unit)
                and unit <= self.plan.buyLimit
            then
                op.quoted = total
                op.status = "quoted"
                self:notify("quote_ready")
            else
                self:cancelQuote()
                self:notify("price_changed")
            end
        end
    elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
        self:cancelQuote()
        self:notify("quote_unavailable")
    elseif event == "COMMODITY_PURCHASED" then
        local id, qty = ...
        self:receipt("commodity", id, qty)
    elseif event == "ITEM_PURCHASED" then
        self:receipt("item", ...)
    elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
        self:receipt("item", nil, nil, ...)
    elseif event == "OWNED_AUCTIONS_UPDATED" then
        if self.api.owned then
            local ok, list = pcall(self.api.owned)
            if ok then
                self.owned, self.ownedAt = list, self.api.clock()
            end
        end
    elseif event == "COMMODITY_PURCHASE_FAILED" then
        if self.active and self.active.kind == "commodity" then
            self.active.status = "unknown"
            self:notify("unknown")
        end
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" and self.fullJob and self.fullJob.waiting then
        local n = self.api.replicateCount()
        if not U.finite(n) or n <= 0 then
            self.fullJob = nil
            self:notify("replicate_empty")
            return
        end
        local j = self.fullJob
        j.waiting = false
        j.total = math.min(n, 160000)
        j.index = 0
        j.groups = {}
        j.groupsCount = 0
        j.skipped = 0
    elseif event == "MAIL_INBOX_UPDATE" then
        if self.api.mail then
            local ok, m = pcall(self.api.mail)
            if ok then
                self.mail = m
                self:mailProposals()
                self:notify("mail_review")
            end
        end
    end
end
function C:more()
    if not self:allowed() or not self.plan or self.plan.complete or not self.api.ready() or not self.job then
        return false
    end
    local ok = pcall(self.api.more, self.key, self.plan.kind)
    if ok then
        self.job.at = self.api.clock()
        self:notify("searching")
    end
    return ok
end
function C:rankCandidate(r)
    if r.scope ~= self.api.scope() then
        return nil
    end
    local history = self:history(r.key)
    local best
    for _, mode in ipairs({ "vendor", "flip" }) do
        local o = self:options(r.key, mode)
        o.commodity = r.kind == "commodity" or (r.kind == nil and r.family == false)
        o.complete = true
        local p = F.Market.plan(r.rows, F.Market.evidence(history), o)
        if
            not best
            or (p.canBuy and not best.canBuy)
            or (p.canBuy == best.canBuy and p.score and p.score > (best.score or -math.huge))
        then
            best = p
            best.group = o.group
            best.groupRemaining = o.groupBudget and math.max(0, o.groupBudget - (o.groupExposure or 0))
        end
    end
    best.kind = r.kind or (r.family == false and "commodity" or "item")
    best.key = r.key
    best.identity = U.key(r.key)
    best.link = r.rows[1] and r.rows[1].link
    best.at = r.at
    best.family = r.family
    best.source = "discovery"
    if self.api.clock() - r.at > 1800 then
        best.canBuy = false
        best.reasons[#best.reasons + 1] = "stale"
    end
    return best
end
function C:rank(yieldPass)
    local out = {}
    local summary = self:summary()
    local source = {}
    for i, row in ipairs(self.candidates) do
        source[i] = row
    end
    for i, r in ipairs(source) do
        self.cachedSummary, self.salesByKey = summary, summary.salesByKey
        local p = self:rankCandidate(r)
        self.cachedSummary, self.salesByKey = nil, nil
        if p then
            out[#out + 1] = p
        end
        if yieldPass and i % 4 == 0 then
            yieldPass("ranking", i, #source)
        end
    end
    table.sort(out, function(a, b)
        if a.canBuy ~= b.canBuy then
            return a.canBuy
        end
        if (a.score or -math.huge) ~= (b.score or -math.huge) then
            return (a.score or -math.huge) > (b.score or -math.huge)
        end
        return a.identity < b.identity
    end)
    self.cachedSummary = nil
    self.salesByKey = nil
    return out
end
function C:recommend(profile, yieldPass)
    if
        self.job
        or self.fullJob
        or (
            self.active
            and (self.active.status == "awaiting" or self.active.status == "unknown" or self.active.status == "bid")
        )
    then
        return { error = "busy" }
    end
    if not self:allowed() then
        return { error = "unavailable" }
    end
    profile = F.Advisor.profiles[profile] and profile or "balanced"
    self.advisorProfile = profile
    self:invalidate()
    local config = F.Advisor.profiles[profile]
    local result = self:allocate({
        budget = self.api.wallet(),
        riskCap = math.floor(self.api.wallet() * config.fraction),
        drop = config.drop,
        yieldPass = yieldPass,
    })
    result.profile = profile
    if not yieldPass then
        self:notify("planner_done")
    end
    return result
end
function C:allocate(o)
    o = U.copy(o or {})
    o.now = self.api.clock()
    local wallet = self.api.wallet()
    local floor = U.number(self.db.settings and self.db.settings.cashFloor, 0.2, 0, 1)
    local available = math.max(0, wallet - self:reserved() - math.floor(wallet * floor))
    if not F.Store.writable(self.db) then
        available = 0
    end
    o.budget = math.min(U.number(o.budget, 0, 0, 1e12), available, self:npcRemaining() or math.huge)
    o.pauseItems = {}
    local performance = self:performance()
    for key, item in pairs(performance.items) do
        if item.pauseSuggested then
            o.pauseItems[key] = true
        end
    end
    local result = F.Workbench.allocate(self:rank(o.yieldPass), o)
    result.scope, result.owner = self.api.scope(), self.api.owner()
    result.ruleVersion = self.ruleVersion
    return result
end
function C:performance()
    local summary, bucket = self:summary(), math.floor(self.api.clock() / 60)
    local cached = self.performanceMemo
    if not cached or cached.summary ~= summary or cached.bucket ~= bucket then
        cached = { summary = summary, bucket = bucket, value = F.Workbench.performance(summary, self.api.clock()) }
        self.performanceMemo = cached
    end
    return cached.value
end
function C:price(id)
    local key = type(id) == "table" and id or { itemID = id }
    local h = self:history(key)
    local latest = h and h.latest
    if latest and not latest.family and latest.at <= self.api.clock() and self.api.clock() - latest.at < 86400 then
        return latest.price, "local"
    end
    if (key.itemLevel or 0) ~= 0 or (key.itemSuffix or 0) ~= 0 or (key.battlePetSpeciesID or 0) ~= 0 then
        return nil
    end
    local sources = F.Adapters.prices(key.itemID)
    for _, p in ipairs(sources) do
        if p.age and p.age >= 0 and p.age < 86400 then
            return p.price, p.source
        end
    end
    return nil
end
function C:bid(index)
    if self.mode == "material" then
        self:notify("bid_blocked")
        return false
    end
    if not self:allowed() or not self:fresh() or self.active or self:reserved() > 0 then
        return false
    end
    local r = self.bidRows[index]
    if not r or not r.auctionID then
        return false
    end
    local ok, _, complete, _, bids = pcall(self.api.rows, self.key, "item")
    local live
    if ok and complete then
        for _, v in ipairs(bids or {}) do
            if v.auctionID == r.auctionID then
                live = v
            end
        end
    end
    if not live then
        return false
    end
    local price = live.minBid
    if
        not U.finite(price)
        or price <= 0
        or price % 1 ~= 0
        or ((live.buyoutAmount or 0) > 0 and price >= live.buyoutAmount)
    then
        self:notify("bid_blocked")
        return false
    end
    local rule = self:options(self.key, "flip")
    rule.commodity = false
    rule.complete = true
    local h = self:history(self.key)
    local check = F.Market.plan(
        { { qty = live.quantity, unit = price / live.quantity, cost = price, auctionID = live.auctionID } },
        F.Market.evidence(h),
        rule
    )
    if not check.canBuy or check.qty ~= live.quantity or check.cost ~= price then
        self:notify("bid_blocked")
        return false
    end
    local op = self:newOperation("item", live.quantity, price, live.auctionID)
    if not op then
        return false
    end
    op.status = "bid"
    local sent = pcall(self.api.buyItem, live.auctionID, price)
    if not sent then
        op.status = "unknown"
    end
    self.plan = nil
    self:notify("bid_reserved")
    return sent
end
-- Posting needs a recent exact search of the same item (the market price check), not a purchase plan.
function C:postReady(item)
    local p = self.plan
    return p
            and item
            and p.origin ~= "radar"
            and p.complete
            and p.scope == self.api.scope()
            and self.api.clock() - (p.at or 0) <= 300
            and F.Adapters.sameListing(item.key, p.key)
        or false
end
function C:post(item, qty, price, duration)
    if not self:allowed() or self.active then
        return false
    end
    if not item then
        self:notify("post_no_item")
        return false
    end
    if not self:postReady(item) then
        self:notify("post_search")
        return false
    end
    if
        not U.finite(qty)
        or qty < 1
        or qty ~= math.floor(qty)
        or qty > item.qty
        or not U.finite(price)
        or price < 100
        or price % 100 ~= 0
    then
        self:notify("post_values")
        return false
    end
    duration = duration or 2
    if duration ~= 1 and duration ~= 2 and duration ~= 3 then
        return false
    end
    local p = self.plan
    local o = self:options(p.key)
    local floorPrice = F.Expr.eval(o.sellFormula, F.Market.sources(p.stats, p.minimum, o))
    local quantity = p.kind == "commodity" and qty or 1
    local gross = price * quantity
    local saleNet = gross
        - F.Market.fee(gross, o.fee, o.minFee)
        - U.floor(gross * (o.reserve or 0))
        - (o.extraCost or 0)
    -- Without price history the formula floor is unknown; the vendor-value check still applies.
    if (floorPrice and price < floorPrice) or (o.vendor and saleNet < quantity * o.vendor) then
        self:notify("post_floor")
        return false
    end
    local ok, deposit = pcall(self.api.deposit, item, p.kind, quantity, duration or 2)
    if not ok or not U.finite(deposit) or deposit > self.api.wallet() - self:reserved() then
        self:notify("deposit_unknown")
        return false
    end
    local location = U.key(item.key) .. "|" .. tostring(item.bag) .. "|" .. tostring(item.slot)
    if self.api.bagItems then
        local live = false
        for _, r in ipairs(self.api.bagItems()) do
            if r.bag == item.bag and r.slot == item.slot and U.key(r.key) == U.key(item.key) and r.qty >= quantity then
                item = r
                live = true
                break
            end
        end
        if not live then
            self.postPending = nil
            self:notify("rescan")
            return false
        end
    end
    local confirm = self.postPending
        and self.postPending.price == price
        and self.postPending.qty == quantity
        and self.postPending.location == location
        and self.postPending.duration == duration
    local sent, needs = pcall(self.api.post, item, p.kind, quantity, price, duration or 2, confirm)
    if not sent then
        self.postPending = nil
        self:notify("post_error")
        return false
    end
    if needs and not confirm then
        self.postPending = { location = location, price = price, qty = quantity, duration = duration }
        self:notify("post_confirm")
    else
        self.db.listings = self.db.listings or {}
        self.db.listings[#self.db.listings + 1] = {
            owner = self.api.owner(),
            scope = self.api.scope(),
            key = U.key(item.key),
            name = U.name(item.id),
            qty = quantity,
            price = price,
            at = self.api.clock(),
            status = "submitted",
        }
        while #self.db.listings > 500 do
            table.remove(self.db.listings, 1)
        end
        self.postPending = nil
        self.plan = nil
        self:notify("post_sent")
    end
    return true
end
function C:budgetStillValid(p, ownOp)
    local o = self:options(p.key, p.mode, ownOp)
    o.complete = p.complete
    o.commodity = p.kind == "commodity"
    if ownOp then
        o.reserved = math.max(0, o.reserved - ownOp.total)
        if o.groupBudget then
            o.budget = math.min(
                math.max(0, o.groupBudget - o.groupExposure + ownOp.total),
                self.overrides and self.overrides.budget or math.huge
            )
        end
    end
    o.budget = math.min(o.budget or math.huge, o.materialBudget or math.huge, self:npcRemaining(ownOp) or math.huge)
    if o.advice then
        o.budget = math.min(o.budget or math.huge, o.advice.maxBudget)
    end
    if p.mode == "vendor" and p.kind == "item" then
        o.vendor = self:variantVendor(p.rows, p.key) or o.vendor
    end
    local h = self:history(p.key)
    local fresh = F.Market.plan(p.rows, F.Market.evidence(h), o)
    return fresh.canBuy and fresh.qty == p.qty and fresh.cost == p.cost
end
function C:mailProposals()
    for _, mail in ipairs(self.mail or {}) do
        mail.suggestedKey = nil
        local matches = {}
        local n = 0
        local key, scope
        mail.suggestedScope = nil
        for _, post in ipairs(self.db.listings or {}) do
            if
                mail.kind == "seller"
                and post.owner == self.api.owner()
                and post.name == mail.name
                and post.qty == mail.qty
            then
                if not matches[post.scope .. "|" .. post.key] then
                    matches[post.scope .. "|" .. post.key] = true
                    n = n + 1
                    key, scope = post.key, post.scope
                end
            end
        end
        if n == 1 then
            mail.suggestedKey, mail.suggestedScope = key, scope
        end
    end
    -- Sale invoices that match exactly one own listing are recorded automatically, once each.
    if (self.db.settings or {}).autoMail ~= false and F.Store.writable(self.db) then
        local recorded, occurrences, cohorts = 0, {}, {}
        for _, mail in ipairs(self.mail or {}) do
            local content = mail.fingerprint
            if content then
                local bucket = mail.arrivalBucket or 0
                local existing = self.db.mailReconciliation
                        and self.db.mailReconciliation[self.api.owner()]
                        and self.db.mailReconciliation[self.api.owner()][content]
                    or {}
                cohorts[content] = cohorts[content] or {}
                for known in pairs(existing) do
                    if math.abs(known - bucket) <= 1 then
                        bucket = known
                        break
                    end
                end
                for known in pairs(cohorts[content]) do
                    if math.abs(known - bucket) <= 1 then
                        bucket = known
                        break
                    end
                end
                cohorts[content][bucket] = true
                mail.normalizedBucket = bucket
                local group = content .. "|" .. tostring(bucket)
                occurrences[group] = (occurrences[group] or 0) + 1
                mail.occurrence = occurrences[group]
            end
            if self:recordMailSale(mail) then
                recorded = recorded + 1
            end
        end
        self.mailRecorded = recorded
    end
end
function C:recordMailSale(mail)
    if
        mail.kind ~= "seller"
        or not mail.suggestedKey
        or not U.finite(mail.amount)
        or mail.amount <= 0
        or not U.finite(mail.deposit)
        or mail.deposit < 0
        or mail.deposit > mail.amount
        or not mail.fingerprint
    then
        return false
    end
    if not F.Store.writable(self.db) or not mail.suggestedScope then
        return false
    end
    -- Old volatile fingerprints cannot prove identity: retain those receipts and require
    -- manual reconciliation for matching content rather than silently booking them again.
    for _, e in ipairs(self.db.ledger or {}) do
        if
            e.source == "mail"
            and not e.mailVersion
            and e.owner == self.api.owner()
            and e.key == mail.suggestedKey
            and e.qty == mail.qty
            and e.total == mail.amount - mail.deposit
        then
            return false
        end
    end
    self.db.mailReconciliation = self.db.mailReconciliation or {}
    local owner = self.api.owner()
    local groups = self.db.mailReconciliation[owner] or {}
    self.db.mailReconciliation[owner] = groups
    local counts = groups[mail.fingerprint] or {}
    groups[mail.fingerprint] = counts
    local bucket = mail.normalizedBucket or mail.arrivalBucket or 0
    -- API expiry rounding may straddle a day boundary; ambiguous adjacent cohorts are
    -- intentionally merged. High-water multiplicity never drops when letters disappear.
    for known in pairs(counts) do
        if math.abs(known - bucket) <= 1 then
            bucket = known
            break
        end
    end
    local occurrence = mail.occurrence or 1
    if occurrence <= (counts[bucket] or 0) then
        return false
    end
    local uid = "mail:v2:" .. owner .. ":" .. mail.fingerprint .. ":" .. bucket .. ":" .. occurrence
    local ok = F.Ledger.append(self.db, {
        uid = uid,
        kind = "sell",
        owner = self.api.owner(),
        scope = mail.suggestedScope,
        key = mail.suggestedKey,
        qty = mail.qty,
        total = mail.amount - mail.deposit,
        fee = 0,
        at = self.api.clock(),
        source = "mail",
        mailVersion = 2,
    })
    if ok then
        counts[bucket] = occurrence
    end
    return ok and true or false
end
