# Architecture

This document is for developers. It describes the modules, how they talk to each other, and the
rules that keep the addon testable.

## Repository layout

```
ForeverFlip/            the addon, exactly as it is installed in Interface/AddOns
  ForeverFlip.toc       metadata and load order
  *.lua                 modules (see below)
tests/                  automated tests (Python + lupa running Lua 5.1)
  mock.lua              simulated WoW client and WoW Forever auction house
  test_*.py             test suites
tools/build.py          checks and packages a release archive into dist/
docs/                   documentation
.github/                CI, release workflow, issue and PR templates
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
| `AH.lua` | `F.AH` | **The only file that calls the auction house API** (`C_AuctionHouse`, bags, item data). Everything else goes through it. |
| `Scan.lua` | `F.Scan` | Full scan job: request, paced reading, grouping, evaluation, history update, save and restore, sniper list. |
| `Deals.lua` | `F.Deals` | The deal list, the exact-search queue, live verification, automatic checks, sniper, alerts, batch checks. |
| `Trade.lua` | `F.Trade` | Buying (quotes, confirmations, outcomes), posting, own auctions, undercut checks, cancelling, vendor selling, journal summary. |
| `Mail.lua` | `F.Mail` | Paced looting of auction house mail. |
| `Analytics.lua` | `F.Analytics` | Own results and market lists, cached per scan. |
| `Merchant.lua` | `F.Merchant` | Merchant → auction house offers and buying from a merchant. |
| `Core.lua` | `F.Engine` | Event frame, event dispatch, the per-frame update loop, error reporting, slash commands. |
| `UI.lua` | `F.UI` | Auction house tab and pages, mailbox and merchant buttons, merchant panel, item tooltips. |

`Core.lua` and `UI.lua` load last, because they wire the other modules together.

## Runtime flow

```
ADDON_LOADED ──► Data.open(ForeverFlipData) ─► Locale.apply ─► UI.tooltips
AUCTION_HOUSE_SHOW ──► Scan.restore(scope) ─► UI.attach (create tab and pages)

OnUpdate (every frame, Engine.update)
  AH.pump            item data requests, 40 per second
  Scan.auto          start a full scan when allowed
  Scan.step          read / recover / evaluate a portion of the scan
  Trade.stepChecks   own-auction price checks
  Deals.step         search timeouts, queued requests, automatic checks, sniper
  Trade.step         purchase timeouts
  Mail.step          paced mail looting
  UI.refresh         at most 4 times a second, only when something changed

Events ──► Engine.handle ──► Scan / Deals / Trade / Mail / UI handlers
```

`F.Engine.changed()` marks the UI dirty. `F.Engine.notify(key)` sets the status message, which the
UI translates through `MESSAGES` and `F.Locale`.

### Scope and owner

- `Engine.scope()` = `<realm>-<faction>` identifies an auction house. Scan history and deals are
  stored per scope.
- `Engine.owner()` = `<realm>-<character>` identifies a character. Positions, journal and
  statistics are stored per owner.

### Exact-search scheduling

Only one exact search is in flight at a time (`F.Deals.search`). Requests come from three sources,
in this order:

1. **The player's requests:** clicks, Check price, Check all statuses, own-auction checks. They form
   a FIFO queue (`D.requests`). A repeated key shares the running query, and every distinct callback
   is completed exactly once.
2. **A background retry slot** (`D.backgroundRetry`), used after a throttled or dropped request.
3. **Automatic checks and the sniper,** started only when nothing else is waiting.

No search runs while a full scan or a purchase is in progress.

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
6. **Bounded storage.** Journal 500 entries, errors 20, scan history pruned after 14 days, daily
   history 5 days, waiting pool 6000 items, cheapest rows 40 per item.

## Adding a feature

- Put calculations in `Market.lua` (or a new pure module) and test them directly.
- Put new game API calls in `AH.lua` and add matching fakes to `tests/mock.lua`.
- Every visible string goes through `L(...)`; add the Ukrainian text to `Locale.lua`.
  `tests/test_locale.py` fails when a string written as `L("...")` has no translation.
- For a release, see [CONTRIBUTING.md](../CONTRIBUTING.md#releasing).
