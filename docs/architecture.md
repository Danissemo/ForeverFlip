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
| `Compat.lua` | `F.Compat` | **Client capabilities:** `caps` (fullScan, commodities, replicateCooldown, spellBook, item, container, tradeSkill, merchantFrame, addonMessages; read live) and the wrappers whose calls differ between clients (spells, item info, item count and icon, bags, merchant items). The documented `C_*` function first, the bare deprecated global only when its namespace is missing. Never calls `C_AuctionHouse`, only asks whether its functions exist. |
| `Locale.lua` | `F.Locale` | English is the code text; Ukrainian translation table; language selection. |
| `Market.lua` | `F.Market` | **Pure maths:** price histogram, usual price, sales between scans, demand, time-of-week pattern, deposit, cut, break-even, deal evaluation, the Sure maths (`saleChances`, `expectedSold`; `Trade` keeps the names as aliases). Calls no game API and no game-facing module: what it needs from them (item kind, vendor price, deposit, sale rate, durations, disenchant value, clock) comes through `M.env`, which `Core` sets with `M.use` (`Engine.wireMarket`). Unwired, it answers with defaults. |
| `Data.lua` | `F.Data` | SavedVariables layout and defaults; schema version and ordered migrations (`D.MIGRATIONS`, run in `Data.open`); per-market and per-character tables; positions, journal, item statistics. |
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
| `Core.lua` | `F.Engine` | Wiring (`wireMarket`), events between services and UI (`emit`/`listen`, the `screen()` reader), event frame, event dispatch, the per-frame update loop, scope and cut, error reporting, key binding actions, `ForeverFlipAPI`, slash commands. |
| `UI.lua` | `F.UI` | The window: widgets (`text`, `button`, `table_`, ...), main frame, menu, page switching, status messages; `UI.shared` holds the locals the page files use. |
| `UIDeals.lua` | `F.UI` | Deals, Shopping list, Bids and My bids pages. |
| `UISelling.lua` | `F.UI` | Sell, My auctions and Undercuts pages. |
| `UIAnalytics.lua` | `F.UI` | Statistics, Analytics and KPI pages. |
| `UICrafting.lua` | `F.UI` | Crafting page. |
| `UIJournal.lua` | `F.UI` | Journal page. |
| `UISettings.lua` | `F.UI` | Settings pages. |
| `UIStatus.lua` | `F.UI` | Status line, `UI.refresh`, Buy tab marks, price history window. |
| `UITab.lua` | `F.UI` | Auction house tab and attach, best-price text, mailbox button, age text. |
| `UITooltip.lua` | `F.UI` | Item tooltips and the post price reasons. |
| `UIMerchant.lua` | `F.UI` | The ForeverFlip tab of the merchant window. |

`Core.lua` and the UI files load last, because they wire the other modules together. The UI page
files load after `UI.lua` in the order above: each starts with `local S = UI.shared` and takes the
locals it uses from earlier UI files (`local button = S.button`). Every public name stays on `F.UI`.
A new UI file needs a game restart, not a `/reload`, to be loaded.

### Layers

1. **Pure:** `Util`, `Locale`, `Market`. No game API, no game-facing module.
2. **Storage:** `Data` (layout, schema version, migrations), `Raw`.
3. **Adapters:** `AH` (auction house) and `Compat` (client capabilities).
4. **Services:** `Scan`, `Deals`, `Sniper`, `Trade`, `Bids`, `Mail`, `Crafting`, `Disenchant`,
   `Merchant`, `Analytics`, `Share`. They never use `F.UI`: they read what the window shows through
   `F.Engine.screen()` (frame, shown, section, filter, selected, selectedAt, buyHoverKey,
   vendorOrder) and ask it to act through `F.Engine.emit` (`"select"`, key). `Core` still calls
   `F.UI` as the wiring layer.
5. **UI:** `UI.lua` and the page files.

## Runtime flow

