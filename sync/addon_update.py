"""Keeps the ForeverFlip addon up to date from the GitHub releases.

Releases are tagged v<version>; a version with a suffix (1.2.0-beta.4) is a pre-release, offered only
to beta testers. The newest release above the installed version is downloaded, checked (the SHA-256
GitHub publishes for the file, a single ForeverFlip/ folder, the TOC's version), and swapped in for
the installed folder. The replaced folder is kept as a zip backup in the helper's folder (the last
two). Nothing is ever downgraded: a beta tester who leaves the beta keeps the beta until a newer
release comes.
"""

from __future__ import annotations

import hashlib
import io
import json
import pathlib
import re
import shutil
import time
import urllib.request
import zipfile

ADDON = "ForeverFlip"
MAX_ZIP = 20 * 1024 * 1024
MAX_UNPACKED = 60 * 1024 * 1024
KEEP_BACKUPS = 2
STAGES = {"alpha": 0, "beta": 1, "rc": 2}
VERSION_TEXT = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)(?:-(alpha|beta|rc)\.?(\d+))?$")


class UpdateError(RuntimeError):
    pass


def parse_version(text: str | None):
    """A sortable version: 1.2.0-beta.4 < 1.2.0-rc.1 < 1.2.0 < 1.2.1-beta.1; None if not a version."""
    m = VERSION_TEXT.match((text or "").strip())
    if not m:
        return None
    major, minor, patch, stage, number = m.groups()
    rank = STAGES[stage] if stage else 3
    return int(major), int(minor), int(patch), rank, int(number or 0)


def is_beta(text: str) -> bool:
    v = parse_version(text)
    return v is not None and v[3] < 3


def addon_folder(game: pathlib.Path) -> pathlib.Path:
    return pathlib.Path(game) / "Interface" / "AddOns" / ADDON


def toc_version(text: str) -> str | None:
    m = re.search(r"^## Version:\s*(\S+)\s*$", text, re.M)
    return m.group(1) if m else None


def installed_version(game: pathlib.Path) -> str | None:
    try:
        return toc_version((addon_folder(game) / f"{ADDON}.toc").read_text(encoding="utf-8-sig", errors="replace"))
    except OSError:
        return None


def fetch_releases(repo: str, agent: str, token: str | None = None) -> list[dict]:
    req = urllib.request.Request(f"https://api.github.com/repos/{repo}/releases?per_page=30")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("User-Agent", agent)
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode("utf-8"))


def candidates(releases: list[dict], beta: bool) -> list[dict]:
    """Usable releases, newest first: {version, tag, beta, asset, url, size, sha256, notes, page}."""
    out = []
    for r in releases:
        tag = str(r.get("tag_name") or "")
        version = tag[1:] if tag.startswith("v") else tag
        if r.get("draft") or parse_version(version) is None:
            continue
        pre = bool(r.get("prerelease")) or is_beta(version)
        if pre and not beta:
            continue
        name = f"{ADDON}-{version}.zip"
        asset = next((a for a in r.get("assets") or [] if a.get("name") == name), None)
        if not asset:
            continue
        digest = str(asset.get("digest") or "")
        out.append({"version": version, "tag": tag, "beta": pre, "asset": name,
                    "url": asset.get("browser_download_url"), "size": int(asset.get("size") or 0),
                    "sha256": digest[7:] if digest.startswith("sha256:") else None,
                    "notes": r.get("body") or "", "page": r.get("html_url") or ""})
    out.sort(key=lambda c: parse_version(c["version"]), reverse=True)
    return out


def newer(installed: str | None, releases: list[dict], beta: bool) -> dict | None:
    """The release to install, or None when the installed addon is the newest (never a downgrade)."""
    found = candidates(releases, beta)
    if not found:
        return None
    best = found[0]
    have = parse_version(installed)
    if have is not None and parse_version(best["version"]) <= have:
        return None
    return best


def download(release: dict, agent: str) -> bytes:
    url = release.get("url") or ""
    if not url.startswith("https://github.com/") and not url.startswith("https://objects.githubusercontent.com/"):
        raise UpdateError("the release file is not on GitHub")
    if release.get("size", 0) > MAX_ZIP:
        raise UpdateError("the release file is too large")
    req = urllib.request.Request(url, headers={"User-Agent": agent})
    with urllib.request.urlopen(req, timeout=300) as resp:
        data = resp.read(MAX_ZIP + 1)
    if len(data) > MAX_ZIP:
        raise UpdateError("the release file is too large")
    if release.get("sha256"):
        if hashlib.sha256(data).hexdigest() != release["sha256"]:
            raise UpdateError("the download does not match the SHA-256 GitHub published for it")
    elif release.get("size") and len(data) != release["size"]:
        raise UpdateError("the download is incomplete")
    return data


