"""ForeverFlip Sync: several game installations as profiles, and the beta channel chosen from the
installed build when the player never chose one (T09, T15)."""

import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / 'sync'))
import addon_update  # noqa: E402
import foreverflip_sync as helper  # noqa: E402
import profiles  # noqa: E402


class ProfileTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)

    def test_an_old_single_game_becomes_the_first_profile_and_keeps_its_state(self):
        config = {'game': r'C:\World of Warcraft\_forever_', 'beta': True}
        self.assertTrue(profiles.migrate(config))
        self.assertEqual(config['installs'], [{'id': 'main', 'game': r'C:\World of Warcraft\_forever_'}])
        self.assertEqual(config['active'], 'main')
        self.assertTrue(config['beta'], 'other settings stay')
        self.assertFalse(profiles.migrate(config), 'a second run changes nothing')
        install = profiles.active_install(config)
        self.assertEqual(profiles.state_path(self.root, install), self.root / 'state.json',
                         'the first profile keeps the state.json of the single-install helper')
        self.assertEqual(profiles.migrate({}), False)

    def test_added_installs_have_their_own_files_and_the_last_cannot_be_removed(self):
        config = {'game': r'C:\A\_forever_'}
        second = profiles.add_install(config, r'D:\Games\WoW\_forever_')
        self.assertEqual(config['active'], second['id'])
        self.assertEqual(config['game'], r'D:\Games\WoW\_forever_', 'game follows the active profile')
        self.assertNotEqual(second['id'], 'main')
        self.assertEqual(profiles.add_install(config, 'd:\\games\\wow\\_forever_\\', activate=False), second,
                         'the same folder is not added twice')
        self.assertEqual(len(config['installs']), 2)
        path = profiles.state_path(self.root, second)
        self.assertEqual(path, self.root / 'profiles' / second['id'] / 'state.json')
        self.assertTrue(path.parent.is_dir())
        self.assertEqual(profiles.backups_folder(self.root, second).parent, path.parent)
        self.assertTrue(profiles.remove_install(config, second['id']))
        self.assertEqual(config['active'], 'main')
        self.assertEqual(config['game'], r'C:\A\_forever_')
        self.assertFalse(profiles.remove_install(config, 'main'), 'the last one stays')
        self.assertEqual(len(config['installs']), 1)

    def test_client_facts_are_read_from_build_info(self):
        game = self.root / 'World of Warcraft' / '_forever_'
        game.mkdir(parents=True)
        (game.parent / '.build.info').write_text(
            'Branch!STRING:0|Active!DEC:1|Version!STRING:0|Product!STRING:0\n'
            'eu|1|1.15.0.1|wow_classic_era\n'
            'eu|1|1.60.1.70938|wowf\n', encoding='utf-8')
        info = profiles.client_info(game)
        self.assertEqual(info, {'flavor': '_forever_', 'version': '1.60.1.70938', 'product': 'wowf'})
        self.assertIn('1.60.1.70938', profiles.describe({'id': 'main', 'game': str(game)}))
        self.assertEqual(profiles.client_info(self.root / 'nothing')['version'], None)


class BetaChannelTests(unittest.TestCase):
    def test_an_installed_beta_chooses_the_beta_channel_until_the_player_chooses(self):
        self.assertEqual(addon_update.channel({}, '2.3.0-beta.1'), (True, True))
        self.assertEqual(addon_update.channel({}, '2.2.0'), (False, False))
        self.assertEqual(addon_update.channel({}, None), (False, False))
        self.assertEqual(addon_update.channel({'beta': False}, '2.3.0-beta.1'), (True, True),
                         'a saved False was the old default, not a choice')
        self.assertEqual(addon_update.channel({'beta': False, 'beta_by_user': True}, '2.3.0-beta.1'), (False, False))
        self.assertEqual(addon_update.channel({'beta': True}, '2.2.0'), (True, False))
        self.assertEqual(addon_update.channel({'beta': True, 'beta_by_user': False}, '2.3.0-beta.1'), (True, False))

    def test_the_automatic_choice_is_stored_as_not_the_players(self):
        config = {}
        self.assertTrue(helper.apply_beta_choice(config, {'beta_auto': True}))
        self.assertEqual(config, {'beta': True, 'beta_by_user': False})
        self.assertFalse(helper.apply_beta_choice(config, {'beta_auto': True}))
        self.assertFalse(helper.apply_beta_choice({}, {'beta_auto': False}))

    def test_check_addon_reads_the_toc_and_offers_betas(self):
        with tempfile.TemporaryDirectory() as tmp:
            game = pathlib.Path(tmp)
            folder = addon_update.addon_folder(game)
            folder.mkdir(parents=True)
            (folder / 'ForeverFlip.toc').write_text('## Interface: 16001\n## Version: 2.3.0-beta.1\n', encoding='utf-8')
            releases = [{'tag_name': 'v2.3.0-beta.2', 'prerelease': True,
                         'assets': [{'name': 'ForeverFlip-2.3.0-beta.2.zip', 'browser_download_url': 'https://github.com/x'}]}]
            original = addon_update.fetch_releases
            addon_update.fetch_releases = lambda *a, **k: releases
            try:
                status = helper.check_addon(game, {})
                chosen = helper.check_addon(game, {'beta': False, 'beta_by_user': True})
            finally:
                addon_update.fetch_releases = original
        self.assertEqual(status['installed'], '2.3.0-beta.1')
        self.assertTrue(status['beta'] and status['beta_auto'])
        self.assertEqual(status['release']['version'], '2.3.0-beta.2')
        self.assertIsNone(chosen['release'], 'the player chose stable releases')
        self.assertFalse(chosen['beta_auto'])


if __name__ == '__main__':
    unittest.main()
