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

local function clock()
    return F.Engine.clock()
end

local function settings()
    return F.db.settings
end

function D.budget()
    local s = settings()
    return math.floor(F.Engine.wallet() * (s.spendShare or 0.8))
end

-- Evaluates a scan group or live listings. `g` has key, kind, id, rows, market, link.
-- One item may hold at most this share of the money (in stock plus the new purchase).
local function itemRoom(key)
    local p = F.Data.char(F.db, F.Engine.owner()).positions[key]
    local share = settings().itemShare or 0.3
    return math.max(0, math.floor(F.Engine.wallet() * share) - (p and p.cost or 0)), p and p.qty or 0
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
        local de = F.Disenchant.evaluate(g.rows, g.id, D.budget())
        -- A shopping deal counts one auction (the player wants the item), a disenchant deal every
        -- lot: their profits do not compare, and the shopping list wins as an order does.
        if de and (not deal or deal.mode ~= "shop" and de.profit > deal.profit) then
            deal, reason = de, nil
        end
    end
    if deal then
        deal.key, deal.kind, deal.id, deal.link = g.key, g.kind, g.id, g.link
        deal.market, deal.vendor = g.market, vendor
        if deal.mode == "vendor" then
            deal.vendorHow = select(2, F.AH.vendorPrice(g.id))
            -- A merchant has refused the item before (a poison's item data is priced by what it
            -- costs, not by what a merchant pays): shown with that warning, not hidden.
            deal.refused = F.AH.refusedByMerchant({ itemID = g.id })
        end
        deal.found = now or clock()
    end
    return deal, reason
end

-- A merchant was sent the item and kept nothing: its vendor deals leave the list at once (the
-- price is real, the sale is not). Sent by AH.noteRefused the first time an item is proved.
function D.refused(id)
    local dropped = false
    for i = #D.list, 1, -1 do
        local d = D.list[i]
        if d.mode == "vendor" and d.id == id then
            table.remove(D.list, i)
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
    local p = F.Data.char(F.db, F.Engine.owner()).positions[d.key]
    return D.sureAt(d.key, d.exit, (d.qty or 1) + (p and p.qty or 0), now)
end

-- Sure of selling `qty` of an item at `price`, kept D.SURE_KEEP seconds for the same price,
-- quantity and sales data (it changes with a scan; the tooltip and the deals share it). Each price
-- and quantity has its own entry: the tooltip asks for one unit and for the deal's units of the
-- same item, and one entry per item made each of them throw the other's away.
function D.sureAt(key, price, qty, now)
    now = now or clock()
    local h = F.Data.market(F.db, F.Engine.scope()).history[key]
    local data = type(h) == "table" and (h.sales and h.sales.at or h.flow and h.flow.at) or 0
    local stamp = price .. ":" .. qty .. ":" .. tostring(data)
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

function D.remove(key)
    for i, d in ipairs(D.list) do
        if d.key == key then
            table.remove(D.list, i)
            F.Engine.changed()
            return
        end
    end
end

function D.get(key)
    for _, d in ipairs(D.list) do
        if d.key == key then
            return d
        end
    end
end

