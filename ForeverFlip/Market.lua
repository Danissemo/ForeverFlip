local F = ForeverFlip
local U = F.Util
local M = {}
F.Market = M
function M.evidence(h)
    local out = {}
    local earliest = math.huge
    for _, s in ipairs(h and h.samples or {}) do
        out[#out + 1] = s
        if U.finite(s.at) then
            earliest = math.min(earliest, s.at)
        end
    end
    for _, d in ipairs(h and h.days or {}) do
        if U.finite(d.firstAt) and d.firstAt < earliest - 600 and U.finite(d.firstPrice) then
            out[#out + 1] = {
                at = d.firstAt,
                price = d.firstPrice,
                token = d.firstToken or ("anchor:" .. d.day),
                complete = true,
                family = d.firstFamily,
                source = "daily-anchor",
            }
        end
    end
    return out
end
function M.snapshot(rows)
    local a, total = {}, 0
    for _, r in ipairs(rows or {}) do
        if U.finite(r.unit) and r.unit > 0 and U.finite(r.qty) and r.qty > 0 then
            a[#a + 1] = r
            total = total + r.qty
        end
    end
    table.sort(a, function(x, y)
        return x.unit < y.unit
    end)
    local function quantile(f)
        local n = 0
        for _, r in ipairs(a) do
            n = n + r.qty
            if n >= total * f then
                return r.unit
            end
        end
    end
    return { price = quantile(0.20), median = quantile(0.5), minimum = a[1] and a[1].unit, qty = total }
end
function M.velocity(sales, key, now)
    local units, first, days = 0, nil, {}
    for _, s in ipairs(sales or {}) do
        if
            (s.kind == nil or s.kind == "sell")
            and s.key == key
            and U.finite(s.at)
            and s.at <= now
            and s.at >= now - 14 * 86400
            and (s.known or 0) > 0
        then
            units = units + s.known
            first = math.min(first or s.at, s.at)
            days[math.floor(s.at / 86400)] = true
        end
    end
    local count = 0
    for _ in pairs(days) do
        count = count + 1
    end
    local span = first and math.max(1, (now - first) / 86400) or 1
    return {
        known = units >= 5 and count >= 2,
        units = units,
        days = count,
        daily = units / span,
        lower = math.max(0, (units - 1.645 * math.sqrt(units)) / span),
    }
end
function M.stats(history, now)
    local prices, days, tokens, first, last = {}, {}, {}, nil, nil
    for _, h in ipairs(history or {}) do
        if
            not h.family
            and U.finite(h.price)
            and h.price > 0
            and U.finite(h.at)
            and h.at <= now
            and h.at >= now - 14 * 86400
            and h.complete ~= false
        then
            local token = tostring(h.token or math.floor(h.at / 600))
            if not tokens[token] then
                tokens[token] = true
                prices[#prices + 1] = h.price
                days[math.floor(h.at / 86400)] = true
                first = math.min(first or h.at, h.at)
                last = math.max(last or h.at, h.at)
            end
        end
    end
    local nDays = 0
    for _ in pairs(days) do
        nDays = nDays + 1
    end
    local ref = U.median(prices)
    local deviations = {}
    for _, p in ipairs(prices) do
        deviations[#deviations + 1] = math.abs(p - (ref or 0))
    end
    local sigma = (U.median(deviations) or 0) * 1.4826
    local age = last and now - last or math.huge
    local credible = #prices >= 5 and nDays >= 2 and last - first >= 86400 and age <= 2 * 86400
    local confidence = math.min(1, #prices / 12) * math.min(1, nDays / 3) * math.exp(-age / (2 * 86400))
    return {
        reference = ref,
        sigma = sigma,
        volatility = ref and sigma / ref or 1,
        n = #prices,
        days = nDays,
        age = age,
        credible = not not credible,
        confidence = confidence,
        lower = ref and math.max(0, math.floor(ref - 1.645 * sigma / math.sqrt(math.max(1, #prices)))) or nil,
    }
end
function M.fee(total, rate, minimum)
    return math.min(total, math.max(U.round(total * (rate or 0.05)), minimum or 0))
end
function M.sources(stats, recent, o)
    local sources = {
        market = stats and stats.lower,
        recent = recent,
        vendorsell = o.vendor,
        avgbuy = o.avgBuy,
        tsm = o.tsm,
        aux = o.aux,
    }
    if o.advice then
        sources.ewma = o.advice.prices.known and o.advice.prices.ewma or nil
        sources.pricefloor = o.advice.priceCap
        sources.winlower = o.advice.trades.winLower
        sources.profitfactor = o.advice.trades.profitFactor
        sources.salesperday = o.advice.rateKnown and o.advice.trades.rateLower or nil
    end
    return sources
end
function M.plan(input, history, o)
    o = o or {}
    local now = o.now or time()
    local s = M.stats(history, now)
    local p = {
        qty = 0,
        cost = 0,
        lots = {},
        reasons = {},
        stats = s,
        canBuy = false,
        profit = 0,
        roi = 0,
        mode = o.mode or "flip",
        complete = o.complete ~= false,
        advice = o.advice,
    }
    local rows = {}
    local totalQty = 0
    for _, v in ipairs(input or {}) do
        if
            U.finite(v.qty)
            and v.qty > 0
            and v.qty == math.floor(v.qty)
            and U.finite(v.unit)
            and v.unit > 0
            and U.finite(v.cost)
            and v.cost > 0
            and v.cost == math.floor(v.cost)
        then
            rows[#rows + 1] = v
            totalQty = totalQty + v.qty
        end
    end
    table.sort(rows, function(a, b)
        if a.unit == b.unit then
            return (a.auctionID or 0) < (b.auctionID or 0)
        end
        return a.unit < b.unit
    end)
    p.rows = rows
    p.totalQty = totalQty
    p.minimum = rows[1] and rows[1].unit
    local wallet = U.number(o.wallet, 0, 0)
    local free = math.max(0, wallet - U.number(o.reserved, 0, 0) - math.floor(wallet * (o.cashFloor or 0.20)))
    p.budget = math.max(
        0,
        math.floor(
            math.min(
                o.budget or free,
                free,
                wallet * (o.maxWallet or 0.10),
                o.absoluteCap or math.huge,
                math.max(0, (wallet + (o.stock or 0)) * (o.maxItem or 0.20) - (o.exposure or 0))
            )
        )
    )
    local roi = U.number(o.minROI, 0.25, 0, 10)
    local fee = U.number(o.fee, 0.05, 0, 0.5)
    local reserve = U.number(o.reserve, 0.02, 0, 0.5)
    p.extraCost = o.extraCost or 0
    p.feeRate = fee
    p.reserveRate = reserve
    p.minFee = o.minFee or 0
    p.minProfit = o.minProfit or 10000
    p.minROI = roi
    local target, limit
    if p.mode == "vendor" then
        target = U.number(o.vendor, nil, 1)
        limit = target and math.floor(target / (1 + roi))
    else
        local sources = M.sources(s, p.minimum, o)
        local explicit = o.sellPrice or F.Expr.eval(o.sellFormula or "90% market", sources)
        target = explicit and math.floor(explicit)
        if target and o.advice and o.advice.priceCap then
            target = math.min(target, o.advice.priceCap)
        end
        limit = o.buyLimit or F.Expr.eval(o.buyFormula or "70% market", sources)
        if not U.finite(limit) or limit <= 0 then
            limit = 0
            p.reasons[#p.reasons + 1] = "formula"
        end
        if target then
            limit = math.min(limit, target * (1 - fee - reserve) / (1 + roi))
        end
        if not s.credible then
            p.reasons[#p.reasons + 1] = "history"
        end
        if s.volatility > 0.30 then
            p.reasons[#p.reasons + 1] = "volatility"
        end
        if s.reference and p.minimum and p.minimum < s.reference * 0.6 and totalQty > 8 then
            p.reasons[#p.reasons + 1] = "crash"
        end
    end
    p.target = target
    p.buyLimit = limit or 0
    local maxQty = math.floor(U.number(o.maxQty, 100, 1, 100000))
    if o.advice and p.mode ~= "vendor" then
        maxQty = math.min(maxQty, o.advice.maxQty)
        if maxQty <= 0 then
            p.reasons[#p.reasons + 1] = "advisor:" .. o.advice.reason
        end
    end
    if p.mode ~= "vendor" then
        maxQty = math.min(maxQty, math.max(1, math.floor(totalQty * (o.maxShare or 0.15))))
    end
    if p.mode ~= "vendor" and o.velocity and o.velocity.known then
        maxQty = math.min(maxQty, math.max(0, math.floor(o.velocity.lower * 3 - (o.ownedQty or 0))))
    end
    if o.legacyUnresolved then
        p.reasons[#p.reasons + 1] = "legacy"
    end
    if not target or target <= 0 or not limit or limit <= 0 then
        p.reasons[#p.reasons + 1] = "exit"
    end
    for index, row in ipairs(rows) do
        if not limit or row.unit > limit or p.qty >= maxQty then
            break
        end
        local n = row.qty
        local cost = row.cost
        if o.commodity ~= false then
            n = math.min(n, maxQty - p.qty, math.floor((p.budget - p.cost) / row.unit))
            cost = n * row.unit
        elseif n > maxQty - p.qty or cost > p.budget - p.cost then
            break
        end
        if n < 1 or cost <= 0 or cost ~= math.floor(cost) then
            break
        end
        p.qty = p.qty + n
        p.cost = p.cost + cost
        p.maxUnit = row.unit
        p.lots[#p.lots + 1] = { qty = n, cost = cost, unit = row.unit, auctionID = row.auctionID, index = index }
        if n < row.qty then
            p.nextPrice = row.unit
            break
        end
        p.nextPrice = rows[index + 1] and rows[index + 1].unit
    end
    p.avg = p.qty > 0 and p.cost / p.qty or 0
    if p.qty > 0 and target then
        local gross = math.floor(p.qty * target)
        local cut = p.mode == "vendor" and 0 or M.fee(gross, fee, o.minFee)
        local riskReserve = p.mode == "vendor" and 0 or U.floor(gross * reserve)
        p.fee = cut
        p.reserve = riskReserve
        p.profit = gross - cut - riskReserve - p.cost - (o.extraCost or 0)
        p.roi = p.cost > 0 and p.profit / p.cost or 0
        local factor = p.mode == "vendor" and 1 or 1 - fee - reserve
        p.breakEven = factor > 0
                and math.ceil(
                    (p.cost + (o.extraCost or 0) + (p.mode == "vendor" and 0 or (o.minFee or 0))) / p.qty / factor
                )
            or nil
        p.liquidation = o.vendor and math.floor(p.qty * o.vendor - p.cost) or nil
        -- Risk-adjusted capital efficiency, not a promised expected return.
        p.confidence = p.mode == "vendor" and 1 or s.confidence
        p.downside = math.max(0, -(p.liquidation or -p.cost))
        p.score = (p.profit * p.confidence - p.downside * (1 - p.confidence)) / math.max(1, p.cost)
        if p.mode ~= "vendor" and o.velocity and o.velocity.known and o.velocity.lower > 0 then
            p.daysToExit = ((o.ownedQty or 0) + p.qty) / o.velocity.lower
            p.score = p.score / math.max(1, p.daysToExit)
        end
        if o.advice and o.advice.rateKnown and o.advice.trades.rateLower > 0 then
            p.daysToExit = ((o.ownedQty or 0) + p.qty) / o.advice.trades.rateLower
        end
    end
    if not p.complete then
        p.reasons[#p.reasons + 1] = "partial"
    end
    if p.qty == 0 then
        p.reasons[#p.reasons + 1] = "budget/price"
    end
    if p.profit < (o.minProfit or 10000) or p.roi < roi then
        p.reasons[#p.reasons + 1] = "margin"
    end
    p.canBuy = p.qty > 0 and p.profit > 0 and #p.reasons == 0
    return p
end
