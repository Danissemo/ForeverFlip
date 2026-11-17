-- Full scans as they came from the server, for the ForeverFlip Sync helper. With the setting on,
-- every auction of a full scan is kept in scan order (which is the order the auctions were created),
-- one line per auction, and the last scans are saved in ForeverFlipRaw. The helper uploads them to
-- the community data repository, where they are archived unchanged and summarised for everyone.
--
-- Line format (decimal numbers, empty when unknown):
--   itemID,count,buyout,minBid,bid,timeLeftBand,own,kind,name
-- buyout is for the whole stack; timeLeftBand is 0 (< 30 min) to 3 (> 12 h); own is 1 for the
-- player's own auction when the server tells; kind is c (commodity), i (item) or g (gear), empty
-- while the game has not loaded the item; name is the full item name, for gear only.
local F = ForeverFlip
local U = F.Util
local R = {}
F.Raw = R

R.FORMAT = "FFR1"
-- Full scans kept for the helper until it uploaded them (each one is several megabytes, and the game
-- writes them only at /reload or logout): two hours of scans every 15 minutes.
R.KEEP = 8

-- Checksum of a scan ("seal"): the helper and the data repository recompute it and refuse a scan
-- whose lines were changed after the game read them. sync/ffscan.py computes the same numbers.
local P = 2147483647
local byte = string.byte
-- Four bytes a step, one remainder per step: h stays below P (2^31), and 31^4 * 2^31 plus the bytes
-- stays below 2^53, so the double holds every step exactly and the result is the byte-by-byte one.
-- Every line of a full scan (up to 290 000) is hashed while it is read: byte by byte it was a third
-- of the reading time.
function R.hash(text)
    local h, n, k = 0, #text, 1
    while k + 3 <= n do
        local a, b, c, d = byte(text, k, k + 3)
        h = ((((h * 31 + a) * 31 + b) * 31 + c) * 31 + d) % P
        k = k + 4
    end
    while k <= n do
        h = (h * 31 + byte(text, k)) % P
        k = k + 1
    end
    return h
end

function R.chain(seal, text)
    return (seal * 1000003 + R.hash(text) + 1) % P
end

function R.active()
    return F.db and F.db.settings.rawScans or false
end

-- Lines are joined a slice at a time while the scan is read: joining all lines of a large scan
-- (290 000 auctions, 8 MB) at its end made one long frame of its own.
R.SLICE = 5000

