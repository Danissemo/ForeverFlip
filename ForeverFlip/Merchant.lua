-- Vendor -> auction house: items a merchant sells for less than they fetch on the auction house
-- (after the 5% cut and the deposit), with measured sales. Read when a merchant window opens; each
-- purchase is a click of the player.
local F = ForeverFlip
local U = F.Util
local M = F.Market
local V = {}
F.Merchant = V

local function historyFor(id, link)
    local history = F.Data.market(F.db, F.Engine.scope()).history
    local key = F.AH.keyFor(id, link)
    if key and history[key] then
        return key, history[key]
    end
    for _, k in ipairs({ U.key("commodity", id), U.key("item", id) }) do
        if history[k] then
            return k, history[k]
        end
    end
end

-- Merchant item info: C_MerchantFrame on modern clients (the global may be missing, as GetItemInfo
-- is on WoW Forever), the old global otherwise.
local function merchantInfo(i)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(i)
        if not info then
            return nil
        end
        return info.name, info.price, info.stackCount, info.numAvailable, info.isPurchasable, info.hasExtendedCost
    end
    ---@diagnostic disable-next-line: deprecated
    if GetMerchantItemInfo then
        ---@diagnostic disable-next-line: deprecated
        local name, _, price, quantity, available, purchasable, _, extended = GetMerchantItemInfo(i)
        return name, price, quantity, available, purchasable, extended
    end
end

-- Profitable merchant items, best profit per day first.
function V.offers(now)
    now = now or F.Engine.clock()
    local out = {}
    local budget = F.Deals.budget()
    local positions = F.Data.char(F.db, F.Engine.owner()).positions
    for i = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
        local name, price, quantity, available, purchasable, extended = merchantInfo(i)
        local link = GetMerchantItemLink and GetMerchantItemLink(i)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id and not extended and (price or 0) > 0 and (quantity or 0) > 0 then
            F.Crafting.rememberMerchantPrice(id, price / quantity)
        end
        if id and purchasable ~= false and not extended and (price or 0) > 0 and (quantity or 0) > 0 then
            local key, h = historyFor(id, link)
            local market = h and F.Market.usual(h)
            if key and U.finite(market) then
                local item = U.parseKey(key)
                local today = type(h.days) == "table" and h.days[#h.days]
                local low = today and today.min
                ---@diagnostic disable-next-line: param-type-mismatch
                local reference = U.finite(low) and math.min(market, low) or market
                local exit = U.below(reference, item.kind)
                local unit = price / quantity
                local each = M.net(exit, 1) - unit - M.unitDeposit(id, item.kind, nil, key, exit)
                local d = M.saleability(h, exit, now)
                -- As a resale on the auction house: the sales times the item's trust factor, and
                -- at most one day of them held, the stock already held included. Offered without
                -- it, every click (or visit) bought one more day of sales.
                local perDay = d.known and d.perDay * F.Deals.trust(key, now) or 0
                if each > 0 and perDay >= 0.5 then
                    local held = positions[key] and positions[key].qty or 0
                    local qty = math.max(1, math.floor(perDay)) - held
                    if (available or -1) >= 0 then
                        qty = math.min(qty, available * quantity)
                    end
                    qty = math.min(qty, math.floor(budget / unit))
                    if qty >= 1 then
                        out[#out + 1] = {
                            index = i,
                            key = key,
                            name = name,
                            link = link,
                            unit = unit,
                            stack = quantity,
                            exit = exit,
                            each = each,
                            perDay = perDay,
                            qty = qty,
                            profit = math.floor(each * qty),
                        }
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.profit ~= b.profit then
            return a.profit > b.profit
        end
        return a.key < b.key
    end)
    return out
end

-- Buys the suggested quantity of one offer (a click) and books it as stock for resale.
-- The units of one stack of the item (1 for items that do not stack).
local function stackOf(index, id)
    local max = tonumber(GetMerchantItemMaxStack and GetMerchantItemMaxStack(index))
    local itemStack = id and tonumber((select(8, U.itemInfo(id))))
    local stack = max and itemStack and math.min(max, itemStack) or max or itemStack or math.huge
    return math.max(1, stack)
