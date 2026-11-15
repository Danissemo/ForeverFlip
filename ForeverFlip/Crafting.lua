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
-- says which (its `learned` flag; the schematic has none). On WoW Forever it gave no flag, so the
-- spell book is asked as well whenever the page is drawn (a recipe's ID is its spell's; C.learnedMap).
-- No answer from either reads as "not known": a failure never hides a recipe the character can craft.
local function knowsSpell(id)
    local S = C_SpellBook
    local known = S and S.IsSpellKnown
    if not known and not S then
        known = IsSpellKnown -- the deprecated fallback, only without the namespace
    end
    if not known then
        return nil
    end
    local ok, has = pcall(known, id)
    if ok and type(has) == "boolean" then
        return has
    end
    return nil
end

local function learned(id)
    local T = C_TradeSkillUI
    if T and T.GetRecipeInfo then
        local ok, info = pcall(T.GetRecipeInfo, id)
        if ok and type(info) == "table" and type(info.learned) == "boolean" then
            return info.learned
        end
    end
    return nil -- the spell book is asked when the page is drawn (C.learnedMap), not saved
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

-- Whether each saved recipe is learned, asked of the spell book now: a recipe saved before the
-- flag existed, or learned since the profession window was last open, is answered without it. If
-- the spell book knows none of them, the IDs are not spells in this client and the saved flags
-- stand. { [id] = true | false | nil }; nil is "not known" and hides nothing.
function C.learnedMap()
    local live, any = {}, false
    for id in pairs(recipes()) do
        live[id] = knowsSpell(id)
        any = any or live[id] == true
    end
    local out = {}
    for id, r in pairs(recipes()) do
        if any and live[id] ~= nil then
            out[id] = live[id]
        else
            out[id] = r.learned
        end
    end
    return out
end

-- Whether a saved recipe is left out of the page: one the character has not learned, while the
-- setting asks for learned recipes only. Only a known "no" hides it.
function C.hidden(learnedFlag)
    return learnedFlag == false and (F.db.settings.hideUnlearned or false) and true or false
end

-- How many saved recipes the setting hides (the toggle says what it is doing).
function C.unlearnedCount()
    local n = 0
    for _, flag in pairs(C.learnedMap()) do
        if flag == false then
            n = n + 1
        end
    end
    return n
end

-- Whether every saved recipe is one the character has not learned, and there is at least one. The
-- page says so when a count of every recipe comes back as large as the unlearned one: a learned
-- recipe with no material price yet is still a row, so the count alone does not answer it.
function C.allUnlearned()
    local total, unlearned = 0, 0
    for _, flag in pairs(C.learnedMap()) do
        total = total + 1
        if flag == false then
            unlearned = unlearned + 1
        end
    end
    return total > 0 and total == unlearned
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
    local learnedMap = C.learnedMap()
    for id, r in pairs(recipes()) do
        if countUnlearned or not C.hidden(learnedMap[id]) then
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
            row.learned = learnedMap[id] ~= false
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

-- How many crafts of a recipe are worth making now, and what to buy for them. Crafts are added one
-- at a time; each takes its materials cheapest first: the stock in the bags and the bank (valued
-- at the material's usual cost, though it is not bought), then the lots of a fresh check or of the
-- last full scan, then a merchant's price, else the usual price as an estimate. A craft is planned
-- while what it brings (Crafting.profits: the product after the cut and the deposit, or the
-- vendor) exceeds what its materials cost by C.PLAN_RETURN of it. The plan also ends at
--   * a day of the product's sales, less the product held (auction route; one craft to try when
--     the sales are not measured, none when nothing sells),
--   * the lots listed, the money on hand (settings.spendShare of it), or C.PLAN_MAX crafts.
-- Each material's price limit is the dearest unit the plan takes of it, so a shopping list entry
-- buys exactly the lots that keep the crafts paying.
-- { crafts, limit, perDay, value, cost, profit, materials = { { id, key, name, per, held, buy,
-- maxPrice, spend, estimated } } }, or nil and a reason ("missing", "unknown").
C.PLAN_RETURN = 0.05
C.PLAN_MAX = 100
C.PLAN_DAYS = 1

