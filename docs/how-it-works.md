# How ForeverFlip works

This document explains where the numbers come from: scanning, the usual price, sales estimates,
deal maths, the money limits and the safety rules. Constants are given with the file that defines
them, so you can check them in the code.

- [Item keys](#item-keys)
- [Full scan](#full-scan)
- [Usual price](#usual-price)
- [Sales estimate](#sales-estimate)
- [Deal evaluation](#deal-evaluation)
- [Money limits](#money-limits)
- [Live verification](#live-verification)
- [Sniper](#sniper)
- [Selling](#selling)
- [Accounting](#accounting)
- [Time-of-week pattern](#time-of-week-pattern)
- [Market analytics](#market-analytics)
- [Merchant offers](#merchant-offers)
- [Safety rules](#safety-rules)
- [Known facts about WoW Forever](#known-facts-about-wow-forever)

---

## Item keys

Every item is identified by a string key (`Util.lua`):

| Key | Kind | Bought |
|---|---|---|
| `c:<itemID>` | commodity (stackable goods) | by quantity, with a price quote and a confirmation |
| `i:<itemID>` | plain item (bags, recipes, ...) | one auction per purchase |
| `g:<itemID>:<name>` | gear | one auction per purchase |

On WoW Forever one gear item ID has several random endings ("of the Wolf", "of the Bear") that only
the full name tells apart, so gear keys include the lower-case name.

Price steps: gear and plain items are listed in **whole silver**, commodities in copper.
`U.below(price, kind)` gives the highest legal price strictly below a price.

## Full scan

`Scan.lua`. `C_AuctionHouse.ReplicateItems` returns every auction of the house. The server allows
this **once per 15 minutes per account** (`S.COOLDOWN = 900`).

1. **Request.** The scan job is created before the request, because the answer may arrive during
   the call itself. WoW Forever does not always send `REPLICATE_ITEM_LIST_UPDATE`, so the job also
   polls the number of replicated auctions once a second. The scan counts as arrived when that
   number has changed and has stopped growing. With no answer in 45 seconds, the job gives up and
   the next attempt is allowed a minute later.
2. **Reading.** Rows are read in portions under a time budget per frame. Bid-only auctions and your
   own auctions are skipped. Rows whose item is not in the game cache are deferred; the item data is
   requested at most 40 items per second (`AH.lua`), and the deferred rows are retried for up to
   30 seconds (`S.RECOVER`).
3. **Grouping.** Rows are grouped per item key. For each item ForeverFlip keeps the **40 cheapest
   auctions** (`S.ROWS`) and a **price histogram** of every listed unit.
4. **Evaluation.** Each item is evaluated in portions per frame: usual price, sales between scans,
   daily lows, time-of-week pattern, then a vendor deal and a resale ([Deal evaluation](#deal-evaluation)).
   Items with an unknown vendor price are kept aside (up to 6000) and evaluated again when their data
   loads.
5. **Saving.** The scan statistics, the deals, the items still waiting for a vendor price and the
   sniper list are saved, so they survive a `/reload`.

Items that have not appeared in a full scan for 14 days are removed from the saved history.

If another addon requests a full scan, ForeverFlip reads the same result and treats the 15-minute
window as used.

## Usual price

`Market.bucketAdd`, `Market.bucketValue`. Every listed unit goes into a histogram with **2% wide
price buckets**. The histogram is stored as a flat array to save memory. The **usual price** of an
item is the cheapest price of the bucket that reaches **30% of the listed volume**:

- the few cheapest units (bargains) do not set it;
- the expensive tail never reaches it.

Resale prices never go above the usual price.

## Sales estimate

`Market.recordFlow`, `Market.demandAt`. The auction house API does not report sales, so ForeverFlip
measures them from the listings that disappear between two full scans.

For four price levels (60%, 75%, 90% and 105% of the usual price, `M.LEVELS`), each scan stores how
many units are listed at or above that level. At the next scan, if it comes no more than 3 hours
later, the units that disappeared at each level count as sold there. The totals and the observed
hours decay with a **2-day half-life**, so recent behaviour counts most.

- **Cheap lots do not inflate the estimate.** Lots taken by other resellers below a level do not
  count as sales at that level.
- **It is an upper bound for one reason and a lower bound for another.** Expired or cancelled
  auctions also disappear, so they count as sales. New listings hide sales.
- **Smoothing.** Units per day are computed as if 4 more hours had been watched with no sale
  (`M.PRIOR_HOURS`). One unit gone in a single 15-minute pair is about 5.6 a day, not 96. The prior
  fades as data accumulates.

`demandAt(h, price)` returns the units per day sold at or above 85% of `price`, rounded to the level
that does not overcount, plus the number of scan pairs. With 0 pairs there is no estimate yet:
the item is still *collecting*.

## Deal evaluation

`Market.evaluate`. Input: an item's listings sorted cheapest first, its kind, the vendor price, the
usual price, the sales history and the money limits. Output: the best deal, or a reason why there is
none.

### Vendor deal

Take every unit priced below the vendor sell price, within budget. Profit is
`qty × vendor price − cost`. There is no auction cut, no deposit and no waiting: the units are sold
to any merchant right away. The deal is kept if profit ≥ **Minimum profit of a vendor deal**.

### Resale

Try every prefix of the cheapest listings, up to 40 auctions. For a prefix that ends at listing *i*:

1. **Exit price** is one legal step below the cheapest unit left after buying. A resale above that
   lot would not sell before it does. The exit is also capped at the usual price.
2. **Profit** = `net(exit, qty) − cost − deposit risk`, where `net` removes the **5% auction cut**
   and the deposit risk counts the deposits lost if the lots do not sell: one per auction for items
   and gear, one per stack for commodities. The deposit is estimated as
   `max(1 silver, 15% of the vendor price × units)`.
3. **Demand.** The sales estimate at the exit price, multiplied by the item's
   [trust factor](#accounting).
   - With no scan pair yet, the item is still collecting data and gets no resale.
   - At least **0.5 units per day** must sell.
   - The units bought plus the stock already held may not exceed **one day of sales**. While there
     is only one scan pair, the cap is **2 units**.
4. **Thresholds.** Profit ≥ **Minimum profit of a resale** and return (`profit / cost`) ≥
   **Minimum resale return**.

The prefix with the highest profit wins. If both a vendor deal and a resale exist, the one with the
higher profit is shown.

When there is no deal, the reason is one of: no price gap, budget, profit too small, still
collecting sales data, not selling, or enough stock already held.

## Money limits

`Deals.lua`, applied to every evaluation:

- **Money one deal may use** (default 80%): a deal may spend at most this share of the gold you
  carry.
- **Money one item may hold** (default 30%): for a resale, the cost of the stock already held of
  that item plus the new purchase may not exceed this share of your gold.

## Live verification

`Deals.lua`. A deal from the full scan is only a lead. Before it can be bought, an exact search
(`C_AuctionHouse.SendSearchQuery`; `SendSellSearchQuery` for gear) reads the item's current listings and the deal is evaluated again with them,
using the same rules.

- A check is valid for **45 seconds** (`D.FRESH`). After that, Buy requires a new check.
- Unchecked scan deals stay listed for **15 minutes** (`D.KEEP`).
- Searches run **one at a time**. Requests from your clicks form a first-in, first-out queue and are
  accepted even while the server is throttling. Background work (automatic checks, sniper) only uses
  an idle slot and never replaces a request of yours.
- A search with no answer in 10 seconds is abandoned. A dropped request
  (`AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED`) is retried.
- Gear is searched like the game's own Sell window does it, across every version of the item key,
  and the rows are filtered by the full item name.
- **Automatic checks** (setting on by default): when nothing else runs, the best deal that has not
  been checked in 5 minutes is checked. The same deal is not retried within 2 minutes. Automatic
  checks pause while the selected deal is freshly checked, to leave you time to click Buy.
- **Check all statuses** captures the whole current page before sending anything, so it is not
  affected by paging or later updates. Each item gets exactly one result: checked, gone, timed out
  or cancelled.

When a check confirms a deal, it is re-added with the live numbers and may raise an
[alert](user-guide.md#alerts). When it no longer holds, the deal is removed.

## Sniper

`Scan.lua` (`S.HOT = 150`), `Deals.snipe`. While evaluating a scan, ForeverFlip scores every item that
is *near* a deal:

- it has a deal;
- its cheapest lot is below 125% of the vendor price;
- its cheapest lot is below 70% of the usual price, with at least 3 units listed.

The score is a decaying count of how often the item was near a deal (×0.9 per scan), plus a bonus of
5 for a current deal. The 150 best items form the sniper list. The sniper cycles through that list,
one search per second, and skips items checked less than a minute ago.

## Selling

`Trade.lua`.

- **Price suggestion:** one legal step below the cheapest listing of another seller, read by an exact
  search that stays fresh for 5 minutes. With no other seller, the usual price is used. The minimum
  is 1 silver for items and 1 copper for commodities.
- **Break-even floor:** for items in stock, **Post next bought** never posts below the price that
  returns the average unit cost after the 5% cut (`Market.breakEven`).
- **Posting** uses `PostCommodity` or `PostItem`. If the game asks for a confirmation
  (`AUCTION_HOUSE_POST_WARNING`), the next click confirms.
- **Undercut detection:** **Check prices** on My auctions reads each listed item, one search per
  second, and compares your price with the cheapest other seller.
- **Sales:** when `OWNED_AUCTIONS_UPDATED` marks an auction as sold, the sale is booked once (per
  auction ID) with its real quantity and price. The chat line *A buyer has been found for your
  auction* triggers a refresh.

## Accounting

`Data.lua`, separately for each character:

- **Positions:** units bought and not yet sold, at **average cost**, with how they were bought
  (vendor or resale), the planned exit price and the purchase time.
- **Sales** take units out of the position at average cost. Profit = money received after the cut
  − cost of those units.
- **Item statistics:** bought, spent, sold, earned, profit, unit-days held, last sale.
- **Journal:** buy, sell, vendor and fail entries, the latest 500.
- **Trust factor** (`Deals.trust`): if you hold stock of an item and nothing has sold since it was
  bought, the item's sales estimate is multiplied by **0.5 after 1 day** and **0.25 after 3 days**.
  Your own results thus correct the scan estimate.
- **Unknown purchases:** an item purchase with no answer for 30 seconds is recorded as unknown, and
  you settle it on the Journal page. The chat line *You won an auction for X* confirms a pending
  purchase automatically when the name and count match.

## Time-of-week pattern

`Market.recordTiming`, `Market.timing`. For items with at least 10 listed units, each scan's usual
price is divided by the item's long-run baseline, an exponential average with weight 0.05. The ratio,
clamped to 0.2–5, is averaged in two independent sets:

- 7 factors, one per weekday;
- 4 factors, one per part of the day: night 0–6, morning 6–12, day 12–18, evening 18–24.

Each factor is a running mean over its last 20 observations. The expected price at a time is
`baseline × day factor × part factor`, so a few weeks of scans are enough. The pattern is reported
once 4 weekdays and 3 parts of the day have data. It gives the current factor, the cheapest and
dearest slot, and the spread between them.

## Market analytics

`Analytics.lua`, built from the saved history of the current auction house and cached per scan:

| List | Rule |
|---|---|
| Below usual | today's cheapest < 95% of the usual price; score = gap × min(units per day, 10) |
| Sells most | units per day near the usual price, highest first |
| Falling / Rising | usual price more than 5% below / above the average of the previous days (up to 5 daily records) |
| Cheap now | time-of-week factor now ≤ 0.93 and at least 0.5 units sold per day |
| Sell now | time-of-week factor now ≥ 1.07, only for items you hold in stock |

Each list shows at most 50 items.

Daily records (the lowest price of the day and the usual price) are kept only for items that are
traded often enough: 10 or more units listed, or items that were near a deal.

## Merchant offers

`Merchant.lua`. When a merchant window opens, every item the merchant sells for gold (no special
currency) is compared with its auction history:

- **exit price:** one step below the lower of the usual price and today's cheapest;
- **profit per unit:** `net(exit) − merchant price − deposit per unit`;
- **quantity:** about one day of measured sales, limited by the merchant's stock and your
  [budget](#money-limits).

Only items with measured sales and a positive profit are listed, highest total profit first.

## Safety rules

- **No automatic trading.** Every purchase, post, cancel, vendor sale and mail action starts with a
  click. Background activity is limited to read-only searches.
- **Buy only on a fresh check.** The Buy button is enabled only for a deal checked in the last 45
  seconds, and the purchase uses the lots from that check.
- **Commodity quotes are compared.** If the server's quote is higher than the checked cost, the
  purchase is cancelled.
- **Server limits are respected:** one full scan per 15 minutes, one exact search at a time with
  pacing, item data at 40 per second, mail actions every 0.4 seconds.
- **Errors are isolated.** Event and frame handlers run under `xpcall`. An error is reported once
  per distinct message and saved (latest 20), and never repeats every frame.

## Known facts about WoW Forever

These facts were seen in game and the code depends on them:

- The client uses the modern engine: the global `GetItemInfo` is missing, so `C_Item.GetItemInfo`
  is used. Merchant item info is read through `C_MerchantFrame.GetItemInfo` when present.
- An exact-search row for an **item** is a bucket of identical auctions. Its price is per item,
  `quantity` is the number of auctions, and `PlaceBid` buys **one** auction.
- Gear links have an empty suffix field, and one ending is split over several item-key versions.
- `REPLICATE_ITEM_LIST_UPDATE` is not always sent after a full scan request.
- The minimum deposit is 1 silver.
- A full scan on a busy realm returns more than 200 000 auctions.
