local F=ForeverFlip; local U=F.Util; local S={}; F.Store=S
S.defaults={minROI=.25,minProfit=10000,maxWallet=.10,maxItem=.20,cashFloor=.20,
    maxQty=100,maxShare=.15,fee=.05,minFee=0,reserve=.02,buyFormula='70% market',sellFormula='max(vendorsell,90% market)',safe=true}
function S.writable(db) return type(db)=='table' and db.schemaVersion==5 end
function S.open(old)
    if type(old)=='table' and old.schemaVersion then
        if old.schemaVersion==5 then
            for k,v in pairs({settings={},watchlist={},groups={},ledger={},legacyLedger={},markets={},pending={},recipes={},disenchant={},vendorPrices={},receipts={},ui={},quarantine={}}) do
                if type(old[k])~='table' then old[k]=v end
            end
            for k,v in pairs(S.defaults) do if old.settings[k]==nil then old.settings[k]=v end end
        end
        return old
    end
    local db={schemaVersion=5,settings=U.copy(S.defaults),watchlist={},groups={},ledger={},legacyLedger={},
        markets={},pending={},recipes={},disenchant={},vendorPrices={},receipts={},ui={},quarantine={},sequence=0}
    if type(old)=='table' then
        db.watchlist=U.copy(old.watchlist or {}); db.recipes=U.copy(old.recipes or {})
        db.disenchant=U.copy(old.disenchant or {}); db.legacyLedger=U.copy(old.ledger or {})
        db.legacyHistory=U.copy(old.history or {}); db.legacyRadarHistory=U.copy(old.radarHistory or {})
        db.groups=U.copy(old.groups or {}); db.ui.theme=old.uiTheme
        if U.finite(old.fee) then db.settings.fee=old.fee end
        if U.finite(old.reserve) then db.settings.reserve=old.reserve end
        if U.finite(old.beginnerMaxCopper) then db.settings.absoluteCap=old.beginnerMaxCopper end
    end
    return db,old
end
function S.observe(db,scope,key,o)
    if not S.writable(db) or not scope or not key or not U.finite(o.at) or not U.finite(o.price) or o.price<=0 or not o.complete then return false end
    db.markets[scope]=db.markets[scope] or {}; local m=db.markets[scope]
    local h=m[key]
    if not h then
        local count=0; for _ in pairs(m) do count=count+1 end
        if count>=2000 then
            local oldest,stamp
            for k,v in pairs(m) do
                local id=tonumber(k:match('^(%d+)')); local watched=false
                for _,w in ipairs(db.watchlist) do if w==id then watched=true end end
                if not watched and (not stamp or (v.at or 0)<stamp) then oldest=k; stamp=v.at or 0 end
            end
            if not oldest then return false end; m[oldest]=nil
        end
        h={samples={},days={}}; m[key]=h
    end
    for _,s in ipairs(h.samples) do if (o.token and s.token==o.token) or math.abs(s.at-o.at)<600 then return false end end
    h.samples[#h.samples+1]=U.copy(o); while #h.samples>120 do table.remove(h.samples,1) end
    h.at=math.max(h.at or 0,o.at); h.latest=U.copy(o)
    local day=math.floor(o.at/86400); local d
    for _,v in ipairs(h.days) do if v.day==day then d=v end end
    if not d then d={day=day,price=0,n=0,low=o.price,high=o.price,qty=0}; h.days[#h.days+1]=d end
    d.price=(d.price*d.n+o.price)/(d.n+1); d.n=d.n+1
    d.low=math.min(d.low,o.price); d.high=math.max(d.high,o.price); d.qty=o.qty or 0
    table.sort(h.days,function(a,b)return a.day<b.day end)
    while #h.days>60 or (#h.days>0 and h.days[1].day<math.floor(h.at/86400)-59) do table.remove(h.days,1) end
    return true
end
function S.watch(db,id)
    id=tonumber(id); if not id or id<1 or id~=math.floor(id) then return false,'Item ID' end
    for _,v in ipairs(db.watchlist) do if v==id then return true end end
    if #db.watchlist>=500 then return false,'Watchlist limit: 500' end
    db.watchlist[#db.watchlist+1]=id; return true
end
function S.importGroup(text)
    if type(text)~='string' or #text>8000 then return nil,'Size' end
    local name,ids,roi,profit,budget,qty=text:match('^FFG1|([^|\r\n]+)|([%d,]+)|([%d%.]+)|([%d%.]+)|([%d%.]+)|(%d+)$')
    if not name then return nil,'FFG1 format required' end
    local g={name=name,items={},rule={}}
    local count=0; for s in ids:gmatch('%d+') do local id=tonumber(s); if id<1 then return nil,'ID' end; g.items[id]=true; count=count+1 end
    if count>500 or count==0 then return nil,'Items limit' end
    g.rule.minROI=tonumber(roi)/100; g.rule.minProfit=U.copper(profit); g.rule.budget=U.copper(budget); g.rule.maxQty=tonumber(qty)
    if g.rule.minROI>10 or not g.rule.minProfit or not g.rule.budget or g.rule.maxQty<1 or g.rule.maxQty>100000 then return nil,'Rule limits' end
    return g
end
function S.exportGroup(g)
    local ids=U.sortedKeys(g.items); local r=g.rule or {}
    return table.concat({'FFG1',g.name,table.concat(ids,','),(r.minROI or .25)*100,U.gold(r.minProfit or 10000),U.gold(r.budget or 1000000),r.maxQty or 100},'|')
end
