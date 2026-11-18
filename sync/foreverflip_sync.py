"""ForeverFlip Sync: shares full auction house scans through GitHub.

The game gives addons no network access, so this small program runs next to the game:

1. Upload. When ForeverFlip's SavedVariables file changes (after /reload or logout), the full scans the
   addon kept (setting "Keep my full scans for the ForeverFlip Sync helper") are checked and shared.
   A scan is refused before sending when it is incomplete, older than 7 days or its seal (the
   checksum the addon computed while reading it) does not match because it was changed. A good scan
   goes, unchanged, into a secret gist of your GitHub account, and an issue in the community data
   repository points to it; the repository checks it again, archives it and closes the issue. The
   gist is deleted afterwards. Any GitHub account can upload, signed in through the ForeverFlip
   Sync GitHub App (permissions: the player's gists, issues of the data repository).
   Sharing needs a GitHub sign-in: the window's "Sign in with GitHub" button (or --login).
2. Download. The community summaries of your realms are downloaded and written into the
   ForeverFlip_Shared addon, which ForeverFlip reads at the next /reload or login. No account needed.
3. Addon updates. New ForeverFlip releases are installed (or only announced) from GitHub; beta
   testers also get the pre-releases. See addon_update.py.

Usage:
    python foreverflip_sync.py                 # desktop window on Windows
    python foreverflip_sync.py --once          # one sync, then exit
    python foreverflip_sync.py --download-only # never upload
    python foreverflip_sync.py --console --upload # share scans from the command line

Signing in: the window's "Sign in with GitHub" button, or --login in a console (GitHub's device flow:
enter the code shown at github.com/login/device). The token is kept encrypted for this Windows user.
It is also read from FF_GITHUB_TOKEN, the config file, or the GitHub CLI (gh auth token).
"""

from __future__ import annotations

import argparse
import base64
import concurrent.futures
import gzip
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import ffscan  # noqa: E402
from ffscan import scope_file  # noqa: E402
from game_location import locate_game, GameNotFound, AmbiguousGame  # noqa: E402
import github_login  # noqa: E402
import addon_update  # noqa: E402
import profiles  # noqa: E402
import self_update  # noqa: E402

# The release this helper ships with; `devflow.py release` writes it with the addon's version.
VERSION = "3.2.0"
DEFAULT_REPO = "Danissemo/ForeverFlip-Data"
ADDON_REPO = "Danissemo/ForeverFlip"
UPDATE_EVERY = 6 * 3600  # how often new addon releases are looked for
API = "https://api.github.com"
RAW_URL = "https://raw.githubusercontent.com/{repo}/main/shared/{file}"
LOG_SINK = None


def log(message: str) -> None:
    line = f"{time.strftime('%H:%M:%S')} {message}"
    if LOG_SINK:
        LOG_SINK(line)
    if sys.stdout is not None:
        encoding = sys.stdout.encoding or "utf-8"
        print(line.encode(encoding, "replace").decode(encoding), flush=True)


# --- Configuration -------------------------------------------------------------------------------

def config_dir() -> pathlib.Path:
    base = os.environ.get("APPDATA") or str(pathlib.Path.home() / ".config")
    path = pathlib.Path(base) / "ForeverFlipSync"
    path.mkdir(parents=True, exist_ok=True)
    return path


def load_json(path: pathlib.Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return default


def save_json(path: pathlib.Path, value) -> None:
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(value, indent=2), encoding="utf-8")
    tmp.replace(path)


def find_game(given: str | None) -> pathlib.Path:
    return locate_game(given)


def saved_variable_files(game: pathlib.Path) -> list[pathlib.Path]:
    return sorted((game / "WTF" / "Account").glob("*/SavedVariables/ForeverFlip.lua"))


def find_token(config: dict) -> str | None:
    return token_source(config)[0]


