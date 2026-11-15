# Where the work stands

The first file to read in a new session. The changelog says what was done; this says what is
being done now, what waits, and what was decided. Keep it short and current: when a task ends, move
its line to the changelog and start the next.

Last updated: 14 November 2026.

## Being done now

**`2.2.0-beta.2` is released** (14 November): version in `ForeverFlip.toc` and `Util.lua`,
`CHANGELOG.md` heading, committed and pushed; the tag `v2.2.0-beta.2` is pushed by hand. It fixes
beta.1, which showed no auction house tab and broke the merchant page (`fitButton` called
`b.GetFontString()` without the button). Confirm in game that the tab and the merchant page are
back.

**Unreleased, after beta.2** (14 November): My items footer explains Best (verdict and the routes
in the Undercuts shape), 11 rows so the list stops above its buttons, posting under the game's
addon restriction (`AH.restricted`, `C_RestrictedActions`) blocked with a reason and a refused post
no longer holding the buttons, and the Gear I can't use button gone from the game's merchant tabs.
To check in game: the footer's wording and layout, and that Post AH-worthy out of combat posts.
**Open: Post AH-worthy gets "That action is currently restricted" out of combat** (15 November).
The server's `AUCTION_HOUSE_SHOW_ERROR` is `HasRestriction` while `C_RestrictedActions` reports
nothing. ForeverFlip posted 60 times from Lasqa until 14 November 08:24 and the posting code has
not changed since. Next: does the game's own Sell tab post the same item? Yes → the client refuses
addon calls (taint, a restriction type not checked); no → the server restricts the character.

## Waiting

- **The in-game checks of the batch of 14 November.** None of it is confirmed in the game yet,
  though all of it is in `2.2.0-beta.1`. Worth a look: **To vendor** with a purse too small for a
  lot (the whole offer listed, Buy taking the part the money covers), the new **Cost** column, the
  Crafting page's **Learned recipes only** toggle, the learned professions list scrolling instead of
  running off the window, **Check all** on **Journal and profit**, a **wait** advice leaving the
  other way out buttons usable, and **Check all** during a full scan (it keeps its name now and the
  scan stops from **Stop scan**).
- **The journal, still.** One defect was found and fixed (a purchase sold before its own mail arrived
  was booked twice, leaving phantom stock and a lot open for good). A review of the accounting found
  no other reproducible fault, but the player's report — "sometimes you can't see what happened
  recently with an item" — was not narrowed to a case; ask for a concrete item and sequence when it
  comes up again.
- **The poison check in game.** A merchant that refuses an item (a rogue's poisons are the ones
  seen) can only be known by selling one: confirm that a stack refused by the merchant drops out of
  **Sell to vendor** and of **Deals → To vendor**, that no rescan brings it back, and that
  `/ff refused` names it. Check too that `hasNoValue` is really in the container info of this client
  (`C_Container.GetContainerItemInfo`): the item data and the API docs say it exists, but it is only
  ever seen as nil so far, and an item it flags should be left off Sell to vendor at once.
- **The three window changes in game.** The **Best** column's hover on Selling → My items (both
  routes, the `*`, the difference), the rebuilt My items footer (seven lines, then the price row,
  then the buttons — nothing overlapping), and the busy **merchant** frame's `Sell gear I can't use`
  inside the window in Ukrainian. All three are layout, which the mock cannot show.
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
