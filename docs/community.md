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

Inside the game, without the helper, ForeverFlip also shares scans with every ForeverFlip user of
your realm over a hidden chat channel (Settings → Sharing, on by default); see
[Sharing scans](user-guide.md#sharing-scans). That covers the players online with you; the GitHub
data adds everyone's history and keeps the full scans.

## For players

### Open the desktop helper

1. Start **ForeverFlipSync.exe**. The Windows build opens a small window, without a console.
2. Check **Game installation**. The helper remembers your selection. It looks at running clients,
   Windows installation records and common folders on local drives; it does not recursively scan
   every drive. If several clients are found, choose the one you play.
3. If necessary, open the game list and press **Add a game folder…**. Select the `_forever_` or
   `_retail_` folder, or the installation folder above them (it means `_forever_`). Classic, PTR
   and beta folders are not accepted. The command-line `--game` option also accepts `Wow.exe` or a
   folder inside the addon directory. Community prices are exchanged for WoW Forever and for
   WoW Retail, each a market of its own; see [Retail markets](#retail-markets).
4. Leave **Sync automatically** on, or press **Sync now** when you want one pass. Community prices
   can be downloaded without a GitHub account. Sharing your scans is off until you enable it.
5. In game, use `/reload` to save new scans and read updated community prices. After the helper
   first creates the **ForeverFlip_Shared** addon, restart the game so it discovers the new addon.

The status line shows progress or a retry message; the log gives the result. Automatic mode checks
for changed saves every five seconds, refreshes community prices every fifteen minutes and checks
pending uploads about once a minute. A failed attempt keeps unsent scans and retries after thirty
seconds. File changes made during a transfer are processed on the next pass. The window stays
responsive while parsing and network work run in the background; the ring at the top right turns
while the helper works. Reading the game's saved file takes under a second even when it holds
eight full scans: only the part from `ForeverFlipRaw` on is decoded and read, and scans already
shared are not parsed again.

**Keep running in the tray** (under Prices, on by default): closing the window then
hides it into the notification area, and the helper goes on syncing prices and sharing new scans.
Click the tray icon to open the window again; right-click it for **Sync now** and **Quit**.

**Start with Windows in the tray** (under Prices, off by default) adds the helper to your own
startup list (the `ForeverFlipSync` value in `HKCU\...\CurrentVersion\Run`, no admin rights).
At sign-in it starts with `--tray`: only the tray icon shows, and syncing goes on as usual. The
switch shows that entry, so turning it off in Task Manager's Startup tab turns it off here too.
It needs the tray: turning it on turns on **Keep running in the tray**, and turning the tray
off turns it off. A packaged helper that was moved or updated points the entry at itself.

### Updating the helper

The helper is built from the same tag as the addon and carries the same version: a release writes
it into `sync/foreverflip_sync.py`, and the build stops when it differs from the TOC. Up to 3.1.0
it kept `2.1.0-beta.2`, whatever release it came with.


For the current stable **3.1.0** release, download **ForeverFlipSync.exe** from the [v3.1.0 release](https://github.com/Danissemo/ForeverFlip/releases/tag/v3.1.0), alongside the addon ZIP.
Close the old helper window before replacing or launching the new file. The helper's addon updater
updates the game addon only; it does not replace its own executable. Your game choice, sign-in and
sharing preferences remain in `%APPDATA%\ForeverFlipSync`.

The helper can update the addon and publish the available release version through the shared-data
addon; the game itself cannot query GitHub. **Show activity** shows upload submissions and the
server's acceptance or rejection; **Community prices updated** describes the independent download,
not proof of an upload. See the [3.1.0 release checks](release-3.1.0-validation.md).

### Addon updates and beta testing

The helper also keeps the ForeverFlip addon up to date from the
[releases](https://github.com/Danissemo/ForeverFlip/releases). The **Updater** section of the window
shows the installed addon and helper versions and whether a newer one is out.

- **Install automatically** (on by default): a newer release is installed as soon as it is found, at
  start and every 6 hours. Off, the helper only announces it, and **Install update** installs it.
  With nothing to install the same button reads **Check now** and looks again at once.
- **Beta versions** (off by default): pre-releases (versions with a `-beta.N` suffix) are offered too. Betas bring new
  features first and may have rough edges; see [the manual testing guide](testing.md) for what to
  check and how to report. Ticking it looks for a beta at once. Unticking it never downgrades: you
  keep the beta until a release newer than it comes out.

Before installing, the helper checks the download against the SHA-256 GitHub publishes for it,
that the archive holds only the `ForeverFlip` folder, and that its TOC has the release's version.
The installed folder is replaced in one step and kept as a zip in
`%APPDATA%\ForeverFlipSync\addon-backups` (the last two versions); if the swap fails, the old
folder is put back. Your saved data (`WTF/.../SavedVariables`) is never touched. After an update,
type `/reload` in game, or restart the game when the helper says that files were added or removed.
A folder that is a developer's checkout (a link or a `.git` folder inside) is never replaced.

### Contributing your scans

1. In game: **Settings → Sharing → Keep my full scans for the ForeverFlip Sync helper**. Up to
   eight full scans are retained until the helper acknowledges them. They can occupy several
   megabytes each and are written when the game saves, including `/reload` and logout.
2. In the helper, press **Sign in with GitHub**. It shows a short code, copies it and opens
   github.com/login/device: enter the code there and approve the **ForeverFlip Sync** app. Sharing
   needs a GitHub account at least seven days old. The app may only create gists of your account
   (the upload) and issues in the community data repository (the note that points to it); it
   cannot touch your other repositories. The helper keeps the sign-in encrypted for your Windows
   user (DPAPI) in `%APPDATA%\ForeverFlipSync`; **Sign out** removes it. To revoke the access on
   GitHub too, see **Settings → Applications → Authorized GitHub Apps**. In a console, `--login` and `--logout` do
   the same.
3. **Share my full scans** turns on with the sign-in (it is not available before). Each new scan is
   checked, uploaded to a secret gist of your account, and announced by a **Scan upload: ...**
   issue in the data repository. The repository checks it again and archives it within minutes;
   the helper shows its answer and deletes the gist.
4. In game, after `/reload`: **Settings → Sharing** shows **Shared by the helper: N of your scans**
   with the age of the newest one, and how many full scans still wait for the helper. Shared scans
   are dropped from the saved file at login.

A sign-in of the [GitHub CLI](https://cli.github.com) (`gh auth login`), `FF_GITHUB_TOKEN` or a
`token` in `config.json` also works; the window shows which one is used and never displays it.

A failed upload is not acknowledged as sent. Completed uploads are saved immediately, even if a
later download fails, and invalid scans are tracked separately from successful uploads. A sharing
failure does not prevent an independent attempt to download community prices.

The helper keeps configuration and state in `%APPDATA%\ForeverFlipSync`. Uploads are public: the
issue and archived file identify the GitHub account, realm and faction. The sharing checkbox is
remembered and applies to command-line runs too, unless an explicit command-line override is used.

### Command-line options

| Option | Meaning |
|---|---|
| `--gui` | Open the desktop window explicitly |
| `--console` | Use the console instead of the window |
| `--once` | Run one sync and exit; a failure returns a nonzero exit code |
| `--download-only` | Never upload, regardless of the saved sharing setting |
| `--upload` | Enable sharing explicitly for this run |
| `--paused` | Open the window with automatic sync paused |
| `--update-addon` | Install a newer ForeverFlip release (if any), then exit |
| `--beta` / `--no-beta` | Become a beta tester or stop (remembered; with `--update-addon` it applies at once) |
| `--login` | Sign in to GitHub with a device code, then exit |
| `--logout` | Remove the helper's GitHub sign-in, then exit |
| `--game <path>` | Forever or Retail client folder, parent installation folder, executable or addon subfolder |
| `--repo <owner/name>` | Another community data repository |
| `--interval <seconds>` | Console check interval, default 60 seconds |

For example, `ForeverFlipSync.exe --console --upload --once` sends eligible scans and downloads
prices once; `--console --download-only` only receives prices. An invalid explicit game path is
reported instead of silently selecting a different installation.

`config.json` accepts `game`, `repo`, `upload`, `automatic` and the legacy `token` setting. Use
GitHub CLI sign-in or an environment credential rather than putting a new secret into this file.

### Build and diagnose the helper

On Windows, install PyInstaller and run `python tools/build_sync_helper.py`. The build bundles any
SSL runtime resource required by the active Python distribution, then runs the frozen executable's
TLS-verification and GUI smoke check. HTTPS certificate and hostname checks remain enabled.
The release workflow uses the same builder.

For a local diagnostic without syncing, run `ForeverFlipSync.exe --self-test --self-test-report
runtime.json`. Add `--self-test-network` to test the public community index as well. This does not
load credentials, share scans or change the game's saved data.

### Retail markets

Retail scans are shared and downloaded like Forever's, but never mixed with them. On Retail one
auction house serves the whole realm, so a scan's house is `<realm>-Server`, and realm names
repeat across regions (Silvermoon is in Europe and in America). The helper therefore reads the
client's region from the `Branch` column of `.build.info` and sends it in the issue's client
line (`client: wow 12.1.5.70961 eu`). The data repository files each region apart:

- summaries and `status.json` in `shared/retail-eu/`, `shared/retail-us/`, ...;
- registry entries with `"market": "retail-eu"`;
- archived scans named `retail-eu_<realm>_Server_...`.

A Retail helper downloads only its region's folder. A Retail scan without a region (an older
helper), a Retail scan of a faction house, a Forever scan of a `-Server` house and scans of
Classic or other clients are refused.

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

The data workflow processes scans with `aggregate.py --defer-completion`, commits and pushes
the registry and summaries, then runs `--complete-only`. Accepted upload issues stay open if
processing or publishing fails, so the next run can retry them. Completion retries only
acknowledge already registered scans; they do not upload or process scans again.

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
4. **Agreement with the community's history.** Before a confirmed scan is published, its usual
   prices are compared with the published summaries of the last 3 days. An item more than twice or
   less than half the community's price is left out, and a scan with more than a quarter of its
   compared items out of line is not published at all (*disputed*). Prices cannot be pushed far by
   a few scans, however well they agree with each other.
5. **Uploader rules** (`registry/uploaders.json` in the data repository):
   - accounts younger than 7 days cannot upload;
   - at most 48 uploads a day per account, and not two scans of one house less than 10 minutes apart;
   - the same file once;
   - the maintainer can ban an account or mark it trusted; scans of trusted accounts are published
     without waiting for confirmation (and the history check).
6. **Checks of the contents:** the format, an auction house name ending in Alliance, Horde or
   Neutral, a time at most 7 days old and not in the future, 50 to 3,000,000 auctions, plausible
   stack sizes and prices, and at most half of the auctions unreadable.
7. **In the addon:** two players' copies of the same server scan (within 2 minutes) count once, and
   only scans of your own realm are merged, each once, at most 7 days old. Deals always come from
   your own scans and live checks, never from shared data alone.

## For developers

| File | Role |
|---|---|
| `ForeverFlip/Core/Raw.lua` | Captures and seals full scans into `ForeverFlipRaw`; imports `ForeverFlipShared` |
| `sync/ffscan.py` | Formats: SavedVariables reader, FFR1 full scans, the seal, the checks, FF1 summaries, `Data.lua` |
| `sync/foreverflip_sync.py` | Transfer engine, retry state and command-line entrypoint |
| `sync/game_location.py` | Forever-specific validation and bounded installation discovery |
| `sync/sync_gui.py` | Desktop window and background worker |
| `sync/assets/` | The window's images (ForeverFlip Sync asset kit, 1x to 4x), app icon and design tokens |
| `tools/build_sync_helper.py` | Windows executable packaging and frozen-runtime verification |
| `sync/aggregate.py` | The aggregator, run by the data repository's workflow on every upload issue and every 30 minutes |
| `sync/addon_update.py` | Addon updates from the GitHub releases: version order, beta channel, checks, install with backup |
| `sync/github_login.py` | Signing in to GitHub from the helper (device flow) and keeping the token encrypted |
| `tests/test_sync.py` | Tests of all of the above, including the addon reading what Python writes |
