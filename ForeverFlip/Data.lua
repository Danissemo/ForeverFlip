-- Saved data (SavedVariables ForeverFlipData).
--   settings          language, profit floors, spending share
--   vendor[itemID]    the client's vendor sell price (0 = cannot be sold to a vendor)
--   vendorSeen[itemID] what a merchant really paid: { p = copper each, t = when, c = client price }
--   deSeen[band]      own disenchant results per item band: { n = disenchants, [itemID] = units }
--   lastScan          time of the last full scan request (one per 15 minutes for the account)
--   markets[scope]    per auction house: history[key] = { scan = {...}, flow = {...} }, stats
--   chars[owner]      per character: positions, journal, pending purchases, listings
local F = ForeverFlip
local D = {}
F.Data = D

D.DEFAULTS = {
    language = nil, -- "en" or "uk"; nil follows the game client
    vendorMinProfit = 10, -- copper per vendor deal
    minProfit = 100, -- copper per resale deal
    minROI = 0.2, -- resale return on the money spent
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
    autoVerify = false, -- check found deals in the background (the best ones first)
}

function D.open(saved)
    local db = type(saved) == "table" and saved or {}
    db.version = 1
    db.settings = type(db.settings) == "table" and db.settings or {}
    for k, v in pairs(D.DEFAULTS) do
        if db.settings[k] == nil then
            db.settings[k] = v
        end
    end
    -- 1.2.0-beta.1 to beta.3 saved a default margin of 20%: back to the new default, once.
    if not db.vendorMarginReset then
        if db.settings.vendorMargin == 20 then
            db.settings.vendorMargin = 0
        end
        db.vendorMarginReset = true
    end
    db.vendor = type(db.vendor) == "table" and db.vendor or {}
    db.vendorSeen = type(db.vendorSeen) == "table" and db.vendorSeen or {}
    db.sellable = type(db.sellable) == "table" and db.sellable or {}
    db.deSeen = type(db.deSeen) == "table" and db.deSeen or {}
    db.markets = type(db.markets) == "table" and db.markets or {}
    db.chars = type(db.chars) == "table" and db.chars or {}
    D.cleanSales(db)
    return db
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

function D.market(db, scope)
    local m = db.markets[scope]
    if type(m) ~= "table" then
        m = { history = {} }
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
-- qty, amount, profit }: for the last three, amount is the deposit (and cancel fee) lost.
-- Daily totals of the journal, kept D.DAILY_DAYS days: the journal keeps only its last 500
-- entries, and a busy week of Analytics read from it alone came out short.
D.DAILY_DAYS = 60
local function addDay(char, e)
    local day = math.floor((e.at or 0) / 86400)
    local d = char.daily[day]
    if not d then
        d = { spent = 0, buys = 0, earned = 0, profit = 0, cost = 0, sales = 0, wins = 0, vendor = 0, auction = 0 }
        char.daily[day] = d
    end
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

-- Journal kinds of a post that came back: its deposit (amount) was lost.
local FAILED_KINDS = { expired = true, ["return"] = true, cancel = true }

