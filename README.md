# ForeverFlip

**An auction house trading assistant for WoW Forever.** ForeverFlip reads the whole auction house,
finds lots you can profit from, checks each one against the live listings right before you buy, and
then helps you post, track and cash out what you bought.

[User guide](docs/user-guide.md) · [How it works](docs/how-it-works.md) · [Changelog](CHANGELOG.md)

---

## Features

- **Full auction house scan.** Reads every auction the server returns (often more than 200 000)
  without freezing the game, at most once per 15 minutes. It can rescan automatically while the
  auction house is open, and it also reads full scans that other addons request.
- **Vendor deals.** Finds lots priced below what a vendor pays for the item. You buy them, sell them
  to any vendor and keep the difference, with no market risk.
- **Resale deals.** Finds lots priced well below the next seller. A deal is shown only if the item
  is selling at the resale price, measured from the drop in listings between scans. The profit
  already includes the 5% auction cut and the deposit you lose on unsold lots.
- **Live check before every purchase.** A deal from the scan is only a lead. Before the Buy button
  becomes active, ForeverFlip runs an exact search and recalculates the deal from the current
  listings. A check is valid for 45 seconds.
- **Sniper.** Between full scans, re-checks the 150 items most often near a deal, one search per
  second. A cheap new listing shows up within seconds instead of after the next full scan.
- **Alerts.** Plays a sound and shows a message on screen when a deal can be bought.
- **Selling help.**
  - **Post next bought:** lists your purchases one legal price step below the cheapest other seller.
  - **My auctions:** shows which of your lots have been undercut and lets you cancel them.
  - **Take auction mail:** collects auction mail in one click at the mailbox and never touches
    player mail or cash-on-delivery.
  - **Sell vendor deals:** sells every item bought as a vendor deal at any merchant in one click.
- **Merchant to auction house offers.** At a merchant, lists the items that sell on the auction
  house for more than the merchant charges.
- **Accounting.** For each character it keeps a purchase/sale journal, stock at average cost,
  profit per item and how long items take to sell.
- **Analytics.**
  - Your results: profit per day, return, hit rate, best and worst items.
  - The market: items selling the most, items below their usual price, falling and rising
    prices, and the cheapest and dearest time of the week.
- **Price tooltips.** Item tooltips show the usual price, the cheapest price today and over five
  days, and the units sold per day.
- **Languages.** English and Ukrainian. The addon picks the language from the game client and lets
  you switch it in Settings.

ForeverFlip never buys, posts or cancels anything on its own. Every trade starts with your click.

## Requirements

| | |
|---|---|
| Game | WoW Forever, client 1.60.1 (Interface `16001`) |
| Dependencies | None. [LibAHTab](https://www.curseforge.com/wow/addons/libahtab) is used if installed, so the ForeverFlip tab sits next to other addon tabs |
| Works next to | Auctionator, TradeSkillMaster and other auction addons |

## Installation

1. Download `ForeverFlip-<version>.zip` from the [latest release](../../releases/latest).
2. Unpack it into `World of Warcraft/<client folder>/Interface/AddOns/`. You should end up with
   `Interface/AddOns/ForeverFlip/ForeverFlip.toc`.
3. Restart the game or type `/reload`. Make sure ForeverFlip is enabled in the AddOns list on the
   character select screen.

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
| `/ff lang en` / `/ff lang uk` | Switches the language (takes effect after `/reload`) |

## Documentation

| Document | Contents |
|---|---|
| [User guide](docs/user-guide.md) | Every page, button, status, setting and message |
| [How it works](docs/how-it-works.md) | Scanning, demand estimates, deal maths, limits and safety rules |
| [Architecture](docs/architecture.md) | Modules, load order, events and data flow, for developers |
| [Saved data](docs/saved-data.md) | Layout of the `ForeverFlipData` SavedVariables file |
| [Testing](docs/testing.md) | Automated tests and an in-game checklist |
| [Contributing](CONTRIBUTING.md) | Development setup, style and release process |

## Limits and honest notes

- The server allows one full scan per 15 minutes **per account**. If another addon uses that window,
  ForeverFlip reads its results instead.
- Sales are estimated from listings that disappear between scans. Lots that expire or are cancelled
  also disappear, so the estimate can be too high. New listings can hide sales, so it can also be too
  low. ForeverFlip lowers its trust in an item when your own stock of it does not sell.
- Deposits are estimated with the classic rule (15% of the vendor price, at least 1 silver).
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
