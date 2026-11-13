# Changelog

All notable changes are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- **Full scan lost most of a busy house.** When the game had not loaded the data of the items with
  the most lots, their rows (210 000 of 242 000 in game) were read again row by row on every pass;
  one pass took longer than the 30-second wait, so rows whose data arrived meanwhile were given up.
  The scan then knew 1 588 items instead of 1 732, and resale found 2 deals. Waiting rows are now
  kept per item and read again only once its data has arrived; the count moves at once, and the
  wait runs on 30 seconds after the last item came in (5 minutes at most).

### Documentation

- Tester checklist checked against the interface of 2.1: page and button names as the game shows
  them (Скупити все для торговця, На складі, Мій список), the full-scan wait of 10 minutes,
  merchant buttons shown only with something to sell. Seven new cards cover what 2.0 and 2.1 added
  without one: the Sure column, Buy all to vendor, My bids, Undercuts and Answer next, Post next
  bought, sending a scan in game and decimal settings; 69 checks in all.

## [2.1.0-beta.1] - 2026-11-13

A full code review (160 findings) and its fixes. Deposits are estimated one way everywhere, and
merchant sales and purchases are booked only once the bags show them.

### Fixed

- Best sale advice compares vendor proceeds with observed auction prices, before raising a post
  to the player's minimum. The tooltip shows those market proceeds separately from the protected
  posting suggestion. Merchant candidates no longer depend on auction-house sellability and
  consistently respect hidden, kept and locked items.
- Selling explanations use the existing three-line scroll area above the price controls, keeping
  long warnings readable without overlapping inputs.
- Journal filters preserve purchase kind through merging and reconstruction; won bids mark the
  correct lot, and vendor, resale and bid purchases of the same item remain separate.
- **Code review fixes (2.0.0-beta.1 and Unreleased code).**
  - Accounting: the one-time journal recount no longer rebuilds stock, lifetime statistics, lots
    and daily totals from the 500-entry journal (it wiped stock bought before the journal window),
    and only invoice purchases of the player's own posts become returns. Open purchase lots are
    never dropped by the 300-lot cap. A late purchase is booked only on one money change equal to its
    price, and no longer wipes a purchase under way. A buyout's own *You won* line no longer closes a
    running bid; an unknown purchase is settled by its line or mail and cannot be booked twice.
    Listings and purchase mail are matched for the 31-day life of auction mail, so late mail no
    longer books a sale, purchase or deposit twice. A cancel's loss is booked once the next list of
    own auctions confirms it, once per auction. Sell all and Vendor sold book only the units of the
    position, sell only vendor-deal units, and the anti-undercut "to a vendor" mark expires and is
    cleared when the item leaves. Post next bought posts only unlisted bought units and keeps the
    keep rule. Losses without stock reach the daily totals and the 7-day summary uses them too.
  - Buying: Confirm never buys an item that is no longer selected or ignored, and Buy all to vendor
    confirms only its own quote. The visit spending limit applies to every purchase path, bids and
    buyouts included, and a limit below 1 gold is kept. Bids wait for a fresh search, never go
    against the player's own lead or an alt's auction, and a bid the server never took is not shown
    as leading.
  - Searches: checks started by hovering or by the buy run wait for a full scan's answer; the "only
    yours" shortcut needs the player's own lot; a stuck throttle's allowance is no longer spent by
    checks that send nothing; dropped sniper and gear messages are released; pages of filtered rows
    are read on; Stop ends the buy run and own-auction checks. Price checks are kept per auction
    house, and prices of lots the player just bought are no longer undercut.
  - Full scans: a house that shrank is scanned again, unanswered requests back off, a resumed answer
    is read, another addon's scan no longer blocks checks for ten minutes, rows read late keep scan
    order, closing while a scan finishes books it once, other characters' purchases no longer hide
    sales, and the player's own uploaded scans are not merged back as community data.
  - Sharing: transfers expire on inactivity, pace within the client's allowance and retry throttled
    parts, one copy is sent at a time, 'Scan sent.' means a scan was sent, and peers' cheapest
    prices, sales, keys, scopes and announcements are checked.
  - Interface: tables sort item links by name and scroll past the first rows (Undercuts), footers
    count every row, a waiting key capture ends with its page, settings keep fractions and decimal
    commas, merchant items come back after closing on the ForeverFlip tab, the hidden window is no
    longer redrawn after the auction house closes, and several texts (cut, ages, run status) are
    right and translated.
  - Speed: break-even is computed in a few steps, the sniper judges rows within a time budget, browse
    keys are learned once per row, raw scan lines are read once and joined in slices, and bid
    candidates, Sure values and Undercuts plans are no longer recomputed needlessly.
  - Merchant: Gear I can't use no longer prints a sale before anything sold (the chat tells what
    really sold at the end), both gear buttons wait while a merchant sale goes, and Stop ends a
    merchant sale through the sale itself, settling stacks queued to be sent again.
  - Deposits: one model for every estimate (`Market.postDeposit`). Advice, deals, the sniper,
    merchant offers, crafting, bids, posts, cancels and the anti-undercut plan all count the game's
    deposit when known, else 15% of the vendor price for the duration posts go for, at least
    1 silver per auction, with one deposit per commodity stack. Cheap commodity resales are sniped
    and offered at merchants again, and the anti-undercut plan's cancel and repost cost what the
    cancel and the post really book. Under Auto every estimate uses the item's own duration, the
    one its post would go for, not always 24 hours.
  - Merchant purchases are booked as their units reach the bags: units a merchant refused (no
    room, sold out) no longer enter stock or the journal. Sales and purchases at a merchant share
    one watch (`Merchant.track`): booked when the bags show them, given up after their wait, and
    sales end when the merchant closes while purchases keep waiting for their units.

### Changed

- **Journal and profit has views of its own: All, Resale, To vendor, Bids.** A third menu level
  under the entry, in the auction house's own look for it (One-Handed Axes under One-Handed), shows
  the purchases of one way of dealing. Purchases won with a bid are marked so.
- **Vendor deals use all the money in the bags.** A merchant pays at once, so a vendor deal is no
  longer held to the share kept for resales (spendShare). When the money no longer covers a deal
  (other purchases since the scan), it shrinks to the units the money buys, cheapest first,
  instead of standing at "not enough money".
