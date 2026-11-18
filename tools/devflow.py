"""The local development flow: every commit is checked, installed into the game and pushed.

Git runs it through the hooks in .githooks (enable them once with
`git config core.hooksPath .githooks`):

    pre-commit   python tools/devflow.py check     style check and tests (when code changed)
    post-commit  python tools/devflow.py publish   install into the game, push main to GitHub

Other commands:

    python tools/devflow.py test [word]  the fast loop: the tests whose name matches `word`
                                      (a module or a test name, e.g. `test_bids` or `mark`),
                                      the whole suite when no word is given
    python tools/devflow.py commit [text]  one step: stage everything, write a message when none was
                                      given, commit, install into the game and push (what the hooks
                                      do, in one command a key binding can run)
    python tools/devflow.py prepare-message  only say what the message would be: writes it into the
                                      commit template the editor reads and puts it in the clipboard
    python tools/devflow.py install   copy ForeverFlip/ into the game's Interface/AddOns
    python tools/devflow.py push      push main when it is ahead of GitHub
    python tools/devflow.py stop      for an AI assistant's "stop" hook: refuses to stop while
                                      changes are not committed, pushes what is not pushed yet

    python tools/devflow.py release X.Y.Z [-m text] [--yes] [--no-ci]  a release in one step: commits
                                      what is pending (documentation too; -m gives its message),
                                      waits for GitHub CI to pass on it (Linux too), writes
                                      the version into the TOC, Core/Util.lua and CHANGELOG.md
                                      (the [Unreleased] notes become the version's section),
                                      checks the package builds, commits "Release X.Y.Z", tags
                                      vX.Y.Z and pushes main and the tag. GitHub Actions then
                                      publishes the release with those notes. It asks to type the
                                      version again first (--yes skips that). X.Y.Z-beta.N is a beta.

Only `release` pushes a tag, and only after the version is typed again; commits and hooks never do.

The whole suite takes about a minute, so the hooks and a quick loop run `test` the same way: one
process per module in parallel (FF_JOBS, default: the processors, at most 8). A module that fails
is then run again alone, so its output is readable and not mixed with the others.

Settings (environment variables or `git config`):

    FF_GAME / ff.game         the WoW Forever folder (default: C:\\World of Warcraft\\_forever_ and
                              other usual places); install is skipped when none is found
    FF_STYLUA / ff.stylua     the StyLua executable (default: C:\\FF\\.tools\\stylua\\stylua.exe or
                              stylua on PATH); the style check is skipped when none is found
    FF_NO_PUSH=1              commit without pushing
    FF_NO_INSTALL=1           commit without installing into the game
    FF_BACKUPS / ff.backups   where install keeps its copies (default: C:\\FF\\backups); before it
                              replaces files it copies the installed addon and the ForeverFlip
                              SavedVariables into auto-install-<time>, and keeps the last 5
"""

from __future__ import annotations

import datetime
import json
import os
import pathlib
import re
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
PAPERS = ("LICENSE", "README.md", "CHANGELOG.md")
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


# --- tests ---------------------------------------------------------------------------------------

# The modules the suite is split into. `unittest discover` would find them too, but one process per
# module is what makes the run parallel and its failures readable.
def test_modules(word: str = "") -> list[str]:
    found = []
    for path in sorted((ROOT / "tests").glob("test_*.py")):
        name = path.stem
        # an empty word means the whole suite; otherwise a module or any test name in it
        if not word or word in name:
            found.append(name)
    return found


# Modules that measure how long a frame takes: run alone, after the others, or the processors they
# share with their neighbours are what the number shows, not the addon.
TIMED = {"test_simulation"}


def jobs() -> int:
    given = os.environ.get("FF_JOBS", "").strip()
    if given.isdigit() and int(given) > 0:
        return int(given)
    return max(1, min(8, os.cpu_count() or 1))


def one_module(name: str, pattern: str | None = None) -> subprocess.CompletedProcess[str]:
    cmd = [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-p", f"{name}.py", "-q"]
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=600)


def run_tests(word: str = "", verbose: bool = False) -> int:
    """`test`: one module at a time and in the open when verbose (the way a debugger needs them),
    otherwise every module in parallel with one readable report per failing module."""
    return debug(word + ".py" if word else "test_*.py") if verbose else run_tests_parallel(word)


