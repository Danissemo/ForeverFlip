local F = ForeverFlip
local U = F.Util
local UI = {}
F.UI = UI
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
        replicate_cooldown = L(
            "Full scan cooldown: approximately 15 minutes.",
            "Full scan cooldown: approximately 15 minutes."
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
        sort = "price",
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
        self:refresh()
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
    toolbar("search", 356, 85, L("Search", "Search"), function()
        local key, err = F.Adapters.keyFromInput(item:GetText())
        if key then
            if c:search(key) then
                self:show("trade")
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
            c:notify(err)
        end
    end)
    item:SetScript("OnEnterPressed", function(e)
        e:ClearFocus()
        self.actions.search:Click()
    end)
    toolbar("fullScan", 446, 115, L("Full scan", "Full scan"), function()
        c:fullScan()
        self:show("deals")
    end)
    toolbar("quickPlan", 566, 125, L("Planner", "Planner"), function()
        self.actions.easyBuild:Click()
    end)
    toolbar("stop", 696, 75, L("Stop", "Stop"), function()
        c:stop()
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
    local function routeAdvice(line)
        if not line then
            return
        end
        c:stop()
        c.overrides = {
            maxQty = math.min(line.qty, c.overrides and c.overrides.maxQty or math.huge),
            budget = math.min(line.cost, c.overrides and c.overrides.budget or math.huge),
        }
        c.mode = line.mode
        self.fields.item:SetText(U.key(line.key))
        self.fields.tradeQty:SetText(tostring(c.overrides.maxQty))
        self.fields.tradeBudget:SetText(U.gold(c.overrides.budget))
        c:search(line.key)
        self:show("trade")
    end
    local function buildAdvice(profile)
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
            if c.job or c.fullJob or c.active then
                c:notify("search_busy")
                return
            end
            c.advisorProfile = nil
            c:invalidate()
            self.allocation = c:allocate({ budget = budget, riskCap = risk, drop = drop / 100 })
            self.advicePage = 1
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
            rowButtons[i] = F.ItemDisplay.row(b, 0, 140 + (i - 1) * 44, 795, function()
                routeAdvice(self.allocation and self.allocation.lines[((self.advicePage or 1) - 1) * 8 + index])
            end)
            rowButtons[i]:SetSize(795, 40)
            self.actions["adviceRow" .. i] = rowButtons[i]
        end
        action("advicePrevious", b, 0, 503, 170, L("← Previous", "← Previous"), function()
            self.advicePage = math.max(1, (self.advicePage or 1) - 1)
            self:refresh()
        end)
        action("adviceNext", b, 185, 503, 170, L("Next →", "Next →"), function()
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
            local a = self.allocation
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
            local stats = F.Workbench.performance(summary, c.api.clock())
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
                    summary.salesHistory,
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
        text(b, 0, 0, 820, L("YOUR TRADING DAY", "YOUR TRADING DAY"), "GameFontNormalLarge")
        action("overviewAdvice", b, 0, 35, 250, L("Suggest purchases", "Suggest purchases"), function()
            buildAdvice(db.ui.advisorProfile or "balanced")
        end)
        text(
            b,
            270,
            40,
            535,
            L(
                "Full scan → plan → verify item → confirm",
                "Full scan → plan → verify item → confirm"
            )
        )
        local overview = text(b, 0, 85, 810, "", "GameFontNormal")
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
                    .. "\n\n"
                    .. L(
                        "Next steps:\n1. Scan or select an item.\n2. Review price and budget in Trading.\n3. Confirm a purchase with a separate click.\n4. Collect items and choose a sale price.\n5. Reconcile completed trades in Portfolio.",
                        "Next steps:\n1. Scan or select an item.\n2. Review price and budget in Trading.\n3. Confirm a purchase with a separate click.\n4. Collect items and choose a sale price.\n5. Reconcile completed trades in Portfolio."
                    )
            )
        end
        action("toDeals", b, 0, 410, 170, L("Find deals", "Find deals"), function()
            self:show("deals")
        end)
        action("toPortfolio", b, 185, 410, 170, L("Reconcile", "Reconcile"), function()
            self:show("portfolio")
        end)
        self.overviewNote = text(
            b,
            0,
            465,
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
        self.refreshers.trade = function()
            local p = c.plan
            self.tradeItem:SetItem(p, p and L("Exact result", "Exact result") or nil)
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
                c.api.isOpen() and c:fresh() and p.canBuy and not c.active and c:reserved() == 0 or false
            )
            self.actions.confirm:SetEnabled(
                c.api.isOpen() and c:fresh() and c.active and c.active.status == "quoted" or false
            )
            self.actions.more:SetEnabled(c.api.isOpen() and p and not p.complete and c.job or false)
            self.bags = {}
            local bagLines = {}
            if c.api.bagItems then
                local ok, items = pcall(c.api.bagItems)
                if ok then
                    for _, item in ipairs(items) do
                        if c.key and U.key(item.key) == U.key(c.key) then
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
        self.refreshers.portfolio = function()
            local r = c:summary()
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
            for i = 1, math.min(6, #r.positions) do
                local p = r.positions[i]
                local key = U.fromKey(p.key)
                local price = key and c:price(key.itemID)
                local age = math.max(0, math.floor((c.api.clock() - (p.at or c.api.clock())) / 86400))
                local actionText = not price and L("no price", "no price")
                    or price * p.qty * 0.93 > p.cost and L("review sale", "review sale")
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
            for i = 1, math.min(3, #self.pendingRows) do
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
            for i = #(db.ledger or {}), math.max(1, #(db.ledger or {}) - 5), -1 do
                local e = db.ledger[i]
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
            for i = 1, math.min(4, #c.mail) do
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
                self:show("trade")
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
            self.shopping = self.toolResult.shopping
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
        self.toolText = text(b, 0, 670, 810, "")
        val("materialIndex", b, 0, 855, 120, L("Material row", "Material row"), "1")
        action(
            "materialSearch",
            b,
            140,
            875,
            250,
            L("Buy material: exact search", "Buy material: exact search"),
            function()
                local m = self.shopping and self.shopping[tonumber(self.fields.materialIndex:GetText())]
                if m then
                    self.fields.item:SetText(tostring(m.id))
                    c:search({ itemID = m.id })
                    self:show("trade")
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
        text(b, 0, 1095, 810, L("Language (reload required)", "Language (reload required)"))
        for i, language in ipairs({
            { "uk", "Українська" },
            { "en", "English" },
            { "auto", "Auto" },
        }) do
            local choice = language[1]
            action("language" .. choice, b, (i - 1) * 175, 1120, 165, language[2], function()
                if F.Locale.choose(choice) then
                    c:notify(
                        L(
                            "Language saved. Use /reload to apply.",
                            "Language saved. Use /reload to apply."
                        )
                    )
                end
            end)
        end
        text(b, 0, 1165, 800, "ForeverFlip " .. F.version)
        self.sections.settings.body:SetHeight(1200)
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
    self:show((db.ui and db.ui.section and db.ui.section ~= "overview") and db.ui.section or "deals")
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
    local r = self.toolResult
    if not r then
        return
    end
    if not r.complete then
        self.toolText:SetText(
            L(
                "Missing input prices/output. Profit unknown.",
                "Missing input prices/output. Profit unknown."
            )
        )
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
        if i <= 5 then
            lines[#lines + 1] = i .. ". " .. U.name(m.id) .. " ×" .. m.qty .. " · " .. U.money(m.cost)
        end
    end
    self.toolText:SetText(table.concat(lines, "\n"))
end
function UI:layout()
    F.NativeLayout.reflow(self)
    if self.section == "history" and not self.refreshing and self.refreshers.history then
        self:refresh()
    end
end
function UI:show(id)
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
    if F.Store.writable(self.c.db) then
        self.c.db.ui.section = id
    end
    self.frame:Show()
    self:refresh()
end
function UI:refresh()
    if self.refreshing then
        return
    end
    self.refreshing = true
    local c = self.c
    self.header:SetText(
        c.api.scope()
            .. "  ·  "
            .. U.money(c.api.wallet())
            .. L("  · reserved ", "  · reserved ")
            .. U.money(c:reserved())
    )
    local message = messages()[c.message] or F.Locale.message(c.message)
    if c.fullJob and not c.fullJob.waiting then
        message = L("Processing: ", "Processing: ") .. c.fullJob.index .. " / " .. c.fullJob.total
    end
    self.status:SetText(message)
    local fn = self.refreshers[self.section]
    local ok, err = true, nil
    if fn then
        ok, err = pcall(fn)
    end
    if ok then
        if self.section == "overview" and self.overviewText then
            local y = 85 + self.overviewText:GetStringHeight() + 20
            self.actions.toDeals:ClearAllPoints()
            self.actions.toDeals:SetPoint("TOPLEFT", self.sections.overview.body, "TOPLEFT", 0, -y)
            self.actions.toPortfolio:ClearAllPoints()
            self.actions.toPortfolio:SetPoint("TOPLEFT", self.sections.overview.body, "TOPLEFT", 185, -y)
            self.overviewNote:ClearAllPoints()
            self.overviewNote:SetPoint("TOPLEFT", self.sections.overview.body, "TOPLEFT", 0, -y - 50)
            self.sections.overview.body:SetHeight(math.max(1100, y + 150))
        end
    end
    self.refreshing = false
    if not ok then
        error(err)
    end
end
