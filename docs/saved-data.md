# Saved data

ForeverFlip stores settings and accounting in `ForeverFlipData`, and raw scans in `ForeverFlipRaw`, in
`WTF/Account/<ACCOUNT>/SavedVariables/ForeverFlip.lua`. The game writes this file at logout and on
`/reload`.

To reset the addon completely, delete that file while the game is closed. To reset only one
character's trade records, delete its entry under `chars`.

All money values are in **copper**. All times are Unix timestamps in seconds (`time()`).

## Top level

| Field | Type | Meaning |
|---|---|---|
| `salesModel` | number | Sales-estimation model (`4`). Older derived sales/flow/pending values and daily sold counts are reset once; prices, positions and journals are retained. |
| `vendorMarginReset` | boolean | The one-time default vendor-margin migration has run. |
| `settings` | table | User settings, see below. |
| `vendor` | table | `vendor[itemID]` = the client's vendor sell price; `0` means vendors do not buy the item. Shared by all characters. |
| `vendorSeen` | table | `vendorSeen[itemID]` = what a merchant really paid, from the buyback list: `{ p = copper each, t = when, c = the client's price then }`. Preferred over `vendor`. |
| `sellable` | table | Item IDs previously accepted for auction posting; fallback when the client's current sellability check is inconclusive. |
| `itemKeys` | table | Cached non-commodity key versions, learned from owned auctions and browse results: `itemKeys[itemID] = { at, list = { { l, s, n }, ... } }` (level, suffix, optional lower-case name). Entries not seen for 14 days are removed. |
| `deSeen` | table | `deSeen[band]` = your own disenchant results per item band (`"2:w:25"` = green weapons up to item level 25): `{ n = disenchants, [itemID] = units }`. |
| `lastScan` | number | Time of the last full-scan request (the 15-minute cooldown is per account). |
| `scanPending` | table | The full-scan request still waiting for (or in the middle of) its answer: `{ at, scope, base, baseMark, other, answered }`. Kept over closing the auction house and `/reload`; cleared when the scan is read or given up. |
| `scanLog` | list | The last 20 full-scan requests: `{ at, ended, outcome, count, other }`; outcome is read, no answer, list kept changing, dropped by the server, empty list, closed while waiting or closed while reading. |
| `markets` | table | `markets[scope]`, one per auction house, where scope = `<realm>-<faction>` or `<realm>-Neutral`; hardcore realms add ` (HC)` to the realm. |
| `chars` | table | `chars[owner]`, one per character, where owner = `<realm>-<character>`. |
| `ui` | table | `ui.section`: the last opened page. |
| `cuts` | table | `cuts[scope]` = the auction cut learned from invoices (for example `0.05` or `0.15`). |
| `deposits` | table | `deposits[itemID][duration]` = deposit per unit the game charged for the last post of an item; `deposits[itemID].neutral[duration]` the same at a neutral house. |
| `sharedSeen` | table | `sharedSeen["<scope>@<time>"]` = when a shared scan was merged, so each one is merged once (kept 7 days). |
| `hiddenSell` | table | `hiddenSell[key]` = name of an item hidden from the Sell page and the posting queues. |
| `lastPosted` | table | `lastPosted[key]` = the last unit price the player posted the item at. |
| `rules` | table | `rules[key]` = posting rule `{ min, normal, max, keep }` (all optional; money in copper). |
| `fights` | table | Per-item undercut/repost observations used by selling advice. |
| `toVendor` | table | Items marked by selling advice for a later merchant sale. |
| `shopping` | table | `shopping[key]` = shopping list entry `{ max, qty, name }`. |
| `blocked` | table | `blocked[key]` = name of an ignored item. |
| `merchantPrices` | table | `merchantPrices[itemID]` = price per unit a merchant asked. |
| `gold` | table | `gold[owner][day]` = the character's money on that day (day = Unix time / 86400), kept 60 days. |
| `errors` | array | The latest 20 addon errors, newest first: `{ at, version, message }`. |
| `diag` | table | The last `/ff diag` result. |

## `settings`

