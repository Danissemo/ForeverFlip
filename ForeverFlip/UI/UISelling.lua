-- ForeverFlip window: Sell, My auctions and Undercuts pages.
-- Moved from UI.lua as it was and loaded after it (ForeverFlip.toc); locals of the
-- earlier UI files come through UI.shared.
local UI = ForeverFlip.UI
local S = UI.shared
local F = S.F
local U = S.U
local L = S.L
local text = S.text
local button = S.button
local editbox = S.editbox
local hint = S.hint
local icon = S.icon
local nameOf = S.nameOf
local table_ = S.table_
local footer = S.footer
local gold = S.gold

-- Sell page --------------------------------------------------------------------------------------
-- Where a suggested price comes from when nobody else sells the item.
UI.FALLBACK_TEXT = {
    last = "Nobody else sells it now. Suggested: your last price %s.",
    aux = "Nobody else sells it now. Suggested: auxForever's usual price %s.",
    history = "Nobody else sells it now. Suggested: its older market price %s.",
    similar = "Nobody else sells it now. Suggested: the usual price of its other versions, %s.",
    cost = "Nobody sells it and there is no price history. Suggested: your cost plus 25%%, %s.",
    vendor = "Nobody sells it and there is no price history. Suggested: 1.5 x the vendor price, %s.",
}
local SELL_ROWS = 11 -- a 12th row ran under the For sale / Hidden / Rule / Hide buttons

-- The button row in three groups, all on one line with the same gaps: Hide and Rule at the left;
-- the Check Sure box, its button and Reset at the right (Reset undoes the check and the chosen
-- route); Choose AH and Choose vendor, shown only for a disputed item, centred in the space between.
-- The right group is chained from the right edge. The box's template draws its border outside the
-- frame, so it keeps a wider gap. When the full Choose labels do not fit (a narrow window, a long
-- translation), the buttons read just "AH" and "Vendor" (their hover says what they do).
local function widthOf(f, default)
    local w = f and f.GetWidth and f:GetWidth() or 0
    return (w and w > 0) and w or default
end
UI.SELL_GAP = 4 -- between the buttons of a group
UI.SELL_BOX_GAP = 10 -- around the Check Sure box (its border is drawn outside it)
UI.SELL_MIN_SPACE = 12 -- the least space between two groups

-- SetText fits the label to the button's old width (cut and in the small font when it was the
-- short one): the label is measured whole again, the button sized to it, and then fitted anew.
local function labelButton(b, text)
    b:SetText(L(text))
    if b.resetLabel then
        b:resetLabel()
    end
    b:SetWidth(math.ceil(UI.labelWidth(b)) + 24)
    if b.fitLabel then
        b:fitLabel()
    end
end

function UI.layoutSellButtons()
    local list = UI.sellButtonsList
    if not list or not UI.sellSureReset then
        return
    end
    local gap, boxGap = UI.SELL_GAP, UI.SELL_BOX_GAP
    UI.sellSureReset:ClearAllPoints()
    UI.sellSureReset:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -6, 6)
    UI.sellSureButton:ClearAllPoints()
    UI.sellSureButton:SetPoint("RIGHT", UI.sellSureReset, "LEFT", -gap, 0)
    UI.sellCheckPrice:ClearAllPoints()
    UI.sellCheckPrice:SetPoint("RIGHT", UI.sellSureButton, "LEFT", -boxGap, 0)
    local left = 6 + widthOf(UI.sellHide, 80) + gap + widthOf(UI.ruleToggle, 64)
    local right = 6
        + widthOf(UI.sellSureReset, 64)
        + gap
        + widthOf(UI.sellSureButton, 90)
        + boxGap
        + widthOf(UI.sellCheckPrice, 60)
        + boxGap
    local total = widthOf(list, 0)
    local function chooseWidth()
        return widthOf(UI.chooseAH, 86) + gap + widthOf(UI.chooseVendor, 104)
    end
    -- Full labels when they fit with room on both sides, otherwise the short ones.
    local short = false
    if total > 0 then
        if UI.chooseShort then
            labelButton(UI.chooseAH, "Choose AH")
            labelButton(UI.chooseVendor, "Choose vendor")
        end
        short = total - left - right - chooseWidth() < 2 * UI.SELL_MIN_SPACE
        if short then
            labelButton(UI.chooseAH, "AH")
            labelButton(UI.chooseVendor, "Vendor")
        end
    end
    UI.chooseShort = short
    local space = UI.SELL_MIN_SPACE
    if total > 0 then
        space = math.max(UI.SELL_MIN_SPACE, math.floor((total - left - right - chooseWidth()) / 2))
    end
    UI.chooseAH:ClearAllPoints()
    UI.chooseAH:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", left + space, 6)
    UI.chooseVendor:ClearAllPoints()
    UI.chooseVendor:SetPoint("LEFT", UI.chooseAH, "RIGHT", gap, 0)
end

