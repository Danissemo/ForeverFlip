# Where the work stands

The first file to read in a new session. The changelog says what was done; this says what is
being done now, what waits, and what was decided. Keep it short and current: when a task ends, move
its line to the changelog and start the next.

Last updated: 17 November 2026.

## Current release: 3.1.0

[ForeverFlip 3.1.0](https://github.com/Danissemo/ForeverFlip/releases/tag/v3.1.0)
is published. The addon metadata (`ForeverFlip/ForeverFlip.toc`) and runtime version
(`ForeverFlip/Core/Util.lua`) both read `3.1.0`. The repository's main branch contains the
release commit plus two follow-up CI/release-flow fixes; these do not define another version.

The 3.1.0 release covers separate auction-house scopes, Retail capability guards, version
announcements through Sync, diagnostic traces and developer mode, and corrections to gear searches,
batch order, scan/sniper interaction, seller advice and tooltip sizing. Use the
[3.1.0 release validation matrix](release-3.1.0-validation.md) for remaining manual checks.
Automated tests and a published release are **not** proof that every WoW Forever or Retail
interaction was checked in the game.

### Current follow-up

- Confirm the 3.1.0 regression matrix on an actual WoW Forever client, including both languages
  and the protected buy/post/cancel actions.
- Check the Retail 12.x capability-dependent paths separately; Sync's game-folder discovery
  intentionally targets WoW Forever rather than Retail.
- Record reproducible failures as issues and note test results before the next tagged release.

## Historical work log (status as recorded before 3.1.0)

The following entries are preserved as dated development notes. Phrases such as
"not committed", "current beta", and "in the working tree" describe the state when written,
**not** the repository or release status now. The changelog and the 3.1.0 tag take precedence.

### Being done then

**`3.0.0` is released** (17 November, the player asked for a full release): version in
`ForeverFlip.toc` and `Util.lua`, `CHANGELOG.md` heading, committed, pushed and tagged `v3.0.0`.
Everything listed below as "installed, not committed" is in it. The in-game checks named below are
still owed.

**Check all speed, Est./day and Sure for new endings, Sure on Bids** (17 November, the player
asked; no commit). Check all on a deal page sends one `SearchForItemKeys` for all its items first
(`Deals.startPre`/`preStep`) and settles items nobody sells or whose lowest price is at or above the
deal's exit; the log reports each batch's time (`D.reportBatchTime`). Gear endings without data take
Est./day and Sure from their other endings (`Deals.siblingEstimate`, greyed "~"). Bids got a Sure
column (`Bids.sure`). Owed in the game: the time of a 35-deal Check all (target 30 s) from the log
line, and whether the first query's answer is ever partial for gear.

**What the addon lacked** (17 November, the player asked for all of it, no commit or release):
sounds for a sale and an outbid, window size, the data summary on Settings → Data, Analytics → My
results, `tools/savedata.py` for copies of the saved data, and a header-fit test. Installed, not
committed. Owed in the game: the sounds (sound kit ids 120 and 12889 on this client), how 90% and
110% sit in the auction house, and the My results table in both languages.

**Column headers and the Settings pages** (17 November, the player asked). Headers unified (names,
widths, alignment, Ukrainian lengths; the shop table lost Source/status). Settings split into
General, Automation, Display, Key bindings, Sharing, Messages, Data; the Market reset limits and
the auction duration are now also on General, Reset settings is new (`Data.resetSettings`).
Installed, not committed. Owed in the game: how the headers and the new pages look in both
languages (the widths were estimated, not measured).

**The unification review, all ten items** (17 November, the player asked for all of it). See the
status at the top of `docs/unification-review.md`. Behaviour changes: disenchant deals and Sniper's
disenchant limit now need the minimum return too; a disenchant deal needs to beat selling the item
as it is; merged colour shades. Not committed. Owed in the game: the colours, the Disenchant page.

**The 15-point round: strategies, Market reset, tooltips, Crafting, review** (17 November).
Under market renamed **Market reset** and made all-or-nothing (every lot under the relist price);
the purchase strategy is kept on the lot and the position (`Trade.boughtWay`, 14 days); Deals and
Journal views in one order with Crafting and Disenchant; tooltips wrap (`UI.tipPair`) and no longer
take clicks (`UI.hoverOnly`); My items, Undercuts, My auctions columns; Crafting Sure and Best by the
Selling rule. `docs/unification-review.md` waits for the player's marks. Installed (backup
`C:\FF\backups\pre-install-20261117-114017`), not committed. Owed in the game: the My items button
rows, a Market reset buy, the tooltips on a narrow screen.

**For sale table, bag check speed, Under market** (17 November, five screenshots). For sale lost
Cost each, Profit "N / N", Note "Choose", buttons spread in four groups (`UI.layoutSellButtons`);
bag checks trust a full scan up to 2 h old (`Scan.notListed` with an age, also restored scans),
do not resend silent searches (`D.silentKey`) and wait at most `D.BAG_SEARCH_TIME`; empty rows take
`T.historyPrice` / other versions and show a greyed likely route; Below usual price renamed Under
market (Ukrainian «Нижче ринку») and works with under 3 days (`M.usualTarget`, weak). Installed, not
committed. Owed in the game: the button spacing, how long Check bags takes now, whether Under
market fills.

**Quick scan gear rows and the Status table** (17 November, screenshots of 13 Giant Club rows and
of Sharing → Status). One browse row of gear listed once (`D.addFound` takes the endings' keys,
`judgeGear` in Sniper); Status drawn as label / value lines (`UI.shareStatus` holds its text for
tests). In the working tree, not installed or committed. Owed in the game: the Status column width
in Ukrainian.

