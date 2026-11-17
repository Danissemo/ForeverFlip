"""The layers of docs/architecture.md: Market reads no game-facing module, the services reach the
screen only through Engine (emit / listen / screen), client differences live in Compat, and the
saved data carries a schema version with ordered migrations."""

import re
import unittest

from test_addon import SETUP, run, source


def code(name):
    # The source without its comments, for checks of what a file calls.
    text = source(name).read_text(encoding='utf-8')
    return re.sub(r'--[^\n]*', '', text)


class LayerTests(unittest.TestCase):
    def test_market_reaches_no_other_module_at_run_time(self):
        used = set(re.findall(r'\bF\.([A-Z][A-Za-z]*)', code('Market.lua')))
        self.assertEqual(used - {'Util', 'Market'}, set())

    def test_market_works_unwired_and_trade_keeps_the_sure_maths_names(self):
        run(SETUP + '''local F=ForeverFlip;local M,T=F.Market,F.Trade
        assert(T.saleChances==M.saleChances and T.expectedSold==M.expectedSold)
        local saved={};for k,v in pairs(M.env) do saved[k]=v end
        for k in pairs(M.env) do M.env[k]=function() end end
        M.env.clock=function() return 0 end
        assert(M.duration('c:10',1,100)==3,'no Auto: the longest duration')
        assert(M.postDeposit(10,'commodity',1,1)==100,'no vendor price: the 1 silver minimum')
        M.use(saved)
        assert(M.env.kindOf(10)=='commodity','wired by Core again')''')

    def test_services_do_not_reach_into_the_ui(self):
        for name in ('Deals.lua', 'Trade.lua', 'Bids.lua', 'Scan.lua', 'Sniper.lua', 'AH.lua', 'Mail.lua'):
            self.assertNotIn('F.UI', code(name), name)

    def test_only_ah_calls_the_auction_house(self):
        # Compat may ask whether a function exists, never call one.
        self.assertIsNone(re.search(r'C_AuctionHouse\.\w+\s*\(', code('Compat.lua')))

    def test_emit_reaches_every_listener_in_order(self):
        run('''local E=ForeverFlip.Engine;local got={}
        E.listen('t13',function(a,b) got[#got+1]='1'..a..b end)
        E.listen('t13',function(a,b) got[#got+1]='2'..a..b end)
        E.emit('t13','x','y');E.emit('nobody listens')
        assert(got[1]=='1xy' and got[2]=='2xy' and #got==2)
        E.emit('select','c:10');assert(ForeverFlip.UI.selected=='c:10','the UI follows a selection')''')

    def test_the_screen_reader_tells_what_is_shown(self):
        run('''local E,UI=ForeverFlip.Engine,ForeverFlip.UI
        UI.section='mybids';assert(E.screen().section=='mybids' and E.screen().shown==true)
        UI.frame:Hide();assert(E.screen().shown==false and E.screen().frame==true)
        local reader=E.screenReader;E.screenReader=nil
        assert(E.screen().frame==false and E.screen().section==nil,'no UI: nothing shown')
        E.screenReader=reader''')


class CapabilityTests(unittest.TestCase):
    def test_forever_client_has_what_the_addon_uses(self):
        run('''local caps=ForeverFlip.Compat.caps
        assert(caps.fullScan and caps.commodities and caps.item and caps.container)
        assert(caps.replicateCooldown==ForeverFlip.Scan.COOLDOWN)''')

    def test_a_client_without_replicate_items_reports_no_full_scan(self):
        run(SETUP + '''local F=ForeverFlip;local S,UI=F.Scan,F.UI
        local real=C_AuctionHouse.ReplicateItems
        C_AuctionHouse.ReplicateItems=nil
        assert(F.Compat.caps.fullScan==false and F.Compat.caps.replicateCooldown==nil)
        local ok,why=S.canStart();assert(not ok and why=='unavailable',tostring(why))
        ok,why=S.start();assert(not ok and why=='unavailable' and not S.busy(),tostring(why))
        F.Engine.keyScan();assert(F.Engine.message=='unavailable')
        UI.refresh()
        assert(not UI.scanButton:IsEnabled(),'the button is greyed out')
        assert(UI.scanButton:GetText()=='No full scan',UI.scanButton:GetText())
        C_AuctionHouse.ReplicateItems=real
        assert(F.Compat.caps.fullScan and S.canStart())''')

    def test_spell_checks_keep_the_namespace_first_rule(self):
        run('''local C=ForeverFlip.Compat
        C_SpellBook={}
        IsSpellKnown=function() return true end
        assert(C.spellKnown(1)==nil,'the namespace is there: no bare fallback')
        C_SpellBook=nil
        assert(C.spellKnown(1)==true,'no namespace: the fallback answers')''')


