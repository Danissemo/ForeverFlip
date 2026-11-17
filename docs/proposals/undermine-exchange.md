# T24 — Undermine Exchange: verified findings and what was built instead

Status: checked 16 November 2026 (undermine.exchange home, `/api.html`, `/terms.html`,
`robots.txt`, and the back-end source github.com/erorus/shatari). No Undermine integration is built.

## Verified findings

- **The API covers Retail only.** Its documented regions are us, eu, tw and kr. The website also
  has WoW Forever regions (usf, euf, twf, krf), but the API documents none of them.
- **No match for the player's house.** Undermine's Forever markets are region-wide; there is no
  realm matching "CAMWOW EU4 Realm 3 PvE-Alliance". A region price is another market and must not
  be mixed into a house's prices.
- **Access.** A key through a Patreon login; the terms forbid scripted access and compiling a
  database without written permission; `robots.txt` disallows `/data/`. So no scraping and no
  helper fetching the website's data files.

## What was built instead (from ForeverFlip's own data)

A **Market reference** in the item tooltip and in the price history window, for the open house
only (the history is kept per realm and faction), under the same 24-hour rule as the rest of the
tooltip (a Full scan or a successful Sync is fresh data). Sources are kept apart:

1. **Your scans** — the player's own full scans. The only source of what was listed: "Cheapest in
   your last scan (age)" with its units, against the 14-day median and mean. History never says a
   listing is available.
2. **Community** — scans shared by other players (guild, realm channel, Sync community data):
   median, mean, days and last seen, as observations.
3. **External** — reserved and empty: "not available (Undermine Exchange has no documented API for
   WoW Forever)".

Day records now keep the per-source prices (`lm`/`lmin` own, `cm`/`cmin` shared) beside the
combined ones. Pure functions in `Market.lua`: `dayPrices`, `priceStats`, `trend` (3, 7, 14 days:
change and least-squares slope, with the number of days), `sourceGap`, `sourcesDisagree`,
`undervalued`, `marketReference`. The undervalued note (cheapest at most 75% of the 14-day median)
is information only and needs a fresh own scan (2 hours), 5 days of prices, reliable sales data
(`M.quality`) and sources that agree. When own and community medians differ by more than 25%, the
Below median strategy offers nothing for the item (`sources_disagree`). The UI caches each item's
reference until the scan data, the item's last scans or the day change. Tests:
`tests/test_market_reference.py`.

## What would unblock an Undermine integration

- **Written permission** from Undermine Exchange (terms@undermine.exchange) for a helper to read
  the data on each user's own key, and
- **documented API support for WoW Forever** (the Forever regions, ideally per realm), so the data
  can be matched to the player's house.

With both, the earlier plan applies: the Sync helper fetches only the player's items with the
user's own key into a separate file, the addon reads it into the External slot, refuses another
realm or region and data older than 24 hours, and never merges it into its own prices.
