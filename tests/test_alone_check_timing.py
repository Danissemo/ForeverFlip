"""T10: "Check all" on My auctions when 30 listed items have no other seller. WoW Forever never answers
a search of such an item, so how long the batch takes depended only on how old the last full scan
was (Scan.notListed, Deals.onlyYours / ALONE_AGE, FAST_WAIT, the batch's retry).

Measured with this file, 30 items:
  scan age     before                         after
  0 s          0 s, 0 searches                0 s, 0 searches
  30 min       180 s, 30 searches             0 s, 0 searches (answered from the scan, marked)
  3 h          360 s, 60 searches, 30 failed  180 s, 30 searches, 30 failed (no second try)
"""

import unittest

from test_addon import SETUP, runtime

N = 30
CODE = SETUP + '''local F, D, T = ForeverFlip, ForeverFlip.Deals, ForeverFlip.Trade
F.db.settings.autoVerify = false
local keys, owned = {}, {}
for i = 1, %(n)d do addItem(1000 + i, 'Thing ' .. i, 10, 'item'); addAuction(1000 + i, 500, 1, 'Me') end
fullScan()
for i = 1, %(n)d do
    keys[i] = 'i:' .. (1000 + i)
    owned[i] = { auctionID = 500 + i, id = 1000 + i, key = keys[i], qty = 1, price = 500 }
end
T.owned = owned
F.Scan.last.at = now - %(age)d
local sent = 0
F.AH.search = function() sent = sent + 1 end -- the server never answers
F.AH.searchKey = function() sent = sent + 1 end
local start = now
D.startBatch('%(scope)s', keys, false)
while D.batch and D.batch.active and now - start < 3000 do run(1) end
local status, _, asOf = T.ownedStatus(owned[1])
return now - start, sent, D.batch.failed, D.FAST_WAIT, status, asOf and (now - asOf) or false
'''


def measure(age, scope='auctions'):
    return runtime().execute(CODE % {'n': N, 'age': age, 'scope': scope})


class AloneCheckAllTiming(unittest.TestCase):
    def test_fresh_scan_answers_without_searching(self):
        seconds, sent, failed, _, status, _ = measure(0)
        self.assertEqual((sent, failed, status), (0, 0, 'alone'))
        self.assertLess(seconds, 2)

    def test_scan_within_two_hours_answers_from_the_scan_and_says_so(self):
        seconds, sent, failed, _, status, age = measure(30 * 60)
        # Before: 180 s, one search each (FAST_WAIT 5 s plus a second of pacing).
        self.assertEqual((sent, failed, status), (0, 0, 'alone'))
        self.assertLess(seconds, 2)
        self.assertGreaterEqual(age, 30 * 60)  # "only yours as of the scan 30 min ago"

    def test_undercuts_page_still_searches_every_item(self):
        seconds, sent, failed, fast, _, _ = measure(30 * 60, 'undercuts')
        self.assertEqual((sent, failed), (N, 0))
        self.assertLessEqual(seconds, N * (fast + 1) + 5)

    def test_older_scan_reports_every_item_unanswered_once_without_a_second_try(self):
        seconds, sent, failed, fast, status, _ = measure(3 * 3600)
        # Before: 360 s, 60 searches (the batch sent the unanswered ones once more), all 30 failed.
        self.assertEqual((sent, failed), (N, N))
        self.assertNotEqual(status, 'cheapest')  # silence is never "cheapest"
        self.assertLessEqual(seconds, N * (fast + 1) + 5)

    def test_search_button_sends_a_real_search_and_finds_a_new_undercut(self):
        lua = runtime()
        out = lua.execute(SETUP + '''local F, D, T, UI = ForeverFlip, ForeverFlip.Deals, ForeverFlip.Trade, ForeverFlip.UI
        addItem(1001, 'Thing', 10, 'item'); addAuction(1001, 500, 1, 'Me')
        fullScan()
        local a = { auctionID = 77, id = 1001, key = 'i:1001', qty = 1, price = 500 }
        T.owned = { a }
        F.Scan.last.at = now - 1800
        D.startBatch('auctions', { 'i:1001' }, false)
        local first = T.ownedStatus(a)
        addAuction(1001, 400, 1, 'Rival') -- listed after the scan
        UI.show('auctions'); UI.ownedSelected = 77; UI.refreshAuctions()
        UI.searchOwned:Click()
        for i = 1, 20 do run(1); if D.search and not D.search.waitKey then answer() end end
        local status, cheapest = T.ownedStatus(a)
        return first, status, cheapest''')
        self.assertEqual(out, ('alone', 'undercut', 400))


if __name__ == "__main__":
    unittest.main()
