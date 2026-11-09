# ForeverFlip 5.1 Workbench — execution plan

User asks to make the addon more useful than TSM's paid features. This continues
the approved auction-window scope. Implement local decision tools and measure
their behavior; do not claim proven trading superiority or clone paid data feeds.

1. Add tests before `Workbench.lua`: shared-capital allocation, independent
   item/group/risk limits, indivisible lots, actual depth costs, stress scenarios,
   deterministic results, stale/family/malformed data and bounded input.
2. Implement a bounded multiple-choice budget/risk dynamic program on conservative
   money/risk bins. At most 60 candidates, 128 budget bins and 8 risk bins; report
   truncation and approximation. Never execute trades or treat outcomes as promises.
3. Add chronological paper replay against a named fixed-discount baseline. It
   uses prior-only training, a future asking-price scenario after a fixed hold,
   configurable exit haircut and no implied real fills. Keep unknown exits open.
4. Add confirmed-trade analytics: known-cost ROI, wins/losses, loss streaks and
   per-item winners/losers; no conversion of disappeared listings into sales.
5. Integrate a single Workbench page inside the existing auction window, with
   portfolio plan rows, stress details, actual performance, replay and a one-click
   route to fresh exact search. Clicking a recommendation only tightens trade caps.
6. Fresh independent diff review, regressions, full suite, LuaLS, compile TOC,
   versioned 5.1 preview ZIP and source. Preserve 5.0 artifacts and live files.

Public comparison source checked 2026-11-09:
https://tradeskillmaster.com/premium. The free tier already includes the in-game
addon; premium adds website/desktop/alerts/backups conveniences. Local analytics
and planning do not replace that network coverage.

Rulings: same dedicated repository; local branch feature/5.1-workbench; the prior
design approval and request to implement remain in force. No further design gate
or live gold spending. Actual client layout/protected calls still need live checks.
