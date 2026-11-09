local F = ForeverFlip
local U = F.Util
local M = F.Market
local W = {}
F.Workbench = W

-- Cash scenarios, not probabilities of a fill or guarantees of a sale.
function W.stress(p, qty, cost, drop)
    if
        not p
        or not U.finite(qty)
        or qty < 1
        or qty % 1 ~= 0
        or not U.finite(cost)
        or cost < 0
        or not U.finite(p.target)
        or p.target <= 0
    then
        return nil
    end
    drop = U.number(drop, 0.20, 0, 0.95)
    if p.advice then
        drop = math.max(drop, p.advice.drop or 0)
    end
    local function net(price)
        local gross = math.floor(price * qty)
        if p.mode == "vendor" then
            return gross - cost - (p.extraCost or 0)
        end
        return gross
            - M.fee(gross, p.feeRate or 0.05, p.minFee or 0)
            - math.floor(gross * (p.reserveRate or 0))
            - cost
            - (p.extraCost or 0)
    end
    local base = net(p.target)
    local price = p.mode == "vendor" and p.target or math.floor(p.target * (1 - drop))
    local stressed = net(price)
    return { base = base, stressed = stressed, loss = math.max(0, -stressed), price = price, drop = drop }
end

local function prefixes(p, o)
    local targets = { [p.qty] = true }
    if p.kind == "commodity" then
        for _, f in ipairs({ 0.25, 0.50, 0.75 }) do
            targets[math.max(1, math.floor(p.qty * f))] = true
        end
    end
    local n = 0
    for i, lot in ipairs(p.lots or {}) do
        n = n + lot.qty
        if i <= 8 then
            targets[math.min(p.qty, n)] = true
        end
    end
    local options, seen = {}, {}
    for _, target in ipairs(U.sortedKeys(targets)) do
        local qty, cost = 0, 0
        for _, lot in ipairs(p.lots or {}) do
            if
                not U.finite(lot.qty)
                or lot.qty < 1
                or not U.finite(lot.cost)
                or lot.cost <= 0
                or not U.finite(lot.unit)
                or lot.unit <= 0
            then
                return {}
            end
            local take = math.min(lot.qty, target - qty)
            if p.kind ~= "commodity" and take < lot.qty then
                break
            end
            if take <= 0 then
                break
            end
            local charge = take == lot.qty and lot.cost or take * lot.unit
            if charge % 1 ~= 0 then
                return {}
            end
            qty = qty + take
            cost = cost + charge
            if qty >= target then
                break
            end
        end
        if qty > 0 and qty <= p.qty and cost > 0 and not seen[qty] then
            seen[qty] = true
            local s = W.stress(p, qty, cost, o.drop)
            local confidence = U.number(p.confidence, p.mode == "vendor" and 1 or 0, 0, 1)
            local carry = math.floor(cost * (o.carryRate or 0) * math.max(1, p.daysToExit or o.holdDays or 3))
            local utility = s and s.base * confidence - s.loss * (1 - confidence) - carry or 0
            if p.advice then
                utility = utility / math.max(1, p.daysToExit or p.advice.horizon)
            end
            if
                s
                and s.base > 0
                and utility > 0
                and s.base >= (p.minProfit or 0)
                and s.base / cost >= (p.minROI or 0)
            then
                options[#options + 1] = {
                    key = U.copy(p.key),
                    mode = p.mode,
                    kind = p.kind,
                    qty = qty,
                    cost = cost,
                    profit = s.base,
                    stressed = s.stressed,
                    loss = s.loss,
                    utility = utility,
                    confidence = confidence,
                    carry = carry,
                    group = p.group,
                    groupRemaining = p.groupRemaining,
                    at = p.at,
                    target = p.target,
                    advice = p.advice and U.copy(p.advice),
                    daysToExit = p.daysToExit,
                }
            end
        end
    end
    table.sort(options, function(a, b)
        if a.cost ~= b.cost then
            return a.cost < b.cost
        end
        return a.qty < b.qty
    end)
    return options
end

