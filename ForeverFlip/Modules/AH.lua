-- The only file that talks to the game's auction house API. Tests replace F.AH with a fake.
-- Facts used here were seen in game on WoW Forever:
--  * an item search row is a bucket of identical auctions; its price is for one item and PlaceBid
--    buys one auction;
--  * gear links have an empty suffix field and one ending is split over several item-key
--    versions; gear is told apart by its full name (the link text carries the ending);
--  * a sell search (SendSellSearchQuery) is never answered (seen by ForeverForge Auction), so gear
--    is searched in two steps: a browse by name gives its item-key versions, then each version is
--    searched (SendSearchQuery);
--  * the throttle check can stay "not ready" for good after a message the server never answered;
--  * commodities are bought with a quote (StartCommoditiesPurchase) and a confirmation;
--  * the server pays less than the client's item data says for some items (recipes listed at 2s
--    sell for 1s 50c; a wand went from 15s to 1c in a patch, seen by ForeverForge): what a merchant
--    really paid is read from the buyback list (F.Merchant.learnBuyback).
local F = ForeverFlip
local U = F.Util
local A = {}
F.AH = A

local AH = C_AuctionHouse

local function plainKey(id)
    return { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
end

-- kinds: the auction house's own answer (item-key info). guesses: a bag item's kind worked out
-- before that answer (kindOfBagItem), used only until the answer comes. Kept as if it were the
-- answer, a wrong guess moved the item to another key once the auction house listed it.
local kinds, guesses = {}, {}
-- "commodity", "gear" or "item"; nil while the game has not loaded the item.
function A.kindOf(id)
    if kinds[id] then
        return kinds[id]
    end
    local ok, info = pcall(AH.GetItemKeyInfo, plainKey(id))
    if not ok or type(info) ~= "table" then
        A.requestItem(id)
        return guesses[id]
    end
    local kind = info.isCommodity and "commodity" or info.isEquipment and "gear" or "item"
    kinds[id], guesses[id] = kind, nil
    return kind
end

-- Gear whose links carry an ending its own name lacks ("Northern Shortsword of Healing"): told by
-- the first link read with a name this session, or by the endings of versions searched before.
local endings = {}
local function otherName(name, base)
    return type(name) == "string" and name ~= "" and name ~= base
end
local function hasEndings(id, base)
    if endings[id] then
        return true
    end
    base = string.lower(base)
    local e = F.db and type(F.db.itemKeys) == "table" and F.db.itemKeys[id]
    for _, v in ipairs(type(e) == "table" and type(e.list) == "table" and e.list or {}) do
        if otherName(v.e, base) or otherName(v.n, base) then
            return true
        end
    end
    return false
end

function A.keyFor(id, link)
    local kind = A.kindOf(id)
    if not kind then
        return nil
    end
    if kind == "gear" then
        local name = U.linkName(link)
        if name and name ~= "" then
            if endings[id] == nil then
                local base = U.itemInfo(id)
                if base then
                    endings[id] = string.lower(name) ~= string.lower(base)
                end
            end
            return U.key(kind, id, name), kind
        end
        -- The game hands out links with an empty name ("[]") while the item is not loaded (own
        -- auctions, in game): the item's own name then, and its data is asked for. Not for gear
        -- with endings: its own name names no lot, so the key stays unknown and the read is tried
        -- again (Trade.onOwned) until the link carries the ending.
        name = U.itemInfo(id)
        if not name or name == "" or hasEndings(id, name) then
            A.requestItem(id)
            return nil
        end
        return U.key(kind, id, name), kind
    end
    return U.key(kind, id), kind
end

-- Equipment the player's class can never wear or wield (WoW classic proficiencies). Armor up to its
-- type the class learns later (mail, plate at 40) counts as wearable; cloaks, rings, necks,
-- trinkets, off-hand items and other "miscellaneous" equipment fit every class.
local WEAPONS = {
    WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
    PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
    HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 },
    ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
    PRIEST = { 4, 10, 15, 19 },
    SHAMAN = { 0, 1, 4, 5, 10, 13, 15 },
    MAGE = { 7, 10, 15, 19 },
    WARLOCK = { 7, 10, 15, 19 },
    DRUID = { 4, 5, 10, 13, 15 },
}
local ARMOR = {
    WARRIOR = { 1, 2, 3, 4, 6 },
    PALADIN = { 1, 2, 3, 4, 6, 7 },
    HUNTER = { 1, 2, 3 },
    ROGUE = { 1, 2 },
    PRIEST = { 1 },
    SHAMAN = { 1, 2, 3, 6, 9 },
    MAGE = { 1 },
    WARLOCK = { 1 },
    DRUID = { 1, 2, 8 },
}
local EVERYONE = {
    INVTYPE_CLOAK = true,
    INVTYPE_HOLDABLE = true,
    INVTYPE_FINGER = true,
    INVTYPE_NECK = true,
    INVTYPE_TRINKET = true,
    INVTYPE_BODY = true,
    INVTYPE_TABARD = true,
}

local function has(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then
            return true
        end
    end
    return false
end

-- Retail (Midnight) proficiencies. Every class wears the armor below its own, so only heavier
-- armor is out; relics are gone. Ranged weapons stay allowed where unsure: a piece left out is only
-- not sold, a wrong one would be.
local RETAIL_WEAPONS = {
    WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
    PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
    DEATHKNIGHT = { 0, 1, 4, 5, 6, 7, 8 },
    HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 18 },
    ROGUE = { 0, 2, 3, 4, 7, 13, 15, 16, 18 },
    PRIEST = { 4, 10, 15, 19 },
    SHAMAN = { 0, 1, 4, 5, 10, 13, 15 },
    MAGE = { 7, 10, 15, 19 },
    WARLOCK = { 7, 10, 15, 19 },
    MONK = { 0, 4, 6, 7, 10, 13 },
    DRUID = { 4, 5, 6, 10, 13, 15 },
    DEMONHUNTER = { 0, 7, 9, 13, 15 },
    EVOKER = { 0, 1, 4, 5, 7, 8, 10, 13, 15 },
}
local RETAIL_ARMOR = {
    WARRIOR = { 1, 2, 3, 4, 6 },
    PALADIN = { 1, 2, 3, 4, 6 },
    DEATHKNIGHT = { 1, 2, 3, 4 },
    HUNTER = { 1, 2, 3 },
    SHAMAN = { 1, 2, 3, 6 },
    EVOKER = { 1, 2, 3 },
    ROGUE = { 1, 2 },
    MONK = { 1, 2 },
    DRUID = { 1, 2 },
    DEMONHUNTER = { 1, 2 },
    PRIEST = { 1 },
    MAGE = { 1 },
    WARLOCK = { 1 },
}
-- Main stats any specialization of the class uses: a respec makes the others' gear wearable.
local MAIN_STATS = {
    WARRIOR = { "STRENGTH" },
    PALADIN = { "STRENGTH", "INTELLECT" },
    DEATHKNIGHT = { "STRENGTH" },
    HUNTER = { "AGILITY" },
    ROGUE = { "AGILITY" },
    DEMONHUNTER = { "AGILITY" },
    MONK = { "AGILITY", "INTELLECT" },
    DRUID = { "AGILITY", "INTELLECT" },
    SHAMAN = { "AGILITY", "INTELLECT" },
    EVOKER = { "INTELLECT" },
    PRIEST = { "INTELLECT" },
    MAGE = { "INTELLECT" },
    WARLOCK = { "INTELLECT" },
}
local ACCOUNT_BINDS = { [7] = true, [8] = true, [9] = true } -- heirloom and warband binds

