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
| `vendor` | table | `vendor[itemID]` = vendor sell price; `0` means vendors do not buy the item. Shared by all characters. |
| `lastScan` | number | Time of the last full-scan request (the 15-minute cooldown is per account). |
| `markets` | table | `markets[scope]`, one per auction house, where scope = `<realm>-<faction>`. |
| `chars` | table | `chars[owner]`, one per character, where owner = `<realm>-<character>`. |
| `ui` | table | `ui.section`: the last opened page. |
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
| `duration` | `3` | Posting duration: `1` = 2 h, `2` = 8 h, `3` = 24 h. |
| `autoScan` | `true` | Automatic full scan every 15 minutes. |
| `sniper` | `true` | Sniper on. |
| `alerts` | `true` | Sound and screen alerts. |
| `alertMinProfit` | `50` | Smallest profit that raises an alert. |
| `tooltipPrices` | `true` | Price lines in item tooltips. |

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
| `days` | Up to 5 daily records `{ d = day number, min = cheapest unit price, m = usual price }`. Present only for items traded often enough. |
| `t` | Time-of-week pattern: `{ b = baseline, w = {7}, wn = {7}, p = {4}, pn = {4} }`, with factors and observation counts per weekday (`w`, Sunday first) and per part of the day (`p`). |

## `chars[owner]`

| Field | Meaning |
|---|---|
| `positions[key]` | Stock bought and not sold: `{ qty, cost, name, since, mode = "vendor" \| "flip", exit }`. `cost` is the total cost of the remaining units. |
| `journal` | Up to 500 entries, oldest first: `{ at, kind = "buy" \| "sell" \| "vendor" \| "fail", key, name, qty, amount, profit }`. |
| `stats[key]` | Item totals: `{ name, bought, spent, sold, earned, profit, days, lastSale }`. `days` is the sum of days held per unit sold. |
| `listings` | Auctions posted through ForeverFlip: price, quantity and auction IDs, used to book sales. |
| `booked[auctionID]` | Sold auctions already booked, so a sale is never counted twice. |
| `unknown` | Purchases without an answer from the server, waiting to be settled on the Journal page. |

## Compatibility

Data from the pre-release builds that already used `ForeverFlipData` is kept and used as is. The
older `ForeverFlipDB` and `ForeverFlipLegacyDB` tables are not read. If they are still in the file,
they disappear the next time the game writes it.
