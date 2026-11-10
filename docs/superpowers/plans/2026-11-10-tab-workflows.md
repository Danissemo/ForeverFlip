# Tabs and opportunity workflows

User scope: optimize all tabs and improve usable gold-making workflows; preserve
financial verification and never equate model predictions with earnings.

Confirmed source issues: craft calculator overwrites ui.shopping native layout;
portfolio truncates inaccessible records; planner and route/material search use
old synchronous or non-deferred paths; portfolio values exact variants with base
prices; shared plan budget can exceed the cumulative NPC trial allowance.

1. Reproduce with regressions, fix state collision, canonical route/material
   selection, visible-plan guards and exact-variant valuation. Test all nine tabs
   after each calculator and after native result events.
2. Add portfolio paging with global row indexes and correct owner/scope filtering.
3. Move large explicit planning into resumable, bounded frame work. Preserve
   original math/constraints, cancellation and stale-context checks. Cache summary
   performance and make group NPC allocations honor the remaining trial allowance.
4. Fresh read-only final review; RED/GREEN fixes, full suite, native API references,
   Lua5.1/StyLua/LuaLS, benchmark, package/install with backup and hash verification.

No real earnings claim. Native game capture previously timed out; in-client
visual/protected-action validation remains separate from unit mocks.
