"""tools/promo.py: release posts drafted from the changelog and the public numbers read offline."""

import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent

CHANGELOG = '''# Changelog

## [Unreleased]

## [9.0.0] - 2026-01-01

### Added

- **A new page.** It does things.
- **Another thing**, described.

### Fixed

- **Bug one is gone.** Details.

### Development

- **Not for players.** Hidden.

[9.0.0]: https://example.invalid
'''


def tool():
    spec = importlib.util.spec_from_file_location('promo', ROOT / 'tools' / 'promo.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PromoToolTests(unittest.TestCase):
    def setUp(self):
        self.promo = tool()

    def test_the_headlines_of_added_and_fixed_are_taken_and_development_is_left_out(self):
        news = self.promo.headlines(self.promo.render(CHANGELOG, '9.0.0', 'o/r'))
        self.assertEqual(news, {'Added': ['A new page', 'Another thing'], 'Fixed': ['Bug one is gone']})

    def test_every_channel_links_the_release_and_names_the_news(self):
        for channel in self.promo.CHANNELS:
            text = self.promo.post(CHANGELOG, '9.0.0', channel, 'o/r')
            self.assertIn('https://github.com/o/r/releases/tag/v9.0.0', text, channel)
            self.assertIn('A new page', text, channel)
            self.assertNotIn('Not for players', text, channel)
        with self.assertRaises(ValueError):
            self.promo.post(CHANGELOG, '9.0.0', 'fax', 'o/r')

    def test_the_discord_draft_counts_one_fix_in_the_singular(self):
        self.assertIn('…and 1 fix.', self.promo.post(CHANGELOG, '9.0.0', 'discord', 'o/r'))

    def test_downloads_count_every_asset_and_skip_drafts(self):
        releases = [{'tag_name': 'v2', 'assets': [{'download_count': 3}, {'download_count': 4}]},
                    {'tag_name': 'v1', 'draft': True, 'assets': [{'download_count': 9}]}]
        self.assertEqual(self.promo.downloads(releases), [('v2', 7)])

    def test_houses_read_the_sharing_players_from_status_json(self):
        status = {'markets': {'B-Horde': {'uploaders': 3, 'published': 12}, 'A-Alliance': {}}}
        self.assertEqual(self.promo.houses(status), [('A-Alliance', 0, 0), ('B-Horde', 3, 12)])


if __name__ == '__main__':
    unittest.main()
