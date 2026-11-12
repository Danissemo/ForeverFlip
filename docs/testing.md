# Testing

Use these steps to check **ForeverFlip and ForeverFlip Sync 1.2.0-beta.6**.
Choose a test, follow its steps and write down what happened. You do not need to read the code.

## In-game checklist

### Start here

These are small checks you can follow without reading the code. The button names below match the
English interface. **Upload** sends your saved scans to the server; **download** gets shared prices.
A **stack** is one pile of an item in a bag. A **lot** is an item or pile listed at the auction house.
**Sync** means the separate ForeverFlip Sync program on Windows. Find a test by its ID with Ctrl+F.

1. Install beta.6. Close the old Sync window and open the new EXE from the same release.
2. Restart WoW if you added or removed addon files/folders. Otherwise type `/reload` in chat.
3. Open the auction house, then the **ForeverFlip** tab. Use cheap items for buy/sell checks:
   buying uses gold, and posting pays an auction deposit.
4. Start with UI-1, SCAN-1, DEAL-5, POST-2 and SYNC-1. Then choose the other cards you can run.
5. Do one card at a time. Write **PASS**, **FAIL** or **SKIP** next to its ID in your notes.
   Missing an item, a second player or enough history means **SKIP**, not FAIL.

**PASS** means you saw the stated result yourself. **FAIL** means you followed the steps but saw
something different. A card marked **Computer check** is run by the automated checker; you do not
need to cause a server error in the live game. Old checkmarks do not count for a new build.

### Current beta checklist

Use the current beta.6 addon and helper for every card. Each card says what you need, exactly what
to do, and what a successful result looks like. There is no need to complete the cards in order.

#### Window and buttons

##### UI-1 — Check the version and reload

**Need:** The auction house is open.

1. Type `/ff diag` in chat. Check that it says `1.2.0-beta.6`.
2. Note the gold, stock and settings you can see. Type `/reload`.
3. Open ForeverFlip again.

**PASS if:** The version is still beta.6. Your saved data and settings have not disappeared.

##### UI-2 — Read and sort the pages

**Need:** A page with at least two rows.

1. Open each page in the left menu. Scroll any long list.
2. Click one column title twice. For a price column, look for smallest-first, then largest-first.
3. Use `/ff lang uk` and `/reload` to check Ukrainian. Return with `/ff lang en` and `/reload`.

**PASS if:** Text fits, buttons work, and sorting changes in both directions. There are no empty boxes instead of letters.

##### UI-3 — Check a list longer than one page

**Need:** Enough items for more than one page in Selling or Deals.

1. Press **Check all**. Write down the total it starts with.
2. Wait for the work to finish. Do not add or remove items during this check.
3. Go to another page of the list and look at the results.

**PASS if:** Items beyond the first page are included. The work ends with results or a clear failed-check count; it does not restart forever.

##### UI-4 — Use a keyboard button

**Need:** A cheap deal and a resale item in your bags.

1. Open **Settings > Key bindings** and assign an unused key to Buy.
2. Select and check a deal. Press the key to buy; if asked to confirm, press the same key again.
3. Try Buy next and Post next bought with their assigned keys too.

**PASS if:** The key acts on the item shown on screen. It does not buy or post again by itself.

#### Scanning and other work in the background

##### SCAN-1 — Make one full scan

**Need:** The Full scan button is enabled. If it shows a countdown, wait.

1. Press **Full scan** once.
2. Watch the status at the top and the counts on the left.
3. While rows are being read, try changing pages.

**PASS if:** The scan finishes and shows its counts. Pages still respond. If the server never replies, use SCAN-3.

##### SCAN-2 — Wait for the next automatic scan

**Need:** Automatic full scans are on in Settings.

1. Finish one full scan.
2. Keep the auction house open and let the Full scan countdown run out. Avoid buying/posting during this check.

**PASS if:** A new scan starts when allowed. It does not keep sending full scans every few seconds.

##### SCAN-3 — Check a missing or incomplete server reply

**Need:** Computer check; no live-game setup.

1. Run the automatic tests listed under Computer checks below for incomplete scans and timeouts.

**PASS if:** Parts of a reply do not become a complete scan. No-answer work times out after five minutes and respects the full-scan cooldown. An explicitly dropped request has its own retry rule.

