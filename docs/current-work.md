# Where the work stands

The first file to read in a new session. The changelog says what was done; this says what is
being done now, what waits, and what was decided. Keep it short and current: when a task ends, move
its line to the changelog and start the next.

Last updated: 14 November 2026.

## Being done now

Nothing: the working tree is clean and pushed, and the changes listed in the changelog under
`[Unreleased]` are finished and checked but not released.

## Waiting

- **Release the unreleased fixes.** The Buy tab marks no longer touch the game's rows, blocked
  actions are recorded and `/ff diag` lists them, and disenchanting uses the documented calls. These
  need a version in `ForeverFlip.toc` and `ForeverFlip/Util.lua` (`2.1.0-beta.3` or `2.1.0`), a
  `CHANGELOG.md` heading and a tag — the hooks never tag. Ask which version.
- **The in-game checks are still owed.** The fixes were proved by the test suite and the simulated
  client, not in the game. Someone has to buy in the Buy tab on a new character (the bug that was
  fixed), read `/ff diag`, and look at disenchant deals. `docs/tester-checklist.uk.xlsx` holds the
  checklist.

## Decided

- Work goes straight to `main`; the hooks test, install into `C:/World of Warcraft/_forever_` and
  push after every commit. `FF_NO_PUSH=1` and `FF_NO_INSTALL=1` skip one step for one commit.
- Releases are manual: a tag pushed by hand, never by a hook.
- The game's client is 1.60.1.70938, Interface 16001. `C:\WOW\World of Warcraft\_retail_` is not
  the target.
- ForeverFlip has a Sync helper (`sync/`, Python, standard library only) and a community aggregator;
  both are part of the same release cycle.
