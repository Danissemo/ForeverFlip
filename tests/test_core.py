import unittest
from test_controller import controller_runtime
from test_domain import ROOT

class CoreTests(unittest.TestCase):
    def test_addon_load_registers_auction_entry_without_spending(self):
        lua=controller_runtime()
        lua.execute((ROOT/'tests/wow_mock.lua').read_text())
        lua.execute((ROOT/'ForeverFlip/UI.lua').read_text(encoding='utf-8-sig'))
        core=ROOT/'ForeverFlip/Core.lua'
        assert core.exists(), 'Missing addon entrypoint'
        lua.execute(core.read_text(encoding='utf-8-sig'))
        lua.execute('''ForeverFlip.boot('ForeverFlip'); assert(ForeverFlip.controller and ForeverFlip.db.schemaVersion==5)
        ForeverFlip.attach(); assert(ForeverFlip.ui and ForeverFlip.entry)
        assert(spent==0 and SlashCmdList.FOREVERFLIP)''')

if __name__=='__main__': unittest.main()
