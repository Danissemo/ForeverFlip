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

local function rememberPrice(k, rows)
    if rows then
        T.prices[k] = { rows = rows, at = clock() }
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

function T.suggest(item)
    local check = T.prices[item.key]
    local position = char().positions[item.key]
    local floor = position and position.qty > 0 and M.breakEven(position.cost / position.qty, 1, item.kind) or nil
    if not check or clock() - check.at > 300 then
        return nil, floor, nil
    end
    local cheapest = check.rows[1] and check.rows[1].unit
    local price
    if cheapest then
        price = U.below(cheapest, item.kind)
    else
        local h = F.Data.market(F.db, F.Engine.scope()).history[item.key]
        price = h and h.scan and h.scan.market and U.stepDown(h.scan.market, item.kind) or nil
    end
    if price and price < (item.kind == "commodity" and 1 or 100) then
        price = item.kind == "commodity" and 1 or 100
    end
    return price, floor, cheapest
end

-- Posting duration (1 = 2 h, 2 = 8 h, 3 = 24 h) from the setting.
function T.durationFor()
    local d = F.db and F.db.settings.duration
    return (d == 1 or d == 2 or d == 3) and d or 3
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
        if p and p.mode ~= "vendor" and p.qty > (listed[b.key] or 0) and not seen[b.key] then
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
function T.postNext()
    local item = T.toPost()[1]
    if not item then
        return false, "nothing_to_post"
    end
    local price, floor = T.suggest(item)
    if not price then
        T.checkPrice(item.key)
        return true, "checking"
    end
    local qty = math.min(item.count, item.position.qty)
    return T.post(item, qty, math.max(price, floor or 0), F.db.settings.duration or 3)
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
