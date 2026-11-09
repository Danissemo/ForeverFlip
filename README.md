# ForeverFlip 5.2

Auction-window addon for WoW Forever 1.60.1, Interface 16001. Pre-release until
live-client checks validate the native protected-action paths.

Money/source formats: [ForeverFlip/DATA_FORMATS.md](ForeverFlip/DATA_FORMATS.md).

Run tests with Python 3.12 and `lupa==2.8` (module `lupa.lua51`):

```powershell
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