def debug(pattern: str = "test_*.py") -> int:
    """The same discovery a debugger needs, one module at a time and in the open: the entry point
    of a debugger's own test discovery (use the editor's local configuration).

        python tools/devflow.py test -v             every module of the suite
        python tools/devflow.py test test_bids -v   one module
    """
    if not pattern.endswith(".py"):
        pattern += ".py"
    return subprocess.run(
        [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-p", pattern, "-v"],
        cwd=ROOT,
    ).returncode


def run_tests_parallel(word: str = "") -> int:
    from concurrent.futures import ThreadPoolExecutor

    modules = test_modules(word)
    if not modules:
        say(f"no test module matches {word!r}")
        return 2
    alone = [m for m in modules if m in TIMED]
    together = [m for m in modules if m not in TIMED]
    with ThreadPoolExecutor(max_workers=jobs()) as pool:
        results = list(pool.map(one_module, together))
    # The timed modules wait for the others to finish: a frame measured next to seven busy
    # neighbours is not the frame the addon draws.
    results += [one_module(m) for m in alone]
    ordered = dict(zip(together + alone, results))
    modules = [m for m in modules if m in ordered]
    results = [ordered[m] for m in modules]
    failures = [(m, r) for m, r in zip(modules, results) if r.returncode != 0]
    total = 0
    for result in results:
        total += int(result.stderr.split("Ran ")[1].split()[0]) if "Ran " in result.stderr else 0
    if not failures:
        say(f"tests passed ({total} tests in {modules_word(len(modules))})")
        return 0
    # Started in parallel, the failures would be mixed: each failing module is run again alone so its
    # output is whole, and the matching test names are run first when the word named a test.
    for name, first in failures:
        narrowed = matching_tests(name, word) if word not in name else []
        if narrowed:
            again = subprocess.run([sys.executable, "-m", "unittest", "-q"] + narrowed, cwd=ROOT,
                                   capture_output=True, text=True, timeout=600)
            sys.stdout.write(again.stdout[-4000:])
            sys.stdout.write(again.stderr[-6000:])
        else:
            sys.stdout.write(first.stdout[-4000:])
            sys.stdout.write(first.stderr[-6000:])
    say(f"tests failed ({modules_word(len(failures))}, {total} tests ran)")
    return 1


def modules_word(count: int) -> str:
    return f"{count} module" if count == 1 else f"{count} modules"


def matching_tests(module: str, word: str) -> list[str]:
    """The tests of a module whose name contains `word`, so a narrow run is quick and readable."""
    if not word:
        return []
    source = (ROOT / "tests" / f"{module}.py").read_text(encoding="utf-8")
    names = [line.strip()[4:].split("(", 1)[0] for line in source.splitlines()
             if line.strip().startswith("def test")]
    return [f"{module}.{n}" for n in names if word in n]


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
    if pyflakes() != 0:
        say("pyflakes: the Python is not clean, nothing was committed")
        return 1
    if run_tests() != 0:
        say("tests failed: nothing was committed")
        return 1
    return 0


def pyflakes() -> int:
    """Unused imports and undefined names in the Python: the tests, the Sync helper and the tools."""
    try:
        import pyflakes  # noqa: F401  # only asks whether the checker is installed
        del pyflakes
    except ImportError:
        say("pyflakes is not installed: the Python check is skipped (pip install -r requirements-dev.txt)")
        return 0
    out = subprocess.run([sys.executable, "-m", "pyflakes", "sync", "tools", "tests"], cwd=ROOT,
                         capture_output=True, text=True)
    if out.returncode != 0:
        sys.stdout.write(out.stdout)
        sys.stderr.write(out.stderr)
    return out.returncode


# --- install -------------------------------------------------------------------------------------

def game_folder() -> pathlib.Path | None:
    given = setting("FF_GAME", "ff.game")
    for candidate in ([given] if given else []) + GAME_PATHS:
        if candidate and (pathlib.Path(candidate) / "Interface" / "AddOns").is_dir():
            return pathlib.Path(candidate)
    return None


AUTO_BACKUP = "auto-install-"  # the backups install makes; only these are pruned
AUTO_KEEP = 5


def backups_folder() -> pathlib.Path:
    given = setting("FF_BACKUPS", "ff.backups")
    return pathlib.Path(given) if given else ROOT.parents[1] / "backups"


def backup_before_install(game: pathlib.Path, target: pathlib.Path, root: pathlib.Path | None = None,
                          stamp: str = "") -> pathlib.Path | None:
    """Before files of the installed addon are replaced: a copy of that addon and of the ForeverFlip
    SavedVariables of every account, as the working rules ask. The newer addon may migrate the saved
    data at the next /reload, and that cannot be undone without this copy. The last AUTO_KEEP copies
    stay; backups made by hand (any other name) are never touched."""
    root = root or backups_folder()
    saved = sorted(game.glob("WTF/Account/*/SavedVariables/ForeverFlip*.lua*"))
    if not (target.is_dir() and any(target.iterdir())) and not saved:
        return None
    stamp = stamp or datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    folder = root / (AUTO_BACKUP + stamp)
    folder.mkdir(parents=True, exist_ok=True)
    if target.is_dir():
        shutil.copytree(target, folder / "ForeverFlip", dirs_exist_ok=True)
    for path in saved:
        account = path.parent.parent.name
        (folder / "SavedVariables" / account).mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, folder / "SavedVariables" / account / path.name)
    for old in sorted(p for p in root.glob(AUTO_BACKUP + "*") if p.is_dir())[:-AUTO_KEEP]:
        shutil.rmtree(old, ignore_errors=True)
    return folder


