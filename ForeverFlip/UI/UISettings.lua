-- ForeverFlip window: Settings pages.
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

-- Settings page ------------------------------------------------------------------------------------
-- Seven pages, opened from the menu (UI.GROUPS): General (the numbers, with Limits and the Market
-- reset), Automation (what runs by itself, and the notices), Display, Key bindings, Sharing,
-- Messages and Data (what was learned, and the two resets).
-- Settings pages share one look: a gold heading with a thin line under it per section, white
-- labels, fields and buttons aligned on the right edge, and the full explanation in tooltips.

-- A section heading at (x, y); `width` nil spans to the right edge of the page.
local function heading(p, label, x, y, width)
    local t = text(p, "GameFontNormal")
    t:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
    t:SetText(L(label))
    local line = p:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.25)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", p, "TOPLEFT", x, y - 16)
    if width then
        line:SetWidth(width)
    else
        line:SetPoint("TOPRIGHT", p, "TOPRIGHT", -12, y - 16)
    end
    return t
end

-- A row's faint stripe, as the auction house's lists have.
local function stripe(p, y, height)
    local t = p:CreateTexture(nil, "BACKGROUND")
    t:SetAtlas("auctionhouse-rowstripe-1")
    t:SetPoint("TOPLEFT", p, "TOPLEFT", 6, y)
    t:SetPoint("TOPRIGHT", p, "TOPRIGHT", -6, y)
    t:SetHeight(height)
    return t
end

-- A check box with a one-line label; the setting's long text is its tooltip.
local function checkRow(p, x, y, label, body, checked, onClick)
    local box = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    box:SetSize(26, 26)
    box:SetPoint("TOPLEFT", p, "TOPLEFT", x - 4, y)
    box:SetChecked(checked)
    box:SetScript("OnClick", function(self, ...)
        return F.Log.action("check " .. tostring(label) .. " " .. tostring(self:GetChecked()), onClick, self, ...)
    end)
    local t = text(p, "GameFontHighlight")
    t:SetPoint("LEFT", box, "RIGHT", 2, 1)
    t:SetWordWrap(false)
    t:SetText(L(label))
    box.label = t
    if body then
        hint(box, label, body)
    end
    return box
end

-- An option of the Automation and Display pages: a check box, its name, and what it does in grey
-- under it, so the page explains itself without a hover. 40 px high.
local OPTION_STEP = 40
local function optionRow(p, y, label, body, checked, onClick)
    local box = checkRow(p, 14, y, label, nil, checked, onClick)
    box.label:SetPoint("RIGHT", p, "RIGHT", -14, 0)
    local about = text(p, "GameFontHighlightSmall")
    about:SetPoint("TOPLEFT", box.label, "BOTTOMLEFT", 0, -3)
    about:SetPoint("RIGHT", p, "RIGHT", -14, 0)
    about:SetJustifyH("LEFT")
    about:SetWordWrap(false)
    about:SetText(UI.C.soft .. L(body) .. "|r")
    box.about = about
    return box
end

-- A number as typed in a settings box, a decimal comma ("12,5") and a percent sign ("15%") allowed.
-- Nil for anything else, a negative or an endless number: that box keeps its value, and Save says so.
local function typedNumber(s)
    local plain = tostring(s or ""):gsub(",", "."):gsub("%%", "")
    local v = tonumber(plain)
    if U.finite(v) and v >= 0 then
        return v
    end
end

-- The pages in menu order (UI.GROUPS has the same ids as settings:<id>).
UI.SETTING_PAGES = { "general", "auto", "display", "keys", "share", "messages", "data" }

function UI.createSettings(p)
    UI.settingFrames = {}
    for _, id in ipairs(UI.SETTING_PAGES) do
        local frame = CreateFrame("Frame", nil, p)
        frame:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
        frame:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
        UI.settingFrames[id] = frame
    end
    UI.createGeneralSettings(UI.settingFrames.general)
    UI.createAutoSettings(UI.settingFrames.auto)
    UI.createDisplaySettings(UI.settingFrames.display)
    UI.createKeySettings(UI.settingFrames.keys)
    UI.createShareSettings(UI.settingFrames.share)
    UI.createMessageSettings(UI.settingFrames.messages)
    UI.createDataSettings(UI.settingFrames.data)
    UI.setSettingsFrame("general")
end