-- Multiple-choice budget/risk DP. Rounded-up resource bins are conservative.
-- One winner per bin means approximate search when group usage differs.
function W.allocate(input, o)
    o = o or {}
    local budget = math.floor(U.number(o.budget, 0, 0, 1e12))
    local risk = math.floor(U.number(o.riskCap, 0, 0, 1e12))
    local r = {
        budget = budget,
        riskCap = risk,
        cost = 0,
        profit = 0,
        loss = 0,
        stressed = 0,
        lines = {},
        considered = 0,
        excluded = 0,
        approximate = true,
        simulated = true,
        truncated = false,
        skipped = {},
    }
    if budget <= 0 then
        return r
    end
    local now = o.now or time()
    local seen = {}
    local candidates = {}
    for i, p in ipairs(input or {}) do
        if i > 2000 then
            r.truncated = true
            break
        end
        local key = p and U.key(p.key)
        local valid = key
            and not seen[key]
            and p.canBuy
            and p.complete ~= false
            and not p.family
            and U.finite(p.at)
            and p.at <= now
            and now - p.at <= (o.maxAge or 1800)
            and U.finite(p.qty)
            and p.qty > 0
            and p.qty % 1 == 0
            and U.finite(p.cost)
            and p.cost > 0
            and U.finite(p.target)
            and p.target > 0
        if valid then
            seen[key] = true
            if o.pauseItems and o.pauseItems[key] then
                r.excluded = r.excluded + 1
            else
                candidates[#candidates + 1] = p
            end
        else
            r.excluded = r.excluded + 1
        end
    end
    table.sort(candidates, function(a, b)
        local sa = (a.profit or 0) / math.max(1, a.cost)
        local sb = (b.profit or 0) / math.max(1, b.cost)
        if sa ~= sb then
            return sa > sb
        end
        return U.key(a.key) < U.key(b.key)
    end)
    if #candidates > 60 then
        r.truncated = true
        while #candidates > 60 do
            table.remove(candidates)
        end
    end
    local cashStep = math.max(1, math.ceil(budget / 128))
    local riskStep = math.max(1, math.ceil(risk / 8))
    local cashMax = math.floor(budget / cashStep)
    local riskMax = math.floor(risk / riskStep)
    r.cashStep = cashStep
    r.riskStep = riskStep
    local dp = { ["0:0"] = { score = 0, cashUnits = 0, riskUnits = 0, cost = 0, loss = 0, groups = {} } }
    for _, p in ipairs(candidates) do
        local options = prefixes(p, o)
        r.considered = r.considered + 1
        local nextDP = {}
        for k, state in pairs(dp) do
            nextDP[k] = state
        end
        -- Stable iteration, including exact ties, makes repeated plans reproducible.
        for _, stateKey in ipairs(U.sortedKeys(dp)) do
            local state = dp[stateKey]
            for _, option in ipairs(options) do
                local cashUnits = state.cashUnits + math.ceil(option.cost / cashStep)
                local riskUnits = state.riskUnits + (option.loss > 0 and math.ceil(option.loss / riskStep) or 0)
                local group = option.group
                local groupUsed = group and (state.groups[group] or 0) or 0
                if
                    cashUnits <= cashMax
                    and riskUnits <= riskMax
                    and state.cost + option.cost <= budget
                    and state.loss + option.loss <= risk
                    and (
                        not group
                        or not U.finite(option.groupRemaining)
                        or groupUsed + option.cost <= option.groupRemaining
                    )
                then
                    local key = cashUnits .. ":" .. riskUnits
                    local score = state.score + option.utility
                    local old = nextDP[key]
                    if not old or score > old.score or (score == old.score and state.cost + option.cost < old.cost) then
                        local groups = state.groups
                        if group then
                            groups = U.copy(groups)
                            groups[group] = groupUsed + option.cost
                        end
                        nextDP[key] = {
                            score = score,
                            cashUnits = cashUnits,
                            riskUnits = riskUnits,
                            cost = state.cost + option.cost,
                            loss = state.loss + option.loss,
                            groups = groups,
                            prev = state,
                            option = option,
                        }
                    end
                end
            end
        end
        dp = nextDP
    end
    local best = { score = 0, cost = 0, loss = 0 }
    for _, k in ipairs(U.sortedKeys(dp)) do
        local s = dp[k]
        if s.score > best.score or (s.score == best.score and s.cost < best.cost) then
            best = s
        end
    end
    while best and best.option do
        local item = U.copy(best.option)
        r.lines[#r.lines + 1] = item
        r.cost = r.cost + item.cost
        r.profit = r.profit + item.profit
        r.loss = r.loss + item.loss
        r.stressed = r.stressed + item.stressed
        best = best.prev
    end
    table.sort(r.lines, function(a, b)
        if a.utility ~= b.utility then
            return a.utility > b.utility
        end
        return U.key(a.key) < U.key(b.key)
    end)
    r.unused = budget - r.cost
    return r
end

function W.performance(summary, now)
    local out = {
        items = {},
        ranked = {},
        days = {},
        realized = summary.realized or 0,
        closed = 0,
        wins = 0,
        losses = 0,
        unknown = summary.unknown or 0,
    }
    local entries = {}
    for i, e in ipairs(summary.salesHistory or {}) do
        if U.finite(e.at) and e.at <= now then
            entries[#entries + 1] = { e = e, i = i }
        end
    end
    table.sort(entries, function(a, b)
        if a.e.at == b.e.at then
            return a.i < b.i
        end
        return a.e.at < b.e.at
    end)
    for _, entry in ipairs(entries) do
        local e = entry.e
        if
            U.finite(e.known)
            and e.known > 0
            and U.finite(e.qty)
            and e.qty >= e.known
            and U.finite(e.profit)
            and U.finite(e.total)
            and U.finite(e.fee)
        then
            local p = out.items[e.key]
                or {
                    key = e.key,
                    profit = 0,
                    cost = 0,
                    knownUnits = 0,
                    closed = 0,
                    wins = 0,
                    losses = 0,
                    lossStreak = 0,
                    fees = 0,
                }
            out.items[e.key] = p
            local proceeds = e.known == e.qty and e.total or math.floor(e.total * e.known / e.qty)
            local fee = e.known == e.qty and e.fee or math.floor(e.fee * e.known / e.qty)
            p.profit = p.profit + e.profit
            p.cost = p.cost + math.max(0, proceeds - fee - e.profit)
            p.knownUnits = p.knownUnits + e.known
            p.fees = p.fees + fee
            p.closed = p.closed + 1
            out.closed = out.closed + 1
            if e.profit > 0 then
                p.wins = p.wins + 1
                out.wins = out.wins + 1
                p.lossStreak = 0
            elseif e.profit < 0 then
                p.losses = p.losses + 1
                out.losses = out.losses + 1
                p.lossStreak = p.lossStreak + 1
            else
                p.lossStreak = 0
            end
            local day = math.floor(e.at / 86400)
            out.days[day] = (out.days[day] or 0) + e.profit
        end
    end
    for _, p in pairs(out.items) do
        p.roi = p.cost > 0 and p.profit / p.cost or nil
        p.pauseSuggested = p.lossStreak >= 3 and p.profit <= 0
        out.ranked[#out.ranked + 1] = p
    end
    table.sort(out.ranked, function(a, b)
        if a.profit ~= b.profit then
            return a.profit > b.profit
        end
        return a.key < b.key
    end)
    return out
end

function W.replay(input, o)
    o = o or {}
    local now = o.now or time()
    local capital = math.floor(U.number(o.capital, 1000000, 0, 1e12))
    local samples, seen = {}, {}
    for _, s in ipairs(input or {}) do
        if #samples >= 1000 then
            break
        end
        if
            not s.family
            and s.complete ~= false
            and U.finite(s.at)
            and s.at <= now
            and U.finite(s.price)
            and s.price > 0
        then
            local token = tostring(s.token or s.at)
            if not seen[token] then
                seen[token] = true
                samples[#samples + 1] = { at = s.at, price = math.floor(s.price), token = token, complete = true }
            end
        end
    end
    table.sort(samples, function(a, b)
        if a.at ~= b.at then
            return a.at < b.at
        end
        return a.price < b.price
    end)
    local out = { simulated = true, trainingInsufficient = true, samples = #samples, baseline = nil, robust = nil }
    local hold = U.number(o.hold, 86400, 3600, 30 * 86400)
    local maxGap = U.number(o.maxGap, 2 * 86400, 0, 7 * 86400)
    for _, strategy in ipairs({ "baseline", "robust" }) do
        local r = {
            name = strategy,
            cash = capital,
            pnl = 0,
            closed = 0,
            wins = 0,
            losses = 0,
            openCost = 0,
            firstEntry = nil,
            entries = 0,
        }
        local history, position = {}
        local trained = false
        for _, s in ipairs(samples) do
            if position and s.at >= position.at + hold and s.at <= position.at + hold + maxGap then
                local gross = math.floor(s.price * (1 - U.number(o.haircut, 0.05, 0, 0.95)))
                local net = gross
                    - M.fee(gross, U.number(o.fee, 0.05, 0, 0.5), U.number(o.minFee, 0, 0))
                    - math.floor(gross * U.number(o.reserve, 0, 0, 0.5))
                local pnl = net - position.cost
                r.cash = r.cash + net
                r.pnl = r.pnl + pnl
                r.closed = r.closed + 1
                if pnl > 0 then
                    r.wins = r.wins + 1
                elseif pnl < 0 then
                    r.losses = r.losses + 1
                end
                position = nil
            end
            local stats = M.stats(history, s.at)
            if stats.credible then
                trained = true
            end
            if not position and stats.credible and s.price <= r.cash then
                local buy = false
                if strategy == "baseline" then
                    buy = s.price <= stats.reference * (1 - U.number(o.discount, 0.30, 0, 0.95))
                else
                    local p = M.plan({ { qty = 1, unit = s.price, cost = s.price } }, history, {
                        wallet = r.cash,
                        budget = r.cash,
                        maxWallet = 1,
                        maxItem = 1,
                        cashFloor = 0,
                        maxQty = 1,
                        maxShare = 1,
                        fee = U.number(o.fee, 0.05, 0, 0.5),
                        minFee = o.minFee or 0,
                        reserve = o.reserve or 0,
                        minProfit = 0,
                        minROI = U.number(o.minROI, 0.25, 0, 10),
                        mode = "flip",
                        now = s.at,
                    })
                    buy = p.canBuy
                end
                if buy then
                    position = { at = s.at, cost = s.price }
                    r.cash = r.cash - s.price
                    r.entries = r.entries + 1
                    r.firstEntry = r.firstEntry or s.at
                end
            end
            history[#history + 1] = s
        end
        if position then
            r.openCost = position.cost
        end
        r.roi = capital > 0 and r.pnl / capital or nil
        out[strategy] = r
        if trained then
            out.trainingInsufficient = false
        end
    end
    return out
end
