"""Core.lua: event wiring, the frame update, key bindings and ForeverFlipAPI (review fixes)."""

import unittest

import lupa.lua51 as lupa

from test_addon import ADDON, HERE, SETUP, runtime


def load(before=''):
    """The addon in a fresh client; `before` runs after the fake client, before the addon files."""
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute((HERE / 'mock.lua').read_text(encoding='utf-8'))
    if before:
        lua.execute(before)
    for line in (ADDON / 'ForeverFlip.toc').read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if line.endswith('.lua'):
            lua.execute((ADDON / line).read_text(encoding='utf-8'))
    return lua


SCAN = SETUP + '''local F=ForeverFlip;local E,D,T,S,UI=F.Engine,F.Deals,F.Trade,F.Scan,F.UI
fullScan()
'''


class BuyNextKeyTests(unittest.TestCase):
    def test_hidden_window_on_the_vendor_page_buys_the_best_deal(self):
        # The player went to the game's Buy tab from To vendor: the hidden page keeps its filter.
        runtime().execute(SCAN + '''UI.show('deals:vendor');UI.frame:Hide()
        local best=D.best();assert(best)
        E.keyBuyNext()
        assert(E.message~='no_deal',tostring(E.message))
        assert(T.run==nil and UI.selected==best.key,tostring(UI.selected))''')

    def test_vendor_page_on_screen_runs_the_vendor_run(self):
        runtime().execute(SCAN + '''UI.show('deals:vendor');UI.refresh()
        E.keyBuyNext()
        assert(T.run and E.message=='run_checking',tostring(E.message))''')


class RefreshTests(unittest.TestCase):
    def test_closed_auction_house_stops_the_one_second_repaint(self):
        runtime().execute(SCAN + '''
        -- The game's IsVisible: the window and every parent are shown.
        UI.frame.IsVisible=function(self)
          local f=self;while f do if not f.shown then return false end;f=rawget(f,'parent') end;return true
        end
        UI.show('sell');UI.refresh()
        local paints,refresh=0,UI.refresh
        UI.refresh=function(...) paints=paints+1;return refresh(...) end
        run(5);assert(paints>=4,'the window on screen is repainted every second: '..paints)
        AuctionHouseFrame:Hide();fire('AUCTION_HOUSE_CLOSED');run(0.5)
        assert(UI.frame:IsShown(),'the window keeps its own flag inside the closed auction house')
        paints=0;run(5);assert(paints==0,'nothing on screen to repaint: '..paints)''')


class SavedDataDialogTests(unittest.TestCase):
    def test_no_saved_data_dialog_uses_the_client_language(self):
        lua = load('''function GetLocale() return "ukUA" end
        StaticPopupDialogs={};function StaticPopup_Show(name) popup=StaticPopupDialogs[name] end''')
        lua.execute('''ForeverFlipData=nil;fire('ADDON_LOADED','ForeverFlip')
        local L=ForeverFlip.Locale
        assert(ForeverFlip.Engine.noSavedData and popup)
        assert(popup.button1==L.uk['Reload'] and popup.button2==L.uk['Continue'],popup.button1)
        assert(not popup.text:find('found no saved data',1,true),popup.text)''')


class ApiDealTests(unittest.TestCase):
    def test_deals_of_a_closed_neutral_house_are_not_reported(self):
        runtime(open_ah=False).execute(SETUP + '''local F,E,API=ForeverFlip,ForeverFlip.Engine,ForeverFlipAPI
        function GetSubZoneText() return 'Ironforge' end
        fire('AUCTION_HOUSE_SHOW');F.UI.frame:Show();fullScan()
        assert(API.GetDeal(10)=='vendor')
        fire('AUCTION_HOUSE_CLOSED')
        assert(API.GetDeal(10)=='vendor','the last scan of this house stays listed')
        now=now+1000
        function GetSubZoneText() return 'Gadgetzan' end
        addAuction(30,1000,1) -- a Linen Bag below its vendor price
        fire('AUCTION_HOUSE_SHOW');fullScan()
        assert(E.scope()=='Realm-Neutral' and API.GetDeal(30)=='vendor')
        fire('AUCTION_HOUSE_CLOSED')
        assert(E.scope()=='Realm-Alliance' and F.Deals.scope=='Realm-Neutral')
        assert(API.GetDeal(30)==nil and API.GetDeal(10)==nil,'the neutral deals are not on sale here')''')