##### SCAN-4 — Read a scan started by another addon

**Need:** Auctionator or auxForever is installed.

1. Open that addon and start its full scan.
2. Look at ForeverFlip while the scan completes.

**PASS if:** ForeverFlip reads the scan too. It does not start a second full scan to replace it.

##### SCAN-5 — Switch the sniper on and off

**Need:** The auction house is open and a full scan is not waiting.

1. Turn **Sniper** on. Leave it running and watch the round/check counts.
2. Browse an item in the normal Buy tab, then return to ForeverFlip.
3. Turn Sniper off.

**PASS if:** The counts grow while it is on, without freezing the window. New sniper work stops when it is off; an answer already on its way may still arrive.

##### QUEUE-1 — Ask for one price during Check all

**Need:** Several items can be checked.

1. Start **Check all**.
2. Choose another item and press **Check price**.
3. Wait for that result, then watch the remaining batch.

**PASS if:** Your selected item is handled before the rest of the waiting batch, once the current reply finishes. The rest continues afterwards.

##### QUEUE-2 — Interrupt a gear price check

**Need:** Several gear items and another item are available to check.

1. Start checking the gear list.
2. While it is working, select the other item and press **Check price**.
3. Wait for the remaining gear checks to finish.

**PASS if:** The manual check gets a turn. Gear checks continue afterwards without losing their progress. They do not claim to cancel a request already sent.

##### QUEUE-3 — Select an item without stopping its own check

**Need:** Check all is working through several items.

1. Select the item it is currently checking.
2. Wait for that item to get a result.
3. Leave it selected and watch the remaining list for about 15 seconds.

**PASS if:** The selected item completes its check. The rest does not remain stuck behind the selection. A checked deal can stay ready for up to five minutes.

##### QUEUE-4 — Click while the addon is busy

**Need:** A large scan or a large Analytics history.

1. Open another page while the addon is processing data.
2. If you have a cheap checked deal, press Buy, or post a cheap ready item.
3. Watch the status at the top.

**PASS if:** The click gets visible feedback. Purchase/post messages remain visible rather than being covered by an unrelated batch message. If the connection is busy, the addon asks you to wait.

#### Deals and buying

##### DEAL-1 — Buy one cheap vendor deal

**Need:** A cheap offer under **Deals > To vendor**. Skip if none exists.

1. Select it and press **Check price** if needed.
2. Read the item, quantity and total. Press **Buy**. Confirm if asked.
3. Check your auction mail and the journal.

**PASS if:** A successful purchase is recorded once and the correct item arrives. If the lot is gone or changed, the addon explains instead of recording a fake purchase.

##### DEAL-2 — Confirm on the same Buy button

**Need:** A cheap commodity deal, such as cloth or herbs.

1. Select and check the deal. Press **Buy**.
2. Read the quoted total. Press **Confirm** on the same button to accept it.
3. On a separate attempt, switch to another item before confirming.

**PASS if:** The first attempt buys only after confirmation. The second item does not inherit the old quote. An expired quote is requested again instead of being blindly confirmed.

##### DEAL-3 — Handle an error during a purchase

**Need:** Computer check, or a real error that occurs naturally.

1. Use the purchase-error computer checks below. Do not try to break the live connection.
2. If a live purchase shows an error, check chat, mail and the journal before trying to buy the same lot again.

**PASS if:** A generic error alone does not say another player won. A later successful purchase is recorded once. Without evidence of success, it is not booked as bought.

##### DEAL-4 — Buy after checking another item

**Need:** A cheap non-commodity item/gear deal and one other item.

1. Check the deal you want to buy.
2. Check a different item, then return to the first deal.
3. Press Buy. If it checks again, wait and press Buy when asked.

**PASS if:** The correct item is bought. Nothing is purchased later without your next click.

##### DEAL-5 — Read unit prices and total profit

**Need:** A deal with more than one unit.

1. Find **Buy at**, **Sells at**, **Profit** and **Qty** in the deal row.
2. Select it and compare the detail below the list.
3. Point at **Est./day** to read its explanation.

**PASS if:** Buy at and Sells at mean one unit; Profit means the whole deal. Est./day can be unknown or zero. It does not promise that an item will sell.

##### DEAL-6 — Keep buying within your limit

