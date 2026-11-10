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
        if id and purchasable ~= false and not extended and (price or 0) > 0 and (quantity or 0) > 0 then
            local key, h = historyFor(id, link)
            local market = h and type(h.scan) == "table" and h.scan.market
            if key and U.finite(market) then
                local item = U.parseKey(key)
                local today = type(h.days) == "table" and h.days[#h.days]
                local low = today and today.min
                ---@diagnostic disable-next-line: param-type-mismatch
                local reference = U.finite(low) and math.min(market, low) or market
                local exit = U.below(reference, item.kind)
                local unit = price / quantity
                local deposit = M.deposit(F.AH.vendorPrice(id), item.kind == "commodity" and quantity or 1)
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
