-- Buying and selling. Every purchase, post and vendor sale starts from a click of the player;
-- nothing is bought or listed automatically.
local F = ForeverFlip
local U = F.Util
local M = F.Market
local T = {}
F.Trade = T

local function clock()
    return F.Engine.clock()
end

local function char()
    return F.Data.char(F.db, F.Engine.owner())
end

local function displayName(key, link)
    local item = U.parseKey(key)
    return U.linkName(link) or (item and U.itemInfo(item.id)) or key
end

function T.busy()
    return T.op ~= nil and T.op.state ~= "done"
end

-- A post waits for the game's AUCTION_HOUSE_AUCTION_CREATED (up to 10 seconds) before the next one:
-- a second post meanwhile would take the place of the first in T.lastPost.
function T.postingNow()
    local l = T.lastPost
    return l ~= nil and #l.ids < l.auctions and clock() - l.at < 10
end

-- Buying ----------------------------------------------------------------------------------------
-- T.op = { state = "quote" | "quoted" | "awaiting", key, kind, id, qty, cost, unit, auctionID, deal }
-- A purchase goes out only while no search waits for its answer and the server is ready: the game
-- queues a message behind an unanswered one, and on WoW Forever some are never answered, so a
-- purchase sent then never left (no money spent, no answer). Background searches rest while a
-- checked deal is selected (Deals.holding), so the way is free within a second or two.
function T.canBuy(deal)
    return deal and deal.verified and clock() - deal.verified <= F.Deals.FRESH and not T.busy() and F.AH.isOpen()
end

-- Selection and mouse movement may prepare read-only data; buying still needs a click.
function T.prepareBuy(key)
    local deal = F.Deals.get(key)
    if not deal or T.busy() or not F.AH.isOpen() then
        return false
    end
    if
        deal.verified
        and clock() - deal.verified <= F.Deals.FRESH
        and (deal.kind == "commodity" or F.AH.searchedLast(deal.id))
    then
        return true
    end
    deal.verified = nil -- a failed preparation cannot leave the earlier ready mark usable
    F.Engine.message = nil
    F.Deals.verify(key)
    F.Engine.changed()
    return false
end

-- The button is actionable only once the query/quote connection is available.
function T.readyToBuy(deal)
    return T.canBuy(deal)
        and not T.postingNow()
        and not F.Deals.pending(deal.key)
        and not F.Deals.searching()
        and not F.Sniper.inFlight()
        and F.AH.available()
        and (deal.kind == "commodity" or F.AH.searchedLast(deal.id))
end

-- The way to the server is free: no search waits for its answer and the throttle is ready. When it
-- is not, background work rests for a few seconds so the next click goes through.
function T.wayFree()
    if not T.busy() and not T.postingNow() and not F.Deals.searching() and not F.Sniper.inFlight() and F.AH.ready() then
        return true
    end
    F.Deals.holdUntil = clock() + 5
    return false
end

function T.buy(key)
    local deal = F.Deals.get(key)
    if not T.canBuy(deal) then
        return false, "verify_first"
    end
    if deal.cost > F.Engine.wallet() then
        return false, "no_money"
    end
    if T.overLimit(deal.cost) then
        return false, "spend_limit"
    end
    if not T.wayFree() then
        return false, "buy_busy"
    end
    if deal.kind ~= "commodity" and deal.id and not F.AH.searchedLast(deal.id) then
        -- Another item was searched since this lot was read: the server would drop the purchase.
        -- The lot is read again (it goes first), and the next click buys.
        T.prepareBuy(deal.key)
        return false, "buy_recheck"
    end
    F.Engine.message = nil
    local op = {
        key = deal.key,
        kind = deal.kind,
        id = deal.id,
        -- Units bought out against an undercut are resold at the player's price.
        mode = deal.resell and "flip" or deal.mode,
        exit = deal.resell or deal.exit,
        link = deal.link,
        at = clock(),
    }
    if deal.kind == "commodity" then
        op.state, op.qty, op.cost = "quote", deal.qty, deal.cost
        if not pcall(F.AH.quote, deal.id, deal.qty) then
            return false, "error"
        end
    else
        local lot = deal.lots and deal.lots[1]
        if not lot or not lot.auctionID then
            return false, "verify_first"
        end
        op.state, op.qty, op.cost, op.auctionID = "awaiting", 1, lot.unit, lot.auctionID
        op.money = F.Engine.wallet() -- the price leaving the wallet confirms the purchase (T.onMoney)
        if not pcall(F.AH.buyItem, lot.auctionID, lot.unit) then
            return false, "error"
        end
    end
    T.op = op
    F.Engine.changed()
    return true
end

-- COMMODITY_PRICE_UPDATED (unit price, total price).
function T.onQuote(_, total)
    local op = T.op
    if not op or op.state ~= "quote" then
        return
    end
    if U.finite(total) and total <= op.cost then
        op.state, op.cost, op.at = "quoted", total, clock()
        F.Engine.notify("quote_ready")
    else
        pcall(F.AH.cancelQuote)
        T.op = nil
        F.Engine.notify("price_changed")
        F.Deals.verify(op.key)
    end
    F.Engine.changed()
end

function T.onQuoteFailed()
    if T.op and T.op.state == "quote" then
        T.op = nil
        F.Engine.notify("price_changed")
        F.Engine.changed()
    end
end

function T.confirm()
    local op = T.op
    if not op or op.state ~= "quoted" then
        return false
    end
    -- A purchase on a stale quote ends in "Internal auction error" on WoW Forever: ask for a new
    -- quote in the same click instead; the next click confirms it.
    local left = F.AH.quoteRemaining()
    if clock() - op.at > 25 or (left and left < 2) then
        pcall(F.AH.cancelQuote)
        op.state, op.at = "quote", clock()
        if not pcall(F.AH.quote, op.id, op.qty) then
            T.op = nil
            F.Engine.notify("quote_expired")
        else
            F.Engine.notify("requote")
        end
        F.Engine.changed()
        return false
    end
    if not pcall(F.AH.confirm, op.id, op.qty) then
        F.Engine.notify("error")
        return false
    end
    op.state, op.at = "awaiting", clock()
    F.Engine.changed()
    return true
end

function T.cancel()
    local op = T.op
    if op and (op.state == "quote" or op.state == "quoted") then
        pcall(F.AH.cancelQuote)
        T.op = nil
        F.Engine.changed()
    end
end

-- Setting spendLimit (gold): what one auction house visit may spend on deals.
function T.overLimit(cost)
    local limit = tonumber(F.db.settings.spendLimit) or 0
    return limit > 0 and (F.Engine.spent or 0) + (cost or 0) > limit * 10000
end

-- Purchases ForeverFlip booked whose buyer invoice is still to come by mail (T.onBuyerInvoice
-- must not book them again): name (lower case) -> { n = units, at = time }.
local function awaitInvoice(c, name, qty)
    c.awaitMail = type(c.awaitMail) == "table" and c.awaitMail or {}
    local k = string.lower(name or "")
    local w = c.awaitMail[k]
    if type(w) ~= "table" or clock() - (w.at or 0) > 3 * 86400 then
        w = { n = 0 }
    end
    w.n, w.at = w.n + qty, clock()
    c.awaitMail[k] = w
end

function T.awaitBuyerInvoice(name, qty)
    awaitInvoice(char(), name, qty)
end

local function bought(op)
    F.Engine.spent = (F.Engine.spent or 0) + (op.cost or 0)
    local c = char()
    local name = displayName(op.key, op.link)
    awaitInvoice(c, name, op.qty)
    F.Data.addPosition(c, op.key, name, op.qty, op.cost, op.mode, op.exit, clock())
    F.Data.log(c, { at = clock(), kind = "buy", key = op.key, name = name, qty = op.qty, amount = op.cost })
    T.op = nil
    F.Engine.notify("bought")
    F.Shopping.bought(op.key, op.qty)
    -- Gear and items are bought one auction per click: the deal is worked out again from the lots
    -- already read, without the lot just bought, so the next click buys the next lot at once.
    F.Deals.afterPurchase(op)
    -- A resale's price is one step below the lot after the ones it buys: a cheap lot left behind
    -- undercuts it. The player is told to buy the rest (in game: one of two 4-silver gloves bought,
    -- the other then sold below the resale price).
    local rest = op.mode == "flip" and op.kind ~= "commodity" and F.Deals.get(op.key)
    if rest and rest.mode == "flip" and type(rest.lots) == "table" and #rest.lots > 0 then
        F.Engine.notify("bought_more")
    end
    F.Engine.changed()
end

local function failed(op, why)
    T.op = nil
    F.Engine.notify(why or "buy_failed")
    F.Deals.verify(op.key)
    F.Engine.changed()
end

function T.onCommodityBought()
    if T.op and T.op.kind == "commodity" and T.op.state == "awaiting" then
        bought(T.op)
    end
end

function T.onCommodityFailed()
    if T.op and T.op.kind == "commodity" and T.op.state == "awaiting" then
        failed(T.op)
    end
end

-- PLAYER_MONEY: the price of an awaited item purchase left the wallet. On WoW Forever the purchase
-- event does not always come, and the chat line "You won an auction" is hidden from addons on newer
-- clients, so the money is the sign that does not fail.
function T.onMoney()
    local op = T.op
    if op and op.kind ~= "commodity" and op.state == "awaiting" and op.money then
        if F.Engine.wallet() <= op.money - (op.cost or 0) then
            bought(op)
        end
        return
    end
    local late = T.late
    if late and clock() <= late.untilAt and F.Engine.wallet() <= late.op.money - (late.op.cost or 0) then
        -- The purchase reported as not gone through was taken after all.
        T.late = nil
        bought(late.op)
        F.Engine.notify("bought_late")
    elseif late and clock() > late.untilAt then
        T.late = nil
    end
end

function T.onItemBought(auctionID)
    local op = T.op
    if op and op.kind ~= "commodity" and op.state == "awaiting" and (not auctionID or auctionID == op.auctionID) then
        bought(op)
    end
end

function T.onError()
    local op = T.op
    if op and op.state == "awaiting" and op.kind ~= "commodity" then
        -- AUCTION_HOUSE_SHOW_ERROR has no auction ID and may belong to another action. It can
        -- also precede the successful purchase's money/event/chat update. Keep the operation
        -- awaiting confirmation (and block a second Buy) until success or the normal timeout.
        -- The wallet may already have changed before PLAYER_MONEY is dispatched.
        T.onMoney()
        F.Engine.changed()
    end
end

