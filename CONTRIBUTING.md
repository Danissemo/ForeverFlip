# Contributing to ForeverFlip

Thank you for helping. Bug reports with an error log, in-game observations of how the WoW Forever
server behaves, and pull requests are all welcome. Everyone taking part follows the
[code of conduct](CODE_OF_CONDUCT.md); security problems are reported privately as the
[security policy](SECURITY.md) explains. Questions are welcome in
[Discussions](https://github.com/Danissemo/ForeverFlip/discussions).

## Development setup

You need Python 3.12 and, for formatting, [StyLua](https://github.com/JohnnyMorganz/StyLua) 2.6 or newer.

```bash
python -m pip install -r requirements-dev.txt
python -m unittest discover -s tests -p "test_*.py"
stylua --check ForeverFlip
```

The `sync/` folder (the Sync helper and the community aggregator) uses only the Python standard
library; its tests run with the others.

## Local development flow

Turn on the repository's git hooks once per clone:

```bash
git config core.hooksPath .githooks
git config ff.game "C:/World of Warcraft/_forever_"
```

Then every commit runs [`tools/devflow.py`](tools/devflow.py):

| Hook | What it does |
|---|---|
| `pre-commit` | When code changed (`ForeverFlip/`, `sync/`, `tests/`, `tools/`): StyLua check and the whole test suite. A failure stops the commit. |
| `post-commit` | Installs `ForeverFlip/` into the game's `Interface/AddOns` (a `/reload` in game picks it up; a full restart when a file was added or removed), then pushes `main` to GitHub. |

Nothing else is published automatically: a release needs a tag (see [Releasing](#releasing)), which
the hooks never push. `FF_NO_PUSH=1` or `FF_NO_INSTALL=1` skip a step for one commit. A push that
fails (no network) is retried at the next commit, or with `python tools/devflow.py push`.

An AI assistant working in the repository (Claude Code) also runs `python tools/devflow.py stop` as
its Stop hook (`.claude/settings.local.json`, not committed): it cannot end its turn while changes are
uncommitted, and anything committed but not pushed is pushed.

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
   Update the version in `docs/testing.md` and its cards, then rebuild the tester workbook with
   `python tools/make_tester_workbook.py` (a test fails while it is out of date).
3. Go through the [in-game checklist](docs/testing.md#in-game-checklist).
4. Commit, then tag and push:

   ```bash
   git tag v1.2.3
   git push origin v1.2.3
   ```

For a beta, set the version to `x.y.z-beta.N` in both files, give it its own dated changelog
section and tag `vx.y.z-beta.N`. The workflow publishes it as a pre-release, using that exact
section and links to the checklist at that tag. Only older betas without their own section fall
back to the `x.y.z` notes. Empty or missing notes stop publication. Set the version back to
`x.y.z` for the stable release itself.

The `Release` workflow checks that the tag matches the TOC version, runs the tests, builds
`ForeverFlip-x.y.z.zip` and `ForeverFlipSync.exe` and publishes a GitHub release (GitHub shows the
SHA-256 of each file). The release notes
come from that version's section of the changelog.

To build an archive locally:

```bash
python tools/build.py            # tests, checks and dist/ForeverFlip-x.y.z.zip
python tools/build.py --skip-tests
```

Versions follow [Semantic Versioning](https://semver.org/): a patch release for fixes, a minor
release for new features, a major release for changes that break saved data or remove features.
