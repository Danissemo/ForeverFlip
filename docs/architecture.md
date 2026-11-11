# Architecture

This document is for developers. It describes the modules, how they talk to each other, and the
rules that keep the addon testable.

## Repository layout

```
ForeverFlip/            the addon, exactly as it is installed in Interface/AddOns
  ForeverFlip.toc       metadata and load order
  Bindings.xml          key bindings (loaded by the game automatically)
  *.lua                 modules (see below)
tests/                  automated tests (Python + lupa running Lua 5.1)
  mock.lua              simulated WoW client and WoW Forever auction house
  test_*.py             test suites
tools/build.py          checks and packages a release archive into dist/
tools/devflow.py        local flow: checks before a commit, install into the game and push after it
.githooks/              the git hooks that call tools/devflow.py (git config core.hooksPath .githooks)
sync/                   ForeverFlip Sync helper and the community data aggregator (Python)
docs/                   documentation
.github/                CI, release workflow, issue and PR templates, README images (assets/)
```

## Modules and load order

The TOC loads the files in this order. Every module adds a table to the global `ForeverFlip`
namespace, here written as `F`.

| File | Namespace | Responsibility |
|---|---|---|
| `Util.lua` | `F.Util` | Creates `ForeverFlip`, `F.version`, item keys, legal price steps, money formatting and parsing, safe `itemInfo`. |
| `Locale.lua` | `F.Locale` | English is the code text; Ukrainian translation table; language selection. |
| `Market.lua` | `F.Market` | **Pure maths:** price histogram, usual price, sales between scans, demand, time-of-week pattern, deposit, cut, break-even, deal evaluation. Calls no game API. |
| `Data.lua` | `F.Data` | SavedVariables layout and defaults; per-market and per-character tables; positions, journal, item statistics. |
| `Shopping.lua` | `F.Shopping` | Shopping list, ignored items, shopping deals. |
| `AH.lua` | `F.AH` | **The only file that calls the auction house API** (`C_AuctionHouse`: full scan, browse and key queries, exact searches, buying, bidding, posting, deposits, own auctions; bags; item data). Everything else goes through it. |
| `Scan.lua` | `F.Scan` | Full scan job: request, paced reading, grouping, lot sequences, evaluation, sales tracking, history update, save and restore, hot list. |
| `Deals.lua` | `F.Deals` | The deal list, the exact-search queue, live verification, automatic checks, learning from the player's searches, trust factor, alerts, batch checks. |
| `Sniper.lua` | `F.Sniper` | Fast sniper: browse rounds, key batches, candidate thresholds and queue. |
| `Trade.lua` | `F.Trade` | Buying (quotes, confirmations, outcomes), posting rules and queues, durations, own auctions, undercut checks and cancelling, invoices and sale rate, vendor selling, journal summary. |
| `Mail.lua` | `F.Mail` | Paced looting of auction house mail; reading every auction mail once for the books. |
| `Analytics.lua` | `F.Analytics` | Own results, market lists (cached per scan), realm gold and stock, CSV export. |
| `Merchant.lua` | `F.Merchant` | Merchant → auction house offers, buying from a merchant, what merchants really pay (buyback list). |
| `Disenchant.lua` | `F.Disenchant` | Disenchanting table, own disenchant results, material value (essence forms), disenchant deals. |
| `Crafting.lua` | `F.Crafting` | Recipes from profession windows, merchant prices, recipe profits, materials to the shopping list. |
| `Bids.lua` | `F.Bids` | Bid candidates, checks, placing bids, won and outbid bids. |
| `Share.lua` | `F.Share` | Shared scans: snapshot, text form, addon messages, the realm channel (ask / have / request), receiving and merging. |
| `Raw.lua` | `F.Raw` | Full scans auction by auction for the Sync helper; import of community data. |
| `Core.lua` | `F.Engine` | Event frame, event dispatch, the per-frame update loop, scope and cut, error reporting, key binding actions, `ForeverFlipAPI`, slash commands. |
| `UI.lua` | `F.UI` | Auction house tab and pages, history and export windows, mailbox and merchant buttons, merchant panel, item tooltips, Buy tab marks. |

`Core.lua` and `UI.lua` load last, because they wire the other modules together.

## Runtime flow

