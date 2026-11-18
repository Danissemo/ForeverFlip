-- ForeverFlip window: auction house tab, attach, mailbox button and age text.
-- Moved from UI.lua as it was and loaded after it (ForeverFlip.toc); locals of the
-- earlier UI files come through UI.shared.
local UI = ForeverFlip.UI
local S = UI.shared
local F = S.F
local U = S.U
local L = S.L
local button = S.button
local gold = S.gold

-- Auction house tab ---------------------------------------------------------------------------------
-- Where other tabs are is only read (GetLeft, GetRight, GetTop, IsVisible, GetObjectType): no other
-- addon's or the game's tab is moved, and ours is anchored to AuctionHouseFrame by an offset, never
-- to another addon's tab (that addon may anchor its tab to ours: two anchors would loop).
local function edges(w)
    if type(w) ~= "table" then
        return
    end
    local ok, l, r, t, b = pcall(function()
        return w:GetLeft(), w:GetRight(), w:GetTop(), w:GetBottom()
    end)
    if ok and type(l) == "number" and type(r) == "number" and type(t) == "number" then
        return l, r, t, type(b) == "number" and b or t - 32
    end
end

local function tabLike(w)
    local ok, kind = pcall(function()
        return w:GetObjectType()
    end)
    if not ok or (kind ~= "Button" and kind ~= "CheckButton") then
        return false
    end
    local seen, shown = pcall(function()
        return w:IsVisible()
    end)
    return seen and shown and true or false
end

