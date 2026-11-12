"""Headless regressions for sharing transitions and the native window icon."""
import pathlib
import queue
import sys
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / 'sync'))
import sync_gui


class GuiStateTests(unittest.TestCase):
    def test_existing_download_session_starts_uploading_after_account_arrives(self):
        session = SimpleNamespace(upload=False, last_seen={'save': (1, 1)}, retry_at=100,
                                  refresh_credentials=Mock(), sync=Mock(return_value=0))
        core = SimpleNamespace(saved_variable_files=Mock(return_value=['save']))
        window = SimpleNamespace(busy=False, game=pathlib.Path('game'), closing=False,
                                 share=Mock(get=Mock(return_value=True)), account=('user', 'helper'),
                                 status=Mock(), set_busy=Mock(), session=session, core=core,
                                 config={}, events=queue.Queue())
        with patch.object(sync_gui.threading, 'Thread') as thread:
            thread.side_effect = lambda target, **kw: SimpleNamespace(start=target)
            sync_gui.SyncWindow.start_sync(window)
        self.assertTrue(session.upload)
        self.assertEqual(session.last_seen, {}, 'unchanged saved scans must be reconsidered')
        self.assertEqual(session.retry_at, 0)
        session.refresh_credentials.assert_called_once()
        session.sync.assert_called_once()

    def test_delayed_account_wakes_automatic_sync_even_with_unchanged_save(self):
        events = queue.Queue()
        events.put(('account', ('user', 'helper')))
        session = SimpleNamespace(upload=False, due=lambda: False)
        window = SimpleNamespace(events=events, account=None, refresh_share_state=Mock(),
                                 updating=False, closing=False, game=pathlib.Path('game'),
                                 next_update=float('inf'), next_check=0, busy=False,
                                 auto=Mock(get=Mock(return_value=True)),
                                 share=Mock(get=Mock(return_value=True)), session=session,
                                 start_sync=Mock(), root=Mock(), poll=Mock())
        sync_gui.SyncWindow.poll(window)
        window.start_sync.assert_called_once()

    def test_title_icon_uses_photos_without_ico_overriding_them(self):
        root, images = Mock(), Mock()
        photos = sync_gui.window_icons(root, images)
        self.assertTrue(photos)
        root.iconphoto.assert_called_once_with(True, *photos)
        root.iconbitmap.assert_not_called()


if __name__ == '__main__':
    unittest.main()