def token_source(config: dict) -> tuple[str | None, str | None]:
    """The GitHub token for uploads and where it came from: "environment", "helper" (signed in from
    the helper), "config" or "gh" (the GitHub CLI)."""
    if os.environ.get("FF_GITHUB_TOKEN"):
        return os.environ["FF_GITHUB_TOKEN"], "environment"
    token = github_login.load_token(config_dir())
    if token:
        return token, "helper"
    if config.get("token"):
        return config["token"], "config"
    for gh in ("gh", r"C:\Program Files\GitHub CLI\gh.exe"):
        try:
            out = subprocess.run([gh, "auth", "token"], capture_output=True, text=True, timeout=20,
                                 creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        except (OSError, subprocess.SubprocessError):
            continue
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip(), "gh"
    return None, None


def console_login(config: dict) -> int:
    """Signs in from a console: shows the code, waits for the approval, keeps the token."""
    try:
        device = github_login.start(github_login.client_id(config), f"ForeverFlipSync/{VERSION}")
        log(f"Open {device['verification_uri']} and enter the code {device['user_code']}.")
        token = github_login.wait_for_token(github_login.client_id(config), device,
                                            agent=f"ForeverFlipSync/{VERSION}")
        github_login.save_token(config_dir(), token)
        log(f"Signed in to GitHub as {github_login.whoami(token)}. Scans can be shared now.")
        return 0
    except (github_login.LoginError, urllib.error.URLError, OSError, ValueError) as exc:
        log(f"Not signed in: {describe(exc)}.")
        return 1


# --- GitHub ---------------------------------------------------------------------------------------

class GitHub:
    def __init__(self, repo: str, token: str | None):
        self.repo, self.token = repo, token

    def request(self, method: str, path: str, value=None):
        data = json.dumps(value).encode() if value is not None else None
        req = urllib.request.Request(API + path, data=data, method=method)
        req.add_header("Accept", "application/vnd.github+json")
        req.add_header("User-Agent", f"ForeverFlipSync/{VERSION}")
        req.add_header("X-GitHub-Api-Version", "2022-11-28")
        if self.token:
            req.add_header("Authorization", f"Bearer {self.token}")
        if data:
            req.add_header("Content-Type", "application/json")
        with urllib.request.urlopen(req, timeout=300) as resp:
            body = resp.read()
        return json.loads(body) if body else None

    def create_gist(self, description: str, files: dict[str, str]) -> dict:
        return self.request("POST", "/gists", {"description": description, "public": False,
                                               "files": {n: {"content": c} for n, c in files.items()}})

    def delete_gist(self, gist_id: str) -> None:
        self.request("DELETE", f"/gists/{gist_id}")

    def create_issue(self, title: str, body: str) -> dict:
        return self.request("POST", f"/repos/{self.repo}/issues", {"title": title, "body": body})

    def issue(self, number: int) -> dict:
        return self.request("GET", f"/repos/{self.repo}/issues/{number}")

    def last_comment(self, number: int) -> str:
        comments = self.request("GET", f"/repos/{self.repo}/issues/{number}/comments?per_page=100") or []
        return comments[-1]["body"] if comments else ""


# --- Upload ----------------------------------------------------------------------------------------

PART = 900_000  # characters per gist file, so that every part is returned whole


def package(scan: ffscan.RawScan) -> tuple[bytes, dict[str, str]]:
    """The file to share (the scan, gzip-compressed, unchanged) and its gist parts (base64)."""
    # Level 6, not 9: five times faster (0.3 s against 1.6 s for a full scan) for 4% more bytes.
    packed = gzip.compress(ffscan.encode_raw(scan).encode("utf-8"), compresslevel=6, mtime=0)
    text = base64.b64encode(packed).decode("ascii")
    parts = {f"scan.{k // PART + 1:03d}.b64": text[k:k + PART] for k in range(0, len(text), PART)}
    return packed, parts


def client_line(game: pathlib.Path | None) -> str:
    """"wowf 1.60.1.70938" / "wow 12.1.5.70961 eu": the game the scan comes from (and for Retail its
    region), so the data repository keeps markets of other clients apart. Empty when the client
    cannot be read."""
    if game is None:
        return ""
    try:
        info = profiles.client_info(game) or {}
    except (OSError, ValueError):
        return ""
    product = re.sub(r"[^A-Za-z0-9_.-]", "", str(info.get("product") or ""))
    version = re.sub(r"[^0-9.]", "", str(info.get("version") or ""))
    region = re.sub(r"[^a-z]", "", str(info.get("region") or "").lower())
    if not product:
        return ""
    return f"{product} {version or '0'} {region}".strip() if product == "wow" and region \
        else f"{product} {version}".strip()


def community_market(game: pathlib.Path | None) -> bool:
    """Whether the client takes part in the community exchange: WoW Forever, and Retail when its
    region is known (each region is a market of its own). Classic and the rest do not."""
    return ffscan.market_of(client_line(game)) is not None


def issue_body(scan: ffscan.RawScan, digest: str, gist_id: str, client: str = "") -> str:
    when = time.strftime("%Y-%m-%d %H:%M UTC", time.gmtime(scan.at))
    return (f"A full auction house scan shared by ForeverFlip Sync. It is checked, archived and this issue is "
            f"closed automatically.\n\n"
            f"Taken {when}, {len(scan.rows)} auctions.\n\n"
            f"```\nscope: {scan.scope}\ntime: {scan.at}\nauctions: {len(scan.rows)}\nseal: {scan.seal}\n"
            f"sha256: {digest}\ngist: {gist_id}\nhelper: {VERSION}\n"
            + (f"client: {client}\n" if client else "") + "```\n")


def raw_section(path: pathlib.Path) -> str:
    """The part of a saved file from the line `ForeverFlipRaw = ` on, or "" without it. Only that part
    is decoded and read: the price history before it is most of the file (35 of 42 MB)."""
    data = path.read_bytes()
    if not data.startswith(b"ForeverFlipRaw"):
        k = data.find(b"\nForeverFlipRaw")
        if k < 0:
            return ""
        data = data[k + 1:]
    # line ends as read_text gave them: Windows ones become \n
    return data.decode("utf-8", errors="replace").replace("\r\n", "\n").replace("\r", "\n")


def shareable_scans(game: pathlib.Path, state: dict, paths=None):
    """The kept full scans not shared yet that pass the checks: (scan, ident, when)."""
    done = set(state.setdefault("uploaded", []))
    for path in saved_variable_files(game) if paths is None else paths:
        try:
            scans = ffscan.scans_from_saved_variables(raw_section(path), skip=done)
        except (ffscan.LuaError, ValueError, OSError) as exc:
            log(f"Cannot read {path}: {exc}")
            continue
        for scan in scans:
            ident = f"{scan.scope}@{scan.at}"
            if ident in done:
                continue
            when = time.strftime("%d.%m %H:%M", time.localtime(scan.at))
            why = ffscan.check(scan, time.time())
            if why:
                rejected = state.setdefault("rejected", {})
                if rejected.get(ident) != why:
                    log(f"Not sharing the scan of {scan.scope} from {when}: {why}.")
                rejected[ident] = why
                while len(rejected) > 500:
                    del rejected[next(iter(rejected))]
                continue
            done.add(ident)
            yield scan, ident, when


def scan_time(ident: str) -> int:
    try:
        return int(ident.rsplit("@", 1)[1])
    except (IndexError, ValueError):
        return 0


def mark_uploaded(state: dict, ident: str) -> None:
    """Remembers a shared scan; the newest 500 are kept. They are ordered by the time of the scan:
    sorted as text, the realms late in the alphabet pushed out the newest scans of the others."""
    done = set(state.setdefault("uploaded", []))
    done.add(ident)
    state["uploaded"] = sorted(done, key=lambda i: (scan_time(i), i))[-500:]
    state.setdefault("exchange", {})["shared_at"] = int(time.time())


def upload_new_scans(game: pathlib.Path, hub: GitHub, state: dict, paths=None, checkpoint=None) -> None:
    client = client_line(game)
    for scan, ident, when in shareable_scans(game, state, paths):
        packed, parts = package(scan)
        digest = hashlib.sha256(packed).hexdigest()
        gist = hub.create_gist(f"ForeverFlip scan of {scan.scope}, {when}", parts)
        try:
            issue = hub.create_issue(f"Scan upload: {scan.scope} {scan.at}", issue_body(scan, digest, gist["id"], client))
        except (urllib.error.URLError, OSError):
            try:
                hub.delete_gist(gist["id"])
            except (urllib.error.URLError, OSError):
                pass
            raise
        state.setdefault("pending", []).append({"issue": issue["number"], "gist": gist["id"], "scan": ident})
        mark_uploaded(state, ident)
        if checkpoint:
            checkpoint()
        log(f"Shared the scan of {scan.scope} from {when}: {len(scan.rows)} auctions, "
            f"{len(packed) // 1024} KB (issue #{issue['number']}).")


def upload_outcome(answer: str) -> str:
    """The data repository's answer in one word: published, waiting (for a confirming scan of
    another player), refused or closed."""
    text = answer.lower()
    if "refused" in text:
        return "refused"
    if "published in the community prices now" in text:
        return "published"
    if "as soon as" in text or "confirm" in text:
        return "waiting"
    return "closed"


def remember_outcome(state: dict, ident: str, outcome: str, answer: str) -> None:
    results = state.setdefault("results", {})
    results.pop(ident, None)
    results[ident] = {"outcome": outcome, "at": int(time.time()), "answer": answer[:300]}
    while len(results) > 100:
        del results[next(iter(results))]


def follow_uploads(hub: GitHub, state: dict) -> None:
    """Reports what the data repository decided and deletes the gists it has read.

    One upload that cannot be followed no longer stops the others, nor the new uploads after it:
    an issue that is gone (deleted or moved: 404/410) is dropped, any other failure keeps the
    upload waiting for the next pass. Before, one such issue failed every pass (follow_uploads
    runs before upload_new_scans), and no new scan was shared again."""
    waiting = []
    for item in state.get("pending", []):
        if not item.get("issue"):
            continue  # nothing to follow without an issue
        try:
            issue = hub.issue(item["issue"])
            if issue["state"] != "closed":
                waiting.append(item)
                continue
            answer = hub.last_comment(item["issue"]) or issue.get("state_reason") or "closed"
        except urllib.error.HTTPError as exc:
            if exc.code in (404, 410):
                log(f"Scan {item['scan']}: its issue #{item['issue']} is gone; it is not followed any more.")
                remember_outcome(state, item["scan"], "closed", f"issue #{item['issue']} is gone")
                continue
            waiting.append(item)
            log(f"Scan {item['scan']}: cannot read issue #{item['issue']} now ({describe(exc)}).")
            continue
        except (urllib.error.URLError, OSError, ValueError, KeyError, TypeError) as exc:
            waiting.append(item)
            log(f"Scan {item['scan']}: cannot read issue #{item['issue']} now ({describe(exc)}).")
            continue
        log(f"Scan {item['scan']}: {answer}")
        remember_outcome(state, item["scan"], upload_outcome(answer), answer)
        try:
            hub.delete_gist(item["gist"])
        except (urllib.error.URLError, OSError) as exc:
            if not (isinstance(exc, urllib.error.HTTPError) and exc.code == 404):
                log(f"Could not delete the gist of {item['scan']} ({describe(exc)}); delete it on GitHub if it stays.")
    state["pending"] = waiting


# --- Download --------------------------------------------------------------------------------------

SCOPE_KEY = re.compile(rb'\["([^"\]]+-(?:Alliance|Horde|Neutral|Server))"\]\s*=\s*\{')
_SCOPES: dict[str, tuple] = {}  # path: ((mtime_ns, size), scopes): the file is read again only when it changes


def my_scopes(game: pathlib.Path) -> set[str]:
    """Auction houses the player uses: the markets keys in ForeverFlip's saved data (Retail's realm-wide
    houses end in -Server)."""
    scopes = set()
    for path in saved_variable_files(game):
        try:
            st = path.stat()
            mark = (st.st_mtime_ns, st.st_size)
            known = _SCOPES.get(str(path))
            if known is None or known[0] != mark:
                found = {m.decode("utf-8", errors="replace") for m in SCOPE_KEY.findall(path.read_bytes())}
                known = _SCOPES[str(path)] = (mark, found)
        except OSError:
            continue
        scopes.update(known[1])
    return scopes


def market_path(market: str, file: str) -> str:
    """The path of a file of the market under shared/: Forever's at its top, Retail's in its folder."""
    return f"{market}/{file}" if market else file


def fetch_status(repo: str, market: str = "") -> dict | None:
    """shared/status.json of the data repository (aggregate.write_status), or None when it has none
    yet or it cannot be read: then the summaries are used as before."""
    url = RAW_URL.format(repo=repo, file=market_path(market, "status.json"))
    req = urllib.request.Request(url, headers={"User-Agent": f"ForeverFlipSync/{VERSION}"})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            status = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return None
        raise
    except ValueError:
        return None
    return status if isinstance(status, dict) and isinstance(status.get("markets"), dict) else None


def download_shared(game: pathlib.Path, repo: str, uploaded: list[str] | None = None,
                    report: dict | None = None) -> int:
    """Writes the community summaries of the player's auction houses into ForeverFlip_Shared.
    `report` receives {scope: {scans, own, latest}}: own counts the player's own shared scans,
    which the addon skips (they are in its history already). With the data repository's status.json
    it also gets published_at (when the repository last published a scan of it), checked_at and,
    when the community price is not reliable yet, reason; such a market's summaries are withheld."""
    texts = []
    mine = set(uploaded or [])
    market = ffscan.market_of(client_line(game)) or ""
    status = fetch_status(repo, market)
    markets = (status or {}).get("markets", {})
    for_addon = {}
    wanted = []
    for scope in sorted(my_scopes(game)):
        house = markets.get(scope)
        if status is not None:
            extra = {"checked_at": status.get("checked_at"),
                     "published_at": (house or {}).get("published_at"),
                     "reason": (house or {}).get("reason") if house else "no scan of it is published yet"}
            for_addon[scope] = extra
            if house is None or not house.get("reliable"):
                if report is not None:
                    report[scope] = {"scans": 0, "own": 0, "latest": (house or {}).get("latest_published"),
                                     **extra}
                continue
        else:
            extra = {}
        wanted.append((scope, extra))

    def fetch(scope):
        url = RAW_URL.format(repo=repo, file=urllib.parse.quote(market_path(market, scope_file(scope))))
        req = urllib.request.Request(url, headers={"User-Agent": f"ForeverFlipSync/{VERSION}"})
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return resp.read().decode("utf-8")
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                return None
            raise

    # The houses' files come at once, not one after another: each is a separate request.
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        bodies = list(pool.map(fetch, [scope for scope, _ in wanted]))
    for (scope, extra), body in zip(wanted, bodies):
        if body is None:
            if report is not None:
                report[scope] = {"scans": 0, "own": 0, "latest": None, **extra}
            continue
        lines = [line for line in body.splitlines() if line.startswith("FF1|")]
        texts += lines
        if report is not None:
            times = []
            for line in lines:
                try:
                    times.append(int(line.split("|")[2], 36))
                except (IndexError, ValueError):
                    pass
            own = sum(1 for at in times if f"{scope}@{at}" in mine)
            report[scope] = {"scans": len(lines), "own": own, "latest": max(times) if times else None, **extra}
    folder = game / "Interface" / "AddOns" / "ForeverFlip_Shared"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "ForeverFlip_Shared.toc").write_text(ffscan.SHARED_TOC, encoding="utf-8")
    tmp = folder / "Data.lua.tmp"
    tmp.write_text(ffscan.lua_data_file(texts, time.time(), uploaded, for_addon or None, LATEST.get(str(game))),
                   encoding="utf-8")
    shutil.move(str(tmp), str(folder / "Data.lua"))
    return len(texts)


