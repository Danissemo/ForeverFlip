"""Updates ForeverFlip Sync itself from the GitHub releases (ForeverFlipSync.exe beside the addon zip).

Every release carries the helper built from the same tag, and GitHub publishes the SHA-256 of each
file. The running build's own version is found by its SHA-256 among the releases: the version
constant in the sources is not raised with every release, so comparing with it alone would offer
the same build again and again. A source run (not frozen) is never replaced.

The new build is downloaded next to the running one (ForeverFlipSync.exe.new), refused unless its
SHA-256 is the one GitHub published, and can be cancelled while it downloads. Windows does not let a
running program be overwritten, but it can be renamed: install() renames the running file to
ForeverFlipSync.exe.old and moves the new one in its place, putting the old one back when that
fails. The new build runs from the next start; the .old file is removed then. The settings live in
the helper's config folder (%APPDATA%) and are not touched.
"""

from __future__ import annotations

import hashlib
import os
import pathlib
import sys
import urllib.request

import addon_update

ASSET = "ForeverFlipSync.exe"
MAX_EXE = 200 * 1024 * 1024
CHUNK = 256 * 1024
HOSTS = ("https://github.com/", "https://objects.githubusercontent.com/")


class Cancelled(Exception):
    pass


def running_executable() -> pathlib.Path | None:
    """The packaged helper's own file; None for a run from the sources."""
    if getattr(sys, "frozen", False):
        return pathlib.Path(sys.executable).resolve()
    return None


def file_sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(CHUNK), b""):
            h.update(block)
    return h.hexdigest()


def releases_of_helper(releases: list[dict]) -> list[dict]:
    """All releases with the helper, beta or not, newest first."""
    return addon_update.candidates(releases, True, asset_name=lambda version: ASSET)


def current_version(releases: list[dict], own_sha256: str | None, fallback: str) -> str:
    """The running build's version: the release whose helper has this SHA-256, else `fallback`."""
    if own_sha256:
        for release in releases_of_helper(releases):
            if release["sha256"] == own_sha256:
                return release["version"]
    return fallback


def newer(releases: list[dict], beta: bool, current: str) -> dict | None:
    """The helper release to offer, or None (never a downgrade)."""
    found = addon_update.candidates(releases, beta, asset_name=lambda version: ASSET)
    if not found:
        return None
    have = addon_update.parse_version(current)
    best = found[0]
    if have is not None and addon_update.parse_version(best["version"]) <= have:
        return None
    return best


def check(releases: list[dict], beta: bool, fallback: str, exe: pathlib.Path | None = None) -> dict:
    """{current, release (newer or None), frozen}."""
    own = None
    if exe is not None:
        try:
            own = file_sha256(exe)
        except OSError:
            own = None
    current = current_version(releases, own, fallback)
    return {"current": current, "release": newer(releases, beta, current), "frozen": exe is not None}


def download(release: dict, target: pathlib.Path, agent: str, opener=urllib.request.urlopen,
             cancelled=lambda: False, progress=None) -> pathlib.Path:
    """Downloads `release` to `target`, checked against the SHA-256 GitHub published. Nothing is
    left at `target` unless the check passed. Raises Cancelled when `cancelled()` turns true."""
    url = release.get("url") or ""
    if not url.startswith(HOSTS):
        raise addon_update.UpdateError("the helper file is not on GitHub")
    want = release.get("sha256")
    if not want:
        raise addon_update.UpdateError("GitHub published no SHA-256 for the helper file; it is not installed")
    if release.get("size", 0) > MAX_EXE:
        raise addon_update.UpdateError("the helper file is too large")
    target = pathlib.Path(target)
    part = target.with_name(target.name + ".part")
    h, size = hashlib.sha256(), 0
    try:
        req = urllib.request.Request(url, headers={"User-Agent": agent})
        with opener(req, timeout=300) as resp, open(part, "wb") as out:
            while True:
                if cancelled():
                    raise Cancelled()
                block = resp.read(CHUNK)
                if not block:
                    break
                size += len(block)
                if size > MAX_EXE:
                    raise addon_update.UpdateError("the helper file is too large")
                h.update(block)
                out.write(block)
                if progress:
                    progress(size, release.get("size") or 0)
        if h.hexdigest() != want:
            raise addon_update.UpdateError("the download does not match the SHA-256 GitHub published for it")
        os.replace(part, target)
    finally:
        try:
            part.unlink()
        except OSError:
            pass
    return target


def install(exe: pathlib.Path, new: pathlib.Path) -> pathlib.Path:
    """Puts the checked `new` file in place of the running `exe`; returns the kept .old file."""
    exe, new = pathlib.Path(exe), pathlib.Path(new)
    old = exe.with_name(exe.name + ".old")
    try:
        old.unlink()
    except FileNotFoundError:
        pass
    except OSError as exc:  # a previous build still running from it
        raise addon_update.UpdateError(f"the previous update is still in use ({old.name}); restart first") from exc
    exe.rename(old)
    try:
        new.rename(exe)
    except OSError:
        old.rename(exe)  # put the running build back
        raise
    return old


def cleanup(exe: pathlib.Path | None) -> None:
    """Removes what an update left behind; called at start."""
    if exe is None:
        return
    for leftover in (exe.with_name(exe.name + ".old"), exe.with_name(exe.name + ".new.part")):
        try:
            leftover.unlink()
        except OSError:
            pass


def update(release: dict, exe: pathlib.Path, agent: str, opener=urllib.request.urlopen,
           cancelled=lambda: False, progress=None) -> dict:
    """Download, check and install; {version, restart: True}. The running build goes on until restart."""
    new = exe.with_name(exe.name + ".new")
    download(release, new, agent, opener=opener, cancelled=cancelled, progress=progress)
    try:
        install(exe, new)
    finally:
        try:
            new.unlink()
        except OSError:
            pass
    return {"version": release["version"], "restart": True}