- **Journal: Sold and Profit columns are wider** ("4878/5148", "4878 in stock" fit), the name
  column gives up the room.
- **Cancels made with ForeverFlip are logged in the journal** (kind "cancel", the deposit and fee
  lost), so a recount keeps them.
- **Analytics, By item.** The name column is narrower, the others wider with full names (Bought,
  Sold, In stock, Profit, Days to sell, Posts sold), and each header explains its column when
  hovered. Table headers can carry such a tooltip.
- **Purchases of one item close together are one lot.** Buys of the same item within 15 minutes
  of its last lot (one position bought in several clicks, or bought back from your own posts) join
  that lot in the journal table; lots saved before are joined once.
- **Analytics overview layout.** The results on the left with Earned most, Lost most and What to
  do as labels beside their text; the chart's title and the 7/30 days buttons on one row, the
  chart under them over the full height (its zero line splits gains and losses), a rule above the
  tabs.

### Fixed

- **Cancelled auctions were booked as purchases.** WoW Forever mails a cancelled auction's items
  with a buyer invoice; it was booked as a purchase at the post's price (in one game: 35 gold of
  Fish Bowls and Enchanted Lutes never bought). A buyer invoice from yourself, or with a cancelled
  or expired subject, is now a post that came back. Once per character the journal is recounted:
  such returns (buys of one item booked within 10 seconds of each other while mail was taken, of
  an item the player had posted at that price) become returns, and the stock, costs, profits,
  purchase lots and daily totals are corrected by them; nothing the journal no longer holds is lost.
- **Lost is calculated.** Posts that came back without a known deposit (expired before deposits
  were booked, the returns above) get the deposit worked out from the merchant price, the quantity
  and the duration in the settings.
- **An item without a sale seen was sent to a merchant.** No sale over the hours it was watched
  counted as a chance of zero: 20 lost deposits were charged against its post (a 28-silver glove:
  -17 silver at the auction house, so the merchant's 3 silver won). It now counts as half a sale
  over the time watched: a short watch leaves a fair chance, months without a sale nearly none.
- **Analytics overview text ran into the tabs.** The left column is wider, Earned most, Lost most
  and What to do share one label column and wrap under their own text, at most two lines each.
- **The journal table's scroll bar jumped back to the top.** The rows were windowed twice; the
  table also shows 16 rows now, filling its block.
- **Checks of auctions only you sell stalled.** WoW Forever never answers a search of an item no
  other player sells: each such check waited out its time, forgot the item's versions (the next
  check browsed again) and was sent once more at the end. A search with no answer of an item the
  last full scan (up to 2 hours old) saw no other seller of is now answered as "only yours" at
  once, without a retry, and keeps its versions.

### Added

- **Journal and profit is a table of purchases.** Each purchase is a row: when, what, units sold of
  units bought, the price paid each and in all, what its posts lost (deposits of expired and
  cancelled posts and cancel fees), what its sold units brought after the cut, and the profit
  once all of it is sold (else how many are still in stock). Sales take the oldest purchase first.
  Earlier trades are filled in from the journal.
- **Selling keeps a minimum profit over the real cost.** Deposits lost on reposts and cancel fees
  join the stock's cost, and no post goes below that cost plus **Selling, % over cost** (Settings,
  5% by default). The floor holds for Post, Post all, Post next bought and Undercuts. The tooltip's
  "You hold" shows what reposts lost.

### Fixed

- **A part of the scan was read as a smaller house** (185 980 of 283 783 auctions stopped for a
  minute and was taken). A list under 75% of the last complete scan of the last 3 hours is a part
  and is never read; after a longer break, a list under half of the day's largest is. A house that
  really shrinks does so a little between two scans.

- **Formula audit.** An outside review of every formula found real defects; all that change a
  decision are fixed:
  - **Sale chances of a large number** read 100% instead of almost 0: the first term of the
    negative binomial rounded to zero and every term after it too. Terms are now kept as logs.
  - **Undercuts counted the deposit already paid twice** against every option that cancels: waiting
    gets it back with a sale, so cancelling now costs only the game's extra cancel fee. A merchant
    can now beat waiting when it should.
  - **A first bid ignored the minimum return** (a bid of 99 for a worth of 100 passed); every bid now
    keeps both the minimum profit and the minimum return.
  - **Shop materials bought a day of the product's units in crafts**: a recipe making 5 bought
    5 times too many.
  - **Another seller's smaller lot read as a partial purchase**: lots now match only within one
    known seller.
  - **Sure rose with purchases at other prices**: the real-buyer share now uses the sales at the
    price only.
  - **Sweeps compared counts of pairs of different lengths**, and never faded: a 3-hour pair at the
    usual rate was cut as a sweep, and old sweeps kept Sure at half for good. Rates per hour are
    compared, and the counts decay.
  - **Deposits lost before a sale were capped at four posts**: an item that sells on 5% of posts
    loses 19 deposits, not 4. Expected expired posts are now (1 − s) / s, up to 20.
  - **Analytics lost sales past the 500-entry journal**: daily totals (60 days) feed it now.
  - **A price cap was passed** when nobody had a normal price; the cap now holds. Break-even is the
    lowest price that returns the cost (it could be one step higher). A price above every measured
    level no longer borrows sales from below it. Undercuts counts your own lots ahead for each price
    an option posts at.

- **Full scans stopped for hours.** The server answered ever more slowly (2, then 4, then over
  5 minutes); the scan gave up at 5 minutes and called again while the server still worked on the
  last call, and in game no scan came for seven hours. It now waits up to 10 minutes, and each call
  left unanswered in a row adds 5 minutes before the next (up to 30); an answer resets it.
- **Undercuts text showed one line.** A text that does not wrap shows only its first line in game;
  each row of the block now has its own line, so the block is filled.

## [2.0.0-beta.1] - 2026-11-12

### Added

- **Analytics, made plain.** One big line says what you earned or lost; plain lines say what you
  spent, sold, still hold and what each 1g brought back; a "What to do" line names the one thing
  that matters now. The market tabs got clear names (Bargains, Popular, Getting cheaper, Getting
  dearer, Buy now, Sell now) with a line under the table on what to do with each.