# --- Addon updates ---------------------------------------------------------------------------------

def addon_settings(config: dict) -> tuple[bool, bool]:
    """(install updates automatically, beta tester as chosen; addon_update.channel adds the
    automatic choice from the installed build)."""
    return bool(config.get("update_addon", True)), bool(config.get("beta", False))


# The newest release of the player's channel per game folder (each installation has its own build and
# so its own channel), from the last update check: download_shared writes it into that game's addon
# data, so the addon can show that an update is out (it has no internet).
LATEST: dict = {}


def check_addon(game: pathlib.Path, config: dict) -> dict:
    """{installed, release (the newer release or None), development (a checkout, never replaced),
    beta, beta_auto (the beta was chosen from the installed build, not by the player)}."""
    installed = addon_update.installed_version(game)
    beta, auto = addon_update.channel(config, installed)
    releases = addon_update.fetch_releases(config.get("addon_repo") or ADDON_REPO, f"ForeverFlipSync/{VERSION}")
    found = addon_update.candidates(releases, beta)
    LATEST[str(game)] = {key: found[0][key] for key in ("version", "beta", "page")} if found else None
    return {"installed": installed, "release": addon_update.newer(installed, releases, beta),
            "development": addon_update.is_development_copy(game), "beta": beta, "beta_auto": auto}