local function lotsOf(key, id, history)
    local rows, estimated = {}, false
    local check = F.Trade.prices[key]
    local source = check and F.Engine.clock() - check.at <= 300 and check or F.Trade.scanPrice(key)
    for _, l in ipairs(source and source.rows or {}) do
        if U.finite(l.unit) and l.unit > 0 and (l.qty or 0) > 0 then
            rows[#rows + 1] = { unit = l.unit, qty = l.qty }
        end
    end
    local merchant = F.db.merchantPrices and F.db.merchantPrices[id]
    if merchant then
        rows[#rows + 1] = { unit = merchant, qty = math.huge, merchant = true }
    end
    if #rows == 0 then
        local usualCost = C.materialCost(history, id)
        if usualCost then
            rows[1] = { unit = usualCost, qty = math.huge }
            estimated = true
        end
    end
    table.sort(rows, function(a, b)
        return a.unit < b.unit
    end)
    return rows, estimated
end

function C.plan(recipeID)
    local r = recipes()[recipeID]
    if not r then
        return nil, "unknown"
    end
    local row
    for _, p in ipairs(C.profits(true)) do
        if p.id == recipeID then
            row = p
            break
        end
    end
    if not row or row.missing or not row.value then
        return nil, "missing"
    end
    local history = F.Data.market(F.db, F.Engine.scope()).history
    local made = math.max(1, r.n or 1)
    local plan = { crafts = 0, perDay = row.perDay, value = row.value, cost = 0, spend = 0, materials = {} }
    -- How many crafts the sales take.
    local cap, capLimit = C.PLAN_MAX, "max"
    if row.route == "auction" then
        if not row.perDay then
            cap, capLimit = 1, "unknown_sales"
        else
            local units = row.perDay * C.PLAN_DAYS - C.have(r.out)
            cap, capLimit = math.max(0, math.floor(units / made)), "sales"
            if cap == 0 then
                capLimit = row.perDay * C.PLAN_DAYS >= made and "stock" or "no_sales"
            end
        end
    end
    local money = math.floor(F.Engine.wallet() * (F.db.settings.spendShare or 0.8))
    local mats = {}
    for _, m in ipairs(r.r) do
        local kind = F.AH.kindOf(m[1])
        local key = kind and U.key(kind, m[1]) or nil
        local lots, estimated = lotsOf(key or "", m[1], history)
        local mat = {
            id = m[1],
            key = key,
            name = U.itemInfo(m[1]),
            per = m[2],
            held = C.have(m[1]),
            usedHeld = 0,
            buy = 0,
            spend = 0,
            maxPrice = nil,
            estimated = estimated,
            usual = C.materialCost(history, m[1]) or 0,
            lots = lots,
            lot = 1,
            taken = 0, -- units taken of the current lot
            buyable = kind ~= nil and kind ~= "gear",
        }
        mats[#mats + 1] = mat
        plan.materials[#plan.materials + 1] = mat
    end
    local limit = capLimit
    while plan.crafts < cap do
        -- The cost of one more craft, without taking it yet.
        local cost, spend, ran = 0, 0, false
        local takes = {}
        for i, mat in ipairs(mats) do
            local need, fromHeld = mat.per, math.min(mat.per, math.max(0, mat.held - mat.usedHeld))
            need = need - fromHeld
            cost = cost + fromHeld * mat.usual
            local lot, taken, top = mat.lot, mat.taken, nil
            local buy, paid = 0, 0
            while need > 0 do
                local l = mat.lots[lot]
                if not l or not mat.buyable then
                    ran = true
                    break
                end
                local n = math.min(need, l.qty - taken)
                if n <= 0 then
                    lot, taken = lot + 1, 0
                else
                    need, taken, buy = need - n, taken + n, buy + n
                    cost, spend, paid = cost + n * l.unit, spend + n * l.unit, paid + n * l.unit
                    top = l.unit
                end
            end
            takes[i] = { fromHeld = fromHeld, lot = lot, taken = taken, buy = buy, paid = paid, top = top }
        end
        if ran then
            limit = "supply"
            break
        end
        if row.value - cost < row.value * C.PLAN_RETURN then
            limit = plan.crafts == 0 and "no_profit" or "price"
            break
        end
        if plan.spend + spend > money then
            limit = "money"
            break
        end
        plan.crafts = plan.crafts + 1
        plan.cost, plan.spend = plan.cost + cost, plan.spend + spend
        for i, mat in ipairs(mats) do
            local t = takes[i]
            mat.usedHeld, mat.lot, mat.taken = mat.usedHeld + t.fromHeld, t.lot, t.taken
            mat.buy, mat.spend = mat.buy + t.buy, mat.spend + t.paid
            if t.top then
                mat.maxPrice = math.max(mat.maxPrice or 0, t.top)
            end
        end
    end
    for _, mat in ipairs(mats) do
        mat.lots, mat.lot, mat.taken = nil, nil, nil
    end
    plan.limit = limit
    plan.profit = plan.crafts * row.value - plan.cost
    return plan
end

-- Puts the materials of the plan (C.plan) on the shopping list: each the units to buy, at the
-- price limit that keeps the crafts paying. Returns the entries added and the plan. With `count`,
-- the materials of that many crafts at their usual cost, less what the bags and the bank hold.
function C.shopMaterials(recipeID, count)
    local r = recipes()[recipeID]
    if not r then
        return 0
    end
    if not count then
        local plan, why = C.plan(recipeID)
        if not plan then
            return 0, nil, why
        end
        local added = 0
        for _, mat in ipairs(plan.materials) do
            if mat.buy > 0 and mat.key and mat.maxPrice then
                local e = type(F.db.shopping) == "table" and F.db.shopping[mat.key]
                local max, qty, name = mat.maxPrice, mat.buy, mat.name
                if type(e) == "table" then
                    max = math.max(max, U.finite(e.max) and e.max or 0)
                    qty = U.finite(e.qty) and math.max(e.qty, qty) or nil
                    name = name or e.name
                end
                if F.Shopping.add(mat.key, max, qty, name) then
                    added = added + 1
                end
            end
        end
        return added, plan
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