- **Undercuts: the text above the buttons scrolls** like the tables (the same scrollbar, the
  mouse wheel; hovering shows it whole) and reads line by line: your auction and what is ahead of
  it, its sales, rivals, what an unsold unit is worth, then each way out as a headline (expected
  money and chance, the advised one marked) with what it does in grey below. A price war no longer
  says "you answered 0 times".

- **Buy all to vendor** (Deals, To vendor): every vendor deal bought click after click. The game
  takes a purchase only from a click, and an item auction only right after a search of that item,
  so each click buys one lot (a stackable: one click asks the price, the next confirms) while the
  next deal is checked just before its click. The further lots of the same item need no new search.
  Check all and the sniper rest during the run; a deal that cannot be confirmed is skipped. The
  button says what the next click does and how many deals are left; Stop ends the run.
- **A new item tooltip**, in sections: Market (usual price and its age, cheapest today, what
  buyers paid), Demand (bought a day near the price, the purchases it rests on, Sure to sell one
  in 2 days), Yours (stock and auctions), the deal now with its Sure, and Selling one (post price,
  what you get, vendor, disenchant) with the best way out.
- **The deal under the table, line by line**: Buy x price = cost, where it sells and the profit
  with its return; Demand a day, how long the units take (minutes, hours or days) and the data's
  age; the purchases seen; and what Sure is made of.

- **Sure**, a new column on the Deals page: how sure a resale is to pay back at its Sells at
  price, from 0 to 100%. It is the chance that real buyers take the units at that price within
  2 days while your lot is the cheapest. Few sales give a low number however fast they came, and
  one buyer of four units counts as one purchase. A lot that vanished whole counts half (often
  another reseller). Shelves cleared in one go, a rival who undercuts often, unsold stock of the
  item and old sales data lower it. Selecting a deal explains the number; the formula is in
  docs/how-it-works.md. Before two full scans have tracked an item's lots, Sure is reckoned from
  the lots that disappeared near the price and is at most 50%.
- **Check all is much faster for gear.** Each item-key version learns its ending from its lots, so
  a check of "Magician Staff of the Owl" searches only its own versions, not the fifteen of every
  ending. One sweep of an item's versions answers the checks of its other endings at once. The
  client loads every item's data when Check all starts (each item waited up to 2 seconds for it).
  A search of Check all with no answer gives up after 5 seconds (was 10; it is sent once more at
  the end). Selecting a checked deal holds Check all for 3 seconds (was 15), plus as long as the
  pointer is on Buy.

- **Shopping list → My bids**: every bid of yours, including those placed in the game's own window.
  It shows whether you lead, were outbid, won or lost, the next bid the house takes and what the
  item is worth to you. For an outbid bid it advises bidding again while that still leaves your
  minimum profit and return (an outbid costs nothing: the money comes back). When hours are left
  and the buyout still pays, it advises buying out. **Bid again** and **Buy out** act on the
  selected bid. Being outbid no longer closes the bid: the auction still runs.

### Fixed

- **Undercuts: "Unsold" showed a unit's worth divided by the stack size** (an 80-unit stack read
  80 times too low); it shows what one unit brings posted again.

- Times read the same on every page ("40 min", "3.5 h", "2.1 days") and are translated; the
  Undercuts page showed whole hours in English. Sure is cached by its data, so the tooltip shares
  it with the deals.

- **Buy all to vendor skipped good deals** when the auction house was busy for a moment right
  after a check; only a check that went stale is sent again now. The run also ends by itself when
  you leave To vendor or click nothing for a minute: it held Check all and the sniper until the
  auction house closed.
- **A house that really shrank was never scanned.** A list smaller than the day's largest scan
  but not a whole number of the server's parts is read after a quiet minute, as the house it is;
  before, every scan of a smaller house (at night, after many auctions ended) was dropped for a day.
- **My bids could advise bidding against yourself** when the server does not name the highest
  bidder: you lead then while the highest bid is the one you placed.
- **Undercuts text jumped back to the top** every minute (its first line holds the time left); it
  keeps its place while the same auction is selected.
- Sure is kept 30 seconds per deal instead of being reckoned for every deal four times a second;
  gear version rows are only collected when a sweep can answer other deals; an unused detail
  function and 70 translations of texts no longer in the addon are gone.

- **A buy out showed different figures on Undercuts and on the Shopping list.** The deal read
  "allows up to 99s (saving 75s 5c)" while Undercuts read "expected 70s 51c". Both now give what
  the bought units bring once resold after the cut (75s 5c); Undercuts adds, named as such, the
  expected sum of yours and theirs together with the chances counted.

- **Post, cancel and answer buttons are disabled while the auction house is busy** (a search or
  the sniper waits for its answer, or a post is on its way). Pressing them then did nothing but say
  "busy"; they come back by themselves within a second or two.

- **Answer next took three clicks.** The sniper and the checks of other pages kept the way to the
  server busy while the Undercuts page was shown, and a cancel sent then failed without a word
  (the status still said "cancelled"). They rest on the Undercuts page now, and a failed answer
  says the auction house is busy.
- **Sure counts rivals as lots ahead**, not as the end of your chance: each undercut puts the
  item's usual lot ahead of yours. A popular item sells through them (Arcane Powder at 280 a day
  read 30%); a slow one does not.

- **Undercuts: honest chances and a better reckoning of every way out.**
  - Few sales no longer read as sure: four units seen in one hour made a 97% chance to sell. The
    rate is now an uncertain belief, and the chances stay wide until more sales are seen.
  - The demand is measured at the price of each option: buyers who reach your lot must accept
    your price, not the cheaper one.
  - The deposit of a kept auction comes back with the sale; cancelling loses it. Waiting was
    undervalued by that much.
  - A stack sells in part: 80 units behind slow demand counted as nothing, now as the units
    expected to sell.
  - Unsold units are worth posting them again (at least a merchant's price), not only the
    merchant's price.
  - Your own cheaper lots of the same item count as units ahead.
  - **Rival undercutters:** how often the item is undercut between full scans is now measured, and
    an undercut is valued as lasting only until the next answer. The page shows the answer rate;
    a rival answering every 4 hours or sooner marks a price war.
- **New option: raise.** Buy every other seller's lot below a higher target (the next seller above
  you less a step, at most the price sales reach), cancel yours and post everything at the target.

