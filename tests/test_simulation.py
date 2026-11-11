"""Simulated play sessions: a living auction house (tests/sim.lua) where other players list, buy and
let lots expire, while ForeverFlip scans, snipes, checks and buys deals, posts what it bought,
sells, takes the mail and sells vendor deals at a merchant. After every 15-minute tick everything
that must always hold is checked, and every page and tooltip is drawn. Any Lua error fails the run.
"""

import pathlib
import time
import unittest

from test_addon import runtime

HERE = pathlib.Path(__file__).resolve().parent

SESSION = '''
local F = ForeverFlip
reported = {}
F.Engine.report = function(err) reported[#reported + 1] = tostring(err) end
F.Engine.autoVerify = true
F.db.settings.autoScan = false
F.db.settings.sniper = true
F.db.settings.vendorMargin = 0
enableBrowse(200)
enableTimeLeft()
if %(chaos)s > 0 then
    -- Real hooks: the addon sees the browses and full scans it did not send.
    function hooksecurefunc(t, name, fn)
        local orig = t[name]
        t[name] = function(...) local a, b, c = orig(...); fn(...); return a, b, c end
    end
    F.AH.browseHooked = false; F.AH.hookBrowse()
    F.Engine.replicateHooked = false; F.Engine.hookReplicate()
end
sim.chaosRate = %(chaos)s
sim.seed(%(seed)d)
sim.setup(%(commodities)d, %(items)d, %(gear)d)
sim.list(%(start)d)
problems = {}
local ticks = { bought = 0, deals = 0 }
for tick = 1, %(ticks)d do
    -- the market moves for 15 minutes
    sim.list(%(perTick)d); sim.buy(%(buyers)d); sim.expire()
    now = now + 901
    -- a full scan, then the sniper and the checks run for a while
    if not (sim.chaosRate > 0 and tick %% 3 == 0 and sim.otherScan()) then
        fullScan()
    end
    sim.play(20)
    ticks.deals = ticks.deals + #F.Deals.list
    ticks.bought = ticks.bought + sim.buyDeals(4)
    sim.play(2)
    sim.post(6)
    fire('OWNED_AUCTIONS_UPDATED')
    for i = #owned, 1, -1 do if owned[i].status == 1 then table.remove(owned, i) end end
    sim.mail()
    F.Trade.sellToVendor()
    sim.drawAll()
    for _, p in ipairs(sim.check()) do problems[#problems + 1] = 'tick ' .. tick .. ': ' .. p end
end
local c = F.Data.char(F.db, F.Engine.owner())
local positions = 0
for _ in pairs(c.positions) do positions = positions + 1 end
summary = string.format('deals seen %%d, bought %%d units in %%d buys, posted %%d, sold %%d, expired %%d, journal %%d, positions %%d'
    .. (sim.chaosRate > 0 and '; Buy tab browses %%d, reopened %%d, other addon scans %%d' or ''),
    ticks.deals, sim.bought, ticks.bought, sim.posted, sim.sold, sim.expired, #c.journal, positions,
    sim.events.browses, sim.events.reopened, sim.events.otherScans)
'''


def session(seed, ticks=10, commodities=15, items=8, gear=6, start=500, per_tick=80, buyers=60, chaos=0):
    lua = runtime()
    lua.execute((HERE / 'sim.lua').read_text(encoding='utf-8'))
    began = time.perf_counter()
    lua.execute(SESSION % dict(seed=seed, ticks=ticks, commodities=commodities, items=items, gear=gear,
                               start=start, perTick=per_tick, buyers=buyers, chaos=chaos))
    took = time.perf_counter() - began
    g = lua.globals()
    problems = [g.problems[i] for i in range(1, len(g.problems) + 1)]
    reported = [g.reported[i] for i in range(1, len(g.reported) + 1)]
    return problems, reported, g.summary, took


class SimulationTests(unittest.TestCase):
    def run_seed(self, seed, **kw):
        problems, reported, summary, took = session(seed, **kw)
        print(f'\nseed {seed}: {summary} ({took:.1f} s)')
        self.assertEqual(reported, [], 'errors the addon caught and reported')
        self.assertEqual(problems, [], 'broken invariants')
        return summary

    def test_session_seed_1(self):
        summary = self.run_seed(1)
        self.assertNotIn('bought 0 units', summary, 'the session bought something')

    def test_session_seed_2(self):
        self.run_seed(2)

    def test_session_with_the_player_and_other_addons_meanwhile(self):
        summary = self.run_seed(6, chaos=0.05)
        self.assertNotIn('other addon scans 0', summary, 'another addon scanned')

    def test_session_seed_3_busy_market(self):
        self.run_seed(3, ticks=8, per_tick=200, buyers=150, start=1500)


def fresh_runtime(saved_lua=None, open_ah=True):
    """A client after /reload: the addon files load again and read the saved data written as text."""
    import lupa.lua51 as lupa
    from test_addon import ADDON
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute((HERE / 'mock.lua').read_text(encoding='utf-8'))
    for line in (ADDON / 'ForeverFlip.toc').read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if line.endswith('.lua'):
            lua.execute((ADDON / line).read_text(encoding='utf-8'))
    if saved_lua:
        lua.execute(saved_lua)
    lua.execute("fire('ADDON_LOADED','ForeverFlip')")
    lua.execute((HERE / 'sim.lua').read_text(encoding='utf-8'))
    if open_ah:
        lua.execute("fire('AUCTION_HOUSE_SHOW');ForeverFlip.UI.frame:Show()")
    return lua


