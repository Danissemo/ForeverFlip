ForeverFlip = ForeverFlip or {}
local F = ForeverFlip
F.version = "1.2.0-beta.7"
local U = {}
F.Util = U

-- True when the client hides the value from addons (a "secret" value: chat text on newer clients).
-- Such a value cannot be read, compared or indexed without an error.
function U.secret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

function U.finite(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

function U.clamp(n, lo, hi)
    return math.max(lo, math.min(hi, n))
end

-- Item keys are strings:
--   "c:<itemID>"          commodity (stackable goods, bought by quantity)
--   "i:<itemID>"          plain item (bags, recipes, ...), one auction per purchase
--   "g:<itemID>:<name>"   gear: on WoW Forever one item ID has several endings ("of the Wolf")
--                         that only the full name tells apart; the name is stored in lower case.
function U.key(kind, id, name)
    if kind == "commodity" then
        return "c:" .. id
    elseif kind == "gear" then
        return "g:" .. id .. ":" .. string.lower(name or "")
    end
    return "i:" .. id
end

function U.parseKey(key)
    if type(key) ~= "string" then
        return nil
    end
    local tag, id, rest = key:match("^(%a):(%d+):?(.*)$")
    id = tonumber(id)
    if not id then
        return nil
    end
    local kind = tag == "c" and "commodity" or tag == "g" and "gear" or tag == "i" and "item" or nil
    if not kind then
        return nil
    end
    return { kind = kind, id = id, name = kind == "gear" and rest or nil }
end

function U.linkName(link)
    return type(link) == "string" and link:match("|h%[(.-)%]|h") or nil
end

-- Gear and plain items are listed in whole silver only; commodities may use copper.
function U.stepDown(price, kind)
    if not U.finite(price) or price <= 0 then
        return 0
    end
    if kind == "commodity" then
        return math.floor(price)
    end
    return math.floor(price / 100) * 100
end

function U.stepUp(price, kind)
    if not U.finite(price) or price <= 0 then
        return 0
    end
    if kind == "commodity" then
        return math.ceil(price)
    end
    return math.ceil(price / 100) * 100
end

-- The highest legal price strictly below `price`.
function U.below(price, kind)
    if kind == "commodity" then
        return math.max(0, math.ceil(price) - 1)
    end
    return math.max(0, (math.ceil(price / 100) - 1) * 100)
end

-- Money as shown: digits with gold, silver and copper coins (as the game shows money). Without
-- the coin textures (U.coins = false) the letters g, s and c in their colours.
U.coins = true
local COIN = {
    g = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
    s = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
    c = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}
local LETTER = { g = "|cffffd100%dg|r", s = "|cffc7c7cf%ds|r", c = "|cffeda55f%dc|r" }

local function parts(copper)
    copper = math.floor(math.abs(copper) + 0.5)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local out = {}
    if g > 0 then
        out[#out + 1] = { "g", g }
    end
    if s > 0 or g > 0 then
        out[#out + 1] = { "s", s }
    end
    out[#out + 1] = { "c", c }
    return out
end

function U.money(copper)
    if not U.finite(copper) then
        return "?"
    end
    local shown = {}
    local all = parts(copper)
    if #all > 2 then
        all[3] = nil -- gold and silver: the copper is left out
    end
    for i, p in ipairs(all) do
        shown[i] = U.coins and (p[2] .. COIN[p[1]]) or string.format(LETTER[p[1]], p[2])
    end
    return (copper < 0 and "-" or "") .. table.concat(shown, " ")
end

-- Money without colour codes or coins, for edit boxes and text ("1g 20s 5c").
function U.plainMoney(copper)
    if not U.finite(copper) then
        return "?"
    end
    local shown = {}
    for i, p in ipairs(parts(copper)) do
        shown[i] = p[2] .. p[1]
    end
    return (copper < 0 and "-" or "") .. table.concat(shown, " ")
end

-- Parses "1g 20s 5c", "20s", "1.5g" or a bare number of silver.
function U.parseMoney(text)
    if type(text) ~= "string" then
        return nil
    end
    text = text:lower():gsub(",", ".")
    local total, found = 0, false
    for amount, unit in text:gmatch("([%d%.]+)%s*([gsc])") do
        local n = tonumber(amount)
        if not n then
            return nil
        end
        total = total + n * (unit == "g" and 10000 or unit == "s" and 100 or 1)
        found = true
    end
    if not found then
        local n = tonumber(text:match("^%s*([%d%.]+)%s*$") or "")
        if not n then
            return nil
        end
        total = n * 100
    end
    return math.floor(total + 0.5)
end

function U.copy(t)
    if type(t) ~= "table" then
        return t
    end
    local out = {}
    for k, v in pairs(t) do
        out[k] = U.copy(v)
    end
    return out
end

-- GetItemInfo moved to C_Item on the WoW Forever client; the global may be missing.
function U.itemInfo(id)
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