function UI.createSell(p)
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 150)
    UI.sellTable = table_(
        list,
        {
            { "Name" },
            { "Qty", 50 },
            { "Best", 70, "LEFT" },
            { "Sells at", 150 },
            { "Sure", 60 },
            { "Note", 95, "LEFT" },
        },
        SELL_ROWS,
        function(row)
            UI.sellSelected = row.item
            UI.sellPrice:SetText("")
            if row.item and UI.sellView == "hidden" then
                F.Engine.changed()
                UI.refresh()
                return
            end
            if row.item then
                -- An item a fresh full scan did not see has no lots: a search would get no answer.
                if not F.Scan.notListed(row.item.key) then
                    F.Trade.checkPrice(row.item.key)
                end
                UI.sellQty:SetText(row.item.count)
                local rule = F.Trade.rule(row.item.key) or {}
                UI.ruleMin:SetText(rule.min and U.plainMoney(rule.min) or "")
                UI.ruleMax:SetText(rule.max and U.plainMoney(rule.max) or "")
                UI.ruleKeep:SetText(rule.keep and tostring(rule.keep) or "")
            end
            F.Engine.changed()
            UI.refresh()
        end
    )
    local noteHeader = UI.sellTable.headers[6]
    UI.tip(
        noteHeader,
        "Note",
        "How the item came, and the way it keeps. resale, market reset, bid: bought through Deals for the auction house. vendor deal: bought to sell to a vendor. other: bought elsewhere. your choice: the route you chose (Reset forgets it). Choose: both routes pay, you decide."
    )
    -- The Best and Sells at cells answer "why this route": a vendor pays at once with no cut, the
    -- auction house pays after its cut and the deposits a lot is expected to lose. The Note cell of
    -- an item waiting for the player's route says what waiting means.
    local function hide()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end
    for _, row in ipairs(UI.sellTable.rows) do
        for _, cell in ipairs({ row.cols[2], row.cols[3] }) do
            UI.hoverOnly(cell)
            cell:SetScript("OnEnter", function(self)
                if row.bestWay then
                    UI.bestTooltip(self, row.bestWay, row.bestName)
                end
            end)
            cell:SetScript("OnLeave", hide)
        end
        local note = row.cols[5]
        UI.hoverOnly(note)
        note:SetScript("OnEnter", function(self)
            if GameTooltip and row.bestWay and row.bestWay.name == "undecided" then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(L("Choose a route"), 1, 0.38, 0.38, 1, true)
                GameTooltip:AddLine(
                    L(
                        "The auction house and a vendor both pay, and neither is clearly better. Select the item and press Choose AH or Choose vendor."
                    ),
                    1,
                    1,
                    1,
                    true
                )
                GameTooltip:AddLine(
                    L("Until a route is chosen, the item is not offered at a vendor and Post AH-worthy skips it."),
                    1,
                    0.82,
                    0,
                    true
                )
                GameTooltip:Show()
            end
        end)
        note:SetScript("OnLeave", hide)
    end
    noteHeader:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    -- For sale and Hidden are the two views of My items in the menu on the left (UI.GROUPS); the
    -- buttons that act on the selected item, Hide and Rule..., sit at the bottom left of the list.
    UI.sellView = UI.sellView or "sale"
    UI.sellHide = button(p, "Hide", 80, function()
        local item = UI.sellSelected
        if not item then
            return
        end
        if UI.sellView == "hidden" then
            F.Trade.unhide(item.key)
            F.Engine.notify("unhidden")
        else
            F.Trade.hide(item.key, item.name or U.linkName(item.link) or nameOf(item.key))
            F.Engine.notify("hidden")
        end
        UI.sellSelected = nil
        UI.sellPrice:SetText("")
        UI.refresh()
    end)
    UI.sellHide:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 6, 6)
    -- Rule of the selected item (minimum and maximum price, units kept in the bags), in a panel over
    -- the bottom of the list, opened with "Rule..." beside Hide. Most items need none.
    local panel = CreateFrame("Frame", nil, p)
    panel:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 4, 32)
    panel:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -4, 32)
    panel:SetHeight(64)
    if panel.SetFrameLevel and list.GetFrameLevel then
        panel:SetFrameLevel((list:GetFrameLevel() or 1) + 20)
    end
    local back = panel:CreateTexture(nil, "BACKGROUND")
    back:SetColorTexture(0.05, 0.05, 0.05, 0.95)
    back:SetAllPoints()
    local edge = panel:CreateTexture(nil, "BORDER")
    edge:SetColorTexture(1, 0.82, 0, 0.4)
    edge:SetHeight(1)
    edge:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    edge:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    panel:Hide()
    UI.rulePanel = panel
    local help = text(panel, "GameFontHighlightSmall")
    help:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 8)
    help:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 8)
    help:SetText(
        L("min: never post below this price. max: sellers asking more are ignored. keep: units that stay in the bags.")
    )
    local ruleLabel = text(panel, "GameFontNormal")
    ruleLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -10)
    ruleLabel:SetText(L("Rule: min"))
    UI.ruleMin = editbox(panel, 70)
    UI.ruleMin:SetPoint("LEFT", ruleLabel, "RIGHT", 8, 0)
    local maxLabel = text(panel, "GameFontNormal")
    maxLabel:SetPoint("LEFT", UI.ruleMin, "RIGHT", 10, 0)
    maxLabel:SetText(L("max"))
    UI.ruleMax = editbox(panel, 70)
    UI.ruleMax:SetPoint("LEFT", maxLabel, "RIGHT", 8, 0)
    local keepLabel = text(panel, "GameFontNormal")
    keepLabel:SetPoint("LEFT", UI.ruleMax, "RIGHT", 10, 0)
    keepLabel:SetText(L("keep"))
    UI.ruleKeep = editbox(panel, 40)
    UI.ruleKeep:SetPoint("LEFT", keepLabel, "RIGHT", 8, 0)
    UI.ruleSave = button(panel, "Save rule", 95, function()
        local item = UI.sellSelected
        if item then
            F.Trade.setRule(item.key, {
                min = U.parseMoney(UI.ruleMin:GetText()),
                max = U.parseMoney(UI.ruleMax:GetText()),
                keep = tonumber(UI.ruleKeep:GetText()),
            })
            F.Engine.notify("saved")
            panel:Hide()
        end
    end)
    UI.ruleSave:SetPoint("LEFT", UI.ruleKeep, "RIGHT", 10, 0)
    UI.ruleToggle = button(p, "Rule", 64, function()
        if panel:IsShown() then
            panel:Hide()
        elseif UI.sellSelected then
            panel:Show()
        end
    end)
    UI.ruleToggle:SetPoint("LEFT", UI.sellHide, "RIGHT", UI.SELL_GAP, 0)
    -- Check Sure, as on Deals -> Resale: a sell price of the player's own in its own box (not the
    -- posting price below), checked with F.Deals.checkAt; the row's Sure shows the price checked and
    -- the footer the figures. Enter in the box checks too. The check is kept with the item's key
    -- until Reset or another item. The box has no label beside it: the Choose buttons share the
    -- line, so its name is on hover.
    UI.sellCheckPrice = editbox(p, 60)
    UI.sellCheckPrice:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        UI.checkSell(self:GetText())
    end)
    UI.sellCheckPrice:SetScript("OnTextChanged", function()
        F.Engine.changed()
    end)
    hint(UI.sellCheckPrice, "Sell at", "A price of your own to check: Check Sure shows how sure it sells at it")
    UI.sellSureButton = button(p, "Check Sure", 90, function()
        UI.checkSell(UI.sellCheckPrice:GetText())
    end)
    -- Reset drops the check, and the route the player chose (AH / V): Best decides again.
    UI.sellSureReset = button(p, "Reset", 64, function()
        UI.sellSureCheck = nil
        UI.sellCheckPrice:SetText("")
        if UI.sellSelected and F.Trade.routeChoice(UI.sellSelected.key) then
            F.Trade.setRouteChoice(UI.sellSelected.key, nil)
            F.Engine.changed()
        end
        UI.refresh()
    end)
    -- When both routes pay (Best "AH / V"), the player decides; the footer gives the sums. The
    -- choice is kept per item (Trade.setRouteChoice) and decides Post AH-worthy and the merchant.
    UI.chooseVendor = button(p, "Choose vendor", 104, function()
        if UI.sellSelected then
            F.Trade.setRouteChoice(UI.sellSelected.key, "vendor")
            F.Engine.changed()
            UI.refresh()
        end
    end)

    UI.chooseAH = button(p, "Choose AH", 86, function()
        if UI.sellSelected then
            F.Trade.setRouteChoice(UI.sellSelected.key, "auction")
            F.Engine.changed()
            UI.refresh()
        end
    end)
    hint(UI.chooseAH, "Choose AH", "Sell this item at the auction house. Kept until Reset.")
    hint(UI.chooseVendor, "Choose vendor", "Sell this item to a merchant. Kept until Reset.")
    -- Laid out again when the list or a button's width changes (UI.layoutSellButtons).
    UI.sellButtonsList = list
    UI.layoutSellButtons()
    list:SetScript("OnSizeChanged", UI.layoutSellButtons)

    -- The footer is laid out as the Undercuts page's: the selected item's lines in a scrolling block
    -- at the top (7 rows, the wheel or the bar reaches the rest), then the price, quantity and
    -- duration in a row of their own, then the posting buttons. Long explanations (the sale route,
    -- the market, the minimum) need more than three lines, and three lines ran into the fields.
    local bar = footer(p, 146, "GameFontHighlightSmall")
    bar.text:Hide()
    UI.sellBox = UI.scrollText(bar, 6, 6, 26) -- a seventh row ran into the price row
    UI.sellText = UI.sellBox.text
    local priceLabel = text(bar, "GameFontNormal")
    priceLabel:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 8, 36)
    priceLabel:SetText(L("Price each"))
    UI.sellPrice = editbox(bar, 100)
    UI.sellPrice:SetScript("OnTextChanged", function(self, userInput)
        if self:GetText() == "" then
            UI.sellPriceAuto = nil
        elseif userInput then
            UI.sellPriceAuto = nil -- typed by the player: kept as it is
        end
        F.Engine.changed()
    end)
    UI.sellPrice:SetPoint("LEFT", priceLabel, "RIGHT", 10, 0)
    local qtyLabel = text(bar, "GameFontNormal")
    qtyLabel:SetPoint("LEFT", UI.sellPrice, "RIGHT", 40, 0) -- room for the Check price button
    qtyLabel:SetText(L("Quantity"))
    UI.sellQty = editbox(bar, 50)
    UI.sellQty:SetPoint("LEFT", qtyLabel, "RIGHT", 10, 0)
    local durationLabel = text(bar, "GameFontNormal")
    durationLabel:SetPoint("LEFT", UI.sellQty, "RIGHT", 14, 0)
    durationLabel:SetText(L("Duration"))
    UI.durations = {}
    local values = { 1, 2, 3, 0 }
    for i = 1, 4 do
        local b = button(bar, UI.durationLabel(values[i]), i == 4 and 50 or 34, function()
            F.db.settings.duration = values[i]
            F.Engine.changed()
            UI.refresh()
        end)
        b.value = values[i]
        b:SetPoint("LEFT", i == 1 and durationLabel or UI.durations[i - 1], "RIGHT", i == 1 and 8 or 2, 0)
        UI.durations[i] = b
    end
    -- Auto explains itself: the deposits each duration is expected to lose for the selected item.
    UI.durations[4]:SetScript("OnEnter", function(self)
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L("Automatic duration"), 1, 0.82, 0)
        GameTooltip:AddLine(
            L(
                "The deposit comes back when the lot sells and is lost only when it expires. Auto picks the duration that loses the least deposit per sale; when two are close (or cost the same), the longer one."
            ),
            1,
            1,
            1,
            true
        )
        local item = UI.sellSelected
        local qty = item and tonumber(UI.sellQty:GetText())
        local price = item and U.parseMoney(UI.sellPrice:GetText())
        local costs, choice, hours, source, cuts = nil, nil, nil, nil, nil
        if item then
            costs, choice, hours, source, cuts = F.Trade.durationCosts(item.key, qty or 1, price)
        end
        if costs then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format(L("Expected to sell in about %.1f h."), hours), 0.8, 0.8, 0.8)
            local from = source == "own posts" and L("From your own posts of it: sold against expired.")
                or source == "own sales" and L("From your own sales of it.")
                or L("From the market: the queue ahead of you and the sales an hour.")
            GameTooltip:AddLine(from, 0.8, 0.8, 0.8, true)
            if (cuts or 0) > 0 then
                GameTooltip:AddLine(string.format(L("Undercut about every %.1f h."), 1 / cuts), 0.8, 0.8, 0.8)
            end
            for d = 1, 3 do
                local lost = costs[d] == math.huge and "-" or U.money(math.floor(costs[d] + 0.5))
                UI.tipPair(
                    GameTooltip,
                    string.format(
                        L("%d h: deposit %s, lost per sale"),
                        F.Trade.DURATION_HOURS[d],
                        U.money(F.Trade.depositFor(item.key, qty or 1, d) or 0)
                    ),
                    lost,
                    d == choice and 0.25 or 1,
                    d == choice and 1 or 1,
                    d == choice and 0.25 or 1,
                    1,
                    1,
                    1
                )
            end
        elseif item then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L("Sales of this item are not measured yet: 24 hours."), 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    UI.durations[4]:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    UI.postButton = button(bar, "Post", 100, function()
        local item = UI.sellSelected
        if not item then
            return
        end
        local price = U.parseMoney(UI.sellPrice:GetText())
        local qty = tonumber(UI.sellQty:GetText())
        local ok, why = F.Trade.post(item, qty, price, F.Trade.durationFor(item.key, qty, price))
        F.Engine.notify(why)
        if ok and why == "post_sent" then
            UI.sellSelected = nil
            UI.sellPrice:SetText("")
        end
    end)
    UI.postButton:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -6, 4)
    UI.postNext = button(bar, "Post next bought", 165, function()
        local _, why = F.Trade.postNext()
        F.Engine.notify(why)
    end)
    UI.postNext:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 6, 4)
    UI.postAll = button(bar, "Post all", 105, function()
        local _, why = F.Trade.postAll()
        F.Engine.notify(why)
    end)
    UI.postAll:SetPoint("LEFT", UI.postNext, "RIGHT", 4, 0)
    -- Post all, except what a merchant pays at least as much for (the Best column says "Vendor").
    UI.postAuction = button(bar, "Post AH-worthy", 150, function()
        local _, why = F.Trade.postAll(true)
        F.Engine.notify(why)
    end)
    UI.postAuction:SetPoint("LEFT", UI.postAll, "RIGHT", 4, 0)
    for b, tip in pairs({
        [UI.postAll] = "Posts all available units of the next item for sale per click.",
        [UI.postAuction] = "Posts all available units of one item per click, only when the auction house pays more than a vendor, after the cut and the deposits (Best column). Items a vendor pays as much for stay in the bags for the merchant.",
    }) do
        UI.tip(b, nil, tip, "ANCHOR_TOP")
    end
    -- The bottom row holds the posting buttons; checking the selected item's price sits at the end
    -- of the rule row above.
    -- Check price: reads the selected item's listings again (selecting it already does once).
    UI.sellCheck = CreateFrame("Button", nil, bar)
    UI.sellCheck:SetSize(22, 22)
    UI.sellCheck:SetPoint("LEFT", UI.sellPrice, "RIGHT", 6, 0)
    if UI.sellCheck.SetNormalTexture then
        UI.sellCheck:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
        UI.sellCheck:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    end
    UI.sellCheck:SetScript("OnClick", function()
        if UI.sellSelected then
            F.Engine.message = nil
            F.Trade.checkPrice(UI.sellSelected.key)
            F.Engine.changed()
            UI.refresh()
        end
    end)
    UI.tip(UI.sellCheck, "Check price", "Reads the item's current listings again.", "ANCHOR_TOP")
