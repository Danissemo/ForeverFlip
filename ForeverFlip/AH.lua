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

local kinds = {}
-- "commodity", "gear" or "item"; nil while the game has not loaded the item.
function A.kindOf(id)
    if kinds[id] then
        return kinds[id]
    end
    local ok, info = pcall(AH.GetItemKeyInfo, plainKey(id))
    if not ok or type(info) ~= "table" then
        A.requestItem(id)
        return nil
    end
    local kind = info.isCommodity and "commodity" or info.isEquipment and "gear" or "item"
    kinds[id] = kind
    return kind
end

function A.keyFor(id, link)
    local kind = A.kindOf(id)
    if not kind then
        return nil
    end
    if kind == "gear" then
        local name = U.linkName(link)
        if not name then
            return nil
        end
        return U.key(kind, id, name), kind
    end
    return U.key(kind, id), kind
end

-- Item data requests, paced at 40 per second.
local queue, queued, nextPump = {}, {}, 0
function A.requestItem(id)
    if queued[id] or #queue >= 4000 then
        return
    end
    if C_Item and C_Item.IsItemDataCachedByID and C_Item.IsItemDataCachedByID(id) then
        return
    end
    queued[id] = true
    queue[#queue + 1] = id
end
function A.pump(now)
    if now < nextPump then
        return
    end
    nextPump = now + 0.1
    for _ = 1, 4 do
        local id = table.remove(queue, 1)
        if not id then
            return
        end
        queued[id] = nil
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
--  "seen"     a merchant paid it (buyback list), the most reliable;
--  "estimate" the client's price less the safety margin (setting vendorMargin, percent), used for
--             deals, because the server may pay less than the client says;
--  "client"   the client's price as it is (raw = true: deposits and totals).
-- nil when the vendor does not buy the item or its data has not loaded.
function A.vendorPrice(id, raw)
    local seen = F.db and F.db.vendorSeen and F.db.vendorSeen[id]
    if type(seen) == "table" and U.finite(seen.p) then
        if seen.p <= 0 then
            return nil, "seen"
        end
        return seen.p, "seen"
    end
    local price = A.clientVendorPrice(id)
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

-- AUCTION_HOUSE_THROTTLED_SYSTEM_READY, or the auction house closed.
function A.throttleReset()
    notReadySince, lastCheck = nil, nil
end

-- Is this owner the player? Owner lists name the player "player" (TSM normalises it the same way),
-- or give the name, with the realm for a connected realm. Names are not unique on WoW Forever, so
-- a name with another realm is somebody else. The names are worked out once (A.refreshPlayer, at
-- each scan and when the auction house opens): this runs for every row of a full scan.
local myName, myFullName
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
-- One auction of the full scan: buyout is for the whole stack.
function A.replicateRow(i)
    local _, _, count, _, _, _, _, minBid, increment, buyout, bidAmount, _, _, owner, _, _, id, complete =
        AH.GetReplicateItemInfo(i)
    if not id then
        return nil
    end
    if not complete then
        return { id = id, complete = false }
    end
    local band
    if AH.GetReplicateItemTimeLeft then
        local ok, left = pcall(AH.GetReplicateItemTimeLeft, i)
        band = ok and U.finite(left) and math.max(0, math.min(3, left - 1)) or nil
    end
    return {
        id = id,
        count = count or 1,
        buyout = buyout or 0,
        owner = owner,
        band = band,
        minBid = (bidAmount or 0) > 0 and bidAmount + (increment or 0) or minBid,
        link = AH.GetReplicateItemLink and AH.GetReplicateItemLink(i) or nil,
        complete = true,
    }
end

-- Every field of a full-scan auction, also before the game has loaded the item (raw scans).
function A.replicateRaw(i)
    local _, _, count, _, _, _, _, minBid, _, buyout, bidAmount, _, _, owner, _, _, id = AH.GetReplicateItemInfo(i)
    if not id then
        return nil
    end
    local band
    if AH.GetReplicateItemTimeLeft then
        local ok, left = pcall(AH.GetReplicateItemTimeLeft, i)
        band = ok and U.finite(left) and math.max(0, math.min(3, left - 1)) or nil
    end
    return {
        id = id,
        count = count,
        buyout = buyout,
        minBid = minBid,
        bid = bidAmount,
        band = band,
        own = A.isPlayer(owner),
        link = AH.GetReplicateItemLink and AH.GetReplicateItemLink(i) or nil,
    }
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
function A.search(item)
    if item.kind == "gear" and AH.SendSellSearchQuery then
        AH.SendSellSearchQuery(plainKey(item.id), sorts(), true)
    else
        AH.SendSearchQuery(plainKey(item.id), sorts(), true)
    end
end

-- Gear in two steps (see the top of the file). Step 1: a browse by the item's own name (without
-- the ending), which lists its item-key versions.
function A.canSearchGear()
    return A.canBrowse()