| Field | Default | Meaning |
|---|---|---|
| `language` | `nil` | `"en"`, `"uk"` or `nil` (follow the game client). |
| `vendorMinProfit` | `10` | Minimum profit of a vendor deal. |
| `minProfit` | `100` | Minimum profit of a resale. |
| `minROI` | `0.2` | Minimum resale return (profit / cost). |
| `spendShare` | `0.8` | Share of the gold on hand one deal may use. |
| `itemShare` | `0.3` | Share of the gold one item may hold (stock plus the new resale). |
| `duration` | `3` | Posting duration: `1` = 2 h, `2` = 8 h, `3` = 24 h, `0` = automatic. |
| `autoScan` | `false` | Automatic full scan every 15 minutes; enabled in Settings. |
| `sniper` | `false` | Sniper on; enabled in Settings. |
| `autoVerify` | `false` | Check discovered deals in the background; enabled in Settings. |
| `alerts` | `true` | Sound and screen alerts. |
| `alertMinProfit` | `50` | Smallest profit that raises an alert. |
| `tooltipPrices` | `true` | Price lines in item tooltips. |
| `undercutPercent` | `0` | Undercut below the cheapest other seller; `0` = one legal price step. |
| `minPricePercent` | `0` | Floor as a share of the usual price; `0` = off. |
| `maxPricePercent` | `2` | A cheapest seller above this share of the usual price is ignored. |
| `belowMin` | `"min"` | Below the floor: `"min"` posts at the floor, `"hold"` keeps the item. |
| `learnBrowsing` | `true` | The player's own searches update prices and deals. |
| `highlight` | `true` | Marks in the game's Buy tab. |
| `disenchant` | `true` | Disenchant deals (only for a character who knows Disenchant). |
| `shareReceive` | `true` | Merge full scans shared by guild and group members. |
| `shareAuto` | `false` | Send each own full scan to the guild. |
| `rawScans` | `true` | Keep full scans for the ForeverFlip Sync helper. |
| `shareChannel` | `true` | Share full scans with every ForeverFlip user of the realm over a hidden channel. |
| `vendorMargin` | `0` | Percent off the client's vendor price while a merchant has not confirmed it (the old default of 20 is reset once, `vendorMarginReset`). |
| `spendLimit` | `0` | Gold one auction house visit may spend on deals; `0` = no limit. |
| `leaveLots` | `0` | Cheap units of a vendor deal left for other buyers. |

Missing settings are filled in with these defaults at load.

## `markets[scope]`

| Field | Meaning |
|---|---|
| `history[key]` | Per-item history, see below. Items not seen in a full scan for 14 days are removed. |
| `peak` | Largest complete scan in the last day, `{ total, at }`, used to reject partial server answers. |
| `last` | The last scan, written on logout and when another house opens, kept until the next scan: `{ at, total, read, skipped, own, stats, deals, pool, hot, ownersKnown, ownUnits }`. `deals` are saved deals without their live rows, `pool` holds items still waiting for a vendor price (up to 6000), `hot` is the sniper list, `ownersKnown` whether the scan named sellers, `ownUnits[key]` the units of your own lots at the time of the scan. |

### `history[key]`

