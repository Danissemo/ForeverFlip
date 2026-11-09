local F=ForeverFlip; local U=F.Util; local UI={}; F.UI=UI
local function L(r,e) return e or r end
local reasons={history=L('Insufficient independent history','Insufficient independent history'),volatility=L('High volatility','High volatility'),
    crash=L('Market drop','Market drop'),legacy=L('Reconcile legacy positions','Reconcile legacy positions'),
    exit=L('No exit price','No exit price'),partial=L('Partial results','Partial results'),
    ['budget/price']=L('Price or budget limit','Price or budget limit'),margin=L('Profit/ROI below rule','Profit/ROI below rule'),stale=L('Stale snapshot','Stale snapshot')}
local messages={ready=L('Open AH and scan or enter an item ID.','Open AH and scan or enter an item ID.'),
    searching=L('Searching…','Searching…'),plan_ready=L('Plan ready. Request quote or buy one lot.','Plan ready. Request quote or buy one lot.'),
    plan_review=L('Review the reasons in the trade card.','Review the reasons in the trade card.'),
    partial=L('Full results required; request more.','Full results required; request more.'),
    quote_wait=L('Waiting for a quote; no purchase yet.','Waiting for a quote; no purchase yet.'),
    quote_ready=L('Quote ready; confirm with a separate click.','Quote ready; confirm with a separate click.'),
    await_receipt=L('Sent; awaiting purchase receipt.','Sent; awaiting purchase receipt.'),
    purchase_recorded=L('Purchase recorded. Collect your items.','Purchase recorded. Collect your items.'),
    unknown=L('Unknown result. Funds remain reserved; reconcile.','Unknown result. Funds remain reserved; reconcile.'),
    price_changed=L('Price changed; quote cancelled.','Price changed; quote cancelled.'),
    readonly=L('Unsupported data schema: read-only.','Unsupported data schema: read-only.'),
    auction_closed=L('Trading requires an open AH and no combat.','Trading requires an open AH and no combat.'),
    buy_blocked=L('Purchase blocked. Check plan freshness and conditions.','Purchase blocked. Check plan freshness and conditions.'),
    resolve_pending=L('Reconcile the pending trade in Portfolio first.','Reconcile the pending trade in Portfolio first.'),
    throttled=L('AH throttled; retry after a pause.','AH throttled; retry after a pause.'),
    search_busy=L('Wait for the current search or press Stop.','Wait for the current search or press Stop.'),
    search_timeout=L('Search timed out; retry manually.','Search timed out; retry manually.'),
    replicate_cooldown=L('Full scan cooldown: approximately 15 minutes.','Full scan cooldown: approximately 15 minutes.'),
    replicate_wait=L('Waiting for full replication…','Waiting for full replication…'),
    replicate_done=L('Scan ready. Select a deal for exact verification.','Scan ready. Select a deal for exact verification.'),
    replicate_timeout=L('Replication timed out; another addon may have scanned.','Replication timed out; another addon may have scanned.'),
    watching=L('Watching for 10 minutes. All trades require clicks.','Watching for 10 minutes. All trades require clicks.'),
    watch_finished=L('Watch session ended.','Watch session ended.'),stopped=L('Stopped.','Stopped.'),
    rescan=L('Settings changed. Search again.','Settings changed. Search again.'),
    post_values=L('Check quantity and price; increment is 1 silver.','Check quantity and price; increment is 1 silver.'),
    post_floor=L('Price below sale floor or NPC net value.','Price below sale floor or NPC net value.'),
    deposit_unknown=L('Cannot verify deposit or funds.','Cannot verify deposit or funds.'),
    post_confirm=L('Click Post again to confirm.','Click Post again to confirm.'),
    post_sent=L('Posting sent. Check your auctions.','Posting sent. Check your auctions.'),
    bid_reserved=L('Bid sent; funds reserved until reconciliation.','Bid sent; funds reserved until reconciliation.'),
    ledger_full=L('Ledger blocked: limit or invalid receipt.','Ledger blocked: limit or invalid receipt.'),
    reconciled=L('Reconciliation saved.','Reconciliation saved.'),quote_expired=L('Quote expired.','Quote expired.'),
    mail_review=L('Mail invoices ready for manual reconciliation.','Mail invoices ready for manual reconciliation.')}
local function text(parent,x,y,w,value,font)
    local v=parent:CreateFontString(nil,'OVERLAY',font or 'GameFontHighlightSmall')
    v:SetPoint('TOPLEFT',x,-y); v:SetWidth(w); v:SetJustifyH('LEFT'); v:SetJustifyV('TOP'); v:SetWordWrap(true); v:SetText(value or '')
    return v
end
local function button(parent,x,y,w,value,callback)
    local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate'); b:SetPoint('TOPLEFT',x,-y); b:SetSize(w,26); b:SetText(value)
    b:SetScript('OnClick',callback); return b
end
local function field(parent,x,y,w,title,value,multi)
    text(parent,x,y,w,title)
    local e=CreateFrame('EditBox',nil,parent,multi and 'BackdropTemplate' or 'InputBoxTemplate')
    e:SetPoint('TOPLEFT',x+4,-y-20); e:SetSize(w-8,multi and 110 or 24); e:SetAutoFocus(false)
    e:SetFontObject('GameFontHighlightSmall'); e:SetText(tostring(value or ''))
    if multi then e:SetMultiLine(true); e:SetTextInsets(6,6,6,6); e:SetBackdrop({bgFile='Interface/Buttons/WHITE8X8'}); e:SetBackdropColor(.09,.12,.17,1) end
    e:SetMaxLetters(multi and 120000 or 1024); e:SetScript('OnEscapePressed',function(s)s:ClearFocus()end)
    e:SetScript('OnEnterPressed',function(s)if not multi then s:ClearFocus()end end); return e
end
local function panel(parent)
    local f=CreateFrame('Frame',nil,parent,'BackdropTemplate')
    f:SetBackdrop({bgFile='Interface/Buttons/WHITE8X8',edgeFile='Interface/Buttons/WHITE8X8',edgeSize=1})
    f:SetBackdropColor(.035,.05,.075,.99); f:SetBackdropBorderColor(.20,.36,.46,1); return f