end

-- Check Sure on the selected item of My items at `price` (as the price box reads it), for the
-- quantity in the box (else every unit held). What the units cost is known for bought stock.
function UI.checkSell(price)
    local item = UI.sellSelected
    local value = U.parseMoney(price or "")
    if not item or UI.sellView == "hidden" or not value or value <= 0 then
        return false
    end
    UI.sellSureCheck = { key = item.key, price = value }
    F.Engine.changed()
    UI.refresh()
    return true
end

function UI.sellCheckResult(item)
    local c = UI.sellSureCheck
    if not c or not item or c.key ~= item.key then
        return nil
    end
    local qty = tonumber(UI.sellQty:GetText()) or item.count or 1
    local p = item.position
    local cost = p and p.qty and p.qty > 0 and p.cost / p.qty * qty or nil
    return F.Deals.checkAt(item.key, c.price, qty, cost, nil, 0, F.Engine.clock())
end

-- Why an item is "AH / V": both routes for the `n` units held, as sums of the analytics, and what
-- the auction house is expected to bring once the chance it sells is counted.
--   AH      n x post - cut - deposits expected lost - cost = profit
--   Vendor  n x vendor price - cost = profit, at once
--   S       Sure of selling the n units at post within 48 h (Deals.sureAt)
--   E       S x AH revenue after the cut + (1 - S) x vendor revenue - lost deposits - cost: what
--           the auction house brings when an unsold lot still goes to a vendor afterwards
-- E above the vendor profit says the auction house pays for the wait; below it, the vendor.
function UI.choiceLines(item, w)
    local r = w.routes
    local a, v = r and r.auction, r and r.vendor
    if not (a and v) then
        return {}
    end
    local function m(x)
        return U.money(math.floor(math.abs(x) + 0.5))
    end
    local n = math.max(1, item.count or 1)
    local q = w.quote or {}
    local post = q.belowFloor and q.marketPost or q.post or 0
    local lines = {}
    lines[#lines + 1] = gold("AH")
        .. " "
        .. string.format(
            "%d x %s = %s - %s %s - %s %s - %s %s = %s%s",
            n,
            U.money(post),
            m(a.revenue),
            L("cut"),
            m(a.cut),
            L("lost deposits"),
            m(a.lost),
            L("cost"),
            m(a.cost),
            a.profit < 0 and "-" or "",
            m(a.profit)
        )
    lines[#lines + 1] = gold("Vendor")
        .. " "
        .. string.format(
            "%d x %s = %s - %s %s = %s%s, %s",
            n,
            U.money(q.vendor or 0),
            m(v.revenue),
            L("cost"),
            m(v.cost),
            v.profit < 0 and "-" or "",
            m(v.profit),
            L("at once")
        )
    local sure = post > 0 and F.Deals.sureAt(item.key, post, n) or nil
    if U.finite(sure) then
        local expected = sure * (a.revenue - a.cut) + (1 - sure) * v.revenue - a.lost - a.cost
        local pace = a.perDay and a.perDay > 0 and string.format(L("about %.1f days to sell %d"), n / a.perDay, n)
            or L("sales not measured")
        lines[#lines + 1] = gold("Expected")
            .. " "
            .. string.format(
                L("Sure %s x %s + (1 - Sure) x %s at a vendor - %s - %s = %s%s (%s)"),
                UI.sureText(sure),
                m(a.revenue - a.cut),
                m(v.revenue),
                m(a.lost),
                m(a.cost),
                expected < 0 and "-" or "",
                m(expected),
                pace
            )
        lines[#lines + 1] = expected > v.profit
                and string.format(
                    L("The auction house is expected to bring %s more than a vendor, if you can wait."),
                    m(expected - v.profit)
                )
            or string.format(L("A vendor pays %s more than the auction house is expected to."), m(v.profit - expected))
    end
    return lines
end

-- Bag items for sale, or (hidden = true) the hidden items, also those no longer in the bags.
local function sellItems(hidden)
    local positions = F.Data.char(F.db, F.Engine.owner()).positions
    local items, byKey = {}, {}
    for _, b in ipairs(F.AH.bagItems()) do
        if F.Trade.hidden(b.key) == (hidden and true or false) then
            local merged = byKey[b.key]
            if merged then
                merged.count = merged.count + b.count
            else
                b.position = positions[b.key]
                items[#items + 1] = b
                byKey[b.key] = b
            end
        end
    end
    if hidden then
        for _, h in ipairs(F.Trade.hiddenItems()) do
            if not byKey[h.key] then
                local item = U.parseKey(h.key)
                items[#items + 1] = { key = h.key, id = item and item.id, count = 0, name = h.name, away = true }
            end
        end
    end
    table.sort(items, function(a, b)
        if (a.position ~= nil) ~= (b.position ~= nil) then
            return a.position ~= nil
        end
        return a.key < b.key
    end)
    return items
end

-- Capture every item in the selected category, independently of pagination and later updates.
function UI.statusTargets()
    ---@type boolean|fun(key: string, complete: function): boolean
    local verifyDeals = false
    local keys, scope = {}, UI.section
    if UI.section == "deals" then
        scope, verifyDeals = "deals:" .. UI.filter, true
        for _, d in ipairs(F.Deals.visible(UI.filter)) do
            keys[#keys + 1] = d.key
        end
    elseif UI.section == "sell" then
        for _, item in ipairs(sellItems()) do
            keys[#keys + 1] = item.key
        end
    elseif UI.section == "auctions" or UI.section == "undercuts" then
        local seen = {}
        for _, a in ipairs(F.Trade.owned or {}) do
            if a.key and not a.sold and not seen[a.key] then
                seen[a.key] = true
                keys[#keys + 1] = a.key
            end
        end
    elseif UI.section == "shop" then
        -- The items on the shopping list are checked as deals: a lot under the list's maximum
        -- price becomes a shopping deal, one no longer there is dropped.
        verifyDeals = true
        for _, key in ipairs(F.Shopping.keys()) do
            keys[#keys + 1] = key
        end
    elseif UI.section == "bids" then
        verifyDeals = function(key, complete)
            return F.Bids.check(key, complete)
        end
        -- The list the page shows: this house's, without auctions that ended.
        for _, c in ipairs(F.Bids.current()) do
            keys[#keys + 1] = c.key
        end
    elseif UI.section == "crafting" then
        keys = F.Crafting.keys()
    elseif UI.section == "journal" then
        -- The journal lists purchases and what became of them, per item: checking them reads the
        -- current price of every item the page shows (the cheapest lots), so the figures behind the
        -- rows are as fresh as the deals'. The view (all, resale, to vendor, bids) chooses which
        -- items; a check is a price, not a deal, so `verifyDeals` stays false.
        local seen = {}
        for _, lot in ipairs(UI.journalLots()) do
            if lot.key and not seen[lot.key] then
                seen[lot.key] = true
                keys[#keys + 1] = lot.key
            end
        end
    else
        return nil, keys, false
    end
    -- Top to bottom as the page is sorted now; what the page does not show goes last.
    local list = UI.section == "deals" and "deals" or UI.section
    return scope, U.inOrder(keys, UI.order(list)), verifyDeals
end

function UI.checkStatuses()
    local scope, keys, verifyDeals = UI.statusTargets()
    if not scope or #keys == 0 then
        return
    end
    F.Deals.startBatch(scope, keys, verifyDeals)
    F.Engine.changed()
    UI.refresh()
end

-- A Best column's route, the same on My items and Crafting: AH green, Vendor orange, "AH / V" for
-- an open choice (Market.routeVerdict left it undecided). Nil for an unknown route.
function UI.routeLabel(way)
    if way == "undecided" then
        return UI.C.good .. L("AH") .. "|r / " .. UI.C.vendor .. L("V") .. "|r"
    end
    local r = UI.ROUTE[way]
    return r and r[1] .. L(r[2]) .. "|r" or nil
end

-- My items' Best column: the route alone (its price is in Sells at).
local function routeText(w)
    local label = UI.routeLabel(w.name)
    if not label then
        -- No auction price yet but a guess or a merchant's price: the likely route, greyed with a
        -- "?" so the row is never empty (the merchant's list and Post AH-worthy do not act on it).
        local q = w.quote
        if q and U.finite(q.net) and q.net > 0 and not (U.finite(q.vendor) and q.vendor >= q.net) then
            return UI.C.dim .. L("AH") .. "?|r"
        elseif q and U.finite(q.vendor) and q.vendor > 0 then
            return UI.C.dim .. L("Vendor") .. "?|r"
        end
        return UI.C.dim .. "-|r"
    end
    return label
end

-- What one unit sells for on a route: the auction house's price (the one the Price each box
-- gets) or what a vendor pays. Nil when the route has no price.
local function routePrice(w, way)
    local q = w.quote
    if not q then
        return nil
    end
    if way == "vendor" then
        return U.finite(q.vendor) and q.vendor > 0 and q.vendor or nil
    elseif way == "auction" then
        return not q.guess and U.finite(q.post) and q.post > 0 and q.post or nil
    end
end
-- The Sells at column: one unit's price on the chosen route, both when the player still has to
-- choose; a guess (no auction price yet) greyed with "~". The profit is on hover and below.
local function priceText(w)
    if w.name == "undecided" then
        local a, v = routePrice(w, "auction"), routePrice(w, "vendor")
        return (a and U.money(a) or "-") .. " / " .. (v and U.money(v) or "-")
    end
    local x = routePrice(w, w.name)
    if not x and w.name == "unknown" and w.quote then
        local q = w.quote
        local unit = U.finite(q.post) and q.post > 0 and q.post or U.finite(q.vendor) and q.vendor > 0 and q.vendor
        if unit then
            return UI.C.dim .. "~|r" .. U.money(unit)
        end
    end
    return x and U.money(x) or "-"
end
local function sortPrice(w)
    if w.name == "undecided" then
        return math.max(routePrice(w, "auction") or -math.huge, routePrice(w, "vendor") or -math.huge)
    end
    return routePrice(w, w.name)
end

-- The Note column's word for how stock came: the strategy it was bought for (F.STRATEGIES), else
-- its mode.
UI.STRATEGY_NOTE = { other = "other" }
for _, st in ipairs(F.STRATEGIES) do
    UI.STRATEGY_NOTE[st.id] = st.note
end

function UI.refreshSell()
    local hiddenView = UI.sellView == "hidden"
    local ways, sures = {}, {}
    local way
    -- Sure of selling the units held at the price the row would be posted at (Deals.sureAt); a
    -- gear ending with no sales of its own takes the one of the item's other endings (approx).
    local approxSure = {}
    local function sureOf(item)
        if sures[item.key] == nil then
            local q = way(item).quote
            local post = q and not q.guess and q.post
            local sure = post and post > 0 and item.count > 0 and F.Deals.sureAt(item.key, post, item.count)
            if not U.finite(sure) then
                local other = F.Deals.siblingEstimate(item.key, math.max(1, item.count or 1))
                if other and U.finite(other.sure) then
                    sure = other.sure
                    approxSure[item.key] = true
                end
            end
            sures[item.key] = U.finite(sure) and sure or false
        end
        return sures[item.key] or nil, approxSure[item.key] or false
    end
    function way(item)
        local w = ways[item.key]
        if not w then
            -- Each route judged apart (T11): "AH / V" (undecided) when the two both pass their
            -- thresholds and the player has not chosen one.
            local name, value, quote, routes, chosen, strategy = F.Trade.sellWay(item.key, item.id, item.count)
            local p = item.position
            w = { name = name, value = value, quote = quote, routes = routes, chosen = chosen, strategy = strategy }
            w.count = item.count
            w.cost = p
                    and U.finite(p.cost)
                    and U.finite(p.qty)
                    and p.qty > 0
                    and p.cost / p.qty * math.min(item.count or 0, p.qty)
                or 0
            ways[item.key] = w
        end
        return w
    end
    local items = UI.sellTable.sort(sellItems(hiddenView), function(item, column)
        local p = item.position
        local w = way(item)
        if column == 3 then
            return w.name
        elseif column == 4 then
            return sortPrice(w)
        elseif column == 5 then
            return (w.name == "auction" or w.name == "undecided") and sureOf(item) or nil
        end
        return ({
            item.name or U.linkName(item.link) or nameOf(item.key),
            item.count,
            nil,
            nil,
            nil,
            p and p.mode or nil,
        })[column]
    end)
    if UI.sellSelected then
        local found
        for _, it in ipairs(sellItems(hiddenView)) do
            if it.key == UI.sellSelected.key then
                found = it
                break
            end
        end
        if not found then
            UI.sellPrice:SetText("")
        end
        UI.sellSelected = found
    end
    local hiddenCount = #F.Trade.hiddenItems()
    -- The counts go on the views' entries in the menu.
    local kids = UI.menuKids or {}
    if kids["sell:sale"] then
        kids["sell:sale"].label:SetText(L("For sale") .. " (" .. #sellItems(false) .. ")")
    end
    if kids["sell:hidden"] then
        kids["sell:hidden"].label:SetText(L("Hidden") .. " (" .. hiddenCount .. ")")
    end
    -- "Return to sale" needs the width the Check Sure box takes on For sale (hidden there).
    UI.sellHide:SetWidth(hiddenView and 130 or 80)
    UI.layoutSellButtons()
    UI.sellHide:SetText(L(hiddenView and "Return to sale" or "Hide"))
    UI.sellCheckPrice:SetShown(not hiddenView)
    UI.sellSureButton:SetShown(not hiddenView)
    UI.sellSureReset:SetShown(not hiddenView)
    UI.sellHide:SetEnabled(UI.sellSelected ~= nil)
    UI.ruleToggle:SetEnabled(UI.sellSelected ~= nil and not hiddenView)
    local rule = UI.sellSelected and F.Trade.rule(UI.sellSelected.key)
    UI.ruleToggle:SetText(L("Rule") .. (rule and " " .. UI.C.good .. "*|r" or ""))
    if not UI.sellSelected or hiddenView then
        UI.rulePanel:Hide()
    end

    -- Check Sure of the selected item (UI.checkSell): its row shows Sure at the price checked and
    -- the price in Note, in blue, as Deals -> Resale shows a checked resale.
    local checked = not hiddenView and UI.sellSelected and UI.sellCheckResult(UI.sellSelected)
    for i, r in ipairs(UI.sellTable.rows) do
        local item = items[i]
        if item then
            r.item, r.key, r.link = item, item.key, item.link
            r.icon:SetTexture(icon(item.id))
            -- nameOf: a bag link named "[]" (the item not loaded, as during a scan) showed as "|...".
            local linked = item.link and U.linkName(item.link) ~= "" and item.link
            local named = type(item.name) == "string" and item.name ~= "" and item.name
            r.name:SetText(linked or named or nameOf(item.key, item.link))
            r.cols[1]:SetText(item.away and "-" or item.count)
            local p = item.position
            -- Best is the route alone, Sells at one unit's price on it (both routes while the
            -- player has to choose); both explain themselves on hover. Sure is the auction house's: a vendor
            -- buys at once.
            local w = way(item)
            r.bestWay = w
            r.bestName = item.name or U.linkName(item.link) or nameOf(item.key)
            r.cols[2]:SetText(routeText(w))
            r.cols[3]:SetText(priceText(w))
            local ah = w.name == "auction" or w.name == "undecided"
            local sure, approx = sureOf(item)
            r.cols[4]:SetText(
                (item.away or not ah) and "-"
                    or approx and (UI.C.dim .. "~" .. UI.pct(sure) .. "%|r")
                    or UI.sureText(sure)
            )
            if checked and UI.sellSelected.key == item.key then
                r.cols[4]:SetText(UI.sureText(checked.sure) .. (checked.thin and UI.C.warn .. "?|r" or ""))
                r.cols[5]:SetText(UI.C.info .. U.money(checked.price) .. "|r")
            elseif hiddenView then
                r.cols[5]:SetText(item.away and L("not in the bags") or L("hidden"))
            elseif w.name == "undecided" then
                r.cols[5]:SetText(UI.C.bad .. L("Choose") .. "|r")
            elseif w.chosen then
                r.cols[5]:SetText(UI.C.info .. L("your choice") .. "|r")
            else
                -- The Deals strategy it was bought for (it holds the route, Trade.boughtWay), else
                -- how it came; the header's tooltip says what each means.
                local s = w.strategy or p and p.mode
                r.cols[5]:SetText(UI.STRATEGY_NOTE[s] and L(UI.STRATEGY_NOTE[s]) or "")
            end
            if UI.sellSelected and UI.sellSelected.key == item.key then
                r.selected:Show()
                UI.sellSelected = item
            else
                r.selected:Hide()
            end
            r:Show()
        else
            r.item, r.key = nil, nil
            r:Hide()
        end
    end
    local empty = UI.sellTable.empty
    if #items == 0 then
        empty:SetText(
            hiddenView
                    and L(
                        "No hidden items. Select an item under For sale and press Hide to keep it out of the list and out of Post all."
                    )
                or L("No items in your bags can be sold on the auction house.")
        )
        empty:Show()
    else
        empty:Hide()
    end
    if hiddenView then
        UI.sellBox.set({
            UI.sellSelected and L("Return to sale puts the item back in the list and in Post all.")
                or L(
                    "Hidden items are not shown for sale and Post all and Post next bought skip them. Select one to return it."
                ),
        }, "hidden")
        UI.postButton:Disable()
        UI.sellCheck:Disable()
        UI.sellSureButton:Disable()
        UI.sellSureReset:Disable()
        UI.chooseAH:Hide()
        UI.chooseVendor:Hide()
        UI.ruleSave:Disable()
        UI.refreshPostNext()
        UI.refreshPostAll()
        return
    end
    for _, b in ipairs(UI.durations) do
        b:SetText(L(UI.durationLabel(b.value)))
        b:SetEnabled(F.db.settings.duration ~= b.value)
    end
    UI.refreshPostAll()
    UI.ruleSave:SetEnabled(UI.sellSelected ~= nil)
    local item = UI.sellSelected
    if not item then
        UI.sellBox.set({ L("Select an item. Its current listings are read to suggest a price.") }, "empty")
        UI.postButton:Disable()
        UI.refreshPostNext()
        UI.sellCheck:Disable()
        UI.sellSureButton:Disable()
        UI.sellSureReset:Disable()
        UI.chooseAH:Hide()
        UI.chooseVendor:Hide()
        return
    end
    if UI.sellSureCheck and UI.sellSureCheck.key ~= item.key then
        UI.sellSureCheck = nil -- a check belongs to its item
    end
    -- The player's route (AH / V) is reset with the check.
    UI.sellSureReset:SetEnabled(UI.sellSureCheck ~= nil or F.Trade.routeChoice(item.key) ~= nil)
    UI.sellCheck:SetEnabled(not F.Deals.pending(item.key) and not F.Trade.busy() and not F.Scan.blocking())
    -- One sum for the page, the tooltip and the Best column (F.Trade.quote, through way()); read
    -- first, it also takes the prices of a full scan up to 5 minutes old.
    way(item)
    local price, floor, cheapest, why = F.Trade.suggest(item)
    -- Best and why come first: the reason for the route is what the footer is read for. The
    -- routes follow the price lines (UI.bestLines).
    local w = way(item)
    local verdict, routes = UI.bestLines(w)
    -- Only for a really open item (or one the player already chose for, to switch it).
    local open = w.name == "undecided" or w.chosen
    UI.chooseAH:SetShown(open and true or false)
    UI.chooseVendor:SetShown(open and true or false)
    UI.chooseAH:SetEnabled(not (w.chosen and w.name == "auction"))
    UI.chooseVendor:SetEnabled(not (w.chosen and w.name == "vendor"))
    local lines = {}
    local checked = UI.sellCheckResult(item)
    if checked then
        for _, line in ipairs(UI.checkLines(checked)) do
            lines[#lines + 1] = line
        end
    end
    for _, line in ipairs(verdict) do
        lines[#lines + 1] = line
    end
    -- Both routes pay and the player decides (or decided): the sums of each (UI.choiceLines).
    if open then
        for _, line in ipairs(UI.choiceLines(item, w)) do
            lines[#lines + 1] = line
        end
    end
    if item.position and item.position.mode == "vendor" then
        lines[#lines + 1] = L("Bought as a vendor deal: sell it to any vendor (button at the merchant).")
    end
    if price and not F.Trade.prices[item.key] and F.Scan.notListed(item.key) then
        lines[#lines + 1] = string.format(L("Nobody listed it at the last full scan (%s)."), UI.age(F.Scan.last.at))
    elseif price and F.Trade.noAnswer[item.key] and not F.Trade.prices[item.key] then
        lines[#lines + 1] = L("The auction house did not answer the check: nobody seems to sell it.")
    end
    if price then
        local suggested = U.plainMoney(math.max(price, floor or 0))
        local typing = UI.sellPrice.HasFocus and UI.sellPrice:HasFocus()
        local shown = UI.sellPrice:GetText()
        if not typing and (shown == "" or shown == UI.sellPriceAuto) and shown ~= suggested then
            UI.sellPrice:SetText(suggested)
            UI.sellPriceAuto = suggested
        end
        if F.Deals.pending(item.key) then
            -- A check is on the way: the price shown is the last one known.
            lines[#lines + 1] = UI.C.gold .. L("Reading current listings...") .. "|r"
        end
        if F.Trade.GUESSES[why] and UI.sellPrice.SetTextColor then
            UI.sellPrice:SetTextColor(1, 0.82, 0)
        elseif UI.sellPrice.SetTextColor then
            UI.sellPrice:SetTextColor(1, 1, 1)
        end
        -- Every suggestion names the price the box gets: never below the floor (break-even, rule).
        if why == "normal" and cheapest then
            lines[#lines + 1] = gold("Price")
                .. " "
                .. string.format(
                    L("The cheapest other seller asks %s, above the maximum. Suggested: the normal price %s."),
                    U.money(cheapest),
                    U.money(math.max(price, floor or 0))
                )
        elseif UI.FALLBACK_TEXT[why] then
            lines[#lines + 1] = gold("Price")
                .. " "
                .. string.format(L(UI.FALLBACK_TEXT[why]), U.money(math.max(price, floor or 0)))
            if F.Trade.GUESSES[why] then
                lines[#lines + 1] = UI.C.gold
                    .. L(
                        "This is a guess: check the price, change it if needed and press Post. Post next bought and Post all skip guessed prices."
                    )
                    .. "|r"
            end
        else
            lines[#lines + 1] = gold("Price")
                .. " "
                .. (
                    cheapest
                        and string.format(
                            L("Cheapest other seller: %s each. Suggested: %s."),
                            U.money(cheapest),
                            U.money(math.max(price, floor or 0))
                        )
                    or L("Nobody else sells it now. Suggested: the usual asking price.")
                )
        end
    elseif F.Deals.search and F.Deals.search.key == item.key then
        lines[#lines + 1] = L("Reading current listings...")
    elseif F.Deals.pending(item.key) then
        lines[#lines + 1] = L("queued")
    elseif F.Trade.prices[item.key] and F.Engine.clock() - F.Trade.prices[item.key].at <= 300 then
        lines[#lines + 1] = L(
            "Nobody sells it on the auction house now and ForeverFlip knows no price for it. Type a price and press Post; it is remembered for the next time."
        )
    elseif F.Trade.noAnswer[item.key] and F.Engine.clock() - F.Trade.noAnswer[item.key] <= 300 then
        lines[#lines + 1] =
            L("The auction house did not answer the check. Press Check price again, or type a price and press Post.")
    else
        lines[#lines + 1] = L("Press Check price to read the current listings.")
    end
    for _, line in ipairs(routes) do
        lines[#lines + 1] = line
    end
    local h = F.Data.market(F.db, F.Engine.scope()).history[item.key]
    -- What buyers really paid (sales seen between full scans), and how much sells a day at the price.
    local sale = h and F.Market.salePrice(h)
    local demand = price and h and F.Deals.saleability(item.key, h, price, F.Engine.clock())
    local market = {}
    if sale then
        market[#market + 1] = string.format(L("buyers paid about %s lately"), U.money(sale))
    end
    if demand and demand.known then
        market[#market + 1] = string.format(
            L("at %s about %s a day sell"),
            U.money(price),
            demand.perDay == 0 and "0" or string.format("%.1f", demand.perDay)
        )
    end
    if #market > 0 then
        lines[#lines + 1] = gold("Market") .. " " .. table.concat(market, "; ") .. "."
    end
    local timing = h and F.Market.timing(h, F.Engine.clock())
    if timing and timing.ready and timing.now <= 0.95 and timing.spread >= 0.08 then
        lines[#lines + 1] = string.format(
            L("Prices for it are usually %d%% higher on %s: posting then may pay more."),
            UI.pct(timing.high.f / timing.now - 1),
            UI.slotName(timing.high)
        )
    end
    if floor then
        lines[#lines + 1] = string.format(
            L("Minimum after the %d%% cut, margin and rules: %s each."),
            UI.pct(F.Market.CUT),
            U.money(floor)
        )
        if price and price < floor then
            lines[#lines + 1] = UI.C.bad
                .. L("The market is below your minimum: wait, change the rule, or choose another sale route.")
                .. "|r"
        end
    end
    UI.sellBox.set(lines, item.key)
    UI.sellSureButton:SetEnabled(U.parseMoney(UI.sellCheckPrice:GetText() or "") ~= nil)
    UI.postButton:SetEnabled(UI.sellPrice:GetText() ~= "" and F.Trade.wayReady())
    UI.refreshPostNext()
    UI.postButton:SetText(F.Trade.pendingPost and L("Confirm post") or L("Post"))
end

-- My auctions page ---------------------------------------------------------------------------------
function UI.createAuctions(p)
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 60)
    UI.auctionTable = table_(
        list,
        {
            { "Name" },
            { "Qty", 50 },
            { "My price", 86 },
            { "Cheapest other", 104 },
            { "Status", 126, "LEFT" },
            { "Time", 70 },
        },
        16,
        function(row)
            UI.ownedSelected = row.auction and row.auction.auctionID
            F.Engine.changed()
            UI.refresh()
        end
    )
    local bar = footer(p, 56)
    -- Centered on top, as in Auctionator's Cancelling tab: what is on sale and what is on its way.
    UI.auctionTotal = text(bar, "GameFontHighlight") -- white, as in Auctionator
    UI.auctionTotal:SetPoint("TOP", bar, "TOP", 0, -6)
    UI.auctionText = bar.text
    UI.auctionText:ClearAllPoints()
    UI.auctionText:SetPoint("TOPLEFT", bar, "TOPLEFT", 8, -20)
    UI.auctionText:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -8, -20)
    UI.auctionText:SetWordWrap(false)
    UI.cancelAuction = button(bar, "Cancel auction", 140, function()
        for _, a in ipairs(F.Trade.owned) do
            if a.auctionID == UI.ownedSelected then
                F.Trade.cancelAuction(a)
            end
        end
    end)
    UI.cancelAuction:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -6, 4)
    UI.refreshOwned = button(bar, "Refresh", 100, function()
        F.Trade.ownedDue = 0
    end)
    UI.refreshOwned:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 6, 4)
    UI.checkOwned = button(bar, "Check prices", 130, function()
        F.Trade.checkOwned()
        UI.refreshAuctions()
    end)
    UI.checkOwned:SetPoint("LEFT", UI.refreshOwned, "RIGHT", 4, 0)
    -- A real search of the selected auction's item: Check all answers an item nobody else sold at
    -- the last scan from that scan (T10), this asks the server now.
    UI.searchOwned = button(bar, "Search", 80, function()
        for _, a in ipairs(F.Trade.owned or {}) do
            if a.auctionID == UI.ownedSelected and a.key and not a.sold then
                F.Trade.checkPrice(a.key)
                break
            end
        end
        UI.refreshAuctions()
    end)
    UI.searchOwned:SetPoint("LEFT", UI.checkOwned, "RIGHT", 4, 0)
    -- The undercut advice and the cancel cost sit between the buttons, never over them.
    UI.auctionText:ClearAllPoints()
    UI.auctionText:SetPoint("LEFT", UI.searchOwned, "RIGHT", 8, 0)
    UI.auctionText:SetPoint("RIGHT", UI.cancelAuction, "LEFT", -8, 0)
end

-- Selling, Undercuts (anti-undercut): every undercut auction, the advice, and every option priced
-- (T.fightPlan); the player picks one with its button.
local OPTION = {
    wait = { UI.C.gold, "wait" },
    undercut = { UI.C.good, "undercut" },
    buyout = { UI.C.info, "buy out" },
    raise = { UI.C.purple, "raise" },
    vendor = { UI.C.warn, "to a vendor" },
}

function UI.createUndercuts(p)
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 150)
    UI.undercutTable = table_(
        list,
        {
            { "Name" },
            { "Qty", 50 },
            { "My price", 86 },
            { "Cheapest other", 104 },
            { "Ahead", 64 },
            { "Advice", 110, "LEFT" },
        },
        10,
        function(row)
            UI.fightSelected = row.plan and row.plan.auction.auctionID
            F.Engine.changed()
            UI.refresh()
        end
    )
    local bar = footer(p, 146, "GameFontHighlightSmall")
    bar.text:Hide()
    UI.fightBox = UI.scrollText(bar, 7, 6, 26)
    UI.fightText = UI.fightBox.text
    UI.fightButtons = {}
    local last
    for _, id in ipairs({ "wait", "undercut", "buyout", "raise", "vendor" }) do
        local b = button(bar, OPTION[id][2], 96, function()
            local job = F.Trade.fightOrderActive()
            for _, plan in ipairs(F.Trade.fightPlans()) do
                if plan.auction.auctionID == UI.fightSelected then
                    if job and id == "buyout" then
                        -- One buy-out runs at a time: the button carries it on (as Answer next does)
                        -- for its own item only; another item's would replace it, nothing bought.
                        if plan.key == job.key then
                            F.Trade.fightOrderClick()
                        end
                    else
                        F.Trade.fight(plan, id)
                    end
                end
            end
            UI.refresh()
        end)
        if last then
            b:SetPoint("LEFT", last, "RIGHT", 4, 0)
        else
            b:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 6, 4)
        end
        UI.fightButtons[id] = b
        last = b
    end
    UI.fightNext = button(bar, "Answer next", 130, function()
        local _, why = F.Trade.fightNext()
        F.Engine.notify(why)
    end)
    UI.fightNext:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -6, 4)
end

local function percent(p)
    return UI.pctText(p)
end

-- Each option in two lines: its name, expected money and chance first (the advice marked), then in
-- grey what it does. Blocked options say why.
local function optionLines(plan, o)
    local a = plan.auction
    local v = OPTION[o.id]
    local best = plan.best == o
    local head = UI.optionHead(best, v[1], v[2])
    local detail = UI.optionDetail
    if o.blocked == "floor" then
        return {
            head .. "  " .. L("not offered"),
            detail(string.format(L("%s would be below your floor of %s"), U.money(plan.new), U.money(plan.floor))),
        }
    elseif o.blocked == "many" then
        return {
            head .. "  " .. L("not offered"),
            detail(string.format(L("%d cheaper units are too many to buy"), o.units)),
        }
    elseif o.blocked == "money" then
        return {
            head .. "  " .. L("not offered"),
            detail(string.format(L("the cheaper units cost %s, more than one deal may use"), U.money(o.cost))),
        }
    end
    local value = o.ev and U.money(math.floor(math.max(0, o.ev))) or "?"
    local advised = UI.optionMark(best, "(advised)")
    local function sells(units, of)
        return string.format(L("sells %.1f of %d on average"), units or 0, of)
    end
    if o.id == "wait" then
        if o.unknown then
            return {
                head .. "  " .. L("chance unknown") .. advised,
                detail(L("keep it: no sales were measured yet, so how soon it sells is unknown")),
            }
        end
        return {
            head .. "  " .. string.format(
                L("expected %s  ·  %s chance all sell in the %s left"),
                value,
                percent(o.p),
                UI.duration(a.timeLeft or 0)
            ) .. advised,
            detail(
                string.format(
                    L("keep it behind %d cheaper units; %s"),
                    plan.ahead + (plan.ownAhead or 0),
                    sells(o.units, a.qty)
                )
            ),
        }
    elseif o.id == "undercut" then
        if o.guess then
            return {
                head .. "  " .. string.format(L("brings %s if it sells (chance unknown)"), value) .. advised,
                detail(
                    string.format(L("cancel (about %s lost) and post at %s"), U.money(plan.cancel), U.money(plan.new))
                ),
            }
        end
        return {
            head .. "  " .. string.format(
                L("expected %s  ·  %s chance to sell  ·  %s a rival answers first"),
                value,
                percent(o.p),
                percent(o.answered)
            ) .. advised,
            detail(
                string.format(
                    L("cancel (about %s lost) and post at %s for %d h; %s"),
                    U.money(plan.cancel),
                    U.money(plan.new),
                    o.hours,
                    sells(o.units, a.qty)
                )
            ),
        }
    elseif o.id == "buyout" then
        local price = a.price or 0
        if o.unknown then
            return {
                head .. "  " .. L("chance unknown") .. advised,
                detail(
                    string.format(
                        L("buy the %d cheaper units for %s and resell them at %s"),
                        o.units,
                        U.money(o.cost),
                        U.money(price)
                    )
                ),
            }
        end
        return {
            head .. "  " .. string.format(
                L("expected %s with yours  ·  %s on the bought units once sold"),
                value,
                UI.signed(F.Market.net(price, o.units) - o.cost)
            ) .. advised,
            detail(
                string.format(
                    L("buy the %d cheaper units for %s and resell them at %s"),
                    o.units,
                    U.money(o.cost),
                    U.money(price)
                )
            ),
        }
    elseif o.id == "raise" then
        return {
            head
                .. "  "
                .. string.format(L("expected %s  ·  %s chance all sell in a day"), value, percent(o.p))
                .. advised,
            detail(
                string.format(
                    L("buy the %d units below %s for %s, cancel yours and post all at %s; %s"),
                    o.units,
                    U.money(o.target),
                    U.money(o.cost),
                    U.money(o.target),
                    sells(o.expect, a.qty + o.units)
                )
            ),
        }
    end
    return {
        head .. "  " .. string.format(L("brings %s at once"), value) .. advised,
        detail(L("cancel and sell to a merchant")),
    }
end

-- What the selected undercut is about, one line each: the auction, its sales, rivals, the unsold.
local function situationLines(plan)
    local a = plan.auction
    local lines = {
        string.format(
            L("%s %d at %s, %s left  ·  %d cheaper units ahead, the cheapest at %s"),
            gold("Your auction"),
            a.qty or 1,
            U.money(a.price or 0),
            UI.duration(a.timeLeft or 0),
            plan.ahead + (plan.ownAhead or 0),
            U.money(plan.cheapest)
        ),
    }
    if plan.rate then
        lines[#lines + 1] = string.format(
            L("%s about %.1f a day at your price (%.0f seen in %d h of scans)%s"),
            gold("Sales"),
            plan.rate,
            plan.sold or 0,
            math.floor(plan.hours or 0),
            plan.thin and ("  ·  " .. L("few seen, chances kept wide")) or ""
        )
    else
        lines[#lines + 1] = gold("Sales") .. " " .. L("none measured yet: two full scans measure them")
    end
    if (plan.answers or 0) >= 0.5 then
        lines[#lines + 1] = string.format(
            L("%s answer about %.1f times a day: an undercut lasts about %s"),
            gold("Rivals"),
            plan.answers,
            UI.duration(86400 / plan.answers)
        )
    end
    if plan.war then
        lines[#lines + 1] = UI.C.bad
            .. L("Price war")
            .. "|r  "
            .. (
                (plan.rounds or 0) > 0
                    and string.format(L("you answered %d times today and were undercut again"), plan.rounds)
                or L("rivals answer within hours; each new post costs a deposit")
            )
    end
    if plan.fallback then
        lines[#lines + 1] = string.format(
            L("%s a unit coming back is worth %s posted again"),
            gold("Unsold"),
            U.money(math.floor(plan.fallback)) -- already the worth of one unit
        )
    end
    return lines
end

-- The Advice column sorts in the order the options are offered.
local ADVICE_RANK = { wait = 1, undercut = 2, buyout = 3, raise = 4, vendor = 5 }

function UI.refreshUndercuts()
    local plans = F.Trade.fightPlans()
    -- Counted over the plans just made: each plan walks the sale model, too dear to make twice.
    local act, selected = F.Trade.fightCount(plans), nil
    -- The selected plan keeps its details and buttons while its row is scrolled out of view.
    for _, plan in ipairs(plans) do
        if plan.auction.auctionID == UI.fightSelected then
            selected = plan
        end
    end
    -- The rows show the sorted part in view; the counts below stay over every plan.
    local shown = UI.undercutTable.sort(plans, function(plan, column)
        local a = plan.auction
        return ({
            nameOf(a.key or ("i:" .. a.id), a.link),
            a.qty,
            a.price,
            plan.cheapest,
            plan.ahead,
            ADVICE_RANK[plan.ordering and "buyout" or plan.verdict],
        })[column]
    end)
    for i, r in ipairs(UI.undercutTable.rows) do
        local plan = shown[i]
        if plan then
            local a = plan.auction
            r.plan, r.key, r.link = plan, a.key, a.link
            r.icon:SetTexture(icon(a.id))
            r.name:SetText(nameOf(a.key or ("i:" .. a.id), a.link))
            r.cols[1]:SetText(a.qty)
            r.cols[2]:SetText(U.money(a.price or 0))
            r.cols[3]:SetText(U.money(plan.cheapest))
            r.cols[4]:SetText(plan.ahead)
            local v = OPTION[plan.verdict]
            -- A running buy-out is not an advice any more: the decision is taken and the cheaper
            -- units are being bought. The row stays so the button can carry it on.
            -- An auction the player chose to leave (wait, or a buy-out order that ended) is skipped
            -- by Answer next until its prices change: it says so instead of its advice.
            local left = F.Trade.waiting and F.Trade.waiting[a.auctionID] == plan.cheapest
            local bought = left and F.Trade.waitWhy and F.Trade.waitWhy[a.auctionID] == "bought"
            r.cols[5]:SetText(
                plan.ordering and (UI.C.info .. L("buy out running") .. "|r")
                    or bought and (UI.C.dim .. L("bought") .. "|r")
                    or left and (UI.C.dim .. L(OPTION.wait[2]) .. "|r")
                    or (v[1] .. L(v[2]) .. "|r" .. (plan.war and " " .. UI.C.bad .. "!|r" or ""))
            )
            if plan == selected then
                r.selected:Show()
            else
                r.selected:Hide()
            end
            r:Show()
        else
            r.plan, r.key = nil, nil
            r:Hide()
        end
    end
    local empty = UI.undercutTable.empty
    if #plans == 0 then
        empty:SetText(
            L(
                "None of your checked auctions is undercut. Check prices on My auctions, or wait for the next full scan: it checks them by itself."
            )
        )
        empty:Show()
    else
        empty:Hide()
    end
    local lines = {}
    if selected then
        lines = situationLines(selected)
        for _, o in ipairs(selected.options) do
            for _, line in ipairs(optionLines(selected, o)) do
                lines[#lines + 1] = line
            end
        end
        -- Why Answer next has nothing to do when the advice is "wait": the button is not blocked,
        -- there is simply no action it would take (waiting is the action). Said in words, since a
        -- count of 0 next to a list of undercuts otherwise reads as a broken button.
        if selected.ordering then
            lines[#lines + 1] = UI.C.info
                .. string.format(
                    L(
                        "A buy out of this auction is running: %d cheaper units are on the shopping list. Press buy out again for the next one; the row leaves this list once it is done."
                    ),
                    (selected.buyout and selected.buyout.units) or 0
                )
                .. "|r"
        elseif selected.verdict == "wait" then
            lines[#lines + 1] = UI.C.dim
                .. L(
                    "Answer next leaves this one alone: keeping it is what pays most, and it takes only the auctions whose advice is an action (undercut, buy out, raise, a merchant). The buttons above work whichever is advised, if you prefer another way out."
                )
                .. "|r"
        end
    elseif #plans > 0 then
        lines[1] = string.format(L("|cffffd100Undercut:|r %d of your auctions  ·  acting pays on %d"), #plans, act)
        lines[2] = L("Click a row: every way out is priced (wait, undercut, buy out, raise, a merchant),")
        lines[3] = L("the best is advised, and you choose. Answer next takes the advised step for you.")
    else
        lines[1] = L("Anti-undercut: when another seller lists your item cheaper, every way out is priced")
        lines[2] = L("from the measured sales (wait, undercut, buy out, raise, a merchant), and you choose.")
    end
    UI.fightBox.set(lines, selected and selected.auction.auctionID or #plans)
    -- Every offered way out stays clickable, whatever is advised (the advice is a recommendation, not
    -- a lock). One buy-out runs at a time, so while a job runs only its own item's "buy out" goes on:
    -- a click acts on the selection, and another item's would replace the order that is running.
    local job = F.Trade.fightOrderActive()
    for id, b in pairs(UI.fightButtons) do
        local o = selected and selected[id]
        local offers = o ~= nil and not o.blocked and (id == "wait" or F.Trade.wayReady())
        if job and id == "buyout" then
            offers = selected ~= nil and selected.key == job.key and F.Trade.fightOrderClickable()
        end
        b:SetEnabled(offers or false)
    end
    -- DEV log: why a way out cannot be clicked, once per change of the selection or of its state.
    if selected then
        local why = {}
        for _, id in ipairs({ "wait", "undercut", "buyout", "raise", "vendor" }) do
            local b, o = UI.fightButtons[id], selected[id]
            if b and not b:IsEnabled() then
                why[#why + 1] = id
                    .. "="
                    .. (o == nil and "not offered" or o.blocked and ("blocked " .. tostring(o.blocked)) or "way busy")
            end
        end
        local state = tostring(selected.auction.auctionID) .. " " .. table.concat(why, ", ")
        if state ~= UI.fightButtonsState then
            UI.fightButtonsState = state
            F.Log.trace(
                "fight.buttons",
                "%s auction %s disabled: %s; job %s, open %s, busy %s, posting %s, searching %s, sniper %s, throttle %s",
                tostring(selected.key),
                tostring(selected.auction.auctionID),
                #why > 0 and table.concat(why, ", ") or "none",
                job and tostring(job.key) or "-",
                tostring(F.AH.isOpen()),
                tostring(F.Trade.busy()),
                tostring(F.Trade.postingNow()),
                tostring(F.Deals.searching()),
                tostring(F.Sniper.inFlight()),
                tostring(not F.AH.ready(false))
            )
        end
    end
    UI.fightNext:SetText(L("Answer next") .. " (" .. act .. ")")
    UI.fightNext:SetEnabled(
        act > 0
            and (
                F.Trade.fightOrderActive() and F.Trade.fightOrderClickable()
                or not F.Trade.fightOrderActive() and F.Trade.wayReady()
            )
    )
end

function UI.refreshAuctions()
    local owned = UI.auctionTable.sort(F.Trade.owned or {}, function(a, column)
        local status, cheapest = F.Trade.ownedStatus(a)
        local rank = status == "sold" and 1
            or status == "undercut" and 2
            or (status == "cheapest" or status == "alone") and 3
            or 4
        return ({ nameOf(a.key or "", a.link), a.qty, a.price, cheapest, rank, a.timeLeft })[column]
    end)
    local selected, undercut = nil, 0
    for i, r in ipairs(UI.auctionTable.rows) do
        local a = owned[i]
        if a then
            r.auction, r.key, r.link = a, a.key, a.link
            r.icon:SetTexture(icon(a.id))
            r.name:SetText(nameOf(a.key or ("i:" .. a.id), a.link))
            r.cols[1]:SetText(a.qty)
            r.cols[2]:SetText(U.money(a.price or 0))
            local status, cheapest, asOf = F.Trade.ownedStatus(a)
            r.cols[3]:SetText(cheapest and U.money(cheapest) or "-")
            if asOf and status == "alone" then
                -- From the full scan, not a search (T10): marked, and said under the table.
                status = "alone_scan"
            end
            if status == "sold" then
                r.cols[4]:SetText(UI.C.good .. L("sold") .. "|r")
            elseif status == "undercut" then
                r.cols[4]:SetText(UI.C.bad .. L("undercut") .. "|r")
            elseif status == "cheapest" then
                r.cols[4]:SetText(UI.C.good .. L("cheapest") .. "|r")
            elseif status == "alone" then
                r.cols[4]:SetText(UI.C.good .. L("only yours") .. "|r")
            elseif status == "alone_scan" then
                r.cols[4]:SetText(UI.C.good .. L("only yours") .. "|r" .. UI.C.dim .. "*|r")
            elseif status == "no_answer" then
                r.cols[4]:SetText(UI.C.gold .. L("no answer") .. "|r")
            elseif status == "pending" then
                r.cols[4]:SetText(UI.C.gold .. L("checking...") .. "|r")
            else
                r.cols[4]:SetText(UI.C.dim .. L("not checked") .. "|r")
            end
            r.cols[5]:SetText(a.sold and "" or a.timeLeft and UI.duration(a.timeLeft) or "-")
            if a.auctionID == UI.ownedSelected then
                r.selected:Show()
                selected = a
            else
                r.selected:Hide()
            end
            r:Show()
        else
            r.auction, r.key = nil, nil
            r:Hide()
        end
    end
    local empty = UI.auctionTable.empty
    if #owned == 0 then
        empty:SetText(L("You have no auctions, or the list has not loaded yet (press Refresh)."))
        empty:Show()
    else
        empty:Hide()
    end
    local queue = F.Trade.checksRemaining()
    -- Total on sale (price of one unit x quantity of every auction still listed) and pending
    -- (sold, the gold on its way by mail), centered as in Auctionator's Cancelling tab.
    -- The undercut count covers every auction too, not only the rows in view.
    local onSale, pending = 0, 0
    for _, a in ipairs(F.Trade.owned or {}) do
        local value = a.total or (a.price or 0) * (a.qty or 1)
        if a.sold then
            pending = pending + value
        else
            onSale = onSale + value
        end
        if F.Trade.ownedStatus(a) == "undercut" then
            undercut = undercut + 1
        end
    end
    UI.auctionTotal:SetText(
        #(F.Trade.owned or {}) > 0
                and string.format(L("Total on sale: %s (%s pending)"), U.money(onSale), U.money(pending))
            or ""
    )
    local lines = {}
    if queue == 0 and undercut > 0 then
        lines[#lines + 1] = string.format(L("Undercut: %d"), undercut)
    end
    local searchable = selected ~= nil and not selected.sold and selected.key ~= nil
    if searchable then
        local status, _, asOf = F.Trade.ownedStatus(selected)
        if status == "alone" and asOf then
            lines[#lines + 1] = string.format(
                L("*Only yours as of the scan %s ago: Search checks it now."),
                UI.duration(math.max(60, F.Engine.clock() - asOf))
            )
        end
        local cost = F.AH.cancelCost(selected.auctionID)
        lines[#lines + 1] = string.format(L("Cancel cost besides the deposit: %s."), U.money(cost or 0))
    end
    UI.auctionText:SetText(table.concat(lines, "  ·  "))
    UI.searchOwned:SetEnabled(searchable and not F.Deals.pending(selected.key) or false)
    UI.cancelAuction:SetEnabled(selected ~= nil and not selected.sold and F.Trade.wayReady())
    UI.checkOwned:SetEnabled(#owned > 0 and queue == 0)
end
