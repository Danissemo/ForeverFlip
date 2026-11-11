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
                local deposit = M.deposit(F.AH.clientVendorPrice(id), item.kind == "commodity" and quantity or 1)
                local each = M.net(exit, 1) - unit - deposit / (item.kind == "commodity" and quantity or 1)
                local d = M.saleability(h, exit, now)
                if each > 0 and d.known and d.perDay >= 0.5 then
                    local qty = math.max(1, math.floor(d.perDay))
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
                            perDay = d.perDay,
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
function V.buy(offer)
    if not offer or not BuyMerchantItem then
        return false
    end
    local cost = math.ceil(offer.unit * offer.qty)
    if cost > F.Engine.wallet() then
        return false, "no_money"
    end
    BuyMerchantItem(offer.index, offer.qty)
    local c = F.Data.char(F.db, F.Engine.owner())
    local name = U.linkName(offer.link) or offer.name or offer.key
    F.Data.addPosition(c, offer.key, name, offer.qty, cost, "flip", offer.exit, F.Engine.clock())
    F.Data.log(c, { at = F.Engine.clock(), kind = "buy", key = offer.key, name = name, qty = offer.qty, amount = cost })
    F.Engine.changed()
    return true
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

-- MERCHANT_SHOW: the list as it is; MERCHANT_UPDATE: the new entries are sales.
function V.watchBuyback(first)
    local list = buybackEntries()
    if first or not V.buyback then
        V.buyback, V.expected = list, {}
        return 0
    end
    local before = {}
    for _, e in ipairs(V.buyback) do
        before[e.sig] = (before[e.sig] or 0) + 1
    end
    local booked = 0
    for _, e in ipairs(list) do
        if (before[e.sig] or 0) > 0 then
            before[e.sig] = before[e.sig] - 1
        else
            local qty = e.qty
            local expected = V.expected[e.id] or 0
            if expected > 0 then
                local n = math.min(expected, qty)
                V.expected[e.id], qty = expected - n, qty - n
            end
            local key = qty > 0 and F.AH.keyFor(e.id, e.link)
            if key and F.Trade.onVendorSale(key, qty, math.floor(e.price / e.qty)) then
                booked = booked + 1
            end
        end
    end
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
