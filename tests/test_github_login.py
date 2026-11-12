"""Signing in to GitHub from the Sync helper (device flow) and keeping the token."""

import json
import os
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / 'sync'))
import foreverflip_sync as helper  # noqa: E402
import github_login  # noqa: E402


class Clock:
    """A fake clock: sleeping moves it on."""

    def __init__(self):
        self.now = 0.0

    def sleep(self, seconds):
        self.now += seconds

    def __call__(self):
        return self.now


def answers(*replies):
    """Fake GitHub token endpoint: one reply per poll, recorded."""
    calls = []
    replies = list(replies)

    def post(url, fields, agent):
        calls.append((url, fields))
        return replies.pop(0)
    return post, calls


DEVICE = {'device_code': 'dev', 'user_code': 'ABCD-1234', 'verification_uri': 'https://github.com/login/device',
          'interval': 5, 'expires_in': 900}


class DeviceFlowTests(unittest.TestCase):
    def wait(self, *replies, cancelled=lambda: False):
        clock = Clock()
        post, calls = answers(*replies)
        with patch.object(github_login, '_post', side_effect=post):
            token = github_login.wait_for_token('client', DEVICE, cancelled=cancelled, sleep=clock.sleep, clock=clock)
        return token, calls, clock

    def test_waits_for_approval_and_returns_the_token(self):
        token, calls, clock = self.wait({'error': 'authorization_pending'}, {'access_token': 'gho_x'})
        self.assertEqual(token, 'gho_x')
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[0][1]['grant_type'], 'urn:ietf:params:oauth:grant-type:device_code')
        self.assertAlmostEqual(clock.now, 10, delta=0.01, msg='polls at the interval GitHub gave')

    def test_slow_down_lengthens_the_interval(self):
        _, _, clock = self.wait({'error': 'slow_down', 'interval': 10}, {'access_token': 'gho_x'})
        self.assertAlmostEqual(clock.now, 15, delta=0.01)

    def test_declined_expired_and_cancelled_sign_ins_say_why(self):
        with self.assertRaisesRegex(github_login.LoginError, 'not approved'):
            self.wait({'error': 'access_denied'})
        with self.assertRaisesRegex(github_login.LoginError, 'expired'):
            self.wait({'error': 'expired_token'})
        with self.assertRaisesRegex(github_login.LoginError, 'cancelled'):
            self.wait(cancelled=lambda: True)

    def test_the_code_runs_out(self):
        clock = Clock()
        device = dict(DEVICE, expires_in=12)
        with patch.object(github_login, '_post', return_value={'error': 'authorization_pending'}):
            with self.assertRaisesRegex(github_login.LoginError, 'expired'):
                github_login.wait_for_token('client', device, sleep=clock.sleep, clock=clock)

    def test_start_asks_for_the_upload_scopes(self):
        post, calls = answers(dict(DEVICE))
        with patch.object(github_login, '_post', side_effect=post):
            device = github_login.start('client')
        self.assertEqual(device['user_code'], 'ABCD-1234')
        self.assertEqual(calls[0][1], {'client_id': 'client', 'scope': 'gist public_repo'})
        with self.assertRaisesRegex(github_login.LoginError, 'not set up'):
            github_login.start('')

    def test_client_id_from_the_config_wins(self):
        self.assertEqual(github_login.client_id({'client_id': ' Iv1.abc '}), 'Iv1.abc')


class TokenStorageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.folder = pathlib.Path(self.tmp.name)

    def test_token_is_kept_encrypted_and_forgotten(self):
        github_login.save_token(self.folder, 'gho_secret_value')
        raw = (self.folder / github_login.TOKEN_FILE).read_bytes()
        if os.name == 'nt':
            self.assertNotIn(b'gho_secret_value', raw, 'kept encrypted with DPAPI')
        self.assertEqual(github_login.load_token(self.folder), 'gho_secret_value')
        github_login.forget(self.folder)
        self.assertIsNone(github_login.load_token(self.folder))
        github_login.forget(self.folder)  # forgetting twice is fine

    def test_a_damaged_file_reads_as_signed_out(self):
        (self.folder / github_login.TOKEN_FILE).write_bytes(b'DPAPI1' + b'\x00garbage')
        self.assertIsNone(github_login.load_token(self.folder))

    def test_the_helpers_sign_in_comes_before_config_and_cli(self):
        github_login.save_token(self.folder, 'from-helper')
        env = {k: v for k, v in os.environ.items() if k != 'FF_GITHUB_TOKEN'}
        with patch.object(helper, 'config_dir', return_value=self.folder), patch.dict(os.environ, env, clear=True), \
             patch.object(helper.subprocess, 'run') as cli:
            self.assertEqual(helper.token_source({'token': 'from-config'}), ('from-helper', 'helper'))
            github_login.forget(self.folder)
            self.assertEqual(helper.token_source({'token': 'from-config'}), ('from-config', 'config'))
            cli.return_value.returncode, cli.return_value.stdout = 0, 'from-cli\n'
            self.assertEqual(helper.token_source({}), ('from-cli', 'gh'))
        with patch.dict(os.environ, {'FF_GITHUB_TOKEN': 'from-env'}):
            self.assertEqual(helper.token_source({}), ('from-env', 'environment'))


