# Where the work stands

The first file to read in a new session. The changelog says what was done; this says what is
being done now, what waits, and what was decided. Keep it short and current: when a task ends, move
its line to the changelog and start the next.

Last updated: 14 November 2026.

## Being done now

Nothing: the changes of 14 November (the six reported items) are finished and checked but not
committed. The changelog under `[Unreleased]` lists them.

## Waiting

- **The in-game checks of the batch of 14 November.** Everything below was proved by the test suite
  and the simulated client, not in the game. Worth a look: **To vendor** with a purse too small for a
  lot (the whole offer listed, Buy taking the part the money covers), the new **Cost** column, the
  Crafting page's **Learned recipes only** toggle, the learned professions list scrolling instead of
  running off the window, **Check all** on **Journal and profit**, and a **wait** advice leaving the
  other way out buttons usable.
- **The journal, still.** One defect was found and fixed (a purchase sold before its own mail arrived
  was booked twice, leaving phantom stock and a lot open for good). A review of the accounting found
  no other reproducible fault, but the player's report — "sometimes you can't see what happened
  recently with an item" — was not narrowed to a case; ask for a concrete item and sequence when it
  comes up again.
- **The poison check in game.** A merchant that refuses an item (a rogue's poisons are the ones
  seen) can only be known by selling one: confirm that a stack refused by the merchant drops out of
  **Sell to vendor** and of **Deals → To vendor**, and that a new deal shows `vendor, refuses`.
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
