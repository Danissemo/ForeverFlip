ForeverFlip = ForeverFlip or {}
local F = ForeverFlip
F.version = "5.5.0-preview"
local U = {}
F.Util = U
function U.finite(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end
function U.number(n, fallback, lo, hi)
    n = tonumber(n)
    if not U.finite(n) then
        return fallback
    end
    if lo then
        n = math.max(lo, n)
    end
    if hi then
        n = math.min(hi, n)
    end
    return n
end
-- Snap only within a few binary rounding units, not a monetary tolerance.
local function integerBoundary(n)
    local nearest = math.floor(n + 0.5)
    if math.abs(n - nearest) <= math.max(1, math.abs(n)) * 4.440892098500626e-16 then
        return nearest
    end
    return n
end
function U.round(n)
    return math.floor(n + 0.5 + math.abs(n) * 4.440892098500626e-16)
end
function U.floor(n)
    return math.floor(integerBoundary(n))
end
function U.ceil(n)
    return math.ceil(integerBoundary(n))
end
function U.copper(s)
    s = tostring(s or ""):gsub(",", "."):gsub("%s", "")
    if not s:match("^%d+%.?%d*$") then
        return nil
    end
    local n = tonumber(s)
    if not U.finite(n) or n < 0 or n > 100000000 then
        return nil
    end
    return U.round(n * 10000)
end
function U.money(n)
    n = U.round(U.number(n, 0))
    local sign = n < 0 and "-" or ""
    n = math.abs(n)
    return string.format("%s%dg %02ds %02dc", sign, math.floor(n / 10000), math.floor(n % 10000 / 100), n % 100)
end
function U.gold(n)
    return string.format("%.4f", (n or 0) / 10000)
end
function U.key(k)
    if type(k) == "number" then
        k = { itemID = k }
    end
    if type(k) ~= "table" then
        return nil
    end
    local id = tonumber(k.itemID)
    if not U.finite(id) or id < 1 or id ~= math.floor(id) then
        return nil
    end
    for _, v in ipairs({ k.itemLevel or 0, k.itemSuffix or 0, k.battlePetSpeciesID or 0 }) do
        if not U.finite(v) or v ~= math.floor(v) or math.abs(v) > 1e9 then
            return nil
        end
    end
    return table.concat({ id, k.itemLevel or 0, k.itemSuffix or 0, k.battlePetSpeciesID or 0 }, ":")
end
function U.fromKey(key)
    local a, b, c, d = tostring(key):match("^(%d+):(%d+):(%-?%d+):(%d+)$")
    if a then
        return {
            itemID = tonumber(a),
            itemLevel = tonumber(b),
            itemSuffix = tonumber(c),
            battlePetSpeciesID = tonumber(d),
        }
    end
end
function U.copy(t, seen, depth)
    if type(t) ~= "table" then
        return t
    end
    seen = seen or {}
    depth = depth or 0
    if seen[t] then
        return seen[t]
    end
    if depth > 48 then
        return {}
    end
    local out = {}
    seen[t] = out
    for k, v in pairs(t) do
        if type(k) == "string" or type(k) == "number" then
            out[k] = U.copy(v, seen, depth + 1)
        end
    end
    return out
end
function U.median(values)
    local a = {}
    for _, v in ipairs(values or {}) do
        if U.finite(v) then
            a[#a + 1] = v
        end
    end
    table.sort(a)
    local n = #a
    if n == 0 then
        return nil
    end
    return n % 2 == 1 and a[(n + 1) / 2] or (a[n / 2] + a[n / 2 + 1]) / 2
end
function U.sortedKeys(t)
    local a = {}
    for k in pairs(t or {}) do
        a[#a + 1] = k
    end
    table.sort(a, function(x, y)
        return tostring(x) < tostring(y)
    end)
    return a
end
function U.name(id)
    local get = GetItemInfo or (C_Item and C_Item.GetItemInfo)
    if get then
        local ok, n = pcall(get, id)
        if ok and n then
            return n
        end
    end
    return "item:" .. tostring(id)
end
function U.vendor(id)
    local get = GetItemInfo or (C_Item and C_Item.GetItemInfo)
    if get then
        local ok, _, _, _, _, _, _, _, _, _, _, price = pcall(get, id)
        if ok and U.finite(price) and price > 0 then
            return price
        end
    end
end
