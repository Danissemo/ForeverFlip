@../../CLAUDE.md

Run repository commands from `C:\FF\development\foreverflip`; `C:\FF` is the surrounding toolchain.
The shared instructions above hold the client/API facts, architecture boundaries and tool paths.
The git hooks
(`.githooks`) are on: a commit runs StyLua, `pyflakes` and the whole suite, then installs the addon
into the game and pushes `main`.

## Fast working loop

- Read `docs/current-work.md` at session start; reuse the SessionStart status output when it
  already includes this file. Read `docs/architecture.md` before larger or cross-module changes,
  then inspect only the relevant implementation, callers and tests.
- Search this repository first. Search `C:\FF\references\wow-ui-source` only for the relevant
  Forever API; avoid scanning `C:\FF` (tooling, backups and distribution copies) for addon code.
- Batch independent searches and reads in one tool round. Reuse findings within the task; reread
  when a file changed, evidence conflicts or verification needs the current contents.
- Delegate substantial independent work, not tiny reads or calculations. Give each worker the
  verified absolute repository path, exact input paths, owned output paths and a completion check.
  Keep writes to shared files such as `Core.lua`, `UI.lua` and `tests/mock.lua` with one owner.
  The coordinator integrates shared changes and runs the final checks once.
- During edits, run the relevant **test module** with the existing runner. For example, from the
  repository root:

  ```powershell
  & 'C:\FF\.tools\python\Scripts\python.exe' tools\devflow.py test test_bids
  ```

  The filter selects module names; do not assume an arbitrary test-method name is supported.
  Use `-v` only when a sequential, detailed run is needed for debugging.
- After code integration, run the required full suite once with `tools\devflow.py test`; the
  runner already parallelizes modules and runs its timed simulation separately. Do not run
  several full suites concurrently or repeat a successful check against unchanged inputs.
  New edits, failures, explicit review requirements and commit hooks still require their checks.
- `tools\devflow.py check` is a **pre-commit check of staged changes**. It can skip checks when
  no code is staged, so its success alone does not verify unstaged changes. Do not stage unrelated
  work just to make it run. Existing commit/install/push hooks remain the canonical commit flow.
- For instruction-only changes, check imports, paths, commands and the diff; do not run the Lua
  suite unless executable behavior or a required project check is affected.
- Worker reports should contain the result, changed paths, checks and unresolved issues. Keep
  routine progress and final replies short; preserve full failure output when needed to diagnose it.

## Isolated implementation and early review

For independent changes that need separate write scopes, prepare **two fresh lanes** from the
current tracked working state (including staged and unstaged changes):

```powershell
& 'C:\FF\.tools\python\Scripts\python.exe' "$env:USERPROFILE\.claude\skills\parallel-tools\scripts\foreverflip_worktrees.py" prepare
```

Use the returned absolute lane paths and `session_file`. Worktrees live in `C:\FF\worktrees`.
Preparation keeps main's files, index and HEAD intact; it creates a private local snapshot ref.
It refuses untracked source files instead of omitting them: stage only intended inputs explicitly
before preparation. Ignored runtime/configuration files are not copied; the prepared lanes receive
their own local Claude settings. Prepare fresh lanes for a new task; never reset an occupied lane.

Assign one implementation to each lane. As soon as a lane's assigned files are stable, hand it to
the read-only reviewer while the other implementer continues. The reviewed lane stays frozen during
review. Resume the same implementer for corrections to this task; do not restart its investigation.
Keep at most three workers active in total (two implementers plus one reviewer).

Worker-local commits retain the existing pre-commit checks. Worker settings suppress installation
and push; worker hooks omit automatic publication and reject pushes. Do not change those settings,
run release commands or copy a worker's addon into the game. Only the coordinator integrates and
uses the normal main checkout's commit/install/push flow when the actual task authorizes it.

Export a completed lane using the same helper with `export --session <session_file> --lane worker-1
--output <absolute-patch-path-outside-the-lane>`. Only the lane's delta from its recorded snapshot
is exported, including binary changes; stage owned new files first so they are included. Export
does not apply or commit anything. Inspect the patch and check it with `git apply --check` in the
integration checkout before applying. Check `status --session <session_file>` for source changes
since preparation; resolve drift and overlapping edits explicitly, then run final integration checks.
