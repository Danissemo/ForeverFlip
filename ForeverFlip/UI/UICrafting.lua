-- ForeverFlip window: Crafting page.
-- Moved from UI.lua as it was and loaded after it (ForeverFlip.toc); locals of the
-- earlier UI files come through UI.shared.
local UI = ForeverFlip.UI
local S = UI.shared
local F = S.F
local U = S.U
local L = S.L
local button = S.button
local icon = S.icon
local table_ = S.table_
local footer = S.footer
local gold = S.gold

-- Crafting page ------------------------------------------------------------------------------------
local CRAFT_ROWS = 15
function UI.createCrafting(p)
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 108)
    UI.craftTable = table_(
        list,
        {
            { "Name" },
            { "Materials", 86 },
            { "Product", 86 },
            { "Profit", 86 },
            { "Est./day", 66 },
            { "Sure", 60 },
            { "Best", 70, "LEFT" },
        },
        CRAFT_ROWS,
        function(row)
            UI.craftSelected = row.recipe
            UI.refresh()
        end
    )
    UI.craftTable.rowTooltip = function(row)
        if row.recipe then
            UI.craftTooltip(row, row.recipe)
            return true
        end
    end
    -- 104 px: four text rows of 14 from 20 below the top end at 76, above the buttons (22 high, 4
    -- above the bottom: their top is 78). At 72 px the rows and the bar ran into the buttons. The
    -- table keeps its 15 rows: 432 - 108 = 324 = 24 + 15 x 20.
    local bar = footer(p, 104)
    UI.craftText = bar.text
    -- The professions are a list as long as the character has professions: a plain font string ran
    -- off the bottom of the window. The scrolling block reaches every line (the box height is its 4
    -- rows; a wheel or the bar shows the rest), and its own text is hidden.
    UI.craftProfText = UI.scrollText(bar, 4, 20, 0, 56)
    UI.craftProfButton = button(bar, "Learned professions", 150, function()
        UI.craftProfOpen = not UI.craftProfOpen
        UI.refreshCrafting()
    end)
    UI.craftProfButton:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 6, 4)
    -- Recipes the character has not learned cannot be crafted: this leaves them out of the table.
    -- The label carries the count, so the player sees what is hidden before turning it off.
    UI.craftHideButton = button(bar, "Learned recipes only", 160, function()
        F.db.settings.hideUnlearned = not F.db.settings.hideUnlearned
        UI.craftSelected = nil
        F.Engine.changed()
        UI.refresh()
    end)
    UI.craftHideButton:SetPoint("LEFT", UI.craftProfButton, "RIGHT", 4, 0)
    -- The plan under the table (F.Crafting.plan) goes on the shopping list: the units to buy of
    -- each material, at the dearest price that keeps the crafts paying.
    UI.craftShop = button(bar, "Shop materials", 150, function()
        local r = UI.craftSelected
        if r then
            local n = F.Crafting.shopMaterials(r.id)
            F.Engine.notify(n > 0 and "craft_saved" or "craft_nothing")
        end
    end)
    UI.craftShop:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -6, 4)
end

