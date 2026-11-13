"""Scans the Sync helper shared: dropped at login and told on the Sharing page (Raw.prune, UI.refreshShare)."""

import unittest

from test_addon import SETUP, run

BASE = SETUP + '''local F, R, UI = ForeverFlip, ForeverFlip.Raw, ForeverFlip.UI
F.db.settings.rawScans = true
local scope = F.Engine.scope()
ForeverFlipRaw = { format = R.FORMAT, scans = {
    { scope = scope, at = 3000, count = 1, rows = 'x' },
    { scope = scope, at = 2000, count = 1, rows = 'x' },
    { scope = scope, at = 1000, count = 1, rows = 'x' },
} }
'''


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
        local text = UI.shareText:GetText()
        assert(text:find('Shared by the helper: 1 of your scans', 1, true), text)
        assert(text:find('Full scans waiting for the helper: 2', 1, true), text)
        ForeverFlipShared.uploaded[scope .. '@3000'] = true; ForeverFlipShared.uploaded[scope .. '@1000'] = true
        R.prune(); UI.refreshShare()
        assert(UI.shareText:GetText():find('all are shared', 1, true), UI.shareText:GetText())''')


if __name__ == "__main__":
    unittest.main()
