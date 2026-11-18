"""ForeverFlip needs no other addon: players install it alone. Other addons (TSM, Auctionator, ...)
may help development (tools/calibrate.py), never the addon at run time."""

import pathlib
import re
import unittest

from test_addon import ADDON, runtime, toc_files

# Public entry points of other auction addons; the addon must not call them.
FOREIGN = re.compile(r'\b(TSM_API|TradeSkillMaster|Auctionator|AUCTIONATOR_\w+|AuctionDB|LibTSM\w*)\b')


def code_lines(path: pathlib.Path):
    for number, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
        code = line.split('--', 1)[0]
        if code.strip():
            yield number, code


class StandaloneTests(unittest.TestCase):
    def test_the_toc_requires_no_other_addon(self):
        toc = (ADDON / 'ForeverFlip.toc').read_text(encoding='utf-8')
        self.assertNotRegex(toc, r'(?im)^##\s*(RequiredDeps|Dependencies|Dep\w*)\s*:')

    def test_no_code_calls_another_auction_addon(self):
        found = [f'{p.name}:{n}: {c.strip()}' for p in toc_files() for n, c in code_lines(p) if FOREIGN.search(c)]
        self.assertEqual(found, [])

    def test_the_addon_loads_and_opens_without_any_library(self):
        lua = runtime()
        G = lua.globals()
        self.assertIsNone(G.LibStub)
        lua.execute("fire('AUCTION_HOUSE_SHOW')")
        self.assertTrue(G.ForeverFlip.UI.frame)


if __name__ == '__main__':
    unittest.main()