-- Gear bound to the account (heirlooms, warband pieces) goes to an alt instead of a merchant.
local function accountBound(id)
    if C_Item and C_Item.IsItemBindToAccount and C_Item.IsItemBindToAccount(id) then
        return true
    end
    if C_Item and C_Item.IsItemBindToAccountUntilEquip and C_Item.IsItemBindToAccountUntilEquip(id) then
        return true
    end
    local bind = select(14, U.itemInfo(id))
    return ACCOUNT_BINDS[bind] == true
end

-- false when the piece carries a main stat some specialization of the class uses, or none at all;
-- true only when every main stat on it is one no specialization of the class uses.
local function wrongMainStat(link, class)
    local read = C_Item and C_Item.GetItemStats or (not C_Item and GetItemStats)
    local wanted = MAIN_STATS[class]
    if not link or not read or not wanted then
        return false
    end
    local ok, stats = pcall(read, link)
    if not ok or type(stats) ~= "table" then
        return false
    end
    local any = false
    for name in pairs(stats) do
        local main = false
        for _, stat in ipairs({ "STRENGTH", "AGILITY", "INTELLECT" }) do
            if string.find(name, stat, 1, true) then
                main = true
                for _, w in ipairs(wanted) do
                    if w == stat then
                        return false
                    end
                end
            end
        end
        any = any or main
    end
    return any
end

-- true: equipment the class can never use; false: usable (or not equipment); nil: unknown. On
-- Retail a piece whose main stat no specialization of the class uses counts too (link needed), and
-- gear bound to the account never does: an alt can wear it.
function A.unusableGear(id, link)
    local info = C_Item and C_Item.GetItemInfoInstant
    if not info then
        return nil
    end
    local _, _, _, equipLoc, _, classID, subclassID = info(id)
    if not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_BAG" then
        return false
    end
    if accountBound(id) then
        return false
    end
    local class = UnitClass and select(2, UnitClass("player"))
    local retail = A.isRetail()
    local weapons, armor = WEAPONS, ARMOR
    if retail then
        weapons, armor = RETAIL_WEAPONS, RETAIL_ARMOR
    end
    if not class or not weapons[class] then
        return nil
    end
    if retail and wrongMainStat(link, class) then
        return true
    end
    if EVERYONE[equipLoc] then
        return false
    end
    if classID == 2 then
        if subclassID == 14 or subclassID == 20 then
            return false -- miscellaneous weapons, fishing poles
        end
        return not has(weapons[class], subclassID)
    elseif classID == 4 then
        if subclassID == 0 or (retail and subclassID == 5) then
            return false -- miscellaneous and cosmetic
        end
        return not has(armor[class], subclassID)
    end
    return false
end

-- Item data requests. At a fixed 40 a second the 16 000 items of a busy house took seven minutes
-- to load after a full scan. Now up to A.ITEM_BATCH go every 0.1 seconds while fewer than
-- A.ITEM_IN_FLIGHT are unanswered: each ITEM_DATA_LOAD_RESULT (A.itemArrived) frees a place, so
-- the pace follows how fast the game answers. A request unanswered for 5 seconds frees its place
-- and may be sent again. The queue is read from a head index: taking the first of many entries off
-- the list moved all the others each time.
A.ITEM_BATCH = 100
A.ITEM_IN_FLIGHT = 400
A.ITEM_QUEUE = 20000
local queue, head, tail, queued, nextPump, sentAt = {}, 1, 0, {}, 0, {}
local inFlight = 0
function A.itemArrived(id)
    if sentAt[id] then
        sentAt[id] = nil
        inFlight = math.max(0, inFlight - 1)
    end
end
-- Requests unanswered for 5 seconds no longer hold a place (only looked for when all are taken).
local function dropLost(now)
    for id, at in pairs(sentAt) do
        if now - at >= 5 then
            sentAt[id] = nil
            inFlight = math.max(0, inFlight - 1)
        end
    end
end
function A.requestItem(id)
    if queued[id] or tail - head + 1 >= A.ITEM_QUEUE then
        return
    end
    local t = GetTime and GetTime() or 0
    if sentAt[id] and t - sentAt[id] < 5 then
        return -- asked for a moment ago: its answer is on the way
    end
    if C_Item and C_Item.IsItemDataCachedByID and C_Item.IsItemDataCachedByID(id) then
        return
    end
    queued[id] = true
    tail = tail + 1
    queue[tail] = id
end
function A.pump(now)
    if now < nextPump then
        return
    end
    nextPump = now + 0.1
    if inFlight >= A.ITEM_IN_FLIGHT then
        dropLost(now)
    end
    for _ = 1, A.ITEM_BATCH do
        if head > tail then
            head, tail = 1, 0
            return
        end
        if inFlight >= A.ITEM_IN_FLIGHT then
            return
        end
        local id = queue[head]
        queue[head], head = nil, head + 1
        queued[id] = nil
        if not sentAt[id] then
            inFlight = inFlight + 1
        end
        sentAt[id] = now
        if C_Item and C_Item.RequestLoadItemDataByID then
            pcall(C_Item.RequestLoadItemDataByID, id)
        end
    end
end

-- The client's vendor sell price, remembered between sessions. Uncached items are only queued for
-- loading: GetItemInfo on an uncached item sends a server query of its own.
function A.clientVendorPrice(id)
    local saved = F.db and F.db.vendor
    local name, _, _, _, _, _, _, _, _, _, price = U.itemInfo(id)
    if not name then
        price = nil
    end
    if price == nil then
        if saved and saved[id] ~= nil then
            return saved[id] > 0 and saved[id] or nil
        end
        A.requestItem(id)
        return nil
    end
    if saved then
        saved[id] = price
    end
    return price > 0 and price or nil
end

-- What a merchant pays for one, and how it is known:
--  "client"   the client's item data (the game's own "Sell Price" line): what merchants pay. Of 115
--             items sold by hand and read back from the buyback list (17 November), 113 were paid
--             exactly this, and the other two were worn gear, which pays less for its wear;
--  "seen"     a merchant paid a different price for a non-gear item (buyback list): the server's
--             own price, used from then on. Gear keeps the client's price (a lower price seen is
--             wear), unless the client has none;
--  "estimate" the client's price less the safety margin (setting vendorMargin, percent, 0 by
--             default), for deals.
-- nil when the vendor does not buy the item or its data has not loaded.
function A.vendorPrice(id, raw)
    local seen = F.db and F.db.vendorSeen and F.db.vendorSeen[id]
    local price = A.clientVendorPrice(id)
    if type(seen) == "table" and U.finite(seen.p) and (not price or (seen.p ~= price and A.kindOf(id) ~= "gear")) then
        if seen.p <= 0 then
            return nil, "seen"
        end
        return seen.p, "seen"
    end
    if not price then
        return nil
    end
    local margin = not raw and F.db and tonumber(F.db.settings.vendorMargin) or 0
    if margin > 0 then
        return math.max(1, math.floor(price * (1 - math.min(90, margin) / 100))), "estimate"
    end
    return price, "client"
