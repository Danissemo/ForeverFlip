-- Saved data (SavedVariables ForeverFlipData).
--   settings          language, profit floors, spending share
--   vendor[itemID]    vendor sell price (0 = cannot be sold to a vendor)
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
    spendShare = 0.8, -- share of the money on hand one deal may use
    duration = 3, -- 1 = 2 h, 2 = 8 h, 3 = 24 h, 0 = automatic from the item's sales
    autoScan = true, -- full scan every 15 minutes while the auction house is open
    itemShare = 0.3, -- share of the money one item may hold (stock and new resale)
    sniper = true, -- re-read hot items between full scans (one search per second)
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
    db.vendor = type(db.vendor) == "table" and db.vendor or {}
    db.markets = type(db.markets) == "table" and db.markets or {}
    db.chars = type(db.chars) == "table" and db.chars or {}
    return db
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

-- Journal entries: { at, kind = "buy" | "sell" | "vendor" | "fail", key, name, qty, amount, profit }
function D.log(char, entry)
    char.journal[#char.journal + 1] = entry
    while #char.journal > 500 do
        table.remove(char.journal, 1)
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

-- Positions: what was bought and not yet sold, with its cost (average price).
function D.addPosition(char, key, name, qty, cost, mode, exit, at)
    local p = char.positions[key]
    if not p then
        p = { qty = 0, cost = 0, name = name, since = at }
        char.positions[key] = p
    end
    if at then
        local s = D.itemStats(char, key, name)
        s.bought, s.spent = s.bought + qty, s.spent + cost
    end
    p.qty, p.cost = p.qty + qty, p.cost + cost
    p.mode, p.exit, p.name = mode or p.mode, exit or p.exit, name or p.name
    return p
end

-- A sale of `qty` units for `amount` (after the cut) at time `at`; returns the units' cost.
function D.sale(char, key, name, qty, amount, at)
    local since = char.positions[key] and char.positions[key].since
    local cost = D.takePosition(char, key, qty)
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
