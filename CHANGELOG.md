# Changelog

All notable changes are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.2.0] - 2026-11-11

Fixes and features from a study of the WoW Forever auction addons (ForeverForge Auction, auxForever,
AuctionHouse Forever, Auctioneer (Forever), TheWoWDB, Price Scanner Forever, ForeverSell, Forever
Auction Master, Arbitrage, WOW4E AH Trader) and of the Forever branches of TSM and Auctionator.

### Fixed

- **Vendor prices.** WoW Forever's server pays less than the client's item data says for some items
  (a recipe listed at 2s sells for 1s 50c; a wand went from 15s to 1c). What a merchant really paid
  is now read from the buyback list and used first. Until then, deals count the client's price 20%
  lower (Settings → Safety) and mark such vendor deals with a yellow `*`.
- **Gear searches.** The sell search ForeverFlip used for gear is never answered on WoW Forever. Gear
  is now searched with a browse by name and an exact search of each item-key version. An item nobody
  sells is known at once instead of after a timeout.
- **Stuck throttle.** The game can stay "not ready" for good after a message the server never
  answered; the sniper and the checks then stopped until the auction house was closed. After 5
  seconds of "not ready", one message goes through.
- **Full scan wait.** The answer to a full scan can take minutes since launch; ForeverFlip waited 45
  seconds and gave up. It now waits up to 5 minutes and shows the seconds; searches and the sniper
  wait for the answer. A request the server dropped is tried again in 10 seconds.
- **Full scans of other addons** are caught when the call is made, not only by the event Forever does
  not always send.
- **Freezes while another addon browses.** Browse results of other addons are read once, a few hundred
  rows per frame, instead of all rows again on every page.
- **Disenchanting.** Green weapons of item level 21-30 give Greater Magic Essence, not astral. An
  essence is valued at most what its other form allows (three lesser make one greater).
- **Own auctions** are recognised also when the game names the owner `player` or adds the realm; a
  player with the same name on another realm is somebody else (names are not unique on Forever).
- **Bids on gear** are read for every item-key version, also versions with bid-only auctions.
- **Deposits** in crafting and resale estimates come from the game's vendor price, which is what the
  auction house charges on.
- **The neutral auction house** is recognised by the auctioneer first: an Alliance or Horde
  auctioneer always means the faction house, whatever the zone. The bar beside the money display and the window
  title name the open house (Alliance blue, Horde red, neutral gold with its 15% cut), and opening
  another house shows that house's own scan and deals (deals just checked on the other house no
  longer come along).
- **The end of a full scan** no longer stalls the game on a large history: forgetting old items
  and sweeping vanished ones run a slice per frame, and the scan is copied into the saved data on
  logout instead of at once.
- **A full scan survives closing the auction house and `/reload`:** the request is remembered
  and the wait goes on when the house opens again (before, the answer was ignored while the
  15-minute pause still ran). While waiting, the status shows how many auctions the server has sent
  (0 = no answer yet); the timeout says whether nothing came or the list kept changing, and
  `/ff diag` lists how the last requests ended.
- **Post all, Post AH-worthy and Post next bought** read the prices of the whole queue on the first
  click, so each next click posts a lot (before, most clicks only read one price).
- **Chat text the client hides from addons** (secret values) no longer causes an error
  (`Trade.lua:200`) or touches the chat.
- **An expired auction can be posted again at once:** its listing stops counting the units as on
  sale when the "Auction expired" (or "Auction cancelled") mail comes, so Post next bought offers the
  item again; a cancel made by ForeverFlip is not taken off twice when its mail arrives.
- **Full bags at the mailbox:** an auction mail with an item is booked when the item is really
  taken, not again on the next visit.
