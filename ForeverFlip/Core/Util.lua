ForeverFlip = ForeverFlip or {}
local F = ForeverFlip
F.version = "3.1.0"

-- The ways stock is bought and sold, in the one order every page lists them (Deals, Journal and
-- profit, the Selling note). `id` is the saved name (positions, lots, the log: old names kept, so
-- "flip" is Resale and "median" is Market reset), `label` the page's name, `note` the word on
-- Selling -> My items, `page` the Deals page that buys it (nil: made by the player's own work).
F.STRATEGIES = {
    { id = "flip", label = "Resale", note = "resale", page = "deals:flip" },
    { id = "median", label = "Market reset", note = "market reset", page = "deals:median" },
    { id = "bid", label = "Bids", note = "bid", page = "bids" },
    { id = "vendor", label = "To vendor", note = "vendor deal", page = "deals:vendor" },
    { id = "craft", label = "Crafting", note = "crafting" },
    { id = "disenchant", label = "Disenchant", note = "disenchant" },
}
F.STRATEGY = {}
for i, st in ipairs(F.STRATEGIES) do
    st.order = i
    F.STRATEGY[st.id] = st
end
local U = {}
F.Util = U

-- The fixed judgements of the addon, in one place. They are not settings (the player never sees
-- them), but each is a choice about money that could be one: change them here, never in a module.
--   routeGain, routeSure, routeFair: when held stock goes to a vendor instead of the auction house
--     (Market.routeVerdict);
--   keepDays: how long stock bought for the auction house keeps that way (Trade.boughtWay);
--   planReturn: the least return a crafting plan buys materials for (Crafting.plan);
--   gapShare: Analytics counts a lot as cheap under this share of the market price;
--   trendMove: Analytics counts a price as rising or falling past this change.
U.TUNING = {
    routeGain = 0.1,
    routeSure = 0.5,
    routeFair = 0.5,
    keepDays = 14,
    planReturn = 0.05,
    gapShare = 0.95,
    trendMove = 0.05,
}

-- True when the client hides the value from addons (a "secret" value: chat text on newer clients).
-- Such a value cannot be read, compared or indexed without an error.
function U.secret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- "3.1.0" or "3.1.0-beta.2" as {major, minor, patch, stage, n}: alpha < beta < rc < the release.
-- nil when the text is not a version.
local STAGES = { alpha = 0, beta = 1, rc = 2, [""] = 3 }
function U.parseVersion(text)
    local a, b, c, rest = tostring(text or ""):match("^v?(%d+)%.(%d+)%.(%d+)(.*)$")
    if not a then
        return nil
    end
    local stage, n = "", 0
    if rest ~= "" then
        local s, num = rest:match("^%-(%a+)%.?(%d+)$")
        if not s or not STAGES[s] then
            return nil
        end
        stage, n = s, tonumber(num)
    end
    return { tonumber(a), tonumber(b), tonumber(c), STAGES[stage], n }
end

-- True when version `a` is newer than version `b` (false when either is not a version).
function U.versionNewer(a, b)
    local x, y = U.parseVersion(a), U.parseVersion(b)
    if not x or not y then
        return false
    end
    for i = 1, 5 do
        if x[i] ~= y[i] then
            return x[i] > y[i]
        end
    end
    return false
end

-- A copy of `list` in the order of `rank` ({ [key] = row }, as Engine.screen().order gives it):
-- what the player sees top to bottom first, the rest after it in the list's own order.
-- `keyOf(entry)` gives an entry's key (entry.key when not given). Nil rank: the list as it is.
function U.inOrder(list, rank, keyOf)
    local out = {}
    for i, e in ipairs(list or {}) do
        out[i] = e
    end
    if type(rank) ~= "table" then
        return out
    end
    local pos, rows = {}, {}
    for i, e in ipairs(out) do
        local key
        if keyOf then
            key = keyOf(e)
        elseif type(e) == "table" then
            key = e.key
        else
            key = e
        end
        pos[e], rows[e] = i, key ~= nil and rank[key] or nil
    end
    table.sort(out, function(a, b)
        local ra, rb = rows[a], rows[b]
        if ra and rb and ra ~= rb then
            return ra < rb
        end
        if (ra == nil) ~= (rb == nil) then
            return ra ~= nil
        end
        return pos[a] < pos[b]
    end)
    return out
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
-- A Lua pattern for one of the game's message templates ("You won an auction for %s"): the %s
-- becomes a capture, everything else matches literally. nil when the template is missing.
function U.globalPattern(template)
    if type(template) ~= "string" then
        return nil
    end
    local s = template:gsub("%%s", "\1"):gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0"):gsub("\1", "(.+)")
    return "^" .. s .. "$"
end

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
        -- A smaller coin after a larger one keeps two digits (1g 05s, 26s 00c), so the columns of
        -- a table line up and 26s 0c is not read as 26s 0 gold.
        local n = i > 1 and string.format("%02d", p[2]) or tostring(p[2])
        shown[i] = U.coins and (n .. COIN[p[1]]) or string.format(LETTER[p[1]]:gsub("%%d", "%%s"), n)
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

local COPPER = { g = 10000, s = 100, c = 1 }
local SMALLER = { g = "s", s = "c" }

-- Parses "1g 20s 5c", "20s", "1.5g" or a bare number of silver. A number after the last coin is
-- the next smaller coin: "5g 50" and "1g50" are 5g 50s and 1g 50s (the 50 was dropped, and a post
-- typed as 5g 50 went up at 5 gold). No price is negative: "-5g" is nil, not 5 gold.
function U.parseMoney(text)
    if type(text) ~= "string" then
        return nil
    end
    text = text:lower():gsub(",", ".")
    if text:find("-", 1, true) then
        return nil
    end
    local total, last, rest = 0, nil, 1
    for amount, unit, after in text:gmatch("([%d%.]+)%s*([gsc])()") do
        local n = tonumber(amount)
        if not n then
            return nil
        end
        total = total + n * COPPER[unit]
        last, rest = unit, after
    end
    local tail = text:match("^%s*([%d%.]+)%s*$", rest)
    if tail then
        local n, unit = tonumber(tail), "s" -- a bare number alone is silver
        if last then
            unit = SMALLER[last] -- after copper there is no smaller coin
        end
        if not n or not unit then
            return nil
        end
        total = total + n * COPPER[unit]
    elseif not last then
        return nil
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
-- The call itself is the capability adapter's (Compat.itemInfo).
function U.itemInfo(id)
    return F.Compat.itemInfo(id)
end
