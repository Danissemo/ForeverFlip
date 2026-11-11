"""The local development flow: every commit is checked, installed into the game and pushed.

Git runs it through the hooks in .githooks (enable them once with
`git config core.hooksPath .githooks`):

    pre-commit   python tools/devflow.py check     style check and tests (when code changed)
    post-commit  python tools/devflow.py publish   install into the game, push main to GitHub

Other commands:

    python tools/devflow.py install   copy ForeverFlip/ into the game's Interface/AddOns
    python tools/devflow.py push      push main when it is ahead of GitHub
    python tools/devflow.py stop      for an AI assistant's "stop" hook: refuses to stop while
                                      changes are not committed, pushes what is not pushed yet

Releases stay manual: a tag (`git push origin vX.Y.Z`) is never pushed by this script.

Settings (environment variables or `git config`):

    FF_GAME / ff.game         the WoW Forever folder (default: C:\\World of Warcraft\\_forever_ and
                              other usual places); install is skipped when none is found
    FF_STYLUA / ff.stylua     the StyLua executable (default: C:\\FF\\.tools\\stylua\\stylua.exe or
                              stylua on PATH); the style check is skipped when none is found
    FF_NO_PUSH=1              commit without pushing
    FF_NO_INSTALL=1           commit without installing into the game
"""

from __future__ import annotations

import json
import os
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADDON = ROOT / "ForeverFlip"
BRANCH = "main"
GAME_PATHS = [
    r"C:\World of Warcraft\_forever_",
    r"C:\Program Files (x86)\World of Warcraft\_forever_",
    r"C:\Program Files\World of Warcraft\_forever_",
    r"D:\World of Warcraft\_forever_",
]
STYLUA_PATHS = [r"C:\FF\.tools\stylua\stylua.exe"]
CODE = ("ForeverFlip/", "sync/", "tests/", "tools/", ".stylua.toml", "requirements-dev.txt")


def git(*args: str, check: bool = True, timeout: int = 120) -> str:
    out = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    if check and out.returncode != 0:
        raise RuntimeError(out.stderr.strip() or f"git {' '.join(args)} failed")
    return out.stdout.strip()


def setting(env: str, key: str) -> str | None:
    value = os.environ.get(env)
    if value:
        return value
    return git("config", "--get", key, check=False) or None


def say(message: str) -> None:
    print(f"[devflow] {message}", flush=True)


# --- check ---------------------------------------------------------------------------------------

def staged_code() -> bool:
    names = git("diff", "--cached", "--name-only").splitlines()
    return any(n.startswith(CODE) or n in CODE for n in names)


def stylua() -> str | None:
    given = setting("FF_STYLUA", "ff.stylua")
    for candidate in ([given] if given else []) + STYLUA_PATHS:
        if candidate and pathlib.Path(candidate).is_file():
            return candidate
    return shutil.which("stylua")


def check() -> int:
    if not staged_code():
        say("no code changed: checks skipped")
        return 0
    tool = stylua()
    if tool:
        if subprocess.run([tool, "--check", "ForeverFlip"], cwd=ROOT).returncode != 0:
            say("StyLua: the Lua code is not formatted (run stylua ForeverFlip)")
            return 1
    else:
        say("StyLua not found: style check skipped")
    tests = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py", "-q"],
                           cwd=ROOT, capture_output=True, text=True)
    if tests.returncode != 0:
        sys.stdout.write(tests.stdout[-4000:] + tests.stderr[-4000:])
        say("tests failed: nothing was committed")
        return 1
    last = [line for line in tests.stderr.splitlines() if line.startswith("Ran ")]
    say(f"tests passed ({last[-1][4:] if last else 'ok'})")
    return 0


# --- install -------------------------------------------------------------------------------------

def game_folder() -> pathlib.Path | None:
    given = setting("FF_GAME", "ff.game")
    for candidate in ([given] if given else []) + GAME_PATHS:
        if candidate and (pathlib.Path(candidate) / "Interface" / "AddOns").is_dir():
            return pathlib.Path(candidate)
    return None


def install() -> int:
    if os.environ.get("FF_NO_INSTALL"):
        return 0
    game = game_folder()
    if not game:
        say("WoW Forever not found (set FF_GAME or git config ff.game): not installed")
        return 0
    target = game / "Interface" / "AddOns" / "ForeverFlip"
    target.mkdir(parents=True, exist_ok=True)
    wanted = {p.relative_to(ADDON) for p in ADDON.rglob("*") if p.is_file()}
    copied = 0
    for rel in sorted(wanted):
        src, dst = ADDON / rel, target / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        if not dst.exists() or dst.read_bytes() != src.read_bytes():
            shutil.copy2(src, dst)
            copied += 1
    shutil.copy2(ROOT / "LICENSE", target / "LICENSE")
    removed = 0
    for p in sorted(target.rglob("*"), reverse=True):
        rel = p.relative_to(target)
        if p.is_file() and rel not in wanted and rel != pathlib.Path("LICENSE"):
            p.unlink()
            removed += 1
        elif p.is_dir() and not any(p.iterdir()):
            p.rmdir()
    version = next((line.split(":", 1)[1].strip() for line in (ADDON / "ForeverFlip.toc").read_text(
        encoding="utf-8").splitlines() if line.startswith("## Version:")), "?")
    say(f"installed ForeverFlip {version} into the game ({copied} files updated, {removed} removed). "
        f"In game: /reload (a full restart when a file was added or removed)")
    return 0


# --- push ----------------------------------------------------------------------------------------

def ahead() -> int:
    git("fetch", "--quiet", "origin", BRANCH, check=False, timeout=60)
    counts = git("rev-list", "--left-right", "--count", f"origin/{BRANCH}...{BRANCH}", check=False)
    try:
        behind, mine = (int(x) for x in counts.split())
    except ValueError:
        return 0
    if behind:
        say(f"GitHub has {behind} commit(s) this copy lacks: pull before pushing")
        return 0
    return mine


def push() -> int:
    if os.environ.get("FF_NO_PUSH"):
        return 0
    if git("rev-parse", "--abbrev-ref", "HEAD") != BRANCH:
        say(f"not on {BRANCH}: not pushed")
        return 0
    if not ahead():
        return 0
    out = subprocess.run(["git", "push", "--quiet", "origin", f"HEAD:{BRANCH}"], cwd=ROOT,
                         capture_output=True, text=True, timeout=180)
    if out.returncode != 0:
        say("push failed, it is tried again at the next commit: " + out.stderr.strip()[-300:])
        return 0
    say(f"pushed {git('rev-parse', '--short', 'HEAD')} to GitHub")
    return 0


def publish() -> int:
    install()
    return push()


# --- stop hook -----------------------------------------------------------------------------------

def stop() -> int:
    """Claude Code Stop hook: the turn may not end with uncommitted work."""
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        data = {}
    if data.get("stop_hook_active"):
        return 0  # already asked once in this turn: never loop
    changes = git("status", "--porcelain", check=False)
    if changes:
        reason = ("The working tree has uncommitted changes:\n" + changes[:1500] +
                  "\nIf the work is finished and checked, commit it on main with a clear message "
                  "(the hooks test, install into the game and push). If it is not finished, say so "
                  "to the user instead.")
        print(json.dumps({"decision": "block", "reason": reason}))
        return 0
    push()
    return 0


COMMANDS = {"check": check, "install": install, "push": push, "publish": publish, "stop": stop}

if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command not in COMMANDS:
        print(__doc__)
        sys.exit(2)
    sys.exit(COMMANDS[command]())
