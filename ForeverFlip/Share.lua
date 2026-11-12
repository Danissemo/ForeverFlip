-- Sharing full scans with other ForeverFlip users. What is sent is the player's price history: per
-- item, the last scan's usual price, cheapest price and units listed, and the daily records of the
-- last S.HISTORY_DAYS days (cheapest price, usual price, units listed, units seen sold), which hold
-- every full scan of those days. Sending each scan would not fit: an addon message carries 255
-- characters and one scan already takes minutes to send. FF1 texts (one scan, as the community data
-- has) are still read. It travels in hidden addon messages
-- to the guild, the group or one player, to every ForeverFlip user of the realm over a hidden chat
-- channel (setting shareChannel), or as a text to copy anywhere (export / import).
--
-- The realm channel (like AuctionHouse Forever's) works by asking:
--   !Q|<scope>|<time>          "my newest scan of this house is from <time>" (after joining)
--   !H|<scope>|<time>          "I have a scan from <time>" (after a full scan, or to answer a Q)
--   !R|<holder>|<scope>|<time> "<holder>, please send it"; the holder sends it once on the channel
--                              and everyone who is behind keeps it
-- A random short wait before answering lets one player answer for everyone.
--
-- Received items far from what the player already knows (more than S.TRUST times off the usual
-- price) are left out: one player's silly or edited scan cannot move the prices.
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
-- FF3: with daily records whose sales are confirmed (not reposts). FF2 has the same form, but its
-- sales were counted before that protection: its prices are read, its sales are not. FF1 (a
-- single scan) is still read.
S.VERSION = 3
S.HISTORY_DAYS = 7
S.CHUNK = 240 -- payload characters per addon message (a message holds 255)
S.PACE = 0.3 -- seconds between two messages sent
S.MAX_AGE = 7 * 86400 -- older scans are not merged
S.TIMEOUT = 300 -- seconds to wait for the rest of a scan being received
S.CHANNEL = "ForeverFlipPrices" -- the hidden realm channel
S.TRUST = 10 -- a shared price more than this many times off the usual price is left out
S.SAME_SCAN = 600 -- a scan this close to the newest one held adds nothing

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

-- The player's price history: { scope, at, history = true, items = { { key, m, min, n, days } } }.
-- m, min and n are the last full scan's (0 for an item it did not see: its usual price is not
-- claimed as current); days = { { o = days before the scan's day, min, m, n, s } }.
function S.snapshot()
    local last = F.Scan.last
    if not last or not last.at or not F.db or last.partial then
        return nil
    end
    local history = F.Data.market(F.db, last.scope).history
    local items, day = {}, math.floor(last.at / 86400)
    for key, h in pairs(history) do
        if type(h) == "table" then
            local seen = type(h.scan) == "table" and h.scan.at == last.at and U.finite(h.scan.market)
            local days = {}
            for _, d in ipairs(type(h.days) == "table" and h.days or {}) do
                local o = day - (d.d or 0)
                if o >= 0 and o < S.HISTORY_DAYS and (U.finite(d.m) or U.finite(d.min)) then
                    days[#days + 1] = { o = o, min = d.min, m = d.m, n = d.n, s = d.s }
                end
            end
            if seen or #days > 0 then
                local today = h.days and h.days[#h.days]
                local low = seen and (today and today.d == day and today.min or h.scan.market) or 0
                items[#items + 1] = {
                    key = key,
                    m = seen and h.scan.market or 0,
                    min = low,
                    n = seen and (h.units or 0) or 0,
                    days = days,
                }
            end
        end
    end
    table.sort(items, function(a, b)
        return a.key < b.key
    end)
    return { scope = last.scope, at = last.at, items = items, history = true }
end

-- Text form: "FF1|<scope>|<time>|key,usual,cheapest,units;..." with numbers in base 36. FF2 adds
-- ",<days>" to each item: records "o.cheapest.usual.units.sold" joined by "/".
function S.encode(snap)
    local parts = {}
    for i, it in ipairs(snap.items) do
        local record = esc(it.key) .. "," .. S.enc(it.m) .. "," .. S.enc(it.min) .. "," .. S.enc(it.n)
        if snap.history then
            local days = {}
            for k, d in ipairs(it.days or {}) do
                days[k] = S.enc(d.o)
                    .. "."
                    .. S.enc(d.min)
                    .. "."
                    .. S.enc(d.m)
                    .. "."
                    .. S.enc(d.n)
                    .. "."
                    .. S.enc(d.s)
            end
            record = record .. "," .. table.concat(days, "/")
        end
        parts[i] = record
    end
    return "FF"
        .. (snap.history and S.VERSION or 1)
        .. "|"
        .. esc(snap.scope)
        .. "|"
        .. S.enc(snap.at)
        .. "|"
        .. table.concat(parts, ";")
end

local function dayRecords(text, noSales)
    local days = {}
    for o, min, m, n, s in (text or ""):gmatch("(%w+)%.(%w+)%.(%w+)%.(%w+)%.(%w+)") do
        local function v(x)
            local value = S.dec(x)
            return value and value > 0 and value or nil
        end
        days[#days + 1] =
            { o = S.dec(o) or 0, min = v(min), m = v(m), n = S.dec(n) or 0, s = not noSales and S.dec(s) or 0 }
    end
    return days
end

-- A frame budget: true once `ms` milliseconds (or `count` steps without a timer) are used.
local function budget(ms, count)
    local t0 = debugprofilestop and debugprofilestop()
    local n = 0
    return function()
        n = n + 1
        if t0 then
            return n % 50 == 0 and debugprofilestop() - t0 >= ms
        end
        return n >= count
    end
end
S.budget = budget

-- Decoding in steps: S.decodeBegin reads the header, S.decodeSome the records (until `done()`).
function S.decodeBegin(text)
    if type(text) ~= "string" then
        return nil
    end
    -- Line breaks a chat or editor may add are dropped; item names keep their spaces.
    text = text:gsub("[\r\n]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    local version, scope, at, body = text:match("^FF(%d+)|([^|]+)|(%w+)|(.*)$")
    version = tonumber(version)
    if version ~= 1 and version ~= 2 and version ~= 3 then
        return nil
    end
    local snap = { scope = unesc(scope), at = S.dec(at), items = {}, history = version >= 2 or nil }
    snap.oldSales = version == 2 or nil
    if not snap.at then
        return nil
    end
    return { snap = snap, body = body, pos = 1 }
end

function S.decodeSome(ctx, done)
    local body = ctx.body
    while ctx.pos <= #body do
        local stop = body:find(";", ctx.pos, true) or (#body + 1)
        local record = body:sub(ctx.pos, stop - 1)
        ctx.pos = stop + 1
        local key, m, min, n, days
        if ctx.snap.history then
            key, m, min, n, days = record:match("^([^,]+),(%w+),(%w+),(%w+),([%w%./]*)$")
        else
            key, m, min, n = record:match("^([^,]+),(%w+),(%w+),(%w+)$")
        end
        key = key and unesc(key)
        if key and U.parseKey(key) then
            ctx.snap.items[#ctx.snap.items + 1] = {
                key = key,
                m = S.dec(m),
                min = S.dec(min),
                n = S.dec(n),
                days = days and dayRecords(days, ctx.snap.oldSales) or nil,
            }
        end
        if done and done() then
            return false
        end
    end
    return true
end

function S.decode(text)
    local ctx = S.decodeBegin(text)
    if not ctx then
        return nil
    end
    S.decodeSome(ctx)
    return ctx.snap
end

local function realmOf(scope)
    return scope and scope:match("^(.*)%-[^%-]+$")
end

-- Merging in steps: S.mergeBegin checks the scan (realm, age, seen before), S.mergeSome merges its
-- items (until `done()`), S.mergeEnd records it. S.merge does it all at once.
function S.mergeBegin(snap, from, how)
    if not snap or not F.db then
        return nil, "invalid"
    end
    local now = F.Engine.clock()
    if realmOf(snap.scope) ~= F.Engine.realm() then
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
    return {
        snap = snap,
        from = from,
        how = how,
        now = now,
        history = F.Data.market(F.db, snap.scope).history,
        day = math.floor(snap.at / 86400),
        merged = 0,
        i = 1,
    }
end

function S.mergeSome(ctx, done)
    local snap, history, day, from = ctx.snap, ctx.history, ctx.day, ctx.from
    while ctx.i <= #snap.items do
        local it = snap.items[ctx.i]
        ctx.i = ctx.i + 1
        local known = history[it.key] and F.Market.usual(history[it.key])
        local function trusted(price)
            return U.finite(price)
                and price > 0
                and (not U.finite(known) or known <= 0 or (price <= known * S.TRUST and price * S.TRUST >= known))
        end
        local current = trusted(it.m)
        local days = {}
        for _, d in ipairs(it.days or {}) do
            if trusted(d.m or d.min) then
                days[#days + 1] = d
            end
        end
        if current or #days > 0 then
            local h = history[it.key]
            if type(h) ~= "table" then
                h = {}
                history[it.key] = h
            end
            if current then
                if type(h.shared) ~= "table" or snap.at > (h.shared.at or 0) then
                    h.shared = { at = snap.at, m = it.m, min = it.min, n = it.n, from = from }
                end
                S.mergeDay(h, day, it)
                if (it.n or 0) >= 10 or h.t then
                    F.Market.recordTiming(h, it.m, snap.at)
                end
            end
            -- Earlier days of the sender's history: every full scan of theirs is in them.
            for _, d in ipairs(days) do
                S.mergeDay(h, day - d.o, d)
            end
            ctx.merged = ctx.merged + 1
        end
        if done and done() then
            return false
        end
    end
    return true
end

function S.mergeEnd(ctx)
    local snap, merged = ctx.snap, ctx.merged
    table.insert(
        S.received,
        1,
        { from = ctx.from, at = snap.at, scope = snap.scope, items = merged, how = ctx.how, got = ctx.now }
    )
    while #S.received > 10 do
        table.remove(S.received)
    end
    if F.Analytics then
        F.Analytics.invalidate()
    end
    F.Engine.changed()
    return merged
end

-- Merges a received scan at once (an import). Returns the number of items merged, or nil and a reason.
function S.merge(snap, from, how)
    local ctx, why = S.mergeBegin(snap, from, how)
    if not ctx then
        return nil, why
    end
    S.mergeSome(ctx)
    return S.mergeEnd(ctx)
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
            -- Units seen sold that day: the larger count (both saw the same market).
            if U.finite(it.s) and it.s > (d.s or 0) then
                d.s = it.s
            end
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
    table.insert(
        h.days,
        pos,
        { d = day, min = it.min, m = it.m, n = it.n, s = U.finite(it.s) and it.s > 0 and it.s or nil }
    )
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
    if channel == "CHANNEL" and not target then
        return false, "error"
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

-- One message per S.PACE seconds (S.step, every frame).
local function stepOutbox(now)
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

-- After each own full scan: send it to the guild when the setting asks for it, and tell the realm
-- channel that a new scan is there.
function S.afterScan()
    if F.db.settings.shareAuto and IsInGuild and IsInGuild() and #S.outbox == 0 then
        S.send("GUILD")
    end
    local snap = F.Scan.last
    if snap and snap.at then
        S.control("H", snap.scope, snap.at)
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
    if text:sub(1, 1) == "!" then
        S.onControl(text, sender)
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
        -- Decoded and merged a slice per frame (S.work): a scan of 20 000 items took over 100 ms in
        -- one go, a stall when it arrived.
        S.pending[#S.pending + 1] = { text = table.concat(r.parts), from = name, how = channel }
    end
end

-- Received scans waiting to be decoded and merged, and the one being worked.
S.pending = {}
function S.work()
    local w = S.working
    if not w then
        local next = table.remove(S.pending, 1)
        if not next then
            return
        end
        local ctx = S.decodeBegin(next.text)
        if not ctx then
            return
        end
        w = { stage = "decode", ctx = ctx, from = next.from, how = next.how }
        S.working = w
    end
    local done = budget(4, 400)
    if w.stage == "decode" then
        if not S.decodeSome(w.ctx, done) then
            return
        end
        local merge = S.mergeBegin(w.ctx.snap, w.from, w.how)
        if not merge then
            S.working = nil
            return
        end
        w.stage, w.ctx = "merge", merge
        return
    end
    if not S.mergeSome(w.ctx, done) then
        return
    end
    S.working = nil
    if S.mergeEnd(w.ctx) then
        F.Engine.notify("share_received")
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

-- The realm channel ---------------------------------------------------------------------------------
S.waits = {} -- delayed answers: { at, run, id }
S.heard = {} -- scope -> newest scan time announced on the channel (by anyone)
S.asked = {} -- "<holder>@<time>" -> when a request for it was seen or sent
S.served = {} -- "<scope>@<time>" -> when this player last sent it on the channel

function S.channelID()
    if not GetChannelName then
        return nil
    end
    local id = GetChannelName(S.CHANNEL)
    return id and id > 0 and id or nil
end

local function ownChannel(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if not F.Util.secret(v) and type(v) == "string" and v:lower():find(S.CHANNEL:lower(), 1, true) then
            return true
        end
    end
    return false
end

-- The channel never shows in a chat window, and its join and leave notices stay out of chat.
function S.hide()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. i]
        if frame then
            if ChatFrame_RemoveChannel then
                pcall(ChatFrame_RemoveChannel, frame, S.CHANNEL)
            elseif frame.RemoveChannel then
                pcall(frame.RemoveChannel, frame, S.CHANNEL)
            end
        end
    end
    if not S.filtered then
        local add = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
        if add then
            local function filter(_, _, ...)
                return ownChannel(...)
            end
            add("CHAT_MSG_CHANNEL_NOTICE", filter)
            add("CHAT_MSG_CHANNEL_NOTICE_USER", filter)
            add("CHAT_MSG_CHANNEL", filter)
            S.filtered = true
        end
    end
end

-- Joins the channel (setting shareChannel) and asks who has a newer scan.
function S.join()
    if not F.db or not F.db.settings.shareChannel or not S.canSend() then
        return false
    end
    if not S.channelID() then
        local join = JoinTemporaryChannel or JoinChannelByName
        if not join then
            return false
        end
        pcall(join, S.CHANNEL)
    end
    S.hide()
    S.joined = true
    S.later(3, function()
        S.ask()
    end)
    return true
end

function S.leave()
    if S.joined and LeaveChannelByName then
        pcall(LeaveChannelByName, S.CHANNEL)
    end
    S.joined = false
end

-- CHAT_MSG_CHANNEL_NOTICE: the game re-adds a joined channel to the chat windows.
function S.onChannelNotice(_, _, _, name)
    if not F.Util.secret(name) and type(name) == "string" and ownChannel(name) then
        S.hide()
    end
end

function S.later(seconds, run, id)
    if id then
        for _, w in ipairs(S.waits) do
            if w.id == id then
                return
            end
        end
    end
    S.waits[#S.waits + 1] = { at = (GetTime and GetTime() or F.Engine.clock()) + seconds, run = run, id = id }
end

local function runWaits(now)
    local due = {}
    for i = #S.waits, 1, -1 do
        if now >= S.waits[i].at then
            due[#due + 1] = table.remove(S.waits, i)
        end
    end
    for _, w in ipairs(due) do
        local ok, err = pcall(w.run)
        if not ok then
            F.Engine.report(err)
        end
    end
end

-- The newest scan time of a house the player holds: own scan or a merged shared one.
function S.newest(scope)
    local newest = 0
    local last = F.Scan.last
    if last and last.scope == scope and last.at then
        newest = last.at
    end
    for id in pairs(F.db and F.db.sharedSeen or {}) do
        local s, at = tostring(id):match("^(.*)@(%d+)$")
        local t = tonumber(at) or 0
        if s == scope and t > newest then
            newest = t
        end
    end
    for _, r in ipairs(S.received) do
        if r.scope == scope and (r.at or 0) > newest then
            newest = r.at
        end
    end
    return newest
end

function S.control(kind, ...)
    local id = S.channelID()
    if not id or not F.db or not F.db.settings.shareChannel then
        return false
    end
    local parts = { "!" .. kind }
    for _, v in ipairs({ ... }) do
        parts[#parts + 1] = type(v) == "number" and S.enc(v) or esc(tostring(v))
    end
    -- Control messages go before the pieces of a scan.
    table.insert(S.outbox, 1, { channel = "CHANNEL", target = id, text = table.concat(parts, "|") })
    return true
end

function S.ask()
    local scope = F.Engine.scope()
    S.control("Q", scope, S.newest(scope))
end

-- !Q, !H and !R from other players of the channel.
function S.onControl(text, sender)
    if not F.db.settings.shareChannel then
        return
    end
    local fields = {}
    for v in (text .. "|"):gmatch("([^|]*)|") do
        fields[#fields + 1] = v
    end
    local kind = fields[1]
    local now = F.Engine.clock()
    local name = Ambiguate and Ambiguate(sender, "none") or sender
    if kind == "!Q" then
        local scope, at = unesc(fields[2] or ""), S.dec(fields[3] or "")
        local last = F.Scan.last
        if not at or not last or last.scope ~= scope or not last.at or last.at <= at + S.SAME_SCAN then
            return
        end
        if now - last.at > S.MAX_AGE then
            return
        end
        -- Wait a moment: someone else may announce the same or a newer scan first.
        S.later(1 + math.random() * 3, function()
            if (S.heard[scope] or 0) < last.at then
                S.control("H", scope, last.at)
            end
        end, "H" .. scope)
    elseif kind == "!H" then
        local scope, at = unesc(fields[2] or ""), S.dec(fields[3] or "")
        if not at then
            return
        end
        S.heard[scope] = math.max(S.heard[scope] or 0, at)
        if scope ~= F.Engine.scope() or at <= S.newest(scope) + S.SAME_SCAN or now - at > S.MAX_AGE then
            return
        end
        local ask = name .. "@" .. at
        S.later(math.random() * 2, function()
            if not S.asked[ask] or now - S.asked[ask] > 120 then
                S.asked[ask] = now
                S.control("R", name, scope, at)
            end
        end, "R" .. ask)
    elseif kind == "!R" then
        local holder, scope, at = unesc(fields[2] or ""), unesc(fields[3] or ""), S.dec(fields[4] or "")
        if not at then
            return
        end
        S.asked[holder .. "@" .. at] = now
        local last = F.Scan.last
        if not F.AH.isPlayer(holder) or not last or last.scope ~= scope or last.at ~= at then
            return
        end
        local served = scope .. "@" .. at
        if S.served[served] and now - S.served[served] < 120 then
            return
        end
        S.served[served] = now
        S.send("CHANNEL", S.channelID())
    end
end

-- Called every frame: delayed answers, then one message per S.PACE seconds.
function S.step(now)
    if #S.waits > 0 then
        runWaits(now)
    end
    stepOutbox(now)
    if S.working or #S.pending > 0 then
        S.work()
    end
end
