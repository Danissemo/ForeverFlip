-- Crafting for profit. When a profession window opens, the recipes are read from the game
-- (C_TradeSkillUI.GetRecipeSchematic works on WoW Forever) and saved per character. At the auction
-- house each recipe is priced: materials at the cheaper of the usual auction price and the price a
-- merchant asked (remembered from merchant windows); the product at its usual auction price after
-- the cut and the deposit, or the vendor price. Recipes are listed by profit with the product's
-- measured sales; "Shop materials" puts the materials on the shopping list.
local F = ForeverFlip
local U = F.Util
local C = {}
F.Crafting = C

local function recipes()
    local c = F.Data.char(F.db, F.Engine.owner())
    c.recipes = type(c.recipes) == "table" and c.recipes or {}
    return c.recipes
end

-- Reads every recipe of the open profession window: { name, out = itemID, n = units made,
-- r = { { itemID, count }, ... } }.
function C.learn()
    local T = C_TradeSkillUI
    if not F.db or not T or not T.GetAllRecipeIDs or not T.GetRecipeSchematic then
        return 0
    end
    local ok, ids = pcall(T.GetAllRecipeIDs)
    if not ok or type(ids) ~= "table" then
        return 0
    end
    local saved, n = recipes(), 0
    for _, id in ipairs(ids) do
        local got, s = pcall(T.GetRecipeSchematic, id, false)
        if got and type(s) == "table" and (s.outputItemID or 0) > 0 then
            local r = {}
            for _, slot in ipairs(s.reagentSlotSchematics or {}) do
                local reagent = slot.reagents and slot.reagents[1]
                if reagent and reagent.itemID and slot.required ~= false and (slot.quantityRequired or 0) > 0 then
                    r[#r + 1] = { reagent.itemID, slot.quantityRequired }
                end
            end
            if #r > 0 then
                saved[id] = { name = s.name, out = s.outputItemID, n = math.max(1, s.quantityMin or 1), r = r }
                n = n + 1
            end
        end
    end
    F.Engine.changed()
    return n
end

-- Prices merchants ask, remembered from merchant windows (per unit).
function C.rememberMerchantPrice(id, unit)
    if F.db and U.finite(unit) and unit > 0 then
        F.db.merchantPrices = F.db.merchantPrices or {}
        F.db.merchantPrices[id] = math.floor(unit + 0.5)
    end
end

local function usual(history, id)
    local kind = F.AH.kindOf(id)
    local h = kind and kind ~= "gear" and history[U.key(kind, id)]
    return h and h.scan and U.finite(h.scan.market) and h.scan.market or nil, h
end

-- Cost of one unit of a material: the cheaper of the auction house and a merchant.
function C.materialCost(history, id)
    local ah = usual(history, id)
    local merchant = F.db.merchantPrices and F.db.merchantPrices[id]
    if ah and merchant then
        return math.min(ah, merchant)
    end
    return ah or merchant
end

-- Every saved recipe with a known cost, best profit first: { id, name, out, n, cost, value, profit,
-- perDay, route = "auction" | "vendor", missing = itemID of a material without a price }.
function C.profits(now)
    now = now or F.Engine.clock()
    local history = F.Data.market(F.db, F.Engine.scope()).history
    local out = {}
    for id, r in pairs(recipes()) do
        local cost, missing = 0, nil
        for _, m in ipairs(r.r) do
            local unit = C.materialCost(history, m[1])
            if not unit then
                missing = m[1]
                break
            end
            cost = cost + unit * m[2]
        end
        local row = { id = id, name = r.name, out = r.out, n = r.n, missing = missing }
        if not missing then
            local price, h = usual(history, r.out)
            local vendor = F.AH.vendorPrice(r.out)
            local auction, perDay
            if price then
                local s = F.Market.saleability(h, price, now)
                perDay = s.known and s.perDay or nil
                auction = F.Market.net(price, r.n) - F.Market.deposit(vendor, r.n)
            end
            local vendorValue = vendor and vendor * r.n or nil
            if auction and (not vendorValue or auction > vendorValue) then
                row.value, row.route = auction, "auction"
            elseif vendorValue then
                row.value, row.route = vendorValue, "vendor"
            end
            row.cost, row.perDay = math.floor(cost), perDay
            row.profit = row.value and row.value - row.cost or nil
        end
        out[#out + 1] = row
    end
    table.sort(out, function(a, b)
        local x, y = a.profit or -math.huge, b.profit or -math.huge
        if x ~= y then
            return x > y
        end
        return tostring(a.name) < tostring(b.name)
    end)
    return out
end

-- Puts the materials of `count` crafts on the shopping list, each at its current cost.
function C.shopMaterials(recipeID, count)
    local r = recipes()[recipeID]
    if not r then
        return 0
    end
    local history = F.Data.market(F.db, F.Engine.scope()).history
    local added = 0
    for _, m in ipairs(r.r) do
        local kind = F.AH.kindOf(m[1])
        local unit = usual(history, m[1])
        if kind and kind ~= "gear" and unit then
            local key = U.key(kind, m[1])
            local name = U.itemInfo(m[1])
            if F.Shopping.add(key, unit, m[2] * (count or 1), name) then
                added = added + 1
            end
        end
    end
    return added
end
