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

-- One auction house per realm and faction.
function E.scope()
    return tostring(GetRealmName and GetRealmName() or "?")
        .. "-"
        .. tostring(UnitFactionGroup and UnitFactionGroup("player") or "?")
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
    "AUCTION_HOUSE_AUCTION_CREATED",
    "AUCTION_HOUSE_POST_WARNING",
    "OWNED_AUCTIONS_UPDATED",
    "ITEM_DATA_LOAD_RESULT",
    "CHAT_MSG_SYSTEM",
    "MAIL_SHOW",
    "MAIL_CLOSED",
    "MAIL_INBOX_UPDATE",
    "MERCHANT_SHOW",
    "MERCHANT_CLOSED",
    "PLAYER_LOGOUT",
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
        F.Scan.restore(E.scope())
        if F.UI then
            F.UI.attach()
        end
        F.Trade.ownedDue = 0
    elseif event == "AUCTION_HOUSE_CLOSED" then
        F.Scan.stop()
        F.Trade.checkQueue = nil
        F.Trade.checkingOwned = nil
        F.Deals.clear()
        F.Trade.cancel()
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        F.Scan.onReplicate()
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        F.Deals.onResults(...)
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        local key = ...
        if type(key) == "table" then
            F.Deals.onResults(key.itemID)
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
    elseif event == "PLAYER_LOGOUT" then
        -- Saves checks and vendor deals found since the scan (SavedVariables are written next).
        F.Scan.save()
    elseif event == "MAIL_SHOW" or event == "MAIL_CLOSED" or event == "MAIL_INBOX_UPDATE" then
        if event ~= "MAIL_INBOX_UPDATE" then
            F.Mail.open = event == "MAIL_SHOW"
        end
        if event == "MAIL_CLOSED" then
            F.Mail.stop()
        end
        if F.UI and F.UI.mail then
            F.UI.mail(F.Mail.open)
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

local paint = 0
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
    F.Trade.step()
    F.Mail.step(GetTime and GetTime() or E.clock())
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
