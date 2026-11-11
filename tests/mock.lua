-- A small WoW client with a simulated WoW Forever auction house.
now = 1800000000
function time()
    return math.floor(now)
end
function GetTime()
    return now
end
function date(fmt, t)
    return os.date(fmt, t)
end
money = 1000000
function GetMoney()
    return money
end
function GetRealmName()
    return "Realm"
end
function UnitName()
    return "Me"
end
function UnitFactionGroup()
    return "Alliance"
end
function GetLocale()
    return "enUS"
end
printed = {}
function print(...)
    printed[#printed + 1] = table.concat({ tostring(select(1, ...)) }, " ")
end
ERR_AUCTION_WON_S = "You won an auction for %s"
ERR_AUCTION_SOLD_S = "A buyer has been found for your auction of %s."
Enum = { AuctionHouseSortOrder = { Price = 0 } }
SlashCmdList = {}
sounds, flashes, screen = 0, 0, {}
SOUNDKIT = { AUCTION_WINDOW_OPEN = 5274 }
function PlaySound()
    sounds = sounds + 1
end
function FlashClientIcon()
    flashes = flashes + 1
end
UIErrorsFrame = {
    AddMessage = function(_, msg)
        screen[#screen + 1] = msg
    end,
}

-- Widgets -----------------------------------------------------------------------------------------
local methods = {}
local meta = {
    __index = function(_, k)
        return methods[k] or function() end
    end,
}
widgets = {}
local function widget(kind, parent)
    local w =
        setmetatable({ kind = kind, parent = parent, scripts = {}, shown = true, enabled = true, text = "" }, meta)
    widgets[#widgets + 1] = w
    return w
end
function methods:SetScript(k, fn)
    self.scripts[k] = fn
end
function methods:Show()
    local was = self.shown
    self.shown = true
    if not was and self.scripts.OnShow then
        self.scripts.OnShow(self)
    end
end
function methods:Hide()
    self.shown = false
end
function methods:IsShown()
    return self.shown
end
function methods:SetText(v)
    self.text = tostring(v or "")
end
function methods:GetText()
    return self.text
end
function methods:SetEnabled(v)
    self.enabled = not not v
end
function methods:Enable()
    self.enabled = true
end
function methods:Disable()
    self.enabled = false
end
function methods:IsEnabled()
    return self.enabled
end
function methods:SetChecked(v)
    self.checked = v
end
function methods:GetChecked()
    return self.checked
end
function methods:CreateFontString()
    return widget("FontString", self)
end
function methods:CreateTexture()
    return widget("Texture", self)
end
function methods:RegisterEvent(e)
    self.events = self.events or {}
    self.events[e] = true
end
function methods:Click()
    if self.enabled and self.scripts.OnClick then
        self.scripts.OnClick(self)
    end
end
function CreateFrame(kind, name, parent, template)
    local w = widget(kind, parent)
    w.template = template
    if template == "AuctionHouseTableHeaderStringTemplate" then
        w.Text = widget("FontString", w)
        w.Arrow = widget("Texture", w)
        w.GetFontString = function(self)
            return self.Text
        end
        -- The real XML template inherits this handler and starts with a visible arrow.
        w:SetScript("OnClick", function(self)
            self.owner:SetSortOrder(self.sortOrder)
        end)
    end
    if name then
        _G[name] = w
    end
    return w
end
UIParent = CreateFrame("Frame")
AuctionHouseFrame = CreateFrame("Frame")
AuctionHouseFrame.Tabs = { CreateFrame("Button") }
MerchantFrame = CreateFrame("Frame")
function hooksecurefunc() end
GameTooltip = CreateFrame("GameTooltip")

-- Items ------------------------------------------------------------------------------------------
items = {} -- id -> { name, vendor, commodity, equipment, cached }
function addItem(id, name, vendor, kind)
    items[id] = {
        name = name,
        vendor = vendor or 0,
        commodity = kind == "commodity",
        equipment = kind == "gear",
        cached = true,
    }
end
function link(id, name)
    return "|cff1eff00|Hitem:"
        .. id
        .. "::::::::22:1484::1:1:12743:1:28:7000:::::|h["
        .. (name or items[id].name)
        .. "]|h|r"
end
local function GetItemInfo(id)
    local it = items[id]
    if not it or not it.cached then
        return nil
    end
    return it.name, link(id), 2, 20, 20, "", "", 1, "", 134400, it.vendor
end
requestedItems = {}
C_Item = {
    IsItemDataCachedByID = function(id)
        return items[id] and items[id].cached or false
    end,
    RequestLoadItemDataByID = function(id)
        requestedItems[#requestedItems + 1] = id
    end,
    GetItemIconByID = function()
        return 134400
    end,
    GetItemInfo = function(id)
        return GetItemInfo(id)
    end,
}

-- Auction house ------------------------------------------------------------------------------------
-- auctions: { id, item, count, buyout, owner, name (full name for gear), incomplete }
auctions = {}
local nextAuction = 1
function addAuction(item, unit, count, owner, name)
    local a = {
        id = nextAuction,
        item = item,
        count = count or 1,
        buyout = unit * (count or 1),
        owner = owner or "Seller",
        name = name or items[item].name,
    }
    nextAuction = nextAuction + 1
    auctions[#auctions + 1] = a
    return a
end
calls = {}
local function call(name, ...)
    calls[#calls + 1] = { name, ... }
end
function lastCall(name)
    for i = #calls, 1, -1 do
        if calls[i][1] == name then
            return calls[i]
        end
    end
end
local replicated = {}
throttleReady = true
C_AuctionHouse = {
    IsThrottledMessageSystemReady = function()
        return throttleReady
    end,
    GetItemKeyInfo = function(key)
        local it = items[key.itemID]
        if not it or not it.cached then
            return nil
        end
        return { itemID = key.itemID, itemName = it.name, isCommodity = it.commodity, isEquipment = it.equipment }
    end,
    ReplicateItems = function()
        call("ReplicateItems")
        if replicateIgnored then
            return
        end
        replicated = {}
        for i, a in ipairs(auctions) do
            replicated[i - 1] = a
        end
        replicatedCount = #auctions
        if replicateEventInside then
            fire("REPLICATE_ITEM_LIST_UPDATE")
        end
    end,
    GetNumReplicateItems = function()
        return replicatedCount or 0
    end,
    GetReplicateItemInfo = function(i)
        local a = replicated[i]
        if not a then
            return nil
        end
        local cached = items[a.item].cached
        return a.name, 1, a.count, 2, true, 20, "", a.minBid or 0, a.increment or 0, a.buyout, a.bid or 0, nil, nil, a.owner, a.owner, 0, a.item, cached
    end,
    GetReplicateItemLink = function(i)
        local a = replicated[i]
        return a and link(a.item, a.name)
    end,
    SendSearchQuery = function(key)
        call("SendSearchQuery", key.itemID)
    end,
    SendSellSearchQuery = function(key)
        call("SendSellSearchQuery", key.itemID)
    end,
    HasFullCommoditySearchResults = function()
        return true
    end,
    HasFullItemSearchResults = function()
        return true
    end,
    GetNumCommoditySearchResults = function(id)
        return #commodityRows(id)
    end,
    GetCommoditySearchResultInfo = function(id, i)
        return commodityRows(id)[i]
    end,
    GetNumItemSearchResults = function(key)
        return #itemRows(key.itemID)
    end,
    GetItemSearchResultInfo = function(key, i)
        return itemRows(key.itemID)[i]
    end,
    StartCommoditiesPurchase = function(id, qty)
        call("StartCommoditiesPurchase", id, qty)
    end,
    ConfirmCommoditiesPurchase = function(id, qty)
        call("ConfirmCommoditiesPurchase", id, qty)
    end,
    CancelCommoditiesPurchase = function()
        call("CancelCommoditiesPurchase")
    end,
    PlaceBid = function(id, price)
        call("PlaceBid", id, price)
    end,
    PostItem = function(loc, duration, qty, bid, buyout)
        call("PostItem", loc, duration, qty, bid, buyout)
        return postNeedsConfirm
    end,
    ConfirmPostItem = function(loc, duration, qty, bid, buyout)
        call("ConfirmPostItem", loc, duration, qty, bid, buyout)
    end,
    PostCommodity = function(loc, duration, qty, price)
        call("PostCommodity", loc, duration, qty, price)
        return postNeedsConfirm
    end,
    CalculateItemDeposit = function()
        return 100
    end,
    CalculateCommodityDeposit = function()
        return 100
    end,
    CancelAuction = function(id)
        call("CancelAuction", id)
    end,
    GetCancelCost = function()
        return 0
    end,
    QueryOwnedAuctions = function()
        call("QueryOwnedAuctions")
    end,
    GetNumOwnedAuctions = function()
        return #owned
    end,
    GetOwnedAuctionInfo = function(i)
        return owned[i]
    end,
}
owned = {}

-- Commodity tiers: one row per price, own units counted apart.
function commodityRows(id)
    local tiers, out = {}, {}
    for _, a in ipairs(auctions) do
        if a.item == id then
            local unit = a.buyout / a.count
            local t = tiers[unit]
            if not t then
                t = { itemID = id, unitPrice = unit, quantity = 0, numOwnerItems = 0, auctionID = a.id }
                tiers[unit] = t
                out[#out + 1] = t
            end
            t.quantity = t.quantity + a.count
            if a.owner == "Me" then
                t.numOwnerItems = t.numOwnerItems + a.count
            end
        end
    end
    table.sort(out, function(x, y)
        return x.unitPrice < y.unitPrice
    end)
    return out
end

-- Item rows: a bucket of identical auctions (same name and price), price per item.
function itemRows(id)
    local buckets, out = {}, {}
    for _, a in ipairs(auctions) do
        if a.item == id then
            local k = a.name .. "|" .. a.buyout .. "|" .. a.owner .. "|" .. tostring(a.minBid)
            local b = buckets[k]
            if not b then
                b = {
                    itemKey = { itemID = id, itemLevel = 18, itemSuffix = 14320 },
                    itemLink = link(id, a.name),
                    quantity = 0,
                    buyoutAmount = a.buyout,
                    auctionID = a.id,
                    containsOwnerItem = a.owner == "Me",
                    minBid = a.minBid,
                }
                buckets[k] = b
                out[#out + 1] = b
            end
            b.quantity = b.quantity + 1
        end
    end
    table.sort(out, function(x, y)
        return x.buyoutAmount < y.buyoutAmount
    end)
    return out
end

-- Bags ---------------------------------------------------------------------------------------------
bags = {} -- [bag] = { [slot] = { itemID, count, link } }
function putBag(bag, slot, id, count, name)
    bags[bag] = bags[bag] or {}
    bags[bag][slot] = { itemID = id, stackCount = count or 1, hyperlink = link(id, name) }
end
soldToVendor = {}
C_Container = {
    GetContainerNumSlots = function(bag)
        return bags[bag] and 16 or 0
    end,
    GetContainerItemInfo = function(bag, slot)
        return bags[bag] and bags[bag][slot]
    end,
    UseContainerItem = function(bag, slot)
        soldToVendor[#soldToVendor + 1] = bags[bag][slot]
        bags[bag][slot] = nil
    end,
}
ItemLocation = {
    CreateFromBagAndSlot = function(_, bag, slot)
        return { bag = bag, slot = slot }
    end,
}

function fire(event, ...)
    ForeverFlip.Engine.handle(event, ...)
end
-- Runs the addon for `seconds` of game time, one update per 0.05 s.
function run(seconds)
    for _ = 1, math.floor((seconds or 1) / 0.05) do
        now = now + 0.05
        ForeverFlip.Engine.update(0.05)
    end
end
-- Full scan through the fake auction house until it is processed.
function fullScan()
    local ok, why = ForeverFlip.Scan.start()
    assert(ok, why)
    fire("REPLICATE_ITEM_LIST_UPDATE")
    local n = 0
    while ForeverFlip.Scan.busy() do
        run(0.05)
        n = n + 1
        assert(n < 100000, "scan never ends")
    end
end
-- Answers the pending exact search.
function answer()
    local s = ForeverFlip.Deals.search
    assert(s, "no search in flight")
    if s.item.kind == "commodity" then
        fire("COMMODITY_SEARCH_RESULTS_UPDATED", s.item.id)
    elseif s.phase then
        -- Gear: the browse for its versions (page by page), then one search per version.
        local guard = 0
        while ForeverFlip.Deals.search == s and s.phase == "browse" do
            browseAnswer()
            guard = guard + 1
            assert(guard < 50, "gear browse never ends")
        end
        while ForeverFlip.Deals.search == s and s.phase == "keys" do
            fire("ITEM_SEARCH_RESULTS_UPDATED", s.keys[s.keyIndex])
            guard = guard + 1
            assert(guard < 50, "gear versions never end")
        end
    else
        fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = s.item.id })
    end
end


-- Mailbox -------------------------------------------------------------------------------------------
MailFrame = CreateFrame("Frame")
AUCTION_WON_MAIL_SUBJECT = "Auction won: %s"
AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
inbox = {} -- { sender, subject, money, cod, items, invoice }
freeBagSlots = 20
function GetInboxNumItems()
    return #inbox
end
function GetInboxHeaderInfo(i)
    local m = inbox[i]
    return nil, nil, m.sender, m.subject, m.money or 0, m.cod or 0, 30, (m.items or 0) > 0 and m.items or nil
end
-- invoice: a type string, or { kind, item, bid, deposit, cut, count } for a full invoice.
function GetInboxInvoiceInfo(i)
    local inv = inbox[i] and inbox[i].invoice
    if type(inv) == "table" then
        return inv.kind, inv.item, "Buyer", inv.bid, inv.bid, inv.deposit or 0, inv.cut or 0, 0, 0, inv.count or 1
    end
    return inv
end
AUCTION_REMOVED_MAIL_SUBJECT = "Auction cancelled: %s"
mailTaken = {}
local function dropEmpty(i)
    local m = inbox[i]
    if (m.money or 0) == 0 and (m.items or 0) == 0 then
        table.remove(inbox, i)
    end
end
function TakeInboxMoney(i)
    mailTaken[#mailTaken + 1] = { "money", inbox[i].subject, inbox[i].money }
    inbox[i].money = 0
    dropEmpty(i)
end
function AutoLootMailItem(i)
    mailTaken[#mailTaken + 1] = { "item", inbox[i].subject }
    inbox[i].items = 0
    freeBagSlots = freeBagSlots - 1
    dropEmpty(i)
end
C_Container.GetContainerNumFreeSlots = function(bag)
    return bag == 0 and freeBagSlots or 0
end

-- Tooltips ------------------------------------------------------------------------------------------
Enum.TooltipDataType = { Item = 0 }
tooltipCalls = {}
TooltipDataProcessor = {
    AddTooltipPostCall = function(_, fn)
        tooltipCalls[#tooltipCalls + 1] = fn
    end,
}
tooltipLines = {}
function GameTooltip:AddLine(text)
    tooltipLines[#tooltipLines + 1] = text
end
function GameTooltip:AddDoubleLine(left, right)
    tooltipLines[#tooltipLines + 1] = left .. " = " .. right
end
function GameTooltip:GetItem()
    return self.itemName, self.itemLink
end


-- Merchant -----------------------------------------------------------------------------------------
merchantItems = {} -- { id, price, quantity, available, extended }
merchantBought = {}
function GetMerchantNumItems()
    return #merchantItems
end
C_MerchantFrame = {
    GetItemInfo = function(i)
        local m = merchantItems[i]
        return m
            and {
                name = items[m.id].name,
                price = m.price,
                stackCount = m.quantity or 1,
                numAvailable = m.available or -1,
                isPurchasable = true,
                hasExtendedCost = m.extended or false,
            }
    end,
}
function GetMerchantItemLink(i)
    return link(merchantItems[i].id)
end
function BuyMerchantItem(i, qty)
    merchantBought[#merchantBought + 1] = { i, qty }
end

-- Browse and key queries (fast sniper) --------------------------------------------------------------
-- enableBrowse(pageSize) installs the browse API. Queries are answered by browseAnswer(), one page
-- per call, like the server: the lowest price and total quantity of each item, cheapest first.
browseShown = {}
local browseRows, browseFull, browsePending, browseQuery = {}, true, false, nil
local function browseAll(ids, search)
    local byItem, out = {}, {}
    search = search and string.lower(search) or ""
    for _, a in ipairs(auctions) do
        local named = search == "" or string.lower(a.name or items[a.item].name):find(search, 1, true)
        if (not ids or ids[a.item]) and named then
            local unit = a.buyout / a.count
            local r = byItem[a.item]
            if not r then
                r = { itemKey = { itemID = a.item, itemLevel = 0, itemSuffix = 0 }, minPrice = unit, totalQuantity = 0 }
                byItem[a.item] = r
                out[#out + 1] = r
            end
            r.minPrice = math.min(r.minPrice, unit)
            r.totalQuantity = r.totalQuantity + a.count
        end
    end
    table.sort(out, function(x, y)
        return x.minPrice < y.minPrice
    end)
    return out
end
function enableBrowse(pageSize)
    pageSize = pageSize or 1000
    C_AuctionHouse.SendBrowseQuery = function(query)
        call("SendBrowseQuery", query)
        browseQuery, browseShown, browsePending = browseAll(nil, query and query.searchString), {}, true
    end
    C_AuctionHouse.SearchForItemKeys = function(keys)
        local ids = {}
        for _, k in ipairs(keys) do
            ids[k.itemID] = true
        end
        call("SearchForItemKeys", #keys)
        browseQuery, browseShown, browsePending = browseAll(ids), {}, true
    end
    C_AuctionHouse.RequestMoreBrowseResults = function()
        call("RequestMoreBrowseResults")
        browsePending = true
    end
    C_AuctionHouse.GetBrowseResults = function()
        return browseShown
    end
    C_AuctionHouse.HasFullBrowseResults = function()
        return #browseShown >= #(browseQuery or {})
    end
    function browseAnswer()
        assert(browsePending, "no browse request pending")
        browsePending = false
        local first = #browseShown == 0
        for _ = 1, pageSize do
            local r = browseQuery[#browseShown + 1]
            if not r then
                break
            end
            browseShown[#browseShown + 1] = r
        end
        fire(first and "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or "AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
    end
    function browsePendingNow()
        return browsePending
    end
end

-- Time left of full-scan rows (lot-by-lot sales tracking): auction.timeLeft 1..4, default 4.
function enableTimeLeft()
    C_AuctionHouse.GetReplicateItemTimeLeft = function(i)
        local a = replicated[i]
        return a and (a.timeLeft or 4)
    end
end