class RecipeTests(unittest.TestCase):
    RECIPES = SETUP + '''local F=ForeverFlip
    local ready,reads=false,0
    C_TradeSkillUI={
      GetAllRecipeIDs=function() reads=reads+1;if ready then return {2963} end;return {} end,
      GetRecipeSchematic=function() return {name='Bolt of Linen Cloth',outputItemID=50,quantityMin=1,
        reagentSlotSchematics={{required=true,quantityRequired=2,reagents={{itemID=10}}}}} end,
    }
    local function learned()
      local n=0;for _ in pairs(F.Data.char(F.db,F.Engine.owner()).recipes or {}) do n=n+1 end;return n
    end
    '''

    def test_list_loaded_right_after_the_window_opens_is_read(self):
        runtime().execute(self.RECIPES + '''fire('TRADE_SKILL_SHOW')
        assert(reads==1 and learned()==0,'the list is still empty when the window opens')
        run(0.5);ready=true;fire('TRADE_SKILL_LIST_UPDATE')
        run(1);assert(reads==2 and learned()==1,reads)''')

    def test_a_burst_of_list_updates_is_read_once_after_it(self):
        runtime().execute(self.RECIPES + '''ready=true;fire('TRADE_SKILL_SHOW');assert(reads==1)
        for _=1,20 do fire('TRADE_SKILL_LIST_UPDATE');run(0.05) end
        assert(reads==1,'not while the events keep coming: '..reads)
        run(1);assert(reads==2,reads)
        run(3);fire('TRADE_SKILL_LIST_UPDATE');assert(reads==3,'two seconds later it is read at once')''')


class HouseChangeTests(unittest.TestCase):
    def test_price_checks_are_forgotten_when_another_house_opens(self):
        runtime().execute(SETUP + '''local F=ForeverFlip
        local forgot=0
        F.Trade.forgetHouse=function() forgot=forgot+1 end
        fire('AUCTION_HOUSE_CLOSED');fire('AUCTION_HOUSE_SHOW')
        assert(forgot==0,'the same house again keeps its checks')
        fire('AUCTION_HOUSE_CLOSED');function GetSubZoneText() return 'Gadgetzan' end;fire('AUCTION_HOUSE_SHOW')
        assert(F.Engine.scope()=='Realm-Neutral' and forgot==1)
        fire('AUCTION_HOUSE_CLOSED');fire('AUCTION_HOUSE_SHOW');assert(forgot==1)
        fire('AUCTION_HOUSE_CLOSED');function GetSubZoneText() return 'Ironforge' end;fire('AUCTION_HOUSE_SHOW')
        assert(F.Engine.scope()=='Realm-Alliance' and forgot==2)
        F.Trade.forgetHouse=nil
        fire('AUCTION_HOUSE_CLOSED');function GetSubZoneText() return 'Gadgetzan' end;fire('AUCTION_HOUSE_SHOW')''')

    def test_checked_price_of_another_house_is_not_used(self):
        lua = runtime()
        if not lua.eval('ForeverFlip.Trade.forgetHouse'):
            self.skipTest('Trade.forgetHouse is not there yet')
        lua.execute(SETUP + '''local T=ForeverFlip.Trade
        T.prices['c:10']={rows={{unit=60,qty=5}},at=time()}
        assert(T.freshCheapest('c:10')==60)
        fire('AUCTION_HOUSE_CLOSED');fire('AUCTION_HOUSE_SHOW')
        assert(T.freshCheapest('c:10')==60,'the same house keeps its checks')
        fire('AUCTION_HOUSE_CLOSED');function GetSubZoneText() return 'Gadgetzan' end;fire('AUCTION_HOUSE_SHOW')
        assert(T.freshCheapest('c:10')==nil,'a check of the Alliance house is no price at the neutral one')''')


