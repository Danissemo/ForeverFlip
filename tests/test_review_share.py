"""Review fixes in Share.lua: pacing and the client's throttle, receiving, the realm channel, trust."""

import unittest

from test_addon import SETUP, run

SHARE = SETUP + '''local F = ForeverFlip
local Sh = F.Share
sentMessages = {}
C_ChatInfo = { RegisterAddonMessagePrefix = function() end,
    SendAddonMessage = function(prefix, text, channel, target)
        sentMessages[#sentMessages + 1] = { prefix, text, channel, target } end }
function IsInGuild() return true end
function IsInGroup() return true end
local function joined() function GetChannelName(name) return name == 'ForeverFlipPrices' and 5 or 0 end end
local function sent(kind)
    for _, m in ipairs(sentMessages) do if m[2]:sub(1, #kind) == kind then return m end end
end
local function data()
    local n = 0
    for _, m in ipairs(sentMessages) do if m[2]:sub(1, 1) ~= '!' then n = n + 1 end end
    return n
end
-- `count` items of the house with a record for each of the last `days` days.
local function addHistory(count, days)
    local history = F.Data.market(F.db, F.Engine.scope()).history
    local day = math.floor(now / 86400)
    for i = 1, count do
        local h = { days = {} }
        for o = days - 1, 0, -1 do
            h.days[#h.days + 1] = { d = day - o, min = 120000 + i, m = 150000 + i, n = 40, s = 3 }
        end
        history['c:' .. (2000 + i)] = h
    end
end
local function request(who)
    Sh.onMessage(Sh.PREFIX, '!R|Me|' .. F.Engine.scope() .. '|' .. Sh.enc(F.Scan.last.at), 'CHANNEL', who)
end
'''


class SendingTests(unittest.TestCase):
    def test_the_pace_stays_within_the_clients_allowance(self):
        # V17-e: 10 messages per prefix, then one a second; more are refused with 3.
        run(SHARE + '''addHistory(150, 7); fullScan()
        local tokens, last, accepted, refused = 10, now, {}, 0
        C_ChatInfo.SendAddonMessage = function(prefix, text)
            tokens = math.min(10, tokens + (now - last)); last = now
            if tokens < 1 then refused = refused + 1; return 3 end
            tokens = tokens - 1; accepted[#accepted + 1] = text; return 0
        end
        assert(Sh.send('GUILD')); local total = #Sh.outbox; assert(total > 20, total)
        local frames = 0
        while #Sh.outbox > 0 do run(0.05); frames = frames + 1; assert(frames < 20000) end
        assert(refused == 0 and #accepted == total, refused .. ' refused, ' .. #accepted .. '/' .. total)''')

    def test_throttled_parts_are_sent_again_in_order(self):
        # V17-e: a client that refuses more than this pace (allowance back at one every 2 s).
        run(SHARE + '''addHistory(150, 7); fullScan()
        local tokens, last, accepted, refused = 10, now, {}, 0
        C_ChatInfo.SendAddonMessage = function(prefix, text)
            tokens = math.min(10, tokens + (now - last) / 2); last = now
            if tokens < 1 then refused = refused + 1; return 3 end
            tokens = tokens - 1; accepted[#accepted + 1] = text; return 0
        end
        assert(Sh.send('GUILD')); local total = #Sh.outbox
        local frames = 0
        while #Sh.outbox > 0 do
            assert(F.Engine.message ~= 'share_sent', 'not sent before the last part is accepted')
            run(0.05); frames = frames + 1; assert(frames < 40000)
        end
        assert(refused > 0, 'the throttle was hit')
        assert(#accepted == total, #accepted .. '/' .. total)
        for i, text in ipairs(accepted) do assert(Sh.dec(text:match('^%w+:(%w+):')) == i, 'in order') end
        assert(F.Engine.message == 'share_sent')
        -- Another player of the realm gets every part.
        F.Scan.last = nil
        for _, text in ipairs(accepted) do Sh.onMessage(Sh.PREFIX, text, 'GUILD', 'Friend-Realm') end
        assert(#Sh.pending == 1, 'the receiver completes the scan')''')

    def test_a_refused_part_ends_the_transfer_without_share_sent(self):
        # V17-e: a result other than success or throttle (9: GeneralError) refuses the part for good.
        run(SHARE + '''addHistory(30, 7); fullScan()
        local calls = 0
        C_ChatInfo.SendAddonMessage = function() calls = calls + 1; if calls == 3 then return 9 end return 0 end
        assert(Sh.send('GUILD')); local total = #Sh.outbox; assert(total > 4, total)
        run(total + 5)
        assert(#Sh.outbox == 0 and calls == 3, 'no part after the refused one: ' .. calls)
        assert(F.Engine.message == 'error', F.Engine.message)
        -- Older clients return true (or nothing) for a message sent.
        C_ChatInfo.SendAddonMessage = function() return true end
        assert(Sh.send('GUILD')); run(total + 5)
        assert(#Sh.outbox == 0 and F.Engine.message == 'share_sent')''')

    def test_control_messages_do_not_report_a_sent_scan(self):
        # V17-b
        run(SHARE + '''joined(); fullScan(); run(1)
        assert(sent('!H'), 'the new scan is announced')
        assert(F.Engine.message == 'scan_done', F.Engine.message)
        F.Engine.notify('no_deal')
        Sh.onMessage(Sh.PREFIX, '!Q|' .. F.Engine.scope() .. '|0', 'CHANNEL', 'Peer-Realm'); run(6)
        assert(F.Engine.message == 'no_deal', 'an answer is not a sent scan: ' .. F.Engine.message)
        assert(Sh.send('GUILD')); run(5)
        assert(F.Engine.message == 'share_sent')''')


