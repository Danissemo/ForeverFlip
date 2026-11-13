"""Review fixes in AH.lua, Scan.lua and Raw.lua: a full-scan row read once with raw scans on, and the
player's own lots in browse rows."""

import unittest

from test_addon import SETUP, run, runtime

# A house read over several frames (400 rows a frame in the tests): bids, the player's own lots,
# gear with endings, and an item whose data loads only after its rows were read (read again later).
HOUSE = SETUP + '''local F,S=ForeverFlip,ForeverFlip.Scan
F.db.settings.rawScans=%s
enableTimeLeft()
addItem(40,'Late Thing',0,'item')
items[40].cached=false
for i=1,1500 do
    local id=({10,20,30,40})[i%%4+1]
    local name=id==20 and ((i%%3==0) and 'Northern Shortsword of Healing' or 'Northern Shortsword, Heavy') or nil
    local a=addAuction(id,100+(i%%50)*7,1+i%%5,(i%%31==0) and 'Me' or 'Seller'..(i%%17),name)
    a.timeLeft=1+i%%4
    if i%%5==0 then a.minBid=50+i%%30 end
    if i%%13==0 then a.bid=40+i%%20; a.increment=5 end
end
reads={info={},link={},left={}}
local AH=C_AuctionHouse
local function counted(name,fn)
    return function(i)
        if S.job and S.job.state=='reading' then reads[name][i]=(reads[name][i] or 0)+1 end
        return fn(i)
    end
end
AH.GetReplicateItemInfo=counted('info',AH.GetReplicateItemInfo)
AH.GetReplicateItemLink=counted('link',AH.GetReplicateItemLink)
AH.GetReplicateItemTimeLeft=counted('left',AH.GetReplicateItemTimeLeft)
assert(S.start()); fire('REPLICATE_ITEM_LIST_UPDATE')
while S.busy() do
    if S.job.state~='reading' then items[40].cached=true end
    run(0.05)
end
'''

# What the scan found, in a fixed order: the summary of the scan, deals, bid candidates, history.
DIGEST = '''local F=ForeverFlip
local function ser(v,out)
    if type(v)=='table' then
        local keys={}
        for k in pairs(v) do keys[#keys+1]=k end
        table.sort(keys,function(a,b)
            if type(a)~=type(b) then return type(a)<type(b) end
            return a<b
        end)
        out[#out+1]='{'
        for _,k in ipairs(keys) do out[#out+1]=tostring(k)..'='; ser(v[k],out); out[#out+1]=',' end
        out[#out+1]='}'
    else
        out[#out+1]=tostring(v)
    end
    return out
end
local last=F.Scan.last
local deals,bids={},{}
for _,d in ipairs(F.Deals.list) do deals[#deals+1]=d.key..'='..tostring(d.mode)..'/'..d.qty..'/'..d.cost end
for _,c in ipairs(F.Bids.candidates) do bids[#bids+1]=c.key..'@'..c.bid end
return table.concat(ser({read=last.read,skipped=last.skipped,own=last.own,listed=last.listed,unread=last.unread,
    ownUnits=last.ownUnits,deals=deals,bids=bids,history=F.Data.market(F.db,F.Engine.scope()).history},{}))
'''


class RawReadTests(unittest.TestCase):
    def test_each_row_is_read_once_with_raw_scans_on(self):
        run(HOUSE % 'true' + '''assert(#S.last.groups['i:40'].rows>0,'the late item was read again')
        for i=0,#auctions-1 do
            for _,name in ipairs({'info','link','left'}) do
                local n=reads[name][i] or 0
                assert(n==1,'row '..i..': '..name..' asked '..n..' times')
            end
        end''')

    def test_raw_lines_and_scan_results_stay_the_same(self):
        lua = runtime()
        lua.execute(HOUSE % 'true' + '''-- the lines as the format says, from the auctions themselves
        local lines,seal={},0
        for i,a in ipairs(auctions) do
            local it=items[a.item]
            local kind=a.item==40 and '' or it.commodity and 'c' or it.equipment and 'g' or 'i'
            lines[i]=table.concat({a.item,a.count,a.buyout,a.minBid or 0,a.bid or 0,(a.timeLeft or 4)-1,
                a.owner=='Me' and 1 or 0,kind,kind=='g' and a.name:gsub(',',' ') or ''},',')
            seal=F.Raw.chain(seal,lines[i])
        end
        local s=ForeverFlipRaw.scans[1]
        assert(s.count==#auctions,s.count)
        assert(s.rows==table.concat(lines,'\\n'),'the lines changed')
        assert(s.seal==F.Raw.chain(seal,s.scope..'|'..s.at..'|'..s.count),'the seal changed')''')
        with_raw = lua.execute(DIGEST)
        lua = runtime()
        lua.execute(HOUSE % 'false')
        self.assertIsNone(lua.eval('ForeverFlipRaw'))
        self.assertEqual(with_raw, lua.execute(DIGEST))


class BrowseOwnLotTests(unittest.TestCase):
    def test_the_players_own_cheap_lot_in_a_browse_leaves_todays_cheapest(self):
        run('''local F=ForeverFlip
        F.Engine.autoVerify=false;F.db.settings.autoScan=false;F.db.settings.sniper=false
        enableBrowse(1000)
        addItem(10,'Linen Cloth',0,'commodity')
        for i=1,6 do addAuction(10,100,5,'Other') end -- 30 cloth at 1 silver by other sellers
        local own=addAuction(10,40,10,'Me') -- the player's own 10 cloth at 40c
        fullScan()
        local h=F.Data.market(F.db,F.Engine.scope()).history['c:10']
        local today=h.days[#h.days]
        assert(today.min==100,'the scan leaves the own lot out: '..tostring(today.min))
        -- The player browses in the game's Buy tab (the sniper is off): its rows are read too.
        local function browse()
            C_AuctionHouse.SendBrowseQuery({searchString=''}); browseAnswer(); run(0.2)
            for _,r in ipairs(F.AH.browseResults()) do if r.id==10 then return r end end
        end
        local row=browse()
        assert(today.min==100,'lowered by the own lot: '..tostring(today.min))
        assert(row.minPrice==40 and row.containsOwnerItem,'the row tells the item has an own lot')
        -- Without the own lot, a cheaper lot of another seller still lowers it.
        for i,a in ipairs(auctions) do if a==own then table.remove(auctions,i) end end
        addAuction(10,60,5,'Other')
        row=browse()
        assert(row.minPrice==60 and not row.containsOwnerItem)
        assert(today.min==60,tostring(today.min))''')


if __name__ == '__main__':
    unittest.main()
