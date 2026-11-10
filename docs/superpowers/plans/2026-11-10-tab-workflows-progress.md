# SDD ledger — plan: docs/superpowers/plans/2026-11-10-tab-workflows.md

Base4fa6d98; branch fix/5.5-tab-workflows in dedicated source repository.
Pre-flight: UI reagent state separated from native shopping; Controller retains
native requests/reservations; coroutine yields never retain cached financial
globals; all routes still require separate current exact verification.

Task1 complete: first6 tests reproduced state collision, failed routes, missing
pages, variant-price misuse and shared NPC budget overflow. Fixed RED→GREEN.
Task2 complete: explicit procurement caps and consumed authorization tests;
portfolio pages use visible global row indexes and actual sale fee assumptions.
Task3 complete: Planner coroutine, rank/DP checkpoints, financial cancellation,
Stop, identical model results and bounded start checks pass.
Final review: tab_workflows_review. Five material findings corrected in one
RED→GREEN pass, including inaccessible reagent identities. Nothing deferred.
Task4 verification:263/263 tests, StyLua, LuaLS20/20 pass. Benchmarks and limitations
recorded in docs/2026-11-10-tab-workflows-review.md. Build/hash/backup installation
receipts are stored outside the source repo in dist/backups. No actual gold spent.
