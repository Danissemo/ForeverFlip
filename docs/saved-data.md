# Saved data

ForeverFlip stores everything in one SavedVariables table, `ForeverFlipData`, in
`WTF/Account/<ACCOUNT>/SavedVariables/ForeverFlip.lua`. The game writes this file at logout and on
`/reload`.

To reset the addon completely, delete that file while the game is closed. To reset only one
character's trade records, delete its entry under `chars`.

All money values are in **copper**. All times are Unix timestamps in seconds (`time()`).

## Top level

| Field | Type | Meaning |
|---|---|---|
| `version` | number | Data format version (currently `1`). |
| `settings` | table | User settings, see below. |
| `vendor` | table | `vendor[itemID]` = the client's vendor sell price; `0` means vendors do not buy the item. Shared by all characters. |
| `vendorSeen` | table | `vendorSeen[itemID]` = what a merchant really paid, from the buyback list: `{ p = copper each, t = when, c = the client's price then }`. Preferred over `vendor`. |
| `deSeen` | table | `deSeen[band]` = your own disenchant results per item band (`"2:w:25"` = green weapons up to item level 25): `{ n = disenchants, [itemID] = units }`. |
| `lastScan` | number | Time of the last full-scan request (the 15-minute cooldown is per account). |
| `markets` | table | `markets[scope]`, one per auction house, where scope = `<realm>-<faction>` or `<realm>-Neutral`; hardcore realms add ` (HC)` to the realm. |
| `chars` | table | `chars[owner]`, one per character, where owner = `<realm>-<character>`. |
| `ui` | table | `ui.section`: the last opened page. |
| `cuts` | table | `cuts[scope]` = the auction cut learned from invoices (for example `0.05` or `0.15`). |
| `deposits` | table | `deposits[itemID][duration]` = deposit per unit the game charged for the last post of an item. |
| `sharedSeen` | table | `sharedSeen["<scope>@<time>"]` = when a shared scan was merged, so each one is merged once (kept 7 days). |
| `hiddenSell` | table | `hiddenSell[key]` = name of an item hidden from the Sell page and the posting queues. |
| `lastPosted` | table | `lastPosted[key]` = the last unit price the player posted the item at. |
| `rules` | table | `rules[key]` = posting rule `{ min, normal, max, keep }` (all optional; money in copper). |
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
| `autoScan` | `true` | Automatic full scan every 15 minutes. |
| `sniper` | `true` | Sniper on. |
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
| `rawScans` | `false` | Keep full scans for the ForeverFlip Sync helper. |
| `shareChannel` | `true` | Share full scans with every ForeverFlip user of the realm over a hidden channel. |
| `vendorMargin` | `20` | Percent off the client's vendor price while a merchant has not confirmed it. |
| `spendLimit` | `0` | Gold one auction house visit may spend on deals; `0` = no limit. |
| `leaveLots` | `0` | Cheap units of a vendor deal left for other buyers. |

Missing settings are filled in with these defaults at load.

## `markets[scope]`

| Field | Meaning |
|---|---|
| `history[key]` | Per-item history, see below. Items not seen in a full scan for 14 days are removed. |
| `last` | The last scan, kept until the next scan: `{ at, total, read, skipped, own, stats, deals, pool, hot }`. `deals` are saved deals without their live rows, `pool` holds items still waiting for a vendor price (up to 6000), `hot` is the sniper list. |

### `history[key]`

`key` is an [item key](how-it-works.md#item-keys) such as `c:2589` or `g:15210:raider's shortsword of the bear`.

| Field | Meaning |
|---|---|
| `scan` | The last scan of the item: `{ at, market, above = {4} }`. `market` is the usual price, `above[i]` the units listed at or above `LEVELS[i] × market`. |
| `flow` | Sales between scans: `{ hours, sold = {4}, pairs, at, market }`. These are decayed sums with a 2-day half-life. `pairs` is capped at 99. |
| `units` | Units listed in the last scan. |
| `hits` | Decaying count of scans in which the item was near a deal (sniper score). |
| `days` | Up to 14 daily records `{ d = day number, min = cheapest unit price, m = usual price, n = units listed, s = units sold }`. Present only for items traded often enough. |
| `lots` | The item's lots of the last scan as text, `"price:count:band,..."` in scan order (up to 300), for lot-by-lot sales tracking. |
| `lotsAt` | Time of the scan `lots` comes from. |
| `shared` | The newest shared scan of the item: `{ at, m = usual price, min = cheapest, n = units, from = sharer }`. |
| `sales` | Lot-tracked sales: `{ hours, pairs, at, b = price histogram of sold units }`, decayed with a 3-day half-life. The histogram is flat: `b[2k]` = units, `b[2k+1]` = cheapest price of 2% bucket k. |
| `t` | Time-of-week pattern: `{ b = baseline, w = {7}, wn = {7}, p = {4}, pn = {4} }`, with factors and observation counts per weekday (`w`, Sunday first) and per part of the day (`p`). |

## `chars[owner]`

| Field | Meaning |
|---|---|
| `positions[key]` | Stock bought and not sold: `{ qty, cost, name, since, mode = "vendor" \| "flip" \| "shop" \| "disenchant", exit }`. `cost` is the total cost of the remaining units. |
| `journal` | Up to 500 entries, oldest first: `{ at, kind = "buy" \| "sell" \| "vendor" \| "expired" \| "fail", key, name, qty, amount, profit }`. |
| `stats[key]` | Item totals: `{ name, bought, spent, sold, earned, profit, days, lastSale }`. `days` is the sum of days held per unit sold. |
| `listings` | Auctions posted through ForeverFlip: price, quantity and auction IDs, used to book sales. |
| `booked[auctionID]` | Sold auctions already booked, so a sale is never counted twice. |
| `unknown` | Purchases without an answer from the server, waiting to be settled on the Journal page. |
| `invoices` | The latest 200 sale invoices `{ at, item, qty, net, cut }`. |
| `rates` | `rates[lower-case item name]` = `{ sold, failed }` posts, from auction mail. |
| `recipes` | `recipes[recipeID]` = `{ name, out = itemID, n = units made, r = { { itemID, count }, ... } }`, read from profession windows. |
| `bids` | `bids[auctionID]` = open bid `{ key, name, qty, amount, value, at }`. |

## `ForeverFlipRaw`

A second SavedVariables table in the same file, written only with **Keep my full scans for the
ForeverFlip Sync helper** on:

```lua
ForeverFlipRaw = {
    format = "FFR1",
    scans = { -- newest first, at most 2
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