end

-- True when the vendor price is known, also when it is zero (the vendor does not buy the item).
function A.vendorKnown(id)
    local saved = F.db and F.db.vendor
    if saved and saved[id] ~= nil then
        return true
    end
    return U.itemInfo(id) ~= nil
end

function A.isOpen()
    return AuctionHouseFrame and AuctionHouseFrame:IsShown() or false
end

-- Is the server ready for the next auction house message? The client can get stuck on "not ready"
-- after a message the server never answered, and then nothing would ever be sent again until the
-- auction house is closed: after A.STUCK seconds of "not ready", watched without a break, one
-- message goes through (the worst it does is get dropped, which is handled). peek: only watch.
A.STUCK = 5
local notReadySince, lastCheck
function A.ready(peek)
    if not AH.IsThrottledMessageSystemReady then
        return true
    end
    local t = GetTime and GetTime() or time()
    local gap = lastCheck and t - lastCheck or math.huge
    lastCheck = t
    if AH.IsThrottledMessageSystemReady() then
        notReadySince = nil
        return true
    end
    if gap > 1 then
        notReadySince = nil
    end
    notReadySince = notReadySince or t
    if not peek and t - notReadySince >= A.STUCK then
        notReadySince = t
        A.forced = (A.forced or 0) + 1
        return true
    end
    return false
end

-- Observe whether a click could send, including the existing stuck-client recovery.
-- Painting a button must not spend that allowance before its click can use it.
function A.available()
    if A.ready(true) then
        return true
    end
    local t = GetTime and GetTime() or time()
    return notReadySince ~= nil and t - notReadySince >= A.STUCK
end

-- AUCTION_HOUSE_THROTTLED_SYSTEM_READY, or the auction house closed.
function A.throttleReset()
    notReadySince, lastCheck = nil, nil
end

-- Is this owner the player? Owner lists name the player "player" (TSM normalises it the same way),
-- or give the name, with the realm for a connected realm. Names are not unique on WoW Forever, so
-- a name with another realm is somebody else. The names are worked out once (A.refreshPlayer, at
-- each scan and when the auction house opens): this runs for every row of a full scan.
local myName, myFullName
-- Whether commodity prices may carry copper (U.commodityStep). A client without the call is WoW
-- Forever's kind, which takes copper. Retail (interface 100000 and up) lists whole silver only even
-- when SupportsCopperValues() does not say false: its server dropped a post of 299 copper without
-- an answer, and every price on its market is whole silver.
A.RETAIL_INTERFACE = 100000
function A.isRetail()
    local interface = GetBuildInfo and select(4, GetBuildInfo())
    return type(interface) == "number" and interface >= A.RETAIL_INTERFACE, interface
end
function A.readPriceStep()
    local ok, copper = pcall(function()
        return AH.SupportsCopperValues()
    end)
    local retail, interface = A.isRetail()
    U.commodityStep = ((ok and copper == false) or retail) and 100 or 1
    F.Log.devTrace(
        "post.step",
        "commodity step %d (SupportsCopperValues %s %s, interface %s)",
        U.commodityStep,
        tostring(ok),
        tostring(copper),
        tostring(interface)
    )
end

function A.refreshPlayer()
    myName = UnitName and UnitName("player") or nil
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName())
        or (GetRealmName and (GetRealmName() or ""):gsub("[%s%-]", ""))
    myFullName = myName and realm and realm ~= "" and (myName .. "-" .. realm) or nil
end
function A.isPlayer(owner)
    if not owner or owner == "" then
        return false
    end
    if not myName then
        A.refreshPlayer()
    end
    return owner == "player" or owner == myName or owner == myFullName
end

-- Full scan -------------------------------------------------------------------------------------
function A.replicate()
    A.replicating = true -- our own call: the ReplicateItems hook ignores it
    local ok, err = pcall(AH.ReplicateItems)
    A.replicating = false
    if not ok then
        error(err, 0)
    end
end
function A.replicateCount()
    return AH.GetNumReplicateItems() or 0