end
local function warningList(p)
    local out={}; for _,r in ipairs(p.reasons or {}) do out[#out+1]=reasons[r] or r end
    return table.concat(out,'; ')
end
function UI.create(c)
    local self=setmetatable({c=c,sections={},fields={},actions={},refreshers={},section='overview',dealPage=1,sort='score',filterMode='all',toolMode='craft'}, {__index=UI})
    local db=c.db; local settings=db.settings or F.Store.defaults
    local host=panel(AuctionHouseFrame or UIParent); self.frame=host
    host:SetSize(1080,680); host:SetPoint('TOPLEFT',AuctionHouseFrame or UIParent,'TOPLEFT',0,0)
    host:SetFrameStrata('HIGH'); host:SetClampedToScreen(true); host:SetMovable(true); host:EnableMouse(true)
    host:RegisterForDrag('LeftButton'); host:SetScript('OnDragStart',function(s)s:StartMoving()end); host:SetScript('OnDragStop',function(s)s:StopMovingOrSizing()end)
    text(host,18,15,175,'FOREVER|cff6dd7bdFLIP|r','GameFontNormalLarge')
    text(host,18,42,150,'5.0 · PREVIEW')
    self.header=text(host,190,15,760,'','GameFontNormal')
    self.fields.item=field(host,190,40,190,L('Item: ID / link / key','Item: ID / link / key'),'')
    local function readKey()
        local s=self.fields.item:GetText(); return U.fromKey(s) or {itemID=tonumber(s:match('item:(%d+)') or s)}
    end
    self.readKey=readKey
    self.actions.search=button(host,390,60,130,L('Exact search','Exact search'),function()
        local key=readKey(); if c:search(key) then self:show('trade') end
    end)
    self.actions.fullScan=button(host,530,60,135,L('Full scan','Full scan'),function() c:fullScan(); self:show('deals') end)
    self.actions.stop=button(host,675,60,90,L('Stop','Stop'),function() c:stop() end)
    button(host,775,60,100,L('Watch','Watch'),function() c:watchStart() end)
    button(host,1005,10,55,'×',function()host:Hide()end)
    host:SetScript('OnReceiveDrag',function()
        if GetCursorInfo then local kind,id=GetCursorInfo(); if kind=='item' then self.fields.item:SetText(tostring(id)); if ClearCursor then ClearCursor()end end end
    end)
    local nav={{'overview',L('Overview','Overview')},{'deals',L('Deals','Deals')},{'trade',L('Trading','Trading')},
        {'watch',L('Watch / rules','Watch / rules')},{'portfolio',L('Portfolio / ledger','Portfolio / ledger')},
        {'history',L('History','History')},{'tools',L('NPC / professions','NPC / professions')},{'settings',L('Settings / data','Settings / data')}}
    self.nav={}
    for i,n in ipairs(nav) do
        local id=n[1]; self.nav[id]=button(host,16,94+(i-1)*38,160,n[2],function()self:show(id)end)
        local scroll=CreateFrame('ScrollFrame',nil,host,'UIPanelScrollFrameTemplate')
        scroll:SetPoint('TOPLEFT',190,-102); scroll:SetPoint('BOTTOMRIGHT',host,'BOTTOMRIGHT',-30,44)
        local body=CreateFrame('Frame',nil,scroll); body:SetSize(840,1100); scroll:SetScrollChild(body)
        self.sections[id]={scroll=scroll,body=body}; scroll:Hide()
    end
    self.status=text(host,190,643,850,'')
    text(host,18,480,155,L('Scan → verify → click → receipt.\n\nEstimated profit is not a guaranteed sale.','Scan → verify → click → receipt.\n\nEstimated profit is not a guaranteed sale.'))
    local function body(id) return self.sections[id].body end
    local function saveable() if not F.Store.writable(db) then c:notify('readonly'); return false end; return true end
    local function action(name,parent,x,y,w,title,fn) local b=button(parent,x,y,w,title,fn); self.actions[name]=b; return b end
    local function val(name,parent,x,y,w,title,value,multi) local e=field(parent,x,y,w,title,value,multi); self.fields[name]=e; return e end
    -- Overview: realized money is kept apart from portfolio valuation.
    do local b=body('overview')
        text(b,0,0,820,L('YOUR TRADING DAY','YOUR TRADING DAY'),'GameFontNormalLarge')
        local overview=text(b,0,42,810,'','GameFontNormal')
        self.refreshers.overview=function()
            local r=c:summary(); local now=c.api.clock(); local day=math.floor(now/86400)
            local today,week,month=0,0,0
            for _,s in ipairs(r.salesHistory) do local age=now-(s.at or 0)
                if math.floor((s.at or 0)/86400)==day then today=today+s.profit end
                if age>=0 and age<=7*86400 then week=week+s.profit end
                if age>=0 and age<=30*86400 then month=month+s.profit end
            end
            overview:SetText(L('Wallet: ','Wallet: ')..U.money(c.api.wallet())..'\n'..
                L('Pending reservations: ','Pending reservations: ')..U.money(c:reserved())..'\n'..
                L('Inventory cost: ','Inventory cost: ')..U.money(r.stock)..'\n\n'..
                L('Realized sales P/L today / 7 / 30 days:\n','Realized sales P/L today / 7 / 30 days:\n')..
                U.money(today)..' / '..U.money(week)..' / '..U.money(month)..'\n'..
                L('Total realized P/L including expenses: ','Total realized P/L including expenses: ')..U.money(r.realized)..'\n'..
                L('Sold with unknown cost: ','Sold with unknown cost: ')..r.unknown..'\n\n'..
                L('Next steps:\n1. Scan or select an item.\n2. Review price and budget in Trading.\n3. Confirm a purchase with a separate click.\n4. Collect items and choose a sale price.\n5. Reconcile completed trades in Portfolio.',
                'Next steps:\n1. Scan or select an item.\n2. Review price and budget in Trading.\n3. Confirm a purchase with a separate click.\n4. Collect items and choose a sale price.\n5. Reconcile completed trades in Portfolio.'))
        end
        action('toDeals',b,0,365,170,L('Find deals','Find deals'),function()self:show('deals')end)
        action('toPortfolio',b,185,365,170,L('Reconcile','Reconcile'),function()self:show('portfolio')end)
        text(b,0,415,800,L('Current character and selected market only. Asking prices and valuations are not earned gold.','Current character and selected market only. Asking prices and valuations are not earned gold.'))
    end
    -- A fixed pool of visible rows, paging and deterministic sorting.
    do local b=body('deals')
        val('dealFilter',b,0,0,260,L('Filter by name / ID / group','Filter by name / ID / group'),'')
        action('filterApply',b,275,20,110,L('Apply','Apply'),function()self.dealPage=1;self:refresh()end)
        action('filterMode',b,395,20,170,L('All strategies','All strategies'),function(btn)
            self.filterMode=self.filterMode=='all' and 'vendor' or self.filterMode=='vendor' and 'flip' or 'all'
            btn:SetText(self.filterMode=='all' and L('All strategies','All strategies') or self.filterMode=='vendor' and 'NPC' or 'FLIP');self:refresh()
        end)
        action('dealSort',b,580,20,220,L('Sort: risk / capital','Sort: risk / capital'),function(btn)
            self.sort=self.sort=='score' and 'profit' or 'score'; btn:SetText(self.sort=='score' and L('Risk / capital','Risk / capital') or L('Net profit','Net profit'));self:refresh()
        end)
        text(b,0,62,820,L('ITEM / STRATEGY                      COST             PROFIT          ROI / EVIDENCE','ITEM / STRATEGY                      COST             PROFIT          ROI / EVIDENCE'),'GameFontNormal')
        self.dealRows={}
        for i=1,12 do local index=i
            self.dealRows[i]=button(b,0,86+(i-1)*31,810,'',function()
                local p=self.visibleDeals and self.visibleDeals[(self.dealPage-1)*12+index]
                if p then self.fields.item:SetText(U.key(p.key)); c.mode=p.mode; c:stop(); c.mode=p.mode; c:search(p.key); self:show('trade') end
            end)
        end
        local pages=text(b,270,473,260,'')
        button(b,0,467,110,'←',function()self.dealPage=math.max(1,self.dealPage-1);self:refresh()end)
        button(b,120,467,110,'→',function()self.dealPage=self.dealPage+1;self:refresh()end)
        text(b,0,515,810,L('A row opens exact verification. Discovery never buys from an old price. NPC and FLIP require different evidence.','A row opens exact verification. Discovery never buys from an old price. NPC and FLIP require different evidence.'))
        self.refreshers.deals=function()
            local all=c:rank(); local out={}; local query=self.fields.dealFilter:GetText():lower()
            for _,p in ipairs(all) do local name=U.name(p.key.itemID); local group=c:rule(p.key.itemID).group or ''
                if (self.filterMode=='all' or p.mode==self.filterMode) and (query=='' or (name..' '..p.key.itemID..' '..group):lower():find(query,1,true)) then out[#out+1]=p end
            end
            if self.sort=='profit' then table.sort(out,function(a,d)return a.profit>d.profit end)end
            self.visibleDeals=out; local count=math.max(1,math.ceil(#out/12)); self.dealPage=math.max(1,math.min(count,self.dealPage))
            pages:SetText(self.dealPage..' / '..count..' · '..#out)
            for i,btn in ipairs(self.dealRows) do local p=out[(self.dealPage-1)*12+i]
                btn:SetEnabled(not not p)
                if p then
                    local mark=p.canBuy and '|cff7ee2ba[+]|r' or '|cffffc86a[?]|r'
                    btn:SetText(string.format('%s %s [%d] · %s · %s → %s · %.1f%% · %s',mark,U.name(p.key.itemID),p.key.itemID,p.mode=='vendor' and 'NPC' or 'FLIP',U.money(p.cost),U.money(p.profit),p.roi*100,p.canBuy and L('Verify','Verify') or warningList(p)))
                else btn:SetText('')end
            end
        end
    end
    do local b=body('trade')
        action('tradeMode',b,0,0,200,L('Strategy: FLIP / NPC','Strategy: FLIP / NPC'),function(btn)
            c:stop(); c.mode=c.mode=='vendor' and 'flip' or 'vendor';btn:SetText(c.mode=='vendor' and 'NPC' or 'FLIP');self:refresh()
        end)
        action('more',b,215,0,170,L('More results','More results'),function()c:more()end)
        action('watchAdd',b,400,0,170,L('Add to watchlist','Add to watchlist'),function()
            if not saveable()then return end; local ok,err=F.Store.watch(db,readKey().itemID);c:notify(ok and L('Item added.','Item added.') or err)
        end)
        self.tradeText=text(b,0,45,805,'','GameFontNormal')
        self.actions.buy=action('buy',b,0,320,245,L('Quote / buy one lot','Quote / buy one lot'),function()c:requestBuy()end)
        self.actions.confirm=action('confirm',b,260,320,245,L('Confirm purchase','Confirm purchase'),function()c:confirmBuy()end)
        action('cancelQuote',b,520,320,170,L('Cancel quote','Cancel quote'),function()c:cancelQuote();self:refresh()end)
        text(b,0,366,810,L('SELL FROM BAGS · search the exact variant first','SELL FROM BAGS · search the exact variant first'),'GameFontNormal')
        val('bagIndex',b,0,394,110,L('Bag row','Bag row'),'1')
        val('postQty',b,125,394,110,L('Quantity','Quantity'),'1')
        val('postPrice',b,250,394,170,L('Unit price, gold','Unit price, gold'),'')
        val('duration',b,435,394,120,L('Duration: 1/2/3','Duration: 1/2/3'),'2')
        action('post',b,570,414,210,L('Post / confirm','Post / confirm'),function()
            local i=tonumber(self.fields.bagIndex:GetText()); local bag=self.bags and self.bags[i]
            c:post(bag,tonumber(self.fields.postQty:GetText()),U.copper(self.fields.postPrice:GetText()),tonumber(self.fields.duration:GetText()))
        end)
        self.bagText=text(b,0,462,810,'')
        text(b,0,630,810,L('BIDS · select row; funds reserved until reconciliation','BIDS · select row; funds reserved until reconciliation'),'GameFontNormal')
        val('bidIndex',b,0,662,120,L('Bid row','Bid row'),'1')
        action('bid',b,140,682,220,L('Place one bid','Place one bid'),function()c:bid(tonumber(self.fields.bidIndex:GetText()))end)
        self.bidText=text(b,0,728,810,'')
        self.refreshers.trade=function()
            local p=c.plan; local lines={}
            if p then
                lines={U.name(p.key.itemID)..' · '..U.key(p.key)..' · '..p.kind..' · '..(p.complete and L('complete','complete')or L('PARTIAL','PARTIAL')),
                    L('Buy: ','Buy: ')..p.qty..' · '..U.money(p.cost)..L(' · budget: ',' · budget: ')..U.money(p.budget),
                    L('Average / maximum: ','Average / maximum: ')..U.money(p.avg)..' / '..U.money(p.maxUnit),
                    L('Exit scenario / unit: ','Exit scenario / unit: ')..U.money(p.target)..L(' · break-even: ',' · break-even: ')..U.money(p.breakEven),
                    L('Net potential: ','Net potential: ')..U.money(p.profit)..string.format(' · ROI %.1f%%',p.roi*100),
                    L('Evidence confidence: ','Evidence confidence: ')..string.format('%.0f%%',100*(p.confidence or 0))..
                        L(' · NPC liquidation: ',' · NPC liquidation: ')..(p.liquidation and U.money(p.liquidation) or '?'),
                    L('Restrictions: ','Restrictions: ')..(warningList(p)~='' and warningList(p) or L('Checks passed; sale not guaranteed','Checks passed; sale not guaranteed'))}
                local depth={}; for i=1,math.min(4,#p.rows) do local r=p.rows[i];depth[#depth+1]=r.qty..' × '..U.money(r.unit) end
                lines[#lines+1]=L('Depth: ','Depth: ')..table.concat(depth,' | ')
                lines[#lines+1]=L('Fee / reserve: ','Fee / reserve: ')..U.money(p.fee)..' / '..U.money(p.reserve)..L(' · age: ',' · age: ')..math.max(0,c.api.clock()-p.at)..'s'
            else lines={L('Enter an ID, link or exact key and press Exact search.\nMissing history means unknown demand.\nFor NPC arbitrage choose NPC and search again.',
                'Enter an ID, link or exact key and press Exact search.\nMissing history means unknown demand.\nFor NPC arbitrage choose NPC and search again.')} end
            self.tradeText:SetText(table.concat(lines,'\n'))
            self.actions.buy:SetEnabled(c.api.isOpen() and c:fresh() and p.canBuy and not c.active and c:reserved()==0 or false)
            self.actions.confirm:SetEnabled(c.api.isOpen() and c:fresh() and c.active and c.active.status=='quoted' or false)
            self.actions.more:SetEnabled(c.api.isOpen() and p and not p.complete and c.job or false)
            self.bags={}; local bagLines={}
            if c.api.bagItems then local ok,items=pcall(c.api.bagItems); if ok then
                for _,item in ipairs(items) do if c.key and U.key(item.key)==U.key(c.key) then self.bags[#self.bags+1]=item end end
            end end
            for i=1,math.min(5,#self.bags) do local item=self.bags[i];bagLines[#bagLines+1]=i..'. '..U.name(item.id)..' × '..item.qty..' · '..U.key(item.key) end
            self.bagText:SetText(#bagLines>0 and table.concat(bagLines,'\n') or L('No matching variant in bags. Select your item and search.','No matching variant in bags. Select your item and search.'))
            local bidLines={};for i=1,math.min(6,#c.bidRows)do local r=c.bidRows[i];bidLines[#bidLines+1]=i..'. #'..r.auctionID..' ×'..r.quantity..' · '..U.money(r.bidAmount or r.minBid)end
            self.bidText:SetText(table.concat(bidLines,'\n'))
        end
    end
    do local b=body('watch')
        text(b,0,0,810,L('LISTS AND OPERATION RULES','LISTS AND OPERATION RULES'),'GameFontNormalLarge')
        local list=text(b,0,40,800,'')
        val('removeWatch',b,0,112,160,L('Remove item ID','Remove item ID'),'')
        action('watchRemove',b,175,132,150,L('Remove from list','Remove from list'),function()
            if not saveable()then return end;local id=tonumber(self.fields.removeWatch:GetText())
            for i=#db.watchlist,1,-1 do if db.watchlist[i]==id then table.remove(db.watchlist,i)end end;c:stop();self:refresh()
        end)
        action('watchStart',b,340,132,180,L('Watch 10 minutes','Watch 10 minutes'),function()c:watchStart()end)
        text(b,0,180,810,L('First matching group overrides defaults. Exchange: FFG1|name|ID,ID|ROI%|profit(g)|budget(g)|quantity','First matching group overrides defaults. Exchange: FFG1|name|ID,ID|ROI%|profit(g)|budget(g)|quantity'))
        val('exchange',b,0,230,810,L('Group import / export','Group import / export'),'FFG1|Cloth|2589,2592|25|1|100|10',true)
        action('groupImport',b,0,370,200,L('Add / replace group','Add / replace group'),function()
            if not saveable()then return end;local g,err=F.Store.importGroup(self.fields.exchange:GetText())
            if g then local found=false;for i,v in ipairs(db.groups)do if v.name==g.name then db.groups[i]=g;found=true end end
                if not found then db.groups[#db.groups+1]=g end;c:invalidate();self:refresh()
            else c:notify(err)end
        end)
        val('groupIndex',b,220,350,100,L('Group row','Group row'),'1')
        action('groupExport',b,340,370,170,L('Export','Export'),function()
            local g=db.groups[tonumber(self.fields.groupIndex:GetText())];if g then self.fields.exchange:SetText(F.Store.exportGroup(g))end
        end)
        action('groupDelete',b,530,370,160,L('Delete group','Delete group'),function()
            if saveable()then local i=tonumber(self.fields.groupIndex:GetText());if i and db.groups[i]then table.remove(db.groups,i);c:invalidate()end end
        end)
        local groups=text(b,0,420,810,'')
        self.refreshers.watch=function()
            local ids={};for _,id in ipairs(db.watchlist or {})do ids[#ids+1]=tostring(id)end
            list:SetText(L('Watchlist: ','Watchlist: ')..table.concat(ids,', ')..'\n'..L('Add items using Trading → Add to watchlist.','Add items using Trading → Add to watchlist.'))
            local lines={};for i,g in ipairs(db.groups or {})do local r=g.rule or {};lines[#lines+1]=i..'. '..g.name..string.format(' · ROI %.0f%%',(r.minROI or 0)*100)..' · '..U.money(r.budget)..' · max '..tostring(r.maxQty or '?')end
            groups:SetText(table.concat(lines,'\n'))
        end
    end
    do local b=body('portfolio')
        self.portfolioText=text(b,0,0,815,'','GameFontNormal')
        val('pendingIndex',b,0,210,120,L('Pending row','Pending row'),'1')
        action('pendingBought',b,140,230,210,L('Purchase completed','Purchase completed'),function()
            local op=self.pendingRows and self.pendingRows[tonumber(self.fields.pendingIndex:GetText())]
            if op then c:reconcile(op.uid,true)end
        end)
        action('pendingCancelled',b,365,230,250,L('Not spent / refunded','Not spent / refunded'),function()
            local op=self.pendingRows and self.pendingRows[tonumber(self.fields.pendingIndex:GetText())]
            if op then c:reconcile(op.uid,false)end
        end)
        text(b,0,275,810,L('ACTUAL TRANSACTION · gold amounts, enter total','ACTUAL TRANSACTION · gold amounts, enter total'),'GameFontNormal')
        val('entryKey',b,0,306,220,L('ID / exact key','ID / exact key'),'')
        val('entryQty',b,235,306,100,L('Quantity','Quantity'),'1')
        val('entryTotal',b,350,306,150,L('Total, gold','Total, gold'),'')
        val('entryFee',b,515,306,130,L('Actual fee, gold','Actual fee, gold'),'0')
        self.entryKind='buy'
        action('entryKind',b,0,370,180,L('Type: purchase','Type: purchase'),function(btn)
            local nextKind={buy='sell',sell='vendor',vendor='expense',expense='buy'}; self.entryKind=nextKind[self.entryKind]
            btn:SetText(({buy=L('Buy','Buy'),sell=L('AH sale','AH sale'),vendor=L('NPC sale','NPC sale'),expense=L('Expense','Expense')})[self.entryKind])
        end)
        action('entrySave',b,200,370,190,L('Record completed trade','Record completed trade'),function()
            if not saveable()then return end
            local raw=self.fields.entryKey:GetText();local key=U.fromKey(raw) or {itemID=tonumber(raw)}
            local identity=U.key(key); local qty=tonumber(self.fields.entryQty:GetText());local amount=U.copper(self.fields.entryTotal:GetText());local fee=U.copper(self.fields.entryFee:GetText())
            if not identity or not fee then c:notify(L('Check identity and fee.','Check identity and fee.'));return end
            local ok,err=F.Ledger.append(db,{kind=self.entryKind,owner=c.api.owner(),scope=c.api.scope(),key=identity,qty=qty,total=amount,fee=fee,at=c.api.clock(),source='manual'})
            c:notify(ok and L('Saved.','Saved.')or err)
        end)
        val('voidID',b,410,350,200,L('UID to correct','UID to correct'),'')
        action('entryVoid',b,625,370,175,L('Append correction','Append correction'),function()
            if saveable()then F.Ledger.correct(db,self.fields.voidID:GetText(),c.api.owner(),c.api.clock());self:refresh()end
        end)
        self.ledgerText=text(b,0,420,810,'')
        text(b,0,630,810,L('MAIL · read invoices only; no automatic collection','MAIL · read invoices only; no automatic collection'),'GameFontNormal')
        action('mailRefresh',b,0,660,180,L('Read invoices','Read invoices'),function()c:event('MAIL_INBOX_UPDATE')end)
        self.mailText=text(b,0,705,810,'')
        action('ledgerExport',b,0,885,200,L('Export ledger CSV','Export ledger CSV'),function()self:exchange(F.Ledger.csv(db.ledger or {}))end)
        self.refreshers.portfolio=function()
            local r=c:summary(); local lines={L('Positions · cost / age / action','Positions · cost / age / action')}
            for i=1,math.min(6,#r.positions)do local p=r.positions[i];local key=U.fromKey(p.key); local price=key and c:price(key.itemID)
                local age=math.max(0,math.floor((c.api.clock()-(p.at or c.api.clock()))/86400))
                local actionText=not price and L('no price','no price') or price*p.qty*.93>p.cost and L('review sale','review sale') or age>=7 and L('reduce / check NPC','reduce / check NPC') or L('watch','watch')
                lines[#lines+1]=p.key..' ×'..p.qty..' · '..U.money(p.cost)..' · '..age..'d · '..actionText
            end
            self.pendingRows={}
            for _,op in pairs(db.pending or {})do if op.owner==c.api.owner() and (op.status=='unknown' or op.status=='bid')then self.pendingRows[#self.pendingRows+1]=op end end
            table.sort(self.pendingRows,function(a,d)return a.at<d.at end)
            lines[#lines+1]='';lines[#lines+1]=L('Pending trades: ','Pending trades: ')..#self.pendingRows
            for i=1,math.min(3,#self.pendingRows)do local op=self.pendingRows[i];lines[#lines+1]=i..'. '..op.key..' ×'..op.qty..' · '..U.money(op.total)..' · '..op.status end
            self.portfolioText:SetText(table.concat(lines,'\n'))
            local entries={};for i=#(db.ledger or {}),math.max(1,#(db.ledger or {})-5),-1 do local e=db.ledger[i]
                entries[#entries+1]=(e.uid or '?')..' · '..(e.kind or '?')..' · '..(e.key or e.target or '?')..' · '..U.money(e.total)
            end; self.ledgerText:SetText(table.concat(entries,'\n'))
            local m={};for i=1,math.min(4,#c.mail)do local e=c.mail[i];m[#m+1]=e.kind..' · '..tostring(e.name)..' ×'..e.qty..' · '..U.money(e.amount)..L(' · reconcile after collection',' · reconcile after collection')end
            self.mailText:SetText(table.concat(m,'\n'))
        end
    end
    do local b=body('history')
        text(b,0,0,810,L('SELECTED ITEM HISTORY · 60 days','SELECTED ITEM HISTORY · 60 days'),'GameFontNormalLarge')
        self.historyText=text(b,0,40,810,'')
        local chart=panel(b);chart:SetPoint('TOPLEFT',0,-108);chart:SetSize(800,220);self.chart=chart;self.chartLines={}
        local tableText=text(b,0,350,810,'')
        self.refreshers.history=function()
            local key=readKey();local h=U.key(key) and c:history(key); local days=h and h.days or {}
            local stat=F.Market.stats(h and h.samples or {},c.api.clock())
            self.historyText:SetText(L('Reference / lower bound: ','Reference / lower bound: ')..U.money(stat.reference)..' / '..U.money(stat.lower)..
                ' · MAD σ '..U.money(stat.sigma)..' · n='..stat.n..' · '..stat.days..L(' days',' days')..'\n'..
                L('Chart: asking prices; disappeared listings are not proven sales.','Chart: asking prices; disappeared listings are not proven sales.'))
            for _,line in ipairs(self.chartLines)do line:Hide()end
            local low,high
            for _,d in ipairs(days)do low=math.min(low or d.price,d.price);high=math.max(high or d.price,d.price)end
            if #days>1 then for i=2,#days do
                local line=self.chartLines[i] or chart:CreateLine(nil,'OVERLAY');self.chartLines[i]=line
                local function y(v)return 200-(v-(low or 0))/math.max(1,(high or 1)-(low or 0))*175 end
                line:SetStartPoint('TOPLEFT',(i-2)/(#days-1)*770+12,-y(days[i-1].price))
                line:SetEndPoint('TOPLEFT',(i-1)/(#days-1)*770+12,-y(days[i].price));line:SetThickness(2);line:SetColorTexture(.35,.85,.74,1);line:Show()
            end end
            local lines={L('Recent daily points:','Recent daily points:')}
            for i=#days,math.max(1,#days-7),-1 do local d=days[i];lines[#lines+1]=date('%d.%m',d.day*86400)..' · '..U.money(d.price)..' · '..d.qty..L(' listed',' listed')end
            local buckets={};for _,s in ipairs(h and h.samples or {})do local hour=tonumber(date('%H',s.at));buckets[hour]=buckets[hour] or {};table.insert(buckets[hour],s.price)end
            local hours={};for hr,values in pairs(buckets)do if #values>=3 then hours[#hours+1]={hour=hr,price=U.median(values),n=#values}end end
            table.sort(hours,function(a,d)return a.price<d.price end)
            lines[#lines+1]='';lines[#lines+1]=L('Hours by median asks (not proven profit):','Hours by median asks (not proven profit):')
            for i=1,math.min(4,#hours)do local v=hours[i];lines[#lines+1]=v.hour..':00 · '..U.money(v.price)..' · n='..v.n end
            tableText:SetText(table.concat(lines,'\n'))
        end
    end
    do local b=body('tools')
        text(b,0,0,810,L('NPC ARBITRAGE · both directions','NPC ARBITRAGE · both directions'),'GameFontNormalLarge')
        val('vendorCost',b,0,42,180,L('NPC purchase unit price, gold','NPC purchase unit price, gold'),'')
        val('vendorQty',b,195,42,120,L('Quantity','Quantity'),'1')
        val('vendorAsk',b,330,42,180,L('AH ask per unit, gold','AH ask per unit, gold'),'')
        action('vendorCalc',b,530,62,200,L('Calculate NPC → AH','Calculate NPC → AH'),function()
            local cost=U.copper(self.fields.vendorCost:GetText()); local ask=U.copper(self.fields.vendorAsk:GetText());local qty=tonumber(self.fields.vendorQty:GetText())
            if not cost or cost<=0 then return end
            self.toolResult=F.Professions.calculate({{id=readKey().itemID or 1,qty=qty,price=cost}},nil,qty,ask,settings)
            local key=readKey();if saveable()and key.itemID then db.vendorPrices[key.itemID]={price=cost,at=c.api.clock(),source='manual'}end
            self:renderToolResult()
        end)
        action('vendorDirection',b,0,108,270,L('AH → NPC: open Trading','AH → NPC: open Trading'),function()c:stop();c.mode='vendor';self:show('trade')end)
        text(b,0,155,810,L('CRAFT / CONVERT · materials and opportunity cost','CRAFT / CONVERT · materials and opportunity cost'),'GameFontNormal')
        val('recipeName',b,0,185,190,L('Saved calculation name','Saved calculation name'),'')
        val('outputQty',b,205,185,100,L('Output quantity','Output quantity'),'1')
        val('outputPrice',b,320,185,180,L('Output unit price, gold','Output unit price, gold'),'')
        val('recipeID',b,515,185,120,'RecipeID','')
        val('materials',b,0,240,810,L('Materials: ID*quantity@price(g); @price optional','Materials: ID*quantity@price(g); @price optional'),'',true)
        action('craftCalc',b,0,380,180,L('Craft / convert','Craft / convert'),function()
            local m,err=F.Professions.parse(self.fields.materials:GetText(),false);if not m then c:notify(err);return end
            local bags=c.api.bagItems and c.api.bagItems() or {}
            for _,material in ipairs(m)do local n=0;for _,item in ipairs(bags)do if item.id==material.id then n=n+item.qty end end;material.owned=n end
            self.toolResult=F.Professions.calculate(m,function(id)return c:price(id)end,tonumber(self.fields.outputQty:GetText()),U.copper(self.fields.outputPrice:GetText()),settings)
            self.shopping=self.toolResult.shopping;self:renderToolResult()
        end)
        action('recipeSave',b,195,380,150,L('Save','Save'),function()
            if not saveable()then return end;local name=self.fields.recipeName:GetText();if name==''then return end
            db.recipes[name]={materials=self.fields.materials:GetText(),outputQty=self.fields.outputQty:GetText(),outputPrice=self.fields.outputPrice:GetText()};c:notify(L('Calculation saved.','Calculation saved.'))
        end)
        action('recipeLoad',b,360,380,150,L('Load','Load'),function()
            local r=(db.recipes or {})[self.fields.recipeName:GetText()]
            if r and r.materials then self.fields.materials:SetText(r.materials);self.fields.outputQty:SetText(r.outputQty or '1');self.fields.outputPrice:SetText(r.outputPrice or '')end
        end)
        action('recipeImport',b,525,380,220,L('Import recipe schematic','Import recipe schematic'),function()
            local id=tonumber(self.fields.recipeID:GetText())
            if not id or not C_TradeSkillUI or not C_TradeSkillUI.GetRecipeSchematic then c:notify('Recipe API unavailable');return end
            local ok,s=pcall(C_TradeSkillUI.GetRecipeSchematic,id,false);local materials={}
            if not ok or not s then c:notify('Recipe unavailable');return end
            for _,slot in ipairs(s.reagentSlotSchematics or {})do
                if slot.required and slot.reagents and #slot.reagents==1 and slot.reagents[1].itemID then materials[#materials+1]=slot.reagents[1].itemID..'*'..slot.quantityRequired
                else c:notify(L('This schematic requires manual input.','This schematic requires manual input.'));return end
            end
            self.fields.materials:SetText(table.concat(materials,', '));self.fields.outputQty:SetText(tostring(s.quantityMin or 1))
        end)
        text(b,0,430,810,L('DISENCHANT / RANDOM OUTPUT','DISENCHANT / RANDOM OUTPUT'),'GameFontNormal')
        val('yields',b,0,458,810,L('Expected output: ID*expected_quantity@price(g)','Expected output: ID*expected_quantity@price(g)'),'',true)
        val('deCost',b,0,598,180,L('Input cost, gold','Input cost, gold'),'')
        action('deCalc',b,200,618,210,L('Calculate disenchant','Calculate disenchant'),function()
            local y,err=F.Professions.parse(self.fields.yields:GetText(),true);if not y then c:notify(err);return end
            self.toolResult=F.Professions.disenchant(y,function(id)return c:price(id)end,U.copper(self.fields.deCost:GetText()),settings);self:renderToolResult()
        end)
        action('deSave',b,425,618,160,L('Save yields','Save yields'),function()
            if saveable()and self.fields.recipeName:GetText()~=''then db.disenchant[self.fields.recipeName:GetText()]={raw=self.fields.yields:GetText(),cost=self.fields.deCost:GetText()}end
        end)
        action('deLoad',b,600,618,160,L('Load yields','Load yields'),function()
            local y=db.disenchant[self.fields.recipeName:GetText()];if y and y.raw then self.fields.yields:SetText(y.raw);self.fields.deCost:SetText(y.cost or '')end
        end)
        self.toolText=text(b,0,670,810,'')
        val('materialIndex',b,0,855,120,L('Material row','Material row'),'1')
        action('materialSearch',b,140,875,250,L('Buy material: exact search','Buy material: exact search'),function()
            local m=self.shopping and self.shopping[tonumber(self.fields.materialIndex:GetText())]
            if m then self.fields.item:SetText(tostring(m.id));c:search({itemID=m.id});self:show('trade')end
        end)
        text(b,0,925,810,L('CROSS-MARKET CALCULATOR · transfer must actually be available','CROSS-MARKET CALCULATOR · transfer must actually be available'),'GameFontNormal')
        val('crossBuy',b,0,955,170,L('Buy / unit, gold','Buy / unit, gold'),'')
        val('crossSell',b,185,955,170,L('Sell / unit, gold','Sell / unit, gold'),'')
        val('crossTransfer',b,370,955,170,L('Transfer / unit, gold','Transfer / unit, gold'),'0')
        action('crossCalc',b,555,975,215,L('Calculate transfer','Calculate transfer'),function()
            local buy=U.copper(self.fields.crossBuy:GetText());local sell=U.copper(self.fields.crossSell:GetText());local transport=U.copper(self.fields.crossTransfer:GetText())
            if buy and buy>0 and sell and transport then self.toolResult=F.Professions.calculate({{id=1,qty=1,price=buy+transport}},nil,1,sell,settings);self:renderToolResult()end
        end)
        self.sections.tools.body:SetHeight(1060)
    end
    do local b=body('settings')
        text(b,0,0,810,L('SHARED TRADE RULES','SHARED TRADE RULES'),'GameFontNormalLarge')
        local fields={{'roi',L('Minimum ROI, %','Minimum ROI, %'),settings.minROI*100},
            {'profit',L('Minimum profit, gold','Minimum profit, gold'),U.gold(settings.minProfit)},
            {'wallet',L('Per trade, % wallet','Per trade, % wallet'),settings.maxWallet*100},
            {'itemShare',L('Per item, % capital','Per item, % capital'),settings.maxItem*100},
            {'cashFloor',L('Cash floor, % wallet','Cash floor, % wallet'),settings.cashFloor*100},
            {'maxQty',L('Maximum units','Maximum units'),settings.maxQty},
            {'fee',L('AH fee, % (assumption)','AH fee, % (assumption)'),settings.fee*100},
            {'minFee',L('Minimum fee, gold (assumption)','Minimum fee, gold (assumption)'),U.gold(settings.minFee)},
            {'reserve',L('Relisting reserve, %','Relisting reserve, %'),settings.reserve*100},
            {'budget',L('Budget cap, gold; 0=auto','Budget cap, gold; 0=auto'),U.gold(settings.budget)},
            {'absoluteCap',L('Absolute cap, gold; 0=none','Absolute cap, gold; 0=none'),U.gold(settings.absoluteCap)},
            {'maxShare',L('Max visible market share, %','Max visible market share, %'),settings.maxShare*100}}
        for i,v in ipairs(fields)do local col=(i-1)%3;local row=math.floor((i-1)/3);val(v[1],b,col*270,45+row*68,250,v[2],v[3])end
        val('buyFormula',b,0,330,810,L('Maximum purchase formula','Maximum purchase formula'),settings.buyFormula)
        val('sellFormula',b,0,395,810,L('Minimum sale formula','Minimum sale formula'),settings.sellFormula)
        action('settingsSave',b,0,460,210,L('Save rules','Save rules'),function()
            if not saveable()then return end
            local numbers={};for _,v in ipairs(fields)do local n=tonumber((self.fields[v[1]]:GetText():gsub(',','.')));if not U.finite(n)or n<0 then c:notify(L('Invalid number.','Invalid number.'));return end;numbers[v[1]]=n end
            if numbers.roi>1000 or numbers.wallet>100 or numbers.itemShare>100 or numbers.cashFloor>100 or numbers.fee+numbers.reserve>=100 or numbers.maxShare>100 or numbers.maxQty<1 or numbers.maxQty>100000 or numbers.maxQty%1~=0 then c:notify('Rule range');return end
            local buy=self.fields.buyFormula:GetText();local sell=self.fields.sellFormula:GetText();local sample={market=10000,recent=10000,vendorsell=500,avgbuy=500}
            if not F.Expr.eval(buy,sample)or not F.Expr.eval(sell,sample)then c:notify(L('Check formula.','Check formula.'));return end
            settings.minROI=numbers.roi/100;settings.minProfit=math.floor(numbers.profit*10000+.5);settings.maxWallet=numbers.wallet/100
            settings.maxItem=numbers.itemShare/100;settings.cashFloor=numbers.cashFloor/100;settings.maxQty=numbers.maxQty;settings.fee=numbers.fee/100
            settings.minFee=math.floor(numbers.minFee*10000+.5);settings.reserve=numbers.reserve/100;settings.maxShare=numbers.maxShare/100
            settings.budget=numbers.budget>0 and math.floor(numbers.budget*10000+.5)or nil
            settings.absoluteCap=numbers.absoluteCap>0 and math.floor(numbers.absoluteCap*10000+.5)or nil
            settings.buyFormula=buy;settings.sellFormula=sell;c:invalidate()
        end)
        val('house',b,230,440,230,L('House: Alliance/Horde/Neutral','House: Alliance/Horde/Neutral'),db.ui and db.ui.house or UnitFactionGroup('player'))
        action('houseSave',b,480,460,220,L('Change market','Change market'),function()
            if not saveable()then return end;local house=self.fields.house:GetText()
            if house~='Alliance'and house~='Horde'and house~='Neutral'then return end
            c:stop();db.ui.house=house;c:notify(L('Market changed. Verify the house and fee.','Market changed. Verify the house and fee.'))
        end)
        text(b,0,515,810,L('Formulas: min/max/first/avg/check/ifgt/ifgte/iflt/iflte/ifeq/round/roundup/rounddown; arithmetic, %, g/s/c.\nSources: market, recent, vendorsell, avgbuy, aux, tsm (only when available). Example: min(70% market, 50g). This is a limited language, not full TSM compatibility.\n\nRisk: median/MAD, lower price bound, age decay, depth and capital limits. No promise of future returns.',
            'Formulas: min/max/first/avg/check/ifgt/ifgte/iflt/iflte/ifeq/round/roundup/rounddown; arithmetic, %, g/s/c.\nSources: market, recent, vendorsell, avgbuy, aux, tsm (only when available). Example: min(70% market, 50g). This is a limited language, not full TSM compatibility.\n\nRisk: median/MAD, lower price bound, age decay, depth and capital limits. No promise of future returns.'))
        action('legacyPreview',b,0,735,230,L('Preview legacy ledger','Preview legacy ledger'),function()
            local lines={'LEGACY · '..#(db.legacyLedger or {})};for i,e in ipairs(db.legacyLedger or {})do if i<=100 then lines[#lines+1]=(e.kind or '?')..' '..tostring(e.id)..' ×'..tostring(e.qty)..' @ '..tostring(e.unit)end end
            self:exchange(table.concat(lines,'\n'))
        end)
        action('legacyAssign',b,250,735,300,L('Confirm legacy owner and market','Confirm legacy owner and market'),function()
            if not saveable()or db.legacyAssigned then return end
            if not self.legacyConfirm then self.legacyConfirm=true;c:notify(L('Review legacy data. Click again to assign ALL entries to this character and market.','Review legacy data. Click again to assign ALL entries to this character and market.'));return end
            for i,e in ipairs(db.legacyLedger or {})do local key=U.key(e.id)
                if key and U.finite(e.qty) and U.finite(e.unit) then
                    local ok=F.Ledger.append(db,{uid='legacy:'..i,owner=c.api.owner(),scope=c.api.scope(),key=key,kind=e.kind,
                        qty=e.qty,total=math.floor(e.qty*e.unit+.5),fee=e.fee or (e.kind=='sell' and F.Market.fee(math.floor(e.qty*e.unit+.5),settings.fee,settings.minFee) or 0),at=e.at or c.api.clock(),source='legacy-confirmed'})
                    if not ok then c:notify('Legacy migration stopped; review ledger capacity');return end
                else db.quarantine[#db.quarantine+1]=U.copy(e)end
            end
            db.legacyAssigned=true;c:invalidate()
        end)
        text(b,0,790,810,L('References: TSM, Auctionator, auxForever, Auctioneer, AuctionMin, AHSentinel, AHledger, Everloot. Paid data access is not included. External prices require matching scope and timestamps.','References: TSM, Auctionator, auxForever, Auctioneer, AuctionMin, AHSentinel, AHledger, Everloot. Paid data access is not included. External prices require matching scope and timestamps.'))
    end
    self.exchangeFrame=panel(host);self.exchangeFrame:SetPoint('CENTER');self.exchangeFrame:SetSize(850,450);self.exchangeFrame:SetFrameLevel(host:GetFrameLevel()+20);self.exchangeFrame:Hide()
    self.exchangeEdit=field(self.exchangeFrame,15,15,810,L('Select Ctrl+A → Ctrl+C. Text only.','Select Ctrl+A → Ctrl+C. Text only.'),'',true)
    self.exchangeEdit:SetHeight(335)
    button(self.exchangeFrame,650,400,160,L('Close','Close'),function()self.exchangeFrame:Hide()end)
    host:Hide();return self
end
function UI:exchange(value)self.exchangeEdit:SetText(value);self.exchangeFrame:Show();self.exchangeEdit:SetFocus();self.exchangeEdit:HighlightText()end
function UI:renderToolResult()
    local r=self.toolResult;if not r then return end
    if not r.complete then self.toolText:SetText(L('Missing input prices/output. Profit unknown.','Missing input prices/output. Profit unknown.'));return end
    local lines={L('Economic cost: ','Economic cost: ')..U.money(r.cost)..L(' · cash needed: ',' · cash needed: ')..U.money(r.cashCost),
        L('Net potential: ','Net potential: ')..U.money(r.profit)..string.format(' · ROI %.1f%%',(r.roi or 0)*100)}
    for i,m in ipairs(r.shopping or {})do if i<=5 then lines[#lines+1]=i..'. '..U.name(m.id)..' ×'..m.qty..' · '..U.money(m.cost)end end
    self.toolText:SetText(table.concat(lines,'\n'))
end
function UI:show(id)
    if not self.sections[id]then return end;self.section=id
    for k,v in pairs(self.sections)do if k==id then v.scroll:Show()else v.scroll:Hide()end end
    for k,b in pairs(self.nav)do b:SetEnabled(k~=id)end
    if F.Store.writable(self.c.db)then self.c.db.ui.section=id end
    self.frame:Show();self:refresh()
end
function UI:refresh()
    if self.refreshing then return end;self.refreshing=true
    local c=self.c
    self.header:SetText(c.api.scope()..'  ·  '..U.money(c.api.wallet())..L('  · reserved ','  · reserved ')..U.money(c:reserved()))
    local message=messages[c.message]or c.message
    if c.fullJob and not c.fullJob.waiting then message=L('Processing: ','Processing: ')..c.fullJob.index..' / '..c.fullJob.total end
    self.status:SetText(message)
    local fn=self.refreshers[self.section];if fn then fn()end
    self.refreshing=false
end