function UI.refreshCrafting()
    local rows = UI.craftTable.sort(F.Crafting.profits(), function(e, column)
        return ({ e.name, e.cost, e.value, e.profit, e.perDay, e.route ~= "vendor" and e.sure or -1, e.route })[column]
    end)
    for i, r in ipairs(UI.craftTable.rows) do
        local e = rows[i]
        if e then
            r.recipe, r.key = e, nil
            r.icon:SetTexture(icon(e.out))
            -- A recipe not learned is greyed with a mark: with the setting off it is still listed,
            -- and the player must be able to tell it apart from one that can be crafted.
            local name = e.name or ("#" .. e.id)
            r.name:SetText(
                e.learned == false and (UI.C.dim .. name .. "|r " .. UI.C.dim .. L("(not learned)") .. "|r") or name
            )
            r.cols[1]:SetText(e.cost and U.money(e.cost) or "?")
            r.cols[2]:SetText(e.value and U.money(e.value) or "?")
            if e.profit then
                r.cols[3]:SetText((e.profit < 0 and UI.C.bad or UI.C.good) .. U.money(e.profit) .. "|r")
            else
                r.cols[3]:SetText("-")
            end
            r.cols[4]:SetText(e.perDay and string.format("~%.1f", e.perDay) or "-")
            r.cols[5]:SetText(e.route and e.route ~= "vendor" and UI.sureText(e.sure) or "-")
            r.cols[6]:SetText(UI.routeLabel(e.route) or "")
            if UI.craftSelected and UI.craftSelected.id == e.id then
                r.selected:Show()
                UI.craftSelected = e
            else
                r.selected:Hide()
            end
            r:Show()
        else
            r.recipe = nil
            r:Hide()
        end
    end
    local empty = UI.craftTable.empty
    if #rows == 0 then
        -- Every recipe is unlearned (not merely "some recipes exist"): a learned recipe with no
        -- material price is still a row, and the reason for an empty page must name the real one.
        local hiddenAll = F.Crafting.allUnlearned()
        empty:SetText(
            hiddenAll
                    and L(
                        "Every saved recipe is one this character has not learned. Press All recipes to list them anyway."
                    )
                or L(
                    "Open each of your profession windows once: ForeverFlip reads the recipes and prices them here with the auction prices of the materials and the product."
                )
        )
        empty:Show()
    else
        empty:Hide()
    end
    local unlearned = F.Crafting.unlearnedCount()
    UI.craftHideButton:SetText(
        (F.db.settings.hideUnlearned and L("Learned recipes only") or L("All recipes"))
            .. (unlearned > 0 and string.format(" (%d)", unlearned) or "")
    )
    UI.craftHideButton.fitWidth() -- the count and the Ukrainian label must stay inside the button
    local s = UI.craftSelected
    if UI.craftProfOpen then
        local professions = F.Crafting.professions()
        local lines = { L("Learned professions") }
        for _, profession in ipairs(professions) do
            local rank = profession.rank
                    and profession.maxRank
                    and string.format("%d/%d", profession.rank, profession.maxRank)
                or profession.rank and tostring(profession.rank)
                or L("rank unknown")
            lines[#lines + 1] = profession.name .. "  " .. rank
        end
        if #professions == 0 then
            lines[#lines + 1] = L("No learned professions found. Open a profession window to refresh it.")
        end
        UI.craftText:Hide()
        -- The line above (craftText) is hidden: the list starts in its place, one line higher.
        UI.craftProfText.moveTop(6)
        UI.craftProfText.set(lines, "professions")
    else
        UI.craftProfText.moveTop(20)
        UI.craftProfText.set(s and not s.missing and UI.craftPlanLines(s) or {}, s and ("plan" .. s.id) or "")
        UI.craftText:Show()
    end
    if s and s.missing then
        UI.craftText:SetText(
            L("A material of this recipe has no price yet: it needs a full scan or a merchant that sells it.")
        )
    elseif s then
        UI.craftText:SetText(
            string.format(
                L("Materials %s, product %s (%s): profit %s per craft at the usual prices."),
                U.money(s.cost),
                U.money(s.value or 0),
                L(s.route == "vendor" and "vendor" or s.route == "undecided" and "auction or vendor" or "auction"),
                U.money(s.profit or 0)
            )
        )
    else
        UI.craftText:SetText(L("Material prices: the cheaper of the usual auction price and a merchant's price."))
    end
    UI.craftShop:SetEnabled(s ~= nil and not s.missing)
end

-- A recipe row's hover, in the look of ForeverFlip's item tooltips: the recipe, the ForeverFlip
-- header, then Materials (each with its price and where it comes from), Product (what it sells for
-- and how fast) and the profit of one craft. The figures are the row's own (F.Crafting.profits),
-- so the hover never disagrees with the table; each is said once.
function UI.craftTooltip(owner, e)
    if not GameTooltip then
        return
    end
    local tip = GameTooltip
    local function grey(s)
        return UI.C.dim .. s .. "|r"
    end
    local function section(title)
        tip:AddLine(UI.C.head .. L(title) .. "|r")
    end
    local function line(left, right, r, g, b)
        UI.tipPair(tip, left, right, r or 0.6, g or 0.6, b or 0.6)
    end
    tip:SetOwner(owner, "ANCHOR_RIGHT")
    if e.learned == false then
        tip:SetText(e.name or ("#" .. e.id), 0.6, 0.6, 0.6)
    else
        tip:SetText(e.name or ("#" .. e.id), 1, 1, 1)
    end
    tip:AddLine(UI.C.gold .. "ForeverFlip|r  " .. grey(L("Crafting")))
    if e.learned == false then
        tip:AddLine("  " .. L("Not learned by this character: it cannot be crafted yet."), 1, 0.6, 0.3, true)
    end
    local history = F.Data.market(F.db, F.Engine.scope()).history
    local merchant = F.db.merchantPrices or {}
    section("Materials")
    for _, m in ipairs(e.reagents or {}) do
        local id, qty = m[1], m[2]
        local name = U.itemInfo(id) or ("#" .. id)
        local unit = F.Crafting.materialCost(history, id)
        local from = unit and merchant[id] and merchant[id] <= unit and L("merchant") or L("auction")
        line(
            "  " .. qty .. " x " .. name .. (unit and (" " .. grey("(" .. from .. ")")) or ""),
            unit and U.money(math.floor(unit * qty + 0.5)) or UI.C.bad .. L("no price") .. "|r",
            0.85,
            0.85,
            0.85
        )
    end
    if e.missing then
        tip:AddLine(
            "  " .. L("A material of this recipe has no price yet: it needs a full scan or a merchant that sells it."),
            1,
            0.6,
            0.3,
            true
        )
    elseif e.cost then
        line("  " .. L("Materials of one craft"), U.money(e.cost))
    end
    if not e.missing then
        section("Product")
        local product = e.out and U.itemInfo(e.out) or nil
        line("  " .. (e.n or 1) .. " x " .. (product or ("#" .. tostring(e.out))), "", 0.85, 0.85, 0.85)
        if e.value then
            line(
                "  "
                    .. (
                        e.route == "vendor" and L("A merchant pays")
                        or L("Sells for") .. " " .. grey("(" .. L("after the cut and the deposit") .. ")")
                    ),
                U.money(e.value)
            )
        else
            line("  " .. L("Sells for"), L("no price yet"))
        end
        if e.route ~= "vendor" then
            line("  " .. L("Bought a day"), e.perDay and string.format("~%.1f", e.perDay) or L("not measured yet"))
        end
        if e.profit then
            local good = e.profit >= 0
            line(
                L("Profit per craft"),
                UI.signed(e.profit),
                good and 0.25 or 1,
                good and 1 or 0.38,
                good and 0.25 or 0.38
            )
        end
    end
    tip:AddLine(
        grey(L("Material prices: the cheaper of the usual auction price and a merchant's price.")),
        1,
        1,
        1,
        true
    )
    tip:Show()
end

-- The plan of the selected recipe (F.Crafting.plan), in the lines under the table: how many crafts
-- and what stopped there, each material to buy with its price limit, and the profit.
local PLAN_LIMIT = {
    sales = "a day of its sales",
    stock = "you already hold a day of its sales",
    no_sales = "the product hardly sells",
    unknown_sales = "its sales are not measured yet: one craft to try",
    price = "the next craft would not pay at the next lots' prices",
    no_profit = "it does not pay even with the cheapest materials",
    supply = "no more material is listed",
    money = "the money on hand",
    max = "the most one plan makes",
}
function UI.craftPlanLines(s)
    local plan = F.Crafting.plan(s.id)
    if not plan then
        return {}
    end
    local lines = {
        gold("Plan") .. " " .. string.format(L("%d crafts"), plan.crafts) .. "  ·  " .. L("limit") .. ": " .. L(
            PLAN_LIMIT[plan.limit] or plan.limit
        ),
    }
    if plan.crafts > 0 then
        for _, mat in ipairs(plan.materials) do
            local name = mat.name or ("#" .. mat.id)
            local line = string.format(
                L("%s: %d needed, %d held, buy %d"),
                name,
                mat.per * plan.crafts,
                math.min(mat.held, mat.per * plan.crafts),
                mat.buy
            )
            if mat.buy > 0 and mat.maxPrice then
                line = line
                    .. string.format(L(" at up to %s each, %s in all"), U.money(mat.maxPrice), U.money(mat.spend))
                    .. (mat.estimated and (" " .. UI.C.gold .. L("(usual price: no lots read)") .. "|r") or "")
            end
            lines[#lines + 1] = "   " .. line
        end
        lines[#lines + 1] = gold("Profit")
            .. " "
            .. string.format(
                L("about %s for %d crafts, %s to spend"),
                UI.signed(plan.profit),
                plan.crafts,
                U.money(plan.spend)
            )
    end
    return lines
end

-- Profession book ----------------------------------------------------------------------------------
-- A button under the profession book disenchants what was bought on the Disenchant page
-- (Disenchant.queue), one item a click: a spell needs a click of the player's own for each cast.
-- It is a secure button of ours casting Disenchant with the item as its target (target-bag and
-- target-slot), set for the next item before each click, out of combat only. The game's targeting
-- uses the item only while the spell waits for one, so a cast that fails never equips the item.
-- Nothing of the book is called or changed: the button is only placed under it.
local function inCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

function UI.updateDisenchantButton()
    local b = UI.deButton
    if not b then
        return 0
    end
    local n = #F.Disenchant.queue()
    b:SetText(string.format(L("Disenchant bought (%d)"), n))
    if not inCombat() then
        if F.Disenchant.canDisenchant() then
            b:Show()
        else
            b:Hide()
        end
    end
    return n
end

-- Sets the button's cast for the first item of the queue; none when it is empty or a cast or loot
-- window is still running (that click would be lost on a busy cast).
function UI.aimDisenchant(b)
    if inCombat() then
        return nil
    end
    local busy = (UnitCastingInfo and UnitCastingInfo("player")) or (GetNumLootItems and (GetNumLootItems() or 0) > 0)
    local nextItem = not busy and F.Disenchant.canDisenchant() and F.Disenchant.queue()[1] or nil
    if nextItem then
        b:SetAttribute("type", "spell")
        b:SetAttribute("spell", F.Disenchant.SPELL)
        b:SetAttribute("target-bag", nextItem.bag)
        b:SetAttribute("target-slot", nextItem.slot)
    else
        b:SetAttribute("type", nil)
        b:SetAttribute("target-bag", nil)
        b:SetAttribute("target-slot", nil)
    end
    return nextItem
end

function UI.professionBook()
    local book = ProfessionsBookFrame
    if UI.deButton or not book or inCombat() then
        return
    end
    local ok, b = pcall(
        CreateFrame,
        "Button",
        "ForeverFlipDisenchantButton",
        book,
        "SecureActionButtonTemplate, UIPanelButtonTemplate"
    )
    if not ok or not b then
        return
    end
    UI.deButton = b
    b:SetSize(190, 22)
    b:SetPoint("TOPRIGHT", book, "BOTTOMRIGHT", -8, -2)
    if b.RegisterForClicks then
        -- Both: the secure click acts on the press when ActionButtonUseKeyDown is on (the
        -- default) and on the release when it is off. Registered for the release only, a click
        -- with the default setting did nothing.
        b:RegisterForClicks("AnyUp", "AnyDown")
    end
    b:SetScript("PreClick", function(self)
        F.Engine.input()
        UI.aimDisenchant(self)
    end)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("ForeverFlip", 1, 0.82, 0)
        GameTooltip:AddLine(
            L("Disenchants the items bought on the Disenchant page, one a click, while they are in your bags."),
            1,
            1,
            1,
            true
        )
        local first = F.Disenchant.queue()[1]
        if first then
            GameTooltip:AddLine(string.format(L("Next: %s"), first.link or U.itemInfo(first.id) or "?"), 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        if GameTooltip and GameTooltip:IsOwned(self) then
            GameTooltip:Hide()
        end
    end)
    -- The count follows the bags while the book is open, on a plain frame of ours: it keeps its
    -- clock while the button is hidden (a character who has not learned Disenchant yet).
    local watch = CreateFrame("Frame", nil, book)
    UI.deWatch = watch
    local since = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        since = since + (elapsed or 0)
        if since >= 0.5 then
            since = 0
            UI.updateDisenchantButton()
        end
    end)
    UI.updateDisenchantButton()
end
