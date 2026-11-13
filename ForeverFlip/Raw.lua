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
function R.hash(text)
    local h = 0
    for k = 1, #text do
        h = (h * 31 + text:byte(k)) % P
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
        .. (kind and kind:sub(1, 1) or "")
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
-- { "FF1|..." } }, merged like scans shared in game. Returns the number of scans merged.
function R.importCommunity()
    local data = ForeverFlipShared
    if type(data) ~= "table" or type(data.scans) ~= "table" or not F.db or not F.db.settings.shareReceive then
        return 0
    end
    -- The player's own scans come back among them once uploaded, and are in the history already.
    -- The merge tells apart only the last scan read here, and this runs at login, before even
    -- that one is restored.
    local sent = R.uploaded()
    local merged = 0
    for _, text in ipairs(data.scans) do
        local snap = F.Share.decode(text)
        if
            snap
            and not sent[tostring(snap.scope) .. "@" .. tostring(snap.at)]
            and F.Share.merge(snap, "community", "community")
        then
            merged = merged + 1
        end
    end
    R.community = { generated = data.generated, scans = #data.scans, merged = merged }
    return merged
end
