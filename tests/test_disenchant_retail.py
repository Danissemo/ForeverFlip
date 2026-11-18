"""Disenchanting on Retail (Midnight): an item gives the materials of its own expansion whatever its
level, so the band is its expansion and quality; Midnight gear is priced from its table, older
expansions only from your own disenchants."""

import unittest

from test_addon import run

RETAIL = '''local F = ForeverFlip
local DE = F.Disenchant
GetBuildInfo = function() return '12.0.1', '1', 'Nov 1 2026', 120001 end
local info = F.Util.itemInfo
local gear = {}
F.Util.itemInfo = function(id)
    local g = gear[id]
    if g then return 'Gear ' .. id, nil, g[1], g[2], 80, '', '', 1, '', 0, 100, g[3], 0, 1, g[4] end
    return info(id)
end
local h = F.Data.market(F.db, F.Engine.scope()).history
local function price(id, p) h['c:' .. id] = { scan = { market = p, at = now } } end
'''


class MidnightDisenchantTests(unittest.TestCase):
    def test_midnight_gear_is_priced_from_its_reagents(self):
        run(RETAIL + '''gear[50] = { 2, 197, 4, 11 }   -- green Midnight armor, item level 197
        gear[51] = { 3, 220, 2, 11 }   -- blue Midnight weapon
        gear[52] = { 4, 250, 4, 11 }   -- epic Midnight armor
        price(243599, 10000); price(243600, 20000)
        price(243602, 50000); price(243603, 80000)
        price(243605, 300000); price(243606, 500000)
        assert(DE.band(2, 197, 4, 11) == 'x11:2:a', DE.band(2, 197, 4, 11))
        local green = DE.value(50)
        local want = math.floor(F.Market.net(10000, 1) * 1.35 + F.Market.net(20000, 1) * 0.45)
        assert(math.abs(green - want) <= 1, green .. ' ' .. want)
        assert(DE.value(51) > green and DE.value(52) > DE.value(51), 'shard over dust, crystal over shard')
        DE.canDisenchant = function() return true end
        assert(DE.status(true) == nil, 'Midnight reagents priced: deals can be found')''')

    def test_older_expansions_are_not_guessed_from_the_classic_table(self):
        # Retail squished item levels: a level 25 green of an older expansion is not Classic's band.
        run(RETAIL + '''gear[60] = { 2, 25, 2, 0 }
        price(10940, 5000); price(10939, 5000); price(10938, 5000); price(10978, 5000)
        assert(DE.outcomes(2, 25, 2, 0) == nil and DE.value(60) == nil)
        assert(DE.band(2, 25, 2, nil) == nil, 'no expansion known: nothing learned or priced')''')

    def test_own_disenchants_teach_an_older_expansion(self):
        run(RETAIL + '''gear[70] = { 2, 60, 4, 10 }   -- green The War Within armor
        loot = {}
        function GetNumLootItems() return #loot end
        function GetLootSlotLink(i) return '|Hitem:' .. loot[i][1] .. ':|h[x]|h' end
        function GetLootSlotInfo(i) return 0, 'x', loot[i][2] end
        bags[0] = { [1] = { itemID = 70, stackCount = 1, isLocked = true } }
        for _ = 1, DE.LEARN do
            DE.onCast('UNIT_SPELLCAST_START', 'player', nil, DE.SPELL)
            DE.onCast('UNIT_SPELLCAST_SUCCEEDED', 'player', nil, DE.SPELL)
            loot = { { 219946, 2 } }
            assert(DE.onLoot())
        end
        local out, how = DE.outcomes(2, 60, 4, 10)
        assert(how == 'yours' and out[1][1] == 219946 and out[1][2] == 2, tostring(how))''')

    def test_wow_forever_keeps_the_classic_table(self):
        run('''local DE = ForeverFlip.Disenchant
        assert(DE.band(2, 25, 2) == '2:w:25' and DE.outcomes(2, 25, 2)[2][1] == 10939)''')


if __name__ == '__main__':
    unittest.main()
