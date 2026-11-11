local F = ForeverFlip
local U = F.Util
local E = {}
F.Engine = E

E.autoVerify = true
E.message = nil

function E.clock()
    return time()
end

function E.wallet()
    return GetMoney() or 0
end

-- Neutral auction houses (goblin towns) have their own listings and a 15% cut. Each of the three
-- zones holds exactly one auction house, the neutral one, so the zone's map ID tells it in any client
-- language; the English town names are a fallback for clients without C_Map.
local NEUTRAL_MAPS = {
    [1434] = true, -- Stranglethorn Vale: Booty Bay
    [1446] = true, -- Tanaris: Gadgetzan
    [1452] = true, -- Winterspring: Everlook
}
local NEUTRAL_TOWNS = { ["booty bay"] = true, ["gadgetzan"] = true, ["everlook"] = true }
function E.detectHouse()
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
        if ok and NEUTRAL_MAPS[map] then
            return "Neutral"
        end
    end
    for _, get in ipairs({ GetSubZoneText, GetMinimapZoneText, GetRealZoneText, GetZoneText }) do
        local ok, zone = pcall(get)
        if ok and type(zone) == "string" and (NEUTRAL_TOWNS[zone] or NEUTRAL_TOWNS[string.lower(zone)]) then
            return "Neutral"
        end
    end
    return nil
end

-- One auction house per realm and faction, plus the neutral house of the realm.
E.house = nil -- "Neutral" while a neutral auction house is open
function E.scope()
    return tostring(GetRealmName and GetRealmName() or "?")
        .. "-"
        .. tostring(E.house or UnitFactionGroup and UnitFactionGroup("player") or "?")
end

-- The cut of an auction house: learned from sale invoices, else 5% (15% on a neutral house).
function E.cutFor(scope)
    local learned = F.db and F.db.cuts and F.db.cuts[scope]
    if U.finite(learned) and learned > 0 and learned < 0.5 then
        return learned
    end
    return scope:match("%-Neutral$") and 0.15 or 0.05
end

function E.applyCut()
    F.Market.CUT = E.cutFor(E.scope())
end

function E.owner()
    return tostring(GetRealmName and GetRealmName() or "?") .. "-" .. tostring(UnitName and UnitName("player") or "?")
end

function E.notify(message)
    E.message, E.messageAt = message, E.clock()
    E.changed()
end

function E.changed()
    E.dirty = true
end

local frame = CreateFrame("Frame")
F.frame = frame

local events = {
    "ADDON_LOADED",
    "AUCTION_HOUSE_SHOW",
    "AUCTION_HOUSE_CLOSED",
    "REPLICATE_ITEM_LIST_UPDATE",
    "COMMODITY_SEARCH_RESULTS_UPDATED",
    "ITEM_SEARCH_RESULTS_UPDATED",
    "COMMODITY_PRICE_UPDATED",
    "COMMODITY_PRICE_UNAVAILABLE",
    "COMMODITY_PURCHASE_SUCCEEDED",
    "COMMODITY_PURCHASE_FAILED",
    "AUCTION_HOUSE_PURCHASE_COMPLETED",
    "AUCTION_HOUSE_SHOW_ERROR",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
    "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
    "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
    "AUCTION_HOUSE_BROWSE_FAILURE",
    "AUCTION_HOUSE_AUCTION_CREATED",
    "AUCTION_HOUSE_POST_WARNING",
    "OWNED_AUCTIONS_UPDATED",
    "ITEM_DATA_LOAD_RESULT",
    "CHAT_MSG_SYSTEM",
    "MAIL_SHOW",
    "MAIL_CLOSED",
    "MAIL_INBOX_UPDATE",
    "MERCHANT_SHOW",
    "TRADE_SKILL_SHOW",
    "TRADE_SKILL_LIST_UPDATE",
    "MERCHANT_CLOSED",
    "PLAYER_LOGOUT",
    "PLAYER_MONEY",
    "CHAT_MSG_ADDON",
    "PLAYER_ENTERING_WORLD",
}
for _, event in ipairs(events) do
    pcall(frame.RegisterEvent, frame, event)
end

