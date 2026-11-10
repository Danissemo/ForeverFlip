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
-- Typical selling price from current listings, robust to both bargains and ambitious asks:
-- skip the cheapest 10% of volume, then take the volume median of the next 40% (10%..50%).
-- Ambitious high asks never enter the window; a few cheap bargains are trimmed away.
function M.marketValue(rows)
    local valid, total = {}, 0
    for _, r in ipairs(rows or {}) do
        if U.finite(r.unit) and r.unit > 0 and U.finite(r.qty) and r.qty > 0 then
            valid[#valid + 1] = r
            total = total + r.qty
        end
    end
    if total == 0 then
        return nil, 0, 0
    end
    table.sort(valid, function(a, b)
        return a.unit < b.unit
    end)
    local from, to = total * 0.10, total * 0.50
    local middle = (from + to) / 2
    local seen = 0
    for _, r in ipairs(valid) do
        seen = seen + r.qty
        if seen >= middle then
            return r.unit, #valid, total
        end
    end
    return valid[#valid].unit, #valid, total
end
-- Resale exit from the current listings alone (like a sniper). The exit is the market value, but
-- below the first competitor left after the bargains are bought, rounded down to whole silver because
-- the auction house only accepts silver prices. Needs a real market — at least 5 units in 3
-- listings — and an exit of at least 1 silver, otherwise nil.
-- Returns exit price, number of listings (liquidity) and the market value.
function M.ladder(rows, discount)
    local market, count, total = M.marketValue(rows)
    if not market or count < 3 or total < 5 then
        return nil
    end
    local exit = math.floor(market / 100) * 100
    local limit = exit * (discount or 0.744)
    local competitor
    for _, r in ipairs(rows) do
        if U.finite(r.unit) and r.unit > limit and (U.finite(r.qty) and r.qty > 0) then
            competitor = math.min(competitor or r.unit, r.unit)
        end
    end
    if competitor then
        exit = math.min(exit, math.floor((competitor - 1) / 100) * 100)
    end
    if exit < 100 then
        return nil
    end
    return exit, count, market
end
function M.fee(total, rate, minimum)
    return math.min(total, math.max(U.round(total * (rate or 0.05)), minimum or 0))
end
-- Shared integer-copper cash model. These are scenario costs, not sale guarantees.
function M.net(gross, fee, reserve, minimum)
    if not U.finite(gross) or gross < 0 then
        return nil
    end
    return gross - M.fee(gross, fee, minimum) - U.floor(gross * (reserve or 0))
end
function M.breakEven(cost, qty, fee, reserve, minimum, extraCost)
    fee, reserve, minimum, extraCost = fee or 0.05, reserve or 0, minimum or 0, extraCost or 0
    if
        not U.finite(cost)
        or cost < 0
        or not U.finite(qty)
        or qty <= 0
        or not U.finite(fee)
        or fee < 0
        or not U.finite(reserve)
        or reserve < 0
        or fee + reserve >= 1
        or not U.finite(minimum)
        or minimum < 0
        or not U.finite(extraCost)
        or extraCost < 0
    then
        return nil
    end
    local needed = cost + extraCost
    if not U.finite(needed) then
        return nil
    end
    -- Lower bounds allow for integer fee rounding; scan the few remaining copper exactly.
    local gross = math.max(0, (needed + minimum - 1) / (1 - reserve), (needed - 1.5) / (1 - fee - reserve))
    local price = math.max(0, math.floor(gross / qty))
    if not U.finite(price * qty) or price > 9007199254740990 then
        return nil
    end
    local steps = 0
    while M.net(U.floor(price * qty), fee, reserve, minimum) < needed do
        if price >= 9007199254740990 then
            return nil
        end
        if steps >= 64 then
            -- Near-total rates can put billions of copper inside the rounding interval.
            -- Use a conservative upper bound instead of scanning that interval.
            price = math.ceil(math.max((needed + minimum) / (1 - reserve), (needed + 0.5) / (1 - fee - reserve)) / qty)
            if
                not U.finite(price * qty)
                or price * qty > 9007199254740990
                or M.net(U.floor(price * qty), fee, reserve, minimum) < needed
            then
                return nil
            end
            return price
        end
        price = price + 1
        steps = steps + 1
    end
    return price
end
function M.priceStep(price, undercut)
    if not U.finite(price) or price <= 0 then
        return nil
    end
    return math.max(100, (undercut and (math.ceil(price / 100) - 1) or math.floor(price / 100)) * 100)
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
    if p.mode == "material" then
        -- Explicit procurement limits, without inventing resale income.
        local limit = U.finite(o.materialPrice) and o.materialPrice > 0 and o.materialPrice or 0
        local cap = math.max(0, math.floor(math.min(o.materialQty or 0, o.maxQty or 0)))
        p.buyLimit, p.material = limit, true
        for index, row in ipairs(rows) do
            if row.unit > limit or p.qty >= cap then
                break
            end
            local qty, cost = row.qty, row.cost
            if o.commodity ~= false then
                qty = math.min(qty, cap - p.qty, math.floor((p.budget - p.cost) / row.unit))
                cost = qty * row.unit
            elseif qty > cap - p.qty or p.cost + cost > p.budget then
                break
            end
            if qty < 1 or cost % 1 ~= 0 then
                break
            end
            p.qty, p.cost, p.maxUnit = p.qty + qty, p.cost + cost, row.unit
            p.lots[#p.lots + 1] = { qty = qty, cost = cost, unit = row.unit, auctionID = row.auctionID, index = index }
        end
        p.avg = p.qty > 0 and p.cost / p.qty or 0
        if not p.complete then
            p.reasons[#p.reasons + 1] = "partial"
        end
        if p.qty == 0 then
            p.reasons[#p.reasons + 1] = "budget/price"
        end
        if o.legacyUnresolved then
            p.reasons[#p.reasons + 1] = "legacy"
        end
        p.canBuy = p.qty > 0 and #p.reasons == 0
        return p
    end
    local roi = U.number(o.minROI, 0.25, 0, 10)
    local fee = U.number(o.fee, 0.05, 0, 0.5)
    local reserve = U.number(o.reserve, 0.02, 0, 0.5)
    p.extraCost = o.extraCost or 0
    p.feeRate = fee
    p.reserveRate = reserve
    p.minFee = o.minFee or 0
    p.minProfit = o.minProfit or 10000
    if o.adaptiveProfit and p.mode ~= "vendor" then
        -- A fixed gold floor rejects every deal for small wallets. Scale it to the money that can
        -- actually be used: 5% of the deal budget, never below 1 silver. The ROI rule still applies.
        p.minProfit = math.min(p.minProfit, math.max(100, math.floor(p.budget * 0.05)))
    end
    p.avgBuy = o.avgBuy
    p.minROI = roi
    local target, limit
    local ladderTarget, ladderListings, ladderReference
    if p.mode ~= "vendor" and not s.credible and o.ladder ~= false then
        ladderTarget, ladderListings, ladderReference = M.ladder(rows, (1 - fee - reserve) / (1 + roi))
    end
    if p.mode == "vendor" then
        target = U.number(o.vendor, nil, 1)
        limit = target and math.floor(target / (1 + roi))
    elseif ladderTarget then
        -- No price history yet: price the exit from what other sellers ask right now.
        local listings, reference
        target, listings, reference = ladderTarget, ladderListings, ladderReference
        p.listings = listings
        p.fairPrice = reference
        if U.finite(o.vendor) and o.vendor > target then
            target = math.floor(o.vendor)
        end
        limit = math.floor(target * (1 - fee - reserve) / (1 + roi))
        p.basis = "listings"
        p.reference = p.fairPrice or target
        local sources = M.sources(s, p.minimum, o)
        sources.market = sources.market or p.fairPrice or target
        local defaults = F.Store and F.Store.defaults or {}
        local customSell = o.sellFormula and o.sellFormula ~= defaults.sellFormula
        local customBuy = o.buyFormula and o.buyFormula ~= defaults.buyFormula
        if o.sellPrice ~= nil or customSell then
            target = o.sellPrice or F.Expr.eval(o.sellFormula, sources)
            if not U.finite(target) or target <= 0 then
                target = nil
                p.reasons[#p.reasons + 1] = "formula"
            end
        end
        if target and o.advice and U.finite(o.advice.priceCap) then
            target = math.min(target, o.advice.priceCap)
        end
        limit = target and math.floor(target * (1 - fee - reserve) / (1 + roi)) or 0
        if o.buyLimit ~= nil or customBuy then
            local explicit = o.buyLimit or F.Expr.eval(o.buyFormula, sources)
            if not U.finite(explicit) or explicit <= 0 then
                limit = 0
                p.reasons[#p.reasons + 1] = "formula"
            else
                limit = math.min(limit, explicit)
            end
        end
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
        p.profit = M.net(
            gross,
            p.mode == "vendor" and 0 or fee,
            p.mode == "vendor" and 0 or reserve,
            p.mode == "vendor" and 0 or p.minFee
        ) - p.cost - p.extraCost
        p.roi = p.cost > 0 and p.profit / p.cost or 0
        p.breakEven = M.breakEven(
            p.cost,
            p.qty,
            p.mode == "vendor" and 0 or fee,
            p.mode == "vendor" and 0 or reserve,
            p.mode == "vendor" and 0 or p.minFee,
            p.extraCost
        )
        p.liquidation = o.vendor and math.floor(p.qty * o.vendor - p.cost) or nil
        -- Risk-adjusted capital efficiency, not a promised expected return.
        -- Listing-based deals rank higher on busier markets: more listings mean faster sales.
        p.confidence = p.mode == "vendor" and 1
            or p.basis == "listings" and (0.25 + 0.25 * math.min(1, (p.listings or 0) / 20))
            or s.confidence
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
    if p.profit < p.minProfit or p.roi < roi then
        p.reasons[#p.reasons + 1] = "margin"
    end
    p.canBuy = p.qty > 0 and p.profit > 0 and #p.reasons == 0
    return p
end
-- Suggested unit price for posting. The auction house accepts whole silver only, so the price
-- undercuts the cheapest listing by one silver step (rounded down), but never goes below the price
-- that returns the own average cost after the fee and risk reserve (rounded up). Minimum 1 silver.
function M.salePrice(p, qty)
    if type(p) ~= "table" then
        return nil
    end
    qty = qty == nil and 1 or qty
    if not U.finite(qty) or qty < 1 or qty ~= math.floor(qty) then
        return nil
    end
    local floor = 0
    if U.finite(p.avgBuy) and p.avgBuy >= 0 then
        local exact = M.breakEven(p.avgBuy * qty, qty, p.feeRate, p.reserveRate, p.minFee, p.extraCost)
        if not exact then
            return nil
        end
        floor = math.max(100, math.ceil(exact / 100) * 100)
    end
    local price = M.priceStep(p.minimum, true) or M.priceStep(p.target)
    if not price then
        return floor > 0 and floor or nil, "cost"
    end
    if price < floor then
        return floor, "cost"
    end
    return price, U.finite(p.minimum) and "undercut" or "market"
end