def apply_beta_choice(config: dict, status: dict) -> bool:
    """Keeps an automatic beta choice in the config, not marked as the player's; True if changed."""
    if status.get("beta_auto") and not config.get("beta"):
        config["beta"] = True
        config["beta_by_user"] = False
        return True
    return False


def update_addon(game: pathlib.Path, release: dict, backups: pathlib.Path | None = None) -> dict:
    """Installs `release`; returns what addon_update.install returns."""
    if addon_update.is_development_copy(game):
        raise addon_update.UpdateError("the installed addon is a development copy; it is not replaced")
    backups = backups or config_dir() / "addon-backups"
    result = addon_update.install(game, release, backups, f"ForeverFlipSync/{VERSION}")
    when = "restart the game (files were added or removed)" if result["restart"] else "use /reload in game"
    log(f"ForeverFlip updated from {result['previous'] or 'nothing'} to {result['version']}"
        f"{' (beta)' if release.get('beta') else ''}: {when}. The previous version is kept in {backups}.")
    return result


def check_helper(config: dict, fetch=None, exe=None) -> dict:
    """{current, release, frozen}: a newer ForeverFlip Sync for the chosen channel (self_update)."""
    fetch = fetch or addon_update.fetch_releases
    releases = fetch(config.get("addon_repo") or ADDON_REPO, f"ForeverFlipSync/{VERSION}")
    exe = self_update.running_executable() if exe is None else exe
    return self_update.check(releases, bool(config.get("beta")), VERSION, exe or None)


