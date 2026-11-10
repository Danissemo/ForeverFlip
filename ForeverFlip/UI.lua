local F = ForeverFlip
local U = F.Util
local UI = {}
F.UI = UI
-- Vertical space reserved at the top of the start page for the "how to earn" guide.
UI.guideHeight = 300
local L = F.Locale.text
local function reasons()
    return {
        history = L("Insufficient independent history", "Insufficient independent history"),
        volatility = L("High volatility", "High volatility"),
        crash = L("Market drop", "Market drop"),
        legacy = L("Reconcile legacy positions", "Reconcile legacy positions"),
        exit = L("No exit price", "No exit price"),
        formula = L("Formula source unavailable", "Formula source unavailable"),
        partial = L("Partial results", "Partial results"),
        ["budget/price"] = L("Price or budget limit", "Price or budget limit"),
        margin = L("Profit/ROI below rule", "Profit/ROI below rule"),
        ["advisor:probe"] = L(
            "Probe: sell current stock first",
            "Probe: sell current stock first"
        ),
        ["advisor:stock_limit"] = L(
            "Stock covers the sale horizon",
            "Stock covers the sale horizon"
        ),
        ["advisor:no_sales"] = L(
            "Stock without confirmed sales for 7+ days",
            "Stock without confirmed sales for 7+ days"
        ),
        ["advisor:loss_history"] = L(
            "Unfavorable profit history",
            "Unfavorable profit history"
        ),
        stale = L("Stale snapshot", "Stale snapshot"),
    }
end
local function messages()
    return {
        ready = L(
            "Open AH and scan or enter an item ID.",
            "Open AH and scan or enter an item ID."
        ),
        searching = L("Searching…", "Searching…"),
        plan_ready = L(
            "Plan ready. Request quote or buy one lot.",
            "Plan ready. Request quote or buy one lot."
        ),
        plan_review = L(
            "Review the reasons in the trade card.",
            "Review the reasons in the trade card."
        ),
        partial = L(
            "Full results required; request more.",
            "Full results required; request more."
        ),
        quote_wait = L(
            "Waiting for a quote; no purchase yet.",
            "Waiting for a quote; no purchase yet."
        ),
        quote_ready = L(
            "Quote ready; confirm with a separate click.",
            "Quote ready; confirm with a separate click."
        ),
        await_receipt = L(
            "Sent; awaiting purchase receipt.",
            "Sent; awaiting purchase receipt."
        ),
        purchase_recorded = L(
            "Purchase recorded. Collect your items.",
            "Purchase recorded. Collect your items."
        ),
        unknown = L(
            "Unknown result. Funds remain reserved; reconcile.",
            "Unknown result. Funds remain reserved; reconcile."
        ),
        price_changed = L(
            "Price changed; quote cancelled.",
            "Price changed; quote cancelled."
        ),
        readonly = L(
            "Unsupported data schema: read-only.",
            "Unsupported data schema: read-only."
        ),
        auction_closed = L(
            "Trading requires an open AH and no combat.",
            "Trading requires an open AH and no combat."
        ),
        buy_blocked = L(
            "Purchase blocked. Check plan freshness and conditions.",
            "Purchase blocked. Check plan freshness and conditions."
        ),
        resolve_pending = L(
            "Reconcile the pending trade in Portfolio first.",
            "Reconcile the pending trade in Portfolio first."
        ),
        throttled = L(
            "AH throttled; retry after a pause.",
            "AH throttled; retry after a pause."
        ),
        search_busy = L(
            "Wait for the current search or press Stop.",
            "Wait for the current search or press Stop."
        ),
        search_timeout = L(
            "Search timed out; retry manually.",
            "Search timed out; retry manually."
        ),
        item_loading = L(
            "Loading item data; search will continue automatically.",
            "Loading item data; search will continue automatically."
        ),
        item_unavailable = L(
            "Item data unavailable. Load its tooltip and retry.",
            "Item data unavailable. Load its tooltip and retry."
        ),
        review_wait = L(
            "Waiting for auction readiness for exact search.",
            "Waiting for auction readiness for exact search."
        ),
        replicate_cooldown = L(
            "Full snapshot: 15-minute interval. Exact search and Live remain available.",
            "Full snapshot: 15-minute interval. Exact search and Live remain available."
        ),
        replicate_wait = L(
            "Waiting for full replication…",
            "Waiting for full replication…"
        ),
        replicate_done = L(
            "Scan ready. Select a deal for exact verification.",
            "Scan ready. Select a deal for exact verification."
        ),
        replicate_timeout = L(
            "Replication timed out; another addon may have scanned.",
            "Replication timed out; another addon may have scanned."
        ),
        watching = L(
            "Watching for 10 minutes. All trades require clicks.",
            "Watching for 10 minutes. All trades require clicks."
        ),
        watch_finished = L("Watch session ended.", "Watch session ended."),
        stopped = L("Stopped.", "Stopped."),
        rescan = L(
            "Settings changed. Search again.",
            "Settings changed. Search again."
        ),
        post_values = L(
            "Check quantity and price; increment is 1 silver.",
            "Check quantity and price; increment is 1 silver."
        ),
        post_no_item = L(
            "Pick an item from your bags in the list above.",
            "Pick an item from your bags in the list above."
        ),
        post_search = L(
            "Press Suggest price first — the addon checks current prices.",
            "Press Suggest price first — the addon checks current prices."
        ),
        post_floor = L(
            "Price below sale floor or NPC net value.",
            "Price below sale floor or NPC net value."
        ),
        deposit_unknown = L(
            "Cannot verify deposit or funds.",
            "Cannot verify deposit or funds."
        ),
        post_confirm = L(
            "Click Post again to confirm.",
            "Click Post again to confirm."
        ),
        post_sent = L(
            "Posting sent. Check your auctions.",
            "Posting sent. Check your auctions."
        ),
        bid_reserved = L(
            "Bid sent; funds reserved until reconciliation.",
            "Bid sent; funds reserved until reconciliation."
        ),
        ledger_full = L(
            "Ledger blocked: limit or invalid receipt.",
            "Ledger blocked: limit or invalid receipt."
        ),
        reconciled = L("Reconciliation saved.", "Reconciliation saved."),
        quote_expired = L("Quote expired.", "Quote expired."),
        planner_done = L(
            "Plan complete. Select an item to verify.",
            "Plan complete. Select an item to verify."
        ),
        calculation_done = L("Calculation complete.", "Calculation complete."),
        calculation_incomplete = L(
            "Insufficient data for calculation.",
            "Insufficient data for calculation."
        ),
        mail_review = L(
            "Mail invoices ready for manual reconciliation.",
            "Mail invoices ready for manual reconciliation."
        ),
    }
end
local function text(parent, x, y, w, value, font)
    local v = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    F.Locale.font(v, font == "GameFontNormalLarge" and 16 or 12)
    F.NativeLayout.place(v, parent, x, y, w)
    v:SetJustifyH("LEFT")
    v:SetJustifyV("TOP")
    v:SetWordWrap(true)
    v:SetText(value or "")
    return v
end
local function button(parent, x, y, w, value, callback)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    F.NativeLayout.place(b, parent, x, y, w, 30)
    b:SetText(value)
    local label = b:GetFontString()
    if label then
        F.Locale.font(label, 11)
        label:SetWidth(w - 14)
        label:SetWordWrap(true)
        if label:GetStringHeight() > 26 then
            F.Locale.font(label, 10)
        end
        if label:GetStringHeight() > 26 then
            F.Locale.font(label, 9)
        end
    end
    b:SetScript("OnClick", callback)
    return b
end
local function field(parent, x, y, w, title, value, multi)
    local titleText = text(parent, x, y, w, title)
    F.Locale.font(titleText, 10)
    titleText:SetHeight(28)
    local e = CreateFrame("EditBox", nil, parent, multi and "BackdropTemplate" or "InputBoxTemplate")
    F.NativeLayout.place(e, parent, x + 4, y + 30, w - 8)
    e:SetHeight(multi and 110 or 24)
    e:SetAutoFocus(false)
    e:SetFontObject("GameFontHighlightSmall")
    F.Locale.font(e, 12)
    e:SetText(tostring(value or ""))
    if multi then
        e:SetMultiLine(true)
        e:SetTextInsets(6, 6, 6, 6)
        e:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" })
        e:SetBackdropColor(0.09, 0.12, 0.17, 1)
    end
    e:SetMaxLetters(multi and 120000 or 1024)
    e:SetScript("OnEscapePressed", function(s)
        s:ClearFocus()
    end)
    e:SetScript("OnEnterPressed", function(s)
        if not multi then
            s:ClearFocus()
        end
    end)
    return e
end
local function panel(parent)
    return CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