def check_package(data: bytes, version: str) -> zipfile.ZipFile:
    """The release zip, refused unless it is one ForeverFlip/ folder of the expected version."""
    try:
        archive = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile as exc:
        raise UpdateError("the release file is not a zip archive") from exc
    total = 0
    members = set()
    files = set()
    for info in archive.infolist():
        name = info.filename
        parts = name.split("/")
        if (name.startswith("/") or "\\" in name or ":" in name or parts[0] != ADDON
                or any(p in ("..", ".") for p in parts) or len(parts) < 2):
            raise UpdateError(f"unexpected file in the release: {name}")
        normalized = name.rstrip("/").casefold()
        if normalized in members:
            raise UpdateError(f"duplicate file in the release: {name}")
        members.add(normalized)
        if not info.is_dir():
            files.add(normalized)
        total += info.file_size
    if total > MAX_UNPACKED:
        raise UpdateError("the release unpacks too large")
    try:
        toc = archive.read(f"{ADDON}/{ADDON}.toc").decode("utf-8-sig", errors="replace")
    except KeyError as exc:
        raise UpdateError("the release has no ForeverFlip.toc") from exc
    if toc_version(toc) != version:
        raise UpdateError(f"the release's TOC says {toc_version(toc)}, not {version}")
    for line in toc.splitlines():
        name = line.strip().replace("\\", "/")
        if name and not name.startswith("#") and f"{ADDON}/{name}".casefold() not in files:
            raise UpdateError(f"the release's TOC lists a missing file: {name}")
    return archive


def backup(folder: pathlib.Path, backups: pathlib.Path, version: str | None) -> pathlib.Path | None:
    if not folder.is_dir():
        return None
    backups.mkdir(parents=True, exist_ok=True)
    target = backups / f"{ADDON}-{version or 'unknown'}-{time.strftime('%Y%m%d-%H%M%S')}.zip"
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(folder.rglob("*")):
            if path.is_file():
                zf.write(path, f"{ADDON}/{path.relative_to(folder).as_posix()}")
    old = sorted(backups.glob(f"{ADDON}-*.zip"), key=lambda p: p.stat().st_mtime)
    for path in old[:-KEEP_BACKUPS]:
        path.unlink(missing_ok=True)
    return target


def install(game: pathlib.Path, release: dict, backups: pathlib.Path, agent: str) -> dict:
    """Downloads, checks and installs `release`. Returns {version, previous, restart}: restart is
    True when files were added or removed (the game reads new files only at a restart)."""
    data = download(release, agent)
    archive = check_package(data, release["version"])
    folder = addon_folder(game)
    addons = folder.parent
    if not addons.is_dir():
        raise UpdateError("the game has no Interface/AddOns folder")
    previous = installed_version(game)
    before = {p.relative_to(folder).as_posix() for p in folder.rglob("*") if p.is_file()} if folder.is_dir() else set()
    staging = addons / f".{ADDON}-update"
    old = addons / f".{ADDON}-old"
    for leftover in (staging, old):
        shutil.rmtree(leftover, ignore_errors=True)
    staging.mkdir()
    try:
        archive.extractall(staging)
        new = staging / ADDON
        after = {p.relative_to(new).as_posix() for p in new.rglob("*") if p.is_file()}
        backup(folder, backups, previous)
        if folder.exists():
            folder.rename(old)
        try:
            new.rename(folder)
        except OSError:
            if old.exists() and not folder.exists():
                old.rename(folder)  # put the previous version back
            raise
    finally:
        shutil.rmtree(staging, ignore_errors=True)
    shutil.rmtree(old, ignore_errors=True)
    return {"version": release["version"], "previous": previous, "restart": after != before}


def is_development_copy(game: pathlib.Path) -> bool:
    """A folder linked to a checkout (or holding one) is a developer's: never replaced."""
    folder = addon_folder(game)
    try:
        junction = getattr(folder, "is_junction", lambda: False)()
        return folder.is_symlink() or junction or (folder / ".git").exists()
    except OSError:
        return False