- Buy prepares an item/gear deal's server search context when selected or hovered, so the first
  enabled click buys instead of only requesting another check. The button waits for in-flight
  searches, and hovering reserves the connection from background searches and owned refreshes.
  Failed preparation invalidates the old ready mark; existing throttle recovery remains usable.
  Commodity confirmation and one hardware click per auction are preserved.

- Recipe and other non-equipment price checks reuse exact item keys from owned auctions and
  browse results, avoiding silent zero-level queries. Item and commodity added-page events are
  processed, stalled cached keys are invalidated, and one multi-version request cannot consume
  more than 30 seconds of reply-wait time. Intentional pauses between versions do not consume it.
  Late replies to timed-out browses cannot certify the next item as having no sellers.

- Audit: prevent duplicate accounting after bid wins, manual purchase settlement, repeated inbox
  updates and merchant buyback events; distribute sale invoices across matching listings and use
  exact sold-lot totals. Preserve gear variant names in bids and localize undercut scan notices.
- Reject inconsistent shared-scan chunks, out-of-window history, truncated saved-data input,
  corrupt compressed uploads and incomplete or duplicate-entry update archives. Deduplicate scan
  uploads within one pass and defer accepted-issue completion until local registry persistence.
- Keep historical-only shared observations for their retention period, release five-minute scan
  working data, refresh time-dependent analytics and align crafting shopping limits with costs.
- Return today's minimum from the public price API only when the daily record is from today.

- **Only complete full scans are used.** A part of the server's list is never read, however long
  it stays quiet: the rest is waited for, up to 10 minutes while the list still grows. A part left
  at the end is dropped with a message, and the deals and sales of the last complete scan stay.
  A part of another addon's scan (Auctionator, TSM) is waited for the same way.
- **Full scans read a part of the house as the whole.** The server sends its list in parts of
  1024 auctions; a part that paused for five seconds was taken as the answer, and each such scan
  lowered the size the next one was measured against (185 344 auctions, then 122 880, 88 064 …
  36 864). The lots missing from a part were read as bought: an oil "sold" 518 units in 1.6 hours,
  and Resale offered only a few deals. A list that is a whole number of parts, or under 75% of the
  largest complete scan of the day, is now waited for (and read as partial when it never grows),
  and a smaller scan no longer lowers that size. Sales measured since are dropped once and measured
  again from the next two complete scans.
- **My auctions: pending was ten times too high.** The game reports a sold auction with the price of
  the whole sale, not of one unit; it was multiplied by the quantity again (22g pending where
  Auctionator showed 1g 98s). The sale was booked with the same error. A sold auction now keeps
  its unit price and its total apart, and matches Auctionator.
- **My auctions footer.** The Cancel undercut button is gone (undercuts are answered on Selling →
  Undercuts; the key binding still works); Refresh and Check prices moved to the left, and the
  progress of Check prices shows in the status line at the top instead of over the buttons.

- The tooltip line "On sale by you" divided the price of one unit by the quantity again (164 Fish
  Bowls at 53c each read as 0c).

- **Check all stood still on the selling pages.** A check started on Undercuts paused as soon as you
  looked at My auctions (and the other way round), and went on only after you left the page. The
  selling pages now share their checks; only checks of other pages rest there.

- **Est./day counted sales that never happened.** Three leaks are closed:
  - A seller who took a lot down and posted the item again at another price or count was counted
    as a sale. Each lot now carries a seller mark; a lot that vanished while its seller posted the
    item again is a repost, whatever the new price.
  - Your own purchases counted as market demand. Units your characters bought between two scans
    are taken out (merchant purchases are not).
  - One buyer clearing a shelf counted as a day of demand. A scan pair that saw more than three
    times the usual pair is counted at that ceiling.
  Sales measured before this release are dropped once and measured again from the next two full
  scans.
- **A deal never buys more units than were ever seen bought** at its Sells at price (a day rate made
  of two purchases bought ten).

- **Sell all at a merchant sold only part of the list** (17 of 24 stacks in game), and the stacks
  left in the bags were booked as sold. Stacks now go in small batches; a stack counts as sold
  only once it has left the bags; a stack the merchant did not take is sent again, up to 3 times.
  The chat line reports what really sold, and lists any stacks that still did not sell. The button
  reads "Selling..." while the sale runs.

### Changed

- Remove the obsolete immediate vendor seller and unused scan/search helpers; play-session tests
  now use the paced production vendor seller. Reconcile data-schema and freshness documentation
  with current defaults and retention limits.

- **An empty Resale page says why.** It lists what the last scan rejected its items for, the most
  common first, with numbers: sales not measured yet, not bought at the resale price, too few
  purchases seen yet to buy enough ("thin", a new reason apart from "not selling"), profit below
  your minimum, over budget, a day of stock already held, ignored. While the sales data is being
  collected (one pair of scans per item), it says so and when the next full scan comes. Budget,
  item limit and minimum profit are always shown.

- **My auctions** shows "Total on sale: ... (... pending)" centered above the buttons, as
  Auctionator's Cancelling tab does, in place of the "Check prices" hint. Pending is what sold and is
  on its way by mail.

- **Stop.** While anything runs (a Check all, queued searches, the checks of your auctions, a full
  scan, a sale to a merchant), the Check all button reads **Stop** and ends all of it at once.
- **Hover to read.** Hovering a table row shows every column of that row in full under the item,
  and hovering the status line shows all of it.
- **Auto duration, redesigned.** A deposit comes back when the lot sells and is lost only when it
  expires, so Auto now compares, for each duration, the deposits expected to be lost per sale
  (deposit x the chance to expire, over the reposts it takes) and picks the cheapest; when two are
  close or the deposits are the same (the 1 silver minimum), the longer one. In practice that is
  24 hours, unless the house asks far more for long posts of an item that sells slowly. Hovering
  Auto shows the deposit and the expected loss of each duration for the selected item.