def install() -> int:
    if os.environ.get("FF_NO_INSTALL"):
        return 0
    game = game_folder()
    if not game:
        say("WoW Forever not found (set FF_GAME or git config ff.game): not installed")
        return 0
    target = game / "Interface" / "AddOns" / "ForeverFlip"
    wanted = {p.relative_to(ADDON) for p in ADDON.rglob("*") if p.is_file()}
    changed = [rel for rel in sorted(wanted)
               if not (target / rel).exists() or (target / rel).read_bytes() != (ADDON / rel).read_bytes()]
    if changed:
        kept = backup_before_install(game, target)
        if kept:
            say(f"backed up the installed addon and its SavedVariables into {kept}")
    target.mkdir(parents=True, exist_ok=True)
    copied = 0
    for rel in changed:
        src, dst = ADDON / rel, target / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        copied += 1
    # The player's papers travel with the addon, as in the release zip (tools/build.py).
    papers = {pathlib.Path(name) for name in PAPERS}
    for name in PAPERS:
        shutil.copy2(ROOT / name, target / name)
    removed = 0
    for p in sorted(target.rglob("*"), reverse=True):
        rel = p.relative_to(target)
        if p.is_file() and rel not in wanted and rel not in papers:
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


# --- commit --------------------------------------------------------------------------------------

def message(index: bool) -> str:
    """A message from what is staged (or working tree), the same shape the prepare-commit-msg hook
    writes: the areas that moved on the subject, the files under it."""
    names = git("diff", "--cached" if index else "HEAD", "--name-only", check=False).splitlines()
    if not names:
        return ""

    def area(name: str) -> str:
        for prefix, label in (("ForeverFlip/", "the addon"), ("tests/", "tests"), ("tools/", "tools"),
                              ("sync/", "the Sync helper"), (".github/", "the build and the hooks"),
                              (".githooks/", "the build and the hooks")):
            if name.startswith(prefix):
                return label
        return "the documentation" if name.endswith(".md") or name.startswith("docs/") else "the project"

    groups: dict[str, int] = {}
    for name in names:
        groups[area(name)] = groups.get(area(name), 0) + 1
    parts = ", ".join(f"{label} ({count})" for label, count in groups.items())
    subject = f"Change {len(names)} file(s) -- {parts}"
    return subject + "\n\nChanged:\n" + "\n".join(f"- {n}" for n in names)


