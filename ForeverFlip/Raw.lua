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
R.KEEP = 2 -- full scans kept for the helper (each one is several megabytes)

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

-- One auction of the scan being read; called for every row, in scan order, before item data loads.
function R.capture(j, i)
    if not j.raw then
        return
    end
    local ok, r = pcall(F.AH.replicateRaw, i)
    if not ok or not r then
        j.raw[#j.raw + 1] = ""
        j.rawSeal = R.chain(j.rawSeal or 0, "")
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
    j.raw[#j.raw + 1] = line
    j.rawSeal = R.chain(j.rawSeal or 0, line)
end

-- The scan is processed: its lines become one saved entry.
function R.finish(j)
    if not j.raw then
        return
    end
    local realm, faction = j.scope:match("^(.*)%-([^%-]+)$")
    ForeverFlipRaw = type(ForeverFlipRaw) == "table" and ForeverFlipRaw or {}
    ForeverFlipRaw.format = R.FORMAT
    ForeverFlipRaw.scans = type(ForeverFlipRaw.scans) == "table" and ForeverFlipRaw.scans or {}
    table.insert(ForeverFlipRaw.scans, 1, {
        scope = j.scope,
        realm = realm,
        faction = faction,
        at = j.finishAt,
        count = #j.raw,
        addon = F.version,
        seal = R.chain(j.rawSeal or 0, j.scope .. "|" .. j.finishAt .. "|" .. #j.raw),
        rows = table.concat(j.raw, "\n"),
    })
    while #ForeverFlipRaw.scans > R.KEEP do
        table.remove(ForeverFlipRaw.scans)
    end
    j.raw, j.rawSeal = nil, nil
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
    local merged = 0
    for _, text in ipairs(data.scans) do
        local snap = F.Share.decode(text)
        if snap and F.Share.merge(snap, "community", "community") then
            merged = merged + 1
        end
    end
    R.community = { generated = data.generated, scans = #data.scans, merged = merged }
    return merged
end