`key` is an [item key](how-it-works.md#item-keys) such as `c:2589` or `g:15210:raider's shortsword of the bear`.

| Field | Meaning |
|---|---|
| `scan` | The last scan of the item: `{ at, market, above = {4} }`. `market` is the usual price, `above[i]` the units listed at or above `LEVELS[i] × market`. |
| `flow` | Sales between scans: `{ hours, sold = {4}, pairs, at, market, watched }`. These are decayed sums with a 2-day half-life. `pairs` is capped at 99; `watched` counts the hours watched since the last sale, without decay. |
| `units` | Units listed in the last scan. |
| `hits` | Decaying count of scans in which the item was near a deal (sniper score). |
| `days` | Up to 14 daily records `{ d = day number, min = cheapest unit price, m = usual price, n = units listed, s = units sold }`. Present only for items traded often enough. |
| `lots` | The item's lots of the last scan as text, `"price:count:band,..."` in scan order (up to 300), for lot-by-lot sales tracking. |
| `lotsAt` | Time of the scan `lots` comes from. |
| `lotOwners` | Parallel comma-separated seller tags for `lots`; tags avoid storing seller names. |
| `pending`, `pendingAt` | Whole lots awaiting another scan to distinguish a sale from a repost; derived sales-model data. |
| `shared` | The newest shared scan of the item: `{ at, m = usual price, min = cheapest, n = units, from = sharer }`. |
| `sales` | Lot-tracked sales: `{ hours, pairs, at, b = price histogram of sold units, watched, soldAt }`, decayed with a 3-day half-life; `watched` counts the hours watched without decay and `soldAt` when units last sold at each price (up to 8). The histogram is flat: `b[2k]` = units, `b[2k+1]` = cheapest price of 2% bucket k. |
| `t` | Time-of-week pattern: `{ b = baseline, w = {7}, wn = {7}, p = {4}, pn = {4} }`, with factors and observation counts per weekday (`w`, Sunday first) and per part of the day (`p`). |

## `chars[owner]`

| Field | Meaning |
|---|---|
| `positions[key]` | Stock bought and not sold: `{ qty, cost, name, since, mode = "vendor" \| "flip" \| "shop" \| "disenchant", exit }`. `cost` is the total cost of the remaining units. |
| `journal` | Up to 500 entries, oldest first: `{ at, kind = "buy" \| "post" \| "sell" \| "vendor" \| "expired" \| "cancel" \| "return", key, name, qty, amount, profit }`. `expired`, `cancel` and `return` book the deposit (and cancel fee) a post lost; `return` is a buy that was really a post coming back by mail. Buy entries carry the auction house `scope`; a loss booked while no stock was held carries a negative `profit`. |
| `stats[key]` | Item totals: `{ name, bought, spent, sold, earned, profit, days, lastSale }`. `days` is the sum of days held per unit sold. |
| `listings` | Auctions posted through ForeverFlip: price, quantity, auction IDs and scope, used to book sales. After 3 days a listing no longer counts as on sale, but it is kept up to 31 days while a sale or cancel booked from it waits for its mail. |
| `cancels` | `cancels[auctionID]` = a cancel made with ForeverFlip `{ at, scope, key, name, qty, lost, estimated, listed, back, booked }`; its loss is booked once the next list of your auctions or its mail confirms it. |
| `booked[auctionID]` | Sold auctions already booked, so a sale is never counted twice. |
| `unknown` | Purchases without an answer from the server, waiting to be settled on the Journal page. |
| `awaitMail` | Per-item quantities already booked as purchases, awaiting matching buyer invoices so stock is not counted twice (kept 31 days, the life of auction mail). |
| `invoices` | The latest 200 sale invoices `{ at, item, qty, net, cut }`. |
| `rates` | `rates[lower-case item name]` = `{ sold, failed }` posts, from auction mail. |
| `recipes` | `recipes[recipeID]` = `{ name, out = itemID, n = units made, r = { { itemID, count }, ... } }`, read from profession windows. |
| `bids` | `bids[auctionID]` = open bid `{ key, name, qty, amount, value, at }`; a bid first seen in the game's own window may also keep `id` and `link` until its key is known, and `missed` marks a bid the game's bids list never showed. |

## `ForeverFlipRaw`

A second SavedVariables table in the same file, written only with **Keep my full scans for the
ForeverFlip Sync helper** on:

```lua
ForeverFlipRaw = {
    format = "FFR1",
    scans = { -- newest first, at most 8; uploaded older entries are removed
        { scope = "Realm-Alliance", realm = "Realm", faction = "Alliance", at = <time>, count = <auctions>,
          addon = "1.2.0", seal = <checksum>, rows = "<one line per auction>" },
    },
}
```

Each line of `rows` is `itemID,count,buyout,minBid,bid,timeLeftBand,own,kind,name`; see
[Community scans](community.md) and the data repository for the meaning of the fields. `seal` is a
checksum of the lines, the realm, the time and the number of auctions, computed while the scan was
read; the Sync helper and the data repository refuse a scan whose lines no longer match it.

## `ForeverFlipShared`

Not saved by the game: a global set by the **ForeverFlip_Shared** addon, which the Sync helper writes.
It has the form `{ generated = <time>, scans = { "FF1|...", ... } }` and is merged at login.

## Compatibility

Data from the pre-release builds that already used `ForeverFlipData` is kept and used as is. The
older `ForeverFlipDB` and `ForeverFlipLegacyDB` tables are not read. If they are still in the file,
they disappear the next time the game writes it.
