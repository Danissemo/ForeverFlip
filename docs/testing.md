# Testing

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
| `test_scheduler.py` | The exact-search queue: FIFO order, sharing, background retry, timeouts. |
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
| `test_locale.py` | Every `L("...")` string has a Ukrainian translation, and no key is translated twice. |

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

✅ = confirmed in game on WoW Forever, ⬜ = still to check.

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
| ⬜ | Menu | Six entries on the left. Deals, Selling and Analytics show tabs above the page; no tab label is cut off; the bottom of every page stays inside the window (look at Analytics → Overview and Selling → My auctions). An entry opens the tab used last. |
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

### Fixed since 1.2.0-beta.1

Check these with 1.2.0-beta.2 (or later); they are the fixes testers of beta.1 should look at again.

| | Area | Check |
|---|---|---|
| ⬜ | Sniper gear checks | Leave the sniper on at a house with gear deals for 10 minutes: no error (it was `Deals.lua:692`), gear deals turn checked. |
| ⬜ | House badge | At a faction auction house the bar beside the money display (at the bottom) and the window title name it in blue (Alliance) or red (Horde); in Booty Bay, Gadgetzan or Everlook the neutral house in gold. Go from one to the other and back: each shows its own last scan and deals, none from the other house. |
| ⬜ | Full scan answer | Press Full scan: the status counts the waited seconds (`35 / 300 s`), the sniper and checks stay still meanwhile, and the scan is read when the answer comes, also on a small house; the button shows no stale countdown while waiting. |
| ⬜ | End of a full scan | On a large house the game does not stall when the scan finishes reading. |
| ⬜ | Sales after a partial scan | When a scan comes back much smaller than the one before, Analytics shows no burst of sales of the missing items. |
| ⬜ | Sell page | Items in the bags and in the reagent bag are listed on Selling → My items, also ones the auction house has not shown yet; `/ff bags` says why an item is not listed. |
| ⬜ | A sale booked once | Sell an item bought through ForeverFlip, take the "Auction successful" mail: the journal has the sale once. |
| ⬜ | Expired auction | Let an auction of bought stock expire (or cancel it in the game's own window), take the mail: Post next bought offers the item again at once. |
| ⬜ | Full bags | Fill the bags and take auction mail with items: ForeverFlip stops with "bags full"; free some space and take it again: the journal has each mail once. |
| ⬜ | Gear check and the Buy tab | Search something in the game's Buy tab right before checking a gear deal: the check never says "nobody sells" for gear that is listed. |
| ⬜ | Vendor or auction house | Selling → My items has a Best column: cheap vendor trash says Vendor, valuable goods say AH, with the same values as the tooltip. Post AH-worthy (N) counts fewer items than Post all (N) and never posts an item marked Vendor. |
| ⬜ | Scan and closing | Press Full scan, close the auction house at once and open it again: the status says it waits again and the scan is read. While waiting, the status shows `server list: N`. `/ff diag` lists how the last requests ended. |
| ⬜ | Scrolling | With more than 11 items for sale, the mouse wheel over Selling → My items scrolls the list and the Name header shows `(5-15 / 15)`. |
| ⬜ | Check all without an answer | Check all on My items with an item only you sell: the search is tried twice, the status says `(1 without an answer)` and the chat names the item. |
| ⬜ | Post queue clicks | Press Post AH-worthy once: the prices are read for the whole queue; each next press posts one lot. |
| ⬜ | Check all | The button at the top says Check all. On Shopping list, Bids and Crafting it is enabled too and counts `Checking <page>: done/total`; afterwards Crafting shows the recipes priced with the checked prices, and Selling → My items the Best column with them. |
| ⬜ | Tooltips | See the Tooltips row above (rewritten in beta.2). |
| ⬜ | Bought elsewhere, sold by hand | See the Bought elsewhere and Vendor sale by hand rows above (new in beta.2). |

### Beta testing

Beta releases (`vX.Y.Z-beta.N`, marked **Pre-release** on the
[releases page](https://github.com/Danissemo/ForeverFlip/releases)) are for players who want to help
test before a release. Install one like a normal release (replace the `ForeverFlip` folder; your saved
data is kept), restart the game, and go through the table of the version above. If you tested
1.2.0-beta.1, check [Fixed since 1.2.0-beta.1](#fixed-since-120-beta1) again.

Report a bug in an [issue](https://github.com/Danissemo/ForeverFlip/issues/new/choose) (the bug
report form asks for the version and the log); questions and general impressions are welcome in
[Discussions](https://github.com/Danissemo/ForeverFlip/discussions). A bug report has:

- the row of the table and what happened instead;
- a screenshot when something looks wrong;
- for an error: type `/reload` and copy the `errors` section of
  `WTF/Account/<ACCOUNT>/SavedVariables/ForeverFlip.lua`, plus the output of `/ff diag`.
