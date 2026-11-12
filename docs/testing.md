# Testing

Current addon and helper: **1.2.0-beta.6**. This checklist describes the current implementation,
including the posting, scheduling, resale, scan-sharing and desktop-helper changes through beta.6.
Use it for a fresh run; passing an older beta does not mark the current build as tested.

## Automated tests

Run from the repository root with Python and the pinned development dependencies:

```bash
python -m pip install -r requirements-dev.txt
python -m unittest discover -s tests -p "test_*.py"
stylua --check ForeverFlip
```

The current checker discovers **502 tests in 38 modules**. The Lua tests load the actual TOC files
in order into `lupa.lua51`, then exercise events and frame updates through `tests/mock.lua`.
Python tests cover the Sync helper, community aggregator and release tooling. Mocked network tests
do not upload real scans or authenticate to GitHub. Tk window tests can be skipped when the
platform has no display; record the skipped count instead of treating it as visual verification.

To run a focused group while developing, use discovery with the module name, for example:

```bash
python -m unittest discover -s tests -p "test_post_quantities.py"
python -m unittest discover -s tests -p "test_sync_gui_state.py"
```

### Coverage by module

| File | Covers |
|---|---|
| `test_addon.py` | Utilities, market maths, full scan pipeline, verification, buying, posting, own auctions, mail, merchant, accounting, analytics, time-of-week pattern. Also provides the `runtime()` helper the other suites use. |
| `test_demand.py` | Sales estimates and their display. |
| `test_scheduler.py` | The exact-search queue: FIFO within priorities, response ownership, shared requests/callbacks, background retries and timeouts. |
| `test_batch_progress.py`, `test_status_batch.py` | Check all: capture, progress and completion. |
| `test_status_ui.py`, `test_tables.py` | Status line, tables, sorting, paging, localisation of the UI. |
| `test_accuracy.py` | Game deposits, neutral auction houses, stale quotes. |
| `test_fast_sniper.py` | Browse rounds, paging, candidates, key batches, the player's browsing. |
| `test_lot_sales.py` | Lot-by-lot sales tracking, sale prices, 14-day history, price age, history window. |
| `test_invoices.py` | Invoices, double-booking protection, failed posts, sale rate, trust, learned cut. |
| `test_post_quantities.py` | Posting across bag stacks, retained quantities, client limits and manual-post boundaries; no unattended next-item posting. |
| `test_selling_rules.py` | Undercut percent, rules, maximum, hold, Post all, Cancel undercut, automatic duration. |
| `test_shopping.py` | Shopping deals, ignored items, the shopping page, learning from searches, key bindings. |
| `test_crafting.py` | Recipes, material and product prices, Shop materials, disenchant table and deals. |
| `test_bids.py` | Bid candidates, checks, placing, won and outbid bids, the Bids page. |
| `test_no_sellers.py` | Items nobody sells: empty checks, fallback prices, guesses, no answer. |
| `test_hidden_items.py` | Hiding items from the Sell page, the Hidden view, returning items. |
| `test_sorting.py` | Column sorting of every table, both directions, cached lists untouched. |
| `test_ingame_round2.py` | Own auctions nobody else sells, no answer, sniper summary, Buy tab marks per row. |
| `test_share.py` | Shared scans: text form, sending, receiving, merging, rejection; key bindings in the settings; statistics display. |
| `test_history.py` | Community-history price filtering and disputed scans; unconfirmed or disputed data is not published as confirmed prices. |
| `test_sync.py` | Raw full-scan capture, SavedVariables parsing, FFR1 uploads, FF1 community summaries, seals, duplicate rejection, confirmation and aggregation. |
| `test_extras.py` | `ForeverFlipAPI`, aux fallback, CSV export, realm gold, presets. |
| `test_forever12.py` | 1.2: vendor prices from the buyback list and the margin, the stuck throttle, owner names, gear searched by browse and version, other addons' full scans, the scan wait, disenchant rules and learning, the realm channel, the trust filter, the spending limit, cheap lots left, Buy next, the saved-data guard, hardcore scopes, tooltip advice. |
| `test_simulation.py` | Simulated play sessions (see below), with and without the player and other addons acting meanwhile, a `/reload` with the saved data written and read back as text, switching between a faction and a neutral house, and a full scan of 100 000 auctions read in small frames. |
| `test_audit.py` | Current regression coverage: stuck quotes and requests, queue order, the request budget, purchases bound to the selected deal, the price field, posting and cancelling twice, late answers, mail the game refuses, one failing part of the frame update. |
| `test_release.py` | Exact beta release notes, legacy fallback, refusal of missing notes, and current-version archive contents. |
| `test_locale.py` | Every `L("...")` string has a Ukrainian translation, and no key is translated twice. |
| `test_foreground.py` | Interactive promotion, wire ownership, safe gear pause/resume, trade exclusion, status priority and posting before read-ahead. |
| `test_optimization.py` | Bounded analytics rankings and build slices, lot comparison work, scan recovery fairness, browse chunks, input painting and indexed own-unit counts. |
| `test_purchase_confirmation.py` | General auction errors preceding successful purchase, money or chat confirmation; timeout and late recovery without double booking. |
| `test_resale_diagnostics.py` | Actual sales-data counts, visible spending limits, affordability classification and safe local re-evaluation after money gains. |
| `test_sync_helper.py` | Forever discovery, retail rejection, upload retries, saved preferences, credential refresh and file-change handling. |
| `test_github_login.py` | GitHub device sign-in, encrypted token storage, sign-out and credential precedence. |
| `test_addon_update.py` | Stable/beta selection, download digest and TOC validation, safe installation and rollback. |
| `test_sync_gui_state.py` | Delayed account discovery wakes automatic sharing, unchanged saves are reconsidered, and PNG window icons are not overridden by ICO decoding. |
| `test_sync_packaging.py` | TLS verification and isolated packaged-runtime diagnostic behavior; the Windows builder also tests the actual EXE. |

