# T13 / T15 — The addon as all-Lua, with capability adapters (proposal)

Status: **implemented** (T13, 16 November 2026), all five steps; see "Implemented" at the end.
[docs/architecture.md](../architecture.md) describes the current Core/Modules/UI layout in 3.1.0.
The paths, line counts and module names below are historical proposal snapshots, not a live file
inventory. The sections below are the proposal as written.

## What the code is today (checked)

- Everything that runs inside the game is already Lua 5.1 on the game's API: 20 files under
  `ForeverFlip/`, about 24,300 lines. There is no compiled or external component inside the
  addon. ForeverFlip Sync (`sync/`, Python) is a separate desktop helper and stays outside this
  plan, as the spec says.
- The only file that calls `C_AuctionHouse` for queries and actions is `AH.lua`. `Core.lua` also
  touches it once: `hooksecurefunc(C_AuctionHouse, "ReplicateItems", ...)`, a passive hook that
  notices another addon's full scan. It calls nothing.
- `Market.lua` calls no game API, but it reaches other modules at run time:
  `F.Trade.saleChances` (Sure maths), `F.AH.kindOf`, `F.AH.vendorPrice` and `F.Share`. These are
  the coupling points to cut first.

## Dependency map (who reads whom, from the code)

| Module | Uses |
|---|---|
| Util, Locale | — |
| Market | AH, Deals, Disenchant, Engine, Share, Trade, Util |
| Data | Engine, Scan, Util |
| AH | Deals, Engine, Market, Merchant, Scan, Util |
| Scan | AH, Analytics, Bids, Data, Deals, Engine, Market, Raw, Share, Sniper, Trade, Util |
| Deals | AH, Data, Disenchant, Engine, Locale, Market, Scan, Shopping, Sniper, Trade, UI, Util |
| Sniper | AH, Data, Deals, Disenchant, Engine, Market, Scan, Shopping, Trade, Util |
| Trade | AH, Bids, Data, Deals, Engine, Locale, Market, Merchant, Scan, Shopping, Sniper, UI, Util |
| Crafting | AH, Data, Engine, Market, Shopping, Trade, Util |
| Disenchant | Data, Engine, Market, Util |
| Merchant | AH, Crafting, Data, Deals, Engine, Market, Trade, Util |
| Analytics | Data, Engine, Market, Scan, Share, Util |
| Share | AH, Analytics, Data, Engine, Market, Scan, Util |
| Raw | AH, Data, Share, Util |
| Bids | AH, Data, Deals, Engine, Market, Scan, Shopping, Sniper, Trade, UI, Util |
| Mail | AH, Bids, Engine, Locale, Trade, Util |
| Shopping | AH, Deals, Engine, Market, Util |
| Core | everything (wiring) |
| UI | everything (pages) |

The cycles that matter: Market ↔ Trade/AH/Deals, and Deals ↔ Trade ↔ UI. They work because Lua
resolves `F.X` at call time, but they make a module impossible to test or replace alone.

## Target layers

1. **Pure** — `Util`, `Locale`, `Market` (with the Sure maths moved from `Trade.saleChances` into
   `Market`). No reference to a game-facing module; inputs are passed in.
2. **Storage** — `Data` (layout, versioned schema, migrations), `Raw` (raw scans).
3. **Adapters** — `AH` (auction house), plus small capability adapters for what differs between
   clients: spells (`C_SpellBook.IsSpellKnown` / fallback), items (`C_Item.*`), professions,
   chat. Each answers "can I?" (`caps.fullScan`, `caps.commodities`, `caps.replicateCooldown`)
   instead of the rest of the code guessing the client. WoW Forever (Interface 16001) is the only
   verified target; another client gets an adapter only after its API is checked against the
   matching wow-ui-source branch (T15).
