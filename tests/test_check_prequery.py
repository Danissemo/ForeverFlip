"""Check all on a deal page asks for the lowest price of every item in one query first: deals whose
item nobody sells any more, or whose lowest price leaves no profit, are settled without the exact
searches the server never answers."""

import unittest

from test_addon import SETUP, run

BASE = SETUP + r'''enableBrowse()
local F, D = ForeverFlip, ForeverFlip.Deals
F.db.settings.autoVerify = false
fullScan()
local keys = {}
for _, d in ipairs(D.list) do keys[#keys + 1] = d.key end
assert(#keys >= 2, 'the scan finds deals: ' .. #keys)
local function count(name)
    local n = 0
    for _, c in ipairs(calls) do if c[1] == name then n = n + 1 end end
    return n
end
'''


class PreQueryTests(unittest.TestCase):
    def test_a_deal_nobody_sells_any_more_is_settled_by_the_first_query(self):
        run(BASE + r'''local gone = F.Util.parseKey(keys[1]).id
        for i = #auctions, 1, -1 do
            if auctions[i].item == gone then table.remove(auctions, i) end
        end
        local before = count('SendSearchQuery') + count('SendSellSearchQuery')
        assert(D.startBatch(F.Engine.scope(), keys, true) == #keys)
        assert(count('SearchForItemKeys') == 1 and D.preFlight(), 'one query for every item first')
        browseAnswer()
        run(1)
        assert(not D.preFlight(), 'answered')
        assert(not D.get(keys[1]), 'the deal nobody sells is gone without a search of its own')
        local same = 0
        for _, k in ipairs(keys) do if F.Util.parseKey(k).id == gone then same = same + 1 end end
        assert(D.batch.settled == same and #keys > same, tostring(D.batch.settled))
        run(60)
        assert(not D.batch.active, 'the rest checked')
        assert(D.lastBatch and D.lastBatch.total == #keys and D.lastBatch.settled == same)''')

    def test_without_an_answer_every_item_gets_its_search(self):
        run(BASE + r'''D.startBatch(F.Engine.scope(), keys, true)
        assert(D.preFlight())
        run(D.PRE_WAIT + 1)
        assert(not D.preFlight() and (D.batch.settled or 0) == 0, 'nothing settled without an answer')
        run(60)
        assert(not D.batch.active)''')


if __name__ == '__main__':
    unittest.main()
