"""Packages the addon into a release archive.

Usage:
    python tools/build.py [--output dist] [--skip-tests]

The archive contains a single ForeverFlip/ folder (the TOC, every file it loads and the licence)
and can be unpacked straight into Interface/AddOns. Before packaging the script checks that:

* every file listed in the TOC exists and no stray .lua file is left out of it;
* the TOC version matches F.version in Util.lua and the Sync helper's VERSION;
* the automated tests pass (unless --skip-tests is given).

It prints the archive path and its SHA-256 checksum (GitHub shows the same one on the release page).
"""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import re
import subprocess
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADDON = ROOT / "ForeverFlip"
TOC = ADDON / "ForeverFlip.toc"
# The player's documents travel in the addon folder too, as other addons ship theirs.
EXTRA_FILES = [ROOT / "LICENSE", ROOT / "README.md", ROOT / "CHANGELOG.md"]
UTIL = ADDON / "Core" / "Util.lua"
SYNC = ROOT / "sync" / "foreverflip_sync.py"  # its helper is built from the same tag


def fail(message: str) -> None:
    print(f"build: {message}", file=sys.stderr)
    sys.exit(1)


def read_toc() -> tuple[str, list[str]]:
    version = None
    files = []
    for raw in TOC.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("##"):
            match = re.match(r"##\s*Version:\s*(\S+)", line)
            if match:
                version = match.group(1)
            continue
        if line.startswith("#"):
            continue
        # The TOC writes folders with the game's "\\"; the archive and the file system take "/".
        files.append(line.replace("\\", "/"))
    if not version:
        fail("the TOC has no '## Version:' line")
    return version, files


def check_sources(version: str, files: list[str]) -> None:
    for name in files:
        if not (ADDON / name).is_file():
            fail(f"the TOC lists {name}, which does not exist")
    listed = {name.lower() for name in files}
    for path in ADDON.rglob("*.lua"):
        rel = path.relative_to(ADDON).as_posix()
        if rel.lower() not in listed:
            fail(f"{rel} is not listed in the TOC")
    util = UTIL.read_text(encoding="utf-8")
    match = re.search(r'F\.version\s*=\s*"([^"]+)"', util)
    if not match or match.group(1) != version:
        fail(f"F.version in Core/Util.lua does not match the TOC version {version}")
    helper = re.search(r'^VERSION = "([^"]+)"', SYNC.read_text(encoding="utf-8"), re.M)
    if not helper or helper.group(1) != version:
        fail(f"VERSION in sync/foreverflip_sync.py does not match the TOC version {version}")


def run_tests() -> None:
    result = subprocess.run(
        [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py"],
        cwd=ROOT,
    )
    if result.returncode != 0:
        fail("tests failed")


def package(version: str, files: list[str], output: pathlib.Path) -> pathlib.Path:
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f"ForeverFlip-{version}.zip"
    entries = [TOC] + [ADDON / name for name in files] + sorted(ADDON.glob("*.xml")) + EXTRA_FILES
    # The icon of the AddOns list (## IconTexture), kept in its own folder.
    entries += sorted((ADDON / "Media").glob("*.tga"))
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in entries:
            inner = path.relative_to(ADDON).as_posix() if ADDON in path.parents else path.name
            info = zipfile.ZipInfo(f"ForeverFlip/{inner}", date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            zf.writestr(info, path.read_bytes())
    return archive


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output", default="dist", help="folder for the archive (default: dist)")
    parser.add_argument("--skip-tests", action="store_true", help="package without running the tests")
    args = parser.parse_args()

    version, files = read_toc()
    check_sources(version, files)
    if not args.skip_tests:
        run_tests()
    archive = package(version, files, ROOT / args.output)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    print(f"{archive.relative_to(ROOT)}  sha256 {digest}")


if __name__ == "__main__":
    main()
