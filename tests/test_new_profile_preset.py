"""T27: a new profile starts on the Careful preset; an existing profile keeps its values."""

import unittest

import lupa.lua51 as lupa

from test_addon import ADDON, HERE


def load(saved):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute((HERE / 'mock.lua').read_text(encoding='utf-8'))
    for line in (ADDON / 'ForeverFlip.toc').read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if line.endswith('.lua'):
            lua.execute((ADDON / line).read_text(encoding='utf-8'))
    lua.execute(saved)
    lua.execute("fire('ADDON_LOADED','ForeverFlip')")
    return lua


class NewProfilePresetTests(unittest.TestCase):
    def test_a_new_profile_starts_careful_with_a_15_copper_vendor_minimum(self):
        load('ForeverFlipData=nil').execute('''local s=ForeverFlip.db.settings
        assert(s.vendorMinProfit==15, tostring(s.vendorMinProfit))
        assert(s.minProfit==500 and math.abs(s.minROI-0.35)<1e-9 and s.alertMinProfit==100)
        assert(math.abs(s.spendShare-0.5)<1e-9 and math.abs(s.itemShare-0.15)<1e-9)''')

    def test_an_existing_profile_keeps_what_it_has(self):
        load('ForeverFlipData={settings={minProfit=123}}').execute('''local s=ForeverFlip.db.settings
        assert(s.minProfit==123, 'the saved value stays')
        assert(s.vendorMinProfit==10, 'a missing value gets the old default, not Careful')''')

    def test_the_careful_button_sets_the_same_values(self):
        load('ForeverFlipData={settings={}}').execute('''local F=ForeverFlip
        assert(F.UI.PRESETS==F.Data.PRESETS, 'the Settings buttons use the same table')
        assert(F.UI.PRESETS.careful.vendorMinProfit==15)''')


if __name__ == '__main__':
    unittest.main()
