-- Auction house mail in one click: bought items, sale gold, expired and cancelled items. The
-- click starts a paced run (one mail action every 0.4 s, as fast mail looting errors out); it
-- stops when the mailbox closes, the bags are full or no auction mail is left.
local F = ForeverFlip
local U = F.Util
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
    if GetInboxItemLink then
        local ok, link = pcall(GetInboxItemLink, i, 1)
        snap.link = ok and link or nil
    end
    if GetInboxInvoiceInfo then
        -- type, item, player, bid, buyout, deposit, cut, money delay, eta hour, eta minute, count:
        -- the count is the 11th value. Reading the 10th (the minute of delivery, nearly always 0)
        -- booked no sale from any invoice. Without a count, the subject's "(5)" tells it.
        local kind, item, player, bid, _, deposit, consignment, _, _, _, count = GetInboxInvoiceInfo(i)
        if not U.finite(count) or count < 1 then
            count = tonumber(type(subject) == "string" and subject:match("%((%d+)%)%s*$")) or 1
        end
        if type(kind) == "string" then
            snap.invoice = {
                kind = kind,
                item = item,
                player = player,
                bid = bid or 0,
                deposit = deposit or 0,
                cut = consignment or 0,
                count = count or 1,
            }
        end
    end
    return snap
end

-- Invoice identity survives inbox updates and taking gold from a mail that still holds items.
local function signature(snap)
    local inv = snap.invoice or {}
    return table.concat({
        tostring(snap.sender),
        tostring(snap.subject),
        tostring(snap.link),
        tostring(inv.kind),
        tostring(inv.item),
        tostring(inv.bid),
        tostring(inv.count),
        tostring(inv.deposit),
        tostring(inv.cut),
    }, "\031")
end

-- Match surviving mail as a multiset: identical letters remain distinct occurrences.
function Mail.snapshot()
    local previous, current, counts = {}, {}, {}
    for _, snap in pairs(Mail.snap) do
        local sig = signature(snap)
        local p = previous[sig] or { count = 0, recorded = 0 }
        p.count = p.count + 1
        p.recorded = p.recorded + (snap.recorded and 1 or 0)
        previous[sig] = p
    end
    for i = 1, (GetInboxNumItems and GetInboxNumItems() or 0) do
        local ok, snap = pcall(read, i)
        if ok then
            current[i] = snap
            local sig = signature(snap)
            counts[sig] = (counts[sig] or 0) + 1
        end
    end
    for sig, p in pairs(previous) do
        -- Removed letters were the recorded ones whose attachments the player took.
        p.recorded = math.max(0, p.recorded - math.max(0, p.count - (counts[sig] or 0)))
    end
    for _, snap in pairs(current) do
        local p = previous[signature(snap)]
        if p and p.recorded > 0 then
            snap.recorded = true
            p.recorded = p.recorded - 1
        end
    end
    Mail.snap = current
end

local function subjectItem(subject, names)
    if type(subject) ~= "string" then
        return nil
    end
    for _, name in ipairs(names) do
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

-- Mail `i` as read at the last inbox update, or now.
local function snapAt(i)
    local snap = Mail.snap[i]
    if not snap then
        local ok, s = pcall(read, i)
        if not ok then
            return nil
        end
        snap = s
        Mail.snap[i] = snap
    end
    return snap
end

-- Books a mail once.
local function book(snap)
    if snap.recorded or not F.db then
        return
    end
    snap.recorded = true
    local inv = snap.invoice
    -- A post that came back. WoW Forever mails a cancelled auction's items with a buyer invoice
    -- (from the player): that is no purchase. Up to 2.0.0-beta.1 it was booked as one. The player
    -- may be named with the realm, as in owner lists (F.AH.isPlayer).
    local name, count = subjectItem(snap.subject, FAILED)
    if not name and inv and inv.kind == "buyer" and type(inv.item) == "string" and F.AH.isPlayer(inv.player) then
        name, count = inv.item, inv.count
    end
    if name then
        F.Trade.onFailedPost(name, count)
        return
    end
    if inv and inv.kind == "seller" and type(inv.item) == "string" then
        F.Trade.onInvoice(inv)
        return
    end
    -- A buyer invoice comes with every item bought on the auction house, also through the game's
    -- Buy tab or another addon: purchases ForeverFlip did not make are booked from it.
    if inv and inv.kind == "buyer" and type(inv.item) == "string" then
        F.Trade.onBuyerInvoice(inv, snap.link)
        return
    end
    name = subjectItem(snap.subject, { "AUCTION_WON_MAIL_SUBJECT" })
    if name then
        F.Bids.won(name)
        return
    end
    name = subjectItem(snap.subject, { "AUCTION_OUTBID_MAIL_SUBJECT" })
    if name then
        F.Bids.outbid(name)
    end
