"""Data.fitSave: the saved file stays readable by the client's Lua 5.1 (262143 constants at most)."""

import unittest

from test_addon import runtime

# Writes the saved globals as the game does (one chunk of table constructors) and loads the text
# back with the client's Lua: true, or false and the error.
WRITE = r'''
local function lit(v)
  if type(v) == 'string' then return string.format('%q', v) end
  if type(v) == 'number' then return string.format('%.17g', v) end
  return tostring(v)
end
local function write(t, out)
  out[#out + 1] = '{\n'
  local n = #t
  for i = 1, n do
    local v = t[i]
    if type(v) == 'table' then write(v, out) else out[#out + 1] = lit(v) end
    out[#out + 1] = ', -- [' .. i .. ']\n'
  end
  for k, v in pairs(t) do
    if type(k) ~= 'number' or k < 1 or k > n or k ~= math.floor(k) then
      out[#out + 1] = '[' .. lit(k) .. '] = '
      if type(v) == 'table' then write(v, out) else out[#out + 1] = lit(v) end
      out[#out + 1] = ',\n'
    end
  end
  out[#out + 1] = '}'
end
function savedText(data, raw)
  local out = { 'ForeverFlipData = ' }
  write(data, out)
  out[#out + 1] = '\nForeverFlipRaw = '
  if raw then write(raw, out) else out[#out + 1] = 'nil' end
  return table.concat(out)
end
function loads(text)
  local f, err = loadstring(text)
  return f ~= nil, err
end
-- A house of `items` items whose sales estimates are all different fractions, as in game.
function bigHouse(items, at)
  local F = ForeverFlip
  local m = F.Data.market(F.db, 'Realm-Alliance')
  for i = 1, items do
    m.history['i:' .. i] = {
      scan = { at = at + i, market = 1000 + i, low = 900 + i },
      lotsAt = at + i,
      sales = { hours = i / 7, watched = i / 11, pairsSeen = i / 13, rates = { i / 17, i / 19 } },
      t = { b = i / 3, w = { i / 23, i / 29 }, p = { i / 31 } },
    }
  end
  return m
end
'''


class SaveLimitTests(unittest.TestCase):
    def test_a_file_past_the_limit_is_cut_back_to_one_the_client_reads(self):
        lua = runtime()
        lua.execute(WRITE)
        lua.execute(r'''
        local F, D = ForeverFlip, ForeverFlip.Data
        local m = bigHouse(30000, 1000000)
        -- unrounded, this is the file the client refused in game
        local ok, err = loads(savedText(F.db))
        assert(not ok and err:find('constant table overflow'), tostring(err))
        F.Data.addPosition(F.Data.char(F.db, 'Realm-Lasqa'), 'i:1', 'Held', 1, 100, 'flip', 200, 5)
        local n, dropped = D.fitSave(F.db, nil, 60000, 50000)
        assert(n <= 50000 and dropped > 0, n .. ' ' .. dropped)
        assert(n == D.countConstants(F.db), 'the count it kept is the real one')
        assert(m.history['i:1'], 'an item the player holds stays')
        assert(not m.history['i:2'] and m.history['i:30000'], 'the item seen longest ago goes first')
        assert(loads(savedText(F.db)))''')

    def test_rounding_alone_keeps_every_item(self):
        lua = runtime()
        lua.execute(WRITE)
        lua.execute(r'''
        local F, D = ForeverFlip, ForeverFlip.Data
        local m = bigHouse(30000, 1000000)
        local n, dropped = D.fitSave(F.db)
        assert(dropped == 0 and n <= D.SAVE_LIMIT, n .. ' ' .. dropped)
        assert(m.history['i:2'] and loads(savedText(F.db)))
        local s = m.history['i:7000'].sales
        assert(s.hours == 1000 and math.abs(m.history['i:7'].sales.watched - 7 / 11) < 0.001, s.hours)''')

    def test_round4_keeps_four_significant_digits(self):
        lua = runtime()
        lua.execute(r'''
        local r = ForeverFlip.Data.round4
        assert(r(4.4394340882289) == 4.439 and r(933.28240391891) == 933.3 and r(0.99703014391463) == 0.997)
        assert(r(1794890526) == 1794890526 and r(945) == 945 and r(0) == 0, 'whole numbers stay')
        assert(r(r(1.0043456654039)) == r(1.0043456654039), 'rounding again changes nothing')''')

    def test_logout_fits_the_file_and_tells_the_player_next_time(self):
        lua = runtime()
        lua.execute(WRITE)
        lua.execute(r'''
        local F, D = ForeverFlip, ForeverFlip.Data
        bigHouse(100, 1000000)
        D.SAVE_LIMIT, D.SAVE_TARGET = 300, 250
        fire('PLAYER_LOGOUT')
        assert(F.db.fitDropped and F.db.fitDropped.items > 0, 'dropped at logout')
        assert(D.countConstants(F.db, ForeverFlipRaw) <= 300)
        ForeverFlipData = F.db
        fire('ADDON_LOADED', 'ForeverFlip')
        assert(not F.db.fitDropped, 'told once')
        local told
        for _, e in ipairs(F.Log.history) do
          if e.text:find('limit', 1, true) then told = true end
        end
        assert(told, 'the player is told in the log')''')


if __name__ == '__main__':
    unittest.main()