-- Purchase lots: every purchase with what became of it, first in, first out. char.lots = {
-- { id, key, name, at, qty, cost, mode, left, sold, received, lost, soldAt } }: cost = what the
-- purchase cost, received = the money its sold units brought after the cut, lost = deposits of
-- posts that expired or were cancelled and the game's cancel fees, booked on the lot whose units
-- were on sale. The last D.LOTS lots are kept.
D.LOTS = 300
-- Purchases of one item within D.LOT_MERGE seconds of the item's last lot join that lot: one
-- position bought in several clicks (or bought back from the player's own posts) is one row.
D.LOT_MERGE = 15 * 60
local function joinLot(into, lot)
    into.qty, into.cost = (into.qty or 0) + (lot.qty or 0), (into.cost or 0) + (lot.cost or 0)
    into.left, into.sold = (into.left or 0) + (lot.left or 0), (into.sold or 0) + (lot.sold or 0)
    into.received, into.lost = (into.received or 0) + (lot.received or 0), (into.lost or 0) + (lot.lost or 0)
    into.soldAt = math.max(into.soldAt or 0, lot.soldAt or 0) > 0 and math.max(into.soldAt or 0, lot.soldAt or 0) or nil
    into.mode = into.mode or lot.mode
end

local function lotKind(mode, bid)
    return bid and "bid" or mode == "vendor" and "vendor" or "flip"
end

-- Only purchases of the same kind join the item's last lot.
local function lotToJoin(lots, key, at, mode, bid)
    for i = #lots, 1, -1 do
        local lot = lots[i]
        if lot.key == key then
            return at
                    and lot.at
                    and at - lot.at <= D.LOT_MERGE
                    and at >= lot.at
                    and lotKind(lot.mode, lot.bid) == lotKind(mode, bid)
                    and lot
                or nil
        end
    end
end

-- Lots booked before purchases were joined: each item's lots bought close together become one.
local function joinSaved(char)
    local out = {}
    for _, lot in ipairs(char.lots) do
        local into = lotToJoin(out, lot.key, lot.at, lot.mode, lot.bid)
        if into then
            joinLot(into, lot)
        else
            out[#out + 1] = lot
        end
    end
    char.lots, char.lotsJoined = out, 1
end

function D.lots(char)
    if type(char.lots) ~= "table" then
        char.lots = {}
        char.lotSeq = 0
        local open = {}
        for _, e in ipairs(char.journal or {}) do
            if e.kind == "buy" and e.key and (e.qty or 0) > 0 then
                local lot = lotToJoin(char.lots, e.key, e.at, e.mode, e.bid)
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
                for _, lot in ipairs(open[e.key]) do
                    if lot.left > 0 then
                        lot.lost = lot.lost + e.amount
                        break
                    end
                end
            end
        end
        while #char.lots > D.LOTS do
            table.remove(char.lots, 1)
        end
        char.lotsJoined = 1
    elseif char.lotsJoined ~= 1 then
        joinSaved(char)
    end
    -- Older bid wins predate the purchase's bid flag. Require a unique exact match;
    -- the item alone cannot distinguish a bid from a later buyout.
    for _, b in ipairs(char.bidLog or {}) do
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
-- stock left it is booked straight into the item's profit.
function D.addCost(char, key, amount, at, qty)
    if not key or type(amount) ~= "number" or amount ~= amount or amount <= 0 then
        return
    end
    local p = char.positions[key]
    local s = D.itemStats(char, key, p and p.name)
    s.lost = (s.lost or 0) + amount
    if p and p.qty > 0 then
        p.cost, p.lost = p.cost + amount, (p.lost or 0) + amount
    else
        s.profit = s.profit - amount
    end
    local lots = openLots(char, key)
    if #lots > 0 then
        local units = 0
        for _, lot in ipairs(lots) do
            units = units + lot.left
        end
        units = math.min(units, math.max(1, qty or lots[1].left))
        local left, allocated = units, 0
        for _, lot in ipairs(lots) do
            local n = math.min(left, lot.left)
            if n > 0 then
                left = left - n
                local share = left == 0 and amount - allocated or math.floor(amount * n / units)
                lot.lost = (lot.lost or 0) + share
                allocated = allocated + share
            end
        end
    else
        for i = #D.lots(char), 1, -1 do
            local lot = char.lots[i]
            if lot.key == key then
                lot.lost = (lot.lost or 0) + amount
                break
            end
        end
    end
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
-- purchase on the auction house (a quote, then a confirmation) takes longer. They become kind
-- "return": `posted` keeps the price they were booked at, `amount` becomes the deposit lost.
D.RETURN_GAP, D.RETURN_MIN = 10, 5
function D.markReturns(journal)
    local last, out = {}, {}
    for i, e in ipairs(journal) do
        if e.kind == "buy" and e.key and (e.qty or 0) >= D.RETURN_MIN then
            local p = last[e.key] and journal[last[e.key]]
            if p and (e.at or 0) - (p.at or 0) <= D.RETURN_GAP then
                for _, x in ipairs({ p, e }) do
                    if x.kind == "buy" then
                        x.kind, x.posted, x.amount = "return", x.amount, 0
                        out[#out + 1] = x
                    end
                end
            end
            last[e.key] = i
        end
    end
    return out
end

-- Rebuilds the item totals, stock, purchase lots and daily totals from the journal (which keeps
-- every trade: D.log drops entries only past 500). A post that came back (expired, cancelled,
-- returned) without its deposit gets `deposit(key, qty)`, the estimate of what posting it cost; nil
-- when that is not known yet (the item's merchant price is still loading): then nothing changes
-- and false is returned. Losses the journal never held (cancels made before they were logged)
-- are kept: what an item lost beyond the journal is booked again, less the returns' estimates
-- (a return is often that very cancel).
function D.recount(char, deposit)
    local journal = char.journal or {}
    local keyOf = {}
    for _, e in ipairs(journal) do
        if e.key and e.name then
            keyOf[string.lower(e.name)] = e.key
        end
    end
    local fills, known, guessed = {}, {}, {}
    for _, e in ipairs(journal) do
        if FAILED_KINDS[e.kind] then
            local key = e.key or (e.name and keyOf[string.lower(e.name)])
            if key and (e.amount or 0) <= 0 then
                local d = deposit(key, e.qty or 1)
                if d == nil then
                    return false
                end
                fills[#fills + 1] = { e = e, key = key, amount = d }
                if e.kind == "return" then
                    guessed[key] = (guessed[key] or 0) + d
                end
            elseif key then
                known[key] = (known[key] or 0) + (e.amount or 0)
            end
        end
    end
    local extra = {}
    for key, s in pairs(char.stats or {}) do
        local x = (s.lost or 0) - (known[key] or 0) - (guessed[key] or 0)
        if x > 0 then
            extra[key] = x
        end
    end
    for _, f in ipairs(fills) do
        f.e.key, f.e.amount, f.e.estimated = f.key, f.amount, true
    end
    local old, oldStats, modes, traded = char.positions or {}, char.stats or {}, {}, {}
    for _, e in ipairs(journal) do
        if e.key then
            traded[e.key] = true
        end
    end
    -- Recover metadata from the matching purchase, never from another lot of the same item.
    local oldLots = char.lots or {}
    for _, e in ipairs(journal) do
        if e.kind == "vendor" and e.key then
            modes[e.key] = "vendor"
        end
    end
    local function purchaseLot(e)
        for i = #oldLots, 1, -1 do
            local lot = oldLots[i]
            if lot.key == e.key and e.at and lot.at and e.at >= lot.at and e.at - lot.at <= D.LOT_MERGE then
                return lot
            end
        end
    end
    char.stats, char.positions, char.lots, char.lotSeq, char.lotsJoined = {}, {}, {}, 0, 1
    for _, e in ipairs(journal) do
        if e.kind == "buy" and e.key then
            local p, lot = old[e.key], purchaseLot(e)
            local bid = e.bid
            if bid == nil and e.mode == nil and lot then
                bid = lot.bid
            end
            D.addPosition(
                char,
                e.key,
                e.name,
                e.qty or 0,
                e.amount or 0,
                e.mode or lot and lot.mode or p and p.mode or modes[e.key],
                p and p.exit,
                e.at,
                bid
            )
        elseif (e.kind == "sell" or e.kind == "vendor") and e.key then
            local cost = D.sale(char, e.key, e.name, e.qty or 0, e.amount or 0, e.at)
            e.profit = (e.amount or 0) - cost
        elseif FAILED_KINDS[e.kind] and e.key and (e.amount or 0) > 0 then
            D.addCost(char, e.key, e.amount, e.at, e.qty)
        end
    end
    -- Items the journal never mentions (stock from before it) keep what they had.
    for key, p in pairs(old) do
        if not traded[key] then
            char.positions[key] = p
        end
    end
    for key, st in pairs(oldStats) do
        if not traded[key] then
            char.stats[key] = st
            extra[key] = nil
        end
    end
    for key, x in pairs(extra) do
        D.addCost(char, key, x)
    end
    char.daily = nil
    D.daily(char)
    return true
end

-- Positions: what was bought and not yet sold, with its cost (average price).
function D.addPosition(char, key, name, qty, cost, mode, exit, at, bid)
    local p = char.positions[key]
    if not p then
        p = { qty = 0, cost = 0, name = name, since = at }
        char.positions[key] = p
    end
    if at then
        local s = D.itemStats(char, key, name)
        s.bought, s.spent = s.bought + qty, s.spent + cost
        local lots = D.lots(char)
        local into = lotToJoin(lots, key, at, mode, bid)
        if into then
            into.qty, into.cost, into.left = into.qty + qty, into.cost + cost, into.left + qty
            into.mode = into.mode or mode
        else
            char.lotSeq = (char.lotSeq or 0) + 1
            lots[#lots + 1] = {
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
            }
        end
        while #lots > D.LOTS do
            table.remove(lots, 1)
        end
    end
    -- Stock held for resale stays for resale when a vendor deal of the same item adds cheap units:
    -- else the vendor sale would sell the dearer resale units at a loss too.
    if mode == "vendor" and p.qty > 0 and p.mode and p.mode ~= "vendor" then
        mode = p.mode
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
    local left = qty
    for _, lot in ipairs(openLots(char, key)) do
        if left <= 0 then
            break
        end
        local take = math.min(left, lot.left)
        lot.left, lot.sold = lot.left - take, lot.sold + take
        lot.received = lot.received + math.floor(amount * take / math.max(qty, 1) + 0.5)
        lot.soldAt = at
        left = left - take
    end
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
