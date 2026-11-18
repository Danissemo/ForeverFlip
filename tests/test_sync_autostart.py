"""Starting ForeverFlip Sync with Windows: the Run entry, the switch and starting hidden in the tray.
The real registry is never touched: winreg is replaced by a dictionary."""

import argparse
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / 'sync'))
import autostart  # noqa: E402
import foreverflip_sync as helper  # noqa: E402


class FakeRegistry:
    """The few winreg calls autostart makes, over {key: {name: value}}."""
    HKEY_CURRENT_USER, KEY_SET_VALUE, REG_SZ = 'HKCU', 2, 1

    def __init__(self):
        self.keys = {}

    class Key:
        def __init__(self, values):
            self.values = values

        def __enter__(self):
            return self

        def __exit__(self, *_):
            return False

    def OpenKey(self, root, path, *_):
        if path not in self.keys:
            raise FileNotFoundError(path)
        return self.Key(self.keys[path])

    def CreateKey(self, root, path):
        return self.Key(self.keys.setdefault(path, {}))

    def QueryValueEx(self, key, name):
        if name not in key.values:
            raise FileNotFoundError(name)
        return key.values[name], self.REG_SZ

    def SetValueEx(self, key, name, _reserved, _kind, value):
        key.values[name] = value

    def DeleteValue(self, key, name):
        if name not in key.values:
            raise FileNotFoundError(name)
        del key.values[name]


class AutostartTests(unittest.TestCase):
    def setUp(self):
        self.reg = FakeRegistry()
        # available() is patched, not os.name: with os.name 'nt' pathlib builds WindowsPath on Linux
        for p in (patch.object(autostart, 'winreg', self.reg), patch.object(autostart, 'available', return_value=True)):
            p.start()
            self.addCleanup(p.stop)

    def test_the_entry_is_the_setting(self):
        self.assertFalse(autostart.enabled())
        autostart.enable()
        self.assertTrue(autostart.enabled())
        self.assertTrue(autostart.current().endswith('--tray'))
        autostart.disable()
        autostart.disable()  # already off: nothing to do
        self.assertFalse(autostart.enabled())

    def test_the_command_starts_the_packaged_helper_or_the_script_without_a_console(self):
        packaged = pathlib.Path(tempfile.gettempdir()) / 'Program Files' / 'ForeverFlipSync.exe'
        exe = autostart.command(executable=packaged)
        self.assertEqual(exe, f'"{packaged.resolve()}" --tray')  # quoted: the path has a space
        script = autostart.command()
        self.assertIn('foreverflip_sync.py', script)
        self.assertTrue(script.endswith('--tray'))

    def test_only_the_packaged_helper_moves_the_entry_to_itself(self):
        autostart.enable('"C:\\old\\ForeverFlipSync.exe" --tray')
        self.assertFalse(autostart.refresh(), 'a run from the sources leaves it alone')
        with patch.object(autostart.sys, 'frozen', True, create=True), \
                patch.object(autostart.sys, 'executable', r'C:\new\ForeverFlipSync.exe'):
            self.assertTrue(autostart.refresh())
            self.assertIn('new', autostart.current())
            self.assertFalse(autostart.refresh(), 'already this copy')

    def test_the_tray_argument_is_known(self):
        self.assertTrue(helper.arguments(['--tray']).tray)


class AutostartWindowTests(unittest.TestCase):
    def setUp(self):
        try:
            import tkinter
            self.root = tkinter.Tk()
        except Exception as error:  # no display
            self.skipTest(f'Tk is not available: {error}')
        self.root.withdraw()
        self.addCleanup(lambda: self.root.winfo_exists() and self.root.destroy())
        import sync_gui
        self.gui = sync_gui
        self.reg = FakeRegistry()
        for p in (patch.object(autostart, 'winreg', self.reg), patch.object(autostart, 'available', return_value=True),
                  patch.object(sync_gui.tray, 'available', return_value=True)):
            p.start()
            self.addCleanup(p.stop)
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def window(self, config, **extra):
        args = argparse.Namespace(paused=True, download_only=False, upload=False, game=None, repo=None, **extra)
        with patch.object(self.gui.SyncWindow, 'discover'), patch.object(self.gui.SyncWindow, 'check_account'), \
                patch.object(self.gui.tray.Tray, 'show', return_value=True):
            w = self.gui.SyncWindow(self.root, args, config, pathlib.Path(self.tmp.name), helper)
        w.tray.show = lambda notice=None: True
        w.tray.hide = lambda: None
        return w

    def test_the_switch_writes_the_entry_and_keeps_the_tray_on(self):
        w = self.window({'tray': False})
        self.assertFalse(w.autostart_on.get())
        w.autostart_button.toggle()
        self.assertTrue(autostart.enabled())
        self.assertTrue(w.tray_on.get(), 'a start at sign-in lives in the tray')
        w.tray_button.toggle()  # the tray off: no start with Windows into an open window
        self.assertFalse(autostart.enabled())
        self.assertFalse(w.autostart_on.get())

    def test_the_switch_shows_what_windows_will_run(self):
        autostart.enable()
        self.assertTrue(self.window({'tray': True}).autostart_on.get())

    def test_started_by_windows_only_the_tray_icon_shows(self):
        self.root.deiconify()
        w = self.window({'tray': True}, tray=True)
        self.root.update_idletasks()
        self.assertEqual(self.root.state(), 'withdrawn')
        self.assertIsNotNone(w)


if __name__ == '__main__':
    unittest.main()
