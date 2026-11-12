# Testing

Current pre-release: **1.2.0-beta.4**. The current beta checklist below is the acceptance list for
this build. Automated tests load the current TOC files, including the new scheduler and UI behavior.

## Automated tests

The tests run the real addon files in **Lua 5.1** inside Python (through
[lupa](https://github.com/scoder/lupa)). `tests/mock.lua` is a small simulated WoW client with a
WoW Forever auction house: items and commodities, full scans, exact searches with throttling,
purchases, posting, own auctions, mail, merchants, bags and frames. Each test loads the TOC files in
order and drives the addon through game events and frame updates.

```bash
python -m pip install -r requirements-dev.txt
python -m unittest discover -s tests -p "test_*.py"
```

| File | Covers |
|---|---|
| `test_addon.py` | Utilities, market maths, full scan pipeline, verification, buying, posting, own auctions, mail, merchant, accounting, analytics, time-of-week pattern. Also provides the `runtime()` helper the other suites use. |
| `test_demand.py` | Sales estimates and their display. |
| `test_scheduler.py` | The exact-search queue: FIFO within priority classes, response ownership, sharing, background retry and timeouts. |
| `test_batch_progress.py`, `test_status_batch.py` | Check all: capture, progress and completion. |
| `test_status_ui.py`, `test_tables.py` | Status line, tables, sorting, paging, localisation of the UI. |
| `test_accuracy.py` | Game deposits, neutral auction houses, stale quotes. |
| `test_fast_sniper.py` | Browse rounds, paging, candidates, key batches, the player's browsing. |
| `test_lot_sales.py` | Lot-by-lot sales tracking, sale prices, 14-day history, price age, history window. |
| `test_invoices.py` | Invoices, double-booking protection, failed posts, sale rate, trust, learned cut. |
| `test_selling_rules.py` | Undercut percent, rules, maximum, hold, Post all, Cancel undercut, automatic duration. |
| `test_shopping.py` | Shopping deals, ignored items, the shopping page, learning from searches, key bindings. |
| `test_crafting.py` | Recipes, material and product prices, Shop materials, disenchant table and deals. |
| `test_bids.py` | Bid candidates, checks, placing, won and outbid bids, the Bids page. |
| `test_no_sellers.py` | Items nobody sells: empty checks, fallback prices, guesses, no answer. |
| `test_hidden_items.py` | Hiding items from the Sell page, the Hidden view, returning items. |
| `test_sorting.py` | Column sorting of every table, both directions, cached lists untouched. |
| `test_ingame_round2.py` | Own auctions nobody else sells, no answer, sniper summary, Buy tab marks per row. |
| `test_share.py` | Shared scans: text form, sending, receiving, merging, rejection; key bindings in the settings; statistics display. |
| `test_sync.py` | Full-scan capture, the SavedVariables reader, FFR1 and FF1 formats, the usual price in Python and Lua, the aggregator. |
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
| `test_sync_packaging.py` | TLS verification and isolated packaged-runtime diagnostic behavior; the Windows builder also tests the actual EXE. |

### Simulated sessions

`tests/sim.lua` turns the mock into a living market: other players list items, commodities and gear,
buy the cheap lots (yours too) and let lots expire (yours come back by mail). A session runs in 15-minute ticks; each tick ForeverFlip
makes a full scan, the sniper and the deal checks run, deals are bought, the bought stock is posted,
own auctions sell, the mail is taken and vendor deals are sold at a merchant. Every page and tooltip
is drawn after each tick, and these always have to hold:

- every deal has a profit, and the scan counts add up (read, skipped and own
  auctions make the total);
- the journal agrees with the item statistics, and with the units the market says were bought,
  sold and returned unsold;
- what the books count as on sale is really on sale;
- every position exists in the bags or in your auctions, money never goes below zero, and nothing
  is sold to a vendor at a loss;
- no Lua error, caught or not.

With `chaos` above 0 the player searches in the game's Buy tab meanwhile (browses ForeverFlip did
not send), the auction house is closed and opened again now and then, and every third scan is
started by another addon.

Seeds 1 to 3 and one session with chaos run in the suite; for more, call `session(seed)` (or
`session(seed, chaos=0.05)`) from `test_simulation.py` in a loop.

The CI workflow runs the same tests, checks formatting with StyLua, and builds the archive on every
push and pull request. Locally, the `pre-commit` hook runs StyLua and the tests before every commit
that changes code (see [CONTRIBUTING](../CONTRIBUTING.md#local-development-flow)).

### Static checks

```bash
stylua --check ForeverFlip
```

[lua-language-server](https://github.com/LuaLS/lua-language-server) with `.luarc.json` (Lua 5.1) can
check the addon too. For WoW API types, add the annotations of the
[WoW API extension](https://github.com/Ketho/vscode-wow-api) as `workspace.library`:

```bash
lua-language-server --check=ForeverFlip --configpath=.luarc.json --checklevel=Warning
```

## In-game checklist

The simulated client cannot prove how the live server behaves. Before a release, go through this
list on a live realm. If something goes wrong, note the chat line (`ForeverFlip error: ...`), type
`/reload` and copy the `errors` section from the SavedVariables file.

✅ = observed in an earlier in-game check on WoW Forever, ⬜ = still to check. These marks are
not a claim that beta.4 has passed a new live run. Use the unchecked current beta table for fresh
acceptance results; automated mocks cannot establish server timing.

| | Area | Check |
|---|---|---|
| ✅ | Install | `/ff` shows the version; all pages are listed on the left. |
| ✅ | Full scan | The progress bar goes through waiting, reading and evaluating; the summary shows the auctions read. |
| ⬜ | Automatic scan | With the auction house open, the next scan starts when the countdown ends. |
| ✅ | Sorting | Every table sorts by its headers, both ways. |
| ✅ | Ukrainian | No boxes in place of symbols; headers and buttons fit. |
| ⬜ | Fast sniper | The summary on the left shows rounds and prices read growing; no "too many requests" errors. |
| ⬜ | Lot sales | After two scans 15 minutes apart, busy items show "sells at"; right-click opens a history with sold bars; Resale lists deals with Est./day. |
| ⬜ | Buy tab marks | Rows priced below their vendor price get a green stripe in the item list, an item's auctions and a commodity's price tiers. |
| ⬜ | Vendor deal | Click → ready → Buy; *Purchase recorded*; a journal entry. |
| ⬜ | Commodity and stale quote | Buy → *Price confirmed* → Confirm; waiting 25 seconds asks a new quote, the next Confirm buys without an error. |
| ✅ | Post | A selected item is posted at the addon's price; the price box clears afterwards. |
| ✅ | Items nobody sells | A recipe or rare item gets a marked suggested price at once; the price you post is suggested next time. |
| ✅ | Hide and return | Hide removes an item from the list and from Post all; the Hidden view returns it. |
| ⬜ | Posting rules | min, max and keep of a rule hold with Post all. |
| ⬜ | My auctions | Check prices gives cheapest / undercut / only yours; Cancel undercut cancels one auction per click. |
| ⬜ | Sale and invoice | A sold lot shows "sold, gold in the mail"; Take auction mail books the sale with the exact amount; Statistics shows Sell %. |
| ✅ | Statistics | Names fit; unsold items show `-`. |
| ✅ | Crafting | Opening a profession window lists its recipes with costs on the Crafting page. |
| ⬜ | Key bindings | Settings → Key bindings sets a key; the key buys the selected deal. |
| ⬜ | Shopping list | An item added with a high price shows as a Shopping deal and can be bought. |
| ⬜ | Bids | A bid on an auction ending soon is placed; a won auction appears in the journal. |
| ⬜ | Disenchant | On an enchanter, a cheap green weapon or armor piece is a disenchant deal. |
| ⬜ | Neutral house | At Booty Bay, Gadgetzan or Everlook deals mention a 15% cut and the history is separate. |
| ⬜ | Shared scans | Export as text gives `FF1|...`; a guild member's scan appears under Received. |
| ⬜ | Community scans | With full scans kept, the Sync helper shares the scan after `/reload` and prints the data repository's answer; the scan is listed in `registry/scans.jsonl` of the data repository; Settings → Sharing shows community data after the next login. |
| ✅ | CSV export | `/ff export` opens the journal as CSV. |
| ⬜ | Persistence | After `/reload` the last scan and its deals are listed as *from scan*. |
| ⬜ | Language | `/ff lang en` and `/reload` switch to English. |

### New in 1.2

Do a full game restart after installing 1.2 (Bindings.xml has a new key).

| | Area | Check |
|---|---|---|
| ⬜ | Menu | Six entries on the left, drawn like the Buy tab's categories. Deals, Selling and Analytics open their pages under them, indented; the bottom of every page stays inside the window (look at Analytics → Overview and Selling → My auctions). An entry opens the tab used last. |
| ⬜ | Summary | Below the menu, the scan and sniper figures are one per line and end above the money display, in English and Ukrainian. |
| ⬜ | Scan answer | While the status counts the seconds of waiting, the sniper's rounds stay still; the scan is read when the answer comes (usually well before 300 s). |
| ⬜ | Vendor price learned | Sell any item to a merchant. Settings → Safety counts it under "confirmed at merchants"; if it differs from the game's data, it is listed with both prices. |
| ⬜ | Vendor deal mark | A vendor deal on an item you never sold shows `vendor *`; after selling one to a merchant the `*` is gone at the next scan. |
| ⬜ | Gear check | Select a gear deal (or press Check prices on Selling → My auctions with gear): the status turns to checked within a few seconds, not "no answer". |
| ⬜ | Gear nobody sells | Check prices on a gear auction only you sell: it shows "only yours" at once. |
| ⬜ | Gear bids | On Deals → Bids, a gear auction with only a bid (no buyout) can be checked and bid on. |
| ⬜ | Full scan wait | When the server is slow, the status counts the seconds (`Waiting for the full scan: 35 / 300 s`) and the scan is read when the answer comes. |
| ⬜ | Other addon's scan | Start a full scan in Auctionator or auxForever: ForeverFlip says it reads it too and processes it. |
| ⬜ | No freeze | Browse the whole house in another addon (or the game's Buy tab with an empty search): the game does not freeze. |
| ⬜ | Sniper keeps going | Leave the auction house open with the sniper on for 10 minutes: rounds keep growing; Safety shows how often the throttle got stuck. |
| ⬜ | Realm channel | `/chatlist` (or the chat channel list) does not show ForeverFlipPrices in any chat window. With a second ForeverFlip user online, a new scan of one appears under Received for the other. |
| ⬜ | Disenchant learning | Disenchant a green item; after 15 of one band Safety shows a learned band. |
| ⬜ | Tooltips | An item tooltip starts with `ForeverFlip: <house>`; it shows your stock and auctions on sale, "Sales: not measured yet" until two scans, and Vendor pays / Auction house / Best side by side. Cheap stackable goods do not show a loss on the auction house. |
| ⬜ | Bought elsewhere | Buy something in the game's Buy tab (or Auctionator), take the mail: Selling → My items lists it as "bought elsewhere", Analytics → Journal has the purchase. |
| ⬜ | Vendor sale by hand | Sell stock bought through ForeverFlip to a merchant by right-click: the journal books a vendor sale, the stock is gone from Selling. |
| ⬜ | Spending limit | Set 1 gold in Safety; buying stops with the limit message once 1 gold was spent this visit. |
| ⬜ | Leave lots | Set 5 in Safety; a vendor deal of commodities leaves 5 cheap units unbought. |
| ⬜ | Buy next key | Bind it in Settings → Key bindings. Press: the best deal is selected and checked; press again: it is bought; for a commodity, press again to confirm. |
| ⬜ | Hardcore | On a hardcore realm the prices are separate from the normal realm of the same name. |
| ⬜ | Shop materials | With materials in the bags, Shop materials adds only what is missing. |
| ⬜ | Saved data guard | Rename `ForeverFlip.lua` in SavedVariables while the game is closed, start the game: the window asks Reload / Continue. Put the file back afterwards. |

### Current beta checklist

**1.2.0-beta.4**, changes since beta.3. Record a fresh result for each row; none is marked passed
merely because the automated suite passed. These scenarios replace the old beta.1/beta.2-specific
lists, whose timing and posting instructions no longer match the current build.

| | Area | Check |
|---|---|---|
| ⬜ | Installed version | After replacing the addon and `/reload`, `/ff` and the addon list show `1.2.0-beta.4`. Saved stock, journal and settings remain. |
| ⬜ | Click before batch | Start Check all, then Check price for another item. It runs at the next safe boundary, before the rest of the batch; the status shows the manual request. |
| ⬜ | Matching batch item | Click an item already queued by Check all. Its existing request is promoted; it is not sent twice, and batch progress completes once. |
| ⬜ | Gear pause/resume | Start a gear batch with several versions, then check another item. The unsent next version pauses; the single check runs, then the same batch resumes without losing its rows or reporting a false failure. |
| ⬜ | Sent request ownership | With the sniper on, press Check price while a reply is pending. The addon waits for that sent reply or timeout before serving the click; it does not claim to cancel a request still running on the server. |
| ⬜ | Purchase and confirmation | Buy a commodity: the same button changes from Buy to Confirm with the quoted total. Select another item before confirming: the old quote is dropped. The status shows asking, confirming and waiting. |
| ⬜ | No false lost race | Buy a gear/item lot. A general AH error must not alone report that another player won. A subsequent purchase event, matching won-chat line or money update records the purchase once; verify its mail and journal. |
| ⬜ | Slow purchase | With no result, an item purchase times out after 30 seconds without being booked as bought. Later confirmation by money records it once. Do not buy the same lot again before checking the outcome. |
| ⬜ | Ready lifetime | A checked deal stays ready for five minutes. Selecting a recently checked deal holds background searches for up to two minutes; an actual busy Buy click also gives it time to clear. |
| ⬜ | Purchase context | Search another item after checking a gear/item lot, then Buy. When required by the server context the lot is read again; the next hardware click buys. No delayed automatic purchase occurs. |
| ⬜ | Quiet Selling page | Open My items with several goods in the bags. Rendering the page alone does not launch a bag-wide price check. Check price and Check all still read the requested prices. |
| ⬜ | Ready post first | Have a ready-priced item followed by one without a price. Post next bought posts the ready one before starting searches for other goods. A recent complete scan can supply its price in the same click. |
| ⬜ | Missing post prices | With no ready item, Post next/Post all prepares missing prices as a bulk queue. A new single Check price goes first. Each later hardware click posts one ready lot; guessed prices still need manual review. |
| ⬜ | Trade exclusion | During an unresolved purchase or post, another bid/post/cancel or search must wait; the original trade must not be confirmed by the other action's money change. |
| ⬜ | Post feedback | After Post, show waiting for AH confirmation; report created only on the creation event. A queued price check or paused batch must not hide posting status. Repeated Post waits instead of overwriting the first operation. |
| ⬜ | Price editing and bags | A refreshed automatic price follows a new result; manual typing remains. Move a selected item to another bag slot or scroll it away: Post still uses that item. |
| ⬜ | Scan recovery | On a house with unloaded item rows, later loaded rows continue to be read; an unloaded prefix must not hold them behind repeated work at the front. No large stall on recovery expiry or scan completion. |
| ⬜ | Full/partial scans | Leave a scan waiting while the server sends parts. No sniper page is sent meanwhile; a partial answer is not counted as confirmed sales or a smaller complete-house baseline. Closing/reopening resumes the pending scan. |
| ⬜ | Full-scan retry | A scan with no answer ends after five minutes; its next automatic attempt waits the server window counted from that request, not repeated one-minute retries. |
| ⬜ | Browse and analytics | With a large browse reply and a large history, buttons remain usable while local rows are processed in chunks. Analytics keeps the previous lists until the new top lists are ready; equal ranking values have stable ordering. |
| ⬜ | Undercuts | Compare wait, repost, buyout and vendor alternatives. Buyout uses the player's resale price, adds the right shopping quantity and counts it down as units are bought. |
| ⬜ | Sales and invoices | Cancel/repost a lot without selling it: no phantom sale appears. Missing whole lots remain suspects until a later scan. Buyer mail with several items books the real count and does not double-book an existing addon purchase. |
| ⬜ | UI and merchant | Check native side-menu pages, settings, scrolling, money coins and the merchant tab. After vendor sales settle, the bag-based lists refresh without another sale click. |
| ⬜ | Sharing compatibility | FF3 history is received and merged without importing obsolete FF2 sale counts. Invalid/duplicate/wrong-house data is rejected, and raw scans remain available to the Sync helper. |
| ⬜ | Regression essentials | Repeat the general checks above for mail, stock, bids, crafting, house switching, English/Ukrainian, key bindings and persistence. Record any differences from beta.3 with the exact row. |

### Automated checker maintenance

Run the full suite with `python -m unittest discover -s tests -p "test_*.py"`; the build and CI use
that same command. Directly running a test file also includes every class defined in it: its
`unittest.main()` entrypoint belongs at the end. Do not delete a still-relevant regression because
its original bug was fixed in an earlier beta. Remove or rewrite a scenario when the intended
behavior has changed, retaining a check of the replacement behavior.

The beta.4 scheduler tests assert safe response ownership instead of instant local cancellation.
The simulated server does not fabricate answers for gear versions that were not sent, and waits
for existing work before starting a full scan. `test_foreground.py`, `test_optimization.py` and
`test_purchase_confirmation.py` cover the new contracts; release tooling has its own tests too.

### Beta testing

Beta releases (`vX.Y.Z-beta.N`, marked **Pre-release** on the
[releases page](https://github.com/Danissemo/ForeverFlip/releases)) are for players who want to help
test before a release. Install one like a normal release (replace the `ForeverFlip` folder; your saved
data is kept), restart the game, and go through the [current beta checklist](#current-beta-checklist).
For beta.4, check every row against the installed `1.2.0-beta.4` build. The broader in-game list
above remains the regression checklist; old observations are not new acceptance results.

Report a bug in an [issue](https://github.com/Danissemo/ForeverFlip/issues/new/choose) (the bug
report form asks for the version and the log); questions and general impressions are welcome in
[Discussions](https://github.com/Danissemo/ForeverFlip/discussions). A bug report has:

- the row of the table and what happened instead;
- a screenshot when something looks wrong;
- for an error: type `/reload` and copy the `errors` section of
  `WTF/Account/<ACCOUNT>/SavedVariables/ForeverFlip.lua`, plus the output of `/ff diag`.
