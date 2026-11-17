"""Scans the Sync helper shared: dropped at login and told on the Sharing page (Raw.prune, UI.refreshShare)."""

import random
import sys
import unittest
from pathlib import Path

from test_addon import SETUP, run, runtime

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'sync'))
from ffscan import _hash  # noqa: E402

BASE = SETUP + '''local F, R, UI = ForeverFlip, ForeverFlip.Raw, ForeverFlip.UI
F.db.settings.rawScans = true
local scope = F.Engine.scope()
ForeverFlipRaw = { format = R.FORMAT, scans = {
    { scope = scope, at = 3000, count = 1, rows = 'x' },
    { scope = scope, at = 2000, count = 1, rows = 'x' },
    { scope = scope, at = 1000, count = 1, rows = 'x' },
} }
'''


class SealTests(unittest.TestCase):
    def test_the_line_hash_is_the_helpers_byte_by_byte_hash(self):
        """R.hash takes four bytes a step (a third of the reading time was hashing byte by byte):
        the helper and the data repository must still get the same seal."""
        hash_ = runtime().eval('ForeverFlip.Raw.hash')
        rnd = random.Random(3)
        texts = ['', 'a', 'ab', 'abc', 'abcd', 'abcde', '2589,20,123456,100,0,3,0,c,', 'é' * 7]
        texts += [''.join(chr(rnd.randint(32, 126)) for _ in range(rnd.randint(0, 90))) for _ in range(500)]
        for text in texts:
            self.assertEqual(hash_(text), _hash(text.encode('utf-8')), text)


class SharedScanTests(unittest.TestCase):
    def test_shared_scans_are_dropped_at_login(self):
        run(BASE + '''ForeverFlipShared = { generated = now, uploaded = { [scope .. '@2000'] = true, [scope .. '@1000'] = true } }
        assert(R.prune() == 2)
        assert(#R.saved() == 1 and R.saved()[1].at == 3000, 'only the scan not shared yet is kept')''')

    def test_the_sharing_page_tells_what_the_helper_shared(self):
        run(BASE + '''ForeverFlipShared = { generated = now, scans = {}, uploaded = { [scope .. '@2000'] = true } }
        R.prune()
        local count, newest = R.sharedSummary()
        assert(count == 1 and newest == 2000)
        UI.show('settings:share'); UI.refreshShare()
        local text = UI.shareStatus
        assert(text:find('Shared by the helper: 1 of your scans', 1, true), text)
        assert(text:find('Full scans waiting for the helper: 2', 1, true), text)
        ForeverFlipShared.uploaded[scope .. '@3000'] = true; ForeverFlipShared.uploaded[scope .. '@1000'] = true
        R.prune(); UI.refreshShare()
        assert(UI.shareStatus:find('all are shared', 1, true), UI.shareStatus)''')


if __name__ == "__main__":
    unittest.main()
