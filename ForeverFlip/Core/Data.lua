-- Saved data (SavedVariables ForeverFlipData).
--   settings          language, profit floors, spending share
--   vendor[itemID]    the client's vendor sell price (0 = cannot be sold to a vendor)
--   vendorSeen[itemID] what a merchant really paid: { p = copper each, t = when, c = client price }
--   deSeen[band]      own disenchant results per item band: { n = disenchants, [itemID] = units }
--   lastScan          time of the last full scan request (one per 15 minutes for the account)
--   markets[scope]    per auction house: history[key] = { scan = {...}, flow = {...} }, stats
--   chars[owner]      per character: positions, journal, pending purchases, listings
local F = ForeverFlip
local U = F.Util
local D = {}
F.Data = D

D.DEFAULTS = {
    language = nil, -- "en" or "uk"; nil follows the game client
    vendorMinProfit = F.Market.THRESHOLDS.vendorMinProfit, -- copper per unit of a vendor deal
    minProfit = F.Market.THRESHOLDS.minProfit, -- copper per resale deal
    minROI = F.Market.THRESHOLDS.minROI, -- resale return on the money spent
    sellMinReturn = 0.05, -- the least a sale of own stock brings over its real cost (price, lost deposits)
    spendShare = 0.8, -- share of the money on hand one deal may use
    duration = 3, -- 1 = 2 h, 2 = 8 h, 3 = 24 h, 0 = automatic from the item's sales
    -- Nothing runs on its own for a new player: automatic scans, the sniper and automatic deal
    -- checks are switched on in Settings.
    autoScan = false, -- full scan every 15 minutes while the auction house is open
    itemShare = 0.3, -- share of the money one item may hold (stock and new resale)
    sniper = false, -- browse for cheap listings between scans; fall back to hot item searches
    alerts = true, -- sound and screen notice when a deal can be bought
    alertMinProfit = 50, -- copper: smaller deals are listed without a notice
    tooltipPrices = true, -- price history lines in item tooltips
    undercutPercent = 0, -- 0: one legal price step below the cheapest other seller
    minPricePercent = 0, -- never post below this share of the usual price (0 = off)
    maxPricePercent = 2, -- a cheapest seller above this share of the usual price is ignored
    belowMin = "min", -- below the floor: "min" posts at the floor, "hold" keeps the item
    learnBrowsing = true, -- the player's own searches update prices and deals
    highlight = true, -- mark deals in the game's Buy tab
    disenchant = true, -- disenchant deals (only for a character who knows Disenchant)
    shareReceive = true, -- merge full scans shared by guild and group members
    shareAuto = false, -- send each own full scan to the guild
    rawScans = true, -- keep full scans for the ForeverFlip Sync helper (community data)
    shareChannel = true, -- share full scans with every ForeverFlip user of the realm (hidden channel)
    -- Percent off the client's vendor price until a merchant's real price is seen. 0: in game every
    -- merchant price checked so far matched the client's, and 20% removed nearly all vendor deals
    -- (74 items below the vendor price in one scan, 1 left at 20%). A price a merchant really paid
    -- is always used for its item (vendorSeen).
    vendorMargin = 0,
    spendLimit = 0, -- gold one auction house visit may spend on deals (0 = no limit)
    leaveLots = 0, -- cheap lots (or commodity units) of a deal left for other buyers
    -- T25: the market reset (Deals -> Market reset, internal id "median"): every lot under the
    -- usual price bought to relist alone. Always on (0 in medianShare or medianDayGold is off); its
    -- own money limits come on top of the ordinary ones.
    median = true,
    medianItemGold = 50, -- gold one item may take
    medianDayGold = 200, -- gold the strategy may spend in a day
    medianShare = 0.5, -- share of the money on hand the strategy may use
    autoVerify = false, -- check found deals in the background (the best ones first)
    hideUnlearned = false, -- Crafting: leave out recipes the character has not learned
    -- The messages chat tab (Log.lua), which already reads a missing value as these.
    logEcho = { error = true }, -- categories also printed to the general chat
    logSound = true, -- a sound for an error
    soundSold = true, -- a coin sound when one of the player's auctions sold
    soundOutbid = true, -- an alarm when another player outbids the player
    windowScale = 1, -- the size of ForeverFlip's window (Settings, Display)
    logTabMade = false, -- the tab was made once; a closed tab is not made again by itself
}

-- Presets set the money and profit thresholds in one click (Settings). Balanced is D.DEFAULTS.
-- Careful's vendor deal minimum is 15 copper (T27): 50 left out most vendor deals, which are
-- risk-free (a merchant pays at once), so being careful there costs only profit.
D.PRESETS = {
    careful = {
        minROI = 0.35,
        minProfit = 500,
        vendorMinProfit = 15,
        spendShare = 0.5,
        itemShare = 0.15,
        alertMinProfit = 100,
    },
    balanced = {
        minROI = 0.2,
        minProfit = 100,
        vendorMinProfit = 10,
        spendShare = 0.8,
        itemShare = 0.3,
        alertMinProfit = 50,
    },
    aggressive = {
        minROI = 0.1,
        minProfit = 50,
        vendorMinProfit = 5,
        spendShare = 0.95,
        itemShare = 0.5,
        alertMinProfit = 20,
    },
}
-- A brand-new profile (no saved file) starts on Careful; a profile that exists keeps every value
-- the player has, so an update never changes thresholds behind the player's back.
D.NEW_PRESET = "careful"

function D.open(saved)
    local fresh = type(saved) ~= "table"
    local db = type(saved) == "table" and saved or {}
    db.settings = type(db.settings) == "table" and db.settings or {}
    if fresh and D.NEW_PRESET then
        for k, v in pairs(D.PRESETS[D.NEW_PRESET]) do
            db.settings[k] = v
        end
    end
    for k, v in pairs(D.DEFAULTS) do
        if db.settings[k] == nil then
            -- A table default is copied: a profile changing it must not change the default.
            db.settings[k] = type(v) == "table" and U.copy(v) or v
        end
    end
    db.vendor = type(db.vendor) == "table" and db.vendor or {}
    db.vendorSeen = type(db.vendorSeen) == "table" and db.vendorSeen or {}
    db.sellable = type(db.sellable) == "table" and db.sellable or {}
    db.deSeen = type(db.deSeen) == "table" and db.deSeen or {}
    db.markets = type(db.markets) == "table" and db.markets or {}
    db.chars = type(db.chars) == "table" and db.chars or {}
    D.migrate(db)
    return db
end

-- The settings of a new profile (Settings > Data > Reset settings): the defaults and the starting
-- preset. The language and whether the chat tab was made stay; nothing but the settings changes.
D.KEPT_SETTINGS = { language = true, logTabMade = true }
function D.resetSettings(db)
    local fresh = D.open(nil).settings
    for k in pairs(db.settings) do
        if not D.KEPT_SETTINGS[k] then
            db.settings[k] = nil
        end
    end
    for k, v in pairs(fresh) do
        if not D.KEPT_SETTINGS[k] then
            db.settings[k] = v
        end
    end
    return db
end

-- A clean start the player asked for (Settings, /ff reset): a new profile of nothing but the
-- player's own settings. Prices, sales, journals, positions and the shopping list all go.
function D.reset(db)
    local fresh = D.open(nil)
    if type(db) == "table" and type(db.settings) == "table" then
        fresh.settings = U.copy(db.settings)
    end
    return fresh