end
-- A short mark of the replicated list: its size and a few auctions (first, middle, last). A new
-- answer of the same size is told apart from the list of the previous scan by it.
function A.replicateMark()
    local n = A.replicateCount()
    if n <= 0 then
        return "0"
    end
    local parts = { tostring(n) }
    for _, i in ipairs({ 0, math.floor(n / 2), n - 1 }) do
        local ok, _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, id = pcall(AH.GetReplicateItemInfo, i)
        parts[#parts + 1] = ok and (tostring(id) .. "x" .. tostring(count) .. "@" .. tostring(buyout)) or "?"
    end
    return table.concat(parts, ":")
end
-- One auction of the full scan: buyout is for the whole stack. With `raw`, also every field as the
-- server sent it (second result), read before the game has loaded the item too.
-- The raw fields are one table, filled again for each row: they are read once, as the row is read
-- (F.Raw.capture turns them into a line at once), and a new table for each of 290 000 rows was work
-- for the garbage collector.
local rawFields = {}
local function replicateRead(i, raw)
    local _, _, count, _, _, _, _, minBid, increment, buyout, bidAmount, _, _, owner, _, _, id, complete =
        AH.GetReplicateItemInfo(i)
    if not id then
        return nil
    end
    local band, link
    if complete or raw then
        if AH.GetReplicateItemTimeLeft then
            local ok, left = pcall(AH.GetReplicateItemTimeLeft, i)
            band = ok and U.finite(left) and math.max(0, math.min(3, left - 1)) or nil
        end
        link = AH.GetReplicateItemLink and AH.GetReplicateItemLink(i) or nil
    end
    local row
    if complete then
        row = {
            id = id,
            count = count or 1,
            buyout = buyout or 0,
            owner = owner,
            band = band,
            minBid = (bidAmount or 0) > 0 and bidAmount + (increment or 0) or minBid,
            link = link,
            complete = true,
        }
    else
        row = { id = id, complete = false }
    end
    if not raw then
        return row
    end
    local fields = rawFields
    fields.id, fields.count, fields.buyout, fields.minBid = id, count, buyout, minBid
    fields.bid, fields.band, fields.own, fields.link = bidAmount, band, A.isPlayer(owner), link
    return row, fields
end
function A.replicateRow(i)
    return (replicateRead(i, false))
end

-- Every field of a full-scan auction, also before the game has loaded the item (raw scans), and the
-- auction as A.replicateRow reads it, from one read. The fields table is filled again by the next
-- call: use it before reading another row: read for each separately, every row of a scan
-- (up to 290 000) asked the client six times.
function A.replicateRaw(i)
    local row, raw = replicateRead(i, true)
    return raw, row
end

-- The full scan tells how long each auction has left: sales can be tracked lot by lot.
function A.canTrackLots()
    return AH.GetReplicateItemTimeLeft ~= nil
end

-- Exact search ----------------------------------------------------------------------------------
local SORTS = nil
local function sorts()
    SORTS = SORTS or { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
    return SORTS
end
-- A.ownSearch marks ForeverFlip's own item searches for the hooks (A.hookBrowse): only searches
-- nobody here sent are the player's.
local function ownSearch(fn, ...)
    A.ownSearch = true
    local ok, err = pcall(fn, ...)
    A.ownSearch = false
    if not ok then
        error(err, 0)
    end
end
function A.search(item)
    A.noteItemSearch(plainKey(item.id))
    if item.kind == "gear" and AH.SendSellSearchQuery then
        ownSearch(AH.SendSellSearchQuery, plainKey(item.id), sorts(), true)
    else
        ownSearch(AH.SendSearchQuery, plainKey(item.id), sorts(), true)
    end
end

-- Browse rows of the current answer whose item-key versions were learned (A.learnKeys). Every
-- browse sent, ours or another addon's (the hook), replaces the results: reading starts over.
local learnedRows = 0

-- Gear in two steps (see the top of the file). Step 1: a browse by the item's own name (without
-- the ending), which lists its item-key versions.
function A.canSearchGear()
    return A.canBrowse()
end
function A.gearBrowse(item)
    local name = U.itemInfo(item.id)
    learnedRows = 0
    A.ownBrowse = true
    local ok, err = pcall(AH.SendBrowseQuery, {
        searchString = name or item.name or "",
        sorts = sorts(),
        filters = {},
        itemClassFilters = {},
    })
    A.ownBrowse = false
    if not ok then
        error(err, 0)
    end
end

-- The server sells an auction of gear or an item only from the last item search: once another item
-- was searched (Check all, the game's Buy tab, another addon), a purchase of the earlier one is
-- dropped without an answer (seen in game). Every item search is noted, whoever sends it.
function A.noteItemSearch(itemKey)
    if type(itemKey) == "table" and itemKey.itemID then
        A.lastItemSearch = { id = itemKey.itemID, at = F.Engine.clock() }
    end
end
function A.searchedLast(id)
    local s = A.lastItemSearch
    return s == nil or s.id == id
end

-- Browse queries ForeverFlip did not send (the game's Buy tab, another addon) replace the results:
-- a gear search waiting for its own answer is told (Deals.onForeignBrowse).
--
-- A search ForeverFlip did not send while its own page is hidden is the player's, in the game's Buy
-- tab: background work (the sniper, automatic checks) gives way to it (A.playerUse). The hooks only
-- listen (hooksecurefunc); nothing of the game's call is changed.
function A.hookBrowse()
    if A.browseHooked or not hooksecurefunc or not AH.SendBrowseQuery then
        return
    end
    A.browseHooked = true
    local function player()
        if A.ownBrowse or A.ownSearch then
            return
        end
        if F.Engine.screen().shown then
            return -- ForeverFlip's page is shown, not the Buy tab: another addon searched
        end
        A.playerAt = F.Engine.clock()
        if F.Sniper and F.Sniper.onPlayerQuery then
            F.Sniper.onPlayerQuery()
        end
    end
    for _, name in ipairs({ "SendSearchQuery", "SendSellSearchQuery" }) do
        if AH[name] then
            hooksecurefunc(AH, name, function(itemKey)
                A.noteItemSearch(itemKey)
                if name == "SendSearchQuery" then
                    player()
                end
            end)
        end
    end
    for _, name in ipairs({ "SendBrowseQuery", "SearchForItemKeys" }) do
        if AH[name] then
            hooksecurefunc(AH, name, function()
                learnedRows = 0
                if not A.ownBrowse then
                    A.foreignAt = F.Engine.clock()
                    F.Deals.onForeignBrowse()
                    player()
                end
            end)
        end
    end
    -- The Buy tab's favorites list: ForeverFlip never asks for it.
    if AH.SearchForFavorites then
        hooksecurefunc(AH, "SearchForFavorites", function()
            learnedRows = 0
            A.foreignAt = F.Engine.clock()
            F.Deals.onForeignBrowse()
            player()
        end)
    end
end
-- True when somebody else sent a browse a moment ago: its answer may still be on the way, and would
-- arrive after (and be read as) the answer to a browse sent now.
A.FOREIGN_WAIT = 10
function A.foreignRecent()
    return A.foreignAt ~= nil and F.Engine.clock() - A.foreignAt < A.FOREIGN_WAIT
end

-- Item-key versions, learned from owned auctions and browse answers (ours or other addons) and
-- kept between sessions: F.db.itemKeys[id] = { at = time, list = { { l = level, s = suffix,
-- n = lower-case name or nil }, ... } }. A check of gear then searches its versions straight away
-- (one search per version of the ending) instead of a browse by name first and every version of
-- every ending after it: a gear check took 17 searches for an item listed in 16 endings, and the
-- browse filled the game's own Buy tab with that item (seen in game). As Auctionator does, the
-- item-key info is in the client's cache before a version is searched.
A.KEYS_FRESH = 6 * 3600
A.KEYS_MAX = 60
-- Every item browsed gets an entry: those not seen for two weeks are forgotten, once a session.
A.KEYS_KEEP = 14 * 86400
local keysPruned = false
local function pruneKeys()
    keysPruned = true
    local now = F.Engine.clock()
    for id, e in pairs(F.db.itemKeys) do
        if type(e) ~= "table" or not U.finite(e.at) or now - e.at > A.KEYS_KEEP then
            F.db.itemKeys[id] = nil
        end
    end
end
function A.rememberKey(key, link, owned)
    local id = type(key) == "table" and key.itemID
    if not F.db or not id or kinds[id] == "commodity" then
        return
    end
    local info = select(2, pcall(AH.GetItemKeyInfo, key))
    if type(info) == "table" then
        kinds[id] = info.isCommodity and "commodity" or info.isEquipment and "gear" or "item"
        guesses[id] = nil
    end
    if kinds[id] == "commodity" then
        return
    end
    -- One owned gear version does not describe every version of the same ending.
    -- Its complete candidate list still comes from browsing, as before.
    if owned and kinds[id] ~= "item" then
        return
    end
    F.db.itemKeys = type(F.db.itemKeys) == "table" and F.db.itemKeys or {}
    if not keysPruned then
        pruneKeys()
    end
    local e = F.db.itemKeys[id]
    if type(e) ~= "table" or type(e.list) ~= "table" then
        e = { list = {} }
        F.db.itemKeys[id] = e
    end
    e.at = F.Engine.clock()
    local name = U.linkName(link) or (type(info) == "table" and info.itemName)
    name = type(name) == "string" and string.lower(name) or nil
    local level, suffix = key.itemLevel or 0, key.itemSuffix or 0
    for _, v in ipairs(e.list) do
        if v.l == level and v.s == suffix then
            v.n = name or v.n
            return
        end
    end
    if #e.list < A.KEYS_MAX then
        e.list[#e.list + 1] = { l = level, s = suffix, n = name }
    end
end

-- Each browse answer event learns only the rows added since the last one (learnedRows): a
-- whole-house browse comes in 16 pages, and reading every row again on each page made 73,000
-- reads of 7,700 items. updated: the answer replaced the results (a new browse).
function A.learnKeys(updated)
    if not F.db then
        return
    end
    local ok, results = pcall(AH.GetBrowseResults)
    if not ok or type(results) ~= "table" then
        return
    end
    if updated or #results < learnedRows then
        learnedRows = 0
    end
    for i = learnedRows + 1, #results do
        local r = results[i]
        A.rememberKey(type(r) == "table" and r.itemKey)
    end
    learnedRows = #results
end

-- The versions to search for `item` (gear: those named like its ending when the names are known,
-- else every version of the item), or nil when none were learned lately: a browse then.
function A.cachedKeys(item)
    local all = F.db and type(F.db.itemKeys) == "table" and F.db.itemKeys[item.id]
    if type(all) ~= "table" or type(all.list) ~= "table" or #all.list == 0 then
        return nil
    end
    if F.Engine.clock() - (all.at or 0) > A.KEYS_FRESH then
        return nil
    end
    -- A version whose ending is not known yet may be this one: it is searched too. Only versions
    -- known to carry another ending are left out. Returns the keys, and true when they are every
    -- version of the item (their rows then answer every ending of it at once).
    local exact, every, named = {}, {}, false
    for _, v in ipairs(all.list) do
        local key = { itemID = item.id, itemLevel = v.l or 0, itemSuffix = v.s or 0, battlePetSpeciesID = 0 }
        every[#every + 1] = key
        local own = item.name and (v.n == item.name or v.e == item.name)
        if own then
            named = true
        end
        -- v.e: the ending read from a lot's link (the game's own name of a version is often the
        -- item's name without its ending, which tells nothing).
        if own or (item.name and v.e == nil) then
            exact[#exact + 1] = key
        end
    end
    if named then
        return exact, #exact == #every
    end
    return every, true
end

-- Every other player's lot of one item-key version, whatever its ending, and the ending's name
-- (lower case; one version is one ending). The name is remembered for the version, so the next
-- check of the item searches only the versions of its own ending.
function A.versionRows(searchKey)
    local rows, name, link, mixed = {}, nil, nil, false
    for i = 1, (AH.GetNumItemSearchResults(searchKey) or 0) do
        local r = AH.GetItemSearchResultInfo(searchKey, i)
        if r and r.itemLink then
            local this = string.lower(U.linkName(r.itemLink) or "")
            if not link then
                link, name = r.itemLink, this
            elseif this ~= name then
                mixed = true -- more than one ending under one version: nothing is learned
            end
        end
        if
            r
            and (r.buyoutAmount or 0) > 0
            and (r.quantity or 0) > 0
            and not r.containsOwnerItem
            and not r.containsAccountItem
        then
            rows[#rows + 1] = { unit = r.buyoutAmount, qty = r.quantity, auctionID = r.auctionID, link = r.itemLink }
        end
    end
    if link and name ~= "" and not mixed then
        A.rememberKey(searchKey, link)
        local e = F.db and type(F.db.itemKeys) == "table" and F.db.itemKeys[searchKey.itemID]
        for _, v in ipairs(type(e) == "table" and type(e.list) == "table" and e.list or {}) do
            if v.l == (searchKey.itemLevel or 0) and v.s == (searchKey.itemSuffix or 0) then
                v.e = name
            end
        end
        return name, rows
    end
    return nil, rows, mixed
end

function A.forgetKeys(id)
    if F.db and type(F.db.itemKeys) == "table" then
        F.db.itemKeys[id] = nil
    end
end

-- The client knows the item's auction house data: a search of it is answered. Without it the
-- server often ignores the search (Auctionator waits for it too); the data is asked for.
function A.keyInfoReady(item, key)
    local ok, info = pcall(AH.GetItemKeyInfo, key or plainKey(item.id))
    if ok and type(info) == "table" then
        return true
    end
    A.requestItem(item.id)
    return false
end

-- The game's own Buy, Sell or Auctions page is shown: the player works there, and a search sent
-- now would replace what that page shows. Background searches wait meanwhile.
--
-- That check alone was not enough: it looks only at the moment a query is sent. A query sent a
-- moment before the player opened the Buy tab took the player's own browse answer for its own and
-- asked for its next pages, and nothing knew the player had searched. Now the player's searches are
-- heard too (A.hookBrowse): for A.PLAYER_IDLE seconds after one, background work waits, unless
-- ForeverFlip's own page is shown or the game's pages read as left. Pages are only read through the
-- widget API (IsShown); nothing is called on or written into them.
A.PLAYER_IDLE = 60
local PURCHASE = { "ItemBuyFrame", "CommoditiesBuyFrame", "BuyDialog" }
local SELL = { "ItemSellFrame", "CommoditiesSellFrame" }
local function page(name)
    local p = rawget(AuctionHouseFrame, name)
    if type(p) == "table" and p.IsShown then
        return p
    end
end
local function anyShown(names)
    for _, name in ipairs(names) do
        local p = page(name)
        if p and p:IsShown() then
            return true
        end
    end
    return false
end
-- Why the player's use of the game's own pages holds background work, or nil: "purchase" (an item
-- or commodity purchase page or its confirmation), "buy" (the Buy tab's list, or a search of the
-- player's within A.PLAYER_IDLE seconds), "sell" (the game's Sell page).
function A.playerUse()
    local f = AuctionHouseFrame
    if not f or not f.IsShown or not f:IsShown() then
        return nil
    end
    if anyShown(PURCHASE) then
        return "purchase"
    end
    local browse = page("BrowseResultsFrame")
    if browse and browse:IsShown() then
        return "buy"
    end
    if anyShown(SELL) then
        return "sell"
    end
    if A.playerAt and F.Engine.clock() - A.playerAt < A.PLAYER_IDLE then
        if F.Engine.screen().shown then
            return nil -- back on ForeverFlip's page
        end
        if browse then
            return nil -- the Buy tab reads as hidden: the player left it
        end
        return "buy"
    end
    return nil
end
function A.nativeShown()
    return A.playerUse() ~= nil
end

-- The item-key versions of `id` in the browse results so far. With `name` (an ending), versions
-- known to carry another ending are left out; the second result is true when none was.
function A.gearKeys(id, name)
    local out, skipped = {}, false
    local known = {}
    local e = name and F.db and type(F.db.itemKeys) == "table" and F.db.itemKeys[id]
    for _, v in ipairs(type(e) == "table" and type(e.list) == "table" and e.list or {}) do
        known[(v.l or 0) .. ":" .. (v.s or 0)] = v.e
    end
    local ok, results = pcall(AH.GetBrowseResults)
    for _, r in ipairs(ok and results or {}) do
        local k = r.itemKey
        if type(k) == "table" and k.itemID == id then
            local n = known[(k.itemLevel or 0) .. ":" .. (k.itemSuffix or 0)]
            if n == nil or n == name then
                out[#out + 1] = k
            else
                skipped = true
            end
        end
    end
    return out, not skipped
end
-- Step 2: one exact version, and its next page.
function A.searchKey(key)
    A.noteItemSearch(key)
    ownSearch(AH.SendSearchQuery, key, sorts(), true)
end
function A.moreKey(key)
    AH.RequestMoreItemSearchResults(key)
end
function A.more(item)
    if item.kind == "commodity" then
        AH.RequestMoreCommoditySearchResults(item.id)
    else
        AH.RequestMoreItemSearchResults(plainKey(item.id))
    end
end
-- Listings of other players, cheapest first: {unit, qty, auctionID}. Returns rows, complete, and
-- the number of results the answer holds so far, those left out included (the player's own lots,
-- bids, other endings): a next page of only those adds no row, yet it is the page asked for.
function A.rows(item, searchKey)
    local rows, complete, count = {}, false, 0
    if item.kind == "commodity" then
        complete = AH.HasFullCommoditySearchResults(item.id)
        count = AH.GetNumCommoditySearchResults(item.id) or 0
        for i = 1, count do
            local r = AH.GetCommoditySearchResultInfo(item.id, i)
            local qty = r and (r.quantity - (r.numOwnerItems or 0)) or 0
            if r and qty > 0 and (r.unitPrice or 0) > 0 then
                rows[#rows + 1] = { unit = r.unitPrice, qty = qty, auctionID = r.auctionID }
            end
        end
    else
        local key = type(searchKey) == "table" and searchKey or plainKey(item.id)
        complete = AH.HasFullItemSearchResults(key)
        count = AH.GetNumItemSearchResults(key) or 0
        for i = 1, count do
            local r = AH.GetItemSearchResultInfo(key, i)
            if
                r
                and (r.buyoutAmount or 0) > 0
                and (r.quantity or 0) > 0
                and not r.containsOwnerItem
                and not r.containsAccountItem
                and (item.kind ~= "gear" or string.lower(U.linkName(r.itemLink) or "") == item.name)
            then
                rows[#rows + 1] =
                    { unit = r.buyoutAmount, qty = r.quantity, auctionID = r.auctionID, link = r.itemLink }
            end
        end
    end
    table.sort(rows, function(a, b)
        return a.unit < b.unit
    end)
    return rows, complete, count
end

-- Browse and key queries: the lowest price of many items at once (fast sniper) --------------------
function A.canBrowse()
    return AH.SendBrowseQuery ~= nil and AH.GetBrowseResults ~= nil and AH.HasFullBrowseResults ~= nil
end
function A.browse()
    learnedRows = 0
    A.ownBrowse = true
    local ok, err =
        pcall(AH.SendBrowseQuery, { searchString = "", sorts = sorts(), filters = {}, itemClassFilters = {} })
    A.ownBrowse = false
    if not ok then
        error(err, 0)
    end
end
function A.browseMore()
    AH.RequestMoreBrowseResults()
end
function A.browseFull()
    return AH.HasFullBrowseResults()
end
function A.searchKeys(ids)
    local keys = {}
    for i, id in ipairs(ids) do
        keys[i] = plainKey(id)
    end
    learnedRows = 0
    A.ownBrowse = true
    local ok, err = pcall(AH.SearchForItemKeys, keys, sorts())
    A.ownBrowse = false
    if not ok then
        error(err, 0)
    end
end
-- One query for the lowest price of each item-key version of a gear item (its answer is a browse
-- answer: A.versionPrices reads it).
function A.searchVersions(keys)
    learnedRows = 0
    A.ownBrowse = true
    local ok, err = pcall(AH.SearchForItemKeys, keys, sorts())
    A.ownBrowse = false
    if not ok then
        error(err, 0)
    end
end
-- The lowest price of each version of item `id` in the browse results: "level:suffix" -> copper.
-- It may be a bid, another ending's lot or the player's own: never above the lots of the version.
function A.versionPrices(id)
    local out = {}
    local ok, results = pcall(AH.GetBrowseResults)
    for _, r in ipairs(ok and type(results) == "table" and results or {}) do
        local k = type(r) == "table" and r.itemKey
        if type(k) == "table" and k.itemID == id and (r.minPrice or 0) > 0 then
            local v = (k.itemLevel or 0) .. ":" .. (k.itemSuffix or 0)
            out[v] = math.min(out[v] or math.huge, r.minPrice)
        end
    end
    return out
end
-- Browse result rows as { id, minPrice, qty, containsOwnerItem }. The lowest price of an item may
-- be a bid, or the price of the player's own lot (containsOwnerItem: the item has one listed).
function A.browseRows(results)
    local out = {}
    for _, r in ipairs(type(results) == "table" and results or {}) do
        if type(r) == "table" and r.itemKey and (r.minPrice or 0) > 0 and (r.totalQuantity or 0) > 0 then
            out[#out + 1] = {
                id = r.itemKey.itemID,
                minPrice = r.minPrice,
                qty = r.totalQuantity,
                containsOwnerItem = r.containsOwnerItem,
            }
        end
    end
    return out
end

-- Every result row so far (A.browseRows).
function A.browseResults()
    local ok, results = pcall(AH.GetBrowseResults)
    return A.browseRows(ok and results)
end

-- One browse answer event, read once: the rows it brought (A.browseRows), their item-key versions
-- learned. ADDED carries only the rows it added (its payload, addedBrowseResults); UPDATED is a
-- new list, read whole. Reading the whole list on every page, twice (keys, then the sniper),
-- copied up to 8,000 rows per page of a whole-house browse: the quick scan froze the game.
-- Returns the rows and true when they are the whole list (UPDATED, or no payload).
function A.browseAnswer(updated, added)
    local new, whole
    if not updated and type(added) == "table" then
        new = added
        learnedRows = learnedRows + #added
    else
        local ok, results = pcall(AH.GetBrowseResults)
        results = ok and type(results) == "table" and results or {}
        if updated or #results < learnedRows then
            learnedRows = 0
        end
        whole = learnedRows == 0
        new = {}
        for i = learnedRows + 1, #results do
            new[#new + 1] = results[i]
        end
        learnedRows = #results
    end
    if F.db then
        for _, r in ipairs(new) do
            A.rememberKey(type(r) == "table" and r.itemKey)
        end
    end
    return A.browseRows(new), whole
end

-- Auctions of an exact item search that take a bid: { auctionID, bid = next bid, qty }.
function A.bidRows(item, searchKey)
    local out = {}
    if item.kind == "commodity" then
        return out
    end
    local key = type(searchKey) == "table" and searchKey or plainKey(item.id)
    for i = 1, (AH.GetNumItemSearchResults(key) or 0) do
        local r = AH.GetItemSearchResultInfo(key, i)
        if
            r
            and (r.minBid or 0) > 0
            and not r.containsOwnerItem
            and not r.containsAccountItem
            and (item.kind ~= "gear" or string.lower(U.linkName(r.itemLink) or "") == item.name)
        then
            out[#out + 1] = { auctionID = r.auctionID, bid = r.minBid, qty = 1 }
        end
    end
    return out
end

function A.bid(auctionID, amount)
    AH.PlaceBid(auctionID, amount)
end

-- The auctions the player has bid on (the game's own Bids list): asked for with A.queryBids, read
-- on BIDS_UPDATED. Each: { auctionID, id, link, minBid (the next bid the house takes), bid (the
-- highest bid now), buyout, band (time left: 0 under 30 min, 1 up to 2 h, 2 up to 12 h, 3 more),
-- leading (the highest bid is the player's) }. nil where the client has no such list.
function A.queryBids()
    if AH.QueryBids then
        AH.QueryBids({}, {})
        return true
    end
end
function A.bids()
    if not AH.GetNumBids or not AH.GetBidInfo then
        return nil
    end
    local me = UnitGUID and UnitGUID("player")
    local out = {}
    for i = 1, (AH.GetNumBids() or 0) do
        local b = AH.GetBidInfo(i)
        if b and b.auctionID then
            -- nil when the server does not name the highest bidder (Bids.onLive decides then);
            -- false when it names another player.
            local leading
            if b.bidder ~= nil and me ~= nil then
                leading = b.bidder == me
            end
            out[#out + 1] = {
                auctionID = b.auctionID,
                id = b.itemKey and b.itemKey.itemID,
                link = b.itemLink,
                minBid = b.minBid,
                bid = b.bidAmount,
                buyout = (b.buyoutAmount or 0) > 0 and b.buyoutAmount or nil,
                band = b.timeLeft,
                leading = leading,
            }
        end
    end
    return out
end

-- Buying (each call comes from a click) -------------------------------------------------------------
function A.quote(id, qty)
    AH.StartCommoditiesPurchase(id, qty)
end
function A.confirm(id, qty)
    AH.ConfirmCommoditiesPurchase(id, qty)
end
function A.cancelQuote()
    if AH.CancelCommoditiesPurchase then
        AH.CancelCommoditiesPurchase()
    end
end
function A.buyItem(auctionID, price)
    AH.PlaceBid(auctionID, price)
end

-- Selling ----------------------------------------------------------------------------------------
-- The kind of a bag item when the auction house has not told it yet (A.kindOf asks for the item
-- key's info, which the game only has for items it has seen on the auction house): the game's own
-- Sell window asks the item location whether it is a commodity, and gear is a weapon or armour
-- (the item classes the auction house keys by level and ending). Bags and quivers are equipped
-- too, but are no gear: counted as gear, they changed key once the auction house answered.
local function kindOfBagItem(id, loc)
    if not AH.GetItemCommodityStatus or not Enum or not Enum.ItemCommodityStatus then
        return nil
    end
    ---@diagnostic disable-next-line: param-type-mismatch
    local ok, status = pcall(AH.GetItemCommodityStatus, loc)
    if not ok then
        return nil
    end
    if status == Enum.ItemCommodityStatus.Commodity then
        return "commodity"
    elseif status == Enum.ItemCommodityStatus.Item then
        local classID = C_Item and C_Item.GetItemInfoInstant and select(6, C_Item.GetItemInfoInstant(id))
        return (classID == 2 or classID == 4) and "gear" or "item"
    end
end

-- Bags 0-4, and the reagent bag (herbs, ore, cloth) when the client has one.
local function bagList()
    local list = { 0, 1, 2, 3, 4 }
    local reagent = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
    if reagent and reagent > 4 then
        list[#list + 1] = reagent
    end
    return list
end

-- Free slots of the general bags (bags 0-4 of bag family 0) for a mail item or a merchant purchase.
-- A quiver, ammo pouch, soul bag or herb bag holds only its own kind of item: counted as room, the
-- game refused the take or the purchase with the other bags full. A client that tells no family
-- counts every bag.
function A.freeBagSlots()
    local get = C_Container and C_Container.GetContainerNumFreeSlots
    if not get then
        return 0
    end
    local free = 0
    for bag = 0, 4 do
        local n, family = get(bag)
        if U.finite(n) and n > 0 and (family == nil or family == 0) then
            free = free + n
        end
    end
    return free
end

-- /ff bags: why bag items are not on the Sell page. { { link, reason } }, reason one of "bound",
-- "not_sellable" (the auction house refuses it), "unknown_kind".
function A.bagReport()
    local out = {}
    if not C_Container or not ItemLocation then
        return out
    end
    for _, bag in ipairs(bagList()) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
                ---@diagnostic disable-next-line: param-type-mismatch
                local valid = not AH.IsSellItemValid or AH.IsSellItemValid(loc, false)
                local reason
                if info.isBound then
                    reason = "bound"
                elseif not valid then
                    reason = "not_sellable"
                elseif not A.keyFor(info.itemID, info.hyperlink) and not kindOfBagItem(info.itemID, loc) then
                    reason = "unknown_kind"
                end
                if reason then
                    out[#out + 1] = { link = info.hyperlink or ("item " .. info.itemID), reason = reason }
                end
            end
        end
    end
    return out
end

-- Items a merchant took back, as { id = true }. Selling is the only way to learn them: item data
-- gives a sell price for consumables such as poisons that can be made but not sold, so a merchant
-- deal on those looked as sure as any. Kept for the session; one sale is proof.
A.refused = {}

-- Whether the client may know that a merchant will not buy the item: it was proved refused, or the
-- bag entry carries the game's own "hasNoValue" flag. False: nothing says so.
function A.refusedByMerchant(info)
    local id = info and (info.id or info.itemID)
    if (id and A.refused[id]) or (info and info.hasNoValue) then
        return true
    end
    return false
end

-- Whether a merchant may take this bag item: the sell price says what the item is worth where it
-- can be sold (a poison's price is what one costs), not that a merchant buys it. So an item is left
-- out only on evidence: proved refused, or flagged by the game. Selling it teaches the first.
function A.accepts(item)
    return not A.refusedByMerchant(item)
end

-- A merchant was sent one and the slot still holds it: it does not buy the item. Its deals go and it
-- is not offered again this session.
function A.noteRefused(id)
    if not id or A.refused[id] then
        return
    end
    A.refused[id] = true
    if F.Deals and F.Deals.refused then
        F.Deals.refused(id)
    end
end

-- The bags are read once per frame: a page refresh asks for them several times (counts, queues,
-- rows). Each caller gets its own copies, since callers change the entries.
local bagFrame, bagCache
function A.bagItems()
    local t = GetTime and GetTime()
    if not t or t ~= bagFrame or not bagCache then
        bagCache, bagFrame = A.readBags(), t
    end
    local out = {}
    for i, b in ipairs(bagCache) do
        local copy = {}
        for k, v in pairs(b) do
            copy[k] = v
        end
        out[i] = copy
    end
    return out
end

-- Merchant sales must not depend on the auction house's posting validation/cache.
function A.merchantItems()
    return A.readBags(true)
end

function A.readBags(merchant)
    local out = {}
    if not C_Container or not ItemLocation then
        return out
    end
    for _, bag in ipairs(bagList()) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and (merchant or not info.isBound) then
                local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
                ---@diagnostic disable-next-line: param-type-mismatch
                local valid = merchant or not AH.IsSellItemValid or AH.IsSellItemValid(loc, false)
                local sellable = F.db and F.db.sellable
                if not merchant and valid and sellable then
                    sellable[info.itemID] = true
                elseif not valid and ((sellable and sellable[info.itemID]) or F.Scan.busy()) then
                    valid = true -- the game says no to everything while a full scan is awaited
                end
                local key, kind = A.keyFor(info.itemID, info.hyperlink)
                if valid and not key then
                    kind = kindOfBagItem(info.itemID, loc)
                    if kind then
                        guesses[info.itemID] = kind
                        key = A.keyFor(info.itemID, info.hyperlink)
                    end
                end
                if valid and key then
                    out[#out + 1] = {
                        bag = bag,
                        slot = slot,
                        loc = loc,
                        id = info.itemID,
                        link = info.hyperlink,
                        count = info.stackCount or 1,
                        key = key,
                        kind = kind,
                        locked = info.isLocked,
                        bound = info.isBound,
                        -- The game's own flag: the item has no value (a merchant would not buy it).
                        hasNoValue = info.hasNoValue,
                    }
                end
            end
        end
    end
    return out
end
-- The posting API accepts matching items across bag stacks. A bag row's count describes only
-- its own slot; the client decides how many units its location can post together.
function A.postCount(item)
    if not AH.GetAvailablePostCount then
        return item.count or 0
    end
    local ok, available = pcall(AH.GetAvailablePostCount, item.loc)
    if not ok or not U.finite(available) or available <= 0 then
        return 0
    end
    local matching = 0
    for _, b in ipairs(A.bagItems()) do
        if b.key == item.key then
            matching = matching + b.count
        end
    end
    -- Never mix another gear variant or include units outside the sellable bags.
    return math.min(math.floor(available), matching)
end

-- The game refuses some auction house calls from addons while one of its restrictions is on:
-- PostItem, PostCommodity, CancelAuction, PlaceBid and StartCommoditiesPurchase are marked
-- HasRestrictions, and the server answers "That action is currently restricted". Returns the
-- active restriction (Combat, Encounter, ChallengeMode, PvPMatch or Map), or nil. A client without
-- C_RestrictedActions has none.
local RESTRICTIONS = { "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map" }
function A.restricted()
    local R = C_RestrictedActions
    local types = Enum and Enum.AddOnRestrictionType
    if not (R and R.IsAddOnRestrictionActive and types) then
        return nil
    end
    for _, name in ipairs(RESTRICTIONS) do
        local t = types[name]
        if t ~= nil then
            local ok, active = pcall(R.IsAddOnRestrictionActive, t)
            if ok and active then
                return name
            end
        end
    end
    return nil
end

-- Returns true when the game asks for a confirmation (call again with confirm = true).
function A.post(item, qty, price, duration, confirm)
    F.Log.devTrace(
        "post.send",
        "%s %s x%s at %s, duration %s%s",
        tostring(item.kind),
        tostring(item.key),
        tostring(qty),
        tostring(price),
        tostring(duration),
        confirm and ", confirmed" or ""
    )
    if item.kind == "commodity" then
        local fn = confirm and AH.ConfirmPostCommodity or AH.PostCommodity
        return fn(item.loc, duration, qty, price)
    end
    local fn = confirm and AH.ConfirmPostItem or AH.PostItem
    return fn(item.loc, duration, qty, nil, price)
end

-- Deposit of a stack of n units as the game charges it, for deal evaluation. Commodities ask the
-- game directly (twice per item, auction house and session); items need a bag location, so the
-- deposit per unit learned from the last post of the item is used. nil: the caller estimates from
-- the vendor price. A neutral house may charge other deposits: its values are kept apart.
local depositRates = {}
-- A read that failed is not kept for the session: the game may answer only at the auction house
-- or once the item's data has loaded. It is asked again when the auction house has opened since,
-- else after A.DEPOSIT_RETRY seconds.
A.DEPOSIT_RETRY = 60
-- Forgets the deposits asked for this session (tests, or a patch that changed them).
function A.resetDeposits()
    depositRates = {}
    F.Market.resetUnitDeposits()
end
-- The deposits per unit learned for an item, by duration: deposits[id][duration], and a neutral
-- house's in deposits[id].neutral[duration].
local function learnedDeposits(id, create)
    local all = F.db and F.db.deposits
    local t = type(all) == "table" and all[id]
    if create and type(t) ~= "table" then
        F.db.deposits = type(all) == "table" and all or {}
        t = {}
        F.db.deposits[id] = t
    end
    if type(t) == "table" and F.Engine.house == "Neutral" then
        if create and type(t.neutral) ~= "table" then
            t.neutral = {}
        end
        t = t.neutral
    end
    return type(t) == "table" and t or nil
end
function A.depositFn(id, kind, duration)
    if kind == "commodity" and AH.CalculateCommodityDeposit then
        -- Realm and faction stay the same for a session: the house tells the scope apart.
        local cacheKey = tostring(F.Engine.house) .. ":" .. id .. ":" .. duration
        local rate = depositRates[cacheKey]
        local now, open = F.Engine.clock(), A.isOpen()
        if rate == nil or rate.failed and (open and not rate.open or now - rate.failed >= A.DEPOSIT_RETRY) then
            local ok1, one = pcall(AH.CalculateCommodityDeposit, id, duration, 1)
            local ok20, twenty = pcall(AH.CalculateCommodityDeposit, id, duration, 20)
            if ok1 and ok20 and U.finite(one) and U.finite(twenty) and one > 0 then
                rate = { one = one, unit = twenty / 20 }
            else
                rate = { failed = now, open = open }
            end
            depositRates[cacheKey] = rate
        end
        if not rate.failed then
            return function(qty)
                return math.max(rate.one, math.floor(rate.unit * qty + 0.5))
            end
        end
        return nil
    end
    local learned = learnedDeposits(id)
    local unit = learned and learned[duration]
    if U.finite(unit) and unit > 0 then
        return function(qty)
            return unit * qty
        end
    end
    return nil
end

-- Remembers the deposit per unit of an item about to be posted (the game knows it for a bag item).
function A.learnDeposit(item, duration)
    if not F.db or item.kind == "commodity" or not AH.CalculateItemDeposit or not item.loc then
        return
    end
    local ok, unit = pcall(AH.CalculateItemDeposit, item.loc, duration, 1)
    if ok and U.finite(unit) and unit > 0 then
        learnedDeposits(item.id, true)[duration] = unit
    end
end

-- Seconds left on the current commodity quote, or nil when the game does not tell.
function A.quoteRemaining()
    if AH.GetQuoteDurationRemaining then
        local ok, s = pcall(AH.GetQuoteDurationRemaining)
        if ok and U.finite(s) then
            return s
        end
    end
end

-- Own auctions -------------------------------------------------------------------------------------
function A.queryOwned()
    if AH.QueryOwnedAuctions then
        AH.QueryOwnedAuctions({})
    end
end
function A.cancel(auctionID)
    AH.CancelAuction(auctionID)
end
function A.cancelCost(auctionID)
    if AH.GetCancelCost then
        local ok, cost = pcall(AH.GetCancelCost, auctionID)
        if ok then
            return cost
        end
    end
end
function A.owned()
    local out = {}
    for i = 1, (AH.GetNumOwnedAuctions and AH.GetNumOwnedAuctions() or 0) do
        local a = AH.GetOwnedAuctionInfo(i)
        if a and a.itemKey then
            A.rememberKey(a.itemKey, a.itemLink, true)
            -- A listed auction reports the price of one unit; a sold one reports the whole sale
            -- (as Auctionator reads it). Kept apart: price is always one unit, total the lot.
            local qty = a.quantity or 1
            local sold = a.status == 1
            local buyout = a.buyoutAmount or a.bidAmount
            local total = buyout and (sold and buyout or buyout * qty)
            out[#out + 1] = {
                auctionID = a.auctionID,
                id = a.itemKey.itemID,
                itemKey = U.copy(a.itemKey),
                link = a.itemLink,
                qty = qty,
                price = buyout and (sold and math.floor(buyout / math.max(qty, 1) + 0.5) or buyout),
                total = total,
                sold = sold,
                timeLeft = a.timeLeftSeconds,
            }
        end
    end
    return out
end