-- The right edge of the last visible tab in the row of the game's tabs, and that row's top and
-- bottom. A tab already after ours (its left edge at or past our right edge) is someone who placed
-- theirs after ours: it is not counted, so the two tabs never chase each other. Nil while the
-- client has not laid the tabs out yet.
function UI.tabSlot()
    local tabs = AuctionHouseFrame and AuctionHouseFrame.Tabs or {}
    local firstLeft, _, rowTop, rowBottom = edges(tabs[1])
    if not firstLeft then
        return
    end
    local ownLeft, ownRight, ownTop = edges(UI.tab)
    if ownTop and math.abs(ownTop - rowTop) > 6 then
        ownLeft = nil -- ours is in the second row: every tab of the first row counts
    end
    local seen, last = {}, nil
    local function consider(w)
        if type(w) ~= "table" or seen[w] or w == UI.tab or w == UI.tabRoot or w == UI.frame then
            return
        end
        seen[w] = true
        if not tabLike(w) then
            return
        end
        local l, r, t = edges(w)
        if not l or math.abs(t - rowTop) > 6 or l < firstLeft - 1 then
            return
        end
        if ownLeft and l >= ownRight - 2 then
            return
        end
        last = math.max(last or r, r)
    end
    for _, t in ipairs(tabs) do
        consider(t)
    end
    -- Other addons' tabs: children of the auction house, or of a frame of theirs on it (LibAHTab
    -- builds them that way).
    local function children(f)
        local out = {}
        if type(f) == "table" and f.GetChildren then
            local got = { pcall(f.GetChildren, f) }
            if got[1] then
                for i = 2, #got do
                    out[#out + 1] = got[i]
                end
            end
        end
        return out
    end
    for _, child in ipairs(children(AuctionHouseFrame)) do
        if child ~= UI.frame and child ~= UI.tabRoot then
            consider(child)
            for _, grandchild in ipairs(children(child)) do
                consider(grandchild)
            end
        end
    end
    return last, rowTop, rowBottom, firstLeft
end

-- Puts our own tab (the one built without LibAHTab) after the last visible tab. With no room left
-- under the window (the row would pass its right edge), the tab starts a second row under the
-- game's first tab instead of hanging past the window: UI.tabRow says which.
function UI.placeTab()
    local root, b = UI.tabRoot, UI.tab
    if not root or type(b) ~= "table" or b == UI.tabLib then
        return
    end
    local right, top, bottom, firstLeft = UI.tabSlot()
    local houseLeft, houseRight, houseTop = edges(AuctionHouseFrame)
    if not right or not houseLeft then
        return -- not laid out yet: the default anchor after the game's last tab stays
    end
    local width = 100
    pcall(function()
        width = b:GetWidth() or width
    end)
    local x, y, row = right - houseLeft, top - houseTop, 1
    if right + 3 + width > houseRight then
        x, y, row = firstLeft - houseLeft - 3, bottom - houseTop + 2, 2
    end
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    local at = UI.tabAt
    if at and at[1] == x and at[2] == y then
        return
    end
    UI.tabAt, UI.tabRow = { x, y }, row
    root:ClearAllPoints()
    root:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", x, y)
end

-- With LibAHTab (Auctionator and TSM bring it), every addon's tab is a link of one chain after the
-- game's tabs, in the order they were made: ForeverFlip, made last, ended at the end of the row and
-- under TSM's tab. Ours goes first: it is anchored to the library's root frame, and the other tabs
-- of the chain follow it in their old order with the library's own gap. The library's list is put
-- in the same order, so a tab made later is chained after the last one, not after ours. Only the
-- anchors of the addons' tab buttons change; the game's own tabs are never touched.
function UI.tabFirst(lib)
    lib = lib or UI.tabLib
    if type(lib) ~= "table" then
        return
    end
    local ok, err = pcall(function()
        local state = lib.internalState
        local mine = lib.GetButton and lib:GetButton("ForeverFlip")
        if type(state) ~= "table" or type(state.Tabs) ~= "table" or not state.rootFrame or not mine then
            return
        end
        local tabs = state.Tabs
        -- The library's gap: the first tab sits that far from the root frame.
        local _, _, _, gap = tabs[1]:GetPoint(1)
        gap = type(gap) == "number" and gap or 3
        local order = { mine }
        for _, t in ipairs(tabs) do
            if t ~= mine then
                order[#order + 1] = t
            end
        end
        for i, t in ipairs(order) do
            tabs[i] = t
            local point, relative, relativePoint, x = t:GetPoint(1)
            local want = i == 1 and state.rootFrame or order[i - 1]
            local wantPoint = i == 1 and "TOPLEFT" or "TOPRIGHT"
            if point ~= "TOPLEFT" or relative ~= want or relativePoint ~= wantPoint or x ~= gap then
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", want, wantPoint, gap, 0)
            end
        end
    end)
    if not ok then
        F.Engine.report("AH tab order: " .. tostring(err))
    end
end

-- Each time the auction house opens: place the tab now, and again after 0.5 and 2 seconds, since
-- other addons add their tabs on the same event, some of them a moment later.
local RECHECK = { 0.5, 2 }
function UI.tabShown()
    if UI.tabLib then
        UI.tabFirst()
    end
    local root = UI.tabRoot or UI.tabLibRoot
    if not root then
        return
    end
    UI.placeTab()
    local waited, next = 0, 1
    root:SetScript("OnUpdate", function(self, elapsed)
        waited = waited + (elapsed or 0)
        if waited >= RECHECK[next] then
            next = next + 1
            UI.placeTab()
            if UI.tabLib then
                UI.tabFirst()
            end
            if not RECHECK[next] then
                self:SetScript("OnUpdate", nil)
            end
        end
    end)
end

function UI.attach()
    if UI.tab then
        UI.tabShown()
        return
    end
    if not AuctionHouseFrame then
        return
    end
    UI.create()
    local lib = LibStub and LibStub("LibAHTab-1-0", true)
    if lib and lib.CreateTab then
        local ok = pcall(function()
            lib:CreateTab("ForeverFlip", UI.frame, "ForeverFlip", "ForeverFlip")
        end)
        if ok then
            UI.tab, UI.tabLib = lib, lib
            -- Rechecked each time the auction house opens, on a frame of our own (other addons
            -- add their tabs on the same event, some a moment later).
            UI.tabLibRoot = CreateFrame("Frame", nil, AuctionHouseFrame)
            UI.tabLibRoot:SetSize(1, 1)
            UI.tabLibRoot:SetScript("OnShow", UI.tabShown)
            UI.tabShown()
            return
        end
    end
    -- Without LibAHTab (it comes with Auctionator or TSM) the tab is built the way LibAHTab builds
    -- it: the button sits on a plain frame after the game's last tab, not on AuctionHouseFrame.
    -- Any step that fails falls back to a plain button, so the page stays reachable.
    local tabs = AuctionHouseFrame.Tabs
    local root = CreateFrame("Frame", nil, AuctionHouseFrame)
    root:SetSize(10, 10)
    UI.tabRoot = root
    if tabs and #tabs > 0 then
        root:SetPoint("TOPLEFT", tabs[#tabs], "TOPRIGHT")
    else
        root:SetPoint("TOPLEFT", AuctionHouseFrame, "BOTTOMLEFT", 20, 0)
    end
    local function call(f, ...)
        if f then
            pcall(f, ...)
        end
    end
    local ok, b = pcall(function()
        local tab = CreateFrame("Button", "ForeverFlipTab", root, "AuctionHouseFrameDisplayModeTabTemplate")
        tab:SetText("ForeverFlip")
        if PanelTemplates_TabResize then
            PanelTemplates_TabResize(tab, 20, nil, 70)
        end
        return tab
    end)
    if not ok or not b then
        F.Engine.report("AH tab: " .. tostring(b))
        b = CreateFrame("Button", "ForeverFlipTabButton", root, "UIPanelButtonTemplate")
        b:SetSize(100, 22)
        b:SetText("ForeverFlip")
    end
    b:SetPoint("TOPLEFT", root, "TOPLEFT", 3, 0)
    call(PanelTemplates_DeselectTab, b)
    UI.frame:Hide()
    b:SetScript("OnClick", function()
        call(AuctionHouseFrame.SetDisplayMode, AuctionHouseFrame, {})
        AuctionHouseFrame.displayMode = nil
        for _, t in ipairs(tabs or {}) do
            call(PanelTemplates_DeselectTab, t)
        end
        call(PanelTemplates_SelectTab, b)
        -- The house is named in the bottom bar (UI.houseName), not twice: the title stays the addon.
        call(AuctionHouseFrame.SetTitle, AuctionHouseFrame, "ForeverFlip")
        UI.frame:Show()
    end)
    if hooksecurefunc and AuctionHouseFrame.SetDisplayMode then
        pcall(hooksecurefunc, AuctionHouseFrame, "SetDisplayMode", function(_, mode)
            if type(mode) == "table" and #mode > 0 then
                UI.frame:Hide()
                call(PanelTemplates_DeselectTab, b)
            end
        end)
    end
    UI.tab = b
    root:SetScript("OnShow", UI.tabShown)
    UI.tabShown()
end

function UI.refreshPostAll()
    local allList, worthyList = F.Trade.toPostAll(), F.Trade.toPostAll(true)
    local all, worthy = #allList, #worthyList
    -- Without a price for any item the click only reads the prices (Trade.postReady): the label
    -- says so, and the next click posts.
    local function label(name, list)
        if #list > 0 and not F.Trade.postReady(list) then
            return L("Check prices") .. " (" .. #list .. ")"
        end
        return L(name) .. " (" .. #list .. ")"
    end
    UI.postAll:SetText(label("Post all", allList))
    UI.postAll:SetEnabled(all > 0 and not F.Trade.posting and F.Trade.wayReady())
    UI.postAuction:SetText(label("Post AH-worthy", worthyList))
    UI.postAuction:SetEnabled(worthy > 0 and not F.Trade.posting and F.Trade.wayReady())
end

-- The Best column of the Sell page: where one unit brings the most, and how much.
local BEST = { vendor = "Vendor", auction = "AH", disenchant = "Disenchant" }
function UI.bestText(w)
    if w.name == "unknown" then
        return UI.C.dim .. L("AH: no price yet") .. "|r"
    end
    -- Both routes pass their thresholds and the player has not chosen (Trade.sellWay): no price,
    -- the player decides; the page explains the sums.
    if w.name == "undecided" then
        return UI.C.good .. L("AH") .. "|r / " .. UI.C.vendor .. L("V") .. "|r"
    end
    local color = (UI.ROUTE[w.name] or UI.ROUTE.disenchant)[1]
    -- The auction house shows the price to post at, the same as the price box of the Sell page; it
    -- turns red when that price loses money on what the stock cost. Sorting uses what it brings.
    local q = w.quote
    if w.name == "auction" and q and q.post then
        local money = U.money(q.post)
        if q.profit and q.profit < 0 then
            money = UI.C.bad .. money .. "|r"
        end
        return color .. L(BEST[w.name]) .. "|r " .. money
    end
    return color .. L(BEST[w.name]) .. "|r " .. U.money(w.value)
end

-- Why the Best column says what it says: the two routes read side by side for one unit, so the
-- choice is visible instead of trusted. A vendor pays at once with no cut and no deposit; the
-- auction house pays after its cut and after the deposits a lot is expected to lose. Prices that
-- are only an estimate are marked, and a route that cannot be taken says why.
-- Why the Best column says what it says, in the Undercuts page's shape: a verdict led by its
-- subject, then each route in two lines, the chosen one first and marked: what one unit brings,
-- then in grey how. The same sums as the column and its hover (F.Trade.quote).
-- What decided the route, in one sentence: the deposits a slow seller loses, the cut, a merchant
-- that does not buy it, or the materials. Read at the market price the route was chosen at.
local function bestReason(w, q, vendor, auction)
    local cut = UI.pct(F.Market.CUT)
    local post = q.belowFloor and q.marketPost or q.post
    local lost = (q.belowFloor and q.marketLost or q.lost) or 0
    local tries = (q.belowFloor and q.marketTries or q.tries) or 1
    local perDay = q.belowFloor and q.marketPerDay or q.perDay
    if w.name == "vendor" then
        if not (auction and post) then
            return nil
        end
        if lost > 0 and auction + lost > vendor then
            local pace = perDay and perDay >= 0.05 and string.format(L("it sells about %.1f a day"), perDay)
                or L("it hardly sells")
            return string.format(
                L(
                    "at %s %s: about %d posts are expected to expire before one sells, and their lost deposits (%s) cost more than the auction house would gain over a vendor."
                ),
                U.money(post),
                pace,
                math.max(1, math.floor(tries - 1 + 0.5)),
                U.money(lost)
            )
        end
        return string.format(
            L("after the %d%% cut, %s on the auction house brings %s: less than the %s a vendor pays at once."),
            cut,
            U.money(post),
            U.money(auction),
            U.money(vendor)
        )
    elseif w.name == "auction" then
        if not vendor then
            return L("no merchant buys it: the auction house is the only way to sell it.")
        end
        if not (auction and post) then
            return nil
        end
        return string.format(
            L(
                "%s on the auction house brings %s after the %d%% cut and %s of expected lost deposits: %s more than a vendor pays."
            ),
            U.money(post),
            U.money(auction),
            cut,
            U.money(lost),
            U.money(auction - vendor)
        )
    elseif w.name == "disenchant" then
        return string.format(
            L("the materials bring %s, more than the auction house (%s) or a vendor (%s)."),
            U.money(q.disenchant or 0),
            auction and U.money(auction) or "-",
            vendor and U.money(vendor) or "-"
        )
    end
    return nil
end

-- Why F.Market.routeVerdict sent stock both routes pay for one way, or left it to the player, in
-- one sentence for `n` units (sums for all of them).
local DOUBT = {
    sure = "Sure of selling at that price is only %s",
    sales = "too few sales were seen to trust the figures",
    war = "rivals answer undercuts often (a price war)",
}
function UI.verdictReason(v, routes)
    local a, vendor = routes and routes.auction, routes and routes.vendor
    if not (v and a and vendor) then
        return nil
    end
    local function m(x)
        return U.money(math.floor(math.max(0, x) + 0.5))
    end
    if v.why == "vendor_more" then
        return string.format(
            L("a vendor pays %s at once, no less than the auction house's profit (%s), with nothing at risk."),
            m(vendor.profit),
            m(a.profit)
        )
    elseif v.why == "small_gain" then
        return string.format(
            L(
                "counting the chance it does not sell, the auction house adds only %s over a vendor's %s: not worth the wait."
            ),
            UI.signed(math.floor(v.gain + 0.5)),
            m(vendor.profit)
        )
    elseif v.why == "ah_more" then
        return string.format(
            L("the auction house is expected to bring %s more than a vendor (%s), and nothing makes it doubtful."),
            m(v.gain),
            m(vendor.profit)
        )
    end
    local doubts = {}
    for _, d in ipairs(v.doubts or {}) do
        local sure = d == "sure" and routes.sure
        doubts[#doubts + 1] = d == "sure" and not sure and L("its chance of selling is not known")
            or string.format(L(DOUBT[d]), sure and UI.sureText(sure) or "")
    end
    local doubt = table.concat(doubts, "; ")
    if v.why == "vendor_poor" then
        return string.format(
            L("the auction house is doubtful (%s), but a vendor pays only %s: too little to fall back on."),
            doubt,
            m(vendor.profit)
        )
    end
    return string.format(
        L(
            "the auction house should bring %s more, but %s; a vendor pays a fair %s at once. Choose AH or Vendor below the list."
        ),
        m(v.gain),
        doubt,
        m(vendor.profit)
    )
end

local ROUTE = UI.ROUTE
function UI.bestLines(w)
    local q = w.quote or {}
    local vendor = q.vendor and q.vendor > 0 and q.vendor or nil
    -- The route is chosen at the market price; a minimum above it only lifts the price posted.
    local auction = q.belowFloor and q.marketNet or q.net
    local verdict
    if w.name == "vendor" then
        verdict = string.format(
            L("Vendor pays %s each; auction at current market prices brings %s."),
            U.money(vendor or 0),
            auction and U.money(auction) or "-"
        )
    elseif w.name == "auction" then
        verdict = vendor
                and auction
                and string.format(L("the auction house brings %s more than a vendor."), U.money(auction - vendor))
            or L("the auction house: no merchant buys it.")
    elseif w.name == "undecided" then
        verdict = L("not decided: both the auction house and a vendor pay.")
    elseif w.name == "disenchant" then
        verdict = string.format(
            L("disenchanting brings %s more than selling it."),
            U.money(math.max(0, (q.disenchant or 0) - math.max(vendor or 0, auction or 0)))
        )
    elseif q.guess then
        verdict = L("not decided: the auction house price is only a guess until the listings are read.")
    else
        verdict = L("not decided yet: the auction house price is not known.")
    end
    if w.chosen then
        verdict = verdict .. " " .. UI.C.dim .. L("(your choice)") .. "|r"
    end
    local head = { gold("Best") .. " " .. verdict }
    -- Both routes pay: the reason is the verdict's (F.Market.routeVerdict), unless the player chose.
    local verdictOf = not w.chosen and w.routes and w.routes.verdict
    local reason = verdictOf and UI.verdictReason(verdictOf, w.routes) or bestReason(w, q, vendor, auction)
    if reason then
        head[2] = gold("Why") .. " " .. reason
    end
    local lines = {}
    local detail = UI.optionDetail
    local function route(id, brings, how)
        local best = w.name == id
        local v = ROUTE[id]
        lines[#lines + 1] = UI.optionHead(best, v[1], v[2]) .. "  " .. brings .. UI.optionMark(best, "(best)")
        if how then
            lines[#lines + 1] = detail(how)
        end
    end
    local order = { "auction", "vendor", "disenchant" }
    for i, id in ipairs(order) do
        if id == w.name then
            table.remove(order, i)
            table.insert(order, 1, id)
            break
        end
    end
    for _, id in ipairs(order) do
        if id == "auction" then
            if q.net and q.post then
                local how = string.format(
                    L("posted at %s: the %d%% cut %s, deposits expected to be lost %s"),
                    U.money(q.post),
                    UI.pct(F.Market.CUT),
                    U.money(q.post - F.Market.net(q.post, 1)),
                    U.money(q.lost or 0)
                )
                if q.profit then
                    how = how .. "; " .. L("profit each") .. " " .. UI.signed(q.profit)
                end
                route("auction", string.format(L("brings %s each"), U.money(q.net)), how)
            else
                route(
                    "auction",
                    L("no price yet"),
                    q.guess and L("only a guess so far: Check price reads the listings")
                        or L("Check price reads the current listings")
                )
            end
        elseif id == "vendor" then
            if vendor then
                local how = L("at once, no cut and no deposit")
                if q.vendorHow == "estimate" then
                    how = how .. "; " .. L("less the safety margin")
                end
                route("vendor", string.format(L("pays %s each"), U.money(vendor)), how)
            else
                route("vendor", L("does not buy it"))
            end
        elseif q.disenchant and q.disenchant > 0 then
            route(
                "disenchant",
                string.format(L("about %s in materials"), U.money(q.disenchant)),
                L("the expected materials at their current prices")
            )
        end
    end
    return head, lines
end

-- Both routes of held stock in the tooltip (Market.sellRoutes): what each brings, what it costs,
-- the cut and fees, the risk, and the threshold it passed. Either is a good sale.
function UI.routeLines(routes, best)
    local function money(v)
        return U.money(math.max(0, math.floor((v or 0) + 0.5)))
    end
    local a, v = routes.auction, routes.vendor
    GameTooltip:AddLine(L("Both routes pass their thresholds: either sells at a profit."), 0.25, 1, 0.25, true)
    if a then
        GameTooltip:AddLine(
            UI.C.good .. L("AH") .. "|r" .. (best == "auction" and ("  " .. L("(best)")) or ""),
            1,
            0.82,
            0
        )
        UI.tipPair(GameTooltip, "  " .. L("Expected revenue"), money(a.revenue), 1, 1, 1, 1, 1, 1)
        UI.tipPair(GameTooltip, "  " .. L("Cost of the stock"), "-" .. money(a.cost), 1, 1, 1, 1, 1, 1)
        UI.tipPair(
            GameTooltip,
            "  " .. string.format(L("Cut %d%% and lost deposits"), UI.pct(F.Market.CUT)),
            "-" .. money(a.cut + a.lost),
            1,
            1,
            1,
            1,
            0.4,
            0.4
        )
        UI.tipPair(GameTooltip, "  " .. L("Profit"), UI.signed(math.floor(a.profit + 0.5)), 1, 1, 1, 1, 1, 1)
        local risk
        if a.perDay and a.perDay > 0 then
            risk = string.format(L("sells about %.1f a day; about %.1f posts per sale"), a.perDay, a.tries or 1)
        else
            risk = string.format(L("sales not measured; about %.1f posts per sale"), a.tries or 1)
        end
        GameTooltip:AddLine("  " .. L("Risk") .. ": " .. risk, 0.67, 0.67, 0.67, true)
        GameTooltip:AddLine(
            "  "
                .. L("Threshold")
                .. ": "
                .. string.format(L("profit at least %s and %d%% return"), U.money(a.threshold), UI.pct(a.minROI)),
            0.67,
            0.67,
            0.67,
            true
        )
    end
    if v then
        GameTooltip:AddLine(
            UI.C.vendor .. L("Vendor") .. "|r" .. (best == "vendor" and ("  " .. L("(best)")) or ""),
            1,
            0.82,
            0
        )
        UI.tipPair(GameTooltip, "  " .. L("Expected revenue"), money(v.revenue), 1, 1, 1, 1, 1, 1)
        UI.tipPair(GameTooltip, "  " .. L("Cost of the stock"), "-" .. money(v.cost), 1, 1, 1, 1, 1, 1)
        UI.tipPair(GameTooltip, "  " .. L("Cut and fees"), L("none"), 1, 1, 1, 1, 1, 1)
        UI.tipPair(GameTooltip, "  " .. L("Profit"), UI.signed(math.floor(v.profit + 0.5)), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddLine(
            "  "
                .. L("Risk")
                .. ": "
                .. (v.confirmed and L("none: a merchant pays at once") or L("less the safety margin")),
            0.67,
            0.67,
            0.67,
            true
        )
        GameTooltip:AddLine(
            "  " .. L("Threshold") .. ": " .. string.format(L("profit at least %s"), U.money(v.threshold)),
            0.67,
            0.67,
            0.67,
            true
        )
    end
    GameTooltip:AddLine(" ")
end

function UI.bestTooltip(cell, w, name)
    if not GameTooltip then
        return
    end
    GameTooltip:SetOwner(cell, "ANCHOR_TOP")
    local q = w.quote or {}
    local cut = UI.pct(F.Market.CUT)
    local both = w.routes and w.routes.both and w.name ~= "disenchant" and true or false
    GameTooltip:SetText(
        L("Best") .. ": " .. (w.name == "undecided" and (L("AH") .. " / " .. L("V")) or (L(BEST[w.name]) or w.name)),
        1,
        0.82,
        0,
        1,
        true
    )
    GameTooltip:AddLine(name or "", 1, 1, 1, true)
    GameTooltip:AddLine(" ")
    if both then
        UI.routeLines(w.routes, w.name)
    end

    -- The vendor route: the game's item data, confirmed or not.
    local vendor, how = q.vendor, q.vendorHow
    if vendor and vendor > 0 then
        UI.tipPair(
            GameTooltip,
            L("Vendor") .. (how == "estimate" and " *" or ""),
            U.money(vendor),
            1,
            1,
            1,
            1,
            0.73,
            0.3
        )
    else
        UI.tipPair(GameTooltip, L("Vendor"), L("does not buy it"), 1, 1, 1, 0.6, 0.6, 0.6)
    end

    -- The auction route: what one unit brings after the cut and the deposits, when it is known.
    if q.net then
        UI.tipPair(
            GameTooltip,
            string.format(L("AH after the %d%% cut"), cut),
            U.money(q.net) .. (q.guess and (" " .. L("(estimate)")) or ""),
            1,
            1,
            1,
            0.25,
            1,
            0.25
        )
        if q.lost and q.lost > 0 then
            UI.tipPair(GameTooltip, L("Deposits expected to be lost"), "-" .. U.money(q.lost), 1, 1, 1, 1, 0.4, 0.4)
        end
    else
        UI.tipPair(
            GameTooltip,
            L("AH"),
            q.guess and L("not enough price data") or L("no answer yet"),
            1,
            1,
            1,
            0.6,
            0.6,
            0.6
        )
    end

    -- The difference, on the route the column chose.
    if q.value and vendor and vendor > 0 then
        GameTooltip:AddLine(" ")
        local diff = U.money(math.abs((q.value or 0) - vendor))
        if w.name == "vendor" or (w.name == "undecided" and vendor >= (q.value or 0)) then
            GameTooltip:AddLine(string.format(L("A vendor pays %s more for it."), diff), 1, 0.73, 0.3, true)
        else
            GameTooltip:AddLine(string.format(L("The auction house brings %s more for it."), diff), 0.25, 1, 0.25, true)
        end
    end
    -- Only a price lowered by the safety margin is a guess, as the Sell page's * says.
    if vendor and how == "estimate" then
        GameTooltip:AddLine(L("Vendor price less the safety margin of Settings → Safety."), 1, 0.82, 0, true)
    end
    if q.belowFloor then
        GameTooltip:AddLine(
            L("The market is below your minimum: wait, change the rule, or choose another route."),
            1,
            0.4,
            0.4,
            true
        )
    end
    GameTooltip:Show()
end

function UI.refreshPostNext()
    local n = #F.Trade.toPost()
    UI.postNext:SetText(L("Post next bought") .. " (" .. n .. ")")
    UI.postNext:SetEnabled(n > 0 and not F.Trade.posting and F.Trade.wayReady())
end

-- Mailbox: one button takes all auction house mail (paced).
function UI.mail(open)
    if not MailFrame then
        return
    end
    if not UI.mailButton then
        UI.mailButton = button(MailFrame, "Take auction mail", 190, function()
            F.Mail.start()
            UI.mail(true)
        end)
        UI.mailButton:SetPoint("TOPRIGHT", MailFrame, "TOPRIGHT", -40, -28)
    end
    local n = open and F.Mail.count() or 0
    if n > 0 or F.Mail.job then
        UI.mailButton:SetText(L("Take auction mail") .. " (" .. n .. ")")
        UI.mailButton:SetEnabled(not F.Mail.job)
        UI.mailButton:Show()
    else
        UI.mailButton:Hide()
    end
end

-- How long ago a time was: "5 min ago", "3 h ago", "2 d ago".
function UI.age(at)
    if not U.finite(at) then
        return "?"
    end
    local s = math.max(0, F.Engine.clock() - at)
    if s < 3600 then
        return string.format(L("%d min ago"), math.floor(s / 60))
    elseif s < 2 * 86400 then
        return string.format(L("%d h ago"), math.floor(s / 3600))
    end
    return string.format(L("%d d ago"), math.floor(s / 86400))
end

-- One way to say where a post price (F.Trade.quote) comes from, on the tooltip and the Sell page.
