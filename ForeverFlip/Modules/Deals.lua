-- Found deals and their exact verification. A deal from the full scan is only a lead: before it
-- can be bought, an exact search reads the item's current listings and the deal is evaluated
-- again with them. Searches run one at a time; explicit batches may use the faster server gate.
local F = ForeverFlip
local U = F.Util
local D = {}
F.Deals = D

D.list = {} -- deals of the current scope, best first
D.byName = {} -- item IDs whose plain search got no answer: searched by name instead
-- Seconds a verification stays valid for buying. A lot's buyout never changes: one bought by someone
-- meanwhile only makes the purchase fail, for nothing. 2 minutes was shorter than checking a page of
-- gear deals (a browse by name, then each version), so the first ones went back to "check again".
D.FRESH = 300
-- Seconds a selected, checked deal holds background searches back, counted from its selection or
-- its check, whichever is later: long enough to press Buy, short enough that Check all never looks
-- stuck behind a deal the player only looked at (120 seconds did, in game; 15 seconds still
-- stopped Check all at every click on a row). Pointing at Buy holds it as long as it stays there.
D.SELECTED_HOLD = 3
-- New searches in a rolling minute at most; the server's throttle is the real pace.
D.PER_MINUTE = 200
-- Shortest gap between two searches of the player or of Check all (was 0.4 s and 1 s).
D.GAP = 0.2
-- Total time spent waiting for sent replies across browse/versions/pages. Per-message
-- timeouts alone allow dozens of slow versions to monopolize the whole manual queue.
D.MAX_SEARCH_TIME = 30
-- Seconds without an answer before a search counts as unanswered: answers come within a second or
-- two, and WoW Forever never answers a search of an item nobody else sells. Check all's searches
-- give up sooner (they are sent once more at the end of the batch).
D.ANSWER_WAIT = 10
D.FAST_WAIT = 5
-- Check all on a deal page first asks for the lowest price of every item in one query (as the
-- sniper does, up to D.PRE_IDS items): an item nobody sells any more, or whose lowest price is at
-- or above what the deal sells for, is settled from that answer. Each of those waited for an
-- exact search the server never answers (WoW Forever), 35 deals took minutes. D.PRE_WAIT: seconds
-- the answer is waited for; without it every item gets its exact search as before.
D.PRE_IDS = 100
D.PRE_WAIT = 4
D.PRE_PAGES = 5
-- The quick check: the deals listed are D.QUICK_AGE seconds old or more (a scan of an hour ago, the
-- auction house opened again) and nothing else is going on: the same one query for the lowest price
-- of every item takes out the deals nobody sells any more and those whose lowest price leaves no
-- profit. Check all removed them all at once the moment it was pressed; now they go first.
D.QUICK_AGE = 120
-- Checking the bags (Check all on My items): a full scan up to this old stands for the searches of
-- the items it did not see, and one item's search gets at most D.BAG_SEARCH_TIME seconds of waiting
-- (a gear item with many remembered versions nobody sells waited 5 s for each, up to 30 s).
D.BAG_SCAN_AGE = 2 * 3600
D.BAG_SEARCH_TIME = 12
-- A Check all that made no progress for D.STALL_GIVEUP seconds while nothing the player does holds
-- it (a full scan, a purchase, a post, another page) gives up its oldest item as "no answer" and
-- goes on: "Checking Bags: 14/15" stood for good in game. The trace says what held the item.
D.STALL_GIVEUP = 45
-- Trace (Log.trace): a Check all batch with no item finished for this many seconds is written down
-- with what every search and gate is doing, again each time as long as it stays stuck; a search
-- that took longer than D.SLOW_SEARCH seconds is kept among the slowest (Log.slow).
D.STALL_TRACE = 10
D.SLOW_SEARCH = 5
-- A deal check of gear reads only the item-key versions whose lowest price (any ending, a bid or
-- the player's own lot included) is at most D.VERSION_REACH times what the deal sells for: lots of
-- the others cannot change the deal, as a page past that price already ends a version's reading.
-- Every version waited ~0.65 s for the throttle: a gear row of 30 versions took 20 s of Check all.
-- A remembered list of D.VERSION_QUERY versions or more is priced first, all in one query, gear
-- or not. A remembered version sold out since gets no answer at all on WoW Forever: the last
-- vendor deals of Check all waited 13 s each on such a second version (10 items, 137 s), where the
-- price query costs one throttle wait (~0.7 s) and drops it.
D.VERSION_REACH = 1.2
D.VERSION_QUERY = 2
D.VERSION_WAIT = 3

local function clock()
    return F.Engine.clock()
end

local function settings()
    return F.db.settings
end

-- The money one deal may use (settings.spendShare of the money on hand); the crafting plan uses
-- the same.
function D.budget()
    local s = settings()
    return math.floor(F.Engine.wallet() * (s.spendShare or 0.8))
end

-- The money one item may hold in all, stock and new resale (settings.itemShare).
function D.itemBudget()
    return math.floor(F.Engine.wallet() * (settings().itemShare or 0.3))
end

-- Evaluates a scan group or live listings. `g` has key, kind, id, rows, market, link.
-- One item may hold at most this share of the money (in stock plus the new purchase).
local function itemRoom(key)
    local p = F.Data.char(F.db, F.Engine.owner()).positions[key]
    return math.max(0, D.itemBudget() - (p and p.cost or 0)), p and p.qty or 0
end

-- How far the scan estimate of sales is trusted for an item, from own results: stock bought a
-- day ago and not sold since halves it, three days quarter it.
function D.trust(key, now)
    local c = F.Data.char(F.db, F.Engine.owner())
    local named = c.stats[key] and c.stats[key].name or c.positions[key] and c.positions[key].name
    local rate = named and F.Trade.rate(named)
    local factor = rate and math.max(0.25, math.min(1, rate / 0.5)) or 1
    return factor * D.ownTrust(c, key, now)
end

function D.ownTrust(c, key, now)
    local p = c.positions[key]
    if not p or not p.since or p.qty <= 0 then
        return 1
    end
    local s = c.stats[key]
    if s and s.lastSale and s.lastSale >= p.since then
        return 1
    end
    local held = (now or clock()) - p.since
    if held > 3 * 86400 then
        return 0.25
    elseif held > 86400 then
        return 0.5
    end
    return 1
end

-- The usual asking price, capped by what sales actually reached once enough were seen.
-- Price a resale may count on: the usual asking price, capped by what buyers really paid. An item
-- watched for an hour or more without one confirmed sale has none (nil, second value true): its
-- asking prices are not a price anyone pays.
function D.resaleCap(market, history)
    local cap = F.Market.saleCap(history)
    if cap and U.finite(market) then
        return math.min(market, cap)
    end
    if not cap and F.Market.watched(history) then
        return nil, true
    end
    return market or cap
end

-- T25: what the resale below the median has spent today (its journal purchases).
function D.medianSpent(now)
    local today = math.floor((now or clock()) / 86400)
    local spent = 0
    for _, e in ipairs(F.Data.char(F.db, F.Engine.owner()).journal) do
        if e.kind == "buy" and e.strategy == "median" and math.floor((e.at or 0) / 86400) == today then
            spent = spent + (e.amount or 0)
        end
    end
    return spent
end

-- T25: copper the resale below the median may still spend: the day's limit less today's
-- purchases, its share of the money on hand and, with `key`, the item's limit less the stock of it.
-- Never more than the ordinary budget (D.budget).
function D.medianRoom(key, now)
    local s = settings()
    local wallet = F.Engine.wallet()
    local room = math.min(
        D.budget(),
        math.floor((tonumber(s.medianDayGold) or 0) * 10000) - D.medianSpent(now),
        math.floor(wallet * (tonumber(s.medianShare) or 0))
    )
    if key then
        local p = F.Data.char(F.db, F.Engine.owner()).positions[key]
        room = math.min(room, math.floor((tonumber(s.medianItemGold) or 0) * 10000) - (p and p.cost or 0))
    end
    return math.max(0, room)
end

-- The market reset is off when its share of the gold or its day's gold is 0 (it has no switch).
function D.medianOff()
    local s = settings()
    return s.median == false or (tonumber(s.medianShare) or 0) <= 0 or (tonumber(s.medianDayGold) or 0) <= 0
end

-- T25: the market reset of a group (every lot under the usual price); nil and a reason.
function D.evaluateMedian(g, history, now)
    if D.medianOff() then
        return nil, "off"
    end
    if F.Shopping.blocked(g.key) then
        return nil, "blocked"
    end
    local room, held = itemRoom(g.key)
    local cap, unsold = D.resaleCap(g.market, history)
    if unsold then
        return nil, "not_selling"
    end
    local duration = F.Market.duration(g.key, nil, cap)
    -- The market reset relists at the median (Market.usualTarget) itself: capped by what buyers
    -- paid (D.resaleCap) it sold where Resale does, and the two pages showed the same deals. It
    -- stays under what most buyers paid (Market.paidTop) instead.
    return F.Market.evaluateMedian(g.rows, {
        kind = g.kind,
        history = history,
        now = now or clock(),
        held = held,
        budget = math.min(room, D.medianRoom(g.key, now)),
        trust = D.trust(g.key, now),
        depositVendor = F.AH.clientVendorPrice(g.id),
        deposit = F.AH.depositFn(g.id, g.kind, duration),
        duration = duration,
        settings = settings(),
    })
end

function D.evaluate(g, vendor, history, now)
    if F.Shopping.blocked(g.key) then
        return nil, "blocked"
    end
    local room, held = itemRoom(g.key)
    local cap, unsold = D.resaleCap(g.market, history)
    local duration = F.Market.duration(g.key, nil, cap)
    local deal, reason = F.Market.evaluate(g.rows, {
        kind = g.kind,
        vendor = vendor,
        depositVendor = F.AH.clientVendorPrice(g.id),
        held = held,
        itemBudget = room,
        trust = D.trust(g.key, now),
        budget = D.budget(),
        vendorBudget = F.Engine.wallet(),
        deposit = F.AH.depositFn(g.id, g.kind, duration),
        duration = duration,
        history = history,
        market = cap,
        noResale = unsold,
        -- The exit is the price the Sell page suggests (Market.postPrice, Trade.suggest).
        usual = F.Market.usual(history) or g.market,
        -- Resale picks its price by the sales seen (Market.evaluate): up to one step under the
        -- cheapest lot left, down to what buyers really paid, whichever brings the most money
        -- expected (Sure); it buys only what sells there in a day (Est./day).
        saleCap = F.Market.saleCap(history),
        limit = F.Trade.postLimit(F.Market.usual(history) or g.market),
        undercut = F.Trade.undercut,
        now = now or clock(),
        settings = settings(),
    })
    if not deal and F.Shopping.entry(g.key) then
        deal = F.Shopping.evaluate(g.rows, g.key, D.budget())
    end
    local ordered = F.Shopping.orderEntry and F.Shopping.orderEntry(g.key)
    if ordered then
        deal, reason = F.Shopping.evaluate(g.rows, g.key, D.budget()), nil
    end
    if not ordered and g.kind == "gear" and F.Disenchant.active() then
        local keep = F.Disenchant.sellValue(g.id, g.kind, g.key, vendor, F.Market.usual(history) or g.market)
        local de = F.Disenchant.evaluate(g.rows, g.id, D.budget(), keep)
        -- A shopping deal counts one auction (the player wants the item), a disenchant deal every
        -- lot: their profits do not compare, and the shopping list wins as an order does.
        if de and (not deal or deal.mode ~= "shop" and de.profit > deal.profit) then
            deal, reason = de, nil
        end
    end
    if deal then
        -- The other route of the lot (Market.evaluate: resale and vendor are judged apart).
        local alt = deal.alt
        deal.alt = nil
        local function finish(d)
            d.key, d.kind, d.id, d.link = g.key, g.kind, g.id, g.link
            d.market, d.vendor = g.market, vendor
            if d.mode == "vendor" then
                d.vendorHow = select(2, F.AH.vendorPrice(g.id))
                -- A merchant has refused the item before (a poison's item data is priced by what it
                -- costs, not by what a merchant pays). The refusal is for the session, so it must
                -- hold every scan: a scan started before the refusal would put the deal back, and
                -- the list would show it again with only a warning. It is dropped here, so no scan
                -- re-adds it.
                d.refused = F.AH.refusedByMerchant({ itemID = g.id })
                if d.refused then
                    return nil
                end
            end
            d.found = now or clock()
            return d
        end
        -- Only a resale and a vendor deal pair up; a shopping or disenchant deal stands alone.
        if alt and not ((deal.mode == "flip" or deal.mode == "vendor") and alt.mode ~= deal.mode) then
            alt = nil
        end
        alt = alt and finish(alt)
        deal = finish(deal)
        if not deal then
            if not alt then
                return nil, "refused"
            end
            deal, alt = alt, nil
        end
        deal.alt = alt
    end
    -- T25: the resale below the median rides along as `median` (its own page), or is the deal
    -- when the lot has no other. Its own reason is the third result: the scan counts them, so the
    -- Market reset page says why it is empty.
    local median, medianWhy = D.evaluateMedian(g, history, now)
    if median then
        median.key, median.kind, median.id, median.link = g.key, g.kind, g.id, g.link
        median.market, median.vendor = g.market, vendor
        median.found = now or clock()
        if deal then
            deal.median = median
        else
            deal, reason = median, nil
        end
    end
    return deal, reason, medianWhy
end

-- The deal of one route: `mode` "flip" or "vendor" picks the resale or the vendor deal of a lot
-- that pays both ways (d.alt); any other mode (or none) is the deal itself. nil when the lot has
-- no such route.
-- T25: mode "median" picks the resale below the median (d.median, or the deal itself). It is a
-- resale (mode "flip") for buying and selling, but not on the Resale page.
local function routeOf(x)
    return x.strategy == "median" and "median" or x.mode
end

-- The resale below the usual price riding along with another deal (d.median), or nil. A median
-- deal of its own carries its price under the same name (a number): not a deal.
function D.medianOf(d)
    return d and type(d.median) == "table" and d.median or nil
end

function D.route(d, mode)
    if not d or not mode or mode == "all" or routeOf(d) == mode then
        return d
    end
    if d.alt and routeOf(d.alt) == mode then
        return d.alt
    end
    if mode == "median" and D.medianOf(d) then
        return d.median
    end
    return nil
end

-- A merchant was sent the item and kept nothing: its vendor deals leave the list at once (the
-- price is real, the sale is not). Sent by AH.noteRefused the first time an item is proved.
function D.refused(id)
    local dropped = false
    for i = #D.list, 1, -1 do
        local d = D.list[i]
        if d.id == id and d.alt and d.alt.mode == "vendor" then
            d.alt, dropped = nil, true
        end
        if d.mode == "vendor" and d.id == id then
            if d.alt then
                D.list[i], d.alt.alt = d.alt, nil
            else
                table.remove(D.list, i)
            end
            dropped = true
        end
    end
    if dropped then
        F.Engine.changed()
    end
end

-- How sure a deal is to pay back at its Sells at price (0 to 1, Market.confidence), and the parts
-- of it: a vendor deal is sure (a merchant pays at once); a resale is reckoned from its sales.
D.SURE_KEEP = 30
D.sureCache = {}
function D.sure(d, now)
    if not d then
        return nil
    end
    if d.mode == "vendor" then
        return 1
    end
    if d.mode ~= "flip" or not U.finite(d.exit) then
        return nil
    end
    return D.sureAt(d.key, d.exit, D.sellQty(d), now)
end

-- The units a Sure is asked for, the same on the tooltip, the Deals page and Selling: a resale's
-- units plus those of it already held; otherwise the units in the bags (at least one).
function D.sellQty(d, key)
    if d and d.mode == "flip" then
        local p = F.Data.char(F.db, F.Engine.owner()).positions[d.key]
        return (d.qty or 1) + (p and p.qty or 0)
    end
    local ok, n = pcall(F.Trade.bagCount, key or (d and d.key))
    return math.max(1, ok and tonumber(n) or 1)
end

-- Sure of selling `qty` of an item at `price`, kept D.SURE_KEEP seconds for the same price,
-- quantity and sales data (it changes with a scan; the tooltip and the deals share it). Each price
-- and quantity has its own entry: the tooltip asks for one unit and for the deal's units of the
-- same item, and one entry per item made each of them throw the other's away.
-- The cache entry of a price and quantity: it changes with the sales data and with the lots of the
-- last scan, which are the queue in front of the price (Market.listedBelow). D.sureRange reads the
-- same entry.
local function sureStamp(h, price, qty)
    local data = type(h) == "table" and (h.sales and h.sales.at or h.flow and h.flow.at) or 0
    local lots = type(h) == "table" and h.lotsAt or 0
    return price .. ":" .. qty .. ":" .. tostring(data) .. ":" .. tostring(lots)
end

function D.sureAt(key, price, qty, now)
    now = now or clock()
    local h = F.Data.market(F.db, F.Engine.scope()).history[key]
    local stamp = sureStamp(h, price, qty)
    local slots = D.sureCache[key]
    local c = slots and slots[stamp]
    if c and now - c.at < D.SURE_KEEP then
        return c.sure, c.parts
    end
    local sure, parts = F.Market.confidence(h, price, qty, now, D.trust(key, now))
    if not slots then
        slots = {}
        D.sureCache[key] = slots
    end
    for old, entry in pairs(slots) do
        if now - entry.at >= D.SURE_KEEP then
            slots[old] = nil
        end
    end
    slots[stamp] = { at = now, sure = sure, parts = parts }
    return sure, parts
end

-- T32: Sure with its 80% limits (Market.sureLimits), kept in the same entry as the Sure of that
-- price and quantity. Returns sure, low, high; nil when there is no Sure.
function D.sureRange(key, price, qty, now)
    now = now or clock()
    local sure = D.sureAt(key, price, qty, now)
    if not U.finite(sure) then
        return nil
    end
    local h = F.Data.market(F.db, F.Engine.scope()).history[key]
    local c = D.sureCache[key][sureStamp(h, price, qty)]
    if c.low == nil then
        local _, low, high = F.Market.sureLimits(h, price, qty, now, D.trust(key, now))
        c.low, c.high = low or sure, high or sure
    end
    return sure, c.low, c.high
end

-- Gear: an ending with no sales data of its own (a new "of the Owl" of an item seen often) is
-- judged from the item's other endings. The keys of each item ID are listed once per scan.
local siblingIndex, siblingStamp, siblingOf
local function siblingKeys(item)
    local history = F.Data.market(F.db, F.Engine.scope()).history
    local last = F.Scan.last
    local stamp = last and last.at or 0
    if siblingOf ~= history or siblingStamp ~= stamp then
        siblingIndex, siblingStamp, siblingOf = {}, stamp, history
        for k in pairs(history) do
            local id = type(k) == "string" and k:match("^g:(%d+):")
            if id then
                id = tonumber(id)
                local list = siblingIndex[id] or {}
                list[#list + 1] = k
                siblingIndex[id] = list
            end
        end
    end
    return siblingIndex[item.id], history
end

-- Est./day and Sure of a gear ending from the item's other endings, each at its own usual price:
-- { perDay (the endings' average), sure (their median), n (endings counted) }, or nil (not gear,
-- or no other ending with sales data). An approximation: the pages show it greyed with "~".
D.siblingCache = {}
function D.siblingEstimate(key, qty, now)
    local item = U.parseKey(key)
    if not item or item.kind ~= "gear" or not F.db then
        return nil
    end
    now = now or clock()
    qty = math.max(1, qty or 1)
    local c = D.siblingCache[key .. ":" .. qty]
    if c and now - c.at < D.SURE_KEEP then
        return c.value or nil
    end
    local keys, history = siblingKeys(item)
    local perDay, n, sures = 0, 0, {}
    for _, k in ipairs(keys or {}) do
        local h = k ~= key and history[k]
        local price = h and F.Market.usual(h)
        if U.finite(price) and price > 0 then
            local s = F.Market.saleability(h, price, now)
            if s.known and U.finite(s.perDay) then
                perDay, n = perDay + s.perDay, n + 1
                local sure = F.Market.confidence(h, price, qty, now)
                if U.finite(sure) then
                    sures[#sures + 1] = sure
                end
            end
        end
    end
    local value = false
    if n > 0 then
        table.sort(sures)
        value = { perDay = perDay / n, sure = sures[math.ceil(#sures / 2)], n = n }
    else
        local h = history[key]
        local price = h and F.Market.usual(h)
        value = U.finite(price) and price > 0 and D.peerEstimate(price, qty, now) or false
    end
    D.siblingCache[key .. ":" .. qty] = { at = now, value = value }
    return value or nil
end

-- Gear with no ending of its own sold either (one seen once, nothing alike): judged from gear of
-- about the same usual price (D.PEER_BAND: within a factor of 2), at most D.PEER_SAMPLE of them,
-- once per scan and price band. { perDay, sure, n, peers = true }, or nil (none with sales data).
D.PEER_SAMPLE = 200
local peerBands, peerStamp, peerOf = {}, nil, nil
function D.peerEstimate(price, qty, now)
    local history = F.Data.market(F.db, F.Engine.scope()).history
    local last = F.Scan.last
    local stamp = last and last.at or 0
    if peerOf ~= history or peerStamp ~= stamp then
        peerBands, peerStamp, peerOf = {}, stamp, history
    end
    local band = math.floor(math.log(price) / math.log(2) + 0.5)
    local slot = band .. ":" .. qty
    if peerBands[slot] == nil then
        local low, high = 2 ^ (band - 1), 2 ^ (band + 1)
        local perDay, n, sures = 0, 0, {}
        for k, h in pairs(history) do
            if n >= D.PEER_SAMPLE then
                break
            end
            if type(k) == "string" and k:sub(1, 2) == "g:" then
                local usual = F.Market.usual(h)
                if U.finite(usual) and usual >= low and usual <= high then
                    local sale = F.Market.saleability(h, usual, now)
                    if sale.known and U.finite(sale.perDay) then
                        perDay, n = perDay + sale.perDay, n + 1
                        local sure = F.Market.confidence(h, usual, qty, now)
                        if U.finite(sure) then
                            sures[#sures + 1] = sure
                        end
                    end
                end
            end
        end
        table.sort(sures)
        peerBands[slot] = n > 0 and { perDay = perDay / n, sure = sures[math.ceil(#sures / 2)], n = n, peers = true }
            or false
    end
    return peerBands[slot] or nil
end

-- Plain items and commodities: the cells of Market.peerCell over the house's history, built once
-- per scan. cells[type .. price band .. ":" .. listed band] = { sum, n } of Market.peerValue at
-- each item's usual price; own[key] = the item's own value, left out of its similar items.
local peerCells, peerOwn, peerCellsStamp, peerCellsOf
local function itemPeerCells(history)
    local last = F.Scan.last
    local stamp = last and last.at or 0
    if peerCellsOf ~= history or peerCellsStamp ~= stamp then
        peerCells, peerOwn, peerCellsStamp, peerCellsOf = {}, {}, stamp, history
        local M = F.Market
        for k, h in pairs(history) do
            local tag = type(k) == "string" and k:sub(1, 2)
            if tag == "c:" or tag == "i:" then
                local usual = M.usual(h)
                local d = U.finite(usual) and usual > 0 and M.lotDemand(h, usual)
                if d then
                    local band, listed = M.peerCell(h, usual)
                    local cell = tag .. band .. ":" .. listed
                    local c = peerCells[cell] or { sum = 0, n = 0 }
                    local v = M.peerValue(d.perDay)
                    c.sum, c.n = c.sum + v, c.n + 1
                    peerCells[cell], peerOwn[k] = c, v
                end
            end
        end
    end
    return peerCells, peerOwn
end

-- Units a day of the items similar to a plain item or commodity (Market.peerCell), at their usual
-- prices, and how many there are; nil for gear, without a usual price or with too few of them.
-- `history` defaults to the scope's.
function D.peerRate(key, h, history)
    local tag = type(key) == "string" and key:sub(1, 2)
    if (tag ~= "c:" and tag ~= "i:") or not F.db and not history then
        return nil
    end
    history = history or F.Data.market(F.db, F.Engine.scope()).history
    local band, listed = F.Market.peerCell(h, F.Market.usual(h))
    if not band then
        return nil
    end
    local cells, own = itemPeerCells(history)
    local sum, n = 0, 0
    for b = band - 1, band + 1 do
        for l = listed - 1, listed + 1 do
            local c = cells[tag .. b .. ":" .. l]
            if c then
                sum, n = sum + c.sum, n + c.n
            end
        end
    end
    if own[key] then
        sum, n = sum - own[key], n - 1
    end
    local rate = F.Market.peerRate(sum, n)
    return rate, rate and n or nil
end

-- Est./day of an item at `price` (Market.saleability), the one figure the Deals column, the deal
-- detail, Check Sure and the tooltip show. A plain item or commodity with lots watched leans on
-- similar items (D.peerRate, Market.withPeers) always: their weight fades as its own hours add up.
-- Above its usual price their rate counts less, in proportion, and it never goes past what the
-- item's own sales allow (their upper 80% limit). While the item's own sample is thin
-- (Market.quality not reliable), gear leans on its other endings or on gear of about its price
-- (D.siblingEstimate) instead of on none: one scan pair read 0 a day for gear whose kind sells
-- every day. The more hours its own lots were watched, the less the others count
-- (Market.withPrior). `history` (optional) is the scope's history.
function D.saleability(key, h, price, now, qty, history)
    now = now or clock()
    local sale = F.Market.saleability(h, price, now)
    local own = sale.known and U.finite(sale.perDay) and F.Market.lotDemand(h, price)
    local peer, n
    if own then
        peer, n = D.peerRate(key, h, history)
    end
    if peer then
        -- Never past the upper 80% limit of the item's own sales: a commodity in a busy cell read
        -- 9 a day after 7 hours with none sold.
        local _, high = F.Market.rateRange(own.sold, own.hours)
        peer = math.min(peer * math.min(1, F.Market.usual(h) / price), high or peer)
        sale.perDay = F.Market.withPeers(own.sold, own.hours, peer)
        sale.prior, sale.priorN, sale.priorPeers = peer, n, true
    elseif sale.known and U.finite(sale.perDay) then
        local q = F.Market.quality(h, price, now)
        if not q.reliable then
            local other = D.siblingEstimate(key, qty or 1, now)
            if other and U.finite(other.perDay) and other.perDay > 0 then
                sale.perDay = F.Market.withPrior(sale.perDay, sale.hours, other.perDay)
                sale.prior, sale.priorN, sale.priorPeers = other.perDay, other.n, other.peers
            end
        end
    end
    return sale
end

-- T32: how good the sales sample of an item is at `price` (Market.quality).
-- The usual price of an item (Market.usual of its history) and the history: the one reader of
-- Trade's floors and the pages. `history` defaults to the scope's.
function D.usualOf(key, history)
    history = history or F.Data.market(F.db, F.Engine.scope()).history
    local h = key and history[key]
    return h and F.Market.usual(h) or nil, h
end

-- The price an item sells for now: a fresh check (Check all, Trade.freshCheapest) before the
-- usual price. What Crafting and Disenchant value products and materials at.
function D.priceOf(key, history)
    local usual, h = D.usualOf(key, history)
    local live = key and F.Trade.freshCheapest(key)
    return live or usual, h
end

function D.qualityAt(key, price, now)
    local h = F.Data.market(F.db, F.Engine.scope()).history[key]
    return F.Market.quality(h, price, now or clock())
end

-- A sell price of the player's own, checked ("Check Sure" on Deals -> Resale and Selling -> My
-- items): Sure, the units sold a day and the money at that price. Nothing is stored and the market
-- data stays as it is. `cost` is what the units cost (nil: unknown, no profit), `risk` the
-- deposits expected to be lost, `held` units of it already in the bags (they sell first, as in
-- D.sure). `thin`: the sales seen are too few to judge the price, and the page says so.
function D.checkAt(key, price, qty, cost, risk, held, now)
    if not key or not U.finite(price) or price <= 0 then
        return nil
    end
    now = now or clock()
    qty = math.max(1, math.floor(qty or 1))
    local h = F.Data.market(F.db, F.Engine.scope()).history[key]
    local sure, parts = D.sureAt(key, price, qty + (held or 0), now)
    local sale = D.saleability(key, h, price, now, qty)
    local out = { key = key, price = price, qty = qty, sure = sure, parts = parts, sale = sale }
    out.net = F.Market.net(price, qty)
    if U.finite(cost) then
        out.cost = cost
        out.profit = out.net - cost - (risk or 0)
        out.roi = cost > 0 and out.profit / cost or nil
    end
    out.thin = not U.finite(sure) or not sale.known or (sale.pairs or 0) < 2
    -- T32: the sample behind the figures and their 80% limits.
    out.quality = D.qualityAt(key, price, now)
    if U.finite(sure) then
        local _, low, high = D.sureRange(key, price, qty + (held or 0), now)
        out.sureLow, out.sureHigh = low, high
    end
    return out
end

-- The same check for a resale deal: its units, its cost and the deposits it already counts.
function D.checkDeal(d, price, now)
    if not d or d.mode ~= "flip" then
        return nil
    end
    local qty = d.qty or 1
    local risk = U.finite(d.exit) and math.max(0, F.Market.net(d.exit, qty) - d.cost - d.profit) or 0
    local p = F.Data.char(F.db, F.Engine.owner()).positions[d.key]
    return D.checkAt(d.key, price, qty, d.cost, risk, p and p.qty or 0, now)
end

local function order(a, b)
    if (a.verified ~= nil) ~= (b.verified ~= nil) then
        return a.verified ~= nil
    end
    if a.profit ~= b.profit then
        return a.profit > b.profit
    end
    return a.key < b.key
end

function D.replace(deals, scope)
    -- Keep deals verified a moment ago; the scan may be older than that check. Only within the
    -- same auction house: another house's lots are not on sale here.
    local sameHouse = scope == D.scope
    D.scope = scope
    local keep = {}
    for _, d in ipairs(D.list) do
        if sameHouse and d.verified and clock() - d.verified < D.FRESH then
            keep[d.key] = d
        end
    end
    D.list = {}
    D.listAt, D.quickDone = clock(), nil
    for _, d in ipairs(deals) do
        D.list[#D.list + 1] = keep[d.key] or d
        keep[d.key] = nil
    end
    for _, d in pairs(keep) do
        D.list[#D.list + 1] = d
    end
    table.sort(D.list, order)
    F.Engine.changed()
end

function D.add(deal, scope)
    if scope ~= D.scope then
        return
    end
    for i, d in ipairs(D.list) do
        if d.key == deal.key then
            D.list[i] = deal
            table.sort(D.list, order)
            F.Engine.changed()
            return
        end
    end
    D.list[#D.list + 1] = deal
    table.sort(D.list, order)
    F.Engine.changed()
end

-- A quick scan's find, listed at once (the player saw nothing until the whole house was read and
-- every candidate checked, minutes later): the deal its lowest price makes of one unit, the only
-- unit the browse vouches for. It is marked `quick` (Status: from quick scan) until its exact check
-- replaces or removes it; buying checks it first like any deal of a scan. A deal checked a moment
-- ago is kept.
local function foundDeal(key, price, now)
    local old = D.get(key)
    if old and old.verified and now - old.verified < D.FRESH then
        return nil
    end
    local item = U.parseKey(key)
    if not item then
        return nil
    end
    local history = F.Data.market(F.db, D.scope).history[key]
    local g = {
        key = key,
        kind = item.kind,
        id = item.id,
        rows = { { unit = price, qty = 1 } },
        market = old and old.market or (history and history.scan and history.scan.market),
        link = old and old.link,
    }
    local ok, deal = pcall(D.evaluate, g, F.AH.vendorPrice(item.id), history, now)
    if not ok or not deal then
        return nil
    end
    deal.quick, deal.found = true, now
    if deal.alt then
        deal.alt.quick, deal.alt.found = true, now
    end
    if D.medianOf(deal) then
        deal.median.quick, deal.median.found = true, now
    end
    return deal
end

-- Returns the key listed, or nil. `keys`: one key, or the keys of every ending of one piece of gear
-- the browse priced together. The browse gives one lowest price an item, whatever its ending: listed
-- under each ending, one cheap Giant Club made 13 identical rows (seen in game). One row then, the
-- ending whose deal pays least (the lot may be any of them), and an unchecked find of another
-- ending of the item leaves the list.
function D.addFound(keys, price, now)
    if not D.scope or D.scope ~= F.Engine.scope() then
        return nil
    end
    now = now or clock()
    if type(keys) ~= "table" then
        keys = { keys }
    end
    local best
    for _, key in ipairs(keys) do
        local deal = foundDeal(key, price, now)
        if deal and (not best or (deal.profit or 0) < (best.profit or 0)) then
            best = deal
        end
    end
    if not best then
        return nil
    end
    if #keys > 1 then
        for i = #D.list, 1, -1 do
            local d = D.list[i]
            if d.quick and not d.verified and d.id == best.id and d.key ~= best.key then
                table.remove(D.list, i)
            end
        end
    end
    D.add(best, D.scope)
    return best.key
end

function D.remove(key)
    for i, d in ipairs(D.list) do
        if d.key == key then
            table.remove(D.list, i)
            F.Engine.changed()
            return
        end
    end
end

-- The deal of an item. A lot that pays both ways has one entry (the better route) with the other
-- as d.alt: `mode` asks for a route, else the route of the Deals page shown (D.view, set by the
-- UI), so selecting, checking and buying on the To vendor page act on the vendor deal. A lot
-- without that route returns its deal as it is.
D.view = nil
function D.get(key, mode)
    mode = mode or D.view
    for _, d in ipairs(D.list) do
        if d.key == key then
            return D.route(d, mode) or d
        end
    end
end

function D.visible(filter)
    local out = {}
    for _, d in ipairs(D.list) do
        -- Deals of the last scan stay listed until the next one; buying checks them first. A lot
        -- that pays both ways is listed on the Resale and the To vendor page, each with its route.
        local shown = D.route(d, filter)
        if shown then
            out[#out + 1] = shown
        end
    end
    return out
end

-- Exact search -------------------------------------------------------------------------------------
-- D.search = { key, item, at, pages, source, callbacks }. Foreground work is FIFO;
-- a background retry has its own slot and can never replace a player's request.
D.requests = {}
D.queued = {} -- queued key -> request; batch setup remains linear even for a whole category
D.sent = {} -- successful or attempted new searches during the last rolling minute
D.infoSince = {} -- key -> since when its search waits for the item's auction house data
-- A search waits for an answer. A gear search between two of its steps (waitKey: its next version
-- is not sent yet) has nothing on the way: a purchase may go meanwhile.
function D.searching()
    return D.search ~= nil and not D.search.waitKey
end

-- A recent selection (D.SELECTED_HOLD), or the pointer on Buy: leave the connection for purchasing.
local function selectedHold(ui)
    local selected = D.get(ui.selected)
    if not selected then
        return false
    end
    if ui.buyHoverKey == ui.selected then
        return true
    end
    if not selected.verified then
        return false
    end
    return clock() - math.max(selected.verified, ui.selectedAt or 0) <= D.SELECTED_HOLD
end

-- The player is about to buy: a Buy click found the way busy (holdUntil), or a checked deal was
-- just selected on the Deals page. Every search that is not a click of the player waits then, the
-- searches of Check all and the next step of a gear search too, so the way frees within a second.
-- The search of the selected item itself never waits (`key`): the player is waiting for it, and
-- holding it behind its own selection stopped Check all for good (seen in game).
function D.buyHolding(key)
    if clock() < (D.holdUntil or 0) or F.Trade.run then
        return true
    end
    local ui = F.Engine.screen()
    if not ui.frame or not ui.shown or ui.section ~= "deals" then
        return false
    end
    if key ~= nil and key == ui.selected then
        return false
    end
    return selectedHold(ui)
end

-- The pages where the player posts and cancels: background searches rest there (D.holding), and
-- only their own checks run (D.batchPaused).
D.SELLING = { sell = true, auctions = true, undercuts = true }

-- Check all of another page rests while the player posts or cancels (the Selling pages) or works in
-- the game's own Buy or Sell page: every search of it held the way to the server, and the Post
-- button then found the auction house busy (seen in game with 28 of 159 deals checked). It goes
-- on by itself when the player comes back.
function D.batchPaused()
    local batch = D.batch
    if not batch or not batch.active then
        return false
    end
    if F.AH.nativeShown and F.AH.nativeShown() then
        return true
    end
    local ui = F.Engine.screen()
    if not ui.frame or not ui.shown then
        return false
    end
    -- Only checks of other pages rest there: the selling pages' own checks (Bags, My auctions,
    -- Undercuts) are what the player waits for on them (a check started on Undercuts stood still
    -- for good once the player looked at My auctions, seen in game).
    return D.SELLING[ui.section] and not D.SELLING[batch.scope] or false
end

-- Background work (the sniper, automatic checks) waits while the player is about to buy or post:
-- a freshly checked deal is selected (D.SELECTED_HOLD seconds), or the Selling page is open. A purchase or
-- a post sent while the sniper's messages are in flight is often thrown away by the server, and
-- the throttle stays busy.
function D.holding()
    if F.Engine.interacting() then
        return true
    end
    if clock() < (D.holdUntil or 0) or F.Trade.run then
        return true -- a click found the way busy, or a Buy first run is on
    end
    local ui = F.Engine.screen()
    if not ui.frame or not ui.shown then
        return false
    end
    -- The Undercuts page too: its answers cancel auctions, and a cancel sent while a search of
    -- the sniper waited found the way busy (Answer next took three clicks in game).
    if D.SELLING[ui.section] then
        return true
    end
    return ui.section == "deals" and selectedHold(ui)
end

-- What may be spent now: the money in the bags, and no more than what is left of this visit's
-- spending limit (Settings) when one is set. The Buy button, Buy next and Buy first shrink a
-- vendor deal to the same amount; T.overLimit stays the last guard of a purchase.
local function spendable()
    local budget = F.Engine.wallet()
    local limit = tonumber(settings().spendLimit) or 0
    if limit > 0 then
        budget = math.min(budget, limit * 10000 - (F.Engine.spent or 0))
    end
    return budget
end

-- A vendor deal is listed as the whole offer (d.offer: every unit on the shelf below the vendor
-- price, its cost and its lots); what can be bought now is the part the money covers, cheapest lots
-- first. The merchant pays for each unit at once, so there is nothing to wait for; an item row is a
-- bucket of identical auctions bought one by one and a part of it fits too. The buyable part lives
-- in d.qty, d.cost and d.lots (the money a click spends); d.offer.qty and d.offer.cost are what the
-- row shows, so an offer too dear for the purse is still read in full. d.short says none of it fits.
-- Every split starts from the offer's lots, so the deal grows back when the money does.
function D.fitWallet(d)
    if not d or d.mode ~= "vendor" then
        return d
    end
    local offer = d.offer
    if type(offer) ~= "table" then
        -- A deal found before the offer was kept (an entry of an older list): the deal is the offer.
        offer = { qty = d.qty or 0, cost = d.cost or 0, profit = d.profit, roi = d.roi, lots = d.lots }
        d.offer = offer
    end
    local lots = offer.lots or d.lots
    if type(lots) ~= "table" or not U.finite(d.exit) then
        return d
    end
    local budget, budgetSpent = spendable(), d.fitBudget
    if budgetSpent == budget then
        return d
    end
    -- Money left for this deal: everything when the offer costs no more than the purse
    -- (the offer itself stays the whole one on the shelf). The spending limit is in `spendable`.
    local user = budget >= (offer.cost or 0) and math.huge or budget
    local qty, cost, used = 0, 0, {}
    for _, l in ipairs(lots) do
        local unit = l.unit or 0
        local take = unit > 0 and math.min(l.qty or 1, math.floor((user - cost) / unit)) or 0
        if take < 1 then
            break
        end
        qty, cost = qty + take, cost + take * unit
        used[#used + 1] = { unit = unit, qty = take, auctionID = l.auctionID }
    end
    d.fitBudget = budget
    d.qty, d.cost, d.lots = qty, cost, used
    -- maxUnit is the priciest unit of the affordable part: a deal that pays for the lots it buys.
    d.maxUnit = used[#used] and used[#used].unit or nil
    d.profit = qty * d.exit - cost
    d.roi = cost > 0 and d.profit / cost or 0
    d.short = qty < 1
    return d
end

-- The best deal the player can buy now (Buy next key): checked deals first, then by profit.
function D.best()
    local wallet = F.Engine.wallet()
    for _, d in ipairs(D.list) do
        D.fitWallet(d)
        -- A vendor offer the purse covers none of sits on the page but buys nothing: skip it.
        if d.cost <= wallet and not d.short and not F.Trade.overLimit(d.cost) then
            return d
        end
    end
end

local function precise()
    return GetTime and GetTime() or clock()
end

function D.pending(key)
    if D.search and (key and D.search.key == key or not key and D.search.source == "manual") then
        return true
    end
    if key and D.queued[key] or not key and #D.requests > 0 then
        return true
    end
    -- Called every frame: no table is made for a missing queue (outside the auction house).
    local checks = F.Trade.checkQueue
    if checks then
        for _, queued in ipairs(checks) do
            if not key or queued == key then
                return true
            end
        end
    end
    -- Keep a dropped/timed-out background check visible as pending until its bounded retry
    -- runs; callers must distinguish it from a key that has never been checked.
    if D.backgroundRetry and (not key or D.backgroundRetry.key == key) then
        return true
    end
    return false
end

local function addCallback(r, callback, identity)
    if not callback then
        return
    end
    identity = identity or callback
    for _, cb in ipairs(r.callbacks) do
        if cb.identity == identity then
            return
        end
    end
    r.callbacks[#r.callbacks + 1] = { run = callback, identity = identity }
end

-- Pacing and priority are independent: a click can promote an already queued fast batch.
local function priority(r)
    return r.priority or (r.source ~= "manual" and 2 or r.fast and 1 or 0)
end

-- The player's own click (r.click: asked or promoted while Engine.interacting, half a second after a
-- button, a row or a key binding). Only such a request goes while a full scan waits for its answer:
-- the preparation on Buy hover and the frame step of Buy first ask with the same priority
-- without a click, and their searches kept the scan's answer from coming.
local function isClick(r)
    return r.click and priority(r) == 0 or false
end

function D.foreground()
    if D.search and priority(D.search) == 0 then
        return D.search, true
    end
    local first = D.requests[1]
    if first and priority(first) == 0 then
        return first, false
    end
end

local function queueRequest(r, ahead)
    local pos = #D.requests + 1
    local last = D.requests[#D.requests]
    if last and (priority(last) > priority(r) or ahead and priority(last) == priority(r)) then
        for i, queued in ipairs(D.requests) do
            if priority(queued) > priority(r) or ahead and priority(queued) == priority(r) then
                pos = i
                break
            end
        end
    end
    table.insert(D.requests, pos, r)
    D.queued[r.key] = r
end

-- Only unsent gear steps may be parked. Removing an on-the-wire request is not cancellation.
local function parkSearch()
    local s = D.search
    if s and s.waitKey then
        D.search = nil
        queueRequest(s)
        return true
    end
    return false
end

local function newRequest(key, callback, source, identity, fast)
    local item = U.parseKey(key)
    if not item then
        return nil
    end
    local now = precise()
    local r = { key = key, item = item, source = source or "manual", callbacks = {}, readyAt = now, fast = fast }
    r.createdAt = now
    r.priority = priority(r)
    r.dealCheck = D.dealCheckNext
    addCallback(r, callback, identity)
    return r
end

-- Waits that are only the normal pace of the queue: counted in the statistics, not traced each time.
local PACING = { another_search = true, gap = true }

-- Why request `r` is held back now (nil: it goes). The time of each reason adds up on the request
-- (r.held, seconds) and in the statistics (wait.<reason>.s); a change of reason is traced.
local function noteHeld(r, why, now)
    if r.heldWhy == why then
        return
    end
    if r.heldWhy and r.heldSince then
        local spent = now - r.heldSince
        r.held = r.held or {}
        r.held[r.heldWhy] = (r.held[r.heldWhy] or 0) + spent
        F.Log.stat("wait." .. r.heldWhy .. ".s", spent)
    end
    r.heldWhy, r.heldSince = why, why and now or nil
    if why and not PACING[why] then
        F.Log.trace("search.held", "%s %s", r.key, why)
    end
end

-- The reasons a request waited, longest first: "throttle 3.2s, full_scan 1.0s".
local function heldText(r)
    local list = {}
    for why, spent in pairs(r.held or {}) do
        list[#list + 1] = { why = why, spent = spent }
    end
    table.sort(list, function(a, b)
        return a.spent > b.spent
    end)
    local out = {}
    for i, h in ipairs(list) do
        if i > 4 then
            break
        end
        out[#out + 1] = string.format("%s %.1fs", h.why, h.spent)
    end
    return #out > 0 and table.concat(out, ", ") or "-"
end

-- The end of a request in the trace and the statistics: how long from asked to answered, from the
-- first message sent, what it waited for, its phase and versions.
local function traceEnd(r, rows, complete)
    local now = precise()
    noteHeld(r, nil, now)
    local total = now - (r.createdAt or now)
    local answer = r.sentAt and now - r.sentAt or 0
    local outcome = rows == nil and "failed" or complete and "complete" or "partial"
    local kind = priority(r) == 0 and "click" or priority(r) == 1 and "batch" or "background"
    F.Log.stat("search." .. kind .. ".s", total)
    F.Log.stat("search.answer.s", answer)
    local why = string.format(
        "%s, %s, %.1fs after sending, phase %s, versions %d, sent %d, waited: %s",
        outcome,
        kind,
        answer,
        tostring(r.phase or "plain"),
        r.keys and #r.keys or 0,
        r.attempts or 0,
        heldText(r)
    )
    F.Log.trace("search.end", "%s %.2fs %s, rows %d", r.key, total, why, rows and #rows or 0)
    if total >= D.SLOW_SEARCH then
        F.Log.slow(total * 1000, r.key, why)
    end
end

local function completeRequest(r, rows, complete)
    if not r or r.completed then
        return
    end
    r.completed = true
    traceEnd(r, rows, complete)
    -- Gear: the item-key versions searched, for callbacks that read each of them (bids). Kept
    -- apart from the arguments: callbacks such as D.verifyCallback take a 4th argument of their own.
    -- The keys the answer was read under: the exact key of a plain search answered under it, the
    -- versions of the search that answered a request from its sweep (r.readKeys).
    D.versions = r.readKeys or r.keys
    for _, cb in ipairs(r.callbacks or {}) do
        local ok, err = pcall(cb.run, r.key, rows, complete)
        if not ok then
            F.Engine.report(err)
        end
    end
end

local function batchHeld(r)
    local batch = D.batch
    local owned = F.Trade.checkingOwned
    return priority(r) > 0
        and not (owned and owned[r.key])
        and batch
        and batch.keySet
        and batch.keySet[r.key]
        and D.batchPaused()
end

-- A batch from another page stays queued while Selling is open. Its paused head
-- must not hold this page's own checks behind it; retain FIFO among runnable work.
-- `clicks`: a full scan waits for its answer, only the player's clicks may go.
local function nextRequest(clicks)
    for i, r in ipairs(D.requests) do
        if not batchHeld(r) and (not clicks or isClick(r)) then
            return r, i
        end
    end
end

-- A browse of ours that ended without its answer (dropped, timed out, stopped) may still be
-- answered, and that answer would be read as the answer to the next gear search. It is noted with
-- its item (F.AH.droppedBrowse): a search of the same item sends the same browse, so the late answer
-- is as good as its own (a dropped browse's retry was never complete before).
local function browseLeft(s)
    local left, now = F.AH.droppedBrowse, clock()
    if left and left.id ~= s.item.id and now - left.at < F.AH.FOREIGN_WAIT then
        -- Answers of two items may be on the way: the older one is foreign to both.
        F.AH.foreignAt = math.max(F.AH.foreignAt or 0, left.at)
    end
    F.AH.droppedBrowse = { id = s.item.id, at = now }
end

-- A browse sent now may get somebody else's answer: a browse of another addon, or of ours for
-- another item, a moment ago.
local function browseForeign(id)
    local left = F.AH.droppedBrowse
    if left and left.id ~= id and clock() - left.at < F.AH.FOREIGN_WAIT then
        return true
    end
    return F.AH.foreignRecent()
end

local nextGearKey -- below: the next version of a gear search

-- Why request `r` cannot be sent now, or nil. The order is the order the gates are asked in: the
-- throttle last (AH.ready lets one message through a stuck throttle).
local function refusal(r, now)
    if D.clearing then
        return "clearing"
    elseif D.search then
        return "another_search"
    -- The quick check gives way to the player's searches (it is asked again later).
    elseif D.pre and not (D.pre.quick and priority(r) < 2) then
        return "pre_query"
    elseif priority(r) > 0 and D.buyHolding(r.key) then
        return "buy_hold"
    elseif not F.AH.isOpen() then
        return "ah_closed"
    elseif F.Trade.busy() then
        return "trade_busy"
    elseif F.Trade.postingNow() then
        return "posting"
    elseif F.Sniper.inFlight() then
        return "sniper"
    -- A full scan waits for its answer: only the player's own clicks go meanwhile.
    elseif F.Scan.blocking() and not isClick(r) then
        return "full_scan"
    elseif batchHeld(r) then
        return "batch_paused"
    -- The game's own Buy or Sell page is shown: what it shows is not replaced.
    elseif priority(r) > 0 and F.AH.nativeShown and F.AH.nativeShown() then
        return "native_page"
    elseif not F.AH.ready() then
        return "throttle"
    -- The server's throttle paces the searches (as in Auctionator). D.GAP only keeps answers
    -- that come inside the call from sending every queued search in one frame; background
    -- work (the sniper, automatic checks) keeps one search per second.
    elseif now - (D.lastRequest or -10) < ((priority(r) >= 2 and not r.fast) and 1 or D.GAP) then
        return "gap"
    elseif #D.sent >= D.PER_MINUTE then
        return "per_minute"
    end
end

local function startRequest(r)
    local now = precise()
    while D.sent[1] and now - D.sent[1] >= 60 do
        table.remove(D.sent, 1)
    end
    local why = refusal(r, now)
    if why then
        noteHeld(r, why, now)
        return false
    end
    if D.pre and D.pre.quick then
        D.pre, D.quickDone = nil, nil
    end
    -- An item the client has no auction house data for yet: asked for, and the search waits up to
    -- two seconds for it (the server often ignores the search of such an item).
    -- Ordinary items (including recipes) can carry nonzero key levels too. Reuse the
    -- server's owned/browse key instead of first waiting for an ignored zero-level query.
    local cached, every
    if r.item.kind ~= "commodity" and F.AH.cachedKeys then
        cached, every = F.AH.cachedKeys(r.item)
    end
    local plain = not (cached or r.item.kind == "gear" or D.byName[r.item.id])
    if (cached or plain) and F.AH.keyInfoReady and not F.AH.keyInfoReady(r.item, cached and cached[1]) then
        -- Kept per item, not per request: an automatic check or a sniper candidate is a new request
        -- at every try, and its wait never ran out (nothing behind it was ever checked).
        local since = D.infoSince[r.key] or now
        D.infoSince[r.key] = since
        if now - since < 2 then
            noteHeld(r, "item_info", now)
            return false
        end
    end
    D.infoSince[r.key] = nil
    noteHeld(r, nil, now)
    if r.waitKey then
        D.search, r.waitKey, r.at, r.budgetAt = r, nil, clock(), now
        if not pcall(F.AH.searchKey, r.keys[r.keyIndex]) then
            D.search = nil
            completeRequest(r, nil, false)
        end
        F.Engine.changed()
        return true
    end
    -- Cached answers and dropped-message events may fire inside the API call.
    r.at, r.pages, r.budgetAt, r.readKeys = clock(), 0, now, nil
    D.search, D.lastRequest = r, now
    D.sent[#D.sent + 1] = now
    r.attempts = (r.attempts or 0) + 1
    r.sentAt = r.sentAt or now
    F.Log.trace(
        "search.start",
        "%s source %s, priority %d, try %d, queued %.2fs",
        r.key,
        tostring(r.source),
        priority(r),
        r.attempts,
        now - (r.createdAt or now)
    )
    local ok
    -- Gear, and items whose plain search got no answer, are searched by name: a browse lists their
    -- exact item keys, then each key is searched.
    local byName = (r.item.kind == "gear" or D.byName[r.item.id]) and F.AH.canSearchGear()
    if cached then
        -- Its versions are known from an earlier browse: they are searched straight away.
        r.phase, r.keys, r.keyIndex, r.found, r.foundIDs, r.allComplete, r.cached =
            "keys", cached, 0, {}, {}, true, true
        r.every, r.shared = every and r.item.kind == "gear", {}
        -- Many versions: their prices first, in one query, and only the versions listed are read
        -- (a deal check: only those within its reach). A ring of 35 versions took 25 s of My
        -- auctions' Check prices, one version after another, all but one of them empty.
        if #cached >= D.VERSION_QUERY and not (r.dealCheck and not D.get(r.key)) then
            r.phase, r.foreign = "prices", browseForeign(r.item.id)
            F.Sniper.yield()
            if pcall(F.AH.searchVersions, cached) then
                F.Engine.changed()
                return true
            end
            r.phase = "keys"
        end
        nextGearKey(r)
        F.Engine.changed()
        return true
    end
    if byName then
        -- Gear: a browse by name first (its item-key versions), then each version (see AH.lua).
        r.phase, r.keys, r.keyIndex, r.found, r.foundIDs, r.allComplete = "browse", nil, 0, {}, {}, true
        -- A browse somebody else sent just before may answer in place of this one.
        r.foreign = browseForeign(r.item.id)
        F.Sniper.yield()
        ok = pcall(F.AH.gearBrowse, r.item)
    else
        r.phase = nil
        ok = pcall(F.AH.search, r.item)
    end
    if not ok and D.search == r then
        D.search = nil
        D.sent[#D.sent] = nil -- the API refused it: nothing was sent
        if r.fast or (r.attempts or 0) >= 3 then
            completeRequest(r, nil, false)
            F.Engine.changed()
            return true
        end
        return false
    end
    F.Engine.changed()
    return true
end

-- Immediate API, retained for background work and callers that need a started/not-started answer.
function D.request(key, callback, source, fast)
    if D.pending() then
        return false
    end
    local r = newRequest(key, callback, source, nil, fast)
    return r and startRequest(r) or false
end

-- Manual requests are accepted even while throttled or another search is in flight. A repeated
-- key shares that query; each distinct callback is retained and completed once.
-- `ahead`: before the other requests of its priority (a batch's second try of an item).
function D.enqueue(key, callback, identity, fast, ahead)
    if D.clearing or not F.AH.isOpen() then
        return false
    end
    local r
    if D.search and D.search.key == key then
        r = D.search
    else
        r = D.queued[key]
    end
    local background = D.backgroundRetry
    if background and background.key == key then
        D.backgroundRetry = nil
        if r then
            for _, cb in ipairs(background.callbacks) do
                addCallback(r, cb.run, cb.identity)
            end
        else
            r = background
        end
    end
    if r then
        r.priority = math.min(priority(r), fast and 1 or 0)
        r.source = "manual"
        r.fast = r.fast or fast
        if not D.dealCheckNext then
            r.dealCheck = nil -- another caller reads its rows too: every version is searched
        end
        -- Only a single check asked by a click marks it (not Check all's, which a click starts too).
        r.click = r.click or not fast and F.Engine.interacting()
        addCallback(r, callback, identity)
        if D.search == r then
            F.Engine.changed()
            return true
        end
        if D.queued[key] then
            for i, queued in ipairs(D.requests) do
                if queued == r then
                    table.remove(D.requests, i)
                    break
                end
            end
        end
    else
        r = newRequest(key, callback, "manual", identity, fast)
        if not r then
            return false
        end
        r.click = not fast and F.Engine.interacting()
    end
    if D.search and priority(D.search) > priority(r) then
        parkSearch()
    end
    queueRequest(r, ahead)
    if D.requests[1] == r and precise() >= r.readyAt then
        table.remove(D.requests, 1)
        D.queued[key] = nil
        if not startRequest(r) then
            table.insert(D.requests, 1, r)
            D.queued[key] = r
        end
    end
    F.Engine.changed()
    return true
end

local function finishSearch(rows, complete)
    local s = D.search
    D.search = nil
    completeRequest(s, rows, complete)
    F.Engine.changed()
end

-- WoW Forever never answers a search of an item no other player sells. A search with no answer of
-- an item the player has listed, that the last full scan (up to D.ALONE_AGE old) saw no other
-- seller of and no check since saw one of, is that case: answered as "nobody else sells it", its
-- item-key versions kept. Before, each such check waited for nothing, forgot the versions (the next
-- check browsed again) and was sent a second time. Without a lot of the player's own the silence
-- proves nothing (a slow answer, a lot listed after the scan): deals were removed for it.
D.ALONE_AGE = 2 * 3600
local function onlyYours(key)
    local T = F.Trade
    if not T.alone(key, D.ALONE_AGE) then
        return false
    end
    local listed = false
    for _, a in ipairs(T.owned or {}) do
        if a.key == key and not a.sold then
            listed = true
            break
        end
    end
    -- Another seller seen after the scan: a deal checked since, or a price check since with lots.
    local last = F.Scan.last
    local since = last and last.at or 0
    local d = D.get(key)
    local check = T.prices and T.prices[key]
    return listed
        and not (d and (d.verified or 0) >= since)
        and not (check and (check.at or 0) >= since and type(check.rows) == "table" and #check.rows > 0)
end
D.onlyYours = onlyYours

-- T10: an item the player has listed whose search went unanswered, and that the last full scan (of
-- any age) saw no other seller of. On WoW Forever that silence is the usual answer for "nobody else
-- sells it"; sending it once more in the same batch only doubled the wait (30 items: 6 minutes).
-- Such a key is reported once as "no answer" instead of retried. It is never taken as "cheapest".
local function silentOwn(key)
    if not F.Trade.alone(key, math.huge) then
        return false
    end
    for _, a in ipairs(F.Trade.owned or {}) do
        if a.key == key and not a.sold then
            return true
        end
    end
    return false
end

local function cheaper(a, b)
    return a.unit < b.unit
end

local function timeoutSearch(s)
    F.Log.trace(
        "search.timeout",
        "%s phase %s, version %d of %d, waited %.1fs",
        s.key,
        tostring(s.phase or "plain"),
        s.keyIndex or 0,
        s.keys and #s.keys or 0,
        s.waited or 0
    )
    if s.phase == "browse" or s.phase == "prices" then
        browseLeft(s) -- its late browse reply must not certify the next item
    end
    -- Gear: the lots of the versions answered so far are kept. They prove another seller, but the
    -- versions without an answer may hold cheaper lots: not a complete list.
    local found = s.phase == "keys" and #s.found > 0 and s.found
    if not found and onlyYours(s.key) then
        finishSearch({}, true)
        return
    end
    if s.cached then
        F.AH.forgetKeys(s.item.id)
    end
    if found then
        table.sort(found, cheaper)
        finishSearch(found, false)
        return
    end
    -- The server never answered (not dropped, not an error): a bag check takes it as nobody
    -- selling the item and does not send it again (startBatch).
    D.silentKey = s.key
    finishSearch(nil, false)
    D.silentKey = nil
end

-- The next item-key version of a gear search, or the end of it with every version's rows.
function nextGearKey(s)
    s.keyIndex, s.keyPages, s.keyRows = s.keyIndex + 1, 0, nil
    local key = s.keys[s.keyIndex]
    if not key then
        if #s.found == 0 and s.pruned and not s.ownSkipped then
            -- No version holds a lot within the deal's reach: the deal's lot is gone.
            finishSearch({}, s.allComplete)
            return
        end
        if #s.found == 0 and (s.cached or s.ownSkipped) then
            -- None of the remembered versions is listed now: the ending may have moved to a new
            -- version. Unknown for now; the next check browses again. A version passed over for the
            -- player's own lot proves nothing without another seller's lot found elsewhere.
            if s.cached then
                F.AH.forgetKeys(s.item.id)
            end
            finishSearch(nil, false)
            return
        end
        table.sort(s.found, function(a, b)
            return a.unit < b.unit
        end)
        local shared = s.every and s.allComplete and s.shared
        finishSearch(s.found, s.allComplete)
        if shared then
            D.shareSweep(s.item.id, s.key, shared, s.keys)
        end
        return
    end
    -- Yield between versions: the next frame can serve a new click or purchase first.
    s.phase, s.at, s.waitKey = "keys", clock(), true
    if priority(s) == 0 and (isClick(s) or not F.Scan.blocking()) and not F.Trade.busy() and F.AH.ready() then
        s.waitKey, s.budgetAt = nil, precise()
        if not pcall(F.AH.searchKey, key) then
            finishSearch(nil, false)
        end
    end
end

-- One search went through every version of a gear item, each read to its end: the queued checks
-- of the item's other endings are answered from those lots at once, without a search of their
-- own (Check all searched the same versions again for every ending of one item). An ending with
-- no lot there waits for its own search: the versions remembered may be out of date. `keys`: the
-- versions searched, where the answered requests' callbacks read them (D.versions, bids).
function D.shareSweep(id, done, shared, keys)
    local answered = {}
    for i = #D.requests, 1, -1 do
        local r = D.requests[i]
        if r.item.kind == "gear" and r.item.id == id and r.key ~= done and not r.waitKey then
            local rows = shared[r.item.name]
            if rows and #rows > 0 then
                table.remove(D.requests, i)
                D.queued[r.key] = nil
                local copy = {}
                for k, row in ipairs(rows) do
                    copy[k] = row
                end
                table.sort(copy, function(a, b)
                    return a.unit < b.unit
                end)
                answered[#answered + 1] = { r = r, rows = copy }
            end
        end
    end
    for _, a in ipairs(answered) do
        a.r.readKeys = keys
        completeRequest(a.r, a.rows, true)
    end
    if answered[1] then
        F.Engine.changed()
    end
    return #answered
end

-- Browse results while a gear search waits for its versions. Returns true when they were its.
-- A gear search keeps only the versions listed in the browse answer (WoW Forever never answers
-- the search of a version nobody sells); a deal check only those that may hold a lot the deal is
-- decided by (D.VERSION_REACH), from the lowest price of each version. Nothing kept: nobody sells
-- the item now (a deal check: the deal's lot is gone). No price read (a foreign or partial
-- answer): all stay.
local function keepVersions(s)
    if s.item.kind == "commodity" or s.foreign or not F.AH.browseFull() then
        return
    end
    local limit = math.huge
    if s.dealCheck then
        local d = D.get(s.key)
        if not d or (d.exit or 0) <= 0 then
            return
        end
        limit = d.exit * D.VERSION_REACH
    end
    local prices = F.AH.versionPrices(s.item.id)
    if next(prices) == nil then
        return
    end
    local kept = {}
    for _, k in ipairs(s.keys) do
        local p = prices[(k.itemLevel or 0) .. ":" .. (k.itemSuffix or 0)]
        if p and p <= limit then
            kept[#kept + 1] = k
        end
    end
    if #kept < #s.keys then
        F.Log.trace("search.versions", "%s %d of %d versions at or under %s", s.key, #kept, #s.keys, tostring(limit))
        s.keys, s.pruned, s.every = kept, true, false
    end
end

function D.onBrowse()
    local s = D.search
    if s and s.phase == "prices" then
        -- The answer to a deal check's query of its versions' prices: only the versions kept.
        s.phase = "keys"
        keepVersions(s)
        nextGearKey(s)
        return true
    end
    if not s or s.phase ~= "browse" then
        return false
    end
    local keys, every = F.AH.gearKeys(s.item.id, s.item.name)
    if #keys == 0 and not F.AH.browseFull() and s.pages < 3 and not F.Scan.blocking() then
        s.pages, s.at = s.pages + 1, clock()
        pcall(F.AH.browseMore)
        return true
    end
    if #keys == 0 then
        -- A complete browse without the item: nobody sells it. Unknown after three pages, and
        -- unknown when somebody else sent a browse meanwhile (the answer may be theirs).
        if F.AH.browseFull() and not s.foreign then
            finishSearch({}, true)
        else
            finishSearch(nil, false)
        end
        return true
    end
    s.keys, s.keyIndex = keys, 0
    s.every, s.shared = every and F.AH.browseFull() and not s.foreign, {}
    if s.foreign then
        -- The versions may come from somebody else's browse: some may be missing, so the rows
        -- found cannot prove there is nothing cheaper.
        s.allComplete = false
    end
    keepVersions(s)
    nextGearKey(s)
    return true
end

-- Somebody else sent a browse query (AH.hookBrowse): the answer a gear search waits for may be
-- theirs, so it can no longer prove that nobody sells the item.
function D.onForeignBrowse()
    local s = D.search
    if s and (s.phase == "browse" or s.phase == "prices") then
        s.foreign = true
    end
    if D.pre then
        D.pre.foreign = true
    end
end

-- The answer of Check all's first query (D.PRE_IDS), page by page. Returns true when it was its.
function D.onPreBrowse(rows, whole)
    local pre = D.pre
    if not pre or pre.full then
        return false
    end
    if whole or not rows then
        pre.rows = rows or F.AH.browseResults()
    else
        for _, r in ipairs(rows) do
            pre.rows[#pre.rows + 1] = r
        end
    end
    pre.answered = true
    if F.AH.browseFull() then
        pre.full = true
    elseif pre.pages < D.PRE_PAGES then
        pre.pages = pre.pages + 1
        pcall(F.AH.browseMore)
    end
    return true
end

-- A query of Check all is on the way: exact searches and the sniper wait for it (a few seconds).
function D.preFlight()
    return D.pre ~= nil
end

function D.onBrowseFailure()
    local s = D.search
    if s and s.phase == "prices" then
        s.phase = "keys"
        nextGearKey(s) -- no prices: every version is searched
        return true
    end
    if not s or s.phase ~= "browse" then
        return false
    end
    finishSearch(nil, false)
    return true
end

local function sameKey(a, b)
    return type(a) == "table"
        and type(b) == "table"
        and a.itemID == b.itemID
        and (a.itemSuffix or 0) == (b.itemSuffix or 0)
        and (a.itemLevel or 0) == (b.itemLevel or 0)
end

-- An item-key version holds an auction of the player's own: WoW Forever never answers a search
-- that only the player's own lots match, so its silence is explained.
local function ownVersion(searchKey)
    for _, a in ipairs(F.Trade.owned or {}) do
        if not a.sold and sameKey(a.itemKey, searchKey) then
            return true
        end
    end
    return false
end

-- Search results arrived (commodity: itemID; item or gear: item key table).
function D.onResults(itemID, searchKey)
    if not F.AH.isOpen() then
        return
    end
    local s = D.search
    if s and s.phase == "keys" and s.item.id == itemID and sameKey(searchKey, s.keys[s.keyIndex]) then
        local ok, rows, complete, count = pcall(F.AH.rows, s.item, searchKey)
        -- Pages are counted in results (AH.rows), not in the rows kept: a page of only other
        -- endings' or the player's own lots is the page asked for all the same.
        count = ok and (count or #rows) or 0
        if ok and not complete and s.keyPages > 0 and count <= (s.keyRows or 0) then
            return -- the same rows again: wait for the page asked for (or the timeout)
        end
        s.keyRows = count
        -- A version with more listings than one page: up to 3 more pages, unless the cheapest
        -- page already reaches past the deal's price.
        local d = D.get(s.key)
        local last = ok and rows[#rows]
        local enough = complete or (d and last and last.unit > (d.exit or 0) * 1.2)
        if ok and not enough and s.keyPages < 3 and F.AH.ready() then
            s.keyPages, s.at = s.keyPages + 1, clock()
            if pcall(F.AH.moreKey, searchKey) then
                return
            end
        end
        local wholeVersion = ok and complete
        complete = complete or enough
        -- Every ending's lots of this version: the version learns its ending's name (the next check
        -- searches only its own ending's versions), and other deals of the item can be answered
        -- from this sweep (D.shareSweep). A version not read to its end answers no other deal.
        local okNamed, named, all, mixed = pcall(F.AH.versionRows, searchKey)
        if s.shared and s.every then
            if not okNamed or not wholeVersion or mixed then
                s.every = false
            elseif named then
                local list = s.shared[named] or {}
                for _, r in ipairs(all) do
                    r.searchKey = searchKey
                    list[#list + 1] = r
                end
                s.shared[named] = list
            end
        end
        if ok then
            for _, r in ipairs(rows) do
                if not r.auctionID or not s.foundIDs[r.auctionID] then
                    if r.auctionID then
                        s.foundIDs[r.auctionID] = true
                    end
                    r.searchKey = searchKey
                    s.found[#s.found + 1] = r
                end
            end
            s.allComplete = s.allComplete and complete
        else
            s.allComplete = false
        end
        nextGearKey(s)
        return
    end
    if not s or s.item.id ~= itemID or s.phase then
        D.learn(itemID, searchKey)
        return
    end
    -- The answer comes under the item's exact key (it may carry an item level): read it there, not
    -- under the plain key of the request, which would find no rows.
    local exact = type(searchKey) == "table" and s.item.kind ~= "commodity" and searchKey or nil
    local ok, rows, complete, count = pcall(F.AH.rows, s.item, exact)
    if not ok then
        finishSearch(nil, false)
        return
    end
    -- Callbacks that read the answer themselves (bids) read it there too (D.versions).
    s.readKeys = exact and { exact } or nil
    -- Counted in results, as above: a page of only the player's own lots or of bids is a page too.
    count = count or #rows
    if not complete and s.pages > 0 and count <= (s.rows or 0) then
        return -- the same rows again: wait for the page asked for (or the timeout)
    end
    s.rows = count
    -- Enough when complete, or when the cheapest page already reaches past every deal price.
    local d = D.get(s.key)
    local last = rows[#rows]
    local enough = complete or (d and last and last.unit > (d.exit or 0) * 1.2)
    if not enough and s.pages < 3 and F.AH.ready() then
        s.pages, s.at = s.pages + 1, clock()
        if exact then
            pcall(F.AH.moreKey, exact)
        else
            pcall(F.AH.more, s.item)
        end
        return
    end
    finishSearch(rows, complete or enough)
end

-- The player searched an item in the game's own Buy tab: its listings are a fresh check of the item,
-- so a deal found in them can be bought at once, and a listed deal that is gone disappears.
function D.learn(itemID, searchKey)
    if not F.db or not F.db.settings.learnBrowsing or not D.scope or type(itemID) ~= "number" or not F.AH.isOpen() then
        return
    end
    local kind = F.AH.kindOf(itemID)
    if not kind then
        return
    end
    local keys = {}
    if kind == "gear" then
        -- Every search event of the game's Buy tab comes here: the item's own keys ("g:<id>:<name>",
        -- U.key) are picked by their start, not by parsing every key of the history.
        local prefix = "g:" .. itemID .. ":"
        for key in pairs(F.Data.market(F.db, D.scope).history) do
            if string.find(key, prefix, 1, true) == 1 then
                keys[#keys + 1] = key
            end
        end
    else
        keys[1] = U.key(kind, itemID)
    end
    for _, key in ipairs(keys) do
        local ok, rows, complete = pcall(F.AH.rows, U.parseKey(key), searchKey)
        if ok and rows and #rows > 0 then
            -- One gear ending is spread over several item-key versions: a search of one version
            -- is never a complete check of the ending (prices are still learned below).
            D.verifyCallback(key, rows, kind ~= "gear" and (complete or #rows >= 40))
        end
    end
end

function D.onDropped()
    local s = D.search
    if s then
        D.search = nil
        if s.phase == "browse" or s.phase == "prices" then
            -- Its browse may still be answered: the next gear search of another item must not take
            -- that answer for its own; its own retry may.
            browseLeft(s)
        end
        s.readyAt = precise() + 2
        if (s.attempts or 0) >= 3 then
            completeRequest(s, nil, false)
        elseif s.source == "manual" then
            queueRequest(s, true)
        elseif s.source ~= "sniper" or settings().sniper then
            D.backgroundRetry = s
        else
            completeRequest(s, nil, false)
        end
        F.Engine.changed()
    end
end

function D.setSniper(enabled)
    settings().sniper = enabled and true or false
    if not enabled and not F.Sniper.quick then
        F.Sniper.reset() -- a quick scan under way goes on: it ends on its own (Sniper.endQuick)
    end
    local r = D.backgroundRetry
    if not enabled and r and r.source == "sniper" then
        D.backgroundRetry = nil
        completeRequest(r, nil, false)
    end
    F.Engine.changed()
end

-- Work the Stop button ends: a check of a whole page, queued searches, the checks of own
-- auctions, a sale to a merchant, posting queues, a full scan waiting for its answer.
function D.busy()
    local batch = D.batch
    return (batch and batch.active)
        or #D.requests > 1
        or (F.Trade.checkQueue and #F.Trade.checkQueue > 0)
        or (F.Trade.sellingToVendor and F.Trade.sellingToVendor())
        or (F.Scan.job ~= nil)
        or false
end

-- Whether the Stop button has anything of its own to end: checks, a purchase, a merchant sale. A
-- full scan is left out: it runs for minutes on its own, and Check all during it means "check the
-- page" (the checks wait for the scan) rather than "throw the scan away". F.Deals.busy() still
-- counts the scan, so nothing else starts during one.
function D.stoppingWork()
    local batch = D.batch
    return (batch and batch.active)
        or #D.requests > 0
        or (F.Trade.checkQueue and #F.Trade.checkQueue > 0)
        or (F.Trade.sellingToVendor and F.Trade.sellingToVendor())
        or false
end

-- Stops all of it at once (the Stop button): queued and running searches are dropped (an answer
-- still on its way is ignored), the full scan is stopped, the sniper's round ends, a merchant sale
-- stops after what was sent, a Buy first run ends. Settings stay as they are.
function D.stopAll()
    D.clear()
    D.holdUntil = nil
    if F.Trade.checkQueue then
        F.Trade.checkQueue = {}
    end
    -- The own-auction checks still to send were only in that queue (the sent ones were answered by
    -- D.clear): My auctions must not wait for them as "checking" until the house is closed.
    F.Trade.checkingOwned = nil
    if F.Trade.stopVendor then
        F.Trade.stopVendor()
    end
    -- Its frame step would send the check of its next deal at once.
    if F.Trade.runStop then
        F.Trade.runStop()
    end
    if F.Scan.job then
        F.Scan.stop()
    end
    if F.Sniper.reset then
        F.Sniper.reset()
    end
    F.Engine.notify("stopped")
    F.Engine.changed()
end

-- Closing the house cancels queued work too, so reopening cannot replay old selections.
function D.clear()
    D.clearing = true
    local active, requests, background = D.search, D.requests, D.backgroundRetry
    if active and active.phase == "browse" then
        browseLeft(active) -- its answer may still come, as after a timeout
    end
    D.search, D.requests, D.queued, D.backgroundRetry = nil, {}, {}, nil
    D.infoSince = {}
    completeRequest(active, nil, false)
    for _, r in ipairs(requests) do
        completeRequest(r, nil, false)
    end
    completeRequest(background, nil, false)
    D.batch = nil
    D.clearing = nil
    F.Engine.changed()
end

-- A click captures the complete current category before sending anything. Each accepted key has
-- one completion callback, including a vanished deal, a timeout, and a cancelled request.
-- `mode`: true = deal checks (a deal is kept, updated or dropped), false = price checks (Check
-- price), or a function(key, complete) that sends a page's own check and returns true when accepted.
function D.startBatch(scope, keys, mode)
    local verifyDeals = mode == true
    if D.clearing or not F.AH.isOpen() or D.batch and D.batch.active then
        return false
    end
    local snapshot, seen = {}, {}
    for _, key in ipairs(keys or {}) do
        if not seen[key] and U.parseKey(key) then
            seen[key] = true
            snapshot[#snapshot + 1] = key
        end
    end
    local batch = {
        scope = scope,
        keys = snapshot,
        total = #snapshot,
        done = 0,
        failed = 0,
        failedKeys = {},
        active = #snapshot > 0,
        keySet = seen,
    }
    D.batch = batch
    batch.startAt, batch.preciseAt = clock(), precise()
    F.Log.trace(
        "batch.start",
        "%s %d items, mode %s",
        tostring(scope),
        #snapshot,
        type(mode) == "function" and "custom" or tostring(mode)
    )
    batch.pending = {}
    local function send(key, settled, ahead)
        local finished = false
        local function complete(_, rows, completeRows)
            if finished then
                return
            end
            finished = true
            if batch.pending[key] == complete then
                batch.pending[key] = nil
            end
            -- A price check is answered by the cheapest lots (the search is sorted by price); a
            -- deal check needs the whole list of the item.
            local success = settled ~= nil or rows ~= nil and (completeRows or (mode == false and #rows > 0))
            if settled == "price" then
                D.remove(key) -- the lowest price is at or above what the deal sells for
            elseif verifyDeals then
                local ok, err = pcall(D.verifyCallback, key, rows, completeRows)
                if not ok then
                    F.Engine.report(err)
                    success = false
                end
            end
            batch.done = batch.done + 1
            F.Log.trace(
                "batch.item",
                "%s %d/%d %s%s",
                key,
                batch.done,
                batch.total,
                success and "ok" or "no answer",
                settled and (" settled " .. tostring(settled)) or ""
            )
            if not success then
                batch.failed = batch.failed + 1
                batch.failedKeys[#batch.failedKeys + 1] = key
                -- Silence on a bag check is the server's "nobody sells it": not sent again.
                if mode == false and rows == nil and ((scope == "sell" and D.silentKey == key) or silentOwn(key)) then
                    batch.noRetry = batch.noRetry or {}
                    batch.noRetry[key] = true
                end
            end
            -- A search without an answer is sent once more at once, ahead of the rest: the batch
            -- goes top to bottom as the page is sorted. Sent again at the end of the batch, it
            -- left a row above the one being checked showing its old scan status, as if skipped.
            if not success and not (batch.noRetry and batch.noRetry[key]) and D.batch == batch then
                batch.noRetry = batch.noRetry or {}
                batch.noRetry[key] = true
                batch.done, batch.failed = batch.done - 1, batch.failed - 1
                batch.failedKeys[#batch.failedKeys] = nil
                F.Log.trace("batch.retry", "%s sent again at once", key)
                batch.send(key, nil, true)
                F.Engine.changed()
                return
            end
            -- The searches without an answer are sent once more (from the next frame): a dropped or
            -- slow answer usually comes the second time. Not the silent ones of the player's own
            -- items (silentOwn): those are reported once.
            local again = {}
            if batch.done >= batch.total and batch.failed > 0 and not batch.retried and D.batch == batch then
                for _, k in ipairs(batch.failedKeys) do
                    if not (batch.noRetry and batch.noRetry[k]) then
                        again[#again + 1] = k
                    end
                end
            end
            if #again > 0 then
                local kept = {}
                for _, k in ipairs(batch.failedKeys) do
                    if batch.noRetry and batch.noRetry[k] then
                        kept[#kept + 1] = k
                    end
                end
                batch.retried, batch.retryKeys = true, again
                batch.done, batch.failed, batch.failedKeys = batch.done - #again, #kept, kept
            else
                -- Searches the scan or a busy game held back are still this batch's work.
                local held = batch.heldKeys and #batch.heldKeys > 0
                batch.active = batch.done < batch.total or held or false
                if not batch.active and batch.failed > 0 then
                    D.reportUnanswered(batch)
                end
                if not batch.active then
                    D.reportBatchTime(batch)
                end
            end
            F.Engine.changed()
        end
        batch.pending[key] = complete
        -- Settled by Check all's first query (D.PRE_IDS): nobody sells the item, or its lowest price
        -- leaves the deal no profit.
        if settled then
            batch.settled = (batch.settled or 0) + 1
            complete(key, settled == "absent" and {} or nil, settled == "absent")
            return
        end
        -- A price check of an item a fresh full scan saw no lot of: nobody else sells it, and the
        -- server would not answer the search (WoW Forever). Checking the bags trusts a scan up to
        -- D.BAG_SCAN_AGE old: each such item waited for that silence, 36 items took minutes.
        if mode == false and F.Scan.notListed(key, scope == "sell" and D.BAG_SCAN_AGE or nil) then
            F.Trade.prices[key] = { rows = {}, at = F.Engine.clock() }
            complete(key, {}, true)
            return
        end
        -- T10: Check all on My auctions. An item of the player's that the last full scan (up to
        -- D.ALONE_AGE old) saw no other seller of, and no check since saw one of: its search would
        -- wait D.FAST_WAIT for an answer WoW Forever never sends. Answered at once as "only
        -- yours as of the scan" (asOf); the page says how old that is and a Search button sends a
        -- real search for one item. Only this page: Undercuts and buying always search.
        if mode == false and scope == "auctions" and onlyYours(key) then
            local last = F.Scan.last
            F.Trade.prices[key] = { rows = {}, at = F.Engine.clock(), asOf = last and last.at }
            complete(key, {}, true)
            return
        end
        local accepted
        if type(mode) == "function" then
            accepted = mode(key, complete)
        elseif verifyDeals then
            D.dealCheckNext = true
            accepted = D.enqueue(key, complete, complete, true, ahead)
            D.dealCheckNext = nil
        else
            accepted = F.Trade.checkPrice(key, complete, true, ahead)
        end
        if not accepted then
            -- Refused right now: a full scan waiting for its answer holds every search that is
            -- not the player's own click, and the game's throttle holds one too. That is not an
            -- answer, so the key is not counted as failed (which told the player "no answer for:
            -- ..." for searches that were never sent): it waits for the batch's next pass, which
            -- goes as soon as the scan settles. A key already waiting is not queued twice.
            if F.Scan.blocking() and not (batch.heldSet and batch.heldSet[key]) then
                batch.heldSet = batch.heldSet or {}
                batch.heldSet[key] = true
                batch.heldKeys = batch.heldKeys or {}
                batch.heldKeys[#batch.heldKeys + 1] = key
                return
            end
            if F.Scan.blocking() then
                return -- already waiting: the next pass has it
            end
            complete(key, nil, false)
        end
    end
    batch.send = send
    -- The client loads every item's auction house data now, all at once: a search of an item
    -- without it waited up to two seconds for it, one item after the other.
    for _, key in ipairs(snapshot) do
        local item = U.parseKey(key)
        if item and F.AH.keyInfoReady then
            local cached = item.kind ~= "commodity" and F.AH.cachedKeys and F.AH.cachedKeys(item)
            pcall(F.AH.keyInfoReady, item, cached and cached[1])
        end
    end
    if verifyDeals and #snapshot > 1 and D.startPre(batch) then
        F.Engine.changed()
        return #snapshot
    end
    for _, key in ipairs(snapshot) do
        if D.batch ~= batch then
            break -- a synchronous close can cancel the whole batch while sending its first key
        end
        send(key)
    end
    F.Engine.changed()
    return #snapshot
end

-- Check all's first query: the lowest price of every item of the batch at once. Sent only when it
-- can go now; otherwise every item gets its exact search as before.
function D.startPre(batch)
    if D.pre and D.pre.quick then
        D.pre = nil -- Check all asks for its own items now
    end
    if
        D.pre
        or D.search
        or not F.AH.ready()
        or F.Scan.blocking()
        or F.Trade.busy()
        or F.Sniper.inFlight()
        or (F.AH.nativeShown and F.AH.nativeShown())
    then
        return false
    end
    local ids, idSet = {}, {}
    for _, key in ipairs(batch.keys) do
        local item = U.parseKey(key)
        if item and not idSet[item.id] and #ids < D.PRE_IDS then
            idSet[item.id] = true
            ids[#ids + 1] = item.id
        end
    end
    local pre = { batch = batch, ids = ids, idSet = idSet, rows = {}, pages = 0, at = clock() }
    D.pre = pre
    if not pcall(F.AH.searchKeys, ids) then
        D.pre = nil
        return false
    end
    if D.pre == pre then
        batch.pre = pre
    end
    -- An answer inside the call (D.onPreBrowse) may have finished it already.
    D.preStep(batch)
    return true
end

-- The lowest price of each item of a first query's answer: item id -> copper.
local function lowestOf(pre)
    local low = {}
    for _, r in ipairs(pre.answered and F.AH.browseRows and pre.rows or {}) do
        local id = r.itemKey and r.itemKey.itemID or r.id
        local price = r.minPrice
        if id and pre.idSet[id] and U.finite(price) and (r.totalQuantity or r.qty or 0) > 0 then
            low[id] = math.min(low[id] or price, price)
        end
    end
    return low
end

-- The lowest price of the item is at or above what the deal sells for: no profit is left.
local function above(x, price)
    return x ~= nil and U.finite(x.exit) and x.exit > 0 and price >= x.exit
end

-- Called every frame while the first query waits: once it is answered (or D.PRE_WAIT passed),
-- each item is settled from it or gets its exact search.
function D.preStep(batch)
    local pre = batch.pre
    if not pre then
        return false
    end
    if not pre.full and clock() - pre.at < D.PRE_WAIT and D.pre == pre then
        return true
    end
    if D.pre == pre then
        D.pre = nil
    end
    batch.pre = nil
    local trusted = pre.full and not pre.foreign
    local low = lowestOf(pre)
    batch.preAnswered = pre.answered or false
    for _, key in ipairs(batch.keys) do
        if D.batch ~= batch then
            return true
        end
        local item = U.parseKey(key)
        local settled
        if trusted and item and pre.idSet[item.id] then
            local price = low[item.id]
            if not price then
                settled = "absent"
            elseif item.kind ~= "item" then
                -- Gear and commodities: the browse price is one unit's (an item stack's is not).
                local d = D.get(key)
                if above(d, price) and (not d.alt or above(d.alt, price)) then
                    settled = "price"
                end
            end
        end
        batch.send(key, settled)
    end
    F.Engine.changed()
    return true
end

-- Starts the quick check (D.QUICK_AGE) when it is due and nothing else waits; true when sent.
-- More than D.PRE_IDS items: the next query goes the next idle frame (D.quickDone: ids asked).
function D.quickCheck(now)
    if
        D.pre
        or D.search
        or #D.list == 0
        or (D.batch and D.batch.active)
        or not F.AH.canBrowse()
        -- Peeked: the one message a stuck throttle lets through is not spent on background work.
        or not F.AH.ready(true)
        or F.Scan.blocking()
        or F.Trade.busy()
        or F.Sniper.inFlight()
        or (F.AH.nativeShown and F.AH.nativeShown())
    then
        return false
    end
    if not D.quickDone then
        if now - math.max(D.listAt or 0, D.quickAt or 0) < D.QUICK_AGE then
            return false
        end
        D.quickDone = {}
    end
    local ids, idSet = {}, {}
    for _, d in ipairs(D.list) do
        local item = U.parseKey(d.key)
        if item and not idSet[item.id] and not D.quickDone[item.id] and #ids < D.PRE_IDS then
            idSet[item.id] = true
            ids[#ids + 1] = item.id
        end
    end
    if #ids == 0 then
        D.quickDone, D.quickAt = nil, now
        return false
    end
    for _, id in ipairs(ids) do
        D.quickDone[id] = true
    end
    local pre = { quick = true, ids = ids, idSet = idSet, rows = {}, pages = 0, at = now }
    D.pre = pre
    if not pcall(F.AH.searchKeys, ids) then
        D.pre, D.quickDone, D.quickAt = nil, nil, now
        return false
    end
    F.Log.trace("quick.check", "%d items asked", #ids)
    return true
end

-- Every frame while the quick check waits: once answered (or D.PRE_WAIT passed), the deals the
-- answer proves stale leave the list. An answer not whole, or another query's, removes nothing.
function D.quickStep()
    local pre = D.pre
    if not F.AH.isOpen() then
        D.pre, D.quickDone = nil, nil
        return
    end
    if not pre.full and clock() - pre.at < D.PRE_WAIT then
        return
    end
    D.pre = nil
    if not (pre.full and not pre.foreign) then
        D.quickDone, D.quickAt = nil, clock()
        F.Log.trace("quick.check", "no whole answer: nothing removed")
        return
    end
    local low = lowestOf(pre)
    local removed = 0
    for i = #D.list, 1, -1 do
        local d = D.list[i]
        local item = U.parseKey(d.key)
        local price = item and low[item.id]
        local fresh = (d.verified or 0) >= pre.at or (d.found or 0) >= pre.at
        local stale = false
        if item and pre.idSet[item.id] and not fresh then
            if not price then
                stale = true
            elseif item.kind ~= "item" then
                -- Gear and commodities: the browse price is one unit's (an item stack's is not).
                local m = D.medianOf(d)
                stale = above(d, price) and (not d.alt or above(d.alt, price)) and (not m or above(m, price))
            end
        end
        if stale then
            table.remove(D.list, i)
            removed = removed + 1
        end
    end
    F.Log.trace("quick.check", "%d items answered, %d deals removed", #pre.ids, removed)
    if removed > 0 then
        F.Log.add(
            "scan",
            string.format(
                F.Locale.text("Quick check: %d deals nobody sells any more or without profit removed."),
                removed
            )
        )
        F.Engine.changed()
    end
end

-- How long Check all took, in the log: the measure the 30 seconds are judged by in the game.
function D.reportBatchTime(batch)
    if batch.timeReported or not batch.startAt then
        return
    end
    batch.timeReported = true
    local seconds = clock() - batch.startAt
    local exact = batch.preciseAt and precise() - batch.preciseAt or seconds
    F.Log.stat("batch." .. tostring(batch.scope) .. ".s", exact)
    if batch.total > 0 then
        F.Log.stat("batch.perItem.s", exact / batch.total)
    end
    F.Log.trace(
        "batch.end",
        "%s %d items in %.1fs, settled %d, no answer %d, stalls %d",
        tostring(batch.scope),
        batch.total,
        exact,
        batch.settled or 0,
        batch.failed or 0,
        batch.stalls or 0
    )
    D.lastBatch = {
        scope = batch.scope,
        total = batch.total,
        seconds = seconds,
        settled = batch.settled or 0,
        failed = batch.failed,
    }
    F.Log.add(
        "scan",
        string.format(
            F.Locale.text("Check all: %d items in %d s (%d settled by one query, %d without an answer)."),
            batch.total,
            math.floor(seconds + 0.5),
            batch.settled or 0,
            batch.failed
        )
    )
end

-- Sends the searches a batch could not start yet (the full scan was waiting for its answer, or the
-- game was busy), and the second try of its unanswered ones. Called every frame.
function D.batchRetry()
    local batch = D.batch
    if D.pre and D.pre.quick then
        D.quickStep()
    elseif D.pre and (D.pre.batch ~= batch or not F.AH.isOpen()) then
        D.pre = nil -- its batch ended or was cancelled: nothing waits for the answer
    end
    if not batch or not F.AH.isOpen() then
        return
    end
    if batch.pre and D.preStep(batch) and batch.pre then
        return
    end
    -- Held searches first: the player's Check all should start the moment the scan settles, not
    -- after the unanswered ones have been tried again.
    local held = batch.heldKeys
    if held and #held > 0 and not F.Scan.blocking() then
        batch.heldKeys, batch.heldSet = nil, nil
        for _, key in ipairs(held) do
            if D.batch ~= batch then
                return
            end
            batch.send(key)
        end
    end
    local keys = batch.retryKeys
    if not keys then
        return
    end
    batch.retryKeys = nil
    for _, key in ipairs(keys) do
        if D.batch ~= batch then
            break
        end
        batch.send(key)
    end
end

-- The items still without an answer after the second try, named in the chat once. On WoW Forever
-- the server does not answer a search for an item nobody else sells.
function D.reportUnanswered(batch)
    local names = {}
    for _, key in ipairs(batch.failedKeys) do
        local item = U.parseKey(key)
        local name = item and (U.itemInfo(item.id) or item.name) or key
        names[#names + 1] = name
    end
    batch.unanswered = names
    F.Log.add(
        "scan",
        string.format(
            F.Locale.text(
                "no answer for: %s. Either nobody else sells them, or the server did not answer their search: the next check searches them by name."
            ),
            table.concat(names, ", ")
        )
    )
end

function D.batchProgress(scope)
    local batch = D.batch
    if not batch or scope and batch.scope ~= scope then
        return 0, 0, false, 0
    end
    return batch.done, batch.total, batch.active, batch.failed
end

-- A manual verification is queued; automatic deal checks only attempt an idle slot.
function D.verify(key, callback, source)
    local done = function(k, rows, complete)
        D.verifyCallback(k, rows, complete, callback)
    end
    if source == "auto" then
        -- Found deals are checked at the faster pace; the sniper keeps one search per second.
        return D.request(key, done, source, true)
    end
    return D.enqueue(key, done, callback or D.verifyCallback)
end

-- A purchase went through: the deal is evaluated again from the rows of its check, less what was
-- bought (the auction for gear and items, the cheapest units for commodities), and keeps the time of
-- its check, so it is checked again once that is too old. No search is sent, except after a bucket:
-- an item row of identical auctions loses only the one bought, and the others stay listed under
-- auction IDs not known yet, which a new search reads before the next purchase.
function D.afterPurchase(op)
    if F.Scan.last then
        F.Scan.last.purchased = F.Scan.last.purchased or {}
        F.Scan.last.purchased[op.key] = true
    end
    local d = D.get(op.key)
    if not d or type(d.rows) ~= "table" then
        D.verify(op.key)
        return
    end
    local rows, left, bucket = {}, op.kind == "commodity" and (op.qty or 0) or 0, false
    for _, r in ipairs(d.rows) do
        if op.kind ~= "commodity" then
            if not (op.auctionID and r.auctionID == op.auctionID) then
                rows[#rows + 1] = r
            elseif (r.qty or 1) > (op.qty or 1) then
                local copy = U.copy(r)
                copy.qty, copy.auctionID = r.qty - (op.qty or 1), nil
                rows[#rows + 1] = copy
                bucket = true
            end
        elseif left >= (r.qty or 0) then
            left = left - (r.qty or 0)
        else
            local copy = U.copy(r)
            copy.qty = (r.qty or 0) - left
            left = 0
            rows[#rows + 1] = copy
        end
    end
    local verified = d.verified
    D.verifyCallback(op.key, rows, true)
    local live = D.get(op.key)
    if live then
        live.verified = verified
        if live.alt then
            live.alt.verified = verified
        end
        if D.medianOf(live) then
            live.median.verified = verified
        end
    end
    if bucket then
        D.verify(op.key)
    end
end

function D.verifyCallback(k, rows, complete, callback)
    local d = D.get(k)
    if rows and complete then
        local item = U.parseKey(k)
        local history = F.Data.market(F.db, F.Engine.scope()).history[k]
        local g = {
            key = k,
            kind = item.kind,
            id = item.id,
            rows = rows,
            market = d and d.market or (history and history.scan and history.scan.market),
            link = d and d.link or (rows[1] and rows[1].link),
        }
        local last = F.Scan.last
        if last and last.groups and last.groups[k] and last.scope == F.Engine.scope() then
            -- A negative check supersedes the old scan too. Keep only the prefix evaluation
            -- uses (40 lots and the following price), so a wallet gain can reuse the newest rows.
            local checked = { key = g.key, kind = g.kind, id = g.id, market = g.market, link = g.link, rows = {} }
            for i = 1, math.min(41, #rows) do
                checked.rows[i] = rows[i]
            end
            last.checkedGroups = last.checkedGroups or {}
            last.checkedGroups[k] = checked
        end
        local live, reason = D.evaluate(g, F.AH.vendorPrice(item.id), history, clock())
        if live then
            live.verified = clock()
            live.rows = rows
            if live.alt then
                live.alt.verified, live.alt.rows = live.verified, rows
            end
            if D.medianOf(live) then
                live.median.verified, live.median.rows = live.verified, rows
            end
            D.add(live, D.scope)
            D.alert(live)
        else
            D.remove(k)
        end
        if callback then
            callback(live, reason)
        end
    elseif callback then
        callback(nil, "search_failed")
    end
end

-- What a stuck batch and the search queue are doing, as one trace line.
function D.stallState(batch)
    local s, head = D.search, D.requests[1]
    local checks = F.Trade.checkQueue
    local function yes(v)
        return tostring(v and true or false)
    end
    return string.format(
        "%s %d/%d (no answer %d, held for the scan %d, retried %s); search %s phase %s version %s/%s waitKey %s held %s waited %.1fs; queue %d head %s held %s; owned checks %d; pre %s, scan blocking %s, trade busy %s, posting %s, paused %s, native page %s",
        tostring(batch.scope),
        batch.done,
        batch.total,
        batch.failed or 0,
        batch.heldKeys and #batch.heldKeys or 0,
        yes(batch.retried),
        s and s.key or "-",
        s and tostring(s.phase or "plain") or "-",
        s and tostring(s.keyIndex or 0) or "-",
        s and s.keys and tostring(#s.keys) or "-",
        s and yes(s.waitKey) or "-",
        s and tostring(s.heldWhy or "-") or "-",
        s and (s.waited or 0) or 0,
        #D.requests,
        head and head.key or "-",
        head and tostring(head.heldWhy or "-") or "-",
        checks and #checks or 0,
        yes(D.pre),
        yes(F.Scan.blocking()),
        yes(F.Trade.busy()),
        yes(F.Trade.postingNow()),
        yes(D.batchPaused()),
        yes(F.AH.nativeShown and F.AH.nativeShown())
    )
end

-- A batch with no item finished for D.STALL_TRACE seconds is traced, every D.STALL_TRACE seconds.
-- The stalled batch's oldest unanswered item is given up (see D.STALL_GIVEUP): the search in
-- flight, a queued request, or a key whose answer was lost on the way. Returns what was done.
function D.unstick(batch)
    -- An item given up already waited D.STALL_GIVEUP: it is not tried a second time.
    batch.noRetry = batch.noRetry or {}
    local s = D.search
    if s and batch.pending[s.key] then
        batch.noRetry[s.key] = true
        F.Log.trace("batch.giveup", "%s in search, %s", s.key, heldText(s))
        if s.waitKey then
            D.search = nil
            completeRequest(s, nil, false)
        else
            timeoutSearch(s)
        end
        return "search"
    end
    for _, key in ipairs(batch.keys) do
        local done = batch.pending[key]
        if done then
            batch.noRetry[key] = true
            local r = D.queued[key]
            if r then
                for i, queued in ipairs(D.requests) do
                    if queued == r then
                        table.remove(D.requests, i)
                        break
                    end
                end
                D.queued[key] = nil
                F.Log.trace("batch.giveup", "%s queued, %s", key, heldText(r))
                completeRequest(r, nil, false)
            else
                F.Log.trace("batch.giveup", "%s lost: no search and not queued", key)
            end
            done(key, nil, false) -- nothing if the request's callback already answered it
            return r and "queued" or "lost"
        end
    end
    if (batch.heldKeys and #batch.heldKeys > 0) or batch.retryKeys then
        return nil -- sent from the next frame by D.batchRetry
    end
    -- Nothing is left to answer, yet the batch counts itself unfinished.
    F.Log.trace("batch.giveup", "%s %d/%d with nothing left to answer", tostring(batch.scope), batch.done, batch.total)
    batch.active = false
    D.reportBatchTime(batch)
    F.Engine.changed()
    return "count"
end

local function watchBatch()
    local batch = D.batch
    if not (batch and batch.active) then
        return
    end
    local t = precise()
    -- What the player does holds a batch on purpose: that is not a stall to give up on.
    if
        batch.lastDone ~= batch.done
        or batch.pre
        or F.Scan.blocking()
        or D.batchPaused()
        or F.Trade.busy()
        or F.Trade.postingNow()
    then
        batch.giveupAt = t
    end
    batch.giveupAt = batch.giveupAt or t
    if t - batch.giveupAt >= D.STALL_GIVEUP and batch.pending then
        batch.giveupAt = t
        batch.givenUp = (batch.givenUp or 0) + 1
        D.unstick(batch)
    end
    if batch.lastDone ~= batch.done then
        batch.lastDone, batch.progressAt = batch.done, t
        return
    end
    batch.progressAt = batch.progressAt or t
    if t - batch.progressAt >= D.STALL_TRACE and t - (batch.stallAt or 0) >= D.STALL_TRACE then
        batch.stallAt = t
        batch.stalls = (batch.stalls or 0) + 1
        local ok, line = pcall(D.stallState, batch)
        F.Log.trace("batch.stall", "%.0fs without progress: %s", t - batch.progressAt, ok and line or tostring(line))
    end
end

-- Called every frame: timeouts, retries, and automatic verification of the best unverified deals.
function D.step()
    D.batchRetry()
    watchBatch()
    local now = clock()
    local s = D.search
    if s then
        local t = precise()
        if not s.waitKey then
            s.waited = (s.waited or 0) + math.max(0, t - (s.budgetAt or t))
        end
        s.budgetAt = t
        local batch = D.batch
        local bag = batch and batch.active and batch.scope == "sell" and batch.keySet and batch.keySet[s.key]
        if (s.waited or 0) >= (bag and D.BAG_SEARCH_TIME or D.MAX_SEARCH_TIME) then
            timeoutSearch(s)
            s = nil
        end
    end
    -- A full scan waits for its answer: only the player's clicks go meanwhile. A gear search held
    -- between its versions by it gives way to a click.
    local blocking = F.Scan.blocking()
    local first = nextRequest(blocking)
    if s and s.waitKey and first and (priority(first) < priority(s) or batchHeld(s) or blocking and not isClick(s)) then
        parkSearch()
        s = nil
    end
    -- The throttle is asked last: with a stuck throttle AH.ready lets one message through, and a
    -- step then held back by another test wasted it (the Buy button never got one).
    if s and s.waitKey then
        local why
        if not (isClick(s) or not blocking) then
            why = "full_scan"
        elseif priority(s) ~= 0 and F.AH.nativeShown and F.AH.nativeShown() then
            why = "native_page"
        elseif batchHeld(s) then
            why = "batch_paused"
        elseif F.Trade.busy() then
            why = "trade_busy"
        elseif F.Trade.postingNow() then
            why = "posting"
        elseif priority(s) ~= 0 and D.buyHolding(s.key) then
            why = "buy_hold"
        elseif not F.AH.ready() then
            why = "throttle"
        end
        -- Time held here between versions is not counted against the search's budget (s.waited).
        noteHeld(s, why, precise())
        if not why then
            s.waitKey, s.at, s.budgetAt = nil, now, precise()
            if not pcall(F.AH.searchKey, s.keys[s.keyIndex]) then
                finishSearch(nil, false)
            end
        end
    end
    s = D.search
    if s and s.phase == "prices" and now - s.at > D.VERSION_WAIT then
        -- No answer to the versions' prices: every version is searched, as before.
        F.Log.trace("search.versions", "%s no price answer in %.1fs: every version", s.key, now - s.at)
        browseLeft(s)
        s.phase = "keys"
        nextGearKey(s)
        s = D.search
    end
    if s and not s.waitKey and s.phase ~= "prices" and now - s.at > (s.fast and D.FAST_WAIT or D.ANSWER_WAIT) then
        -- Nobody else sells it (only yours): no retry by name, it is answered as such.
        local alone = onlyYours(s.key)
        if s.phase == "keys" and not (alone and #s.found == 0) and ownVersion(s.keys[s.keyIndex]) then
            -- A version with the player's own lot gave no answer: the next one is searched, and the
            -- rows read so far are kept. Other endings are not answered from an unread version.
            s.ownSkipped, s.every = true, false
            nextGearKey(s)
        elseif s.phase == "keys" and s.keyIndex > 1 and not s.resent and not alone then
            -- One version without an answer, after others answered, is asked once more, the lots
            -- read kept. Ending the search there threw every version read away: a check sent again
            -- walked all 23 versions of a gear item from the first (Check all stood on one row for
            -- half a minute). A first version silent is more likely a remembered one gone stale.
            s.resent = true
            F.Log.trace(
                "search.resend",
                "%s version %d of %d: no answer in %.1fs, asked once more",
                s.key,
                s.keyIndex,
                #s.keys,
                now - s.at
            )
            s.keyPages, s.keyRows, s.waitKey, s.at = 0, nil, true, now
        elseif not alone and s.item.kind == "item" and not s.phase and F.AH.canSearchGear() and not s.byNameTried then
            -- No answer to the plain search: tried again at once by name (a browse lists the
            -- item's exact keys, then each is searched), as gear is. Remembered for next time.
            D.byName[s.item.id] = true
            s.byNameTried = true
            D.search = nil
            s.readyAt = precise()
            queueRequest(s, true)
        else
            timeoutSearch(s)
        end
    end
    if D.search or F.Trade.busy() or not F.AH.isOpen() then
        return
    end
    local r, index = nextRequest(blocking)
    if blocking and not r then
        return
    end
    if r then
        if precise() >= r.readyAt then
            table.remove(D.requests, index)
            D.queued[r.key] = nil
            if not startRequest(r) then
                table.insert(D.requests, index, r)
                D.queued[r.key] = r
            end
        end
        return
    end
    -- Owned-auction checks enter this same FIFO before any new background work.
    if F.Trade.checkQueue and #F.Trade.checkQueue > 0 then
        return
    end
    -- The player is about to buy or post, or works in the game's own Buy or Sell page: background
    -- searches wait (D.holding).
    if D.holding() or (F.AH.nativeShown and F.AH.nativeShown()) then
        return
    end
    r = D.backgroundRetry
    if r then
        if r.source == "sniper" and not settings().sniper or r.source == "auto" and not settings().autoVerify then
            D.backgroundRetry = nil
            completeRequest(r, nil, false)
        elseif precise() >= r.readyAt then
            D.backgroundRetry = nil
            if not startRequest(r) then
                D.backgroundRetry = r
            end
            return
        else
            return
        end
    end
    if D.quickCheck(now) then
        return
    end
    if settings().autoVerify then
        for _, d in ipairs(D.list) do
            if (not d.verified or now - d.verified > 300) and now - (d.tried or 0) > 120 then
                if D.verify(d.key, nil, "auto") then
                    d.tried = now
                end
                return
            end
        end
    end
    D.snipe()
end

-- Sniper: exact checks of candidates found by browse rounds. Without browse support, cycle through
-- hot items from the last full scan, with at most one search per second.
function D.snipe()
    local hot = F.Scan.hot
    if not (F.db.settings.sniper or F.Sniper.quick) or not D.scope then
        return false
    end
    -- The throttle is only looked at (AH.available): with a stuck throttle AH.ready lets one message
    -- through, and taking it here left none for the search itself, nor for the Buy button.
    if F.Sniper.active() then
        -- A quick scan checks its candidates once every page is read (Sniper.step).
        local quick = F.Sniper.quick
        if quick and not quick.done and not F.db.settings.sniper then
            return false
        end
        -- Fast sniper: exact checks of the candidates its browse rounds found.
        if precise() - (D.lastRequest or -10) < 0.4 or not F.AH.available() then
            return false
        end
        local key = F.Sniper.next()
        if key and D.request(key, D.verifyCallback, "sniper", true) then
            D.snipes = (D.snipes or 0) + 1
            return true
        end
        if key then
            F.Sniper.putBack(key)
        end
        return false
    end
    if not hot or #hot == 0 then
        return false
    end
    if precise() - (D.lastRequest or -10) < 1 or not F.AH.available() then
        return false
    end
    D.snipeIndex = (D.snipeIndex or 0) % #hot + 1
    local key = hot[D.snipeIndex]
    local d = D.get(key)
    if d and d.verified and clock() - d.verified < D.FRESH then
        return false
    end
    if D.request(key, D.verifyCallback, "sniper") then
        D.snipes = (D.snipes or 0) + 1
        return true
    end
    return false
end

-- Sound, screen and chat notice for a deal that can be bought now. Once per item, again only
-- after 10 minutes or when the profit grew by a fifth.
D.alerted = {}
function D.alert(d)
    local s = settings()
    if not s.alerts or d.profit < s.alertMinProfit then
        return false
    end
    local last = D.alerted[d.key]
    if last and clock() - last.at < 600 and d.profit <= last.profit * 1.2 then
        return false
    end
    D.alerted[d.key] = { at = clock(), profit = d.profit }
    local L = F.Locale.text
    local name = d.link or d.key
    local msg = string.format(
        L("ForeverFlip: deal %s · profit %s (%s)"),
        name,
        U.money(d.profit),
        L(d.mode == "vendor" and "vendor" or "resale")
    )
    F.Log.sound("deal")
    if FlashClientIcon then
        pcall(FlashClientIcon)
    end
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(msg, 1, 0.82, 0)
    end
    F.Log.add("deal", msg)
    return true
end

function D.progress()
    local total, done = 0, 0
    for _, d in ipairs(D.list) do
        total = total + 1
        if d.verified then
            done = done + 1
        end
    end
    return done, total
end
