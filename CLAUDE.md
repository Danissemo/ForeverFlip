# ForeverFlip repository instructions

ForeverFlip is a World of Warcraft auction-house addon (Lua 5.1), with a Python
desktop Sync helper, packaging tools, and simulated-client tests.

## Before editing

- Read [docs/current-work.md](docs/current-work.md) for outstanding work and
  [docs/architecture.md](docs/architecture.md) for the module layout and API boundaries.
- Use `ForeverFlip/ForeverFlip.toc` as the addon load-order source of truth.
- Keep `Core/Util.lua`'s `F.version` equal to the TOC version; do not invent
  a new release number without a matching changelog section.
- Put auction-house API calls in `Modules/AH.lua`, client-dependent wrappers in
  `Core/Compat.lua`, pure calculations in `Modules/Market.lua`, and UI in `UI/`.
- Every visible new string must have an English and Ukrainian translation.
  Do not automatically buy, bid, post or cancel without a direct player action.
- Preserve SavedVariables and apply additive, ordered migrations instead of
  editing old migrations.

## Checks

```sh
python -m pip install -r requirements-dev.txt
python tools/devflow.py test
python -m pyflakes sync tools tests
stylua --check ForeverFlip
python tools/make_tester_workbook.py --check
python tools/build.py
```

- Update tests with behavioral changes, and run them on both Linux and Windows CI.
- Run in-game verification separately: simulated client tests cannot verify
  protected actions, client secrets or real server behavior.
- Keep current documentation consistent with the code; keep historical release
  notes in `CHANGELOG.md`.
- Use a branch and pull request for review. Do not force-push, tag, release,
  install the addon into someone's game or merge without authorization.
- Local editor and assistant hook configuration is machine-specific and is
  intentionally not tracked. Optional Git hooks live in `.githooks/`;
  see [CONTRIBUTING.md](CONTRIBUTING.md) for how they work.
