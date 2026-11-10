local F = ForeverFlip
local U = F.Util
local L = F.Locale.text
local P = {}
F.Progress = P
local function result(mode, label, value, done, total)
    return { mode = mode, label = label, value = value, done = done, total = total }
end
local function waiting(label, at, now)
    return result(
        "waiting",
        label .. string.format(L(" · %d s", " · %d s"), math.max(0, math.floor(now - (at or now))))
    )
end
local failures = {
    post_no_item = true,
    post_search = true,
    item_unavailable = true,
    rescan = true,
    throttled = true,
    buy_blocked = true,
    readonly = true,
    auction_closed = true,
    scope_unknown = true,
    post_floor = true,
    post_values = true,
    deposit_unknown = true,
    bid_blocked = true,
    search_busy = true,
    resolve_pending = true,
    tab_error = true,
    replicate_error = true,
    replicate_timeout = true,
    replicate_empty = true,
    search_timeout = true,
    calculation_incomplete = true,
    results_error = true,
    quote_error = true,
    quote_unavailable = true,
    quote_expired = true,
    post_error = true,
    unknown = true,
    ledger_full = true,
}
local done = {
    replicate_done = true,
    plan_ready = true,
    plan_review = true,
    purchase_recorded = true,
    post_sent = true,
    reconciled = true,
    watch_finished = true,
    planner_done = true,
    calculation_done = true,
}
function P.isFailure(message)
    return failures[message] or (type(message) == "string" and message:find("search_error:", 1, true) == 1)