function E.handle(event, ...)
    if event == "ADDON_LOADED" then
        if ... == "ForeverFlip" then
            ForeverFlipData = F.Data.open(ForeverFlipData)
            F.db = ForeverFlipData
            F.Locale.apply(F.db.settings.language)
            E.applyCut()
            F.Mail.hook()
            F.Share.register()
            F.Bids.prune()
            if F.UI and F.UI.tooltips then
                F.UI.tooltips()
            end
        end
        return
    end
    if not F.db then
        return
    end
    if event == "AUCTION_HOUSE_SHOW" then
        E.house = E.detectHouse()
        E.applyCut()
        F.Scan.restore(E.scope())
        if F.UI then
            F.UI.attach()
        end
        F.Trade.ownedDue = 0
    elseif event == "AUCTION_HOUSE_CLOSED" then
        F.Scan.stop()
        F.Trade.checkQueue = nil
        F.Trade.checkingOwned = nil
        F.Trade.held = {}
        F.Deals.clear()
        F.Sniper.reset()
        F.Trade.cancel()
        E.house = nil
        E.applyCut()
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        F.Scan.onReplicate()
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        F.Deals.onResults(...)
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        local key = ...
        if type(key) == "table" then
            F.Deals.onResults(key.itemID, key)
        end
    elseif event == "COMMODITY_PRICE_UPDATED" then
        F.Trade.onQuote(...)
    elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
        F.Trade.onQuoteFailed()
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
        F.Trade.onCommodityBought()
    elseif event == "COMMODITY_PURCHASE_FAILED" then
        F.Trade.onCommodityFailed()
    elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
        F.Trade.onItemBought(...)
    elseif event == "AUCTION_HOUSE_SHOW_ERROR" then
        F.Trade.onError()
    elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
        F.Deals.onDropped()
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        F.Sniper.onResults()
    elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" then
        F.Sniper.onFailure()
    elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
        F.Trade.onAuctionCreated(...)
    elseif event == "AUCTION_HOUSE_POST_WARNING" then
        F.Trade.onPostWarning()
    elseif event == "OWNED_AUCTIONS_UPDATED" then
        F.Trade.onOwned()
    elseif event == "ITEM_DATA_LOAD_RESULT" then
        local id, ok = ...
        if ok then
            F.Scan.itemLoaded(id)
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        F.Trade.onChat(...)
    elseif event == "CHAT_MSG_ADDON" then
        F.Share.onMessage(...)
        return
    elseif event == "PLAYER_MONEY" or event == "PLAYER_ENTERING_WORLD" then
        F.Analytics.recordGold()
    elseif event == "PLAYER_LOGOUT" then
        F.Analytics.recordGold()
        -- Saves checks and vendor deals found since the scan (SavedVariables are written next).
        F.Scan.save()
    elseif event == "MAIL_SHOW" or event == "MAIL_CLOSED" or event == "MAIL_INBOX_UPDATE" then
        if event ~= "MAIL_INBOX_UPDATE" then
            F.Mail.open = event == "MAIL_SHOW"
        end
        if event == "MAIL_CLOSED" then
            F.Mail.stop()
        else
            F.Mail.snapshot()
        end
        if F.UI and F.UI.mail then
            F.UI.mail(F.Mail.open)
        end
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" then
        -- Recipes are read at most every two seconds; the list event fires often.
        if E.clock() - (E.recipesAt or 0) >= 2 then
            E.recipesAt = E.clock()
            F.Crafting.learn()
        end
    elseif event == "MERCHANT_SHOW" or event == "MERCHANT_CLOSED" then
        if F.UI and F.UI.merchant then
            F.UI.merchant(event == "MERCHANT_SHOW")
            F.UI.merchantOffers(event == "MERCHANT_SHOW")
        end
    end
    E.changed()
end

-- Errors are reported once per message (chat and saved data), never once per frame.
local reported = {}
local function report(err)
    err = tostring(err)
    if reported[err] then
        return
    end
    reported[err] = true
    print("|cffff4040ForeverFlip error:|r " .. err)
    if F.db then
        F.db.errors = F.db.errors or {}
        table.insert(F.db.errors, 1, { at = E.clock(), version = F.version, message = err })
        while #F.db.errors > 20 do
            table.remove(F.db.errors)
        end
    end
end
E.report = report
local function trace(err)
    return tostring(err) .. (debugstack and (" | " .. debugstack(2, 6, 0)) or "")
end

frame:SetScript("OnEvent", function(_, event, ...)
    local args = { ... }
    local ok, err = xpcall(function()
        E.handle(event, unpack(args))
    end, trace)
    if not ok then
        report(event .. ": " .. err)
    end
end)

local paint, marks = 0, 0
function E.update(elapsed)
    if not F.db then
        return
    end
    F.AH.pump(GetTime and GetTime() or E.clock())
    if not F.Deals.pending() then
        F.Scan.auto()
    end
    F.Scan.step()
    F.Trade.stepChecks()
    F.Deals.step()
    F.Sniper.step()
    F.Trade.step()
    F.Mail.step(GetTime and GetTime() or E.clock())
    F.Share.step(GetTime and GetTime() or E.clock())
    -- The game's Buy tab scrolls and reuses its rows: its deal marks are refreshed twice a second.
    marks = marks + (elapsed or 0)
    if marks >= 0.5 and F.UI and F.UI.highlightBrowse and F.AH.isOpen() then
        marks = 0
        pcall(F.UI.highlightBrowse)
    end
    paint = paint + (elapsed or 0)
    if E.dirty and paint >= 0.25 and F.UI and F.UI.refresh then
        paint, E.dirty = 0, false
        F.UI.refresh()
    end
end

