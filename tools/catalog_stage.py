"""Stage the packaged addon for the addon sites (CurseForge, Wago, WoWInterface).

    python tools/catalog_stage.py --zip dist/ForeverFlip-3.2.0.zip --notes release-notes.md --out stage

The BigWigs packager uploads to the sites, but it packages a git repository whose top folder holds
the TOC. Ours keeps the addon in ForeverFlip/ beside the tests and tools, so this unpacks the zip
that tools/build.py made (the same files as the GitHub release) into a small repository of its
own, tagged v<version>, with a .pkgmeta that uses the release notes as the site changelog.
Prints the staged folder, which the packager takes as its top directory (-t).
"""

import argparse
import pathlib
import re
import shutil
import subprocess
import sys
import zipfile

ADDON = "ForeverFlip"
NOTES = "RELEASE_NOTES.md"
PKGMETA = f"""package-as: {ADDON}

manual-changelog:
  filename: {NOTES}
  markup-type: markdown

ignore:
  - {NOTES}
"""


def toc_version(toc: pathlib.Path) -> str:
    match = re.search(r"^## Version:\s*(\S+)", toc.read_text(encoding="utf-8"), re.M)
    if not match:
        raise SystemExit(f"no '## Version:' line in {toc}")
    return match.group(1)


def git(folder: pathlib.Path, *args: str) -> None:
    subprocess.run(["git", "-c", "user.name=ForeverFlip release", "-c", "user.email=release@localhost",
                    "-c", "commit.gpgsign=false", "-c", "tag.gpgsign=false", *args],
                   cwd=folder, check=True, stdout=subprocess.DEVNULL)


def stage(archive: pathlib.Path, notes: pathlib.Path, out: pathlib.Path) -> pathlib.Path:
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    with zipfile.ZipFile(archive) as z:
        z.extractall(out)
    top = out / ADDON
    toc = top / f"{ADDON}.toc"
    if not toc.is_file():
        raise SystemExit(f"{archive} has no {ADDON}/{ADDON}.toc")
    version = toc_version(toc)
    shutil.copyfile(notes, top / NOTES)
    (top / ".pkgmeta").write_text(PKGMETA, encoding="utf-8", newline="\n")
    git(top, "init", "-q")
    git(top, "add", "-A")
    git(top, "commit", "-q", "-m", f"{ADDON} {version}")
    git(top, "tag", "-a", f"v{version}", "-m", f"{ADDON} {version}")
    return top


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--zip", required=True, type=pathlib.Path, help="the archive tools/build.py made")
    parser.add_argument("--notes", required=True, type=pathlib.Path, help="the release notes in markdown")
    parser.add_argument("--out", default=pathlib.Path("stage"), type=pathlib.Path, help="folder to stage in")
    args = parser.parse_args(argv)
    print(stage(args.zip, args.notes, args.out).as_posix())
    return 0


if __name__ == "__main__":
    sys.exit(main())