### Simulated sessions

`tests/sim.lua` provides a changing market: other players list, buy, cancel and expire auctions.
`test_simulation.py` runs seeds **1, 2 and 3**, plus seed **6** with player/other-addon activity
(`chaos=0.05`). It also tests reload persistence, switching houses and a 100,000-auction scan.
After each simulated tick, journal totals, stock, listings and money must agree, and caught or
uncaught Lua errors fail the run. Additional seeds can use `session(seed)` from that module.

### Build and release verification

```bash
python tools/build.py --output dist
```

This verifies TOC/runtime version agreement, runs the same full suite and creates the addon ZIP.
CI also checks StyLua on main pushes and pull requests. On Windows, build the helper separately:

```powershell
python -m pip install pyinstaller
python tools/build_sync_helper.py --output dist
```

The Windows builder includes the Sync asset kit and EXE icon, preserves any TLS resource required
by the Python distribution, and runs the actual EXE's TLS/Tk self-test. `--self-test-network` adds a
public community-index GET; `--self-test-report <path>` saves the JSON result. Self-test mode runs
before configuration or credentials are read and does not sync user data.

For a release, also verify that the tag, TOC and `F.version` agree; the helper's `VERSION` identifies
the matching build; the ZIP contains the tagged runtime files; the published EXE contains the asset
kit; and both downloads match GitHub's published digests. A frozen runtime self-test does not check
the full window layout, title-bar icon or actual scan submission: use the manual rows below.

