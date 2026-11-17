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
python tools/devflow.py test          # the whole suite, one process per module
python tools/devflow.py test test_bids  # only a module or a test name
stylua --check ForeverFlip
python -m pyflakes sync tools tests
```

The `sync/` folder (the Sync helper and the community aggregator) uses only the Python standard
library; its tests run with the others.

The suite is one process per module, so it takes about half a minute instead of a minute
(`FF_JOBS` sets how many run at once). `test_simulation` is run last and alone: it measures how long
a frame takes, and on a busy processor that number would be the neighbours', not the addon's. A module
that fails is then run again alone, so its output is whole and not mixed with the others.
`python -m unittest discover -s tests -p "test_*.py"` still runs everything in one process when a
debugger is attached to it.

## Local development flow

Turn on the repository's git hooks once per clone:

```bash
git config core.hooksPath .githooks
git config ff.game "C:/World of Warcraft/_forever_"
```

Then every commit runs the hooks in [.githooks](.githooks) and [`tools/devflow.py`](tools/devflow.py):

| Hook | What it does |
|---|---|
| `prepare-commit-msg` | When the message is empty, writes one from what is staged (the areas that moved and the files), so `Commit` with nothing typed still leaves a readable history. A typed message is never touched. |
| `pre-commit` | When code changed (`ForeverFlip/`, `sync/`, `tests/`, `tools/`): StyLua check, `pyflakes` and the whole test suite. A failure stops the commit. |
| `post-commit` | Installs `ForeverFlip/` into the game's `Interface/AddOns` (a `/reload` in game picks it up; a full restart when a file was added or removed), then pushes `main` to GitHub. |

Nothing else is published automatically: a release needs a tag (see [Releasing](#releasing)), which
the hooks never push. `FF_NO_PUSH=1` or `FF_NO_INSTALL=1` skip a step for one commit. A push that
fails (no network) is retried at the next commit, or with `python tools/devflow.py push`.

Assistant and editor hooks are optional local settings, not tracked repository files. See
[`CLAUDE.md`](CLAUDE.md) for portable contribution guidance. A clean checkout does not install
assistant hooks or publish commits on your behalf.

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

1. Write the notes under `## [Unreleased]` in `CHANGELOG.md`. For release-specific testing, update the relevant manual checklist and its cards, then rebuild
   the tester workbook with `python tools/make_tester_workbook.py` (a test fails if it is out of sync).
   The existing `docs/testing.md` cards describe a historical beta: update their actual test steps
   before declaring them verified for a newer version.
2. Go through the [current release checks](docs/release-3.1.0-validation.md), or create
   a new version-specific checklist for a subsequent release.
3. Run the release command with the new version:

   ```bash
   python tools/devflow.py release 1.2.3
   ```

   It says what it will do and asks you to type the version again. Then it commits whatever is
   pending (documentation too; `-m "text"` gives that commit its message), writes the version into
   `ForeverFlip/ForeverFlip.toc` and `ForeverFlip/Core/Util.lua`, turns the `Unreleased` notes into
   a `## [1.2.3] - YYYY-MM-DD` section with its compare link, checks that the package builds,
   commits `Release 1.2.3` (the hooks test, install and push `main`), tags `v1.2.3` and pushes the
   tag. It stops before changing anything when the version is not newer than the current one, the
   tag exists, the notes are empty, or GitHub has commits this copy lacks.

By hand, the same is: the version in both files (the build fails if they differ), the changelog
heading, a commit, then `git tag v1.2.3` and `git push origin v1.2.3`.

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