-- Appends one line; a full slice of lines becomes one text (j.rawParts).
local function add(j, line)
    local raw = j.raw
    raw[#raw + 1] = line
    j.rawSeal = R.chain(j.rawSeal or 0, line)
    if #raw >= R.SLICE then
        j.rawParts = j.rawParts or {}
        j.rawParts[#j.rawParts + 1] = table.concat(raw, "\n")
        j.rawLines = (j.rawLines or 0) + #raw
        j.raw = {}
    end
end

-- One auction of the scan being read; called for every row, in scan order, before item data loads.
-- `r`: its fields (F.AH.replicateRaw, read once with the row the scan reads), nil when the row could
-- not be read.
local KIND = { commodity = "c", item = "i", gear = "g" }
function R.capture(j, r)
    if not j.raw then
        return
    end
    if not r then
        add(j, "")
        return
    end
    local kind = F.AH.kindOf(r.id)
    local name = ""
    if r.link and kind == "gear" then
        name = (U.linkName(r.link) or ""):gsub("[,\n]", " ")
    end
    local line = r.id
        .. ","
        .. (r.count or "")
        .. ","
        .. (r.buyout or "")
        .. ","
        .. (r.minBid or "")
        .. ","
        .. (r.bid or "")
        .. ","
        .. (r.band or "")
        .. ","
        .. (r.own and "1" or "0")
        .. ","
        .. (KIND[kind] or "")
        .. ","
        .. name
    add(j, line)
end

-- The scan is processed: its lines become one saved entry.
-- Scans the helper has uploaded (it lists them in the ForeverFlip_Shared addon): "scope@time".
function R.uploaded()
    local data = ForeverFlipShared
    return type(data) == "table" and type(data.uploaded) == "table" and data.uploaded or {}
end

function R.finish(j)
    if not j.raw then
        return
    end
    local realm, faction = j.scope:match("^(.*)%-([^%-]+)$")
    -- The slices joined while reading, and the lines after the last of them.
    local parts, count = j.rawParts or {}, (j.rawLines or 0) + #j.raw
    if #j.raw > 0 then
        parts[#parts + 1] = table.concat(j.raw, "\n")
    end
    ForeverFlipRaw = type(ForeverFlipRaw) == "table" and ForeverFlipRaw or {}
    ForeverFlipRaw.format = R.FORMAT
    ForeverFlipRaw.scans = type(ForeverFlipRaw.scans) == "table" and ForeverFlipRaw.scans or {}
    table.insert(ForeverFlipRaw.scans, 1, {
        scope = j.scope,
        realm = realm,
        faction = faction,
        at = j.finishAt,
        count = count,
        addon = F.version,
        seal = R.chain(j.rawSeal or 0, j.scope .. "|" .. j.finishAt .. "|" .. count),
        rows = table.concat(parts, "\n"),
    })
    local sent = R.uploaded()
    for i = #ForeverFlipRaw.scans, 2, -1 do
        local s = ForeverFlipRaw.scans[i]
        if type(s) == "table" and sent[tostring(s.scope) .. "@" .. tostring(s.at)] then
            table.remove(ForeverFlipRaw.scans, i)
        end
    end
    while #ForeverFlipRaw.scans > R.KEEP do
        table.remove(ForeverFlipRaw.scans)
    end
    j.raw, j.rawSeal, j.rawParts, j.rawLines = nil, nil, nil, nil
end

-- Scans the helper reports shared are dropped at login, not only after the next full scan: each
-- holds several megabytes, and the Sharing page counted them as still waiting for the helper.
function R.prune()
    local scans = type(ForeverFlipRaw) == "table" and ForeverFlipRaw.scans
    if type(scans) ~= "table" then
        return 0
    end
    local sent, dropped = R.uploaded(), 0
    for i = #scans, 1, -1 do
        local s = scans[i]
        if type(s) == "table" and sent[tostring(s.scope) .. "@" .. tostring(s.at)] then
            table.remove(scans, i)
            dropped = dropped + 1
        end
    end
    return dropped
end

-- What the helper reports shared: how many scans, and when the newest of them was taken.
function R.sharedSummary()
    local count, newest = 0, nil
    for ident in pairs(R.uploaded()) do
        count = count + 1
        local at = tonumber(tostring(ident):match("@(%d+)$"))
        if at and (not newest or at > newest) then
            newest = at
        end
    end
    return count, newest
end

function R.saved()
    local scans = type(ForeverFlipRaw) == "table" and ForeverFlipRaw.scans
    return type(scans) == "table" and scans or {}
end

-- Community data written by the helper into the ForeverFlip_Shared addon: { generated, scans =
-- { "FF1|..." }, status = { [scope] = { checked_at, published_at, reason } } }, merged like scans
-- shared in game. Returns the number of scans merged. R.community keeps, per auction house, how many
-- scans came, how many were merged and how many were the player's own, with the data repository's
-- status, so the Share tab can tell "downloaded" from "published" and say why there is no price.
function R.importCommunity()
    local data = ForeverFlipShared
    if type(data) ~= "table" or type(data.scans) ~= "table" or not F.db or not F.db.settings.shareReceive then
        return 0
    end
    -- The player's own scans come back among them once uploaded: they are no community price, but
    -- they fill the player's own history where it has no such day (the merge keeps the prices it
    -- has). The helper's list tells them apart; the merge alone knows only the last scan read here.
    local sent = R.uploaded()
    local merged = 0
    local scopes = {}
    local function house(scope)
        scopes[scope] = scopes[scope] or { scans = 0, merged = 0, own = 0, newest = 0 }
        return scopes[scope]
    end
    for _, text in ipairs(data.scans) do
        local snap = F.Share.decode(text)
        local info = snap and house(tostring(snap.scope))
        if info then
            info.scans = info.scans + 1
            info.newest = math.max(info.newest, tonumber(snap.at) or 0)
        end
        if snap and sent[tostring(snap.scope) .. "@" .. tostring(snap.at)] then
            info.own = info.own + 1
            -- The player's own scan: merged as the player's prices when the history does not hold
            -- it (after Reset all data, on another computer), skipped when it does (Share.hold).
            -- Never a community price.
            if F.Share.merge(snap, "own", "own") then
                info.restored = (info.restored or 0) + 1
            end
        elseif snap then
            local ok, why = F.Share.merge(snap, "community", "community")
            if ok then
                merged = merged + 1
                info.merged = info.merged + 1
            end
            -- T31: a scan of the house that Sync brought counts as fresh data, as a full scan
            -- does, once it is in the history: merged now, or at an earlier login ("duplicate").
            -- A scan refused (too old, another realm, damaged) or a Sync run that brought no new
            -- scan moves nothing.
            if ok or why == "duplicate" then
                local market = F.Data.market(F.db, snap.scope)
                market.syncScanAt = math.max(market.syncScanAt or 0, snap.at)
            end
        end
    end
    if type(data.status) == "table" then
        for scope, status in pairs(data.status) do
            if type(status) == "table" then
                local info = house(tostring(scope))
                info.publishedAt = tonumber(status.published_at)
                info.checkedAt = tonumber(status.checked_at)
                info.reason = type(status.reason) == "string" and status.reason or nil
            end
        end
    end
    R.community = { generated = data.generated, scans = #data.scans, merged = merged, scopes = scopes }
    return merged
end

-- Reading the raw scans back (T32: the derived sales statistics are rebuilt from them) -----------
-- The raw scans of one auction house, oldest first: a scan saved twice (same time) once, scans of
-- other houses never, entries without rows or time left out.
function R.scansFor(scope)
    local out, seen = {}, {}
    for _, s in ipairs(R.saved()) do
        if
            type(s) == "table"
            and s.scope == scope
            and U.finite(s.at)
            and type(s.rows) == "string"
            and not seen[s.at]
        then
            seen[s.at] = true
            out[#out + 1] = s
        end
    end
    table.sort(out, function(a, b)
        return a.at < b.at
    end)
    return out
end

-- One raw line as { id, count, buyout, band, own, kind, name }; nil for a row the game could not
-- read (an empty line). kind is nil while the item was not loaded (its rows say nothing then).
function R.parse(line)
    local id, count, buyout, band, own, kind, name =
        line:match("^(%d+),(%d*),(%d*),[^,]*,[^,]*,(%d*),(%d?),(%a?),(.*)$")
    id = tonumber(id)
    if not id then
        return nil
    end
    local kinds = { c = "commodity", i = "item", g = "gear" }
    return {
        id = id,
        count = tonumber(count) or 0,
        buyout = tonumber(buyout) or 0,
        band = tonumber(band),
        own = own == "1",
        kind = kinds[kind],
        name = name ~= "" and name or nil,
    }
end

-- T07: the cheapest unit price of item `id` in each raw full scan of `scope`, oldest first:
-- { { at, unit, n = units listed }, ... }. `name` (optional, lower case): only gear of that name.
-- The player's own lots are left out (they are not the market's price).
function R.pricePoints(scope, id, name)
    local out = {}
    local prefix = tostring(id) .. ","
    for _, scan in ipairs(R.scansFor(scope)) do
        local text = scan.rows
        local best, units = nil, 0
        local function take(line)
            local r = R.parse(line)
            if
                r
                and r.id == id
                and not r.own
                and r.count > 0
                and r.buyout > 0
                and (not name or not r.name or string.lower(r.name) == name)
            then
                local unit = math.floor(r.buyout / r.count + 0.5)
                best = best and math.min(best, unit) or unit
                units = units + r.count
            end
        end
        local function lineAt(start)
            local stop = text:find("\n", start, true)
            return text:sub(start, (stop or #text + 1) - 1)
        end
        if text:sub(1, #prefix) == prefix then
            take(lineAt(1))
        end
        local pos = 1
        while true do
            local at = text:find("\n" .. prefix, pos, true)
            if not at then
                break
            end
            take(lineAt(at + 1))
            pos = at + 1
        end
        if best then
            out[#out + 1] = { at = scan.at, unit = best, n = units }
        end
    end
    return out
end
-- A reader over the lines of a raw scan: R.readLines(reader, done, fn) calls fn(line) for each
-- line until done() says the frame's budget is spent; true once every line was read.
function R.reader(scan)
    return { text = scan.rows, pos = 1, lines = 0 }
end

function R.readLines(reader, done, fn)
    local text = reader.text
    local n = #text
    while reader.pos <= n do
        local stop = text:find("\n", reader.pos, true)
        local line = text:sub(reader.pos, (stop or n + 1) - 1)
        reader.pos = (stop or n) + 1
        reader.lines = reader.lines + 1
        fn(line)
        if done() then
            return reader.pos > n
        end
    end
    return true
end
