# Current development status

Updated: 17 November 2026. The latest published stable release is
[ForeverFlip 3.1.0](https://github.com/Danissemo/ForeverFlip/releases/tag/v3.1.0).
The TOC and `Core/Util.lua` both declare `3.1.0`; the desktop Sync helper has a
separate internal version identifier. Later changes to `main` fixed the release process
without changing the addon release number.

## Current priorities

- Run the [3.1.0 release verification checklist](release-3.1.0-validation.md)
  in WoW Forever 1.60.1 (Alliance, Horde, neutral houses, English and Ukrainian).
- Verify Retail 12.x capability-dependent features in a live client before claiming
  comprehensive compatibility.
- Test purchase, posting, cancellation, Quick scan + sniper, gear-key searches, tooltips,
  saved-data migration, and the Windows Sync updater in game.
- Reproduce or resolve the earlier report of `That action is currently restricted`
  while posting outside combat; simulated tests alone do not establish a fix.
- Keep CI passing on Windows and Linux before merging or tagging another release.
- Check the `[Unreleased]` ignore-list split in game: after the first login (data migration 5),
  Ignore item lists only ignored items, and the blocked-action records stay in `/ff diag`.

## Source of truth

- [CHANGELOG.md](../CHANGELOG.md): shipped behavior and full release history.
- [Architecture](architecture.md): current modules, game API boundaries and runtime flow.
- [How it works](how-it-works.md): formulas and business rules.
- [Testing](testing.md): historical Ukrainian 2.3.0-beta.1 manual checklist
  and workbook; their version header is **not** evidence of 3.1.0 in-game testing.
- [Release verification](release-3.1.0-validation.md): remaining checks for 3.1.0.

Completed development notes and superseded proposals are available in Git history rather
than maintained as live work status.
