"""Gear I can't use on Retail: proficiencies are Retail's, a main stat any specialization of the
class uses keeps a piece (a respec makes it wearable), and gear bound to the account (heirlooms,
warband pieces) never counts, since an alt can wear it."""

import unittest

from test_addon import run
import test_audit

RETAIL = test_audit.GearSellTests.GEAR + '''GetBuildInfo = function() return '12.0.1', '1', 'Nov 1 2026', 120001 end
local instant = C_Item.GetItemInfoInstant
C_Item.GetItemInfoInstant = function(id)
    local kinds = { [85] = { 'INVTYPE_POLEARM', 2, 6 }, [86] = { 'INVTYPE_CHEST', 4, 2 },
        [87] = { 'INVTYPE_CHEST', 4, 2 }, [88] = { 'INVTYPE_CHEST', 4, 4 }, [89] = { 'INVTYPE_TRINKET', 4, 0 },
        [90] = { 'INVTYPE_CHEST', 4, 1 } }
    local k = kinds[id]
    if not k then return instant(id) end
    return id, '', '', k[1], 0, k[2], k[3]
end
local stats = { ['l86'] = { ITEM_MOD_STRENGTH_SHORT = 900 }, ['l87'] = { ITEM_MOD_INTELLECT_SHORT = 900 },
    ['l89'] = { ITEM_MOD_STRENGTH_SHORT = 500 }, ['l90'] = { ITEM_MOD_AGILITY_INTELLECT_SHORT = 700 } }
C_Item.GetItemStats = function(l) return stats[l] or {} end
local warband = {}
C_Item.IsItemBindToAccount = function(id) return warband[id] == true end
'''


class RetailUnusableGearTests(unittest.TestCase):
    def test_druid_on_retail(self):
        run(RETAIL + '''local A = F.AH
        assert(A.unusableGear(85, 'l85') == false, 'druids wield polearms on Retail')
        assert(A.unusableGear(87, 'l87') == false, 'intellect leather: balance and restoration wear it')
        assert(A.unusableGear(86, 'l86') == true, 'strength leather fits no druid specialization')
        assert(A.unusableGear(89, 'l89') == true, 'a strength trinket too')
        assert(A.unusableGear(90, 'l90') == false, 'cloth with agility or intellect is wearable')
        assert(A.unusableGear(88, 'l88') == true, 'no plate for a druid')
        assert(A.unusableGear(84) == true, 'no mail for a druid')''')

    def test_a_respec_counts_for_every_class(self):
        run(RETAIL + '''UnitClass = function() return 'Paladin', 'PALADIN' end
        assert(F.AH.unusableGear(87, 'l87') == false, 'holy wears intellect')
        assert(F.AH.unusableGear(86, 'l86') == false, 'retribution wears strength')
        UnitClass = function() return 'Monk', 'MONK' end
        assert(F.AH.unusableGear(86, 'l86') == true, 'no monk uses strength')
        assert(F.AH.unusableGear(85, 'l85') == false, 'monks wield polearms')''')

    def test_warband_gear_is_kept_for_alts(self):
        run(RETAIL + '''warband[88] = true; warband[86] = true
        assert(F.AH.unusableGear(88, 'l88') == false, 'warband plate goes to an alt')
        assert(F.AH.unusableGear(86, 'l86') == false, 'warband strength leather too')''')

    def test_heirlooms_are_kept_on_forever_too(self):
        run(test_audit.GearSellTests.GEAR + '''local info = F.Util.itemInfo
        F.Util.itemInfo = function(id)
            if id == 84 then return 'Chain Vest', nil, 7, 1, 1, '', '', 1, '', 0, 900, 4, 3, 7 end
            return info(id)
        end
        assert(F.AH.unusableGear(84) == false, 'an heirloom chain vest is for an alt')
        assert(F.AH.unusableGear(81) == true, 'the axe still goes')''')


if __name__ == '__main__':
    unittest.main()