4. **Services** — `Scan`, `Deals`, `Sniper`, `Trade`, `Bids`, `Mail`, `Crafting`, `Disenchant`,
   `Merchant`, `Analytics`, `Share`: they reach the game only through layer 3, and the screen
   only through notifications (`F.Engine.notify("deals-changed")`) instead of `F.UI.*`.
5. **UI** — `UI.lua` split into page files (Deals, Selling, Crafting, Analytics, Settings,
   Tooltip) sharing a small widgets file.

## Migration, step by step (each step ships alone, suite green, no data change)

1. Move `saleChances` into `Market`; `Trade` calls it there. Pass `kindOf`/`vendorPrice` results
   into `Market` instead of `Market` calling `AH`.
2. Add `Engine.notify/listen`; replace `F.UI.*` calls in Deals/Trade/Bids with notifications.
3. Introduce the adapters with the current calls moved verbatim; add `caps`.
4. Split `UI.lua` by page, one page per change (7,800 lines; the tests drive it by names that
   must stay).
5. Data: a schema version field and one migration function per version, run in `Data.open`,
   with SavedVariables backed up before installing.

No step deletes SavedVariables, history or settings; the tests in `tests/` are the safety net and
gain one test per adapter (`caps` on a client without `C_AuctionHouse.ReplicateItems`).

## Decision needed

Start with steps 1–3 (small, internal), and split `UI.lua` only after the open UI items of the
review are done, so code being changed is not moved at the same time.

## Implemented (T13, 16 November 2026)

Each step left the whole suite green (1276 tests before; 1289 in 107 modules after step 5).

1. **Sure maths in Market.** `erf`, `CHANCE_TERMS`, `saleChances` and `expectedSold` moved from
   `Trade.lua` to `Market.lua`; `Trade.saleChances` and `Trade.expectedSold` are aliases. Market
   no longer reads `F.AH`, `F.Trade`, `F.Disenchant`, `F.Engine`, `F.Share` or `F.db`: it asks
   `M.env` (kind, vendor price, deposit, sale rate, durations, disenchant value, clock), which
   `Core` fills with `M.use` (`Engine.wireMarket`) through closures that look the module up at
   call time.
2. **Events.** `F.Engine.notify` already was the status message, so the events are
   `F.Engine.emit/listen`. The services read the window through `F.Engine.screen()` and select a
   row with `emit("select", key)`; Deals, Trade, Bids, Scan, Sniper, AH and Mail no longer
   mention `F.UI`. Refresh points are unchanged (`Engine.changed`).
3. **Compat.lua** (after Util in the TOC): `caps` read live, and the spell, item, bag and
   merchant wrappers moved verbatim from Crafting, Disenchant, Util, Trade, Merchant and UI.
   Without `C_AuctionHouse.ReplicateItems` a full scan answers "unavailable" and the button reads
   "No full scan".
4. **UI split.** `UI.lua` (9,341 lines) became `UI.lua` and ten page files (UIDeals, UISelling,
   UIAnalytics, UICrafting, UIJournal, UISettings, UIStatus, UITab, UITooltip, UIMerchant), moved
   in the original order. Shared file locals go through `UI.shared`. Public names are unchanged.
5. **Schema.** `db.schemaVersion` and `Data.MIGRATIONS`: 1 the vendor margin reset, 2 the sales
   model clean-up. Both keep their old markers, so they are idempotent. `STATS_VERSION` is
   unchanged.

What remains:

- Crafting's `C_TradeSkillUI` calls, Share's `C_ChatInfo` calls and the Merchant buyback reads
  stay in their modules. `Compat.caps` reports them (`tradeSkill`, `addonMessages`), but their
  calls were not moved.
- Services still call each other directly (Deals, Trade, Sniper, Bids). Only the UI edge became
  events.
- `Core` is the wiring layer and still calls `F.UI`.
- A widgets file separate from `UI.lua` was not made. The widgets stay at the top of `UI.lua`.
- Nothing here is checked in the game yet.
