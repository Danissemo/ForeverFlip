"""Helper setup, game discovery and transfer retry behavior; no real network requests."""

import importlib
import pathlib
import sys
import tempfile
import unittest
import urllib.error
import json
from unittest.mock import Mock, patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / 'sync'))
import foreverflip_sync as helper
from test_sync import make_scan, market


class GameLocationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)
        self.location = importlib.import_module('game_location')

    def game(self, parent='Games/World of Warcraft'):
        game = self.root / parent / '_forever_'
        (game / 'Interface/AddOns/ForeverFlip').mkdir(parents=True)
        (game / 'Wow.exe').write_bytes(b'client fixture')
        return game.resolve()

    def test_parent_executable_and_addon_folder_resolve_to_same_client(self):
        game = self.game()
        for value in (game, game.parent, game / 'Wow.exe', game / 'Interface/AddOns/ForeverFlip'):
            with self.subTest(value=value):
                self.assertEqual(self.location.normalize_game(value), game)

    def test_retail_is_not_accepted_just_because_it_has_addons(self):
        game = self.game()
        retail = game.parent / '_retail_'
        (retail / 'Interface/AddOns').mkdir(parents=True)
        (retail / 'Wow.exe').write_bytes(b'retail fixture')
        self.assertIsNone(self.location.normalize_game(retail))

    def test_nonstandard_client_name_requires_forever_product_metadata(self):
        game = self.root / 'My client'
        (game / 'Interface/AddOns').mkdir(parents=True)
        (game / 'Wow.exe').touch()
        self.assertIsNone(self.location.normalize_game(game))
        (game / '.build.info').write_text('Active!DEC:1|Product!STRING:0\n1|wowf\n', encoding='utf-8')
        self.assertEqual(self.location.normalize_game(game), game.resolve())

    def test_renamed_client_can_use_its_parent_installation_metadata(self):
        game = self.root/'Installation'/'Custom client'
        (game/'Interface/AddOns').mkdir(parents=True)
        (game/'Wow.exe').touch()
        (game.parent/'.build.info').write_text('Active!DEC:1|Product!STRING:0\n1|wowf\n', encoding='utf-8')
        self.assertEqual(self.location.normalize_game(game), game.resolve())

    def test_discovery_deduplicates_parent_and_client_paths(self):
        game = self.game()
        self.assertEqual(self.location.discover_games([game.parent, game, game/'Wow.exe']), [game])

    def test_invalid_explicit_path_never_falls_back_to_another_game(self):
        game = self.game()
        with patch.object(self.location, 'discover_games', return_value=[game]):
            with self.assertRaises(self.location.GameNotFound):
                self.location.locate_game(str(self.root/'Missing'))

    def test_multiple_games_require_a_choice(self):
        games = [self.game('One'), self.game('Two')]
        with patch.object(self.location, 'discover_games', return_value=games):
            with self.assertRaises(self.location.AmbiguousGame) as error:
                self.location.locate_game()
        self.assertEqual(error.exception.candidates, games)


class UploadRetryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.game = pathlib.Path(self.tmp.name)
        self.saved = self.game/'ForeverFlip.lua'
        self.saved.write_text('SavedVariables fixture', encoding='utf-8')
        self.scan = make_scan(int(helper.time.time()), market())
        self.hub = Mock()
        self.hub.create_gist.return_value = {'id': 'gist-id'}
        self.hub.create_issue.return_value = {'number': 42}
        self.state = {}

    def upload(self):
        with patch.object(helper, 'saved_variable_files', return_value=[self.saved]), \
             patch.object(helper.ffscan, 'scans_from_saved_variables', return_value=[self.scan]), \
             patch.object(helper, 'log'):
            helper.upload_new_scans(self.game, self.hub, self.state)

    def test_failed_issue_does_not_acknowledge_scan_and_can_retry(self):
        self.hub.create_issue.side_effect = urllib.error.HTTPError('url', 503, 'unavailable', {}, None)
        with self.assertRaises(urllib.error.HTTPError):
            self.upload()
        self.assertEqual(self.state.get('uploaded', []), [])
        self.hub.create_issue.side_effect = None
        self.upload()
        self.assertEqual(self.state['uploaded'], [f'{self.scan.scope}@{self.scan.at}'])
        self.assertEqual(len(self.state['pending']), 1)

    def test_invalid_scan_is_rejected_without_uploaded_acknowledgement(self):
        with patch.object(helper.ffscan, 'check', return_value='bad seal'):
            self.upload()
        self.assertEqual(self.state.get('uploaded', []), [])
        self.hub.create_gist.assert_not_called()

    def test_successful_upload_is_not_sent_again(self):
        self.upload(); self.upload()
        self.assertEqual(self.hub.create_issue.call_count, 1)