class ReceivingTests(unittest.TestCase):
    def test_a_scan_is_dropped_when_its_parts_stop_coming(self):
        # V17-a: one part a second, a long scan takes longer than S.TIMEOUT.
        run(SHARE + '''Sh.onMessage(Sh.PREFIX, 'slow:1:3:a', 'GUILD', 'Friend-Realm')
        now = now + 200; Sh.onMessage(Sh.PREFIX, 'slow:2:3:b', 'GUILD', 'Friend-Realm')
        now = now + 200; Sh.onMessage(Sh.PREFIX, 'slow:3:3:c', 'GUILD', 'Friend-Realm')
        assert(#Sh.pending == 1 and Sh.pending[1].text == 'abc', 'parts that keep coming complete it')
        Sh.onMessage(Sh.PREFIX, 'gone:1:2:a', 'GUILD', 'Other-Realm')
        now = now + Sh.TIMEOUT + 1
        Sh.onMessage(Sh.PREFIX, 'next:1:2:a', 'GUILD', 'Third-Realm')
        assert(not Sh.inbox['Other-Realm/gone'], 'no part for S.TIMEOUT seconds')''')

    def test_a_sender_has_one_scan_being_received(self):
        # V17-a: with no fixed end, a sender's new scan replaces its unfinished one.
        run(SHARE + '''Sh.onMessage(Sh.PREFIX, 'old:1:2:a', 'GUILD', 'Friend-Realm')
        Sh.onMessage(Sh.PREFIX, 'its:1:2:a', 'GUILD', 'Other-Realm')
        Sh.onMessage(Sh.PREFIX, 'new:1:2:a', 'GUILD', 'Friend-Realm')
        assert(not Sh.inbox['Friend-Realm/old'] and Sh.inbox['Friend-Realm/new'])
        assert(Sh.inbox['Other-Realm/its'], 'other senders keep theirs')''')

    def test_the_cheapest_price_and_the_sales_are_checked(self):
        # V17-c: a trusted usual price with 1c as the cheapest and 10^12 units sold yesterday.
        run(SHARE + '''fullScan()
        local scope, E = F.Engine.scope(), Sh.enc
        local h = F.Data.market(F.db, scope).history['c:10']
        local own, today = h.scan.market, math.floor(now / 86400)
        local text = 'FF3|' .. scope .. '|' .. E(now - 3600) .. '|c:10,' .. E(own) .. ',' .. E(1) .. ',' .. E(5) .. ','
            .. E(1) .. '.' .. E(1) .. '.' .. E(own) .. '.' .. E(5) .. '.' .. E(1e12)
        Sh.onMessage(Sh.PREFIX, 'x1:1:1:' .. text, 'GUILD', 'Evil-Realm'); run(0.5)
        assert(#Sh.received == 1, 'the trusted usual price is merged')
        local yesterday
        for _, d in ipairs(h.days) do if d.d == today - 1 then yesterday = d end end
        assert(h.days[#h.days].d == today and h.days[#h.days].min == own, 'cheapest today unchanged')
        assert(yesterday and yesterday.m == own and yesterday.min ~= 1, 'no 1c cheapest yesterday')
        assert(yesterday.s <= 5 * 96, 'sales bounded by the units listed: ' .. yesterday.s)
        local _, cheapest = ForeverFlipAPI.GetPrice(10); assert(cheapest == own, cheapest)''')

    def test_only_canonical_keys_and_the_realms_houses_are_merged(self):
        # V17-g
        run(SHARE + '''local scope, E = F.Engine.scope(), Sh.enc
        local function item(key) return key .. ',' .. E(500) .. ',' .. E(400) .. ',' .. E(5) .. ',' end
        local text = 'FF3|' .. scope .. '|' .. E(now - 3600) .. '|' .. table.concat({ item('c:10:junk'),
            item('i:30xyz'), item('c:77%00'), item('c:78%0Aboom'), item('c:010'), item('g:20:Upper Case'),
            item('g:20:odd%2C name'), item('c:11') }, ';')
        local keys = {}
        for _, it in ipairs(Sh.decode(text).items) do keys[#keys + 1] = it.key end
        assert(table.concat(keys, '|') == 'g:20:odd, name|c:11', table.concat(keys, '|'))
        local items = { { key = 'i:999', m = 5, min = 5, n = 1 } }
        local n, why = Sh.merge({ scope = 'Realm-Anything', at = now - 7200, items = items }, 'Evil', 'GUILD')
        assert(not n and why == 'share_invalid' and F.db.markets['Realm-Anything'] == nil, tostring(why))
        assert(Sh.merge({ scope = 'Realm-Horde', at = now - 7200, items = items }, 'Friend', 'GUILD') == 1)
        -- Control characters never go out raw (an addon message cannot carry a NUL).
        local nul = 'g:20:a' .. string.char(0) .. 'b'
        local own = Sh.encode({ scope = scope, at = now, items = { { key = nul, m = 1, min = 1, n = 1 } } })
        assert(not own:find('%z') and own:find('%%00'))
        -- A malformed key already in the history is not shared on.
        fullScan()
        F.Data.market(F.db, scope).history['c:77' .. string.char(0)] =
            { scan = { at = F.Scan.last.at, market = 500 }, units = 5 }
        for _, it in ipairs(Sh.snapshot().items) do assert(not it.key:find('%z'), 'junk key shared') end''')

    def test_a_pasted_text_with_doubled_pipes_is_imported(self):
        # V23-f
        run(SHARE + '''fullScan()
        local snap = Sh.snapshot(); snap.at = snap.at + 600
        local text = Sh.encode(snap):gsub('|', '||')
        local merged, why = Sh.import(text); assert(merged and merged > 0, tostring(why))''')


