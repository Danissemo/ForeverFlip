# Beta 5 release plan

**Goal:** Publish every completed change since beta.4 as 1.2.0-beta.5, with addon ZIP and Windows Sync helper.

**Scope:** Existing main HEAD plus release metadata and documentation; no new runtime features.

- [x] Update TOC and Util version, promote Unreleased notes and update the current beta checklist.
- [x] Run Lua formatting and the complete automated suite; package the addon and build the asset-based helper with frozen-runtime verification.
- [ ] Review the diff, verify author identity, commit and push main and the new beta tag.
- [ ] Verify GitHub CI, pre-release status and both downloadable release assets.

Keep previous release notes and relevant regression tests. Do not mark in-game checks passed without fresh client observations. Preserve all work already committed on main.
