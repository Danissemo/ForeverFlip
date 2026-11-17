# Sales model: Sure, Est./day, and how they are rebuilt (T32)

What the two numbers a resale rests on are made of, which biases were proven in them, what was
changed, and how the derived statistics are rebuilt from the raw scans. Code: `Market.lua`
(formulas, no game API), `Scan.lua` (lot tracking, rebuild job), `Data.lua` (versions, backup,
rollback), `Raw.lua` (raw scan reader). Tests: `tests/test_analytics_model.py`.

## 1. Inputs

| Data | Where | Kind |
|---|---|---|
| Lots of the last full scan per item (`price:count:band`, owner flags) | `h.lots`, `h.lotsAt`, `h.lotOwners` | observed |
| Listed units by price level, usual price, daily min/median | `h.scan`, `h.days[].min/m/n`, `h.units` | observed |
| Raw full scans, one line per auction, no seller name, own flag only | `ForeverFlipRaw.scans` (at most `R.KEEP` = 8, removed once uploaded) | observed |
| Journals, invoices, settings | `F.db.chars`, `F.db.settings` | observed, never touched |
| Lot-tracked sales: price histogram `s.b` (part sales + whole lots), `s.bl` (whole lots only, new), sale log, `pairs`, `hours`, `sure`, `lots` | `h.sales` | derived |
| Units that disappeared per price level | `h.flow` | derived |
| Units seen sold per day | `h.days[].s` | derived |
| Whole lots waiting for the next scan | `h.pending`, `h.pendingAt` | derived |

Units: prices in copper per unit, rates in units per day, hours are the decayed sum of the
intervals between compared scans (half-life `M.SALE_HALF_LIFE` = 3 days).

## 2. Formulas

**Lot tracking** (`S.trackLots`, `M.trackSales`, `M.confirmGone`, `M.recordSales`). Two full scans
300 s to 3 h apart are compared lot by lot. A lot that shrank is a sure part sale. A lot that
vanished whole is a suspect only if its time band guarantees it could not have expired
(`M.BAND_MIN`) and it was not dearer than the cheapest lot still there (else: cancelled); it is
confirmed by the next scan within 3 h unless the same lot shows up again (a repost). The player's
own purchases (`S.ownBought`) are taken out. Partial scans and scans with unreadable rows are not
used for vanished items.

**Est./day** (`lotDemand`): `(part units + 0.5 · whole-lot units, at ≥ 85% of price) /
(hours + 4) · 24`. Fallback `demandAt` on `h.flow` (disappearances at levels 0.6/0.75/0.9/1.05 ×
market) while no lot pair exists.

