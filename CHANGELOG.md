# Changelog

All notable changes are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.1.0] - 2026-11-11

Features found in other auction addons (TSM, Auctionator, Point Blank Sniper, AnS, Journalator,
auxForever, AuctionMin) and adapted to WoW Forever, community scans, and fixes from in-game testing.

### Added

**Finding deals**

- **Fast sniper.** Browse rounds read the lowest price of every item on the auction house in seconds.
  - Between rounds, the hot items and the shopping list are read in batches of 100 keys.
  - Items whose lowest price may hold a deal are checked with an exact search before they can be
    bought.
  - If the game does not offer browse queries, the old per-item sniper is used.
  - Its figures are in the summary on the left.
- **Sales tracked lot by lot.** Full scans are compared auction by auction:
  - partial purchases count as sales;
  - vanished lots count only if they could not have expired and no cheaper lot survived.

  This gives the median price of real sales ("sells at") and a 75% cap for resale exits.
- **14 days of history** per item: usual price, cheapest price, units listed and sold. Right-click an
  item in any table to open its history chart.
- **Shopping list:** items with the most you pay for one. The scan, the sniper and your own searches
  turn cheaper lots into Shopping deals.
- **Ignored items:** an Ignore item button on deals. Ignored items never become deals.
- **Disenchant deals** for characters who know Disenchant, from the Classic disenchanting table and
  the usual material prices.
- **Bids:** auctions ending within 30 minutes whose next bid is well below the item's worth.
  - Check reads the auction.
  - Place bid bids with a click.
  - Won auctions become stock and outbid mail closes the bid.
- **Crafting page:** recipes are read when a profession window opens. Each is priced with the
  cheaper of auction and merchant prices for materials, and the product's auction value or vendor
  price. Shop materials puts one day of crafts on the shopping list.
- **Learning from your own searches:** item searches in the game's Buy tab check the item's deal at
  once, and browse results feed the sniper and today's lowest prices.
- **Marks in the game's Buy tab:** a green stripe on rows priced low enough to hold a deal.
  - Rows are marked in the list of items, in the auctions of one item and in the price tiers of a
    commodity.
  - The marks are refreshed while you scroll.
  - Item tooltips show the current deal.

**Selling**

- **Posting rules.**
  - Settings: undercut by a percent, a minimum and a maximum as a percent of the usual price, and
    hold-or-post below the minimum.
  - Per item: minimum, maximum and units to keep in the bags.
- **Post all** posts every sellable bag item, not only purchases.
- **Hide** on the Sell page keeps items you want out of the list for sale and out of the posting
  queues. A **Hidden** view lists them, and **Return to sale** brings them back.
- **Items nobody sells.** Recipes and rare drops get a suggested price, in this order:
  1. your last post of the item;
  2. auxForever's price;
  3. your cost + 25%;
  4. 1.5 × the vendor price.

  The last two are marked as guesses, and the posting queues skip them.
- **Cancel undercut** cancels your undercut auctions one click at a time, but only those whose
  repost still reaches the item's floor.
- **Only yours:** My auctions marks items nobody else sells from the last full scan, without a
  search; a check the server did not answer shows **no answer**.
- **Automatic duration:** 2, 8 or 24 hours, chosen by how fast the item sells.
- **Fresh quotes:** a commodity quote about to expire is asked again instead of confirmed.
- **Deposits from the game:** commodities use `CalculateCommodityDeposit`; items use the deposit
  learned from their last post.

**Accounting, analytics and sharing**

- **Accounting from auction mail.**
  - Seller invoices book sales with the exact amount, including sales of items posted outside
    ForeverFlip.
  - Expired and cancelled mails count as failed posts. The resulting sale rate per item (Statistics:
    Sell %) lowers the trust in items that keep coming back unsold.
  - The game's own mailbox buttons are hooked too.
- **Neutral auction houses** (Booty Bay, Gadgetzan, Everlook) have their own price history and a
  15% cut, recognised by the zone in any client language. The cut of each house is learned from
  invoices.
- **Shared scans in game:** send your last full scan to the guild, the group or one player, every
  scan to the guild automatically, or as text to export and import.
  - Received scans of your realm add days to the price history and fill the weekly pattern.
  - They also give a fresh usual price when your own scan is older.
- **Community scans through GitHub.**
  - With **Settings → Sharing → Keep my full scans for the ForeverFlip Sync helper**, full scans are
    kept auction by auction (`ForeverFlipRaw`).
  - The **ForeverFlip Sync** helper (`sync/`) uploads them unchanged to
    [ForeverFlip-Data](https://github.com/Danissemo/ForeverFlip-Data), where they are archived by
    day, and downloads the community summaries of your realms into the **ForeverFlip_Shared** addon.
    See [docs/community.md](docs/community.md).
- **Gold of all characters** of the realm and stock at cost on the Analytics page.
- **CSV export** of the journal (`/ff export` or Export CSV on the Journal page).
- **ForeverFlipAPI** for other addons (`GetPrice`, `GetDeal`). auxForever prices are used as a
  fallback for unseen materials.

**Comfort**

- **Sorting:** every table sorts by any column, both ways.
- **Key bindings:** Buy/Confirm, Post next (then Post all), Cancel undercut, Full scan. Set them on
  Settings → Key bindings or in the game's Key Bindings window.
- **Presets:** Careful, Balanced, Aggressive.
- **Settings** in three tabs: General, Key bindings, Sharing.

### Changed

- Statistics by item has fewer, narrower columns so names fit.
  - `-` stands for "nothing yet".
  - Days to sell are shown only for units bought through ForeverFlip.
  - Stale stock is red.
- The price change on the Analytics page compares with the previous five days of the 14 kept.
- New README layout with a hero image, badges and a questions-and-answers section.
- CI uses current versions of the GitHub actions and a pinned StyLua binary. A release also builds
  `ForeverFlipSync.exe`.

### Fixed

- Ukrainian texts showed boxes in place of symbols the game's Cyrillic font lacks; column headers,
  statuses and buttons were cut off or overlapped in Ukrainian.
- The price box of the Sell page kept the last price after posting.

## [1.0.0] - 2026-11-10

First public release.

### Added

- Full auction house scan, read over many frames, with automatic rescans every 15 minutes and reuse
  of scans requested by other addons.
- Vendor deals: lots below the vendor sell price.
- Resale deals with measured demand, the 5% cut, the deposit risk, and caps per deal and per item.
- Live verification of every deal before purchase. Buy is enabled only for a deal checked in the
  last 45 seconds.
- Sniper: re-checks the 150 items most often near a deal between scans.
- Sound, screen and chat alerts for deals that can be bought.
- Buying commodities (quote and confirm) and items or gear (one auction per click).
- Sell my items: price suggestions, Post next bought with a break-even floor.
- My auctions: undercut checks, cancelling, automatic booking of sales.
- Check all statuses for deal pages, bags and own auctions.
- Take auction mail at the mailbox.
- Sell vendor deals at a merchant.
- Merchant → auction house offers.
- Per-character accounting: positions at average cost, a journal, item statistics, a trust factor
  from unsold stock, and settling of unknown purchases.
- Analytics: own results over 7 or 30 days, market lists (below usual, sells most, falling,
  rising, cheap now, sell now) and a time-of-week price pattern.
- Price history lines in item tooltips.
- English and Ukrainian interface.
- Slash commands `/ff`, `/ff diag`, `/ff rescan`, `/ff lang`.

[Unreleased]: ../../compare/v1.1.0...HEAD
[1.1.0]: ../../compare/v1.0.0...v1.1.0
[1.0.0]: ../../releases/tag/v1.0.0
