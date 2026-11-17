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
        self.window.tray.show = lambda notice=None: self.shown.append(notice) or True
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

    def test_without_an_icon_the_window_is_not_hidden(self):
        w = self.window
        w.tray.show = lambda notice=None: False
        with patch.object(self.gui.tray, 'available', return_value=True):
            w.close()
        self.assertFalse(alive(self.root), 'it closes instead of hiding with nothing to bring it back')


class TrayOptionTests(unittest.TestCase):
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

    def window(self, config):
        args = argparse.Namespace(paused=True, download_only=False, upload=False, game=None, repo=None)
        with patch.object(self.gui.SyncWindow, 'discover'), patch.object(self.gui.SyncWindow, 'check_account'):
            return self.gui.SyncWindow(self.root, args, config, pathlib.Path(self.tmp.name), helper)

    def test_the_tray_is_on_for_a_new_config_and_a_saved_off_is_kept(self):
        self.assertTrue(self.window({}).tray_on.get())
        self.assertFalse(self.window({'tray': False}).tray_on.get())

    def test_the_tray_image_is_a_file_of_the_kit(self):
        self.assertTrue(any(path.is_file() for path in self.gui.tray_icons()))
        self.assertTrue(self.gui.tray_icons()[0].is_file(), 'app-icon.ico is shipped with the helper')


class FakePystray:
    """Enough of pystray to see the icon made and run; nothing reaches the notification area."""

    def __init__(self):
        self.icons = []
        fake = self

        class Menu:
            SEPARATOR = object()

            def __init__(self, *items):
                self.items = items

        class Icon:
            def __init__(self, name, image, title, menu):
                self.name, self.image, self.title, self.menu = name, image, title, menu
                self.visible, self.notices, self.stopped = False, [], False
                fake.icons.append(self)

            def run(self, setup=None):
                setup(self)

            def notify(self, text, title):
                self.notices.append(text)

            def stop(self):
                self.stopped = True

        self.Menu, self.Icon = Menu, Icon
        self.MenuItem = lambda text, action, default=False: (text, action)


class FakeImage:
    opened = []

    @classmethod
    def open(cls, path):
        if not pathlib.Path(path).is_file():
            raise OSError(path)
        cls.opened.append(pathlib.Path(path))
        return type('Picture', (), {'load': lambda self: None})()

    @staticmethod
    def new(mode, size, color):
        return ('square', color)


class TrayIconTests(unittest.TestCase):
    def setUp(self):
        import tray
        self.tray = tray
        self.fake = FakePystray()
        FakeImage.opened = []
        patcher = patch.multiple(tray, pystray=self.fake, Image=FakeImage)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.sent = []

    def wait(self, icon):
        import threading
        for thread in threading.enumerate():
            if thread.name == 'tray':
                thread.join(2)

    def test_the_icon_is_created_with_the_kit_image_and_its_menu_reaches_the_window(self):
        import sync_gui
        t = self.tray.Tray([pathlib.Path('missing.png'), *sync_gui.tray_icons()], self.sent.append)
        self.assertTrue(t.show('still running'))
        self.wait(t)
        self.assertEqual(len(self.fake.icons), 1)
        icon = self.fake.icons[0]
        self.assertTrue(icon.visible)
        self.assertEqual(icon.notices, ['still running'])
        self.assertEqual(FakeImage.opened, [sync_gui.tray_icons()[0]], 'the first file that opens')
        self.assertTrue(t.show('again'), 'shown once')
        self.assertEqual(len(self.fake.icons), 1)
        for text, action in icon.menu.items[:2]:
            action()
        self.assertEqual(self.sent, ['open', 'sync'])
        t.hide()
        self.assertTrue(icon.stopped)

    def test_a_backend_failure_reports_no_icon(self):
        def broken(*args, **kwargs):
            raise RuntimeError('no notification area')
        self.fake.Icon = broken
        t = self.tray.Tray(pathlib.Path('missing.png'), self.sent.append)
        self.assertFalse(t.show())
        self.assertIsNone(t.icon)


if __name__ == '__main__':
    unittest.main()
