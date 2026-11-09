# Search and live readiness

User authorizes game testing and cumulative expenditure up to10,000 copper.
Computer capture currently fails with `window capture timed out` even after
windowed-mode change and alternative bound native observation. No money spent.

Root causes to reproduce/fix: native ItemKey tables omit required/defaulted fields;
family rows are clicked with level0 instead of their link-resolved exact variant;
links of non-equipment incorrectly receive tooltip item levels; cold item data
is not explicitly requested by live discovery; pending selection has no visible
preview and transient throttle loses the user's action. NPC default1g minimum
profit suppresses tiny-capital opportunities.

Implement regression-first: canonical keys and link-aware selection/preview,
bounded data loading and retry, visible Live preparation/load counts, clarify
full-snapshot cooldown (Auctionator uses same15min policy) while exact searches
remain available. Add explicit manual-only NPC starter with cumulative1g cap,
positive confirmed vendor margin and persisted run spending. Retain financial
checks; no real trades unless game state can be observed.

Verify Lua5.1/native mocks, full suite, bounded performance, final fresh review,
package/install with backup. Report actual spending/profit separately from
simulations; never claim a game test succeeded without native evidence.
