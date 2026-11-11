# How ForeverFlip works

This document explains where the numbers come from: scanning, the usual price, sales estimates,
deal maths, the money limits and the safety rules. Constants are given with the file that defines
them, so you can check them in the code.

- [Item keys](#item-keys)
- [Full scan](#full-scan)
- [Auction houses and the cut](#auction-houses-and-the-cut)
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
- [Crafting](#crafting)
- [Bids](#bids)
- [Sharing scans](#sharing-scans)
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
   number has changed and has stopped growing. Since launch the answer can take minutes, so the
   job waits up to 5 minutes (`S.ANSWER_WAIT`), showing the seconds; with no answer it gives up
   and the next attempt is allowed a minute later. Searches and the sniper wait for the answer: when
   they went on meanwhile, the answer did not come in game.
2. **Reading.** Rows are read in portions under a time budget per frame. Bid-only auctions and your
   own auctions are skipped. Rows whose item is not in the game cache are deferred; the item data is
   requested at most 40 items per second (`AH.lua`), and the deferred rows are retried for up to
   30 seconds (`S.RECOVER`).
3. **Grouping.** Rows are grouped per item key. For each item ForeverFlip keeps:
   - the **40 cheapest auctions** (`S.ROWS`);
   - a **price histogram** of every listed unit;
   - when the client reports each auction's time left (`GetReplicateItemTimeLeft`), the **lot
     sequence** in scan order (up to 300 lots, `M.LOTS`) for [lot-by-lot sales](#sales-tracked-lot-by-lot).

   Auctions with a bid that end within 30 minutes become [bid candidates](#bids).
4. **Evaluation.** Each item is evaluated in portions per frame: usual price, sales between scans,
   daily records, time-of-week pattern. Then come the deals ([Deal evaluation](#deal-evaluation)):
   vendor, resale, shopping list and disenchant. Items with an unknown vendor price are kept aside
   (up to 6000) and evaluated again when their data loads. Items that vanished from the house since
   the last scan have all their lots compared too: a sold-out item counts its sales.
5. **Saving.** The scan statistics, the deals, the items still waiting for a vendor price and the
   sniper list are put into the saved data on logout and `/reload` (when the game writes it) and
   when another auction house opens, so they survive a `/reload`.

Items that have not appeared in a full scan for 14 days are removed from the saved history. Like the
rest of the scan, this pass over the history (and the sweep of vanished items) runs a slice per
frame, so the end of a scan does not stall the game on a large history.

If another addon requests a full scan, ForeverFlip reads the same result and treats the 15-minute
window as used. The call itself is watched (`C_AuctionHouse.ReplicateItems` is hooked), because the
event that announces the answer is not always sent.

## Auction houses and the cut

`Core.lua`. Each auction house has its own history and deals, keyed by its scope:

- `<realm>-<faction>`: the faction house;
- `<realm>-Neutral`: the neutral house of Booty Bay, Gadgetzan or Everlook. Each of their zones
  (Stranglethorn Vale, Tanaris, Winterspring) holds only that one auction house, so the zone's map
  ID (`C_Map.GetBestMapForUnit`) identifies it in any client language. The English town names are a
  fallback.

The auction cut (`M.CUT`) is set when the auction house opens: 5% for a faction house, 15% for a
neutral one, unless a cut was [learned from invoices](#accounting).

## Usual price

`Market.bucketAdd`, `Market.bucketValue`. Every listed unit goes into a histogram with **2% wide
price buckets**. The histogram is stored as a flat array to save memory. The **usual price** of an
item is the cheapest price of the bucket that reaches **30% of the listed volume**:

- the few cheapest units (bargains) do not set it;
- the expensive tail never reaches it.

Resale prices never go above the usual price, nor above the **sale cap**: the price that a quarter of
the [sales seen](#sales-tracked-lot-by-lot) reached (`M.saleCap`, once 3 units were seen sold). The
median of the sales seen (`M.salePrice`) is shown as "sells at" in tooltips.

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

`demandAt(h, price)` returns the units per day sold at or above 85% of `price`, plus the number of
scan pairs. With 0 pairs there is no estimate yet: the item is still *collecting*. When lot-by-lot
data exists (below), it is used instead of the level method.

### Sales tracked lot by lot

`Market.trackSales`, `Market.recordSales`, `Scan.trackLots`. A full scan lists an item's auctions in
the order they were created, each with a time-left band: under 30 minutes, up to 2 hours, up to 12
hours, longer. Two scans 5 minutes to 3 hours apart are compared lot by lot:

1. **Matching.** The old lots are walked in order, and each is matched to the next new lot with the
   same price, no more units and no more time left. New auctions are appended at the end, so they do
   not disturb the order. A second pass matches the remaining lots by price.
2. **Partial purchases.** A matched lot that got smaller was partly bought; the difference is a sale.
   An auction can only be cancelled as a whole.
3. **Vanished lots** count as sold only if both hold:
   - the lot could not have expired: its band guaranteed more time left than had passed;
   - no cheaper lot of the item survived, because buyers take the cheapest units first. A vanished
     lot above a surviving cheaper one was cancelled or reposted.

The sold units go into a price histogram per item (`h.sales`), decayed with a **3-day half-life**,
together with the observed hours. Units per day at or above 85% of a price use the same smoothing
prior of 4 hours. This removes the main error of the level method: expired and cancelled auctions no
longer count as sales.

ForeverFlip's [learning from searches](#learning-from-the-players-searches) also lowers today's
cheapest price of an item between scans.

## Deal evaluation

`Market.evaluate`. Input: an item's listings sorted cheapest first, its kind, the vendor price, the
usual price, the sales history and the money limits. Output: the best deal, or a reason why there is
none.

### Vendor deal

Take every unit priced below the vendor sell price, within budget. Profit is
`qty × vendor price − cost`. There is no auction cut, no deposit and no waiting: the units are sold
to any merchant right away. The deal is kept if profit ≥ **Minimum profit of a vendor deal**.

The vendor price is what a merchant really paid when one was seen in the buyback list (any item you
sell to a merchant). Until then it is the game's item data less the **Safety** margin (20%), because
the server pays less than the client says for some items. Gear sold damaged sells for less, so for
gear a lower buyback price only replaces a higher one after a patch changed the client's price.
With **Cheap units left for other buyers** set, the priciest of the cheap units are not bought.

### Resale

Try every prefix of the cheapest listings, up to 40 auctions. For a prefix that ends at listing *i*:

1. **Exit price** is one legal step below the cheapest unit left after buying. A resale above that
   lot would not sell before it does. The exit is also capped at the usual price.
2. **Profit** = `net(exit, qty) − cost − deposit risk`.
   - `net` removes the [auction cut](#auction-houses-and-the-cut).
   - The deposit risk counts the deposits lost if the lots do not sell: one per auction for items and
     gear, one per stack for commodities.
   - **Deposit amounts** (`AH.depositFn`):
     - commodities: the game's own value from `CalculateCommodityDeposit`, read for 1 and 20 units
       once per session;
     - items: the deposit per unit learned from their last post (`CalculateItemDeposit`);
     - otherwise: the estimate `max(1 silver, 15% of the vendor price × units)`.
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
collecting sales data, not selling, enough stock already held, or an ignored item.

### Shopping deal

`Shopping.lua`. If the item has no vendor deal or resale and is on the shopping list: take every unit
at or below the wanted price, up to the wanted quantity and the budget (one auction for items and
gear). Its "profit" is the saving against the wanted price. Bought units are booked with mode
`shop` and are kept out of Post next bought.

### Disenchant deal

`Disenchant.lua`, for gear, when the character knows Disenchant (`IsPlayerSpell(13262)`) and the
setting is on.

1. **Expected materials.** The item's quality (green or blue), item level and class (weapon or
   armor) select a row of the **Classic Era disenchanting table**:
   - green armor gives dust 75% (80% below level 16), essence 20% and sometimes a shard;
   - weapons swap dust and essence; green weapons of item level 21-30 give Greater Magic Essence;
   - blue items give one shard (and a 0.5% Nexus Crystal from level 56).
2. **Your own disenchants.** When a Disenchant cast starts, the item it is aimed at is noted; the
   loot window that follows is added to the item's band. After 15 disenchants of a band, their
   results replace the table for it (Settings → Safety shows how many bands are learned).
3. **Value.** Each material is priced at its usual auction price after the cut. An essence is worth
   at most what its other form allows: three lesser make one greater, and a greater splits into
   three lesser. A material that makes up 10% or more of the outcome must have a price.
4. **Deal.** Every gear lot below `value − minimum profit` is bought, within the budget.

The table has not been checked on WoW Forever item by item, so the values are estimates. Bought units
are booked with mode `disenchant` and are kept out of Post next bought.

### Ignored items

An ignored item (Ignore item, kept in `F.db.blocked`) never becomes a deal, a sniper candidate, a bid
candidate or part of Post all.

## Money limits

`Deals.lua`, applied to every evaluation:

- **Money one deal may use** (default 80%): a deal may spend at most this share of the gold you
  carry.
- **Money one item may hold** (default 30%): for a resale, the cost of the stock already held of
  that item plus the new purchase may not exceed this share of your gold.

## Live verification

`Deals.lua`. A deal from the full scan is only a lead. Before it can be bought, an exact search
(`C_AuctionHouse.SendSearchQuery`) reads the item's current listings and the deal is evaluated again
with them, using the same rules.

- A check is valid for **45 seconds** (`D.FRESH`). After that, Buy requires a new check.
- Unchecked scan deals stay listed for **15 minutes** (`D.KEEP`).
- Searches run **one at a time**. Requests from your clicks form a first-in, first-out queue and are
  accepted even while the server is throttling. Background work (automatic checks, sniper) only uses
  an idle slot and never replaces a request of yours.
- A search with no answer in 10 seconds is abandoned. A dropped request
  (`AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED`) is retried.
- Gear is searched in two steps, because the sell search is never answered on WoW Forever: a browse
  by the item's name lists its item-key versions, then each version is searched and the rows are
  merged and filtered by the full item name. A complete browse without the item means nobody sells
  it, known at once. (Without browse queries the sell search is still tried.) A browse somebody else
  sent (the game's Buy tab, another addon) during the search, or less than 10 seconds before it, may
  answer in its place: then the result is "unknown", not "nobody sells it", and the versions found
  are not taken as all of them.
- The throttle check (`IsThrottledMessageSystemReady`) can stay "not ready" for good after a message
  the server never answered. It is watched every frame; after 5 seconds of "not ready" one message
  goes through.
- **Automatic checks** (setting on by default): when nothing else runs, the best deal that has not
  been checked in 5 minutes is checked. The same deal is not retried within 2 minutes. Automatic
  checks pause while the selected deal is freshly checked, to leave you time to click Buy.
- **Check all** captures the whole current page before sending anything, so it is not
  affected by paging or later updates. Each item gets exactly one result: checked, gone, timed out
  or cancelled.

When a check confirms a deal, it is re-added with the live numbers and may raise an
[alert](user-guide.md#alerts). When it no longer holds, the deal is removed.

## Sniper

`Sniper.lua`, `Deals.snipe`.

### Fast sniper (browse rounds)

A browse query with an empty search (`C_AuctionHouse.SendBrowseQuery`) returns every item of the
house with its lowest price and total quantity, page by page; 7718 items took 8.5 seconds over 16
requests on WoW Forever. A key query (`SearchForItemKeys`) returns the same for up to 100 chosen items
in one request.

1. **Round.** A browse round reads every page (`RequestMoreBrowseResults`) and then waits 2.5 seconds
   (`S.PAUSE`).
2. **Pause.** During the pause, the hot items of the last scan (below) and the shopping list are read
   with key queries, 100 per request, one request per second.
3. **Candidates.** Each lowest price is compared with a **threshold**: the highest lowest-price at
   which the item can still hold a deal (`S.threshold`). The threshold is the highest of:
   - the vendor price − the minimum vendor profit;
   - for an item selling 0.5+ units a day at its exit price (usual price, sale cap):
     `(net(exit) − deposit) / (1 + minimum return)`;
   - the shopping list price;
   - for gear, when disenchant deals are on: the disenchant value − the minimum profit.

   A price at or below the threshold is a candidate, scored by how far below it is. An unchanged
   price is not judged again for 2 minutes (`S.REJUDGE`), and a deal checked in the last minute at
   the same price is skipped.
4. **Exact check.** Candidates are checked one by one with an exact search at the faster pace (0.4
   seconds) and evaluated with the full deal rules. No new browse page is asked for while
   candidates wait, and no browse request is sent while your own requests, a scan or a purchase are
   running.

Gear keys are told apart only by the exact search, so a cheap gear item ID makes every known ending
of that ID a candidate.

Browse results that come while the sniper has no query of its own, such as the player browsing the
game's Buy tab or another addon's search, are judged the same way. Only their new rows are read, 300
per frame, so another addon browsing the whole house does not freeze the game. A gear check needs
the browse too: the round in flight gives way and starts again after the pause.

### Fallback: the hot list

Without browse queries, the sniper re-reads the hot list one item per second. While evaluating a
scan, ForeverFlip scores every item that is *near* a deal (`S.HOT = 150`):

- it has a deal;
- its cheapest lot is below 125% of the vendor price;
- its cheapest lot is below 70% of the usual price, with at least 3 units listed.

The score is a decaying count of how often the item was near a deal (×0.9 per scan), plus a bonus of
5 for a current deal. The 150 best items form the hot list. Items checked less than a minute ago are
skipped.

### Learning from the player's searches

`Deals.learn`. When the player searches an item in the game's Buy tab (`COMMODITY_SEARCH_RESULTS_UPDATED`,
`ITEM_SEARCH_RESULTS_UPDATED` for an item ForeverFlip is not searching itself), the listings are
evaluated like an exact check: a deal is added as freshly checked, or a listed deal that no longer
holds is removed. Gear is evaluated for every known ending of the item ID.

## Selling

`Trade.lua`.

- **Price suggestion** (`T.suggest`), from an exact search that stays fresh for 5 minutes:
  - **undercut:** one legal step below the cheapest listing of another seller, or `undercutPercent`
    below it (never less than one step);
  - **normal price:** the rule's `normal`, else the usual price. It is used when nobody else sells,
    or when the cheapest other seller asks more than the maximum (the rule's `max`, else
    `maxPricePercent` × the normal price, 200% by default);
  - **fallback** (`T.fallbackPrice`) when nobody else sells and there is no normal price, in this
    order:
    1. the last price the player posted the item at (`F.db.lastPosted`);
    2. auxForever's usual price;
    3. the stock's break-even + 25%;
    4. 1.5 × the vendor price.

    The last two are guesses (`T.GUESSES`) that the posting queues never post;
  - **minimum:** 1 silver for items and 1 copper for commodities.
- **Floor** (`T.floorFor`), the highest of:
  - the break-even price of the stock: the price that returns the average unit cost after the cut
    (`Market.breakEven`);
  - the rule's `min`;
  - `minPricePercent` × the usual price.
- **Posting queues** (`postFirst`):
  - **Post next bought:** positions bought for resale, oldest first.
  - **Post all:** every sellable bag item except vendor-deal, shopping and disenchant stock, ignored
    items, items hidden on the Sell page (`F.db.hiddenSell`) and the units of a `keep` rule.
    Post next bought skips hidden items too.
  - Each click either reads a missing price or posts one item. Below the floor, an item is posted at
    the floor (`belowMin = "min"`) or skipped for the session (`"hold"`).
- **Duration** (`T.durationFor`): 2, 8 or 24 hours from the setting. With **Auto**, it is the
  shortest duration that the measured sales fill: the units sell within 2 hours → 2 h; within 8
  hours → 8 h; else 24 h. Shorter posts cost smaller deposits.
- **Posting** uses `PostCommodity` or `PostItem`. Before an item is posted, its deposit per unit is
  read from the game (`CalculateItemDeposit`) and kept for deal evaluation. If the game asks for a
  confirmation (`AUCTION_HOUSE_POST_WARNING`), the next click confirms.
- **Undercut detection:** **Check prices** on My auctions reads each listed item, one search per
  second, and compares your price with the cheapest other seller.
- **Cancel undercut** (`T.undercutList`, `T.cancelNextUndercut`): an undercut auction is offered for
  cancelling only if its repost price (the undercut of the cheapest other seller) still reaches the
  item's floor. Each click cancels one.
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
- **Sales to a merchant by hand** (`Merchant.watchBuyback`): the buyback list is compared each time
  it changes; a new entry of an item in stock is booked as a vendor sale at the price paid. Sales of
  the Sell vendor deals button are booked by it and only matched.
- **Journal:** buy, sell, vendor, expired and fail entries, the latest 500.
- **Invoices** (`Mail.record`, `Trade.onInvoice`). Every auction mail is read once, when its money or
  items are taken. That happens through the Take auction mail button, or through the game's
  `TakeInboxMoney`, `AutoLootMailItem` and `TakeInboxItem`, which are hooked. The content is
  snapshotted at `MAIL_INBOX_UPDATE`, so a mail is never read twice.
  - **Seller invoice** (`GetInboxInvoiceInfo`): the sale price, the cut and the units.
    - The units are booked against an open listing of the item if one exists.
    - If no listing of the item was posted through ForeverFlip in the last 3 days, the units are
      booked against the stock.
    - Units already booked from the own-auction list are not booked again: both paths reduce the
      same open quantity of the listing.
  - **Buyer invoice** (an item bought on the auction house): a won bid closes the bid; a purchase
    ForeverFlip made is only matched (it was booked when bought); any other purchase, through the
    game's Buy tab or another addon, is booked as stock **bought elsewhere** at the price of the
    invoice. Such stock is counted in statistics but never posted by Post next bought.
  - **Expired and cancelled mails** count as failed posts.
  - **Sale rate** per item = sold / (sold + failed), shown after 3 posts.
  - **Cut learning:** cut / sale price above 10% belongs to the neutral house, otherwise to the
    faction house. Each invoice of 10 silver or more moves the scope's learned cut 20% of the way
    towards its ratio.
- **Trust factor** (`Deals.trust`) multiplies the item's sales estimate:
  - if you hold stock of an item and nothing has sold since it was bought: **0.5 after 1 day** and
    **0.25 after 3 days**;
  - with a sale rate below 50%: rate / 0.5, at least 0.25.

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

Daily records are kept for **14 days** (`S.DAYS`), only for items that are traded often enough: 10 or
more units listed, or items that were near a deal. Each record holds:

- the lowest price of the day;
- the usual price;
- the units listed;
- the units sold, from lot-by-lot tracking.

The records feed the price history window and the analytics.

**Realm summary** (`A.realm`): the gold of each character is recorded once per day (kept 60 days) on
login, logout and money changes. The Analytics page adds up the characters of the realm, their gold
change over the period and their stock at cost.

## Merchant offers

`Merchant.lua`. When a merchant window opens, every item the merchant sells for gold (no special
currency) is compared with its auction history:

- **exit price:** one step below the lower of the usual price and today's cheapest;
- **profit per unit:** `net(exit) − merchant price − deposit per unit`;
- **quantity:** about one day of measured sales, limited by the merchant's stock and your
  [budget](#money-limits).

Only items with measured sales and a positive profit are listed, highest total profit first.

Every merchant price seen is remembered (`F.db.merchantPrices`) as a material price for crafting.

## Crafting

`Crafting.lua`.

1. **Learning.** When a profession window opens (`TRADE_SKILL_SHOW`, `TRADE_SKILL_LIST_UPDATE`, at
   most every 2 seconds), every recipe is read through `C_TradeSkillUI.GetRecipeSchematic`: the
   product, units made and required materials. The recipes are saved per character.
2. **Material cost.** Each material costs the cheaper of:
   - its usual auction price (for a material ForeverFlip has not seen, the usual price from
     `AuxForeverAPI` if auxForever is installed);
   - the price a merchant asked.
3. **Product value.** The higher of:
   - `net(usual price, units) − deposit` on the auction house;
   - the vendor price × units.
4. **Profit** = value − materials, with the product's measured sales per day.

**Shop materials** adds each material to the shopping list at its current price, for one day of
crafts.

## Bids

`Bids.lua`.

1. **Candidates.** During a full scan, auctions of items and gear (not commodities) with a bid, in the
   shortest time band (under 30 minutes), are collected. Each candidate's next bid is the current
   bid plus the increment, or the minimum bid.
2. **Worth** of a unit: the vendor price, or `net(usual price) − deposit` for an item that sells 0.5+
   units a day, whichever is higher.
3. **Selection.** Candidates whose worth exceeds the next bid by at least the minimum resale profit
   are kept, the best 100.
4. **Check.** An exact search reads the item's auctions with a bid (`minBid`) and keeps the most
   profitable one for 60 seconds.
5. **Place bid** calls `PlaceBid(auctionID, minBid)` from a click and records the bid.
6. **Result.**
   - The chat line *You won an auction for X* or the "Auction won" mail books the item as stock: mode
     `vendor` if the vendor pays at least its worth, else `flip`.
   - The "Outbid" mail closes the bid.
   - Bids older than two days are forgotten.

## Sharing scans

`Share.lua`.

- **Snapshot.** Every item seen in the player's last full scan, with its usual price, the day's
  cheapest price and the units listed (`S.snapshot`).
- **Text form.** `FF1|<scope>|<time>|key,usual,cheapest,units;...`, with numbers in base 36 and the
  separators `%`, `,`, `;`, `|` in item keys escaped as `%XX`. The same text is used for export and
  import.
- **Transport.**
  - Addon messages with the prefix `ForeverFlip` (`C_ChatInfo.SendAddonMessage`) to GUILD, PARTY,
    RAID or WHISPER.
  - The text is cut into pieces of 240 characters, each sent as `id:part:total:payload`, one every
    0.3 seconds (`S.PACE`).
  - The receiver joins the parts and drops an incomplete scan after 5 minutes.
- **Acceptance** (`S.merge`):
  - the scope's realm must be the player's realm;
  - the scan must be at most 7 days old, and no more than 10 minutes in the future;
  - each scan is merged once (`F.db.sharedSeen`);
  - a scan within 2 minutes of the player's own scan is the same server scan, and is skipped.
- **Merging,** per item:
  1. `h.shared = { at, m, min, n, from }` when newer than the stored one;
  2. the record of that day: the lowest price wins, the usual price and units fill in what is missing,
     and the records stay in day order;
  3. the time-of-week pattern, for items with 10 or more units listed.
- **Usual price** (`Market.usual`): the newer of the player's own scan and the shared one. It is used
  for posting prices, crafting, disenchant values, bids, merchant offers, the sniper threshold,
  tooltips and `ForeverFlipAPI.GetPrice`. Sales estimates, lot tracking and deals use only the
  player's own scans.
- **Retention:** history entries known only from shared scans are pruned like the others, 14 days
  after the item was last seen.

## Safety rules

- **No automatic trading.** Every purchase, bid, post, cancel, vendor sale and mail action starts with
  a click or a key binding. Background activity is limited to read-only queries.
- **Buy only on a fresh check.** The Buy button is enabled only for a deal checked in the last 45
  seconds, and the purchase uses the lots from that check.
- **Commodity quotes are compared.** If the server's quote is higher than the checked cost, the
  purchase is cancelled.
- **Stale quotes are refreshed.** A quote older than 25 seconds, or with less than 2 seconds left
  (`GetQuoteDurationRemaining`), is cancelled and asked again in the same click instead of being
  confirmed.
- **Server limits are respected:**
  - one full scan per 15 minutes;
  - one exact search at a time with pacing, at most 100 per minute;
  - browse queries only when nothing else waits and the game's throttle is ready;
  - item data at 40 per second;
  - mail actions every 0.4 seconds.
- **Errors are isolated.** Event and frame handlers run under `xpcall`. An error is reported once
  per distinct message and saved (latest 20), and never repeats every frame.

## Known facts about WoW Forever

These facts were seen in game and the code depends on them:

- The client uses the modern engine: the global `GetItemInfo` is missing, so `C_Item.GetItemInfo`
  is used. Merchant item info is read through `C_MerchantFrame.GetItemInfo` when present.
- An exact-search row for an **item** is a bucket of identical auctions. Its price is per item,
  `quantity` is the number of auctions, and `PlaceBid` buys **one** auction.
- Gear links have an empty suffix field, and one ending is split over several item-key versions.
  The link text carries the full name with the ending.
- `REPLICATE_ITEM_LIST_UPDATE` is not always sent after a full scan request.

Facts other Forever addons recorded on the live server, used since 1.2 (sources in brackets):

- The server pays less than the client's item data says for some items: recipes listed at 2s sell for
  1s 50c, and a wand went from 15s to 1c in a patch (ForeverForge). What a merchant really paid is
  read from the buyback list.
- `SendSellSearchQuery` is never answered (ForeverForge). Gear is searched with a browse by name and
  a `SendSearchQuery` per item-key version.
- The throttle check can stay "not ready" for good after a message the server never answered
  (ForeverForge). After 5 seconds of "not ready" one message goes through.
- Since launch the answer to a full scan can take more than 5 minutes (auxForever); ForeverFlip waits
  up to 10; ForeverFlip waits 5. A full scan refused by the 15-minute account limit is never
  answered (Price Scanner).
- Gear and other items are listed in whole silver; the server refuses a copper buyout on them
  (auxForever, ForeverForge). A buyout equal to the starting bid gives "Internal auction error".
- Green weapons of item level 21-30 give Greater Magic Essence, never an astral one (ForeverForge,
  from logged disenchants).
- Hardcore realms are told apart with `C_GameRules.IsGameRuleActive(Enum.GameRule.HardcoreRuleset)`
  (TSM).
- The client may not read an addon's saved data at login (ForeverSell, Forever Auction Master).
- The minimum deposit is 1 silver.
- A full scan on a busy realm returns more than 200 000 auctions.
- A browse of the whole house takes about 8.5 seconds over 16 requests.
- A purchase on a stale commodity quote ends with "Internal auction error".
- Posting durations are 2, 8 and 24 hours.

These are assumptions that have not been confirmed on Forever. The code is built so that it does
not depend on them strictly:

- the 15% cut of a neutral house; the actual cut is learned from invoices;
- the auction order of a full scan being creation order; lot matching has a second pass by price;
- the Classic disenchanting table; your own disenchants replace it band by band once 15 were seen.