DUMP = '''local function dump(v)
    if type(v) ~= 'table' then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. '=' .. dump(v[k]) end
    return '{' .. table.concat(out, ',') .. '}'
end
'''


class SchemaTests(unittest.TestCase):
    def test_old_data_is_migrated_once_and_keeps_its_values(self):
        run(DUMP + '''local D = ForeverFlip.Data
        assert(D.SCHEMA_VERSION == #D.MIGRATIONS and D.SCHEMA_VERSION >= 2)
        local old = { settings = { vendorMargin = 20, minProfit = 777 }, salesModel = 3, lastScan = 5,
            vendor = { [10] = 30 }, chars = { ['A-R'] = { journal = { { kind = 'buy', price = 9 } } } },
            markets = { R = { statsVersion = 1, history = { ['c:1'] = { scan = { median = 120 },
                sales = { pairs = 4 }, lots = '1:1:3', days = { { d = 1, m = 120, s = 2 } } } } } } }
        local db = D.open(old)
        assert(db.schemaVersion == D.SCHEMA_VERSION, tostring(db.schemaVersion))
        assert(db.settings.vendorMargin == 0 and db.settings.minProfit == 777)
        assert(db.lastScan == 5 and db.vendor[10] == 30 and db.chars['A-R'].journal[1].price == 9)
        local h = db.markets.R.history['c:1']
        assert(h.scan.median == 120 and h.days[1].m == 120 and not h.days[1].s and not h.sales)
        assert(db.markets.R.statsVersion == 1, 'the statistics keep their own version')
        db.settings.vendorMargin = 20 -- set again by the player: not migrated a second time
        local before = dump(db)
        assert(dump(D.open(db)) == before, 'a second open changes nothing')
        assert(dump(D.open(db)) == before)''')

    def test_a_file_without_a_version_but_with_the_old_markers_is_not_changed(self):
        run('''local D = ForeverFlip.Data
        local db = D.open({ vendorMarginReset = true, salesModel = D.SALES_MODEL, settings = { vendorMargin = 20 },
            markets = { R = { history = { ['c:1'] = { sales = { pairs = 4 } } } } } })
        assert(db.settings.vendorMargin == 20 and db.markets.R.history['c:1'].sales.pairs == 4)
        assert(db.schemaVersion == D.SCHEMA_VERSION)''')

    def test_a_fresh_file_gets_the_current_version(self):
        run('''local D = ForeverFlip.Data
        assert(D.open(nil).schemaVersion == D.SCHEMA_VERSION)
        assert(D.open({}).schemaVersion == D.SCHEMA_VERSION)''')

    def test_a_newer_file_is_left_alone_with_a_warning(self):
        run('''local D = ForeverFlip.Data
        local db = D.open({ schemaVersion = D.SCHEMA_VERSION + 5, settings = { vendorMargin = 20 }, salesModel = 1,
            markets = { R = { history = { ['c:1'] = { sales = { pairs = 4 } } } } } })
        assert(db.schemaVersion == D.SCHEMA_VERSION + 5 and db.settings.vendorMargin == 20)
        assert(db.markets.R.history['c:1'].sales.pairs == 4 and db.salesModel == 1)
        local text = ForeverFlip.Log.last('error')
        assert(text and text:find('newer ForeverFlip'), tostring(text))''')


if __name__ == '__main__':
    unittest.main()
