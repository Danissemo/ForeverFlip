# Changelog

All notable changes are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- Neutral auction houses are recognised by the zone's map ID, in any client language; the English
  town names remain a fallback.
- CI uses current versions of the GitHub actions and a pinned StyLua binary.
- New README layout with a hero image, badges and a questions-and-answers section.

### Fixed

- An item nobody sells on the auction house and never seen in a scan (recipes, rare drops) got no
  suggested price, and the Sell page kept asking for a price check. Now:
  - the price comes, in this order, from your last post of the item, auxForever, your cost + 25%, or
    1.5 × the vendor price;
  - guessed prices are marked and skipped by the posting queues;
  - the page says when nobody sells the item or when the auction house did not answer;
  - an item missing from a full scan of the last 20 minutes, or whose check got no answer (WoW
    Forever does not answer a search for an item without lots), gets its price at once.

## [1.1.0] - 2026-11-10

Features found in other auction addons (TSM, Auctionator, Point Blank Sniper, AnS, Journalator,
auxForever, AuctionMin) and adapted to WoW Forever.

### Added

- **Fast sniper.** Browse rounds read the lowest price of every item on the auction house in
  seconds. Between rounds, the hot items and the shopping list are read in batches of 100 keys.
  Items whose lowest price may hold a deal are checked with an exact search before they can be
  bought. If the game does not offer browse queries, the old per-item sniper is used.
- **Sales tracked lot by lot.** Full scans are compared auction by auction:
  - partial purchases count as sales;
  - vanished lots count only if they could not have expired and no cheaper lot survived.

  This gives the median price of real sales ("sells at") and a 75% cap for resale exits.
- **14 days of history** per item: usual price, cheapest price, units listed and sold. Right-click an
  item in any table to open its history chart.
- **Accounting from auction mail.** Seller invoices book sales with the exact amount, including
  sales of items posted outside ForeverFlip. Expired and cancelled mails count as failed posts. The
  resulting sale rate per item (Statistics: Sell %) lowers the trust in items that keep coming back
  unsold. The game's own mailbox buttons are hooked too.
- **Neutral auction houses** (Booty Bay, Gadgetzan, Everlook) have their own price history and a
  15% cut. The cut of each house is learned from invoices.
- **Deposits from the game:** commodities use `CalculateCommodityDeposit`; items use the deposit
  learned from their last post.
- **Fresh quotes:** a commodity quote about to expire is asked again instead of confirmed.
- **Posting rules.**
  - Settings: undercut by a percent, a minimum and a maximum as a percent of the usual price, and
    hold-or-post below the minimum.
  - Per item: minimum, maximum and units to keep in the bags.
- **Post all** posts every sellable bag item, not only purchases.
- **Cancel undercut** cancels your undercut auctions one click at a time, but only those whose
  repost still reaches the item's floor.
- **Automatic duration:** 2, 8 or 24 hours, chosen by how fast the item sells.
- **Shopping list:** items with the most you pay for one. The scan, the sniper and your own
  searches turn cheaper lots into Shopping deals.
- **Ignored items:** an Ignore item button on deals. Ignored items never become deals.
- **Learning from your own searches:** item searches in the game's Buy tab check the item's deal at
  once, and browse results feed the sniper and today's lowest prices.
- **Marks in the game's Buy tab:** a green stripe on browse rows of items with a deal. Item tooltips
  show the current deal.
- **Key bindings:** Buy/Confirm, Post next (then Post all), Cancel undercut, Full scan.
- **Crafting page:** recipes are read when a profession window opens. Each is priced with the
  cheaper of auction and merchant prices for materials, and the product's auction value or vendor
  price. Shop materials puts one day of crafts on the shopping list.
- **Disenchant deals** for characters who know Disenchant, from the Classic disenchanting table and
  the usual material prices.
- **Bids:** auctions ending within 30 minutes whose next bid is well below the item's worth.
  - Check reads the auction.
  - Place bid bids with a click.
  - Won auctions become stock and outbid mail closes the bid.
- **ForeverFlipAPI** for other addons (`GetPrice`, `GetDeal`). auxForever prices are used as a
  fallback for unseen materials.
- **CSV export** of the journal (`/ff export` or Export CSV on the Journal page).
- **Gold of all characters** of the realm and stock at cost on the Analytics page.
- **Presets:** Careful, Balanced, Aggressive.

### Changed

- The price change on the Analytics page compares with the previous five days of the 14 kept.
- The Settings page shows its checkboxes in two columns.

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