**Need:** A cheap deal and a spending limit smaller than its total cost.

1. In **Settings > Safety**, set the visit spending limit low enough to block this purchase.
2. Try to buy the deal.
3. Restore your normal setting after the check.

**PASS if:** The addon explains the limit and does not spend beyond it. The computer checks also cover per-item limits, ignored items, shopping quantities and leaving cheap units for others.

#### Sales history and Resale

##### DEMAND-1 — Check that a missing lot is not instantly called a sale

**Need:** Computer check; see confirmed-sales/repost checks below.

1. Run the computer checks for partial sales, missing lots and reposts.

**PASS if:** A reduced stack can supply sales evidence. A whole missing lot waits for a later scan to rule out a repost. Two full scans do not automatically mean confirmed whole-lot sales.

##### DEMAND-2 — Read an empty Resale page

**Need:** At least one saved full scan.

1. Open **Deals > Resale**.
2. If it is empty, read the explanation and the **Sales data** count on the left.
3. Collect more full scans when the normal countdown allows it. Check again.

**PASS if:** An empty page explains the current missing data or limits. It does not promise that exactly two scans will create offers. Profitable offers may still be absent.

##### DEMAND-3 — Get more gold after a budget rejection

**Need:** An empty Resale page that explicitly says your budget is too small.

1. Write down the last scan time.
2. Get more gold, for example by collecting a sale from the mailbox.
3. Return to the auction house and look at Resale before a new full scan.

**PASS if:** The addon considers the new budget using saved information. A lead may appear, but still needs a live price check before buying. It is also correct to show no offers if the other requirements are not met.

#### Posting items for sale

##### POST-1 — Open Selling without checking every bag item

**Need:** Several sellable items in your bags.

1. Open **Selling > My items**.
2. Look at the status before pressing any price-check or posting button.
3. Then request Post all or Check all yourself.

**PASS if:** Opening the page alone does not start a bag-wide price-check job. Requested work starts only when you ask for it. A ready item can post before unrelated missing prices are checked.

##### POST-2 — Post all stacks of one item

**Need:** 40 cheap sellable units of one commodity. Use a known price above the vendor value. Hide other for-sale items for this check.

1. Split the 40 units into stacks of 10, 10 and 20. Remove any keep rule for this item.
2. Press **Post AH-worthy** once. Wait for confirmation and look in **My auctions**.
3. For the second part, start again with 40 units in your bags. Open **Rule...**, set **keep** to 25, save, then press Post AH-worthy.

**PASS if:** The first part posts 40 units in one request if the client allows 40. The second posts 15 and leaves 25 in your bags. Do not run the second part with empty bags from the first part.

##### POST-3 — Wait before posting the next item

**Need:** Two different cheap ready-priced items in your bags.

1. Press **Post all** once.
2. While it waits for confirmation, try pressing it again.
3. After the first post is confirmed, press once more for the next item.

**PASS if:** There is one post at a time. A second item needs another click. If the game asks for a price warning confirmation, it is not accepted automatically.

##### POST-4 — Keep an item out of the posting queue

**Need:** A cheap item in Selling and no other ready item for this check.

1. Select the item and press **Hide**. Try Post all.
2. Open **Hidden**, select it and return it to sale.
3. Open **Rule...**, set keep to the number of units you own and save. Try Post all again.

**PASS if:** A hidden item is not posted. Returning it makes it visible again. Keeping every unit leaves it in your bags. Price floors, maximums and guessed prices are checked separately by the computer.

##### POST-5 — Keep your typed price

**Need:** A cheap sellable item.

1. Select it and let the addon fill a suggested price.
2. Type your own price. Refresh the price check.
3. Move the selected item to another bag slot. Read the price and item before posting.

**PASS if:** Your typed price remains. The selection still refers to the same item, not a different item now in the old slot.

##### POST-6 — Check and cancel one own auction

**Need:** An auction you own and are willing to cancel.

1. Open **Selling > My auctions** and press **Check prices**.
2. Read the result. If only your lots are listed, it should explain that.
3. For an undercut lot, use the cancel action once and check your mail.

**PASS if:** The chosen auction is cancelled once, not repeatedly. If there is no suitable lot, skip the cancellation part.

##### POST-7 — Use the Undercuts advice

