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
| `test_batch_progress.py`, `test_status_batch.py` | Check all statuses: capture, progress and completion. |
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
| `test_locale.py` | Every `L("...")` string has a Ukrainian translation, and no key is translated twice. |

The CI workflow runs the same tests, checks formatting with StyLua, and builds the archive on every
push and pull request.

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
| ⬜ | Community scans | With full scans kept, the Sync helper uploads after `/reload`; the scan appears in the data repository's archive; Settings → Sharing shows community data after the next login. |
| ✅ | CSV export | `/ff export` opens the journal as CSV. |
| ⬜ | Persistence | After `/reload` the last scan and its deals are listed as *from scan*. |
| ⬜ | Language | `/ff lang en` and `/reload` switch to English. |
