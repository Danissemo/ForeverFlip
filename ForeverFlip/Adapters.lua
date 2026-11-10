local F = ForeverFlip
local U = F.Util
local A = {}
F.Adapters = A
function A.normalKey(key)
    local id = U.key(key)
    return id and U.fromKey(id) or nil
end
-- Search results belong to the queried key. Item level is compared only when both sides know it,
-- because the client may report equipment under a base key with item level 0.
function A.sameListing(a, b)
    if type(a) ~= "table" or type(b) ~= "table" or a.itemID ~= b.itemID then
        return false
    end
    if (a.itemSuffix or 0) ~= (b.itemSuffix or 0) or (a.battlePetSpeciesID or 0) ~= (b.battlePetSpeciesID or 0) then
        return false
    end
    local x, y = a.itemLevel or 0, b.itemLevel or 0
    return x == 0 or y == 0 or x == y
end
local dataQueue, dataPending, nextData, dataCount = {}, {}, 0, 0
local dataFailed, failedCount = {}, 0
function A.requestData(id)
    if not U.key(id) or not C_Item or not C_Item.RequestLoadItemDataByID or dataPending[id] or dataFailed[id] then
        return false
    end
    if C_Item.IsItemDataCachedByID and C_Item.IsItemDataCachedByID(id) then
        return false
    end
    if dataCount >= 2000 then
        return false
    end
    dataPending[id] = true
    dataCount = dataCount + 1
    dataQueue[#dataQueue + 1] = id
    return true
end
function A.pumpData(now)
    if now < nextData then
        return
    end
    nextData = now + 0.1
    for _ = 1, 2 do
        local id = table.remove(dataQueue, 1)
        if not id then
            break
        end
        if C_Item and C_Item.RequestLoadItemDataByID then
            local ok = pcall(C_Item.RequestLoadItemDataByID, id)
            if not ok then
                A.dataLoaded(id, false)
            end
        end
    end
end
function A.dataLoaded(id, success)
    local pending = dataPending[id]
    if pending then
        dataCount = math.max(0, dataCount - 1)
    end
    dataPending[id] = nil
    if success == false then
        if failedCount >= 2000 then
            dataFailed, failedCount = {}, 0
        end
        if not dataFailed[id] then
            dataFailed[id] = true
            failedCount = failedCount + 1
        end
    else
        dataFailed[id] = nil
    end
    return pending
end
function A.keyFromInput(s)
    s = tostring(s or "")
    local exact = U.fromKey(s)
    if exact then
        return exact
    end
    local raw = s:match("item:([^|]+)")
    if raw then
        local fields = {}
        for part in (raw .. ":"):gmatch("(.-):") do
            fields[#fields + 1] = part
        end
        local id = tonumber(fields[1])
        local suffix = tonumber(fields[7]) or 0
        local get = C_Item and C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo
        local level
        if get then
            local ok, v = pcall(get, s)
            if ok and U.finite(v) then
                level = v
            end
        end
        local info
        if C_AuctionHouse and C_AuctionHouse.GetItemKeyInfo and id then
            local ok, value = pcall(C_AuctionHouse.GetItemKeyInfo, A.normalKey({ itemID = id }))
            if ok then
                info = value
            end
            if not info then
                A.requestData(id)
                return nil, "Item link data not loaded; use an exact key or bag item"
            end
        end
        if info and (info.isCommodity or info.isEquipment == false) then
            level = 0
        end
        if not level then
            A.requestData(id)
            return nil, "Item link data not loaded; use an exact key or bag item"
        end
        local key = A.normalKey({ itemID = id, itemLevel = level, itemSuffix = suffix })
        if U.key(key) then
            return key
        end
        return nil, "Invalid item link"
    end
    local id = tonumber(s)
    if id and U.key(id) then
        if C_AuctionHouse and C_AuctionHouse.GetItemKeyInfo then
            local ok, info = pcall(C_AuctionHouse.GetItemKeyInfo, A.normalKey({ itemID = id }))
            if not ok or not info or info.isEquipment then
                local get = C_Item and C_Item.GetItemInfo or GetItemInfo
                local got, _, link
                if get then
                    got, _, link = pcall(get, id)
                end
                if got and link then
                    return A.keyFromInput(link)
                end
                A.requestData(id)
                return nil, "Item link data not loaded; use an exact key or bag item"
            end
        end
        return A.normalKey({ itemID = id })
    end
    return nil, "Item ID / exact key required"
end
function A.prices(item)
    local out = {}
    local id = type(item) == "table" and item.itemID or tonumber(item)
    local atr = Auctionator and Auctionator.API and Auctionator.API.v1
    if atr and atr.GetAuctionPriceByItemID and id then
        local ok, p = pcall(atr.GetAuctionPriceByItemID, "ForeverFlip", id)
        if ok and U.finite(p) and p > 0 then
            local age
            if atr.GetAuctionAgeByItemID then
                local got, days = pcall(atr.GetAuctionAgeByItemID, "ForeverFlip", id)
                if got and U.finite(days) and days >= 0 and days <= 21 then
                    age = days * 86400
                end
            end
            out[#out + 1] = { source = "Auctionator", price = p, age = age, freshnessGranularity = "day" }
        end
    end
    if AuxForeverAPI and AuxForeverAPI.GetUsualPrice then
        local ok, p, age = pcall(AuxForeverAPI.GetUsualPrice, id)
        if ok and U.finite(p) and p > 0 then
            out[#out + 1] = { source = "auxForever", price = p, age = age and age * 86400 }
        end
    end
    return out
end
function A.native(db)
    local C = C_AuctionHouse or {}
    local api = {}
    local commodityCache = {}
    api.clock = function()
        return time()
    end
    api.wallet = function()
        return GetMoney()
    end
    api.owner = function()
        return tostring(GetRealmID and GetRealmID() or GetRealmName()) .. ":" .. tostring(UnitGUID("player"))
    end
    api.scope = function()
        return "wowf:"
            .. tostring(GetCurrentRegion and GetCurrentRegion() or "?")
            .. ":"
            .. tostring(GetRealmID and GetRealmID() or GetRealmName())
            .. ":"
            .. tostring(db.ui and db.ui.house or UnitFactionGroup("player"))
    end
    api.isOpen = function()
        return AuctionHouseFrame and AuctionHouseFrame:IsShown() and not (InCombatLockdown and InCombatLockdown())
    end
    api.ready = function()
        return not C.IsThrottledMessageSystemReady or C.IsThrottledMessageSystemReady()
    end
    api.search = function(key)
        C.SendSearchQuery(
            A.normalKey(key),
            { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } },
            true
        )
    end
    api.keyReady = function(key)
        if not C.GetItemKeyInfo then
            return true
        end
        local info = C.GetItemKeyInfo(A.normalKey(key))
        if not info then
            A.requestData(key.itemID)
        end
        return info ~= nil
    end
    api.more = function(key, kind)
        if kind == "commodity" then
            C.RequestMoreCommoditySearchResults(key.itemID)
        else
            C.RequestMoreItemSearchResults(A.normalKey(key))
        end
    end
    api.rows = function(key, kind)
        local rows, bids = {}, {}
        local complete
        if kind == "commodity" then
            complete = C.HasFullCommoditySearchResults(key.itemID)
            for i = 1, (C.GetNumCommoditySearchResults(key.itemID) or 0) do
                local r = C.GetCommoditySearchResultInfo(key.itemID, i)
                if
                    r
                    and r.quantity > 0
                    and r.unitPrice > 0
                    and not r.containsOwnerItem
                    and not r.containsAccountItem
                then
                    rows[#rows + 1] = {
                        qty = r.quantity,
                        unit = r.unitPrice,
                        cost = r.quantity * r.unitPrice,
                        auctionID = r.auctionID,
                    }
                end
            end
        else
            key = A.normalKey(key)
            complete = C.HasFullItemSearchResults(key)
            for i = 1, (C.GetNumItemSearchResults(key) or 0) do
                local r = C.GetItemSearchResultInfo(key, i)
                if
                    r
                    and A.sameListing(r.itemKey, key)
                    and not r.containsOwnerItem
                    and not r.containsAccountItem
                    and (r.quantity or 0) > 0
                then
                    if (r.buyoutAmount or 0) > 0 then
                        rows[#rows + 1] = {
                            qty = r.quantity,
                            unit = r.buyoutAmount / r.quantity,
                            cost = r.buyoutAmount,
                            auctionID = r.auctionID,
                            link = r.itemLink,
                        }
                    end
                    if (r.minBid or 0) > 0 then
                        bids[#bids + 1] = r
                    end
                end
            end
        end
        return rows, complete, kind, bids
    end
    api.quote = function(id, qty)
        C.StartCommoditiesPurchase(id, qty)
    end
    api.confirm = function(id, qty)
        C.ConfirmCommoditiesPurchase(id, qty)
    end
    api.cancelQuote = function()
        if C.CancelCommoditiesPurchase then
            C.CancelCommoditiesPurchase()
        end
    end
    api.quoteRemaining = function()
        return C.GetQuoteDurationRemaining and C.GetQuoteDurationRemaining()
    end
    api.buyItem = function(auctionID, cost)
        C.PlaceBid(auctionID, cost)
    end
    api.vendor = U.vendor
    api.replicate = function()
        C.ReplicateItems()
    end
    api.queryOwned = function()
        C.QueryOwnedAuctions({})
    end
    -- The player's own listings: active ones are compared with competitors, sold ones await mail.
    api.owned = function()
        local out = {}
        for i = 1, (C.GetNumOwnedAuctions and C.GetNumOwnedAuctions() or 0) do
            local a = C.GetOwnedAuctionInfo(i)
            if a and a.itemKey and (a.quantity or 0) > 0 then
                out[#out + 1] = {
                    auctionID = a.auctionID,
                    key = A.normalKey(a.itemKey),
                    link = a.itemLink,
                    qty = a.quantity,
                    buyout = a.buyoutAmount,
                    sold = a.status == 1,
                    timeLeft = a.timeLeftSeconds,
                }
            end
        end
        return out
    end
    api.replicateCount = function()
        return C.GetNumReplicateItems()
    end
    api.replicateRow = function(i)
        local _, _, qty, _, _, _, _, bid, _, buyout, _, _, _, owner, _, _, id, complete = C.GetReplicateItemInfo(i)
        if id and not complete then
            return { id = id, complete = false }
        end
        if not id or not qty or qty < 1 or (buyout or 0) <= 0 then
            return nil
        end
        local link = C.GetReplicateItemLink and C.GetReplicateItemLink(i)
        local suffix = 0
        if link then
            local raw = link:match("item:([^|]+)")
            if raw then
                local fields = {}
                for x in (raw .. ":"):gmatch("(.-):") do
                    fields[#fields + 1] = x
                end
                suffix = tonumber(fields[7]) or 0
            end
        end
        -- Item level cannot always be recovered from replication: discovery only.
        local commodity = commodityCache[id]
        if commodity == nil and C.GetItemKeyInfo then
            local ok, info =
                pcall(C.GetItemKeyInfo, { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 })
            if ok and info then
                commodity = info.isCommodity
                commodityCache[id] = commodity
            end
        end
        return {
            id = id,
            qty = qty,
            buyout = buyout,
            bid = bid,
            key = { itemID = id, itemSuffix = commodity and 0 or suffix },
            link = link,
            complete = complete,
            owner = owner,
            family = commodity ~= true,
        }
    end
    api.bagItems = function()
        local out = {}
        if not C_Container or not ItemLocation then
            return out
        end
        for bag = 0, 4 do
            for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
                local r = C_Container.GetContainerItemInfo(bag, slot)
                if r and not r.isLocked and r.itemID then
                    local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
                    local ok, key = pcall(C.GetItemKeyFromItem, loc)
                    if ok and key then
                        out[#out + 1] = {
                            id = r.itemID,
                            key = key,
                            qty = r.stackCount,
                            loc = loc,
                            link = r.hyperlink,
                            bag = bag,
                            slot = slot,
                        }
                    end
                end
            end
        end
        return out
    end
    api.deposit = function(item, kind, qty, duration)
        if kind == "commodity" then
            return C.CalculateCommodityDeposit(item.id, duration, qty)
        end
        return C.CalculateItemDeposit(item.loc, duration, qty)
    end
    api.post = function(item, kind, qty, price, duration, confirm)
        if kind == "commodity" then
            local fn = confirm and C.ConfirmPostCommodity or C.PostCommodity
            return fn(item.loc, duration, qty, price)
        end
        local fn = confirm and C.ConfirmPostItem or C.PostItem
        return fn(item.loc, duration, 1, nil, price)
    end
    api.mail = function()
        local out = {}
        if not GetInboxInvoiceInfo then
            return out
        end
        for i = 1, (GetInboxNumItems() or 0) do
            local kind, name, player, bid, buyout, deposit, cut, delay, _, _, count = GetInboxInvoiceInfo(i)
            local _, _, sender, subject, money, _, daysLeft = GetInboxHeaderInfo(i)
            if kind == "seller" or kind == "buyer" then
                out[#out + 1] = {
                    index = i,
                    kind = kind,
                    name = name,
                    qty = count or 1,
                    amount = money or 0,
                    bid = bid,
                    buyout = buyout,
                    deposit = deposit,
                    cut = cut,
                    delay = delay,
                    -- Expiry-derived arrival is stable as daysLeft falls. Coarse buckets are
                    -- reconciled conservatively by the controller, never an inbox index.
                    arrivalBucket = daysLeft and math.floor(((api.clock() + daysLeft * 86400) / 86400) + 0.5),
                    fingerprint = table.concat({
                        kind,
                        tostring(name),
                        tostring(player),
                        tostring(bid),
                        tostring(count),
                        tostring(subject),
                        tostring(money),
                    }, "|"),
                }
            end
        end
        return out
    end
    return api
end
