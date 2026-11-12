"""The community-history check of every published scan."""

import pathlib
import tempfile
import time
import unittest

from test_sync import FakeHub, aggregate, ffscan, make_scan


def big_market(scale=None, extra=()):
    """Six lots of 30 items; `scale` maps an item to a price factor."""
    scale = scale or {}
    return [(item, 5, int((100 * item + k) * scale.get(item, 1))) for item in range(1, 31) for k in range(6)] \
        + list(extra)


class HistoryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.data = pathlib.Path(self.tmp.name)
        (self.data / 'registry').mkdir()
        (self.data / 'registry' / 'uploaders.json').write_text('{"trusted": [], "banned": []}')
        self.now = int(time.time())
        self.hub = FakeHub()

    def run_once(self, now=None):
        aggregate.process(self.hub, self.data, now or self.now)
        return {e['uploader']: e for e in aggregate.load_registry(self.data)}

    def published(self, at):
        path = self.data / 'shared' / 'Realm-Alliance.txt'
        for when, items in aggregate.read_summaries(path):
            if when == at:
                return items
        return None

    def history(self, scale=None, days_ago=1):
        shared = self.data / 'shared'
        shared.mkdir(exist_ok=True)
        items = ffscan.summarize(make_scan(self.now - days_ago * 86400, big_market(scale)))
        aggregate.add_summary(shared, 'Realm-Alliance', self.now - days_ago * 86400, items)

    def test_prices_far_from_the_history_are_left_out(self):
        self.history()
        odd = big_market({3: 5})  # item 3 five times dearer than the community saw
        self.hub.add_upload(make_scan(self.now - 3000, odd), 'Alice', 1)
        self.hub.add_upload(make_scan(self.now - 60, odd), 'Bob', 2)
        result = self.run_once()
        self.assertEqual(result['Bob']['status'], 'confirmed')
        items = self.published(self.now - 60)
        self.assertNotIn('c:3', items)
        self.assertIn('c:4', items)
        self.assertEqual(result['Bob']['history'], {'compared': 30, 'off': 1})

    def test_a_scan_mostly_out_of_line_is_disputed(self):
        self.history()
        odd = big_market({item: 4 for item in range(1, 12)})  # 11 of 30 items far off
        self.hub.add_upload(make_scan(self.now - 3000, odd), 'Alice', 1)
        self.hub.add_upload(make_scan(self.now - 60, odd), 'Bob', 2)
        result = self.run_once()
        self.assertEqual(result['Bob']['status'], 'disputed')
        self.assertIsNone(self.published(self.now - 60))


if __name__ == '__main__':
    unittest.main()