-- "You won an auction for X" (also printed when the purchase event never comes).
function T.onChat(msg)
    if F.Util.secret(msg) or type(msg) ~= "string" then
        return
    end
    local won = type(ERR_AUCTION_WON_S) == "string" and ERR_AUCTION_WON_S:gsub("%%s", "\1")
    if won then
        local pattern = "^" .. won:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0"):gsub("\1", "(.+)") .. "$"
        local name = msg:match(pattern)
        local op = T.op
        if name and not (op and op.state == "awaiting") then
            F.Bids.won((name:gsub("%s*%(x%d+%)%s*$", "")))
        end
        if name and op and op.state == "awaiting" then
            local count = tonumber(name:match("%(x(%d+)%)%s*$"))
            name = name:gsub("%s*%(x%d+%)%s*$", "")
            if string.lower(name) == string.lower(displayName(op.key, op.link)) and (not count or count == op.qty) then
                bought(op)
            end
        end
    end
    local sold = type(ERR_AUCTION_SOLD_S) == "string" and ERR_AUCTION_SOLD_S:gsub("%%s", "\1")
    if sold then
        local pattern = "^" .. sold:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0"):gsub("\1", "(.+)") .. "$"
        if msg:match(pattern) then
            T.ownedDue = 0
        end
    end
end

-- A purchase without any answer for 30 seconds is kept as unknown; the player settles it in the
-- journal (the chat line "You won an auction" tells).
function T.step()
    T.stepVendor()
    local op = T.op
    if op and op.state == "awaiting" and op.money and clock() - op.at > 30 then
        -- No money spent in 30 seconds: reported, and the deal is checked again. The server can
        -- still take it later (seen in game: the money left after the report), so the wallet is
        -- watched 3 more minutes and a late purchase is booked then (T.onMoney).
        T.late = { op = op, untilAt = clock() + 180 }
        failed(op, "buy_no_answer")
    elseif op and op.state == "awaiting" and clock() - op.at > 30 then
        local c = char()
        c.unknown = c.unknown or {}
        c.unknown[#c.unknown + 1] = {
            at = op.at,
            key = op.key,
            name = displayName(op.key, op.link),
            qty = op.qty,
            cost = op.cost,
            mode = op.mode,
            exit = op.exit,
        }
        T.op = nil
        F.Engine.notify("buy_unknown")
        F.Engine.changed()
    elseif op and op.state == "quote" and clock() - op.at > 15 then
        T.op = nil
        F.Engine.notify("price_changed")
        F.Engine.changed()
    elseif op and op.state == "quoted" and clock() - op.at > 60 then
        pcall(F.AH.cancelQuote)
        T.op = nil
        F.Engine.notify("quote_expired")
        F.Engine.changed()
    end
    local l = T.lastPost
    if l and #l.ids == 0 and clock() - l.at > 10 then
        T.lastPost = nil
        F.Engine.notify("post_unconfirmed")
        F.Engine.changed()
    end
    T.posting = T.postingNow()
    T.stepChecks()
    if
        F.AH.isOpen()
        and clock() >= (T.ownedDue or 0)
        and not F.Deals.searching()
        and not F.Deals.pending()
        and not F.Scan.blocking()
        and not T.busy()
        and not F.Deals.buyHolding()
        and F.AH.ready()
    then
        T.ownedDue = clock() + 60
        pcall(F.AH.queryOwned)
    end
end

function T.settle(index, wasBought)
    local c = char()
    local u = c.unknown and c.unknown[index]
    if not u then
        return
    end
    table.remove(c.unknown, index)
    if wasBought then
        F.Engine.spent = (F.Engine.spent or 0) + u.cost
        awaitInvoice(c, u.name, u.qty)
        F.Data.addPosition(c, u.key, u.name, u.qty, u.cost, u.mode, u.exit, clock())
        F.Data.log(c, { at = clock(), kind = "buy", key = u.key, name = u.name, qty = u.qty, amount = u.cost })
    end
    F.Engine.changed()
end

-- Selling on the auction house -------------------------------------------------------------------------
-- Price suggestion for a bag item: one legal step below the cheapest listing of another seller,
-- never below the price that returns what the item cost.
T.prices = {} -- key -> { rows, at }

-- A check that got no answer is remembered too: the Sell page then says so instead of asking for
-- a check again.
T.noAnswer = {}
local function rememberPrice(k, rows)
    if rows then
        T.prices[k] = { rows = rows, at = clock() }
        T.noAnswer[k] = nil
    else
        T.noAnswer[k] = clock()
    end
end

