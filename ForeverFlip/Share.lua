-- Sharing full scans with other ForeverFlip users. A shared scan is a summary of a full scan: per
-- item seen, its usual price, cheapest price and units listed. It travels in hidden addon messages
-- to the guild, the group or one player, or as a text to copy anywhere (export / import).
--
-- A received scan of the player's realm is merged into the price history: today's (or that day's)
-- record of each item, the time-of-week pattern, and the usual price when it is newer than the
-- player's own scan (F.Market.usual). It never creates deals by itself: deals still come from the
-- player's own scans and live checks.
local F = ForeverFlip
local U = F.Util
local S = {}
F.Share = S

S.PREFIX = "ForeverFlip"
S.VERSION = 1
S.CHUNK = 240 -- payload characters per addon message (a message holds 255)
S.PACE = 0.3 -- seconds between two messages sent
S.MAX_AGE = 7 * 86400 -- older scans are not merged
S.TIMEOUT = 300 -- seconds to wait for the rest of a scan being received

S.outbox = {}
S.inbox = {}
S.received = {} -- the latest merged scans: { from, at, items, how }

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
function S.enc(n)
    n = math.floor(n or 0)
    if n <= 0 then
        return "0"
    end
    local out = ""
    while n > 0 do
        local d = n % 36
        out = DIGITS:sub(d + 1, d + 1) .. out
        n = math.floor(n / 36)
    end
    return out
end

function S.dec(s)
    return tonumber(s, 36)
end

-- Item keys may hold any character of an item name; the separators are escaped.
local function esc(s)
    return (s:gsub("[%%,;|]", function(c)
        return string.format("%%%02X", c:byte())
    end))
end

local function unesc(s)
    return (s:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

-- Summary of the player's last full scan: { scope, at, items = { { key, m, min, n } } }.
function S.snapshot()
    local last = F.Scan.last
    if not last or not last.at or not F.db then
        return nil
    end
    local history = F.Data.market(F.db, last.scope).history
    local items, day = {}, math.floor(last.at / 86400)
    for key, h in pairs(history) do
        if type(h) == "table" and type(h.scan) == "table" and h.scan.at == last.at and U.finite(h.scan.market) then
            local today = h.days and h.days[#h.days]
            local low = today and today.d == day and today.min or h.scan.market
            items[#items + 1] = { key = key, m = h.scan.market, min = low, n = h.units or 0 }
        end
    end
    table.sort(items, function(a, b)
        return a.key < b.key
    end)
    return { scope = last.scope, at = last.at, items = items }
end

-- Text form: "FF1|<scope>|<time>|key,usual,cheapest,units;..." with numbers in base 36.
function S.encode(snap)
    local parts = {}
    for i, it in ipairs(snap.items) do
        parts[i] = esc(it.key) .. "," .. S.enc(it.m) .. "," .. S.enc(it.min) .. "," .. S.enc(it.n)
    end
    return "FF" .. S.VERSION .. "|" .. esc(snap.scope) .. "|" .. S.enc(snap.at) .. "|" .. table.concat(parts, ";")
end

function S.decode(text)
    if type(text) ~= "string" then
        return nil
    end
    -- Line breaks a chat or editor may add are dropped; item names keep their spaces.
    text = text:gsub("[\r\n]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    local version, scope, at, body = text:match("^FF(%d+)|([^|]+)|(%w+)|(.*)$")
    if tonumber(version) ~= S.VERSION then
        return nil
    end
    local snap = { scope = unesc(scope), at = S.dec(at), items = {} }
    if not snap.at then
        return nil
    end
    for record in body:gmatch("[^;]+") do
        local key, m, min, n = record:match("^([^,]+),(%w+),(%w+),(%w+)$")
        key = key and unesc(key)
        if key and U.parseKey(key) then
            snap.items[#snap.items + 1] = { key = key, m = S.dec(m), min = S.dec(min), n = S.dec(n) }
        end
    end
    return snap
end

local function realmOf(scope)
    return scope and scope:match("^(.*)%-[^%-]+$")
end

-- Merges a received scan. Returns the number of items merged, or nil and a reason.
function S.merge(snap, from, how)
    if not snap or not F.db then
        return nil, "invalid"
    end
    local now = F.Engine.clock()
    if realmOf(snap.scope) ~= tostring(GetRealmName and GetRealmName() or "?") then
        return nil, "other_realm"
    end
    if now - snap.at > S.MAX_AGE or snap.at > now + 600 then
        return nil, "old"
    end
    F.db.sharedSeen = type(F.db.sharedSeen) == "table" and F.db.sharedSeen or {}
    local id = snap.scope .. "@" .. snap.at
    if F.db.sharedSeen[id] then
        return nil, "duplicate"
    end
    local last = F.Scan.last
    if last and last.scope == snap.scope and math.abs((last.at or 0) - snap.at) < 120 then
        return nil, "duplicate" -- the same server scan the player read himself
    end
    F.db.sharedSeen[id] = now
    for k, at in pairs(F.db.sharedSeen) do
        if now - at > S.MAX_AGE then
            F.db.sharedSeen[k] = nil
        end
    end
    local history = F.Data.market(F.db, snap.scope).history
    local day = math.floor(snap.at / 86400)
    local merged = 0
    for _, it in ipairs(snap.items) do
        if U.finite(it.m) and it.m > 0 then
            local h = history[it.key]
            if type(h) ~= "table" then
                h = {}
                history[it.key] = h
            end
            if type(h.shared) ~= "table" or snap.at > (h.shared.at or 0) then
                h.shared = { at = snap.at, m = it.m, min = it.min, n = it.n, from = from }
            end
            S.mergeDay(h, day, it)
            if (it.n or 0) >= 10 or h.t then
                F.Market.recordTiming(h, it.m, snap.at)
            end
            merged = merged + 1
        end
    end
    table.insert(S.received, 1, { from = from, at = snap.at, items = merged, how = how, got = now })
    while #S.received > 10 do
        table.remove(S.received)
    end
    if F.Analytics then
        F.Analytics.invalidate()
    end
    F.Engine.changed()
    return merged
end

-- The item's record of `day`, kept in day order (at most F.Scan.DAYS records).
function S.mergeDay(h, day, it)
    h.days = type(h.days) == "table" and h.days or {}
    for _, d in ipairs(h.days) do
        if d.d == day then
            if it.min and (not d.min or it.min < d.min) then
                d.min = it.min
            end
            d.m = d.m or it.m
            d.n = d.n or it.n
            return
        end
    end
    local pos = #h.days + 1
    for i, d in ipairs(h.days) do
        if d.d > day then
            pos = i
            break
        end
    end
    table.insert(h.days, pos, { d = day, min = it.min, m = it.m, n = it.n })
    while #h.days > F.Scan.DAYS do
        table.remove(h.days, 1)
    end
end

-- Sending ------------------------------------------------------------------------------------------
function S.canSend()
    return C_ChatInfo ~= nil and C_ChatInfo.SendAddonMessage ~= nil
end

function S.register()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, S.PREFIX)
    end
end

-- Queues the last scan for `channel` ("GUILD", "PARTY", "RAID" or "WHISPER" with `target`).
function S.send(channel, target)
    if not S.canSend() then
        return false, "error"
    end
    if channel == "GUILD" and not (IsInGuild and IsInGuild()) then
        return false, "no_guild"
    end
    if (channel == "PARTY" or channel == "RAID") and not (IsInGroup and IsInGroup()) then
        return false, "no_group"
    end
    if channel == "WHISPER" and (not target or target == "") then
        return false, "values"
    end
    local snap = S.snapshot()
    if not snap or #snap.items == 0 then
        return false, "no_scan"
    end
    local text = S.encode(snap)
    local id = S.enc(snap.at % 46656) .. S.enc(math.random(0, 1295))
    local total = math.ceil(#text / S.CHUNK)
    for i = 1, total do
        S.outbox[#S.outbox + 1] = {
            channel = channel,
            target = target,
            text = id .. ":" .. S.enc(i) .. ":" .. S.enc(total) .. ":" .. text:sub((i - 1) * S.CHUNK + 1, i * S.CHUNK),
        }
    end
    S.sending = { items = #snap.items, total = total, channel = channel, target = target }
    F.Engine.changed()
    return true, "share_queued"
end

-- Called every frame: one message per S.PACE seconds.
function S.step(now)
    if #S.outbox == 0 or now < (S.nextSend or 0) then
        return
    end
    local m = table.remove(S.outbox, 1)
    S.nextSend = now + S.PACE
    pcall(C_ChatInfo.SendAddonMessage, S.PREFIX, m.text, m.channel, m.target)
    if #S.outbox == 0 then
        F.Engine.notify("share_sent")
    end
    F.Engine.changed()
end

-- After each own full scan: send it to the guild when the setting asks for it.
function S.afterScan()
    if F.db.settings.shareAuto and IsInGuild and IsInGuild() and #S.outbox == 0 then
        S.send("GUILD")
    end
end

-- Receiving ----------------------------------------------------------------------------------------
local function isSelf(sender)
    local name = Ambiguate and Ambiguate(sender, "none") or sender
    return name == (UnitName and UnitName("player"))
end

-- CHAT_MSG_ADDON
function S.onMessage(prefix, text, channel, sender)
    if prefix ~= S.PREFIX or type(text) ~= "string" or not F.db or not F.db.settings.shareReceive then
        return
    end
    if not sender or isSelf(sender) then
        return
    end
    local id, seq, total, payload = text:match("^(%w+):(%w+):(%w+):(.*)$")
    seq, total = S.dec(seq or ""), S.dec(total or "")
    if not id or not seq or not total or seq < 1 or seq > total or total > 5000 then
        return
    end
    local now = F.Engine.clock()
    for k, r in pairs(S.inbox) do
        if now - r.started > S.TIMEOUT then
            S.inbox[k] = nil
        end
    end
    local key = sender .. "/" .. id
    local r = S.inbox[key]
    if not r then
        r = { parts = {}, got = 0, total = total, started = now }
        S.inbox[key] = r
    end
    if not r.parts[seq] then
        r.parts[seq] = payload
        r.got = r.got + 1
    end
    if r.got >= r.total then
        S.inbox[key] = nil
        local name = Ambiguate and Ambiguate(sender, "none") or sender
        local merged = S.merge(S.decode(table.concat(r.parts)), name, channel)
        if merged then
            F.Engine.notify("share_received")
        end
    end
end

-- Import of a pasted text. Returns the number of items merged, or nil and a reason.
function S.import(text)
    local snap = S.decode(text)
    if not snap then
        return nil, "share_invalid"
    end
    return S.merge(snap, "text", "import")
end