-- Messages: ForeverFlip's chat tab (Log.lua), which categories also go to the general chat, and
-- the error sound.
function UI.createMessageSettings(p)
    heading(p, "Chat tab", 12, -4)
    local about = text(p, "GameFontHighlight")
    about:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -28)
    about:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, -28)
    about:SetJustifyH("LEFT")
    about:SetText(
        L(
            "Errors, deals, sales and scan notes go to the ForeverFlip tab of your chat. It is made once; if you close it, make it again here or with /ff log."
        )
    )
    UI.logTabButton = button(p, "Show the ForeverFlip tab", 190, function()
        F.Log.show()
        UI.refreshMessages()
    end)
    UI.logTabButton:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -66)
    UI.logTabState = text(p, "GameFontHighlightSmall")
    UI.logTabState:SetPoint("LEFT", UI.logTabButton, "RIGHT", 10, 0)

    heading(p, "Also in the general chat", 12, -108)
    UI.logEchoBoxes = {}
    for i, category in ipairs(F.Log.ECHOED) do
        local box = checkRow(
            p,
            14,
            -130 - (i - 1) * 26,
            "|cff" .. F.Log.COLORS[category] .. L(F.Log.LABELS[category]) .. "|r",
            nil,
            F.Log.echoes(category),
            function(self)
                F.Log.setEcho(category, self:GetChecked())
            end
        )
        UI.logEchoBoxes[category] = box
    end
    heading(p, "Sound", 12, -130 - #F.Log.ECHOED * 26 - 8)
    UI.logSoundBox = checkRow(
        p,
        14,
        -130 - #F.Log.ECHOED * 26 - 30,
        "Sound for errors",
        nil,
        F.Log.soundOn(),
        function(self)
            F.db.settings.logSound = self:GetChecked() and true or false
        end
    )
    -- Developer: the saved trace (Log.trace, /ff trace) and DEV mode, which adds every action.
    local devY = -130 - #F.Log.ECHOED * 26 - 66
    heading(p, "Developer", 12, devY)
    UI.traceBox = checkRow(
        p,
        14,
        devY - 22,
        "Trace searches, checks and slow moments",
        "Saves what each search and Check all waited for and every moment the game waited for ForeverFlip. /ff trace shows it; the whole trace is in the saved file.",
        F.Log.tracing(),
        function(self)
            if self:GetChecked() then
                F.db.settings.trace = nil
            else
                F.db.settings.trace = false
            end
            UI.refreshMessages()
        end
    )
    UI.devBox = checkRow(
        p,
        14,
        devY - 48,
        "DEV: trace every action",
        "Also saves every game event, click, opened page and the time of each part of a frame. For finding a freeze; the trace keeps the last 2000 lines.",
        F.Log.dev(),
        function(self)
            F.db.settings.dev = self:GetChecked() and true or nil
            if F.db.settings.dev then
                F.db.settings.trace = nil
            end
            UI.refreshMessages()
        end
    )
    UI.traceShowButton = button(p, "Show trace", 110, function()
        for _, line in ipairs(F.Log.traceCommand("")) do
            F.Log.add("info", line, { chat = true, raw = true })
        end
    end)
    UI.traceShowButton:SetPoint("TOPLEFT", p, "TOPLEFT", 12, devY - 80)
    UI.traceClearButton = button(p, "Clear trace", 110, function()
        F.Log.clearTrace()
        UI.refreshMessages()
    end)
    UI.traceClearButton:SetPoint("LEFT", UI.traceShowButton, "RIGHT", 6, 0)
    p:SetScript("OnShow", UI.refreshMessages)
end

-- The clean start (Settings > Data, /ff reset): asked first, then everything but the settings
-- is left out of the file at the reload (Core, PLAYER_LOGOUT).
function UI.confirmReset()
    local function reset()
        F.resetPending = true
        if ReloadUI then
            ReloadUI()
        end
    end
    if not StaticPopupDialogs or not StaticPopup_Show then
        return
    end
    StaticPopupDialogs.FOREVERFLIP_RESET = {
        text = L(
            "Reset all ForeverFlip data?\n\nPrices, sales history, journals, positions and the shopping list of every character are forgotten for good. Settings stay. The interface reloads now."
        ),
        button1 = L("Reset"),
        button2 = L("Cancel"),
        OnAccept = reset,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("FOREVERFLIP_RESET")
end

function UI.refreshMessages()
    if not UI.logEchoBoxes then
        return
    end
    for category, box in pairs(UI.logEchoBoxes) do
        box:SetChecked(F.Log.echoes(category))
    end
    UI.logSoundBox:SetChecked(F.Log.soundOn())
    UI.traceBox:SetChecked(F.Log.tracing())
    UI.devBox:SetChecked(F.Log.dev())
    UI.logTabState:SetText(
        F.Log.chatFrame() and L("The tab is open.") or UI.C.dim .. L("There is no ForeverFlip tab now.") .. "|r"
    )
end

-- Limits (once the Safety page, now a section of General): the vendor price margin, the spending
-- limit and the lots left for others, in two columns from `top`. What ForeverFlip learned is on the
-- Data page (UI.refreshSafety). The page's Save saves these boxes too (UI.saveSafety).
-- { setting, short label, column, row, full explanation (tooltip) }
local LIMIT_FIELDS = {
    { "vendorMargin", "Vendor price margin, %", 1, 0, "Vendor prices of deals count less by this safety margin, %" },
    {
        "spendLimit",
        "Gold per visit (0 = no limit)",
        2,
        0,
        "Gold one auction house visit may spend on deals (0 = no limit)",
    },
    { "leaveLots", "Units left for others", 1, 1, "Cheap units of a vendor deal left for other buyers" },
}

function UI.createSafetySettings(p, top, COL, WIDTH)
    heading(p, "Limits", COL[1], top, COL[2] + WIDTH - COL[1])
    UI.safetyBoxes = {}
    for i, f in ipairs(LIMIT_FIELDS) do
        local x, y = COL[f[3]], top - 22 - f[4] * 26
        local label = text(p, "GameFontHighlight")
        label:SetPoint("TOPLEFT", p, "TOPLEFT", x, y - 4)
        label:SetWidth(WIDTH - 100)
        label:SetWordWrap(false)
        label:SetText(L(f[2]))
        local e = editbox(p, 86)
        e:SetPoint("TOPRIGHT", p, "TOPLEFT", x + WIDTH, y)
        e:SetJustifyH("RIGHT")
        e.field = f
        hint(e, f[2], f[5])
        e:SetScript("OnTextChanged", UI.updateSave)
        UI.safetyBoxes[i] = e
    end
    UI.loadSafety()
end

-- Saves the Limits boxes; true when one of them held no number (it keeps its saved value).
function UI.saveSafety()
    local bad = false
    for _, e in ipairs(UI.safetyBoxes or {}) do
        local key = e.field[1]
        local v = typedNumber(e:GetText())
        if not v then
            bad = true
        elseif key == "spendLimit" then
            -- Gold with its fraction (0.5 is 50 silver), kept to the copper: a limit floored to
            -- 0 would mean no limit at all.
            F.db.settings[key] = v > 0 and math.max(1, math.floor(v * 10000 + 0.5)) / 10000 or 0
        elseif key == "vendorMargin" then
            F.db.settings[key] = U.clamp(math.floor(v), 0, 90)
        else
            F.db.settings[key] = math.floor(v)
        end
    end
    UI.loadSafety()
    return bad
end

function UI.loadSafety()
    for _, e in ipairs(UI.safetyBoxes or {}) do
        e:SetText(tostring(F.db.settings[e.field[1]] or 0))
        e.saved = e:GetText()
    end
    UI.updateSave()
end

-- True when a box of the page holds other text than was loaded into it: only then has Save
-- something to do (the check boxes and presets are saved at once).
function UI.settingsChanged()
    for _, list in ipairs({ UI.settingBoxes or {}, UI.safetyBoxes or {} }) do
        for _, e in ipairs(list) do
            if e.saved ~= nil and e:GetText() ~= e.saved then
                return true
            end
        end
    end
    return false
end

function UI.updateSave()
    if UI.saveButton then
        UI.saveButton:SetEnabled(UI.settingsChanged())
    end
end

-- What the saved file holds (Settings, Data): the items with prices on this house and on all, the
-- journal and the stock of this character, the last full scan, and what the last logout left out.
function UI.dataSummary()
    local lines = {}
    local here, houses, all = 0, 0, 0
    local scope = F.Engine.scope()
    for id, m in pairs(F.db.markets or {}) do
        if type(m) == "table" and type(m.history) == "table" then
            houses = houses + 1
            local n = 0
            for _ in pairs(m.history) do
                n = n + 1
            end
            all = all + n
            if id == scope then
                here = n
            end
        end
    end
    local c = F.Data.char(F.db, F.Engine.owner())
    local held = 0
    for _ in pairs(c.positions or {}) do
        held = held + 1
    end
    lines[#lines + 1] = string.format(
        L("Saved: prices of %d items on this auction house (%d on %d houses); journal %d entries, %d items in stock."),
        here,
        all,
        houses,
        #(c.journal or {}),
        held
    )
    local last = tonumber(F.db.lastScan)
    lines[#lines + 1] = last and last > 0 and string.format(L("Last full scan: %s."), UI.age(last))
        or L("No full scan yet: prices come with the first one.")
    local dropped = F.db.fitDropped
    if type(dropped) == "table" and (tonumber(dropped.items) or 0) > 0 then
        lines[#lines + 1] = string.format(
            L("At the last logout %d items seen longest ago were left out, so the saved file stays loadable."),
            dropped.items
        )
    end
    return lines
end

function UI.refreshSafety()
    if not UI.safetyText then
        return
    end
    local lines = UI.dataSummary()
    local seen = 0
    for _ in pairs(F.db.vendorSeen or {}) do
        seen = seen + 1
    end
    local differ = F.Merchant.differences()
    lines[#lines + 1] = string.format(
        L("Vendor prices confirmed at merchants: %d; different from the game's item data: %d."),
        seen,
        #differ
    )
    for i = 1, math.min(2, #differ) do
        local d = differ[i]
        local name = U.itemInfo(d.id) or ("item " .. d.id)
        lines[#lines + 1] = string.format("  %s: %s (%s %s)", name, U.money(d.seen), L("game says"), U.money(d.client))
    end
    lines[#lines + 1] = L("Sell an item to any merchant once and its real price is used from then on.")
    local bands, learned = 0, 0
    for _, b in pairs(F.db.deSeen or {}) do
        bands = bands + 1
        if (b.n or 0) >= F.Disenchant.LEARN then
            learned = learned + 1
        end
    end
    lines[#lines + 1] = string.format(
        L("Own disenchants: %d item bands seen, %d used instead of the table (from %d disenchants each)."),
        bands,
        learned,
        F.Disenchant.LEARN
    )
    local limit = tonumber(F.db.settings.spendLimit) or 0
    if limit > 0 then
        lines[#lines + 1] = string.format(
            L("Spent on deals this visit: %s of %s."),
            U.money(F.Engine.spent or 0),
            U.money(limit * 10000)
        )
    end
    if (F.AH.forced or 0) > 0 then
        lines[#lines + 1] = string.format(
            L("The auction house throttle was stuck %d times; ForeverFlip went on after 5 seconds."),
            F.AH.forced
        )
    end
    UI.safetyText:SetText(table.concat(lines, "\n"))
end

-- The client did not hand over any saved data. On a first install that is normal; otherwise the
-- file was not read, and playing on would overwrite it at logout. The player decides.
function UI.noSavedData()
    if not StaticPopupDialogs or not StaticPopup_Show then
        F.Log.add(
            "info",
            L("No saved data was loaded. If you used ForeverFlip before, type /reload now."),
            { chat = true }
        )
        return
    end
    StaticPopupDialogs.FOREVERFLIP_NO_DATA = {
        text = L(
            "ForeverFlip found no saved data.\n\nFirst time? Press Continue.\n\nUsed it before? The game did not read the file: press Reload. Playing on would replace your history at logout."
        ),
        button1 = L("Reload"),
        button2 = L("Continue"),
        OnAccept = function()
            if ReloadUI then
                ReloadUI()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = false,
    }
    StaticPopup_Show("FOREVERFLIP_NO_DATA")
end

-- Which Settings page shows (UI.SETTING_PAGES); UI.show calls it for settings:<page>.
function UI.setSettingsFrame(id)
    if not UI.settingFrames or not UI.settingFrames[id] then
        id = "general"
    end
    UI.settingsTab = id
    for key, frame in pairs(UI.settingFrames or {}) do
        if key == id then
            frame:Show()
        else
            frame:Hide()
        end
    end
end

-- Key bindings: click a button, press the key. Right-click clears; Escape cancels.
UI.BINDINGS = {
    { "FOREVERFLIP_BUY", "Buy or confirm the selected deal" },
    { "FOREVERFLIP_BUY_NEXT", "Buy the next best deal (check, buy, confirm)" },
    { "FOREVERFLIP_POST", "Post next bought (then Post all)" },
    { "FOREVERFLIP_CANCEL", "Cancel the next undercut auction" },
    { "FOREVERFLIP_SCAN", "Full scan" },
}
local MODIFIER_KEYS = {
    LSHIFT = true,
    RSHIFT = true,
    LCTRL = true,
    RCTRL = true,
    LALT = true,
    RALT = true,
    UNKNOWN = true,
}

function UI.bindingKey(command)
    return GetBindingKey and GetBindingKey(command) or nil
end

-- Binds `key` to `command` in the character's (or account's) binding set; nil key clears it.
function UI.setBinding(command, key)
    if InCombatLockdown and InCombatLockdown() then
        F.Engine.notify("combat")
        return false
    end
    local old = UI.bindingKey(command)
    while old do
        SetBinding(old)
        local again = UI.bindingKey(command)
        if again == old then
            break
        end
        old = again
    end
    if key then
        SetBinding(key, command)
    end
    if SaveBindings and GetCurrentBindingSet then
        SaveBindings(GetCurrentBindingSet())
    end
    F.Engine.changed()
    return true
end

-- A key press as the game names it in bindings: "CTRL-SHIFT-B".
function UI.keyName(key)
    local prefix = ""
    if IsAltKeyDown and IsAltKeyDown() then
        prefix = prefix .. "ALT-"
    end
    if IsControlKeyDown and IsControlKeyDown() then
        prefix = prefix .. "CTRL-"
    end
    if IsShiftKeyDown and IsShiftKeyDown() then
        prefix = prefix .. "SHIFT-"
    end
    return prefix .. key
end

-- The capture ends without a key: the key page was left, or the auction house closed with it.
function UI.cancelCapture()
    UI.capturing = nil
    if UI.keyCatcher then
        UI.keyCatcher:Hide()
    end
end

function UI.captureKey(command)
    UI.capturing = command
    local c = UI.keyCatcher
    if not c then
        -- A child of the key page that still covers the whole screen: when the page goes (another
        -- page, the game's own tab, the auction house closed) the catcher goes with it, and the next
        -- key the player presses walks or casts again instead of being bound and saved.
        c = CreateFrame("Frame", nil, UI.settingFrames.keys)
        c:SetAllPoints(UIParent)
        c:SetFrameStrata("TOOLTIP")
        if c.EnableKeyboard then
            c:EnableKeyboard(true)
        end
        if c.SetPropagateKeyboardInput then
            c:SetPropagateKeyboardInput(false)
        end
        c:SetScript("OnKeyDown", function(_, key)
            UI.onCapturedKey(key)
        end)
        -- The game runs OnHide when a parent hides too. The catcher then hides by its own flag as
        -- well, or it would come back with the page and swallow a key with nothing waiting for it.
        c:SetScript("OnHide", UI.cancelCapture)
        UI.keyCatcher = c
    end
    c:Show()
    UI.refresh()
end

function UI.onCapturedKey(key)
    local command = UI.capturing
    if not command or MODIFIER_KEYS[key] then
        return
    end
    UI.capturing = nil
    if UI.keyCatcher then
        UI.keyCatcher:Hide()
    end
    if key ~= "ESCAPE" then
        UI.setBinding(command, UI.keyName(key))
    end
    UI.refresh()
end

function UI.createKeySettings(p)
    heading(p, "Key bindings", 12, -6)
    UI.keyButtons = {}
    for i, b in ipairs(UI.BINDINGS) do
        local y = -28 - (i - 1) * 30
        if i % 2 == 1 then
            stripe(p, y + 2, 30)
        end
        local label = text(p, "GameFontHighlight")
        label:SetPoint("TOPLEFT", p, "TOPLEFT", 14, y - 7)
        label:SetWordWrap(false)
        label:SetText(L(b[2]))
        local key = button(p, "", 170, function()
            UI.captureKey(b[1])
        end)
        key:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, y - 2)
        if key.RegisterForClicks then
            key:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        end
        key:SetScript("OnClick", function(_, mouse)
            if mouse == "RightButton" then
                UI.setBinding(b[1], nil)
            else
                UI.captureKey(b[1])
            end
        end)
        key.command = b[1]
        UI.keyButtons[i] = key
    end
    local below = -28 - #UI.BINDINGS * 30
    heading(p, "How to set a key", 12, below - 14)
    UI.keyText = text(p, "GameFontHighlight")
    UI.keyText:SetPoint("TOPLEFT", p, "TOPLEFT", 14, below - 38)
    UI.keyText:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, below - 38)
    UI.keyText:SetSpacing(4)
    UI.keyText:SetText(
        L(
            "Click a button, then press the key (with Shift, Ctrl or Alt if you like). Right-click clears a key; Escape cancels. The same keys are in the game's Key Bindings window under AddOns."
        )
    )
end

function UI.refreshKeys()
    for _, b in ipairs(UI.keyButtons or {}) do
        if UI.capturing == b.command then
            b:SetText(UI.C.gold .. L("Press a key...") .. "|r")
        else
            b:SetText(UI.bindingKey(b.command) or L("Not bound"))
        end
    end
end

-- Sharing full scans with other players.
function UI.createShareSettings(p)
    heading(p, "Automatic", 12, -6)
    -- Short labels; the whole sentence is the tooltip.
    local function toggle(row, setting, label, body)
        return checkRow(p, 14, -26 - row * 26, label, body, F.db.settings[setting], function(self)
            F.db.settings[setting] = self:GetChecked() and true or false
        end)
    end
    toggle(
        0,
        "shareReceive",
        "Accept scans from guild and group",
        "Accept full scans shared by guild and group members"
    )
    toggle(1, "shareAuto", "Send my scans to the guild", "Send my full scans to the guild after each scan")
    toggle(
        2,
        "rawScans",
        "Keep scans for ForeverFlip Sync",
        "Keep my full scans for the ForeverFlip Sync helper (community data)"
    )
    local channel = toggle(
        3,
        "shareChannel",
        "Share with the whole realm",
        "Share full scans with every ForeverFlip user of the realm"
    )
    channel:HookScript("OnClick", function(self)
        if self:GetChecked() then
            F.Share.join()
        else
            F.Share.leave()
        end
    end)

    local send = heading(p, "Send my price history", 12, -140)
    -- What is sent, in the heading's tooltip instead of a paragraph on the page.
    local about = CreateFrame("Frame", nil, p)
    about:SetAllPoints(send)
    hint(
        about,
        "Send my price history",
        "What is shared is your price history of the last 7 days (every full scan of those days, by day: cheapest and usual price, units listed and seen sold) and the prices of your last scan. Received history fills the other player's days and sales data and gives a fresh usual price when theirs is older. It never creates deals by itself, and the other player needs ForeverFlip too."
    )
    local to = text(p, "GameFontHighlight")
    to:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -168)
    to:SetText(L("Send to:"))
    UI.shareGuild = button(p, "Guild", 90, function()
        local _, why = F.Share.send("GUILD")
        F.Engine.notify(why)
    end)
    UI.shareGuild:SetPoint("LEFT", to, "RIGHT", 10, 0)
    UI.shareGroup = button(p, "Group", 90, function()
        local _, why = F.Share.send((IsInRaid and IsInRaid()) and "RAID" or "PARTY")
        F.Engine.notify(why)
    end)
    UI.shareGroup:SetPoint("LEFT", UI.shareGuild, "RIGHT", 4, 0)
    UI.shareWhisper = button(p, "Send", 80, function()
        local _, why = F.Share.send("WHISPER", UI.shareName:GetText())
        F.Engine.notify(why)
    end)
    UI.shareWhisper:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, -163)
    UI.shareName = editbox(p, 120)
    UI.shareName:SetPoint("RIGHT", UI.shareWhisper, "LEFT", -8, 0)
    local whisper = text(p, "GameFontHighlight")
    whisper:SetPoint("RIGHT", UI.shareName, "LEFT", -10, 0)
    whisper:SetText(L("Player:"))
    UI.shareExport = button(p, "Export as text", 140, function()
        local snap = F.Share.snapshot()
        if not snap then
            F.Engine.notify("no_scan")
            return
        end
        UI.showText(
            L("Last full scan as text: press Ctrl+A, then Ctrl+C, and send it to a friend."),
            F.Share.encode(snap)
        )
    end)
    UI.shareExport:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -194)
    UI.shareImport = button(p, "Import text", 140, function()
        UI.showText(L("Paste a shared scan (Ctrl+V), then press Import."), "", function(textValue)
            local merged, why = F.Share.import(textValue)
            F.Engine.notify(merged and "share_received" or why)
            return merged ~= nil
        end)
    end)
    UI.shareImport:SetPoint("LEFT", UI.shareExport, "RIGHT", 4, 0)

    heading(p, "Status", 12, -232)
    UI.shareStatusPage = p
    UI.shareLines = {}
end

-- The status as a table of two columns: gold labels in one column, the facts beside them, one fact
-- a line, so no line runs over into the next (one string with the label in front wrapped
-- "Full scans waiting for the helper" under the label). A faint band marks every second group.
local SHARE_TOP, SHARE_LINE, SHARE_LABEL = -256, 20, 116
local function shareLine(n)
    local row = UI.shareLines[n]
    if row then
        return row
    end
    local p = UI.shareStatusPage
    local y = SHARE_TOP - (n - 1) * SHARE_LINE
    row = {}
    row.band = p:CreateTexture(nil, "BACKGROUND")
    row.band:SetColorTexture(1, 1, 1, 0.04)
    row.band:SetPoint("TOPLEFT", p, "TOPLEFT", 8, y + 3)
    row.band:SetPoint("TOPRIGHT", p, "TOPRIGHT", -8, y + 3)
    row.band:SetHeight(SHARE_LINE)
    row.label = text(p, "GameFontNormal")
    row.label:SetPoint("TOPLEFT", p, "TOPLEFT", 14, y)
    row.label:SetWidth(SHARE_LABEL - 8)
    row.label:SetWordWrap(false)
    row.value = text(p, "GameFontHighlight")
    row.value:SetPoint("TOPLEFT", p, "TOPLEFT", 14 + SHARE_LABEL, y)
    row.value:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, y)
    row.value:SetWordWrap(false)
    UI.shareLines[n] = row
    return row
