local F = ForeverFlip
local U = F.Util
local L = {}
F.Ledger = L
function L.append(db, e)
    if not F.Store.writable(db) or #db.ledger >= 10000 then
        return false, "Ledger limit/read-only"
    end
    if
        not e.owner
        or not e.scope
        or not e.key
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
    if not F.Store.writable(db) or #db.ledger >= 10000 then
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
    local void, seen, queues = {}, {}, {}
    for _, e in ipairs(entries or {}) do
        if e.kind == "void" and (not owner or e.owner == owner) then
            void[e.target] = true
        end
    end
    for _, e in ipairs(entries or {}) do
        if
            (not owner or e.owner == owner)
            and (not scope or e.scope == scope)
            and not (e.uid and (seen[e.uid] or void[e.uid]))
        then
            if e.uid then
                seen[e.uid] = true
            end
            local qty, total = e.qty, e.total
            if U.finite(qty) and qty > 0 and qty == math.floor(qty) and U.finite(total) and total >= 0 and e.key then
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
                    local left, cost = qty, 0
                    while left > 0 and #q.lots > 0 do
                        local lot = q.lots[1]
                        local take = math.min(left, lot.qty)
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