class DroppedMessageTests(unittest.TestCase):
    def test_sniper_hears_a_dropped_message_while_the_search_is_still_in_flight(self):
        runtime().execute(SCAN + '''local seen,calls
        F.Sniper.onDropped=function() calls=(calls or 0)+1;seen=D.search~=nil end
        D.verify('c:10');assert(D.search)
        fire('AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED')
        assert(calls==1 and seen==true and D.search==nil)
        F.Sniper.onDropped=nil
        fire('AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED')''')


class EventNoiseTests(unittest.TestCase):
    # Every frame records its registrations: event -> the unit, or 'all'.
    RECORD = '''local create=CreateFrame
    CreateFrame=function(...)
      local w=create(...)
      rawset(w,'registered',{})
      w.RegisterEvent=function(self,e) rawget(self,'registered')[e]='all' end
      w.RegisterUnitEvent=UNIT_EVENTS and function(self,e,unit) rawget(self,'registered')[e]=unit end
      return w
    end
    '''
    CASTS = ('UNIT_SPELLCAST_START', 'UNIT_SPELLCAST_SUCCEEDED', 'UNIT_SPELLCAST_INTERRUPTED',
             'UNIT_SPELLCAST_FAILED')

    def test_casts_are_registered_for_the_player_only(self):
        registered = load('UNIT_EVENTS=true\n' + self.RECORD).eval('ForeverFlip.frame.registered')
        for event in self.CASTS:
            self.assertEqual(registered[event], 'player', event)
        self.assertEqual(registered['LOOT_OPENED'], 'all')

    def test_casts_are_registered_for_every_unit_without_register_unit_event(self):
        registered = load('UNIT_EVENTS=false\n' + self.RECORD).eval('ForeverFlip.frame.registered')
        for event in self.CASTS:
            self.assertEqual(registered[event], 'all', event)

    def test_other_units_casts_do_not_repaint_the_window(self):
        runtime().execute(SCAN + '''local casts=0
        F.Disenchant.onCast=function() casts=casts+1 end
        E.dirty=false
        fire('UNIT_SPELLCAST_START','nameplate3','Cast-1',133)
        fire('UNIT_SPELLCAST_SUCCEEDED','nameplate3','Cast-1',133)
        assert(not E.dirty and casts==0)
        fire('UNIT_SPELLCAST_START','player','Cast-2',13262);assert(casts==1)''')

    def test_only_item_loads_the_scan_waits_for_repaint_the_window(self):
        runtime().execute(SCAN + '''E.dirty=false
        fire('ITEM_DATA_LOAD_RESULT',123456,true) -- another addon's item
        assert(not E.dirty)
        -- A Linen Bag above its vendor price: no deal, but the summary counts its vendor price.
        D.remove('i:30');S.last.waitVendor[30]={{key='i:30',kind='item',id=30,rows={{unit=5000,qty=1}}}}
        E.dirty=false
        fire('ITEM_DATA_LOAD_RESULT',30,true)
        assert(not D.get('i:30') and E.dirty)
        S.last.waitVendor[30]={{key='i:30',kind='item',id=30,rows={{unit=100,qty=1}}}};E.dirty=false
        fire('ITEM_DATA_LOAD_RESULT',30,true);assert(D.get('i:30') and E.dirty)''')


class FrameUpdateTests(unittest.TestCase):
    def test_frame_handler_adds_no_garbage_to_the_update(self):
        runtime(open_ah=False).execute(SETUP + '''local F=ForeverFlip
        local handler=F.frame.scripts.OnUpdate
        local function bytes(fn)
          collectgarbage('collect');collectgarbage('stop')
          local before=collectgarbage('count')
          for _=1,20000 do fn() end
          local used=(collectgarbage('count')-before)*1024/20000
          collectgarbage('restart')
          return used
        end
        for _=1,100 do handler(F.frame,0.016) end
        local viaHandler=bytes(function() handler(F.frame,0.016) end)
        local direct=bytes(function() F.Engine.update(0.016) end)
        assert(viaHandler-direct<16,viaHandler..' bytes per frame against '..direct)''')


if __name__ == '__main__':
    unittest.main()
