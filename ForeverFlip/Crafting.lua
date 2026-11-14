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

-- Returns the professions the character has learned.  The classic API exposes these through
-- GetProfessions/GetProfessionInfo; keep this separate from recipe learning because the latter
-- only knows about the profession window that is currently open.
function C.professions()
    if not GetProfessions or not GetProfessionInfo then
        return {}
    end
    local ok, p1, p2, p3, p4, p5, p6 = pcall(GetProfessions)
    if not ok then
        return {}
    end
    local out, seen = {}, {}
    -- A slot not learned (prof1, prof2, archaeology, fishing, cooking, first aid) is nil, so the
    -- list has holes: each slot is read by its index.
    local ids = { p1, p2, p3, p4, p5, p6 }
    for i = 1, 6 do
        local id = ids[i]
        if id and not seen[id] then
            local got, name, _, rank, maxRank = pcall(GetProfessionInfo, id)
            if got and type(name) == "string" and name ~= "" then
                out[#out + 1] = {
                    name = name,
                    rank = U.finite(rank) and rank or nil,
                    maxRank = U.finite(maxRank) and maxRank or nil,
                }
                seen[id] = true
            end
        end
    end
    return out
end

local function recipes()
    local c = F.Data.char(F.db, F.Engine.owner())
    c.recipes = type(c.recipes) == "table" and c.recipes or {}
    return c.recipes
end

-- Reads every recipe of the open profession window: { name, out = itemID, n = units made,
-- learned = the character may craft it, r = { { itemID, count }, ... } }.
-- GetAllRecipeIDs lists the whole profession, known and unknown: C_TradeSkillUI.GetRecipeInfo
-- says which (its `learned` flag; the schematic has none). Without that call every recipe counts
-- as learned, so a client that lacks it keeps the old list.
local function learned(id)
    local T = C_TradeSkillUI
    if not T or not T.GetRecipeInfo then
        return true
    end
    local ok, info = pcall(T.GetRecipeInfo, id)
    return not ok or type(info) ~= "table" or info.learned ~= false
end

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
                saved[id] = {
                    name = s.name,
                    out = s.outputItemID,
                    n = math.max(1, s.quantityMin or 1),
                    learned = learned(id),
                    r = r,
                }
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

-- Whether a saved recipe is left out of the page: one the character has not learned, while the
-- setting asks for learned recipes only. A recipe saved before the flag existed is shown (only a
-- known "no" hides it).
function C.hidden(r)
    return r.learned == false and (F.db.settings.hideUnlearned or false) and true or false
end

-- How many saved recipes the setting hides (the toggle says what it is doing).
function C.unlearnedCount()
    local n = 0
    for _, r in pairs(recipes()) do
        if r.learned == false then
            n = n + 1
        end
    end
    return n
end

-- The auction price of an item: a fresh check (Check all on this page) before the scan's usual price.
-- Gear is kept under its name (F.AH.keyFor; nil until the game has loaded the item).
local function usual(history, id)
    local key = F.AH.keyFor(id)
    local h = key and history[key]
    local live = key and F.Trade.freshCheapest(key)
    return live or (h and F.Market.usual(h)) or nil, h
end

-- Keys of every material and product of the saved recipes (what Check all reads on this page).
function C.keys()
    local out, seen = {}, {}
    for _, r in pairs(recipes()) do
        local ids = { r.out }
        for _, m in ipairs(r.r or {}) do
            ids[#ids + 1] = m[1]
        end
        for _, id in ipairs(ids) do
            local key = F.AH.keyFor(id)
            if key and not seen[key] then
                seen[key] = true
                out[#out + 1] = key
            end
        end
    end
    table.sort(out)
    return out
end

-- Cost of one unit of a material: the cheaper of the auction house and a merchant.
function C.materialCost(history, id)
    local ah = usual(history, id) or F.Engine.auxPrice(id)
    local merchant = F.db.merchantPrices and F.db.merchantPrices[id]
    if ah and merchant then
        return math.min(ah, merchant)
    end
    return ah or merchant
end

-- Every saved recipe with a known cost, best profit first: { id, name, out, n, cost, value, profit,
-- perDay, route = "auction" | "vendor", missing = itemID of a material without a price }.
-- A recipe the character has not learned is left out when the setting says so: it cannot be
-- crafted, so its profit is no deal yet. C.profits(true) counts every recipe (what the row count
-- of the toggle shows).
function C.profits(countUnlearned)
    local now = F.Engine.clock()
    local history = F.Data.market(F.db, F.Engine.scope()).history
    local out = {}
    for id, r in pairs(recipes()) do
        if countUnlearned or not C.hidden(r) then
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
                    local d = F.Market.duration(F.AH.keyFor(r.out), r.n, price)
                    auction = F.Market.net(price, r.n) - F.Market.postDeposit(r.out, nil, r.n, d)
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
            row.learned = r.learned ~= false
            out[#out + 1] = row
        end
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

-- Units of an item the player already has, in the bags and the bank (the bank as last seen);
-- `bagsOnly`: in the bags.
function C.have(id, bagsOnly)
    -- The documented form takes the item as ItemInfo (an ID is accepted); the bare GetItemCount is
    -- its deprecated fallback, kept for a client that does not have C_Item.
    local count = C_Item and C_Item.GetItemCount or GetItemCount
    if not count then
        return 0
    end
    local ok, n = pcall(count, id, not bagsOnly)
    return ok and U.finite(n) and n or 0
end

-- Puts the materials of `count` crafts on the shopping list, each at its current cost, less what
-- the bags and the bank already hold.
function C.shopMaterials(recipeID, count)
    local r = recipes()[recipeID]
    if not r then
        return 0
    end
    local history = F.Data.market(F.db, F.Engine.scope()).history
    local added = 0
    for _, m in ipairs(r.r) do
        local kind = F.AH.kindOf(m[1])
        local unit = C.materialCost(history, m[1])
        if kind and kind ~= "gear" and unit then
            local key = U.key(kind, m[1])
            local name = U.itemInfo(m[1])
            local need = m[2] * (count or 1) - C.have(m[1])
            -- An entry already on the list (the player's own, another recipe's materials) is
            -- widened, not replaced: its "any quantity", a larger quantity and a higher price stay.
            -- Its quantity is not added to: an entry never counts down as units are bought
            -- (F.Shopping.bought), so each click would grow it by a day of materials.
            local e = type(F.db.shopping) == "table" and F.db.shopping[key]
            local max, qty = unit, need
            if type(e) == "table" then
                max = math.max(unit, U.finite(e.max) and e.max or 0)
                qty = U.finite(e.qty) and math.max(e.qty, need) or nil
                name = name or e.name
            end
            if need > 0 and F.Shopping.add(key, max, qty, name) then
                added = added + 1
            end
        end
    end
    return added
end