frame:SetScript("OnUpdate", function(_, elapsed)
    local ok, err = xpcall(function()
        E.update(elapsed)
    end, trace)
    if not ok then
        report(err)
    end
end)

-- Key bindings (Bindings.xml). A key press is a hardware event like a click.
function E.keyBuy()
    local T, UI = F.Trade, F.UI
    if T.op and T.op.state == "quoted" then
        T.confirm()
    elseif UI and UI.selected then
        local ok, why = T.buy(UI.selected)
        if not ok then
            if why == "verify_first" then
                F.Deals.verify(UI.selected)
            end
            E.notify(why)
        end
    end
end

function E.keyPost()
    local ok, why = F.Trade.postNext()
    if not ok and why == "nothing_to_post" then
        ok, why = F.Trade.postAll()
    end
    E.notify(why)
end

function E.keyCancel()
    local _, why = F.Trade.cancelNextUndercut()
    E.notify(why)
end

function E.keyScan()
    local ok, why = F.Scan.start()
    if not ok then
        E.notify(why)
    end
end

-- ForeverFlipAPI: ForeverFlip's prices for other addons. The functions keep their names and meaning;
-- new ones raise `version`. `item` is an item link, an item string or an item ID.
ForeverFlipAPI = {
    version = 1,
}
local API = ForeverFlipAPI

local function keyOf(item)
    if not F.db then
        return nil
    end
    local id, link
    if type(item) == "number" then
        id = item
    elseif type(item) == "string" then
        id = tonumber(item:match("item:(%d+)") or item:match("^%d+$"))
        link = item:find("|H", 1, true) and item or nil
    end
    if not id then
        return nil
    end
    return F.AH.keyFor(id, link)
end

function API.IsReady()
    return F.db ~= nil
end

-- Prices of the player's auction house: usual asking price, cheapest today, median of sales seen,
-- units sold per day near the usual price (nil: unknown) and the age of the usual price in seconds.
function API.GetPrice(item)
    local key = keyOf(item)
    local h = key and F.Data.market(F.db, E.scope()).history[key]
    local usual, at = F.Market.usual(h)
    if not usual or type(h) ~= "table" then
        return nil
    end
    local today = h.days and h.days[#h.days]
    local s = F.Market.saleability(h, usual, E.clock())
    return usual,
        today and today.min or nil,
        F.Market.salePrice(h),
        s.known and s.perDay or nil,
        at and E.clock() - at or nil
end

-- The current deal of an item: mode ("vendor", "flip", "shop", "disenchant"), profit, cost, units,
-- and whether it was checked on the auction house in the last 45 seconds.
function API.GetDeal(item)
    local key = keyOf(item)
    local d = key and F.Deals.get(key)
    if not d then
        return nil
    end
    return d.mode, d.profit, d.cost, d.qty, d.verified ~= nil and E.clock() - d.verified <= F.Deals.FRESH
end

-- aux's usual price (auxForever, if installed) for items ForeverFlip has not seen.
function E.auxPrice(id)
    local aux = AuxForeverAPI
    if type(aux) == "table" and aux.IsReady and aux.GetUsualPrice then
        local ok, ready = pcall(aux.IsReady)
        if ok and ready then
            local got, price = pcall(aux.GetUsualPrice, id)
            if got and U.finite(price) and price > 0 then
                return price
            end
        end
    end
end

SLASH_FOREVERFLIP1 = "/ff"
SLASH_FOREVERFLIP2 = "/foreverflip"
SlashCmdList.FOREVERFLIP = function(msg)
    msg = string.lower(msg or "")
    local L = F.Locale.text
    if msg == "diag" then
        local last = F.Scan.last
        if not last then
            print("ForeverFlip: " .. L("No full scan yet."))
            return
        end
        local s = last.stats
        print(
            string.format(
                "ForeverFlip %s: %d auctions, %d read, %d skipped, %d own; %d items, vendor price known %d, below vendor %d, collecting sales data %d; deals %d",
                F.version,
                last.total,
                last.read,
                last.skipped,
                last.own,
                s.items,
                s.vendorKnown,
                s.belowVendor,
                s.collecting,
                #F.Deals.list
            )
        )
        F.db.diag = { at = last.at, total = last.total, read = last.read, skipped = last.skipped, stats = U.copy(s) }
        return
    end
    if msg == "export" then
        if F.UI and F.UI.showExport then
            F.UI.showExport()
        end
        return
    end
    if msg == "rescan" then
        -- After a scan the server never answered: allow the next request now.
        F.db.lastScan = 0
        print("ForeverFlip: " .. L("the full scan can be requested again."))
        return
    end
    local lang = msg:match("^lang%s+(%a+)$")
    if lang == "en" or lang == "uk" then
        F.db.settings.language = lang
        print("ForeverFlip: /reload")
        return
    end
    print(
        "ForeverFlip " .. F.version .. ": " .. L("open the auction house and use the ForeverFlip tab.") .. " /ff diag"
    )
end