class ConsoleLoginTests(unittest.TestCase):
    def test_login_and_logout_from_the_console(self):
        with tempfile.TemporaryDirectory() as folder:
            folder = pathlib.Path(folder)
            (folder / 'config.json').write_text(json.dumps({'client_id': 'client'}), encoding='utf-8')
            lines = []
            with patch.object(helper, 'config_dir', return_value=folder), \
                 patch.object(helper, 'log', side_effect=lines.append), \
                 patch.object(github_login, 'start', return_value=dict(DEVICE)), \
                 patch.object(github_login, 'wait_for_token', return_value='gho_new'), \
                 patch.object(github_login, 'whoami', return_value='Danissemo'):
                self.assertEqual(helper.main(['--login']), 0)
                self.assertEqual(github_login.load_token(folder), 'gho_new')
                self.assertTrue(any('ABCD-1234' in line for line in lines))
                self.assertTrue(any('Danissemo' in line for line in lines))
                self.assertEqual(helper.main(['--logout']), 0)
                self.assertIsNone(github_login.load_token(folder))

    def test_without_a_sign_in_sharing_is_not_attempted(self):
        lines = []
        with patch.object(helper, 'upload_new_scans') as upload, patch.object(helper, 'download_shared', return_value=0), \
             patch.object(helper, 'log', side_effect=lines.append):
            state = {}
            helper.run_once(pathlib.Path('.'), 'o/r', state, None, True)
        upload.assert_not_called()
        self.assertTrue(any('Sign in with GitHub' in line for line in lines))



class WindowTests(unittest.TestCase):
    def setUp(self):
        try:
            import tkinter
            self.root = tkinter.Tk()
        except Exception as error:  # no display
            self.skipTest(f'Tk is not available: {error}')
        self.root.withdraw()
        self.addCleanup(self.root.destroy)
        import argparse
        import sync_gui
        self.gui = sync_gui
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        args = argparse.Namespace(paused=True, download_only=False, upload=False, game=None, repo=None)
        with patch.object(sync_gui.SyncWindow, 'discover'), patch.object(sync_gui.SyncWindow, 'check_account'):
            self.window = sync_gui.SyncWindow(self.root, args, {'client_id': 'client'}, pathlib.Path(self.tmp.name),
                                              helper)
        self.window.set_busy(False)

    def pump(self):
        with patch.object(self.root, 'after'):
            self.window.poll()

    def test_sharing_needs_a_sign_in(self):
        w = self.window
        self.assertTrue(w.share_button.instate(['disabled']))
        self.assertEqual(w.login_button.cget('text'), 'Sign in with GitHub')
        w.events.put(('account', ('Danissemo', 'helper')))
        self.pump()
        self.assertFalse(w.share_button.instate(['disabled']))
        self.assertEqual(w.login_button.cget('text'), 'Sign out')
        self.assertIn('Danissemo', w.account_text.get())
        w.events.put(('account', ('Danissemo', 'gh')))
        self.pump()
        self.assertIn('GitHub CLI', w.account_text.get())
        self.assertFalse(w.login_button.instate(['disabled']), 'the app sign-in can replace the CLI one')
        self.assertEqual(w.login_button.cget('text'), 'Sign in with GitHub')

    def test_the_code_is_shown_copied_and_signing_in_turns_sharing_on(self):
        w = self.window
        w.login_running = True
        with patch.object(self.gui.webbrowser, 'open') as browser, patch.object(helper, 'save_json'):
            w.events.put(('login_code', dict(DEVICE)))
            self.pump()
            browser.assert_called_once_with('https://github.com/login/device')
            self.assertEqual(w.code_text.get(), 'ABCD-1234')
            self.assertTrue(w.code_box.winfo_manager(), 'the code is shown')
            self.assertEqual(self.root.clipboard_get(), 'ABCD-1234')
            self.assertEqual(w.login_button.cget('text'), 'Cancel')
            w.events.put(('signed_in', 'Danissemo'))
            self.pump()
        self.assertTrue(w.share.get())
        self.assertEqual(w.account, ('Danissemo', 'helper'))

    def test_signing_out_forgets_the_token(self):
        w = self.window
        github_login.save_token(pathlib.Path(self.tmp.name), 'gho_x')
        w.account = ('Danissemo', 'helper')
        with patch.object(self.gui.SyncWindow, 'check_account'), patch.object(helper, 'log'):
            w.sign_in_or_out()
        self.assertIsNone(github_login.load_token(pathlib.Path(self.tmp.name)))
        self.assertIsNone(w.account)
        self.assertTrue(w.share_button.instate(['disabled']))


if __name__ == '__main__':
    unittest.main()
