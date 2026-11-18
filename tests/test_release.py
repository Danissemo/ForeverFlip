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

    def test_the_ci_runs_of_a_commit_say_one_word(self):
        verdict = tool('devflow').ci_verdict
        done = {'status': 'completed', 'conclusion': 'success'}
        self.assertEqual(verdict([]), 'missing')
        self.assertEqual(verdict([done, {'status': 'in_progress', 'conclusion': ''}]), 'running')
        self.assertEqual(verdict([done]), 'success')
        self.assertEqual(verdict([done, {'status': 'completed', 'conclusion': 'failure'}]), 'failure')

    def test_a_failed_ci_log_is_cut_to_what_failed(self):
        # The lines of `gh run view --log-failed` from the Linux run that held back 3.0.0 and 3.1.0.
        log = ('release\tRun tests and package\t2026-11-17T17:19:43.1399276Z FAIL: test_added_installs '
               '(test_sync_profiles.ProfileTests.test_added_installs)\n'
               'release\tRun tests and package\t2026-11-17T17:19:43.1400666Z Traceback (most recent call last):\n'
               'release\tRun tests and package\t2026-11-17T17:19:43.1406365Z   File "/home/runner/tests/'
               'test_sync_profiles.py", line 39, in test_added_installs\n'
               'release\tRun tests and package\t2026-11-17T17:19:43.1408404Z AssertionError: a != b\n'
               'release\tRun tests and package\t2026-11-17T17:19:43.1411972Z FAILED (failures=1, skipped=13)\n'
               'release\tRun tests and package\t2026-11-17T17:19:43.1417289Z #1 completion pending\n')
        lines = tool('devflow').ci_failures(log)
        self.assertEqual(lines[0], 'FAIL: test_added_installs (test_sync_profiles.ProfileTests.test_added_installs)')
        self.assertEqual(len(lines), 4, lines)
        self.assertIn('AssertionError: a != b', lines)

    def test_a_red_ci_stops_the_release_before_the_version_is_written(self):
        # 3.0.0 and 3.1.0 were tagged on commits whose Linux CI had failed, so GitHub published nothing.
        flow = tool('devflow')
        with tempfile.TemporaryDirectory() as folder:
            folder = pathlib.Path(folder)
            flow.TOC, flow.UTIL, flow.CHANGELOG = folder / 'a.toc', folder / 'Util.lua', folder / 'CHANGELOG.md'
            flow.TOC.write_text('## Version: 3.0.0\n', encoding='utf-8')
            flow.UTIL.write_text('F.version = "3.0.0"\n', encoding='utf-8')
            flow.SYNC = folder / 'foreverflip_sync.py'
            flow.SYNC.write_text('VERSION = "3.0.0"\n', encoding='utf-8')
            flow.CHANGELOG.write_text(self.TEXT, encoding='utf-8')
            answers = {('rev-parse', '--abbrev-ref', 'HEAD'): flow.BRANCH, ('rev-parse', 'HEAD'): 'abc1234'}
            flow.git = lambda *args, **_: answers.get(args, '')
            flow.ahead_of_us = lambda: 0
            flow.doc_problems = lambda *_: []
            flow.push = lambda: 0
            waited = []
            flow.wait_for_ci = lambda sha: waited.append(sha) or 'failure'
            self.assertEqual(flow.release('3.1.0', yes=True), 1)
            self.assertEqual(waited, ['abc1234'])
            self.assertEqual(flow.TOC.read_text(encoding='utf-8'), '## Version: 3.0.0\n')
            self.assertEqual(flow.CHANGELOG.read_text(encoding='utf-8'), self.TEXT)

    def test_an_install_keeps_a_copy_of_the_addon_and_the_saved_data_first(self):
        flow = tool('devflow')
        with tempfile.TemporaryDirectory() as folder:
            folder = pathlib.Path(folder)
            game, root = folder / 'game', folder / 'backups'
            target = game / 'Interface' / 'AddOns' / 'ForeverFlip'
            target.mkdir(parents=True)
            (target / 'ForeverFlip.toc').write_text('## Version: 3.0.0\n', encoding='utf-8')
            saved = game / 'WTF' / 'Account' / 'A#1' / 'SavedVariables'
            saved.mkdir(parents=True)
            (saved / 'ForeverFlip.lua').write_text('ForeverFlipData = {}\n', encoding='utf-8')
            (saved / 'Other.lua').write_text('x = 1\n', encoding='utf-8')
            (root / 'by-hand').mkdir(parents=True)
            for i in range(7):
                kept = flow.backup_before_install(game, target, root, stamp=f'2026111{i}-000000')
            self.assertTrue((kept / 'ForeverFlip' / 'ForeverFlip.toc').is_file())
            self.assertTrue((kept / 'SavedVariables' / 'A#1' / 'ForeverFlip.lua').is_file())
            self.assertFalse((kept / 'SavedVariables' / 'A#1' / 'Other.lua').exists(), 'only our files')
            names = sorted(p.name for p in root.iterdir())
            self.assertEqual(len(names), flow.AUTO_KEEP + 1, names)
            self.assertIn('by-hand', names, 'a backup made by hand is never pruned')
            self.assertNotIn(flow.AUTO_BACKUP + '20261110-000000', names, 'the oldest go')
            self.assertIsNone(flow.backup_before_install(folder / 'empty', folder / 'none', root),
                              'a first install has nothing to keep')

    def test_the_guides_name_the_version_in_their_fields_not_only_somewhere(self):
        # The old check asked whether the version was anywhere in README and current-work.md: a
        # sentence about a fix passed while the release link still named an older version.
        flow = tool('devflow')
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            (root / 'docs').mkdir()
            for name in ('README.md', 'docs/testing.md', 'docs/current-work.md'):
                (root / name).write_bytes((ROOT / name).read_bytes())
            readme = root / 'README.md'
            readme.write_text(readme.read_text(encoding='utf-8') + '\nFixed in 9.9.0: the sorting.\n',
                              encoding='utf-8')
            fields = sum(len(p) for p in flow.DOC_FIELDS['stable'].values())
            self.assertEqual(len(flow.doc_problems('9.9.0', root)), fields, 'a mention is not a field')
            cards = flow.doc_versions('checklist', root)
            flow.set_doc_versions('9.9.0', root)
            self.assertEqual(flow.doc_problems('9.9.0', root), [])
            self.assertIn('[9.9.0](https://github.com/Danissemo/ForeverFlip/releases/tag/v9.9.0)',
                          readme.read_text(encoding='utf-8'))
            self.assertEqual(flow.doc_versions('checklist', root), cards, 'the cards keep their version')
            flow.set_doc_versions('10.0.0-beta.1', root)
            self.assertEqual(flow.doc_problems('9.9.0', root), [], 'a beta writes nothing')
            beta = flow.doc_problems('10.0.0-beta.1', root)
            self.assertEqual(len(beta), sum(len(p) for p in flow.DOC_FIELDS['checklist'].values()),
                             'a beta waits for the cards to name it')
            readme.write_text('Current release: 9.9.0\n', encoding='utf-8')
            self.assertEqual(flow.doc_problems('9.9.0', root),
                             ["README.md: 'Current stable release: [': the field is missing"])

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