def commit(text: str = "") -> int:
    """`commit [text]`: stage everything, write a message when none was given, commit, install and
    push. What one button does: the hooks still run (style, pyflakes, the tests), and a failure
    stops it before anything is committed."""
    subprocess.run(["git", "add", "-A"], cwd=ROOT, check=True)
    staged = git("diff", "--cached", "--name-only", check=False)
    if not staged:
        say("nothing to commit")
        return 0
    text = text.strip() or message(index=True)
    if not text:
        say("no message and nothing staged to describe")
        return 2
    first = text.splitlines()[0]
    result = subprocess.run(["git", "commit", "-F", "-"], cwd=ROOT, input=text, text=True,
                            capture_output=True)
    if result.returncode != 0:
        sys.stdout.write(result.stdout[-2000:] + result.stderr[-2000:])
        return result.returncode
    say(f"committed {git('rev-parse', '--short', 'HEAD')}: {first}")
    # The hooks did their part above: pre-commit ran the style check, pyflakes and the tests, and
    # post-commit installed the addon and pushed. Nothing is repeated here.
    return 0


# --- release -------------------------------------------------------------------------------------

TOC = ADDON / "ForeverFlip.toc"
UTIL = ADDON / "Core" / "Util.lua"
CHANGELOG = ROOT / "CHANGELOG.md"
SEMVER = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.]+))?$")


def current_version() -> str:
    found = re.search(r"^## Version:\s*(\S+)", TOC.read_text(encoding="utf-8"), re.M)
    return found.group(1) if found else ""


def version_key(version: str) -> tuple:
    """Order of versions as Semantic Versioning has it: 3.1.0-beta.1 comes before 3.1.0."""
    major, minor, patch, pre = SEMVER.match(version).groups()
    parts = tuple((0, int(p), "") if p.isdigit() else (1, 0, p) for p in (pre or "").split(".") if p)
    return (int(major), int(minor), int(patch), 0 if pre else 1, parts)


# The places in the guides that name a version, each a pattern whose groups are the version.
# A version written anywhere else in the text counts for nothing: the old check asked only whether
# the version was somewhere in a file, and a sentence about a fix passed for an outdated release link.
_V = r"(\d+\.\d+\.\d+(?:-beta\.\d+)?)"
_TAG = r"\]\(https://github\.com/Danissemo/ForeverFlip/releases/tag/v" + _V + r"\)"
DOC_FIELDS = {
    # The current stable release: a stable release writes it, a beta leaves it alone.
    "stable": {
        "README.md": [r"Current stable release: \[" + _V + _TAG],
        "docs/testing.md": [r"## Поточна версія: " + _V + "$", r"\[ForeverFlip " + _V + _TAG],
        "docs/current-work.md": [r"\[ForeverFlip " + _V + _TAG, r"`Core/Util\.lua` both declare `" + _V + "`"],
    },
    # The version the testers' cards were written for. Their steps change with it, so it is written
    # by hand, and a beta (whose notes send testers to the cards) is not released without it.
    "checklist": {
        "docs/testing.md": [
            r"призначені для \*\*ForeverFlip і ForeverFlip Sync " + _V + r"\*\*",
            r"\[випуску " + _V + _TAG,
            r"Архів `ForeverFlip-" + _V + r"\.zip`",
            r"Установіть " + _V + r" \(START-1\)",
            r"У чаті видно версію " + _V + r"\.",
            r"У рядку Addon видно " + _V + r"\.",
            r"Версії аддона / помічника: " + _V + " / " + _V,
        ],
    },
}


def doc_versions(kind: str, root: pathlib.Path | None = None) -> dict:
    """{"file: 'words'": [every version its matches name]}; an empty list is a field that is gone."""
    root = root or ROOT
    found = {}
    for name, patterns in DOC_FIELDS[kind].items():
        text = (root / name).read_text(encoding="utf-8")
        for pattern in patterns:
            label = pattern.split("(")[0].replace("\\", "").strip()  # the words before the version
            found[f"{name}: '{label}'"] = [v for m in re.finditer(pattern, text, re.M) for v in m.groups()]
    return found


def doc_problems(version: str, root: pathlib.Path | None = None) -> list[str]:
    """The version fields that do not name `version`: the stable release's for a stable version, the
    testers' cards' for a beta."""
    problems = []
    for field, versions in doc_versions("checklist" if "-" in version else "stable", root).items():
        if not versions:
            problems.append(f"{field}: the field is missing")
        elif set(versions) != {version}:
            problems.append(f"{field}: names {', '.join(sorted(set(versions)))}, not {version}")
    return problems


