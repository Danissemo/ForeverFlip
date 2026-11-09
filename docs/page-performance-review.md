# Page performance 5.4.1

Base024bec4; plan superpowers/plans/2026-11-09-page-performance.md.
Source investigation and Lua5.1 replay reproduced the opening stall on2,000
commodity candidates with64 rows each. Baseline opening ran8,000 model calls,
4,040 metadata calls and took1,581.3ms. A refresh repeated4,000 models and2,020
metadata calls in765–789ms. Native OnShow and UI.show both refreshed the page.

Changes: UI-only incremental discovery cache (four candidates/update,2ms soft
budget); identical single-candidate formulas shared with synchronous explicit
planning; ledger summary/position/sale indexes; metadata cached by exact variant
and validated link with2,048-entry cap; names precomputed once when sorting;
only visible rows request full metadata. No key parsing inside sort comparisons.
Unrelated item-load events no longer repaint the auction. Financial rules,
wallet/reservations, owner/scope and ledger mutations invalidate the UI cache.
Financial actions still require a new, separately verified native search.

Fresh reviewer page_performance_review found four issues, all corrected in one
regression-first pass:

1. Idle regular Deals needed a throttled freshness poll while radar ran.
2. Builds needed a stable candidate array and their actual processed revision,
   followed by a coalesced pass for newer revisions; retained rows expire even
   when a hidden pass resumes after minutes.
3. Cold commodity name filtering needed the same auction-key name fallback as
   displayed rows, without bulk RequestLoad calls.
4. Paused Deals progress could mislead on other sections. Scoped to visible
   regular Deals; treated as a functional UI fix because it implied active work
   on a section where preparation was intentionally paused.

All four cases failed before their fixes. No findings deferred. Additional tests
compare all2,000 cached plans to the original math and verify financial
invalidation, item identity, request counts, ordering and coalescing behavior.

Final verification:226 unittest tests pass; StyLua verified; LuaLS19/19 reports
no problems. Build separately compiles all19 modules using Lua5.1.

Reproducible benchmark: tools/benchmark_ui.py. Latest local run:

| Stage | Time | Model calls | Metadata calls | Item info calls |
|---|---:|---:|---:|---:|
| Cold page open |1.933ms|0|0|0|
| First paint after preparation |4.248ms|0|20|20|
| Reopen prepared page |5.333ms|0|20|0|
| Refresh prepared page |3.755ms|0|20|0|

Preparation:500 bounded updates,538.018ms total CPU,0.938ms median and8.099ms
maximum update including Lua GC/scheduling. Preparation progresses between
frames; its total duration is not included in the cold-open figure. This is an
external Lua5.1/mocked UI benchmark, not WoW FPS or live native rendering.
No real purchases, bids, mail collection, SavedVariables writes or in-game
scriptProfile changes were performed.
