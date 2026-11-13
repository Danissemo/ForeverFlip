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