end

-- Books mail `i` once.
function Mail.record(i)
    local snap = snapAt(i)
    if snap then
        book(snap)
    end
end

-- The game's own mailbox buttons and other mail addons take mail through these functions. The
-- Take auction mail run books its own takes (Mail.step): ownTake while it calls them.
local ownTake = false
function Mail.hook()
    if Mail.hooked or not hooksecurefunc then
        return
    end
    Mail.hooked = true
    for _, name in ipairs({ "TakeInboxMoney", "AutoLootMailItem", "TakeInboxItem" }) do
        if _G[name] then
            hooksecurefunc(name, function(i)
                -- With full bags the item stays in the mail: it is booked when it is really taken.
                if ownTake or name ~= "TakeInboxMoney" and F.AH.freeBagSlots() == 0 then
                    return
                end
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

function Mail.start()
    if Mail.job or not Mail.open then
        return false
    end
    Mail.job = { next = 0, gold = 0, items = 0 }
    F.Engine.changed()
    return true
end

-- The take of the step before: once its mail changed or left the inbox (sig differs), its gold or
-- item is counted and an item mail is booked. A take the game refused leaves the mail as it was:
-- nothing is counted or booked, and the mail is booked when it is really taken. Booked before the
-- take, a refused item mail (the bags full but for a quiver) was booked again after a /reload.
local function settle(job, sig)
    local t = job.taking
    if not t or t.sig == sig then
        return
    end
    job.taking = nil
    job.gold = job.gold + (t.gold or 0)
    job.items = job.items + (t.items or 0)
    if t.snap then
        book(t.snap)
    end
end

function Mail.stop(reason)
    local job = Mail.job
    Mail.job = nil
    -- Closed right after a take, before its answer was seen: the take counts as done.
    if job and (reason == nil or reason == "mail_closed") then
        settle(job, nil)
    end
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
    local n = GetInboxNumItems() or 0
    for i = 1, n do
        if Mail.isAuction(i) then
            local _, _, _, subject, money, _, _, hasItem = GetInboxHeaderInfo(i)
            job.next = now + Mail.PACE
            -- The same mail asked for again and again without a change: the game refuses it. The
            -- inbox size tells a look-alike mail that moved up into the place of a taken one apart
            -- (eight identical sale mails stopped the run after five as refused).
            local sig = table.concat({ n, i, tostring(subject), tostring(money), tostring(hasItem) }, "|")
            settle(job, sig)
            job.tries = job.tries or {}
            job.tries[sig] = (job.tries[sig] or 0) + 1
            if job.tries[sig] > 5 then
                Mail.stop("mail_stuck")
                return
            end
            local take, taking = TakeInboxMoney, { sig = sig, gold = money }
            if (money or 0) > 0 then
                Mail.record(i) -- money needs no bag room: booked as it is taken
            elseif F.AH.freeBagSlots() == 0 then
                -- Not booked yet: the mail stays, and is booked when its item is taken.
                Mail.stop("bags_full")
                return
            else
                take, taking = AutoLootMailItem, { sig = sig, items = 1, snap = snapAt(i) }
            end
            ownTake = true
            local ok, err = pcall(take, i)
            ownTake = false
            if not ok then
                error(err, 0)
            end
            job.taking = taking
            F.Engine.changed()
            return
        end
    end
    settle(job, nil)
    Mail.stop("mail_done")
end
