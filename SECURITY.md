# Security policy

## Supported versions

| Version | Supported |
|---|---|
| The latest release | ✅ |
| The latest beta (pre-release) | ✅ while it is the newest version |
| Older versions | ❌ update first |

## What counts as a security problem

- The **ForeverFlip Sync** helper (`ForeverFlipSync.exe`, `sync/`) leaking or misusing your GitHub
  token, writing outside the game's `Interface/AddOns` and `%APPDATA%\ForeverFlipSync` folders, or
  running anything it downloads.
- The community data pipeline ([ForeverFlip-Data](https://github.com/Danissemo/ForeverFlip-Data))
  accepting a scan it should refuse, or letting an upload change other players' data.
- The addon sending your data anywhere except the addon messages you chose (guild, group, whisper,
  the realm channel), or trading without a click or key press.
- A release file that does not match the SHA-256 shown on the release page.

A bug that only gives wrong prices or deals is not a security problem: open a normal
[issue](https://github.com/Danissemo/ForeverFlip/issues/new/choose).

## Reporting

Please **do not open a public issue**. Report it privately on GitHub:
[Security → Report a vulnerability](https://github.com/Danissemo/ForeverFlip/security/advisories/new).

Include what you found, how to reproduce it and which version you used. You get an answer within a
week. Once a fix is released, the advisory is published, with credit to you if you want it.

## Good to know

- Download ForeverFlip only from the
  [releases page](https://github.com/Danissemo/ForeverFlip/releases) and compare the SHA-256 GitHub
  shows there.
- The Sync helper needs a GitHub token only to upload scans, with the scopes `gist` and
  `public_repo`. Downloading community data needs none. Never give your token to anyone.