def saved_variables(lua):
    """ForeverFlipData written like the game writes SavedVariables (a Lua table constructor)."""
    def lit(v):
        t = lua.eval('type')(v)
        if t == 'table':
            parts = []
            for k in v.keys():
                parts.append('[' + lit(k) + '] = ' + lit(v[k]))
            return '{' + ', '.join(parts) + '}'
        if t == 'string':
            return '"' + v.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'
        if t == 'number':
            return repr(v) if isinstance(v, float) else str(v)
        if t == 'boolean':
            return 'true' if v else 'false'
        return 'nil'
    return 'ForeverFlipData = ' + lit(lua.eval('ForeverFlipData')) + '\n'


class ReloadAndHouseTests(unittest.TestCase):
    def test_a_reload_keeps_scan_deals_stock_and_journal(self):
        lua = runtime()
        lua.execute((HERE / 'sim.lua').read_text(encoding='utf-8'))
        lua.execute(SESSION % dict(seed=4, ticks=5, commodities=12, items=6, gear=4, start=400, perTick=80, buyers=60, chaos=0))
        lua.execute("fire('PLAYER_LOGOUT')")
        before = lua.eval("""(function()
            local F = ForeverFlip; local c = F.Data.char(F.db, F.Engine.owner())
            local n = 0; for _ in pairs(c.positions) do n = n + 1 end
            return table.concat({ F.Scan.last.at, F.Scan.last.total, #F.Deals.list, n, #c.journal }, ' ')
        end)()""")
        text = saved_variables(lua)
        clock = lua.eval('now')
        after_lua = fresh_runtime(text, open_ah=False)
        after_lua.execute('now = %r' % clock)
        after_lua.execute("fire('AUCTION_HOUSE_SHOW');ForeverFlip.UI.frame:Show()")
        after = after_lua.eval("""(function()
            local F = ForeverFlip; local c = F.Data.char(F.db, F.Engine.owner())
            local n = 0; for _ in pairs(c.positions) do n = n + 1 end
            return table.concat({ F.Scan.last and F.Scan.last.at or 0, F.Scan.last and F.Scan.last.total or 0,
                #F.Deals.list, n, #c.journal }, ' ')
        end)()""")
        self.assertEqual(before, after, 'scan time, auctions, deals, positions and journal after /reload')
        self.assertFalse(after_lua.eval('ForeverFlip.Engine.noSavedData'), 'saved data was read')

    def test_switching_houses_keeps_each_house_apart(self):
        lua = runtime()
        lua.execute((HERE / 'sim.lua').read_text(encoding='utf-8'))
        lua.execute(SESSION % dict(seed=5, ticks=3, commodities=10, items=5, gear=3, start=300, perTick=60, buyers=40, chaos=0))
        result = lua.eval("""(function()
            local F = ForeverFlip
            local allianceScan, allianceDeals = F.Scan.last.at, #F.Deals.list
            fire('AUCTION_HOUSE_CLOSED')
            F.Engine.detectHouse = function() return 'Neutral' end
            fire('AUCTION_HOUSE_SHOW')
            local neutral = (F.Scan.last == nil) and #F.Deals.list == 0 and F.Engine.scope():match('Neutral$') ~= nil
            now = now + 901; F.db.lastScan = 0; fullScan()
            local neutralScan = F.Scan.last.at
            fire('AUCTION_HOUSE_CLOSED')
            F.Engine.detectHouse = function() return nil end
            fire('AUCTION_HOUSE_SHOW')
            local back = F.Scan.last and F.Scan.last.at == allianceScan
            return tostring(neutral) .. ' ' .. tostring(back) .. ' ' .. tostring(neutralScan ~= allianceScan)
        end)()""")
        self.assertEqual(result, 'true true true', 'neutral starts empty, the faction house comes back as it was')


class LargeScanTests(unittest.TestCase):
    def test_a_scan_of_100000_auctions_is_read_in_small_frames(self):
        lua = runtime()
        lua.execute("""ForeverFlip.db.settings.autoScan=false;ForeverFlip.db.settings.sniper=false
        ForeverFlip.Engine.autoVerify=false
        for id = 1000, 1999 do addItem(id, 'Ware ' .. id, 50 + id % 300, id % 3 == 0 and 'item' or 'commodity') end
        for i = 1, 100000 do addAuction(1000 + i % 1000, 100 + (i * 7) % 900, 1 + i % 20) end""")
        began = time.perf_counter()
        frames = lua.eval("""(function()
            local S = ForeverFlip.Scan; assert(S.start()); fire('REPLICATE_ITEM_LIST_UPDATE')
            local n = 0; while S.busy() do run(0.05); n = n + 1 end
            return n
        end)()""")
        took = time.perf_counter() - began
        per_frame_ms = took / frames * 1000
        print(f'\n100 000 auctions: {frames} frames, {took:.1f} s, {per_frame_ms:.2f} ms of work per frame')
        self.assertEqual(lua.eval('ForeverFlip.Scan.last.total'), 100000)
        self.assertLess(per_frame_ms, 12, 'no frame does much more than the 6 ms budget')


if __name__ == '__main__':
    unittest.main()