```
ADDON_LOADED ──► Data.open(ForeverFlipData) (UI.noSavedData when nothing was read)
             ─► Engine.hookReplicate ─► Locale.apply ─► Engine.applyCut ─► UI.tooltips
             ─► Mail.hook ─► Share.register ─► Raw.importCommunity (ForeverFlip_Shared) ─► Bids.prune
PLAYER_ENTERING_WORLD ──► Share.join (realm channel, 8 seconds later)
AUCTION_HOUSE_SHOW ──► Engine.detectHouse ─► Engine.applyCut ─► Scan.restore(scope) ─► UI.attach

OnUpdate (every frame, Engine.update)
  AH.pump            item data requests, 40 per second
  AH.ready(peek)     watch the throttle, so a stuck "not ready" is noticed
  Scan.auto          start a full scan when allowed
  Scan.step          read (and capture raw lines) / recover / evaluate a portion of the scan
  Trade.stepChecks   own-auction price checks
  Deals.step         search timeouts, queued requests, automatic checks, sniper candidates
  Sniper.step        other addons' browse rows (300 per frame), browse rounds and key batches
  Trade.step         purchase timeouts
  Mail.step          paced mail looting
  Share.step         delayed realm-channel answers, one shared-scan message every 0.3 seconds
  UI.highlightBrowse marks in the game's Buy tab, twice a second
  UI.refresh         at most 4 times a second, only when something changed

Events ──► Engine.handle ──► Scan / Deals / Sniper / Trade / Mail / Share / Crafting / Merchant /
                              Disenchant / UI handlers
  browse results: a gear search waiting for its versions (Deals.onBrowse), else the sniper
  MERCHANT_SHOW / MERCHANT_UPDATE: Merchant.learnBuyback (what merchants really pay)
  UNIT_SPELLCAST_START / LOOT_OPENED: Disenchant.onCast / onLoot (own disenchant results)
C_AuctionHouse.ReplicateItems (hooked): Scan.onOtherScan when another addon starts a full scan
```

`F.Engine.changed()` marks the UI dirty. `F.Engine.notify(key)` sets the status message, which the
UI translates through `MESSAGES` and `F.Locale`.

### Scope and owner

- `Engine.scope()` = `<realm>-<faction>` identifies an auction house (` (HC)` follows the realm on
  hardcore realms). Scan history and deals are stored per scope.
- `Engine.owner()` = `<realm>-<character>` identifies a character. Positions, journal and
  statistics are stored per owner.

### Exact-search scheduling

Only one exact search is in flight at a time (`F.Deals.search`). Requests come from three sources,
in this order:

1. **The player's requests:** clicks, Check price, Check all, own-auction checks. They form
   a FIFO queue (`D.requests`). A repeated key shares the running query, and every distinct callback
   is completed exactly once.
2. **A background retry slot** (`D.backgroundRetry`), used after a throttled or dropped request.
3. **Automatic checks and the sniper's candidates,** started only when nothing else is waiting.

Gear is searched in two steps inside one request: a browse by the item's name lists its item-key
versions (`phase = "browse"`), then each version is searched (`phase = "keys"`) and the rows are
merged. The sniper's browse round in flight gives way (`F.Sniper.yield`).

No search runs while a purchase or a full scan is in progress, also while the scan waits for its
answer (`F.Scan.blocking`): queries sent meanwhile kept the answer from coming in game. Browse and key queries of the sniper
(`F.Sniper.query`) are separate from exact searches. They are sent only when no exact search is in
flight or queued and no candidate is waiting.

## Design rules

1. **One gateway to the game.** Only `AH.lua` (and the UI, for frames) touches game APIs. Tests
   replace these APIs with `tests/mock.lua`.
2. **Pure maths in `Market.lua`.** Deal rules are plain functions of their inputs, so they can be
   tested exhaustively.
3. **Nothing heavy in a single frame.** Scans are read and evaluated under a per-frame time budget
   (`debugprofilestop`); deal pages prepare lazily.
4. **No automatic trading.** Every protected action (buy, post, cancel, use a container item, take
   mail) is called from a click handler.
5. **Fail soft.** Every event and frame handler runs under `xpcall`. API calls that may be missing
   on WoW Forever are guarded (`C_Item.GetItemInfo` vs `GetItemInfo`,
   `C_MerchantFrame.GetItemInfo` vs `GetMerchantItemInfo`, `SendSellSearchQuery`).
6. **Bounded storage.** Every saved collection has a cap or an expiry:

   | Data | Limit |
   |---|---|
   | Journal | 500 entries |
   | Errors | 20 |
   | Invoices | 200 |
   | Scan history | pruned after 14 days without the item |
   | Daily records | 14 days |
   | Lots per item | 300 |
   | Waiting pool | 6000 items |
   | Cheapest rows per item | 40 |
   | Bid candidates | 100 |
   | Gold records | 60 days |
   | Bids | 2 days |

## Adding a feature

- Put calculations in `Market.lua` (or a new pure module) and test them directly.
- Put new game API calls in `AH.lua` and add matching fakes to `tests/mock.lua`.
- Every visible string goes through `L(...)`; add the Ukrainian text to `Locale.lua`.
  `tests/test_locale.py` fails when a string written as `L("...")` has no translation.
- For a release, see [CONTRIBUTING.md](../CONTRIBUTING.md#releasing).
