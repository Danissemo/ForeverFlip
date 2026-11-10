"""Every interface string passed to the translation function has a Ukrainian translation."""

import pathlib
import re
import unittest

from test_addon import runtime

ADDON = pathlib.Path(__file__).resolve().parent.parent / 'ForeverFlip'
CALL = re.compile(r'\bL\(\s*"((?:[^"\\]|\\.)*)"\s*\)')
ESCAPES = {'\\n': '\n', '\\"': '"', '\\\\': '\\'}


def unescape(text):
    return re.sub(r'\\[n"\\]', lambda m: ESCAPES[m.group(0)], text)


def literals():
    found = set()
    for path in ADDON.glob('*.lua'):
        if path.name == 'Locale.lua':
            continue
        for match in CALL.finditer(path.read_text(encoding='utf-8')):
            found.add(unescape(match.group(1)))
    return found


class LocaleTest(unittest.TestCase):
    def test_every_literal_is_translated(self):
        lua = runtime()
        uk = lua.eval('ForeverFlip.Locale.uk')
        missing = sorted(s for s in literals() if uk[s] is None)
        self.assertEqual(missing, [], 'missing Ukrainian translations')


class LocaleTableTest(unittest.TestCase):
    def test_no_key_is_translated_twice(self):
        import collections
        source = (ADDON / 'Locale.lua').read_text(encoding='utf-8')
        keys = re.findall(r'^    \["((?:[^"\\]|\\.)*)"\] =', source, re.M)
        twice = [k for k, n in collections.Counter(keys).items() if n > 1]
        self.assertEqual(twice, [])


if __name__ == '__main__':
    unittest.main()
