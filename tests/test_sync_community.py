"""ForeverFlip Sync: the community exchange as the player sees it (T22). The last successful
exchange, the last error, "no community price yet" for a realm without prices, and a sharing pass
that one unreadable issue no longer stops."""

import io
import pathlib
import sys
import tempfile
import time
import unittest
import urllib.error
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / 'sync'))
import ffscan  # noqa: E402
import foreverflip_sync as helper  # noqa: E402


class Answer(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()


def http_error(code):
    return urllib.error.HTTPError('https://api.github.com/x', code, 'Not Found', {}, None)


class FakeHub:
    def __init__(self, issues, comments=None, gist_error=None):
        self.issues, self.comments, self.gist_error = issues, comments or {}, gist_error
        self.deleted = []

    def issue(self, number):
        value = self.issues[number]
        if isinstance(value, Exception):
            raise value
        return value

    def last_comment(self, number):
        return self.comments.get(number, '')

    def delete_gist(self, gist):
        if self.gist_error:
            raise self.gist_error
        self.deleted.append(gist)


class FollowTests(unittest.TestCase):
    def test_one_unreadable_issue_does_not_stop_the_others(self):
        state = {'pending': [{'issue': 1, 'gist': 'g1', 'scan': 'A-Horde@1'},
                             {'issue': 2, 'gist': 'g2', 'scan': 'A-Horde@2'},
                             {'issue': 3, 'gist': 'g3', 'scan': 'A-Horde@3'},
                             {'issue': 4, 'gist': 'g4', 'scan': 'A-Horde@4'}]}
        hub = FakeHub({1: http_error(404), 2: urllib.error.URLError('offline'),
                       3: {'state': 'closed'}, 4: {'state': 'open'}},
                      {3: 'Checked and archived. It is waiting for a scan of another player to confirm it.'})
        with patch.object(helper, 'log'):
            helper.follow_uploads(hub, state)
        self.assertEqual([i['issue'] for i in state['pending']], [2, 4], 'a gone issue is dropped, others wait')
        self.assertEqual(hub.deleted, ['g3'])
        self.assertEqual(state['results']['A-Horde@3']['outcome'], 'waiting')
        self.assertEqual(state['results']['A-Horde@1']['outcome'], 'closed')

    def test_a_gist_that_cannot_be_deleted_is_logged_not_raised(self):
        state = {'pending': [{'issue': 1, 'gist': 'g1', 'scan': 'A-Horde@1'}]}
        hub = FakeHub({1: {'state': 'closed'}}, {1: 'Refused: the seal does not match.'},
                      gist_error=urllib.error.URLError('offline'))
        with patch.object(helper, 'log') as log:
            helper.follow_uploads(hub, state)
        self.assertEqual(state['pending'], [])
        self.assertEqual(state['results']['A-Horde@1']['outcome'], 'refused')
        self.assertTrue(any('gist' in str(c) for c in log.call_args_list))

    def test_the_answers_are_sorted_into_outcomes(self):
        self.assertEqual(helper.upload_outcome('Checked and published in the community prices now.'), 'published')
        self.assertEqual(helper.upload_outcome('Refused: too old.'), 'refused')
        self.assertEqual(helper.upload_outcome('completed'), 'closed')


class UploadedTests(unittest.TestCase):
    def test_the_newest_scans_are_kept_whatever_their_realm(self):
        state = {'uploaded': [f'Zz-Horde@{100 + i}' for i in range(500)]}
        helper.mark_uploaded(state, 'Aa-Alliance@100000')
        self.assertIn('Aa-Alliance@100000', state['uploaded'], 'sorted as text, this one was cut at once')
        self.assertNotIn('Zz-Horde@100', state['uploaded'])
        self.assertEqual(len(state['uploaded']), 500)
        self.assertIn('shared_at', state['exchange'])


class DownloadReportTests(unittest.TestCase):
    def test_each_auction_house_reports_its_community_scans(self):
        mine, other = 1_700_000_000, 1_700_003_600
        body = '\n'.join([ffscan.encode_summary('Realm-Horde', mine, {'1': (10, 9, 2)}),
                          ffscan.encode_summary('Realm-Horde', other, {'1': (12, 9, 2)})])

        def urlopen(req, timeout=None):
            if 'Empty' in req.full_url:
                raise http_error(404)
            return Answer(body.encode())
        with tempfile.TemporaryDirectory() as tmp, \
                patch.object(helper, 'my_scopes', return_value={'Realm-Horde', 'Empty-Alliance'}), \
                patch.object(helper.urllib.request, 'urlopen', urlopen):
            report = {}
            count = helper.download_shared(pathlib.Path(tmp), 'o/r', [f'Realm-Horde@{mine}'], report=report)
        self.assertEqual(count, 2)
        self.assertEqual(report['Empty-Alliance'], {'scans': 0, 'own': 0, 'latest': None})
        self.assertEqual(report['Realm-Horde'], {'scans': 2, 'own': 1, 'latest': other})


class StatusTests(unittest.TestCase):
    def test_run_once_records_the_exchange_and_its_error(self):
        state = {}
        with patch.object(helper, 'download_shared', side_effect=urllib.error.URLError('offline')), \
                patch.object(helper, 'log'):
            with self.assertRaises(helper.SyncError):
                helper.run_once(pathlib.Path('game'), 'o/r', state, None, False)
        self.assertIn('Community download', state['exchange']['error'])
        self.assertNotIn('ok_at', state['exchange'])
        lines = helper.community_status(state)
        self.assertEqual(lines[0], 'No successful exchange yet')
        self.assertTrue(lines[1].startswith('Last error'))

        def fill(game, repo, uploaded, report):
            report['Realm-Horde'] = {'scans': 0, 'own': 0, 'latest': None}
            return 0
        with patch.object(helper, 'download_shared', side_effect=fill), patch.object(helper, 'log'):
            helper.run_once(pathlib.Path('game'), 'o/r', state, None, False)
        self.assertNotIn('error', state['exchange'])
        lines = helper.community_status(state)
        self.assertTrue(lines[0].startswith('Last exchange'))
        self.assertIn('Realm-Horde: No community price yet (no scan of it is published)', lines)
        self.assertFalse(any(line.startswith('Last error') for line in lines), 'an older error is not shown')

    def test_own_scans_and_waiting_shares_are_told_apart(self):
        now = int(time.time())
        state = {'exchange': {'ok_at': now, 'scopes': {
                    'A-Horde': {'scans': 2, 'own': 2, 'latest': now},
                    'B-Alliance': {'scans': 5, 'own': 1, 'latest': now}}},
                 'results': {'A-Horde@1': {'outcome': 'waiting'}, 'A-Horde@2': {'outcome': 'refused'}},
                 'pending': [{'issue': 9}]}
        text = '\n'.join(helper.community_status(state))
        self.assertIn("A-Horde: No community price yet (only your own scans are published; the addon has them already)", text)
        self.assertIn('B-Alliance: 5 community scans, newest', text)
        self.assertIn("1 shared scan(s) wait for another player's scan", text)
        self.assertIn('1 shared scan(s) were refused', text)
        self.assertIn('1 shared scan(s) are being checked', text)

    def test_an_empty_state_says_so(self):
        self.assertEqual(helper.community_status({}), ['No successful exchange yet'])


if __name__ == '__main__':
    unittest.main()
