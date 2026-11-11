"""ForeverFlip Sync: shares full auction house scans through GitHub.

The game gives addons no network access, so this small program runs next to the game:

1. Upload. When ForeverFlip's SavedVariables file changes (after /reload or logout), the full scans the
   addon kept (setting "Keep my full scans for the ForeverFlip Sync helper") are checked and shared.
   A scan is refused before sending when it is incomplete, older than 7 days or its seal (the
   checksum the addon computed while reading it) does not match because it was changed. A good scan
   goes, unchanged, into a secret gist of your GitHub account, and an issue in the community data
   repository points to it; the repository checks it again, archives it and closes the issue. The
   gist is deleted afterwards. Any GitHub account can upload (scopes "gist" and "public_repo").
2. Download. The community summaries of your realms are downloaded and written into the
   ForeverFlip_Shared addon, which ForeverFlip reads at the next /reload or login. No account needed.

Usage:
    python foreverflip_sync.py                 # run until closed, checking every minute
    python foreverflip_sync.py --once          # one upload and download, then exit
    python foreverflip_sync.py --download-only # never upload

The token is read from FF_GITHUB_TOKEN, from the config file, or from the GitHub CLI (gh auth token).
"""

from __future__ import annotations

import argparse
import base64
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

VERSION = "1.2.0"
DEFAULT_REPO = "Danissemo/ForeverFlip-Data"
API = "https://api.github.com"
RAW_URL = "https://raw.githubusercontent.com/{repo}/main/shared/{file}"
GAME_PATHS = [
    r"C:\World of Warcraft\_forever_",
    r"C:\Program Files (x86)\World of Warcraft\_forever_",
    r"C:\Program Files\World of Warcraft\_forever_",
    r"D:\World of Warcraft\_forever_",
]


def log(message: str) -> None:
    line = f"{time.strftime('%H:%M:%S')} {message}"
    encoding = sys.stdout.encoding or "utf-8"  # a Windows console cannot show every character
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
    for candidate in ([given] if given else []) + GAME_PATHS:
        if candidate and (pathlib.Path(candidate) / "Interface" / "AddOns").is_dir():
            return pathlib.Path(candidate)
    raise SystemExit("WoW Forever was not found. Pass its folder with --game, for example "
                     r'--game "C:\World of Warcraft\_forever_"')


def saved_variable_files(game: pathlib.Path) -> list[pathlib.Path]:
    return sorted((game / "WTF" / "Account").glob("*/SavedVariables/ForeverFlip.lua"))


def find_token(config: dict) -> str | None:
    token = os.environ.get("FF_GITHUB_TOKEN") or config.get("token")
    if token:
        return token
    for gh in ("gh", r"C:\Program Files\GitHub CLI\gh.exe"):
        try:
            out = subprocess.run([gh, "auth", "token"], capture_output=True, text=True, timeout=20)
        except (OSError, subprocess.SubprocessError):
            continue
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip()
    return None


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
    packed = gzip.compress(ffscan.encode_raw(scan).encode("utf-8"), mtime=0)
    text = base64.b64encode(packed).decode("ascii")
    parts = {f"scan.{k // PART + 1:03d}.b64": text[k:k + PART] for k in range(0, len(text), PART)}
    return packed, parts


def issue_body(scan: ffscan.RawScan, digest: str, gist_id: str) -> str:
    when = time.strftime("%Y-%m-%d %H:%M UTC", time.gmtime(scan.at))
    return (f"A full auction house scan shared by ForeverFlip Sync. It is checked, archived and this issue is "
            f"closed automatically.\n\n"
            f"Taken {when}, {len(scan.rows)} auctions.\n\n"
            f"```\nscope: {scan.scope}\ntime: {scan.at}\nauctions: {len(scan.rows)}\nseal: {scan.seal}\n"
            f"sha256: {digest}\ngist: {gist_id}\nhelper: {VERSION}\n```\n")


def upload_new_scans(game: pathlib.Path, hub: GitHub, state: dict) -> None:
    done = set(state.setdefault("uploaded", []))
    for path in saved_variable_files(game):
        try:
            scans = ffscan.scans_from_saved_variables(path.read_text(encoding="utf-8", errors="replace"))
        except ffscan.LuaError as exc:
            log(f"Cannot read {path}: {exc}")
            continue
        for scan in scans:
            ident = f"{scan.scope}@{scan.at}"
            if ident in done:
                continue
            done.add(ident)
            state["uploaded"] = sorted(done)[-500:]
            when = time.strftime("%d.%m %H:%M", time.localtime(scan.at))
            why = ffscan.check(scan, time.time())
            if why:
                log(f"Not sharing the scan of {scan.scope} from {when}: {why}.")
                continue
            packed, parts = package(scan)
            digest = hashlib.sha256(packed).hexdigest()
            gist = hub.create_gist(f"ForeverFlip scan of {scan.scope}, {when}", parts)
            try:
                issue = hub.create_issue(f"Scan upload: {scan.scope} {scan.at}", issue_body(scan, digest, gist["id"]))
            except urllib.error.HTTPError:
                hub.delete_gist(gist["id"])
                raise
            state.setdefault("pending", []).append({"issue": issue["number"], "gist": gist["id"], "scan": ident})
            log(f"Shared the scan of {scan.scope} from {when}: {len(scan.rows)} auctions, "
                f"{len(packed) // 1024} KB (issue #{issue['number']}).")


