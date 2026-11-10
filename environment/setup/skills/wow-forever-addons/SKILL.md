---
name: wow-forever-addons
description: Use when developing, porting, or debugging Lua/XML addons for the locally installed World of Warcraft Forever client. Covers Forever API compatibility, TOC metadata, SavedVariables, and in-game diagnostics.
---

# WoW Forever addon development

The installed game is `C:/World of Warcraft/_forever_`, product `wowf`.
Initial inspection: client `1.60.1.70862`, addon interface `16001`.
Recheck `C:/World of Warcraft/.build.info` after updates. The separate
`C:/WOW/World of Warcraft/_retail_` installation is a different target.

Tools and source reference are in
`C:/FF`.
Read its README for commands; `.tools/installed.json` records tool versions
and the exact UI mirror commit. `references/wow-ui-source` tracks the `forever`
branch of https://github.com/Gethe/wow-ui-source, a community mirror of Blizzard UI.

Use Lua 5.1 syntax and check the actual Forever source before copying Retail
or Classic API examples. Search `Interface/AddOns/Blizzard_APIDocumentationGenerated`
and the calling UI code. Ketho editor annotations can describe other builds;
the checked-out Forever UI and client observations decide compatibility.
Do not assume `WOW_PROJECT_ID` identifies Forever; inspect the current source.
Respect protected actions, combat lockdown, taint, and secret values. Check
API availability and documented restrictions; do not attempt bypasses.

For an existing addon, inspect its TOC, load order, dependency declarations,
and SavedVariables names first. Preserve load order and filenames, especially
case for cross-platform distribution. Obtain the interface number from the
current client (`/dump select(4, GetBuildInfo())`), not a guessed expansion.

Work in a source copy. Back up the original addon and any affected saved
variables before deploying changes. Do not overwrite WTF data while WoW is
running: the client may overwrite those files on exit. Never execute saved
variables as Lua to inspect them; read them as text. Avoid exposing account or
character names in reports.

Validation: parse with the installed `lupa.lua51` compiler without executing
the chunk; run StyLua only on the changed source, then verify in the client.
An external Lua runtime has no WoW APIs and cannot prove in-game behavior.
Useful client diagnostics: `/console scriptErrors 1`, `/reload`, `/fstack`,
`/etrace`, and `/dump GetBuildInfo()`. Enable script profiling only for an
explicit performance investigation, then disable it after measuring.

The configured `wow_forever_files` MCP serves this workspace, installed addon
files, and game logs. Its write/edit/create/move tools are disabled in Codex.
Use its read tools for inspection and the normal workspace tools for changes
authorized by the user's task.
