<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/assets/hero-dark.svg" />
    <img alt="ForeverFlip — auction house trading assistant for WoW Forever" src=".github/assets/hero-light.svg" width="900" />
  </picture>
</div>

<p align="center">
  <a href="https://github.com/Danissemo/ForeverFlip/releases/latest"><img src="https://img.shields.io/github/v/release/Danissemo/ForeverFlip?label=release&color=f5b52e" alt="Latest release" /></a>
  <a href="https://github.com/Danissemo/ForeverFlip/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/Danissemo/ForeverFlip/ci.yml?branch=main&label=tests" alt="Tests" /></a>
  <a href="https://github.com/Danissemo/ForeverFlip/releases"><img src="https://img.shields.io/github/downloads/Danissemo/ForeverFlip/total?color=2ea44f" alt="Downloads" /></a>
  <a href="https://www.wowhead.com/forever"><img src="https://img.shields.io/badge/WoW-Forever%201.60.1%20%2B%20Retail-8a2be2" alt="WoW Forever 1.60.1 and Retail" /></a>
  <a href="https://www.lua.org/manual/5.1/"><img src="https://img.shields.io/badge/Lua-5.1-000080?logo=lua&logoColor=white" alt="Lua 5.1" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Danissemo/ForeverFlip?color=blue" alt="MIT license" /></a>
</p>

<h3 align="center">
  Scan the whole auction house, find lots worth flipping, check them live and buy, post and track profit, all from one tab.
</h3>

<p align="center">
  <a href="docs/user-guide.md">User guide</a> ·
  <a href="docs/how-it-works.md">How it works</a> ·
  <a href="CHANGELOG.md">Changelog</a> ·
  <a href="https://github.com/Danissemo/ForeverFlip/releases/latest">Download</a>
</p>

> [!IMPORTANT]
> **ForeverFlip never trades on its own.** Every purchase, bid, post and cancel starts with your click
> or key press. In the background it only reads the auction house, at the pace the server allows.