- **A browse sent just before a gear check** (the game's Buy tab, another addon) can no longer be
  taken for the check's answer and report that nobody sells the item.
- **Sales from a full scan:** items whose rows could not be read in time, and scans far smaller than
  the house's last one (a partial answer), no longer count their missing lots as sold.
- **A late scan event** for the scan just read no longer starts a second reading and a new cooldown;
  a request that failed with an error does not use up the cooldown.
- **A sale is booked once** when both the auction list and the invoice mail report it.
- **Purchases outside ForeverFlip** (the game's Buy tab, another addon) are booked from their buyer
  invoice mail as stock bought elsewhere; **sales to a merchant by hand** are booked from the buyback
  list. Before, only what ForeverFlip itself bought and sold was tracked.
- **Item tooltips** were rewritten: they name the auction house of their prices, say when sales are
  not measured yet, show your stock and your auctions on sale, and the vendor price, the auction
  house after the cut and deposits, and disenchanting side by side. The deposit of commodities is
  the per-unit share of a stack, and the tries come from your own sale rate: cheap stackable goods
  no longer look like a loss on the auction house.
- **The Sell page lists every sellable bag item:** items the auction house has not seen yet get
  their kind from the item itself (as the game's Sell window does), and the reagent bag is read.
  `/ff bags` tells why an item is left out.
- **Gear checks** read up to three more pages of a version with many listings; a search of one gear
  version in the game's Buy tab is no longer taken as a full check of the deal.

### Added

- **Selling → My items: vendor or auction house.** A **Best** column tells, for each item, whether a
  merchant pays at least what the auction house leaves after the cut and deposits, or the auction
  house pays more; **Post AH-worthy** posts only the latter, next to **Post all**.
- **Check all** (was Check all statuses) works on every page with a list: also the Shopping list
  (shopping deals are found), Bids and Crafting (every material and product). Prices of a fresh
  check are used by the page for 5 minutes: the Best column, the recipe profits.
- **Realm channel sharing:** full scans are shared with every ForeverFlip user of the realm over a
  hidden chat channel. A player who logs in asks who has a newer scan, one player answers, everyone
  behind keeps it. Shared prices more than 10 times off the known usual price are left out (also for
  guild and group scans).
- **Learning from your own disenchants:** after 15 disenchants of an item band, their results replace
  the Classic table for it.
- **Safety tab** in Settings: the vendor price margin, a spending limit per auction house visit, cheap
  units of a vendor deal left for other buyers, and what was learned.
- **Buy the next best deal** key binding: each press selects and checks the best deal you can afford,
  buys it, and confirms a commodity price.
- **Tooltip advice:** sell to a vendor, disenchant, or post on the auction house (after the cut and
  three deposits).
- **Hardcore realms** keep their own prices.
- **Shop materials** counts what the bags and the bank already hold.
- A window asks before going on when the game handed ForeverFlip no saved data at login.

### Changed

- **Six menu entries** instead of thirteen: Deals (All, To vendor, Resale, From the list, Bids),
  Selling (My items, My auctions), Shopping list, Crafting, Analytics (Overview, By item, Journal
  and profit) and Settings. Pages of an entry are tabs above the page; each entry opens the tab used
  last. The summary of the scan and the sniper below the menu has room for one figure per line.
- Settings has a fourth tab, **Safety**.

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
  - The **ForeverFlip Sync** helper (`sync/`) shares them unchanged with
    [ForeverFlip-Data](https://github.com/Danissemo/ForeverFlip-Data), where they are archived by
    day, and downloads the community summaries of your realms into the **ForeverFlip_Shared** addon.
  - Any GitHub account at least 7 days old can upload: the helper puts the scan into a secret gist and
    opens an upload issue that the data repository processes and closes.
  - Every kept scan is sealed with a checksum of its lines. The helper checks a scan before sending
    and the data repository checks it again, so a scan edited afterwards is refused.
  - A scan reaches the summaries only after a scan of another player confirms it, and only with the
    items whose prices agree.
  - See [docs/community.md](docs/community.md).
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

[Unreleased]: ../../compare/v1.2.0...HEAD
[1.2.0]: ../../compare/v1.1.0...v1.2.0
[1.1.0]: ../../releases/tag/v1.1.0
[1.0.0]: ../../releases/tag/v1.0.0
