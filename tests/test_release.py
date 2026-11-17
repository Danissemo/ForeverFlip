"""Release notes select the requested beta; the archive contains the current addon."""

import importlib.util
import pathlib
import tempfile
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent


def tool(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'tools' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ReleaseNotesTests(unittest.TestCase):
    def test_exact_beta_section_precedes_base_version(self):
        notes = tool('release_notes')
        text = '# Changelog\n\n## [Unreleased]\nfuture\n\n## [1.2.0-beta.4] - 2026-11-12\n\n### Fixed\n\n- New scheduler.\n\n## [1.2.0]\nold notes\n'
        result = notes.render(text, '1.2.0-beta.4', 'Danissemo/ForeverFlip')
        self.assertIn('New scheduler.', result)
        self.assertNotIn('old notes', result)
        self.assertNotIn('future', result)
        self.assertIn('/blob/v1.2.0-beta.4/docs/testing.md', result)

    def test_legacy_beta_can_fall_back_to_base_section(self):
        notes = tool('release_notes')
        result = notes.render('## [1.2.0]\n\n- Base notes.\n', '1.2.0-beta.2', 'owner/repo')
        self.assertIn('Base notes.', result)
        self.assertIn('Beta for testing', result)

    def test_unknown_or_empty_release_fails_instead_of_publishing_blank_notes(self):
        notes = tool('release_notes')
        for text in ('## [1.1.0]\nold\n', '## [1.2.0-beta.4]\n\n## [1.2.0]\nold\n'):
            with self.subTest(text=text), self.assertRaises(ValueError):
                notes.render(text, '1.2.0-beta.4', 'owner/repo')

    def test_stable_notes_omit_beta_warning_and_reference_definitions(self):
        result = tool('release_notes').render(
            '## [1.2.0]\n\n- Stable.\n\n[1.2.0]: https://example.test/release\n', '1.2.0', 'owner/repo')
        self.assertEqual(result, '- Stable.\n')


class ReleaseCommandTests(unittest.TestCase):
    """`devflow.py release` turns the Unreleased notes into the version's section."""

    TEXT = ('# Changelog\n\n## [Unreleased]\n\n### Fixed\n\n- A fix.\n\n## [3.0.0] - 2026-11-17\n\nold\n\n'
            '[Unreleased]: ../../compare/v3.0.0...HEAD\n[3.0.0]: ../../compare/v2.3.0-beta.1...v3.0.0\n')

    def test_the_unreleased_notes_become_the_version_and_the_links_follow(self):
        flow = tool('devflow')
        self.assertEqual(flow.unreleased(self.TEXT), '### Fixed\n\n- A fix.')
        text = flow.stamp_changelog(self.TEXT, '3.1.0', '3.0.0', '2026-12-01')
        self.assertEqual(flow.unreleased(text), '')
        self.assertIn('## [Unreleased]\n\n## [3.1.0] - 2026-12-01\n\n### Fixed\n\n- A fix.', text)
        self.assertIn('[Unreleased]: ../../compare/v3.1.0...HEAD\n'
                      '[3.1.0]: ../../compare/v3.0.0...v3.1.0\n[3.0.0]:', text)
        notes = tool('release_notes').render(text, '3.1.0', 'Danissemo/ForeverFlip')
        self.assertEqual(notes, '### Fixed\n\n- A fix.\n')

    def test_versions_are_ordered_with_betas_before_their_release(self):
        key = tool('devflow').version_key
        order = ['3.0.0', '3.1.0-beta.1', '3.1.0-beta.2', '3.1.0-beta.10', '3.1.0', '3.1.1', '4.0.0']
        self.assertEqual(sorted(order, key=key), order)


class PackageTests(unittest.TestCase):
    def test_archive_contains_current_version_and_every_runtime_file(self):
        build = tool('build')
        version, files = build.read_toc()
        build.check_sources(version, files)
        with tempfile.TemporaryDirectory() as folder:
            archive = build.package(version, files, pathlib.Path(folder))
            with zipfile.ZipFile(archive) as package:
                names = set(package.namelist())
                self.assertIn('ForeverFlip/Bindings.xml', names)
                self.assertIn('ForeverFlip/LICENSE', names)
                for name in ['ForeverFlip.toc'] + [f.replace('\\', '/') for f in files]:
                    self.assertEqual(package.read('ForeverFlip/' + name), (ROOT / 'ForeverFlip' / name).read_bytes())
                for name in ('README.md', 'CHANGELOG.md'):
                    self.assertEqual(package.read('ForeverFlip/' + name), (ROOT / name).read_bytes())
                self.assertFalse(any(name.startswith(('tests/', 'tools/')) for name in names))
                self.assertIn(('## Version: ' + version).encode(), package.read('ForeverFlip/ForeverFlip.toc'))
                self.assertIn('ForeverFlip/Media/Logo.tga', names, 'the AddOns list icon is packaged')

    def test_addons_list_shows_it_under_auctions_with_its_icon(self):
        toc = (ROOT / 'ForeverFlip' / 'ForeverFlip.toc').read_text(encoding='utf-8')
        self.assertIn('## Category-enUS: Auctions', toc)
        self.assertIn('## Category-ruRU: Лоты', toc)
        icon = [line for line in toc.splitlines() if line.startswith('## IconTexture:')]
        self.assertEqual(len(icon), 1)
        path = icon[0].split(':', 1)[1].strip().replace('Interface\\AddOns\\', '').replace('\\', '/')
        logo = ROOT / (path + '.tga')
        self.assertTrue(logo.is_file(), logo)
        header = logo.read_bytes()[:18]
        self.assertEqual((header[2], header[12], header[14], header[16]), (2, 64, 64, 32), 'a 64x64 32-bit TGA')
        import sys
        sys.path.insert(0, str(ROOT / 'sync'))
        import ffscan
        self.assertIn('## Category-enUS: Auctions', ffscan.SHARED_TOC)
        self.assertIn('## Group: ForeverFlip', ffscan.SHARED_TOC)


if __name__ == '__main__':
    unittest.main()