end

-- Merchant transactions ----------------------------------------------------------------------------
-- Sales and purchases sent to a merchant are booked when the bags show them, never at the click:
-- the merchant may refuse a call (no room, sold out) or its answer may come late. A transaction
-- { kind = "sell" | "buy", qty, wait, seen(), onDone(n), onGiveUp(left, closing) } tells through
-- seen() how many of its units the bags show done; V.settle books the new ones (onDone) and gives up
-- on the rest after `wait` seconds (onGiveUp). A closing merchant ends the sales at once; purchases
-- still arrive after the window closed, so they keep their wait. V.settle runs on every bag change
-- (BAG_UPDATE_DELAYED), when the merchant closes, after a purchase and at every step of a sale.
V.pending = {}
V.BUY_WAIT = 10

local function preciseNow()
    return GetTime and GetTime() or F.Engine.clock()
end

function V.track(t)
    t.done, t.at = 0, preciseNow()
    V.pending[#V.pending + 1] = t
    return t
end

function V.settle(closing)
    if #V.pending == 0 then
        return -- every bag change in the game asks
    end
    local now, list = preciseNow(), V.pending
    V.pending = {}
    for _, t in ipairs(list) do
        local n = math.min(t.qty, math.max(0, t.seen())) - t.done
        if n > 0 then
            t.done = t.done + n
            t.onDone(n)
        end
        if t.done < t.qty then
            if closing and t.kind == "sell" or now - t.at >= t.wait then
                if t.onGiveUp then
                    t.onGiveUp(t.qty - t.done, closing)
                end
            else
                V.pending[#V.pending + 1] = t
            end
        end
    end
end

-- `n` units of a merchant purchase reached the bags: stock for resale, and the journal entry.
local function bookPurchase(w, n)
    local c = F.Data.char(F.db, F.Engine.owner())
    local cost = math.ceil(w.unit * n)
    F.Data.addPosition(c, w.key, w.name, n, cost, "flip", w.exit, F.Engine.clock())
    F.Data.log(c, {
        at = F.Engine.clock(),
        kind = "buy",
        key = w.key,
        name = w.name,
        qty = n,
        amount = cost,
        -- Without it a recount took the mode of the item's lot: a lot started by an own-use
        -- purchase up to 15 minutes before turned this resale into own use.
        mode = "flip",
        merchant = true, -- bought from a merchant: no auction house lot was taken (Scan.ownBought)
    })
    F.Engine.changed()
end

-- Buys the offer in calls of at most one stack each: one call for more than a stack ends in
-- "Internal Bag Error", and items that do not stack need a bag slot each. Never more than the
-- free slots of the general bags hold. Returns true and the units bought, or false and a reason.
function V.buy(offer)
    if not offer or not BuyMerchantItem then
        return false
    end
    local id = tonumber(offer.link and offer.link:match("item:(%d+)"))
    if not id then
        return false
    end
    local stack = stackOf(offer.index, id)
    local qty = math.min(offer.qty, F.AH.freeBagSlots() * stack)
    if qty < 1 then
        return false, "bags_full"
    end
    local cost = math.ceil(offer.unit * qty)
    if cost > F.Engine.wallet() then
        return false, "no_money"
    end
    -- Booked as the units reach the bags (merchant transactions above).
    local w = {
        key = offer.key,
        name = U.linkName(offer.link) or offer.name or offer.key,
        unit = offer.unit,
        exit = offer.exit,
    }
    local before = F.Crafting.have(id, true)
    V.track({
        kind = "buy",
        qty = qty,
        wait = V.BUY_WAIT,
        seen = function()
            return F.Crafting.have(id, true) - before
        end,
        onDone = function(n)
            bookPurchase(w, n)
        end,
    })
    local left = qty
    while left > 0 do
        local n = math.min(left, stack)
        BuyMerchantItem(offer.index, n)
        left = left - n
    end
    V.settle()
    return true, qty
end

-- What merchants really pay ---------------------------------------------------------------------------
-- WoW Forever's server pays less than the client's item data says for some items. The buyback list
-- shows what was paid for each of the last things sold, so every price there is remembered for the
-- account (F.db.vendorSeen) and used before the client's (F.AH.vendorPrice). The newest sale wins,
-- so a patch that changes a price is learned at the next sale. Damaged gear sells for less and the
-- list does not say how damaged it was: for gear a lower price only replaces a higher one when the
-- client's price changed (a patch), otherwise the highest seen is kept.
local function buybackInfo(i)
    if C_MerchantFrame and C_MerchantFrame.GetBuybackItemInfo then
        local ok, info = pcall(C_MerchantFrame.GetBuybackItemInfo, i)
        if ok and type(info) == "table" then
            return info.price, info.quantity or info.stackCount
        end
    end
    if GetBuybackItemInfo then
        local _, _, price, quantity = GetBuybackItemInfo(i)
        return price, quantity
    end
end

-- Sales to a merchant made by hand are booked too: the buyback list is compared with the one seen
-- before, and each new entry of an item in stock is a vendor sale (T.onVendorSale). Sales of the
-- Sell vendor deals button are booked by it and only matched here (V.expectSale).
V.buyback, V.expected = nil, {}

function V.expectSale(id, qty)
    V.expected[id] = (V.expected[id] or 0) + qty
end

function V.cancelExpectedSale(id, qty)
    V.expected[id] = math.max(0, (V.expected[id] or 0) - qty)
end

local function buybackEntries()
    local list = {}
    for i = 1, (GetNumBuybackItems and GetNumBuybackItems() or 0) do
        local link = GetBuybackItemLink and GetBuybackItemLink(i)
        local id = link and tonumber(link:match("item:(%d+)"))
        local price, quantity = buybackInfo(i)
        if id and U.finite(price) and U.finite(quantity) and quantity >= 1 then
            list[#list + 1] =
                { id = id, link = link, price = price, qty = quantity, sig = link .. "|" .. price .. "|" .. quantity }
        end
    end
    return list
end

-- A full buyback window can hide repeated identical sales. Bag decreases together with
-- exactly matching payment provide independent evidence; neither one alone is a sale.
local function bagSnapshot()
    local counts = {}
    for _, item in ipairs(F.AH.merchantItems()) do
        counts[item.key] = (counts[item.key] or 0) + item.count
    end
    return counts
end

-- MERCHANT_SHOW establishes the baseline; only later changes are booked.
function V.watchBuyback(first)
    local list, bags, money = buybackEntries(), bagSnapshot(), GetMoney and GetMoney()
    local now = F.Engine.clock()
    if first or not V.buyback then
        V.buyback, V.expected, V.inferred, V.pendingAt = list, {}, {}, nil
        V.bags, V.money, V.knownQty, V.knownMoney = bags, money, {}, 0
        return 0
    end
    local before, sales, prices, visibleQty = {}, {}, {}, {}
    for _, e in ipairs(V.buyback) do
        before[e.sig] = (before[e.sig] or 0) + 1
    end
    local visibleMoney = 0
    for _, e in ipairs(list) do
        local key = F.AH.keyFor(e.id, e.link)
        if key then
            local each = math.floor(e.price / e.qty)
            if prices[key] and prices[key].each ~= each then
                prices[key].ambiguous = true -- durability can change a gear item's vendor price
            else
                prices[key] = prices[key] or { id = e.id, each = each }
            end
        end
        if (before[e.sig] or 0) > 0 then
            before[e.sig] = before[e.sig] - 1
        elseif key then
            -- Bags and money may prove the sale before its new buyback row arrives.
            -- Consume that evidence once when the delayed row becomes visible.
            local qty, each = e.qty, math.floor(e.price / e.qty)
            for _, credit in ipairs(V.inferred or {}) do
                if credit.key == key and credit.each == each and now - credit.at <= 5 then
                    local n = math.min(qty, credit.qty)
                    qty, credit.qty = qty - n, credit.qty - n
                end
            end
            sales[#sales + 1] = { key = key, id = e.id, qty = qty, each = each }
            visibleQty[key] = (visibleQty[key] or 0) + qty
            visibleMoney = visibleMoney + qty * each
        end
    end
    V.knownQty = V.knownQty or {}
    V.knownMoney = (V.knownMoney or 0) + visibleMoney
    for key, n in pairs(visibleQty) do
        V.knownQty[key] = (V.knownQty[key] or 0) + n
    end
    if #list >= 12 and V.bags and money and V.money and (not V.pendingAt or now - V.pendingAt <= 5) then
        local missing, total = {}, 0
        for key, p in pairs(prices) do
            local n = (V.bags[key] or 0) - (bags[key] or 0) - (V.knownQty[key] or 0)
            if n > 0 and p.each > 0 and not p.ambiguous then
                missing[key], total = n, total + n * p.each
            end
        end
        if total > 0 and money - V.money == V.knownMoney + total then
            for key, n in pairs(missing) do
                local p = prices[key]
                sales[#sales + 1] = { key = key, id = p.id, qty = n, each = p.each }
                V.inferred = V.inferred or {}
                V.inferred[#V.inferred + 1] = { key = key, each = p.each, qty = n, at = now }
                V.knownQty[key] = (V.knownQty[key] or 0) + n
            end
            V.knownMoney = V.knownMoney + total
        end
    end
    local settled = money and V.money and money - V.money == V.knownMoney
    for key, n in pairs(V.knownQty) do
        if (V.bags[key] or 0) - (bags[key] or 0) ~= n then
            settled = false
        end
    end
    -- A bag decrease with delayed payment must retain its original baseline too.
    for key in pairs(prices) do
        if (V.bags[key] or 0) - (bags[key] or 0) > (V.knownQty[key] or 0) then
            settled = false
        end
    end
    if not settled then
        V.pendingAt = V.pendingAt or now
    end
    if settled or V.pendingAt and now - V.pendingAt > 5 then
        V.pendingAt = nil
        V.bags, V.money, V.knownQty, V.knownMoney = bags, money, {}, 0
    end
    local booked = 0
    for _, e in ipairs(sales) do
        local n = math.min(V.expected[e.id] or 0, e.qty)
        V.expected[e.id], e.qty = (V.expected[e.id] or 0) - n, e.qty - n
        if e.qty > 0 and F.Trade.onVendorSale(e.key, e.qty, e.each) then
            booked = booked + 1
        end
    end
    local credits = {}
    for _, credit in ipairs(V.inferred or {}) do
        if credit.qty > 0 and now - credit.at <= 5 then
            credits[#credits + 1] = credit
        end
    end
    V.inferred = credits
    V.buyback = list
    return booked
end

function V.learnBuyback(now)
    local seen = F.db and F.db.vendorSeen
    if not seen or not GetNumBuybackItems or not GetBuybackItemLink then
        return 0
    end
    now = now or F.Engine.clock()
    local learned = 0
    for i = 1, (GetNumBuybackItems() or 0) do
        local link = GetBuybackItemLink(i)
        local id = link and tonumber(link:match("item:(%d+)"))
        local price, quantity = buybackInfo(i)
        if id and U.finite(price) and price >= 0 and U.finite(quantity) and quantity >= 1 then
            local each = math.floor(price / quantity)
            local client = F.AH.clientVendorPrice(id)
            local old = seen[id]
            local keep = type(old) == "table"
                and F.AH.kindOf(id) == "gear"
                and old.c == client
                and U.finite(old.p)
                and old.p > each
            if not keep and (type(old) ~= "table" or old.p ~= each or old.c ~= client) then
                seen[id] = { p = each, t = now, c = client }
                learned = learned + 1
            elseif type(old) == "table" then
                old.t = now
            end
        end
    end
    return learned
end

-- Learned prices that differ from the client's: { { id, seen, client } }, newest first.
function V.differences()
    local out = {}
    for id, r in pairs(F.db and F.db.vendorSeen or {}) do
        if type(r) == "table" and r.c and r.p ~= r.c then
            out[#out + 1] = { id = id, seen = r.p, client = r.c, at = r.t or 0 }
        end
    end
    table.sort(out, function(a, b)
        return a.at > b.at
    end)
    return out
end
