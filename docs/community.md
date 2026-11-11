# Community scans

ForeverFlip users can pool their full auction house scans through GitHub. Everyone gets the prices of
many scans, and the full scans themselves are archived for any later use.

```
Game (ForeverFlip)               ForeverFlip Sync helper             GitHub: ForeverFlip-Data
──────────────────               ───────────────────────             ────────────────────────
full scan, sealed  ───────────▶  checks the scan, puts it   ───▶  issue "Scan upload: ..."
→ ForeverFlipRaw                 into your secret gist               │ the workflow checks it again
(SavedVariables)                                                     ├─▶ release raw-YYYY-MM-DD
                                                                     │   (full scans, unchanged)
                                                                     ├─▶ registry/scans.jsonl
                                                                     │   (who, when, confirmed?)
ForeverFlip_Shared addon  ◀────  downloads the summaries    ◀───  shared/<realm>-<faction>.txt
(read at /reload or login)       of your realms                   (confirmed scans only)
```

The game gives addons no network access, so a small program, the **ForeverFlip Sync** helper, runs
next to the game and moves the files.

## For players

### Getting community prices (no account needed)

1. Download the helper: **ForeverFlipSync.exe** from the
   [latest ForeverFlip release](https://github.com/Danissemo/ForeverFlip/releases/latest). With Python
   3.12 installed you can also run [`sync/foreverflip_sync.py`](../sync/foreverflip_sync.py).
2. Start it while you play, or once before you play:

   ```bash
   ForeverFlipSync.exe --download-only
   ```

   It finds `C:\World of Warcraft\_forever_` by itself. For another folder, add
   `--game "D:\Games\World of Warcraft\_forever_"`.
3. It writes the **ForeverFlip_Shared** addon into `Interface/AddOns`. ForeverFlip reads it at the
   next `/reload` or login. **Settings → Sharing** then shows "Community data: N scans, updated …".

The helper downloads only the auction houses you use (taken from ForeverFlip's saved data), every
15 minutes and whenever the game saves.

### Contributing your scans

1. In the game: **Settings → Sharing → Keep my full scans for the ForeverFlip Sync helper**. Every full
   scan is then kept, auction by auction; the last 2 are saved. They are several megabytes each, so
   the saved-data file grows and logging out takes a moment longer.
2. Any GitHub account can upload; nobody has to add you. The account must be at least 7 days old.
   Give the helper a token of it, in one of these ways:
   - log in with the [GitHub CLI](https://cli.github.com) once (`gh auth login`); the helper uses its
     token;
   - create a classic token with the scopes **gist** and **public_repo** and set it in the
     environment variable `FF_GITHUB_TOKEN`, or put `{"token": "..."}` into
     `%APPDATA%\ForeverFlipSync\config.json`.
3. Run the helper without `--download-only`. After each `/reload` or logout it shares the new full
   scans, each once:
   1. it checks the scan first and refuses to send one that is incomplete, more than 7 days old or
      whose seal does not match (see below);
   2. it puts the scan, unchanged and compressed, into a **secret gist** of your account and opens an
      issue **Scan upload: ...** in the data repository that points to it;
   3. the repository checks the scan again, archives it and answers in the issue within minutes;
   4. the helper prints the answer and deletes the gist.

The helper keeps its state in `%APPDATA%\ForeverFlipSync\state.json`. Uploads are public: the issue and
the archived file name show your GitHub login, the realm and the faction.

### Options

| Option | Meaning |
|---|---|
| `--once` | One upload and download, then exit |
| `--download-only` | Never upload |
| `--game <folder>` | The WoW Forever folder (with `Interface` and `WTF`) |
| `--repo <owner/name>` | Another data repository |
| `--interval <seconds>` | How often to look for a new save (default 60) |

`config.json` accepts the same settings as `game`, `repo` and `token`.

## What is shared and how it is used

- **Uploaded:** the full scan exactly as the addon read it. One line per auction gives the item,
  stack size, buyout, bids, time-left band, whether it was your own auction (when the server tells),
  the item kind and, for gear, the full name. Nothing else from your saved data is read or uploaded.
- **In the archive:** each full scan is kept unchanged in the release of its day. The format is
  described in the [data repository](https://github.com/Danissemo/ForeverFlip-Data#-full-scan-format-ffr-gz-ffr1).
- **In the addon:** the summaries are merged like scans shared in game (see
  [How it works](how-it-works.md#sharing-scans)):
  - more days of history;
  - the time-of-week pattern;
  - a fresh usual price when your own scan is older. Tooltips then show "shared by community".

  Deals still come only from your own scans and live checks.

## Safeguards

A scan comes from the player's own computer, so nothing can prove that it was not changed. Several
layers make a changed scan useless instead.

1. **Seal.** While the addon reads a full scan it computes a checksum of every auction line and of
   the realm, time and number of auctions, and saves it with the scan. The helper refuses to send a
   scan whose lines no longer match it, and the data repository refuses it again. Editing the saved
   file by hand therefore fails. The algorithm is public, so the seal stops casual edits, not a
   determined forger; the next layers do that.
2. **The upload cannot change on the way.** The issue carries the SHA-256 of the file and the gist
   must belong to the issue's author. The archive keeps the bytes that were checked, and
   `registry/scans.jsonl` records their SHA-256.
3. **Confirmation by another player.** A scan is published in the summaries only after a scan of
   another uploader of the same auction house, taken within 3 hours, shares at least half of its
   auctions. Even then only the items whose prices agree with that scan are published (usual prices
   within 25%, or the cheap lots that set the price are listed in both). An invented cheap lot is in
   nobody else's scan, so its item is left out. A scan that nobody confirms within 24 hours stays in
   the archive marked *unconfirmed* and never reaches the summaries.
4. **Uploader rules** (`registry/uploaders.json` in the data repository):
   - accounts younger than 7 days cannot upload;
   - at most 48 uploads a day per account, and not two scans of one house less than 10 minutes apart;
   - the same file once;
   - the maintainer can ban an account or mark it trusted; scans of trusted accounts are published
     without waiting for confirmation.
5. **Checks of the contents:** the format, an auction house name ending in Alliance, Horde or
   Neutral, a time at most 7 days old and not in the future, 50 to 3,000,000 auctions, plausible
   stack sizes and prices, and at most half of the auctions unreadable.
6. **In the addon:** two players' copies of the same server scan (within 2 minutes) count once, and
   only scans of your own realm are merged, each once, at most 7 days old. Deals always come from
   your own scans and live checks, never from shared data alone.

## For developers

| File | Role |
|---|---|
| `ForeverFlip/Raw.lua` | Captures and seals full scans into `ForeverFlipRaw`; imports `ForeverFlipShared` |
| `sync/ffscan.py` | Formats: SavedVariables reader, FFR1 full scans, the seal, the checks, FF1 summaries, `Data.lua` |
| `sync/foreverflip_sync.py` | The helper: checks, gist and issue uploads, downloads |
| `sync/aggregate.py` | The aggregator, run by the data repository's workflow on every upload issue and every 30 minutes |
| `tests/test_sync.py` | Tests of all of the above, including the addon reading what Python writes |