-- A full scan read in the last 5 minutes stands for a price search of an item to post: its other
-- sellers' lots are what the search would return (one search per item, gear by name and then
-- version by version, took minutes in game). Not for an item the player has listed: the scan may
-- not tell those lots apart. Returns { rows, at, scan = true } or nil.
T.SCAN_ROWS = 10
function T.scanPrice(key)
    local last = F.Scan.last
    if not last or type(last.groups) ~= "table" or last.partial or last.scope ~= F.Engine.scope() then
        return nil
    end
    if clock() - (last.at or 0) > 300 then
        last.groups = nil -- too old to stand for a search: the memory is given back
        return nil
    end
    local item = U.parseKey(key)
    if not item then
        return nil
    end
    -- A scan that names the owners leaves the player's own lots out: it prices their items too.
    if not last.ownersKnown then
        for _, o in ipairs(T.owned or {}) do
            if o.id == item.id or (o.itemKey and o.itemKey.itemID == item.id) then
                return nil
            end
        end
    end
    -- An item the scan did not see needs no price either: nobody sells it (T.noSellers).
    local g = last.groups[key]
    if type(g) ~= "table" or type(g.rows) ~= "table" or #g.rows == 0 then
        return nil
    end
    local rows = {}
    for _, r in ipairs(g.rows) do
        rows[#rows + 1] = { unit = r.unit, qty = r.qty }
    end
    table.sort(rows, function(a, b)
        return a.unit < b.unit
    end)
    while #rows > T.SCAN_ROWS do
        rows[#rows] = nil
    end
    return { rows = rows, at = last.at, scan = true }
end

-- The cheapest unit of a check up to 5 minutes old (Check price, Check all), nil without one.
function T.freshCheapest(key)
    local check = key and T.prices[key]
    if check and clock() - check.at <= 300 and check.rows[1] then
        return check.rows[1].unit
    end
end

function T.checkPrice(key, callback, fast)
    if not callback and not fast then
        return F.Deals.enqueue(key, rememberPrice, rememberPrice, fast)
    end
    return F.Deals.enqueue(key, function(k, rows, complete)
        -- The search is sorted by price: its first pages hold the cheapest lots, which is all a
        -- price needs, also when an item has more lots than the pages read.
        if not fast or complete or (rows and #rows > 0) then
            rememberPrice(k, rows)
        end
        if callback then
            callback(k, rows, complete)
        end
    end, callback or rememberPrice, fast)
end

-- Posting rules -------------------------------------------------------------------------------------
-- Per item (F.db.rules[key]): min = never post below, normal = price when nobody else sells or the
-- others ask too much, max = above it the cheapest other seller is ignored, keep = units that stay
-- in the bags. Settings give the defaults: undercut (one legal step or a percent), a minimum and a
-- maximum as a percent of the usual price, and what to do below the minimum (hold or post at it).
function T.rule(key)
    local r = F.db.rules and F.db.rules[key]
    return type(r) == "table" and r or nil
end

function T.setRule(key, rule)
    F.db.rules = F.db.rules or {}
    local clean = {}
    for _, field in ipairs({ "min", "normal", "max", "keep" }) do
        local v = rule and rule[field]
        if U.finite(v) and v > 0 then
            clean[field] = math.floor(v)
        end
    end
    F.db.rules[key] = next(clean) and clean or nil
    F.Engine.changed()
end

function T.undercut(price, kind)
    local step = U.below(price, kind)
    local share = F.db.settings.undercutPercent or 0
    if share > 0 then
        return math.min(step, U.stepDown(price * (1 - share), kind))
    end
    return step
end

local function usualOf(key)
    local h = F.Data.market(F.db, F.Engine.scope()).history[key]
    return M.usual(h), h
end

-- Lowest price a post of `item` may use: break-even of the stock, the rule's minimum, the minimum
-- percent of the usual price.
function T.floorFor(item)
    local s = F.db.settings
    local position = char().positions[item.key]
    local floor = position and position.qty > 0 and M.breakEven(position.cost / position.qty, 1, item.kind) or nil
    local rule = T.rule(item.key)
    if rule and rule.min then
        floor = math.max(floor or 0, rule.min)
    end
    local usual = usualOf(item.key)
    if usual and (s.minPricePercent or 0) > 0 then
        floor = math.max(floor or 0, U.stepUp(usual * s.minPricePercent, item.kind))
    end
    return floor
end

-- Price of an item nobody sells and ForeverFlip has no market price for, with its source:
-- "last" = the player's last post of it, "aux" = auxForever's usual price, then two guesses:
-- "cost" = the stock's break-even plus 25%, "vendor" = 1.5 x the vendor price (the game's own
-- default). Guesses are only suggestions: the posting queues never use them.
T.GUESSES = { cost = true, vendor = true }
function T.fallbackPrice(item)
    local last = F.db.lastPosted and F.db.lastPosted[item.key]
    if U.finite(last) and last > 0 then
        return last, "last"
    end
    local aux = F.Engine.auxPrice and F.Engine.auxPrice(item.id)
    if aux then
        return aux, "aux"
    end
    local position = char().positions[item.key]
    if position and position.qty > 0 then
        return math.floor(M.breakEven(position.cost / position.qty, 1, item.kind) * 1.25), "cost"
    end
    local vendor = F.AH.vendorPrice(item.id)
    if vendor then
        return math.floor(vendor * 1.5), "vendor"
    end
end

-- Suggested price: below the cheapest other seller (by the undercut setting); the normal price when
-- nobody else sells or the cheapest asks more than the maximum; else a fallback price.
-- Returns price, floor, cheapest, why ("undercut", "normal", "last", "aux", "cost", "vendor").
-- Nobody else sells the item for sure: the last check found no lot, or the server did not answer
-- the check of an item the last full scan did not see, or a recent full scan did not see it at all.
-- On WoW Forever an exact search for an item without any lot gets no answer.
function T.noSellers(key)
    local check = T.prices[key]
    if check and clock() - check.at <= 300 then
        return #check.rows == 0
    end
    local silent = T.noAnswer[key] and clock() - T.noAnswer[key] <= 300
    return F.Scan.notListed(key) or (silent and not (F.Scan.last and F.Scan.last.listed and F.Scan.last.listed[key]))
end

function T.suggest(item)
    local check = T.prices[item.key]
    local floor = T.floorFor(item)
    if not check or clock() - check.at > 300 then
        if not T.noSellers(item.key) then
            return nil, floor, nil
        end
        check = { rows = {}, at = clock() }
    end
    local s = F.db.settings
    local rule = T.rule(item.key) or {}
    local usual = usualOf(item.key)
    local normal = rule.normal or usual
    local cap = rule.max or (normal and (s.maxPricePercent or 0) > 0 and normal * s.maxPricePercent) or nil
    local cheapest = check.rows[1] and check.rows[1].unit
    local price, why
    if cheapest and not (cap and cheapest > cap and normal) then
        price, why = T.undercut(cheapest, item.kind), "undercut"
    elseif normal then
        price, why = U.stepDown(normal, item.kind), "normal"
    else
        local fallback, source = T.fallbackPrice(item)
        if fallback then
            price, why = U.stepDown(fallback, item.kind), source
        end
    end
    if price and price < (item.kind == "commodity" and 1 or 100) then
        price = item.kind == "commodity" and 1 or 100
    end
    return price, floor, cheapest, why
end

-- One price for an item, the same on every page (the tooltip, the Sell page, its Best column):
--   post      price each to post at: one step below the cheapest other seller (T.suggest) from a
--             check or full scan up to 5 minutes old; without one, an estimate from the usual
--             price (why = "estimate"); never below the floor (break-even, the rule's minimum)
--   net       what one unit brings after the cut and the deposits expected to be lost (F.Market.advice)
--   profit    net - what you paid each (stock only)
-- and the vendor price and disenchanting to compare with. Returns a table (see below) or nil when
-- the key is not an item.
function T.quote(key, id)
    local item = U.parseKey(key)
    if not item then
        return nil
    end
    id = id or item.id
    item = { key = key, id = id, kind = item.kind }
    local check = T.prices[key]
    if not (check and clock() - check.at <= 300) then
        local scanned = T.scanPrice(key)
        if scanned then
            T.prices[key] = scanned
        end
    end
    local h = F.Data.market(F.db, F.Engine.scope()).history[key]
    h = type(h) == "table" and h or nil
    local price, floor, cheapest, why = T.suggest(item)
    local live = price ~= nil
    if not price then
        local rule = T.rule(key) or {}
        local normal = rule.normal or M.usual(h)
        if normal then
            price, why = U.stepDown(normal, item.kind), "estimate"
        else
            local fallback, source = T.fallbackPrice(item)
            if fallback then
                price, why = U.stepDown(fallback, item.kind), source
            end
        end
    end
    local q = {
        key = key,
        why = why,
        live = live,
        cheapest = cheapest,
        floor = floor,
        guess = T.GUESSES[why] or false,
    }
    if price and floor and price < floor then
        q.market, q.belowFloor = price, true
        price = U.stepUp(floor, item.kind)
    end
    local position = char().positions[key]
    if position and position.qty > 0 then
        q.cost = position.cost / position.qty
        q.breakEven = M.breakEven(q.cost, 1, item.kind)
    end
    -- A guessed price is only a starting point for the Sell page: it brings no money in any sum.
    local advice = M.advice(id, key, h, not q.guess and price or nil)
    q.post = price
    if advice then
        q.net, q.tries, q.lost, q.perDay = advice.auction, advice.tries, advice.lost, advice.perDay
        q.post = advice.post or q.post
        q.vendor, q.vendorHow, q.disenchant = advice.vendor, advice.vendorHow, advice.disenchant
        q.best, q.value = advice.best, advice.value
    end
    if q.net and q.cost then
        q.profit = q.net - q.cost
    end
    return q
end

-- Posting duration (1 = 2 h, 2 = 8 h, 3 = 24 h). Setting 0 = automatic. A longer post costs a
-- larger deposit, which comes back with the sale and is lost only when the post expires; a post
-- that expires is posted again at the same duration. So each duration costs, per sale, the
-- deposits expected to be lost before it sells:
--   lost(d) = deposit(d) x q / (1 - q),   q = exp(-hours(d) / T)  (the chance it is not sold in time)
-- where T is the hours the lot is expected to take to sell. The cheapest duration wins; when a
-- longer one costs at most T.DURATION_SLACK of the sale more (or the deposits are equal, as with
-- the 1 silver minimum on WoW Forever), the longer one wins: fewer reposts, fewer chances to be
-- undercut while relisting. T comes from
--   * your own sales of the item, once 3 units were sold (days from purchase to sale, per unit), else
--   * the market: the units ahead of yours in the queue (other sellers' lots at or below your
--     price, from a fresh check, else every unit the last scan listed) plus yours, over the units
--     measured bought per day near that price.
-- 24 hours when the sales are not measured, measured from fewer than two pairs of scans, or older
-- than 3 hours. Deposits come from the game (commodities), from the last post of the item at that
-- duration, else from the vendor price at the Classic multiples 1, 2 and 4 (at least 1 silver).
T.DURATION_HOURS = { 2, 8, 24 }
T.DURATION_SLACK = 0.02

function T.expectedHours(key, qty, price)
    qty = qty or 1
    local own = char().stats[key]
    if own and (own.sold or 0) >= 3 and U.finite(own.days) and own.days > 0 then
        return own.days / own.sold * 24 * qty
    end
    local usual, h = usualOf(key)
    local at = price or usual
    if not at or not h then
        return nil
    end
    local s = M.saleability(h, at, clock())
    if not s.known or s.stale or (s.pairs or 0) < 2 or not s.perDay or s.perDay <= 0 then
        return nil
    end
    local ahead = 0
    local check = T.prices[key]
    if check and clock() - check.at <= 300 then
        for _, r in ipairs(check.rows) do
            if r.unit <= at then
                ahead = ahead + (r.qty or 1)
            end
        end
    else
        ahead = U.finite(h.units) and h.units or 0
    end
    return (ahead + qty) / s.perDay * 24
end

-- The deposit of posting `qty` units of `key` for duration `d` (1 to 3).
function T.depositFor(key, qty, d)
    local item = U.parseKey(key)
    if not item then
        return nil
    end
    local fn = F.AH.depositFn(item.id, item.kind, d)
    if fn then
        return fn(qty)
    end
    local base = M.deposit(F.AH.clientVendorPrice(item.id), qty) -- at least 1 silver
    local raw = math.floor((F.AH.clientVendorPrice(item.id) or 0) * 0.15 * qty) * ({ 1, 2, 4 })[d]
    return math.max(base, raw)
end

-- Expected deposits lost per sale for each duration: { [d] = copper }, and the choice.
function T.durationCosts(key, qty, price)
    local hours = T.expectedHours(key, qty, price)
    if not hours then
        return nil, 3
    end
    local costs, best = {}, nil
    for d = 1, 3 do
        local deposit = T.depositFor(key, qty or 1, d) or 0
        local q = math.exp(-T.DURATION_HOURS[d] / math.max(hours, 0.01))
        costs[d] = q >= 0.999 and math.huge or deposit * q / (1 - q)
        if not best or costs[d] < costs[best] then
            best = d
        end
    end
    local slack = math.max(1, T.DURATION_SLACK * (price or 0) * (qty or 1))
    local choice = best
    for d = 3, best + 1, -1 do
        if costs[d] <= costs[best] + slack then
            choice = d
            break
        end
    end
    return costs, choice, hours
end

function T.durationFor(key, qty, price)
    local d = F.db and F.db.settings.duration
    if d == 1 or d == 2 or d == 3 then
        return d
    end
    if not key then
        return 3
    end
    local _, choice = T.durationCosts(key, qty, price)
    return choice
end

function T.post(item, qty, price, duration)
    if T.postingNow() or not F.AH.isOpen() then
        return false, "busy"
    end
    -- Like a purchase, a post waits for a search in flight and for the server (T.wayFree).
    if not T.wayFree() then
        return false, "post_busy"
    end
    if not U.finite(qty) or qty < 1 or qty > F.AH.postCount(item) or not U.finite(price) or price < 1 then
        return false, "values"
    end
    if item.kind ~= "commodity" then
        price = U.stepDown(price, item.kind)
        if price < 100 then
            return false, "values"
        end
    end
    local confirm = T.pendingPost
        and T.pendingPost.key == item.key
        and T.pendingPost.bag == item.bag
        and T.pendingPost.slot == item.slot
        and T.pendingPost.price == price
        and T.pendingPost.qty == qty
        and T.pendingPost.duration == duration
    T.lastItem = { key = item.key, bag = item.bag, slot = item.slot, price = price, qty = qty, duration = duration }
    F.db.lastPosted = F.db.lastPosted or {}
    F.db.lastPosted[item.key] = price
    F.AH.learnDeposit(item, duration)
    local ok, needs = pcall(F.AH.post, item, qty, price, duration, confirm)
    if not ok then
        T.pendingPost = nil
        return false, "error"
    end
    if needs and not confirm then
        T.pendingPost = T.lastItem
        return true, "confirm"
    end
    T.pendingPost = nil
    -- Booked when the game reports the created auction (AUCTION_HOUSE_AUCTION_CREATED).
    T.lastPost = {
        key = item.key,
        name = displayName(item.key, item.link),
        qty = qty,
        price = price,
        at = clock(),
        ids = {},
        open = qty,
        auctions = item.kind == "commodity" and 1 or qty,
    }
    T.ownedDue = clock() + 3
    F.Engine.changed()
    -- "Auction created" only when the game reports it (T.onAuctionCreated).
    return true, "post_sent"
end

-- AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED right after a post: the server threw it away.
function T.onDropped()
    local op = T.op
    if op and op.state == "awaiting" and clock() - op.at <= 3 then
        T.op = nil
        F.Engine.notify("buy_dropped")
        F.Deals.verify(op.key)
        F.Engine.changed()
        return
    end
    local l = T.lastPost
    if l and #l.ids == 0 and clock() - l.at <= 3 then
        T.lastPost = nil
        F.Engine.notify("post_dropped")
        F.Engine.changed()
    end
end

-- The game asks to confirm a post (price far from the market, etc.): the next Post click confirms.
function T.onPostWarning()
    local l = T.lastPost
    if l and clock() - l.at < 10 and #l.ids == 0 then
        T.lastPost = nil
        T.pendingPost = T.lastItem
        F.Engine.notify("confirm")
    end
end

function T.onAuctionCreated(auctionID)
    local l = T.lastPost
    if not l or clock() - l.at > 30 then
        return
    end
    if #l.ids == 0 then
        local c = char()
        c.listings[#c.listings + 1] = l
        F.Engine.notify("posted")
    end
    l.ids[#l.ids + 1] = auctionID
    if #l.ids >= l.auctions then
        T.lastPost = nil
    end
    F.Engine.changed()
end

-- Own auctions refreshed: auctions marked sold are booked once, with their real quantity and price.
T.owned = {}
function T.onOwned()
    local ok, owned = pcall(F.AH.owned)
    if not ok then
        return
    end
    local unnamed = false
    for _, a in ipairs(owned) do
        a.key = F.AH.keyFor(a.id, a.link)
        unnamed = unnamed or a.key == nil
    end
    T.owned = owned
    -- Read again a few times while the items load (each try asks for their data).
    T.unnamedTries = unnamed and (T.unnamedTries or 0) + 1 or 0
    if unnamed and T.unnamedTries <= 5 then
        T.ownedDue = math.min(T.ownedDue or math.huge, clock() + 3)
    end
    local c = char()
    c.booked = c.booked or {}
    local changed = false
    for _, a in ipairs(owned) do
        if a.sold and not c.booked[a.auctionID] then
            for _, l in ipairs(c.listings) do
                for _, id in ipairs(l.ids) do
                    if id == a.auctionID and l.open > 0 then
                        c.booked[a.auctionID] = clock()
                        local qty = math.min(a.qty, l.open)
                        l.open = l.open - qty
                        -- The invoice of this sale comes later by mail: it must not book it again.
                        l.awaiting = (l.awaiting or 0) + qty
                        local unit = a.price or l.price
                        local gross = a.total and a.total * qty / math.max(a.qty, 1) or unit * qty
                        local net = M.net(gross, 1)
                        local cost = F.Data.sale(c, l.key, l.name, qty, net, clock())
                        F.Data.log(c, {
                            at = clock(),
                            kind = "sell",
                            key = l.key,
                            name = l.name,
                            qty = qty,
                            amount = net,
                            profit = net - cost,
                        })
                        changed = true
                    end
                end
            end
        end
    end
    -- Forget finished listings and old booking marks.
    for i = #c.listings, 1, -1 do
        local l = c.listings[i]
        if clock() - l.at > 3 * 86400 then
            table.remove(c.listings, i)
        end
    end
    for id, at in pairs(c.booked) do
        if clock() - at > 7 * 86400 then
            c.booked[id] = nil
        end
    end
    if changed then
        F.Engine.notify("sold")
        F.Engine.changed()
    end
end

-- Sale invoices and failed posts -----------------------------------------------------------------
-- Sale rate of an item: posts that sold against posts that came back (expired or cancelled).
function T.rate(name)
    local r = name and char().rates and char().rates[string.lower(name)]
    if not r or r.sold + r.failed < 3 then
        return nil, r
    end
    return r.sold / (r.sold + r.failed), r
end

local function rateOf(name)
    local c = char()
    c.rates = c.rates or {}
    local k = string.lower(name)
    c.rates[k] = c.rates[k] or { sold = 0, failed = 0 }
    return c.rates[k]
end

-- The cut of each house is learned from invoices: about 5% on a faction house, 15% on a neutral one.
local function learnCut(inv)
    if inv.bid < 1000 or inv.cut <= 0 then
        return
    end
    local ratio = inv.cut / inv.bid
    local realm = F.Engine.realm()
    local scope = ratio > 0.1 and realm .. "-Neutral"
        or realm .. "-" .. tostring(UnitFactionGroup and UnitFactionGroup("player") or "?")
    F.db.cuts = F.db.cuts or {}
    local old = F.db.cuts[scope]
    F.db.cuts[scope] = U.finite(old) and old + (ratio - old) * 0.2 or ratio
    F.Engine.applyCut()
end

-- "Auction successful": the real money of a sale. Units not booked yet from the own-auction list are
-- booked here, with the exact amount after the cut.
local bookInvoice
function T.onInvoice(inv)
    local c = char()
    local net = inv.bid - inv.cut
    learnCut(inv)
    c.invoices = c.invoices or {}
    table.insert(c.invoices, 1, { at = clock(), item = inv.item, qty = inv.count, net = net, cut = inv.cut })
    while #c.invoices > 200 do
        table.remove(c.invoices)
    end
    bookInvoice(c, inv.item, inv.count, net, clock())
end

-- Invoices saved before the count was read right (qty 0): their sales were never booked, so the
-- stock stayed open and the sale rates counted only failures. Booked once now, the count taken
-- from the listing's price (gold before the cut / price per unit), else 1.
function T.repairInvoices()
    local c = char()
    if c.invoicesRepaired or type(c.invoices) ~= "table" then
        return 0
    end
    c.invoicesRepaired = true
    local fixed = 0
    for i = #c.invoices, 1, -1 do
        local inv = c.invoices[i]
        if type(inv) == "table" and type(inv.item) == "string" and (inv.qty or 0) < 1 and U.finite(inv.net) then
            local bid, count = inv.net + (inv.cut or 0), 1
            local name = string.lower(inv.item)
            for _, l in ipairs(c.listings or {}) do
                if string.lower(l.name or "") == name and U.finite(l.price) and l.price > 0 then
                    count = math.max(1, math.floor(bid / l.price + 0.5))
                    break
                end
            end
            inv.qty = count
            bookInvoice(c, inv.item, count, inv.net, inv.at or clock())
            fixed = fixed + 1
        end
    end
    return fixed
end

function bookInvoice(c, item, count, net, at)
    local inv = { item = item, count = count }
    local r = rateOf(inv.item)
    r.sold = r.sold + inv.count
    local name = string.lower(inv.item)
    -- Units already booked from the owned-auction list (T.onOwned) are only matched here.
    local count = inv.count
    for _, l in ipairs(c.listings) do
        if count > 0 and string.lower(l.name or "") == name and (l.awaiting or 0) > 0 then
            local n = math.min(count, l.awaiting)
            l.awaiting, count = l.awaiting - n, count - n
        end
    end
    if count <= 0 then
        F.Engine.changed()
        return
    end
    local allocations, order = {}, {}
    local function allocate(key, qty)
        if not allocations[key] then
            allocations[key] = 0
            order[#order + 1] = key
        end
        allocations[key] = allocations[key] + qty
        count = count - qty
    end
    for _, l in ipairs(c.listings) do
        if count > 0 and string.lower(l.name or "") == name and l.open > 0 then
            local qty = math.min(count, l.open)
            l.open = l.open - qty
            allocate(l.key, qty)
        end
    end
    -- Remaining units may have been posted outside ForeverFlip, even if an older listing exists.
    for key, p in pairs(c.positions) do
        if count > 0 and string.lower(p.name or "") == name and p.mode ~= "vendor" then
            local qty = math.min(count, math.max(0, p.qty - (allocations[key] or 0)))
            if qty > 0 then
                allocate(key, qty)
            end
        end
    end
    local allocated, distributed = 0, 0
    for _, key in ipairs(order) do
        local qty = allocations[key]
        allocated = allocated + qty
        local cumulative = math.floor(net * allocated / inv.count + 0.5)
        local amount = cumulative - distributed
        distributed = cumulative
        local cost = F.Data.sale(c, key, inv.item, qty, amount, at)
        F.Data.log(c, {
            at = at,
            kind = "sell",
            key = key,
            name = inv.item,
            qty = qty,
            amount = amount,
            profit = amount - cost,
        })
        F.Engine.notify("sold")
    end
    F.Engine.changed()
end

-- A buyer invoice (the mail with an item bought on the auction house). A won bid closes the bid;
-- a purchase ForeverFlip made is only matched; any other purchase (the game's Buy tab, another
-- addon) is booked as stock bought elsewhere ("other": counted, never posted automatically).
function T.onBuyerInvoice(inv, link)
    local c = char()
    local count = math.max(1, inv.count or 1)
    local w = type(c.awaitMail) == "table" and c.awaitMail[string.lower(inv.item)]
    if type(w) == "table" and (w.n or 0) > 0 and clock() - (w.at or 0) <= 3 * 86400 then
        local n = math.min(count, w.n)
        w.n, count = w.n - n, count - n
    end
    if count <= 0 then
        F.Engine.changed()
        return
    end
    if F.Bids.won(inv.item, true) then
        return
    end
    local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
    local key = id and F.AH.keyFor(id, link)
    if not key or (inv.bid or 0) <= 0 then
        return
    end
    local amount = math.floor(inv.bid * count / math.max(1, inv.count or 1) + 0.5)
    F.Data.addPosition(c, key, inv.item, count, amount, "other", nil, clock())
    F.Data.log(c, { at = clock(), kind = "buy", key = key, name = inv.item, qty = count, amount = amount })
    F.Engine.notify("bought_elsewhere")
    F.Engine.changed()
end

-- Something was sold to a merchant without ForeverFlip's button (seen in the buyback list): stock
-- of it is booked as a vendor sale. `each` is what the merchant paid for one.
function T.onVendorSale(key, qty, each)
    local c = char()
    local p = c.positions[key]
    if not p or p.qty <= 0 then
        return false
    end
    qty = math.min(qty, p.qty)
    local amount = each * qty
    local cost = F.Data.sale(c, key, p.name, qty, amount, clock())
    F.Data.log(c, {
        at = clock(),
        kind = "vendor",
        key = key,
        name = p.name,
        qty = qty,
        amount = amount,
        profit = amount - cost,
    })
    F.Engine.changed()
    return true
end

-- "Auction expired" / "Auction cancelled": the post did not sell, and the item comes back. Its
-- listing no longer counts the units as on sale (else Post next bought would skip them until the
-- listing is forgotten); a cancel ForeverFlip made already took them off, and is only matched.
function T.onFailedPost(name, count)
    count = count or 1
    local r = rateOf(name)
    r.failed = r.failed + count
    local c = char()
    local lower, left = string.lower(name or ""), count
    for _, l in ipairs(c.listings) do
        if left > 0 and string.lower(l.name or "") == lower and (l.cancelled or 0) > 0 then
            local n = math.min(left, l.cancelled)
            l.cancelled, left = l.cancelled - n, left - n
        end
    end
    for _, l in ipairs(c.listings) do
        if left > 0 and string.lower(l.name or "") == lower and (l.open or 0) > 0 then
            local n = math.min(left, l.open)
            l.open, left = l.open - n, left - n
        end
    end
    F.Data.log(c, { at = clock(), kind = "expired", name = name, qty = count, amount = 0 })
    F.Engine.changed()
end

-- Bought for resale, still in the bags and not yet listed: oldest purchase first.
function T.toPost()
    local c = char()
    local listed = {}
    for _, l in ipairs(c.listings) do
        listed[l.key] = (listed[l.key] or 0) + l.open
    end
    local out, seen = {}, {}
    for _, b in ipairs(F.AH.bagItems()) do
        local p = c.positions[b.key]
        local own = p and (p.mode == "vendor" or p.mode == "shop" or p.mode == "disenchant" or p.mode == "other")
        if p and not own and not T.hidden(b.key) and p.qty > (listed[b.key] or 0) and not seen[b.key] then
            seen[b.key] = true
            b.position = p
            out[#out + 1] = b
        end
    end
    table.sort(out, function(a, b)
        local x, y = a.position.since or 0, b.position.since or 0
        if x ~= y then
            return x < y
        end
        return a.key < b.key
    end)
    return out
end

-- One click posts the next bought item: one step below the cheapest other seller, never below
-- the break-even price. Without a fresh price the click reads the listings first; the next click
-- posts.
-- One click of a posting queue: the first item that is not held reads its price or is posted.
-- Below the floor an item is posted at the floor, or held (skipped) with the "hold" setting.
T.held = {}
-- Every item of a posting queue without a fresh price is searched at once (one search after
-- another, in the background): the price is read before its turn comes, so each next click posts.
local function readAhead(list)
    for _, item in ipairs(list) do
        local check = T.prices[item.key]
        if not (check and clock() - check.at <= 300) then
            local scanned = T.scanPrice(item.key)
            if scanned then
                T.prices[item.key], check = scanned, scanned
            end
        end
        if
            not T.held[item.key]
            and not (check and clock() - check.at <= 300)
            and not T.noSellers(item.key)
            and not F.Deals.pending(item.key)
        then
            T.checkPrice(item.key, nil, true)
        end
    end
end

-- One click posts the first item of the queue whose price is known; items whose search is still on
-- the way are passed over until their answer comes.
T.readAhead = readAhead

local function postFirst(list, quantity)
    local waiting = false
    for _, item in ipairs(list) do
        if not T.held[item.key] then
            -- Local scan data can price this click immediately; only network read-ahead waits.
            local check = T.prices[item.key]
            if not (check and clock() - check.at <= 300) then
                local scanned = T.scanPrice(item.key)
                if scanned then
                    T.prices[item.key] = scanned
                end
            end
            local price, floor, _, why = T.suggest(item)
            if T.GUESSES[why] then
                price = nil -- a guess needs the player's own look on the Sell page
            end
            local check = T.prices[item.key]
            if not price and not (check and clock() - check.at <= 300) and not T.noSellers(item.key) then
                waiting = true -- its search is on the way (readAhead)
            else
                if price and floor and price < floor then
                    if F.db.settings.belowMin == "hold" then
                        price = nil
                    else
                        price = U.stepUp(floor, item.kind)
                    end
                end
                local qty = price and quantity(item) or 0
                if qty >= 1 then
                    return T.post(item, qty, price, T.durationFor(item.key, qty, price))
                end
                T.held[item.key] = true
            end
        end
    end
    -- A ready item gets this hardware click before any bulk search can occupy the connection.
    readAhead(list)
    if waiting then
        return true, "checking"
    end
    return false, "nothing_to_post"
end

function T.postNext()
    return postFirst(T.toPost(), function(item)
        return math.min(F.AH.postCount(item), item.position.qty)
    end)
end

-- Items the player does not want to sell: hidden from the Sell page and skipped by the posting queues.
local function hiddenList()
    F.db.hiddenSell = type(F.db.hiddenSell) == "table" and F.db.hiddenSell or {}
    return F.db.hiddenSell
end

function T.hide(key, name)
    hiddenList()[key] = name or key
    F.Engine.changed()
end

function T.unhide(key)
    hiddenList()[key] = nil
    F.Engine.changed()
end

function T.hidden(key)
    return F.db ~= nil and key ~= nil and hiddenList()[key] ~= nil
end

-- { key, name } of every hidden item, by name.
function T.hiddenItems()
    local out = {}
    for key, name in pairs(hiddenList()) do
        out[#out + 1] = { key = key, name = name }
    end
    table.sort(out, function(a, b)
        return tostring(a.name) < tostring(b.name)
    end)
    return out
end

-- Where one unit of an item brings the most: "vendor" when a merchant pays at least what the
-- auction house leaves after the cut and the deposits, "auction" when the auction house pays more,
-- "disenchant" when the materials are worth more (a character who can); "unknown" when the auction
-- house has no price for it yet (a guessed price does not count). Returns way, value, quote
-- (T.quote): value is what one unit brings that way (for the auction house: after the cut and
-- the deposits), quote.post the price to post at.
function T.bestWay(key, id)
    local q = T.quote(key, id)
    if not q or not q.best then
        return "unknown", nil, q
    end
    if not q.net or q.guess then
        return "unknown", q.vendor, q
    end
    if q.vendor and q.vendor >= q.net and q.best ~= "disenchant" then
        return "vendor", q.vendor, q
    end
    return q.best, q.value, q
end

-- Every sellable bag item, not only purchases: vendor-deal stock and blocked items are left out,
-- and each item's "keep" rule stays in the bags. With `auctionOnly`, items a merchant pays at least
-- as much for (T.bestWay) are left out too: they are better sold to a vendor.
function T.toPostAll(auctionOnly)
    local positions = char().positions
    local out, seen = {}, {}
    for _, b in ipairs(F.AH.bagItems()) do
        local p = positions[b.key]
        local rule = T.rule(b.key)
        local blocked = F.Shopping and F.Shopping.blocked(b.key)
        if
            not seen[b.key]
            and not T.hidden(b.key)
            and not (p and p.mode == "vendor")
            and not blocked
            and not (rule and rule.keep and rule.keep >= T.bagCount(b.key))
            and not (auctionOnly and T.bestWay(b.key, b.id) == "vendor")
        then
            seen[b.key] = true
            out[#out + 1] = b
        end
    end
    return out
end

function T.bagCount(key)
    local n = 0
    for _, b in ipairs(F.AH.bagItems()) do
        if b.key == key then
            n = n + b.count
        end
    end
    return n
end

function T.postAll(auctionOnly)
    return postFirst(T.toPostAll(auctionOnly), function(item)
        local rule = T.rule(item.key)
        local spare = T.bagCount(item.key) - (rule and rule.keep or 0)
        return math.min(F.AH.postCount(item), spare)
    end)
end

-- Undercut own auctions worth reposting: the repost price would still reach the item's floor.
function T.undercutList()
    local out = {}
    for _, a in ipairs(T.owned or {}) do
        local just = T.cancelled[a.auctionID] and clock() - T.cancelled[a.auctionID] < 30
        local status, cheapest = T.ownedStatus(a)
        if just then
            status = nil
        end
        local item = status == "undercut" and U.parseKey(a.key)
        if item then
            local floor = T.floorFor({ key = a.key, kind = item.kind })
            if not floor or T.undercut(cheapest, item.kind) >= floor then
                out[#out + 1] = a
            end
        end
    end
    return out
end

-- One click cancels the next undercut auction; the item comes back by mail and is posted again
-- from the Sell page (Post next bought / Post all).
function T.cancelNextUndercut()
    local a = T.undercutList()[1]
    if not a then
        return false, "nothing_undercut"
    end
    local ok = T.cancelAuction(a)
    return ok, ok and "cancelled" or "post_busy"
end

-- My auctions: price checks one item after another (one search per second), and cancelling.
function T.checksRemaining()
    local done, total, active = F.Deals.batchProgress("auctions")
    if active then
        return total - done
    end
    local count = 0
    for _ in pairs(T.checkingOwned or {}) do
        count = count + 1
    end
    return count
end

-- Own units on sale of an item.
local ownedSource, ownedCounts
local function ownedUnits(key)
    if ownedSource ~= T.owned then
        ownedSource, ownedCounts = T.owned, {}
        for _, a in ipairs(T.owned or {}) do
            local itemKey = a.key
            if itemKey and not a.sold then
                ownedCounts[itemKey] = (ownedCounts[itemKey] or 0) + (a.qty or 1)
            end
        end
    end
    return ownedCounts and ownedCounts[key] or 0
end

-- True when a recent full scan saw no more units of the item than the player has listed: nobody
-- else sells it. WoW Forever does not answer a search for an item without lots of other players.
function T.alone(key)
    local units = F.Scan.listedUnits(key)
    if units == nil then
        return false
    end
    if F.Scan.last.ownersKnown then
        return units == 0 -- own lots are not in the count: any unit is another seller's
    end
    return units <= ownedUnits(key)
end

function T.checkOwned()
    local remaining = T.checksRemaining()
    if remaining > 0 then
        return remaining
    end
    local seen, queue = {}, {}
    for _, a in ipairs(T.owned) do
        if a.key and not a.sold and not seen[a.key] and not T.alone(a.key) then
            seen[a.key] = true
            queue[#queue + 1] = a.key
        end
    end
    T.checkQueue, T.checkingOwned, T.checkTotal = queue, seen, #queue
    F.Engine.changed()
    return #queue
end

local function rememberOwnedPrice(key, rows)
    rememberPrice(key, rows)
    if T.checkingOwned then
        T.checkingOwned[key] = nil
    end
    F.Engine.changed()
end

function T.stepChecks()
    local q = T.checkQueue
    if q and #q > 0 then
        if F.Deals.enqueue(q[1], rememberOwnedPrice, rememberOwnedPrice, true) then
            table.remove(q, 1)
        end
    end
end

-- Status of one own auction: "sold", "alone" (nobody else sells it), "cheapest", "undercut" (with
-- the cheaper price), "no_answer" or nil (not checked).
function T.ownedStatus(a)
    if a.sold then
        return "sold"
    end
    local check = a.key and T.prices[a.key]
    if (not check or clock() - check.at > 600) and a.key then
        -- A full scan of the last 5 minutes tells it without a search (T.scanPrice).
        local scanned = T.scanPrice(a.key)
        if scanned then
            T.prices[a.key], check = scanned, scanned
        end
    end
    if not check or clock() - check.at > 600 then
        if a.key and T.alone(a.key) then
            return "alone"
        end
        if a.key and T.noAnswer[a.key] and clock() - T.noAnswer[a.key] <= 600 then
            return "no_answer"
        end
        return nil
    end
    local cheapest = check.rows[1] and check.rows[1].unit
    if not cheapest then
        return "alone"
    end
    if a.price and cheapest < a.price then
        return "undercut", cheapest
    end
    return "cheapest", cheapest
end

-- Cancelling loses the deposit (and maybe more: GetCancelCost); the item comes back by mail.
T.cancelled = {}
function T.cancelAuction(a)
    if not a or a.sold or not F.AH.isOpen() then
        return false
    end
    if T.cancelled[a.auctionID] and clock() - T.cancelled[a.auctionID] < 30 then
        return false
    end
    if not T.wayFree() then
        return false
    end
    if not pcall(F.AH.cancel, a.auctionID) then
        return false
    end
    local c = char()
    for _, l in ipairs(c.listings) do
        for _, id in ipairs(l.ids) do
            if id == a.auctionID then
                local n = math.min(l.open, a.qty or 1)
                l.open = l.open - n
                -- The "Auction cancelled" mail comes later: it must not take units off again.
                l.cancelled = (l.cancelled or 0) + n
            end
        end
    end
    T.cancelled[a.auctionID] = clock()
    T.ownedDue = clock() + 2
    F.Engine.notify("cancelled")
    F.Engine.changed()
    return true
end

-- Anti-undercut ------------------------------------------------------------------------------------
-- When another seller lists an item cheaper than the player's auction, every way out is priced and
-- the player chooses. Each option's value is its expected money, from the item's measured sales.
--
-- Sales. Buyers take the cheapest lots first. The units sold in t hours at or above a price p are
-- counted from the lot-tracked full scans: n units in h hours watched. The rate is not taken as
-- known: with few sales it is uncertain, so it is a Gamma(n + 1/2, (h + M.PRIOR_HOURS) / 24 days)
-- belief, and the units sold in t hours follow the matching negative binomial (T.saleChances). Four
-- units in one hour no longer read as a sure 22 a day: the chances stay wide until more is seen.
-- A lot behind k units (other sellers' cheaper lots, the player's own cheaper lots, then its own)
-- sells u units: E[min(max(N - k, 0), qty)], so a stack sells in part (T.expectedSold). The buyers
-- who reach a lot must accept its price: the demand is measured at the lot's own price.
--
-- Deposits come back with a sale and are lost on expiry or cancel. Unsold units come back by mail
-- and are worth what posting them again brings (F.Trade.quote), at least a merchant's price.
--
-- Rival undercutters. A seller who answers each undercut makes a single step down last only until
-- the answer. The answer rate c per hour is the item's undercuts seen between full scans
-- (M.undercutRate) or the player's own answers in the last day / 24, the higher. A lot first in line
-- stays first for E[min(T, t)] = (1 - e^(-ct)) / c hours; after an answer the rest waits behind the
-- rival's new lot.
--   wait     keep the auction until it ends;
--   undercut cancel (deposit lost, and the game may charge more) and post one step below the cheaper
--            seller (T.undercut) for the duration the item needs;
--   buyout   buy the cheaper units (shopping list) so yours is first again; sell them at your price;
--   raise    buy every other seller's lot below a higher target (the next seller above yours less
--            a step, at most the price sales reach, M.saleCap), cancel yours and post all at the
--            target: a shelf cleared of cheap lots sells at the price buyers pay;
--   vendor   cancel and sell to a merchant.
-- Not offered: undercut below the item's floor; buyout and raise when the units cost more than
-- the money one deal may use or are more than T.BUYOUT_UNITS. Without measured sales the chances
-- are not known: wait and buyout are not priced, raise is not offered, and the advice is to wait.
T.WAR_ROUNDS = 3
T.WAR_RATE = 1 / 4 -- an answer every 4 hours or sooner: a price war
T.BUYOUT_UNITS = 50
local HOURS = { 2, 8, 24 }

local function fights()
    F.db.fights = type(F.db.fights) == "table" and F.db.fights or {}
    return F.db.fights
end

-- Times the player answered an undercut of the item in the last day.
function T.rounds(key)
    local list = fights()[key]
    local n, now = 0, clock()
    for _, at in ipairs(type(list) == "table" and list or {}) do
        if now - at <= 86400 then
            n = n + 1
        end
    end
    return n
end

-- P(N >= k) for N ~ Poisson(m); a normal approximation for large numbers.
local function erf(x)
    local sign = x < 0 and -1 or 1
    x = math.abs(x)
    local t = 1 / (1 + 0.3275911 * x)
    local y = 1
        - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592)
            * t
            * math.exp(-x * x)
    return sign * y
end

function T.atLeast(k, m)
    if k <= 0 then
        return 1
    end
    if not U.finite(m) or m <= 0 then
        return 0
    end
    if k > 150 or m > 150 then
        local z = (k - 0.5 - m) / math.sqrt(m)
        return math.max(0, math.min(1, 1 - 0.5 * (1 + erf(z / math.sqrt(2)))))
    end
    local term, below = math.exp(-m), 0
    for i = 0, k - 1 do
        below = below + term
        term = term * m / (i + 1)
    end
    return math.max(0, math.min(1, 1 - below))
end

-- Chances of the units sold in `t` hours when n units sold in h hours watched (T.saleChances):
-- the negative binomial of a Gamma(n + 1/2, (h + M.PRIOR_HOURS) / 24) rate. Returns tail(k) =
-- P(N >= k); a normal approximation beyond T.CHANCE_TERMS units.
T.CHANCE_TERMS = 2000
function T.saleChances(sold, hours, t)
    local shape = math.max(0, U.finite(sold) and sold or 0) + 0.5
    local exposure = (math.max(0, U.finite(hours) and hours or 0) + M.PRIOR_HOURS) / 24
    local days = math.max(0, U.finite(t) and t or 0) / 24
    if days <= 0 then
        return function(k)
            return k <= 0 and 1 or 0
        end
    end
    local p = exposure / (exposure + days) -- the chance of "no sale" in each step of the mixture
    local mean = shape * (1 - p) / p
    local sd = math.sqrt(mean / p)
    local tails = { [0] = 1 }
    local term = p ^ shape -- P(N = 0)
    local below, n = 0, 0
    return function(k)
        if k <= 0 then
            return 1
        end
        if k > T.CHANCE_TERMS then
            local z = (k - 0.5 - mean) / math.max(sd, 1e-9)
            return math.max(0, math.min(1, 1 - 0.5 * (1 + erf(z / math.sqrt(2)))))
        end
        while n < k do
            below = below + term
            term = term * (n + shape) / (n + 1) * (1 - p)
            n = n + 1
            tails[n] = math.max(0, math.min(1, 1 - below))
        end
        return tails[k]
    end
end

-- Expected units of a lot of `qty` sold behind `ahead` units, with tail(k) = P(N >= k):
-- sum over j = 1..qty of P(N >= ahead + j).
function T.expectedSold(tail, ahead, qty)
    local units = 0
    for j = 1, math.max(0, qty or 0) do
        local p = tail(ahead + j)
        units = units + p
        if p < 1e-6 then
            break
        end
    end
    return units
end

-- The answer rate of rival sellers per hour (see the comment above) and where it comes from.
function T.answerRate(key, h)
    local own = T.rounds(key) / 24
    local seen = M.undercutRate(h)
    local scans = seen and seen.perHour or 0
    return math.max(own, scans), seen
end

-- Units of a lot first in line at `price` sold in `t` hours when rivals answer at c per hour:
-- first for E[min(T, t)], then behind the rival's new lot of `rivalQty` for the rest.
local function soldUnderFire(d, ahead, qty, t, c, rivalQty)
    local first = c > 0 and (1 - math.exp(-c * t)) / c or t
    local early = T.expectedSold(T.saleChances(d.sold, d.hours, first), ahead, qty)
    local rest = math.floor(qty - early + 0.5)
    if c <= 0 or rest <= 0 or t - first <= 0 then
        return early
    end
    local late = T.expectedSold(T.saleChances(d.sold, d.hours, t - first), ahead + rivalQty, rest)
    -- The answer comes in only part of the cases: the rest of the time the lot stays first.
    local answered = 1 - math.exp(-c * t)
    local stayed = T.expectedSold(T.saleChances(d.sold, d.hours, t), ahead, qty)
    return math.min(qty, (1 - answered) * stayed + answered * (early + late))
end

function T.fightPlan(a)
    if not a or a.sold or not a.key then
        return nil
    end
    local status, cheapest = T.ownedStatus(a)
    if status ~= "undercut" or not cheapest then
        return nil
    end
    local item = U.parseKey(a.key)
    if not item then
        return nil
    end
    local qty, price = a.qty or 1, a.price or 0
    local check = T.prices[a.key]
    local rows = check and check.rows or {}
    local ahead, buyCost = 0, 0
    local wall -- the cheapest other seller above the player's price
    for _, r in ipairs(rows) do
        if r.unit < price then
            ahead = ahead + (r.qty or 1)
            buyCost = buyCost + r.unit * (r.qty or 1)
        elseif r.unit > price and (not wall or r.unit < wall) then
            wall = r.unit
        end
    end
    -- The player's own lots of the item that buyers reach first.
    local ownAhead = 0
    for _, o in ipairs(T.owned or {}) do
        if
            o ~= a
            and not o.sold
            and o.key == a.key
            and (o.price or 0) > 0
            and (o.price < price or (o.price == price and (o.auctionID or 0) < (a.auctionID or 0)))
        then
            ownAhead = ownAhead + (o.qty or 1)
        end
    end
    local rivalQty = rows[1] and rows[1].qty or 1
    local new = T.undercut(cheapest, item.kind)
    local floor = T.floorFor({ key = a.key, kind = item.kind })
    local vendorPrice = F.AH.clientVendorPrice(item.id)
    local function depositFor(units)
        local per = M.deposit(vendorPrice, item.kind == "commodity" and units or 1)
        return item.kind == "commodity" and per or per * units
    end
    local deposit = depositFor(qty)
    local okCost, extra = pcall(F.AH.cancelCost, a.auctionID)
    local cancel = deposit + (okCost and U.finite(extra) and extra or 0)
    local vendor = (F.AH.vendorPrice(item.id, true) or 0)
    -- An unsold unit comes back: worth posting again (the quote), at least a merchant's price.
    local again = 0
    local okQuote, q = pcall(T.quote, a.key, item.id)
    if okQuote and type(q) == "table" and U.finite(q.value) then
        again = q.value
    end
    local fallback = math.max(vendor, again)
    local h = F.Data.market(F.db, F.Engine.scope()).history[a.key]
    h = type(h) == "table" and h or nil
    local d = M.demandAt(h, price)
    local known = (d.pairs or 0) > 0
    local c, seen = T.answerRate(a.key, h)
    local left = (a.timeLeft or 0) / 3600
    local plan = {
        auction = a,
        key = a.key,
        new = new,
        cheapest = cheapest,
        ahead = ahead,
        ownAhead = ownAhead,
        floor = floor,
        cancel = cancel,
        fallback = fallback,
        rate = known and d.perDay or nil,
        sold = d.sold,
        hours = d.hours,
        thin = known and ((d.sold or 0) < 10 or (d.hours or 0) < 6),
        answers = c * 24,
        cutsSeen = seen and seen.cuts or nil,
        rounds = T.rounds(a.key),
        options = {},
    }
    local function add(o)
        plan.options[#plan.options + 1] = o
        plan[o.id] = o
    end
    -- Money of `units` sold out of `lot` at `at` each: the sale, its deposit back, the rest again.
    local function value(units, lot, at, dep)
        return units * M.net(at, 1) + dep * units / math.max(lot, 1) + (lot - units) * fallback
    end
    -- Wait: behind the cheaper units and own cheaper lots until the auction ends.
    if known then
        local tail = T.saleChances(d.sold, d.hours, left)
        local units = T.expectedSold(tail, ahead + ownAhead, qty)
        add({ id = "wait", p = tail(ahead + ownAhead + qty), units = units, ev = value(units, qty, price, deposit) })
    else
        add({ id = "wait", unknown = true, ev = nil })
    end
    -- Undercut: cancel, then first in line at the new price until a rival answers.
    if floor and new < floor then
        add({ id = "undercut", blocked = "floor" })
    else
        local hours = HOURS[T.durationFor(a.key, qty, new)] or 24
        local newDeposit = depositFor(qty)
        if known then
            local d2 = M.demandAt(h, new)
            d2 = (d2.pairs or 0) > 0 and d2 or d
            local units = soldUnderFire(d2, ownAhead, qty, hours, c, rivalQty)
            local tail = T.saleChances(d2.sold, d2.hours, hours)
            add({
                id = "undercut",
                p = tail(ownAhead + qty),
                units = units,
                answered = 1 - math.exp(-c * hours),
                ev = value(units, qty, new, newDeposit) - newDeposit - cancel,
                hours = hours,
            })
        else
            add({ id = "undercut", ev = M.net(new, qty) - cancel, guess = true, hours = hours })
        end
    end
    -- Buy out the cheaper units: yours is first again, theirs follow at your price for a day.
    local budget = F.Deals.budget()
    if ahead > 0 and ahead <= T.BUYOUT_UNITS and buyCost <= budget then
        if known then
            local mine = soldUnderFire(d, ownAhead, qty, left, c, rivalQty)
            local resell = depositFor(ahead)
            local theirs = soldUnderFire(d, ownAhead + qty, ahead, 24, c, rivalQty)
            add({
                id = "buyout",
                cost = buyCost,
                units = ahead,
                p = T.saleChances(d.sold, d.hours, left)(ownAhead + qty),
                ev = value(mine, qty, price, deposit) + value(theirs, ahead, price, resell) - resell - buyCost,
            })
        else
            add({ id = "buyout", cost = buyCost, units = ahead, unknown = true })
        end
    else
        add({ id = "buyout", blocked = ahead > T.BUYOUT_UNITS and "many" or "money", cost = buyCost, units = ahead })
    end
    -- Raise: clear the shelf below a higher target, then post everything at the target.
    if known then
        local cap = M.saleCap(h)
        local target = wall and U.below(wall, item.kind) or nil
        if cap then
            target = target and math.min(target, cap) or cap
        end
        if target and target > price then
            local units, cost = 0, 0
            for _, r in ipairs(rows) do
                if r.unit < target then
                    units = units + (r.qty or 1)
                    cost = cost + r.unit * (r.qty or 1)
                end
            end
            if units > T.BUYOUT_UNITS or cost > budget then
                add({
                    id = "raise",
                    blocked = units > T.BUYOUT_UNITS and "many" or "money",
                    cost = cost,
                    units = units,
                    target = target,
                })
            else
                local lot = qty + units
                local d3 = M.demandAt(h, target)
                d3 = (d3.pairs or 0) > 0 and d3 or { sold = 0, hours = d.hours }
                local all = depositFor(lot)
                local sold = soldUnderFire(d3, ownAhead, lot, 24, c, rivalQty)
                add({
                    id = "raise",
                    cost = cost,
                    units = units,
                    target = target,
                    expect = sold,
                    p = T.saleChances(d3.sold, d3.hours, 24)(ownAhead + lot),
                    ev = value(sold, lot, target, all) - all - cancel - cost,
                })
            end
        end
    end
    -- Vendor: cancel now and sell to a merchant.
    if vendor > 0 then
        add({ id = "vendor", ev = vendor * qty - cancel })
    end
    local best
    for _, o in ipairs(plan.options) do
        if o.ev and not o.blocked and (not best or o.ev > best.ev) then
            best = o
        end
    end
    -- Without measured sales waiting is not priced: it stays the advice unless a merchant is.
    if not known and best and best.id ~= "vendor" then
        best = plan.wait
    end
    plan.best = best or plan.wait
    plan.verdict = plan.best.id
    plan.war = plan.rounds >= T.WAR_ROUNDS or c >= T.WAR_RATE
    plan.net = plan.best.ev or 0
    return plan
end

-- Plans of every undercut auction: those where acting pays most first.
local ORDER = { undercut = 1, raise = 2, buyout = 3, vendor = 4, wait = 5 }
function T.fightPlans()
    local out = {}
    for _, a in ipairs(T.owned or {}) do
        local just = T.cancelled[a.auctionID] and clock() - T.cancelled[a.auctionID] < 30
        local plan = not just and T.fightPlan(a)
        if plan then
            out[#out + 1] = plan
        end
    end
    table.sort(out, function(x, y)
        if ORDER[x.verdict] ~= ORDER[y.verdict] then
            return ORDER[x.verdict] < ORDER[y.verdict]
        end
        if x.net ~= y.net then
            return x.net > y.net
        end
        return x.auction.auctionID < y.auction.auctionID
    end)
    return out
end

-- Auctions where the advice is to act (undercut or vendor: a click cancels them).
function T.fightCount()
    local n = 0
    for _, plan in ipairs(T.fightPlans()) do
        if plan.verdict == "undercut" or plan.verdict == "vendor" then
            n = n + 1
        end
    end
    return n
end

local function remember(key)
    local list = fights()[key]
    list = type(list) == "table" and list or {}
    local now = clock()
    for i = #list, 1, -1 do
        if now - list[i] > 86400 then
            table.remove(list, i)
        end
    end
    list[#list + 1] = now
    fights()[key] = list
end

-- Carries out an option of a plan. undercut: cancels (the item comes back by mail and is posted
-- again from My items, one step below the cheaper seller). vendor: cancels and marks the item for
-- the merchant's Sell all. buyout: puts the cheaper units on the shopping list (up to one step
-- below your price) and checks them: they are bought from Shopping list, Deals from the list.
-- raise: puts every lot below the target on the shopping list and cancels the auction.
-- wait: nothing changes; the auction is left out of Answer next until the prices change.
function T.fight(plan, id)
    id = id or plan.verdict
    local o = plan[id]
    if not o or o.blocked then
        return false
    end
    if id == "wait" then
        T.waiting = T.waiting or {}
        T.waiting[plan.auction.auctionID] = plan.cheapest
        F.Engine.changed()
        return true
    end
    if id == "buyout" then
        local item = U.parseKey(plan.key)
        local max = U.below(plan.auction.price or 0, item and item.kind)
        if not F.Shopping.add(plan.key, max, o.units, U.linkName(plan.auction.link), plan.auction.price) then
            return false
        end
        F.Deals.verify(plan.key)
        return true
    end
    if id == "raise" then
        -- The lots below the target go on the shopping list, then yours is cancelled: once they are
        -- bought, the cheapest other seller is the wall and posting again lands just below it.
        local item = U.parseKey(plan.key)
        local max = U.below(o.target, item and item.kind)
        if not F.Shopping.add(plan.key, max, o.units, U.linkName(plan.auction.link), o.target) then
            return false
        end
        if not T.cancelAuction(plan.auction) then
            return false
        end
        remember(plan.key)
        F.Deals.verify(plan.key)
        return true
    end
    if not T.cancelAuction(plan.auction) then
        return false
    end
    remember(plan.key)
    if id == "vendor" then
        F.db.toVendor = type(F.db.toVendor) == "table" and F.db.toVendor or {}
        F.db.toVendor[plan.key] = clock()
    end
    return true
end

-- One click: the next auction where acting pays (undercut or vendor) is answered.
function T.fightNext()
    for _, plan in ipairs(T.fightPlans()) do
        local waited = T.waiting and T.waiting[plan.auction.auctionID] == plan.cheapest
        if not waited and (plan.verdict == "undercut" or plan.verdict == "vendor") then
            return T.fight(plan), "cancelled"
        end
    end
    return false, "nothing_to_fight"
end

-- After a full scan: a line in the chat when auctions of the player are worth answering.
function T.afterScan()
    local n = T.fightCount()
    if n > 0 and n ~= T.toldFights then
        local L = F.Locale.text
        print(
            "ForeverFlip: "
                .. string.format(L("%d of your auctions were undercut and are worth answering: Selling, Undercuts."), n)
        )
    end
    T.toldFights = n
end

-- Statistics per item: totals, stock and how long it has been held.
function T.itemStats()
    local c = char()
    local out, now = {}, clock()
    for key, s in pairs(c.stats) do
        local p = c.positions[key]
        out[#out + 1] = {
            key = key,
            name = s.name or key,
            bought = s.bought,
            sold = s.sold,
            profit = s.profit,
            rate = (T.rate(s.name)),
            avgDays = s.sold > 0 and s.days / s.sold or nil,
            -- Days to sell only for units bought through ForeverFlip (their purchase time is known).
            days = s.sold > 0 and s.bought > 0 and s.days > 0 and s.days / s.sold or nil,
            stock = p and p.qty or 0,
            stockCost = p and p.cost or 0,
            held = p and p.since and (now - p.since) / 86400 or nil,
            lastSale = s.lastSale,
        }
    end
    for key, p in pairs(c.positions) do
        if not c.stats[key] then
            out[#out + 1] = {
                key = key,
                name = p.name or key,
                bought = p.qty,
                sold = 0,
                profit = 0,
                stock = p.qty,
                stockCost = p.cost,
                held = p.since and (now - p.since) / 86400 or nil,
            }
        end
    end
    for _, s in ipairs(out) do
        -- Stale: in stock for 3 days without a sale since it was bought.
        s.stale = s.stock > 0 and (s.held or 0) > 3 and (not s.lastSale or now - s.lastSale > 3 * 86400)
    end
    table.sort(out, function(a, b)
        if a.stale ~= b.stale then
            return a.stale
        end
        if a.profit ~= b.profit then
            return a.profit > b.profit
        end
        return a.key < b.key
    end)
    return out
end

-- Selling vendor deals at a merchant (one click sells every bag item bought as a vendor deal).
function T.vendorItems()
    local c = char()
    local out = {}
    if not C_Container then
        return out
    end
    for bag = 0, 4 do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                for key, p in pairs(c.positions) do
                    local item = U.parseKey(key)
                    -- Never at a loss: the merchant must pay at least what a unit cost on average.
                    local vendor = item and F.AH.vendorPrice(item.id, true) or 0
                    if
                        p.mode == "vendor"
                        and p.qty > 0
                        and vendor * p.qty >= p.cost
                        and item.id == info.itemID
                        and (item.kind ~= "gear" or string.lower(U.linkName(info.hyperlink) or "") == item.name)
                    then
                        out[#out + 1] = { bag = bag, slot = slot, key = key, count = info.stackCount or 1 }
                        break
                    end
                end
            end
        end
    end
    return out
end

-- Everything to sell at a merchant, stack by stack: vendor-deal stock (never at a loss), and every
-- bag item whose Best is "vendor" (Selling page: a merchant pays at least what the auction house
-- leaves), resale stock included: once its resale no longer pays, the merchant is the better way
-- and the sale closes the position. Left out: hidden items, items with a "keep" rule, and vendor-deal
-- stock a merchant would pay less for than it cost. { bag, slot, key, id, count, price, link },
-- dearest first.
function T.vendorSellList()
    local c = char()
    local out, seen = {}, {}
    for _, v in ipairs(T.vendorItems()) do
        seen[v.bag .. ":" .. v.slot] = true
        local item = U.parseKey(v.key)
        v.id = item and item.id
        v.price = (item and F.AH.vendorPrice(item.id, true) or 0) * v.count
        out[#out + 1] = v
    end
    for _, b in ipairs(F.AH.bagItems()) do
        local p = c.positions[b.key]
        local rule = T.rule(b.key)
        if
            not seen[b.bag .. ":" .. b.slot]
            and not T.hidden(b.key)
            and not (rule and rule.keep)
            and not (p and p.qty > 0 and p.mode == "vendor")
            and not b.locked
            and (T.bestWay(b.key, b.id) == "vendor" or (F.db.toVendor and F.db.toVendor[b.key]))
        then
            local price = F.AH.vendorPrice(b.id, true)
            if price and price > 0 then
                out[#out + 1] = {
                    bag = b.bag,
                    slot = b.slot,
                    key = b.key,
                    id = b.id,
                    count = b.count,
                    link = b.link,
                    price = price * b.count,
                }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.price ~= b.price then
            return a.price > b.price
        end
        return a.key < b.key
    end)
    return out
end

-- Equipment in the bags the class can never use (AH.unusableGear), to sell to a merchant: bound
-- pieces, and pieces the auction house would not pay more for. Hidden items and resale stock stay.
-- { bag, slot, key, id, count, price, link }, dearest first.
function T.unusableGearList()
    local c = char()
    local out = {}
    if not C_Container then
        return out
    end
    for bag = 0, 4 do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if id and not info.isLocked and F.AH.unusableGear(id) then
                local key = F.AH.keyFor(id, info.hyperlink)
                local p = key and c.positions[key]
                local price = F.AH.vendorPrice(id, true)
                local auction = not info.isBound and key and T.bestWay(key, id) == "auction"
                if
                    price
                    and price > 0
                    and not auction
                    and not (key and T.hidden(key))
                    and not (p and p.qty > 0 and p.mode ~= "vendor")
                then
                    local count = info.stackCount or 1
                    out[#out + 1] = {
                        bag = bag,
                        slot = slot,
                        key = key or ("i:" .. id),
                        id = id,
                        count = count,
                        link = info.hyperlink,
                        price = price * count,
                    }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        return a.price > b.price
    end)
    return out
end

function T.sellUnusableGear()
    if not MerchantFrame or not MerchantFrame:IsShown() then
        return 0, 0
    end
    local stacks, money = 0, 0
    for _, v in ipairs(T.unusableGearList()) do
        C_Container.UseContainerItem(v.bag, v.slot)
        stacks, money = stacks + 1, money + v.price
    end
    if stacks > 0 then
        F.Engine.changed()
    end
    return stacks, money
end

-- Sells the whole list (T.vendorSellList) to the open merchant, in paced batches. Selling every
-- stack in one frame lost part of them: the server took 17 of 24 (seen in game), the rest stayed
-- in the bags and was booked as sold anyway. Now T.VENDOR_BATCH stacks go every T.VENDOR_GAP
-- seconds (T.stepVendor), a stack counts as sold only once it left its bag slot, and a stack
-- still there after T.VENDOR_WAIT seconds is sent again (up to 3 tries). Returns the stacks and
-- money of the whole list; the chat line with what really sold comes at the end.
T.VENDOR_BATCH = 6
T.VENDOR_GAP = 0.3
T.VENDOR_WAIT = 2

local function preciseNow()
    return GetTime and GetTime() or clock()
end

local function slotHolds(v)
    local info = C_Container and C_Container.GetContainerItemInfo(v.bag, v.slot)
    return info ~= nil and info.itemID == v.id and (info.stackCount or 1) == v.count
end

-- A stack that left its slot: booked (stock as its sale, the buyback entry only matched).
local function bookVendorSale(job, v)
    local c = char()
    job.sold, job.money = job.sold + 1, job.money + v.price
    if F.db.toVendor then
        F.db.toVendor[v.key] = nil -- marked by the anti-undercut: sold now
    end
    local p = c.positions[v.key]
    if p and p.qty > 0 then
        local name = p.name or v.key
        local cost = F.Data.sale(c, v.key, name, v.count, v.price, clock())
        F.Data.log(c, {
            at = clock(),
            kind = "vendor",
            key = v.key,
            name = name,
            qty = v.count,
            amount = v.price,
            profit = v.price - cost,
        })
    end
end

local function finishVendorJob(job)
    T.vendorJob = nil
    if job.sold > 0 then
        print(
            "ForeverFlip: "
                .. string.format(F.Locale.text("sold %d stacks to the vendor for %s"), job.sold, U.money(job.money))
        )
    end
    if job.failed > 0 then
        print(
            "ForeverFlip: "
                .. string.format(F.Locale.text("%d stacks did not sell: the merchant did not take them"), job.failed)
        )
    end
    F.Engine.changed()
end

-- One step of a vendor sale (every frame, from T.step): sent stacks that left their slot are
-- booked, stuck ones are sent again, and the next batch goes once the gap has passed.
function T.stepVendor()
    local job = T.vendorJob
    if not job then
        return
    end
    if not MerchantFrame or not MerchantFrame:IsShown() then
        -- The merchant was closed: what left the bags is booked, the rest stays unsold.
        for _, v in ipairs(job.sent) do
            if not slotHolds(v) then
                bookVendorSale(job, v)
            elseif v.expected then
                F.Merchant.cancelExpectedSale(v.id, v.count)
            end
        end
        for _, v in ipairs(job.queue) do
            if v.expected then
                F.Merchant.cancelExpectedSale(v.id, v.count)
            end
        end
        job.sent, job.queue = {}, {}
        finishVendorJob(job)
        return
    end
    local t = preciseNow()
    local waiting = {}
    for _, v in ipairs(job.sent) do
        if not slotHolds(v) then
            bookVendorSale(job, v)
        elseif t - v.at < T.VENDOR_WAIT then
            waiting[#waiting + 1] = v
        elseif v.tries < 3 then
            table.insert(job.queue, 1, v) -- not taken: sent again
        else
            if v.expected then
                F.Merchant.cancelExpectedSale(v.id, v.count)
            end
            job.failed = job.failed + 1
        end
    end
    job.sent = waiting
    if #job.queue > 0 and t - (job.last or -10) >= T.VENDOR_GAP then
        job.last = t
        for _ = 1, T.VENDOR_BATCH do
            local v = table.remove(job.queue, 1)
            if not v then
                break
            end
            if slotHolds(v) then
                v.at, v.tries = t, (v.tries or 0) + 1
                if not v.expected then
                    F.Merchant.expectSale(v.id, v.count)
                    v.expected = true
                end
                C_Container.UseContainerItem(v.bag, v.slot)
                job.sent[#job.sent + 1] = v
            end
        end
    end
    if #job.queue == 0 and #job.sent == 0 then
        finishVendorJob(job)
    end
end

function T.sellAllToVendor()
    if not MerchantFrame or not MerchantFrame:IsShown() or T.vendorJob then
        return 0, 0
    end
    local list = T.vendorSellList()
    if #list == 0 then
        return 0, 0
    end
    local money, stacks = 0, #list
    for _, v in ipairs(list) do
        money = money + v.price
    end
    T.vendorJob = { queue = list, sent = {}, sold = 0, money = 0, failed = 0 }
    T.stepVendor() -- the first batch goes with the click
    F.Engine.changed()
    return stacks, money
end

-- True while a vendor sale is under way (the Sell all button waits).
function T.sellingToVendor()
    return T.vendorJob ~= nil
end

-- Summary for the journal.
function T.summary(days)
    local c = char()
    local since = clock() - (days or 7) * 86400
    local s = { spent = 0, earned = 0, profit = 0, sales = 0, buys = 0 }
    for _, e in ipairs(c.journal) do
        if e.at >= since then
            if e.kind == "buy" then
                s.spent, s.buys = s.spent + e.amount, s.buys + 1
            elseif e.kind == "sell" or e.kind == "vendor" then
                s.earned, s.sales = s.earned + e.amount, s.sales + 1
                s.profit = s.profit + (e.profit or 0)
            end
        end
    end
    local held = 0
    for _, p in pairs(c.positions) do
        held = held + p.cost
    end
    s.held = held
    return s
end
