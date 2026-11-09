local F = ForeverFlip
local U = F.Util
local C = {}
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
    return self.cachedSummary or F.Ledger.summary(self.db.ledger, self.api.owner(), self.api.scope())
end
function C:rule(value)
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
    return out
end
function C:options(key, mode, ownOp)
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
    for _, p in ipairs(summary.positions) do
        if p.key == identity then
            o.exposure = p.cost
            o.ownedQty = p.qty
        end
    end
    o.velocity = F.Market.velocity(
        self.salesByKey and (self.salesByKey[identity] or {}) or summary.salesHistory,
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
    if self.advisorProfile and o.mode ~= "vendor" then
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
            self.salesByKey and (self.salesByKey[identity] or {}) or summary.salesHistory,
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
    if (key.itemLevel or 0) ~= 0 or (key.itemSuffix or 0) ~= 0 or (key.battlePetSpeciesID or 0) ~= 0 then
        o.vendor = nil
    end
    for k, v in pairs(self.overrides or {}) do
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
    local h = self.db.markets and self.db.markets[self.api.scope()]
    return h and h[U.key(key)]
end
function C:search(key)
    if not self:allowed() or not U.key(key) then
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
    if self.job or self.fullJob then
        self:notify("search_busy")
        return false
    end
    if not self.api.ready() or self.api.clock() - self.lastRequest < 2 then
        self:notify("throttled")
        return false
    end
    self.serial = self.serial + 1
    self.key = U.copy(key)
    self.plan = nil
    self.job = { key = U.copy(key), scope = self.api.scope(), at = self.api.clock(), token = self.serial, tries = 0 }
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
    self.bidRows = bids or {}
    self.planMode = self.mode
    if complete then
        self.job = nil
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
                    complete = true,
                    scope = j.scope,
                    kind = resultKind or kind,
                    family = false,
                }
            end
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
function C:fresh()
    local p = self.plan
    return p
        and p.complete
        and p.scope == self.api.scope()
        and p.at <= self.api.clock()
        and self.api.clock() - p.at <= 30
        and p.ruleVersion == self.ruleVersion
        and self.planMode == self.mode
        and not self.job
end
function C:invalidate()
    self.ruleVersion = self.ruleVersion + 1
    self.plan = nil
    self:cancelQuote()
    self:notify("rescan")
end
function C:newOperation(kind, qty, total, auctionID)
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
    if not self:budgetStillValid(self.plan, op) then
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
function C:receipt(kind, id, qty)
    local op = self.active
    if not op or op.status ~= "awaiting" or op.kind ~= kind or op.id ~= id then
        return
    end
    if kind == "item" then
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
    self.active = nil
    self.plan = nil
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
function C:stop()
    self.watching = false
    self.job = nil
    self.fullJob = nil
    self.plan = nil
    self.postPending = nil
    self:cancelQuote()
    self:notify("stopped")
end
function C:watchStart()
    if not self:allowed() or #(self.db.watchlist or {}) == 0 then
        return false
    end
    self.watching = true
    self.watchUntil = self.api.clock() + 600
    self.watchIndex = 0
    self.alerts = {}
    self:notify("watching")
    return true