**Need:** An own auction with a cheaper competing offer.

1. Open **Selling > Undercuts** and select it.
2. Read the choices: wait, repost, buy out or vendor.
3. If you choose a buyout, inspect the added Shopping quantity before buying.

**PASS if:** The choices show their estimates. A buyout target uses your resale plan and goes down as its requested units are bought. Do not buy just to obtain a PASS; skip the buying part if you do not want the trade.

#### Mail, gold and the other pages

##### BOOK-1 — Record an auction sale once

**Need:** A sold multi-unit auction and its gold mail.

1. Note the item count and gold in the mail.
2. Press **Take auction mail**.
3. Open **Analytics > Journal**, then reload and check it again.

**PASS if:** The sale has the correct count and money and is not added a second time after reload.

##### BOOK-2 — Take auction mail only

**Need:** Auction mail plus an unrelated ordinary letter.

1. Open the mailbox and press **Take auction mail**.
2. Look at what remains in the inbox.
3. On a separate run, close the mailbox while collection is active.

**PASS if:** Ordinary mail is left alone. Closing the mailbox stops the job. Full bags and refused mail are also covered by computer checks.

##### BOOK-3 — Record a vendor sale once

**Need:** Cheap vendor stock tracked by ForeverFlip.

1. Open a merchant and use the ForeverFlip sell button.
2. After the bags update, look at the sell list and journal.
3. With another tracked item, sell it manually to the merchant and check the journal again.

**PASS if:** Sold items leave the list. Each sale is recorded once, whether the addon button or a manual sale was used.

##### FEATURE-1 — Add a shopping item

**Need:** An item link and an item you want to track.

1. Add it to **Shopping list** with a wanted quantity and price.
2. Check its price and look for a matching Shopping deal.
3. Remove the entry or ignore it and check the list again.

**PASS if:** The entry and eligible deals follow the quantity/price you chose. Ignored items do not remain purchase targets. No matching offer is a valid result.

##### FEATURE-2 — Show a learned recipe

**Need:** A character with a profession.

1. Open the profession window once.
2. Open **Crafting** and choose a recipe.
3. Use **Shop materials** when you have some, but not all, materials in your bags.

**PASS if:** The recipe appears. Missing prices are explained. The shopping list asks for missing materials rather than ones already in your bags. Disenchant-specific cases need an enchanter or computer checks.

##### FEATURE-3 — Place and track a bid

**Need:** A cheap near-expiry auction you actually want to bid on.

1. Open **Deals > Bids**, select it and check the price.
2. Read the amount and place the bid.
3. When a won/outbid mail arrives, collect it and inspect the journal.

**PASS if:** The bid and its final outcome are tracked once. If there is no suitable auction or you do not want to bid, skip it.

##### FEATURE-4 — Keep two auction houses separate

**Need:** Access to your faction house and a neutral house.

1. Scan at your faction auction house and note the house name.
2. Travel to a neutral auction house and open ForeverFlip.
3. Return to the first house later.

**PASS if:** The house label and stored prices follow the house you opened. Neutral calculations start with a 15% cut. Hardcore and map edge cases have computer checks too.

##### FEATURE-5 — Read history and export the journal

**Need:** Some saved history and journal entries.

1. Open **Analytics** and select different views.
2. Right-click a deal to open its history. Point at an item tooltip.
3. Type `/ff export` and copy the CSV text if needed.

**PASS if:** The pages/charts open without errors and show price age or missing data. Export opens copyable journal text. Weekly advice needs enough history; skip that part on a fresh profile.

##### FEATURE-6 — Keep saved data after reload

**Need:** Existing stock, journal entries and saved settings.

1. Write down one stock count, one journal entry and one setting.
2. Type `/reload` and open the same pages.
3. If you use another character/house, check its own saved view too.

**PASS if:** The recorded data is still present under the correct character/house. Test the missing-save warning only with a disposable profile or the computer checker, not by deleting your real save.

#### Sharing and the Windows helper

##### SHARE-1 — Copy and share scan history

**Need:** A completed scan; a second player for the receiving part.

1. Open **Settings > Sharing** and export the scan history as text.
2. Check that the copied text starts with `FF3|`.
3. Have the second player receive/import it and look at Received.