end
local function warningList(p)
    local out = {}
    for _, r in ipairs(p.reasons or {}) do
        out[#out + 1] = reasons()[r] or F.Locale.message(r)
    end
    return table.concat(out, "; ")
end
function UI.create(c)
    local self = setmetatable({
        c = c,
        sections = {},
        fields = {},
        actions = {},
        refreshers = {},
        section = "overview",
        dealPage = 1,
        sort = "profit",
        sortDescending = true,
        filterMode = "all",
        toolMode = "craft",
    }, { __index = UI })
    local db = c.db
    local settings = db.settings or F.Store.defaults
    local root = CreateFrame("Frame", nil, AuctionHouseFrame)
    self.frame = root
    root:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 4, -34)
    root:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -4, 28)
    root:SetMovable(false)
    root:SetResizable(false)
    root:SetClipsChildren(true)
    local host = F.NativeLayout.shell(self)
    root:SetScript("OnSizeChanged", function()
        self:layout()
    end)
    root:SetScript("OnShow", function()
        self:layout()
        if not self.showing then
            self:refresh()
        end
    end)
    root:SetScript("OnHide", function()
        c.dealPageVisible = false
        c:radarPause()
    end)
    local label = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    F.Locale.font(label, 12)
    label:SetPoint("TOPLEFT", host, "TOPLEFT", 68, -12)
    label:SetText(L("Search:", "Search:"))
    local item = CreateFrame("EditBox", nil, host, "InputBoxTemplate")
    item:SetPoint("TOPLEFT", host, "TOPLEFT", 140, -6)
    item:SetSize(205, 23)
    item:SetAutoFocus(false)
    item:SetFontObject("ChatFontNormal")
    F.Locale.font(item, 12)
    item:SetMaxLetters(1024)
    item:SetText("")
    self.fields.item = item
    item:SetScript("OnEscapePressed", function(e)
        e:ClearFocus()
    end)
    local function readKey()
        local key, err = F.Adapters.keyFromInput(item:GetText())
        if not key then
            c:notify(err)
        end
        return key or {}
    end
    self.readKey = readKey
    local function toolbar(name, x, w, title, fn)
        local b = CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
        b:SetPoint("TOPLEFT", host, "TOPLEFT", x, -5)
        b:SetSize(w, 24)
        b:SetText(title)
        F.Locale.font(b:GetFontString(), 11)
        b:SetScript("OnClick", fn)
        self.actions[name] = b
        return b
    end
    toolbar("search", 356, 80, L("Search", "Search"), function()
        local input = item:GetText()
        if U.fromKey(input) or tonumber(input) or input:find("item:", 1, true) then
            if c:searchInput(item:GetText()) then
                self:show("trade", "deal")
            end
        elseif
            item:GetText() ~= ""
            and not item:GetText():find("|H", 1, true)
            and not item:GetText():match("^item:")
        then
            c:notify(
                L(
                    "Filtered current snapshot. Select an item for exact search.",
                    "Filtered current snapshot. Select an item for exact search."
                )
            )
            self.fields.dealFilter:SetText(item:GetText())
            self.dealPage = 1
            self:show("deals")
        else
            c:notify("Item ID / exact key required")
        end
    end)
    item:SetScript("OnEnterPressed", function(e)
        e:ClearFocus()
        self.actions.search:Click()
    end)
    toolbar("fullScan", 441, 100, L("Full scan", "Full scan"), function()
        c:fullScan()
        self:show("deals")
    end)
    toolbar("live", 546, 88, L("Live", "Live"), function()
        if c.radar and c.radar.enabled and not c.radar.paused then
            c:radarPause(true)
        elseif c.radar and c.radar.enabled and c.radar.paused and c:radarStart() then
            self.liveOnly = true
        elseif c:radarAll() then
            self.liveOnly = true
            self.filterMode = "all"
            self.watchOnly = false
            self.groupFilter = nil
            self.fields.dealFilter:SetText("")
            self.dealPage = 1
        end
        self:show("deals")
    end)
    toolbar("quickPlan", 639, 73, L("Planner", "Planner"), function()
        c:radarPause()
        self.actions.easyBuild:Click()
    end)
    toolbar("stop", 717, 54, L("Stop", "Stop"), function()
        c:stop()
        c:radarPause(true)
    end)
    host:SetScript("OnReceiveDrag", function()
        if GetCursorInfo then
            local kind, id = GetCursorInfo()
            if kind == "item" then
                item:SetText(tostring(id))
                if ClearCursor then
                    ClearCursor()
                end
            end
        end
    end)
    local function body(id)
        return self.sections[id].body
    end
    local function saveable()
        if not F.Store.writable(db) then
            c:notify("readonly")
            return false
        end
        return true
    end
    local function action(name, parent, x, y, w, title, fn)
        local b = button(parent, x, y, w, title, fn)
        self.actions[name] = b
        return b
    end
    local function val(name, parent, x, y, w, title, value, multi)
        local e = field(parent, x, y, w, title, value, multi)
        self.fields[name] = e
        return e
    end
    local function currentAllocation()
        local a = self.allocation
        if
            a
            and (
                (a.scope and a.scope ~= c.api.scope())
                or (a.owner and a.owner ~= c.api.owner())
                or (a.ruleVersion and a.ruleVersion ~= c.ruleVersion)
            )
        then
            self.allocation, self.replay, self.advicePage = nil, nil, 1
            return nil
        end
        return a
    end
    local function routeAdvice(line)
        if not line then
            return
        end
        if not currentAllocation() then
            c:notify("rescan")
            return
        end
        c:stop("manual")
        c.overrides = {
            maxQty = math.min(line.qty, c.overrides and c.overrides.maxQty or math.huge),
            budget = math.min(line.cost, c.overrides and c.overrides.budget or math.huge),
        }
        c.mode = line.mode
        self.fields.item:SetText(U.key(line.key))
        self.fields.tradeQty:SetText(tostring(c.overrides.maxQty))
        self.fields.tradeBudget:SetText(U.gold(c.overrides.budget))
        c:openDeal(line)
        self:show("trade", "deal")
    end
    local function buildAdvice(profile)
        if #c.candidates > 4 or c.job or c.fullJob then
            if
                F.Planner.start(c, profile, nil, function(result)
                    self.allocation = result
                    self.advicePage = 1
                    if F.Store.writable(db) then
                        db.ui.advisorProfile = profile
                    end
                    self:refresh()
                end)
            then
                self:show("workbench")
            end
            return
        end
        c.overrides = nil
        local result = c:recommend(profile)
        if result.error then
            c:notify(result.error == "busy" and "search_busy" or "buy_blocked")
            self:refresh()
            return
        end
        self.allocation = result
        self.advicePage = 1
        if F.Store.writable(db) then
            db.ui.advisorProfile = profile
        end
        self:show("workbench")
    end
    do
        local hostBody = body("workbench")
        hostBody:SetSize(840, 1600)
        text(hostBody, 0, 0, 810, L("PURCHASE ASSISTANT", "PURCHASE ASSISTANT"), "GameFontNormalLarge")
        action(
            "easyBuild",
            hostBody,
            0,
            35,
            225,
            L("Suggest purchases", "Suggest purchases"),
            function()
                buildAdvice("balanced")
            end
        )
        action(
            "easySafe",
            hostBody,
            240,
            35,
            225,
            L("Conservative plan", "Conservative plan"),
            function()
                buildAdvice("safe")
            end
        )
        self.advancedPlan = CreateFrame("Frame", nil, hostBody)
        self.advancedPlan:SetSize(820, 110)
        F.NativeLayout.container(self.advancedPlan, hostBody, 20)
        self.advancedPlan:SetPoint("TOPLEFT", 0, -85)
        self.advancedPlan:Hide()
        local advanced = self.advancedPlan
        local content = CreateFrame("Frame", nil, hostBody)
        content:SetSize(820, 1350)
        self.workbenchContent = content
        F.NativeLayout.container(content, hostBody, 20)
        action(
            "adviceAdvanced",
            hostBody,
            480,
            35,
            280,
            L("Advanced controls", "Advanced controls"),
            function()
                if advanced:IsShown() then
                    advanced:Hide()
                else
                    advanced:Show()
                end
                self:refresh()
            end
        )
        val("planBudget", advanced, 0, 0, 155, L("Budget, gold", "Budget, gold"), "100")
        val("planRisk", advanced, 175, 0, 155, L("Stress loss cap, gold", "Stress loss cap, gold"), "10")
        val("planDrop", advanced, 350, 0, 140, L("Price drop, %", "Price drop, %"), "20")
        val("planIndex", advanced, 510, 0, 90, L("Row", "Row"), "1")
        action("planBuild", advanced, 0, 60, 230, L("Manual allocation", "Manual allocation"), function()
            local budget = U.copper(self.fields.planBudget:GetText())
            local risk = U.copper(self.fields.planRisk:GetText())
            local drop = tonumber(self.fields.planDrop:GetText())
            if not budget or not risk or not drop or drop < 0 or drop > 95 then
                return
            end
            if #c.candidates > 4 or c.job or c.fullJob then
                if
                    F.Planner.start(
                        c,
                        "manual",
                        { budget = budget, riskCap = risk, drop = drop / 100 },
                        function(result)
                            self.allocation = result
                            self.advicePage = 1
                            self:refresh()
                        end
                    )
                then
                    self:show("workbench")
                end
                return
            end
            if c.job or c.fullJob or c.active then
                c:notify("search_busy")
                return
            end
            c.advisorProfile = nil
            c.overrides = nil
            c:invalidate()
            self.allocation = c:allocate({ budget = budget, riskCap = risk, drop = drop / 100 })
            self.advicePage = 1
            c:notify("planner_done")
            self:refresh()
        end)
        action(
            "planRoute",
            advanced,
            250,
            60,
            290,
            L("Row → fresh exact search", "Row → fresh exact search"),
            function()
                routeAdvice(self.allocation and self.allocation.lines[tonumber(self.fields.planIndex:GetText()) or 0])
            end
        )
        local b = content
        local report = text(b, 0, 0, 810, "", "GameFontNormal")
        self.adviceReport = report
        local rowButtons = {}
        F.ItemDisplay.headers(b, 0, 120)
        for i = 1, 8 do
            local index = i
            rowButtons[i] = F.ItemDisplay.row(b, 0, 140 + (i - 1) * 28, 795, function()
                routeAdvice(self.allocation and self.allocation.lines[((self.advicePage or 1) - 1) * 8 + index])
            end)
            rowButtons[i]:SetSize(795, 26)
            self.actions["adviceRow" .. i] = rowButtons[i]
        end
        action("advicePrevious", b, 0, 368, 170, L("← Previous", "← Previous"), function()
            self.advicePage = math.max(1, (self.advicePage or 1) - 1)
            self:refresh()
        end)
        action("adviceNext", b, 185, 368, 170, L("Next →", "Next →"), function()
            local pages = math.max(1, math.ceil(#(self.allocation and self.allocation.lines or {}) / 8))
            self.advicePage = math.min(pages, (self.advicePage or 1) + 1)
            self:refresh()
        end)
        local performance = text(b, 0, 555, 810, "", "GameFontNormal")
        text(
            b,
            0,
            840,
            810,
            L(
                "REPLAY: HYPOTHETICAL PRICES, NOT FILLS",
                "REPLAY: HYPOTHETICAL PRICES, NOT FILLS"
            ),
            "GameFontNormalLarge"
        )
        val("replayHold", b, 0, 875, 170, L("Holding period, days", "Holding period, days"), "1")
        val("replayHaircut", b, 190, 875, 170, L("Exit haircut, %", "Exit haircut, %"), "5")
        local replayText = text(b, 0, 980, 810, "", "GameFontNormal")
        action(
            "replay",
            b,
            0,
            935,
            350,
            L("Replay item from header", "Replay item from header"),
            function()
                local key = readKey()
                if not key then
                    return
                end
                local hold = tonumber(self.fields.replayHold:GetText())
                local haircut = tonumber(self.fields.replayHaircut:GetText())
                if not hold or hold < 1 or hold > 30 or not haircut or haircut < 0 or haircut > 95 then
                    return
                end
                local rule = c:rule(key)
                self.replay = F.Workbench.replay(F.Market.evidence(c:history(key)), {
                    now = c.api.clock(),
                    capital = U.copper(self.fields.planBudget:GetText()) or 0,
                    hold = hold * 86400,
                    haircut = haircut / 100,
                    fee = rule.fee,
                    minFee = rule.minFee,
                    reserve = rule.reserve,
                    minROI = rule.minROI,
                })
                self:refresh()
            end
        )
        self.refreshers.workbench = function()
            content:ClearAllPoints()
            content:SetPoint("TOPLEFT", 0, advanced:IsShown() and -215 or -85)
            local a = currentAllocation()
            local lines = {
                L(
                    "1. Full scan → 2. Suggest purchases → 3. Click an item to verify.",
                    "1. Full scan → 2. Suggest purchases → 3. Click an item to verify."
                ),
            }
            if a then
                local profile = a.profile == "safe" and L("Conservative", "Conservative")
                    or a.profile == "balanced" and L("Balanced", "Balanced")
                    or L("Manual", "Manual")
                lines[#lines + 1] = profile
                    .. L(" · cost / potential / stress: ", " · cost / potential / stress: ")
                    .. U.money(a.cost)
                    .. " / "
                    .. U.money(a.profit)
                    .. " / "
                    .. U.money(a.stressed)
                lines[#lines + 1] = L("Unused: ", "Unused: ")
                    .. U.money(a.budget - a.cost)
                    .. L(
                        " · approximate plan; page ",
                        " · approximate plan; page "
                    )
                    .. (self.advicePage or 1)
                    .. " / "
                    .. math.max(1, math.ceil(#a.lines / 8))
                if #a.lines == 0 then
                    lines[#lines + 1] = L(
                        "No qualifying buys: check scan age, history, limits and holdings. New items use a 1-unit probe.",
                        "No qualifying buys: check scan age, history, limits and holdings. New items use a 1-unit probe."
                    )
                end
                if a.truncated then
                    lines[#lines + 1] = L(
                        "Best 60 candidates checked; list truncated.",
                        "Best 60 candidates checked; list truncated."
                    )
                end
            else
                lines[#lines + 1] = L(
                    "Start with a full scan. No formula or budget entry required.",
                    "Start with a full scan. No formula or budget entry required."
                )
            end
            lines[#lines + 1] = L(
                "Estimates do not guarantee sales. Spending requires confirmation.",
                "Estimates do not guarantee sales. Spending requires confirmation."
            )
            report:SetText(table.concat(lines, "\n"))
            local page = self.advicePage or 1
            for i, btn in ipairs(rowButtons) do
                local row = a and a.lines[(page - 1) * 8 + i]
                if row then
                    local status = row.mode == "vendor" and "NPC"
                        or row.advice and (row.advice.rateKnown and L(
                            "own sales measured",
                            "own sales measured"
                        ) or L("probe", "probe"))
                        or "AH"
                    local horizon = row.daysToExit
                            and string.format(L(" · ~%.1f days", " · ~%.1f days"), row.daysToExit)
                        or ""
                    btn:SetItem(row, status .. horizon)
                    btn:Show()
                    btn:SetEnabled(true)
                else
                    btn:Hide()
                    btn:SetEnabled(false)
                end
            end
            self.actions.advicePrevious:SetEnabled(page > 1)
            self.actions.adviceNext:SetEnabled(a and page * 8 < #a.lines or false)
            local summary = c:summary()
            local stats = c:performance()
            local t = {
                L(
                    "ACTUAL RESULTS: KNOWN COST",
                    "ACTUAL RESULTS: KNOWN COST"
                ),
                L("Wins / losses: ", "Wins / losses: ")
                    .. stats.wins
                    .. " / "
                    .. stats.losses,
            }
            for i = 1, math.min(5, #stats.ranked) do
                local r = stats.ranked[i]
                local key = U.fromKey(r.key)
                local own = F.Advisor.trades(
                    summary.salesByKey[r.key] or {},
                    r.key,
                    c.api.clock(),
                    summary.activity[r.key] and summary.activity[r.key].since
                )
                t[#t + 1] = (key and U.name(key.itemID) or r.key)
                    .. ": "
                    .. U.money(r.profit)
                    .. "; ROI "
                    .. (r.roi and string.format("%.1f%%", r.roi * 100) or "?")
                    .. (
                        own.winLower
                            and string.format(
                                L(
                                    "; lower profitable-close fraction %.0f%%",
                                    "; lower profitable-close fraction %.0f%%"
                                ),
                                own.winLower * 100
                            )
                        or ""
                    )
            end
            performance:SetText(table.concat(t, "\n"))
            if self.replay then
                local r = self.replay
                local t = {
                    L(
                        "Exit uses a future ask with haircut; demand and fills are unknown.",
                        "Exit uses a future ask with haircut; demand and fills are unknown."
                    ),
                }
                for _, name in ipairs({ "robust", "baseline" }) do
                    local v = r[name]
                    t[#t + 1] = (
                        name == "robust" and "ForeverFlip 5.0"
                        or L("Fixed 30% discount (not TSM)", "Fixed 30% discount (not TSM)")
                    )
                        .. ": "
                        .. U.money(v.pnl)
                        .. L("; exits ", "; exits ")
                        .. v.closed
                        .. L("; open cost ", "; open cost ")
                        .. U.money(v.openCost)
                end
                t[#t + 1] = L(
                    "Replay compares the base pricing model, without the new advisor or own sales rate.",
                    "Replay compares the base pricing model, without the new advisor or own sales rate."
                )
                if r.trainingInsufficient then
                    t[#t + 1] =
                        L("Insufficient independent history.", "Insufficient independent history.")
                end
                replayText:SetText(table.concat(t, "\n"))
            end
        end
    end
    -- Overview: realized money is kept apart from portfolio valuation.
    do
        local b = body("overview")
        local G = UI.guideHeight
        text(
            b,
            0,
            0,
            820,
            L("HOW TO EARN GOLD — 3 STEPS", "HOW TO EARN GOLD — 3 STEPS"),
            "GameFontNormalLarge"
        )
        local steps = {
            {
                "guideNPC",
                L("1. Sell to vendors", "1. Sell to vendors"),
                L(
                    "No price risk. The addon finds lots cheaper than a vendor pays for them. Buy (every purchase is your click and confirmation), collect from mail and sell to any vendor. It spends at most 25% of your money per day (at least 1g).",
                    "No price risk. The addon finds lots cheaper than a vendor pays for them. Buy (every purchase is your click and confirmation), collect from mail and sell to any vendor. It spends at most 25% of your money per day (at least 1g)."
                ),
                function()
                    self:startNPC()
                    self:show("deals")
                end,
            },
            {
                "guideScan",
                L("2. Find cheap lots", "2. Find cheap lots"),
                L(
                    "A full auction scan (at most every 15 minutes) lists items below their usual price. Profit is shown after the auction fee. Click a row → Trading → check the price → Quote / buy one lot → Confirm purchase.",
                    "A full auction scan (at most every 15 minutes) lists items below their usual price. Profit is shown after the auction fee. Click a row → Trading → check the price → Quote / buy one lot → Confirm purchase."
                ),
                function()
                    c:fullScan()
                    self:show("deals")
                end,
            },
            {
                "guideSell",
                L("3. Sell and see profit", "3. Sell and see profit"),
                L(
                    "Post what you bought from Portfolio at the suggested price. The addon remembers what you paid and shows real profit, not an estimate.",
                    "Post what you bought from Portfolio at the suggested price. The addon remembers what you paid and shows real profit, not an estimate."
                ),
                function()
                    self:show("portfolio")
                end,
            },
        }
        for i, step in ipairs(steps) do
            local y = 35 + (i - 1) * 72
            action(step[1], b, 0, y, 230, step[2], step[4])
            text(b, 245, y, 565, step[3])
        end
        text(
            b,
            0,
            G - 50,
            810,
            L(
                "Tips: start with cheap items and small batches; avoid things that rarely sell. The addon never buys on its own — you confirm every action. Profit is not guaranteed.",
                "Tips: start with cheap items and small batches; avoid things that rarely sell. The addon never buys on its own — you confirm every action. Profit is not guaranteed."
            )
        )
        text(b, 0, G, 820, L("YOUR TRADING DAY", "YOUR TRADING DAY"), "GameFontNormalLarge")
        action(
            "overviewAdvice",
            b,
            0,
            G + 35,
            250,
            L("Suggest purchases", "Suggest purchases"),
            function()
                buildAdvice(db.ui.advisorProfile or "balanced")
            end
        )
        text(
            b,
            270,
            G + 40,
            535,
            L(
                "Full scan → plan → verify item → confirm",
                "Full scan → plan → verify item → confirm"
            )
        )
        local overview = text(b, 0, G + 85, 810, "", "GameFontNormal")
        self.overviewText = overview
        self.refreshers.overview = function()
            local r = c:summary()
            local now = c.api.clock()
            local day = math.floor(now / 86400)
            local today, week, month = 0, 0, 0
            for _, s in ipairs(r.salesHistory) do
                local age = now - (s.at or 0)
                if math.floor((s.at or 0) / 86400) == day then
                    today = today + s.profit
                end
                if age >= 0 and age <= 7 * 86400 then
                    week = week + s.profit
                end
                if age >= 0 and age <= 30 * 86400 then
                    month = month + s.profit
                end
            end
            overview:SetText(
                L("Wallet: ", "Wallet: ")
                    .. U.money(c.api.wallet())
                    .. "\n"
                    .. L("Pending reservations: ", "Pending reservations: ")
                    .. U.money(c:reserved())
                    .. "\n"
                    .. L("Inventory cost: ", "Inventory cost: ")
                    .. U.money(r.stock)
                    .. "\n\n"
                    .. L(
                        "Realized sales P/L today / 7 / 30 days:\n",
                        "Realized sales P/L today / 7 / 30 days:\n"
                    )
                    .. U.money(today)
                    .. " / "
                    .. U.money(week)
                    .. " / "
                    .. U.money(month)
                    .. "\n"
                    .. L(
                        "Total realized P/L including expenses: ",
                        "Total realized P/L including expenses: "
                    )
                    .. U.money(r.realized)
                    .. "\n"
                    .. L(
                        "Sold with unknown cost: ",
                        "Sold with unknown cost: "
                    )
                    .. r.unknown
            )
        end
        action("toDeals", b, 0, G + 410, 170, L("Find deals", "Find deals"), function()
            self:show("deals")
        end)
        action("toPortfolio", b, 185, G + 410, 170, L("Reconcile", "Reconcile"), function()
            self:show("portfolio")
        end)
        self.overviewNote = text(
            b,
            0,
            G + 465,
            800,
            L(
                "Current character and selected market only. Asking prices and valuations are not earned gold.",
                "Current character and selected market only. Asking prices and valuations are not earned gold."
            )
        )
    end
    F.NativeShopping.create(self, warningList)
    do
        local b = body("trade")
        action("tradeMode", b, 0, 0, 200, L("Strategy: FLIP / NPC", "Strategy: FLIP / NPC"), function(btn)
            c:stop()
            c.mode = c.mode == "vendor" and "flip" or "vendor"
            btn:SetText(c.mode == "vendor" and "NPC" or L("Resale", "Resale"))
            self:refresh()
        end)
        action("more", b, 215, 0, 170, L("More results", "More results"), function()
            c:more()
        end)
        action("watchAdd", b, 400, 0, 170, L("Add to watchlist", "Add to watchlist"), function()
            if not saveable() then
                return
            end
            local key = readKey()
            local value = (
                (key.itemSuffix or 0) ~= 0
                or (key.itemLevel or 0) ~= 0
                or (key.battlePetSpeciesID or 0) ~= 0
            )
                    and U.key(key)
                or key.itemID
            local ok, err = F.Store.watch(db, value)
            c:notify(ok and L("Item added.", "Item added.") or err)
        end)
        self.tradeItem = F.ItemDisplay.row(b, 0, 44, 810, function() end)
        local tradeContent = CreateFrame("Frame", nil, b)
        tradeContent:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -40)
        tradeContent:SetSize(840, 1140)
        F.NativeLayout.container(tradeContent, b, 0)
        b:SetHeight(1180)
        b = tradeContent
        self.tradeText = text(b, 0, 45, 805, "", "GameFontNormal")
        val("tradeQty", b, 0, 266, 140, L("Quantity cap", "Quantity cap"), settings.maxQty)
        val(
            "tradeBudget",
            b,
            155,
            266,
            160,
            L("Maximum total, gold", "Maximum total, gold"),
            U.gold(settings.budget or 1000000)
        )
        action(
            "tradeApply",
            b,
            330,
            286,
            220,
            L("Apply → search again", "Apply → search again"),
            function()
                local qty = tonumber(self.fields.tradeQty:GetText())
                local budget = U.copper(self.fields.tradeBudget:GetText())
                if not qty or qty < 1 or qty > 100000 or qty % 1 ~= 0 or not budget or budget <= 0 then
                    return
                end
                c.overrides = { maxQty = qty, budget = budget }
                c:invalidate()
            end
        )
        self.actions.buy = action(
            "buy",
            b,
            0,
            320,
            245,
            L("Quote / buy one lot", "Quote / buy one lot"),
            function()
                c:requestBuy()
            end
        )
        self.actions.confirm = action(
            "confirm",
            b,
            260,
            320,
            245,
            L("Confirm purchase", "Confirm purchase"),
            function()
                c:confirmBuy()
            end
        )
        action("cancelQuote", b, 520, 320, 170, L("Cancel quote", "Cancel quote"), function()
            c:cancelQuote()
            self:refresh()
        end)
        text(
            b,
            0,
            366,
            810,
            L(
                "SELL FROM BAGS · search the exact variant first",
                "SELL FROM BAGS · search the exact variant first"
            ),
            "GameFontNormal"
        )
        val("bagIndex", b, 0, 394, 110, L("Bag row", "Bag row"), "1")
        val("postQty", b, 125, 394, 110, L("Quantity", "Quantity"), "1")
        val("postPrice", b, 250, 394, 170, L("Unit price, gold", "Unit price, gold"), "")
        val("duration", b, 435, 394, 120, L("Duration: 1/2/3", "Duration: 1/2/3"), "2")
        action("post", b, 570, 414, 210, L("Post / confirm", "Post / confirm"), function()
            local i = tonumber(self.fields.bagIndex:GetText())
            local bag = self.bags and self.bags[i]
            c:post(
                bag,
                tonumber(self.fields.postQty:GetText()),
                U.copper(self.fields.postPrice:GetText()),
                tonumber(self.fields.duration:GetText())
            )
        end)
        action("suggestPrice", b, 250, 436, 170, L("Suggest price", "Suggest price"), function()
            local price, why = F.Market.salePrice(c.plan, tonumber(self.fields.cardQty:GetText()) or 1)
            if not price then
                c:notify(
                    L(
                        "Search for this item first.",
                        "Search for this item first."
                    )
                )
                return
            end
            self.fields.postPrice:SetText(U.gold(price))
            c:notify(
                why == "cost"
                        and L(
                            "Price kept above your purchase cost after the fee.",
                            "Price kept above your purchase cost after the fee."
                        )
                    or why == "undercut" and L(
                        "1 silver below the cheapest listing.",
                        "1 silver below the cheapest listing."
                    )
                    or L("Usual market price.", "Usual market price.")
            )
        end)
        self.bagText = text(b, 0, 462, 810, "")
        text(
            b,
            0,
            630,
            810,
            L(
                "BIDS · select row; funds reserved until reconciliation",
                "BIDS · select row; funds reserved until reconciliation"
            ),
            "GameFontNormal"
        )
        val("bidIndex", b, 0, 662, 120, L("Bid row", "Bid row"), "1")
        action("bid", b, 140, 682, 220, L("Place one bid", "Place one bid"), function()
            c:bid(tonumber(self.fields.bidIndex:GetText()))
        end)
        self.bidText = text(b, 0, 728, 810, "")
        self.tradeAdvice = text(b, 0, 825, 810, "", "GameFontNormal")
        -- Simple mode: a deal card styled like the native auction buy frame — item header,
        -- striped step table and a separate sell panel.
        local tradeBody = self.sections.trade.body
        local function inset(y, height)
            local f = CreateFrame("Frame", nil, tradeBody, "InsetFrameTemplate")
            f:SetPoint("TOPLEFT", tradeBody, "TOPLEFT", 0, -y)
            f:SetSize(840, height)
            F.NativeLayout.container(f, tradeBody, 4)
            local art = f:CreateTexture(nil, "BACKGROUND", nil, 1)
            art:SetAtlas("auctionhouse-background-index")
            art:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
            art:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
            return f
        end
        local card = inset(36, 252)
        self.tradeCard, self.tradeContent = card, tradeContent
        local header = card:CreateTexture(nil, "BORDER")
        header:SetAtlas("auctionhouse-itemheaderframe")
        header:SetPoint("TOPLEFT", card, "TOPLEFT", 6, -6)
        header:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, -6)
        header:SetHeight(58)
        self.cardIcon = card:CreateTexture(nil, "ARTWORK")
        self.cardIcon:SetSize(40, 40)
        self.cardIcon:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -15)
        self.cardIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        self.cardName = text(card, 66, 14, 720, "", "GameFontNormalLarge")
        self.cardVerdict = text(card, 66, 38, 720, "", "GameFontHighlight")
        self.cardFreshness = text(card, 10, 58, 800, "", "GameFontHighlightSmall")
        self.cardTooltip = CreateFrame("Button", nil, card)
        self.cardTooltip:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -10)
        self.cardTooltip:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -10)
        self.cardTooltip:SetHeight(48)
        self.cardTooltip:Show()
        self.cardTooltip:SetScript("OnEnter", function(frame)
            F.ItemDisplay.tooltip(frame, self.cardMetadata)
        end)
        self.cardTooltip:SetScript("OnLeave", function()
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)
        self.cardTooltip:SetScript("OnHide", function()
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)
        self.cardRows = {}
        for i = 1, 4 do
            local row = CreateFrame("Frame", nil, card)
            F.NativeLayout.place(row, card, 8, 70 + (i - 1) * 24, 815, 23)
            local stripe = row:CreateTexture(nil, "BACKGROUND", nil, 2)
            stripe:SetAtlas("auctionhouse-rowstripe-1")
            stripe:SetAllPoints()
            stripe:SetAlpha(i % 2 == 0 and 0.8 or 0.3)
            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.label:SetPoint("LEFT", row, "LEFT", 10, 0)
            row.label:SetJustifyH("LEFT")
            F.Locale.font(row.label, 12)
            row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.value:SetPoint("RIGHT", row, "RIGHT", -10, 0)
            row.value:SetJustifyH("RIGHT")
            F.Locale.font(row.value, 12)
            self.cardRows[i] = row
        end
        self.cardSteps = text(card, 10, 168, 800, "", "GameFontHighlightSmall")
        action("cardBuy", card, 8, 210, 190, L("1. Buy", "1. Buy"), function()
            c:requestBuy()
        end)
        action(
            "cardConfirm",
            card,
            206,
            210,
            210,
            L("2. Confirm purchase", "2. Confirm purchase"),
            function()
                c:confirmBuy()
            end
        )
        action(
            "cardRecheck",
            card,
            424,
            210,
            190,
            L("Check price again", "Check price again"),
            function()
                if c.selection then
                    c:openDeal(c.selection)
                end
                self:refresh()
            end
        )
        action("cardCancel", card, 622, 210, 150, L("Cancel", "Cancel"), function()
            c:cancelQuote()
            self:refresh()
        end)
        local sell = inset(294, 300)
        self.tradeSell = sell
        self:createSellPanel(sell)
        self.refreshers.trade = function()
            self.actions.tradeMode:SetText(
                c.mode == "material" and L("Reagents", "Reagents")
                    or c.mode == "vendor" and "NPC"
                    or L("Resale", "Resale")
            )
            local p = c.plan
            if p and (p.origin == "radar" or (c.selection and U.key(p.key) ~= U.key(c.selection.key))) then
                p = nil
            end
            self.tradeItem:SetItem(
                p or c.selection,
                p and L("Exact result", "Exact result")
                    or L("Waiting for exact verification", "Waiting for exact verification")
            )
            local advice = p and p.advice
            local details = {}
            if advice then
                details[#details + 1] = L("WHY THIS SIZE AND PRICE", "WHY THIS SIZE AND PRICE")
                details[#details + 1] = L("Advisor cap: ", "Advisor cap: ")
                    .. advice.maxQty
                    .. L(" units / ", " units / ")
                    .. U.money(advice.maxBudget)
                if advice.priceCap then
                    details[#details + 1] = "EWMA / Q25 / "
                        .. L("price cap: ", "price cap: ")
                        .. U.money(advice.prices.ewma)
                        .. " / "
                        .. U.money(advice.prices.q25)
                        .. " / "
                        .. U.money(advice.priceCap)
                end
                if advice.rateKnown then
                    details[#details + 1] = string.format(
                        L(
                            "Conservative own rate: %.2f units/day; %d-day stock horizon.",
                            "Conservative own rate: %.2f units/day; %d-day stock horizon."
                        ),
                        advice.trades.rateLower,
                        advice.horizon
                    )
                else
                    details[#details + 1] = L(
                        "Rate unknown: probe up to 1 unit less current holdings.",
                        "Rate unknown: probe up to 1 unit less current holdings."
                    )
                end
                if advice.trades.kelly then
                    details[#details + 1] = string.format(
                        L(
                            "Quarter Kelly: %.2f%% of wallet, further limited by profile.",
                            "Quarter Kelly: %.2f%% of wallet, further limited by profile."
                        ),
                        advice.trades.kelly * 25
                    )
                end
                details[#details + 1] = L(
                    "Your recorded sale rate is not the whole market's sale rate.",
                    "Your recorded sale rate is not the whole market's sale rate."
                )
            end
            self.tradeAdvice:SetText(table.concat(details, "\n"))
            local lines = {}
            if p then
                lines = {
                    U.name(p.key.itemID) .. " · " .. U.key(p.key) .. " · " .. p.kind .. " · " .. (p.complete and L(
                        "complete",
                        "complete"
                    ) or L("PARTIAL", "PARTIAL")),
                    L("Buy: ", "Buy: ") .. p.qty .. " · " .. U.money(p.cost) .. L(
                        " · budget: ",
                        " · budget: "
                    ) .. U.money(p.budget),
                    L("Average / maximum: ", "Average / maximum: ")
                        .. U.money(p.avg)
                        .. " / "
                        .. U.money(p.maxUnit),
                    L("Exit scenario / unit: ", "Exit scenario / unit: ") .. U.money(p.target) .. L(
                        " · break-even: ",
                        " · break-even: "
                    ) .. U.money(p.breakEven),
                    L("Net potential: ", "Net potential: ")
                        .. U.money(p.profit)
                        .. string.format(" · ROI %.1f%%", p.roi * 100),
                    L("Evidence confidence: ", "Evidence confidence: ")
                        .. string.format("%.0f%%", 100 * (p.confidence or 0))
                        .. L(" · NPC liquidation: ", " · NPC liquidation: ")
                        .. (p.liquidation and U.money(p.liquidation) or "?"),
                    L("Restrictions: ", "Restrictions: ")
                        .. (
                            warningList(p) ~= "" and warningList(p)
                            or L(
                                "Checks passed; sale not guaranteed",
                                "Checks passed; sale not guaranteed"
                            )
                        ),
                }
                if p.material then
                    lines[4] = L(
                        "Reagent procurement: price and quantity caps; no resale forecast.",
                        "Reagent procurement: price and quantity caps; no resale forecast."
                    )
                    lines[5] = L(
                        "Price capped by the calculation. Purchase requires separate confirmation.",
                        "Price capped by the calculation. Purchase requires separate confirmation."
                    )
                end
                local depth = {}
                for i = 1, math.min(4, #p.rows) do
                    local r = p.rows[i]
                    depth[#depth + 1] = r.qty .. " × " .. U.money(r.unit)
                end
                lines[#lines + 1] = L("Depth: ", "Depth: ") .. table.concat(depth, " | ")
                lines[#lines + 1] = L("Fee / reserve: ", "Fee / reserve: ")
                    .. U.money(p.fee)
                    .. " / "
                    .. U.money(p.reserve)
                    .. L(" · age: ", " · age: ")
                    .. math.max(0, c.api.clock() - p.at)
                    .. "s"
            else
                lines = {
                    L(
                        "Enter an ID, link or exact key and press Exact search.\nMissing history means unknown demand.\nFor NPC arbitrage choose NPC and search again.",
                        "Enter an ID, link or exact key and press Exact search.\nMissing history means unknown demand.\nFor NPC arbitrage choose NPC and search again."
                    ),
                }
            end
            self.tradeText:SetText(table.concat(lines, "\n"))
            self.actions.buy:SetEnabled(
                c.api.isOpen() and p and c:fresh() and p.canBuy and not c.active and c:reserved() == 0 or false
            )
            self.actions.confirm:SetEnabled(
                c.api.isOpen() and p and c:fresh() and c.active and c.active.status == "quoted" or false
            )
            self.actions.more:SetEnabled(c.api.isOpen() and p and not p.complete and c.job or false)
            self.bags = {}
            local bagLines = {}
            if c.api.bagItems then
                local ok, items = pcall(c.api.bagItems)
                if ok then
                    for _, item in ipairs(items) do
                        if c.key and F.Adapters.sameListing(item.key, c.key) then
                            self.bags[#self.bags + 1] = item
                        end
                    end
                end
            end
            for i = 1, math.min(5, #self.bags) do
                local item = self.bags[i]
                bagLines[#bagLines + 1] = i
                    .. ". "
                    .. U.name(item.id)
                    .. " × "
                    .. item.qty
                    .. " · "
                    .. U.key(item.key)
            end
            self.bagText:SetText(
                #bagLines > 0 and table.concat(bagLines, "\n")
                    or L(
                        "No matching variant in bags. Select your item and search.",
                        "No matching variant in bags. Select your item and search."
                    )
            )
            local bidLines = {}
            for i = 1, math.min(6, #c.bidRows) do
                local r = c.bidRows[i]
                bidLines[#bidLines + 1] = i
                    .. ". #"
                    .. r.auctionID
                    .. " ×"
                    .. r.quantity
                    .. " · "
                    .. U.money(r.bidAmount or r.minBid)
            end
            self.bidText:SetText(table.concat(bidLines, "\n"))
            self:refreshCard(p, warningList)
        end
    end
    do
        local b = body("watch")
        text(
            b,
            0,
            0,
            810,
            L("LISTS AND OPERATION RULES", "LISTS AND OPERATION RULES"),
            "GameFontNormalLarge"
        )
        local list = text(b, 0, 40, 800, "")
        val("removeWatch", b, 0, 112, 160, L("Remove item ID", "Remove item ID"), "")
        action("watchRemove", b, 175, 132, 150, L("Remove from list", "Remove from list"), function()
            if not saveable() then
                return
            end
            local raw = self.fields.removeWatch:GetText()
            local id = U.fromKey(raw) and raw or tonumber(raw)
            for i = #db.watchlist, 1, -1 do
                if db.watchlist[i] == id then
                    table.remove(db.watchlist, i)
                end
            end
            c:stop()
            self:refresh()
        end)
        action("watchStart", b, 340, 132, 180, L("Watch 10 minutes", "Watch 10 minutes"), function()
            c:watchStart()
        end)
        text(
            b,
            0,
            180,
            810,
            L(
                "First matching group overrides defaults. Exchange: FFG1|name|ID,ID|ROI%|profit(g)|budget(g)|quantity",
                "First matching group overrides defaults. Exchange: FFG1|name|ID,ID|ROI%|profit(g)|budget(g)|quantity"
            )
        )
        val(
            "exchange",
            b,
            0,
            230,
            810,
            L("Group import / export", "Group import / export"),
            "FFG1|Cloth|2589,2592|25|1|100|10",
            true
        )
        action(
            "groupImport",
            b,
            0,
            370,
            200,
            L("Add / replace group", "Add / replace group"),
            function()
                if not saveable() then
                    return
                end
                local g, err = F.Store.importGroup(self.fields.exchange:GetText())
                if g then
                    local found = false
                    for i, v in ipairs(db.groups) do
                        if v.name == g.name then
                            db.groups[i] = g
                            found = true
                        end
                    end
                    if not found then
                        db.groups[#db.groups + 1] = g
                    end
                    c:invalidate()
                    self:refresh()
                else
                    c:notify(err)
                end
            end
        )
        val("groupIndex", b, 220, 350, 100, L("Group row", "Group row"), "1")
        action("groupExport", b, 340, 370, 170, L("Export", "Export"), function()
            local g = db.groups[tonumber(self.fields.groupIndex:GetText())]
            if g then
                self.fields.exchange:SetText(F.Store.exportGroup(g))
            end
        end)
        action("groupDelete", b, 530, 370, 160, L("Delete group", "Delete group"), function()
            if saveable() then
                local i = tonumber(self.fields.groupIndex:GetText())
                if i and db.groups[i] then
                    table.remove(db.groups, i)
                    c:invalidate()
                end
            end
        end)
        local groups = text(b, 0, 420, 810, "")
        self.groupSummary = groups
        self.refreshers.watch = function()
            local ids = {}
            for _, id in ipairs(db.watchlist or {}) do
                ids[#ids + 1] = tostring(id)
            end
            list:SetText(
                L("Watchlist: ", "Watchlist: ")
                    .. table.concat(ids, ", ")
                    .. "\n"
                    .. L(
                        "Add items using Trading → Add to watchlist.",
                        "Add items using Trading → Add to watchlist."
                    )
            )
            local lines = {}
            for i, g in ipairs(db.groups or {}) do
                local r = g.rule or {}
                lines[#lines + 1] = i
                    .. ". "
                    .. g.name
                    .. string.format(" · ROI %.0f%%", (r.minROI or 0) * 100)
                    .. " · "
                    .. U.money(r.budget)
                    .. " · max "
                    .. tostring(r.maxQty or "?")
            end
            groups:SetText(table.concat(lines, "\n"))
        end
    end
    do
        local b = body("portfolio")
        self.portfolioText = text(b, 0, 0, 815, "", "GameFontNormal")
        self:createSimplePortfolio(b)
        val("pendingIndex", b, 0, 210, 120, L("Pending row", "Pending row"), "1")
        action(
            "pendingBought",
            b,
            140,
            230,
            210,
            L("Purchase completed", "Purchase completed"),
            function()
                local op = self.pendingRows and self.pendingRows[tonumber(self.fields.pendingIndex:GetText())]
                if op then
                    c:reconcile(op.uid, true)
                end
            end
        )
        action(
            "pendingCancelled",
            b,
            365,
            230,
            250,
            L("Not spent / refunded", "Not spent / refunded"),
            function()
                local op = self.pendingRows and self.pendingRows[tonumber(self.fields.pendingIndex:GetText())]
                if op then
                    c:reconcile(op.uid, false)
                end
            end
        )
        text(
            b,
            0,
            275,
            810,
            L(
                "ACTUAL TRANSACTION · gold amounts, enter total",
                "ACTUAL TRANSACTION · gold amounts, enter total"
            ),
            "GameFontNormal"
        )
        val("entryKey", b, 0, 306, 220, L("ID / exact key", "ID / exact key"), "")
        val("entryQty", b, 235, 306, 100, L("Quantity", "Quantity"), "1")
        val("entryTotal", b, 350, 306, 150, L("Total, gold", "Total, gold"), "")
        val("entryFee", b, 515, 306, 130, L("Actual fee, gold", "Actual fee, gold"), "0")
        self.entryKind = "buy"
        action("entryKind", b, 0, 370, 180, L("Type: purchase", "Type: purchase"), function(btn)
            local nextKind = { buy = "sell", sell = "vendor", vendor = "expense", expense = "buy" }
            self.entryKind = nextKind[self.entryKind]
            btn:SetText(({
                buy = L("Buy", "Buy"),
                sell = L("AH sale", "AH sale"),
                vendor = L("NPC sale", "NPC sale"),
                expense = L("Expense", "Expense"),
            })[self.entryKind])
        end)
        action("entrySave", b, 200, 370, 190, L("Record completed trade", "Record completed trade"), function()
            if not saveable() then
                return
            end
            local raw = self.fields.entryKey:GetText()
            local key = U.fromKey(raw) or { itemID = tonumber(raw) }
            local identity = U.key(key)
            local qty = tonumber(self.fields.entryQty:GetText())
            local amount = U.copper(self.fields.entryTotal:GetText())
            local fee = U.copper(self.fields.entryFee:GetText())
            if not identity or not fee then
                c:notify(L("Check identity and fee.", "Check identity and fee."))
                return
            end
            local ok, err = F.Ledger.append(db, {
                kind = self.entryKind,
                owner = c.api.owner(),
                scope = c.api.scope(),
                key = identity,
                qty = qty,
                total = amount,
                fee = fee,
                at = c.api.clock(),
                source = "manual",
            })
            c:notify(ok and L("Saved.", "Saved.") or err)
        end)
        val("voidID", b, 410, 350, 200, L("UID to correct", "UID to correct"), "")
        action(
            "entryVoid",
            b,
            625,
            370,
            175,
            L("Append correction", "Append correction"),
            function()
                if saveable() then
                    F.Ledger.correct(db, self.fields.voidID:GetText(), c.api.owner(), c.api.clock())
                    self:refresh()
                end
            end
        )
        self.ledgerText = text(b, 0, 420, 810, "")
        text(
            b,
            0,
            630,
            810,
            L(
                "MAIL · read invoices only; no automatic collection",
                "MAIL · read invoices only; no automatic collection"
            ),
            "GameFontNormal"
        )
        action("mailRefresh", b, 0, 660, 180, L("Read invoices", "Read invoices"), function()
            c:event("MAIL_INBOX_UPDATE")
        end)
        val("mailIndex", b, 205, 640, 110, L("Mail row", "Mail row"), "1")
        action(
            "mailPrepare",
            b,
            335,
            660,
            320,
            L("Prepare uniquely matched receipt", "Prepare uniquely matched receipt"),
            function()
                local m = c.mail[tonumber(self.fields.mailIndex:GetText())]
                if not m or not m.suggestedKey then
                    c:notify(
                        L(
                            "Ambiguous invoice: enter identity manually.",
                            "Ambiguous invoice: enter identity manually."
                        )
                    )
                    return
                end
                if not U.finite(m.amount) or not U.finite(m.deposit) or m.deposit < 0 or m.deposit > m.amount then
                    c:notify(
                        L(
                            "Invoice net proceeds unknown. Check returned deposit manually.",
                            "Invoice net proceeds unknown. Check returned deposit manually."
                        )
                    )
                    return
                end
                local saleNet = m.amount - m.deposit
                self.fields.entryKey:SetText(m.suggestedKey)
                self.fields.entryQty:SetText(tostring(m.qty))
                self.fields.entryTotal:SetText(U.gold(saleNet))
                self.fields.entryFee:SetText("0")
                self.entryKind = "sell"
                self.actions.entryKind:SetText(L("AH sale", "AH sale"))
                c:notify(
                    L(
                        "Net sale excludes returned deposit, fee 0. Record after receipt; never deduct the fee twice.",
                        "Net sale excludes returned deposit, fee 0. Record after receipt; never deduct the fee twice."
                    )
                )
            end
        )
        self.mailText = text(b, 0, 705, 810, "")
        action("ledgerExport", b, 0, 885, 200, L("Export ledger CSV", "Export ledger CSV"), function()
            self:exchange(F.Ledger.csv(db.ledger or {}))
        end)
        action("portfolioPrevious", b, 0, 935, 170, L("← Previous", "← Previous"), function()
            self.portfolioPage = math.max(1, (self.portfolioPage or 1) - 1)
            self:refresh()
            self.fields.pendingIndex:SetText(tostring((self.portfolioPage - 1) * 3 + 1))
            self.fields.mailIndex:SetText(tostring((self.portfolioPage - 1) * 4 + 1))
        end)
        action("portfolioNext", b, 185, 935, 170, L("Next →", "Next →"), function()
            self.portfolioPage = (self.portfolioPage or 1) + 1
            self:refresh()
            self.fields.pendingIndex:SetText(tostring((self.portfolioPage - 1) * 3 + 1))
            self.fields.mailIndex:SetText(tostring((self.portfolioPage - 1) * 4 + 1))
        end)
        local portfolioPages = text(b, 380, 940, 400, "")
        self.refreshers.portfolio = function()
            local r = c:summary()
            self:refreshSimplePortfolio(r)
            local ledgerRows, ownedUIDs, pendingCount = {}, {}, 0
            for _, e in ipairs(db.ledger or {}) do
                if
                    e.owner == c.api.owner()
                    and (e.scope == c.api.scope() or (e.kind == "void" and ownedUIDs[e.target]))
                then
                    ledgerRows[#ledgerRows + 1] = e
                    if e.uid then
                        ownedUIDs[e.uid] = true
                    end
                end
            end
            for _, op in pairs(db.pending or {}) do
                if op.owner == c.api.owner() and (op.status == "unknown" or op.status == "bid") then
                    pendingCount = pendingCount + 1
                end
            end
            local total = math.max(
                1,
                math.ceil(#r.positions / 6),
                math.ceil(#ledgerRows / 6),
                math.ceil(pendingCount / 3),
                math.ceil(#c.mail / 4)
            )
            local page = math.max(1, math.min(total, self.portfolioPage or 1))
            self.portfolioPage = page
            portfolioPages:SetText(string.format(L("Page %d / %d", "Page %d / %d"), page, total))
            self.actions.portfolioPrevious:SetEnabled(page > 1)
            self.actions.portfolioNext:SetEnabled(page < total)
            local lines = {
                L(
                    "Positions · cost / age / action",
                    "Positions · cost / age / action"
                ),
            }
            local inBags = {}
            if c.api.bagItems then
                local ok, items = pcall(c.api.bagItems)
                if ok then
                    for _, item in ipairs(items) do
                        local k = U.key(item.key)
                        inBags[k] = (inBags[k] or 0) + item.qty
                    end
                end
            end
            for i = (page - 1) * 6 + 1, math.min(page * 6, #r.positions) do
                local p = r.positions[i]
                local key = U.fromKey(p.key)
                local price = key and c:price(key)
                local age = math.max(0, math.floor((c.api.clock() - (p.at or c.api.clock())) / 86400))
                local rule = key and c:rule(key) or settings
                local gross = price and U.floor(price * p.qty)
                local net = gross
                    and (gross - F.Market.fee(gross, rule.fee, rule.minFee) - U.floor(gross * (rule.reserve or 0)))
                local actionText = not price and L("no price", "no price")
                    or net > p.cost and L("review sale", "review sale")
                    or age >= 7 and L("reduce / check NPC", "reduce / check NPC")
                    or L("watch", "watch")
                local bags = math.min(p.qty, inBags[p.key] or 0)
                lines[#lines + 1] = p.key
                    .. " ×"
                    .. p.qty
                    .. " · "
                    .. U.money(p.cost)
                    .. " · "
                    .. age
                    .. "d · "
                    .. actionText
                    .. L(" · bags/outside bags ", " · bags/outside bags ")
                    .. bags
                    .. "/"
                    .. math.max(0, p.qty - bags)
            end
            self.pendingRows = {}
            for _, op in pairs(db.pending or {}) do
                if op.owner == c.api.owner() and (op.status == "unknown" or op.status == "bid") then
                    self.pendingRows[#self.pendingRows + 1] = op
                end
            end
            table.sort(self.pendingRows, function(a, d)
                return a.at < d.at
            end)
            lines[#lines + 1] = ""
            lines[#lines + 1] = L("Pending trades: ", "Pending trades: ") .. #self.pendingRows
            for i = (page - 1) * 3 + 1, math.min(page * 3, #self.pendingRows) do
                local op = self.pendingRows[i]
                lines[#lines + 1] = i
                    .. ". "
                    .. op.key
                    .. " ×"
                    .. op.qty
                    .. " · "
                    .. U.money(op.total)
                    .. " · "
                    .. op.status
            end
            self.portfolioText:SetText(table.concat(lines, "\n"))
            local entries = {}
            for i = #ledgerRows - (page - 1) * 6, math.max(1, #ledgerRows - page * 6 + 1), -1 do
                local e = ledgerRows[i]
                entries[#entries + 1] = (e.uid or "?")
                    .. " · "
                    .. (e.kind or "?")
                    .. " · "
                    .. (e.key or e.target or "?")
                    .. " · "
                    .. U.money(e.total)
            end
            self.ledgerText:SetText(table.concat(entries, "\n"))
            local m = {}
            for i = (page - 1) * 4 + 1, math.min(page * 4, #c.mail) do
                local e = c.mail[i]
                m[#m + 1] = i
                    .. ". "
                    .. e.kind
                    .. " · "
                    .. tostring(e.name)
                    .. " ×"
                    .. e.qty
                    .. " · "
                    .. U.money(e.amount)
                    .. " · "
                    .. (e.suggestedKey or L("unknown variant", "unknown variant"))
            end
            self.mailText:SetText(table.concat(m, "\n"))
        end
    end
    do
        local b = body("history")
        text(
            b,
            0,
            0,
            810,
            L("SELECTED ITEM HISTORY · 60 days", "SELECTED ITEM HISTORY · 60 days"),
            "GameFontNormalLarge"
        )
        self.historyText = text(b, 0, 40, 810, "")
        local chart = panel(b)
        F.NativeLayout.place(chart, b, 0, 108, 800, 220)
        self.chart = chart
        self.chartLines = {}
        local tableText = text(b, 0, 350, 810, "")
        self.refreshers.history = function()
            local key = readKey()
            local h = U.key(key) and c:history(key)
            local days = h and h.days or {}
            local stat = F.Market.stats(F.Market.evidence(h), c.api.clock())
            self.historyText:SetText(
                L("Reference / lower bound: ", "Reference / lower bound: ")
                    .. U.money(stat.reference)
                    .. " / "
                    .. U.money(stat.lower)
                    .. " · MAD σ "
                    .. U.money(stat.sigma)
                    .. " · n="
                    .. stat.n
                    .. " · "
                    .. stat.days
                    .. L(" days", " days")
                    .. "\n"
                    .. L(
                        "Chart: asking prices; disappeared listings are not proven sales.",
                        "Chart: asking prices; disappeared listings are not proven sales."
                    )
            )
            for _, line in pairs(self.chartLines) do
                line:Hide()
            end
            local low, high
            for _, d in ipairs(days) do
                low = math.min(low or d.price, d.price)
                high = math.max(high or d.price, d.price)
            end
            if #days > 1 then
                for i = 2, #days do
                    local line = self.chartLines[i] or chart:CreateLine(nil, "OVERLAY")
                    self.chartLines[i] = line
                    local function y(v)
                        return 200 - (v - (low or 0)) / math.max(1, (high or 1) - (low or 0)) * 175
                    end
                    line:SetStartPoint(
                        "TOPLEFT",
                        chart,
                        (i - 2) / (#days - 1) * math.max(1, chart:GetWidth() - 24) + 12,
                        -y(days[i - 1].price)
                    )
                    line:SetEndPoint(
                        "TOPLEFT",
                        chart,
                        (i - 1) / (#days - 1) * math.max(1, chart:GetWidth() - 24) + 12,
                        -y(days[i].price)
                    )
                    line:SetThickness(2)
                    line:SetColorTexture(0.35, 0.85, 0.74, 1)
                    line:Show()
                end
            end
            local lines = { L("Recent daily points:", "Recent daily points:") }
            for i = #days, math.max(1, #days - 7), -1 do
                local d = days[i]
                lines[#lines + 1] = date("%d.%m", d.day * 86400)
                    .. " · "
                    .. U.money(d.price)
                    .. " · "
                    .. d.qty
                    .. L(" listed", " listed")
            end
            local buckets = {}
            for _, s in ipairs(h and h.samples or {}) do
                local hour = tonumber(date("%H", s.at))
                buckets[hour] = buckets[hour] or {}
                table.insert(buckets[hour], s.price)
            end
            local hours = {}
            for hr, values in pairs(buckets) do
                if #values >= 3 then
                    hours[#hours + 1] = { hour = hr, price = U.median(values), n = #values }
                end
            end
            table.sort(hours, function(a, d)
                return a.price < d.price
            end)
            lines[#lines + 1] = ""
            lines[#lines + 1] = L(
                "Hours by median asks (not proven profit):",
                "Hours by median asks (not proven profit):"
            )
            for i = 1, math.min(4, #hours) do
                local v = hours[i]
                lines[#lines + 1] = v.hour .. ":00 · " .. U.money(v.price) .. " · n=" .. v.n
            end
            tableText:SetText(table.concat(lines, "\n"))
        end
    end
    do
        local b = body("tools")
        text(
            b,
            0,
            0,
            810,
            L("NPC ARBITRAGE · both directions", "NPC ARBITRAGE · both directions"),
            "GameFontNormalLarge"
        )
        val("vendorCost", b, 0, 42, 180, L("NPC purchase unit price, gold", "NPC purchase unit price, gold"), "")
        val("vendorQty", b, 195, 42, 120, L("Quantity", "Quantity"), "1")
        val("vendorAsk", b, 330, 42, 180, L("AH ask per unit, gold", "AH ask per unit, gold"), "")
        action("vendorCalc", b, 530, 62, 200, L("Calculate NPC → AH", "Calculate NPC → AH"), function()
            local cost = U.copper(self.fields.vendorCost:GetText())
            local ask = U.copper(self.fields.vendorAsk:GetText())
            local qty = tonumber(self.fields.vendorQty:GetText())
            if not cost or cost <= 0 then
                return
            end
            self.toolResult = F.Professions.calculate(
                { { id = readKey().itemID or 1, qty = qty, price = cost } },
                nil,
                qty,
                ask,
                settings
            )
            local key = readKey()
            if saveable() and key.itemID then
                db.vendorPrices[key.itemID] = { price = cost, at = c.api.clock(), source = "manual" }
            end
            self:renderToolResult()
        end)
        action(
            "vendorDirection",
            b,
            0,
            108,
            270,
            L("AH → NPC: open Trading", "AH → NPC: open Trading"),
            function()
                c:stop()
                c.mode = "vendor"
                self:show("trade", "deal")
            end
        )
        text(
            b,
            0,
            155,
            810,
            L(
                "CRAFT / CONVERT · materials and opportunity cost",
                "CRAFT / CONVERT · materials and opportunity cost"
            ),
            "GameFontNormal"
        )
        val(
            "recipeName",
            b,
            0,
            185,
            190,
            L("Saved calculation name", "Saved calculation name"),
            ""
        )
        val("outputQty", b, 205, 185, 100, L("Output quantity", "Output quantity"), "1")
        val("outputPrice", b, 320, 185, 180, L("Output unit price, gold", "Output unit price, gold"), "")
        val("recipeID", b, 515, 185, 120, "RecipeID", "")
        val(
            "materials",
            b,
            0,
            240,
            810,
            L(
                "Materials: ID*quantity@price(g); @price optional",
                "Materials: ID*quantity@price(g); @price optional"
            ),
            "",
            true
        )
        action("craftCalc", b, 0, 380, 180, L("Craft / convert", "Craft / convert"), function()
            local m, err = F.Professions.parse(self.fields.materials:GetText(), false)
            if not m then
                c:notify(err)
                return
            end
            local bags = c.api.bagItems and c.api.bagItems() or {}
            for _, material in ipairs(m) do
                local n = 0
                for _, item in ipairs(bags) do
                    if item.id == material.id then
                        n = n + item.qty
                    end
                end
                material.owned = n
            end
            self.toolResult = F.Professions.calculate(m, function(id)
                return c:price(id)
            end, tonumber(self.fields.outputQty:GetText()), U.copper(self.fields.outputPrice:GetText()), settings)
            self.materialShopping = self.toolResult.shopping
            self:renderToolResult()
        end)
        action("recipeSave", b, 195, 380, 150, L("Save", "Save"), function()
            if not saveable() then
                return
            end
            local name = self.fields.recipeName:GetText()
            if name == "" then
                return
            end
            db.recipes[name] = {
                materials = self.fields.materials:GetText(),
                outputQty = self.fields.outputQty:GetText(),
                outputPrice = self.fields.outputPrice:GetText(),
            }
            c:notify(L("Calculation saved.", "Calculation saved."))
        end)
        action("recipeLoad", b, 360, 380, 150, L("Load", "Load"), function()
            local r = (db.recipes or {})[self.fields.recipeName:GetText()]
            if r and r.materials then
                self.fields.materials:SetText(r.materials)
                self.fields.outputQty:SetText(r.outputQty or "1")
                self.fields.outputPrice:SetText(r.outputPrice or "")
            end
        end)
        action(
            "recipeImport",
            b,
            525,
            380,
            220,
            L("Import recipe schematic", "Import recipe schematic"),
            function()
                local id = tonumber(self.fields.recipeID:GetText())
                if not id or not C_TradeSkillUI or not C_TradeSkillUI.GetRecipeSchematic then
                    c:notify("Recipe API unavailable")
                    return
                end
                local ok, s = pcall(C_TradeSkillUI.GetRecipeSchematic, id, false)
                local materials = {}
                if not ok or not s then
                    c:notify("Recipe unavailable")
                    return
                end
                for _, slot in ipairs(s.reagentSlotSchematics or {}) do
                    if slot.required and slot.reagents and #slot.reagents == 1 and slot.reagents[1].itemID then
                        materials[#materials + 1] = slot.reagents[1].itemID .. "*" .. slot.quantityRequired
                    else
                        c:notify(
                            L(
                                "This schematic requires manual input.",
                                "This schematic requires manual input."
                            )
                        )
                        return
                    end
                end
                self.fields.materials:SetText(table.concat(materials, ", "))
                self.fields.outputQty:SetText(tostring(s.quantityMin or 1))
            end
        )
        text(
            b,
            0,
            430,
            810,
            L("DISENCHANT / RANDOM OUTPUT", "DISENCHANT / RANDOM OUTPUT"),
            "GameFontNormal"
        )
        val(
            "yields",
            b,
            0,
            458,
            810,
            L(
                "Expected output: ID*expected_quantity@price(g)",
                "Expected output: ID*expected_quantity@price(g)"
            ),
            "",
            true
        )
        val("deCost", b, 0, 598, 180, L("Input cost, gold", "Input cost, gold"), "")
        action(
            "deCalc",
            b,
            200,
            618,
            210,
            L("Calculate disenchant", "Calculate disenchant"),
            function()
                local y, err = F.Professions.parse(self.fields.yields:GetText(), true)
                if not y then
                    c:notify(err)
                    return
                end
                self.toolResult = F.Professions.disenchant(y, function(id)
                    return c:price(id)
                end, U.copper(self.fields.deCost:GetText()), settings)
                self:renderToolResult()
            end
        )
        action("deSave", b, 425, 618, 160, L("Save yields", "Save yields"), function()
            if saveable() and self.fields.recipeName:GetText() ~= "" then
                db.disenchant[self.fields.recipeName:GetText()] =
                    { raw = self.fields.yields:GetText(), cost = self.fields.deCost:GetText() }
            end
        end)
        action("deLoad", b, 600, 618, 160, L("Load yields", "Load yields"), function()
            local y = db.disenchant[self.fields.recipeName:GetText()]
            if y and y.raw then
                self.fields.yields:SetText(y.raw)
                self.fields.deCost:SetText(y.cost or "")
            end
        end)
        self.toolScroll = CreateFrame("ScrollFrame", nil, b, "UIPanelScrollFrameTemplate")
        F.NativeLayout.place(self.toolScroll, b, 0, 670, 780, 165)
        self.toolContent = CreateFrame("Frame", nil, self.toolScroll)
        self.toolContent:SetSize(750, 170)
        F.NativeLayout.container(self.toolContent, self.toolScroll, 30)
        self.toolScroll:SetScrollChild(self.toolContent)
        self.toolText = text(self.toolContent, 0, 0, 810, "")
        val("materialIndex", b, 0, 855, 120, L("Material row", "Material row"), "1")
        action(
            "materialSearch",
            b,
            140,
            875,
            250,
            L("Buy material: exact search", "Buy material: exact search"),
            function()
                local m = self.materialShopping and self.materialShopping[tonumber(self.fields.materialIndex:GetText())]
                if m and m.qty > 0 then
                    c:stop("manual")
                    c.mode = "material"
                    local requestID = c.api.owner()
                        .. "|"
                        .. c.api.scope()
                        .. "|"
                        .. self.fields.materialIndex:GetText()
                    self.materialRequests = self.materialRequests or {}
                    self.materialRequests[requestID] = self.materialRequests[requestID]
                        or {
                            itemID = m.id,
                            qty = m.qty,
                            price = m.price,
                            cost = m.cost,
                            first = #db.ledger,
                            owner = c.api.owner(),
                            scope = c.api.scope(),
                        }
                    c.materialRequest = self.materialRequests[requestID]
                    self.fields.item:SetText(tostring(m.id))
                    c.overrides = {
                        maxQty = m.qty,
                        budget = m.cost,
                    }
                    c:searchInput(tostring(m.id))
                    self:show("trade", "deal")
                end
            end
        )
        text(
            b,
            0,
            925,
            810,
            L(
                "CROSS-MARKET CALCULATOR · transfer must actually be available",
                "CROSS-MARKET CALCULATOR · transfer must actually be available"
            ),
            "GameFontNormal"
        )
        val("crossBuy", b, 0, 955, 170, L("Buy / unit, gold", "Buy / unit, gold"), "")
        val("crossSell", b, 185, 955, 170, L("Sell / unit, gold", "Sell / unit, gold"), "")
        val("crossTransfer", b, 370, 955, 170, L("Transfer / unit, gold", "Transfer / unit, gold"), "0")
        action("crossCalc", b, 555, 975, 215, L("Calculate transfer", "Calculate transfer"), function()
            local buy = U.copper(self.fields.crossBuy:GetText())
            local sell = U.copper(self.fields.crossSell:GetText())
            local transport = U.copper(self.fields.crossTransfer:GetText())
            if buy and buy > 0 and sell and transport then
                self.toolResult =
                    F.Professions.calculate({ { id = 1, qty = 1, price = buy + transport } }, nil, 1, sell, settings)
                self:renderToolResult()
            end
        end)
        self.sections.tools.body:SetHeight(1060)
    end
    do
        local b = body("settings")
        text(
            b,
            0,
            0,
            810,
            L("SHARED TRADE RULES", "SHARED TRADE RULES"),
            "GameFontNormalLarge"
        )
        local fields = {
            { "roi", L("Minimum ROI, %", "Minimum ROI, %"), settings.minROI * 100 },
            { "profit", L("Minimum profit, gold", "Minimum profit, gold"), U.gold(settings.minProfit) },
            { "wallet", L("Per trade, % wallet", "Per trade, % wallet"), settings.maxWallet * 100 },
            { "itemShare", L("Per item, % capital", "Per item, % capital"), settings.maxItem * 100 },
            {
                "cashFloor",
                L("Cash floor, % wallet", "Cash floor, % wallet"),
                settings.cashFloor * 100,
            },
            { "maxQty", L("Maximum units", "Maximum units"), settings.maxQty },
            { "fee", L("AH fee, % (assumption)", "AH fee, % (assumption)"), settings.fee * 100 },
            {
                "minFee",
                L("Minimum fee, gold (assumption)", "Minimum fee, gold (assumption)"),
                U.gold(settings.minFee),
            },
            { "reserve", L("Relisting reserve, %", "Relisting reserve, %"), settings.reserve * 100 },
            {
                "budget",
                L("Budget cap, gold; 0=auto", "Budget cap, gold; 0=auto"),
                U.gold(settings.budget),
            },
            {
                "absoluteCap",
                L("Absolute cap, gold; 0=none", "Absolute cap, gold; 0=none"),
                U.gold(settings.absoluteCap),
            },
            { "maxShare", L("Max visible market share, %", "Max visible market share, %"), settings.maxShare * 100 },
        }
        for i, v in ipairs(fields) do
            local col = (i - 1) % 3
            local row = math.floor((i - 1) / 3)
            val(v[1], b, col * 270, 45 + row * 68, 250, v[2], v[3])
        end
        val(
            "buyFormula",
            b,
            0,
            330,
            810,
            L("Maximum purchase formula", "Maximum purchase formula"),
            settings.buyFormula
        )
        val(
            "sellFormula",
            b,
            0,
            395,
            810,
            L("Minimum sale formula", "Minimum sale formula"),
            settings.sellFormula
        )
        action("settingsSave", b, 0, 460, 210, L("Save rules", "Save rules"), function()
            if not saveable() then
                return
            end
            local numbers = {}
            for _, v in ipairs(fields) do
                local n = tonumber((self.fields[v[1]]:GetText():gsub(",", ".")))
                if not U.finite(n) or n < 0 then
                    c:notify(L("Invalid number.", "Invalid number."))
                    return
                end
                numbers[v[1]] = n
            end
            if
                numbers.roi > 1000
                or numbers.wallet > 100
                or numbers.itemShare > 100
                or numbers.cashFloor > 100
                or numbers.fee + numbers.reserve >= 100
                or numbers.maxShare > 100
                or numbers.maxQty < 1
                or numbers.maxQty > 100000
                or numbers.maxQty % 1 ~= 0
            then
                c:notify("Rule range")
                return
            end
            local buy = self.fields.buyFormula:GetText()
            local sell = self.fields.sellFormula:GetText()
            local sample = {
                market = 10000,
                recent = 10000,
                vendorsell = 500,
                avgbuy = 500,
                ewma = 9500,
                pricefloor = 9000,
                winlower = 0.5,
                profitfactor = 1.5,
                salesperday = 2,
            }
            if not F.Expr.eval(buy, sample) or not F.Expr.eval(sell, sample) then
                c:notify(L("Check formula.", "Check formula."))
                return
            end
            settings.minROI = numbers.roi / 100
            settings.minProfit = math.floor(numbers.profit * 10000 + 0.5)
            settings.maxWallet = numbers.wallet / 100
            settings.maxItem = numbers.itemShare / 100
            settings.cashFloor = numbers.cashFloor / 100
            settings.maxQty = numbers.maxQty
            settings.fee = numbers.fee / 100
            settings.minFee = math.floor(numbers.minFee * 10000 + 0.5)
            settings.reserve = numbers.reserve / 100
            settings.maxShare = numbers.maxShare / 100
            settings.budget = numbers.budget > 0 and math.floor(numbers.budget * 10000 + 0.5) or nil
            settings.absoluteCap = numbers.absoluteCap > 0 and math.floor(numbers.absoluteCap * 10000 + 0.5) or nil
            settings.buyFormula = buy
            settings.sellFormula = sell
            c:invalidate()
        end)
        val(
            "house",
            b,
            230,
            440,
            230,
            L("House: Alliance/Horde/Neutral", "House: Alliance/Horde/Neutral"),
            db.ui and db.ui.house or UnitFactionGroup("player")
        )
        action("houseSave", b, 480, 460, 220, L("Change market", "Change market"), function()
            if not saveable() then
                return
            end
            local house = self.fields.house:GetText()
            if house ~= "Alliance" and house ~= "Horde" and house ~= "Neutral" then
                return
            end
            c:stop()
            db.ui.house = house
            c:notify(
                L(
                    "Market changed. Verify the house and fee.",
                    "Market changed. Verify the house and fee."
                )
            )
        end)
        text(
            b,
            0,
            515,
            810,
            L(
                "Formulas: min/max/first/avg/check/ifgt/ifgte/iflt/iflte/ifeq/round/roundup/rounddown; arithmetic, %, g/s/c.\nSources: market, recent, vendorsell, avgbuy, aux, tsm (only when available). Example: min(70% market, 50g). This is a limited language, not full TSM compatibility.\n\nRisk: median/MAD, lower price bound, age decay, depth and capital limits. No promise of future returns.",
                "Formulas: min/max/first/avg/check/ifgt/ifgte/iflt/iflte/ifeq/round/roundup/rounddown; arithmetic, %, g/s/c.\nSources: market, recent, vendorsell, avgbuy, aux, tsm (only when available). Example: min(70% market, 50g). This is a limited language, not full TSM compatibility.\n\nRisk: median/MAD, lower price bound, age decay, depth and capital limits. No promise of future returns."
            )
        )
        action(
            "legacyPreview",
            b,
            0,
            735,
            230,
            L("Preview legacy ledger", "Preview legacy ledger"),
            function()
                local lines = { L("Legacy", "Legacy") .. " · " .. #(db.legacyLedger or {}) }
                for i, e in ipairs(db.legacyLedger or {}) do
                    if i <= 100 then
                        lines[#lines + 1] = (e.kind or "?")
                            .. " "
                            .. tostring(e.id)
                            .. " ×"
                            .. tostring(e.qty)
                            .. " @ "
                            .. tostring(e.unit)
                    end
                end
                self:exchange(table.concat(lines, "\n"))
            end
        )
        action(
            "legacyAssign",
            b,
            250,
            735,
            300,
            L("Confirm legacy owner and market", "Confirm legacy owner and market"),
            function()
                if not saveable() or db.legacyAssigned then
                    return
                end
                if not self.legacyConfirm then
                    self.legacyConfirm = true
                    c:notify(
                        L(
                            "Review legacy data. Click again to assign ALL entries to this character and market.",
                            "Review legacy data. Click again to assign ALL entries to this character and market."
                        )
                    )
                    return
                end
                local ok, err = F.Store.adoptLegacy(db, c.api.owner(), c.api.scope(), c.api.clock())
                if ok then
                    c:invalidate()
                else
                    c:notify(err)
                end
            end
        )
        text(
            b,
            0,
            790,
            810,
            L(
                "References: TSM, Auctionator, auxForever, Auctioneer, AuctionMin, AHSentinel, AHledger, Everloot. Paid data access is not included. External prices require matching scope and timestamps.",
                "References: TSM, Auctionator, auxForever, Auctioneer, AuctionMin, AHSentinel, AHledger, Everloot. Paid data access is not included. External prices require matching scope and timestamps."
            )
        )
        val(
            "priceImport",
            b,
            0,
            875,
            810,
            L(
                "Import prices: FFP1|exact_scope|Unix_time, then key,copper,quantity rows",
                "Import prices: FFP1|exact_scope|Unix_time, then key,copper,quantity rows"
            ),
            "",
            true
        )
        action(
            "priceImport",
            b,
            0,
            1020,
            220,
            L("Validate and import", "Validate and import"),
            function()
                if not saveable() then
                    return
                end
                local ok, err =
                    F.Store.importPrices(db, self.fields.priceImport:GetText(), c.api.scope(), c.api.clock())
                c:notify(
                    ok
                            and L(
                                "Imported with source label.",
                                "Imported with source label."
                            )
                        or err
                )
            end
        )
        text(
            b,
            0,
            1095,
            810,
            L("Language (the UI reloads)", "Language (the UI reloads)")
        )
        for i, language in ipairs({
            { "en", "English" },
            { "uk", "Українська" },
            { "auto", L("Game language", "Game language") },
        }) do
            local choice = language[1]
            action("language" .. choice, b, (i - 1) * 175, 1120, 165, language[2], function()
                F.NativeLayout.chooseLanguage(self, choice)
            end)
        end
        local function autoScanLabel()
            return (db.settings or {}).autoScan == false
                    and L("Auto scan: off", "Auto scan: off")
                or L("Auto scan: on", "Auto scan: on")
        end
        action("autoScan", b, 0, 1160, 260, autoScanLabel(), function(btn)
            if not saveable() then
                return
            end
            if db.settings.autoScan == false then
                db.settings.autoScan = nil
            else
                db.settings.autoScan = false
            end
            btn:SetText(autoScanLabel())
        end)
        text(
            b,
            270,
            1165,
            540,
            L(
                "Every 15 minutes while the auction house is open, the addon scans the market to learn usual prices.",
                "Every 15 minutes while the auction house is open, the addon scans the market to learn usual prices."
            )
        )
        text(b, 0, 1205, 800, "ForeverFlip " .. F.version)
        self.sections.settings.body:SetHeight(1240)
    end
    self.exchangeFrame = panel(host)
    self.exchangeFrame:SetPoint("CENTER")
    self.exchangeFrame:SetSize(850, 450)
    F.NativeLayout.container(self.exchangeFrame, host, 24)
    self.exchangeFrame:SetFrameLevel(host:GetFrameLevel() + 20)
    self.exchangeFrame:Hide()
    self.exchangeEdit = field(
        self.exchangeFrame,
        15,
        15,
        810,
        L(
            "Select Ctrl+A → Ctrl+C. Text only.",
            "Select Ctrl+A → Ctrl+C. Text only."
        ),
        "",
        true
    )
    self.exchangeEdit:SetHeight(335)
    button(self.exchangeFrame, 650, 400, 160, L("Close", "Close"), function()
        self.exchangeFrame:Hide()
    end)
    self:buildSplitPages()
    local saved = db.ui and db.ui.section
    if F.NativeLayout.simple(self) and not (db.ui and db.ui.guideSeen) then
        -- First visit in simple mode opens the guide once; afterwards the last section is restored.
        if F.Store.writable(db) then
            db.ui.guideSeen = true
        end
        self:show("overview")
    else
        self:show((saved and saved ~= "overview") and saved or "deals")
    end
    host:Show()
    root:Hide()
    return self
end
function UI:exchange(value)
    self.exchangeEdit:SetText(value)
    self.exchangeFrame:Show()
    self.exchangeEdit:SetFocus()
    self.exchangeEdit:HighlightText()
end
function UI:renderToolResult()
    if self.sections.tools.split then
        self:show("tools", "result")
    end
    local r = self.toolResult
    if r ~= self.materialSource then
        self.materialSource, self.materialRequests = r, {}
    end
    self.materialShopping = r and r.shopping or nil
    if not r then
        return
    end
    if not r.complete then
        self.toolContent:SetHeight(170)
        self.toolText:SetText(
            L(
                "Missing input prices/output. Profit unknown.",
                "Missing input prices/output. Profit unknown."
            )
        )
        self.c:notify("calculation_incomplete")
        return
    end
    local lines = {
        L("Economic cost: ", "Economic cost: ") .. U.money(r.cost) .. L(
            " · cash needed: ",
            " · cash needed: "
        ) .. U.money(r.cashCost),
        L("Net potential: ", "Net potential: ")
            .. U.money(r.profit)
            .. string.format(" · ROI %.1f%%", (r.roi or 0) * 100),
    }
    for i, m in ipairs(r.shopping or {}) do
        lines[#lines + 1] = i .. ". " .. U.name(m.id) .. " ×" .. m.qty .. " · " .. U.money(m.cost)
    end
    self.toolText:SetText(table.concat(lines, "\n"))
    self.toolContent:SetHeight(math.max(170, self.toolText:GetStringHeight() + 20))
    self.toolScroll:SetVerticalScroll(0)
    self.c:notify("calculation_done")
end
function UI:updateProgress(dt)
    F.Progress.paint(self, dt)
end
function UI:layout()
    F.NativeLayout.reflow(self)
    if self.section == "history" and not self.refreshing and self.refreshers.history then
        self:refresh()
    end
end
-- Every tab except Auction becomes a split page: a category list on the left and one compact panel
-- on the right. Existing controls are moved by their original y range; their logic is unchanged.
function UI:buildSplitPages()
    local N = F.NativeLayout
    local function body(id)
        return self.sections[id].body
    end
    local function entries(list)
        local out = {}
        for _, e in ipairs(list) do
            out[#out + 1] = { e[1], section = e[2], page = e[3] }
        end
        return out
    end
    local function build(section, list, fill)
        N.split(self, section, entries(list))
        fill(function(id)
            return N.page(self, section, id)
        end)
    end
    build("overview", {
        { L("How to earn", "How to earn"), "overview", "guide" },
        { L("My trading day", "My trading day"), "overview", "day" },
    }, function(page)
        N.migrate(self, page("guide"), body("overview"), 0, 300, 0)
        N.migrate(self, page("day"), body("overview"), 300, 700, 0)
        N.migrate(self, page("day"), body("overview"), 700, 800, 230)
    end)
    build("trade", {
        { L("Deal", "Deal"), "trade", "deal" },
        { L("Sell what you bought", "Sell what you bought"), "trade", "sell" },
        { L("Calculation and limits", "Calculation and limits"), "trade", "calc" },
        { L("Bids", "Bids"), "trade", "bids" },
    }, function(page)
        N.attach(self, page("deal"), self.tradeCard, 0, 252)
        N.migrate(self, page("deal"), body("trade"), 0, 40, 258)
        N.attach(self, page("sell"), self.tradeSell, 0, 330)
        N.migrate(self, page("calc"), self.tradeContent, 40, 260, 0)
        N.migrate(self, page("calc"), self.tradeContent, 260, 320, 160)
        N.migrate(self, page("calc"), self.tradeContent, 820, 900, 235)
        N.migrate(self, page("bids"), self.tradeContent, 625, 800, 0)
    end)
    build("portfolio", {
        { L("My items", "My items"), "portfolio", "items" },
        { L("My auctions", "My auctions"), "portfolio", "auctions" },
        { L("Unfinished purchases", "Unfinished purchases"), "portfolio", "pending" },
        { L("Mail", "Mail"), "portfolio", "mail" },
        { L("Transaction log", "Transaction log"), "portfolio", "journal" },
        { L("Manual entry", "Manual entry"), "portfolio", "manual" },
    }, function(page)
        N.attach(self, page("items"), self.portfolioSimple, 0, 254)
        self:createOwnedPage(page("auctions"))
        N.attach(self, page("pending"), self.portfolioPendingRoot, 0, 188)
        N.migrate(self, page("mail"), body("portfolio"), 625, 880, 0)
        N.migrate(self, page("journal"), body("portfolio"), 415, 625, 0)
        N.migrate(self, page("journal"), body("portfolio"), 880, 1000, 215)
        N.migrate(self, page("manual"), body("portfolio"), 270, 415, 0)
    end)
    local analytics = {
        { L("Purchase planner", "Purchase planner"), "workbench", "pick" },
        { L("Sales statistics", "Sales statistics"), "workbench", "stats" },
        { L("Planner report", "Planner report"), "workbench", "report" },
        { L("Manual allocation", "Manual allocation"), "workbench", "manual" },
        { L("History replay", "History replay"), "workbench", "replay" },
        { L("Watchlist", "Watchlist"), "watch", "list" },
        { L("Rule groups", "Rule groups"), "watch", "groups" },
        { L("Price history", "Price history"), "history", "chart" },
    }
    build("workbench", analytics, function(page)
        N.migrate(self, page("pick"), body("workbench"), 30, 70, 0)
        N.migrate(self, page("pick"), self.workbenchContent, 115, 410, 40)
        N.migrate(self, page("report"), self.workbenchContent, 0, 115, 0)
        N.migrate(self, page("report"), self.workbenchContent, 550, 835, 115)
        N.attach(self, page("manual"), self.advancedPlan, 0, 100)
        N.migrate(self, page("replay"), self.workbenchContent, 835, 1100, 0)
        self.actions.adviceAdvanced:Hide()
        N.scrolling(self, page("stats"))
        self:createStatsPage(page("stats").ffContent)
    end)
    build("watch", analytics, function(page)
        N.migrate(self, page("list"), body("watch"), 0, 180, 0)
        N.migrate(self, page("groups"), body("watch"), 180, 600, 0)
        N.scrolling(self, page("groups"))
    end)
    build("history", analytics, function(page)
        N.migrate(self, page("chart"), body("history"), 35, 600, 0)
        N.scrolling(self, page("chart"))
    end)
    build("tools", {
        { L("Vendor and auction", "Vendor and auction"), "tools", "vendor" },
        { L("Crafting", "Crafting"), "tools", "craft" },
        { L("Disenchanting", "Disenchanting"), "tools", "disenchant" },
        { L("Buying reagents", "Buying reagents"), "tools", "reagents" },
        { L("Between markets", "Between markets"), "tools", "cross" },
        { L("Calculation result", "Calculation result"), "tools", "result" },
    }, function(page)
        N.migrate(self, page("vendor"), body("tools"), 0, 150, 0)
        N.migrate(self, page("craft"), body("tools"), 150, 425, 0)
        N.migrate(self, page("disenchant"), body("tools"), 425, 665, 0)
        N.migrate(self, page("reagents"), body("tools"), 665, 920, 0)
        N.migrate(self, page("cross"), body("tools"), 920, 1100, 0)
        N.attach(self, page("result"), self.toolScroll, 0, 280)
        for _, e in ipairs(self.nativeLayout.controls) do
            if e.widget == self.toolScroll then
                e.parent, e.y, e.baseY, e.height = page("result"), 0, 0, 280
            end
        end
    end)
    build("settings", {
        { L("General", "General"), "settings", "main" },
        { L("Trading limits", "Trading limits"), "settings", "rules" },
        { L("Formulas and market", "Formulas and market"), "settings", "formulas" },
        { L("Legacy data", "Legacy data"), "settings", "legacy" },
        { L("Price import", "Price import"), "settings", "import" },
    }, function(page)
        N.migrate(self, page("main"), body("settings"), 1090, 1300, 0)
        N.migrate(self, page("rules"), body("settings"), 0, 325, 0)
        N.migrate(self, page("formulas"), body("settings"), 325, 500, 0)
        N.migrate(self, page("legacy"), body("settings"), 500, 780, 0)
        N.migrate(self, page("import"), body("settings"), 780, 1070, 0)
        local save = button(page("rules"), 0, 310, 210, L("Save rules", "Save rules"), function()
            self.actions.settingsSave:Click()
        end)
        self.actions.settingsSaveRules = save
    end)
    local workbench, portfolio = self.refreshers.workbench, self.refreshers.portfolio
    self.refreshers.workbench = function()
        if workbench then
            workbench()
        end
        self:refreshStats()
    end
    self.refreshers.portfolio = function()
        if portfolio then
            portfolio()
        end
        self:refreshOwnedPage()
    end
end
function UI:show(id, page)
    if not self.sections[id] then
        return
    end
    self.section = id
    for k, v in pairs(self.sections) do
        if k == id then
            v.scroll:Show()
        else
            v.scroll:Hide()
        end
    end
    F.NativeLayout.select(self, id)
    F.NativeLayout.selectPage(self, id, page)
    if F.Store.writable(self.c.db) then
        self.c.db.ui.section = id
    end
    self.showing = true
    self.frame:Show()
    self.showing = false
    self:refresh()
end
-- Beginner route: live auction lots that a vendor buys back for more, under the 1g purchase cap.
function UI:startNPC()
    if not self.c:easyNPC() then
        return false
    end
    self.liveOnly = true
    self.watchOnly = false
    self.groupFilter = nil
    self.filterMode = "vendor"
    self.sort = "profit"
    self.sortDescending = true
    self.dealPage = 1
    self.fields.dealFilter:SetText("")
    return true
end
-- Fills the simple-mode deal card. Every purchase still needs the player's two clicks.
local PORTFOLIO_ROWS, PENDING_ROWS = 6, 5
local function insetPanel(parent, y, height, padding)
    local f = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    f:SetSize(800, height)
    F.NativeLayout.container(f, parent, padding or 4)
    local art = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    art:SetAtlas("auctionhouse-background-index")
    art:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
    art:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
    return f
end
local function itemRow(parent, index, height)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -4 - (index - 1) * height)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, -4 - (index - 1) * height)
    row:SetHeight(height - 1)
    local stripe = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    stripe:SetAtlas("auctionhouse-rowstripe-1")
    stripe:SetAllPoints()
    stripe:SetAlpha(index % 2 == 0 and 0.8 or 0.3)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(height - 6, height - 6)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local function label(font, x, width, justify)
        local f = row:CreateFontString(nil, "OVERLAY", font)
        f:SetPoint("LEFT", row, "LEFT", x, 0)
        f:SetWidth(width)
        f:SetJustifyH(justify or "LEFT")
        f:SetWordWrap(false)
        F.Locale.font(f, 12)
        return f
    end
    row.name = label("GameFontHighlight", height + 4, 165)
    row.qty = label("GameFontHighlight", 200, 40, "CENTER")
    row.cost = label("GameFontHighlight", 245, 90, "RIGHT")
    row.advice = label("GameFontNormalSmall", 345, 100)
    row.advice:SetPoint("RIGHT", row, "RIGHT", -122, 0)
    return row
end
local function smallButton(parent, width, title, fn)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 20)
    b:SetText(title)
    F.Locale.font(b:GetFontString(), 11)
    b:SetScript("OnClick", fn)
    return b
end
-- Simple-mode Portfolio: what you own, what to do with it, and unfinished purchases as rows
-- with their own buttons instead of row-number fields.
function UI:createSimplePortfolio(body)
    local c = self.c
    local ui = self
    local root = CreateFrame("Frame", nil, body)
    root:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    root:SetSize(800, 470)
    F.NativeLayout.container(root, body, 0)
    self.portfolioSimple = root
    local summary = insetPanel(root, 0, 40)
    self.portfolioSummary = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.portfolioSummary:SetPoint("LEFT", summary, "LEFT", 12, 0)
    self.portfolioSummary:SetPoint("RIGHT", summary, "RIGHT", -12, 0)
    self.portfolioSummary:SetJustifyH("LEFT")
    F.Locale.font(self.portfolioSummary, 12)
    local title = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", root, "TOPLEFT", 4, -50)
    F.Locale.font(title, 12)
    title:SetText(L("MY ITEMS", "MY ITEMS"))
    local headers = {
        { 8, 190, L("Item", "Item") },
        { 200, 42, L("Qty", "Qty") },
        { 245, 96, L("Paid", "Paid") },
        { 345, 210, L("What to do", "What to do") },
    }
    for _, h in ipairs(headers) do
        local header = F.NativeLayout.header(root, h[3])
        header:SetPoint("TOPLEFT", root, "TOPLEFT", h[1], -66)
        header:SetSize(h[2], 22)
    end
    local list = insetPanel(root, 90, PORTFOLIO_ROWS * 26 + 8)
    self.portfolioEmpty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    self.portfolioEmpty:SetPoint("CENTER", list, "CENTER")
    F.Locale.font(self.portfolioEmpty, 12)
    self.portfolioEmpty:SetText(
        L(
            "Everything you buy through the addon appears here.",
            "Everything you buy through the addon appears here."
        )
    )
    self.portfolioRows = {}
    for i = 1, PORTFOLIO_ROWS do
        local row = itemRow(list, i, 26)
        row.sell = smallButton(row, 110, L("Sell", "Sell"), function(b)
            local key = b:GetParent().itemKey
            ui:show("trade", "sell")
            for _, entry in ipairs(key and ui:sellCandidates() or {}) do
                if F.Adapters.sameListing(entry.key, key) then
                    ui:selectSellItem(entry)
                    return
                end
            end
            c:notify("post_no_item")
        end)
        row.sell:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        self.portfolioRows[i] = row
    end
    root:SetHeight(90 + PORTFOLIO_ROWS * 26 + 8)
    local pendingRoot = CreateFrame("Frame", nil, body)
    pendingRoot:SetSize(800, 40 + PENDING_ROWS * 28 + 8)
    self.portfolioPendingRoot = pendingRoot
    self.portfolioNoPending = pendingRoot:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    self.portfolioNoPending:SetPoint("TOP", pendingRoot, "TOP", 0, -80)
    F.Locale.font(self.portfolioNoPending, 12)
    self.portfolioNoPending:SetText(
        L(
            "No unfinished purchases — everything is recorded.",
            "No unfinished purchases — everything is recorded."
        )
    )
    local pendingY = 0
    local pendingTitle = pendingRoot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pendingTitle:SetPoint("TOPLEFT", pendingRoot, "TOPLEFT", 4, -pendingY)
    pendingTitle:SetWidth(540)
    pendingTitle:SetJustifyH("LEFT")
    F.Locale.font(pendingTitle, 12)
    pendingTitle:SetText(
        L(
            "UNFINISHED PURCHASES · check chat or mail and mark the result",
            "UNFINISHED PURCHASES · check chat or mail and mark the result"
        )
    )
    self.portfolioPendingTitle = pendingTitle
    local pending = insetPanel(pendingRoot, pendingY + 36, PENDING_ROWS * 28 + 8)
    self.portfolioPendingPanel = pending
    self.portfolioPending = {}
    for i = 1, PENDING_ROWS do
        local row = itemRow(pending, i, 28)
        row.no = smallButton(row, 110, L("Not bought", "Not bought"), function(b)
            local op = b:GetParent().op
            if op then
                c:reconcile(op.uid, false)
                ui:refresh()
            end
        end)
        row.no:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.yes = smallButton(row, 110, L("Bought", "Bought"), function(b)
            local op = b:GetParent().op
            if op then
                c:reconcile(op.uid, true)
                ui:refresh()
            end
        end)
        row.yes:SetPoint("RIGHT", row.no, "LEFT", -6, 0)
        self.portfolioPending[i] = row
    end
    self.portfolioPrev = smallButton(root, 30, "<", function()
        ui.portfolioSimplePage = math.max(1, (ui.portfolioSimplePage or 1) - 1)
        ui:refresh()
    end)
    self.portfolioNextPage = smallButton(root, 30, ">", function()
        ui.portfolioSimplePage = (ui.portfolioSimplePage or 1) + 1
        ui:refresh()
    end)
    self.portfolioPrev:SetPoint("TOPRIGHT", root, "TOPRIGHT", -40, -48)
    self.portfolioNextPage:SetPoint("TOPRIGHT", root, "TOPRIGHT", -4, -48)
    self.portfolioSimplePageText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.portfolioSimplePageText:SetPoint("RIGHT", self.portfolioPrev, "LEFT", -8, 0)
end
local function setItem(row, key)
    local m = key and F.ItemDisplay.metadata(key)
    local color = m and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[m.quality]
    row.icon:SetTexture(m and m.icon or 134400)
    row.name:SetText(m and m.name or "?")
    row.name:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
end
function UI:refreshSimplePortfolio(r)
    local c = self.c
    if not F.NativeLayout.simple(self) then
        self.portfolioSimple:Hide()
        return
    end
    self.portfolioSimple:Show()
    local now = c.api.clock()
    local week = 0
    for _, sale in ipairs(r.salesHistory or {}) do
        if now - (sale.at or 0) <= 7 * 86400 then
            week = week + (sale.profit or 0)
        end
    end
    self.portfolioSummary:SetText(
        L("Money: ", "Money: ")
            .. U.money(c.api.wallet())
            .. "     "
            .. L("Items worth: ", "Items worth: ")
            .. U.money(r.stock)
            .. "     "
            .. L("Closed trade profit in 7 days: ", "Closed trade profit in 7 days: ")
            .. U.money(week)
    )
    local pending = {}
    for _, op in pairs(self.c.db.pending or {}) do
        if op.owner == c.api.owner() and (op.status == "unknown" or op.status == "bid") then
            pending[#pending + 1] = op
        end
    end
    table.sort(pending, function(a, b)
        return (a.at or 0) < (b.at or 0)
    end)
    local pages = math.max(1, math.ceil(#r.positions / PORTFOLIO_ROWS))
    local page = math.max(1, math.min(pages, self.portfolioSimplePage or 1))
    self.portfolioSimplePage = page
    self.portfolioSimplePageText:SetText(page .. " / " .. pages)
    self.portfolioPrev:SetEnabled(page > 1)
    self.portfolioNextPage:SetEnabled(page < pages)
    if #r.positions == 0 then
        self.portfolioEmpty:Show()
    else
        self.portfolioEmpty:Hide()
    end
    for i, row in ipairs(self.portfolioRows) do
        local position = r.positions[(page - 1) * PORTFOLIO_ROWS + i]
        if position then
            local key = U.fromKey(position.key)
            row.itemKey = key
            setItem(row, key)
            row.qty:SetText(position.qty)
            row.cost:SetText(U.money(position.cost))
            local vendor = key and (key.itemSuffix or 0) == 0 and U.vendor(key.itemID)
            local price = key and c:price(key)
            local rule = key and c:rule(key) or {}
            local advice
            if vendor and vendor * position.qty >= position.cost then
                advice = string.format(
                    L("Sell to a vendor: %s", "Sell to a vendor: %s"),
                    U.money(vendor * position.qty)
                )
                row.advice:SetTextColor(0.3, 1, 0.3)
            elseif price then
                local gross = U.floor(price * position.qty)
                local net = F.Market.net(gross, rule.fee, rule.reserve, rule.minFee) - (rule.extraCost or 0)
                if net > position.cost then
                    advice =
                        string.format(L("List at %s each", "List at %s each"), U.money(price))
                    row.advice:SetTextColor(0.3, 1, 0.3)
                else
                    advice = L(
                        "Wait: it sells below your cost now",
                        "Wait: it sells below your cost now"
                    )
                    row.advice:SetTextColor(1, 0.82, 0)
                end
            else
                advice = L("No price — press Sell", "No price — press Sell")
                row.advice:SetTextColor(0.7, 0.7, 0.7)
            end
            row.advice:SetText(advice)
            row:Show()
        else
            row.itemKey = nil
            row:Hide()
        end
    end
    if #pending == 0 then
        self.portfolioPendingTitle:Hide()
        self.portfolioPendingPanel:Hide()
        self.portfolioNoPending:Show()
    else
        self.portfolioPendingTitle:Show()
        self.portfolioPendingPanel:Show()
        self.portfolioNoPending:Hide()
    end
    for i, row in ipairs(self.portfolioPending) do
        local op = pending[i]
        row.op = op
        if op then
            setItem(row, U.fromKey(op.key))
            row.qty:SetText(op.qty)
            row.cost:SetText(U.money(op.total))
            row.advice:SetText("")
            row:Show()
        else
            row:Hide()
        end
    end
end
local function columnText(parent, font, x, width, justify)
    local f = parent:CreateFontString(nil, "OVERLAY", font)
    f:SetPoint("LEFT", parent, "LEFT", x, 0)
    f:SetWidth(width)
    f:SetJustifyH(justify or "LEFT")
    f:SetWordWrap(false)
    F.Locale.font(f, 12)
    return f
end
local STAT_COLUMNS = { { 8, 90 }, { 100, 50 }, { 155, 100 }, { 260, 100 }, { 365, 70 }, { 440, 110 } }
-- Analytics → Sales statistics: per-period results, best items and plain advice.
function UI:createStatsPage(page)
    local titles = {
        L("Period", "Period"),
        L("Sales", "Sales"),
        L("Revenue", "Revenue"),
        L("Closed P/L", "Closed P/L"),
        L("Return", "Return"),
        L("Sells in", "Sells in"),
    }
    for i, column in ipairs(STAT_COLUMNS) do
        local header = F.NativeLayout.header(page, titles[i])
        header:SetPoint("TOPLEFT", page, "TOPLEFT", column[1], 0)
        header:SetSize(column[2], 22)
    end
    local table_ = insetPanel(page, 24, 3 * 40 + 8)
    self.statRows = {}
    for i = 1, 3 do
        local row = CreateFrame("Frame", nil, table_)
        row:SetPoint("TOPLEFT", table_, "TOPLEFT", 4, -4 - (i - 1) * 40)
        row:SetPoint("TOPRIGHT", table_, "TOPRIGHT", -4, -4 - (i - 1) * 40)
        row:SetHeight(23)
        local stripe = row:CreateTexture(nil, "BACKGROUND", nil, 2)
        stripe:SetAtlas("auctionhouse-rowstripe-1")
        stripe:SetAllPoints()
        stripe:SetAlpha(i % 2 == 0 and 0.8 or 0.3)
        row.cells = {}
        for c, column in ipairs(STAT_COLUMNS) do
            row.cells[c] = columnText(
                row,
                c == 1 and "GameFontNormal" or "GameFontHighlight",
                column[1] - 4,
                column[2],
                c == 1 and "LEFT" or "RIGHT"
            )
        end
        row:SetHeight(39)
        for c, column in ipairs(STAT_COLUMNS) do
            row.cells[c]:ClearAllPoints()
            row.cells[c]:SetPoint("TOPLEFT", row, "TOPLEFT", column[1] - 4, -2)
        end
        row.summary = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.summary:SetPoint("TOPLEFT", row, "TOPLEFT", 96, -21)
        row.summary:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -21)
        row.summary:SetJustifyH("LEFT")
        F.Locale.font(row.summary, 10)
        self.statRows[i] = row
    end
    local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -160)
    F.Locale.font(title, 12)
    title:SetText(L("MOST PROFITABLE ITEMS · 30 days", "MOST PROFITABLE ITEMS · 30 days"))
    local list = insetPanel(page, 178, 5 * 22 + 8)
    self.statTop = {}
    for i = 1, 5 do
        local row = itemRow(list, i, 22)
        row.advice:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        self.statTop[i] = row
    end
    self.statTips = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.statTips:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -300)
    self.statTips:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, -300)
    self.statTips:SetJustifyH("LEFT")
    self.statTips:SetJustifyV("TOP")
    F.Locale.font(self.statTips, 12)
end
function UI:refreshStats()
    if not self.statRows then
        return
    end
    local st = F.Stats.compute(self.c)
    for i, row in ipairs(self.statRows) do
        local p = st.periods[i]
        row.summary:SetText(
            string.format(
                L("Expenses: %s · net: %s", "Expenses: %s · net: %s"),
                U.money(p.expenses or 0),
                U.money(p.netProfit or p.profit)
            )
        )
        row.cells[1]:SetText(p.label)
        row.cells[2]:SetText(p.sales)
        row.cells[3]:SetText(U.money(p.revenue))
        row.cells[4]:SetText((p.profit >= 0 and "+" or "") .. U.money(p.profit))
        row.cells[4]:SetTextColor(p.profit >= 0 and 0.3 or 1, p.profit >= 0 and 1 or 0.35, 0.3)
        row.cells[5]:SetText(p.roi and string.format("%d%%", math.floor(p.roi * 100 + 0.5)) or "—")
        row.cells[6]:SetText(p.heldDays and string.format(L("%.1f d", "%.1f d"), p.heldDays) or "—")
    end
    for i, row in ipairs(self.statTop) do
        local k = st.top[i]
        if k then
            local key = U.fromKey(k.key)
            local m = key and F.ItemDisplay.metadata(key)
            row.icon:SetTexture(m and m.icon or 134400)
            row.name:SetText(m and m.name or k.key)
            row.qty:SetText(k.units)
            row.cost:SetText("")
            row.advice:SetText((k.profit >= 0 and "+" or "") .. U.money(k.profit))
            row.advice:SetTextColor(k.profit >= 0 and 0.3 or 1, k.profit >= 0 and 1 or 0.35, 0.3)
            row:Show()
        else
            row:Hide()
        end
    end
    self.statTips:SetText(table.concat(st.tips, "\n"))
    self.sections.workbench.split.pages.stats.ffMinHeight = 316 + self.statTips:GetStringHeight()
end
-- Portfolio → My auctions: are my listings still the cheapest?
local function pager(ui, parent, prefix, refresh)
    ui[prefix .. "Page"] = 1
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    F.Locale.font(label, 10)
    label:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -68, -6)
    ui[prefix .. "Pages"] = label
    for _, v in ipairs({ { "Previous", "<", -1, -36 }, { "Next", ">", 1, -4 } }) do
        local delta = v[3]
        local b = smallButton(parent, 28, v[2], function()
            ui[prefix .. "Page"] = math.max(1, ui[prefix .. "Page"] + delta)
            refresh(ui)
        end)
        b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", v[4], -2)
        ui.actions[prefix .. v[1]] = b
    end
end
local function pageOffset(ui, prefix, count, size)
    local total = math.max(1, math.ceil(count / size))
    local page = math.min(total, math.max(1, ui[prefix .. "Page"] or 1))
    ui[prefix .. "Page"] = page
    ui[prefix .. "Pages"]:SetText(string.format(L("Page %d / %d", "Page %d / %d"), page, total))
    ui.actions[prefix .. "Previous"]:SetEnabled(page > 1)
    ui.actions[prefix .. "Next"]:SetEnabled(page < total)
    return (page - 1) * size
end
function UI:createOwnedPage(page)
    local c = self.c
    local ui = self
    self.actions.ownedRefresh = smallButton(
        page,
        170,
        L("Refresh my auctions", "Refresh my auctions"),
        function()
            c:refreshOwned()
            ui:refresh()
        end
    )
    self.actions.ownedRefresh:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    self.ownedInfo = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.ownedInfo:SetPoint("LEFT", self.actions.ownedRefresh, "RIGHT", 10, 0)
    F.Locale.font(self.ownedInfo, 11)
    for _, h in ipairs({
        { 8, 190, L("Item", "Item") },
        { 200, 42, L("Qty", "Qty") },
        { 245, 96, L("My price", "My price") },
        { 345, 210, L("Status", "Status") },
    }) do
        local header = F.NativeLayout.header(page, h[3])
        header:SetPoint("TOPLEFT", page, "TOPLEFT", h[1], -28)
        header:SetSize(h[2], 22)
    end
    local list = insetPanel(page, 52, 8 * 26 + 8)
    self.ownedEmpty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    self.ownedEmpty:SetPoint("CENTER", list, "CENTER")
    F.Locale.font(self.ownedEmpty, 12)
    pager(self, page, "owned", UI.refreshOwnedPage)
    self.ownedInfo:SetWidth(180)
    self.ownedInfo:SetWordWrap(true)
    self.ownedRows = {}
    for i = 1, 8 do
        local row = itemRow(list, i, 26)
        row.advice:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        self.ownedRows[i] = row
    end
    local hint = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -270)
    hint:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, -270)
    hint:SetJustifyH("LEFT")
    F.Locale.font(hint, 11)
    hint:SetText(
        L(
            "Snapshot comparisons may be stale. Recheck the market before cancelling or relisting; no sale is guaranteed.",
            "Snapshot comparisons may be stale. Recheck the market before cancelling or relisting; no sale is guaranteed."
        )
    )
end
function UI:refreshOwnedPage()
    if not self.ownedRows then
        return
    end
    local c = self.c
    local list = c.owned or {}
    self.ownedInfo:SetText(
        c.ownedAt
                and string.format(
                    L("Listings snapshot: %d s ago", "Listings snapshot: %d s ago"),
                    math.max(0, c.api.clock() - c.ownedAt)
                )
            or L("Press to check your listings", "Press to check your listings")
    )
    if #list == 0 then
        self.ownedEmpty:SetText(
            c.ownedAt and L("You have no auctions listed.", "You have no auctions listed.")
                or L("The list is not loaded yet.", "The list is not loaded yet.")
        )
        self.ownedEmpty:Show()
    else
        self.ownedEmpty:Hide()
    end
    local offset = pageOffset(self, "owned", #list, #self.ownedRows)
    for i, row in ipairs(self.ownedRows) do
        local a = list[offset + i]
        if a then
            local m = F.ItemDisplay.metadata(a.key, a.link)
            row.icon:SetTexture(m and m.icon or 134400)
            row.name:SetText(m and m.name or "?")
            row.qty:SetText(a.qty)
            local unit = a.qty > 0 and math.floor((a.buyout or 0) / a.qty) or 0
            row.cost:SetText(U.money(unit))
            local status, price = c:ownedStatus(a)
            if status == "undercut" and price <= 100 then
                row.advice:SetText(
                    L(
                        "No lower legal price — review market",
                        "No lower legal price — review market"
                    )
                )
                row.advice:SetTextColor(1, 0.82, 0)
            elseif status == "undercut" then
                row.advice:SetText(
                    string.format(
                        L("Snapshot lower: %s — list at %s", "Snapshot lower: %s — list at %s"),
                        U.money(price),
                        U.money(F.Market.priceStep(price, true))
                    )
                )
                row.advice:SetTextColor(1, 0.35, 0.3)
            elseif status == "cheapest" then
                row.advice:SetText(
                    L(
                        "Lowest in snapshot; sale not guaranteed",
                        "Lowest in snapshot; sale not guaranteed"
                    )
                )
                row.advice:SetTextColor(0.3, 1, 0.3)
            elseif status == "sold" then
                row.advice:SetText(
                    L(
                        "Sold — collect the money from mail",
                        "Sold — collect the money from mail"
                    )
                )
                row.advice:SetTextColor(1, 0.82, 0)
            else
                row.advice:SetText(
                    L(
                        "No data — scan the auction house",
                        "No data — scan the auction house"
                    )
                )
                row.advice:SetTextColor(0.7, 0.7, 0.7)
            end
            row:Show()
        else
            row:Hide()
        end
    end
end
-- Trading → Sell what you bought: pick an item from the bags, check its price, list it.
local SELL_ROWS = 6
local DURATIONS = { { 1, "12" }, { 2, "24" }, { 3, "48" } }
function UI:createSellPanel(sell)
    local c = self.c
    local ui = self
    local title = sell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", sell, "TOPLEFT", 10, -8)
    F.Locale.font(title, 12)
    title:SetText(
        L(
            "SELL WHAT YOU BOUGHT · pick an item from your bags",
            "SELL WHAT YOU BOUGHT · pick an item from your bags"
        )
    )
    local list = insetPanel(sell, 26, SELL_ROWS * 24 + 8)
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", sell, "TOPLEFT", 6, -26)
    list:SetPoint("TOPRIGHT", sell, "TOPRIGHT", -6, -26)
    self.sellEmpty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    self.sellEmpty:SetPoint("CENTER", list, "CENTER")
    self.sellEmpty:SetWidth(420)
    F.Locale.font(self.sellEmpty, 12)
    self.sellEmpty:SetText(
        L(
            "No purchased items in your bags. Collect them from the mail.",
            "No purchased items in your bags. Collect them from the mail."
        )
    )
    title:SetWidth(300)
    title:SetWordWrap(false)
    pager(self, sell, "sell", UI.refreshSell)
    self.sellRows = {}
    for i = 1, SELL_ROWS do
        local row = itemRow(list, i, 24)
        row.advice:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        local click = CreateFrame("Button", nil, row)
        click:SetAllPoints()
        click:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        click:SetScript("OnClick", function()
            ui:selectSellItem(row.entry)
        end)
        row.click = click
        self.sellRows[i] = row
    end
    self.sellSelected = sell:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.sellSelected:SetPoint("TOPLEFT", sell, "TOPLEFT", 10, -186)
    self.sellSelected:SetPoint("TOPRIGHT", sell, "TOPRIGHT", -10, -186)
    self.sellSelected:SetJustifyH("LEFT")
    F.Locale.font(self.sellSelected, 12)
    self.fields.cardQty = CreateFrame("EditBox", nil, sell, "InputBoxTemplate")
    self.fields.cardPrice = CreateFrame("EditBox", nil, sell, "InputBoxTemplate")
    local function box(e, x, width, label)
        local t = sell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t:SetPoint("TOPLEFT", sell, "TOPLEFT", x, -208)
        F.Locale.font(t, 10)
        t:SetText(label)
        e:SetPoint("TOPLEFT", sell, "TOPLEFT", x + 4, -222)
        e:SetSize(width, 22)
        e:SetAutoFocus(false)
        e:SetFontObject("GameFontHighlightSmall")
        F.Locale.font(e, 12)
        e:SetScript("OnEscapePressed", function(self_)
            self_:ClearFocus()
        end)
        e:SetScript("OnEnterPressed", function(self_)
            self_:ClearFocus()
        end)
    end
    box(self.fields.cardQty, 10, 60, L("Quantity", "Quantity"))
    box(self.fields.cardPrice, 82, 100, L("Unit price, gold", "Unit price, gold"))
    self.fields.cardQty:SetText("1")
    self.fields.cardPrice:SetText("")
    self.sellDuration = 2
    local function durationLabel()
        for _, d in ipairs(DURATIONS) do
            if d[1] == ui.sellDuration then
                return string.format(L("Duration: %s h", "Duration: %s h"), d[2])
            end
        end
    end
    self.actions.cardSuggest = smallButton(sell, 130, L("Suggest price", "Suggest price"), function()
        ui:suggestSellPrice()
    end)
    self.actions.cardSuggest:SetPoint("TOPLEFT", sell, "TOPLEFT", 196, -222)
    self.actions.cardDuration = smallButton(sell, 100, "", function(b)
        ui.sellDuration = ui.sellDuration % 3 + 1
        b:SetText(durationLabel())
    end)
    self.actions.cardDuration:SetText(durationLabel())
    self.actions.cardDuration:SetPoint("LEFT", self.actions.cardSuggest, "RIGHT", 6, 0)
    self.actions.cardPost = smallButton(sell, 120, L("List", "List"), function()
        local item = ui.sellItem
        c:post(item, tonumber(ui.fields.cardQty:GetText()), U.copper(ui.fields.cardPrice:GetText()), ui.sellDuration)
        ui:refresh()
    end)
    self.actions.cardPost:SetPoint("LEFT", self.actions.cardDuration, "RIGHT", 6, 0)
    self.cardBags = sell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.cardBags:SetPoint("TOPLEFT", sell, "TOPLEFT", 10, -254)
    self.cardBags:SetPoint("TOPRIGHT", sell, "TOPRIGHT", -10, -254)
    self.cardBags:SetJustifyH("LEFT")
    F.Locale.font(self.cardBags, 11)
end
-- Items in the bags, grouped by item; purchased (portfolio) items first.
function UI:sellCandidates()
    local c = self.c
    local held = {}
    for _, position in ipairs(c:summary().positions or {}) do
        held[position.key] = position
    end
    local groups, order = {}, {}
    local ok, items = pcall(c.api.bagItems or function()
        return {}
    end)
    for _, item in ipairs(ok and items or {}) do
        local id = U.key(item.key)
        if id then
            local g = groups[id]
            if not g then
                g = { key = item.key, link = item.link, qty = 0, slots = {}, bought = held[id] }
                if not g.bought then
                    for k, position in pairs(held) do
                        if F.Adapters.sameListing(U.fromKey(k), item.key) then
                            g.bought = position
                        end
                    end
                end
                groups[id] = g
                order[#order + 1] = g
            end
            g.qty = g.qty + (item.qty or 0)
            g.slots[#g.slots + 1] = item
        end
    end
    table.sort(order, function(a, b)
        if (a.bought and true or false) ~= (b.bought and true or false) then
            return a.bought and true or false
        end
        return U.key(a.key) < U.key(b.key)
    end)
    local out = {}
    for _, g in ipairs(order) do
        if g.bought then
            out[#out + 1] = g
        end
    end
    return out
end
function UI:selectSellItem(entry)
    if not entry then
        return
    end
    local c = self.c
    self.sellEntry = entry
    table.sort(entry.slots, function(a, b)
        return (a.qty or 0) > (b.qty or 0)
    end)
    self.sellItem = entry.slots[1]
    self.fields.cardQty:SetText(tostring(self.sellItem and self.sellItem.qty or 1))
    self.fields.cardPrice:SetText("")
    self:suggestSellPrice()
end
-- Uses a recent exact search of this item, or starts one and fills the price when it arrives.
function UI:suggestSellPrice()
    local c = self.c
    local item = self.sellItem
    if not item then
        c:notify("post_no_item")
        return
    end
    if c:postReady(item) then
        local price = F.Market.salePrice(c.plan, tonumber(self.fields.cardQty:GetText()) or 1)
        if price then
            self.fields.cardPrice:SetText(U.gold(price))
        end
        self.sellPricePending = nil
        return
    end
    self.sellPricePending = U.key(item.key)
    c.selection = { key = U.copy(item.key), link = item.link, mode = "flip" }
    c:search(U.copy(item.key))
    self:refresh()
end
function UI:refreshSell(p)
    if not self.sellRows then
        return
    end
    local c = self.c
    local list = self:sellCandidates()
    if #list == 0 then
        self.sellEmpty:Show()
    else
        self.sellEmpty:Hide()
    end
    local selectedId = self.sellEntry and U.key(self.sellEntry.key)
    local previous = self.sellItem
    local current
    local stillThere = false
    for _, g in ipairs(list) do
        if U.key(g.key) == selectedId then
            stillThere = true
            self.sellEntry = g
            for _, slot in ipairs(g.slots or {}) do
                if previous and slot.bag == previous.bag and slot.slot == previous.slot then
                    current = slot
                    break
                end
                if not current or (slot.qty or 0) > (current.qty or 0) then
                    current = slot
                end
            end
            break
        end
    end
    self.sellItem = current
    if
        previous
        and (
            not current
            or previous.bag ~= current.bag
            or previous.slot ~= current.slot
            or U.key(previous.key) ~= U.key(current.key)
        )
    then
        c.postPending = nil
    end
    local quantity = tonumber(self.fields.cardQty:GetText())
    if current and U.finite(quantity) and quantity > current.qty then
        self.fields.cardQty:SetText(tostring(current.qty))
        c.postPending = nil
    end
    local offset = pageOffset(self, "sell", #list, SELL_ROWS)
    for i, row in ipairs(self.sellRows) do
        local g = list[offset + i]
        row.entry = g
        if g then
            local m = F.ItemDisplay.metadata(g.key, g.link)
            row.icon:SetTexture(m and m.icon or 134400)
            row.name:SetText(m and m.name or "?")
            row.qty:SetText(g.qty)
            row.cost:SetText(g.bought and U.money(math.floor(g.bought.cost / math.max(1, g.bought.qty))) or "")
            row.advice:SetText(
                U.key(g.key) == selectedId and L("selected", "selected")
                    or L("click to sell", "click to sell")
            )
            row.advice:SetTextColor(
                U.key(g.key) == selectedId and 0.3 or 1,
                U.key(g.key) == selectedId and 1 or 0.82,
                0.3
            )
            stillThere = stillThere or U.key(g.key) == selectedId
            row:Show()
        else
            row:Hide()
        end
    end
    if self.sellEntry and not stillThere then
        self.sellEntry, self.sellItem = nil, nil
    end
    if self.sellPricePending and c.plan and self.sellItem and c:postReady(self.sellItem) then
        local price = F.Market.salePrice(c.plan, tonumber(self.fields.cardQty:GetText()) or 1)
        if price then
            self.fields.cardPrice:SetText(U.gold(price))
        end
        self.sellPricePending = nil
    end
    local entry = self.sellEntry
    if entry then
        local m = F.ItemDisplay.metadata(entry.key, entry.link)
        local market = c:postReady(self.sellItem) and c.plan.minimum
        self.sellSelected:SetText(
            string.format(L("Selected: %s × %d", "Selected: %s × %d"), m and m.name or "?", entry.qty)
                .. (
                    market
                        and string.format(
                            L(" · exact snapshot minimum: %s", " · exact snapshot minimum: %s"),
                            U.money(market)
                        )
                    or ""
                )
        )
    else
        self.sellSelected:SetText(L("No item selected", "No item selected"))
    end
    self.actions.cardSuggest:SetEnabled(self.sellItem ~= nil and not c.job)
    self.actions.cardPost:SetEnabled(
        self.sellItem ~= nil and c:postReady(self.sellItem) and not c.active and true or false
    )
    local vendor = self.sellItem and (self.sellItem.key.itemSuffix or 0) == 0 and U.vendor(self.sellItem.key.itemID)
    local typed = U.copper(self.fields.cardPrice:GetText())
    local vendorBetter = vendor and typed and typed * 0.95 < vendor
    self.cardBags:SetText(
        vendorBetter
                and string.format(
                    L(
                        "A vendor pays more (%s each) — sell this item to a vendor.",
                        "A vendor pays more (%s each) — sell this item to a vendor."
                    ),
                    U.money(vendor)
                )
            or self.sellPricePending and L("Checking current prices…", "Checking current prices…")
            or c.postPending and L(
                "Press List again to confirm.",
                "Press List again to confirm."
            )
            or L(
                "Suggests a legal silver step below the snapshot minimum, respecting cost, fee, reserve and extra costs.",
                "Suggests a legal silver step below the snapshot minimum, respecting cost, fee, reserve and extra costs."
            )
    )
end
function UI:refreshCard(p, warningList)
    local c = self.c
    local simple = F.NativeLayout.simple(self)
    local cardFrames = { self.tradeCard, self.tradeSell }
    if not simple then
        self.tradeContent:Show()
        self.actions.tradeMode:Show()
        self.tradeItem:Show()
        for _, f in ipairs(cardFrames) do
            f:Hide()
        end
        return
    end
    self.tradeContent:Hide()
    self.actions.tradeMode:Hide()
    self.tradeItem:Hide()
    for _, f in ipairs(cardFrames) do
        f:Show()
    end
    local yellow, green, red = { 1, 0.82, 0 }, { 0.3, 1, 0.3 }, { 1, 0.35, 0.3 }
    local verdict, color, note
    local rows = {}
    local active = c.active and c.active.status
    local key = (p and p.key) or (c.selection and c.selection.key)
    local bought = c.lastPurchase
    if bought and not (key and U.key(bought.key) == U.key(key)) then
        bought = nil
    end
    if active == "quoted" then
        verdict, color =
            L(
                "Price confirmed — press 2. Confirm purchase",
                "Price confirmed — press 2. Confirm purchase"
            ),
            yellow
    elseif active == "awaiting" or active == "quote" then
        verdict, color = L("Purchase in progress…", "Purchase in progress…"), yellow
    elseif active == "unknown" then
        verdict, color =
            L("Could not confirm the purchase", "Could not confirm the purchase"), red
        note = L(
            "If the chat said You won an auction, the purchase went through. Mark it in Portfolio with Purchase completed.",
            "If the chat said You won an auction, the purchase went through. Mark it in Portfolio with Purchase completed."
        )
    elseif bought and not p then
        verdict =
            string.format(L("Bought: %d for %s", "Bought: %d for %s"), bought.qty, U.money(bought.total))
        color = green
        rows = {
            {
                L("2. Collect from the mailbox", "2. Collect from the mailbox"),
                L("mailbox", "mailbox"),
            },
            {
                L("3. Sell", "3. Sell"),
                c.mode == "vendor" and L("to any vendor", "to any vendor")
                    or L("panel below", "panel below"),
            },
        }
    elseif not p then
        if c.selection then
            verdict, color =
                L(
                    "Checking current auction listings…",
                    "Checking current auction listings…"
                ),
                yellow
            note = L(
                "The addon re-reads this item's prices so you never buy on stale data. It usually takes 1-3 seconds. If nothing changes, press Check price again.",
                "The addon re-reads this item's prices so you never buy on stale data. It usually takes 1-3 seconds. If nothing changes, press Check price again."
            )
        else
            verdict, color =
                L(
                    "Pick a deal on the Auction tab",
                    "Pick a deal on the Auction tab"
                ),
                yellow
            note = L(
                "Click any bright row with a green amount — a step-by-step plan appears here.",
                "Click any bright row with a green amount — a step-by-step plan appears here."
            )
        end
    elseif p.canBuy then
        verdict = string.format(L("Worth it: +%s net", "Worth it: +%s net"), U.money(p.profit))
        color = green
        local unit = p.qty > 0 and math.floor(p.cost / p.qty) or 0
        rows[1] = {
            L("1. Buy on the auction house", "1. Buy on the auction house"),
            string.format("%d × %s = %s", p.qty, U.money(unit), U.money(p.cost)),
        }
        rows[2] = {
            L("2. Collect from the mailbox", "2. Collect from the mailbox"),
            L("mailbox", "mailbox"),
        }
        if p.mode == "vendor" then
            rows[3] = {
                L("3. Sell to any vendor", "3. Sell to any vendor"),
                U.money(math.floor(p.qty * (p.target or 0))),
            }
            note = L(
                "No price risk: vendors always pay the same.",
                "No price risk: vendors always pay the same."
            )
        else
            rows[3] = {
                L("3. List on the auction house", "3. List on the auction house"),
                string.format(L("%s each", "%s each"), U.money(p.target)),
            }
            if p.basis == "listings" then
                note = string.format(
                    L(
                        "Snapshot asking price: about %s. No price history yet; recheck before trading.",
                        "Snapshot asking price: about %s. No price history yet; recheck before trading."
                    ),
                    U.money(p.reference)
                )
            else
                note = L(
                    "This item usually sells higher. Selling may take a while.",
                    "This item usually sells higher. Selling may take a while."
                )
            end
        end
        rows[4] = {
            L("Net profit after fees", "Net profit after fees"),
            "+" .. U.money(p.profit),
            true,
        }
    else
        verdict, color = L("Not worth buying right now", "Not worth buying right now"), red
        local why = warningList(p)
        local hints = {}
        for _, reason in ipairs(p.reasons or {}) do
            if reason == "history" then
                hints[#hints + 1] = L(
                    "The addon does not know this item's usual price yet. Scan the auction house a few times on different days; meanwhile earn with Sell to vendors.",
                    "The addon does not know this item's usual price yet. Scan the auction house a few times on different days; meanwhile earn with Sell to vendors."
                )
            elseif reason == "budget/price" then
                hints[#hints + 1] = L(
                    "Listings cost more than the profitable price, or there is not enough money for the deal.",
                    "Listings cost more than the profitable price, or there is not enough money for the deal."
                )
            elseif reason == "margin" then
                hints[#hints + 1] = L(
                    "The gain is too small to be worth the risk.",
                    "The gain is too small to be worth the risk."
                )
            elseif reason == "exit" then
                hints[#hints + 1] = L(
                    "There is no known selling price. Pick another item.",
                    "There is no known selling price. Pick another item."
                )
            end
        end
        rows[1] = { L("Reason", "Reason"), why ~= "" and why or "?" }
        note = table.concat(hints, "\n")
    end
    local metadata = key and F.ItemDisplay.metadata(key, p and p.link or (c.selection and c.selection.link))
    self.cardMetadata = metadata
    self.cardIcon:SetTexture(metadata and metadata.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    local quality = metadata and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[metadata.quality]
    self.cardName:SetText(metadata and metadata.name or L("No deal selected", "No deal selected"))
    self.cardName:SetTextColor(quality and quality.r or 1, quality and quality.g or 0.82, quality and quality.b or 0)
    self.cardVerdict:SetText(verdict)
    self.cardVerdict:SetTextColor(color[1], color[2], color[3])
    for i, row in ipairs(self.cardRows) do
        local r = rows[i]
        if r then
            row.label:SetText(r[1])
            row.value:SetText(r[2])
            if r[3] then
                row.value:SetTextColor(0.3, 1, 0.3)
            else
                row.value:SetTextColor(1, 1, 1)
            end
            row:Show()
        else
            row:Hide()
        end
    end
    self.cardFreshness:SetText(
        p
                and U.finite(p.at)
                and string.format(
                    L(
                        "Snapshot %d s ago · recheck before trading",
                        "Snapshot %d s ago · recheck before trading"
                    ),
                    math.max(0, c.api.clock() - p.at)
                )
            or L("No exact price snapshot yet", "No exact price snapshot yet")
    )
    self.cardSteps:SetText(note or "")
    self.actions.cardBuy:SetEnabled(self.actions.buy:IsEnabled())
    self.actions.cardConfirm:SetEnabled(self.actions.confirm:IsEnabled())
    self.actions.cardRecheck:SetEnabled(c.selection and not c.job and not c.active and true or false)
    self.actions.cardCancel:SetEnabled(active == "quoted" or active == "quote")
    self:refreshSell(p)
end
function UI:refresh()
    if self.refreshing then
        return
    end
    self.refreshing = true
    local c = self.c
    c.plannerVisible = self.frame:IsShown() and self.section == "workbench"
    c.dealPageVisible = self.frame:IsShown() and self.section == "deals" and not self.liveOnly
    local radar = c.radar
    self.actions.live:SetText(
        radar and radar.enabled and (radar.paused and L("Resume", "Resume") or L("Pause", "Pause"))
            or L("Live", "Live")
    )
    self.header:SetText(
        c.api.scope()
            .. "  ·  "
            .. U.money(c.api.wallet())
            .. L("  · reserved ", "  · reserved ")
            .. U.money(c:reserved())
    )
    local message = messages()[c.message] or F.Locale.message(c.message)
    if not F.Progress.isFailure(c.message) and c.fullJob and not c.fullJob.waiting then
        message = L("Processing: ", "Processing: ") .. c.fullJob.index .. " / " .. c.fullJob.total
    end
    if
        not F.Progress.isFailure(c.message)
        and radar
        and radar.enabled
        and self.section == "deals"
        and not (c.fullJob and not c.fullJob.waiting)
    then
        message = L(
            "Live search: one listing check per second · full scan every 15 min.",
            "Live search: one listing check per second · full scan every 15 min."
        )
        local wait = 900 - (c.api.clock() - (c.db.lastReplicate or 0))
        if wait > 0 and #c.candidates < 200 then
            message = message
                .. string.format(
                    L(" Full scan in %d min.", " Full scan in %d min."),
                    math.ceil(wait / 60)
                )
        end
    end
    if not F.Progress.isFailure(c.message) and c:npcRemaining() and self.section == "deals" then
        message = L(
            "Sell to vendors: you can still spend today ",
            "Sell to vendors: you can still spend today "
        ) .. U.money(c:npcRemaining())
    end
    self.status:SetText(message)
    local fn = self.refreshers[self.section]
    local ok, err = true, nil
    if fn then
        ok, err = pcall(fn)
    end
    if ok then
    end
    F.NativeLayout.fitScrolling(self)
    self:updateProgress(0)
    self.refreshing = false
    if not ok then
        error(err)
    end
end
