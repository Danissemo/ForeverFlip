"""tools/savedata.py: copies of the saved file outside the game, and putting one back."""

import datetime
import importlib.util
import io
import os
import pathlib
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parent.parent


def tool():
    spec = importlib.util.spec_from_file_location('savedata', ROOT / 'tools' / 'savedata.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SaveDataToolTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = pathlib.Path(self.tmp.name)
        self.game, self.backups = base / 'game', base / 'backups'
        self.saved = self.game / 'WTF' / 'Account' / '123#1' / 'SavedVariables'
        self.saved.mkdir(parents=True)
        (self.saved / 'ForeverFlip.lua').write_text('ForeverFlipData = {a=1}', encoding='utf-8')
        (self.saved / 'ForeverFlip.lua.bak').write_text('ForeverFlipData = {a=0}', encoding='utf-8')
        (self.saved / 'Other.lua').write_text('other addon', encoding='utf-8')
        self.env = mock.patch.dict(os.environ, {'FF_BACKUPS': str(self.backups)})
        self.env.start()
        self.sd = tool()

    def tearDown(self):
        self.env.stop()
        self.tmp.cleanup()

    def quiet(self, fn, *args):
        with redirect_stdout(io.StringIO()):
            return fn(*args)

    def test_backup_copies_only_foreverflip_files_of_every_account(self):
        target = self.quiet(self.sd.backup, self.game, 'my label!', datetime.datetime(2026, 11, 17, 14, 5, 9))
        self.assertEqual(target.name, 'savedata-20261117-140509-mylabel')
        names = sorted(p.name for p in target.rglob('*') if p.is_file())
        self.assertEqual(names, ['ForeverFlip.lua', 'ForeverFlip.lua.bak'])
        self.assertTrue((target / 'Account' / '123#1' / 'SavedVariables' / 'ForeverFlip.lua').is_file())
        self.assertEqual([p.name for p in self.sd.copies()], [target.name])

    def test_restore_puts_the_copy_back_and_keeps_what_was_there(self):
        target = self.quiet(self.sd.backup, self.game, '', datetime.datetime(2026, 1, 1))
        (self.saved / 'ForeverFlip.lua').write_text('ForeverFlipData = {a=2}', encoding='utf-8')
        with mock.patch.object(self.sd, 'game_running', return_value=False):
            self.assertEqual(self.quiet(self.sd.restore, self.game, target.name), 0)
        self.assertEqual((self.saved / 'ForeverFlip.lua').read_text(encoding='utf-8'), 'ForeverFlipData = {a=1}')
        before = [p for p in self.sd.copies() if p.name.endswith('-before-restore')]
        self.assertEqual(len(before), 1, 'what was there is copied first')
        kept = before[0] / 'Account' / '123#1' / 'SavedVariables' / 'ForeverFlip.lua'
        self.assertEqual(kept.read_text(encoding='utf-8'), 'ForeverFlipData = {a=2}')

    def test_restore_refuses_while_the_game_runs_or_without_a_copy(self):
        target = self.quiet(self.sd.backup, self.game, '', datetime.datetime(2026, 1, 1))
        (self.saved / 'ForeverFlip.lua').write_text('changed', encoding='utf-8')
        with mock.patch.object(self.sd, 'game_running', return_value=True):
            self.assertEqual(self.quiet(self.sd.restore, self.game, target.name), 1)
        self.assertEqual((self.saved / 'ForeverFlip.lua').read_text(encoding='utf-8'), 'changed')
        with mock.patch.object(self.sd, 'game_running', return_value=False):
            self.assertEqual(self.quiet(self.sd.restore, self.game, 'savedata-none'), 1)


if __name__ == '__main__':
    unittest.main()
