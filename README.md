# ForeverFlip

**An auction house trading assistant for WoW Forever.** ForeverFlip reads the whole auction house,
finds lots you can profit from, checks each one against the live listings right before you buy, and
then helps you post, track and cash out what you bought.

[User guide](docs/user-guide.md) · [How it works](docs/how-it-works.md) · [Changelog](CHANGELOG.md)

---

## Features

**Finding deals**

- **Full auction house scan.** Reads every auction the server returns (often more than 200 000)
  without freezing the game, at most once per 15 minutes. It can rescan automatically while the
  auction house is open, and it also reads full scans that other addons request.
- **Fast sniper.** Between full scans, browse rounds read the lowest price of every item on the
  auction house in seconds. Hot items and the shopping list are re-read in batches of 100. Every
  cheap price is checked with an exact search at once.
- **Vendor deals.** Lots priced below what a vendor pays for the item. You buy them, sell them to any
  vendor and keep the difference, with no market risk.
- **Resale deals.** Lots priced well below the next seller, for items that really sell at the resale
  price.
  - **Sales tracked auction by auction:** partial buys count as sales; expired and cancelled lots do
    not.
  - **Resale price cap:** at what real sales reached.
  - **Profit** includes the auction cut and the deposit you lose on unsold lots.
- **Shopping list.** Items with the most you pay for one; cheaper lots become Shopping deals.
- **Disenchant deals** for enchanters: green and blue gear below the value of its materials.
- **Bids** on auctions ending within 30 minutes whose next bid is well below the item's worth.
- **Crafting.** Prices every recipe you know with auction and merchant prices, and shows what is
  worth crafting.
- **Live check before every purchase.** A deal is only a lead until an exact search confirms it with
  the current listings. A check is valid for 45 seconds. Your own searches in the game's Buy tab count
  as checks too.
- **Alerts.** A sound, a screen message and a mark in the game's Buy tab when a deal can be bought.

**Selling**

- **Posting rules:** undercut by a step or a percent, a minimum and maximum price, units to keep, hold
  below the minimum. Posts never go below your break-even.
- **Post next bought / Post all:** one click per item, at the right price and an automatic duration.
- **Cancel undercut:** cancels undercut auctions one by one, only when the repost still pays.
- **Take auction mail** in one click, and **Sell vendor deals** at any merchant in one click.
- **Merchant to auction house offers:** items a merchant sells for less than they fetch on the
  auction house.

**Accounting and analytics**

- **Journal, stock at average cost, profit per item, days to sell.**
- **Sale invoices** from auction mail book the exact amounts, also for items posted with the game's
  own Sell tab. Expired and cancelled mails give the sale rate of each item.
- **The cut is learned from invoices**, and neutral auction houses get their own 15% cut and their
  own history.
- **Analytics:** profit per day, return, hit rate, best and worst items, gold and stock of all
  characters, market lists (below usual, sells most, falling, rising, cheap now, sell now), and the
  time-of-week price pattern.
- **14-day price history** chart for any item (right-click), and price lines with their age in item
  tooltips.
- **CSV export** of the journal.

**Comfort**

- Key bindings for Buy/Confirm, Post, Cancel undercut and Full scan.
- Careful, Balanced and Aggressive presets.
- `ForeverFlipAPI` for other addons; auxForever prices as a fallback.
- English and Ukrainian.

ForeverFlip never buys, posts or cancels anything on its own. Every trade starts with your click.

## Requirements

| | |
|---|---|
| Game | WoW Forever, client 1.60.1 (Interface `16001`) |
| Dependencies | None. [LibAHTab](https://www.curseforge.com/wow/addons/libahtab) is used if installed, so the ForeverFlip tab sits next to other addon tabs. [auxForever](https://github.com/TylerHampton/aux-forever) prices are used if installed |
| Works next to | Auctionator, TradeSkillMaster and other auction addons |

## Installation

1. Download `ForeverFlip-<version>.zip` from the [latest release](../../releases/latest).
2. Unpack it into `World of Warcraft/<client folder>/Interface/AddOns/`. You should end up with
   `Interface/AddOns/ForeverFlip/ForeverFlip.toc`.
3. Restart the game or type `/reload`. Make sure ForeverFlip is enabled in the AddOns list on the
   character select screen.
4. Optional: bind keys under **Key Bindings → AddOns → ForeverFlip**, and open your profession windows
   once so the Crafting page knows your recipes.

To update, delete the old `ForeverFlip` folder and unpack the new one. Your data is kept: it is stored
in `WTF/Account/<ACCOUNT>/SavedVariables/ForeverFlip.lua`, not in the addon folder.

## Quick start

1. Open the auction house and click the **ForeverFlip** tab at the bottom.
2. Click **Full scan** (or wait for the automatic scan) and let the progress bar finish.
3. Open **Sell to vendor (no risk)**. Click a deal: it is checked live and, if it still holds, its
   status turns **ready**.
4. Click **Buy**. For stackable goods, also click **Confirm purchase** once the game quotes the price.
5. Sell vendor deals at any merchant with **Sell vendor deals**. List resale purchases from
   **Sell my items → Post next bought**.

Resale deals need sales data: they start to appear after two or three full scans (30 to 45 minutes
with the auction house open).

The [user guide](docs/user-guide.md) explains every page, button, status and setting.

## Slash commands

| Command | Action |
|---|---|
| `/ff` or `/foreverflip` | Shows the version and a short hint |
| `/ff diag` | Prints statistics of the last full scan (auctions read, skipped, deals found) |
| `/ff rescan` | Allows a full scan right away after the server did not answer the last one |
| `/ff export` | Opens the journal as CSV to copy into a spreadsheet |
| `/ff lang en` / `/ff lang uk` | Switches the language (takes effect after `/reload`) |

## Documentation

| Document | Contents |
|---|---|
| [User guide](docs/user-guide.md) | Every page, button, status, setting and message |
| [How it works](docs/how-it-works.md) | Scanning, demand estimates, deal maths, limits and safety rules |
| [Architecture](docs/architecture.md) | Modules, load order, events and data flow, for developers |
| [Saved data](docs/saved-data.md) | Layout of the `ForeverFlipData` SavedVariables file |
| [API](docs/api.md) | `ForeverFlipAPI` for other addons |
| [Testing](docs/testing.md) | Automated tests and an in-game checklist |
| [Contributing](CONTRIBUTING.md) | Development setup, style and release process |

## Limits and honest notes

- The server allows one full scan per 15 minutes **per account**. If another addon uses that window,
  ForeverFlip reads its results instead.
- Sales are measured from full scans, auction by auction, when the client reports each auction's
  time left; otherwise from listings that disappear, where expired lots look like sales. Either way it
  is an estimate. ForeverFlip lowers its trust in an item when your own stock of it does not sell or
  keeps coming back unsold.
- Commodity deposits come from the game; item deposits are learned from your posts, and estimated
  with the classic rule until then.
- The 15% neutral cut and the disenchanting table are taken from Classic and have not been confirmed
  on WoW Forever. The cut is corrected from your sale invoices.
- No profit is guaranteed: other players see the same lots. A purchase that fails because someone
  was faster costs nothing.

## Development

```bash
python -m pip install -r requirements-dev.txt
python -m unittest discover -s tests -p "test_*.py"
python tools/build.py
```

The tests run the real addon code in Lua 5.1 (through [lupa](https://github.com/scoder/lupa)) against
a simulated WoW client and auction house. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