class ParserWorkTests(unittest.TestCase):
    def test_reader_does_not_copy_the_remaining_file_for_every_table_key(self):
        class Text(str):
            copied = 0

            def __getitem__(self, key):
                value = super().__getitem__(key)
                if isinstance(key, slice) and key.stop is None:
                    self.copied += len(value)
                return value

        text = Text('Data = {' + ','.join(f'["item{i}"] = {i}' for i in range(1000)) + '}')
        data = helper.ffscan.lua_assignments(text)
        self.assertEqual(data['Data']['item999'], 999)
        self.assertLess(text.copied, len(text)*3, 'parsing keys made quadratic suffix copies')


class SyncSessionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.game = pathlib.Path(self.tmp.name)
        self.saved = self.game/'WTF/Account/test/SavedVariables/ForeverFlip.lua'
        self.saved.parent.mkdir(parents=True)
        self.saved.write_text('first save', encoding='utf-8')
        self.state_path = self.game/'state.json'

    def session(self):
        return helper.SyncSession(self.game, 'owner/repo', {}, self.state_path, None, False)

    def test_failed_sync_is_retried_and_persists_successful_partial_progress(self):
        session = self.session()

        def partial(*args, **kwargs):
            session.state['uploaded'] = ['scope@42']
            raise urllib.error.URLError('offline')

        with patch.object(helper, 'run_once', side_effect=partial):
            with self.assertRaises(urllib.error.URLError):
                session.sync()
        self.assertEqual(json.loads(self.state_path.read_text())['uploaded'], ['scope@42'])
        self.assertTrue(session.due(now=session.retry_at+1), 'failed file changes are not acknowledged')

    def test_save_during_transfer_is_detected_on_the_next_pass(self):
        session = self.session()

        def changed(*args, **kwargs):
            self.saved.write_text('a newer save during transfer', encoding='utf-8')
            return 0

        with patch.object(helper, 'run_once', side_effect=changed):
            session.sync()
        self.assertTrue(session.due(), 'the new save has not been processed yet')

    def test_unchanged_successful_save_does_not_trigger_another_sync(self):
        session = self.session()
        with patch.object(helper, 'run_once', return_value=0) as sync:
            session.sync()
        self.assertFalse(session.due())
        self.assertEqual(sync.call_count, 1)

    def test_upload_failure_still_allows_community_prices_to_download(self):
        with patch.object(helper, 'follow_uploads'), \
             patch.object(helper, 'upload_new_scans', side_effect=urllib.error.URLError('offline')), \
             patch.object(helper, 'download_shared', return_value=3) as download, \
             patch.object(helper, 'log'):
            with self.assertRaises(helper.SyncError):
                helper.run_once(self.game, 'owner/repo', {}, 'fake-token', True)
        download.assert_called_once()

    def test_signing_in_refreshes_credentials_and_makes_existing_files_eligible(self):
        session = self.session()
        session.upload = True
        session.last_seen = session.fingerprint()
        session.state['warned'] = True
        with patch.object(helper, 'find_token', return_value='new-test-credential'):
            session.refresh_credentials({}, force=True)
        self.assertEqual(session.token, 'new-test-credential')
        self.assertEqual(session.last_seen, {})
        self.assertNotIn('warned', session.state)

    def test_console_once_respects_saved_sharing_off(self):
        (self.game/'config.json').write_text('{"upload":false}', encoding='utf-8')
        with patch.object(helper, 'config_dir', return_value=self.game), \
             patch.object(helper, 'find_game', return_value=self.game), \
             patch.object(helper, 'find_token') as token, \
             patch.object(helper, 'SyncSession') as session, patch.object(helper, 'log'):
            self.assertEqual(helper.main(['--once']), 0)
        self.assertFalse(session.call_args.args[-1])
        token.assert_not_called()



class DescribeFailureTests(unittest.TestCase):
    def test_missing_file_is_named(self):
        import errno
        error = FileNotFoundError(errno.ENOENT, 'No such file or directory', r'C:\x\policy.pem')
        self.assertEqual(helper.describe(error), r'No such file or directory: C:\x\policy.pem')

    def test_network_and_http_failures_read_plainly(self):
        self.assertIn('no connection to GitHub', helper.describe(urllib.error.URLError('timed out')))
        http = urllib.error.HTTPError('u', 404, 'Not Found', {}, None)
        self.assertEqual(helper.describe(http), 'GitHub answered 404 Not Found')
        self.assertEqual(helper.describe(ValueError()), 'ValueError')

    def test_download_failure_names_the_missing_file(self):
        import errno
        missing = FileNotFoundError(errno.ENOENT, 'No such file or directory', 'policy.pem')
        with patch.object(helper, 'download_shared', side_effect=missing):
            with self.assertRaises(helper.SyncError) as caught:
                helper.run_once(pathlib.Path('.'), 'o/r', {}, None, False)
        self.assertIn('policy.pem', str(caught.exception))


if __name__ == '__main__':
    unittest.main()