The pre-commit hook checks formatting and runs the suite when code changes; the local post-commit
flow can install the addon and push main. See [local development flow](../CONTRIBUTING.md#local-development-flow).

## In-game checklist

Install the current addon and use `/reload` for changed existing files. Restart the game when addon
files or addon folders are added/removed, including the first `ForeverFlip_Shared` installation.
Download the current helper EXE separately and close the old helper before starting it: automatic
addon updates do not replace the helper executable. SavedVariables remain outside the addon folder.

### Current beta checklist

All rows start **⬜ pending** for a fresh beta.6 run. Record **pass**, **fail** or **not tested**, the
build/platform and any prerequisites. A missing suitable lot or second player means not tested;
it is not a failure or a pass. Keep server timing observations separate from simulated results.

#### Installation and interface

| Result | ID | Action and expected result |
|---|---|---|
| ⬜ | UI-1 | `/ff`, the addon list and `/ff diag` identify beta.6. Existing settings, stock and journal survive reload. All current pages and their submenus open without errors. |
| ⬜ | UI-2 | Check English and Ukrainian, native auction-house styling, money coins, long names, tooltips and scrolling. Sort each table both ways; sorting happens before paging and remains after refresh. |
| ⬜ | UI-3 | Start Check all on a list longer than one page. It captures the applicable unique items across all pages, reports progress/failures and completes once. Unsupported or empty actions are disabled. |
| ⬜ | UI-4 | Bind Buy, Buy next and Post next bought in Settings. Each key acts on the current item, including the same Buy key/button confirming a commodity quote. Shift-clickable item names still link to chat. |

#### Full scans, sniper and click priority

| Result | ID | Action and expected result |
|---|---|---|
| ⬜ | SCAN-1 | Run a complete scan. Waiting, reading and evaluation progress are visible; read/skipped/own counts agree. Unloaded rows do not prevent later loaded rows from being read. Large replies are processed between frames. |
| ⬜ | SCAN-2 | Leave automatic scanning enabled at the house. The next attempt follows the account cooldown. A scan awaiting an answer blocks competing browse/search traffic; closing and reopening preserves pending scan work. |
| ⬜ | SCAN-3 | If the server sends partial replies, they are not used as a smaller complete-house baseline or confirmed sales. A no-answer request ends after five minutes; another automatic attempt respects the full-scan window from that request. An explicitly dropped request is a separate retry case. |
| ⬜ | SCAN-4 | Start a full scan from Auctionator or auxForever. ForeverFlip reads it without starting a second full scan. Ordinary foreign browsing is not mistaken for the answer to an exact/gear request. |
| ⬜ | SCAN-5 | Enable sniper and browse with another addon/the Buy tab. Rounds and candidate checks continue at safe boundaries, without freezes or request flooding. Turning sniper off suppresses new work/retries without reassigning an already-sent response. |
| ⬜ | QUEUE-1 | During Check all, manually check another item. The click takes priority at the next safe boundary. Clicking an already-queued key promotes the existing request; it does not send a duplicate. |
| ⬜ | QUEUE-2 | Pause a multi-version gear batch with a manual check. Unsent versions wait, then resume with partial results preserved. A request already on the wire finishes or times out before another owns the connection. |
| ⬜ | QUEUE-3 | Select the item currently being checked. Its own check continues. A checked selection holds unrelated background searches for up to 15 seconds; a checked deal remains ready for five minutes. A busy Buy click gives the outgoing work time to clear. |
| ⬜ | QUEUE-4 | During scan/history/analytics processing, button feedback paints before more local work. Manual purchase/post status stays visible over paused batch status. Auto scans do not interrupt preparing a ready purchase. |

#### Deals, purchases and sales observations

| Result | ID | Action and expected result |
|---|---|---|
| ⬜ | DEAL-1 | Verify a vendor deal and buy it. Only a supported success signal records the purchase; stock and journal update once. A vanished or repriced lot is re-evaluated rather than bought using stale rows. |
| ⬜ | DEAL-2 | Buy a commodity: Buy becomes Confirm on the same control, with the quoted quantity/total. An expired or nearly expired quote is requested again; switching selection drops the old quote. A higher price is not silently accepted. |
| ⬜ | DEAL-3 | For an item/gear purchase, a generic AH error alone must not claim another player won. Matching purchase/chat/money evidence can confirm it. A 30-second no-result timeout remains unresolved until evidence arrives; late success records it only once. |
| ⬜ | DEAL-4 | After checking a gear/item lot, search another item and return to Buy. Required server context is refreshed; a later hardware click buys. No purchase is replayed automatically after waiting for a busy connection. |
| ⬜ | DEAL-5 | In a multi-unit deal, Buy at and Sells at are unit prices; Profit covers the whole deal. Compare tooltips, detail and the actual total. Est./day distinguishes unknown, observed zero and stale observations; it is not a sale guarantee. |
| ⬜ | DEMAND-1 | Compare usable full scans at least 15 minutes apart. A partially reduced lot can provide immediate sales evidence; a whole vanished lot waits for a later scan to rule out reposting. Reposts, expiry and incomplete scans must not invent immediate sales. |
| ⬜ | DEMAND-2 | Inspect Resale with and without usable observations. Sales data counts items with observations. Empty results explain current budget/per-item limits where applicable. Two scans alone do not guarantee profitable offers or confirmed whole-lot sales. |
| ⬜ | DEMAND-3 | Increase gold after a budget-only rejection. Cached leads are re-evaluated locally without another full scan; they still require live verification. Previously disproved/bought lots must not reappear from older scan rows. |
| ⬜ | DEAL-6 | Check spending/per-item limits, minimum profit and cheap units left for others. Shopping quantities and ignored items still constrain candidates. Own auctions never become purchase targets. |

#### Selling, bags and accounting

| Result | ID | Action and expected result |
|---|---|---|
| ⬜ | POST-1 | Open Selling with many bag items: rendering alone sends no bag-wide searches. A ready item posts before unrelated read-ahead; a fresh complete scan can price it in the same click. Missing prices are checked when a queue action is requested. |
| ⬜ | POST-2 | Put one commodity in stacks of 10, 10 and 20. Post AH-worthy/Post all submits all 40 available units in one operation, subject to the client limit. A keep rule of 25 leaves 25 and posts 15. Post next bought caps quantity to its tracked stock; manual Post respects client availability too. |
| ⬜ | POST-3 | Distinct items still need separate clicks after confirmation. A pending post blocks another post/bid/purchase; only the created event reports success. Warning confirmation is explicit; a drop/timeout does not falsely book a listing. |
| ⬜ | POST-4 | Exercise min/max/normal price, below-min hold and automatic/fixed duration. Guessed prices are marked and skipped by posting queues until manually reviewed. Hide/return, vendor/shopping/ignored exclusions and keep rules remain effective. |
| ⬜ | POST-5 | Refresh an automatically filled price, then type a manual price and refresh again: the manual value remains. Move the selected item to another bag slot or scroll it away: Post still targets that item. |
| ⬜ | POST-6 | In My auctions, check gear/commodity prices, including only-your-auctions and no-answer cases. Cancel undercut acts once per click and never cancels a lot twice. |
| ⬜ | POST-7 | In Undercuts, compare wait/repost/buyout/vendor alternatives. Choosing buyout adds the correct shopping quantity using the player's resale price; purchased units reduce the remaining target. |
| ⬜ | BOOK-1 | Sell a multi-unit lot and collect its invoice. The actual count, proceeds and learned cut are booked once, even if the owned list already reported the sale. Expired/cancelled mail returns stock without booking a sale twice. |
| ⬜ | BOOK-2 | Take auction mail with unrelated mail present; only auction mail is processed. Full bags, closing the mailbox or a repeatedly refused mail stop the job. Purchases made outside ForeverFlip are booked from their mail; addon purchases are not booked again. |
| ⬜ | BOOK-3 | Sell vendor stock through the merchant button and manually. Each sale is booked once; lists refresh after bags settle. Scroll long merchant lists and check gear the character cannot use. |

#### Other supported features and persistence

| Result | ID | Action and expected result |
|---|---|---|
| ⬜ | FEATURE-1 | Add/remove shopping entries and ignore an item. Eligible Shopping deals obey requested quantity/price. Shop materials adds only missing materials after counting bags. |
| ⬜ | FEATURE-2 | Open a profession window and inspect Crafting. Material/product prices and missing-price explanations agree with available data. On an enchanter, verify disenchant deals and learning without assuming every result is guaranteed. |
| ⬜ | FEATURE-3 | Check and bid on a near-expiry auction, including gear. Won and outbid outcomes update tracking once. |
| ⬜ | FEATURE-4 | At faction, neutral and hardcore houses, scan history/prices remain correctly scoped; faction NPCs in neutral zones are recognized. Neutral cut starts at 15% and invoice learning remains consistent. |
| ⬜ | FEATURE-5 | Inspect Analytics, per-item statistics, history charts and price age, weekly patterns when enough history exists, stock and tooltip advice. Large histories build between frames; unknown rates remain unknown. `/ff export` still produces journal CSV. |
| ⬜ | FEATURE-6 | Reload and switch houses/characters. Stored scan/deals, journal, lists, realm gold and settings persist under the correct scope. Test the missing-saved-data guard only in a disposable profile; Reload/Continue must not silently destroy an existing profile. |

#### Sharing and the Windows Sync helper

| Result | ID | Action and expected result |
|---|---|---|
| ⬜ | SHARE-1 | Export/import current in-game history as `FF3|...`; use a second player for guild/group/realm exchange. The hidden realm channel stays out of chat windows. Duplicate, old, malformed and wrong-realm snapshots are rejected. |
| ⬜ | SHARE-2 | Receive history and reload. Newer trusted shared prices can supply history without creating a live-verified deal. Legacy FF1 community summaries remain readable; obsolete FF2 sale counts are not imported. Receiving one's own summary again must not add the same sales repeatedly. |
| ⬜ | SYNC-1 | Run the beta.6 EXE at 100%, 125%, 150%, 200% and a higher available scale. Verify header/buttons/switches, disabled/hover states, log expansion and the blue quill in the Windows title bar. Runtime self-tests alone do not establish these visual results. |
| ⬜ | SYNC-2 | Discover a running/common/nonstandard Forever install; select its parent or game folder manually and restart. Selection is remembered; Retail/Classic and ambiguous choices are not silently accepted as Forever. |
| ⬜ | SYNC-3 | Use device sign-in, enter/approve the code yourself, and restart to verify encrypted storage. Check cancellation/expiry. Sign out removes the helper's stored token. If environment/config/CLI credentials also exist they can still supply an account; use a clean credential profile when testing signed-out behavior. |
| ⬜ | SYNC-4 | Enable full-scan saving in the game before a complete scan, then `/reload`. With opt-in sharing and a sign-in, Show activity reports submission and later the data repository's answer. Confirm the issue/registry outcome; a downloaded-price status alone is not upload confirmation. |
| ⬜ | SYNC-5 | Restart with sharing already enabled and saved unsent scans. Even when account discovery completes after the first download, existing scans become eligible without toggling sharing or making a new game save. Change sharing during a transfer and verify the next pass uses the new setting. |
| ⬜ | SYNC-6 | Interrupt a transfer. Successful partial uploads remain acknowledged, failed submissions retry, and saves made during a transfer are picked up next pass. Errors identify missing files/HTTP/network failures; a sharing failure does not block an independent price-download attempt. |
| ⬜ | SYNC-7 | Download community prices without signing in. After the first Shared addon installation restart the game; later updates load at `/reload`. Check generated time and imported history, including when your own submitted scans occur in the downloaded summaries. |
| ⬜ | SYNC-8 | In an isolated game copy, exercise stable/beta update selection, update-only notification with automatic updates off, hash/TOC validation, backups and rollback. Leaving beta never downgrades; development copies are not replaced. Added/removed addon files prompt a restart. |
| ⬜ | SYNC-9 | Run the helper from its packaged EXE with HTTPS verification enabled. Exercise manual sync, automatic sync, paused mode and the supported console options. UI remains responsive while parsing large saves/network replies; closing during a transfer waits for the operation. |

### Automated checker maintenance

The module table above must list every existing `tests/test_*.py` file. Tests named after an old
release or incident still protect current functions; remove one only when its contract or called
path has actually been removed or superseded. Rename misleading test descriptions to describe the
current layer being tested, rather than removing a live regression.

In particular, `Market.trackSales` produces candidate vanished-lot counts; `Scan.trackLots` defers
whole-lot confirmation to rule out reposts. Keep both unit and scan-level tests. Keep FF1 parsing,
FF2 sales rejection, saved-data migration, aux/API fallbacks and the owned-auction progress adapter:
these paths still exist. The removed anonymous relay is not a current upload path.

There is one current manual checklist above. Old release-specific checklists, inherited pass marks,
fixed gear-response promises and guaranteed Resale-after-two-scans expectations are not acceptance
criteria. Do not reintroduce automatic purchase/post replay after a timer or pretend an in-flight
server request was cancelled locally. Put `unittest.main()` after every test class so direct runs
and discovery cover the same cases.

### Beta testing

Use [the beta.6 release](https://github.com/Danissemo/ForeverFlip/releases/tag/v1.2.0-beta.6), or turn on
**Beta tester** in the [Sync helper](community.md#addon-updates-and-beta-testing) for addon updates.
Install the matching helper EXE separately. Follow the current checklist against the installed
build; automated checks do not establish live auction timing or real GitHub upload acceptance.

Report an [issue](https://github.com/Danissemo/ForeverFlip/issues/new/choose) with the checklist ID,
addon/helper version, what you did, expected/actual result, and whether it reproduces. Include a
screenshot for visual faults. For Lua failures, `/reload` and provide the relevant `errors` entries
from `WTF/Account/<ACCOUNT>/SavedVariables/ForeverFlip.lua` plus `/ff diag`. For Sync failures, include
the relevant **Show activity** lines and submission outcome. Never include tokens or sign-in codes.
