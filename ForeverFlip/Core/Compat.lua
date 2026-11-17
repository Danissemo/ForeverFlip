-- Capability adapters: what this client offers (C.caps) and the calls that differ between clients,
-- in one place. The documented C_* function is asked first; a bare deprecated global only when its
-- namespace is missing (the client installs those only while `loadDeprecationFallbacks` is on).
-- WoW Forever (Interface 16001) is the verified target; Retail (12.x) is supported by the same
-- checks: what differs is asked of the API (C.caps), never of a version number. Compat never calls C_AuctionHouse:
-- it only reports whether its functions exist; AH.lua is the only file that calls them.
local F = ForeverFlip
local U = F.Util
local C = {}
F.Compat = C

-- The server allows one full scan per 15 minutes and 20 seconds on WoW Forever (see Scan.lua).
C.REPLICATE_COOLDOWN = 920

local function has(ns, ...)
    if type(ns) ~= "table" then
        return false
    end
    for i = 1, select("#", ...) do
        if ns[select(i, ...)] == nil then
            return false
        end
    end
    return true
end

-- Each capability is read when asked, so a client (or a test) that changes a namespace later is
-- answered as it is now.
local CHECKS = {
    -- The whole auction house in one list (C_AuctionHouse.ReplicateItems and its readers).
    fullScan = function()
        return has(C_AuctionHouse, "ReplicateItems", "GetNumReplicateItems", "GetReplicateItemInfo")
    end,
    -- Commodity searches and purchases (quote and confirm).
    commodities = function()
        return has(C_AuctionHouse, "SendSearchQuery", "GetCommoditySearchResultInfo", "StartCommoditiesPurchase")
    end,
    -- Seconds between full scans the server allows; nil without a full scan.
    replicateCooldown = function()
        return has(C_AuctionHouse, "ReplicateItems") and C.REPLICATE_COOLDOWN or nil
    end,
    spellBook = function()
        return has(C_SpellBook, "IsSpellKnown")
    end,
    item = function()
        return type(C_Item) == "table"
    end,
    container = function()
        return has(C_Container, "GetContainerNumSlots", "GetContainerItemInfo")
    end,
    tradeSkill = function()
        return has(C_TradeSkillUI, "GetAllRecipeIDs", "GetRecipeSchematic")
    end,
    merchantFrame = function()
        return has(C_MerchantFrame, "GetItemInfo")
    end,
    addonMessages = function()
        return has(C_ChatInfo, "SendAddonMessage")
    end,
    -- The WoW Forever client: its experience presets (Classic / Enhanced) exist on no other client.
    forever = function()
        return (Enum and Enum.ForeverExperiencePreset ~= nil) or has(C_GameRules, "GetForeverExperiencePreset")
    end,
    -- Alliance, Horde and the neutral goblin houses each keep their own auctions (WoW Forever).
    -- Without it (Retail) one auction house serves both factions of the realm: the server's house.
    factionHouses = function()
        return C.caps.forever
    end,
    -- Secret values (Retail 12): some answers, a tooltip's item in combat among them, cannot be read.
    secrets = function()
        return type(issecretvalue) == "function"
    end,
}
C.caps = setmetatable({}, {
    __index = function(_, name)
        local check = CHECKS[name]
        if check then
            return check()
        end
    end,
})

-- Whether `v` is a secret value the addon may not read (only clients with secret values have any).
function C.secret(v)
    if type(issecretvalue) ~= "function" then
        return false
    end
    local ok, s = pcall(issecretvalue, v)
    return not ok or s == true
end

-- Realms -------------------------------------------------------------------------------------------
-- A realm name as the game compares them: no spaces or hyphens, case ignored ("Argent Dawn" and
-- "ArgentDawn" are one realm).
function C.realmKey(name)
    if type(name) ~= "string" then
        return nil
    end
    return (name:gsub("[%s%-']", ""):lower())
end

-- The realms connected to the player's: they share one auction house. Keys as C.realmKey, the
-- player's own realm included; just the own realm without the connected-realm list.
function C.connectedRealms()
    local set = {}
    local own = C.realmKey(GetRealmName and GetRealmName())
    if own then
        set[own] = true
    end
    if type(GetAutoCompleteRealms) == "function" then
        local ok, list = pcall(GetAutoCompleteRealms)
        if ok and type(list) == "table" then
            for _, name in ipairs(list) do
                local key = C.realmKey(name)
                if key then
                    set[key] = true
                end
            end
        end
    end
    return set
end

-- Spells ------------------------------------------------------------------------------------------
-- Whether the character knows spell `id`: true, false, or nil when no answer (Crafting: a recipe's
-- ID is its spell's). No answer reads as "not known" to the callers.
function C.spellKnown(id)
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

-- Whether the player's own spell book holds spell `id` (Disenchant): true or false.
function C.playerSpell(id)
    -- C_SpellBook first: the bare IsPlayerSpell/IsSpellKnown are the deprecated fallbacks the client
    -- installs only while `loadDeprecationFallbacks` is on, and they mean the same thing.
    local known = C_SpellBook and C_SpellBook.IsSpellKnown
    if known then
        local ok, has = pcall(known, id, Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player)
        return ok and has or false
    end
    if IsPlayerSpell then
        local ok, has = pcall(IsPlayerSpell, id)
        if ok and has then
            return true
        end
    end
    if IsSpellKnown then
        local ok, has = pcall(IsSpellKnown, id)
        return ok and has or false
    end
    return false
end

-- Items -------------------------------------------------------------------------------------------
-- GetItemInfo moved to C_Item on the WoW Forever client; the global may be missing.
function C.itemInfo(id)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not get then
        return nil
    end
    local ok, name, link, quality, level, minLevel, itemType, subType, stack, equip, texture, sellPrice, classID =
        pcall(get, id)
    if not ok then
        return nil
    end
    return name, link, quality, level, minLevel, itemType, subType, stack, equip, texture, sellPrice, classID
end

-- Units of an item the player has: in the bags, and with `bank` the bank too (as last seen); 0
-- when unknown.
function C.itemCount(id, bank)
    -- The documented form takes the item as ItemInfo (an ID is accepted); the bare GetItemCount is
    -- its deprecated fallback, kept for a client that does not have C_Item.
    local count = C_Item and C_Item.GetItemCount or GetItemCount
    if not count then
        return 0
    end
    local ok, n = pcall(count, id, bank)
    return ok and U.finite(n) and n or 0
end

function C.itemIcon(id)
    if C_Item and C_Item.GetItemIconByID then
        return C_Item.GetItemIconByID(id)
    end
    return 134400
end

-- Bags --------------------------------------------------------------------------------------------
-- Slots of bag `bag` (0 without the container API) and the item in a slot (ContainerItemInfo or nil).
function C.bagSlots(bag)
    if not C_Container then
        return 0
    end
    return C_Container.GetContainerNumSlots(bag) or 0
end

function C.bagItem(bag, slot)
    return C_Container and C_Container.GetContainerItemInfo(bag, slot)
end

-- Uses the item in a slot: sells it while a merchant is open.
function C.useBagItem(bag, slot)
    C_Container.UseContainerItem(bag, slot)
end

-- Merchants ---------------------------------------------------------------------------------------
-- Merchant item info: C_MerchantFrame on modern clients (the global may be missing, as GetItemInfo
-- is on WoW Forever), the old global otherwise.
function C.merchantItem(i)
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
