local F = ForeverFlip
local U = F.Util
local S = {}
F.Store = S
S.defaults = {
    minROI = 0.25,
    minProfit = 10000,
    maxWallet = 0.10,
    maxItem = 0.20,
    cashFloor = 0.20,
    maxQty = 100,
    maxShare = 0.15,
    fee = 0.05,
    minFee = 0,
    reserve = 0.02,
    buyFormula = "70% market",
    sellFormula = "max(vendorsell,90% market)",
    safe = true,
}
S.invalid = setmetatable({}, { __mode = "k" })
function S.writable(db)
    return type(db) == "table" and db.schemaVersion == 5 and not S.invalid[db] and not db.migrationBlocked
end
function S.open(old)
    if type(old) == "table" and old.schemaVersion then
        if old.schemaVersion == 5 then
            for _, key in ipairs({
                "settings",
                "watchlist",
                "groups",
                "ledger",
                "legacyLedger",
                "markets",
                "pending",
                "recipes",
                "disenchant",
                "ui",
            }) do
                if type(old[key]) ~= "table" then
                    S.invalid[old] = true
                    return old
                end
            end
            for _, op in pairs(old.pending) do
                if type(op) ~= "table" then
                    S.invalid[old] = true
                    return old
                end
            end
            for _, e in ipairs(old.ledger) do
                if type(e) ~= "table" then
                    S.invalid[old] = true
                    return old
                end
            end
            for k, v in pairs(S.defaults) do
                if
                    old.settings[k] ~= nil
                    and (type(old.settings[k]) ~= type(v) or (type(v) == "number" and not U.finite(old.settings[k])))
                then
                    S.invalid[old] = true
                    return old
                end
            end
            for k, v in pairs({
                settings = {},
                watchlist = {},
                groups = {},
                ledger = {},
                legacyLedger = {},
                markets = {},
                pending = {},
                recipes = {},
                disenchant = {},
                vendorPrices = {},
                receipts = {},
                ui = {},
                quarantine = {},
            }) do
                if type(old[k]) ~= "table" then
                    old[k] = v
                end
            end
            for k, v in pairs(S.defaults) do
                if old.settings[k] == nil then
                    old.settings[k] = v
                end
            end
        end
        return old
    end
    local db = {
        schemaVersion = 5,
        settings = U.copy(S.defaults),
        watchlist = {},
        groups = {},
        ledger = {},
        legacyLedger = {},
        markets = {},
        pending = {},
        recipes = {},
        disenchant = {},
        vendorPrices = {},
        receipts = {},
        ui = {},
        quarantine = {},
        sequence = 0,
    }
    if type(old) == "table" then
        local function legacy(name)
            if type(old[name]) == "table" then
                return U.copy(old[name])
            end
            if old[name] ~= nil then
                db.quarantine[#db.quarantine + 1] = { field = name, value = U.copy(old[name]) }
            end
            return {}
        end
        db.watchlist = legacy("watchlist")
        db.recipes = legacy("recipes")
        db.disenchant = legacy("disenchant")
        db.legacyLedger = legacy("ledger")
        db.legacyHistory = legacy("history")
        db.legacyRadarHistory = legacy("radarHistory")
        db.groups = legacy("groups")
        db.ui.theme = old.uiTheme
        if old.ledger ~= nil and type(old.ledger) ~= "table" then
            db.migrationBlocked = true
        end
        for _, e in ipairs(db.legacyLedger) do
            if
                type(e) ~= "table"
                or not U.key(e.id)
                or not U.finite(e.qty)
                or e.qty < 1
                or e.qty % 1 ~= 0
                or not U.finite(e.unit)
                or e.unit < 0
            then
                db.migrationBlocked = true
            end
        end
        for _, r in pairs(db.recipes) do
            if type(r) == "table" then
                r.outputQty = r.outputQty or r.qty or 1
            end
        end
        for _, r in pairs(db.disenchant) do
            if type(r) == "table" then
                r.raw = r.raw or r.materials
                r.cost = r.cost or r.buyCost
            end
        end
        if U.finite(old.fee) then
            db.settings.fee = old.fee
        end
        if U.finite(old.reserve) then
            db.settings.reserve = old.reserve
        end
        if U.finite(old.beginnerMaxCopper) then
            db.settings.absoluteCap = old.beginnerMaxCopper
        end
    end
    return db, old
end
function S.observe(db, scope, key, o)
    if
        not S.writable(db)
        or not scope
        or not key
        or not U.finite(o.at)
        or not U.finite(o.price)
        or o.price <= 0
        or not o.complete
    then
        return false
    end
    db.markets[scope] = db.markets[scope] or {}
    local m = db.markets[scope]
    local h = m[key]
    if not h then
        local count = 0
        for _ in pairs(m) do
            count = count + 1
        end
        if count >= 2000 then
            local oldest, stamp
            for k, v in pairs(m) do
                local id = tonumber(k:match("^(%d+)"))
                local watched = false
                for _, w in ipairs(db.watchlist) do
                    if w == id then
                        watched = true
                    end
                end
                if not watched and (not stamp or (v.at or 0) < stamp) then
                    oldest = k
                    stamp = v.at or 0
                end
            end
            if not oldest then
                return false
            end
            m[oldest] = nil
        end
        h = { samples = {}, days = {} }
        m[key] = h
    end
    for _, s in ipairs(h.samples) do
        if (o.token and s.token == o.token) or math.abs(s.at - o.at) < 600 then
            return false
        end
    end
    local sample = {
        at = o.at,
        price = o.price,
        qty = o.qty,
        token = o.token,
        complete = true,
        source = o.source,
        family = o.family,
    }
    h.samples[#h.samples + 1] = sample
    while #h.samples > 120 do
        table.remove(h.samples, 1)
    end
    h.at = math.max(h.at or 0, o.at)
    h.latest = {
        at = o.at,
        price = o.price,
        qty = o.qty,
        complete = true,
        token = o.token,
        source = o.source,
        family = o.family,
    }
    if o.rows then
        h.latest.rows = {}
        for i = 1, math.min(64, #o.rows) do
            h.latest.rows[i] = U.copy(o.rows[i])
        end
    end
    local day = math.floor(o.at / 86400)
    local d
    for _, v in ipairs(h.days) do
        if v.day == day then
            d = v
        end
    end
    if not d then
        d = { day = day, price = 0, n = 0, low = o.price, high = o.price, qty = 0 }
        h.days[#h.days + 1] = d
    end
    d.price = (d.price * d.n + o.price) / (d.n + 1)
    d.n = d.n + 1
    d.low = math.min(d.low, o.price)
    d.high = math.max(d.high, o.price)
    d.qty = o.qty or 0
    table.sort(h.days, function(a, b)
        return a.day < b.day
    end)
    while #h.days > 60 or (#h.days > 0 and h.days[1].day < math.floor(h.at / 86400) - 59) do
        table.remove(h.days, 1)
    end
    return true
end
function S.watch(db, id)
    if type(id) == "string" and U.fromKey(id) then
        id = U.key(U.fromKey(id))
    else
        id = tonumber(id)
        if not id or id < 1 or id ~= math.floor(id) then
            return false, "Item ID"
        end
    end
    for _, v in ipairs(db.watchlist) do
        if v == id then
            return true
        end
    end
    if #db.watchlist >= 500 then
        return false, "Watchlist limit: 500"
    end
    db.watchlist[#db.watchlist + 1] = id
    return true
end
function S.importGroup(text)
    if type(text) ~= "string" or #text > 8000 then
        return nil, "Size"
    end
    local version, name, ids, roi, profit, budget, qty =
        text:match("^(FFG[12])|([^|\r\n]+)|([%d,:%-]+)|([%d%.]+)|([%d%.]+)|([%d%.]+)|(%d+)$")
    if not name then
        return nil, "FFG1 format required"
    end
    local g = { name = name, items = {}, keys = {}, rule = {} }
    local count = 0
    for value in ids:gmatch("[^,]+") do
        if version == "FFG2" then
            local key = U.fromKey(value)
            if not key then
                return nil, "Exact key required"
            end
            g.keys[U.key(key)] = true
        else
            local id = tonumber(value)
            if not U.finite(id) or id < 1 or id % 1 ~= 0 then
                return nil, "ID"
            end
            g.items[id] = true
        end
        count = count + 1
    end
    if count > 500 or count == 0 then
        return nil, "Items limit"
    end
    local roiNumber = tonumber(roi)
    if not U.finite(roiNumber) then
        return nil, "Invalid ROI"
    end
    g.rule.minROI = roiNumber / 100
    g.rule.minProfit = U.copper(profit)
    g.rule.budget = U.copper(budget)
    g.rule.maxQty = tonumber(qty)
    if
        g.rule.minROI > 10
        or not g.rule.minProfit
        or not g.rule.budget
        or g.rule.maxQty < 1
        or g.rule.maxQty > 100000
    then
        return nil, "Rule limits"
    end
    return g
end
function S.exportGroup(g)
    local exact = g.keys and next(g.keys) ~= nil
    local ids = U.sortedKeys(exact and g.keys or g.items)
    local r = g.rule or {}
    return table.concat({
        exact and "FFG2" or "FFG1",
        g.name,
        table.concat(ids, ","),
        (r.minROI or 0.25) * 100,
        U.gold(r.minProfit or 10000),
        U.gold(r.budget or 1000000),
        r.maxQty or 100,
    }, "|")
end
function S.adoptLegacy(db, owner, scope, now)
    if not S.writable(db) then
        return false, "Read-only"
    end
    if db.legacyAssigned then
        return true
    end
    local additions, seen = {}, {}
    for _, e in ipairs(db.ledger) do
        if e.uid then
            seen[e.uid] = true
        end
    end
    for i, e in ipairs(db.legacyLedger) do
        if
            type(e) ~= "table"
            or not U.key(e.id)
            or not U.finite(e.qty)
            or e.qty < 1
            or e.qty % 1 ~= 0
            or not U.finite(e.unit)
            or e.unit < 0
            or (e.kind ~= "buy" and e.kind ~= "sell" and e.kind ~= "expense")
        then
            return false, "Invalid legacy row " .. i
        end
        local uid = "legacy:" .. i
        local total = math.floor(e.qty * e.unit + 0.5)
        if not seen[uid] then
            additions[#additions + 1] = {
                uid = uid,
                owner = owner,
                scope = scope,
                key = U.key(e.id),
                kind = e.kind,
                qty = e.qty,
                total = total,
                fee = e.fee or (e.kind == "sell" and F.Market.fee(total, db.settings.fee, db.settings.minFee) or 0),
                at = e.at or now,
                source = "legacy-confirmed",
            }
        end
    end
    if #db.ledger + #additions > 10000 then
        return false, "Ledger capacity: export/reconcile first"
    end
    for _, e in ipairs(additions) do
        db.ledger[#db.ledger + 1] = e
    end
    db.legacyAssigned = true
    return true
end
function S.importPrices(db, text, scope, now)
    if not S.writable(db) or type(text) ~= "string" or #text > 200000 then
        return false, "Input limit/read-only"
    end
    local header, body = text:match("^([^\r\n]+)[\r\n]+(.*)$")
    local sourceScope, stamp
    if header then
        sourceScope, stamp = header:match("^FFP1|([^|]+)|(%d+)$")
    end
    stamp = tonumber(stamp)
    if sourceScope ~= scope or not stamp or stamp > now or stamp < now - 60 * 86400 then
        return false, "Market scope / timestamp mismatch"
    end
    local pending = {}
    local count = 0
    for line in body:gmatch("[^\r\n]+") do
        local key, price, qty = line:match("^([%d:%-]+),(%d+),(%d+)$")
        price, qty = tonumber(price), tonumber(qty)
        if not U.fromKey(key) or not price or price <= 0 or price > 1e12 or not qty or qty < 1 or qty > 100000000 then
            return false, "Invalid price row"
        end
        count = count + 1
        if count > 2000 then
            return false, "2000 rows maximum"
        end
        pending[#pending + 1] = { key = key, price = price, qty = qty }
    end
    if #pending == 0 then
        return false, "No price rows"
    end
    for _, p in ipairs(pending) do
        S.observe(
            db,
            scope,
            p.key,
            { at = stamp, price = p.price, qty = p.qty, complete = true, token = "import:" .. stamp, source = "import" }
        )
    end
    return true
end