def follow_uploads(hub: GitHub, state: dict) -> None:
    """Reports what the data repository decided and deletes the gists it has read."""
    waiting = []
    for item in state.get("pending", []):
        issue = hub.issue(item["issue"])
        if issue["state"] != "closed":
            waiting.append(item)
            continue
        answer = hub.last_comment(item["issue"]) or issue.get("state_reason") or "closed"
        log(f"Scan {item['scan']}: {answer}")
        try:
            hub.delete_gist(item["gist"])
        except urllib.error.HTTPError as exc:
            if exc.code != 404:
                raise
    state["pending"] = waiting


# --- Download --------------------------------------------------------------------------------------

def my_scopes(game: pathlib.Path) -> set[str]:
    """Auction houses the player uses: the markets keys in ForeverFlip's saved data."""
    scopes = set()
    for path in saved_variable_files(game):
        text = path.read_text(encoding="utf-8", errors="replace")
        scopes.update(re.findall(r'\["([^"\]]+-(?:Alliance|Horde|Neutral))"\]\s*=\s*\{', text))
    return scopes


def download_shared(game: pathlib.Path, repo: str) -> int:
    texts = []
    for scope in sorted(my_scopes(game)):
        url = RAW_URL.format(repo=repo, file=urllib.parse.quote(scope_file(scope)))
        req = urllib.request.Request(url, headers={"User-Agent": f"ForeverFlipSync/{VERSION}"})
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                body = resp.read().decode("utf-8")
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                continue
            raise
        texts += [line for line in body.splitlines() if line.startswith("FF1|")]
    folder = game / "Interface" / "AddOns" / "ForeverFlip_Shared"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "ForeverFlip_Shared.toc").write_text(ffscan.SHARED_TOC, encoding="utf-8")
    tmp = folder / "Data.lua.tmp"
    tmp.write_text(ffscan.lua_data_file(texts, time.time()), encoding="utf-8")
    shutil.move(str(tmp), str(folder / "Data.lua"))
    return len(texts)


# --- Main loop -------------------------------------------------------------------------------------

def run_once(game: pathlib.Path, repo: str, state: dict, token: str | None, upload: bool) -> None:
    if upload:
        if token:
            hub = GitHub(repo, token)
            follow_uploads(hub, state)
            upload_new_scans(game, hub, state)
        elif not state.get("warned"):
            log("No GitHub token: scans are not uploaded (see --help). Downloading still works.")
            state["warned"] = True
    count = download_shared(game, repo)
    log(f"Community data: {count} scans written to ForeverFlip_Shared (used after /reload).")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--game", help=r"WoW Forever folder, e.g. C:\World of Warcraft\_forever_")
    parser.add_argument("--repo", default=None, help=f"community data repository (default {DEFAULT_REPO})")
    parser.add_argument("--once", action="store_true", help="run one upload and download, then exit")
    parser.add_argument("--download-only", action="store_true", help="never upload scans")
    parser.add_argument("--interval", type=int, default=60, help="seconds between checks (default 60)")
    args = parser.parse_args()

    folder = config_dir()
    config = load_json(folder / "config.json", {})
    state_path = folder / "state.json"
    state = load_json(state_path, {})
    game = find_game(args.game or config.get("game"))
    repo = args.repo or config.get("repo") or DEFAULT_REPO
    token = None if args.download_only else find_token(config)
    log(f"ForeverFlip Sync {VERSION}: game {game}, data {repo}, "
        f"{'upload and download' if token else 'download only'}.")

    last_seen: dict[str, float] = {}
    next_download = 0.0
    while True:
        try:
            changed = False
            for path in saved_variable_files(game):
                mtime = path.stat().st_mtime
                if last_seen.get(str(path)) != mtime:
                    last_seen[str(path)] = mtime
                    changed = True
            if changed or time.time() >= next_download or args.once:
                run_once(game, repo, state, token, not args.download_only)
                save_json(state_path, state)
                next_download = time.time() + 15 * 60
        except (urllib.error.URLError, OSError, ValueError) as exc:
            log(f"Error: {exc}. Trying again later.")
        if args.once:
            return
        time.sleep(max(15, args.interval))


if __name__ == "__main__":
    main()
