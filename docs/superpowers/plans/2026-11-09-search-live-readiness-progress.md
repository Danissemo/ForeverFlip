# SDD ledger — plan: docs/superpowers/plans/2026-11-09-search-live-readiness.md

Base436fab8; isolated source branch fix/5.4-search-live-readiness.
Pre-flight: Controller owns requests/reservations; Adapters normalizes native
keys and bounded metadata loads; preview is informational; Radar reads discovery.
First7 regression tests failed before implementation. Added regressions for
native numeric equipment resolution, quote-own-reserve exclusion, load bounds,
actual toolbar entry, actual completion event, late background results, snapshot
recovery, scope-independent spending and starter UI sorting.
Final fresh reviewer search_live_readiness_review reported6 Important issues.
All reproduced RED→GREEN and fixed in one pass; no findings deferred.
244 tests pass, StyLua verified and LuaLS19/19 passed. Build artifacts and backup
installation receipts are outside the source repository in dist/backups.
Real game test remains blocked by native screenshot timeout through both
available bindings after user switched windowed. No financial UI inputs sent.
Authorised10000 copper; actual spent0.
