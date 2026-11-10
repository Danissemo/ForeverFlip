# Tab workflows and performance —5.5.0

Base4fa6d98; plan superpowers/plans/2026-11-10-tab-workflows.md.
Client file version rechecked:1.60.1.70862. Native interface16001.

## Changes by workflow

- Auction: the native two-pane state survives craft/disenchant/calculator use;
  reagent shopping no longer overwrites ui.shopping and breaks resize/layout.
- Planner: large explicit calculations run in a coroutine with bounded rank and
  allocation steps; only visible Workbench advances it. Stop and financial,
  owner/scope/rule changes cancel work. Temporary summary globals are cleared
  before each yield. Results are checked against their scope/owner/rule version
  before display/routing. Small explicit plans retain immediate behavior.
- Trading: plan/material routes use deferred exact search with preview; buy and
  confirmation controls require the visible matching plan. Material purchases
  have explicit quantity, unit-price and total-cost caps, zero invented resale
  profit, no bids, and separate quote/confirmation. Purchases/reservations consume
  the authorization; reopening a calculated row does not reset its baseline.
- Lists: existing group/watch callbacks preserved and exercised by regressions.
- Portfolio: positions, pending operations, owned market ledger and invoices have
  pages; row indexes follow the visible page. Exact variants use their own price
  history. Review-sale hints apply actual fee/minimum fee/reserve rules.
- History: graph sizing and selected-key history regressions retained.
- Professions: all reagent rows are readable in a bounded scroll area; each
  calculated row keeps its own procurement request. Another row does not inherit
  the previous reagent's derived quantity/budget. A new calculation starts new
  requests. Scope/owner boundaries remain separate.
- Settings/Overview: all-nine-tab transitions after calculation, settings quote
  invalidation, saved language and owner-scoped FIFO regressions pass.

Shared NPC allocations are capped by the remaining cumulative1g allowance.
Closed-trade summary statistics are memoized by summary revision/minute. These
improvements reduce repeated work and misleading suggestions; they are not
evidence of higher realized income or superiority over another addon.

## Review and verification

Fresh read-only reviewer tab_workflows_review found: material bids bypassed
procurement price limits; a repeated row reset spending; another row inherited
the old derived caps; foreign allocations remained routable; reagent rows after
five were hidden. Each case was reproduced by a failing regression and corrected
in one fix pass. The hidden-row finding was treated as functional because the
user could not verify a reagent identity before buying it. No findings deferred.
Additional group-budget and portfolio page-selection defects were reproduced
and fixed before final verification.

263 unittest tests pass, including19 tab-workflow regressions. StyLua verified,
LuaLS20/20 reports no problems. Packaging compiles every TOC module in Lua5.1.
Model comparisons require equal cost/profit/loss for cooperative vs synchronous
planning; all trade simulations use mocks and spend no game gold.

External Lua5.1 benchmark,2,000 candidates ×64 rows:

| Measurement | Result |
|---|---:|
| Synchronous full planning |498.348ms|
| Cooperative request start |0.037ms|
| Cooperative updates |205|
| Total cooperative CPU |564.310ms|
| Median / maximum update |3.626 /11.969ms|

The calculation is spread across updates; it is not claimed to use less total
CPU. Native debugprofilestop provides a soft2ms scheduling budget, with four
resume calls as the fallback bound; one operation/GC can exceed that soft budget.
These are external timings, not measured WoW FPS. Native visual/protected-action
validation of this release remains unconfirmed. No purchases, bids or mail
collection were performed in game, and no SavedVariables files were overwritten.
