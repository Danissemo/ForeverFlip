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

-- Buying ----------------------------------------------------------------------------------------
-- T.op = { state = "quote" | "quoted" | "awaiting", key, kind, id, qty, cost, unit, auctionID, deal }
function T.canBuy(deal)
    return deal
        and deal.verified
        and clock() - deal.verified <= F.Deals.FRESH
        and not T.busy()
        and not F.Deals.searching()
        and F.AH.isOpen()
end

function T.buy(key)
    local deal = F.Deals.get(key)
    if not T.canBuy(deal) then
        return false, "verify_first"
    end
    if deal.cost > F.Engine.wallet() then
        return false, "no_money"
    end
    local op = {
        key = deal.key,
        kind = deal.kind,
        id = deal.id,
        mode = deal.mode,
        exit = deal.exit,
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
        if not pcall(F.AH.buyItem, lot.auctionID, lot.unit) then
            return false, "error"
        end
    end
    T.op = op
    F.Engine.changed()
    return true
end

function T.onQuote(unit, total)
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

local function bought(op)
    local c = char()
    local name = displayName(op.key, op.link)
    F.Data.addPosition(c, op.key, name, op.qty, op.cost, op.mode, op.exit, clock())
    F.Data.log(c, { at = clock(), kind = "buy", key = op.key, name = name, qty = op.qty, amount = op.cost })
    T.op = nil
    F.Engine.notify("bought")
    -- Gear and items are bought one auction per click: read the listings again for the next one.
    F.Deals.verify(op.key)
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

function T.onItemBought(auctionID)
    local op = T.op
    if op and op.kind ~= "commodity" and op.state == "awaiting" and (not auctionID or auctionID == op.auctionID) then
        bought(op)
    end
end

function T.onError()
    local op = T.op
    if op and op.state == "awaiting" and op.kind ~= "commodity" then
        failed(op)
    end
end

-- "You won an auction for X" (also printed when the purchase event never comes).
function T.onChat(msg)
    if type(msg) ~= "string" then
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
    local op = T.op
    if op and op.state == "awaiting" and clock() - op.at > 30 then
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
    end
    T.stepChecks()
    if
        F.AH.isOpen()
        and clock() >= (T.ownedDue or 0)
        and not F.Deals.searching()
        and not F.Deals.pending()
        and not F.Scan.busy()
        and not T.busy()
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

function T.checkPrice(key, callback, fast)
    if not callback and not fast then
        return F.Deals.enqueue(key, rememberPrice, rememberPrice, fast)
    end
    return F.Deals.enqueue(key, function(k, rows, complete)
        if not fast or complete then
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
    return h and h.scan and U.finite(h.scan.market) and h.scan.market or nil, h
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

-- Posting duration (1 = 2 h, 2 = 8 h, 3 = 24 h). Setting 0 = automatic: the shortest duration that
-- the measured sales of the item fill (a shorter post costs a smaller deposit); 24 h otherwise.
function T.durationFor(key, qty)
    local d = F.db and F.db.settings.duration
    if d == 1 or d == 2 or d == 3 then
        return d
    end
    local usual, h = usualOf(key or "")
    if usual and h then
        local s = M.saleability(h, usual, clock())
        if s.known and s.perDay > 0 then
            local days = (qty or 1) / s.perDay
            if days <= 2 / 24 then
                return 1
            elseif days <= 8 / 24 then
                return 2
            end
        end
    end
    return 3
end

function T.post(item, qty, price, duration)
    if T.posting or not F.AH.isOpen() then
        return false, "busy"
    end
    if not U.finite(qty) or qty < 1 or qty > item.count or not U.finite(price) or price < 1 then
        return false, "values"
    end
    if item.kind ~= "commodity" then
        price = U.stepDown(price, item.kind)
        if price < 100 then
            return false, "values"
        end
    end
    local confirm = T.pendingPost
        and T.pendingPost.bag == item.bag
        and T.pendingPost.slot == item.slot
        and T.pendingPost.price == price
        and T.pendingPost.qty == qty
    T.lastItem = { bag = item.bag, slot = item.slot, price = price, qty = qty }
    F.db.lastPosted = F.db.lastPosted or {}
    F.db.lastPosted[item.key] = price
    F.AH.learnDeposit(item, duration)
    local ok, needs = pcall(F.AH.post, item, qty, price, duration, confirm)
    if not ok then
        T.pendingPost = nil
        return false, "error"
    end
    if needs and not confirm then
        T.pendingPost = { bag = item.bag, slot = item.slot, price = price, qty = qty }
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
    return true, "posted"
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
    for _, a in ipairs(owned) do
        a.key = F.AH.keyFor(a.id, a.link)
    end
    T.owned, T.ownedAt = owned, clock()
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
                        local unit = a.price or l.price
                        local net = M.net(unit, qty)
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
    local realm = tostring(GetRealmName and GetRealmName() or "?")
    local scope = ratio > 0.1 and realm .. "-Neutral"
        or realm .. "-" .. tostring(UnitFactionGroup and UnitFactionGroup("player") or "?")
    F.db.cuts = F.db.cuts or {}
    local old = F.db.cuts[scope]
    F.db.cuts[scope] = U.finite(old) and old + (ratio - old) * 0.2 or ratio
    F.Engine.applyCut()
end

-- "Auction successful": the real money of a sale. Units not booked yet from the own-auction list are
-- booked here, with the exact amount after the cut.
function T.onInvoice(inv)
    local c = char()
    local net = inv.bid - inv.cut
    learnCut(inv)
    local r = rateOf(inv.item)
    r.sold = r.sold + inv.count
    c.invoices = c.invoices or {}
    table.insert(c.invoices, 1, { at = clock(), item = inv.item, qty = inv.count, net = net, cut = inv.cut })
    while #c.invoices > 200 do
        table.remove(c.invoices)
    end
    local name = string.lower(inv.item)
    local listing, known
    for _, l in ipairs(c.listings) do
        if string.lower(l.name or "") == name then
            known = true
            if l.open > 0 then
                listing = l
                break
            end
        end
    end
    local key, qty
    if listing then
        key, qty = listing.key, math.min(inv.count, listing.open)
        listing.open = listing.open - qty
    elseif not known then
        -- Posted outside ForeverFlip (or the listing is older than three days): book against stock.
        for k, p in pairs(c.positions) do
            if string.lower(p.name or "") == name and p.mode ~= "vendor" then
                key, qty = k, math.min(inv.count, p.qty)
                break
            end
        end
    end
    if key and qty and qty > 0 then
        local amount = math.floor(net * qty / inv.count + 0.5)
        local cost = F.Data.sale(c, key, inv.item, qty, amount, clock())
        F.Data.log(c, {
            at = clock(),
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

-- "Auction expired" / "Auction cancelled": the post did not sell.
function T.onFailedPost(name, count)
    local r = rateOf(name)
    r.failed = r.failed + (count or 1)
    F.Data.log(char(), { at = clock(), kind = "expired", name = name, qty = count or 1, amount = 0 })
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
        local own = p and (p.mode == "vendor" or p.mode == "shop" or p.mode == "disenchant")
        if p and not own and p.qty > (listed[b.key] or 0) and not seen[b.key] then
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
local function postFirst(list, quantity)
    for _, item in ipairs(list) do
        if not T.held[item.key] then
            local price, floor, _, why = T.suggest(item)
            if T.GUESSES[why] then
                price = nil -- a guess needs the player's own look on the Sell page
            end
            local check = T.prices[item.key]
            if not price and not (check and clock() - check.at <= 300) and not T.noSellers(item.key) then
                T.checkPrice(item.key)
                return true, "checking"
            end
            if price and floor and price < floor then
                if F.db.settings.belowMin == "hold" then
                    price = nil
                else
                    price = U.stepUp(floor, item.kind)
                end
            end
            if price then
                local qty = quantity(item)
                if qty >= 1 then
                    return T.post(item, qty, price, T.durationFor(item.key, qty))
                end
            end
            T.held[item.key] = true
        end
    end
    return false, "nothing_to_post"
end

function T.postNext()
    return postFirst(T.toPost(), function(item)
        return math.min(item.count, item.position.qty)
    end)
end

-- Every sellable bag item, not only purchases: vendor-deal stock and blocked items are left out,
-- and each item's "keep" rule stays in the bags.
function T.toPostAll()
    local positions = char().positions
    local out, seen = {}, {}
    for _, b in ipairs(F.AH.bagItems()) do
        local p = positions[b.key]
        local rule = T.rule(b.key)
        local blocked = F.Shopping and F.Shopping.blocked(b.key)
        if
            not seen[b.key]
            and not (p and p.mode == "vendor")
            and not blocked
            and not (rule and rule.keep and rule.keep >= T.bagCount(b.key))
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

function T.postAll()
    return postFirst(T.toPostAll(), function(item)
        local rule = T.rule(item.key)
        local spare = T.bagCount(item.key) - (rule and rule.keep or 0)
        return math.min(item.count, spare)
    end)
end

-- Undercut own auctions worth reposting: the repost price would still reach the item's floor.
function T.undercutList()
    local out = {}
    for _, a in ipairs(T.owned or {}) do
        local status, cheapest = T.ownedStatus(a)
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
    return T.cancelAuction(a), "cancelled"
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

function T.checkOwned()
    local remaining = T.checksRemaining()
    if remaining > 0 then
        return remaining
    end
    local seen, queue = {}, {}
    for _, a in ipairs(T.owned) do
        if a.key and not a.sold and not seen[a.key] then
            seen[a.key] = true
            queue[#queue + 1] = a.key
        end
    end
    T.checkQueue, T.checkingOwned = queue, seen
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
        if F.Deals.enqueue(q[1], rememberOwnedPrice) then
            table.remove(q, 1)
        end
    end
end

-- Status of one own auction: "sold", "cheapest", "undercut" (with the cheaper price) or nil.
function T.ownedStatus(a)
    if a.sold then
        return "sold"
    end
    local check = a.key and T.prices[a.key]
    if not check or clock() - check.at > 600 then
        return nil
    end
    local cheapest = check.rows[1] and check.rows[1].unit
    if cheapest and a.price and cheapest < a.price then
        return "undercut", cheapest
    end
    return "cheapest", cheapest
end

-- Cancelling loses the deposit (and maybe more: GetCancelCost); the item comes back by mail.
function T.cancelAuction(a)
    if not a or a.sold or not F.AH.isOpen() then
        return false
    end
    if not pcall(F.AH.cancel, a.auctionID) then
        return false
    end
    local c = char()
    for _, l in ipairs(c.listings) do
        for _, id in ipairs(l.ids) do
            if id == a.auctionID then
                l.open = math.max(0, l.open - (a.qty or 1))
            end
        end
    end
    T.ownedDue = clock() + 2
    F.Engine.notify("cancelled")
    F.Engine.changed()
    return true
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
                    if
                        p.mode == "vendor"
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

function T.sellToVendor()
    local c = char()
    local sold = 0
    for _, v in ipairs(T.vendorItems()) do
        local item = U.parseKey(v.key)
        local price = F.AH.vendorPrice(item.id) or 0
        C_Container.UseContainerItem(v.bag, v.slot)
        local p = c.positions[v.key]
        local name = p and p.name or v.key
        local cost = F.Data.sale(c, v.key, name, v.count, price * v.count, clock())
        F.Data.log(c, {
            at = clock(),
            kind = "vendor",
            key = v.key,
            name = name,
            qty = v.count,
            amount = price * v.count,
            profit = price * v.count - cost,
        })
        sold = sold + 1
    end
    if sold > 0 then
        F.Engine.changed()
    end
    return sold
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