end

local function grey(s)
    return UI.C.dim .. s .. "|r"
end

-- groups: { { label, { value, ... } }, ... }. UI.shareStatus keeps the same as plain text.
local function showShare(groups)
    local n, plain = 0, {}
    for g, group in ipairs(groups) do
        for i, value in ipairs(group[2]) do
            n = n + 1
            local row = shareLine(n)
            row.label:SetText(i == 1 and L(group[1]) or "")
            row.value:SetText(value)
            row.band:SetShown(g % 2 == 1)
            row.label:Show()
            row.value:Show()
            plain[#plain + 1] = (i == 1 and L(group[1]) or "") .. "  " .. value
        end
    end
    for i = n + 1, #UI.shareLines do
        local row = UI.shareLines[i]
        row.band:Hide()
        row.label:Hide()
        row.value:Hide()
    end
    UI.shareStatus = table.concat(plain, "\n")
end

function UI.refreshShare()
    local groups = {}
    local update = F.Raw.updateText()
    if update then
        groups[#groups + 1] = { "Update", { update } }
    end
    local s = F.Share.sending
    if #F.Share.outbox > 0 and s then
        groups[#groups + 1] =
            { "Sending", { string.format(L("%d items, %d messages left"), s.items, #F.Share.outbox) } }
    end
    local community = F.Raw.community
    if community and community.generated then
        -- Downloaded (by the helper, read at /reload) and published (by the data repository) are two
        -- different moments; each is shown with its own time.
        local here = community.scopes and community.scopes[F.Engine.scope()]
        local facts =
            { string.format(L("%d scans, downloaded by the helper %s"), community.scans, UI.age(community.generated)) }
        if here and here.publishedAt then
            facts[#facts + 1] = string.format(L("published %s"), UI.age(here.publishedAt))
        end
        groups[#groups + 1] = { "Community", facts }
        local house
        if here and here.reason then
            house = grey(string.format(L("No community price yet: %s."), here.reason))
        elseif not here or here.scans == 0 then
            house = grey(L("No community price yet: no scan of this auction house is published."))
        elseif here.own >= here.scans then
            house = grey(L("No community price yet: only your own scans are published, and you have them."))
        else
            house = string.format(
                L("%d scans by others, %d new, the newest %s"),
                here.scans - here.own,
                here.merged,
                UI.age(here.newest)
            )
        end
        local facts = { house }
        -- How many players' scans the community price rests on: each one more makes it better.
        if here and here.sharers and here.sharers > 0 then
            facts[#facts + 1] = string.format(L("%d players share scans of this house"), here.sharers)
            if not F.db.settings.rawScans then
                facts[#facts + 1] = grey(L("Add yours: turn on Keep my full scans for the ForeverFlip Sync helper"))
            end
        end
        groups[#groups + 1] = { "This house", facts }
    else
        groups[#groups + 1] = { "Community", { grey(L("none: run the ForeverFlip Sync helper to get it")) } }
    end
    -- What the helper did with the player's own scans (it lists the ones it shared, read at /reload).
    local shared, newest = F.Raw.sharedSummary()
    local own = {}
    if shared > 0 then
        own[#own + 1] =
            string.format(L("Shared by the helper: %d of your scans, the newest %s"), shared, UI.age(newest))
    end
    if F.db.settings.rawScans then
        local saved = F.Raw.saved()
        own[#own + 1] = #saved > 0 and string.format(L("Full scans waiting for the helper: %d"), #saved)
            or L("all are shared")
    end
    if #own > 0 then
        groups[#groups + 1] = { "My scans", own }
    end
    if #F.Share.received > 0 then
        local got = {}
        for i = 1, math.min(3, #F.Share.received) do
            local r = F.Share.received[i]
            got[#got + 1] = string.format(L("%s (%d items, %s)"), r.from, r.items, UI.age(r.at))
        end
        groups[#groups + 1] = { "Received", got }
    else
        groups[#groups + 1] = { "Received", { grey(L("nothing yet")) } }
    end
    showShare(groups)
    local busy = #F.Share.outbox > 0
    UI.shareGuild:SetEnabled(not busy and F.Scan.last ~= nil)
    UI.shareGroup:SetEnabled(not busy and F.Scan.last ~= nil)
    UI.shareWhisper:SetEnabled(not busy and F.Scan.last ~= nil)
    UI.shareExport:SetEnabled(F.Scan.last ~= nil)
end

function UI.createGeneralSettings(p)
    -- { setting, short label, kind, column, full explanation (tooltip) }
    local fields = {
        { "vendorMinProfit", "Vendor deal", "money", 1, "Minimum profit of a vendor deal, per unit" },
        { "minProfit", "Resale", "money", 1, "Minimum profit of a resale" },
        { "minROI", "Resale return, %", "percent", 1, "Minimum resale return, %" },
        {
            "sellMinReturn",
            "Selling, % over cost",
            "percent",
            1,
            "Least a sale of your stock brings over its real cost (price paid plus deposits lost on reposts), %: posts never go below it",
        },
        { "spendShare", "One deal, % of money", "percent", 2, "Money one deal may use, %" },
        { "itemShare", "One item, % of money", "percent", 2, "Money one item may hold (stock and new resale), %" },
        { "alertMinProfit", "Sound notice from", "money", 1, "Smallest profit with a sound notice" },
        {
            "undercutPercent",
            "Undercut, %",
            "percent",
            2,
            "How far below the cheapest other seller your posts go, %. 0 = one price step below them. Used when you post and when Undercuts reposts.",
        },
        {
            "minPricePercent",
            "Never post below, %",
            "percent",
            2,
            "The lowest a post may go, % of the item's usual price: a cheaper market is not followed below it. 0 = off; the break-even of your stock and a rule's minimum still apply.",
        },
        {
            "maxPricePercent",
            "Ignore sellers above, %",
            "percent+",
            2,
            "When the cheapest seller asks more than this % of the usual price, post at the usual price instead of just under them. 0 = always follow the cheapest seller.",
        },
        -- The Market reset's own limits (also on its Deals page): sections 3 and 4, under Limits.
        { "medianItemGold", "Per item, g", "gold", 3, "Gold one item may take in this strategy" },
        { "medianDayGold", "Per day, g", "gold", 3, "Gold this strategy may spend in a day (0 turns it off)" },
        {
            "medianShare",
            "% of gold",
            "percent",
            4,
            "Share of the money on hand this strategy may use, % (0 turns it off)",
        },
    }
    local COL = { 12, 326 }
    local WIDTH = 296
    heading(p, "Minimum profit", COL[1], -6, WIDTH)
    heading(p, "Money and prices", COL[2], -6, WIDTH)
    UI.settingBoxes = {}
    local function box(i, f, x, y)
        local label = text(p, "GameFontHighlight")
        label:SetPoint("TOPLEFT", p, "TOPLEFT", x, y - 4)
        label:SetWidth(WIDTH - 100)
        label:SetWordWrap(false)
        label:SetText(L(f[2]))
        local e = editbox(p, 86)
        e:SetPoint("TOPRIGHT", p, "TOPLEFT", x + WIDTH, y)
        e:SetJustifyH("RIGHT")
        e.field = f
        hint(e, f[2], f[5])
        e:SetScript("OnTextChanged", UI.updateSave)
        UI.settingBoxes[i] = e
    end
    local rows = { 0, 0 }
    for i, f in ipairs(fields) do
        if f[4] <= 2 then
            box(i, f, COL[f[4]], -30 - rows[f[4]] * 26)
            rows[f[4]] = rows[f[4]] + 1
        end
    end

    -- Limits under the profit and money boxes, then the Market reset and the posting duration.
    local top = -30 - math.max(rows[1], rows[2]) * 26 - 8
    UI.createSafetySettings(p, top, COL, WIDTH)
    top = top - 22 - 2 * 26 - 8
    heading(p, "Market reset", COL[1], top, WIDTH)
    heading(p, "Posting", COL[2], top, WIDTH)
    rows = { 0, 0 }
    for i, f in ipairs(fields) do
        if f[4] > 2 then
            local col = f[4] - 2
            box(i, f, COL[col], top - 22 - rows[col] * 26)
            rows[col] = rows[col] + 1
        end
    end
    -- The duration of new posts, the same setting as the Duration buttons of the Selling page.
    local y = top - 22 - rows[2] * 26
    local durationLabel = text(p, "GameFontHighlight")
    durationLabel:SetPoint("TOPLEFT", p, "TOPLEFT", COL[2], y - 4)
    durationLabel:SetText(L("Auction duration, h"))
    UI.settingDurations = {}
    for i, d in ipairs({ { 1, 1 }, { 2, 2 }, { 3, 3 }, { 0, 0 } }) do
        local b = button(p, UI.durationLabel(d[1]), i == 4 and 50 or 34, function()
            F.db.settings.duration = d[2]
            F.Engine.changed()
            UI.refreshGeneralSettings()
            UI.refresh()
        end)
        b.value = d[2]
        hint(
            b,
            "Auction duration, h",
            "How long new posts stay up. Auto picks it from the item's sales. The Selling page has the same buttons."
        )
        UI.settingDurations[i] = b
    end
    -- Laid out from the right edge of the column, like the boxes.
    UI.settingDurations[4]:SetPoint("TOPRIGHT", p, "TOPLEFT", COL[2] + WIDTH, y)
    for i = 3, 1, -1 do
        UI.settingDurations[i]:SetPoint("RIGHT", UI.settingDurations[i + 1], "LEFT", -2, 0)
    end
    p:SetScript("OnShow", UI.refreshGeneralSettings)

    -- Bottom: Save and the presets.
    local bar = CreateFrame("Frame", nil, p)
    bar:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
    bar:SetHeight(34)
    local line = bar:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.25)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", bar, "TOPLEFT", 4, 0)
    line:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -4, 0)
    UI.saveButton = button(bar, "Save", 90, function()
        local bad = false
        for _, e in ipairs(UI.settingBoxes) do
            local key, kind = e.field[1], e.field[3]
            local v
            if kind == "money" then
                v = U.parseMoney(e:GetText())
            else
                v = typedNumber(e:GetText())
            end
            if v and v >= 0 then
                if kind == "percent" then
                    v = U.clamp(v / 100, 0, 1)
                elseif kind == "percent+" then
                    v = U.clamp(v / 100, 0, 10)
                end
                F.db.settings[key] = v
            else
                bad = true
            end
        end
        bad = UI.saveSafety() or bad
        UI.loadSettings()
        F.Engine.notify(bad and "not_number" or "saved")
    end)
    UI.saveButton:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 8, 6)
    -- Off while no box was changed; the hover says why, so it works on the disabled button too.
    UI.saveButton:SetMotionScriptsWhileDisabled(true)
    UI.saveButton:SetScript("OnEnter", function(self)
        if GameTooltip then
            local changed = self:IsEnabled()
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L(changed and "Save" or "Nothing to save"), 1, 0.82, 0, 1, true)
            GameTooltip:AddLine(
                L(
                    changed and "Saves the boxes you changed."
                        or "No box was changed. Check boxes and presets are saved at once."
                ),
                1,
                1,
                1,
                true
            )
            GameTooltip:Show()
        end
    end)
    UI.saveButton:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    -- The Safety page's own Save, from before the pages were one.
    UI.safetySave = UI.saveButton
    local last = UI.saveButton
    for i, name in ipairs({ "careful", "balanced", "aggressive" }) do
        local b = button(bar, UI.PRESET_LABELS[name], 86, function()
            UI.applyPreset(name)
        end)
        b:SetPoint("LEFT", last, "RIGHT", i == 1 and 14 or 4, 0)
        hint(b, "Presets:", "Set the money and profit thresholds in one click.")
        last = b
        UI["preset_" .. name] = b
    end
    UI.loadSettings()
end

-- Presets set the money and profit thresholds in one click.
UI.PRESET_LABELS = { careful = "Careful", balanced = "Balanced", aggressive = "Aggressive" }
-- The values live in Data (D.PRESETS): a new profile starts on Careful (T27).
UI.PRESETS = F.Data.PRESETS
function UI.applyPreset(name)
    for key, value in pairs(UI.PRESETS[name] or {}) do
        F.db.settings[key] = value
    end
    UI.loadSettings()
    F.Engine.notify("saved")
end

function UI.loadSettings()
    for _, e in ipairs(UI.settingBoxes) do
        local key, kind = e.field[1], e.field[3]
        local v = F.db.settings[key]
        if kind == "money" then
            e:SetText(U.plainMoney(v))
        elseif kind == "gold" then
            e:SetText(string.format("%g", tonumber(v) or 0))
        else
            -- The percent as saved (2.5, not 3): Save reads every box again, so a rounded one would
            -- change a setting the player did not touch.
            e:SetText(string.format("%g", v * 100))
        end
        e.saved = e:GetText()
    end
    UI.loadSafety()
end

-- General shown again: the boxes nobody is typing in show the saved values (the Market reset limits
-- may have been changed on their Deals page), and the duration buttons the current one.
function UI.refreshGeneralSettings()
    for _, b in ipairs(UI.settingDurations or {}) do
        b:SetText(L(UI.durationLabel(b.value)))
        b:SetEnabled(F.db.settings.duration ~= b.value)
    end
    local typed = {}
    for _, e in ipairs(UI.settingBoxes or {}) do
        if e.saved ~= nil and e:GetText() ~= e.saved then
            typed[e] = e:GetText()
        end
    end
    UI.loadSettings()
    for e, value in pairs(typed) do
        e:SetText(value)
    end
    UI.updateSave()
end

-- Automation: what ForeverFlip does by itself while the auction house is open, and the notices.
-- { setting, label, explanation }, or { heading }; the sniper goes through Deals.setSniper.
local AUTO_OPTIONS = {
    { "Background work" },
    { "autoScan", "Full scan every 15 minutes", "Full scan every 15 minutes while the auction house is open" },
    {
        "autoVerify",
        "Check deals automatically",
        "Check found deals on the auction house automatically (one search per second)",
    },
    { "sniper", "Sniper between scans", "Sniper: between scans, re-read the items most often near a deal" },
    {
        "learnBrowsing",
        "Learn from my searches",
        "Learn prices and deals from my own searches in the Buy tab",
    },
    { "Selling" },
    {
        "belowMin",
        "Keep items below their floor",
        "Keep items in the bags when the market is below their floor",
    },
    { "Notices" },
    { "alerts", "Sound for a buyable deal", "Sound and screen notice when a deal can be bought" },
    { "soundSold", "Sound for a sale", "A coin sound when the game says one of your auctions sold" },
    {
        "soundOutbid",
        "Sound when outbid",
        "An alarm when someone outbids you; the bid can be answered on the shopping list (My bids)",
    },
}

-- Display: what ForeverFlip adds to the game's own windows and how its lists look.
local DISPLAY_OPTIONS = {
    { "In the game" },
    { "tooltipPrices", "Prices in item tooltips", "Price history from the scans in item tooltips" },
    { "highlight", "Mark deals in the Buy tab", "Mark deals in the game's Buy tab" },
    { "Lists" },
    {
        "hideUnlearned",
        "Learned recipes only",
        "Crafting lists only the recipes this character has learned. The Crafting page has the same switch.",
    },
}

local function optionChecked(setting)
    if setting == "belowMin" then
        return F.db.settings.belowMin == "hold"
    end
    return F.db.settings[setting] and true or false
end

local function optionSet(setting, on)
    if setting == "sniper" then
        F.Deals.setSniper(on)
    elseif setting == "belowMin" then
        F.db.settings.belowMin = on and "hold" or "min"
    else
        F.db.settings[setting] = on
    end
end

-- Builds a page of options from the top; returns the y under the last row.
local function optionPage(p, list)
    local y = -6
    p.optionBoxes = {}
    for _, o in ipairs(list) do
        if not o[2] then
            heading(p, o[1], 12, y)
            y = y - 22
        else
            local box = optionRow(p, y, o[2], o[3], optionChecked(o[1]), function(self)
                optionSet(o[1], self:GetChecked() and true or false)
                UI.refresh()
            end)
            box.setting = o[1]
            p.optionBoxes[#p.optionBoxes + 1] = box
            if o[1] == "sniper" then
                UI.sniperBox = box
            end
            y = y - OPTION_STEP
        end
    end
    p:SetScript("OnShow", function(self)
        for _, b in ipairs(self.optionBoxes) do
            b:SetChecked(optionChecked(b.setting))
        end
    end)
    return y - 8
end

function UI.createAutoSettings(p)
    local y = optionPage(p, AUTO_OPTIONS)
    -- The smallest profit with a sound is a box of General (it is saved with the others).
    local note = text(p, "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", p, "TOPLEFT", 14, y)
    note:SetPoint("RIGHT", p, "RIGHT", -14, 0)
    note:SetJustifyH("LEFT")
    note:SetText(
        UI.C.dim .. L("The smallest profit that sounds a notice is set on General (Sound notice from).") .. "|r"
    )
end

function UI.createDisplaySettings(p)
    local y = optionPage(p, DISPLAY_OPTIONS)
    heading(p, "Window size", 12, y)
    local sizeAbout = text(p, "GameFontHighlightSmall")
    sizeAbout:SetPoint("TOPLEFT", p, "TOPLEFT", 14, y - 22)
    sizeAbout:SetPoint("RIGHT", p, "RIGHT", -14, 0)
    sizeAbout:SetJustifyH("LEFT")
    sizeAbout:SetText(
        UI.C.soft
            .. L("How large ForeverFlip draws its window inside the auction house; smaller fits more in the lists.")
            .. "|r"
    )
    UI.scaleButtons = {}
    local function syncScale()
        local now = UI.windowScale()
        for _, b in ipairs(UI.scaleButtons) do
            b:SetEnabled(math.abs(b.scale - now) > 0.001)
        end
    end
    for i, scale in ipairs(UI.SCALES) do
        local b = button(p, string.format("%d%%", math.floor(scale * 100 + 0.5)), 60, function(self)
            F.db.settings.windowScale = self.scale
            UI.applyScale()
            syncScale()
            UI.refresh()
        end)
        b.scale = scale
        b:SetPoint("TOPLEFT", p, "TOPLEFT", 12 + (i - 1) * 64, y - 44)
        UI.scaleButtons[i] = b
    end
    syncScale()
    local was = p:GetScript("OnShow")
    p:SetScript("OnShow", function(self)
        if was then
            was(self)
        end
        syncScale()
    end)
    y = y - 80
    heading(p, "Language", 12, y)
    local about = text(p, "GameFontHighlightSmall")
    about:SetPoint("TOPLEFT", p, "TOPLEFT", 14, y - 22)
    about:SetPoint("RIGHT", p, "RIGHT", -14, 0)
    about:SetJustifyH("LEFT")
    about:SetText(
        UI.C.soft
            .. L("ForeverFlip's own language. The interface reloads to apply it; the game's language does not change.")
            .. "|r"
    )
    local en = button(p, "English", 90, function()
        F.db.settings.language = "en"
        F.Engine.notify("reload")
    end)
    en:SetPoint("TOPLEFT", p, "TOPLEFT", 12, y - 44)
    local uk = button(p, "Українська", 90, function()
        F.db.settings.language = "uk"
        F.Engine.notify("reload")
    end)
    uk:SetPoint("LEFT", en, "RIGHT", 4, 0)
    hint(en, "Language (applies after /reload)", "Language (applies after /reload)")
    hint(uk, "Language (applies after /reload)", "Language (applies after /reload)")
end

-- Data: what ForeverFlip learned, and the two clean starts (the settings, or everything else).
function UI.createDataSettings(p)
    heading(p, "What ForeverFlip learned", 12, -6)
    UI.safetyText = text(p, "GameFontHighlightSmall")
    UI.safetyText:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -30)
    UI.safetyText:SetPoint("RIGHT", p, "RIGHT", -14, 0)
    UI.safetyText:SetHeight(130)
    UI.safetyText:SetJustifyH("LEFT")
    UI.safetyText:SetJustifyV("TOP")

    local function section(y, title, about, label, onClick)
        heading(p, title, 12, y)
        local t = text(p, "GameFontHighlightSmall")
        t:SetPoint("TOPLEFT", p, "TOPLEFT", 14, y - 22)
        t:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, y - 22)
        t:SetJustifyH("LEFT")
        t:SetText(L(about))
        local b = button(p, label, 190, onClick)
        b:SetPoint("TOPLEFT", p, "TOPLEFT", 12, y - 52)
        return b
    end
    UI.resetSettingsButton = section(
        -176,
        "Settings",
        "Puts every setting back as on a new profile (the Careful preset, nothing running by itself). Prices, sales and journals stay; so do the language and the key bindings.",
        "Reset settings...",
        function()
            UI.confirmResetSettings()
        end
    )
    UI.resetDataButton = section(
        -266,
        "Saved data",
        "Forgets every price, sale, journal and position and starts learning the market anew. Your settings stay. The interface reloads.",
        "Reset all data...",
        function()
            UI.confirmReset()
        end
    )
    p:SetScript("OnShow", UI.refreshSafety)
end

-- Settings back to a new profile's (Data.resetSettings), asked first.
function UI.resetSettings()
    if F.db.settings.sniper then
        F.Deals.setSniper(false)
    end
    F.Data.resetSettings(F.db)
    UI.applyScale()
    UI.loadSettings()
    UI.refreshGeneralSettings()
    F.Engine.notify("saved")
    UI.refresh()
end

function UI.confirmResetSettings()
    if not StaticPopupDialogs or not StaticPopup_Show then
        return
    end
    StaticPopupDialogs.FOREVERFLIP_RESET_SETTINGS = {
        text = L(
            "Put every ForeverFlip setting back as on a new profile?\n\nThresholds, limits and options return to the Careful preset. Your data, language and key bindings stay."
        ),
        button1 = L("Reset"),
        button2 = L("Cancel"),
        OnAccept = UI.resetSettings,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("FOREVERFLIP_RESET_SETTINGS")
end
