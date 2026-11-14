"""One short summary of where the work stands, printed when an AI assistant starts a session.

    python tools/status.py

Set as a SessionStart hook in `.claude/settings.local.json`. It reads only: the current branch and
how far it is from GitHub, the files changed but not committed, the newest commit, the folders that
changed since the last release tag, and the addon's version. It refuses nothing and touches nothing.
"""

from __future__ import annotations

import sys

import devflow

CHECKS = {
    ".githooks": "the git hooks (they call tools/devflow.py)",
    ".luarc.json": "the Lua diagnostics settings (references/wow-forever-globals.lua)",
    "CHANGELOG.md": "notes only, no tests",
    "CONTRIBUTING.md": "notes only, no tests",
    "ForeverFlip": "the addon (run the tests)",
    "README.md": "notes only, no tests",
    "docs": "documentation only (no tests)",
    "requirements-dev.txt": "the test requirements (no tests)",
    "sync": "the Sync helper (run the tests)",
    "tests": "the tests",
    "tools": "the tools (run the tests)",
}


def show(title: str, *args: str) -> None:
    print(f"{title}: {devflow.git(*args, check=False).strip() or '-'}")


def main() -> int:
    print("Where the work stands (C:/FF/development/foreverflip):")
    show("Branch", "status", "--short", "--branch")
    show("Not committed", "status", "--porcelain")
    show("Last 3 commits", "log", "--oneline", "-3")
    tag = devflow.git("describe", "--tags", "--abbrev=0", check=False).strip()
    if tag:
        show(f"What changed since {tag}", "diff", "--stat", f"{tag}..HEAD")
        folders = devflow.git("diff", "--name-only", f"{tag}..HEAD", check=False).splitlines()
        areas = sorted({line.split("/")[0] for line in folders if line.strip()})
        for area in areas:
            if area == ".github":
                continue  # CI and the release workflow
            print(f"  {area}: {CHECKS.get(area, 'look at it')}")
    else:
        print("Releases: no tag yet")

    version = "?"
    try:
        with open("ForeverFlip/Util.lua", encoding="utf-8") as source:
            for line in source:
                if line.startswith("F.version = "):
                    version = line.split('"')[1]
                    break
    except OSError:
        pass
    print(f"Addon version: {version}")
    print('First: read CLAUDE.md and docs/current-work.md, then run "python tools/devflow.py test" '
          "before changing anything.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