end
function C:fullScan()
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
    self.fullJob = { waiting = true, at = self.api.clock(), scope = self.api.scope() }
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
function C:tick()
    if not F.Store.writable(self.db) then
        return
    end
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
    if not self.api.isOpen() then
        if self.watching or self.job or self.fullJob then
            self:stop()
        end
        return
    end
    if self.job and now - self.job.at > 20 then
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
        local stop = math.min(j.index + 220, j.total)
        for i = j.index, stop - 1 do
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
                local k = U.key(r.key)
                local g = j.groups[k]
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
                    if #g.rows < 64 then
                        g.rows[#g.rows + 1] = row
                    else
                        local worst, index = 0, nil
                        for n, v in ipairs(g.rows) do
                            if v.unit > worst then
                                worst = v.unit
                                index = n
                            end
                        end
                        if index and price < worst then
                            g.rows[index] = row
                        end
                    end
                end
            else
                j.skipped = j.skipped + 1
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
            self.fullJob = nil
            self:notify("replicate_done")
        end
        return
    end
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
    if event == "AUCTION_HOUSE_CLOSED" then
        self:stop()
        return
    end
    if event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED" then
        local id = ...
        if self.job and id == self.job.key.itemID then
            self:results("commodity", self.job.key)
        elseif self.plan and self.plan.key.itemID == id then
            self:invalidate()
        end
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED" then
        local key = ...
        if type(key) == "table" then
            if self.job then
                self:results("item", key)
            elseif self.plan and U.key(self.plan.key) == U.key(key) then
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
function C:rank()
    local out = {}
    self.cachedSummary = self:summary()
    self.salesByKey = {}
    for _, s in ipairs(self.cachedSummary.salesHistory) do
        self.salesByKey[s.key] = self.salesByKey[s.key] or {}
        table.insert(self.salesByKey[s.key], s)
    end
    for _, r in ipairs(self.candidates) do
        if r.scope == self.api.scope() then
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
            best.link = r.rows[1] and r.rows[1].link
            best.at = r.at
            best.family = r.family
            best.source = "discovery"
            if self.api.clock() - r.at > 1800 then
                best.canBuy = false
                best.reasons[#best.reasons + 1] = "stale"
            end
            out[#out + 1] = best
        end
    end
    table.sort(out, function(a, b)
        if a.canBuy ~= b.canBuy then
            return a.canBuy
        end
        if (a.score or -math.huge) ~= (b.score or -math.huge) then
            return (a.score or -math.huge) > (b.score or -math.huge)
        end
        return U.key(a.key) < U.key(b.key)
    end)
    self.cachedSummary = nil
    self.salesByKey = nil
    return out
end
function C:recommend(profile)
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
    })
    result.profile = profile
    self:notify("planner_done")
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
    o.budget = math.min(U.number(o.budget, 0, 0, 1e12), available)
    o.pauseItems = {}
    local performance = F.Workbench.performance(self:summary(), o.now)
    for key, item in pairs(performance.items) do
        if item.pauseSuggested then
            o.pauseItems[key] = true
        end
    end
    return F.Workbench.allocate(self:rank(), o)
end
function C:price(id)
    local h = self:history({ itemID = id })
    local latest = h and h.latest
    if latest and not latest.family and latest.at <= self.api.clock() and self.api.clock() - latest.at < 86400 then
        return latest.price, "local"
    end
    local sources = F.Adapters.prices(id)
    for _, p in ipairs(sources) do
        if p.age and p.age >= 0 and p.age < 86400 then
            return p.price, p.source
        end
    end
    return nil
end
function C:bid(index)
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
    op.status = "bid"
    local sent = pcall(self.api.buyItem, live.auctionID, price)
    if not sent then
        op.status = "unknown"
    end
    self.plan = nil
    self:notify("bid_reserved")
    return sent
end
function C:post(item, qty, price, duration)
    if not self:allowed() or not self:fresh() or not item or U.key(item.key) ~= U.key(self.key) or self.active then
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
    local o = self:options(self.key)
    local floorPrice = F.Expr.eval(o.sellFormula, F.Market.sources(p.stats, p.minimum, o))
    local quantity = p.kind == "commodity" and qty or 1
    local gross = price * quantity
    local saleNet = gross
        - F.Market.fee(gross, o.fee, o.minFee)
        - U.floor(gross * (o.reserve or 0))
        - (o.extraCost or 0)
    if not floorPrice or price < floorPrice or (o.vendor and saleNet < quantity * o.vendor) then
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
        local key
        for _, post in ipairs(self.db.listings or {}) do
            if
                mail.kind == "seller"
                and post.owner == self.api.owner()
                and post.scope == self.api.scope()
                and post.name == mail.name
                and post.qty == mail.qty
            then
                if not matches[post.key] then
                    matches[post.key] = true
                    n = n + 1
                    key = post.key
                end
            end
        end
        if n == 1 then
            mail.suggestedKey = key
        end
    end
end
