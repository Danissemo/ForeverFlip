"""ForeverFlip Sync: shares full auction house scans through GitHub.

The game gives addons no network access, so this small program runs next to the game:

1. Upload. When ForeverFlip's SavedVariables file changes (after /reload or logout), the full scans the
   addon kept (setting "Keep my full scans for the ForeverFlip Sync helper") are uploaded, unchanged,
   to the community data repository. This needs a GitHub token with write access to that repository.
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

VERSION = "1.0.0"
DEFAULT_REPO = "Danissemo/ForeverFlip-Data"
INCOMING = "incoming"
API = "https://api.github.com"
RAW_URL = "https://raw.githubusercontent.com/{repo}/main/shared/{file}"
GAME_PATHS = [
    r"C:\World of Warcraft\_forever_",
    r"C:\Program Files (x86)\World of Warcraft\_forever_",
    r"C:\Program Files\World of Warcraft\_forever_",
    r"D:\World of Warcraft\_forever_",
]


def log(message: str) -> None:
    print(time.strftime("%H:%M:%S"), message, flush=True)


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

    def request(self, method: str, url: str, data: bytes | None = None, content_type: str | None = None,
                accept: str = "application/vnd.github+json"):
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Accept", accept)
        req.add_header("User-Agent", f"ForeverFlipSync/{VERSION}")
        req.add_header("X-GitHub-Api-Version", "2022-11-28")
        if self.token:
            req.add_header("Authorization", f"Bearer {self.token}")
        if content_type:
            req.add_header("Content-Type", content_type)
        with urllib.request.urlopen(req, timeout=120) as resp:
            body = resp.read()
        if accept.endswith("json") and body:
            return json.loads(body)
        return body

    def release(self, tag: str) -> dict:
        return self.request("GET", f"{API}/repos/{self.repo}/releases/tags/{urllib.parse.quote(tag)}")

    def upload_asset(self, release: dict, name: str, data: bytes) -> dict:
        url = release["upload_url"].split("{")[0] + "?name=" + urllib.parse.quote(name)
        return self.request("POST", url, data=data, content_type="application/gzip")


def scan_name(scan: ffscan.RawScan, uploader: str) -> str:
    """incoming asset name: <realm>_<faction>_<time>_<uploader hash>.ffr.gz (GitHub keeps ASCII)."""
    def safe(text: str) -> str:
        return re.sub(r"[^A-Za-z0-9-]", "-", text) or "x"
    who = hashlib.sha256(uploader.encode()).hexdigest()[:8]
    return f"{safe(scan.realm)}_{safe(scan.faction)}_{scan.at}_{who}.ffr.gz"


# --- Upload ----------------------------------------------------------------------------------------

def upload_new_scans(game: pathlib.Path, hub: GitHub, state: dict, uploader: str) -> int:
    uploaded = set(state.setdefault("uploaded", []))
    sent = 0
    release = None
    for path in saved_variable_files(game):
        try:
            scans = ffscan.scans_from_saved_variables(path.read_text(encoding="utf-8", errors="replace"))
        except ffscan.LuaError as exc:
            log(f"Cannot read {path}: {exc}")
            continue
        for scan in scans:
            ident = f"{scan.scope}@{scan.at}"
            if ident in uploaded:
                continue
            if release is None:
                release = hub.release(INCOMING)
            data = gzip.compress(ffscan.encode_raw(scan).encode("utf-8"), mtime=0)
            try:
                hub.upload_asset(release, scan_name(scan, uploader), data)
            except urllib.error.HTTPError as exc:
                if exc.code != 422:  # 422: an asset with this name exists already
                    raise
            uploaded.add(ident)
            state["uploaded"] = sorted(uploaded)[-500:]
            sent += 1
            log(f"Uploaded the scan of {scan.scope} from {time.strftime('%d.%m %H:%M', time.localtime(scan.at))}: "
                f"{len(scan.rows)} auctions, {len(data) // 1024} KB")
    return sent


# --- Download --------------------------------------------------------------------------------------

def my_scopes(game: pathlib.Path) -> set[str]:
    """Auction houses the player uses: the markets keys in ForeverFlip's saved data."""
    scopes = set()
    for path in saved_variable_files(game):
        text = path.read_text(encoding="utf-8", errors="replace")
        scopes.update(re.findall(r'\["([^"\]]+-(?:Alliance|Horde|Neutral))"\]\s*=\s*\{', text))
    return scopes


def scope_file(scope: str) -> str:
    return re.sub(r"[^A-Za-z0-9-]", "-", scope) + ".txt"


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
            uploader = state.setdefault("uploader", hashlib.sha256(os.urandom(16)).hexdigest())
            upload_new_scans(game, hub, state, uploader)
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