function D.visible(filter)
    local out = {}
    for _, d in ipairs(D.list) do
        -- Deals of the last scan stay listed until the next one; buying checks them first.
        if not filter or filter == "all" or d.mode == filter then
            out[#out + 1] = d
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
    local ui = F.UI
    if not ui or not ui.frame or not ui.frame:IsShown() or ui.section ~= "deals" then
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
    local ui = F.UI
    if not ui or not ui.frame or not ui.frame:IsShown() then
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
        return true -- a click found the way busy, or Buy all to vendor runs
    end
    local ui = F.UI
    if not ui or not ui.frame or not ui.frame:IsShown() then
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
-- spending limit (Settings) when one is set. The Buy button, Buy next and Buy all to vendor shrink a
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
-- the preparation on Buy hover and the frame step of Buy all to vendor ask with the same priority
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
    local r = { key = key, item = item, source = source or "manual", callbacks = {}, readyAt = precise(), fast = fast }
    r.priority = priority(r)
    addCallback(r, callback, identity)
    return r
end

local function completeRequest(r, rows, complete)
    if not r or r.completed then
        return
    end
    r.completed = true
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

local function startRequest(r)
    local now = precise()
    while D.sent[1] and now - D.sent[1] >= 60 do
        table.remove(D.sent, 1)
    end
    if
        D.clearing
        or D.search
        or (priority(r) > 0 and D.buyHolding(r.key))
        or not F.AH.isOpen()
        or F.Trade.busy()
        or F.Trade.postingNow()
        or F.Sniper.inFlight()
        -- A full scan waits for its answer: only the player's own clicks go meanwhile.
        or (F.Scan.blocking() and not isClick(r))
        or batchHeld(r)
        -- The game's own Buy or Sell page is shown: what it shows is not replaced.
        or (priority(r) > 0 and F.AH.nativeShown and F.AH.nativeShown())
        or not F.AH.ready()
        -- The server's throttle paces the searches (as in Auctionator). D.GAP only keeps answers
        -- that come inside the call from sending every queued search in one frame; background
        -- work (the sniper, automatic checks) keeps one search per second.
        or now - (D.lastRequest or -10) < ((priority(r) >= 2 and not r.fast) and 1 or D.GAP)
        or #D.sent >= D.PER_MINUTE
    then
        return false
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
            return false
        end
    end
    D.infoSince[r.key] = nil
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
    local ok
    -- Gear, and items whose plain search got no answer, are searched by name: a browse lists their
    -- exact item keys, then each key is searched.
    local byName = (r.item.kind == "gear" or D.byName[r.item.id]) and F.AH.canSearchGear()
    if cached then
        -- Its versions are known from an earlier browse: they are searched straight away.
        r.phase, r.keys, r.keyIndex, r.found, r.foundIDs, r.allComplete, r.cached =
            "keys", cached, 0, {}, {}, true, true
        r.every, r.shared = every and r.item.kind == "gear", {}
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
function D.enqueue(key, callback, identity, fast)
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
    queueRequest(r)
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

local function cheaper(a, b)
    return a.unit < b.unit
end

local function timeoutSearch(s)
    if s.phase == "browse" then
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
    finishSearch(nil, false)
end

-- The next item-key version of a gear search, or the end of it with every version's rows.
function nextGearKey(s)
    s.keyIndex, s.keyPages, s.keyRows = s.keyIndex + 1, 0, nil
    local key = s.keys[s.keyIndex]
    if not key then
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
function D.onBrowse()
    local s = D.search
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
    nextGearKey(s)
    return true
end

-- Somebody else sent a browse query (AH.hookBrowse): the answer a gear search waits for may be
-- theirs, so it can no longer prove that nobody sells the item.
function D.onForeignBrowse()
    local s = D.search
    if s and s.phase == "browse" then
        s.foreign = true
    end
end

function D.onBrowseFailure()
    local s = D.search
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
        if s.phase == "browse" then
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
    if not enabled then
        F.Sniper.reset()
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

-- Stops all of it at once (the Stop button): queued and running searches are dropped (an answer
-- still on its way is ignored), the full scan is stopped, the sniper's round ends, a merchant sale
-- stops after what was sent, Buy all to vendor ends. Settings stay as they are.
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
    local function send(key)
        local finished = false
        local function complete(_, rows, completeRows)
            if finished then
                return
            end
            finished = true
            -- A price check is answered by the cheapest lots (the search is sorted by price); a
            -- deal check needs the whole list of the item.
            local success = rows ~= nil and (completeRows or (mode == false and #rows > 0))
            if verifyDeals then
                local ok, err = pcall(D.verifyCallback, key, rows, completeRows)
                if not ok then
                    F.Engine.report(err)
                    success = false
                end
            end
            batch.done = batch.done + 1
            if not success then
                batch.failed = batch.failed + 1
                batch.failedKeys[#batch.failedKeys + 1] = key
            end
            if batch.done >= batch.total and batch.failed > 0 and not batch.retried and D.batch == batch then
                -- The searches without an answer are sent once more (from the next frame): a
                -- dropped or slow answer usually comes the second time.
                batch.retried, batch.retryKeys = true, batch.failedKeys
                batch.done, batch.failed, batch.failedKeys = batch.done - #batch.retryKeys, 0, {}
            else
                batch.active = batch.done < batch.total
                if not batch.active and batch.failed > 0 then
                    D.reportUnanswered(batch)
                end
            end
            F.Engine.changed()
        end
        -- A price check of an item a fresh full scan saw no lot of: nobody else sells it, and the
        -- server would not answer the search (WoW Forever).
        if mode == false and F.Scan.notListed(key) then
            F.Trade.prices[key] = { rows = {}, at = F.Engine.clock() }
            complete(key, {}, true)
            return
        end
        local accepted
        if type(mode) == "function" then
            accepted = mode(key, complete)
        elseif verifyDeals then
            accepted = D.enqueue(key, complete, complete, true)
        else
            accepted = F.Trade.checkPrice(key, complete, true)
        end
        if not accepted then
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
    for _, key in ipairs(snapshot) do
        if D.batch ~= batch then
            break -- a synchronous close can cancel the whole batch while sending its first key
        end
        send(key)
    end
    F.Engine.changed()
    return #snapshot
end

-- Sends the second try of a batch's unanswered searches (called every frame).
function D.batchRetry()
    local batch = D.batch
    local keys = batch and batch.retryKeys
    if not keys or not F.AH.isOpen() then
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
    print(
        "ForeverFlip: "
            .. string.format(
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

-- Called every frame: timeouts, retries, and automatic verification of the best unverified deals.
function D.step()
    D.batchRetry()
    local now = clock()
    local s = D.search
    if s then
        local t = precise()
        if not s.waitKey then
            s.waited = (s.waited or 0) + math.max(0, t - (s.budgetAt or t))
        end
        s.budgetAt = t
        if (s.waited or 0) >= D.MAX_SEARCH_TIME then
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
    if
        s
        and s.waitKey
        and (isClick(s) or not blocking)
        and (priority(s) == 0 or not (F.AH.nativeShown and F.AH.nativeShown()))
        and not batchHeld(s)
        and not F.Trade.busy()
        and not F.Trade.postingNow()
        and (priority(s) == 0 or not D.buyHolding(s.key))
        and F.AH.ready()
    then
        s.waitKey, s.at, s.budgetAt = nil, now, precise()
        if not pcall(F.AH.searchKey, s.keys[s.keyIndex]) then
            finishSearch(nil, false)
        end
    end
    s = D.search
    if s and not s.waitKey and now - s.at > (s.fast and D.FAST_WAIT or D.ANSWER_WAIT) then
        -- Nobody else sells it (only yours): no retry by name, it is answered as such.
        local alone = onlyYours(s.key)
        if s.phase == "keys" and not (alone and #s.found == 0) and ownVersion(s.keys[s.keyIndex]) then
            -- A version with the player's own lot gave no answer: the next one is searched, and the
            -- rows read so far are kept. Other endings are not answered from an unread version.
            s.ownSkipped, s.every = true, false
            nextGearKey(s)
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
    if not F.db.settings.sniper or not D.scope then
        return false
    end
    -- The throttle is only looked at (AH.available): with a stuck throttle AH.ready lets one message
    -- through, and taking it here left none for the search itself, nor for the Buy button.
    if F.Sniper.active() then
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
    if d and d.verified and clock() - d.verified < 60 then
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
    if PlaySound then
        pcall(PlaySound, SOUNDKIT and SOUNDKIT.AUCTION_WINDOW_OPEN or 5274)
    end
    if FlashClientIcon then
        pcall(FlashClientIcon)
    end
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(msg, 1, 0.82, 0)
    end
    print(msg)
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
