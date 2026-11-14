"""Whether the player can disenchant: the documented C_SpellBook first, the client's deprecated
bare functions only when it does not have it."""

import unittest

from test_addon import SETUP, run


class CanDisenchantTests(unittest.TestCase):
    def test_c_spellbook_is_asked_with_the_player_spell_bank(self):
        run(SETUP + '''local DE=ForeverFlip.Disenchant
        local asked
        Enum.SpellBookSpellBank={Player=1,Pet=2}
        C_SpellBook={IsSpellKnown=function(id,bank) asked={id,bank};return true end}
        assert(DE.canDisenchant()==true)
        assert(asked[1]==DE.SPELL and asked[2]==1,'the item spell, the player bank')''')

    def test_a_client_without_c_spellbook_falls_back_to_the_bare_functions(self):
        run(SETUP + '''local DE=ForeverFlip.Disenchant
        C_SpellBook=nil
        IsPlayerSpell=function(id) return false end
        IsSpellKnown=function(id) return true end
        assert(DE.canDisenchant()==true,'the second, older form still answers')''')

    def test_an_unknown_spell_and_an_error_both_mean_no(self):
        run(SETUP + '''local DE=ForeverFlip.Disenchant
        Enum.SpellBookSpellBank={Player=1}
        C_SpellBook={IsSpellKnown=function() return false end}
        assert(DE.canDisenchant()==false)
        C_SpellBook={IsSpellKnown=function() error('blocked') end}
        assert(DE.canDisenchant()==false,'a protected call that fails is not a yes')''')

    def test_nothing_to_ask_means_no(self):
        run(SETUP + '''local DE=ForeverFlip.Disenchant
        C_SpellBook=nil;IsPlayerSpell=nil;IsSpellKnown=nil
        assert(DE.canDisenchant()==false)''')

    def test_the_same_answer_costs_nothing_extra(self):
        # Called from the trade pages, so it is asked on every refresh: no scan of the bags or the
        # auction house data is started by it.
        run(SETUP + '''local DE=ForeverFlip.Disenchant
        Enum.SpellBookSpellBank={Player=1}
        local calls=0
        C_SpellBook={IsSpellKnown=function() calls=calls+1;return true end}
        DE.canDisenchant();DE.canDisenchant()
        assert(calls==2,'asked each time, never cached behind a stale answer')''')


if __name__ == '__main__':
    unittest.main()
