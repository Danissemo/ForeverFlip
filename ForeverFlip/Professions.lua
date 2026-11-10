local F = ForeverFlip
local U = F.Util
local P = {}
F.Professions = P
local function validOptions(o)
    local fee, reserve = o.fee or 0.05, o.reserve or 0
    return U.finite(fee)
        and fee >= 0
        and fee <= 0.5
        and U.finite(reserve)
        and reserve >= 0
        and reserve <= 0.5
        and fee + reserve < 1
        and U.finite(o.minFee or 0)
        and (o.minFee or 0) >= 0
        and U.finite(o.extraCost or 0)
        and (o.extraCost or 0) >= 0
end
function P.parse(text, fraction)
    local out = {}
    if type(text) ~= "string" or #text > 16000 then
        return nil, "Input size"
    end
    for part in text:gmatch("[^,;\n]+") do
        local id, q, price = part:match("^%s*(%d+)%s*%*%s*([%d%.]+)%s*@%s*([%d%.]+)%s*$")
        if not id then
            id, q = part:match("^%s*(%d+)%s*%*%s*([%d%.]+)%s*$")
        end
        id, q = tonumber(id), tonumber(q)
        if
            not U.finite(id)
            or id < 1
            or not U.finite(q)
            or q <= 0
            or q > 100000
            or (not fraction and q ~= math.floor(q))
        then
            return nil, "ID*quantity@price"
        end
        local explicit = price and U.copper(price)
        if price and not explicit then
            return nil, "ID*quantity@price"
        end
        out[#out + 1] = { id = id, qty = q, price = explicit }
        if #out > 100 then
            return nil, "Maximum 100 materials"
        end
    end
    if #out == 0 then
        return nil, "No materials"
    end
    return out
end
function P.calculate(materials, lookup, outputQty, outputPrice, o)
    o = o or {}
    local r = { complete = true, cost = 0, cashCost = 0, shopping = {}, missing = {}, profit = nil }
    if
        not validOptions(o)
        or not U.finite(outputQty)
        or outputQty <= 0
        or not U.finite(outputPrice)
        or outputPrice <= 0
    then
        r.complete = false
        return r
    end
    local stock = {}
    for _, m in ipairs(materials or {}) do
        if m.id and U.finite(m.owned) and m.owned >= 0 then
            stock[m.id] = math.max(stock[m.id] or 0, m.owned)
        end
    end
    for _, m in ipairs(materials or {}) do
        local price = m.price or (lookup and lookup(m.id))
        if not U.finite(m.qty) or m.qty <= 0 or not U.finite(price) or price <= 0 or not U.finite(m.qty * price) then
            r.complete = false
            r.missing[#r.missing + 1] = m.id
        else
            local cost = U.ceil(m.qty * price)
            local available = stock[m.id] or 0
            local missing = math.max(0, m.qty - available)
            stock[m.id] = math.max(0, available - m.qty)
            r.cost = r.cost + cost
            r.cashCost = r.cashCost + U.ceil(missing * price)
            r.shopping[#r.shopping + 1] = { id = m.id, qty = missing, price = price, cost = U.ceil(missing * price) }
        end
    end
    if not U.finite(r.cost) or not U.finite(r.cashCost) or not U.finite(outputQty * outputPrice) then
        r.complete = false
    end
    if r.complete then
        local gross = U.floor(outputQty * outputPrice)
        r.net = F.Market.net(gross, o.fee, o.reserve, o.minFee)
        r.profit = r.net - r.cost - (o.extraCost or 0)
        r.roi = r.cost > 0 and r.profit / r.cost or 0
        if not U.finite(r.net) or not U.finite(r.profit) or not U.finite(r.roi) then
            r.complete, r.net, r.profit, r.roi = false, nil, nil, nil
        end
    end
    return r
end
-- Expected yields are scenarios; each output item is sold separately and incurs its own fee.
function P.disenchant(yields, lookup, cost, o)
    o = o or {}
    if not validOptions(o) then
        return { complete = false, missing = {} }
    end
    local total, outputs = 0, {}
    local missing = {}
    for _, m in ipairs(yields or {}) do
        local price = m.price or (lookup and lookup(m.id))
        if
            not m.id
            or not U.finite(price)
            or price <= 0
            or not U.finite(m.qty)
            or m.qty <= 0
            or not U.finite(price * m.qty)
        then
            missing[#missing + 1] = m.id or "output"
        else
            local value = price * m.qty
            total = total + value
            outputs[m.id] = (outputs[m.id] or 0) + value
        end
    end
    if #missing > 0 or not U.finite(total) or not U.finite(cost) or cost <= 0 then
        return { complete = false, missing = missing }
    end
    local net = 0
    for _, value in pairs(outputs) do
        net = net + F.Market.net(U.floor(value), o.fee, o.reserve, o.minFee)
    end
    local profit = net - cost - (o.extraCost or 0)
    local roi = profit / cost
    if not U.finite(net) or not U.finite(profit) or not U.finite(roi) then
        return { complete = false, missing = missing }
    end
    return { complete = true, value = total, net = net, profit = profit, roi = roi }
end
