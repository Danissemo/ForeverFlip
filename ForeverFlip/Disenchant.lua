-- Disenchanting: the expected value of the materials a green or blue weapon or armor piece gives,
-- priced at the usual auction price of each material after the cut. A gear lot priced well below
-- that value is a "disenchant" deal for an enchanter.
--
-- The outcome table is the Classic Era one (item level band, quality, armor or weapon). It has not
-- been checked on WoW Forever item by item; the values are estimates.
local F = ForeverFlip
local U = F.Util
local DE = {}
F.Disenchant = DE

DE.SPELL = 13262 -- Disenchant

local STRANGE, SOUL, VISION, DREAM, ILLUSION = 10940, 11083, 11137, 11176, 16204
local LESSER_MAGIC, GREATER_MAGIC = 10938, 10939
local LESSER_ASTRAL, GREATER_ASTRAL = 10998, 11082
local LESSER_MYSTIC, GREATER_MYSTIC = 11134, 11135
local LESSER_NETHER, GREATER_NETHER = 11174, 11175
local LESSER_ETERNAL, GREATER_ETERNAL = 16202, 16203
local SMALL_GLIMMERING, LARGE_GLIMMERING = 10978, 11084
local SMALL_GLOWING, LARGE_GLOWING = 11138, 11139
local SMALL_RADIANT, LARGE_RADIANT = 11177, 11178
local SMALL_BRILLIANT, LARGE_BRILLIANT = 14343, 14344
local NEXUS = 20725

-- Uncommon items: { up to item level, dust, dust qty, essence, essence qty, shard, shard chance }.
-- Armor gives dust 75% (80% below level 16) and essence 20%; weapons swap the two.
local UNCOMMON = {
    { 15, STRANGE, 1.5, LESSER_MAGIC, 1.5, nil, 0 },
    { 20, STRANGE, 2.5, GREATER_MAGIC, 1.5, SMALL_GLIMMERING, 0.05 },
    { 25, STRANGE, 5, LESSER_ASTRAL, 1.5, SMALL_GLIMMERING, 0.1 },
    { 30, SOUL, 1.5, GREATER_ASTRAL, 1.5, LARGE_GLIMMERING, 0.05 },
    { 35, SOUL, 3.5, LESSER_MYSTIC, 1.5, SMALL_GLOWING, 0.05 },
    { 40, VISION, 1.5, GREATER_MYSTIC, 1.5, LARGE_GLOWING, 0.05 },
    { 45, VISION, 3.5, LESSER_NETHER, 1.5, SMALL_RADIANT, 0.05 },
    { 50, DREAM, 1.5, GREATER_NETHER, 1.5, LARGE_RADIANT, 0.05 },
    { 55, DREAM, 3.5, LESSER_ETERNAL, 1.5, SMALL_BRILLIANT, 0.05 },
    { 60, ILLUSION, 1.5, GREATER_ETERNAL, 1.5, LARGE_BRILLIANT, 0.05 },
    { 65, ILLUSION, 3.5, GREATER_ETERNAL, 2.5, LARGE_BRILLIANT, 0.05 },
}

-- Rare items: one shard by item level band.
local RARE = {
    { 25, SMALL_GLIMMERING },
    { 30, LARGE_GLIMMERING },
    { 35, SMALL_GLOWING },
    { 40, LARGE_GLOWING },
    { 45, SMALL_RADIANT },
    { 50, LARGE_RADIANT },
    { 55, SMALL_BRILLIANT },
    { 65, LARGE_BRILLIANT },
}

DE.MATERIALS = {
    STRANGE,
    SOUL,
    VISION,
    DREAM,
    ILLUSION,
    LESSER_MAGIC,
    GREATER_MAGIC,
    LESSER_ASTRAL,
    GREATER_ASTRAL,
    LESSER_MYSTIC,
    GREATER_MYSTIC,
    LESSER_NETHER,
    GREATER_NETHER,
    LESSER_ETERNAL,
    GREATER_ETERNAL,
    SMALL_GLIMMERING,
    LARGE_GLIMMERING,
    SMALL_GLOWING,
    LARGE_GLOWING,
    SMALL_RADIANT,
    LARGE_RADIANT,
    SMALL_BRILLIANT,
    LARGE_BRILLIANT,
    NEXUS,
}

