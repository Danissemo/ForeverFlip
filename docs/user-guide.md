# ForeverFlip user guide

This guide covers everything you see in game: the auction house tab and its pages, the mailbox and
merchant buttons, tooltips, alerts, settings and slash commands. To learn how the numbers are
calculated, read [How it works](how-it-works.md).

- [The ForeverFlip tab](#the-foreverflip-tab)
- [Top bar](#top-bar)
- [Deals pages](#deals-pages)
- [Buying](#buying)
- [Sell my items](#sell-my-items)
- [My auctions](#my-auctions)
- [Statistics by item](#statistics-by-item)
- [Analytics](#analytics)
- [Journal and profit](#journal-and-profit)
- [Settings](#settings)
- [Outside the auction house](#outside-the-auction-house)
- [Slash commands](#slash-commands)
- [Messages](#messages)
- [Troubleshooting](#troubleshooting)
- [A typical session](#a-typical-session)

---

## The ForeverFlip tab

When you open the auction house, a **ForeverFlip** tab appears next to the game's own tabs (Buy,
Sell, Auctions). If [LibAHTab](https://www.curseforge.com/wow/addons/libahtab) is installed, the tab
is created through it so it sits next to the tabs of other addons.

The window has three parts:

- **Top bar:** scan and sniper buttons and a status line. A thin yellow bar along the top edge shows
  the progress of the current task.
- **Left column:** the page list and, below it, a short summary of the last scan.
- **Right side:** the selected page. Most pages have a table on top and an explanation and buttons
  at the bottom.

ForeverFlip remembers the last page you opened.

## Top bar

| Control | What it does |
|---|---|
| **Full scan** | Asks the server for every auction of the house. The button shows a countdown while the 15-minute cooldown runs. |
| **Sniper: ON / OFF** | Turns the [sniper](#sniper) on or off. |
| **Check all statuses** | Checks every entry of the current page on the auction house, one search after another. It works on All deals, Vendor deals, Resale, Bags (Sell my items) and My auctions. While it runs the button shows `Checking <page>: done/total`. Afterwards it shows `Checked ...`, with the number of failed searches if any. |
| Status line | The current task (`Reading auctions 12000 / 231000`, `Evaluating items ...`), the last message, and while the sniper runs, how many items it watches and how many checks it has made. |

### Full scan

A full scan runs in stages, all shown on the progress bar:

1. **Waiting for the auction house to send the full scan.** The server answers in a few seconds to a
   minute. If it does not answer in 45 seconds, ForeverFlip says so and tries again a minute later.
2. **Reading auctions.** The scan is read in small portions per frame, so the game keeps running
   smoothly.
3. **Loading item data.** Some items are not in the game's cache yet. ForeverFlip asks the game to
   load them and waits up to 30 seconds.
4. **Evaluating items.** Each item is checked for a vendor deal and a resale.

The server allows **one full scan per 15 minutes per account**. With **Full scan every 15 minutes** on
(Settings, on by default), ForeverFlip starts the next scan by itself when the cooldown ends, if the
auction house is open and no other action is running.

If another addon (Auctionator, TSM, ...) requests a full scan, ForeverFlip reads the result too and
says so in the status line.

The last scan and its deals are saved. After a `/reload` or a new login they are shown again until
the next scan, but every deal has to be checked again before you can buy it.

### Sniper

Between full scans, the sniper re-checks the items that are most often close to a deal, up to 150
of them, one search per second. A new cheap listing is found within seconds, not at the next full
scan. Items checked less than a minute ago are skipped. The sniper pauses while you buy, post or run
a manual check.

## Deals pages

There are three deal pages:

- **All deals:** every deal, best first.
- **Sell to vendor (no risk):** lots priced below the vendor sell price. You buy them and sell them
  to any merchant. Profit is certain as long as the lot is still there.
- **Resale:** lots priced well below the next seller, for items that are measured to sell at the
  resale price. You buy them and post them again on the auction house.

### Columns

| Column | Meaning |
|---|---|
| Item | Icon and name. Hover for the game tooltip. |
| Price | The highest unit price you pay in this deal (the last lot taken). |
| Qty | Units to buy. |
| Cost | Total price of those units. |
| Profit | Money you keep after selling, after the 5% cut and the deposit risk for a resale. |
| Status | See below. |
| Est./day | For resale deals: units per day that sell near the resale price. |

Click a column header to sort by it, and click it again to reverse the order. Use **<** and **>** to
change pages.

### Statuses

| Status | Meaning |
|---|---|
| **ready** (green) | Checked on the auction house in the last 45 seconds. You can buy it. |
| **checking...** | The exact search for this item is running now. |
| **queued** | Waiting for its turn to be checked. |
| **check again** | It was checked more than 45 seconds ago. Click it to check it again. |
| **from scan** | Found by the full scan and not checked yet. |
| **old scan** | Found by a scan more than 20 minutes ago. The lots may be gone. |
| **not enough money** (red) | The deal costs more than you carry. |

Deals that have not been checked are dropped 15 minutes after the scan that found them. A deal that
no longer holds when checked disappears from the list.

### Details of the selected deal

Under the table, the selected deal is explained in one or two sentences:

- For a vendor deal: its return. It is sold to a vendor at once, with no risk.
- For a resale: its return and roughly how many days the units take to sell at the measured rate.
  The sentence also says when the sales data is old.
- When the [time-of-week pattern](how-it-works.md#time-of-week-pattern) of the item is known, it says
  when prices are usually higher, which is the better time to post.

With **Check found deals automatically** on (Settings), ForeverFlip checks the best unchecked deals
by itself, one search per second.

## Buying

1. Click a deal. If it has not been checked in the last 45 seconds, it is checked now. Wait for
   **ready**.
2. Click **Buy**.
   - **Stackable goods (commodities)** are bought by quantity. The game first quotes the total price.
     When the status line says *Price confirmed*, click **Confirm purchase**. If the quoted price is
     higher than the checked deal, the purchase is cancelled and the deal is checked again. Use
     **Cancel** to drop the quote.
   - **Items and gear** are bought one auction per click, because the server sells one lot per
     purchase. After each purchase the item is checked again so the next click buys the next lot.
3. When the purchase goes through, the status line shows *Purchase recorded*. The units are added to
   your stock at their real cost and logged in the journal.

If someone was faster, the purchase fails and costs nothing. The deal is checked again.

If the game does not answer within 30 seconds, the purchase is kept as **unknown**. Settle it on the
[Journal](#journal-and-profit) page with **It was bought** or **Not bought**. The chat line *You won
an auction for ...* tells you which one is right; ForeverFlip also reads that line and settles the
purchase by itself when it appears.

**Check price** next to Buy runs an exact search for the selected item without buying.

## Sell my items

This page lists the items in your bags that can be sold on the auction house. Bound items are left
out.

| Column | Meaning |
|---|---|
| Qty | Units in the bags. |
| Cost each | What you paid per unit, if it was bought through ForeverFlip. |
| Listed | Units you already have on the auction house. |
| Note | The suggested price, the cheapest other seller and your break-even price, or a hint about selling time. |

At the bottom:

- Selecting an item reads its current listings at once and fills in the quantity.
- **Price each**, **Quantity** and **Duration** (2, 8 or 24 hours) fields, and **Post** to create the
  auction for the selected item. The price field accepts `1g 20s 5c`, `20s`, `1.5g` or a bare number
  of silver.
- **Check price** reads the current listings of the selected item. A price stays fresh for 5 minutes.
- **Post next bought (N)** handles the items you bought for resale, oldest first, still in the bags
  and not yet listed. N is how many are waiting.
  - **First click:** if there is no fresh price, ForeverFlip reads the listings
    (*Reading the current price first*).
  - **Next click:** posts the item one legal price step below the cheapest other seller, and
    **never below your break-even price**.

The suggested price is one step below the cheapest other seller. Gear and plain items are listed in
whole silver; commodities may use copper. With no other seller, the usual price from the scans is
used. If the game asks for a confirmation (for example, the price is far from the market), the status
line says so and the next **Post** click confirms.

## My auctions

Your active auctions, with:

| Column | Meaning |
|---|---|
| Qty | Units in the auction. |
| My price | Your unit price. |
| Cheapest other | The cheapest listing of another seller, after a check. |
| Status | **cheapest**, **undercut**, or **sold, gold in the mail**. |
| Time left | The game's remaining time band. |

Buttons:

- **Check prices** checks your listed items one after another, one search per second.
- **Refresh** reloads your auctions from the server.
- **Cancel auction** cancels the selected auction. The item comes back by mail. **The deposit is
  lost**, and the game may charge more for cancelling.

When an auction is marked sold, the sale is booked once with its real quantity and price. The
profit is calculated against the average cost of your stock.

## Statistics by item

One row per item you have traded through ForeverFlip:

| Column | Meaning |
|---|---|
| Bought | Units bought. |
| Sold | Units sold (auction house and vendor). |
| Profit | Money received minus the cost of the units sold. |
| In stock | Units bought and not sold yet. |
| Days to sell | Average days between buying and selling a unit. |
| Note | **stale** when stock has been held for 3 days or more without a sale. |

When stock bought for resale does not sell, ForeverFlip trusts the scan estimate for that item less:
half after a day without a sale, a quarter after three days. Fewer resale deals for it are suggested
until a unit sells again.

## Analytics

The page has two parts.

**Your results** for the last 7 or 30 days:

- profit and profit per day, split into auction resale and vendor deals;
- number of sales, the share that made a profit, and the return on cost;
- units and money bought;
- money held in stock, and stock that has not sold for 3 days or more;
- average days to sell and how much of the stock turns over per day;
- your best and worst items, and a bar chart of profit per day.

**The market** of the current auction house, built from the saved scan history:

| View | Shows |
|---|---|
| Below usual | Items whose cheapest price today is well below their usual price, weighted by how much of the item sells. |
| Sells most | Items with the most units sold per day near the usual price. |
| Falling | Items whose usual price fell the most against the 5-day average. These may be good to buy. |
| Rising | Items whose usual price rose the most. These may be good to sell from stock. |
| Cheap now | Items that sell regularly and are usually cheaper at the current time of the week. |
| Sell now | Items you hold in stock that are usually dearer at the current time of the week. |

Columns: usual price, cheapest today, change, units per day, and for the time-of-week views, the
cheapest and dearest times. Click a row to check the item on the auction house now.

The lists fill in after a few full scans. Price changes need scans on two different days, and the
time-of-week pattern needs scans on at least four weekdays.

## Journal and profit

- A summary of the last 7 days: money spent, money received, profit of closed sales, and stock
  bought and not sold yet.
- **Unknown purchases**, if any, with **It was bought** and **Not bought** to settle them.
- The latest entries of the journal: purchases, auction sales, vendor sales and failed purchases.

The journal keeps the latest 500 entries per character.

## Settings

| Setting | Default | Meaning |
|---|---|---|
| Minimum profit of a vendor deal | 10c | Smaller vendor deals are not listed. |
| Minimum profit of a resale | 1s | Smaller resale deals are not listed. |
| Minimum resale return, % | 20 | Profit divided by cost, for resale deals. |
| Money one deal may use, % | 80 | The share of the gold you carry that one deal may spend. |
| Money one item may hold, % | 30 | The share of your gold one item may hold, counting stock already bought plus the new resale. |
| Smallest profit with a sound notice | 50c | Smaller deals are listed without an alert. |
| Check found deals automatically | on | Checks the best unchecked deals by itself, one search per second. This option is reset when you log in. |
| Full scan every 15 minutes | on | Starts a full scan whenever the cooldown ends and the auction house is open. |
| Sniper | on | See [Sniper](#sniper). |
| Sound and screen notice | on | See [Alerts](#alerts). |
| Price history in item tooltips | on | See [Tooltips](#item-tooltips). |
| Language | client | English or Ukrainian. Ukrainian clients start in Ukrainian; other clients start in English. Takes effect after `/reload`. |

Money fields accept `1g 20s 5c`, `20s`, `1.5g` or a bare number of silver. Click **Save** to apply
them.

## Outside the auction house

### Alerts

When a checked deal can be bought and its profit is at least the alert minimum, ForeverFlip:

- plays the auction house sound;
- flashes the game icon on the taskbar;
- shows a yellow line in the middle of the screen;
- prints the deal in chat.

Each item alerts once, and alerts again only after 10 minutes or if the profit grew by a fifth.

### Item tooltips

For items seen in the scans, the tooltip gets extra lines:

- **ForeverFlip usual price**: the typical asking price from the last scan.
- **cheapest today / 5 days**.
- **gone per day near the usual price**: the measured sales rate.
- **cheapest / dearest time**: when the time-of-week pattern is known.

### Mailbox

At a mailbox, **Take auction mail (N)** takes everything from auction house mail: gold from sales,
won items, and expired or cancelled items. It takes one mail every 0.4 seconds, because faster
looting causes errors. It skips player mail and any mail with cash on delivery. It stops when the
mailbox closes, your bags are full or no auction mail is left, and prints a summary in chat.

### Merchant

At a merchant, ForeverFlip adds two things:

- **Sell vendor deals (N)** sells every item in your bags that was bought as a vendor deal, and
  books the sales in the journal.
- **ForeverFlip: buy here, sell on the auction house** is a panel listing the items this merchant
  sells for less than they fetch on the auction house. For each item it shows the price here, the
  expected auction price, the profit per unit (after the cut and deposit) and the measured sales per
  day. **Buy** purchases the suggested quantity: no more than about one day of sales, and within
  your budget. The items are booked as stock for resale.

## Slash commands

| Command | Action |
|---|---|
| `/ff`, `/foreverflip` | Version and a short hint. |
| `/ff diag` | Statistics of the last full scan: auctions total, read, skipped and your own; items; items with a known vendor price; items below vendor price; items still collecting sales data; deals. |
| `/ff rescan` | Clears the scan cooldown. Use it when the server did not answer a scan and you do not want to wait 15 minutes. The server may still refuse. |
| `/ff lang en`, `/ff lang uk` | Sets the language. Type `/reload` afterwards. |

## Messages

| Message | Meaning |
|---|---|
| A full scan is allowed once per 15 minutes. | Wait for the countdown on the Full scan button. |
| The auction house did not answer the full scan ... | Another addon may have used the 15-minute window. ForeverFlip tries again in a minute. |
| The auction house returned an empty scan. | Try again later. |
| The auction house is busy. | The server is throttling requests. Try again in a moment. |
| Checking the current price first... | Buy was clicked on a deal that is not freshly checked. It is being checked now. |
| The price changed. The deal is checked again. | The quote for a commodity was higher than the checked price. |
| The price offer expired. Press Buy again. | The commodity quote timed out before you confirmed. |
| The purchase failed (someone was faster). | The lot was sold to someone else. Nothing was spent. |
| No answer from the auction house. Settle the purchase in the Journal. | See [Buying](#buying). |
| The game asks for a confirmation: press Post again. | The game warns about the posting price. |
| Not enough money. | The deal costs more than you carry. |
| Wait for the current action. | A purchase or post is still running. |

Errors inside the addon are printed once in chat, as `ForeverFlip error: ...`. The latest 20 are
saved in the SavedVariables file (see [Troubleshooting](#troubleshooting)).

## Troubleshooting

**No deals after a scan.**
- Vendor deals depend on the market at that moment; often there are none.
- Resale deals need sales data, so they appear after two or three scans.
- Check the minimums in Settings.
- `/ff diag` shows how many items are still collecting data.

**The scan never starts, or waits forever.** Another addon may have used the account's
15-minute window. Wait for the countdown, or use `/ff rescan` if the server did not answer.

**Buy stays disabled.** The deal must be **ready** (checked in the last 45 seconds) and no other
search or purchase may be running. Click the deal to check it again.

**Resale estimates look too optimistic.** Expired and cancelled auctions look like sales between two
scans. ForeverFlip limits each purchase to about one day of sales (two units while only one pair of
scans exists) and lowers its trust when your own stock does not sell. Raise **Minimum resale
return** to be more careful.

**Reporting a bug.** Type `/reload`, then open
`WTF/Account/<ACCOUNT>/SavedVariables/ForeverFlip.lua` and copy the `errors` section into an issue.
The result of `/ff diag` helps too.

## A typical session

1. Open the auction house. The automatic scan starts as soon as the cooldown allows.
2. Buy the **ready** vendor deals. Keep the sniper on and react to alerts.
3. Check the **Resale** page after a few scans. Buy deals with a good return and a good Est./day.
4. Use **Sell my items → Post next bought** to list your purchases.
5. Every so often, run **My auctions → Check prices** and repost the undercut lots.
6. At a mailbox, **Take auction mail**. At a merchant, **Sell vendor deals**.
7. Look at **Analytics** to see which items actually make money, and drop those that do not.
