local F=ForeverFlip; local U=F.Util; local P={}; F.Professions=P
function P.parse(text,fraction)
    local out={}; if type(text)~='string' or #text>16000 then return nil,'Input size' end
    for part in text:gmatch('[^,;\n]+') do
        local id,q,price=part:match('^%s*(%d+)%s*%*%s*([%d%.]+)%s*@%s*([%d%.]+)%s*$')
        if not id then id,q=part:match('^%s*(%d+)%s*%*%s*([%d%.]+)%s*$') end
        id,q=tonumber(id),tonumber(q)
        if not id or id<1 or not U.finite(q) or q<=0 or q>100000 or (not fraction and q~=math.floor(q)) then return nil,'ID*quantity@price' end
        out[#out+1]={id=id,qty=q,price=price and U.copper(price)}
        if #out>100 then return nil,'Maximum 100 materials' end
    end
    if #out==0 then return nil,'No materials' end; return out
end
function P.calculate(materials,lookup,outputQty,outputPrice,o)
    o=o or {}; local r={complete=true,cost=0,cashCost=0,shopping={},missing={},profit=nil}
    if not U.finite(outputQty) or outputQty<=0 or not U.finite(outputPrice) or outputPrice<=0 then r.complete=false; return r end
    for _,m in ipairs(materials or {}) do
        local price=m.price or (lookup and lookup(m.id))
        if not U.finite(m.qty) or m.qty<=0 or not U.finite(price) or price<=0 then
            r.complete=false; r.missing[#r.missing+1]=m.id
        else
            local cost=math.ceil(m.qty*price); local missing=math.max(0,m.qty-(m.owned or 0))
            r.cost=r.cost+cost; r.cashCost=r.cashCost+math.ceil(missing*price)
            r.shopping[#r.shopping+1]={id=m.id,qty=missing,price=price,cost=math.ceil(missing*price)}
        end
    end
    if r.complete then
        local gross=math.floor(outputQty*outputPrice)
        r.net=gross-F.Market.fee(gross,o.fee or .05,o.minFee)-math.floor(gross*(o.reserve or 0))
        r.profit=r.net-r.cost-(o.extraCost or 0); r.roi=r.cost>0 and r.profit/r.cost or 0
    end
    return r
end
function P.disenchant(yields,lookup,cost,o)
    local total=0; local missing={}
    for _,m in ipairs(yields or {}) do
        local p=m.price or (lookup and lookup(m.id))
        if not U.finite(p) or p<=0 or not U.finite(m.qty) or m.qty<=0 then missing[#missing+1]=m.id
        else total=total+p*m.qty end
    end
    if #missing>0 or not U.finite(cost) or cost<=0 then return {complete=false,missing=missing} end
    o=o or {}; local net=math.floor(total)-F.Market.fee(math.floor(total),o.fee,o.minFee)-math.floor(total*(o.reserve or 0))
    return {complete=true,value=total,net=net,profit=net-cost,roi=(net-cost)/cost}
end
