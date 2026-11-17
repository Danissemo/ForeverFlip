"""T30: work repeated every frame or every refresh, measured by counters (Engine.counts).

E.scope() names the auction house whose data a figure uses. It is asked for each deal's Sure, by
every page refresh and by every item tooltip; each answer used to call C_GameRules through pcall and
build a new string of three parts. Now the rules' answer is kept for the same C_GameRules table and
the string is built again only when the realm, the hardcore mark, the open house or the faction
changes.

Measured on the scenario below (a full scan, the Deals page refreshed 50 times over 25 seconds of
frames, 20 item tooltips) on a hardcore realm:

                       before    after
    E.scope() calls    198       198
    strings built      198       0 (built once before, at the scan; again per change of house)
    C_GameRules asked  198       0 (once per session)
"""

import unittest

from test_addon import SETUP, run

SCENARIO = SETUP + '''local F, E, UI = ForeverFlip, ForeverFlip.Engine, ForeverFlip.UI
Enum = Enum or {}; Enum.GameRule = { HardcoreRuleset = 7 }
C_GameRules = { IsGameRuleActive = function(rule) return rule == 7 end }
fullScan()
UI.show('deals:flip')
E.counts = { scope = 0, scopeBuilt = 0, hardcoreAsked = 0 }
for i = 1, 50 do F.Engine.changed(); UI.refresh(); run(0.5) end
for i = 1, 20 do
    tooltipLines = {}
    GameTooltip.itemLink = link(10)
    for _, fn in ipairs(tooltipCalls) do fn(GameTooltip) end
end
'''


class ScopeMemoTests(unittest.TestCase):
    def test_the_scope_is_built_once_while_nothing_changes(self):
        counts = run(SCENARIO + '''local c = E.counts
        assert(E.scope() == 'Realm (HC)-Alliance', E.scope())
        return c.scope .. ' ' .. c.scopeBuilt .. ' ' .. c.hardcoreAsked''')
        calls, built, asked = (int(x) for x in counts.split())
        print('\nT30 E.scope: %d calls, %d strings built, C_GameRules asked %d times (before: %d, %d, %d)'
              % (calls, built, asked, calls, calls, calls))
        self.assertGreater(calls, 100, 'the scenario asks often')
        self.assertLessEqual(built, 1)
        self.assertLessEqual(asked, 1)

    def test_a_change_of_house_or_rules_gives_the_new_scope(self):
        run(SETUP + '''local E = ForeverFlip.Engine
        assert(E.scope() == 'Realm-Alliance')
        E.house = 'Neutral'; assert(E.scope() == 'Realm-Neutral')
        E.house = nil; assert(E.scope() == 'Realm-Alliance')
        Enum = Enum or {}; Enum.GameRule = { HardcoreRuleset = 7 }
        C_GameRules = { IsGameRuleActive = function(rule) return rule == 7 end }
        assert(E.scope() == 'Realm (HC)-Alliance')
        C_GameRules = nil; assert(E.scope() == 'Realm-Alliance')
        local real = GetRealmName; GetRealmName = function() return 'Other' end
        assert(E.scope() == 'Other-Alliance'); GetRealmName = real''')


if __name__ == '__main__':
    unittest.main()
