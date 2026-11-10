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
| `test_locale.py` | Every `L("...")` string has a Ukrainian translation. |

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
list on a live realm. Each step takes 1–3 minutes. If something goes wrong, note the chat line
(`ForeverFlip error: ...`), type `/reload` and copy the `errors` section from the SavedVariables file.

1. **Full scan.** Click **Full scan**. The progress bar goes through waiting, reading and
   evaluating. `/ff diag` reports the auctions read.
2. **Automatic scan.** Leave the auction house open until the Full scan countdown ends. The next scan
   starts by itself. If the server does not answer, the status line says *Next try in a minute*.
3. **Vendor deal.** Click a vendor deal, wait for **ready**, click **Buy**. *Purchase recorded*
   appears and the journal has a buy entry.
4. **Commodity purchase.** Buy a commodity deal: **Buy**, then **Confirm purchase** after *Price
   confirmed*.
5. **Sniper.** After a scan, the status line shows the number of items watched and checks made. The
   check count grows by about one per second, and no "too many requests" errors appear in chat.
6. **Alert.** When a deal becomes buyable, a sound plays and a yellow line appears in the middle of
   the screen.
7. **Posting.** **Sell my items → Post next bought.** The first click reads the price and the second
   posts it. The game's own Auctions tab shows the lot at the addon's price.
8. **My auctions.** **Check prices** gives every lot a status (**cheapest** or **undercut**).
   **Cancel auction** removes a lot, and the item comes back by mail.
9. **Sale.** When a lot sells, My auctions shows **sold, gold in the mail**, and the journal has a sale
   with its profit.
10. **Mail.** At a mailbox, **Take auction mail (N)** takes auction mail only. It does not touch
    player mail or cash on delivery, and it prints a summary.
11. **Vendor selling.** At a merchant, **Sell vendor deals (N)** sells the items bought as vendor
    deals and adds journal entries.
12. **Merchant offers.** At a merchant with goods that also trade on the auction house, the
    ForeverFlip panel lists profitable items.
13. **Tooltips.** Hover over an item seen in a scan. The tooltip shows the usual price and the
    cheapest today / 5 days.
14. **Resale.** After two or three full scans (30–45 minutes), the Resale page lists deals with an
    Est./day value.
15. **Persistence.** `/reload`. The last scan and its deals are still listed with the status
    *from scan*.
16. **Language.** `/ff lang uk`, `/reload`. The interface is in Ukrainian. Switch back with
    `/ff lang en`.
