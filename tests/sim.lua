-- A living auction house for simulations (tests/test_simulation.py). Loaded after mock.lua and the
-- addon. Other players list, buy and let lots expire every tick; the player's own purchases, posts,
-- sales and mail go through the same fake client calls the addon makes.
sim = { processed = 0, nextAuction = 100000, errors = {}, bought = 0, posted = 0, sold = 0, expired = 0 }

-- Deterministic random numbers (the same run for the same seed).
local seed = 1
function sim.seed(s)
    seed = s
end
function sim.rand(a, b)
    seed = (seed * 1103515245 + 12345) % 2147483648
    local r = seed / 2147483648
    if a then
        return a + math.floor(r * (b - a + 1))
    end
    return r
end

-- The goods: commodities, plain items and gear with endings. base = what they usually sell for.
sim.goods = {}
local ENDINGS = { "of the Bear", "of the Eagle", "of the Monkey" }
function sim.setup(nCommodities, nItems, nGear)
    local id = 500
    for i = 1, nCommodities do
        id = id + 1
        local vendor = sim.rand(5, 400)
        addItem(id, "Good " .. i, vendor, "commodity")
        sim.goods[#sim.goods + 1] = { id = id, kind = "commodity", base = vendor * sim.rand(2, 6), vendor = vendor }
    end
    for i = 1, nItems do
        id = id + 1
        local vendor = sim.rand(100, 3000)
        addItem(id, "Thing " .. i, vendor, "item")
        sim.goods[#sim.goods + 1] = { id = id, kind = "item", base = vendor * sim.rand(2, 5), vendor = vendor }
    end
    for i = 1, nGear do
        id = id + 1
        local vendor = sim.rand(200, 5000)
        addItem(id, "Blade " .. i, vendor, "gear")
        sim.goods[#sim.goods + 1] = { id = id, kind = "gear", base = vendor * sim.rand(2, 4), vendor = vendor }
    end
    for bag = 0, 4 do
        bags[bag] = bags[bag] or {}
    end
end

local function nameOf(g)
    if g.kind == "gear" then
        return items[g.id].name .. " " .. ENDINGS[sim.rand(1, #ENDINGS)]
    end
    return items[g.id].name
end

-- Other players list lots around the usual price; now and then one far below it (a deal).
function sim.list(n)
    for _ = 1, n do
        local g = sim.goods[sim.rand(1, #sim.goods)]
        local unit = math.floor(g.base * (0.8 + sim.rand() * 0.6))
        if sim.rand() < 0.04 then
            unit = math.max(1, math.floor(g.vendor * (0.4 + sim.rand() * 0.5))) -- below the vendor price
        elseif sim.rand() < 0.06 then
            unit = math.max(1, math.floor(g.base * 0.35)) -- far below the usual price
        end
        local count = g.kind == "commodity" and sim.rand(1, 20) or 1
        local a = addAuction(g.id, unit, count, "Seller" .. sim.rand(1, 30), nameOf(g))
        a.timeLeft = sim.rand(2, 4)
    end
end

-- Mail for the player.
local addToBags -- below
local function mail(subject, item, bid, count, kind, link_)
    inbox[#inbox + 1] = {
        sender = "Auction House",
        subject = subject,
        money = kind == "seller" and bid or 0,
        items = kind == "buyer" and 1 or 0,
        link = link_,
        invoice = { kind = kind, item = item, bid = bid, count = count, cut = math.floor(bid * 0.05) },
    }
end

-- Buyers take the cheapest units of random items; own lots sold this way become sales by mail.
function sim.buy(n)
    for _ = 1, n do
        local g = sim.goods[sim.rand(1, #sim.goods)]
        local cheapest, at
        for i, a in ipairs(auctions) do
            if a.item == g.id and (not cheapest or a.buyout / a.count < cheapest.buyout / cheapest.count) then
                cheapest, at = a, i
            end
        end
        if cheapest then
            local take = math.min(cheapest.count, sim.rand(1, 5))
            local unit = cheapest.buyout / cheapest.count
            if cheapest.owner == "Me" then
                -- An own lot is bought whole (the game reports a partly sold stack the same way,
                -- as a sold auction of the units bought; keeping it whole keeps the sim simple).
                take = cheapest.count
                for _, o in ipairs(owned) do
                    if o.auctionID == cheapest.id then
                        o.status = 1
                        o.quantity = take
                    end
                end
                mail("Auction successful: " .. cheapest.name, cheapest.name, math.floor(unit * take), take, "seller")
                sim.sold = sim.sold + take
            end
            cheapest.count = cheapest.count - take
            cheapest.buyout = math.floor(unit * cheapest.count)
            if cheapest.count <= 0 then
                table.remove(auctions, at)
            end
        end
    end
end

-- Lots run out of time. The player's own come back by mail ("Auction expired"); the item is put
-- into the bags at once, like a purchase.
function sim.expire()
    for i = #auctions, 1, -1 do
        local a = auctions[i]
        a.timeLeft = (a.timeLeft or 4) - (sim.rand() < 0.3 and 1 or 0)
        if a.timeLeft <= 0 then
            table.remove(auctions, i)
            if a.owner == "Me" then
                for k = #owned, 1, -1 do
                    if owned[k].auctionID == a.id then
                        table.remove(owned, k)
                    end
                end
                addToBags(a.item, a.count, items[a.item].commodity and nil or a.name)
                local subject = AUCTION_EXPIRED_MAIL_SUBJECT:format(a.name .. (a.count > 1 and (" (" .. a.count .. ")") or ""))
                inbox[#inbox + 1] = { sender = "Auction House", subject = subject, money = 0, items = 1 }
                sim.expired = sim.expired + a.count
            end
        end
    end
end

addToBags = function(id, count, name)
    local commodity = items[id].commodity
    for bag = 0, 4 do
        for slot = 1, 16 do
            local it = bags[bag][slot]
            if commodity and it and it.itemID == id then
                it.stackCount = it.stackCount + count
                return true
            end
        end
    end
    for bag = 0, 4 do
        for slot = 1, 16 do
            if not bags[bag][slot] then
                putBag(bag, slot, id, count, name)
                return true
            end
        end
    end
    return false
end

-- Answers what the addon asked the fake client since the last call: purchases and posts.
function sim.serve()
    while sim.processed < #calls do
        sim.processed = sim.processed + 1
        local c = calls[sim.processed]
        if c[1] == "StartCommoditiesPurchase" then
            local id, qty = c[2], c[3]
            local left, total = qty, 0
            local lots = {}
            for _, a in ipairs(auctions) do
                if a.item == id and a.owner ~= "Me" then
                    lots[#lots + 1] = a
                end
            end
            table.sort(lots, function(x, y)
                return x.buyout / x.count < y.buyout / y.count
            end)
            for _, a in ipairs(lots) do
                local take = math.min(left, a.count)
                total, left = total + math.floor(a.buyout / a.count) * take, left - take
                if left == 0 then
                    break
                end
            end
            if left == 0 then
                fire("COMMODITY_PRICE_UPDATED", math.floor(total / qty), total)
            else
                fire("COMMODITY_PRICE_UNAVAILABLE")
            end
        elseif c[1] == "ConfirmCommoditiesPurchase" then
            local id, qty = c[2], c[3]
            local left, total = qty, 0
            for i = #auctions, 1, -1 do
                auctions[i].sortKey = auctions[i].buyout / auctions[i].count
            end
            table.sort(auctions, function(x, y)
                return x.sortKey < y.sortKey
            end)
            for i = #auctions, 1, -1 do
                auctions[i].sortKey = nil
            end
            for i = 1, #auctions do
                local a = auctions[i]
                if left > 0 and a.item == id and a.owner ~= "Me" then
                    local take = math.min(left, a.count)
                    local unit = math.floor(a.buyout / a.count)
                    total, left = total + unit * take, left - take
                    a.count = a.count - take
                    a.buyout = unit * a.count
                end
            end
            for i = #auctions, 1, -1 do
                if auctions[i].count <= 0 then
                    table.remove(auctions, i)
                end
            end
            money = money - total
            addToBags(id, qty)
            sim.bought = sim.bought + qty
            mail("Auction won: " .. items[id].name, items[id].name, total, qty, "buyer", link(id))
            fire("COMMODITY_PURCHASE_SUCCEEDED")
        elseif c[1] == "PlaceBid" then
            local auctionID, price = c[2], c[3]
            for i, a in ipairs(auctions) do
                if a.id == auctionID then
                    table.remove(auctions, i)
                    money = money - price
                    addToBags(a.item, 1, a.name)
                    sim.bought = sim.bought + 1
                    mail("Auction won: " .. a.name, a.name, price, 1, "buyer", link(a.item, a.name))
                    fire("AUCTION_HOUSE_PURCHASE_COMPLETED", auctionID)
                    break
                end
            end
        elseif c[1] == "PostItem" or c[1] == "PostCommodity" or c[1] == "ConfirmPostItem" then
            local loc, qty = c[2], c[4]
            local price = c[1] == "PostCommodity" and c[5] or c[6]
            local it = bags[loc.bag] and bags[loc.bag][loc.slot]
            if it and (c[1] == "PostCommodity" or not postNeedsConfirm or c[1] == "ConfirmPostItem") then
                local name = it.hyperlink and it.hyperlink:match("%[(.-)%]") or items[it.itemID].name
                local id = it.itemID
                it.stackCount = it.stackCount - qty
                if it.stackCount <= 0 then
                    bags[loc.bag][loc.slot] = nil
                end
                local auctionID
                if c[1] == "PostCommodity" then
                    local a = addAuction(id, price, qty, "Me", name)
                    a.timeLeft = 2
                    auctionID = a.id
                    owned[#owned + 1] =
                        { auctionID = a.id, itemKey = { itemID = id }, quantity = qty, buyoutAmount = price, status = 0 }
                else
                    for _ = 1, qty do
                        local a = addAuction(id, price, 1, "Me", name)
                        a.timeLeft = 2
                        auctionID = auctionID or a.id
                        owned[#owned + 1] =
                            { auctionID = a.id, itemKey = { itemID = id }, quantity = 1, buyoutAmount = price, status = 0 }
                    end
                end
                sim.posted = sim.posted + qty
                fire("AUCTION_HOUSE_AUCTION_CREATED", auctionID)
            end
        end
    end
end

-- Lets the addon run for `seconds`, answering every query it sends like the server would.
function sim.play(seconds)
    for _ = 1, math.floor(seconds / 0.1) do
        run(0.1)
        if browsePendingNow and browsePendingNow() then
            browseAnswer()
        end
        if ForeverFlip.Deals.search then
            answer()
        end
        sim.serve()
        sim.chaos()
    end
end

-- Buys every deal that is ready, one step per deal (check, buy, confirm), like the Buy key.
function sim.buyDeals(limit)
    local D, T = ForeverFlip.Deals, ForeverFlip.Trade
    local n = 0
    for _, d in ipairs(D.visible("all")) do
        if n >= limit then
            break
        end
        if not T.busy() and d.verified and F_now() - d.verified <= D.FRESH and d.cost <= GetMoney() then
            if T.buy(d.key) then
                n = n + 1
                sim.serve()
                if T.op and T.op.state == "quoted" then
                    T.confirm()
                    sim.serve()
                end
            end
        end
    end
    return n
end

function F_now()
    return ForeverFlip.Engine.clock()
end

-- Posts what was bought for resale, one Post next bought press at a time.
function sim.post(limit)
    local T = ForeverFlip.Trade
    for _ = 1, limit do
        local ok, why = T.postNext()
        if why == "checking" then
            sim.play(1)
            ok, why = T.postNext()
        end
        sim.serve()
        if not ok then
            break
        end
    end
end

-- Takes all auction mail through the addon's button.
function sim.mail()
    if #inbox == 0 then
        return
    end
    mailEvents = true
    MailFrame:Show()
    fire("MAIL_SHOW")
    fire("MAIL_INBOX_UPDATE")
    ForeverFlip.Mail.start()
    for _ = 1, 400 do
        run(0.1)
        if not ForeverFlip.Mail.job then
            break
        end
    end
    fire("MAIL_CLOSED")
    MailFrame:Hide()
    -- Mail the addon could not take (not auction mail) stays; the rest is gone.
    inbox = {}
    freeBagSlots = 20
end

-- What must always hold. Returns a list of problems (empty when all is well).
function sim.check()
    local F = ForeverFlip
    local problems = {}
    local function bad(msg)
        problems[#problems + 1] = msg
    end
    for _, d in ipairs(F.Deals.list) do
        if not (d.qty and d.qty >= 1) then
            bad("deal " .. d.key .. " without units")
        end
        if not (d.cost and d.cost > 0) then
            bad("deal " .. d.key .. " without cost")
        end
        if not (d.profit and d.profit > 0) then
            bad("deal " .. d.key .. " without profit: " .. tostring(d.profit))
        end
        if d.mode == "vendor" and d.maxUnit and d.vendor and d.maxUnit >= d.vendor then
            bad("vendor deal " .. d.key .. " pays " .. d.maxUnit .. " for a vendor price of " .. d.vendor)
        end
        if d.mode == "flip" and d.exit and d.maxUnit and d.exit <= d.maxUnit then
            bad("resale " .. d.key .. " exits at " .. d.exit .. " below its cost " .. d.maxUnit)
        end
    end
    local c = F.Data.char(F.db, F.Engine.owner())
    for key, p in pairs(c.positions) do
        if not (p.qty and p.qty > 0) then
            bad("position " .. key .. " with qty " .. tostring(p.qty))
        end
        if not (p.cost and p.cost >= 0 and p.cost == p.cost) then
            bad("position " .. key .. " with cost " .. tostring(p.cost))
        end
    end
    local journalProfit, statsProfit = 0, 0
    for _, e in ipairs(c.journal) do
        if e.kind == "sell" or e.kind == "vendor" then
            journalProfit = journalProfit + (e.profit or 0)
        end
    end
    for _, s in pairs(c.stats) do
        statsProfit = statsProfit + (s.profit or 0)
        if (s.sold or 0) > (s.bought or 0) + 0 and s.bought and s.bought > 0 then
            bad("item " .. tostring(s.name) .. " sold " .. s.sold .. " of " .. s.bought .. " bought")
        end
    end
    if math.abs(journalProfit - statsProfit) > 1 then
        bad("journal profit " .. journalProfit .. " but statistics " .. statsProfit)
    end
    local last = F.Scan.last
    -- Own lots are counted apart (the simulated market has no bid-only lots).
    if last and last.read + last.skipped + last.own ~= last.total then
        bad("scan read " .. last.read .. " + skipped " .. last.skipped .. " + own " .. last.own .. " of " .. last.total)
    end
    if GetMoney() < 0 then
        bad("money below zero: " .. GetMoney())
    end
    -- The books against what really happened on the market.
    local boughtUnits, soldUnits = 0, 0
    for _, e in ipairs(c.journal) do
        if e.kind == "buy" then
            boughtUnits = boughtUnits + (e.qty or 0)
        elseif e.kind == "sell" then
            soldUnits = soldUnits + (e.qty or 0)
        elseif e.kind == "vendor" and (e.profit or 0) < 0 and F.Data.char(F.db, F.Engine.owner()) then
            bad("vendor sale of " .. tostring(e.name) .. " at a loss: " .. tostring(e.profit))
        end
    end
    if boughtUnits ~= sim.bought then
        bad("journal buys " .. boughtUnits .. " units, the market sold the player " .. sim.bought)
    end
    if soldUnits ~= sim.sold then
        bad("journal sales " .. soldUnits .. " units, the market bought " .. sim.sold .. " of the player's")
    end
    -- Stock in the books is really there: in the bags or on sale.
    local have = {}
    for _, b in ipairs(F.AH.bagItems()) do
        have[b.key] = (have[b.key] or 0) + b.count
    end
    for _, a in ipairs(auctions) do
        if a.owner == "Me" then
            local key = F.AH.keyFor(a.item, link(a.item, a.name))
            if key then
                have[key] = (have[key] or 0) + a.count
            end
        end
    end
    for key, p in pairs(c.positions) do
        if p.qty > (have[key] or 0) then
            bad("position " .. key .. " holds " .. p.qty .. " but only " .. (have[key] or 0) .. " exist")
        end
    end
    -- Every auction that came back is booked once.
    local expired = 0
    for _, e in ipairs(c.journal) do
        if e.kind == "expired" then
            expired = expired + (e.qty or 0)
        end
    end
    if expired ~= sim.expired then
        bad("journal has " .. expired .. " units expired, the house returned " .. sim.expired)
    end
    -- What the books count as on sale is on sale (else Post next bought skips stock that came back).
    local onSale, open = {}, {}
    for _, a in ipairs(auctions) do
        if a.owner == "Me" then
            onSale[a.name] = (onSale[a.name] or 0) + a.count
        end
    end
    for _, l in ipairs(c.listings) do
        open[l.name] = (open[l.name] or 0) + l.open
    end
    for name, n in pairs(open) do
        if n > (onSale[name] or 0) then
            bad("listings count " .. n .. " " .. name .. " on sale, the house has " .. (onSale[name] or 0))
        end
    end
    return problems
end

-- Every page and every item tooltip is drawn without an error.
function sim.drawAll()
    local UI = ForeverFlip.UI
    for _, group in ipairs(UI.GROUPS) do
        for _, page in ipairs(group.pages) do
            UI.show(page[1])
            UI.refresh()
        end
    end
    for _, g in ipairs(sim.goods) do
        GameTooltip.itemLink = link(g.id)
        tooltipLines = {}
        for _, fn in ipairs(tooltipCalls) do
            fn(GameTooltip)
        end
    end
end

-- Things the player and other addons do meanwhile: a search in the game's Buy tab (another browse
-- the addon did not send), closing and opening the auction house again.
sim.chaosRate = 0
sim.events = { browses = 0, reopened = 0, otherScans = 0 }
function sim.chaos()
    if sim.rand() < sim.chaosRate then
        local g = sim.goods[sim.rand(1, #sim.goods)]
        C_AuctionHouse.SendBrowseQuery({ searchString = items[g.id].name, sorts = {}, filters = {} })
        sim.events.browses = sim.events.browses + 1
        if sim.rand() < 0.5 then
            browseAnswer()
        end
    end
    if sim.rand() < sim.chaosRate / 20 then
        fire("AUCTION_HOUSE_CLOSED")
        run(0.5)
        fire("AUCTION_HOUSE_SHOW")
        sim.events.reopened = sim.events.reopened + 1
    end
end

-- A full scan another addon starts (ForeverFlip reads it as its own, Scan.onOtherScan).
function sim.otherScan()
    if ForeverFlip.Scan.cooldown() > 0 or ForeverFlip.Scan.busy() then
        return false
    end
    C_AuctionHouse.ReplicateItems()
    fire("REPLICATE_ITEM_LIST_UPDATE")
    local n = 0
    while ForeverFlip.Scan.busy() do
        run(0.05)
        n = n + 1
        assert(n < 100000, "the other addon's scan never ends")
    end
    sim.events.otherScans = sim.events.otherScans + 1
    return true
end