end
function P.state(c)
    if P.isFailure(c.message) then
        return result(
            "error",
            L(
                "Action incomplete — see message above",
                "Action incomplete — see message above"
            ),
            0
        )
    end
    local now = c.api.clock()
    if c.selectionRequest then
        return waiting(
            L("Loading selected item data", "Loading selected item data"),
            c.selectionRequest.at,
            now
        )
    end
    local full = c.fullJob
    if full then
        if full.waiting then
            return waiting(
                L("Waiting for auction data", "Waiting for auction data"),
                full.at,
                now
            )
        end
        local total = math.max(1, full.total or 1)
        local n = math.max(0, math.min(total, full.index or 0))
        local value = n / total
        return result(
            "processing",
            string.format(
                L("Processing: %d / %d · %d%%", "Processing: %d / %d · %d%%"),
                n,
                total,
                math.floor(value * 100)
            ),
            value,
            n,
            total
        )
    end
    local op = c.active
    if op then
        if op.status == "quote" then
            return waiting(L("Requesting quote", "Requesting quote"), op.at, now)
        end
        if op.status == "quoted" then
            return result(
                "action",
                L(
                    "Quote received — confirm purchase",
                    "Quote received — confirm purchase"
                ),
                1
            )
        end
        if op.status == "awaiting" then
            return waiting(L("Waiting for purchase receipt", "Waiting for purchase receipt"), op.at, now)
        end
        if op.status == "bid" then
            return result(
                "action",
                L("Bid reserved — reconcile outcome", "Bid reserved — reconcile outcome"),
                1
            )
        end
    end
    if c.reviewRequest then
        return waiting(
            L(
                "Waiting for background search before manual review",
                "Waiting for background search before manual review"
            ),
            c.reviewRequest.at,
            now
        )
    end
    if c.job and c.job.origin ~= "radar" and c.plan and c.plan.complete == false and c.message == "partial" then
        return result(
            "action",
            L(
                "Click More results to continue",
                "Click More results to continue"
            )
        )
    end
    if c.job then
        return waiting(
            L("Waiting for search results", "Waiting for search results"),
            c.job.at,
            now
        )
    end
    for _, pending in pairs(c.db.pending or {}) do
        if pending.owner == c.api.owner() and pending.status == "unknown" then
            return result(
                "error",
                L(
                    "Outcome unknown — reconcile in Portfolio",
                    "Outcome unknown — reconcile in Portfolio"
                ),
                0
            )
        end
    end
    if c.postPending then
        return result(
            "action",
            L(
                "Click again to confirm posting",
                "Click again to confirm posting"
            ),
            1
        )
    end
    if c.plannerVisible and c.planning then
        local j = c.planning
        local total = math.max(1, j.total)
        local label = j.phase == "ranking"
                and L("Planner: checking market %d / %d", "Planner: checking market %d / %d")
            or L(
                "Planner: allocating budget %d / %d",
                "Planner: allocating budget %d / %d"
            )
        return result("processing", string.format(label, j.done, total), math.min(1, j.done / total), j.done, total)
    end
    if
        c.dealPageVisible
        and c.dealCache
        and c.dealCache.job
        and not (c.radar and c.radar.enabled and not c.radar.paused)
    then
        local j = c.dealCache.job
        local total = math.max(1, j.inputs.count)
        local n = math.min(total, j.index - 1)
        return result(
            "processing",
            string.format(
                L("Preparing deals: %d / %d", "Preparing deals: %d / %d"),
                n,
                j.inputs.count
            ),
            n / total,
            n,
            j.inputs.count
        )
    end
    local backgroundPlan = (c.message == "plan_ready" or c.message == "plan_review")
        and c.plan
        and c.plan.origin == "radar"
    if done[c.message] and not backgroundPlan and not (c.radar and c.radar.enabled and not c.radar.paused) then
        local caption = L("Action complete", "Action complete")
        if c.message == "replicate_done" then
            caption = L("Full scan processed", "Full scan processed")
        elseif c.message == "planner_done" then
            caption = L("Plan calculated", "Plan calculated")
        elseif c.message == "plan_ready" or c.message == "plan_review" then
            caption = L("Search complete", "Search complete")
        elseif c.message == "post_sent" then
            caption = L("Posting request sent", "Posting request sent")
        end
        return result("done", caption, 1)
    end
    if c.radar and c.radar.enabled then
        local r = c.radar
        if r.paused then
            return result(
                "action",
                L("Live paused — click Resume", "Live paused — click Resume")
            )
        end
        if r.build then
            local n = math.min(#r.build.candidates, r.build.index - 1)
            local total = math.max(1, #r.build.candidates)
            return result(
                "processing",
                string.format(
                    L("Live: selecting candidates %d / %d", "Live: selecting candidates %d / %d"),
                    n,
                    total
                ),
                n / total,
                n,
                total
            )
        end
        if r.idleInputs and r.index > #r.queue and not c.job then
            local s = r.stats or { items = 0, vendorKnown = 0, vendor = 0, resale = 0, collecting = 0 }
            local deals = 0
            for _ in pairs(r.opportunities) do
                deals = deals + 1
            end
            return result(
                "live",
                string.format(
                    L(
                        "Live: %d items · vendor price known %d · below vendor %d · resale %d · collecting data %d · deals %d · recheck in %d s",
                        "Live: %d items · vendor price known %d · below vendor %d · resale %d · collecting data %d · deals %d · recheck in %d s"
                    ),
                    s.items,
                    s.vendorKnown,
                    s.vendor,
                    s.resale,
                    s.collecting,
                    deals,
                    math.max(0, (r.idleUntil or now) - now)
                )
            )
        end
        local found = 0
        for _, v in pairs(r.opportunities) do
            if now >= v.at and now - v.at <= 30 then
                found = found + 1
            end
        end
        return result(
            "live",
            string.format(
                L(
                    "Live: checked %d / %d candidates · deals %d · wait %d s",
                    "Live: checked %d / %d candidates · deals %d · wait %d s"
                ),
                r.checked,
                #r.queue,
                found,
                math.max(0, math.ceil(r.nextAt - now))
            )
        )
    end
    if c.watching then
        local elapsed = math.max(0, math.min(600, 600 - (c.watchUntil - now)))
        return result(
            "processing",
            string.format(L("Watching: %d / 600 s", "Watching: %d / 600 s"), elapsed),
            elapsed / 600,
            elapsed,
            600
        )
    end
    if c.message == "replicate_cooldown" then
        local remain = math.max(0, math.min(900, math.ceil(900 - (now - (c.db.lastReplicate or 0)))))
        return result(
            "cooldown",
            string.format(
                L("Full scan available in %d s", "Full scan available in %d s"),
                remain
            ),
            1 - remain / 900
        )
    end
    if c.message == "stopped" then
        return result("stopped", L("Stopped", "Stopped"), 0)
    end
    return result("idle", L("Ready", "Ready"), 0)
end
function P.create(ui)
    local bar = CreateFrame("StatusBar", nil, ui.canvas)
    bar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.04, 0.04, 0.85)
    local spark = bar:CreateTexture(nil, "ARTWORK")
    spark:SetTexture("Interface/TargetingFrame/UI-StatusBar")
    spark:SetVertexColor(0.85, 0.65, 0.15, 0.9)
    spark:Hide()
    local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetAllPoints()
    F.Locale.font(text, 10)
    ui.progressUI = { bar = bar, spark = spark, text = text, phase = 0 }
    bar:Show()
end
function P.layout(ui, width)
    local p = ui.progressUI
    if not p then
        return
    end
    p.bar:ClearAllPoints()
    p.bar:SetPoint("BOTTOMLEFT", ui.canvas, "BOTTOMLEFT", 8, 4)
    p.bar:SetSize(math.max(1, width - 16), 16)
    ui.status:ClearAllPoints()
    ui.status:SetPoint("BOTTOMLEFT", ui.canvas, "BOTTOMLEFT", 8, 24)
end
function P.paint(ui, dt)
    local p = ui.progressUI
    if not p then
        return
    end
    local state = P.state(ui.c)
    p.state = state
    p.phase = p.phase + (dt or 0)
    p.bar:SetValue(state.mode == "error" and 1 or state.value or 0)
    p.text:SetText(state.label)
    if state.mode == "waiting" or state.mode == "live" then
        local width = p.bar:GetWidth()
        local segment = math.max(1, width * 0.18)
        local offset = (math.sin(p.phase * 2) + 1) * 0.5 * math.max(0, width - segment)
        p.spark:ClearAllPoints()
        p.spark:SetPoint("LEFT", p.bar, "LEFT", offset, 0)
        p.spark:SetSize(segment, 16)
        p.spark:Show()
    else
        p.spark:Hide()
    end
    if state.mode == "error" then
        p.bar:SetStatusBarColor(0.75, 0.15, 0.12)
    elseif state.mode == "action" or state.mode == "cooldown" then
        p.bar:SetStatusBarColor(0.65, 0.5, 0.15)
    elseif state.mode == "processing" then
        p.bar:SetStatusBarColor(0.2, 0.48, 0.75)
    else
        p.bar:SetStatusBarColor(0.18, 0.6, 0.25)
    end
end
return P
