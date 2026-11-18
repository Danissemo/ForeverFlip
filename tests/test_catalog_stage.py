"""tools/catalog_stage.py: the release zip becomes a tagged repository the BigWigs packager can upload."""

import importlib.util
import pathlib
import subprocess
import tempfile
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent


def tool():
    spec = importlib.util.spec_from_file_location('catalog_stage', ROOT / 'tools' / 'catalog_stage.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CatalogStageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = pathlib.Path(self.tmp.name)
        self.zip = self.base / 'ForeverFlip-9.8.7.zip'
        with zipfile.ZipFile(self.zip, 'w') as z:
            z.writestr('ForeverFlip/ForeverFlip.toc', '## Interface: 16001\n## Version: 9.8.7\nCore/Util.lua\n')
            z.writestr('ForeverFlip/Core/Util.lua', 'local F = {}\n')
        self.notes = self.base / 'notes.md'
        self.notes.write_text('### Added\n- Something\n', encoding='utf-8')

    def tearDown(self):
        self.tmp.cleanup()

    def test_the_addon_folder_is_its_own_repository_tagged_with_the_toc_version(self):
        top = tool().stage(self.zip, self.notes, self.base / 'stage')
        self.assertTrue((top / 'ForeverFlip.toc').is_file())
        self.assertTrue((top / 'Core' / 'Util.lua').is_file())
        tag = subprocess.run(['git', 'describe', '--tags'], cwd=top, capture_output=True, text=True, check=True)
        self.assertEqual(tag.stdout.strip(), 'v9.8.7')
        pkgmeta = (top / '.pkgmeta').read_text(encoding='utf-8')
        self.assertIn('package-as: ForeverFlip', pkgmeta)
        self.assertIn('filename: RELEASE_NOTES.md', pkgmeta)
        self.assertEqual((top / 'RELEASE_NOTES.md').read_text(encoding='utf-8'), '### Added\n- Something\n')

    def test_a_zip_without_the_addon_toc_is_refused(self):
        bad = self.base / 'bad.zip'
        with zipfile.ZipFile(bad, 'w') as z:
            z.writestr('Other/Other.toc', '## Version: 1\n')
        with self.assertRaises(SystemExit):
            tool().stage(bad, self.notes, self.base / 'stage')


if __name__ == '__main__':
    unittest.main()