**PASS if:** Current history is readable by the other addon. Reimporting the exact same history is rejected as a duplicate. If you have no second player, skip that part.

##### SHARE-2 — Receive shared data without creating a fake purchase

**Need:** Shared or community history.

1. Receive/import it, then type `/reload`.
2. Open history and compare stock and journal with your earlier notes.
3. Import the same history again.

**PASS if:** History can update; stock and journal do not gain a fake purchase/sale. Repeated data is not counted again. FF1 community support and ignoring old FF2 sales are computer-checked compatibility paths.

##### SYNC-1 — Look at the new helper window

**Need:** The beta.6 EXE on Windows.

1. Start it. Look for the blue quill in the top-left title bar.
2. Open **Show activity** and close it again.
3. If possible, repeat at another Windows display scale, such as 125%, 150% or 200%.

**PASS if:** The icon, pictures, switches and buttons appear. Text fits and nothing important is cut off. If you cannot change scale, mark that part SKIP.

##### SYNC-2 — Choose and remember the game folder

**Need:** Your Forever game folder.

1. Press **Change** beside GAME. Choose `_forever_` or its installation parent.
2. Close and reopen the helper.
3. If you have more than one installation, check which path it chose.

**PASS if:** It remembers the right Forever installation. It asks for a choice when needed and does not silently use Retail or Classic.

##### SYNC-3 — Sign in and sign out

**Need:** A GitHub account.

1. Press **Sign in with GitHub**. Enter and approve the shown code yourself on the opened GitHub page.
2. Restart the helper and check the account line.
3. Press **Sign out** to remove the helper-stored sign-in.

**PASS if:** The helper remembers the approved sign-in and removes its own stored token on sign-out. If another login source (CLI/config/environment) remains, it can still show an account; that alone is not a failed sign-out.

##### SYNC-4 — Send one saved full scan

**Need:** GitHub sign-in and sharing enabled in the helper.

1. In the game, turn on **Settings > Sharing > Keep my full scans for the ForeverFlip Sync helper**.
2. Make a new complete scan, then type `/reload` to save it to disk.
3. In Sync press **Sync now**, then **Show activity**.

**PASS if:** Activity shows the scan submission and later the server answer. Check that answer, not just Community prices updated: that message only describes a download. Record a rejection reason if the server rejects it.

##### SYNC-5 — Send saved scans after a restart

**Need:** An unsent saved scan; helper sharing already switched on.

1. Close and reopen the helper.
2. Wait for its sign-in check and automatic sync, or press Sync now.
3. Read **Show activity** without toggling sharing or making another game save.

**PASS if:** The saved scan is considered for upload after the sign-in is found. Starting a price download first must not leave sharing silently off.

##### SYNC-6 — Retry after a connection failure

**Need:** Computer check; or a connection failure that happens naturally.

1. Use the retry computer checks below.
2. If a real failure occurs, restore the connection and press Sync now. Read Show activity.

**PASS if:** Successful uploads stay acknowledged; unfinished ones can retry. The error names the failed operation. A price download can still be attempted when sharing fails.

##### SYNC-7 — Download and read community prices

**Need:** Sync automatic downloads on, or the Sync now button.

1. Press **Sync now**, then look at the PRICES row.
2. If the helper created `ForeverFlip_Shared` for the first time, restart WoW. For later data updates, type `/reload`.
3. In the game, inspect community information under Sharing.

**PASS if:** Available downloaded prices are loaded. No community prices yet can also be correct if none exists. Your own returned summaries do not repeatedly add the same sales.

##### SYNC-8 — Choose beta or stable addon updates

**Need:** The helper and an isolated game copy for installation experiments.

1. Look at the installed addon version shown in the helper.
2. Turn **Beta tester** on and check which update is offered.
3. Turn it off again. If you do not have a separate test copy, stop before an installation experiment.

**PASS if:** Beta mode can offer pre-releases. Turning it off does not install an older version. Hash checks, backups and rollback are covered by computer checks. The helper EXE itself must still be downloaded separately.

##### SYNC-9 — Keep the helper responsive

**Need:** A saved scan large enough to take noticeable processing time.

1. Press Sync now and open Show activity while it works.
2. Try moving the helper window or changing the log view.
3. Close it during an active sync.

