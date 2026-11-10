# Model audit — 2026-11-10

Read-only inspection of Market, Advisor, Workbench, Planner, Radar, DealCache, Stats, Professions, Expressions and Util in the current development working tree. No source or game files changed. Lua 5.1 isolated runtime evidence; no in-game guarantees.

## Additional actionable defects

### P2 — Suggested posting floor can lose money when a minimum fee is configured

- Location: `ForeverFlip/Market.lua:446` (`salePrice`), called by UI posting controls at `UI.lua:1077`, `3440`, `3493`.
- Trigger: own average cost is known and `minFee` exceeds the percentage cut at the proposed price. The cost floor divides average cost by `1-fee-reserve`, ignoring `minFee` and fixed extra costs. This contradicts the function's explicit cost-recovery promise.
- Reproduced: `Market.salePrice({minimum=1200,avgBuy=1000,feeRate=.05,reserveRate=0,minFee=500})` returns `1100`. The same fee model produces `1100 - Market.fee(1100,.05,500) - 1000 = -400` copper.
- Impact: a suggested price can realize a loss. `Controller.lua:1802` only rejects a price below formula/vendor floors; it does not independently enforce the own-average-cost floor. Thus this is more than a conservative display discrepancy. A low or unavailable formula floor permits this suggestion through.
- Fixed extra costs need the intended listing quantity to be handled correctly; the current salePrice API does not receive it. A per-unit minimum-fee floor is safe for single-unit listings but can overprice a multi-unit commodity post.

### P2 — Duplicate recipe material IDs reuse the same owned stock

- Location: `ForeverFlip/Professions.lua:54`; connected trigger: `ForeverFlip/UI.lua:2009` through `2015`.
- Parser accepts duplicate material IDs. craftCalc assigns the full bag quantity for that ID to each row; calculate subtracts owned independently for every row instead of consuming shared inventory or normalizing duplicate IDs.
- Reproduced: parse `1*3@0.01;1*3@0.01`, assign `owned=3` to each parsed row (exactly as the UI does with three units in bags), then calculate with output quantity1, price1000 and fee0. Result: cost600, cashCost0, two shopping rows each qty0. Actual required materials6, available3, so missing3 and cashCost300 copper.
- Existing ui_runtime also reproduced this through `u.actions.craftCalc:Click()` with `api.bagItems` returning three units: toolResult.cost600 and toolResult.cashCost0.
- Impact: crafting procurement cash and shopping list understate required purchases. Total economic material cost/profit remains600-based; the cash/shopping fields are wrong. Reject duplicates or aggregate requirements before allocating owned stock.

### P3 — Break-even display charges both the full minimum fee and percentage fee

- Location: `ForeverFlip/Market.lua:407`.
- Formula adds minFee to costs before dividing by the percentage/reserve factor, although `Market.fee` charges `max(percentageFee,minFee)`.
- Reproduced with cost1000, quantity1, fee5%, reserve0, minFee500: `Market.plan` reports breakEven1579; price1500 produces exactly zero profit (`1500 - 500 - 1000`).
- Impact: misleading break-even guidance; conservative, does not authorize a losing purchase. Find the smallest price satisfying the same fee/reserve rounding model used by profit rather than adding both fees.

## Known defects confirmed, not counted again

- The no-credible-history ladder branch bypasses explicit buy/sell limits and formulas (`Market.lua:318`–`329`), and can dereference nil after a second ladder calculation. It also bypasses `advice.priceCap`: sparse daily history can be sufficient for Advisor.prices (three days) but insufficient for Market.stats (five samples), so the same branch ignores that advisor ceiling. This is the same branch/root cause as the separately reproduced issue supplied to this audit.
- Stats raw purchase aggregation counts voided purchases (`Stats.lua:54`–`60`), already supplied as reproduced.

## Model assumptions and limitations, separate from defects

