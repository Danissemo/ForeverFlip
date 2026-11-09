local F=ForeverFlip; local U=F.Util; local A={}; F.Adapters=A
function A.prices(item)
    local out={}; local id=type(item)=='table' and item.itemID or tonumber(item)
    local atr=Auctionator and Auctionator.API and Auctionator.API.v1
    if atr and atr.GetAuctionPriceByItemID and id then
        local ok,p=pcall(atr.GetAuctionPriceByItemID,'ForeverFlip',id)
        if ok and U.finite(p) and p>0 then out[#out+1]={source='Auctionator',price=p,age=nil} end
    end
    if AuxForeverAPI and AuxForeverAPI.GetUsualPrice then
        local ok,p,age=pcall(AuxForeverAPI.GetUsualPrice,id)
        if ok and U.finite(p) and p>0 then out[#out+1]={source='auxForever',price=p,age=age and age*86400} end
    end
    return out
end
function A.native(db)
    local C=C_AuctionHouse or {}; local api={}
    api.clock=function() return time() end
    api.wallet=function() return GetMoney() end
    api.owner=function() return tostring(GetRealmID and GetRealmID() or GetRealmName())..':'..tostring(UnitGUID('player')) end
    api.scope=function() return 'wowf:'..tostring(GetCurrentRegion and GetCurrentRegion() or '?')..':'..
        tostring(GetRealmID and GetRealmID() or GetRealmName())..':'..tostring(db.ui and db.ui.house or UnitFactionGroup('player')) end
    api.isOpen=function() return AuctionHouseFrame and AuctionHouseFrame:IsShown() and not (InCombatLockdown and InCombatLockdown()) end
    api.ready=function() return not C.IsThrottledMessageSystemReady or C.IsThrottledMessageSystemReady() end
    api.search=function(key)
        C.SendSearchQuery(key,{{sortOrder=Enum.AuctionHouseSortOrder.Price,reverseSort=false}},true)
    end
    api.more=function(key,kind)
        if kind=='commodity' then C.RequestMoreCommoditySearchResults(key.itemID) else C.RequestMoreItemSearchResults(key) end
    end
    api.rows=function(key,kind)
        local rows,bids={},{}; local complete
        if kind=='commodity' then
            complete=C.HasFullCommoditySearchResults(key.itemID)
            for i=1,(C.GetNumCommoditySearchResults(key.itemID) or 0) do
                local r=C.GetCommoditySearchResultInfo(key.itemID,i)
                if r and r.quantity>0 and r.unitPrice>0 and not r.containsOwnerItem and not r.containsAccountItem then
                    rows[#rows+1]={qty=r.quantity,unit=r.unitPrice,cost=r.quantity*r.unitPrice,auctionID=r.auctionID}
                end
            end
        else
            complete=C.HasFullItemSearchResults(key)
            for i=1,(C.GetNumItemSearchResults(key) or 0) do
                local r=C.GetItemSearchResultInfo(key,i)
                if r and U.key(r.itemKey)==U.key(key) and not r.containsOwnerItem and not r.containsAccountItem and (r.quantity or 0)>0 then
                    if (r.buyoutAmount or 0)>0 then rows[#rows+1]={qty=r.quantity,unit=r.buyoutAmount/r.quantity,cost=r.buyoutAmount,auctionID=r.auctionID} end
                    if (r.minBid or 0)>0 then bids[#bids+1]=r end
                end
            end
        end
        return rows,complete,kind,bids
    end
    api.quote=function(id,qty) C.StartCommoditiesPurchase(id,qty) end
    api.confirm=function(id,qty) C.ConfirmCommoditiesPurchase(id,qty) end
    api.cancelQuote=function() if C.CancelCommoditiesPurchase then C.CancelCommoditiesPurchase() end end
    api.quoteRemaining=function() return C.GetQuoteDurationRemaining and C.GetQuoteDurationRemaining() end
    api.buyItem=function(auctionID,cost) C.PlaceBid(auctionID,cost) end
    api.vendor=U.vendor
    api.replicate=function() C.ReplicateItems() end
    api.replicateCount=function() return C.GetNumReplicateItems() end
    api.replicateRow=function(i)
        local _,_,qty,_,_,_,_,bid,_,buyout,_,_,_,owner,_,_,id,complete=C.GetReplicateItemInfo(i)
        if not id or not qty or qty<1 or (buyout or 0)<=0 then return nil end
        local link=C.GetReplicateItemLink and C.GetReplicateItemLink(i)
        local suffix=0
        if link then local raw=link:match('item:([^|]+)'); if raw then
            local fields={}; for x in (raw..':'):gmatch('(.-):') do fields[#fields+1]=x end
            suffix=tonumber(fields[7]) or 0
        end end
        -- Item level cannot always be recovered from replication: discovery only.
        return {id=id,qty=qty,buyout=buyout,bid=bid,key={itemID=id,itemSuffix=suffix},link=link,complete=complete,owner=owner,family=true}
    end
    api.bagItems=function()
        local out={}; if not C_Container or not ItemLocation then return out end
        for bag=0,4 do for slot=1,(C_Container.GetContainerNumSlots(bag) or 0) do
            local r=C_Container.GetContainerItemInfo(bag,slot)
            if r and not r.isLocked and r.itemID then
                local loc=ItemLocation:CreateFromBagAndSlot(bag,slot)
                local ok,key=pcall(C.GetItemKeyFromItem,loc)
                if ok and key then out[#out+1]={id=r.itemID,key=key,qty=r.stackCount,loc=loc,link=r.hyperlink} end
            end
        end end
        return out
    end
    api.deposit=function(item,kind,qty,duration)
        if kind=='commodity' then return C.CalculateCommodityDeposit(item.id,duration,qty) end
        return C.CalculateItemDeposit(item.loc,duration,qty)
    end
    api.post=function(item,kind,qty,price,duration,confirm)
        if kind=='commodity' then
            local fn=confirm and C.ConfirmPostCommodity or C.PostCommodity
            return fn(item.loc,duration,qty,price)
        end
        local fn=confirm and C.ConfirmPostItem or C.PostItem
        return fn(item.loc,duration,1,nil,price)
    end
    api.mail=function()
        local out={}; if not GetInboxInvoiceInfo then return out end
        for i=1,(GetInboxNumItems() or 0) do
            local kind,name,player,bid,buyout,deposit,cut,delay,_,_,count=GetInboxInvoiceInfo(i)
            local _,_,sender,subject,money=GetInboxHeaderInfo(i)
            if kind=='seller' or kind=='buyer' then out[#out+1]={index=i,kind=kind,name=name,qty=count or 1,
                amount=money or 0,bid=bid,buyout=buyout,deposit=deposit,cut=cut,delay=delay,
                fingerprint=table.concat({kind,tostring(name),tostring(player),tostring(bid),tostring(count),tostring(subject)},'|')}
            end
        end
        return out
    end
    return api
end