end
function A.gearBrowse(item)
    local name = U.itemInfo(item.id)
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

-- Browse queries ForeverFlip did not send (the game's Buy tab, another addon) replace the results:
-- a gear search waiting for its own answer is told (Deals.onForeignBrowse).
function A.hookBrowse()
    if A.browseHooked or not hooksecurefunc or not AH.SendBrowseQuery then
        return
    end
    A.browseHooked = true
    for _, name in ipairs({ "SendBrowseQuery", "SearchForItemKeys" }) do
        if AH[name] then
            hooksecurefunc(AH, name, function()
                if not A.ownBrowse then
                    A.foreignAt = F.Engine.clock()
                    F.Deals.onForeignBrowse()
                end
            end)
        end
    end
end
-- True when somebody else sent a browse a moment ago: its answer may still be on the way, and would
-- arrive after (and be read as) the answer to a browse sent now.
A.FOREIGN_WAIT = 10
function A.foreignRecent()
    return A.foreignAt ~= nil and F.Engine.clock() - A.foreignAt < A.FOREIGN_WAIT
end

-- The item-key versions of `id` in the browse results so far.
function A.gearKeys(id)
    local out = {}
    local ok, results = pcall(AH.GetBrowseResults)
    for _, r in ipairs(ok and results or {}) do
        if type(r.itemKey) == "table" and r.itemKey.itemID == id then
            out[#out + 1] = r.itemKey
        end
    end
    return out
end
-- Step 2: one exact version, and its next page.
function A.searchKey(key)
    AH.SendSearchQuery(key, sorts(), true)
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
-- Listings of other players, cheapest first: {unit, qty, auctionID}. Returns rows, complete.
function A.rows(item, searchKey)
    local rows, complete = {}, false
    if item.kind == "commodity" then
        complete = AH.HasFullCommoditySearchResults(item.id)
        for i = 1, (AH.GetNumCommoditySearchResults(item.id) or 0) do
            local r = AH.GetCommoditySearchResultInfo(item.id, i)
            local qty = r and (r.quantity - (r.numOwnerItems or 0)) or 0
            if r and qty > 0 and (r.unitPrice or 0) > 0 then
                rows[#rows + 1] = { unit = r.unitPrice, qty = qty, auctionID = r.auctionID }
            end
        end
    else
        local key = type(searchKey) == "table" and searchKey or plainKey(item.id)
        complete = AH.HasFullItemSearchResults(key)
        for i = 1, (AH.GetNumItemSearchResults(key) or 0) do
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
    return rows, complete
end

-- Browse and key queries: the lowest price of many items at once (fast sniper) --------------------
function A.canBrowse()
    return AH.SendBrowseQuery ~= nil and AH.GetBrowseResults ~= nil and AH.HasFullBrowseResults ~= nil
end
function A.browse()
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
    A.ownBrowse = true
    local ok, err = pcall(AH.SearchForItemKeys, keys, sorts())
    A.ownBrowse = false
    if not ok then
        error(err, 0)
    end
end
-- Every result row so far: { id, minPrice, qty }. The lowest price of an item may be a bid.
function A.browseResults()
    local out = {}
    local ok, results = pcall(AH.GetBrowseResults)
    for _, r in ipairs(ok and results or {}) do
        if r.itemKey and (r.minPrice or 0) > 0 and (r.totalQuantity or 0) > 0 then
            out[#out + 1] = { id = r.itemKey.itemID, minPrice = r.minPrice, qty = r.totalQuantity }
        end
    end
    return out
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
-- Sell window asks the item location whether it is a commodity, and gear is what can be equipped.
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
        local equip = C_Item and C_Item.GetItemInfoInstant and select(4, C_Item.GetItemInfoInstant(id))
        return (type(equip) == "string" and equip ~= "" and equip ~= "INVTYPE_NON_EQUIP_IGNORE") and "gear" or "item"
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

function A.bagItems()
    local out = {}
    if not C_Container or not ItemLocation then
        return out
    end
    for _, bag in ipairs(bagList()) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not info.isBound then
                local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
                ---@diagnostic disable-next-line: param-type-mismatch
                local valid = not AH.IsSellItemValid or AH.IsSellItemValid(loc, false)
                local key, kind = A.keyFor(info.itemID, info.hyperlink)
                if valid and not key then
                    kind = kindOfBagItem(info.itemID, loc)
                    if kind then
                        kinds[info.itemID] = kind
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
                    }
                end
            end
        end
    end
    return out
end
function A.deposit(item, qty, duration)
    if item.kind == "commodity" then
        return AH.CalculateCommodityDeposit(item.id, duration, qty)
    end
    return AH.CalculateItemDeposit(item.loc, duration, qty)
end
-- Returns true when the game asks for a confirmation (call again with confirm = true).
function A.post(item, qty, price, duration, confirm)
    if item.kind == "commodity" then
        local fn = confirm and AH.ConfirmPostCommodity or AH.PostCommodity
        return fn(item.loc, duration, qty, price)
    end
    local fn = confirm and AH.ConfirmPostItem or AH.PostItem
    return fn(item.loc, duration, qty, nil, price)
end

-- Deposit of a stack of n units as the game charges it, for deal evaluation. Commodities ask the
-- game directly (twice per item and session); items need a bag location, so the deposit per unit
-- learned from the last post of the item is used. nil: the caller estimates from the vendor price.
local depositRates = {}
function A.depositFn(id, kind, duration)
    if kind == "commodity" and AH.CalculateCommodityDeposit then
        local cacheKey = id .. ":" .. duration
        local rate = depositRates[cacheKey]
        if rate == nil then
            local ok1, one = pcall(AH.CalculateCommodityDeposit, id, duration, 1)
            local ok20, twenty = pcall(AH.CalculateCommodityDeposit, id, duration, 20)
            if ok1 and ok20 and U.finite(one) and U.finite(twenty) and one > 0 then
                rate = { one = one, unit = twenty / 20 }
            else
                rate = false
            end
            depositRates[cacheKey] = rate
        end
        if rate then
            return function(qty)
                return math.max(rate.one, math.floor(rate.unit * qty + 0.5))
            end
        end
        return nil
    end
    local learned = F.db and F.db.deposits and F.db.deposits[id]
    local unit = type(learned) == "table" and learned[duration]
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
        F.db.deposits = F.db.deposits or {}
        F.db.deposits[item.id] = F.db.deposits[item.id] or {}
        F.db.deposits[item.id][duration] = unit
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
            out[#out + 1] = {
                auctionID = a.auctionID,
                id = a.itemKey.itemID,
                link = a.itemLink,
                qty = a.quantity or 1,
                price = a.buyoutAmount,
                sold = a.status == 1,
                timeLeft = a.timeLeftSeconds,
            }
        end
    end
    return out
end