def addon_pass(game: pathlib.Path, config: dict, install: bool | None = None) -> dict | None:
    """Looks for a newer release and installs it when updates are automatic (or `install`)."""
    automatic, _ = addon_settings(config)
    status = check_addon(game, config)
    release = status["release"]
    if release is None:
        return status
    if status["development"]:
        log(f"ForeverFlip {release['version']} is out; this installation is a development copy and is left alone.")
        return status
    if automatic if install is None else install:
        profile = profiles.find_install(config, game)
        status["result"] = (update_addon(game, release, profiles.backups_folder(config_dir(), profile))
                            if profile else update_addon(game, release))
        status["installed"], status["release"] = release["version"], None
    else:
        log(f"ForeverFlip {release['version']}{' (beta)' if release['beta'] else ''} is available: {release['page']}")
    return status


# --- Main loop -------------------------------------------------------------------------------------

class SyncError(RuntimeError):
    pass


def describe(exc: BaseException) -> str:
    """A failure in words a player can act on. The missing file is named: a bare "[Errno 2] No such
    file or directory" from a build without its TLS resource said nothing about what was missing."""
    if isinstance(exc, urllib.error.HTTPError):
        return f"GitHub answered {exc.code} {exc.reason}"
    if isinstance(exc, urllib.error.URLError):
        reason = exc.reason
        return f"no connection to GitHub ({describe(reason) if isinstance(reason, BaseException) else reason})"
    if isinstance(exc, OSError) and exc.filename:
        return f"{exc.strerror or exc}: {exc.filename}"
    return str(exc) or type(exc).__name__


