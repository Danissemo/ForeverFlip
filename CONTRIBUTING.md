# Contributing to ForeverFlip

Thank you for helping. Bug reports with an error log, in-game observations of how the WoW Forever
server behaves, and pull requests are all welcome.

## Development setup

You need Python 3.12 and, for formatting, [StyLua](https://github.com/JohnnyMorganz/StyLua) 2.6 or newer.

```bash
python -m pip install -r requirements-dev.txt
python -m unittest discover -s tests -p "test_*.py"
stylua --check ForeverFlip
```

The `sync/` folder (the Sync helper and the community aggregator) uses only the Python standard
library; its tests run with the others.

For in-game testing, link or copy the `ForeverFlip` folder into `Interface/AddOns` of your client and
use `/reload` after each change.

Read [docs/architecture.md](docs/architecture.md) before larger changes.

## Code style

- Lua 5.1, the dialect of the WoW client. Formatting is enforced by StyLua (`.stylua.toml`: 4 spaces,
  120 columns, double quotes).
- Game API calls belong in `AH.lua`. Calculations belong in `Market.lua` or another module that makes
  no game calls.
- Comments explain *why* something is done or which in-game fact it depends on, not *what* the next
  line does.
- Every visible string goes through `L(...)` and needs a Ukrainian entry in `Locale.lua`.
- Nothing may trade without a click: buying, posting, cancelling, selling and mail actions must
  start in a click handler.
- Keep storage bounded. Anything saved per item or per event needs a cap or an expiry.

## Tests

Every behaviour change needs a test. Tests are Python `unittest` cases that run Lua code in the
simulated client (`tests/mock.lua`). Reuse `runtime()` from `tests/test_addon.py`:

```python
from test_addon import runtime

lua = runtime()
lua.execute("assert(ForeverFlip.Util.money(12345) ~= nil)")
```

If you add a game API call, add a fake for it to `mock.lua`, based on behaviour you have seen in game.

## Pull requests

1. Branch from `main`.
2. Keep the change focused, with tests, and run the test suite and StyLua.
3. Add a line to the `Unreleased` section of [CHANGELOG.md](CHANGELOG.md).
4. Describe what you checked in game, if anything.

## Releasing

1. Update the version in **both** `ForeverFlip/ForeverFlip.toc` (`## Version:`) and
   `ForeverFlip/Util.lua` (`F.version`). The build fails if they differ.
2. Move the `Unreleased` notes in `CHANGELOG.md` under a new `## [x.y.z] - YYYY-MM-DD` heading.
3. Go through the [in-game checklist](docs/testing.md#in-game-checklist).
4. Commit, then tag and push:

   ```bash
   git tag v1.2.3
   git push origin v1.2.3
   ```

The `Release` workflow checks that the tag matches the TOC version, runs the tests, builds
`ForeverFlip-x.y.z.zip` with its SHA-256 checksum and publishes a GitHub release. The release notes
come from that version's section of the changelog.

To build an archive locally:

```bash
python tools/build.py            # tests, checks and dist/ForeverFlip-x.y.z.zip
python tools/build.py --skip-tests
```

Versions follow [Semantic Versioning](https://semver.org/): a patch release for fixes, a minor
release for new features, a major release for changes that break saved data or remove features.
