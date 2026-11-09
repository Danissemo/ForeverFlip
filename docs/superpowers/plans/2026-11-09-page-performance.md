# Page performance fix

Reproduction on 2,000 commodity candidates ×64 rows: opening Deals called the
planner8,000 times and metadata4,040 times (1,581ms); every refresh repeated4,000
plans and2,020 metadata calls (~780ms). OnShow plus show() both refreshed. Item
load events from any addon retriggered whole-market work.

1. RED tests: large page entry must not synchronously rank the market; bounded
   incremental work, cache reuse, input invalidation, same results as existing
   formulas, visible-row-only metadata and targeted item data invalidation.
2. Extract unchanged single-candidate rank, add UI-only incremental result cache;
   preserve synchronous explicit planner APIs. Cache ledger summary by mutation
   and scope; never reuse cached discovery for protected financial actions.
3. Cache item metadata with bounds and explicit invalidation. Avoid metadata
   lookup for unfiltered/unseen rows; precompute sort names once, skip duplicate
   opening refresh. Pause page preparation when hidden or in another section.
4. Benchmark before/after, full regression suite, Lua5.1/StyLua/LuaLS, fresh final
   read-only review; package and install backed-up5.4.1-preview.

Review focus: financial cache invalidation, starvation after frequent scan/item
events, scope/owner changes, UI ordering/filter/pagination, hidden background CPU,
bounded memory, item variants and valid tooltips. No in-game profiling assumed.
