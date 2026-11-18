-- Disenchanting: the expected value of the materials a green or blue weapon or armor piece gives,
-- priced at the usual auction price of each material after the cut. A gear lot priced well below
-- that value is a "disenchant" deal for an enchanter.
--
-- The outcome table is the Classic Era one (item level band, quality, armor or weapon), with what
-- ForeverForge Auction found from logged disenchants: green weapons of item level 21-30 give
-- Greater Magic Essence, never an astral one. Your own disenchants are learned (LOOT_OPENED after
-- the spell) and replace the table for a band once DE.LEARN of them were seen.
--
-- Retail (12.x) is another game: its item levels were squished and an item disenchants into the
-- materials of its own expansion, whatever its level. There an item's band is its expansion and
-- quality ("x11:2:a"); Midnight gear has a table (DE.MIDNIGHT), gear of older expansions is learned
-- from your own disenchants only, since a guess from the Classic table would price it wrong.
local F = ForeverFlip
local U = F.Util
local DE = {}
F.Disenchant = DE

DE.SPELL = 13262 -- Disenchant
DE.LEARN = 15 -- own disenchants of a band before their results replace the table

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

-- Midnight's reagents, each in two ranks (the second worth more): Eversinging Dust from uncommon
-- gear, Radiant Shard from rare, Dawn Crystal from epic.
local DUST_1, DUST_2 = 243599, 243600
local SHARD_1, SHARD_2 = 243602, 243603
local CRYSTAL_1, CRYSTAL_2 = 243605, 243606
DE.MIDNIGHT_EXPANSION = 11 -- LE_EXPANSION_MIDNIGHT, GetItemInfo's 15th answer
-- Expected units of each by quality, from Wowhead's disenchant logs of Midnight gear (item level 197
-- and up, November 2026): a green gives about two dust (a quarter of them rank 2), a blue a shard, an
-- epic a crystal, about a third and a half of them rank 2. Your own disenchants replace it (DE.LEARN).
DE.MIDNIGHT = {
    [2] = { { DUST_1, 1.35 }, { DUST_2, 0.45 } },
    [3] = { { SHARD_1, 0.7 }, { SHARD_2, 0.3 } },
    [4] = { { CRYSTAL_1, 0.5 }, { CRYSTAL_2, 0.45 } },
}

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

function DE.retail()
    return F.AH.isRetail() and true or false
end

-- The band of an item: a key for learning ("2:w:25" = green weapon up to item level 25; on Retail
-- "x11:2:w" = a green Midnight weapon) and the Classic table row; nil when it cannot be
-- disenchanted. `expansion`: GetItemInfo's, asked on Retail only.
function DE.band(quality, level, classID, expansion)
    if classID ~= 2 and classID ~= 4 then
        return nil
    end
    local kind = classID == 2 and "w" or "a"
    if DE.retail() then
        if not U.finite(quality) or quality < 2 or quality > 4 or not U.finite(expansion) then
            return nil
        end
        return "x" .. expansion .. ":" .. quality .. ":" .. kind
    end
    if not U.finite(level) or level < 5 then
        return nil
    end
    if quality == 2 then
        for _, row in ipairs(UNCOMMON) do
            if level <= row[1] then
                return "2:" .. kind .. ":" .. row[1], row
            end
        end
    elseif quality == 3 and level >= 11 then
        for _, row in ipairs(RARE) do
            if level <= row[1] then
                return "3:" .. kind .. ":" .. row[1], row
            end
        end
    end
    return nil
end

