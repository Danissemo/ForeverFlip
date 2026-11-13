-- Shopping list and ignored items. A shopping entry is an item the player wants at or below a
-- price ("Linen Cloth up to 30c"); any lot at or below it becomes a "shop" deal, found by the full
-- scan, the sniper and the player's own searches like any other deal. Ignored items never become
-- deals and are skipped by the sniper and Post all.
local F = ForeverFlip
local U = F.Util
local S = {}
F.Shopping = S

local function list()
    F.db.shopping = type(F.db.shopping) == "table" and F.db.shopping or {}
    return F.db.shopping
end

local function blockedList()
    F.db.blocked = type(F.db.blocked) == "table" and F.db.blocked or {}
    return F.db.blocked
end

-- Item key of a link or an item name the game knows; nil while the item is not loaded.
function S.resolve(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end
    local id = tonumber(text:match("item:(%d+)"))
    local link = id and text
    if not id then
        local _, found = U.itemInfo(text)
        link = found
        id = found and tonumber(found:match("item:(%d+)"))
    end
    if not id then
        return nil
    end
    local key = F.AH.keyFor(id, link)
    return key, U.linkName(link) or text
end

-- entry = { max = copper per unit, qty = units wanted (nil: any), name }
-- `resell` (optional): the price the units are resold at (a buy out against an undercut, from
-- Selling -> Undercuts). Such an entry counts down as units are bought and goes when done.
function S.add(key, max, qty, name, resell)
    if not U.parseKey(key) or not U.finite(max) or max <= 0 then
        return false
    end
    list()[key] = {
        max = math.floor(max),
        qty = U.finite(qty) and qty > 0 and math.floor(qty) or nil,
        name = name,
        resell = U.finite(resell) and resell > 0 and math.floor(resell) or nil,
    }
    F.Engine.changed()
    return true
end

-- Units of the item were bought: a buy-out entry counts them down.
function S.bought(key, qty)
    local e = S.orders[key] or F.db and list()[key]
    if not e or not e.resell or not e.qty then
        return
    end
    e.qty = e.qty - (qty or 1)
    if e.qty <= 0 then
        if S.orders[key] == e then
            S.orders[key] = nil
        else
            S.remove(key)
        end
    end
end

function S.remove(key)
    list()[key] = nil
    if F.Deals.get(key) and F.Deals.get(key).mode == "shop" then
        F.Deals.remove(key)
    end
    F.Engine.changed()
end

-- Session-only purchase intents from Selling/Undercuts never overwrite saved shopping rules.
S.orders = {}
function S.orderEntry(key)
    return S.orders[key]
end
function S.order(key, max, qty, name, resell)
    if not U.parseKey(key) or not U.finite(max) or max <= 0 or not U.finite(qty) or qty < 1 then
        return false
    end
    S.orders[key] = { max = math.floor(max), qty = math.floor(qty), name = name, resell = resell, origin = "undercuts" }
    return true
end
function S.entry(key)
    return S.orders[key] or F.db and list()[key]
end

function S.maxPrice(key)
    local e = F.db and list()[key]
    return e and e.max
end

function S.keys()
    local out = {}
    if not F.db then
        return out
    end
    for key in pairs(list()) do
        out[#out + 1] = key
    end
    table.sort(out)
    return out
end

function S.block(key, name)
    blockedList()[key] = name or key
    F.Deals.remove(key)
    F.Engine.changed()
end

function S.unblock(key)
    blockedList()[key] = nil
    F.Engine.changed()
end

function S.blocked(key)
    return F.db ~= nil and key ~= nil and blockedList()[key] ~= nil
end

function S.blockedKeys()
    local out = {}
    if not F.db then
        return out
    end
    for key, name in pairs(blockedList()) do
        out[#out + 1] = { key = key, name = name }
    end
    table.sort(out, function(a, b)
        return tostring(a.name) < tostring(b.name)
    end)
    return out
end

-- A shopping deal from listings sorted cheapest first: every unit at or below the wanted price,
-- up to the wanted quantity and the budget. "Profit" is the saving against the wanted price.
function S.evaluate(rows, key, budget)
    local e = S.entry(key)
    if not e then
        return nil
    end
    local item = U.parseKey(key)
    local qty, cost, saving, used = 0, 0, 0, {}
    for _, r in ipairs(rows) do
        if r.unit > e.max then
            break
        end
        local take = r.qty
        if e.qty then
            take = math.min(take, e.qty - qty)
        end
        if cost + take * r.unit > budget then
            take = math.floor((budget - cost) / r.unit)
        end
        if take < 1 then
            break
        end
        qty, cost, saving = qty + take, cost + take * r.unit, saving + take * (e.max - r.unit)
        used[#used + 1] = { unit = r.unit, qty = take, auctionID = r.auctionID }
        if item and item.kind ~= "commodity" or (e.qty and qty >= e.qty) then
            break -- items and gear: one auction per purchase
        end
    end
    if qty < 1 then
        return nil
    end
    local profit = saving
    if e.resell then
        profit = F.Market.net(e.resell, qty) - cost
    end
    return {
        mode = "shop",
        qty = qty,
        cost = cost,
        exit = e.resell or e.max,
        profit = profit,
        roi = cost > 0 and profit / cost or 0,
        maxUnit = used[#used].unit,
        lots = used,
        resell = e.resell,
        wanted = e.qty,
    }
end