def set_doc_versions(version: str, root: pathlib.Path | None = None) -> None:
    """Write a stable `version` into the stable release's fields and nowhere else in the text."""
    if "-" in version:
        return
    root = root or ROOT
    for name, patterns in DOC_FIELDS["stable"].items():
        path = root / name
        text = path.read_text(encoding="utf-8")
        for pattern in patterns:
            def put(match):
                out, at = [], match.start()
                for i in range(1, len(match.groups()) + 1):
                    out.append(match.string[at:match.start(i)] + version)
                    at = match.end(i)
                return "".join(out) + match.string[at:match.end()]
            text = re.sub(pattern, put, text, flags=re.M)
        path.write_text(text, encoding="utf-8", newline="\n")


def unreleased(text: str) -> str:
    """The notes under `## [Unreleased]`, up to the next version heading."""
    found = re.search(r"^## \[Unreleased\][ \t]*\n(.*?)(?=^## \[|^\[[^\]]+\]: |\Z)", text, re.S | re.M)
    return found.group(1).strip() if found else ""


def stamp_changelog(text: str, version: str, previous: str, day: str) -> str:
    """The Unreleased notes become the version's section; the compare links follow."""
    text = re.sub(r"^## \[Unreleased\][ \t]*\n", f"## [Unreleased]\n\n## [{version}] - {day}\n",
                  text, count=1, flags=re.M)
    link = f"[{version}]: ../../compare/v{previous}...v{version}\n"
    head = f"[Unreleased]: ../../compare/v{version}...HEAD\n"
    text, done = re.subn(r"^\[Unreleased\]: .*\n", lambda _: head + link, text, count=1, flags=re.M)
    if not done:
        text = text.rstrip("\n") + "\n\n" + head + link
    return text


def ahead_of_us() -> int:
    """How many commits GitHub's main has that this copy lacks."""
    git("fetch", "--quiet", "origin", BRANCH, check=False, timeout=60)
    counts = git("rev-list", "--left-right", "--count", f"origin/{BRANCH}...{BRANCH}", check=False)
    try:
        return int(counts.split()[0])
    except (ValueError, IndexError):
        return 0


def ci_verdict(runs: list) -> str:
    """The CI runs GitHub lists for one commit (gh run list --json status,conclusion) in one word:
    "success", "failure", "running" or "missing"."""
    if not runs:
        return "missing"
    if any(r.get("status") != "completed" for r in runs):
        return "running"
    return "success" if all(r.get("conclusion") == "success" for r in runs) else "failure"


def ci_failures(log: str, limit: int = 20) -> list[str]:
    """The lines of a failed run's log that say what failed, without the job and time prefixes."""
    lines = []
    for line in log.splitlines():
        text = re.sub(r"^[^\t]*\t[^\t]*\t\S+Z ", "", line).strip()
        if re.match(r"(FAIL|ERROR):|\w*Error\b|File \"|FAILED \(", text) and text not in lines:
            lines.append(text)
    return lines[:limit]


def wait_for_ci(sha: str, timeout: int = 900) -> str:
    """Waits for GitHub's CI on `sha` (every system it runs on, Linux too) and says how it ended.
    The tests here run on Windows only: a test that breaks on Linux shows up only there."""
    if not shutil.which("gh"):
        say("release stopped: the GitHub CLI (gh) is not found, so the CI result cannot be read; "
            "install it, or pass --no-ci after checking https://github.com/Danissemo/ForeverFlip/actions")
        return "missing"
    import time

    start = time.monotonic()
    said = False
    while True:
        out = subprocess.run(["gh", "run", "list", "--workflow", "CI", "--commit", sha,
                              "--json", "databaseId,status,conclusion"],
                             cwd=ROOT, capture_output=True, text=True, timeout=60)
        runs = json.loads(out.stdout or "[]") if out.returncode == 0 else []
        verdict = ci_verdict(runs)
        if verdict in ("success", "failure"):
            break
        if time.monotonic() - start > timeout:
            say(f"release stopped: no CI result for {sha[:7]} after {timeout // 60} minutes "
                "(https://github.com/Danissemo/ForeverFlip/actions)")
            return verdict
        if not said:
            say(f"waiting for GitHub CI on {sha[:7]} (Windows and Linux, about 2 minutes)")
            said = True
        time.sleep(15)
    if verdict == "failure":
        for run in runs:
            if run.get("conclusion") != "success":
                log = subprocess.run(["gh", "run", "view", str(run["databaseId"]), "--log-failed"],
                                     cwd=ROOT, capture_output=True, text=True, encoding="utf-8",
                                     errors="replace", timeout=120).stdout
                for line in ci_failures(log):
                    print("    " + line)
        say(f"release stopped: CI failed on {sha[:7]}; nothing of the version is written. Fix it, "
            "commit, and run release again")
    else:
        say(f"CI passed on {sha[:7]}")
    return verdict