**PASS if:** The window responds. Closing waits for the active sync to finish rather than silently losing its saved progress. Command-line and TLS details are covered by the computer checker.

#### Computer checks for hard-to-create situations

Run these from the repository root. The program creates a pretend auction house and checks the
result for you. `OK` means the group passed; `FAILED` means copy the failure for the developer.
These tests do not buy real items or upload your scans. A skipped window test still needs a real
Windows check using the cards above.

| What is checked | Run this command |
|---|---|
| Missing/partial full-scan replies, purchase/post errors and duplicate actions | `python -m unittest discover -s tests -p "test_audit.py"` |
| A generic purchase error followed by success, or a late answer | `python -m unittest discover -s tests -p "test_purchase_confirmation.py"` |
| Partial sales, missing lots and repost protection | `python -m unittest discover -s tests -p "test_lot_sales.py"` |
| Current confirmed-sales rates and the separate flow fallback | `python -m unittest discover -s tests -p "test_demand.py"` |
| Price rules, minimum/maximum, keep and automatic duration | `python -m unittest discover -s tests -p "test_selling_rules.py"` |
| Posting limits, all bag stacks and retained units | `python -m unittest discover -s tests -p "test_post_quantities.py"` |
| Safe gear pause/resume and manual request priority | `python -m unittest discover -s tests -p "test_foreground.py"` |
| Failed submissions, retry, changed saves and readable errors | `python -m unittest discover -s tests -p "test_sync_helper.py"` |
| Delayed account discovery and the window icon setup | `python -m unittest discover -s tests -p "test_sync_gui_state.py"` |
| Bad update packages, hash checks, backups and rollback | `python -m unittest discover -s tests -p "test_addon_update.py"` |
| All groups, including mail, bids, crafting and compatibility | `python -m unittest discover -s tests -p "test_*.py"` |

#### Write down a result

Copy this and fill in the blanks:

```text
Test ID: POST-2
Addon / helper version: 1.2.0-beta.6 / 1.2.0-beta.6
Result: PASS / FAIL / SKIP
What I had before the test:
What I clicked:
What I saw afterwards:
Screenshot or activity message:
```

## Beta testing

Use [the beta.6 release](https://github.com/Danissemo/ForeverFlip/releases/tag/v1.2.0-beta.6), or turn on
**Beta tester** in the [Sync helper](community.md#addon-updates-and-beta-testing) for addon updates.
Install the matching helper EXE separately. Follow the current checklist against the installed
build; automated checks do not establish live auction timing or real GitHub upload acceptance.

Report an [issue](https://github.com/Danissemo/ForeverFlip/issues/new/choose) with the checklist ID,
addon/helper version, what you did, expected/actual result, and whether it reproduces. Include a
screenshot for visual faults. For Lua failures, `/reload` and provide the relevant `errors` entries
from `WTF/Account/<ACCOUNT>/SavedVariables/ForeverFlip.lua` plus `/ff diag`. For Sync failures, include
the relevant **Show activity** lines and submission outcome. Never include tokens or sign-in codes.

## Automated tests

To run the full checker:

1. Open the source project folder: it contains `README.md`, `tests`, `sync` and `ForeverFlip`.
   This is not the installed addon folder inside the game.
2. Open a terminal in that folder. Python must be installed; the project's CI uses Python 3.12.
3. Paste the commands below one at a time. The first installs the test libraries; the second runs
   the tests. `OK` means they passed. If it says `FAILED`, save the error text for the developer.
4. The last command checks Lua formatting and needs StyLua installed. It does not run the game.

```bash
python -m pip install -r requirements-dev.txt
python -m unittest discover -s tests -p "test_*.py"
stylua --check ForeverFlip
```

The current checker discovers **509 tests in 38 modules**. The Lua tests load the actual TOC files
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
| `test_demand.py` | Confirmed-sales rates, observed zero, price levels, age, smoothing and priority over flow; separate tests retain the flow-only fallback. |
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

### Automated checker maintenance

Confirmed-sales tests must use records produced by `Market.recordSales`; flow-only examples belong
in the explicitly named fallback tests. Check that a valid observed record with no sales near a
high price gives zero, while absent observations remain unknown. Batch retries may revisit a failed
item once after the other items; do not label that intermediate failure as a permanent final result.

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