def run_once(game: pathlib.Path, repo: str, state: dict, token: str | None, upload: bool,
             paths=None, download=True, checkpoint=None, config=None) -> int | None:
    if not community_market(game):
        if not state.get("other_game"):
            log("Community prices are not shared for this client (only WoW Forever and Retail with a "
                "known region are); it keeps its scans to itself.")
            state["other_game"] = True
        return None
    errors = []
    if upload:
        if token:
            hub = GitHub(repo, token)
            try:
                follow_uploads(hub, state)
                upload_new_scans(game, hub, state, paths=paths, checkpoint=checkpoint)
            except (urllib.error.URLError, OSError, ValueError) as exc:
                errors.append(f"Sharing: {describe(exc)}")
        elif not state.get("warned"):
            log("Sharing needs a GitHub sign-in: press Sign in with GitHub (or run with --login). "
                "Community downloads still work.")
            state["warned"] = True
    count = None
    exchange = state.setdefault("exchange", {})
    if download:
        report = {}
        if config is not None and str(game) not in LATEST:
            # The update check runs beside the first download (the window starts both): without its
            # answer this Data.lua would lose the release the addon is to name.
            try:
                check_addon(game, config)
            except (addon_update.UpdateError, urllib.error.URLError, OSError, ValueError):
                pass
        try:
            count = download_shared(game, repo, state.get("uploaded", []), report=report)
            log(f"Community data: {count} scans ready. In game, use /reload to read updated prices.")
            exchange["downloaded_at"] = int(time.time())
            exchange["scopes"] = report
        except (urllib.error.URLError, OSError, ValueError) as exc:
            errors.append(f"Community download: {describe(exc)}")
    if errors:
        exchange["error"], exchange["error_at"] = "; ".join(errors), int(time.time())
        raise SyncError("; ".join(errors))
    if download or (upload and token):  # something was exchanged
        exchange["ok_at"] = int(time.time())
        exchange.pop("error", None)
    return count


def _when(at) -> str:
    return time.strftime("%d.%m %H:%M", time.localtime(at))


def community_status(state: dict) -> list[str]:
    """The real state of the community exchange, in lines for the window, keeping three things
    apart: what this helper uploaded (and when), what the data repository published (and when), and
    what was downloaded into the game (and when). Per auction house: its newest community scan or
    "No community price yet" with the reason; shared scans still waiting for another player's
    confirming scan."""
    exchange = state.get("exchange") or {}
    lines = []
    ok_at, error_at = exchange.get("ok_at"), exchange.get("error_at") or 0
    lines.append(f"Last exchange {_when(ok_at)}" if ok_at else "No successful exchange yet")
    if exchange.get("error") and error_at >= (ok_at or 0):
        lines.append(f"Last error {_when(error_at)}: {exchange['error']}")
    if exchange.get("shared_at"):
        lines.append(f"Uploaded: your last scan was sent {_when(exchange['shared_at'])}")
    if exchange.get("downloaded_at"):
        lines.append(f"Downloaded: community data written for the game {_when(exchange['downloaded_at'])} "
                     f"(/reload in game to read it)")
    newest_shared = {}
    for ident in state.get("uploaded") or []:
        scope, at = ident.rsplit("@", 1)[0], scan_time(ident)
        newest_shared[scope] = max(newest_shared.get(scope, 0), at)
    for scope, info in sorted((exchange.get("scopes") or {}).items()):
        scans, own = info.get("scans") or 0, info.get("own") or 0
        published = f", published {_when(info['published_at'])}" if info.get("published_at") else ""
        if info.get("reason"):
            lines.append(f"{scope}: No community price yet ({info['reason']}){published}")
        elif not scans:
            lines.append(f"{scope}: No community price yet (no scan of it is published)")
        elif scans <= own:
            lines.append(f"{scope}: No community price yet (only your own scans are published; "
                         f"the addon has them already)")
        elif info.get("latest"):
            lines.append(f"{scope}: {scans} community scans, newest {_when(info['latest'])}{published}")
        else:
            lines.append(f"{scope}: {scans} community scans{published}")
        mine = newest_shared.get(scope)
        if mine and mine > (info.get("latest") or 0) and not info.get("reason"):
            lines.append(f"{scope}: your scan of {_when(mine)} is uploaded, not published yet")
    results = (state.get("results") or {}).values()
    waiting = sum(1 for r in results if r.get("outcome") == "waiting")
    if waiting:
        lines.append(f"{waiting} shared scan(s) wait for another player's scan of the same auction house "
                     f"to confirm them")
    refused = sum(1 for r in results if r.get("outcome") == "refused")
    if refused:
        lines.append(f"{refused} shared scan(s) were refused (see the activity)")
    if state.get("pending"):
        lines.append(f"{len(state['pending'])} shared scan(s) are being checked by the data repository")
    return lines


