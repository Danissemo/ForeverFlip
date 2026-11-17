-- ForeverFlip's messages: notifications, diagnostics and information in a chat tab of their own
-- ("ForeverFlip", made once in the player's chat dock), so the general chat stays the player's and
-- the messages do not depend on the auction house window.
--   F.Log.add(category, text, opts)   category: error, deal, trade, scan, info
--   opts.chat = true                  also print it to the chat (a slash command's answer: the player
--                                     asked for it); opts.raw = true prints the text as it is
-- The history is kept in memory (F.Log.history, the last F.Log.KEEP lines) for this session; a tab
-- made during the session gets it all.
-- Settings (nil means the default, so an older saved file needs no migration):
--   logEcho    { [category] = true }: categories also printed to the general chat (default: errors
--              only, so an error is never lost when the tab is closed)
--   logSound   a sound for an error (default: on), at most once in SOUND_GAP seconds
--   soundSold  a coin sound when the game says one of the player's auctions sold (default: on)
--   soundOutbid an alarm when the player is outbid (default: on)
--   logTabMade the tab was made once: a tab the player closed is not made again by itself (/ff log
--              or Settings, Messages makes it again)
-- A line repeated within REPEAT_GAP seconds counts up (x2, x3) on its entry instead of adding one,
-- and is neither printed nor sounded again.
local F = ForeverFlip
local Log = {}
F.Log = Log

Log.KEEP = 300
Log.REPEAT_GAP = 60
Log.SOUND_GAP = 10
Log.TAB = "ForeverFlip"
Log.CATEGORIES = { "error", "deal", "trade", "scan", "info" }
-- The categories the player can also send to the general chat (Settings, Messages). Info is not one:
-- its lines are answers to the player's slash commands, which reach the chat always (opts.chat).
Log.ECHOED = { "error", "deal", "trade", "scan" }
Log.LABELS = { error = "Errors", deal = "Deals", trade = "Trade", scan = "Scan", info = "Info" }
Log.COLORS = { error = "ff4040", deal = "ffd100", trade = "40ff40", scan = "4fa3ff", info = "ffffff" }
Log.history = {}

local function clock()
    if F.Engine and F.Engine.clock then
        return F.Engine.clock()
    end
    return time and time() or 0
end

local function settings()
    return F.db and type(F.db.settings) == "table" and F.db.settings or nil
end

-- Is `category` also printed to the chat? Errors are, unless the player turned them off.
function Log.echoes(category)
    local s = settings()
    local echo = s and s.logEcho
    if type(echo) ~= "table" then
        return category == "error"
    end
    return echo[category] == true
end

function Log.setEcho(category, on)
    local s = settings()
    if not s then
        return
    end
    if type(s.logEcho) ~= "table" then
        s.logEcho = { error = true }
    end
    s.logEcho[category] = on and true or false
end

function Log.soundOn()
    local s = settings()
    return not (s and s.logSound == false)
end

local function chatLine(entry)
    if entry.raw then
        return entry.text
    end
    if entry.category == "error" then
        return "|cffff4040ForeverFlip error:|r " .. entry.text
    end
    if entry.text:find("^ForeverFlip") then
        return entry.text
    end
    return "ForeverFlip: " .. entry.text
end

-- One line of the tab: the time, the line in its category's colour, the repeat count.
function Log.format(entry)
    local at = date and date("%H:%M:%S", entry.at) or tostring(entry.at)
    local count = (entry.count or 1) > 1 and string.format(" (x%d)", entry.count) or ""
    return string.format("|cff999999%s|r |cff%s%s|r%s", at, Log.COLORS[entry.category] or "ffffff", entry.text, count)
end

function Log.add(category, text, opts)
    if text == nil then
        return
    end
    text = tostring(text)
    category = Log.COLORS[category] and category or "info"
    opts = opts or {}
    local now = clock()
    local last = Log.history[#Log.history]
    if last and last.category == category and last.text == text and now - last.at <= Log.REPEAT_GAP then
        -- The same line again: counted on its entry. A slash command's answer still reaches the chat,
        -- since the player asked for it again.
        last.count, last.at = (last.count or 1) + 1, now
        if opts.chat then
            print(chatLine(last))
        end
        return last
    end
    local entry = { at = now, category = category, text = text, count = 1, raw = opts.raw }
    Log.history[#Log.history + 1] = entry
    while #Log.history > Log.KEEP do
        table.remove(Log.history, 1)
    end
    if opts.chat or Log.echoes(category) then
        print(chatLine(entry))
    end
    if category == "error" then
        if Log.soundOn() and PlaySound and now - (Log.soundAt or -math.huge) >= Log.SOUND_GAP then
            Log.soundAt = now
            pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
        end
    end
    Log.append(entry)
    -- A slash command's answer (raw) is not traced: /ff trace would copy the trace into itself.
    if not opts.raw then
        Log.trace("log." .. category, "%s", text)
    end
    if F.Engine and F.Engine.changed then
        F.Engine.changed()
    end
    return entry
end

-- Sounds of events (Log.sound): the setting that turns each off, its sound and the fallback id.
-- The deal sound follows `alerts` (Deals.alert also flashes the icon and writes on the screen).
Log.EVENT_SOUNDS = {
    deal = { setting = "alerts", kit = "AUCTION_WINDOW_OPEN", id = 5274, gap = 0 },
    sold = { setting = "soundSold", kit = "LOOT_WINDOW_COIN_SOUND", id = 120 },
    outbid = { setting = "soundOutbid", kit = "ALARM_CLOCK_WARNING_3", id = 12889 },
}
-- Several sales a second (a stack sold in parts) make one sound; each deal has its own (Deals.alert
-- already keeps one deal from sounding again).
Log.EVENT_GAP = 3
Log.eventAt = {}

-- Plays the sound of `kind` unless its setting is off or it sounded within EVENT_GAP seconds.
-- Returns true when it played.
function Log.sound(kind)
    local e = Log.EVENT_SOUNDS[kind]
    local s = settings()
    if not e or not PlaySound or (s and s[e.setting] == false) then
        return false
    end
    local now = clock()
    if now - (Log.eventAt[kind] or -math.huge) < (e.gap or Log.EVENT_GAP) then
        return false
    end
    Log.eventAt[kind] = now
    pcall(PlaySound, SOUNDKIT and SOUNDKIT[e.kit] or e.id)
    return true
end

-- The last line's text (for a test or a status), or nil.
function Log.last(category)
    for i = #Log.history, 1, -1 do
        local e = Log.history[i]
        if not category or e.category == category then
            return e.text
        end
    end
end

function Log.clear()
    Log.history = {}
    local tab = Log.chatFrame()
    if tab and tab.Clear then
        tab:Clear()
    end
    if F.Engine and F.Engine.changed then
        F.Engine.changed()
    end
end

-- Chat tab ------------------------------------------------------------------------------------------
-- The chat window named "ForeverFlip" that is open (shown, or docked behind another tab), or nil.
function Log.chatFrame()
    if type(GetChatWindowInfo) ~= "function" then
        return
    end
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local ok, name, _, _, _, _, _, shown, _, docked = pcall(GetChatWindowInfo, i)
        local frame = _G["ChatFrame" .. i]
        if ok and name == Log.TAB and (shown or docked) and frame and frame.AddMessage then
            return frame
        end
    end
end

function Log.append(entry)
    local tab = Log.chatFrame()
    if tab then
        tab:AddMessage(Log.format(entry))
    end
end

-- Makes the tab when there is none (docked beside General, listening to no chat channel) and fills
-- it with this session's history; `select` brings it to the front. Returns the tab, or nil (no free
-- chat window, or in combat).
function Log.makeTab(select)
    local tab = Log.chatFrame()
    if not tab then
        if type(FCF_OpenNewWindow) ~= "function" or (InCombatLockdown and InCombatLockdown()) then
            return
        end
        local ok, made = pcall(FCF_OpenNewWindow, Log.TAB, true)
        tab = Log.chatFrame() or (ok and type(made) == "table" and made or nil)
        if not tab then
            return
        end
        local s = settings()
        if s then
            s.logTabMade = true
        end
        for _, e in ipairs(Log.history) do
            tab:AddMessage(Log.format(e))
        end
    end
    if select and tab.isDocked and type(FCF_SelectDockFrame) == "function" then
        pcall(FCF_SelectDockFrame, tab)
    end
    return tab
end

-- /ff log: the tab, made again if it was closed, in front.
function Log.show()
    if not Log.makeTab(true) then
        print("ForeverFlip: " .. F.Locale.text("No free chat window for the ForeverFlip tab: close one and try again."))
    end
end

-- After the saved data is read; the tab itself is made a moment after entering the world, once the
-- game has restored the player's own chat windows, and only the first time.
function Log.init()
    local s = settings()
    if s then
        s.logShown = nil -- the old message window's setting
    end
end

function Log.entered()
    local s = settings()
    if s and not s.logTabMade and F.Share and F.Share.later then
        F.Share.later(3, function()
            if not Log.chatFrame() then
                Log.makeTab(false)
            elseif s then
                s.logTabMade = true
            end
        end, "logtab")
    end
end

-- Trace ---------------------------------------------------------------------------------------------
-- A saved timeline of what the addon does, read afterwards to find why something took long: game
-- events, searches (sent, held back and by what, answered, timed out), Check all batches and their
-- stalls, frame parts slower than Log.SLOW_MS, and the messages above. Saved in ForeverFlipData:
--   trace       the last Log.TRACE_KEEP lines, plain strings "MM-DD HH:MM:SS t=<GetTime> event ...";
--               a line repeated within 5 seconds counts up (xN) instead of adding one
--   traceStats  { [kind] = { n, total, max, maxAt } }: running times in milliseconds or seconds
--               (the kind says which), e.g. search.ms, wait.throttle.ms, part.Scan.step.ms
--   traceSlow   the Log.SLOW_KEEP slowest searches: { ms, key, name, why, at }
-- settings.trace = false turns it off (/ff trace off). Kinds are a fixed set; keys go only into
-- lines and traceSlow, so the saved file stays small.
Log.TRACE_KEEP = 2000
Log.SLOW_MS = 50
Log.SLOW_KEEP = 25
Log.REPEAT_TRACE = 5

-- Milliseconds of a precise clock (debugprofilestop, else GetTime).
function Log.ms()
    if debugprofilestop then
        return debugprofilestop()
    end
    return (GetTime and GetTime() or clock()) * 1000
end

function Log.tracing()
    local s = settings()
    return type(F.db) == "table" and not (s and s.trace == false)
end

-- DEV mode (Settings > Messages, /ff dev): every event, click, page and frame part is traced
-- with its time, not only searches, checks and slow frames.
function Log.dev()
    local s = settings()
    return Log.tracing() and s ~= nil and s.dev == true
end

-- Runs fn(...) and traces it as `what` with its time: always when it took Log.SLOW_MS or more
-- (the game waited for it), every time in DEV mode. Returns what fn returned.
-- A trace for repairs (each click, status message, posting decision): only in DEV mode.
function Log.devTrace(event, fmt, ...)
    if Log.dev() then
        Log.trace(event, fmt, ...)
    end
end

local function finishAction(what, start, ...)
    local spent = Log.ms() - start
    if spent >= Log.SLOW_MS then
        Log.stat("slowaction.ms", spent)
        Log.trace("slowaction", "%s %.0f ms", what, spent)
    elseif Log.dev() then
        Log.trace("action", "%s %.0f ms", what, spent)
    end
    return ...
end

function Log.action(what, fn, ...)
    if not Log.tracing() then
        return fn(...)
    end
    return finishAction(what, Log.ms(), fn(...))
end

local traceLast -- { text, line, count, at } of the newest line, for counting repeats

function Log.trace(event, fmt, ...)
    if not Log.tracing() then
        return
    end
    local text = tostring(event)
    if fmt ~= nil then
        local ok, s = pcall(string.format, fmt, ...)
        text = text .. " " .. (ok and s or tostring(fmt))
    end
    local db = F.db
    if type(db.trace) ~= "table" then
        db.trace = {}
    end
    local list = db.trace
    local now = clock()
    local last = traceLast
    if last and last.text == text and now - last.at <= Log.REPEAT_TRACE and list[#list] == last.line then
        last.count, last.at = last.count + 1, now
        last.line = last.base .. string.format(" (x%d)", last.count)
        list[#list] = last.line
        return
    end
    local stamp = date and date("%m-%d %H:%M:%S", now) or tostring(now)
    local base = string.format("%s t=%.3f %s", stamp, GetTime and GetTime() or now, text)
    traceLast = { text = text, base = base, line = base, count = 1, at = now }
    list[#list + 1] = base
    local extra = #list - Log.TRACE_KEEP
    if extra > 0 then
        -- One cut for many lines: table.remove from the front moves the whole list each time.
        local kept = {}
        for i = extra + 1, #list do
            kept[#kept + 1] = list[i]
        end
        db.trace = kept
    end
end

-- Adds one measurement of `kind` to the running statistics.
function Log.stat(kind, value)
    if not Log.tracing() or type(value) ~= "number" or value ~= value then
        return
    end
    local db = F.db
    if type(db.traceStats) ~= "table" then
        db.traceStats = {}
    end
    local s = db.traceStats[kind]
    if type(s) ~= "table" then
        s = { n = 0, total = 0, max = 0 }
        db.traceStats[kind] = s
    end
    s.n, s.total = s.n + 1, s.total + value
    if value > s.max then
        s.max, s.maxAt = value, clock()
    end
end

-- Remembers a slow search among the Log.SLOW_KEEP slowest: `ms`, its key and why it took long.
function Log.slow(ms, key, why)
    if not Log.tracing() then
        return
    end
    local db = F.db
    if type(db.traceSlow) ~= "table" then
        db.traceSlow = {}
    end
    local list = db.traceSlow
    local smallest = list[#list]
    if #list >= Log.SLOW_KEEP and smallest and smallest.ms >= ms then
        return
    end
    local item = F.Util and F.Util.parseKey and F.Util.parseKey(key)
    local name = item and F.Compat and F.Compat.itemInfo(item.id)
    list[#list + 1] = { ms = math.floor(ms + 0.5), key = key, name = name, why = why, at = clock() }
    table.sort(list, function(a, b)
        return a.ms > b.ms
    end)
    while #list > Log.SLOW_KEEP do
        list[#list] = nil
    end
end

function Log.clearTrace()
    if type(F.db) == "table" then
        F.db.trace, F.db.traceStats, F.db.traceSlow = {}, {}, {}
    end
    traceLast = nil
end

-- The statistics as lines, the kind with the most time first.
function Log.statLines()
    local out = {}
    local stats = type(F.db) == "table" and type(F.db.traceStats) == "table" and F.db.traceStats or {}
    local kinds = {}
    for kind in pairs(stats) do
        kinds[#kinds + 1] = kind
    end
    table.sort(kinds, function(a, b)
        return stats[a].total > stats[b].total
    end)
    for _, kind in ipairs(kinds) do
        local s = stats[kind]
        out[#out + 1] = string.format(
            "%s: %d times, average %.1f, longest %.1f, total %.0f",
            kind,
            s.n,
            s.n > 0 and s.total / s.n or 0,
            s.max,
            s.total
        )
    end
    return out
end

-- /ff trace [stats|slow|clear|on|off|<lines>]: the answer, as lines for the chat.
function Log.traceCommand(arg)
    local L = F.Locale.text
    local db = F.db
    arg = arg or ""
    if arg == "clear" then
        Log.clearTrace()
        return { L("Trace cleared.") }
    end
    if arg == "on" or arg == "off" then
        if arg == "off" then
            db.settings.trace = false
        else
            db.settings.trace = nil
        end
        return { arg == "off" and L("Trace off.") or L("Trace on.") }
    end
    if arg == "dev" then
        db.settings.dev = not db.settings.dev or nil
        return { db.settings.dev and L("DEV mode on: every action is traced.") or L("DEV mode off.") }
    end
    local out = {}
    if arg == "stats" or arg == "" then
        out[#out + 1] = L("Times (ms unless the kind says s):")
        for _, line in ipairs(Log.statLines()) do
            out[#out + 1] = "  " .. line
        end
    end
    if arg == "slow" or arg == "" then
        out[#out + 1] = L("Slowest searches:")
        for i, s in ipairs(type(db.traceSlow) == "table" and db.traceSlow or {}) do
            if i > 10 then
                break
            end
            out[#out + 1] = string.format("  %d ms %s %s: %s", s.ms, s.name or "", s.key or "", s.why or "")
        end
    end
    local count = tonumber(arg) or (arg == "" and 20 or 0)
    local list = type(db.trace) == "table" and db.trace or {}
    if count > 0 then
        out[#out + 1] =
            string.format(L("Last %d of %d trace lines (all are in the saved file):"), math.min(count, #list), #list)
        for i = math.max(1, #list - count + 1), #list do
            out[#out + 1] = "  " .. list[i]
        end
    end
    return out
end
