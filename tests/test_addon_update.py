"""Addon updates from GitHub releases in the Sync helper, with an opt-in beta channel."""

import hashlib
import io
import pathlib
import sys
import tempfile
import unittest
import zipfile
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / 'sync'))
import addon_update as au  # noqa: E402
import foreverflip_sync as helper  # noqa: E402


def package(version, files=None, toc_version=None):
    files = files if files is not None else {'Core.lua': '-- core', 'UI.lua': '-- ui'}
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, 'w') as zf:
        zf.writestr('ForeverFlip/ForeverFlip.toc', f'## Title: ForeverFlip\n## Version: {toc_version or version}\n')
        for name, text in files.items():
            zf.writestr(name if '/' in name else f'ForeverFlip/{name}', text)
    return buffer.getvalue()


def release(version, prerelease=None, draft=False, asset=True, data=None):
    data = data or package(version)
    assets = [{'name': f'ForeverFlip-{version}.zip', 'size': len(data),
               'digest': 'sha256:' + hashlib.sha256(data).hexdigest(),
               'browser_download_url': f'https://github.com/o/r/releases/download/v{version}/ForeverFlip-{version}.zip'},
              {'name': 'ForeverFlipSync.exe', 'size': 1}] if asset else []
    return {'tag_name': f'v{version}', 'prerelease': '-' in version if prerelease is None else prerelease,
            'draft': draft, 'assets': assets, 'html_url': f'https://github.com/o/r/releases/tag/v{version}'}


RELEASES = [release('1.2.0-beta.4'), release('1.2.0-beta.3'), release('1.1.0'), release('1.0.0'),
            release('1.3.0', draft=True), release('1.2.5', asset=False)]


class VersionTests(unittest.TestCase):
    def test_betas_sort_before_their_release(self):
        order = ['1.1.0', '1.2.0-alpha.1', '1.2.0-beta.3', '1.2.0-beta.10', '1.2.0-rc.1', '1.2.0', '1.2.1-beta.1']
        self.assertEqual(sorted(order, key=au.parse_version), order)
        self.assertIsNone(au.parse_version('banana'))
        self.assertTrue(au.is_beta('1.2.0-beta.4'))
        self.assertFalse(au.is_beta('1.2.0'))

    def test_stable_players_get_only_releases(self):
        self.assertEqual(au.newer('1.0.0', RELEASES, beta=False)['version'], '1.1.0')
        self.assertIsNone(au.newer('1.1.0', RELEASES, beta=False))

    def test_beta_testers_get_pre_releases(self):
        best = au.newer('1.1.0', RELEASES, beta=True)
        self.assertEqual(best['version'], '1.2.0-beta.4')
        self.assertTrue(best['beta'])
        self.assertEqual(len(best['sha256']), 64)

    def test_drafts_and_releases_without_the_zip_are_skipped(self):
        versions = [c['version'] for c in au.candidates(RELEASES, beta=True)]
        self.assertNotIn('1.3.0', versions)
        self.assertNotIn('1.2.5', versions)

    def test_leaving_the_beta_never_downgrades(self):
        self.assertIsNone(au.newer('1.2.0-beta.4', RELEASES, beta=False))
        later = RELEASES + [release('1.2.0')]
        self.assertEqual(au.newer('1.2.0-beta.4', later, beta=False)['version'], '1.2.0')

    def test_nothing_installed_gets_the_newest(self):
        self.assertEqual(au.newer(None, RELEASES, beta=False)['version'], '1.1.0')


