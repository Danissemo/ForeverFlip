"""T06/T08: the Full scan button is pressable only when a press would send the scan.

It used to be enabled whenever the 15-minute cooldown was over, and a press while the server was
busy (throttled) or a purchase was in flight only printed an error."""

import unittest

from test_addon import run

BASE = '''local F=ForeverFlip;local UI=F.UI
F.db.settings.autoScan=false;F.db.settings.sniper=false
addItem(2589,'Linen Cloth',100,'commodity')
addAuction(2589,900,5)
F.db.lastScan=nil
'''


class ScanButtonStateTests(unittest.TestCase):
    def test_ready_server_and_no_cooldown_enable_it(self):
        run(BASE + '''UI.refresh()
        assert(F.Scan.canStart(), 'nothing stands in the way')
        assert(UI.scanButton:IsEnabled(), 'so it is pressable')''')

    def test_a_busy_server_greys_it_out_without_spending_the_stuck_allowance(self):
        run(BASE + '''throttleReady=false
        local forced=F.AH.forced or 0
        UI.refresh()
        local ok, why=F.Scan.canStart()
        assert(not ok and why=='throttled', tostring(why))
        assert(not UI.scanButton:IsEnabled(), 'a press would only fail')
        assert((F.AH.forced or 0)==forced, 'painting the button sends nothing')
        throttleReady=true
        UI.refresh()
        assert(UI.scanButton:IsEnabled(), 'it comes back once the server is ready')''')

    def test_the_cooldown_greys_it_out_and_shows_the_time(self):
        run(BASE + '''assert(F.Scan.start())
        F.Scan.stop(); UI.refresh()
        local ok, why=F.Scan.canStart()
        assert(not ok and why=='cooldown', tostring(why))
        assert(not UI.scanButton:IsEnabled())
        assert(UI.scanButton:GetText():find('Full scan in'), UI.scanButton:GetText())''')


if __name__ == '__main__':
    unittest.main()
