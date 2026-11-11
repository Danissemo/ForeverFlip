# Community scans

ForeverFlip users can pool their full auction house scans through GitHub. Everyone gets the prices of
many scans, and the full scans themselves are archived for any later use.

```
Game (ForeverFlip)                ForeverFlip Sync helper            GitHub: ForeverFlip-Data
──────────────────                ───────────────────────            ────────────────────────
full scan → ForeverFlipRaw  ───▶  reads new scans after     ───▶  release "incoming"
(SavedVariables)                  /reload or logout                     │  every 10 minutes:
                                                                        ├─▶ release raw-YYYY-MM-DD
                                                                        │   (full scans, unchanged)
ForeverFlip_Shared addon    ◀───  downloads the summaries   ◀───  shared/<realm>-<faction>.txt
(read at /reload or login)        of your realms                  (12 newest scans per house)
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
2. Give the helper a GitHub token with write access to
   [ForeverFlip-Data](https://github.com/Danissemo/ForeverFlip-Data). Ask the maintainer to add you as
   a collaborator. Then do one of these:
   - log in with the GitHub CLI once (`gh auth login`); the helper uses its token;
   - set the environment variable `FF_GITHUB_TOKEN`;
   - put `{"token": "..."}` into `%APPDATA%\ForeverFlipSync\config.json`.
3. Run the helper without `--download-only`. After each `/reload` or logout it uploads the new full
   scans; each scan is uploaded once.

The helper keeps its state in `%APPDATA%\ForeverFlipSync\state.json`, including an anonymous uploader
ID. The uploaded files carry a short hash of it, not your name or account.

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

- Uploading needs write access to the data repository, so only collaborators can upload.
- The aggregator refuses files with a wrong format, scans more than 7 days old or from the future,
  implausible numbers of auctions and negative values.
- Two players' copies of the same server scan (within 2 minutes) count once in the summaries.
- The addon merges only scans of your own realm, each once, at most 7 days old.

## For developers

| File | Role |
|---|---|
| `ForeverFlip/Raw.lua` | Captures full scans into `ForeverFlipRaw`; imports `ForeverFlipShared` |
| `sync/ffscan.py` | Formats: SavedVariables reader, FFR1 full scans, FF1 summaries, `Data.lua` |
| `sync/foreverflip_sync.py` | The helper |
| `sync/aggregate.py` | The aggregator, run by the data repository's workflow |
| `tests/test_sync.py` | Tests of all of the above, including the addon reading what Python writes |
