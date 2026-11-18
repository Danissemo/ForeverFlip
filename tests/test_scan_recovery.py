"""Full scan: rows waiting for item data are kept per item, read again only once the data arrives,
and the wait runs on while data keeps arriving (Scan.lua, recover)."""

import unittest

from test_addon import SETUP, run

# 3000 lots of an uncached commodity and 400 of another, besides the usual few.
BASE = SETUP + '''local F, S = ForeverFlip, ForeverFlip.Scan
addItem(40, 'Wool Cloth', 33, 'commodity'); addItem(41, 'Silk Cloth', 150, 'commodity')
for i = 1, 3000 do addAuction(40, 100 + i % 7, 20) end
for i = 1, 400 do addAuction(41, 300 + i % 5, 10) end
items[40].cached, items[41].cached = false, false
local reads = 0
local row = F.AH.replicateRow
F.AH.replicateRow = function(i) reads = reads + 1; return row(i) end
local function toRecovery()
    assert(S.start()); fire('REPLICATE_ITEM_LIST_UPDATE')
    while S.job and S.job.state ~= 'recovering' do run(0.05) end
    assert(S.job and S.job.state == 'recovering', 'rows of the two items wait')
end
'''


class RecoveryTests(unittest.TestCase):
    def test_waiting_rows_are_not_read_again_until_their_data_arrives(self):
        run(BASE + '''toRecovery()
        assert(S.job.waitLeft == 3400, tostring(S.job.waitLeft))
        reads = 0
        run(5)
        assert(reads < 50, 'no pass over every waiting row: ' .. reads)
        items[40].cached = true
        run(1)
        local what, done, total = S.progress()
        assert(what == 'scan_recovering' and done == total - 400, 'the count moves at once: ' .. done)
        items[41].cached = true
        while S.busy() do run(0.05) end
        assert(S.last.skipped == 0, 'every row read: ' .. S.last.skipped)
        assert(F.Deals and S.listedUnits('c:40') == 60000 and S.listedUnits('c:41') == 4000)''')

    def test_the_wait_runs_on_while_data_keeps_arriving(self):
        # Wool loads after 20 seconds and silk 25 seconds later: 45 seconds in all, more than the
        # 30 seconds without news after which rows are given up.
        run(BASE + '''toRecovery()
        run(20); items[40].cached = true
        run(25); items[41].cached = true
        while S.busy() do run(0.05) end
        assert(S.last.skipped == 0, 'nothing given up: ' .. S.last.skipped)
        assert(S.listedUnits('c:41') == 4000)''')

    def test_rows_whose_data_never_comes_are_given_up(self):
        run(BASE + '''toRecovery()
        items[40].cached = true
        local start = now
        while S.busy() do run(0.05) end
        assert(now - start < S.RECOVER + 5, 'given up 30 seconds after the last news: ' .. (now - start))
        assert(S.last.skipped == 400 and S.listedUnits('c:40') == 60000)
        assert(S.listedUnits('c:41') == nil, 'the unread item is not known as unlisted')''')


    def test_a_few_rows_left_are_given_up_after_a_short_silence(self):
        # On Retail every scan ended with about 30 rows whose data never came: the progress stood
        # still for the whole S.RECOVER. A few rows left wait S.RECOVER_FEW_IDLE seconds only.
        run(BASE + '''S.RECOVER_FEW = 500
        toRecovery()
        items[40].cached = true
        local start = now
        while S.busy() do run(0.05) end
        assert(now - start < S.RECOVER_FEW_IDLE + 3, 'no 30 second wait: ' .. (now - start))
        assert(S.last.skipped == 400 and S.last.unread[41] and S.listedUnits('c:40') == 60000)
        local found = false
        for _, line in ipairs(ForeverFlip.db.trace) do
            found = found or line:find('scan.unread 400 rows unread', 1, true) and line:find('items 41', 1, true)
        end
        assert(found, 'the unread items are traced')''')

    def test_many_rows_left_keep_the_long_wait(self):
        run(BASE + '''toRecovery()
        items[40].cached = true
        local start = now
        while S.busy() do run(0.05) end
        assert(now - start >= S.RECOVER - 1, '400 rows are more than a few: ' .. (now - start))''')