- **The evidence behind Est./day is shown.** The deal detail says how many units were seen bought
  at the price, in how many buys, how many from lots bought in part (sure) and how many as whole
  lots, the price range and median. The tooltip has the same in short. Est./day is orange when only
  whole lots were seen. The Est./day header explains what is counted and left out.

- **AddOns list.** ForeverFlip and ForeverFlip Shared Data are listed under **Auctions** (beside
  Auctionator and TradeSkillMaster) with their own icon: a gold coin with flip arrows. The ForeverFlip
  Sync helper writes the new Shared Data TOC on its next update.

- **Faster checks.**
  - Gear is checked straight from its remembered item-key versions. The addon learns them from
    every browse, including the game's Buy tab and other addons, and keeps them between sessions.
    A check of an item listed in 16 endings took a browse plus 16 searches; now it usually takes
    one search.
  - Searches go as soon as the server's throttle is ready, as in Auctionator, instead of a fixed
    0.4 to 1 second gap. Only background work keeps one search per second.
  - An item the client has no auction house data for is loaded before it is searched. The server
    often ignored such a search, which cost a 10-second wait and a second search by name.
- **Check all gives way.** It pauses while you are on **Selling**, **My auctions** or
  **Undercuts**, so **Post** no longer finds the auction house busy. It also pauses while the
  game's own Buy or Sell page is shown, so ForeverFlip no longer replaces what that page shows. The
  status line says when it is paused, and it goes on when you come back.
- **Clicks during a full scan.** Check price, Buy and Post work while a full scan waits for its
  answer. Background work still waits.