-- Outcomes { { itemID, expected units } } of an item of `quality` (2 or 3), `level` and class
-- (2 = weapon, 4 = armor); nil when it cannot be disenchanted.
function DE.outcomes(quality, level, classID)
    if not U.finite(level) or level < 5 or (classID ~= 2 and classID ~= 4) then
        return nil
    end
    if quality == 2 then
        for _, row in ipairs(UNCOMMON) do
            if level <= row[1] then
                local shard = row[7]
                local dustShare = level <= 15 and 0.8 or 0.75
                local essenceShare = 1 - dustShare - shard
                if classID == 2 then
                    dustShare, essenceShare = essenceShare, dustShare
                end
                local out = { { row[2], dustShare * row[3] }, { row[4], essenceShare * row[5] } }
                if row[6] then
                    out[#out + 1] = { row[6], shard }
                end
                return out
            end
        end
    elseif quality == 3 and level >= 11 then
        for _, row in ipairs(RARE) do
            if level <= row[1] then
                if row[2] == LARGE_BRILLIANT then
                    return { { LARGE_BRILLIANT, 0.995 }, { NEXUS, 0.005 } }
                end
                return { { row[2], 1 } }
            end
        end
    end
    return nil
end

function DE.canDisenchant()
    if IsPlayerSpell then
        local ok, known = pcall(IsPlayerSpell, DE.SPELL)
        if ok and known then
            return true
        end
    end
    if IsSpellKnown then
        local ok, known = pcall(IsSpellKnown, DE.SPELL)
        return ok and known or false
    end
    return false
end

function DE.active()
    return F.db and F.db.settings.disenchant and DE.canDisenchant() or false
end

-- Expected money from disenchanting one item and selling the materials on the auction house;
-- nil when the item cannot be disenchanted or a material has no usual price yet.
function DE.value(id)
    local _, _, quality, level, _, _, _, _, _, _, _, classID = U.itemInfo(id)
    local outcomes = DE.outcomes(quality, level, classID)
    if not outcomes then
        return nil
    end
    local history = F.Data.market(F.db, F.Engine.scope()).history
    local total = 0
    for _, o in ipairs(outcomes) do
        local h = history[U.key("commodity", o[1])] or history[U.key("item", o[1])]
        local price = h and h.scan and h.scan.market
        if not U.finite(price) then
            if o[2] >= 0.1 then
                return nil
            end
        else
            total = total + F.Market.net(price, 1) * o[2]
        end
    end
    return math.floor(total)
end

-- A disenchant deal from gear listings sorted cheapest first: every lot below the value minus the
-- minimum profit, within the budget. Gear is bought one auction per click.
function DE.evaluate(rows, id, budget)
    local value = DE.value(id)
    if not value or value <= 0 then
        return nil
    end
    local minProfit = F.db.settings.minProfit or 100
    local qty, cost, profit, used = 0, 0, 0, {}
    for _, r in ipairs(rows) do
        if r.unit > value - minProfit then
            break
        end
        local take = r.qty
        if cost + take * r.unit > budget then
            take = math.floor((budget - cost) / r.unit)
        end
        if take < 1 then
            break
        end
        qty, cost, profit = qty + take, cost + take * r.unit, profit + take * (value - r.unit)
        used[#used + 1] = { unit = r.unit, qty = take, auctionID = r.auctionID }
    end
    if qty < 1 or profit < minProfit then
        return nil
    end
    return {
        mode = "disenchant",
        qty = qty,
        cost = cost,
        exit = value,
        profit = profit,
        roi = profit / cost,
        maxUnit = used[#used].unit,
        lots = used,
    }
end
