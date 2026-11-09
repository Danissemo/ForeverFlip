# Live radar 5.4 review and verification

Base: 4d3ee28. Plan: superpowers/plans/2026-11-09-live-radar.md.
Fresh read-only reviewer: live_radar_review. Seven findings addressed in one fix
pass, each reproduced by a failing regression before implementation:

- Abandoned-background/manual same-key overlap: preserve the outstanding job,
  queue manual review, then issue its own request after completion/timeout.
  Radar-origin plans and queued review cannot pass fresh().
- First replication discarded by Pause: keep passive ingestion until complete.
- Family reduced to first resolved link: group each resolved exact variant and
  skip only individual unresolved rows.
- Pagination repeatedly requested without responses: one outstanding request,
  response clears its wait flag; three-page budget and native timeout remain.
- Synchronous shortlist CPU burst: evaluate at most four exact variants per
  update, retain at most160 provisional plans, cap the queue at80.
- Completed cache changed but old opportunity survived: matching native cache
  updates invalidate the stored live opportunity.
- Stop retained stale displayed opportunities: Stop clears the live list. This
  was treated as material because it affected price information shown to users.

Additional regressions cover recent scoped cache recovery after reload, bounds,
throttle/error backoff, both strategies, current group/budget constraints, expiry,
scope/owner/close/stop, manual navigation and hiding the native tab, translation,
and avoiding full-market reranking on every Live UI repaint.

Verification: 211 unittest tests passed; StyLua verification passed; LuaLS18/18
modules reported no problems. Build separately compiles all TOC modules as Lua5.1.
Local synthetic benchmark: 2,000 commodity keys ×64 rows, 500 incremental updates,
624.26ms total CPU, 0.905ms median /9.268ms maximum update, queue80, one query.
These timings describe this external Lua5.1 test process, not game frame times.
No purchases, bids or mail collection performed; live server timing and visual
appearance remain unverified. No claim of universal market coverage or superior
realized returns over TSM is made.