- **Scrollbars.** Every table has the auction house's own scrollbar: the same thin track, thumb
  and arrows (Blizzard's MinimalScrollBar textures) in the same place. Drag the thumb, click the
  track or an arrow, or use the mouse wheel. The Deals list scrolls instead of using pages.
- **New players start with no automation.** Automatic full scans, the sniper and automatic deal
  checks are off until you switch them on in Settings. Keeping full scans for the ForeverFlip Sync
  helper is on. Existing settings are not changed.
- **Bids.** Candidates now include auctions that end within 2 hours, not only within 30 minutes.
  They are kept across `/reload` and dropped once their auction has ended. An empty Bids page says
  why it is empty.

- **One price for selling, everywhere.** The item tooltip, the Sell page price box and its
  **Best** column now use one calculation and show the same numbers:
  - **Post at:** one step below the cheapest other seller from a check or a full scan up to
    5 minutes old. Without one, the usual price is used as an estimate. The price is never below
    your break-even or rule minimum.
  - **You get each:** the post price minus the house cut and the deposits expected to be lost.
  - **Profit each:** what you get minus what the stock cost.
- The **Best** column shows the price to post at, the same as the price box, and turns red when
  that price loses money. Before, it showed the net sum, so the column said 23c while the box said
  49c.
- The tooltip no longer prices the auction house from old sales (it said 94c while the market was
  at 50c). The median of sales seen is now its own line, **Buyers paid lately**.
- Deposits come back with a sale, so only expired posts are counted as lost. Before, every post
  was charged, which made cheap, fast-selling items look worse than selling to a vendor.
- **Post AH-worthy** and the Best column compare the vendor with the price that would really be
  posted. Before, they used the cheapest seller even when the posting queue would ignore that seller
  as too expensive.

## [1.2.0-beta.7] - 2026-11-12

Changes since beta.6. Includes the updated addon and ForeverFlip Sync helper.

### Fixed

- The **ForeverFlip** tab appears at the auction house without LibAHTab (no Auctionator or
  TradeSkillMaster installed). The tab is built the way LibAHTab builds it; if the client still
  cannot create it, a plain **ForeverFlip** button opens the page and the cause is reported once.

### Changed

- The Ukrainian tester workbook and the in-game checklist were rewritten: a start sheet with setup,
  status legend, progress count and bug reporting; each check split into preparation, numbered
  steps, expected result and importance; installation, tooltips, Buy tab marks, merchant tab and
  saved data checks added; checks that only ran automated tests removed.

## [1.2.0-beta.6] - 2026-11-12

Changes since beta.5. Includes the updated addon and ForeverFlip Sync helper.

### Fixed

- Posting queues use the client's available posting count across bag stacks instead of only the
  first stack. Post AH-worthy and Post all submit all available matching units, respecting keep
  rules and client limits; Post next bought also uses the full available quantity of its stock.

- Sync re-evaluates its sharing mode after delayed GitHub account discovery or a settings change
  during a transfer. Existing saved scans are reconsidered even when their file has not changed.
- The window title icon uses Tk's PNG photo path, without overriding it with the asset kit's
  PNG-compressed ICO frames that Tk 8.6's bitmap reader cannot decode reliably.

## [1.2.0-beta.5] - 2026-11-12

Changes since beta.4. Includes all earlier beta improvements.

### Changed

- **The Sync helper wears the ForeverFlip Sync asset kit.** The window's app icon, row badges,
  header waves, buttons (default, hover, pressed, disabled) and switches are now the kit's images,
  with its colours and spacing, at the density of the screen's scale (100% to 400%). The executable
  and the taskbar show the new app icon. Anything missing from a build is drawn as before.

- The Sync helper's window follows the new design: a light window with the app's icon and the
  overall status in the header, one rounded card of settings rows (game, GitHub, sharing, addon,
  prices) each with its icon, pill switches, the sign-in code shown large, and the activity log
  behind **Show activity**. The window fits the screen and its content.
- ForeverFlip Sync opens a desktop window on Windows, with remembered game selection, manual
  and automatic sync, opt-in sharing and a background worker. Command-line mode remains available.
- Game discovery accepts installation parents, executables and addon folders, checks Forever
  product evidence, consults running clients and installation records, and asks when ambiguous.

### Fixed

- **Buy at and Sells at are prices of one unit.** The deals table showed what all the units cost
  and bring (after the cut and deposits) next to a tooltip giving the price of one unit sold, so a
  deal of 3 units listed at 93 silver each read as "Sells at 2 gold 59" against "sold at 1 gold 55"
  and looked far above the market. **Cost** is now **Buy at** (the average price of one unit) and
  **Sells at** is the price to list one unit at; **Profit** stays the whole deal's.
- **Check all no longer stops behind a selected deal.** Selecting a checked deal held the
  background checks back for two minutes, so Buy would go at once; when the selected deal was the
  one Check all was reading, its own search waited for itself and the check stood still. The
  selected item's search is never held now, and a selection holds the others for 15 seconds.
- The Sync helper now bundles its Python distribution's required TLS policy resource. Frozen
  builds verify TLS and Tk at build time, preventing a missing-file error before HTTPS starts.
- Sync errors name what failed: the missing file, the GitHub answer or the lost connection,
  instead of a bare "[Errno 2] No such file or directory".
- Sync uploads are acknowledged only after successful submission; partial progress is persisted,
  failed uploads can retry, and missing credentials can be refreshed without restarting.
- SavedVariables parsing no longer copies the remaining file for every table key.
- Resale now distinguishes missing sales observations from spending limits. The Sales data
  counter shows items with measured observations, and the empty list shows the current purchase
  budget and per-item limit instead of always asking for two scans.
- A money gain re-evaluates still-cached scan leads locally in small slices. Results remain
  unverified; live checks (including negative results) and items already bought supersede old
  scan rows. An unaffordable first lot is reported as budget-limited.

### Added

- **Addon updates and beta testing in the Sync helper.** The helper looks for new ForeverFlip
  releases at start and every 6 hours and installs them (or only announces them, if automatic
  updates are off). **Beta tester** adds the pre-releases; leaving the beta never downgrades. Each
  download is checked against GitHub's SHA-256 and the TOC version, the previous version is kept as
  a zip backup, and a failed swap puts it back. `--update-addon`, `--beta` and `--no-beta` do the
  same from a console.
- **Sign in with GitHub inside the Sync helper.** The window's button (or `--login`) shows a code
  to enter at github.com/login/device; the GitHub CLI is no longer needed. The sign-in is kept
  encrypted for the Windows user, and **Sign out** (`--logout`) removes it. Sharing scans is
  available only when signed in.
- **Community-history check of shared scans.** A confirmed scan's prices are compared with the
  summaries of the last 3 days: items more than twice or less than half the community's price are
  left out, and a scan mostly out of line is not published ("disputed").

## [1.2.0-beta.4] - 2026-11-12

Changes since beta.3. This is a pre-release; use the current beta checklist before reporting results.

### Fixed

- Single-item checks promote matching batch requests and run before the remaining batch. Gear
  batches pause between versions and resume without discarding their partial results. Requests
  already sent to the server keep their response ownership instead of being cancelled locally
  and sent again.
- Browse pages, full scans, bids, purchases and posts no longer compete with an unresolved
  outgoing trade or search. Automatic scans wait while the player is preparing a purchase.
- Button feedback is painted on the next frame, before background calculations. Purchase and
  post status take precedence over paused batch progress. Local scan/sharing/analytics slices
  shrink while an interactive action is pending.
- Opening Selling no longer searches all bag items. Posting queues prepare missing prices on
  request, after trying ready items first; fresh scan prices are used in the same click.
- Scan recovery keeps its cursor between frames, so unloaded rows at the front cannot starve
  loaded rows at the end. Large browse replies and the unread-row pass are processed in slices.
- Analytics keeps bounded top-50 rankings during its incremental build; medium histories also
  build between frames. Incompatible lot buckets are rejected without repeated pairwise scans,
  and own-unit counts are indexed once per own-auction snapshot.
- A general auction house error no longer discards an awaiting item purchase or claims another
  player bought it. Money, purchase events and matching auction-won messages can still confirm it;
  without confirmation the normal timeout applies. Purchase failure messages no longer guess who
  bought the lot.

### Changed

- Buying and confirming a commodity use the same button. A checked deal remains ready for five
  minutes, and selecting it holds background searches while the player prepares to buy.
- The native auction-house styling, side menu, settings, coin display, merchant tab and scrolling
  lists have been updated. Selling includes actions for gear the character cannot use.
- Full scans keep partial server replies separate from complete scans and preserve pending scans
  across closing/reopening the house. Retry timing respects the account's full-scan window.
- Reposted or merely missing lots no longer count immediately as sales. Sale estimates use
  confirmed observations, older contaminated estimates are cleared once, and FF3 shared histories
  avoid importing the old FF2 sale counts. Buyer invoices use the actual item count.
- Undercuts compares waiting, reposting, buying out and vendoring from measured demand; buyout
  entries use the player's resale price and count down as the requested units are bought.

### Testing and release tooling

- The beta.4 checklist replaces obsolete beta-specific instructions. Previous regression tests
  remain; standalone test entrypoints now include classes added later in their files.
- Release notes select the exact beta changelog section. Packaging and release-note selection
  have automated tests, and generated checklist links point to the release tag.

## [1.2.0] - 2026-11-11

Fixes and features from a study of the WoW Forever auction addons (ForeverForge Auction, auxForever,
AuctionHouse Forever, Auctioneer (Forever), TheWoWDB, Price Scanner Forever, ForeverSell, Forever
Auction Master, Arbitrage, WOW4E AH Trader) and of the Forever branches of TSM and Auctionator.

### Fixed

- **Checked deals stay ready for 5 minutes** instead of 2: checking a page of gear deals takes longer
  than 2 minutes, and the first ones went back to "check again". A lot's buyout never changes, so a
  lot gone meanwhile only makes the purchase fail. Background searches wait 2 minutes for a selected
  deal, as before.
- **Posting needs no price search after a full scan:** for 5 minutes the scan's lots of each item
  stand for a search (items the player has listed are still searched).
- **The merchant's lists update by themselves** once the bags settle after Sell all.
- **A scan the server did not answer no longer keeps the next ones away.** After 5 minutes without an
  answer the next try came a minute later, but the server counts its 15 minutes from every call:
  each early retry started them again (in game: unanswered at 04:08, 04:14 and 04:23, read at
  04:38). The next try now waits 15 minutes and 20 seconds from the unanswered call, and regular
  scans keep the same 20 seconds of margin (a call 15:00 after the last one went unanswered).
- **Full scans no longer read a part of the answer.** The server sends the list in parts; a part
  was taken as the whole once one partial scan had been read, because the next one was measured
  against it (seen: 28 672, 30 720, 73 728 of about 250 000 auctions in a row). Lists are now
  measured against the largest complete scan of the last day, the answer event is ignored for a
  part, and a part waits 60 quiet seconds. A list that stays partial until the end of the wait is
  read for its prices but marked partial: it counts no sales and does not lower the measure.
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
- **Deals columns: Name, Qty, Cost, Sells at, Profit, Est./day, Status.** Cost is what buying all
  the units costs; **Sells at** is what selling them brings after the cut and the deposits, from the
  price the market really pays (just below the next seller, at most the usual price and what a
  quarter of the sales seen reached, only as many units as sell in a day); Profit is the difference;
  Est./day is how many sell a day at that price. The headers explain them on hover. The Selling page
  says what buyers paid lately and how many units a day sell at the suggested price.
- **A check stays valid for 2 minutes** (was 45 seconds) before a deal says check again; background
  searches still wait only 45 seconds for a selected deal.
- **Searches of items answered under their exact key** (with an item level) are read under that key:
  they ended as "without an answer" (WoW Forever scrolls). An item whose search gets no answer at all
  is searched by name the next time, like gear.
- **Posting says what really happened:** "Posting..." until the game confirms the auction, a post
  the server throws away or never confirms is reported, and a search in flight steps aside for the
  post. The Selling page reads the prices of the posting queues ahead, so the first press posts.
- **Selling is more compact:** the rule fields moved into a panel opened with **Rule...**, Check
  price is a small refresh button beside the price, and the list shows 12 rows. Check all is
  narrower.
- **Full scans are read whole again:** the server sends the list in parts with pauses between
  them, and a scan was read after one quiet second: in game only 1024, 2048 or 24576 of 300 000
  auctions, so most deals were missing. The list must now stay unchanged for 5 seconds, and a list
  far smaller than the last full scan waits longer.
- **Bag items stay on Selling while a full scan is awaited** (the game then says no item can be
  posted).
- **The menu is the auction house's:** the Buy tab's own category buttons are copied at run time
  (their textures, from the fields WoW Forever's list keeps them in), the side panel is as narrow as
  its list, and the pages of an entry open under it, indented, like the subcategories of Weapons;
  the row of tabs above the page is gone. `/ff look` prints what the native buttons are made of.
- **New look:** money is shown with gold, silver and copper coins everywhere (price fields keep
  `1g 20s 5c`), table rows use the normal font, the tabs above a page share its width (they ran past
  its edge), and the top buttons sit a little further left. Money shows its two largest coins (gold
  and silver, or silver and copper), so it fits the columns. The side menu is larger. At a
  merchant, the merchant's own item pages are hidden while the ForeverFlip tab is open (they showed
  through it). The side panel is narrower, and its entries are dark plates with a thin border
  (gold when selected). Item names in the tables have no brackets, and Shift-click puts an item's
  link into the chat line.
- **Merchant buy list redrawn:** each item shows its icon, its name in its quality colour, the price
  here and on the auction house, the profit each and the sales a day, with Buy N and the cost of the
  purchase on the right. More offers than its four rows scroll with the mouse wheel; the title
  counts them.
- **Gear I can't use:** a button at the merchant sells the equipment your class can never use, bound
  or not (unbound pieces only when the auction house would not pay more).
- **Auto duration is careful:** it counts the other sellers' units ahead of yours, keeps three
  times the expected time to sell (2 hours only for a sale expected within 40 minutes, 8 hours
  within 2.7 hours), takes 24 hours when the sales data is old or thin, and uses your own sales of
  the item once 3 were sold. Before, every sale of the market counted as yours and lots expired.
- **A slow purchase is not reported as failed too early:** an item purchase waits 30 seconds for
  its money to leave the wallet (it was 10, and in game the money left later, after "did not go
  through"); after that the wallet is still watched 3 minutes and a late purchase is booked then.
- **Buy is enabled for every ready deal:** the background rests as long as the selected deal is
  ready (it rested only 45 seconds, so a ready deal's Buy turned grey). When a search is still
  answered at the click, the status says so and the background rests 5 seconds for the next click.
- **A purchase or a post goes out only on a free way to the server:** Buy is enabled while no search
  waits for its answer and the server is ready (the background rests while a checked deal is
  selected). A purchase sent behind an unanswered search never left the game (no money spent, "no
  answer" after 30 seconds). An item purchase whose price has not left the wallet after 10 seconds
  is reported as not gone through, and the deal is checked again.
- **Items whose plain search gets no answer** (recipes, WoW Forever scrolls) are searched again by
  name at once, in the same check.
- **Buying and posting go through at once:** the sniper and the automatic checks wait while the
  Selling page is open or a freshly checked deal is selected, so the server is free for the click
  (with the sniper on, posts were refused as busy and purchases thrown away). An item purchase is
  confirmed by its price leaving the wallet: the purchase event does not always come on WoW Forever,
  and the chat line "You won an auction" is hidden from addons on newer clients, so purchases waited
  30 seconds. A purchase the server throws away is said at once.
- **Selling text** is smaller and the market line is one line, so it no longer runs into the price
  row.
- **Merchant: a ForeverFlip tab and Sell to vendor.** One button on the Merchant tab sells everything
  a merchant pays the most for (Best = Vendor on Selling, and vendor-deal stock), except hidden
  items, items with a keep rule and resale stock. The ForeverFlip tab beside Merchant and Buyback
  lists it, with Sell all, and the items to buy here for the auction house (the side panel is gone).
- **Buying at a merchant** goes one stack per purchase and only as much as the bags hold: buying
  several items that do not stack (throwing weapons) ended in "Internal Bag Error".
- **Vendor deals are back:** the vendor-price safety margin is 0% by default (it was 20%, and the
  saved 20% is reset once). Every merchant price checked in game matched the client's, and the
  margin left 1 of 74 items listed below their vendor price.
- **Latency audit fixes:**
  - a single check (a click) goes before a running Check all and takes the place of a background
    search in flight; searches wait for a full scan only while it waits for its answer;
  - a price offer nobody confirms ends after a minute; a request the game refuses ends after three
    tries and does not count against the 100 searches a minute; a sniper candidate whose search could
    not start stays in the list; the full scan can release a stuck throttle itself;
  - selecting another deal drops the price offer of the previous one, and Buy next confirms the deal
    it shows; the status line follows a purchase (asking for the price, confirm, buying);
  - Selling: the selected item follows its bag slot (also when scrolled out of view), a filled-in
    price follows a new check while a typed one is kept, nothing is filled in while you type, Post
    is enabled as soon as a price is typed, a second post waits for the first, an auction is not
    cancelled twice;
  - answers that come after the auction house closed check nothing; a repeated answer does not use
    up a page; a bid check without an answer does not read old results; an auction house error ends
    only a purchase sent a moment ago; item data is not asked for twice in a row;
  - mail the game keeps refusing stops the mail job instead of looping; an error in one part of the
    frame update no longer stops the others; the window redraws every second (timers, messages);
  - the bags are read once per frame (a Selling refresh read them six times or more).
  - a scan shared by another player is decoded and merged a slice per frame (20 000 items took
    over 100 ms in one go when it arrived); Analytics works out a large history a slice per frame
    and shows the previous lists meanwhile.
- **Faster buying:** after a purchase the deal is worked out from the lots already read, so the next
  lot is bought on the next click without a new search; a click on Buy no longer waits for (or is
  disabled by) a search in flight. Before, every purchase searched the item again, and the Buy
  button of every other deal stayed off until that search ended.
- **Sell vendor deals never sells at a loss:** units of a vendor deal bought while resale stock of
  the item is held join that stock; before, the whole stock turned into a vendor deal and its dearer
  units were sold to a merchant too.
- **Price checks of items with very many lots** take the cheapest lots of the first pages; they no
  longer end as "without an answer" (seen with WoW Forever scrolls listed hundreds of times).
- **Tables scroll with the mouse wheel:** a list longer than its rows (Selling, Bids, Crafting,
  Shopping list, Analytics) showed only its first rows; the first header shows which are on screen.
- **Check all tries unanswered searches again** by itself, says `(N without an answer)` instead of
  "failed" and names those items in the chat; items a fresh full scan did not see are not searched.
- **The summary no longer repeats the auction house**; it is named in the bottom bar.
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

- **Buying is one button.** Gear and items are bought in one click; a commodity in two, as the
  game wants: the first asks the price of the whole quantity, and the same button then shows
  "Confirm" and the total. A selected checked deal, or a Buy click that found the way busy, holds
  Check all and the next steps of gear searches back, so the purchase goes within a second.
- **Sales no longer count reposts.** A lot that vanished while a new lot of the same price and
  count appeared was posted again, not sold (in game: one seller's 65-80 silver bracers read as
  sales while the item sold at 3-4 silver, and Sells at came out ten times too high). The resale
  cap also stays within three times the median sale.
- **Buy did nothing after Check all.** The server sells gear and items only from the last item
  search, so a lot read before other items were searched was dropped without an answer. Buy now
  reads such a lot again first and asks for one more click.
- **Buy out (Undercuts) resells.** Units bought out against an undercut are resold at your price,
  not kept for own use; the shopping list counts them down ("N left to buy, one auction per click").
- **No resale at prices nobody paid.** An item watched for an hour or more without one confirmed sale
  is no resale deal: the prices others ask are not a price to resell at (in game, gear bought at 27
  silver to resell at 94 silver, all of it expired). One or two confirmed sales already cap the
  resale price.
- **Sales measured with reposts are dropped once.** Sold units, the flow and the daily sold counts
  saved before are cleared at login and measured again; prices stay. Shared scans are FF3 now: the
  sales of FF2 texts (older versions) are not read, their prices are.
- **Sale invoices booked no sale.** The count of an invoice was read from the wrong value (the minute
  of delivery, nearly always 0): sold stock stayed open, statistics missed the profit and the sale
  rates counted only failures, which lowered the trust of items that did sell. The count is read
  right (or from the subject's "(5)"), and invoices saved before are booked once at login.
- **A vanished lot is a sale only once the next scan confirms it.** Until then it is a suspect: if
  the same price and count comes back as a new lot, it was cancelled and posted again. An item gone
  from the house altogether confirms its suspects; a lot that got smaller is a sale at once (an
  auction is cancelled only whole). Every sales figure uses confirmed sales only: sold per day,
  sale prices, the daily history, shared scans, and the flow model when the lots cover the item.
- **Anti-undercut (Selling → Undercuts).** For every auction of yours another seller undercut, each
  way out is priced in expected money from the item's measured sales (Poisson chances of selling in
  the time left or the new duration): wait, undercut (cancel and post one step below), buy out the
  cheaper units (through the shopping list) and sell everything at your price, or a merchant. The
  best is advised, every option has its button, Answer next acts on the next one where acting
  pays, and price wars (three answers in a day) are marked. A full scan that names the owners
  checks your auctions without searches and the chat tells how many are worth answering.
- **Every scan is shared, not only the last one.** In game, Sharing sends the price history: per item
  the daily records of the last 7 days (cheapest and usual price, units listed, units seen sold),
  which hold every full scan of those days, with the last scan's prices (format FF2; FF1 texts and
  the community data are still read). Received days fill the history and the sales data. For the
  Sync helper, up to 8 full scans are kept until it has uploaded them (it tells the game which, in
  the ForeverFlip_Shared addon), instead of the last 2.
- **Settings pages in the side menu** (General, Key bindings, Sharing, Safety), each laid out in
  sections with headings.

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

[Unreleased]: ../../compare/v2.1.0-beta.1...HEAD
[2.1.0-beta.1]: ../../compare/v2.0.0-beta.1...v2.1.0-beta.1
[1.2.0-beta.6]: ../../compare/v1.2.0-beta.5...v1.2.0-beta.6
[1.2.0-beta.5]: ../../compare/v1.2.0-beta.4...v1.2.0-beta.5
[1.2.0-beta.4]: ../../compare/v1.2.0-beta.3...v1.2.0-beta.4
[1.2.0]: ../../compare/v1.1.0...v1.2.0
[1.1.0]: ../../releases/tag/v1.1.0
[1.0.0]: ../../releases/tag/v1.0.0
