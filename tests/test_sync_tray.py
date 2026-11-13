"""ForeverFlip Sync window: the turning status ring, closing into the tray, the tray's menu and
layouts that are not repeated for nothing."""

import argparse
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / 'sync'))
import foreverflip_sync as helper  # noqa: E402


def alive(root):
    try:
        return bool(root.winfo_exists())
    except Exception:  # the application has been destroyed
        return False


class TrayWindowTests(unittest.TestCase):
    def setUp(self):
        try:
            import tkinter
            self.root = tkinter.Tk()
        except Exception as error:  # no display
            self.skipTest(f'Tk is not available: {error}')
        self.root.withdraw()
        self.addCleanup(lambda: alive(self.root) and self.root.destroy())
        import sync_gui
        self.gui = sync_gui
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        args = argparse.Namespace(paused=True, download_only=False, upload=False, game=None, repo=None)
        with patch.object(sync_gui.SyncWindow, 'discover'), patch.object(sync_gui.SyncWindow, 'check_account'):
            self.window = sync_gui.SyncWindow(self.root, args, {'tray': True}, pathlib.Path(self.tmp.name), helper)
        self.window.set_busy(False)
        # No real notification-area icon in tests.
        self.shown = []
        self.window.tray.show = lambda notice=None: self.shown.append(notice)
        self.window.tray.hide = lambda: self.shown.append('hidden')

    def pump(self):
        with patch.object(self.root, 'after'):
            self.window.poll()

    def test_the_status_ring_turns_while_busy(self):
        w = self.window
        with patch.object(self.root, 'winfo_viewable', return_value=True), patch.object(self.root, 'after'):
            w.set_busy(True)
            first = float(w.bg.itemcget('spinner', 'start'))
            w.spin()
            w.spin()
            self.assertNotEqual(float(w.bg.itemcget('spinner', 'start')), first, 'the arc moved')
            w.set_busy(False)
            w.tone('ok')
            w.spin()
            self.assertFalse(w.spinning, 'it stops once the work is done')
            self.assertEqual(w.bg.find_withtag('spinner'), ())

    def test_closing_hides_into_the_tray_and_its_menu_opens_or_quits(self):
        w = self.window
        if not self.gui.tray.available():
            self.skipTest('pystray or Pillow is not installed')
        w.close()
        self.assertTrue(alive(self.root), 'the helper keeps running')
        self.assertEqual(self.root.state(), 'withdrawn')
        self.assertTrue(self.shown and 'keeps syncing' in self.shown[0])
        w.events.put(('tray', 'open'))
        self.pump()
        self.assertEqual(self.root.state(), 'normal')
        self.assertIn('hidden', self.shown)
        w.events.put(('tray', 'quit'))
        self.pump()
        self.assertFalse(alive(self.root), 'Quit from the tray closes for good')

    def test_without_the_option_closing_ends_the_helper(self):
        w = self.window
        w.tray_on.set(False)
        w.close()
        self.assertFalse(alive(self.root))

    def test_the_tray_option_is_saved(self):
        w = self.window
        w.tray_on.set(False)
        w.tray_changed()
        self.assertFalse(helper.load_json(pathlib.Path(self.tmp.name) / 'config.json', {})['tray'])

    def test_a_burst_of_resizes_lays_the_window_out_once(self):
        w = self.window
        with patch.object(self.root, 'after_idle') as idle:
            w.request_layout()
            w.request_layout()
            w.request_layout()
        self.assertEqual(idle.call_count, 1)
        w.layout_now()
        drawn = []
        with patch.object(w, 'draw_background', side_effect=lambda *a: drawn.append(a)):
            w.layout()
        self.assertEqual(drawn, [], 'the same size draws no backdrop again')


if __name__ == '__main__':
    unittest.main()
