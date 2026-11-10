-- Auction house mail in one click: bought items, sale gold, expired and cancelled items. The
-- click starts a paced run (one mail action every 0.4 s, as fast mail looting errors out); it
-- stops when the mailbox closes, the bags are full or no auction mail is left.
local F = ForeverFlip
local Mail = {}
F.Mail = Mail

Mail.PACE = 0.4

local SUBJECTS = {
    "AUCTION_EXPIRED_MAIL_SUBJECT",
    "AUCTION_REMOVED_MAIL_SUBJECT",
    "AUCTION_WON_MAIL_SUBJECT",
    "AUCTION_SOLD_MAIL_SUBJECT",
    "AUCTION_OUTBID_MAIL_SUBJECT",
}

local function subjectPattern(template)
    if type(template) ~= "string" then
        return nil
    end
    local s = template:gsub("%%s", "\1")
    s = s:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0")
    s = s:gsub("\1", ".+")
    return "^" .. s .. "$"
end

-- An auction house mail without cash on delivery, with gold or items to take.
function Mail.isAuction(i)
    local _, _, _, subject, money, cod, _, hasItem = GetInboxHeaderInfo(i)
    if (cod or 0) > 0 or ((money or 0) <= 0 and not hasItem) then
        return false
    end
    if GetInboxInvoiceInfo and GetInboxInvoiceInfo(i) then
        return true
    end
    for _, name in ipairs(SUBJECTS) do
        local pattern = subjectPattern(_G[name])
        if pattern and type(subject) == "string" and subject:match(pattern) then
            return true
        end
    end
    return false
end

-- Accounting from auction mail --------------------------------------------------------------------
-- A seller invoice tells the real sale price, the cut and the deposit; expired and cancelled mails
-- tell which posts failed. A mail is read when its money or items are taken: by the Take auction
-- mail button or by the game's own mailbox (hooked), each mail once.
Mail.snap = {}

local FAILED = { "AUCTION_EXPIRED_MAIL_SUBJECT", "AUCTION_REMOVED_MAIL_SUBJECT" }

local function read(i)
    local _, _, sender, subject, money = GetInboxHeaderInfo(i)
    local snap = { subject = subject, money = money, sender = sender }
    if GetInboxInvoiceInfo then
        local kind, item, _, bid, _, deposit, consignment, _, _, count = GetInboxInvoiceInfo(i)
        if type(kind) == "string" then
            snap.invoice = {
                kind = kind,
                item = item,
                bid = bid or 0,
                deposit = deposit or 0,
                cut = consignment or 0,
                count = count or 1,
            }
        end
    end
    return snap
end

-- MAIL_INBOX_UPDATE: what each mail holds before anything is taken.
function Mail.snapshot()
    Mail.snap = {}
    for i = 1, (GetInboxNumItems and GetInboxNumItems() or 0) do
        local ok, snap = pcall(read, i)
        if ok then
            Mail.snap[i] = snap
        end
    end
end

local function failedItem(subject)
    if type(subject) ~= "string" then
        return nil
    end
    for _, name in ipairs(FAILED) do
        local pattern = subjectPattern(_G[name])
        if pattern then
            local item = subject:match(pattern:gsub("%.%+", "(.+)", 1))
            if item then
                local plain, count = item:match("^(.-)%s*%((%d+)%)$")
                return plain or item, tonumber(count) or 1
            end
        end
    end
end

-- Books mail `i` once.
function Mail.record(i)
    local snap = Mail.snap[i]
    if not snap then
        local ok, s = pcall(read, i)
        if not ok then
            return
        end
        snap = s
        Mail.snap[i] = snap
    end
    if snap.recorded or not F.db then
        return
    end
    snap.recorded = true
    local inv = snap.invoice
    if inv and inv.kind == "seller" and type(inv.item) == "string" then
        F.Trade.onInvoice(inv)
        return
    end
    local name, count = failedItem(snap.subject)
    if name then
        F.Trade.onFailedPost(name, count)
    end
end

-- The game's own mailbox buttons and other mail addons take mail through these functions.
function Mail.hook()
    if Mail.hooked or not hooksecurefunc then
        return
    end
    Mail.hooked = true
    for _, name in ipairs({ "TakeInboxMoney", "AutoLootMailItem", "TakeInboxItem" }) do
        if _G[name] then
            hooksecurefunc(name, function(i)
                pcall(Mail.record, i)
            end)
        end
    end
end

function Mail.count()
    local n = 0
    for i = 1, (GetInboxNumItems and GetInboxNumItems() or 0) do
        if Mail.isAuction(i) then
            n = n + 1
        end
    end
    return n
end

local function freeSlots()
    local free = 0
    for bag = 0, 4 do
        free = free + (C_Container and C_Container.GetContainerNumFreeSlots(bag) or 0)
    end
    return free
end

function Mail.start()
    if Mail.job or not Mail.open then
        return false
    end
    Mail.job = { next = 0, gold = 0, items = 0 }
    F.Engine.changed()
    return true
end

function Mail.stop(reason)
    local job = Mail.job
    Mail.job = nil
    if job and reason then
        F.Engine.notify(reason)
        local L = F.Locale.text
        print(
            "ForeverFlip: "
                .. string.format(L("auction mail taken: %s gold, %d items"), F.Util.money(job.gold), job.items)
        )
    end
    F.Engine.changed()
end

function Mail.step(now)
    local job = Mail.job
    if not job or now < job.next then
        return
    end
    if not Mail.open then
        Mail.stop("mail_closed")
        return
    end
    for i = 1, (GetInboxNumItems() or 0) do
        if Mail.isAuction(i) then
            local _, _, _, _, money, _, _, hasItem = GetInboxHeaderInfo(i)
            job.next = now + Mail.PACE
            Mail.record(i)
            if (money or 0) > 0 then
                TakeInboxMoney(i)
                job.gold = job.gold + money
            elseif hasItem then
                if freeSlots() == 0 then
                    Mail.stop("bags_full")
                    return
                end
                AutoLootMailItem(i)
                job.items = job.items + 1
            end
            F.Engine.changed()
            return
        end
    end
    Mail.stop("mail_done")
end