def release(version: str, note: str = "", yes: bool = False, ci: bool = True) -> int:
    """`release <version> [-m text] [--yes]`: commit what is pending (documentation included), set the
    version in the TOC, Core/Util.lua, CHANGELOG.md and, for a stable release, the current
    release's fields of README.md, docs/testing.md and docs/current-work.md (DOC_FIELDS), build the package to check it, commit
    "Release <version>", tag v<version> and push main and the tag. GitHub Actions
    (.github/workflows/release.yml) then builds the zip and Sync and publishes the release with
    this version's changelog notes; a version with "-" (3.1.0-beta.1) is published as a beta.

    It asks for the version to be typed again before anything is changed, unless --yes is given."""
    previous = current_version()
    problems = []
    if not SEMVER.match(version or ""):
        problems.append(f"'{version}' is not a version like 3.1.0 or 3.1.0-beta.1")
    elif SEMVER.match(previous) and version_key(version) <= version_key(previous):
        problems.append(f"{version} is not newer than the current {previous}")
    if git("rev-parse", "--abbrev-ref", "HEAD", check=False) != BRANCH:
        problems.append(f"not on {BRANCH}")
    if version and git("tag", "--list", f"v{version}", check=False):
        problems.append(f"the tag v{version} already exists")
    if os.environ.get("FF_NO_PUSH"):
        problems.append("FF_NO_PUSH is set: a release has to be pushed")
    changelog = CHANGELOG.read_text(encoding="utf-8")
    if not unreleased(changelog):
        problems.append("CHANGELOG.md has nothing under ## [Unreleased]: write the notes first")
    if not problems:
        # A beta's notes send testers to the cards, so their version is updated by hand first. A
        # stable release writes its own fields; one it cannot find (reworded) would keep the old one.
        found = doc_problems(version)
        if "-" not in version:
            found = [p for p in found if p.endswith("the field is missing")]
        problems.extend("the guides: " + p for p in found)
        if "-" in version and found:
            problems.append("update the cards of docs/testing.md for the beta, then "
                            "python tools/make_tester_workbook.py")
    if not problems and ahead_of_us():
        problems.append("GitHub has commits this copy lacks: pull first")
    if problems:
        for problem in problems:
            say("release stopped: " + problem)
        return 2

    pending = git("status", "--porcelain", check=False)
    say(f"release {previous} -> {version}"
        + (" (a beta, published as a prerelease)" if "-" in version else ""))
    if pending:
        say(f"first the pending changes are committed ({len(pending.splitlines())} files)"
            + (f": {note}" if note else ", with a message written from them"))
    say("then: the version in the TOC, Core/Util.lua and the guides, the CHANGELOG section, "
        f"a build check, commit 'Release {version}', tag v{version}, push main and the tag")
    if not yes:
        try:
            answer = input(f"Type {version} to go on: ").strip()
        except EOFError:
            answer = ""
        if answer != version:
            say("release cancelled, nothing changed")
            return 1

    if pending:
        result = commit(note)
        if result != 0 or git("status", "--porcelain", check=False):
            say("release stopped: the pending changes were not committed (see above)")
            return result or 1
        changelog = CHANGELOG.read_text(encoding="utf-8")
    if ci:
        push()
        if wait_for_ci(git("rev-parse", "HEAD")) != "success":
            return 1

    day = datetime.date.today().isoformat()
    TOC.write_text(re.sub(r"^## Version:.*$", f"## Version: {version}", TOC.read_text(encoding="utf-8"),
                          count=1, flags=re.M), encoding="utf-8", newline="\n")
    # newline="\n": the repository keeps LF, and Python on Windows would write CRLF, which StyLua refuses
    UTIL.write_text(re.sub(r'^F\.version = ".*"$', f'F.version = "{version}"',
                           UTIL.read_text(encoding="utf-8"), count=1, flags=re.M), encoding="utf-8",
                    newline="\n")
    CHANGELOG.write_text(stamp_changelog(changelog, version, previous, day), encoding="utf-8",
                         newline="\n")
    set_doc_versions(version)
    if current_version() != version or f'F.version = "{version}"' not in UTIL.read_text(encoding="utf-8") \
            or doc_problems(version):
        say("release stopped: the version was not written; check the TOC, Core/Util.lua, README.md "
            "and docs/testing.md")
        return 1
    workbook = ROOT / "tools" / "make_tester_workbook.py"
    if workbook.exists():  # the testers' workbook follows the cards; a test checks it
        subprocess.run([sys.executable, str(workbook)], cwd=ROOT, capture_output=True, text=True)

    build = subprocess.run([sys.executable, str(ROOT / "tools" / "build.py"), "--output", "dist"],
                           cwd=ROOT, capture_output=True, text=True)
    if build.returncode != 0:
        sys.stdout.write(build.stdout[-2000:] + build.stderr[-2000:])
        say("release stopped: the package does not build; the version files are changed but not "
            "committed (git checkout -- ForeverFlip CHANGELOG.md undoes them)")
        return build.returncode
    result = commit(f"Release {version}")
    if result != 0:
        return result
    git("tag", "-a", f"v{version}", "-m", f"ForeverFlip {version}")
    push()
    if ahead():
        say(f"release stopped: main is not on GitHub yet; the tag v{version} is made here, push "
            f"both with: git push origin {BRANCH} v{version}")
        return 1
    out = subprocess.run(["git", "push", "origin", f"v{version}"], cwd=ROOT, capture_output=True,
                         text=True, timeout=180)
    if out.returncode != 0:
        sys.stdout.write(out.stderr[-1000:])
        say(f"the tag v{version} is made but not pushed: git push origin v{version}")
        return out.returncode
    say(f"pushed v{version}: GitHub Actions builds and publishes the release "
        "(https://github.com/Danissemo/ForeverFlip/actions)")
    return 0


