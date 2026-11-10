-- The only file that talks to the game's auction house API. Tests replace F.AH with a fake.
-- Facts used here were seen in game on WoW Forever:
--  * an item search row is a bucket of identical auctions; its price is for one item and PlaceBid
--    buys one auction;
--  * gear links have an empty suffix field and one ending is split over several item-key
--    versions, so gear is searched like Blizzard's Sell window (every version) and told apart by
--    its full name;
--  * commodities are bought with a quote (StartCommoditiesPurchase) and a confirmation.
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

-- Vendor sell price, remembered between sessions. Uncached items are only queued for loading:
-- GetItemInfo on an uncached item sends a server query of its own.
function A.vendorPrice(id)
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

function A.ready()
    return not AH.IsThrottledMessageSystemReady or AH.IsThrottledMessageSystemReady()
end

function A.player()
    return UnitName("player")
end

-- Full scan -------------------------------------------------------------------------------------
function A.replicate()
    AH.ReplicateItems()
end
function A.replicateCount()
    return AH.GetNumReplicateItems() or 0
end
-- One auction of the full scan: buyout is for the whole stack.
function A.replicateRow(i)
    local _, _, count, _, _, _, _, _, _, buyout, _, _, _, owner, _, _, id, complete = AH.GetReplicateItemInfo(i)
    if not id then
        return nil
    end
    if not complete then
        return { id = id, complete = false }
    end
    return {
        id = id,
        count = count or 1,
        buyout = buyout or 0,
        owner = owner,
        link = AH.GetReplicateItemLink and AH.GetReplicateItemLink(i) or nil,
        complete = true,
    }
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
function A.more(item)
    if item.kind == "commodity" then
        AH.RequestMoreCommoditySearchResults(item.id)
    else
        AH.RequestMoreItemSearchResults(plainKey(item.id))
    end
end
-- Listings of other players, cheapest first: {unit, qty, auctionID}. Returns rows, complete.
function A.rows(item)
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
        local key = plainKey(item.id)
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
function A.bagItems()
    local out = {}
    if not C_Container or not ItemLocation then
        return out
    end
    for bag = 0, 4 do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not info.isBound then
                local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
                ---@diagnostic disable-next-line: param-type-mismatch
                local valid = not AH.IsSellItemValid or AH.IsSellItemValid(loc, false)
                local key, kind = A.keyFor(info.itemID, info.hyperlink)
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
-- learned from the last post of the item is used. nil: estimate from the vendor price.
local depositRates = {}
function A.depositFn(id, kind, vendor, duration)
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
