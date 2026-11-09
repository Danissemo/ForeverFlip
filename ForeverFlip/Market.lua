local F=ForeverFlip; local U=F.Util; local M={}; F.Market=M
function M.stats(history,now)
    local prices,days,tokens,first,last={},{},{},nil,nil
    for _,h in ipairs(history or {}) do
        if U.finite(h.price) and h.price>0 and U.finite(h.at) and h.at<=now and h.at>=now-14*86400 and h.complete~=false then
            local token=tostring(h.token or math.floor(h.at/600))
            if not tokens[token] then
                tokens[token]=true; prices[#prices+1]=h.price; days[math.floor(h.at/86400)]=true
                first=math.min(first or h.at,h.at); last=math.max(last or h.at,h.at)
            end
        end
    end
    local nDays=0; for _ in pairs(days) do nDays=nDays+1 end
    local ref=U.median(prices); local deviations={}
    for _,p in ipairs(prices) do deviations[#deviations+1]=math.abs(p-(ref or 0)) end
    local sigma=(U.median(deviations) or 0)*1.4826
    local age=last and now-last or math.huge
    local credible=#prices>=5 and nDays>=2 and last-first>=86400 and age<=2*86400
    local confidence=math.min(1,#prices/12)*math.min(1,nDays/3)*math.exp(-age/(2*86400))
    return {reference=ref,sigma=sigma,volatility=ref and sigma/ref or 1,n=#prices,days=nDays,age=age,
        credible=not not credible,confidence=confidence,
        lower=ref and math.max(0,math.floor(ref-1.645*sigma/math.sqrt(math.max(1,#prices)))) or nil}
end
function M.fee(total,rate,minimum) return math.min(total,math.max(math.floor(total*(rate or .05)+.5),minimum or 0)) end
function M.plan(input,history,o)
    o=o or {}; local now=o.now or time(); local s=M.stats(history,now)
    local p={qty=0,cost=0,lots={},reasons={},stats=s,canBuy=false,profit=0,roi=0,mode=o.mode or 'flip',complete=o.complete~=false}
    local rows={}; local totalQty=0
    for _,v in ipairs(input or {}) do
        if U.finite(v.qty) and v.qty>0 and v.qty==math.floor(v.qty) and U.finite(v.unit) and v.unit>0
            and U.finite(v.cost) and v.cost>0 and v.cost==math.floor(v.cost) then
            rows[#rows+1]=v; totalQty=totalQty+v.qty
        end
    end
    table.sort(rows,function(a,b)if a.unit==b.unit then return (a.auctionID or 0)<(b.auctionID or 0) end; return a.unit<b.unit end)
    p.rows=rows; p.totalQty=totalQty; p.minimum=rows[1] and rows[1].unit
    local wallet=U.number(o.wallet,0,0); local free=math.max(0,wallet-U.number(o.reserved,0,0)-math.floor(wallet*(o.cashFloor or .20)))
    p.budget=math.max(0,math.floor(math.min(o.budget or free,free,wallet*(o.maxWallet or .10),o.absoluteCap or math.huge,
        math.max(0,(wallet+(o.stock or 0))*(o.maxItem or .20)-(o.exposure or 0)))))
    local roi=U.number(o.minROI,.25,0,10); local fee=U.number(o.fee,.05,0,.5); local reserve=U.number(o.reserve,.02,0,.5)
    local target,limit
    if p.mode=='vendor' then
        target=U.number(o.vendor,nil,1); limit=target and math.floor(target/(1+roi))
    else
        local sources={market=s.lower,recent=p.minimum,vendorsell=o.vendor,avgbuy=o.avgBuy,tsm=o.tsm,aux=o.aux}
        local explicit=o.sellPrice or F.Expr.eval(o.sellFormula or '90% market',sources)
        target=explicit and math.floor(explicit)
        limit=o.buyLimit or F.Expr.eval(o.buyFormula or '70% market',sources)
        if target then limit=math.min(limit or math.huge,target*(1-fee-reserve)/(1+roi)) end
        if not s.credible then p.reasons[#p.reasons+1]='history' end
        if s.volatility>.30 then p.reasons[#p.reasons+1]='volatility' end
        if s.reference and p.minimum and p.minimum<s.reference*.6 and totalQty>8 then p.reasons[#p.reasons+1]='crash' end
    end
    p.target=target; p.buyLimit=limit or 0
    local maxQty=math.floor(U.number(o.maxQty,100,1,100000))
    if p.mode~='vendor' then maxQty=math.min(maxQty,math.max(1,math.floor(totalQty*(o.maxShare or .15)))) end
    if o.legacyUnresolved then p.reasons[#p.reasons+1]='legacy' end
    if not target or target<=0 or not limit or limit<=0 then p.reasons[#p.reasons+1]='exit' end
    for index,row in ipairs(rows) do
        if not limit or row.unit>limit or p.qty>=maxQty then break end
        local n=row.qty; local cost=row.cost
        if o.commodity~=false then
            n=math.min(n,maxQty-p.qty,math.floor((p.budget-p.cost)/row.unit)); cost=n*row.unit
        elseif n>maxQty-p.qty or cost>p.budget-p.cost then break end
        if n<1 or cost<=0 or cost~=math.floor(cost) then break end
        p.qty=p.qty+n; p.cost=p.cost+cost; p.maxUnit=row.unit
        p.lots[#p.lots+1]={qty=n,cost=cost,unit=row.unit,auctionID=row.auctionID,index=index}
        if n<row.qty then p.nextPrice=row.unit; break end
        p.nextPrice=rows[index+1] and rows[index+1].unit
    end
    p.avg=p.qty>0 and p.cost/p.qty or 0
    if p.qty>0 and target then
        local gross=math.floor(p.qty*target)
        local cut=p.mode=='vendor' and 0 or M.fee(gross,fee,o.minFee)
        local riskReserve=p.mode=='vendor' and 0 or math.floor(gross*reserve)
        p.fee=cut; p.reserve=riskReserve; p.profit=gross-cut-riskReserve-p.cost-(o.extraCost or 0)
        p.roi=p.cost>0 and p.profit/p.cost or 0
        local factor=p.mode=='vendor' and 1 or 1-fee-reserve
        p.breakEven=factor>0 and math.ceil((p.cost+(o.extraCost or 0)+(o.minFee or 0))/p.qty/factor) or nil
        p.liquidation=o.vendor and math.floor(p.qty*o.vendor-p.cost) or nil
        -- Risk-adjusted capital efficiency, not a promised expected return.
        p.confidence=p.mode=='vendor' and 1 or s.confidence
        p.downside=math.max(0,-(p.liquidation or -p.cost))
        p.score=(p.profit*p.confidence-p.downside*(1-p.confidence))/math.max(1,p.cost)
    end
    if not p.complete then p.reasons[#p.reasons+1]='partial' end
    if p.qty==0 then p.reasons[#p.reasons+1]='budget/price' end
    if p.profit<(o.minProfit or 10000) or p.roi<roi then p.reasons[#p.reasons+1]='margin' end
    p.canBuy=p.qty>0 and p.profit>0 and #p.reasons==0
    return p
end