> [!CAUTION]
> Download ForeverFlip only from the [Releases](https://github.com/Danissemo/ForeverFlip/releases) page
> of this repository. GitHub shows the SHA-256 of every file on the release page; compare it with
> `certutil -hashfile ForeverFlip-<version>.zip SHA256` (Windows) or `sha256sum` (Linux, macOS).

## 💡 Why ForeverFlip

- **Free and on its own.** No subscription, no desktop app required, no other addon needed.
- **Tells you what a deal is worth before you buy.** Profit after the auction cut and deposits,
  how many sell a day (**Est./day**) and the chance it sells at your price (**Sure**), learned from
  the sales on your own realm.
- **Checks every deal live.** Nothing can be bought from an old scan: an exact search confirms the
  price first.
- **Gets better with every player.** Scans shared through [ForeverFlip Sync](docs/community.md) fill
  in the prices of items you have not seen sell yet; the Share tab shows how many players share
  scans of your auction house.
- **Shows what really paid.** **Analytics → By strategy** books every sale against what it cost.

## 📸 Screenshots

<p align="center">
  <img src=".github/assets/screenshots/deals.png" width="800"
       alt="Deals → Resale: buy price, sell price, profit, sales a day and the chance to sell for each deal" />
  <br /><sub><b>Deals.</b> What each lot costs, what it sells for, the profit after the cut, how many sell a day and how sure the sale is.</sub>
</p>

<table>
  <tr>
    <td width="50%"><img src=".github/assets/screenshots/tooltip.png" alt="Item tooltip with prices, demand, the best time to buy and what you hold" /><br />
      <sub><b>Tooltip.</b> Vendor and auction prices, sales a day, the best time to buy and what you paid.</sub></td>
    <td width="50%"><img src=".github/assets/screenshots/professions.png" alt="Professions → Crafting: materials, product, profit per recipe" /><br />
      <sub><b>Professions.</b> Each recipe you know: materials against the product, and where to sell it.</sub></td>
  </tr>
  <tr>
    <td><img src=".github/assets/screenshots/selling.png" alt="Selling → My items: best place to sell each item from the bags" /><br />
      <sub><b>Selling.</b> Auction or vendor for each item in the bags, with price, quantity and duration.</sub></td>
    <td><img src=".github/assets/screenshots/settings.png" alt="Settings → General: minimum profit, money limits, market reset and posting" /><br />
      <sub><b>Settings.</b> Profit thresholds and money limits, or one click: Careful, Balanced, Aggressive.</sub></td>
  </tr>
  <tr>
    <td colspan="2" align="center"><img src=".github/assets/screenshots/sync-helper.png" width="380" alt="ForeverFlip Sync window: game, sharing, updater and community prices" /><br />
      <sub><b>ForeverFlip Sync</b> (optional). Community prices, shared scans and automatic updates.</sub></td>
  </tr>
</table>

## ✨ Feature highlights

**Finding deals**

- **Full scans:** every auction of the house, often more than 200 000, read in small portions so
  the game never freezes. One per 15 minutes, optionally automatic while the auction house is open, and scans
  of other addons are read too.
- **Fast sniper:** browse rounds read the lowest price of every item in seconds; hot items and your
  shopping list are re-read 100 at a time; every suspicious price is checked at once.
- **Vendor deals:** lots below what a vendor pays. Buy, sell to any merchant, keep the difference,
  with no market risk. The real price a merchant pays is learned from the buyback list, because
  WoW Forever's server pays less than the game's item data for some items.
- **Resale:** lots far below the next seller, for items that really sell at the resale price.
  - Sales are tracked auction by auction.
  - Profit counts the auction cut and the deposit risk.
- **Shopping list:** your items and your price; cheaper lots become deals.
- **Disenchant deals** for enchanters.
- **Bids** on auctions about to end.
- **Crafting:** what is worth crafting, priced from your recipes, auction and merchant prices.
- **Live check:** nothing can be bought until an exact search confirms the deal in the last 5 minutes.
- **Alerts:** a sound, a screen message and a green mark in the game's Buy tab.

**Selling**

- **Posting rules:** undercut by a step or a percent, minimum and maximum price, units to keep, hold
  below the minimum. Never below your break-even.
- **Post next bought / Post all:** all available units across bag stacks, one click per item, at the right price and the selected duration
  (24 hours by default, or **Auto**).
- **Cancel undercut:** cancels undercut auctions one by one, only when the repost still pays.
- **One-click chores:** take all auction mail, sell all vendor deals at a merchant.

**Accounting and analytics**

- **Books from auction mail:** the real sale amounts, the learned cut, and the sale rate of every item.
- **Analytics:**
  - profit per day, return and hit rate;
  - best and worst items;
  - gold and stock of all your characters;
  - market lists and the time-of-week price pattern.
- **History:** a 14-day price chart for any item (right-click), and tooltip prices with their age.
- **Shared scans:** pool full scans with every ForeverFlip user of your realm over a hidden channel,
  with your guild, group or friends, or with the whole community through GitHub ([ForeverFlip Sync](docs/community.md)); full scans are archived unchanged
  in [ForeverFlip-Data](https://github.com/Danissemo/ForeverFlip-Data).
- **Export:** the journal as CSV.
- **Safety:** a spending limit per visit, cheap lots left for others, and tooltip advice: vendor,
  disenchant or auction house.
- **Comfort:** key bindings (including "buy the next best deal"), Careful / Balanced / Aggressive
  presets, `ForeverFlipAPI` for other addons, English and Ukrainian.

## 📦 Installation

1. Download `ForeverFlip-<version>.zip` from the [latest release](https://github.com/Danissemo/ForeverFlip/releases/latest).
2. Unpack it into `Interface/AddOns/` of your WoW Forever client, so that the file
   `Interface/AddOns/ForeverFlip/ForeverFlip.toc` exists.
3. Restart the game or type `/reload`, and make sure ForeverFlip is enabled in the AddOns list.
4. Optional:
   - bind keys under **Key Bindings → AddOns → ForeverFlip**;
   - open each profession window once, so the Crafting page knows your recipes.

> [!NOTE]
> **Current stable release: [3.2.0](https://github.com/Danissemo/ForeverFlip/releases/tag/v3.2.0)** (18 November 2026).
> **Analytics → By strategy** shows what Resale, Market reset, Bids and To vendor really earned;
> **Disenchant bought** disenchants your purchases one click each; Est./day no longer reads 0 for
> items that sell, and leans on similar items while their own sales are few. ForeverFlip Sync starts
> with Windows in the tray and shares Retail scans per region. Check all, Market reset, posting on
> Retail and two dozen other things are fixed.
> See the [3.2.0 changelog](CHANGELOG.md#320---2026-11-18).

> [!TIP]
> To update, replace the `ForeverFlip` folder, or let the
> [ForeverFlip Sync helper](docs/community.md#addon-updates-and-beta-testing) do it: it installs new
> releases by itself, and new betas too if you tick **Beta versions**. Your data lives in
> `WTF/Account/<ACCOUNT>/SavedVariables/ForeverFlip.lua` and is kept.

| Requirement | |
|---|---|
| Game | WoW Forever 1.60.1 (Interface `16001`); Retail 12.0.5 (Interface `120105`) is capability-adapted, with in-game verification still recommended |
| Dependencies | None for the addon. The optional ForeverFlip Sync desktop helper is Windows-oriented and has its own release/build version |
| Optional | [LibAHTab](https://www.curseforge.com/wow/addons/libahtab) puts the tab next to other addon tabs. [auxForever](https://github.com/TylerHampton/aux-forever) prices fill in materials ForeverFlip has not seen yet |
| Works next to | Auctionator, TradeSkillMaster and other auction addons |

## 🚀 Quick start

1. Open the auction house and click the **ForeverFlip** tab.
2. Click **Full scan** and let the progress bar finish. Automatic scans and the sniper can be enabled in Settings.
3. Open **Deals → To vendor** and click a deal. It is checked live; when it says **ready**,
   click **Buy**. For stackable goods, also click **Confirm purchase** once the game quotes the price.
4. Sell vendor deals, and everything else a merchant pays the most for, at any merchant with
   **Sell to vendor**. Post resale purchases with
   **Selling → My items → Post next bought**.

Resale deals need sales data, so they start to appear after two or three full scans (30–45 minutes
with the auction house open).

## ⌨️ Commands and key bindings

| Command | Action |
|---|---|
| `/ff` | Version and a short hint |
| `/ff diag` | Statistics of the last full scan |
| `/ff rescan` | Allow a full scan right away after the server did not answer |
| `/ff export` | The journal as CSV, ready to copy |
| `/ff trace` | Show the recent trace and slow-operation diagnostics |
| `/ff dev` | Toggle developer trace mode (off by default) |
| `/ff lang en` · `/ff lang uk` | Switch the language (after `/reload`) |

The Key Bindings window has five bindings (also set on **Settings → Key bindings**):

- Buy or confirm the selected deal
- Buy the next best deal (each press: check, buy, confirm)
- Post next bought (then Post all)
- Cancel the next undercut auction
- Full scan

## 📚 Documentation

| Document | What is inside |
|---|---|
| [User guide](docs/user-guide.md) | Every page, button, status, setting and message |
| [How it works](docs/how-it-works.md) | Scans, the sniper, sales tracking, deal maths, limits and safety rules |
| [Architecture](docs/architecture.md) | Modules, load order, events and data flow |
| [Saved data](docs/saved-data.md) | Layout of the `ForeverFlipData` SavedVariables file |
| [Community scans](docs/community.md) | The ForeverFlip Sync helper and the community data repository |
| [Promotion](docs/promotion.md) | Addon-site uploads, release posts, the shot list and the public numbers |
| [API](docs/api.md) | `ForeverFlipAPI` for other addons |
| [Testing](docs/testing.md) | Archived Ukrainian 2.3.0-beta.1 manual checks and the corresponding [Excel worksheet](docs/tester-checklist.uk.xlsx); see the current release matrix below |
| [3.1.0 validation](docs/release-3.1.0-validation.md) | Release-specific regression and in-game verification matrix |

## ❓ Questions and answers

### There are no deals after a scan

- Vendor deals depend on the market at that moment; often there are none.
- Resale needs sales data from two or three scans.
- Check the minimums in **Settings**, or try the **Aggressive** preset.
- `/ff diag` shows how many items are still collecting data.

### The Buy button stays grey

A deal can be bought only when it is **ready**, checked in the last 5 minutes, while no other search
or purchase runs. Click the deal to check it again.

### The scan does not start

The server allows one full scan per 15 minutes **per account**, and another addon may have used the
window. Wait for the countdown on the button, or use `/ff rescan` if the server did not answer.

### Is the profit guaranteed?

No. Other players see the same lots, and sales are an estimate. Several safeguards limit the risk:

- each resale buys at most about one day of sales;
- the resale price is capped at what real sales reached;
- items whose stock does not sell, or keeps coming back unsold, are trusted less;
- a purchase that fails because someone was faster costs nothing.

### What has not been confirmed on WoW Forever yet?

These are taken from Classic and checked in a simulated client only:

- the 15% cut of neutral auction houses, which is corrected from your sale invoices;
- the disenchanting table.

The [in-game checklist](docs/testing.md#in-game-checklist) lists what to try.

### Can someone spoil the community prices with a fake scan?

Not easily. Anyone with a GitHub account can share scans, but:

- every scan is sealed by the addon while it reads it, so a scan edited afterwards is refused;
- a scan reaches the community prices only when another player's scan confirms it, and only with the
  items whose prices agree;
- deals always come from your own scans and live checks.

See [Safeguards](docs/community.md#safeguards).

### How do I report a bug?

1. Type `/reload`.
2. Copy the `errors` section of `WTF/Account/<ACCOUNT>/SavedVariables/ForeverFlip.lua`, plus the
   output of `/ff diag`.
3. Paste both into a [bug report](https://github.com/Danissemo/ForeverFlip/issues/new/choose).

Questions go to [Discussions](https://github.com/Danissemo/ForeverFlip/discussions). A security
problem is reported privately: see the [security policy](SECURITY.md).

## 🛠️ Local development

You need Python 3.12 and [StyLua](https://github.com/JohnnyMorganz/StyLua). The tests run the real
addon code in Lua 5.1 through [lupa](https://github.com/scoder/lupa), against a simulated WoW client
and auction house.

```bash
python -m pip install -r requirements-dev.txt
python tools/devflow.py test          # one process per module; `test <word>` narrows it
stylua --check ForeverFlip
python -m pyflakes sync tools tests
python tools/build.py
python tools/savedata.py backup       # copy the saved data out of the game (`list`, `restore <name>`)
```

`tools/build.py` checks the TOC and the version, runs the tests, writes `dist/ForeverFlip-<version>.zip`
and prints its SHA-256.

## 🤝 Contributing

Bug reports, observations of how the WoW Forever server behaves, ideas and pull requests are welcome.

- [Contributing guide](CONTRIBUTING.md): the code style, tests, the local flow and releases.
- [Code of conduct](CODE_OF_CONDUCT.md): how we talk to each other.
- [Security policy](SECURITY.md): how to report a security problem privately.
- [Discussions](https://github.com/Danissemo/ForeverFlip/discussions): questions, ideas and beta
  feedback that is not a bug.

## 📄 License

ForeverFlip is released under the [MIT license](LICENSE).

<sub>World of Warcraft is a trademark of Blizzard Entertainment. ForeverFlip is a fan-made addon and
is not affiliated with or endorsed by Blizzard Entertainment.</sub>
