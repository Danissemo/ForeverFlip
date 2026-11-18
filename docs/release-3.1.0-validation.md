# ForeverFlip 3.1.0 — release validation matrix

**Baseline:** [v3.1.0](https://github.com/Danissemo/ForeverFlip/releases/tag/v3.1.0),
published 17 November 2026. Compare the working copy with the tagged release before using
this checklist. The addon declares `3.1.0` in `ForeverFlip/ForeverFlip.toc` and
`ForeverFlip/Core/Util.lua`. The 3.1.0 helper executable still reports `2.1.0-beta.2`; from the
next release `sync/foreverflip_sync.py` carries the release version too.

This checklist is a **plan**, not a test report. No live WoW Forever or Retail session was
performed as part of this documentation pass. The [historical Ukrainian checklist](testing.md)
and its Excel workbook contain the 2.3.0-beta.1 scenarios and are labelled with that version;
none of their procedures was verified for 3.1.0.

## Automated release gates

Run from the repository root, in Python 3.12:

```sh
python -m pip install -r requirements-dev.txt
python tools/devflow.py test
python -m pyflakes sync tools tests
stylua --check ForeverFlip
python tools/make_tester_workbook.py --check
python tools/build.py
```

The workbook command checks that the **archived beta** worksheet matches its archived cards
and the current TOC version; if it fails, regenerate the workbook and review the version/wording
before a future release. These checks must pass on Linux in GitHub Actions, too. The release
workflow additionally builds the Windows Sync executable and verifies the tag matches the TOC.
Use the [CI workflow](https://github.com/Danissemo/ForeverFlip/actions/workflows/ci.yml)
and [release workflow](https://github.com/Danissemo/ForeverFlip/actions/workflows/release.yml)
for actual run results.

## In-game regression checks (not yet attested here)

| ID | Area | Manual verification | Pass condition |
|---|---|---|---|
| R31-01 | Version and install | Install the 3.1.0 ZIP on a clean WoW Forever 1.60.1 profile | Enabled addon, `/ff` reports 3.1.0, no Lua startup error |
| R31-02 | Separate markets | Open an Alliance, Horde and neutral house, if accessible | Correct scope/header and separate prices; neutral auction cut verified from invoices |
| R31-03 | Retail capability | Load on a Retail 12.0.5 environment with restricted/secret tooltip values | No forbidden reads or Lua failures; shared Server house label |
| R31-04 | Helper notices | Run current release Sync with addon older than the latest available | Correct channel/version hint in game after shared-data refresh and reload; no false newer-version warning |
| R31-05 | Tracing | Enable DEV with `/ff dev`, use UI and search, then `/ff trace` | Diagnostic records for actions, queries and slow work; off by default; bounded storage |
| R31-06 | Full scan | Scan auction inventory with several item-key variants | Completes without UI freeze; figures are internally consistent |
| R31-07 | Quick scan + sniper | Enable sniper, trigger Quick scan during full-scan cooldown | Quick scan performs its own round and sniper resumes after |
| R31-08 | Check all ordering | Sort deals, bags and own auctions; trigger Check all | Processes visible top-to-bottom order; silent queries eventually clear |
| R31-09 | Gear versions | Check auction price for an item with many known endings | Batch query avoids repeated stalls; no repeated work on answered versions |
| R31-10 | Purchases | Live-verify cheap commodity and item deals, then click Buy/Confirm | No purchase without direct hardware input and current quote |
| R31-11 | Selling | Post, cancel undercut and inspect automatic durations | Respect price floor, deposit estimate, sorted order and per-click restrictions |
| R31-12 | Merchant | View large gold values in merchant offers | Prices and projected profits remain on distinct readable lines |
| R31-13 | Tooltip | Inspect items with long descriptions and multiple coin prices | Header/footer end at same measured width without excess extension |
| R31-14 | Locales | Repeat key screens in English and Ukrainian at 90–110% scale | No clipped headers, overlapping values or missing translations |
| R31-15 | Saved data | Upgrade a copy of prior saved variables, then reload | Preserves journal, positions and settings; no unexpected resets |
| R31-16 | Sync profiles | Test several WoW Forever installs on Windows; attempt unsupported game folders | Correct profile isolation, no cross-profile writes, backups on update |
| R31-17 | Community scans | Upload and download a signed scan with test credentials and data | Seal and realm/house checks respected; upload status distinct from community download |
| R31-18 | Regression | Recheck known problem: `That action is currently restricted` when posting outside combat | Record actual server/client behavior; do not report fixed without a successful repro-and-retest |

## Documentation and maintenance consistency

- Keep `README.md`, `CHANGELOG.md`, release notes, the TOC and runtime version aligned.
- Update `docs/current-work.md` as **current status**, and label dated plans/reviews historical.
- Keep `docs/architecture.md` authoritative for load order and module paths.
- Review `docs/how-it-works.md`, `docs/analytics-model.md` and `docs/saved-data.md`
  when economic formulas or persisted fields change; update the Ukrainian formulas reference
  from the *actual code* rather than merely changing its old version label.
- Regenerate `docs/tester-checklist.uk.xlsx` with `tools/make_tester_workbook.py`
  whenever the source test cards are updated; do not silently relabel historical test evidence.
- Keep `sync/assets/` binaries and screenshots untouched unless there is a source-based
  regeneration and visual verification. Ignore generated `__pycache__`, `*.pyc` and build output.

## Results log

| Check | Result | Evidence / issues |
|---|---|---|
| Current source manifest and published release metadata | Inspected | v3.1.0 tag; main-tree source inventory |
| Baseline Windows/Linux CI on main after repository cleanup | Passed | [GitHub Actions run 44144665994](https://github.com/Danissemo/ForeverFlip/actions/runs/44144665994) (17 November 2026) |
| Tests for later changes | Not attested by the baseline run | Check the CI run for each new PR commit before merging |
| Manual WoW Forever client validation | Not run | Needs game-side tester |
| Manual Retail compatibility validation | Not run | Needs Retail tester |
| Helper Windows executable build and GUI review | Not run | Verify Windows release CI |
