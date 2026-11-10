local F = ForeverFlip
local U = F.Util
local L = {}
F.Ledger = L
local function active(op)
    return op.status == "quote"
        or op.status == "quoted"
        or op.status == "awaiting"
        or op.status == "unknown"
        or op.status == "bid"
end
function L.capacity(db, ownOp)
    local reserved = 0
    for _, op in pairs(db.pending or {}) do
        if op ~= ownOp and active(op) then
            reserved = reserved + 1
        end
    end
    return #db.ledger + reserved < 10000
end
function L.effective(entries, owner, scope)
    local void, seen, out, indexes = {}, {}, {}, {}
    for _, e in ipairs(entries or {}) do
        if type(e) == "table" and e.kind == "void" and type(e.target) == "string" then
            void[tostring(e.owner) .. "|" .. e.target] = true
        end
    end
    for i, e in ipairs(entries or {}) do
        if
            type(e) == "table"
            and e.kind ~= "void"
            and (not owner or e.owner == owner)
            and (not scope or e.scope == scope)
        then
            local uid = e.uid and (tostring(e.owner) .. "|" .. e.uid)
            if not uid or not (seen[uid] or void[uid]) then
                if uid then
                    seen[uid] = true
                end
                out[#out + 1], indexes[e] = e, i
            end
        end
    end
    return out, indexes
end
function L.append(db, e)
    -- A previously submitted purchase must always be recoverable, even if an older version
    -- spent with a full ledger. Only the matching unresolved receipt may exceed the soft cap.
    local op = e.uid and db.pending and db.pending[e.uid]
    local recovery = op
        and active(op)
        and e.kind == "buy"
        and e.owner == op.owner
        and e.scope == op.scope
        and e.key == op.key
        and e.qty == op.qty
        and e.total == op.total
    if not F.Store.writable(db) or (not recovery and not L.capacity(db)) then
        return false, "Ledger limit/read-only"
    end
    if
        not e.owner
        or not e.scope
        or type(e.key) ~= "string"
        or U.key(U.fromKey(e.key)) ~= e.key
        or not U.finite(e.qty)
        or e.qty < 1
        or e.qty ~= math.floor(e.qty)
        or not U.finite(e.total)
        or e.total < 0
        or e.total ~= math.floor(e.total)
    then
        return false, "Invalid receipt"
    end
    if e.uid then
        for _, v in ipairs(db.ledger) do
            if v.uid == e.uid then
                if
                    recovery
                    and v.kind == e.kind
                    and v.owner == e.owner
                    and v.scope == e.scope
                    and v.key == e.key
                    and v.qty == e.qty
                    and v.total == e.total
                then
                    return true, v.uid
                end
                return false, "Duplicate"
            end
        end
    end
    db.sequence = (db.sequence or 0) + 1
    e = U.copy(e)
    e.uid = e.uid or "entry:" .. db.sequence
    db.ledger[#db.ledger + 1] = e
    return true, e.uid
end
function L.correct(db, uid, owner, at)
    if not F.Store.writable(db) then
        return false
    end
    for _, e in ipairs(db.ledger) do
        if e.kind == "void" and e.target == uid then
            return false
        end
    end
    for _, e in ipairs(db.ledger) do
        if e.uid == uid and e.owner == owner and e.kind ~= "void" then
            db.sequence = (db.sequence or 0) + 1
            db.ledger[#db.ledger + 1] =
                { kind = "void", target = uid, owner = owner, at = at, uid = "entry:" .. db.sequence }
            return true
        end
    end
    return false
end
function L.summary(entries, owner, scope)
    local r = {
        buys = 0,
        sales = 0,
        fees = 0,
        realized = 0,
        unknown = 0,
        stock = 0,
        positions = {},
        salesHistory = {},
        activity = {},
        transactions = 0,
    }
    local queues = {}
    for _, e in ipairs(L.effective(entries, owner, scope)) do
        do
            local qty, total = e.qty, e.total
            if
                U.finite(qty)
                and qty > 0
                and qty == math.floor(qty)
                and U.finite(total)
                and total >= 0
                and type(e.key) == "string"
            then
                local identity = tostring(e.owner) .. "|" .. tostring(e.scope) .. "|" .. e.key
                local q = queues[identity] or { lots = {}, key = e.key, scope = e.scope, owner = e.owner }
                queues[identity] = q
                r.transactions = r.transactions + 1
                if e.kind == "buy" then
                    if U.finite(e.at) then
                        local a = r.activity[e.key] or {}
                        a.since = math.min(a.since or e.at, e.at)
                        r.activity[e.key] = a
                    end
                    q.lots[#q.lots + 1] = { qty = qty, cost = total, at = e.at }
                    r.buys = r.buys + total
                elseif e.kind == "expense" then
                    r.fees = r.fees + total
                    r.realized = r.realized - total
                elseif e.kind == "sell" or e.kind == "vendor" then
                    local fee = U.number(e.fee, 0, 0, total)
                    local left, cost, held = qty, 0, 0
                    while left > 0 and #q.lots > 0 do
                        local lot = q.lots[1]
                        local take = math.min(left, lot.qty)
                        held = held + take * math.max(0, (e.at or 0) - (lot.at or e.at or 0))
                        local used = take == lot.qty and lot.cost or math.floor(lot.cost * take / lot.qty)
                        cost = cost + used
                        lot.cost = lot.cost - used
                        lot.qty = lot.qty - take
                        left = left - take
                        if lot.qty == 0 then
                            table.remove(q.lots, 1)
                        end
                    end
                    local known = qty - left
                    local proceeds = known == qty and total or math.floor(total * known / qty)
                    local knownFee = known == qty and fee or math.floor(fee * known / qty)
                    local profit = proceeds - knownFee - cost
                    r.sales = r.sales + total
                    r.fees = r.fees + fee
                    r.realized = r.realized + profit
                    r.unknown = r.unknown + left
                    r.salesHistory[#r.salesHistory + 1] = {
                        kind = e.kind,
                        key = e.key,
                        qty = qty,
                        known = known,
                        unknown = left,
                        profit = profit,
                        at = e.at,
                        total = total,
                        fee = fee,
                        cost = cost,
                        -- Average seconds the sold units were held (FIFO), for sell-speed statistics.
                        held = known > 0 and held / known or nil,
                    }
                end
            end
        end
    end
    for _, q in pairs(queues) do
        local qty, cost, oldest = 0, 0, nil
        for _, lot in ipairs(q.lots) do
            qty = qty + lot.qty
            cost = cost + lot.cost
            oldest = math.min(oldest or lot.at or 0, lot.at or 0)
        end
        if qty > 0 then
            r.positions[#r.positions + 1] =
                { key = q.key, qty = qty, cost = cost, at = oldest, owner = q.owner, scope = q.scope }
            r.stock = r.stock + cost
        end
    end
    table.sort(r.positions, function(a, b)
        return a.cost > b.cost
    end)
    return r
end
function L.csv(entries)
    local lines = { "uid,kind,owner,scope,item,quantity,total_copper,fee_copper,at" }
    local function quote(v)
        return '"' .. tostring(v or ""):gsub('"', '""'):gsub("[\r\n]", " ") .. '"'
    end
    for _, e in ipairs(entries or {}) do
        local a = {}
        for _, k in ipairs({ "uid", "kind", "owner", "scope", "key", "qty", "total", "fee", "at" }) do
            a[#a + 1] = quote(e[k])
        end
        lines[#lines + 1] = table.concat(a, ",")
    end
    return table.concat(lines, "\n")
end