class ChannelTests(unittest.TestCase):
    def test_announcements_from_the_future_are_not_believed(self):
        # V17-f
        run(SHARE + '''joined(); fullScan(); run(1)
        local scope = F.Engine.scope()
        local function answered(who)
            sentMessages = {}
            Sh.onMessage(Sh.PREFIX, '!Q|' .. scope .. '|0', 'CHANNEL', who); run(6)
            return sent('!H') ~= nil
        end
        assert(answered('Peer1-Realm'))
        sentMessages = {}
        Sh.onMessage(Sh.PREFIX, '!H|' .. scope .. '|zzzzzzzz', 'CHANNEL', 'Evil-Realm')
        Sh.onMessage(Sh.PREFIX, '!H|' .. scope .. '|' .. Sh.enc(now + 3600), 'CHANNEL', 'Ahead-Realm')
        Sh.onMessage(Sh.PREFIX, '!H|Realm-Anything|' .. Sh.enc(now), 'CHANNEL', 'Evil-Realm')
        run(3)
        assert(Sh.heard[scope] == nil and Sh.heard['Realm-Anything'] == nil and not sent('!R'))
        assert(answered('Peer2-Realm'), 'newcomers are still answered')''')

    def test_with_receiving_off_the_channel_is_still_served(self):
        # V23-e: only asking needs shareReceive.
        run(SHARE + '''F.db.settings.shareReceive = false; joined(); fullScan(); run(2)
        assert(sent('!H'), 'the new scan is announced')
        sentMessages = {}; request('Other-Realm'); run(3)
        assert(data() > 0, 'and sent when asked')
        sentMessages = {}
        Sh.onMessage(Sh.PREFIX, '!Q|' .. F.Engine.scope() .. '|0', 'CHANNEL', 'Newcomer-Realm'); run(6)
        assert(sent('!H'), 'a newcomer is answered')
        sentMessages = {}; now = now + 1200
        Sh.onMessage(Sh.PREFIX, '!H|' .. F.Engine.scope() .. '|' .. Sh.enc(now - 60), 'CHANNEL', 'Holder-Realm')
        Sh.ask(); run(4)
        assert(not sent('!R') and not sent('!Q'), 'nothing is asked for')''')

    def test_one_copy_is_sent_at_a_time(self):
        # V17-d: a copy longer than the 120 s between two requests is not queued again.
        run(SHARE + '''fullScan(); addHistory(900, 7); joined()
        request('Peer1-Realm'); run(0.5)
        local first = #Sh.outbox; assert(first > 400, first)
        run(121); local left = #Sh.outbox
        request('Peer2-Realm'); run(0.5)
        assert(#Sh.outbox <= left, #Sh.outbox .. ' > ' .. left)''')

    def test_the_text_is_built_in_slices_once_per_scan(self):
        # V24-a: no snapshot and encode of the whole history inside the request event, nor per request.
        run(SHARE + '''fullScan(); addHistory(900, 1); joined(); sentMessages = {}
        request('Peer1-Realm')
        assert(#Sh.outbox == 0, 'built a slice per frame')
        run(0.5); local parts = #Sh.outbox + data(); assert(parts > 1, parts)
        local frames = 0
        while #Sh.outbox > 0 do run(0.5); frames = frames + 1; assert(frames < 2000) end
        now = now + 121
        request('Peer2-Realm')
        assert(#Sh.outbox == parts, 'the text built before is sent at once: ' .. #Sh.outbox)''')

    def test_a_scan_receivers_cannot_take_is_neither_offered_nor_sent(self):
        # V24-a: the limit is what a receiver takes (S.MAX_PARTS), on both sides.
        run(SHARE + '''Sh.MAX_PARTS = 5; addHistory(30, 7); joined(); fullScan(); run(2)
        assert(not sent('!H'), 'not announced')
        request('Peer-Realm'); run(3)
        assert(data() == 0, 'not sent on request')
        local ok, why = Sh.send('GUILD'); assert(not ok and why == 'share_too_large', tostring(why))
        Sh.onMessage(Sh.PREFIX, 'big:1:6:x', 'GUILD', 'Friend-Realm')
        Sh.onMessage(Sh.PREFIX, 'fit:1:5:x', 'GUILD', 'Other-Realm')
        assert(not Sh.inbox['Friend-Realm/big'] and Sh.inbox['Other-Realm/fit'])''')

    def test_requests_are_forgotten_after_their_120_seconds(self):
        # Requests name anyone: what is kept of them stays bounded.
        run(SHARE + '''local scope = F.Engine.scope()
        Sh.onMessage(Sh.PREFIX, '!R|Someone|' .. scope .. '|' .. Sh.enc(now), 'CHANNEL', 'Peer-Realm')
        local old = 'Someone@' .. Sh.dec(Sh.enc(now)); assert(Sh.asked[old])
        now = now + 121
        Sh.onMessage(Sh.PREFIX, '!R|Other|' .. scope .. '|' .. Sh.enc(now), 'CHANNEL', 'Peer-Realm')
        assert(not Sh.asked[old])''')


if __name__ == '__main__':
    unittest.main()
