"""A Check all must not end the full scan the player is waiting for.

The bulk button read Stop whenever Deals.busy() was true, and a running full scan makes it true,
so pressing it during the six minutes of a scan cancelled the scan instead of checking the page."""

import unittest

from test_addon import run

BASE = '''local F=ForeverFlip;local D=F.Deals
F.db.settings.autoScan=false;F.db.settings.sniper=false
addItem(2589,'Linen Cloth',100,'commodity')
for i=1,3 do addAuction(2589,900,5) end
'''


class CheckDuringScanTests(unittest.TestCase):
    def test_the_button_keeps_its_name_through_a_scan(self):
        run(BASE + '''local UI=F.UI
        assert(F.Scan.start(),'the scan runs')
        assert(D.busy(),'a scan counts as busy for everything else')
        UI.refresh()
        assert(UI.bulkButton:GetText()=='Check all','a scan is not a check to stop')
        ''')

    def test_pressing_it_during_a_scan_leaves_the_scan_running(self):
        run(BASE + '''local UI=F.UI
        assert(F.Scan.start())
        UI.refresh()
        UI.bulkButton:Click()
        assert(F.Scan.job,'the scan the player waited for is still running')
        assert(not D.stoppingWork(),'and nothing of the button own work was running')
        ''')

    def test_the_scan_is_still_stopped_by_its_own_control(self):
        run(BASE + '''assert(F.Scan.start())
        F.Scan.stop()
        assert(not F.Scan.job,'the scan has its own Stop')''')

    def test_a_running_batch_still_reads_stop(self):
        run(BASE + '''local UI=F.UI
        UI.show('deals:all')
        D.startBatch('deals:all',{'c:2589'},false)
        UI.refresh()
        assert(UI.bulkButton:GetText()=='Stop','a running batch is a check to stop')
        UI.bulkButton:Click()
        assert(not select(3,D.batchProgress()),'Stop ends the batch')
        assert(UI.bulkButton:GetText()=='Check all')
        ''')


if __name__ == '__main__':
    unittest.main()


class ScanStopControlTests(unittest.TestCase):
    """A running scan is stopped from its own button, which reads Stop scan while it runs."""

    def test_the_scan_button_stops_a_running_scan(self):
        run(BASE + '''local UI=F.UI
        assert(F.Scan.start())
        UI.refresh()
        assert(UI.scanButton:GetText()=='Stop scan','the scan offers its own stop')
        assert(UI.scanButton:IsEnabled(),'and it is pressable')
        UI.scanButton:Click()
        assert(not F.Scan.job,'the scan stops from its own button')
        UI.refresh()
        assert(UI.scanButton:GetText()~='Stop scan','back to starting a scan')
        ''')

    def test_nothing_else_reads_stop_during_a_scan(self):
        run(BASE + '''local UI=F.UI
        assert(F.Scan.start())
        UI.refresh()
        assert(UI.bulkButton:GetText()=='Check all','Check all is not a stop for the scan')
        ''')