-- Own results of a band once enough were seen: { { itemID, units per disenchant } }.
local function learned(band)
    local seen = band and F.db and F.db.deSeen and F.db.deSeen[band]
    if type(seen) ~= "table" or (seen.n or 0) < DE.LEARN then
        return nil
    end
    local out = {}
    for id, units in pairs(seen) do
        if type(id) == "number" and U.finite(units) and units > 0 then
            out[#out + 1] = { id, units / seen.n }
        end
    end
    table.sort(out, function(a, b)
        return a[1] < b[1]
    end)
    return #out > 0 and out or nil
end

-- Outcomes { { itemID, expected units } } of an item of `quality` (2 or 3), `level` and class
-- (2 = weapon, 4 = armor); nil when it cannot be disenchanted. Second value: "yours" when your own
-- disenchants set them, else "table".
function DE.outcomes(quality, level, classID, expansion)
    local band = DE.band(quality, level, classID, expansion)
    if not band then
        return nil
    end
    local own = learned(band)
    if own then
        return own, "yours"
    end
    if DE.retail() then
        local row = expansion == DE.MIDNIGHT_EXPANSION and DE.MIDNIGHT[quality]
        return row or nil, row and "table" or nil
    end
    if quality == 2 then
        for _, row in ipairs(UNCOMMON) do
            if level <= row[1] then
                local shard = row[7]
                local dustShare = level <= 15 and 0.8 or 0.75
                local essenceShare = 1 - dustShare - shard
                local essence = row[4]
                if classID == 2 then
                    dustShare, essenceShare = essenceShare, dustShare
                    if level >= 21 and level <= 30 then
                        essence = GREATER_MAGIC
                    end
                end
                local out = { { row[2], dustShare * row[3] }, { essence, essenceShare * row[5] } }
                if row[6] then
                    out[#out + 1] = { row[6], shard }
                end
                return out, "table"
            end
        end
    elseif quality == 3 and level >= 11 then
        for _, row in ipairs(RARE) do
            if level <= row[1] then
                if row[2] == LARGE_BRILLIANT then
                    return { { LARGE_BRILLIANT, 0.995 }, { NEXUS, 0.005 } }, "table"
                end
                return { { row[2], 1 } }, "table"
            end
        end
    end
    return nil
end

function DE.canDisenchant()
    return F.Compat.playerSpell(DE.SPELL)
end

function DE.active()
    -- No switch any more: a character who knows Disenchant always gets the deals on their page.
    return F.db and DE.canDisenchant() or false
end

-- Why no disenchant deal can be found, the first that applies (nil: they can be, there is just none
-- right now): "unlearned" (this character does not know Disenchant), "noscan" (no full scan of
-- this house yet) or "noprices" (no material has a usual price yet).
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
    DUST_1,
    DUST_2,
    SHARD_1,
    SHARD_2,
    CRYSTAL_1,
    CRYSTAL_2,
}
function DE.status(scanned)
    if not DE.canDisenchant() then
        return "unlearned"
    elseif not scanned then
        return "noscan"
    end
    local history = F.Data.market(F.db, F.Engine.scope()).history
    for _, id in ipairs(DE.MATERIALS) do
        if U.finite(DE.materialPrice(history, id)) then
            return nil
        end
    end
    return "noprices"
end

-- Three lesser essences make one greater and a greater splits into three lesser, so neither is
-- worth more than the other form allows (ForeverForge Auction): { other form, units of it }.
local ESSENCE_PAIRS = {
    [LESSER_MAGIC] = { GREATER_MAGIC, 1 / 3 },
    [GREATER_MAGIC] = { LESSER_MAGIC, 3 },
    [LESSER_ASTRAL] = { GREATER_ASTRAL, 1 / 3 },
    [GREATER_ASTRAL] = { LESSER_ASTRAL, 3 },
    [LESSER_MYSTIC] = { GREATER_MYSTIC, 1 / 3 },
    [GREATER_MYSTIC] = { LESSER_MYSTIC, 3 },
    [LESSER_NETHER] = { GREATER_NETHER, 1 / 3 },
    [GREATER_NETHER] = { LESSER_NETHER, 3 },
    [LESSER_ETERNAL] = { GREATER_ETERNAL, 1 / 3 },
    [GREATER_ETERNAL] = { LESSER_ETERNAL, 3 },
}

-- Materials are commodities, older scans kept some as items: the key the history holds.
local function usualOf(history, id)
    local key = U.key("commodity", id)
    if not history[key] and history[U.key("item", id)] then
        key = U.key("item", id)
    end
    return (F.Deals.priceOf(key, history))
end

-- The usual price of a disenchanting material, an essence at most what its other form allows.
function DE.materialPrice(history, id)
    local price = usualOf(history, id)
    local pair = ESSENCE_PAIRS[id]
    local other = pair and usualOf(history, pair[1])
    if U.finite(other) then
        local cap = other * pair[2]
        price = U.finite(price) and math.min(price, cap) or nil
    end
    return price
end

-- Expected money from disenchanting one item and selling the materials on the auction house;
-- nil when the item cannot be disenchanted or a material has no usual price yet.
function DE.value(id)
    local _, _, quality, level, _, _, _, _, _, _, _, classID, _, _, expansion = U.itemInfo(id)
    local outcomes = DE.outcomes(quality, level, classID, expansion)
    if not outcomes then
        return nil
    end
    local history = F.Data.market(F.db, F.Engine.scope()).history
    local total = 0
    for _, o in ipairs(outcomes) do
        local price = DE.materialPrice(history, o[1])
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

-- What one unit of the item brings sold as it is, by the route rule of Selling (Market.sellRoutes
-- at no cost): the vendor price, or the usual price after the cut and the deposit, the better one.
-- nil when neither is known.
function DE.sellValue(id, kind, key, vendor, usual)
    local q = { vendor = vendor }
    if U.finite(usual) and usual > 0 then
        local unit = F.Market.unitNet(id, kind, key, usual)
        q.post, q.net, q.lost = usual, unit, F.Market.net(usual, 1) - unit
    end
    local routes = F.Market.sellRoutes(q, 1, F.db.settings)
    local best
    for _, r in pairs({ routes.vendor, routes.auction }) do
        if not best or r.profit > best then
            best = r.profit
        end
    end
    return best
end

-- A disenchant deal from gear listings sorted cheapest first: every lot at most F.Market.maxBuy of
-- the value (minimum profit and return, as Bids), within the budget. Gear is bought one auction per
-- click. `keep` (DE.sellValue): when selling the item as it is brings as much, disenchanting it is
-- no deal.
function DE.evaluate(rows, id, budget, keep)
    local value = DE.value(id)
    if not value or value <= 0 or U.finite(keep) and keep >= value then
        return nil
    end
    local minProfit = F.Market.thresholds(F.db.settings).minProfit
    local most = F.Market.maxBuy(value, "disenchant", F.db.settings) or 0
    local qty, cost, profit, used = 0, 0, 0, {}
    for _, r in ipairs(rows) do
        if r.unit > most then
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

-- Learning from your own disenchants ------------------------------------------------------------------
-- When the Disenchant cast starts, the item it is aimed at is locked in the bags: it is noted. The
-- loot window that opens right after holds its result, added to the item's band (F.db.deSeen).
-- Other items can be locked at that moment too (attached to an unsent mail, in the trade window or
-- the auction house's sell slot): only a weapon or armor piece of uncommon quality or better (or an
-- item whose data is not loaded yet) can be the target, and two different ones leave it unknown,
-- so nothing is learned rather than the loot booked into another item's band.
local function lockedItem()
    if not F.Compat.caps.container then
        return nil
    end
    local found, foundLink
    for bag = 0, 4 do
        for slot = 1, F.Compat.bagSlots(bag) do
            local info = F.Compat.bagItem(bag, slot)
            if type(info) == "table" and info.isLocked and info.itemID then
                local _, _, quality, _, _, _, _, _, _, _, _, classID = U.itemInfo(info.itemID)
                if quality == nil or (U.finite(quality) and quality >= 2 and (classID == 2 or classID == 4)) then
                    if found and found ~= info.itemID then
                        return nil
                    end
                    found, foundLink = info.itemID, info.hyperlink
                end
            end
        end
    end
    return found, foundLink
end

-- UNIT_SPELLCAST_START notes the item and the cast; _INTERRUPTED and _FAILED of that same cast
-- forget it, so a loot window that follows (a mob, a chest) is never counted as a disenchant. A
-- second press while casting fails with its own cast GUID and leaves the running cast alone. The
-- loot window may come before or after _SUCCEEDED. (event, unit, cast GUID, spell ID)
function DE.onCast(event, unit, castGUID, spellID)
    if unit ~= "player" or spellID ~= DE.SPELL then
        return
    end
    local c = DE.casting
    if event == "UNIT_SPELLCAST_START" then
        local id, link = lockedItem()
        DE.casting = id and { id = id, link = link, at = F.Engine.clock(), guid = castGUID } or nil
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if c and (not c.guid or c.guid == castGUID) then
            c.done = true
        end
    elseif c and (not c.guid or not castGUID or c.guid == castGUID) and not c.done then
        DE.casting = nil
    end
end

function DE.onLoot()
    local c = DE.casting
    DE.casting = nil
    if not c or F.Engine.clock() - c.at > 15 or not GetNumLootItems or not GetLootSlotLink then
        return false
    end
    local _, _, quality, level, _, _, _, _, _, _, _, classID, _, _, expansion = U.itemInfo(c.id)
    local band = DE.band(quality, level, classID, expansion)
    if not band then
        return false
    end
    local got = {}
    for i = 1, (GetNumLootItems() or 0) do
        local link = GetLootSlotLink(i)
        local id = link and tonumber(link:match("item:(%d+)"))
        local _, _, quantity = GetLootSlotInfo(i)
        if id and U.finite(quantity) and quantity > 0 then
            got[id] = (got[id] or 0) + quantity
        end
    end
    if not next(got) then
        return false
    end
    local seen = F.db.deSeen[band] or { n = 0 }
    F.db.deSeen[band] = seen
    seen.n = (seen.n or 0) + 1
    for id, quantity in pairs(got) do
        seen[id] = (seen[id] or 0) + quantity
    end
    DE.chain(c, got)
    return true
end

-- T21: an item bought for disenchanting (a held position) and disenchanted: the materials carry
-- its cost as a chain (F.Data.convert), shared by their prices. Nothing for an item not held.
function DE.chain(c, got)
    local key = F.AH.keyFor(c.id, c.link)
    local char = F.Data.char(F.db, F.Engine.owner())
    if not key or not char.positions[key] then
        return nil
    end
    local history = F.Data.market(F.db, F.Engine.scope()).history
    local outputs = {}
    for id, quantity in pairs(got) do
        outputs[#outputs + 1] = {
            key = F.AH.keyFor(id),
            name = U.itemInfo(id),
            qty = quantity,
            value = DE.materialPrice(history, id),
        }
    end
    table.sort(outputs, function(a, b)
        return tostring(a.key) < tostring(b.key)
    end)
    return F.Data.convert(char, "disenchant", { { key = key, qty = 1 } }, outputs, F.Engine.clock())
end
