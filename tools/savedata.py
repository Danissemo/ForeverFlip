"""Copies of ForeverFlip's saved data (WTF/.../SavedVariables/ForeverFlip.lua), kept outside the game.

A copy inside the game is not possible: the saved file is already tens of megabytes, near what the
client can read back (Data.fitSave), and a second copy in it would double that. So the snapshot is a
copy of the file, made here:

    python tools/savedata.py backup [label]   copy the saved data of every account into
                                              C:\\FF\\backups\\savedata-<date>-<time>[-label]
    python tools/savedata.py list             the copies, newest first, with their size
    python tools/savedata.py restore <name>   put a copy back (the game must be closed: it writes the
                                              file at logout and would overwrite it); what is there
                                              now is copied first, as savedata-...-before-restore

Settings: FF_GAME / ff.game (the game folder, as devflow.py), FF_BACKUPS (default C:\\FF\\backups).
"""

from __future__ import annotations

import datetime
import os
import pathlib
import shutil
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import devflow  # noqa: E402

PREFIX = "savedata-"
FILES = ("ForeverFlip.lua", "ForeverFlip.lua.bak")


def backups_folder() -> pathlib.Path:
    return pathlib.Path(os.environ.get("FF_BACKUPS") or devflow.ROOT.parent.parent / "backups")


def saved_files(game: pathlib.Path) -> list[pathlib.Path]:
    """ForeverFlip's saved files of every account (not the per-character folders: it has none)."""
    found = []
    for folder in sorted((game / "WTF" / "Account").glob("*/SavedVariables")):
        for name in FILES:
            if (folder / name).is_file():
                found.append(folder / name)
    return found


def game_running() -> bool:
    """Is a WoW client running? (Windows: tasklist; elsewhere never.)"""
    if os.name != "nt":
        return False
    try:
        out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq Wow*", "/NH"], capture_output=True,
                             text=True, timeout=20).stdout
    except (OSError, subprocess.SubprocessError):
        return False
    return any(line.lower().startswith("wow") for line in out.splitlines())


def backup(game: pathlib.Path, label: str = "", now: datetime.datetime | None = None) -> pathlib.Path | None:
    files = saved_files(game)
    if not files:
        print("no saved ForeverFlip data found under", game / "WTF")
        return None
    stamp = (now or datetime.datetime.now()).strftime("%Y%m%d-%H%M%S")
    clean = "".join(c for c in label if c.isalnum() or c in "-_")
    target = backups_folder() / (PREFIX + stamp + ("-" + clean if clean else ""))
    for src in files:
        rel = src.relative_to(game / "WTF")
        dst = target / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
    size = sum(f.stat().st_size for f in target.rglob("*") if f.is_file())
    print(f"saved {len(files)} files ({size / 1048576:.1f} MB) into {target}")
    return target


def copies() -> list[pathlib.Path]:
    folder = backups_folder()
    if not folder.is_dir():
        return []
    return sorted((p for p in folder.iterdir() if p.is_dir() and p.name.startswith(PREFIX)),
                  key=lambda p: p.name, reverse=True)


def list_copies() -> int:
    found = copies()
    if not found:
        print("no copies in", backups_folder())
    for p in found:
        size = sum(f.stat().st_size for f in p.rglob("*") if f.is_file())
        print(f"{p.name}  {size / 1048576:.1f} MB")
    return 0


def restore(game: pathlib.Path, name: str) -> int:
    source = backups_folder() / name
    if not name or not source.is_dir():
        print("no such copy:", source)
        return 1
    if game_running():
        print("the game is running: close it first (it writes the saved file at logout)")
        return 1
    files = [f for f in source.rglob("*") if f.is_file() and f.name in FILES]
    if not files:
        print("the copy holds no ForeverFlip files:", source)
        return 1
    backup(game, "before-restore")
    for src in files:
        dst = game / "WTF" / src.relative_to(source)
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
    print(f"restored {len(files)} files from {name}")
    return 0


def main(args: list[str]) -> int:
    command = args[0] if args else ""
    if command == "list":
        return list_copies()
    if command not in ("backup", "restore"):
        print(__doc__)
        return 2
    game = devflow.game_folder()
    if not game:
        print("WoW Forever not found (set FF_GAME or git config ff.game)")
        return 1
    if command == "backup":
        return 0 if backup(game, args[1] if len(args) > 1 else "") else 1
    return restore(game, args[1] if len(args) > 1 else "")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
