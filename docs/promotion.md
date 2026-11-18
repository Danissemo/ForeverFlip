# Promotion

How ForeverFlip reaches players: where it is listed, what is posted with each release, and how
to tell whether it works. The addon sends nothing anywhere; every number here is public.

## Addon sites (one-time setup, by the maintainer)

Every tagged release uploads to CurseForge, Wago and WoWInterface once the site is set up
(`.github/workflows/release.yml`, the BigWigs packager; CI packages it without uploading on every
push). For each site:

1. Create the project by hand with the description from the README's first screen, the logo
   (`.github/assets/logo.svg`, `social-preview.png` as the banner) and the screenshots of the shot list below.
2. GitHub → **Settings → Secrets and variables → Actions**:

   | Site        | Secret (token)    | Variable (project ID) | Where to get them                                  |
   |-------------|-------------------|-----------------------|----------------------------------------------------|
   | CurseForge  | `CF_API_KEY`      | `CF_PROJECT_ID`       | authors.curseforge.com → API tokens; the project's About box |
   | Wago        | `WAGO_API_TOKEN`  | `WAGO_PROJECT_ID`     | addons.wago.io → account → API keys; the project URL |
   | WoWInterface| `WOWI_API_TOKEN`  | `WOWI_PROJECT_ID`     | wowinterface.com → Author Portal → API tokens; the addon ID |

Where it stands (18 November 2026): all three projects exist, the first two waiting for moderators:
CurseForge [1814511](https://authors.curseforge.com/#/projects/1814511) (`CF_PROJECT_ID`),
WoWInterface 27314 (`WOWI_PROJECT_ID`) and Wago `qGYBxzNg` (`WAGO_PROJECT_ID`). 3.3.0 went to
all three through their upload forms. Two tokens are refused by their APIs: CurseForge's
(`Error fetching game version info`) and Wago's (`401 Unauthenticated`). Make new ones and replace
`CF_API_KEY` and `WAGO_API_TOKEN` before the next release.

A release reads the project IDs when its tag is pushed. A site set up later gets that version
through **Actions → Upload to the addon sites → Run workflow** (`.github/workflows/catalogs.yml`),
which sends the zip from the GitHub release:

```powershell
gh workflow run catalogs.yml -f version=3.3.0 -f sites="wago"
```

A site without its token or ID is skipped, not failed. The packager maps `## Interface: 16001` to
the *Forever* game version and `120105` to Retail; WoWInterface has no Forever version and gets
the Retail one only.

## With every release

```powershell
C:\FF\.tools\python\Scripts\python.exe tools\promo.py post --version 3.2.0 --channel reddit
C:\FF\.tools\python\Scripts\python.exe tools\promo.py post --version 3.2.0 --channel discord
C:\FF\.tools\python\Scripts\python.exe tools\promo.py post --version 3.2.0 --channel telegram
```

The drafts come from the changelog's bold headlines; read and edit before posting by hand. The
Telegram draft frames them in Ukrainian, the headlines stay English until translated.

| Channel | When | Note |
|---------|------|------|
| WoW Forever Discord (addons channel) | every stable release | the Discord draft; one post, no repeats |
| r/woweconomy | major releases only (x.y.0 with a new feature) | the Reddit draft; answer comments the same day |
| Ukrainian WoW Telegram/Discord groups | every stable release | the Telegram draft; the translation is the hook |
| GitHub Discussions → Announcements | every release | the full release notes |
| YouTube/Twitch gold-making creators | once, then on big features | the letter below |

## Letter to creators

> Subject: A free flipping addon for WoW Forever, if it fits a video
>
> Hi! I make ForeverFlip, a free and open-source auction-house addon for WoW Forever. Before you
> buy it shows what a flip should earn after the cut, how many sell a day and how likely it sells
> at that price, and it checks the live price before every purchase. Players who run its helper
> share their scans, so prices are there even on a quiet server.
>
> If it suits a gold-making video, I'm glad to answer questions or set up a test with you.
> Download: https://github.com/Danissemo/ForeverFlip/releases/latest

Send it personally, one creator at a time, and only to those who cover WoW Forever or flipping.

## Shot list (recorded in game)

Short, without other addons' frames, UI scale 1. In `.github/assets/screenshots/` and the README:

- [x] Deals → Resale (`deals.png`), Professions → Crafting, Selling → My items, Settings → General,
      the item tooltip, the Sync helper window.

Still to record (GIFs under 5 MB so GitHub shows them):

1. GIF, 10 s: a scan finishing and the Deals tab filling, sorted by Profit.
2. GIF, 8 s: **Check all** striking out a stale deal, then a buy with the live check.
3. Screenshot: Analytics → By strategy after a week of play.
4. Screenshot: Settings → Sharing with "N players share scans of this house" (after the next
   release).
5. Screenshot: Professions with a profitable recipe on top, and Selling with a Sure above 0%: the
   current ones show mostly losses and 0%, honest but not the best first impression.

GIF 1 goes to the top of the README in place of `deals.png`. The addon sites take the PNGs as
they are.

## Measuring

```powershell
C:\FF\.tools\python\Scripts\python.exe tools\promo.py metrics
```

Downloads per release (GitHub) and, per auction house, how many players' scans the community
prices rest on. Note them in a line after each post: a post that moved neither number is not
worth repeating. The addon sites show their own download counts once uploads run.
