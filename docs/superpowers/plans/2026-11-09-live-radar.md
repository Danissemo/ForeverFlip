# ForeverFlip live opportunity radar

User-authorized scope: continuous auction resale and auction-to-NPC discovery in
the native auction window. Profession calculators stay available. No automatic
financial actions. Existing budget, confidence, inventory and group rules apply.

1. Add regression tests for a bounded runtime-only radar scheduler: initial and
   900-second replication, 3-second candidate queries, throttle/backoff, complete
   results only, both strategies, alert deduplication, partial pagination, scope,
   manual pause and stop. Run RED, implement, then run full suite GREEN.
2. Add native Live/Pause/Resume control, live results filter, honest progress and
   EN/UK strings. Test UI actions, progress and translation coverage.
3. Review whole branch, fix material findings with regression tests; format,
   compile Lua 5.1, run suite and LuaLS, package 5.4.0-preview and install with
   backup and hash verification. Never change WTF data.

Interfaces: Radar owns only jobs tagged origin=radar. Controller keeps sole
ownership of native requests. Radar plans cannot pass fresh() for trading.
Manual interaction pauses background work; auction close and Stop disable it.
Replication is market discovery; exact search is bounded to 80 promising/watched
keys per cycle, not an attempt to query the entire market via SendSearchQuery.
Unresolved family variants are skipped. Exact results expire after 30 seconds.

Review focus: late events after pause, request starvation/retry loops, empty
results and stale profits, mixed variants, budgets, partial results, trading
interference and CPU costs. Unit mocks do not establish live server behavior.