class SyncSession:
    def __init__(self, game, repo, state, state_path, token, upload, config=None):
        self.game, self.repo, self.state = game, repo, state
        self.state_path, self.token, self.upload = state_path, token, upload
        self.config = config or {}
        self.last_seen = {}
        self.next_download = self.next_follow = self.retry_at = 0.0

    def refresh_credentials(self, config, force=False):
        if self.upload and (force or not self.token):
            token = find_token(config)
            if token and token != self.token:
                self.last_seen = {}
                self.retry_at = 0
                self.state.pop('warned', None)
            self.token = token

    def fingerprint(self):
        result = {}
        for path in saved_variable_files(self.game):
            try:
                stat = path.stat()
                result[str(path)] = (stat.st_mtime_ns, stat.st_size)
            except FileNotFoundError:
                continue  # the game may replace the file while we inspect it
        return result

    def due(self, now=None):
        now = time.monotonic() if now is None else now
        return now >= self.retry_at and (self.fingerprint() != self.last_seen or now >= self.next_download
                                        or bool(self.state.get("pending")) and now >= self.next_follow)

    def sync(self, force=False):
        before = self.fingerprint()
        changed = [pathlib.Path(path) for path, stamp in before.items() if self.last_seen.get(path) != stamp]
        now = time.monotonic()
        download = force or bool(changed) or now >= self.next_download
        try:
            count = run_once(self.game, self.repo, self.state, self.token, self.upload,
                             paths=None if force else changed, download=download,
                             checkpoint=lambda: save_json(self.state_path, self.state), config=self.config)
        except (urllib.error.URLError, OSError, ValueError, SyncError):
            self.retry_at = time.monotonic() + 30
            raise
        else:
            self.last_seen = before  # a save made during the transfer must trigger another pass
            self.retry_at = 0
            self.next_follow = time.monotonic() + 60
            if download:
                # Just after an upload the data repository has not published it yet: look again soon
                # instead of a quarter of an hour later.
                soon = bool(self.state.get("pending"))
                self.next_download = time.monotonic() + (3 if soon else 15) * 60
            return count
        finally:
            save_json(self.state_path, self.state)


