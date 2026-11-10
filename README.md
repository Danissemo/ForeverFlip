# ForeverFlip 5.5

Auction-window addon for WoW Forever 1.60.1, Interface 16001. Pre-release until
live-client checks validate the native protected-action paths.

Money/source formats: [ForeverFlip/DATA_FORMATS.md](ForeverFlip/DATA_FORMATS.md).

Run tests with Python 3.12; install requirements-dev.txt (Lua tests use lupa.lua51):

```powershell
python -m pip install -r requirements-dev.txt
python -m unittest discover -s tests -v
python tools/build.py --output dist
```

The build verifies all tests, compiles every TOC module with Lua 5.1, validates
the archive and emits SHA-256. It never changes live addons or SavedVariables.
No network service or subscription is required. There is no bundled TSM Premium
code or data; the addon implements its own models and limited formula language.

5.1 adds a shared-capital plan with conservative budget/risk/group constraints,
known-cost performance, loss-streak exclusions and chronological asking-price
replay. It does not establish trading superiority over TSM or provide paid feeds.
See docs/workbench-plan.md and docs/workbench-review.md.

5.2 adds an optional conservative advisor with day-balanced EWMA/quantile price
caps, Wilson profitable-close statistics, ROI-normalized quarter-Kelly sizing,
own-sale turnover caps, one-unit probes and click-through paged recommendations.
No formula entry is required for automatic planning.

5.2.3: Ukrainian interface with /ff lang uk and an OFL Cyrillic font, placeholder
and glyph coverage tests. See ForeverFlip/README_UK.md.

5.3 replaces the scaled dashboard shell with native auction top tabs, a two-pane
shopping list/results view, native table headers and responsive unscaled item
columns. Existing trade/math/accounting callbacks remain behind the new shell.
English uses native WoW fonts; Cyrillic keeps the bundled font fallback.

5.4 adds an explicit Live radar in the native auction window. Market replication
runs no more often than every900 seconds; up to80 promising/watched exact keys
are checked at least3 seconds apart, respecting native readiness. Resale and
auction-to-NPC opportunities use existing confidence and financial rules. Exact
results expire after30 seconds and always require a separate manual search
before trading. Pause preserves passive snapshot ingestion; manual review waits
for an outstanding radar search to drain. Stop/auction close disable the radar.
Ranking is incremental, four exact variants per update; no automatic buying.

5.4.1 removes synchronous whole-market ranking from Deals page entry. Results
prepare between frames, prepared pages reuse a financial-input-aware cache,
only visible rows request full item metadata and item-name sorting parses each
key once. See docs/page-performance-review.md and tools/benchmark_ui.py.

5.5 repairs tab transitions after profession calculations, pages the portfolio,
uses exact variant prices/current fees and caps shared NPC plans by the remaining
trial budget. Large planning is cooperative; reagent procurement has explicit
price/quantity/cumulative-cost bounds and separate manual confirmation, with
no invented resale profit or material bids. See docs/2026-11-10-tab-workflows-review.md.