**Sure** (`M.confidence`): chance the lot sells within `M.SURE_HOURS` = 48 h. Units sold at ≥ 95%
of price, share of them real (`real`: part sales count 1, whole lots `M.LOT_WEIGHT`), units per
purchase `m`, the queue ahead (units listed below the price at the last scan, `M.listedBelow`, when
that scan is under 24 h old); rivals' later undercuts take a share of the buyers,
`share = min(M.RIVAL_SHARE = 1/2, undercuts an hour × median lot / units bought an hour)`, so the
rate is × (1 − share); a negative binomial tail on the purchase rate (prior 0.1 over 24 h), × sweep
factor × freshness `0.5^((age − 6 h)/48 h)`. One Sure for the item: the units to sell
(`Deals.sellQty`: a resale's units plus those held, else the units in the bags) at the recommended
price, the same on the tooltip, Deals and Selling. The 80% limits are not shown any more.
Earlier the undercuts were queued as whole lots for 48 hours: Silver Ore, selling about 290 a day
with 7.8 undercuts an hour, got about 1,000 units ahead and Sure 0% at every price.
Fallback on `h.flow`, capped at 0.5, with the same listed-below queue.

Why Sure falls as the price rises: with `n(p)` the units bought at ≥ 0.95·p and `L(p)` the units
listed below p, `n` never grows and `L` never shrinks as p rises, so the purchases needed,
`ceil((qty + L(p) + c·H·lot) / m)`, never fall while the rate behind them never rises, and the
tail `P(B ≥ k)` is monotone in both. Before the queue counted `L(p)`, a price above the cheapest
lots kept the same queue, and Sure barely moved between prices with the same sales above 95%.

## 3. Biases found

Proven by tests (old behaviour on the left):

1. **Whole lot = full sale in Est./day, half in Sure.** A lot that vanished whole may have been
   cancelled or moved; Sure already counted it at 0.5, Est./day at 1. Now 0.5 in both (`s.bl`
   keeps the whole-lot part per price, `M.LOT_WEIGHT`). `test_a_whole_lot_counts_half_in_est_per_day`.
2. **Reprice of an unknown seller = sale.** Without owners (raw scans, scans that name no seller)
   a lot taken down and posted at another price looked like a sale plus a new lot. A vanished lot
   is now a repost when a new lot of the same count appears in the same pair or the confirming scan
   (`takeCount`). Conservative: a real sale of N units at the same moment as a new lot of N at
   another price is missed. `test_an_unknown_seller_reposting_a_lot_at_a_new_price_did_not_sell`.
3. **Disappearance fallback** (`h.flow`) counts expired and cancelled units. Kept, but marked:
   `M.quality` reports `flow_only`, so a page can say the number is inferred.
4. **One pair, full confidence.** One 15-minute pair with a sale gave a full Est./day (prior only
   4 h). `M.quality` now reports `few_pairs` below 4 pairs and `few_hours` below 2 h watched.
5. **Stale data shown as current.** Est./day had no age limit; `M.quality` reports `stale` past
   3 days since the last pair.

Checked and not biased: incomplete scans are excluded (live: `S.isShort`, unreadable > 0.5%, scan
< 60% of the previous; the rebuild applies the same unreadable/size rules); a repost at the same
price is not double counted; realms never mix (history is per `scope`, raw scans are filtered by
`scope`, `test_scans_of_another_realm_never_mix`).

Known limits, not fixed: lots beyond `M.LOTS` = 300 per item are not tracked; raw lines carry no
seller, so a rebuild sees reposts less well than a live scan with owners (a seller tag in a future
`FFR2` format would close it); `h.days[].s` counts units unweighted by price.

## 4. Sample quality

`M.quality(h, price, now, own)` → `level` none/low/ok, `reliable`, `reason` (`no_data`,
`flow_only`, `few_pairs`, `few_hours`, `stale`), the sample (pairs, hours watched, part and
whole-lot units, own sold/failed), `perDay` with 80% limits (`M.rateRange`, Jeffreys prior,
Wilson-Hilferty quantile). Zero sales over enough hours is reliable: 0 with an upper limit.
`M.sureLimits` gives Sure at the lower and upper rate limits (kept for the calibration; pages show
only the figure itself). `M.calibration` (Brier score, five
bins) and `M.rateCheck` (predicted vs invoiced units) compare predictions with what happened, once
posts record the Sure/Est./day they were made with.

Thresholds: `M.RELIABLE_PAIRS` = 4, `M.RELIABLE_HOURS` = 2, `M.RELIABLE_AGE` = 3 days,
`M.LIMIT_Z` = 1.2816.

## 5. Rebuild, migration and rollback

- `D.STATS_VERSION` = 1; each house carries `statsVersion`. A new house starts current.
- On the first frame with data `S.planRebuild` lists houses below the version. `S.rebuildStep`
  (a 4 ms slice per frame, full scans blocked meanwhile: `canStart`/`start` return "busy",
  `auto` waits) replays `R.scansFor(scope)` oldest first, deduplicated by time, through
  `S.trackLots` and `M.recordFlow` into separate shadow tables, only for items the history knows.
- A complete replay is committed at once (`D.commitStats`): `h.sales`, `h.flow`, `h.days[].s`
  replaced; the last lots and suspects only when the replay saw a newer scan. If a live scan of the
  house finished meanwhile, the house is replayed again. An error leaves the old tables and
  `market.statsError`; the next login tries again.
- Not touched: raw scans, prices, listed units, daily min/median, journals, invoices, settings
  (`test_rebuild_measures_from_raw_and_leaves_raw_journals_and_settings_alone`). Replaying twice
  gives the same tables (`test_rebuild_is_idempotent`).
- An item no raw scan covers starts from no data (`no_data`) until new scans measure it.
- Rollback: `market.statsBackup` keeps the replaced tables for 7 days; `D.rollbackStats(market)`
  puts them back and sets `statsHold`, so the same version is not rebuilt again.
