local F = ForeverFlip
local U = F.Util
local A = {}
F.Advisor = A
local DAY = 86400
A.profiles = {
    safe = { fraction = 0.01, horizon = 2, roi = 0.35, drop = 0.25 },
    balanced = { fraction = 0.03, horizon = 3, roi = 0.25, drop = 0.20 },
}
local function quantile(values, q)
    local v = {}
    for i, x in ipairs(values) do
        v[i] = x
    end
    table.sort(v)
    return v[math.max(1, math.ceil(#v * q))]
end

-- Balance observation days before smoothing, so repeated scans cannot add days.
function A.prices(history, now)
    local buckets, seen = {}, {}
    for _, s in ipairs(history or {}) do
        if
            U.finite(s.at)
            and s.at <= now
            and s.at >= now - 14 * DAY
            and U.finite(s.price)
            and s.price > 0
            and not s.family
            and s.complete ~= false
        then
            local token = tostring(s.token or math.floor(s.at / 600))
            if not seen[token] then
                seen[token] = true
                local d = math.floor(s.at / DAY)
                buckets[d] = buckets[d] or {}
                table.insert(buckets[d], s.price)
            end
        end
    end
    local days = U.sortedKeys(buckets)
    local daily = {}
    for _, d in ipairs(days) do
        daily[#daily + 1] = U.median(buckets[d])
    end
    local out = { known = false, days = #days, drop = 0.20 }
    if #days < 3 then
        return out
    end
    local median = U.median(daily)
    local deviations = {}
    for i, p in ipairs(daily) do
        deviations[i] = math.abs(p - median)
    end
    local sigma = 1.4826 * (U.median(deviations) or 0)
    local upper = median + math.max(3 * sigma, 0.10 * median)
    local ewma = math.min(daily[1], upper)
    local losses = {}
    for i = 2, #daily do
        local alpha = 1 - 2 ^ (-(days[i] - days[i - 1]) / 2)
        ewma = alpha * math.min(daily[i], upper) + (1 - alpha) * ewma
        if daily[i] < daily[i - 1] then
            losses[#losses + 1] = 1 - daily[i] / daily[i - 1]
        end
    end
    out.known = now - days[#days] * DAY <= 3 * DAY
    out.ewma = ewma
    out.q25 = quantile(daily, 0.25)
    out.trend = daily[#daily] / daily[1] - 1
    out.priceCap = out.known and math.floor(math.min(ewma, out.q25, daily[#daily])) or nil
    out.drop = math.max(0.10, math.min(0.50, quantile(losses, 0.80) or 0.20))
    return out
end

-- Win statistics describe fully costed closed AH receipts, never fill chance.
function A.trades(history, key, now, since)
    local r = { n = 0, wins = 0, losses = 0, gains = 0, loss = 0, units = 0, days = 0, rateKnown = false }
    local days, rateDays, roiDays = {}, {}, {}
    local roiWins, roiLosses, gainROI, lossROI = 0, 0, 0, 0
    for _, s in ipairs(history or {}) do
        if
            s.key == key
            and s.kind == "sell"
            and U.finite(s.at)
            and s.at <= now
            and s.at >= now - 30 * DAY
            and U.finite(s.qty)
            and s.qty > 0
            and s.known == s.qty
            and U.finite(s.profit)
            and U.finite(s.total)
            and U.finite(s.fee)
        then
            if s.profit > 0 then
                r.wins = r.wins + 1
                r.gains = r.gains + s.profit
            elseif s.profit < 0 then
                r.losses = r.losses + 1
                r.loss = r.loss - s.profit
            end
            local cost = s.total - s.fee - s.profit
            if cost > 0 and s.profit ~= 0 then
                roiDays[math.floor(s.at / DAY)] = true
                if s.profit > 0 then
                    roiWins = roiWins + 1
                    gainROI = gainROI + s.profit / cost
                else
                    roiLosses = roiLosses + 1
                    lossROI = lossROI - s.profit / cost
                end
            end
            days[math.floor(s.at / DAY)] = true
            if s.at >= now - 14 * DAY and U.finite(since) and s.at >= since then
                r.units = r.units + s.qty
                rateDays[math.floor(s.at / DAY)] = true
            end
        end
    end
    for _ in pairs(days) do
        r.days = r.days + 1
    end
    local saleDays = 0
    for _ in pairs(rateDays) do
        saleDays = saleDays + 1
    end
    r.n = r.wins + r.losses
    if r.n > 0 then
        local z = 1.645
        local n = r.n
        local p = r.wins / n
        r.winRate = p
        r.winLower =
            math.max(0, (p + z * z / (2 * n) - z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))) / (1 + z * z / n))
    end
    r.profitFactor = r.loss > 0 and r.gains / r.loss or nil
    local roiN = roiWins + roiLosses
    local roiDayCount = 0
    for _ in pairs(roiDays) do
        roiDayCount = roiDayCount + 1
    end
    if roiN >= 10 and roiDayCount >= 3 and roiWins > 0 and roiLosses > 0 then
        local z = 1.645
        local p = roiWins / roiN
        local lower = (p + z * z / (2 * roiN) - z * math.sqrt(p * (1 - p) / roiN + z * z / (4 * roiN * roiN)))
            / (1 + z * z / roiN)
        local payoff = (gainROI / roiWins) / (lossROI / roiLosses)
        r.payoff = payoff
        r.kelly = math.max(0, math.min(1, lower - (1 - lower) / payoff))
    end
    if U.finite(since) and since < now then
        r.observedDays = math.min(14, (now - since) / DAY)
        r.daily = r.units / math.max(1, r.observedDays)
        r.rateLower = math.max(0, (r.units - 1.645 * math.sqrt(r.units)) / math.max(1, r.observedDays))
        r.rateKnown = r.observedDays >= 2 and saleDays >= 2 and r.units >= 5
    end
    return r
end

function A.parameters(history, sales, since, now, profile, wallet, owned, key)
    local config = A.profiles[profile] or A.profiles.balanced
    local prices = A.prices(history, now)
    local trades = A.trades(sales, key, now, since)
    local fraction = config.fraction
    if trades.kelly then
        fraction = math.min(fraction, trades.kelly * 0.25)
    end
    local out = {
        prices = prices,
        trades = trades,
        priceCap = prices.priceCap,
        maxBudget = math.floor(wallet * fraction),
        minROI = config.roi,
        horizon = config.horizon,
        drop = math.max(config.drop, prices.drop),
        rateKnown = trades.rateKnown,
    }
    if trades.rateKnown then
        out.maxQty = math.max(0, math.floor(trades.rateLower * config.horizon - (owned or 0)))
        out.reason = out.maxQty > 0 and "measured" or "stock_limit"
    else
        out.maxQty = math.max(0, 1 - (owned or 0))
        out.reason = "probe"
        if (owned or 0) > 0 and trades.observedDays and trades.observedDays >= 7 and trades.units == 0 then
            out.maxQty = 0
            out.reason = "no_sales"
        end
    end
    if fraction == 0 then
        out.reason = "loss_history"
    end
    return out
end
