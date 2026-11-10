local F = ForeverFlip
local P = {}
F.Planner = P
local function context(c)
    return table.concat(
        { c.api.owner(), c.api.scope(), c.api.wallet(), c:reserved(), #c.db.ledger, c.db.sequence or 0, c.ruleVersion },
        "|"
    )
end
function P.start(c, profile, options, completed)
    if
        not c:allowed()
        or c.active
        or (c.job and c.job.origin ~= "radar")
        or (c.fullJob and c.fullJob.origin ~= "radar")
    then
        c:notify("search_busy")
        return false
    end
    c:radarPause()
    c.overrides = nil
    c.planning = {
        profile = profile,
        options = F.Util.copy(options),
        completed = completed,
        owner = c.api.owner(),
        scope = c.api.scope(),
        at = c.api.clock(),
        phase = "waiting",
        done = 0,
        total = 1,
    }
    return true
end
function P.tick(c)
    local j = c.planning
    if not j then
        return
    end
    if
        not c.api.isOpen()
        or j.owner ~= c.api.owner()
        or j.scope ~= c.api.scope()
        or c.api.clock() - j.at > 180
        or (j.context and j.context ~= context(c))
    then
        c.planning = nil
        c:notify("rescan")
        return
    end
    if c.job or c.fullJob or c.reviewRequest or c.selectionRequest or c.active then
        return
    end
    if not j.thread then
        j.thread = coroutine.create(function()
            local function yieldPass(phase, done, total)
                coroutine.yield(phase, done, total)
            end
            if j.profile == "manual" then
                c.advisorProfile = nil
                c:invalidate()
                local o = F.Util.copy(j.options or {})
                o.yieldPass = yieldPass
                return c:allocate(o)
            end
            return c:recommend(j.profile, yieldPass)
        end)
    end
    local started = debugprofilestop and debugprofilestop()
    for _ = 1, 4 do
        local ok, phase, done, total = coroutine.resume(j.thread)
        c.cachedSummary, c.salesByKey = nil, nil
        if not ok then
            c.planning = nil
            c:notify("calculation_incomplete")
            return
        end
        if coroutine.status(j.thread) == "dead" then
            c.planning = nil
            if type(phase) == "table" and not phase.error then
                if j.completed then
                    j.completed(phase)
                end
                c:notify("planner_done")
            else
                c:notify("search_busy")
            end
            return
        end
        j.phase, j.done, j.total = phase, done or 0, math.max(1, total or 1)
        j.context = j.context or context(c)
        if started and debugprofilestop() - started >= 2 then
            break
        end
    end
end
