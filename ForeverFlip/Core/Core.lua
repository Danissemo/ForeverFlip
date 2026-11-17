local F = ForeverFlip
local U = F.Util
local E = {}
F.Engine = E

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
    -- One house for both factions (Retail): no neutral house to tell apart.
    if not F.Compat.caps.factionHouses then
        return nil
    end
    -- The auctioneer tells it best: the auctioneers of Alliance and Horde towns belong to their
    -- faction, the goblins of the neutral houses to none. The zone is only the fallback.
    if UnitExists and UnitFactionGroup and UnitExists("npc") then
        local faction = UnitFactionGroup("npc")
        if faction == "Alliance" or faction == "Horde" then
            return nil
        end
    end
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

-- Hardcore realms have their own economy: their prices are kept apart (TSM does the same, with
-- the same game rule check).
-- T30: E.scope() is asked many times a frame (every deal's Sure, every refresh, every tooltip).
-- The realm's rules do not change while the game runs, so the answer of C_GameRules is kept for
-- the same C_GameRules table, and the scope string is built again only when one of its parts
-- (realm name, hardcore, open house, faction) differs. E.counts tells how often each was built.
E.counts = { scope = 0, scopeBuilt = 0, hardcoreAsked = 0 }
local hcFor, hcRule, hcActive
function E.hardcore()
    if not (C_GameRules and C_GameRules.IsGameRuleActive and Enum and Enum.GameRule) then
        return false
    end
    local rule = Enum.GameRule.HardcoreRuleset
    if rule == nil then
        return false
    end
    if hcFor == C_GameRules and hcRule == rule then
        return hcActive
    end
    E.counts.hardcoreAsked = E.counts.hardcoreAsked + 1
    local ok, active = pcall(C_GameRules.IsGameRuleActive, rule)
    hcFor, hcRule, hcActive = C_GameRules, rule, ok and active == true
    return hcActive
end

-- The realm part of a scope: the realm name, marked on hardcore realms.
function E.realm()
    return tostring(GetRealmName and GetRealmName() or "?") .. (E.hardcore() and " (HC)" or "")
end

-- The auction houses of a realm, by the side part of their scope:
--   "Alliance", "Horde"  a faction's own house (WoW Forever)
--   "Neutral"            a goblin town's house, shared by both factions, 15% cut (WoW Forever)
--   "Server"             the one house of both factions (Retail, C.caps.factionHouses off)
-- Connected realms share their houses: Share takes their scans as the player's realm's own.
E.SIDES = { Alliance = true, Horde = true, Neutral = true, Server = true }
E.house = nil -- "Neutral" while a neutral auction house is open

-- The house the player's own faction trades at, when no neutral house is open.
function E.homeSide()
    if not F.Compat.caps.factionHouses then
        return "Server"
    end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    return (faction == "Alliance" or faction == "Horde") and faction or "?"
end

-- The side of the open (or, closed, the player's usual) auction house.
function E.side()
    return E.house or E.homeSide()
end

-- Whether a realm name (a scope's realm part, " (HC)" included) is the player's realm or one
-- connected to it, on the same ruleset: their auction houses are the same.
function E.sameHouseRealm(realm)
    if type(realm) ~= "string" then
        return false
    end
    if realm == E.realm() then
        return true
    end
    local name, hc = realm:match("^(.-)( %(HC%))$")
    name = name or realm
    if (hc ~= nil) ~= E.hardcore() then
        return false
    end
    return F.Compat.connectedRealms()[F.Compat.realmKey(name)] == true
end

local memo = {}
function E.scope()
    E.counts.scope = E.counts.scope + 1
    local realm = GetRealmName and GetRealmName() or "?"
    local hc = E.hardcore()
    local side = E.side()
    if memo.scope and memo.realm == realm and memo.hc == hc and memo.side == side then
        return memo.scope
    end
    E.counts.scopeBuilt = E.counts.scopeBuilt + 1
    memo.realm, memo.hc, memo.side = realm, hc, side
    memo.scope = tostring(realm) .. (hc and " (HC)" or "") .. "-" .. tostring(side)
    return memo.scope
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

-- Market reads no game-facing module itself: what it needs from them is handed in here. Each
-- accessor looks the module up when called, so a module replaced later (tests) is still the one used.
function E.wireMarket()
    F.Market.use({
        kindOf = function(id)
            return F.AH and F.AH.kindOf and F.AH.kindOf(id)
        end,
        vendorPrice = function(id, confirmed)
            return F.AH.vendorPrice(id, confirmed)
        end,
        clientVendorPrice = function(id)
            return F.AH.clientVendorPrice(id)
        end,
        depositFn = function(id, kind, d)
            return F.AH.depositFn(id, kind, d)
        end,
        saleRate = function(name)
            return F.Trade.rate(name)
        end,
        durationFor = function(key, qty, price)
            return F.Trade and F.Trade.durationFor and F.Trade.durationFor(key, qty, price)
        end,
        durationHours = function(d)
            return F.Trade.DURATION_HOURS and F.Trade.DURATION_HOURS[d]
        end,
        durationSetting = function()
            return F.db and F.db.settings.duration
        end,
        canDisenchant = function()
            return F.Disenchant.canDisenchant()
        end,
        disenchantValue = function(id)
            return F.Disenchant.value(id)
        end,
        clock = function()
            return F.Engine and F.Engine.clock and F.Engine.clock() or 0
        end,
    })
end
E.wireMarket()

function E.owner()
    return tostring(GetRealmName and GetRealmName() or "?") .. "-" .. tostring(UnitName and UnitName("player") or "?")
end

function E.notify(message)
    if message ~= nil and F.Log and F.Log.dev and F.Log.dev() then
        F.Log.trace("notify", "%s", tostring(message))
    end
    E.message, E.messageAt = message, E.clock()
    E.changed()
end

function E.changed()
    E.dirty = true
end

-- Services tell the screen what happened (E.emit) instead of calling F.UI; the UI subscribes
-- (E.listen). E.notify stays the status message. Listeners run in the caller's frame, under its
-- error handler, in the order they subscribed.
E.listeners = {}
function E.listen(event, fn)
    local list = E.listeners[event]
    if not list then
        list = {}
        E.listeners[event] = list
    end
    list[#list + 1] = fn
end

function E.emit(event, ...)
    local list = E.listeners[event]
    if not list then
        return
    end
    for i = 1, #list do
        list[i](...)
    end
end

-- What the screen shows, for services that pace their work by it, read when asked: { frame (the
-- window exists), shown, section, filter, selected, selectedAt, buyHoverKey, vendorOrder }. The
-- UI registers the reader (E.screenReader); without one nothing is shown. Read it, never keep it.
local noScreen = { frame = false, shown = false }
function E.screen()
    local read = E.screenReader
    return read and read() or noScreen
end

-- A hardware callback still sends protected actions itself. This only schedules immediate
-- feedback and briefly holds off new background queries while the player is interacting.
function E.input()
    E.inputUntil = (GetTime and GetTime() or E.clock()) + 0.5
    E.urgent = true
    E.changed()
end

function E.interacting()
    return (GetTime and GetTime() or E.clock()) < (E.inputUntil or 0)
end

-- Independent local jobs still advance while the server answers a click, with shorter slices.
-- A purchase always gets 2 ms. `soft`: the cap while the player only clicks or a price check is
-- waited for (2 ms when not given); the full scan's reading keeps half its pace then instead of a
-- sixth, and reading 200 000 auctions is what the player waits for.
function E.workSlice(ms, soft)
    if F.Trade.busy() then
        return math.min(ms, 2)
    end
    if E.interacting() or F.Deals.foreground() then
        return math.min(ms, soft or 2)
    end
    return ms
end

local frame = CreateFrame("Frame")
F.frame = frame

local events = {
    "ADDON_LOADED",
    "AUCTION_HOUSE_SHOW",
    "AUCTION_HOUSE_CLOSED",
    "REPLICATE_ITEM_LIST_UPDATE",
    "COMMODITY_SEARCH_RESULTS_UPDATED",
    "COMMODITY_SEARCH_RESULTS_ADDED",
    "ITEM_SEARCH_RESULTS_UPDATED",
    "ITEM_SEARCH_RESULTS_ADDED",
    "COMMODITY_PRICE_UPDATED",
    "COMMODITY_PRICE_UNAVAILABLE",
    "COMMODITY_PURCHASE_SUCCEEDED",
    "COMMODITY_PURCHASE_FAILED",
    "AUCTION_HOUSE_PURCHASE_COMPLETED",
    "AUCTION_HOUSE_SHOW_ERROR",
    "ADDON_RESTRICTION_STATE_CHANGED",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
    "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
    "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
    "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
    "AUCTION_HOUSE_BROWSE_FAILURE",
    "AUCTION_HOUSE_AUCTION_CREATED",
    "AUCTION_HOUSE_POST_WARNING",
    "OWNED_AUCTIONS_UPDATED",
    "BIDS_UPDATED",
    "BID_ADDED",
    "ITEM_DATA_LOAD_RESULT",
    "ITEM_KEY_ITEM_INFO_RECEIVED",
    "CHAT_MSG_SYSTEM",
    "MAIL_SHOW",
    "MAIL_CLOSED",
    "MAIL_INBOX_UPDATE",
    "MERCHANT_SHOW",
    "MERCHANT_UPDATE",
    "BAG_UPDATE_DELAYED",
    "LOOT_OPENED",
    "CHAT_MSG_CHANNEL_NOTICE",
    "TRADE_SKILL_SHOW",
    "TRADE_SKILL_LIST_UPDATE",
    "MERCHANT_CLOSED",
    "PLAYER_LOGOUT",
    "PLAYER_MONEY",
    "CHAT_MSG_ADDON",
    "PLAYER_ENTERING_WORLD",
    -- The game names the addon and the function it blocked (E.onBlocked).
    "ADDON_ACTION_FORBIDDEN",
    "ADDON_ACTION_BLOCKED",
}
for _, event in ipairs(events) do
    pcall(frame.RegisterEvent, frame, event)
end
-- Only the player's own casts matter (Disenchant.onCast). Registered for every unit, the casts of
-- nameplates, party and target would repaint the window several times a second. A client without
-- RegisterUnitEvent sends every unit's casts, and E.handle drops the others.
local playerEvents = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_FAILED",
}
for _, event in ipairs(playerEvents) do
    if not (frame.RegisterUnitEvent and pcall(frame.RegisterUnitEvent, frame, event, "player")) then
        pcall(frame.RegisterEvent, frame, event)
    end
end

-- The game blocked a protected action (a purchase, a post, a cancel...) and named this addon. What
-- it blocked and what ForeverFlip was doing then are kept (the last 10, shown by /ff diag): the
-- game's own dialog says neither.
E.BLOCKED_KEEP = 10
-- A client that sends ADDON_ACTION_BLOCKED with the addon only: the function is unknown, and the
-- record says so instead of "nil".
local BLOCKED_UNKNOWN = "?"
-- What /ff diag calls the record ("forbidden" is what the game says for the first event).
function E.blockedKindText(kind)
    local L = F.Locale.text
    return L(kind == "forbidden" and "forbidden" or "blocked")
end
function E.onBlocked(event, addon, func)
    if addon ~= "ForeverFlip" or not F.db then
        return
    end
    func = type(func) == "string" and func or (func ~= nil and tostring(func) or BLOCKED_UNKNOWN)
    local T, UI = F.Trade, F.UI
    local doing = {}
    if UI and UI.section then
        doing[#doing + 1] = "page " .. tostring(UI.section)
    end
    if T and T.op then
        doing[#doing + 1] = "purchase " .. tostring(T.op.state)
    end
    if T and T.vendorJob then
        doing[#doing + 1] = "merchant sale"
    end
    if F.Mail and F.Mail.job then
        doing[#doing + 1] = "taking mail"
    end
    if F.Scan and F.Scan.job then
        doing[#doing + 1] = "full scan " .. tostring(F.Scan.job.state)
    end
    for name, shown in pairs({
        AH = AuctionHouseFrame and AuctionHouseFrame:IsShown(),
        merchant = MerchantFrame and MerchantFrame:IsShown(),
        mail = MailFrame and MailFrame:IsShown(),
    }) do
        if shown then
            doing[#doing + 1] = name .. " open"
        end
    end
    if InCombatLockdown and InCombatLockdown() then
        doing[#doing + 1] = "in combat"
    end
    F.db.blocked = type(F.db.blocked) == "table" and F.db.blocked or {}
    table.insert(F.db.blocked, 1, {
        at = E.clock(),
        version = F.version,
        event = event == "ADDON_ACTION_FORBIDDEN" and "forbidden" or "blocked",
        func = func,
        doing = table.concat(doing, ", "),
    })
    while #F.db.blocked > E.BLOCKED_KEEP do
        table.remove(F.db.blocked)
    end
    -- Told once for each function, and once in every session (a saved list of the last 10 must not
    -- silence the chat line for the ones seen before): the player has to know while it happens. It
    -- reaches the general chat by the Errors box of Settings, Messages (on by default).
    E.blockedSeen = E.blockedSeen or {}
    if not E.blockedSeen[func] then
        E.blockedSeen[func] = true
        F.Log.add(
            "error",
            string.format(
                F.Locale.text("the game blocked %s. Type /ff diag and send the lines to the developer."),
                func
            )
        )
    end
end

-- Events whose arguments are chat text or noise: the trace gets only their name.
E.TRACE_NAME_ONLY = {
    CHAT_MSG_SYSTEM = true,
    CHAT_MSG_ADDON = true,
    CHAT_MSG_CHANNEL_NOTICE = true,
    ADDON_LOADED = true,
}

-- An event's first arguments for the trace, each cut short; a value that cannot be read (a secret
-- value on Retail) is written as "?".
local function traceArgs(event, ...)
    if E.TRACE_NAME_ONLY[event] then
        return ""
    end
    local out = {}
    for i = 1, math.min(3, select("#", ...)) do
        local v = select(i, ...)
        local ok, text = pcall(tostring, v)
        if not ok or (F.Compat and F.Compat.secret(v)) then
            text = "?"
        end
        if type(v) == "table" then
            text = "table"
        end
        out[#out + 1] = string.sub(text, 1, 60)
    end
    return table.concat(out, " ")
end

function E.handle(event, ...)
    if F.Log.dev() and (event ~= "ADDON_LOADED" or ... == "ForeverFlip") then
        F.Log.trace("event", "%s %s", event, traceArgs(event, ...))
    end
    if event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
        E.onBlocked(event, ...)
        return
    end
    if event == "ADDON_LOADED" then
        if ... == "ForeverFlip" then
            -- The client may fail to read the saved file (other Forever addons report it). Starting
            -- empty would overwrite the real file at logout, so the player is asked first.
            E.noSavedData = type(ForeverFlipData) ~= "table"
            ForeverFlipData = F.Data.open(ForeverFlipData)
            F.db = ForeverFlipData
            -- Before the dialog below: its text and buttons are translated when it is built.
            F.Locale.apply(F.db.settings.language)
            if E.noSavedData and F.UI and F.UI.noSavedData then
                F.UI.noSavedData()
            end
            F.Log.init()
            local fit = F.db.fitDropped
            if type(fit) == "table" then
                F.db.fitDropped = nil
                local text =
                    "Saved data neared the client's limit: %d items not seen for the longest time were forgotten."
                F.Log.add("info", string.format(F.Locale.text(text), tonumber(fit.items) or 0))
            end
            E.hookReplicate()
            F.AH.hookBrowse()
            E.applyCut()
            F.Mail.hook()
            F.Share.register()
            F.Raw.importCommunity()
            F.Raw.announceUpdate()
            F.Raw.prune()
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
        E.spent = 0
        F.AH.refreshPlayer()
        E.house = E.detectHouse()
        E.applyCut()
        local scope = E.scope()
        -- Price checks are kept for the house they were made at: another house's cheapest prices
        -- would price posts and call own auctions undercut here.
        if E.openedScope and E.openedScope ~= scope and F.Trade.forgetHouse then
            F.Trade.forgetHouse()
        end
        E.openedScope = scope
        F.Scan.restore(scope)
        F.Scan.resume(scope)
        if F.UI then
            F.UI.attach()
        end
        F.Trade.ownedDue = 0
    elseif event == "AUCTION_HOUSE_CLOSED" then
        F.AH.throttleReset()
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
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED" then
        F.Deals.onResults(...)
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED" then
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
        F.Trade.onError(...)
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        E.changed() -- the posting buttons follow the game's restriction (AH.restricted)
    elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
        -- The sniper hears it first, while the purchase, scan or exact search that may own the
        -- dropped message is still marked as waiting for its answer.
        if F.Sniper.onDropped then
            F.Sniper.onDropped()
        end
        F.Trade.onDropped()
        F.Scan.onDropped()
        F.Deals.onDropped()
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        F.AH.throttleReset()
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        -- Every browse answer teaches item-key versions (AH.learnKeys). A gear search browses for
        -- the item's versions; every other browse feeds the sniper. UPDATED brings a new list, read
        -- from its first row even when no browse sent through the hook (AH.hookBrowse) said so.
        local updated = event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED"
        local rows, whole = F.AH.browseAnswer(updated, ...)
        if not F.Deals.onPreBrowse(rows, whole) and not F.Deals.onBrowse() then
            F.Sniper.onResults(updated, rows, whole)
        end
    elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" then
        if not F.Deals.onBrowseFailure() then
            F.Sniper.onFailure()
        end
    elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
        F.Trade.onAuctionCreated(...)
    elseif event == "AUCTION_HOUSE_POST_WARNING" then
        F.Trade.onPostWarning()
    elseif event == "OWNED_AUCTIONS_UPDATED" then
        F.Trade.onOwned()
    elseif event == "BIDS_UPDATED" then
        F.Bids.onLive()
    elseif event == "BID_ADDED" then
        F.Bids.liveDue = 0
    elseif event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
        -- The auction house now knows the item's kind: the Sell page and the deals may list it.
        E.changed()
    elseif event == "ITEM_DATA_LOAD_RESULT" then
        -- Other addons and the game's own windows load items all the time. Only an item a deal of
        -- the scan waits for (its vendor price) changes the window at once; the names of other
        -- items show at the next one-second refresh.
        local id, ok = ...
        F.AH.itemArrived(id) -- frees a place for the next item data request
        local last = F.Scan.last
        local waited = ok and last and last.waitVendor and last.waitVendor[id]
        if ok then
            F.Scan.itemLoaded(id)
        else
            F.Scan.itemFailed(id) -- an item the server may not have: a scan stops waiting for it
        end
        if not waited then
            return
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        F.Trade.onChat(...)
    elseif event == "CHAT_MSG_ADDON" then
        F.Share.onMessage(...)
        return
    elseif event == "PLAYER_MONEY" or event == "PLAYER_ENTERING_WORLD" then
        if event == "PLAYER_MONEY" then
            F.Trade.onMoney()
            F.Scan.onMoney()
            if MerchantFrame and MerchantFrame:IsShown() then
                F.Merchant.watchBuyback(false)
            end
        end
        F.Analytics.recordGold()
        if event == "PLAYER_ENTERING_WORLD" then
            F.Trade.repairInvoices()
            F.Log.entered()
        end
        if event == "PLAYER_ENTERING_WORLD" and not F.Share.joined then
            -- The game joins its own channels first; joining ours a few seconds later keeps their order.
            F.Share.later(8, F.Share.join, "join")
        end
    elseif event == "PLAYER_LOGOUT" then
        if F.resetPending then
            -- The player asked for a clean start (F.resetAll): only the settings are written.
            ForeverFlipData, ForeverFlipRaw = F.Data.reset(F.db), nil
            return
        end
        F.Analytics.recordGold()
        -- Saves checks and vendor deals found since the scan (SavedVariables are written next).
        F.Scan.save()
        -- Last: a file the client cannot read loses everything at the next logout (D.fitSave).
        local ok, count, dropped = pcall(F.Data.fitSave, F.db, ForeverFlipRaw)
        if ok and dropped > 0 then
            F.db.fitDropped = { at = E.clock(), items = dropped, constants = count }
        end
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
        -- Recipes are read at once at most every two seconds; the list event fires often. An event
        -- inside those two seconds is read half a second after the last one (E.update): the list
        -- at TRADE_SKILL_SHOW can still be empty, and the loaded list comes with an update.
        local t = GetTime and GetTime() or E.clock()
        if not E.recipesAt or t - E.recipesAt >= 2 then
            E.recipesAt, E.recipesDue = t, nil
            F.Crafting.learn()
        else
            E.recipesDue = t + 0.5
        end
    elseif event == "MERCHANT_UPDATE" then
        F.Merchant.watchBuyback(false)
        F.Merchant.learnBuyback()
    elseif event == "BAG_UPDATE_DELAYED" then
        F.Merchant.settle() -- merchant purchases are booked as their units arrive
        -- Items sold to a merchant leave the bags a moment after the click: the merchant lists
        -- are built again once the bags settled, not on the next click.
        if MerchantFrame and MerchantFrame:IsShown() and F.UI and F.UI.merchant then
            F.Merchant.watchBuyback(false)
            F.UI.merchant(true)
        end
    elseif
        event == "UNIT_SPELLCAST_START"
        or event == "UNIT_SPELLCAST_SUCCEEDED"
        or event == "UNIT_SPELLCAST_INTERRUPTED"
        or event == "UNIT_SPELLCAST_FAILED"
    then
        if ... ~= "player" then
            return -- another unit's cast (registered for every unit without RegisterUnitEvent)
        end
        F.Disenchant.onCast(event, ...)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            F.Crafting.onCast(select(3, ...))
        end
    elseif event == "LOOT_OPENED" then
        F.Disenchant.onLoot()
    elseif event == "CHAT_MSG_CHANNEL_NOTICE" then
        F.Share.onChannelNotice(...)
    elseif event == "MERCHANT_SHOW" or event == "MERCHANT_CLOSED" then
        if event == "MERCHANT_SHOW" then
            F.Merchant.watchBuyback(true)
            F.Merchant.learnBuyback()
        else
            F.Merchant.settle(true)
        end
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
    F.Log.add("error", err)
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

-- A full scan another addon starts (Auctionator, TSM, auxForever ...) uses the account's 15-minute
-- window: it is read too. WoW Forever does not always send REPLICATE_ITEM_LIST_UPDATE, so the call
-- itself is watched (TSM hooks it the same way).
function E.hookReplicate()
    if E.replicateHooked or not hooksecurefunc or not C_AuctionHouse or not C_AuctionHouse.ReplicateItems then
        return
    end
    E.replicateHooked = true
    hooksecurefunc(C_AuctionHouse, "ReplicateItems", function()
        if not F.AH.replicating then
            F.Scan.onOtherScan()
        end
    end)
end

local paint, marks, tick = 0, 0, 0
-- Each part of the frame update runs on its own: an error in one (reported once) does not stop the
-- others, nor the window from being redrawn.
-- A part slower than F.Log.SLOW_MS is traced (a frame the game waited for): its name and time.
local function part(name, fn, ...)
    local t0 = F.Log.ms()
    local ok, err = pcall(fn, ...)
    if not ok then
        report(name .. ": " .. tostring(err))
    end
    local spent = F.Log.ms() - t0
    if spent >= F.Log.SLOW_MS then
        F.Log.stat("slowframe." .. name .. ".ms", spent)
        F.Log.trace("slowframe", "%s %.0f ms", name, spent)
    elseif F.Log.dev() then
        F.Log.stat("part." .. name .. ".ms", spent)
    end
end

-- The ForeverFlip window is on screen. IsVisible also counts the parents: the window keeps its own
-- "shown" flag inside the auction house frame after the auction house closes. Frames without a real
-- IsVisible (the tests' fakes) answer nil, and IsShown is asked then.
local function onScreen()
    local f = F.UI and F.UI.frame
    if not f then
        return false
    end
    local visible = f.IsVisible and f:IsVisible()
    if visible == nil then
        visible = f:IsShown()
    end
    return visible and true or false
end

function E.update(elapsed)
    if not F.db then
        return
    end
    local now = GetTime and GetTime() or E.clock()
    if E.urgent and F.UI and F.UI.refresh then
        E.urgent, E.dirty, paint = false, false, 0
        part("UI.refresh", F.UI.refresh)
    end
    part("AH.pump", F.AH.pump, now)
    if F.AH.isOpen() then
        F.AH.ready(true) -- watched every frame, so a stuck "not ready" is noticed
    end
    if not F.Deals.pending() then
        part("Scan.auto", F.Scan.auto)
    end
    part("Scan.step", F.Scan.step)
    part("Deals.step", F.Deals.step)
    part("Sniper.step", F.Sniper.step)
    part("Trade.step", F.Trade.step)
    part("Mail.step", F.Mail.step, now)
    part("Share.step", F.Share.step, now)
    part("Analytics.step", F.Analytics.step)
    if E.recipesDue and now >= E.recipesDue then
        E.recipesAt, E.recipesDue = now, nil
        part("Crafting.learn", F.Crafting.learn)
    end
    -- Timers on screen (the scan cooldown, a message running out) change without an event.
    tick = tick + (elapsed or 0)
    if tick >= 1 then
        tick = 0
        if onScreen() then
            E.dirty = true
        end
    end
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

-- One function for every frame: xpcall passes no arguments in Lua 5.1, and a closure built for each
-- frame would be garbage sixty times a second.
local updateElapsed
local function runUpdate()
    E.update(updateElapsed)
end
frame:SetScript("OnUpdate", function(_, elapsed)
    updateElapsed = elapsed
    local ok, err = xpcall(runUpdate, trace)
    if not ok then
        report(err)
    end
end)

-- Key bindings (Bindings.xml). A key press is a hardware event like a click.
-- Buy the next deal: the best deal ready to buy is selected (checked first when it needs it), and
-- each press moves it one step: check, buy, confirm.
function E.keyBuyNext()
    E.input()
    local T, UI = F.Trade, F.UI
    -- Only the To-vendor page on screen takes the key for its run: a hidden window keeps the page
    -- it showed last, and the key then buys the best deal like on any other page.
    if UI and UI.section == "deals" and UI.filter == "vendor" and onScreen() then
        local ok, why = T.runClick()
        if not ok then
            E.notify(why)
        end
        return
    end
    if T.op and T.op.state == "quoted" then
        if UI then
            UI.selected = T.op.key -- the confirmed purchase is the one on screen
        end
        T.confirm()
        return
    end
    local current = UI and UI.selected and F.Deals.fitWallet(F.Deals.get(UI.selected))
    local stuck = current and (current.cost > F.Engine.wallet() or T.overLimit(current.cost))
    if not current or T.busy() or stuck then
        local best = F.Deals.best()
        if not best then
            E.notify("no_deal")
            return
        end
        -- Selecting checks the deal when it needs it; the next press buys.
        if UI and UI.selectDeal then
            UI.selectDeal(best.key)
        elseif UI then
            UI.selected = best.key
        end
        local d = F.Deals.get(best.key)
        if not d or not d.verified or E.clock() - d.verified > F.Deals.FRESH then
            return
        end
    end
    E.keyBuy()
end

function E.keyBuy()
    E.input()
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
    E.input()
    local ok, why = F.Trade.postNext()
    if not ok and why == "nothing_to_post" then
        ok, why = F.Trade.postAll()
    end
    E.notify(why)
end

function E.keyCancel()
    E.input()
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
    if today and today.d ~= math.floor(E.clock() / 86400) then
        today = nil
    end
    local s = F.Market.saleability(h, usual, E.clock())
    return usual,
        today and today.min or nil,
        F.Market.salePrice(h),
        s.known and s.perDay or nil,
        at and E.clock() - at or nil
end

-- The current deal of an item: mode ("vendor", "flip", "shop", "disenchant"), profit, cost, units,
-- and whether it was checked on the auction house in the last five minutes.
function API.GetDeal(item)
    -- The deal list is the last open house's: once a neutral house closes, its deals are not on
    -- sale at the faction house the prices come from. A list without a house holds only checks
    -- made before the first scan, at the house open then.
    if F.Deals.scope and F.Deals.scope ~= E.scope() then
        return nil
    end
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

-- A slash command's answer: in the chat (the player asked for it) and in the message window.
local function say(text)
    F.Log.add("info", text, { chat = true, raw = true })
end

SLASH_FOREVERFLIP1 = "/ff"
SLASH_FOREVERFLIP2 = "/foreverflip"
SlashCmdList.FOREVERFLIP = function(msg)
    msg = string.lower(msg or "")
    local L = F.Locale.text
    if msg == "log" then
        -- ForeverFlip's chat tab (errors, deals, trade and scan notes), made again if it was closed.
        F.Log.show()
        return
    end
    if msg == "reset" then
        -- Everything saved goes, the settings stay: asked first (UI.confirmReset).
        if F.UI and F.UI.confirmReset then
            F.UI.confirmReset()
        end
        return
    end
    if msg == "stats rollback" then
        -- T32: the sales statistics of this house as they were before the last rebuild (kept a week).
        if F.Scan.rebuilding() then
            say("ForeverFlip: " .. L("The sales statistics are being rebuilt: try again once it ends."))
        elseif F.db and F.Data.rollbackStats(F.Data.market(F.db, E.scope())) then
            F.Deals.sureCache = {}
            say("ForeverFlip: " .. L("Sales statistics of this auction house are back as before the rebuild."))
            E.changed()
        else
            say("ForeverFlip: " .. L("No earlier sales statistics are kept for this auction house."))
        end
        return
    end
    if msg == "dump" then
        -- The auction house window frame by frame, in a box to copy (open it on the Buy tab).
        if F.UI and F.UI.showDump then
            F.UI.showDump()
        end
        return
    end
    if msg == "look" then
        -- The auction house's own category button, layer by layer, against ForeverFlip's.
        for _, line in ipairs(F.UI.lookReport()) do
            say("ForeverFlip look: " .. line)
        end
        return
    end
    if msg == "dev" then
        say("ForeverFlip: " .. F.Log.traceCommand("dev")[1])
        if F.UI and F.UI.refreshMessages then
            F.UI.refreshMessages()
        end
        return
    end
    if msg == "trace" or msg:match("^trace%s") then
        -- The saved timeline and times of searches, checks and slow frames (Log.trace).
        for _, line in ipairs(F.Log.traceCommand(msg:match("^trace%s+(.-)%s*$"))) do
            say(line)
        end
        return
    end
    if msg == "diag" then
        local blocked = F.db and type(F.db.blocked) == "table" and F.db.blocked or {}
        if #blocked == 0 then
            say("ForeverFlip: " .. L("No blocked action recorded."))
        end
        for _, b in ipairs(blocked) do
            -- The whole line goes to the developer, so its English words are translated; the event's
            -- name and the function name that the game gave are left as they are.
            say(
                string.format(
                    "ForeverFlip %s: %s %s, %s ago; %s",
                    tostring(b.version),
                    E.blockedKindText(b.event),
                    tostring(b.func),
                    F.UI and F.UI.age and F.UI.age(b.at) or tostring(b.at),
                    b.doing ~= "" and b.doing or "-"
                )
            )
        end
        local last = F.Scan.last
        if not last then
            say("ForeverFlip: " .. L("No full scan yet."))
            return
        end
        local s = last.stats
        say(
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
        -- The last full scan requests and how each ended.
        for i, e in ipairs(F.db.scanLog or {}) do
            if i > 5 then
                break
            end
            say(
                string.format(
                    "  %s: %s%s, %d auctions in the list, after %d s",
                    date and date("%H:%M", e.at) or tostring(e.at),
                    e.outcome,
                    e.other and " (another addon's request)" or "",
                    e.count or 0,
                    math.floor((e.ended or e.at) - e.at)
                )
            )
        end
        return
    end
    if msg == "bags" then
        -- Why bag items are not on the Sell page (the auction house must be open).
        local missing = F.AH.bagReport()
        say(string.format("ForeverFlip: " .. L("%d bag items are not on the Sell page."), #missing))
        for i = 1, math.min(30, #missing) do
            say("  " .. missing[i].link .. ": " .. missing[i].reason)
        end
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
        say("ForeverFlip: " .. L("the full scan can be requested again."))
        return
    end
    if msg == "refused" or msg:match("^refused%s") then
        -- The session's merchant refusals (AH.refused): what is left off Sell to vendor and To
        -- vendor. A wrong one (a sale the server was too busy to take) keeps a good item off both
        -- lists until the UI is reloaded, so "clear" forgets them all.
        local count = 0
        for _ in pairs(F.AH.refused or {}) do
            count = count + 1
        end
        if msg:match("^refused%s+clear") then
            for id in pairs(F.AH.refused or {}) do
                F.AH.refused[id] = nil
            end
            say(string.format("ForeverFlip: " .. L("%d merchant refusals forgotten."), count))
            F.Engine.changed()
            return
        end
        local list = {}
        for id in pairs(F.AH.refused or {}) do
            list[#list + 1] = id
        end
        table.sort(list)
        say(string.format("ForeverFlip: " .. L("%d items a merchant refused this session."), #list))
        for i = 1, math.min(20, #list) do
            say("  " .. (U.itemInfo(list[i]) or "item") .. " (" .. list[i] .. ")")
        end
        if #list > 0 then
            say("ForeverFlip: " .. L("/ff refused clear forgets them."))
        end
        return
    end
    local lang = msg:match("^lang%s+(%a+)$")
    if lang == "en" or lang == "uk" then
        F.db.settings.language = lang
        say("ForeverFlip: /reload")
        return
    end
    say(
        "ForeverFlip "
            .. F.version
            .. ": "
            .. L("open the auction house and use the ForeverFlip tab.")
            .. " /ff log, /ff diag, /ff trace"
    )
end