# --- prepare-message -----------------------------------------------------------------------------

TEMPLATE = ROOT / ".git" / "ff-commit-message.txt"


def prepare_message(copy: bool = True) -> int:
    """`prepare-message`: write the message for what is staged into the commit template, and put it
    into the clipboard. The editor fills its Commit box from that template (the Git extension's
    command "Restore Commit Template"), so one key gives both the box and the clipboard.

    Nothing is committed: this only says what the message would be.
    """
    subprocess.run(["git", "add", "-A"], cwd=ROOT, check=False)
    text = message(index=True)
    if not text:
        say("nothing to describe: the working tree is clean")
        return 0
    TEMPLATE.parent.mkdir(parents=True, exist_ok=True)
    TEMPLATE.write_text(text + "\n", encoding="utf-8")
    subject = text.splitlines()[0]
    if copy and not clipboard(subject):
        say(f"the template is written; copy it by hand: {subject}")
        return 0
    say(f"in the clipboard: {subject}")
    return 0


def clipboard(text: str) -> bool:
    """The system clipboard, on Windows through clip.exe (no extra package)."""
    try:
        out = subprocess.run(["clip.exe"], input=text, text=True, timeout=15, check=False)
        return out.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


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


COMMANDS = {"check": check, "test": run_tests, "commit": commit, "prepare-message": prepare_message,
            "install": install, "push": push, "publish": publish, "stop": stop,
            "release": release}

if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command not in COMMANDS:
        print(__doc__)
        sys.exit(2)
    args = sys.argv[2:]
    if command == "test":
        word = next((a for a in args if not a.startswith("-")), "")
        sys.exit(run_tests(word, verbose="-v" in args))
    if command == "commit":
        sys.exit(commit(" ".join(args)))
    if command == "release":
        text = ""
        if "-m" in args and args.index("-m") + 1 < len(args):
            text = args[args.index("-m") + 1]
        version = next((a for a in args if not a.startswith("-") and a != text), "")
        sys.exit(release(version, text, yes="--yes" in args, ci="--no-ci" not in args))
    if command == "prepare-message":
        sys.exit(prepare_message(copy="--no-copy" not in args))
    sys.exit(COMMANDS[command]())
