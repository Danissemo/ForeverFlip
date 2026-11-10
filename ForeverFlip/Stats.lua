local F = ForeverFlip
local U = F.Util
local L = F.Locale.text
local S = {}
F.Stats = S
local DAY = 86400
-- Sales statistics for the current character and market, computed from the ledger summary.
-- Recorded sale receipts count when booked, including verified mail invoices; collection into the wallet may happen later.
function S.compute(c, now)
    now = now or c.api.clock()
    local r = c:summary()
    local periods = {
        { id = "today", label = L("Today", "Today"), from = math.floor(now / DAY) * DAY },
        { id = "week", label = L("7 days", "7 days"), from = now - 7 * DAY },
        { id = "month", label = L("30 days", "30 days"), from = now - 30 * DAY },
    }
    for _, p in ipairs(periods) do
        p.sales, p.units, p.revenue, p.profit, p.cost, p.heldSum, p.heldUnits = 0, 0, 0, 0, 0, 0, 0
        p.buys, p.spent, p.expenses = 0, 0, 0
    end
    local byKey = {}
    for _, sale in ipairs(r.salesHistory or {}) do
        local at = sale.at or 0
        for _, p in ipairs(periods) do
            if at >= p.from and at <= now then
                p.sales = p.sales + 1
                p.units = p.units + (sale.qty or 0)
                p.revenue = p.revenue + (sale.total or 0)
                p.profit = p.profit + (sale.profit or 0)
                p.cost = p.cost + (sale.cost or 0)
                if sale.held and (sale.known or 0) > 0 then
                    p.heldSum = p.heldSum + sale.held * sale.known
                    p.heldUnits = p.heldUnits + sale.known
                end
            end
        end
        if at >= now - 30 * DAY and at <= now and sale.key then
            local k = byKey[sale.key] or { key = sale.key, profit = 0, units = 0, sales = 0 }
            k.profit, k.units, k.sales = k.profit + (sale.profit or 0), k.units + (sale.qty or 0), k.sales + 1
            byKey[sale.key] = k
        end
    end
    for _, e in ipairs(F.Ledger.effective(c.db.ledger, c.api.owner(), c.api.scope())) do
        if e.kind == "buy" and e.owner == c.api.owner() and e.scope == c.api.scope() then
            for _, p in ipairs(periods) do
                if (e.at or 0) >= p.from and (e.at or 0) <= now then
                    p.buys, p.spent = p.buys + 1, p.spent + (e.total or 0)
                end
            end
        elseif e.kind == "expense" then
            for _, p in ipairs(periods) do
                if (e.at or 0) >= p.from and (e.at or 0) <= now then
                    p.expenses = p.expenses + (e.total or 0)
                end
            end
        end
    end
    for _, p in ipairs(periods) do
        -- Keep profit as closed-trade profit for the existing UI; expenses are separate cash events.
        p.closedProfit, p.netProfit = p.profit, p.profit - p.expenses
        p.roi = p.cost > 0 and p.profit / p.cost or nil
        p.heldDays = p.heldUnits > 0 and p.heldSum / p.heldUnits / DAY or nil
    end
    local top, worst = {}, {}
    for _, k in pairs(byKey) do
        top[#top + 1] = k
        if k.profit < 0 then
            worst[#worst + 1] = k
        end
    end
    table.sort(top, function(a, b)
        if a.profit == b.profit then
            return a.key < b.key
        end
        return a.profit > b.profit
    end)
    table.sort(worst, function(a, b)
        return a.profit < b.profit
    end)
    local stale, staleValue = 0, 0
    for _, position in ipairs(r.positions or {}) do
        if now - (position.at or now) >= 3 * DAY then
            stale, staleValue = stale + 1, staleValue + position.cost
        end
    end
    local month = periods[3]
    local tips = {}
    if month.sales == 0 then
        tips[#tips + 1] = L(
            "No sales recorded yet. Open your mailbox — sale letters are recorded automatically and statistics appear here.",
            "No sales recorded yet. Open your mailbox — sale letters are recorded automatically and statistics appear here."
        )
    end
    if top[1] and top[1].profit > 0 then
        local id = U.fromKey(top[1].key)
        tips[#tips + 1] = string.format(
            L(
                "Your best earner is %s (+%s in 30 days) — add it to your watchlist.",
                "Your best earner is %s (+%s in 30 days) — add it to your watchlist."
            ),
            id and U.name(id.itemID) or top[1].key,
            U.money(top[1].profit)
        )
    end
    if stale > 0 then
        tips[#tips + 1] = string.format(
            L(
                "%d items have been held over 3 days (%s) — lower the price or sell to a vendor.",
                "%d items have been held over 3 days (%s) — lower the price or sell to a vendor."
            ),
            stale,
            U.money(staleValue)
        )
    end
    if worst[1] then
        local id = U.fromKey(worst[1].key)
        tips[#tips + 1] = string.format(
            L(
                "Lost on %s: %s — avoid buying it again.",
                "Lost on %s: %s — avoid buying it again."
            ),
            id and U.name(id.itemID) or worst[1].key,
            U.money(-worst[1].profit)
        )
    end
    if month.roi and month.sales >= 5 and month.roi < 0.1 then
        tips[#tips + 1] = L(
            "Average return is below 10% — raise the minimum return in Settings → Trading limits.",
            "Average return is below 10% — raise the minimum return in Settings → Trading limits."
        )
    end
    if month.heldDays then
        tips[#tips + 1] = string.format(
            L(
                "On average an item sells in %.1f days.",
                "On average an item sells in %.1f days."
            ),
            month.heldDays
        )
    end
    return { periods = periods, top = top, worst = worst, stale = stale, staleValue = staleValue, tips = tips }
end