1. **Own sales rate is not market liquidity or fill probability.** `Market.lua:70` uses time since first known sale within14 days, so idle time before that sale is excluded. This can be optimistic for newly resumed/rare sellers; ten known units on each of two days two days apart yield lower rate about6.32/day, versus about0.904/day if those20 units were observed across14 days. `Advisor.lua:143`–`148` improves this by using recorded activity since first purchase, but that clock also includes periods with no listed inventory, so can be pessimistic. Neither measures units exposed for sale or distinguishes a receipt timestamp from actual auction sale time. `Advisor.trades` deliberately excludes unknown-cost, partial-cost and vendor receipts; sparse evidence forces a one-unit probe. Win statistics condition on fully costed closed sales and do not establish chances of selling unsold stock.
2. **Ladder price is an ask scenario.** `Market.lua:158`–`188` needs only three listings/five units and uses a volume quantile, not executed trades. Confidence increases with listing count, though more competing listings need not mean faster demand. Simultaneous market manipulation and correlated price collapses remain possible. These should remain scenario/ranking assumptions, not expected-return claims.
3. **Minimum fees are aggregated once.** `Professions.lua:62`, `84` charge one floor on the combined output value. Selling different disenchant output IDs necessarily creates separate auctions; with two100-copper outputs, minFee75 and fee0, the function estimates net125 while separate sales net50. Fractional expected yields plus nonlinear minimum fees also cannot be transformed into expected net proceeds without an outcome/distribution or batch-sale assumption. Market plans similarly treat resale proceeds as a consolidated batch. The fee setting is explicitly labeled an assumption; this audit does not establish a real Forever minimum auction fee. If a nonzero floor is used, output batching must be disclosed or modeled.
4. **Allocator is intentionally approximate.** `Workbench.lua:189`–`217` truncates to the60 best full-plan ROI candidates before calculating utility; partial-prefix options sample only quarter quantities and the first eight lot boundaries. Rounded-up resource bins can reject feasible combinations, and one state per cash/risk bin can discard a lower-utility state whose group usage permits a better final plan (`:248`–`269`). The code explicitly returns approximate/truncated indicators. Sum of scenario losses is not a calibrated portfolio loss quantile; it ignores probabilities, tail risks beyond drop, and correlation modeling.
5. **Replay assumes exits from future asks and leaves unresolved capital open.** `Workbench.lua:437` only closes between hold and hold+maxGap. A gap beyond that permanently leaves that position open for the rest of the replay, even if observations later resume; result separately exposes openCost, so closed P/L alone omits that exposure. Training uses prior observations only; no ordinary future lookahead found. Current settings apply retrospectively; no advisor, inventory exposure, turnover/queue, fill probability or historical rule-version model. UI labels these limitations (`UI.lua:779`–`802`).
6. **Live scanning deliberately excludes stable failed checks until new discovery data.** `Radar.lua:237`–`240` records checkedAt after an unfinished search, and `:139` suppresses candidates with unchanged older snapshot time and no opportunity. No time-based retry resets that suppression. Normally a new15-minute snapshot provides fresh data; prolonged snapshot failure leaves that item unqueried indefinitely. Tests intentionally assert the no-spin behavior (`test_radar.py:test_timeout_does_not_spin`). This trades retry responsiveness for query pressure.
7. **Top live opportunities can starve lower-ranked items.** `Radar.lua:153`–`172` retains the top120;40 rotating watchlist entries can consume queue capacity. Already-found opportunities bypass checkedAt suppression and keep competing in subsequent cycles. Persistent strong deals may occupy every discovery slot, with no rotating share for lower-ranked discovery candidates. Watchlist fairness exists; market-wide exhaustive fairness does not.
8. **Sales-period returns exclude separately recorded expenses.** Stats aggregates `salesHistory` profit at `Stats.lua:35`–`36`; performance item/day breakdowns likewise aggregate closed receipts (`Workbench.lua:350`–`380`), while summary.realized includes expense entries. Performance UI explicitly labels its separate total as including expenses (`UI.lua:935`). Period/item profits should be interpreted as closed-sales margins, not net business earnings including listing costs and transport expenses.
9. **Display caches and frame budgets are bounded, not immutable snapshots.** DealCache invalidates owner/scope/wallet/reservations/ledger sequence/rules and revisits advancing candidate versions after an ongoing pass; cached display can intentionally lag30 seconds while actual trading re-searches. Planner guards owner/scope/wallet/reservations/ledger/rules; quote changes do not cancel its captured pass. No additional reproducible cache correctness failure found. Coroutine/frame limits check at operation boundaries, so one large candidate may exceed2ms even though aggregate work yields.
10. **Direct model inputs do not uniformly reject monetary overflow.** Expressions limits intermediate values to1e15 and bounded grammar; material parser caps requirement count/quantities/prices. Professions.calculate, however, accepts finite enormous outputQty and outputPrice whose product is infinity, returning complete=true with NaN profit. Normal output-price UI parser caps price, but a finite outputQty such as1e308 still overflows against it. Low practical priority; no arbitrary execution observed.

## Verification

Using `C:/FF/.tools/python/Scripts/python.exe` and existing `lupa.lua51` runtimes:

- `-m unittest discover -s tests -p test_domain.py -q`:21 tests passed.
- From tests/: `-m unittest test_advisor test_workbench test_earning test_radar test_performance test_speed test_sales_stats test_functional_audit -q`:112 tests passed (7.353s).
- Additional read-only snippets reproduced the three new actionable monetary/procurement discrepancies exactly as above. Existing tests did not detect them.

No source/game mutation, deployment, SavedVariables execution, or live financial action performed.
