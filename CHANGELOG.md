# Changelog

All notable changes are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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

[Unreleased]: ../../compare/v1.0.0...HEAD
[1.0.0]: ../../releases/tag/v1.0.0
