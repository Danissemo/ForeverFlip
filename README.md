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
  <img src="https://img.shields.io/badge/WoW%20Forever-1.60.1-8a2be2" alt="WoW Forever 1.60.1" />
  <img src="https://img.shields.io/badge/Lua-5.1-000080?logo=lua&logoColor=white" alt="Lua 5.1" />
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
> of this repository. Each archive comes with its SHA-256 checksum.

## ✨ Feature highlights

**Finding deals**

- **Full scans:** every auction of the house, often more than 200 000, read in small portions so
  the game never freezes. One per 15 minutes, automatic while the auction house is open, and scans
  of other addons are read too.
- **Fast sniper:** browse rounds read the lowest price of every item in seconds; hot items and your
  shopping list are re-read 100 at a time; every suspicious price is checked at once.
- **Vendor deals:** lots below what a vendor pays. Buy, sell to any merchant, keep the difference,
  with no market risk.
- **Resale:** lots far below the next seller, for items that really sell at the resale price.
  - Sales are tracked auction by auction.
  - Profit counts the auction cut and the deposit risk.
- **Shopping list:** your items and your price; cheaper lots become deals.
- **Disenchant deals** for enchanters.
- **Bids** on auctions about to end.
- **Crafting:** what is worth crafting, priced from your recipes, auction and merchant prices.
- **Live check:** nothing can be bought until an exact search confirms the deal in the last 45 seconds.
- **Alerts:** a sound, a screen message and a green mark in the game's Buy tab.

**Selling**

- **Posting rules:** undercut by a step or a percent, minimum and maximum price, units to keep, hold
  below the minimum. Never below your break-even.
- **Post next bought / Post all:** one click per item, at the right price and an automatic duration.
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
- **Shared scans:** pool full scans with your guild, group or friends in game, or with the whole
  community through GitHub ([ForeverFlip Sync](docs/community.md)); full scans are archived unchanged
  in [ForeverFlip-Data](https://github.com/Danissemo/ForeverFlip-Data).
- **Export:** the journal as CSV.
- **Comfort:** key bindings, Careful / Balanced / Aggressive presets, `ForeverFlipAPI` for other
  addons, English and Ukrainian.

## 📦 Installation

1. Download `ForeverFlip-<version>.zip` from the [latest release](https://github.com/Danissemo/ForeverFlip/releases/latest).
2. Unpack it into `Interface/AddOns/` of your WoW Forever client, so that the file
   `Interface/AddOns/ForeverFlip/ForeverFlip.toc` exists.
3. Restart the game or type `/reload`, and make sure ForeverFlip is enabled in the AddOns list.
4. Optional:
   - bind keys under **Key Bindings → AddOns → ForeverFlip**;
   - open each profession window once, so the Crafting page knows your recipes.

> [!TIP]
> To update, replace the `ForeverFlip` folder. Your data lives in
> `WTF/Account/<ACCOUNT>/SavedVariables/ForeverFlip.lua` and is kept.

| Requirement | |
|---|---|
| Game | WoW Forever, client 1.60.1 (Interface `16001`) |
| Dependencies | None |
| Optional | [LibAHTab](https://www.curseforge.com/wow/addons/libahtab) puts the tab next to other addon tabs. [auxForever](https://github.com/TylerHampton/aux-forever) prices fill in materials ForeverFlip has not seen yet |
| Works next to | Auctionator, TradeSkillMaster and other auction addons |

## 🚀 Quick start

1. Open the auction house and click the **ForeverFlip** tab.
2. Click **Full scan**, or wait for the automatic one, and let the progress bar finish.
3. Open **Sell to vendor (no risk)** and click a deal. It is checked live; when it says **ready**,
   click **Buy**. For stackable goods, also click **Confirm purchase** once the game quotes the price.
4. Sell vendor deals at any merchant with **Sell vendor deals**. Post resale purchases with
   **Sell my items → Post next bought**.

Resale deals need sales data, so they start to appear after two or three full scans (30–45 minutes
with the auction house open).

## ⌨️ Commands and key bindings

| Command | Action |
|---|---|
| `/ff` | Version and a short hint |
| `/ff diag` | Statistics of the last full scan |
| `/ff rescan` | Allow a full scan right away after the server did not answer |
| `/ff export` | The journal as CSV, ready to copy |
| `/ff lang en` · `/ff lang uk` | Switch the language (after `/reload`) |

The Key Bindings window has four bindings:

- Buy or confirm the selected deal
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
| [API](docs/api.md) | `ForeverFlipAPI` for other addons |
| [Testing](docs/testing.md) | Automated tests and the in-game checklist |

## ❓ Questions and answers

### There are no deals after a scan

- Vendor deals depend on the market at that moment; often there are none.
- Resale needs sales data from two or three scans.
- Check the minimums in **Settings**, or try the **Aggressive** preset.
- `/ff diag` shows how many items are still collecting data.

### The Buy button stays grey

A deal can be bought only when it is **ready**, checked in the last 45 seconds, while no other search
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

### How do I report a bug?

1. Type `/reload`.
2. Copy the `errors` section of `WTF/Account/<ACCOUNT>/SavedVariables/ForeverFlip.lua`, plus the
   output of `/ff diag`.
3. Paste both into a [new issue](https://github.com/Danissemo/ForeverFlip/issues/new/choose).

## 🛠️ Local development

You need Python 3.12 and [StyLua](https://github.com/JohnnyMorganz/StyLua). The tests run the real
addon code in Lua 5.1 through [lupa](https://github.com/scoder/lupa), against a simulated WoW client
and auction house.

```bash
python -m pip install -r requirements-dev.txt
python -m unittest discover -s tests -p "test_*.py"
stylua --check ForeverFlip
python tools/build.py
```

`tools/build.py` checks the TOC and the version, runs the tests and writes `dist/ForeverFlip-<version>.zip`
with its checksum.

## 🤝 Contributing

Bug reports, observations of how the WoW Forever server behaves, and pull requests are welcome. Read
the [contributing guide](CONTRIBUTING.md) for the code style, tests and the release process.

## 📄 License

ForeverFlip is released under the [MIT license](LICENSE).

<sub>World of Warcraft is a trademark of Blizzard Entertainment. ForeverFlip is a fan-made addon and
is not affiliated with or endorsed by Blizzard Entertainment.</sub>