**Below usual price** (17 November, the player could not use Below median; chose all four
proposals). Renamed (Ukrainian «Нижче звичної ціни»); on by default with 50% of the gold (migration 3
moves a saved off / 20% once); weak-data finds offered greyed, "few sales data", capped at a day of
sales (`M.MEDIAN_WEAK_DAYS`, `d.weak`); the empty page lists the last scan's reasons
(`stats.medianReasons`, `UI.noMedianText`). In the working tree, not installed or committed. Owed in
the game: whether the greyed rows and the reasons read well.

**Full scan reads twice as fast** (17 November, screenshot "Reading auctions 28280 / 209437").
The list was never smaller than in 2.2 (209 437 is the whole house); the read pass now takes
`S.READ_MS` 12 ms a frame (was 6) and `S.READ_SOFT_MS` 6 ms while the player clicks (was 2; a
purchase still 2, `E.workSlice`). In the working tree, not installed or committed. Owed in the
game: how long the read phase takes now, and whether the frame rate stays bearable during it.

**Quick scan finds in Deals at once** (17 November, screenshot "27099 items read · 1297 to
check"). Each find that makes a deal of its cheapest unit is listed while the house is still read
(Status: from quick scan) and is checked first afterwards; the status line says found / left to
check instead of the misleading "to check" (only the best 200 are kept). In the working tree, not
installed or committed. Owed in the game: how soon the rows appear, and how long the check phase
takes (up to 200 exact searches, gear several each — that is most of the 2–5 minutes).

**Save off with nothing to save** (17 November, Settings screenshot). Enabled by the boxes'
OnTextChanged against the text loaded; the mock's SetText now runs OnTextChanged as the game does.
Installed, not committed.

**Vendor price is the Sell Price** (17 November, Buccaneer's Bracers tooltip). No API gives the
server's price; the client's Sell Price matched 113 of 115 buyback sales (the 2 others worn gear),
so it is exact now: no "confirmed after a sale" note, no `*` unless the margin is set; a different
buyback price still wins for non-gear. Installed, not committed.

**One Sure and no 0% recommendation** (17 November, Silver Ore and Imposing Shoulders tooltips).
Rivals' undercuts now take at most half the buyers (they queued about 1,000 units in front of a
290-a-day ore); the tooltip, Deals and My items ask Sure for the same units at the same price; the
Recommendation ranks the auction by net x Sure, never below 10%, and names the post price; the 80%
ranges are gone. Installed, not committed. Owed in the game: Silver Ore's Sure near the cheapest
lot, and the shoulders recommending the vendor.

**The player's 5 remarks of 17 November, second batch** (quick scan freeze and Stop, vendor minimum
per unit, both routes on All, 5-minute deal hold, tooltip Deal now in Selling, Resale why line).
In the working tree, installed into the game 17 November, not committed. Owed in the game: does the
quick scan still freeze, how long it takes next to TSM, and the Stop button.

**The player's 15 remarks of 17 November** (Quick scan, tooltip layout, scan_empty text, My items
Check Sure / AH / V, Professions, tab order, Sharing, Analytics fixes, scan speed). In the working
tree with T01–T32; installed into the game 17 November 05:50 (backup
`C:/FF/backups/pre-install-20261117-0550`), not committed. Owed in the game: Quick scan during the 15-minute
wait (button text, status line, it ends by itself), the new tooltip's width and wording, the
messages chat tab being made (`FCF_OpenNewWindow`, out of combat) without blame, and whether
Check all still freezes (the addon's part is ~2 ms an answer in the simulation).

**The remarks T01–T32 (spec of 16 November).** Implemented in the working tree, not committed or
installed: all of them, T24 as an alternative from our own data (Undermine has no documented
Forever API). T22 goes live only after pushing the addon's `sync/` and then the data repo
(local commit 8815c4c + workflow change). Backups of every T13 step: `C:/FF/backups/T13-step*`. `docs/review-2026-11-16.md` holds the table with files and tests, and what is owed
in the game. Before installing: back up the addon, `ForeverFlipData` and `ForeverFlipRaw` (the
first login rebuilds the sales statistics).

**`2.3.0-beta.1` is the current release** (15 November): crafting batch and material purchase
plans, learned-recipe filtering, clearer Best route explanations, per-unit vendor-deal profit,
and selling/crafting layout and restriction handling fixes. See the changelog and current beta
checklist. Automated checks do not replace the pending in-game checks below.

**Open: Post AH-worthy gets "That action is currently restricted" out of combat** (15 November).
The server's `AUCTION_HOUSE_SHOW_ERROR` is `HasRestriction` while `C_RestrictedActions` reports
nothing. ForeverFlip posted 60 times from Lasqa until 14 November 08:24 and the posting code has
not changed since. Next: does the game's own Sell tab post the same item? Yes → the client refuses
addon calls (taint, a restriction type not checked); no → the server restricts the character.

### Waiting (historical)

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

### Decided (historical)

- Work goes straight to `main`; the hooks test, install into `C:/World of Warcraft/_forever_` and
  push after every commit. `FF_NO_PUSH=1` and `FF_NO_INSTALL=1` skip one step for one commit.
- Releases are started by hand: `tools/devflow.py release X.Y.Z` (asks to type the version
  again) or a tag pushed by hand; never by a hook or a plain commit.
- The game's client is 1.60.1.70938, Interface 16001. `C:\WOW\World of Warcraft\_retail_` is not
  the target.
- ForeverFlip has a Sync helper (`sync/`, Python, standard library only) and a community aggregator;
  both are part of the same release cycle.