class MissingItemTests(unittest.TestCase):
    """Rows of items the server does not have are given up at once, not after S.RECOVER."""

    def test_waiting_rows_of_a_failed_item_are_given_up_at_once(self):
        run(BASE + '''toRecovery()
        items[40].cached = true
        fire('ITEM_DATA_LOAD_RESULT', 41, false)
        local start = now
        while S.busy() do run(0.05) end
        assert(now - start < 5, 'no 30 second wait: ' .. (now - start))
        assert(S.last.skipped == 400 and S.listedUnits('c:40') == 60000)
        assert(S.last.unread[41], 'its lots are not taken for sales')
        assert(S.listedUnits('c:41') == nil)''')

    def test_rows_of_an_item_that_failed_before_are_not_held(self):
        run(BASE + '''items[40].cached = true
        fire('ITEM_DATA_LOAD_RESULT', 41, false)
        assert(S.start()); fire('REPLICATE_ITEM_LIST_UPDATE')
        local start = now
        while S.busy() do run(0.05) end
        assert(now - start < 5, 'nothing waited for: ' .. (now - start))
        assert(S.last.skipped == 400 and S.last.unread[41])''')

    def test_an_item_the_game_still_knows_is_waited_for(self):
        # A failed load alone is not trusted when DoesItemExistByID says the item exists.
        run(BASE + '''C_Item.DoesItemExistByID = function() return true end
        toRecovery()
        items[40].cached = true
        fire('ITEM_DATA_LOAD_RESULT', 41, false)
        local start = now
        while S.busy() do run(0.05) end
        assert(now - start >= S.RECOVER - 1, 'the usual wait: ' .. (now - start))''')

    def test_a_later_successful_load_clears_the_mark(self):
        run(BASE + '''fire('ITEM_DATA_LOAD_RESULT', 41, false)
        fire('ITEM_DATA_LOAD_RESULT', 41, true)
        toRecovery()
        items[40].cached = true
        run(5); items[41].cached = true
        while S.busy() do run(0.05) end
        assert(S.last.skipped == 0, 'every row read: ' .. S.last.skipped)''')


class PrefetchTests(unittest.TestCase):
    """While the full scan's answer is awaited, items this house listed before are loaded."""

    def test_known_items_are_asked_for_during_the_wait(self):
        run(SETUP + '''local F, S = ForeverFlip, ForeverFlip.Scan
        addItem(40, 'Wool Cloth', 33, 'commodity'); addItem(41, 'Silk Cloth', 150, 'commodity')
        items[40].cached, items[41].cached = false, true
        local history = F.Data.market(F.db, F.Engine.scope()).history
        history['c:40'], history['c:41'], history['i:42'] = {}, {}, {}
        for id = 1000, 1999 do history['i:' .. id] = {} end
        S.PREFETCH, F.AH.ITEM_IN_FLIGHT = 300, 5000 -- the mock never answers: no cap on unanswered requests
        for k in pairs(requestedItems) do requestedItems[k] = nil end
        assert(S.start())
        run(2)
        assert(S.job and S.job.state == 'waiting', 'still waiting for the answer')
        local asked = {}
        for _, id in ipairs(requestedItems) do asked[id] = (asked[id] or 0) + 1 end
        assert(asked[40] == 1 and asked[42] == 1 and asked[1999] == 1, 'uncached items asked for once')
        assert(not asked[41], 'a cached item is not asked for')
        assert(S.job.prefetched, 'the whole list went in a few frames')''')


class ItemRequestTests(unittest.TestCase):
    """Item data requests follow the game's answers: a batch every 0.1 s while places are free."""

    def test_requests_go_in_batches_up_to_the_unanswered_limit(self):
        run(SETUP + '''local A = ForeverFlip.AH
        local asked = {}
        C_Item.IsItemDataCachedByID = function() return false end
        C_Item.RequestLoadItemDataByID = function(id) asked[#asked + 1] = id end
        A.ITEM_BATCH, A.ITEM_IN_FLIGHT = 100, 250
        for id = 5001, 6000 do A.requestItem(id) end
        A.pump(now); assert(#asked == 100, 'one batch: ' .. #asked)
        A.pump(now + 0.1); A.pump(now + 0.2)
        assert(#asked == 250, 'no more than the unanswered limit: ' .. #asked)
        for i = 1, 50 do A.itemArrived(asked[i]) end
        A.pump(now + 0.3); assert(#asked == 300, 'each answer frees a place: ' .. #asked)
        A.pump(now + 6); assert(#asked == 400, 'unanswered for 5 s, the places are free again: ' .. #asked)''')


if __name__ == "__main__":
    unittest.main()
