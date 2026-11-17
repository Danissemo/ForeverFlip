"""The clean start the player asks for (Settings > Messages, /ff reset), and Resale on fresh data."""

import unittest

from test_addon import runtime


class ResetDataTests(unittest.TestCase):
    def test_reset_keeps_only_the_settings(self):
        lua = runtime()
        lua.execute(r'''
        local F, D = ForeverFlip, ForeverFlip.Data
        F.db.settings.minProfit = 50
        D.market(F.db, 'Realm-Alliance').history['i:1'] = { scan = { at = 1, market = 10 } }
        D.addPosition(D.char(F.db, 'Realm-Lasqa'), 'i:1', 'Held', 1, 100, 'flip', 200, 5)
        local fresh = D.reset(F.db)
        assert(fresh.settings.minProfit == 50, 'the player keeps their settings')
        assert(fresh.settings ~= F.db.settings, 'a copy, not the old table')
        assert(next(fresh.markets) == nil and next(fresh.chars) == nil, 'prices and journals go')
        assert(fresh.schemaVersion == D.SCHEMA_VERSION)''')

    def test_the_reload_after_the_confirmation_writes_a_clean_file(self):
        lua = runtime()
        lua.execute(r'''
        local F, D = ForeverFlip, ForeverFlip.Data
        local reloaded
        ReloadUI = function() reloaded = true end
        StaticPopupDialogs = {}
        StaticPopup_Show = function() end
        F.db.settings.minProfit = 50
        D.market(F.db, 'Realm-Alliance').history['i:1'] = { scan = { at = 1, market = 10 } }
        ForeverFlipRaw = { scans = { {} } }
        SlashCmdList.FOREVERFLIP('reset')
        assert(StaticPopupDialogs.FOREVERFLIP_RESET, 'asked first')
        assert(not F.resetPending, 'nothing happens before the answer')
        StaticPopupDialogs.FOREVERFLIP_RESET.OnAccept()
        assert(F.resetPending and reloaded)
        fire('PLAYER_LOGOUT')
        assert(ForeverFlipRaw == nil, 'the full scans go')
        assert(ForeverFlipData.settings.minProfit == 50)
        assert(next(ForeverFlipData.markets) == nil)''')


class FreshDataResaleTests(unittest.TestCase):
    def test_an_item_watched_under_an_hour_is_still_being_learned(self):
        lua = runtime()
        lua.execute(r'''
        local M, now = ForeverFlip.Market, 1700000000
        local rows = { { unit = 998, qty = 5 }, { unit = 7800, qty = 16 } }
        local h = {}
        M.recordSales(h, {}, 1800, now)
        h.sales.pairs = 2
        local d, why = M.evaluate(rows, { kind = 'commodity', budget = 1000000, history = h, market = 7800,
          now = now, settings = {} })
        assert(not d and why == 'collecting', why)
        h = {}
        M.recordSales(h, {}, 3 * 3600, now)
        h.sales.pairs = 4
        d, why = M.evaluate(rows, { kind = 'commodity', budget = 1000000, history = h, market = 7800,
          now = now, settings = {} })
        assert(not d and why == 'not_selling', why)''')


if __name__ == '__main__':
    unittest.main()