end

-- Schema of ForeverFlipData: db.schemaVersion is the number of D.MIGRATIONS already applied. Each
-- migration runs once, in order, from the file's version up; each is idempotent too (it keeps its
-- own older marker), so a file without schemaVersion, written before migrations had numbers, is
-- brought up safely. A fresh file runs them all and gets the current version. A file of a newer
-- ForeverFlip (a version this one does not know) is left as it is, with a warning in the log.
-- The derived sales statistics have their own version (D.STATS_VERSION, rebuilt by Scan).
D.MIGRATIONS = {
    -- 1: 1.2.0-beta.1 to beta.3 saved a default margin of 20%: back to the new default, once.
    function(db)
        if not db.vendorMarginReset then
            if db.settings.vendorMargin == 20 then
                db.settings.vendorMargin = 0
            end
            db.vendorMarginReset = true
        end
    end,
    -- 2: sales measured by an older model are dropped (D.cleanSales, db.salesModel).
    function(db)
        D.cleanSales(db)
    end,
    -- 3: Under market was saved off with 20% of the gold, the old defaults: the new ones, once.
    -- A player who changed either keeps their choice.
    function(db)
        if not db.medianDefaults then
            local s = db.settings
            if s.median == false and s.medianShare == 0.2 then
                s.median, s.medianShare = true, 0.5
            end
            db.medianDefaults = 2
        end
    end,
    -- 4: Market reset lost its Turn on box (0 in its "% of gold" is off now): a page saved off
    -- keeps being off as a share of 0.
    function(db)
        local s = db.settings
        if s.median == false then
            s.median, s.medianShare = true, 0
        end
    end,
    -- 5: db.blocked held two lists in one table: the ignore list (key -> name) and, from 3.0, the
    -- game's blocked actions (an array of records), which then showed up as ignored "items".
    -- They are apart now: db.ignored and db.blockedActions.
    function(db)
        local old = db.blocked
        if type(old) ~= "table" then
            db.blocked = nil
            return
        end
        db.ignored = type(db.ignored) == "table" and db.ignored or {}
        db.blockedActions = type(db.blockedActions) == "table" and db.blockedActions or {}
        for key, value in pairs(old) do
            if type(key) == "string" then
                db.ignored[key] = db.ignored[key] or value
            end
        end
        for _, record in ipairs(old) do
            if type(record) == "table" and record.func then
                db.blockedActions[#db.blockedActions + 1] = record
            end
        end
        db.blocked = nil
    end,
}
D.SCHEMA_VERSION = #D.MIGRATIONS

function D.migrate(db)
    local version = tonumber(db.schemaVersion) or 0
    if version > D.SCHEMA_VERSION then
        if F.Log and F.Log.add then
            local text = "Saved data comes from a newer ForeverFlip (schema %d, this version knows %d): left as it is."
            F.Log.add("error", string.format(F.Locale and F.Locale.text(text) or text, version, D.SCHEMA_VERSION))
        end
        return
    end
    for i = math.max(version, 0) + 1, D.SCHEMA_VERSION do
        D.MIGRATIONS[i](db)
        db.schemaVersion = i
    end
    db.schemaVersion = D.SCHEMA_VERSION
end

-- Sales measured before 1.2.0-beta.4 counted reposts (and the flow cancelled, expired and repriced
-- auctions) as sales: in game, 194 "sales" of an item with 31 units listed, and gear "sold" at
-- asking prices nobody paid. They are dropped once, to be measured again with the confirmation
-- by the next scan; prices and listed units stay. Model 3 (1.2.0-beta.8) drops them once more: a
-- lot taken down and posted again at a new price still counted as sold, and so did the player's
-- own purchases. Model 4 (1.2.0-beta.8): parts of the server's answer were read as complete
-- scans, and the lots missing from a part were read as bought (in game, 518 units of an oil
-- "sold" in 1.6 hours); the lots kept for the comparison and the house's size go too.
D.SALES_MODEL = 4
function D.cleanSales(db)
    if (tonumber(db.salesModel) or 1) >= D.SALES_MODEL then
        return
    end
    for _, m in pairs(db.markets) do
        if type(m) == "table" and type(m.history) == "table" then
            m.peak = nil
            for _, h in pairs(m.history) do
                if type(h) == "table" then
                    h.sales, h.flow, h.pending, h.pendingAt = nil, nil, nil, nil
                    h.lots, h.lotsAt, h.lotOwners = nil, nil, nil
                    if type(h.days) == "table" then
                        for _, d in ipairs(h.days) do
                            if type(d) == "table" then
                                d.s = nil
                            end
                        end
                    end
                end
            end
        end
    end
    db.salesModel = D.SALES_MODEL
end

-- Derived sales statistics (T32). What is observed and what is inferred are kept apart:
--   observed  per item h.scan (usual price, listed units by level), h.days[].d/min/m/n, h.t, h.units,
--             h.lots/lotsAt/lotOwners (the last scan's lots), the full scans in ForeverFlipRaw, and
--             the journals, invoices and settings of every character (never touched here);
--   derived   h.sales (lot-tracked sales: Est./day, Sure, sale prices), h.flow (units that
--             disappeared), h.days[].s (units seen sold per day), and the pending suspects.
-- The derived tables carry the version of the formulas that built them (market.statsVersion). A
-- newer version rebuilds them from the observations at load (F.Scan.rebuildStep): the raw full
-- scans still kept are replayed through the current formulas into separate tables, and only a
-- complete replay replaces the old ones (D.commitStats). The old ones are kept beside them for
-- D.STATS_KEEP (market.statsBackup, D.rollbackStats). An item no raw scan covers keeps its tables,
-- marked legacy (M.quality says so) until new scans have measured it again; a house without raw
-- scans is only stamped with the version.
-- 1: whole lots that vanished count M.LOT_WEIGHT of a sale everywhere, a lot of an unknown seller
--    posted again at a new price is no sale, sample quality (M.quality).
D.STATS_VERSION = 1
D.STATS_KEEP = 7 * 86400
-- The last scan's lots and the suspects waiting for the next scan: taken from a rebuild only when
-- it saw a newer scan than the one they come from.
D.CARRY = { "lots", "lotsAt", "lotOwners", "pending", "pendingAt" }

function D.statsCurrent(market)
    return type(market) == "table"
        and ((tonumber(market.statsVersion) or 0) >= D.STATS_VERSION or market.statsHold == D.STATS_VERSION)
end

-- Replaces the derived tables of `market` with the rebuilt ones. `shadows`: { [key] = { sales,
-- flow, daySold = { [day] = units }, lots, lotsAt, ... } } for the items the raw scans covered; an
-- item without one keeps its tables, marked legacy (h.sales.legacy: built by older formulas, see
-- M.quality), so no measurement is lost. `info` is kept as market.statsBuilt. The tables replaced
-- are kept in market.statsBackup (one generation). Returns the number of items rebuilt.
function D.commitStats(market, shadows, now, info)
    local backup = { version = tonumber(market.statsVersion) or 0, at = now, items = {}, legacy = {} }
    local built = 0
    for key, h in pairs(market.history) do
        -- Covered: the replay compared at least one pair of scans of the item.
        local w = shadows[key]
        if w and not w.sales then
            w = nil
        end
        if type(h) == "table" and not w then
            if type(h.sales) == "table" and not h.sales.legacy then
                h.sales.legacy = true
                backup.legacy[#backup.legacy + 1] = key
            end
        elseif type(h) == "table" then
            local old = { sales = h.sales, flow = h.flow, s = {} }
            for _, d in ipairs(type(h.days) == "table" and h.days or {}) do
                if type(d) == "table" and d.s then
                    old.s[#old.s + 1] = d.d
                    old.s[#old.s + 1] = d.s
                end
            end
            if (w.lotsAt or 0) > (h.lotsAt or 0) then
                old.carry = true
                for _, f in ipairs(D.CARRY) do
                    old[f] = h[f]
                    h[f] = w[f]
                end
            end
            backup.items[key] = old
            h.sales, h.flow = w.sales, w.flow
            if h.sales then
                built = built + 1
            end
            for _, d in ipairs(type(h.days) == "table" and h.days or {}) do
                if type(d) == "table" then
                    d.s = w.daySold and w.daySold[d.d] or nil
                end
            end
        end
    end
    market.statsBackup = backup
    market.statsVersion = D.STATS_VERSION
    market.statsBuilt = info or { at = now }
    if market.statsBuilt.items == nil then
        market.statsBuilt.items = built
    end
    market.statsError = nil
    return built
end

-- Puts back the derived tables a rebuild replaced, and keeps that version from being rebuilt again
-- (market.statsHold) until the formulas change once more. False without a backup.
function D.rollbackStats(market)
    local b = type(market) == "table" and market.statsBackup
    if type(b) ~= "table" or type(b.items) ~= "table" then
        return false
    end
    for key, old in pairs(b.items) do
        local h = market.history[key]
        if type(h) == "table" then
            h.sales, h.flow = old.sales, old.flow
            local days = {}
            for i = 1, #(old.s or {}) - 1, 2 do
                days[old.s[i]] = old.s[i + 1]
            end
            for _, d in ipairs(type(h.days) == "table" and h.days or {}) do
                if type(d) == "table" then
                    d.s = days[d.d]
                end
            end
            if old.carry then
                for _, f in ipairs(D.CARRY) do
                    h[f] = old[f]
                end
            end
        end
    end
    for _, key in ipairs(b.legacy or {}) do
        local h = market.history[key]
        if type(h) == "table" and type(h.sales) == "table" then
            h.sales.legacy, h.sales.newPairs = nil, nil
        end
    end
    market.statsHold = market.statsVersion
    market.statsVersion = b.version
    market.statsBackup, market.statsBuilt = nil, nil
    return true
end

-- Backups older than D.STATS_KEEP go: each holds a copy of every item's sales.
function D.dropStatsBackups(db, now)
    for _, m in pairs(type(db) == "table" and type(db.markets) == "table" and db.markets or {}) do
        local b = type(m) == "table" and m.statsBackup
        if type(b) == "table" and U.finite(now) and now - (b.at or 0) > D.STATS_KEEP then
            m.statsBackup = nil
        end
    end
end

-- The client reads the saved file as one Lua 5.1 chunk, which holds at most 262143 distinct
-- constants (every different string and number, keys included). Past that the whole file fails to
-- load ("constant table overflow" in Logs\FrameXML.log), the addon starts empty and the next logout
-- writes the empty data over it: in game, 26274 items of sales history were lost that way at 260 000
-- constants. D.fitSave runs at logout: fractions in the item histories (hours, rates, factors, all
-- estimates) keep 4 significant digits, so they stop being a new constant each; if the file would
-- still hold more than D.SAVE_LIMIT, the items of the houses seen longest ago go until D.SAVE_TARGET.
-- Items the player holds or has listed stay.
D.SAVE_LIMIT = 200000
D.SAVE_TARGET = 180000

local function round4(x)
    if x == math.floor(x) or not U.finite(x) or x == 0 then
        return x
    end
    local f = 10 ^ (3 - math.floor(math.log10(math.abs(x))))
    return math.floor(x * f + 0.5) / f
end
D.round4 = round4

local function roundTree(t, depth)
    for k, v in pairs(t) do
        if type(v) == "number" then
            local r = round4(v)
            if r ~= v then
                t[k] = r
            end
        elseif type(v) == "table" and depth < 6 then
            roundTree(v, depth + 1)
        end
    end
end

-- Calls add(value) for every constant the saved file of `t` would hold: string and number values,
-- and keys except the positions 1..#t of a list (written without a key).
local function constants(t, add, depth)
    local n = #t
    for k, v in pairs(t) do
        if type(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then
            add(k)
        end
        if type(v) == "table" then
            if depth < 30 then
                constants(v, add, depth + 1)
            end
        elseif type(v) == "string" or type(v) == "number" then
            add(v)
        end
    end
end

-- Number of distinct constants of the saved globals (D.fitSave).
function D.countConstants(...)
    local seen, n = {}, 0
    local function add(v)
        if not seen[v] then
            seen[v], n = true, n + 1
        end
    end
    for i = 1, select("#", ...) do
        local t = select(i, ...)
        if type(t) == "table" then
            constants(t, add, 0)
        end
    end
    return n
end

local function lastSeen(h)
    local at = 0
    if type(h) == "table" then
        at = math.max(tonumber(h.lotsAt) or 0, type(h.scan) == "table" and tonumber(h.scan.at) or 0)
    end
    return at
end

-- Keeps the saved file loadable. Returns the number of constants written and of items dropped.
function D.fitSave(db, raw, limit, target)
    limit, target = limit or D.SAVE_LIMIT, target or D.SAVE_TARGET
    if type(db) ~= "table" or type(db.markets) ~= "table" then
        return 0, 0
    end
    for _, m in pairs(db.markets) do
        if type(m) == "table" and type(m.history) == "table" then
            for _, h in pairs(m.history) do
                if type(h) == "table" then
                    roundTree(h, 0)
                end
            end
        end
    end
    -- How often each constant is used: an item's constants leave the file only with their last use.
    local uses, n = {}, 0
    local function add(v)
        local c = uses[v]
        if not c then
            n = n + 1
        end
        uses[v] = (c or 0) + 1
    end
    constants(db, add, 0)
    if type(raw) == "table" then
        constants(raw, add, 0)
    end
    if n <= limit then
        return n, 0
    end
    local held = {}
    for _, c in pairs(type(db.chars) == "table" and db.chars or {}) do
        if type(c) == "table" then
            for key in pairs(type(c.positions) == "table" and c.positions or {}) do
                held[key] = true
            end
            for _, l in ipairs(type(c.listings) == "table" and c.listings or {}) do
                if type(l) == "table" and l.key then
                    held[l.key] = true
                end
            end
        end
    end
    local items = {}
    for _, m in pairs(db.markets) do
        if type(m) == "table" and type(m.history) == "table" then
            for key, h in pairs(m.history) do
                if not held[key] then
                    items[#items + 1] = { m = m, key = key, at = lastSeen(h) }
                end
            end
        end
    end
    table.sort(items, function(a, b)
        return a.at < b.at
    end)
    local function drop(v)
        local c = uses[v] - 1
        if c <= 0 then
            uses[v], n = nil, n - 1
        else
            uses[v] = c
        end
    end
    local dropped = 0
    for _, x in ipairs(items) do
        if n <= target then
            break
        end
        local h = x.m.history[x.key]
        drop(x.key)
        if type(h) == "table" then
            constants(h, drop, 0)
        elseif type(h) == "string" or type(h) == "number" then
            drop(h)
        end
        x.m.history[x.key] = nil
        if type(x.m.statsBackup) == "table" and type(x.m.statsBackup.items) == "table" then
            local old = x.m.statsBackup.items[x.key]
            if type(old) == "table" then
                constants(old, drop, 0)
                drop(x.key)
                x.m.statsBackup.items[x.key] = nil
            end
        end
        dropped = dropped + 1
    end
    return n, dropped
end

function D.market(db, scope)
    local m = db.markets[scope]
    if type(m) ~= "table" then
        -- A new house is measured by the current formulas from its first scan on.
        m = { history = {}, statsVersion = D.STATS_VERSION }
        db.markets[scope] = m
    end
    m.history = type(m.history) == "table" and m.history or {}
    return m
end

function D.char(db, owner)
    local c = db.chars[owner]
    if type(c) ~= "table" then
        c = {}
        db.chars[owner] = c
    end
    c.positions = type(c.positions) == "table" and c.positions or {}
    c.journal = type(c.journal) == "table" and c.journal or {}
    c.listings = type(c.listings) == "table" and c.listings or {}
    c.stats = type(c.stats) == "table" and c.stats or {}
    return c
end

-- Journal entries: { at, kind = "buy" | "sell" | "vendor" | "expired" | "cancel" | "return", key, name,
-- qty, amount, profit }: for the last three, amount is the deposit (and cancel fee) lost, and
-- profit (negative) the part of it that left the item's profit at once (no stock was held).
-- Journal kinds of a post that came back: its deposit (amount) was lost.
local FAILED_KINDS = { expired = true, ["return"] = true, cancel = true }
-- Daily totals of the journal, kept D.DAILY_DAYS days: the journal keeps only its last 500
-- entries, and a busy week of Analytics read from it alone came out short.
D.DAILY_DAYS = 60
local function dayOf(char, at)
    local day = math.floor((at or 0) / 86400)
    local d = char.daily[day]
    if not d then
        d = { spent = 0, buys = 0, earned = 0, profit = 0, cost = 0, sales = 0, wins = 0, vendor = 0, auction = 0 }
        char.daily[day] = d
    end
    return d
end

local function addDay(char, e)
    local d = dayOf(char, e.at)
    if e.kind == "buy" then
        d.spent, d.buys = d.spent + (e.amount or 0), d.buys + 1
    elseif e.kind == "sell" or e.kind == "vendor" then
        local profit = e.profit or 0
        d.earned, d.profit, d.sales = d.earned + (e.amount or 0), d.profit + profit, d.sales + 1
        d.cost = d.cost + ((e.amount or 0) - profit)
        d.wins = d.wins + (profit > 0 and 1 or 0)
        if e.kind == "vendor" then
            d.vendor = d.vendor + profit
        else
            d.auction = d.auction + profit
        end
    elseif FAILED_KINDS[e.kind] and e.profit then
        -- A deposit or fee lost while none of the item was held (D.addCost); one lost on stock joins
        -- its cost and reaches the profit with the sale.
        d.profit = d.profit + e.profit
    end
end

-- The character's daily totals, built once from the journal when they do not exist yet.
function D.daily(char)
    if type(char.daily) ~= "table" then
        char.daily = {}
        for _, e in ipairs(char.journal or {}) do
            addDay(char, e)
        end
    end
    return char.daily
end

function D.log(char, entry)
    -- A purchase names the auction house it was made at: a full scan of one house counts only the
    -- player's purchases there as its own (F.Scan.ownBought).
    if entry.kind == "buy" and entry.scope == nil and F.Engine and F.Engine.scope then
        entry.scope = F.Engine.scope()
    end
    D.logLotEvent(char, entry)
    D.daily(char)
    char.journal[#char.journal + 1] = entry
    addDay(char, entry)
    while #char.journal > 500 do
        table.remove(char.journal, 1)
    end
    local oldest = math.floor((entry.at or 0) / 86400) - D.DAILY_DAYS
    for day in pairs(char.daily) do
        if day < oldest then
            char.daily[day] = nil
        end
    end
end

-- Per item totals for the statistics page.
function D.itemStats(char, key, name)
    local s = char.stats[key]
    if not s then
        s = { name = name, bought = 0, spent = 0, sold = 0, earned = 0, profit = 0, days = 0 }
        char.stats[key] = s
    end
    s.name = name or s.name
    return s
end

-- Purchase lots: every purchase with what became of it, first in, first out. char.lots = {
-- { id, key, name, at, qty, cost, mode, left, sold, received, lost, soldAt } }: cost = what the
-- purchase cost, received = the money its sold units brought after the cut, lost = deposits of
-- posts that expired or were cancelled and the game's cancel fees, booked on the lot whose units
-- were on sale. Past D.LOTS lots the oldest closed ones are dropped; an open lot is the stock
-- sales take from first, so it is never dropped.
D.LOTS = 300
local function trimLots(lots)
    local i = 1
    while #lots > D.LOTS and i <= #lots do
        if (lots[i].left or 0) <= 0 then
            table.remove(lots, i)
        else
            i = i + 1
        end
    end
end
-- Durable movements belong to a purchase, not to the rolling 500-entry activity journal.
-- Keep the purchase origin when trimming movements; mark any missing history explicitly.
D.LOT_EVENTS = 300
local pendingEvents = setmetatable({}, { __mode = "k" })
local function appendEvent(lot, event)
    lot.events = lot.events or {}
    lot.events[#lot.events + 1] = event
    while #lot.events > D.LOT_EVENTS do
        table.remove(lot.events, lot.events[1].kind == "buy" and 2 or 1)
        lot.historyIncomplete = true
    end
    return event
end

local function movement(lot, e, qty, amount)
    return appendEvent(lot, {
        at = e.at,
        kind = e.kind,
        qty = qty,
        amount = amount,
        mode = e.mode,
        bid = e.bid,
        source = e.source,
        estimated = e.estimated,
        deposit = e.deposit,
        accounted = e.accounted,
    })
end

local function remember(char, kind, key, refs, at)
    local p = pendingEvents[char] or {}
    pendingEvents[char] = p
    p[kind] = { key = key, refs = refs, at = at }
    return p[kind]
end

-- Accounting records exact FIFO allocations first; the journal supplies the observed exit kind.
-- Calling this never books revenue, stock or costs a second time.
function D.logLotEvent(char, e)
    if not e.key then
        return
    end
    local category = e.kind == "buy" and "buy"
        or (e.kind == "sell" or e.kind == "vendor") and "sale"
        or (e.kind == "cancel" or e.kind == "expired" or e.kind == "return") and "loss"
    local pending = pendingEvents[char]
    local p = category and pending and pending[category]
    if p and p.key == e.key and (not p.at or not e.at or math.abs(p.at - e.at) <= 2) then
        e.lots = {}
        for _, ref in ipairs(p.refs) do
            local event = ref.event
            event.kind, event.estimated, event.accounted = e.kind, e.estimated, e.accounted
            event.source = e.source or event.source
            e.lots[#e.lots + 1] = { id = ref.lot.id, qty = event.qty, amount = event.amount }
        end
        if (p.written or 0) > 0 then
            -- D.addCost found no stock: the loss left the item's profit, so the day counts it.
            e.profit = -p.written
        end
        pending[category] = nil
        return
    end
    -- Non-financial movements (listing, returned items) use the same FIFO ownership convention.
    if e.kind ~= "post" and e.kind ~= "cancel" and e.kind ~= "expired" and e.kind ~= "return" then
        return
    end
    local left, allocated = e.lossQty or e.qty or 0, 0
    local total = left
    e.lots = {}
    for _, lot in ipairs(D.lots(char)) do
        if lot.key == e.key and left > 0 then
            local n = math.min(left, lot.left or 0)
            if n > 0 then
                left = left - n
                local amount = left == 0 and (e.amount or 0) - allocated
                    or math.floor((e.amount or 0) * n / math.max(total, 1))
                allocated = allocated + amount
                local event = movement(lot, e, n, amount)
                if e.deposit then
                    event.deposit = math.floor(e.deposit * n / math.max(total, 1))
                end
                e.lots[#e.lots + 1] = { id = lot.id, qty = n, amount = amount }
            end
        end
    end
end
-- Purchases of one item within D.LOT_MERGE seconds of the item's last lot join that lot: one
-- position bought in several clicks (or bought back from the player's own posts) is one row.
D.LOT_MERGE = 15 * 60
local function joinLot(into, lot)
    into.qty, into.cost = (into.qty or 0) + (lot.qty or 0), (into.cost or 0) + (lot.cost or 0)
    into.left, into.sold = (into.left or 0) + (lot.left or 0), (into.sold or 0) + (lot.sold or 0)
    into.received, into.lost = (into.received or 0) + (lot.received or 0), (into.lost or 0) + (lot.lost or 0)
    into.soldAt = math.max(into.soldAt or 0, lot.soldAt or 0) > 0 and math.max(into.soldAt or 0, lot.soldAt or 0) or nil
    into.mode = into.mode or lot.mode
    for _, e in ipairs(lot.events or {}) do
        appendEvent(into, e)
    end
    into.historyIncomplete = into.historyIncomplete or lot.historyIncomplete
end

local function lotKind(mode, bid)
    return bid and "bid" or mode == "vendor" and "vendor" or "flip"
end

-- Only purchases of the same kind join the item's last lot. The products of a craft or a
-- disenchant (T21: `chain`) are a lot of their own, and nothing joins them.
local function lotToJoin(lots, key, at, mode, bid, chain, strategy)
    if chain then
        return nil
    end
    for i = #lots, 1, -1 do
        local lot = lots[i]
        if lot.key == key then
            return at
                    and not lot.chain
                    and lot.at
                    and at - lot.at <= D.LOT_MERGE
                    and at >= lot.at
                    and lotKind(lot.mode, lot.bid) == lotKind(mode, bid)
                    and lot.strategy == strategy
                    and lot
                or nil
        end
    end
end

-- Lots booked before purchases were joined: each item's lots bought close together become one.
local function joinSaved(char)
    local out = {}
    for _, lot in ipairs(char.lots) do
        local into = lotToJoin(out, lot.key, lot.at, lot.mode, lot.bid, lot.chain, lot.strategy)
        if into then
            joinLot(into, lot)
        else
            out[#out + 1] = lot
        end
    end
    char.lots, char.lotsJoined = out, 1
end

local function shareLoss(lots, amount, qty, at, refs)
    local units, first = 0, nil
    for _, lot in ipairs(lots) do
        if (lot.left or 0) > 0 then
            first = first or lot
            units = units + lot.left
        end
    end
    if not first then
        local last = lots[#lots]
        if last then
            last.lost = (last.lost or 0) + amount
            if refs then
                refs[#refs + 1] = { lot = last, event = movement(last, { kind = "loss", at = at }, qty or 0, amount) }
            end
        end
        return
    end
    units = math.min(units, math.max(1, qty or first.left))
    local left, allocated = units, 0
    for _, lot in ipairs(lots) do
        local n = math.min(left, lot.left or 0)
        if n > 0 then
            left = left - n
            local share = left == 0 and amount - allocated or math.floor(amount * n / units)
            lot.lost = (lot.lost or 0) + share
            allocated = allocated + share
            if refs then
                refs[#refs + 1] = { lot = lot, event = movement(lot, { kind = "loss", at = at }, n, share) }
            end
        end
    end
end

-- Per character: the lots table D.lots checked last, and the last bid log entry it looked at.
local checkedLots = setmetatable({}, { __mode = "k" })
function D.lots(char)
    if type(char.lots) ~= "table" then
        char.lots = {}
        char.lotSeq = 0
        local open = {}
        for _, e in ipairs(char.journal or {}) do
            if e.kind == "buy" and e.key and (e.qty or 0) > 0 then
                local lot = lotToJoin(char.lots, e.key, e.at, e.mode, e.bid, nil, e.strategy)
                if lot then
                    lot.qty, lot.cost, lot.left = lot.qty + e.qty, lot.cost + (e.amount or 0), lot.left + e.qty
                else
                    char.lotSeq = char.lotSeq + 1
                    lot = {
                        id = char.lotSeq,
                        key = e.key,
                        name = e.name,
                        at = e.at,
                        qty = e.qty,
                        cost = e.amount or 0,
                        mode = e.mode,
                        bid = e.bid,
                        left = e.qty,
                        sold = 0,
                        received = 0,
                        lost = 0,
                    }
                    char.lots[#char.lots + 1] = lot
                    open[e.key] = open[e.key] or {}
                    table.insert(open[e.key], lot)
                end
            elseif (e.kind == "sell" or e.kind == "vendor") and e.key and open[e.key] then
                local left = e.qty or 0
                for _, lot in ipairs(open[e.key]) do
                    if left <= 0 then
                        break
                    end
                    local take = math.min(left, lot.left)
                    if take > 0 then
                        lot.left, lot.sold = lot.left - take, lot.sold + take
                        lot.received = lot.received + math.floor((e.amount or 0) * take / math.max(e.qty, 1) + 0.5)
                        lot.soldAt = e.at
                        left = left - take
                    end
                end
            elseif FAILED_KINDS[e.kind] and e.key and open[e.key] and (e.amount or 0) > 0 then
                shareLoss(open[e.key], e.amount, e.lossQty or e.qty)
            end
        end
        trimLots(char.lots)
        char.lotsJoined = 1
    elseif char.lotsJoined ~= 1 then
        joinSaved(char)
    end
    -- The repairs below run once per lots table (the journal page asks for the lots on every
    -- refresh): a table built or joined above is a new one and is checked again.
    local seen = checkedLots[char]
    if not seen or seen.lots ~= char.lots then
        for _, lot in ipairs(char.lots) do
            if type(lot.events) ~= "table" then
                -- Surviving totals are authoritative; the global journal may have lost the origin
                -- and cannot safely attribute sales to these old lots.
                lot.events, lot.historyIncomplete = {}, true
            end
        end
        seen = { lots = char.lots }
        checkedLots[char] = seen
    end
    -- Older bid wins predate the purchase's bid flag. Require a unique exact match;
    -- the item alone cannot distinguish a bid from a later buyout. The bid log only grows at its
    -- end: wins after the last one checked are new.
    local log = type(char.bidLog) == "table" and char.bidLog or {}
    local from = 1
    for i = #log, 1, -1 do
        if log[i] == seen.last then
            from = i + 1
            break
        end
    end
    for i = from, #log do
        local b = log[i]
        if b.outcome == "won" and b.ended then
            local match, n = nil, 0
            for _, lot in ipairs(char.lots) do
                if lot.key == b.key and lot.qty == b.qty and lot.cost == b.amount and lot.at == b.ended then
                    match, n = lot, n + 1
                end
            end
            if n == 1 then
                match.bid = true
            end
        end
    end
    seen.last = log[#log]
    return char.lots
end

local function openLots(char, key)
    local out = {}
    for _, lot in ipairs(D.lots(char)) do
        if lot.key == key and (lot.left or 0) > 0 then
            out[#out + 1] = lot
        end
    end
    return out
end

-- A cost of holding the item that is not its price: a deposit lost on an expired or cancelled post,
-- a cancel fee. It joins the stock's cost, so the floor and the next sale's profit count it; with no
-- stock left it is booked straight into the item's profit. Returns that part (0 when stock took
-- it): the journal entry logged next for the loss carries it as its profit (D.logLotEvent).
function D.addCost(char, key, amount, at, qty)
    -- An infinite amount would make every floor and break-even price infinite.
    if not key or not U.finite(amount) or amount <= 0 then
        return 0
    end
    local p = char.positions[key]
    local s = D.itemStats(char, key, p and p.name)
    s.lost = (s.lost or 0) + amount
    local written = 0
    if p and p.qty > 0 then
        p.cost, p.lost = p.cost + amount, (p.lost or 0) + amount
    else
        s.profit = s.profit - amount
        written = amount
    end
    local lots, refs = openLots(char, key), {}
    if #lots > 0 then
        shareLoss(lots, amount, qty, at, refs)
    else
        for i = #D.lots(char), 1, -1 do
            local lot = char.lots[i]
            if lot.key == key then
                lot.lost = (lot.lost or 0) + amount
                refs[#refs + 1] = { lot = lot, event = movement(lot, { kind = "loss", at = at }, qty or 0, amount) }
                break
            end
        end
    end
    remember(char, "loss", key, refs, at).written = written
    return written
end

-- Journal losses can be exact recorded charges, reconstructed estimates, or an older
-- total whose source event has aged out. Keep that distinction visible to the user.
function D.lossEvidence(char, key)
    local out = { recorded = 0, estimated = 0, unattributed = 0 }
    for _, e in ipairs(char.journal or {}) do
        if e.key == key and FAILED_KINDS[e.kind] then
            local field = e.estimated and "estimated" or "recorded"
            out[field] = out[field] + (e.amount or 0)
        end
    end
    local total = char.stats and char.stats[key] and char.stats[key].lost or 0
    out.unattributed = math.max(0, total - out.recorded - out.estimated)
    return out
end

-- Recount ------------------------------------------------------------------------------------------
-- WoW Forever mails the items of a cancelled auction with a buyer invoice. Up to 2.0.0-beta.1 that
-- was booked as a purchase at the post's price: tens of gold "spent" that never left the bags. The
-- journal holds such returns as buys of one item that follow each other within D.RETURN_GAP
-- seconds, each of D.RETURN_MIN units or more: taking mail books them a second apart, while a
-- purchase on the auction house (a quote, then a confirmation) takes longer. Only what the buyer
-- invoice booked counts (ForeverFlip's purchases carry a mode, a merchant's `merchant`, a won bid
-- `bid`), and only units the player had posted before at the price they were booked at. They
-- become kind "return": `posted` keeps the price they were booked at, `amount` becomes the deposit
-- lost, `booked` says the purchase is still in the books until D.recount takes it out (returns an
-- older recount found were taken out by it).
D.RETURN_GAP, D.RETURN_MIN = 10, 5
local function returnedPost(posts, e)
    if e.kind ~= "buy" or not e.key or (e.qty or 0) < D.RETURN_MIN or e.mode or e.merchant or e.bid then
        return nil
    end
    for _, p in ipairs(posts[e.key] or {}) do
        -- The post's price for the units that came back, to the copper the invoice was rounded to.
        if p.qty >= e.qty and math.abs((e.amount or 0) * p.qty - (p.amount or 0) * e.qty) <= p.qty then
            return p
        end
    end
end

function D.markReturns(journal)
    local last, out, posts = {}, {}, {}
    for i, e in ipairs(journal) do
        if e.kind == "post" and e.key and (e.qty or 0) > 0 then
            posts[e.key] = posts[e.key] or {}
            table.insert(posts[e.key], e)
        elseif returnedPost(posts, e) then
            local p = last[e.key] and journal[last[e.key]]
            if p and (e.at or 0) - (p.at or 0) <= D.RETURN_GAP then
                for _, x in ipairs({ p, e }) do
                    if x.kind == "buy" then
                        x.kind, x.posted, x.amount, x.booked = "return", x.amount, 0, true
                        out[#out + 1] = x
                    end
                end
            end
            last[e.key] = i
        end
    end
    return out
end

-- A sale costed again: its entry, the item's profit and the day's totals take the new profit.
local function reprofit(char, s, e, profit)
    local old = e.profit or 0
    if profit == old then
        return
    end
    s.profit, e.profit = s.profit + profit - old, profit
    local d = type(char.daily) == "table" and char.daily[math.floor((e.at or 0) / 86400)]
    if d then
        d.profit, d.cost = d.profit + profit - old, d.cost - (profit - old)
        d.wins = d.wins + (profit > 0 and 1 or 0) - (old > 0 and 1 or 0)
        if e.kind == "vendor" then
            d.vendor = d.vendor + profit - old
        else
            d.auction = d.auction + profit - old
        end
    end
end

-- The lot a return was booked into gives back its units and price: the lot its journal entry names,
-- else the item's lot it joined or started (lots built from the journal before it was found). Sales
-- that FIFO gave to the returned units sold units of the item's next lots.
local function unbookLot(char, e)
    local lots, refs, index = char.lots, type(e.lots) == "table" and e.lots or {}, nil
    for i, lot in ipairs(lots) do
        for _, ref in ipairs(refs) do
            if lot.id == ref.id and lot.key == e.key then
                index = i
            end
        end
    end
    for i = #lots, 1, -1 do
        local lot = lots[i]
        if #refs == 0 and lot.key == e.key and lot.at and e.at and lot.at <= e.at then
            if e.at - lot.at <= D.LOT_MERGE and lotKind(lot.mode, lot.bid) == "flip" then
                index = i
            end
            break
        end
    end
    local lot = index and lots[index]
    if not lot or (lot.qty or 0) < e.qty then
        return
    end
    lot.qty, lot.cost, lot.left = lot.qty - e.qty, (lot.cost or 0) - e.posted, (lot.left or 0) - e.qty
    local over, sold = -lot.left, lot.sold or 0
    if over > 0 then
        local moved = sold > 0 and math.floor((lot.received or 0) * over / sold + 0.5) or 0
        lot.left, lot.sold, lot.received = 0, sold - over, (lot.received or 0) - moved
        for i = index + 1, #lots do
            local l = lots[i]
            if over > 0 and l.key == e.key and (l.left or 0) > 0 then
                local n = math.min(over, l.left)
                local share = n == over and moved or math.floor(moved * n / over + 0.5)
                l.left, l.sold, l.received = l.left - n, (l.sold or 0) + n, (l.received or 0) + share
                over, moved = over - n, moved - share
            end
        end
        -- Sold beyond the item's later lots: those sales stay on this one.
        lot.sold, lot.received = lot.sold + over, lot.received + moved
    end
    for i, event in ipairs(lot.events or {}) do
        if event.kind == "buy" and event.at == e.at and event.qty == e.qty and event.amount == e.posted then
            table.remove(lot.events, i)
            break
        end
    end
    if lot.qty <= 0 and (lot.sold or 0) <= 0 and (lot.lost or 0) <= 0 then
        table.remove(lots, index)
    end
end

-- Takes the returns of `key` still booked as purchases out of the books. Every movement after the
-- first of them is still in the journal (it drops its oldest entries): the item's stock before it
-- is worked back from today's, and those movements are booked again without the returns, so the
-- sales since get their real cost. Losses stay where they were booked.
local function unbookReturns(char, key, from)
    local journal, entries = char.journal, {}
    for i = from, #journal do
        if journal[i].key == key then
            entries[#entries + 1] = journal[i]
        end
    end
    local function returned(e)
        return e.kind == "return" and e.booked and e.posted
    end
    local p, s = char.positions[key], D.itemStats(char, key)
    local qty, cost, units, price, known = p and p.qty or 0, p and p.cost or 0, 0, 0, true
    for i = #entries, 1, -1 do
        local e = entries[i]
        if returned(e) then
            qty, cost, units, price = qty - e.qty, cost - e.posted, units + e.qty, price + e.posted
        elseif e.kind == "buy" then
            qty, cost = qty - (e.qty or 0), cost - (e.amount or 0)
        elseif e.kind == "sell" or e.kind == "vendor" then
            known = known and e.profit ~= nil
            qty, cost = qty + (e.qty or 0), cost + (e.amount or 0) - (e.profit or 0)
        end
    end
    if known and qty >= 0 and cost >= 0 then
        for _, e in ipairs(entries) do
            if e.kind == "buy" then
                qty, cost = qty + (e.qty or 0), cost + (e.amount or 0)
            elseif e.kind == "sell" or e.kind == "vendor" then
                local n = math.min(e.qty or 0, qty)
                local taken = n > 0 and math.floor(cost * n / qty + 0.5) or 0
                qty, cost = qty - n, cost - taken
                reprofit(char, s, e, (e.amount or 0) - taken)
            end
        end
        if qty <= 0 then
            -- Cost left without stock (a loss booked on the returned units) belongs to the sales.
            s.profit = s.profit - cost
        end
    else
        -- Today's stock does not follow from the journal: the returned units leave it at its
        -- average cost, and the sales keep their profits.
        qty = (p and p.qty or 0) - units
        cost = qty > 0 and math.floor(p.cost * qty / p.qty + 0.5) or 0
    end
    if p and qty > 0 then
        p.qty, p.cost = qty, cost
    elseif p then
        char.positions[key] = nil
    end
    s.bought, s.spent = math.max(0, s.bought - units), math.max(0, s.spent - price)
    for _, e in ipairs(entries) do
        if returned(e) then
            local d = type(char.daily) == "table" and char.daily[math.floor((e.at or 0) / 86400)]
            if d then
                d.spent, d.buys = math.max(0, d.spent - e.posted), math.max(0, d.buys - 1)
            end
            if type(char.lots) == "table" then
                unbookLot(char, e)
            end
            e.booked = nil
        end
    end
end

-- Stock, item totals, purchase lots and daily totals are never rebuilt from the journal: it keeps
-- only its last 500 entries, and what was booked before them would be lost. A recount corrects them.
-- The returns D.markReturns just found leave them at once, in the call right after it: lots and
-- daily totals that did not exist then are built from the journal later, where they are no
-- purchases. A post that came back (expired, cancelled, returned) without its deposit gets
-- `deposit(key, qty)`, the estimate of what posting it cost, booked as a loss now (D.addCost); nil
-- when that is not known yet (the item's merchant price is still loading): then no estimate is
-- booked and false is returned. What an item lost beyond the journal (cancels made before they were
-- logged) is often the very cancel a return came back from: a return's estimate is booked only past
-- it.
function D.recount(char, deposit)
    local journal = char.journal or {}
    local first = {}
    for i, e in ipairs(journal) do
        if e.kind == "return" and e.booked and e.posted and e.key and not first[e.key] then
            first[e.key] = i
        end
    end
    for key, i in pairs(first) do
        unbookReturns(char, key, i)
    end
    local keyOf = {}
    for _, e in ipairs(journal) do
        if e.key and e.name then
            keyOf[string.lower(e.name)] = e.key
        end
    end
    local fills, known = {}, {}
    for _, e in ipairs(journal) do
        if FAILED_KINDS[e.kind] then
            local key = e.key or (e.name and keyOf[string.lower(e.name)])
            if key and (e.amount or 0) <= 0 and not e.accounted then
                local d = deposit(key, e.qty or 1)
                if d == nil then
                    return false
                end
                fills[#fills + 1] = { e = e, key = key, amount = d }
            elseif key then
                known[key] = (known[key] or 0) + (e.amount or 0)
            end
        end
    end
    local beyond = {}
    for key, s in pairs(char.stats or {}) do
        beyond[key] = math.max(0, (s.lost or 0) - (known[key] or 0))
    end
    if #fills > 0 then
        -- Built before the estimates are written into the journal, which a new lots table reads.
        D.lots(char)
    end
    for _, f in ipairs(fills) do
        local e, book = f.e, f.amount
        if e.kind == "return" then
            local same = math.min(book, beyond[f.key] or 0)
            beyond[f.key], book = (beyond[f.key] or 0) - same, book - same
        end
        pendingEvents[char] = nil
        local written = D.addCost(char, f.key, book, e.at, e.lossQty or e.qty)
        e.key, e.amount, e.estimated = f.key, f.amount, true
        if pendingEvents[char] then
            -- The lots' shares of the loss take the entry's kind (no second booking).
            D.logLotEvent(char, e)
        end
        if written > 0 and type(char.daily) == "table" then
            local d = dayOf(char, e.at)
            d.profit = d.profit - written
        end
    end
    pendingEvents[char] = nil
    return true
end

-- Positions: what was bought and not yet sold, with its cost (average price).
-- `chain` (T21): the units are the products of a craft or a disenchant (D.convert), not a purchase:
-- their cost was spent on the materials, so the item's bought/spent totals are left alone.
-- `strategy` (Deals): "median" for a market reset; it keeps its own lots, and the position
-- remembers the way it was bought for (p.strategy, p.bought) so Selling keeps it (Trade.sellWay).
function D.addPosition(char, key, name, qty, cost, mode, exit, at, bid, source, chain, strategy)
    local p = char.positions[key]
    if not p then
        p = { qty = 0, cost = 0, name = name, since = at }
        char.positions[key] = p
    end
    if at then
        if not chain then
            local s = D.itemStats(char, key, name)
            s.bought, s.spent = s.bought + qty, s.spent + cost
        end
        local lots = D.lots(char)
        local into = lotToJoin(lots, key, at, mode, bid, chain, strategy)
        if into then
            into.qty, into.cost, into.left = into.qty + qty, into.cost + cost, into.left + qty
            into.mode = into.mode or mode
        else
            char.lotSeq = (char.lotSeq or 0) + 1
            into = {
                id = char.lotSeq,
                key = key,
                name = name,
                at = at,
                qty = qty,
                cost = cost,
                mode = mode,
                bid = bid,
                left = qty,
                sold = 0,
                received = 0,
                lost = 0,
                events = {},
                chain = chain,
                strategy = strategy,
            }
            lots[#lots + 1] = into
        end
        local event = movement(
            into,
            { at = at, kind = "buy", mode = mode, bid = bid, source = source or (bid and "bid" or "buyout") },
            qty,
            cost
        )
        if not chain then
            remember(char, "buy", key, { { lot = into, event = event } }, at)
        end
        trimLots(lots)
    end
    -- Stock held for resale stays for resale when a vendor deal of the same item adds cheap units:
    -- else the vendor sale would sell the dearer resale units at a loss too.
    local kept = mode == "vendor" and p.qty > 0 and p.mode and p.mode ~= "vendor"
    if kept then
        mode = p.mode
    elseif at and not chain then
        p.strategy, p.bought = bid and "bid" or strategy or mode, at
    end
    p.qty, p.cost = p.qty + qty, p.cost + cost
    p.mode, p.exit, p.name = mode or p.mode, exit or p.exit, name or p.name
    return p
end

-- A sale of `qty` units for `amount` (after the cut) at time `at`; returns the units' cost.
function D.sale(char, key, name, qty, amount, at)
    local since = char.positions[key] and char.positions[key].since
    local cost = D.takePosition(char, key, qty)
    -- The oldest lots of the item sold first; the money is shared by units.
    local left, allocated, refs = qty, 0, {}
    for _, lot in ipairs(openLots(char, key)) do
        if left <= 0 then
            break
        end
        local take = math.min(left, lot.left)
        lot.left, lot.sold = lot.left - take, lot.sold + take
        local share = left == take and amount - allocated or math.floor(amount * take / math.max(qty, 1))
        allocated = allocated + share
        lot.received = lot.received + share
        lot.soldAt = at
        left = left - take
        refs[#refs + 1] = { lot = lot, event = movement(lot, { kind = "sell", at = at }, take, share) }
    end
    remember(char, "sale", key, refs, at)
    local s = D.itemStats(char, key, name)
    s.sold, s.earned, s.profit = s.sold + qty, s.earned + amount, s.profit + amount - cost
    if since and at then
        s.days = s.days + (at - since) / 86400 * qty
    end
    s.lastSale = at
    return cost
end

-- Removes `qty` units at average cost; returns that cost.
function D.takePosition(char, key, qty)
    local p = char.positions[key]
    if not p or p.qty <= 0 then
        return 0
    end
    qty = math.min(qty, p.qty)
    local cost = math.floor(p.cost * qty / p.qty + 0.5)
    p.qty, p.cost = p.qty - qty, p.cost - cost
    if p.qty <= 0 then
        char.positions[key] = nil
    end
    return cost
end

-- T21: chains. Held units made into other items: `op` "disenchant" or "craft", `inputs` and
-- `outputs` { { key, name, qty }, ... } (an output may carry `value`, its unit price, to share the
-- cost by worth; else by units). The inputs leave their positions and their oldest lots at the
-- positions' cost (lot.converted, lot.convertedCost and a movement of kind `op`); the outputs become
-- lots of their own (lot.chain) that carry that cost, so their sale shows what the chain earned.
-- Only held units count: none held, no chain (nil). Older entries and lots have no chain.
D.CHAINS = 200
function D.convert(char, op, inputs, outputs, at)
    local id = (char.chainSeq or 0) + 1
    local used, cost = {}, 0
    for _, input in ipairs(inputs or {}) do
        local p = input.key and char.positions[input.key]
        local qty = p and math.min(input.qty or 0, p.qty) or 0
        if qty > 0 then
            local taken = D.takePosition(char, input.key, qty)
            local left, allocated, refs = qty, 0, {}
            for _, lot in ipairs(openLots(char, input.key)) do
                if left <= 0 then
                    break
                end
                local n = math.min(left, lot.left)
                left = left - n
                local share = left == 0 and taken - allocated or math.floor(taken * n / qty)
                allocated = allocated + share
                lot.left = lot.left - n
                lot.converted = (lot.converted or 0) + n
                lot.convertedCost = (lot.convertedCost or 0) + share
                movement(lot, { kind = op, at = at }, n, share).chain = id
                refs[#refs + 1] = { id = lot.id, qty = n, amount = share }
            end
            cost = cost + taken
            used[#used + 1] = { key = input.key, name = input.name or p.name, qty = qty, cost = taken, lots = refs }
        end
    end
    local made = {}
    for _, o in ipairs(outputs or {}) do
        if o.key and U.finite(o.qty) and o.qty > 0 then
            made[#made + 1] = o
        end
    end
    if #used == 0 or #made == 0 then
        return nil
    end
    char.chainSeq = id
    local weights, total = {}, 0
    for i, o in ipairs(made) do
        weights[i] = (U.finite(o.value) and o.value > 0 and o.value or 1) * o.qty
        total = total + weights[i]
    end
    local chain = { id = id, op = op, at = at, cost = cost, inputs = used, outputs = {} }
    local allocated = 0
    for i, o in ipairs(made) do
        local share = i == #made and cost - allocated or math.floor(cost * weights[i] / total)
        allocated = allocated + share
        D.addPosition(char, o.key, o.name, o.qty, share, "flip", nil, at, nil, op, id)
        chain.outputs[#chain.outputs + 1] = { key = o.key, name = o.name, qty = o.qty, cost = share }
    end
    char.chains = type(char.chains) == "table" and char.chains or {}
    char.chains[id] = chain
    char.chains[id - D.CHAINS] = nil
    D.log(char, {
        at = at,
        kind = op,
        key = used[1].key,
        name = used[1].name,
        qty = used[1].qty,
        amount = cost,
        chain = id,
    })
    return chain
end

-- What a chain brought so far: { cost, received, lost, left (output units unsold), profit, done }.
-- nil when the chain is not kept.
function D.chainProfit(char, id)
    local chain = id and type(char.chains) == "table" and char.chains[id]
    if not chain then
        return nil
    end
    local out = { cost = chain.cost or 0, received = 0, lost = 0, left = 0, op = chain.op }
    for _, lot in ipairs(D.lots(char)) do
        if lot.chain == id then
            out.received = out.received + (lot.received or 0)
            out.lost = out.lost + (lot.lost or 0)
            out.left = out.left + (lot.left or 0)
        end
    end
    out.profit = out.received - out.lost - out.cost
    out.done = out.left <= 0
    return out
end