class PackageTests(unittest.TestCase):
    def test_missing_toc_runtime_file_is_refused(self):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w') as zf:
            zf.writestr('ForeverFlip/ForeverFlip.toc', '## Version: 1.2.0\nCore.lua\n')
        with self.assertRaisesRegex(au.UpdateError, 'Core.lua'):
            au.check_package(buffer.getvalue(), '1.2.0')

    def test_duplicate_case_insensitive_members_are_refused(self):
        data = package('1.2.0', {'Core.lua': 'one', 'core.lua': 'two'})
        with self.assertRaisesRegex(au.UpdateError, 'duplicate'):
            au.check_package(data, '1.2.0')

    def test_a_good_package_passes(self):
        archive = au.check_package(package('1.2.0'), '1.2.0')
        self.assertIn('ForeverFlip/Core.lua', archive.namelist())

    def test_bad_packages_are_refused(self):
        cases = {
            'unexpected file': package('1.2.0', {'../evil.lua': 'x'}),
            'unexpected': package('1.2.0', {'Other/evil.lua': 'x'}),
            'TOC says': package('1.2.0', toc_version='1.1.0'),
            'not a zip': b'not a zip at all',
        }
        for reason, data in cases.items():
            with self.assertRaisesRegex(au.UpdateError, reason):
                au.check_package(data, '1.2.0')

    def test_download_must_match_the_published_sha256(self):
        r = au.candidates([release('1.2.0')], beta=False)[0]

        class Response:
            def __init__(self, body):
                self.body = body

            def read(self, n=-1):
                return self.body

            def __enter__(self):
                return self

            def __exit__(self, *a):
                return False

        with patch.object(au.urllib.request, 'urlopen', return_value=Response(package('1.2.0'))):
            self.assertEqual(au.download(r, 'test'), package('1.2.0'))
        with patch.object(au.urllib.request, 'urlopen', return_value=Response(b'tampered')):
            with self.assertRaisesRegex(au.UpdateError, 'SHA-256'):
                au.download(r, 'test')
        with self.assertRaisesRegex(au.UpdateError, 'not on GitHub'):
            au.download(dict(r, url='https://evil.example/x.zip'), 'test')


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = pathlib.Path(self.tmp.name)
        self.game, self.backups = root / '_forever_', root / 'backups'
        self.addon = self.game / 'Interface' / 'AddOns' / 'ForeverFlip'
        self.addon.mkdir(parents=True)
        (self.addon / 'ForeverFlip.toc').write_text('## Version: 1.1.0\n', encoding='utf-8')
        (self.addon / 'Core.lua').write_text('-- old core', encoding='utf-8')
        (self.addon / 'UI.lua').write_text('-- old ui', encoding='utf-8')

    def install(self, version, files=None):
        r = au.candidates([release(version, data=package(version, files))], beta=True)[0]
        with patch.object(au, 'download', return_value=package(version, files)):
            return au.install(self.game, r, self.backups, 'test')

    def test_install_replaces_the_folder_and_keeps_a_backup(self):
        result = self.install('1.2.0')
        self.assertEqual(result, {'version': '1.2.0', 'previous': '1.1.0', 'restart': False})
        self.assertEqual(au.installed_version(self.game), '1.2.0')
        self.assertEqual((self.addon / 'Core.lua').read_text(), '-- core')
        backups = list(self.backups.glob('ForeverFlip-1.1.0-*.zip'))
        self.assertEqual(len(backups), 1)
        with zipfile.ZipFile(backups[0]) as zf:
            self.assertEqual(zf.read('ForeverFlip/Core.lua').decode(), '-- old core')
        self.assertEqual(sorted(p.name for p in self.addon.parent.iterdir()), ['ForeverFlip'], 'no leftovers')

    def test_added_or_removed_files_need_a_restart(self):
        self.assertTrue(self.install('1.2.0', {'Core.lua': 'x', 'UI.lua': 'y', 'New.lua': 'z'})['restart'])

    def test_a_failed_swap_puts_the_old_version_back(self):
        real = pathlib.Path.rename

        def rename(path, target):
            if path.name == 'ForeverFlip' and path.parent.name == '.ForeverFlip-update':
                raise OSError('locked')
            return real(path, target)

        with patch.object(pathlib.Path, 'rename', rename):
            with self.assertRaises(OSError):
                self.install('1.2.0')
        self.assertEqual(au.installed_version(self.game), '1.1.0')
        self.assertEqual((self.addon / 'Core.lua').read_text(), '-- old core')

    def test_only_the_last_two_backups_are_kept(self):
        for version in ['1.2.0', '1.2.1', '1.2.2']:
            self.install(version)
        self.assertEqual(len(list(self.backups.glob('*.zip'))), 2)

    def test_a_development_copy_is_never_replaced(self):
        (self.addon / '.git').mkdir()
        self.assertTrue(au.is_development_copy(self.game))
        with patch.object(helper, 'config_dir', return_value=pathlib.Path(self.tmp.name)):
            with self.assertRaisesRegex(au.UpdateError, 'development copy'):
                helper.update_addon(self.game, {'version': '1.2.0'})


class HelperPassTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.game = pathlib.Path(self.tmp.name) / '_forever_'
        addon = self.game / 'Interface' / 'AddOns' / 'ForeverFlip'
        addon.mkdir(parents=True)
        (addon / 'ForeverFlip.toc').write_text('## Version: 1.1.0\n', encoding='utf-8')

    def run_pass(self, config, install=None):
        lines = []
        with patch.object(au, 'fetch_releases', return_value=RELEASES), \
             patch.object(helper, 'update_addon', return_value={'version': 'x', 'restart': False}) as update, \
             patch.object(helper, 'log', side_effect=lines.append):
            status = helper.addon_pass(self.game, config, install=install)
        return status, update, lines

    def test_automatic_updates_install_and_notify_only_announces(self):
        status, update, _ = self.run_pass({'beta': True})
        update.assert_called_once()
        self.assertEqual(status['installed'], '1.2.0-beta.4')
        status, update, lines = self.run_pass({'beta': True, 'update_addon': False})
        update.assert_not_called()
        self.assertTrue(any('1.2.0-beta.4 (beta) is available' in line for line in lines))

    def test_console_beta_switch_is_remembered(self):
        with tempfile.TemporaryDirectory() as folder:
            folder = pathlib.Path(folder)
            with patch.object(helper, 'config_dir', return_value=folder), \
                 patch.object(helper, 'find_game', return_value=self.game), \
                 patch.object(au, 'fetch_releases', return_value=RELEASES), \
                 patch.object(helper, 'update_addon', return_value={'version': '1.2.0-beta.4', 'restart': True}) as update, \
                 patch.object(helper, 'log'):
                self.assertEqual(helper.main(['--update-addon', '--beta']), 0)
                self.assertTrue(helper.load_json(folder / 'config.json', {})['beta'])
                update.assert_called_once()
                self.assertEqual(helper.main(['--update-addon', '--no-beta']), 0)
                self.assertFalse(helper.load_json(folder / 'config.json', {})['beta'])
                self.assertEqual(update.call_count, 1, 'without the beta, 1.1.0 is already the newest')


class WindowTests(unittest.TestCase):
    def setUp(self):
        try:
            import tkinter
            self.root = tkinter.Tk()
        except Exception as error:
            self.skipTest(f'Tk is not available: {error}')
        self.root.withdraw()
        self.addCleanup(self.root.destroy)
        import argparse
        import sync_gui
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        args = argparse.Namespace(paused=True, download_only=False, upload=False, game=None, repo=None)
        with patch.object(sync_gui.SyncWindow, 'discover'), patch.object(sync_gui.SyncWindow, 'check_account'):
            self.window = sync_gui.SyncWindow(self.root, args, {}, pathlib.Path(self.tmp.name), helper)

    def test_the_addon_line_tells_the_state(self):
        w = self.window
        w.show_addon({'installed': '1.1.0', 'release': au.candidates([release('1.2.0')], False)[0]})
        self.assertIn('1.2.0 available', w.addon_text.get())
        self.assertFalse(w.update_button.instate(['disabled']))
        w.show_addon({'installed': '1.2.0-beta.4', 'release': None})
        self.assertIn('1.2.0-beta.4 (beta) — up to date', w.addon_text.get())
        self.assertTrue(w.update_button.instate(['disabled']))
        w.show_addon({'installed': '1.2.0', 'release': None, 'result': {'restart': True}})
        self.assertIn('restart the game', w.addon_text.get())

    def test_switching_the_beta_on_looks_again_at_once(self):
        w = self.window
        w.next_update = 10 ** 12
        w.beta.set(True)
        with patch.object(helper, 'save_json') as save:
            w.addon_options_changed()
        self.assertTrue(save.call_args.args[1]['beta'])
        self.assertEqual(w.next_update, 0.0)


if __name__ == '__main__':
    unittest.main()
