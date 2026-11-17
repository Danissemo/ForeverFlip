"""ForeverFlip Sync updating itself: the running build is found by its SHA-256, only a newer build
of the chosen channel is offered, and a download is installed only when it matches the SHA-256
GitHub published. The network is faked."""

import hashlib
import io
import pathlib
import sys
import tempfile
import unittest
import urllib.error

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / 'sync'))
import addon_update  # noqa: E402
import foreverflip_sync as helper  # noqa: E402
import self_update  # noqa: E402

OLD, NEW, BETA = b'old build', b'new build' * 1000, b'beta build'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def release(version, data, prerelease=False, digest=True):
    asset = {'name': 'ForeverFlipSync.exe', 'size': len(data),
             'browser_download_url': f'https://github.com/o/r/releases/download/v{version}/ForeverFlipSync.exe'}
    if digest:
        asset['digest'] = 'sha256:' + sha(data)
    return {'tag_name': f'v{version}', 'prerelease': prerelease, 'assets': [asset]}


RELEASES = [release('2.4.0-beta.1', BETA, prerelease=True), release('2.3.0', NEW), release('2.2.0', OLD)]


class Answer(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()


class CheckTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.exe = pathlib.Path(self.tmp.name) / 'ForeverFlipSync.exe'
        self.exe.write_bytes(OLD)

    def test_the_running_build_is_known_by_its_sha256_not_by_the_constant(self):
        status = self_update.check(RELEASES, False, '9.9.9', self.exe)
        self.assertEqual(status['current'], '2.2.0')
        self.assertEqual(status['release']['version'], '2.3.0')
        self.assertTrue(status['frozen'])
        self.assertEqual(self_update.check(RELEASES, True, '9.9.9', self.exe)['release']['version'], '2.4.0-beta.1')

    def test_the_newest_build_is_not_offered_again(self):
        self.exe.write_bytes(NEW)
        self.assertIsNone(self_update.check(RELEASES, False, '1.0.0', self.exe)['release'])

    def test_a_source_run_uses_the_constant_and_is_not_replaced(self):
        status = self_update.check(RELEASES, False, '2.3.0', None)
        self.assertEqual(status, {'current': '2.3.0', 'release': None, 'frozen': False})

    def test_check_helper_follows_the_beta_choice(self):
        fetch = lambda repo, agent: RELEASES  # noqa: E731
        self.assertEqual(helper.check_helper({}, fetch=fetch, exe=self.exe)['release']['version'], '2.3.0')
        self.assertEqual(helper.check_helper({'beta': True}, fetch=fetch, exe=self.exe)['release']['version'],
                         '2.4.0-beta.1')
        self.assertFalse(helper.check_helper({}, fetch=fetch, exe=False)['frozen'])


class DownloadTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.folder = pathlib.Path(self.tmp.name)
        self.exe = self.folder / 'ForeverFlipSync.exe'
        self.exe.write_bytes(OLD)
        self.new = self_update.newer(RELEASES, False, '2.2.0')

    def opener(self, data):
        self.requests = []

        def open_(req, timeout=None):
            self.requests.append(req)
            return Answer(data)
        return open_

    def leftovers(self):
        return sorted(p.name for p in self.folder.iterdir())

    def test_a_matching_download_replaces_the_build_and_keeps_the_old_one_until_restart(self):
        seen = []
        result = self_update.update(self.new, self.exe, 'test', opener=self.opener(NEW),
                                    progress=lambda done, total: seen.append((done, total)))
        self.assertEqual(result, {'version': '2.3.0', 'restart': True})
        self.assertEqual(self.exe.read_bytes(), NEW)
        self.assertEqual(self.leftovers(), ['ForeverFlipSync.exe', 'ForeverFlipSync.exe.old'])
        self.assertEqual(seen[-1], (len(NEW), len(NEW)))
        self.assertEqual(self.requests[0].get_header('User-agent'), 'test')
        self_update.cleanup(self.exe)
        self.assertEqual(self.leftovers(), ['ForeverFlipSync.exe'])

    def test_a_download_that_does_not_match_is_refused_and_leaves_nothing(self):
        with self.assertRaisesRegex(addon_update.UpdateError, 'SHA-256'):
            self_update.update(self.new, self.exe, 'test', opener=self.opener(b'tampered'))
        self.assertEqual(self.exe.read_bytes(), OLD)
        self.assertEqual(self.leftovers(), ['ForeverFlipSync.exe'])

    def test_without_a_published_sha256_nothing_is_downloaded(self):
        unsigned = addon_update.candidates([release('2.3.0', NEW, digest=False)], False,
                                           asset_name=lambda v: self_update.ASSET)[0]
        with self.assertRaisesRegex(addon_update.UpdateError, 'no SHA-256'):
            self_update.update(unsigned, self.exe, 'test', opener=self.opener(NEW))
        self.assertEqual(self.requests, [])

    def test_only_github_is_trusted(self):
        elsewhere = dict(self.new, url='https://example.com/ForeverFlipSync.exe')
        with self.assertRaises(addon_update.UpdateError):
            self_update.download(elsewhere, self.folder / 'x', 'test', opener=self.opener(NEW))

    def test_cancel_stops_the_download_and_keeps_the_build(self):
        with self.assertRaises(self_update.Cancelled):
            self_update.update(self.new, self.exe, 'test', opener=self.opener(NEW), cancelled=lambda: True)
        self.assertEqual(self.exe.read_bytes(), OLD)
        self.assertEqual(self.leftovers(), ['ForeverFlipSync.exe'])

    def test_a_network_error_keeps_the_build(self):
        def offline(req, timeout=None):
            raise urllib.error.URLError('no route')
        with self.assertRaises(urllib.error.URLError):
            self_update.update(self.new, self.exe, 'test', opener=offline)
        self.assertEqual(self.exe.read_bytes(), OLD)
        self.assertEqual(self.leftovers(), ['ForeverFlipSync.exe'])

    def test_a_failed_swap_puts_the_running_build_back(self):
        missing = self.folder / 'ForeverFlipSync.exe.new'  # never written: the second rename fails
        with self.assertRaises(OSError):
            self_update.install(self.exe, missing)
        self.assertEqual(self.exe.read_bytes(), OLD)
        self.assertEqual(self.leftovers(), ['ForeverFlipSync.exe'])


if __name__ == '__main__':
    unittest.main()
