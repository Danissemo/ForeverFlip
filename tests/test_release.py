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
                for name in ['ForeverFlip.toc'] + files:
                    self.assertEqual(package.read('ForeverFlip/' + name), (ROOT / 'ForeverFlip' / name).read_bytes())
                self.assertFalse(any(name.startswith(('tests/', 'tools/')) for name in names))
                self.assertIn(('## Version: ' + version).encode(), package.read('ForeverFlip/ForeverFlip.toc'))


if __name__ == '__main__':
    unittest.main()