```
ADDON_LOADED ──► Data.open(ForeverFlipData) ─► Locale.apply (UI.noSavedData when nothing was read)
             ─► Engine.hookReplicate ─► Engine.applyCut ─► UI.tooltips
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
  Sniper.step        other addons' browse rows (3 ms per frame), browse rounds and key batches
  Trade.step         purchase timeouts
  Mail.step          paced mail looting
  Share.step         delayed realm-channel answers, one shared-scan message a second, the scan text built in slices
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
UI translates through `MESSAGES` and `F.Locale`. `F.Engine.emit(event, ...)` calls every function
given to `F.Engine.listen(event, fn)`, in order, at once (the name `notify` was already the status
message).

`Data.open` fills defaults, then runs `D.migrate`: `db.schemaVersion` counts the applied
`D.MIGRATIONS`; each runs once, in order, and is idempotent. A fresh file gets the current version;
a file from a newer ForeverFlip keeps its data and version, with a warning in the log. The sales
statistics keep their own `D.STATS_VERSION`. A change to the saved layout adds a migration at the
end of the list; never edit or reorder the existing ones.

`Engine.input()` marks a hardware callback for feedback on the next frame and holds new automatic
queries for half a second. It never replays the protected action later. `Engine.workSlice(ms)`
reduces local scan, receive and analytics slices to 2 ms while input, a purchase or a single-item
check is pending. These are cooperative budgets, checked between work units, not OS threads or
hard real-time deadlines. The normal dirty refresh remains limited to four times a second.

### Scope and owner

- `Engine.scope()` = `<realm>-<faction>` identifies an auction house (` (HC)` follows the realm on
  hardcore realms). Scan history and deals are stored per scope.
- `Engine.owner()` = `<realm>-<character>` identifies a character. Positions, journal and
  statistics are stored per owner.

### Exact-search scheduling

Only one exact search is in flight at a time (`F.Deals.search`). Requests come from three sources,
in this order:

1. **The player's requests:** single-item clicks before Check all, posting preparation and
   own-auction batches. Requests remain FIFO within their priority class (`D.requests`); the
   `priority` field is independent of `fast` pacing. A repeated key shares the query and promotes
   queued batch work when clicked individually. Every distinct callback completes exactly once.
2. **A background retry slot** (`D.backgroundRetry`), used after a throttled or dropped request.
3. **Automatic checks and the sniper's candidates,** started only when nothing else is waiting.

Gear is searched in two steps inside one request: a browse by the item's name lists its item-key
versions (`phase = "browse"`), then each version is searched (`phase = "keys"`) and the rows are
merged. Once the sniper's sent browse reply is drained, its unsent pagination gives way
(`F.Sniper.yield`).

Non-commodity searches reuse exact keys learned from owned auctions or browse results; ordinary
items such as recipes can have a nonzero key level too. Both UPDATED and ADDED result events
advance pagination. A request has a 30-second cumulative reply-wait budget across its stages;
intentional waits between versions do not consume it. Expired requests return unknown, and
unresponsive cached keys are invalidated before later retries.

Deal selection and Buy hover call `Trade.prepareBuy` to restore an item/gear's search context
before its hardware purchase callback. `Trade.readyToBuy` gates the button on actual connection
availability. Hovering extends the brief selection hold; owned-auction refreshes also yield.
`AH.available` observes readiness (including the existing stuck-throttle allowance) without
consuming it during rendering. Preparation callbacks never replay protected purchase actions.

An already sent query cannot be cancelled by clearing a Lua field: its reply must still be
drained, or time out, before another request owns the connection. Only an unsent gear-version
step (`waitKey`) can be parked in the queue; it resumes with the same keys and accumulated rows.
Sniper pagination also waits for manual work and pending trades. Merely rendering Selling no
longer starts price requests for bag contents; explicit checks and posting queues do that work.

Scan recovery preserves its cursor between frames. Analytics builds bounded top-50 heaps along
with its incremental rows, and sorts only those small heaps at completion.

No search runs while a purchase or a full scan is in progress, also while the scan waits for its
answer (`F.Scan.blocking`): queries sent meanwhile kept the answer from coming in game. Browse and key queries of the sniper
(`F.Sniper.query`) are separate from exact searches. They are sent only when no exact search is in
flight or queued and no candidate is waiting.

## Design rules

1. **One gateway to the game.** Only `AH.lua` calls `C_AuctionHouse` (Core adds a passive hook on
   `ReplicateItems`). Calls that differ between clients go through `Compat.lua`, which also says
   what the client can do (`F.Compat.caps`); the UI touches only frames. Tests replace these APIs
   with `tests/mock.lua`. `tests/test_architecture.py` checks the layer rules.
2. **Pure maths in `Market.lua`.** Deal rules are plain functions of their inputs, so they can be
   tested exhaustively. Market reaches other modules only through `M.env`.
3. **Nothing heavy in a single frame.** Scans are read and evaluated under a per-frame time budget
   (`debugprofilestop`); deal pages prepare lazily.
4. **No automatic trading.** Every hardware-protected action (buy, quote and confirm, bid, post,
   cancel) is sent only inside a click handler or a key binding. Selling to a merchant and taking
   auction mail are not hardware-protected: a click starts them as paced jobs, `Trade.stepVendor`
   and `Mail.step` continue them from OnUpdate, and they stop when the merchant or mailbox closes.
5. **Fail soft.** Every event and frame handler runs under `xpcall`. API calls that may be missing
   on WoW Forever are guarded in `Compat.lua` (`C_Item.GetItemInfo` vs `GetItemInfo`,
   `C_MerchantFrame.GetItemInfo` vs `GetMerchantItemInfo`) or `AH.lua` (`SendSellSearchQuery`); a
   missing full scan shows "No full scan" instead of an error.
6. **Bounded event history.** Transient records have caps or expiry; user catalogues such as shopping
   lists, posting rules, recipes and lifetime item statistics remain until explicitly changed.
   Do not discard accounting or settings as cache data.

   | Data | Limit |
   |---|---|
   | Journal | 500 entries |
   | Errors | 20 |
   | Invoices | 200 |
   | Scan history | pruned after 14 days without the item |
   | Daily records | 14 days |
   | Purchase lots | 300 per character; open lots are never dropped |
   | Waiting pool | 6000 items |
   | Cheapest rows per item | 40 |
   | Bid candidates | 100 |
   | Gold records | 60 days |
   | Bids | 2 days |
   | Raw full scans | 8; uploaded older scans removed |
   | Item-key versions | 14 days without the item |

Full-scan working groups expire after five minutes; the lightweight listed-unit snapshot remains
available for its twenty-minute no-seller check. Market analytics refreshes its cache each minute.

## Adding a feature

- Put calculations in `Market.lua` (or a new pure module) and test them directly.
- Put new auction house calls in `AH.lua`, other calls that differ between clients in
  `Compat.lua`, and add matching fakes to `tests/mock.lua`.
- A service that must change the window emits an event (`F.Engine.emit`); the UI listens.
- A page goes into its own `UI*.lua` file, listed in the TOC after `UI.lua`.
- Every visible string goes through `L(...)`; add the Ukrainian text to `Locale.lua`.
  `tests/test_locale.py` fails when a string written as `L("...")` has no translation.
- For a release, see [CONTRIBUTING.md](../CONTRIBUTING.md#releasing).