def arguments(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--game", help="Forever client, its parent installation folder, or Wow.exe")
    parser.add_argument("--repo", default=None, help=f"community data repository (default {DEFAULT_REPO})")
    parser.add_argument("--once", action="store_true", help="one console sync, then exit")
    sharing = parser.add_mutually_exclusive_group()
    sharing.add_argument("--download-only", action="store_true", help="never upload scans")
    sharing.add_argument("--upload", action="store_true", help="enable sharing for this run")
    parser.add_argument("--interval", type=int, default=60, help="console check interval (default 60 seconds)")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--gui", action="store_true", help="open the desktop window")
    mode.add_argument("--console", action="store_true", help="use console mode")
    parser.add_argument("--paused", action="store_true", help="open the window with automatic sync paused")
    parser.add_argument("--tray", action="store_true",
                        help="start hidden in the tray (how Windows starts it at sign-in)")
    parser.add_argument("--update-addon", action="store_true", help="install a newer ForeverFlip release, then exit")
    parser.add_argument("--beta", action="store_true", help="be a beta tester: include pre-releases (remembered)")
    parser.add_argument("--no-beta", action="store_true", help="stop getting pre-releases (remembered)")
    account = parser.add_mutually_exclusive_group()
    account.add_argument("--login", action="store_true", help="sign in to GitHub (device code), then exit")
    account.add_argument("--logout", action="store_true", help="forget the GitHub sign-in, then exit")
    parser.add_argument("--self-test", action="store_true", help="check the packaged TLS and GUI runtime without syncing")
    parser.add_argument("--self-test-network", action="store_true", help="also test a public community-index download")
    parser.add_argument("--self-test-report", type=pathlib.Path, help="write the self-test result as JSON")
    return parser.parse_args(argv)


def runtime_check(check_gui=True, check_network=False):
    import ssl
    context = ssl.create_default_context()
    if context.verify_mode != ssl.CERT_REQUIRED or not context.check_hostname:
        raise RuntimeError('HTTPS certificate and hostname verification must remain enabled')
    if check_gui:
        import tkinter
        import sync_gui
        root = tkinter.Tk()
        root.withdraw()
        try:
            if sync_gui.Images(root, sync_gui.Scale(root)).get('app-icon') is None:
                raise RuntimeError(f'The window images are missing from {sync_gui.ASSETS}')
            root.update_idletasks()
        finally:
            root.destroy()
    if check_network:
        url = f'https://raw.githubusercontent.com/{DEFAULT_REPO}/main/shared/index.json'
        with urllib.request.urlopen(url, timeout=20) as response:
            response.read()
    import tray
    return {'ok': True, 'tls_verified': True, 'gui_checked': check_gui, 'network_checked': check_network,
            'tray': tray.available()}


def main(argv=None) -> int:
    args = arguments(argv)
    if args.self_test:
        try:
            result = runtime_check(check_network=args.self_test_network)
        except Exception as error:
            result = {'ok': False, 'error': f'{type(error).__name__}: {error}'}
        if args.self_test_report:
            args.self_test_report.write_text(json.dumps(result, indent=2), encoding='utf-8')
        else:
            log(json.dumps(result))
        return 0 if result['ok'] else 1
    folder = config_dir()
    config = load_json(folder / "config.json", {})
    if not isinstance(config, dict):
        config = {}
    if args.beta or args.no_beta:
        config["beta"] = bool(args.beta)
        config["beta_by_user"] = True
        save_json(folder / "config.json", config)
    if profiles.migrate(config):
        save_json(folder / "config.json", config)
    if args.login:
        return console_login(config)
    if args.update_addon:
        try:
            game = find_game(args.game or os.environ.get("FF_GAME") or config.get("game"))
            status = addon_pass(game, config, install=True)
            if apply_beta_choice(config, status):
                save_json(folder / "config.json", config)
        except (GameNotFound, AmbiguousGame, addon_update.UpdateError, urllib.error.URLError, OSError, ValueError) as exc:
            log(f"Addon update: {describe(exc)}.")
            return 1
        if not status.get("result") and status.get("release") is None:
            log(f"ForeverFlip {status['installed'] or '(not installed)'} is the newest"
                f"{' (beta releases included)' if status['beta'] else ''}.")
        return 0
    if args.logout:
        github_login.forget(folder)
        log("Signed out: the helper's GitHub sign-in was removed. To revoke it on GitHub too, see "
            "Settings > Applications > Authorized GitHub Apps.")
        return 0
    if not args.once and not args.console and (args.gui or os.name == "nt"):
        import sync_gui
        return sync_gui.launch(args, config, folder, sys.modules[__name__])
    try:
        game = find_game(args.game or os.environ.get("FF_GAME") or config.get("game"))
    except (GameNotFound, AmbiguousGame) as exc:
        log(str(exc))
        log('Use --game "<your Forever folder>" or start the desktop window to choose it.')
        return 1
    install = profiles.add_install(config, game)
    save_json(folder / "config.json", config)
    repo = args.repo or config.get("repo") or DEFAULT_REPO
    state_path = profiles.state_path(folder, install)
    state = load_json(state_path, {})
    if not isinstance(state, dict):
        state = {}
    upload = not args.download_only and (args.upload or bool(config.get('upload', False)))
    token = find_token(config) if upload else None
    session = SyncSession(game, repo, state, state_path, token, upload, config)
    log(f"ForeverFlip Sync {VERSION}: {game}; {'sharing and downloads' if token else 'downloads only'}.")
    next_update = 0.0
    while True:
        failed = False
        if not args.once and time.monotonic() >= next_update:
            next_update = time.monotonic() + UPDATE_EVERY
            try:
                addon_pass(game, config)
            except (addon_update.UpdateError, urllib.error.URLError, OSError, ValueError) as exc:
                log(f"Addon update: {describe(exc)}.")
        try:
            if args.once or session.due():
                session.sync(force=args.once)
        except (urllib.error.URLError, OSError, ValueError, SyncError) as exc:
            log(f"{exc}. Retrying in 30 seconds; unsent scans are kept.")
            failed = True
        if args.once:
            return 1 if failed else 0
        time.sleep(max(5, min(args.interval, 30) if failed else args.interval))


if __name__ == "__main__":
    # The packaged GUI has no console. Explicit command-line runs may attach to their terminal.
    if os.name == 'nt' and sys.stdout is None and any(a in sys.argv for a in ('--console', '--once', '--help', '--login', '--logout', '--update-addon')):
        import ctypes
        attached = ctypes.windll.kernel32.AttachConsole(-1)
        if not attached and any(a in sys.argv for a in ('--console', '--login', '--update-addon')):
            attached = ctypes.windll.kernel32.AllocConsole()
        if attached:
            sys.stdout = open('CONOUT$', 'w', encoding='utf-8', buffering=1)
            sys.stderr = open('CONOUT$', 'w', encoding='utf-8', buffering=1)
    raise SystemExit(main())
