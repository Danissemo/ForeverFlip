# Changelog

All notable changes are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).


## [Unreleased]

## [3.1.0] - 2026-11-17

### Added

- **The addon says when a newer ForeverFlip is out.** The game gives addons no internet, so the
  ForeverFlip Sync helper writes the newest release of your channel (stable, or beta if you are a
  beta tester) into the community data. At login the chat names the new version, and the status
  line and the sharing page of Settings show it until you update. Needs Sync running; nothing is
  said when your version is the newest.
- **Every auction house has its own prices and header.** Alliance, Horde, the neutral goblin houses
  (15% cut) and the hardcore realms' houses are kept apart; connected realms share one house, so a
  scan shared from a connected realm joins yours. The tooltip opens with
  `=========== FOREVER FLIP: ALLIANCE AH ===========` (Horde, Neutral, Server) and closes with a
  `=== X ===` rule, so it is clear where ForeverFlip's part ends.
- **Retail support**: on Retail one house serves both factions, shown as SERVER AH; the TOC lists
  the Retail interface (120105) next to WoW Forever's 16001. Item tooltips the game keeps secret
  (Retail 12, in combat) are left alone instead of raising an error.
- **A trace of what the addon does**, to find what makes it hang: every search, check and slow
  moment with its time and reason, kept in the saved data (`ForeverFlipData.trace`, `traceStats`,
  `traceSlow`). `/ff trace` shows it, Settings → Messages → Developer turns it on or off, shows and
  clears it.
- **DEV mode** (Settings → Messages → Developer, or `/ff dev`): every click, check box, page and
  game event goes into the trace with how long it took. Off by default; a slow action is traced
  either way.

### Fixed

- **Check prices on My auctions no longer hangs on gear with many versions.** A ring known in 35
  item-key versions was searched one version after another, 25 seconds on "checking...", though
  only one of them had lots. Every gear check with four or more remembered versions now asks their
  prices in one query first and reads only the versions that are listed; with none of them listed
  the item is answered as nobody else selling it.
- **The merchant tab's offers stay on their own lines.** "Vendor … · AH …" with large prices ran
  onto a second line, over the profit line and the next offer. A line that does not fit beside the
  Buy button now leaves out its labels ("36 40 -> 46 00", "+2 95 · ~1.1/day").
- **Check all no longer stands still** ("Checking Bags: 14/15" for good): after 45 seconds without
  progress, and with nothing you do holding it (a scan, a purchase, a post), the item it waits for
  is given up as "no answer" and the rest go on. The trace says what held it.
- **Bulk buttons go down the list as you sorted it**: Check all, Post all, Post AH-worthy, Post
  next, Check prices, Cancel next undercut and the undercut answers take the top row first, on
  every page, in the order shown now.
- **Auto duration picks shorter posts where they save deposits.** It now counts how often the item
  is undercut (an undercut lot stops selling, so a long post mostly waits behind a cheaper one) and
  the item's own posts that sold against those that expired. Posts remember the duration they went
  for, and the duration tooltip on the Sell page says where the estimate came from.
- **The tooltip's header and footer sit centred across the tooltip again.** An item's long "Use:"
  text no longer stretches them across the screen, and both rules now reach the right edge: a
  two-column line was counted 20 px narrower than the game draws it (the game puts 40 px between
  the columns), and the "=" count was rounded down. The whole rule is now measured and "=" added on
  both sides until it reaches the widest line.
- **No more "no answer" on My auctions** when nobody else sells the item: the auction house's
  silence about it means your auction is alone, and it says so.
- **The tooltip rules reach the end of the price lines.** A coin icon sits 2 px to the right of
  where a measure puts it, and a price line has up to three: the rules came out a sign short. The
  icons' shift is counted, and a rule now stops within half a sign of the widest line.
- **Item names no longer blink to "item:12047"** while a quick scan checks its finds: when the
  game drops an item from its cache for a moment, the row keeps the name it showed.
- **Check all goes strictly top to bottom.** An item whose search got no answer is sent again at
  once, before the next row; it used to wait for the end of the batch, so a row above the one being
  checked kept its scan status and looked skipped.
- **Gear with many versions no longer hangs Check all.** One version of an item the server did not
  answer ended the whole search, and the check started over from the first of its 23 versions:
  Nomad Trousers stood on "checking..." for half a minute. Now that one version is asked once more
  and the versions already read are kept.
- **The tooltip's header and footer are the same width.** Each had the same number of "=" on both
  sides, so its width moved two signs at a time, and the "X" line could stand a sign out past the
  header. Now one side may hold a sign more, and a few spaces around the middle take up the rest.
  The widths are measured in the font the tooltip's own lines are drawn in, not in a font object of
  the same name that kept "=", spaces and letters in other proportions. In DEV mode the trace keeps
  the expected and the drawn width of both lines (`tooltip.rules`). That trace showed the game
  drawing the "X" line 5 to 6 px wider than measured while the header came out as measured, so the
  addon now learns that difference from the tooltips it has drawn (per font, kept in the saved
  data as `tipSkew`) and aims the "X" line short by it.
- **The summary under the menu is no longer cut short.** Its lines were counted once, when a page
  was opened; if the window was still being laid out, only four lines fit and the sniper's figures
  were gone until another page was opened. They are counted again at every refresh now.
- **Quick scan works with the sniper on.** While the full scan waited its 15 minutes, the button
  only counted down whenever the sniper ran, so Quick scan could not be pressed. Now it reads one
  whole round of its own and lists what it finds, and the sniper goes on afterwards. Switching the
  sniper off no longer cuts a quick scan short.
- **Check all reads gear much faster.** Each version of an item waited for the auction house's
  throttle, so a piece of gear with 30 versions took about 20 seconds. Check all now asks the
  lowest price of all versions in one query and reads only those that could change the deal; if
  that answer does not come, every version is read as before.
- **Analytics: the list buttons stay inside the window.** The seven buttons above the list (Bargains
  … My results) share the row's width instead of a fixed 96 px each, which pushed My results past
  the edge.
- **Analytics: Today's chart goes hour by hour** instead of one block filling the chart; 7 and 30
  days stay a bar a day.
- **After a buy out on Undercuts the row says "bought"** instead of a grey "wait", and the price is
  checked again, so the next answer comes from the new market.

### Changed

- **The addon's files are sorted into folders**: `Core`, `Locale`, `Modules`, `UI`, as other addons
  do. Nothing about the speed changes; the game loads the same files in the same order. Because
  files moved, the game needs a full restart after the update, not a `/reload`. The zip now
  carries `README.md` and `CHANGELOG.md` next to the licence.

### Development

- DEV mode also traces every status message, and the posting buttons trace each item they post,
  hold or wait for (post.go, post.held, post.wait), next to every click and its time: "the button
  did nothing" can be read from the trace.

- **`python tools/devflow.py release X.Y.Z`** makes a release in one step: commits what is pending
  (documentation too), writes the version into the TOC, `Core/Util.lua` and this changelog, checks
  the package builds, commits, tags and pushes; GitHub Actions publishes it. It asks to type the
  version again first.
- The trace records why the Undercuts buttons are disabled (`fight.buttons`, DEV mode) and what
  an own auction's silent search was (`owned.silent`).

## [3.0.0] - 2026-11-17

The first full release after the 2.x betas. Resale and Market reset are separate strategies again,
each priced from the market's own sales: Resale buys only what sells in a day at the price where
Sure expects the most money. One Sure and one sell price across Deals, Bids, My items and the item
tooltip, with Est./day and Sure for gear seen too rarely to measure. The full scan is about twice
as fast and records every item it sees; Check all asks the server once for a whole page. The
tooltip has a new layout with a market reference, a production chain and a price chart, and Sync
now restores the scans the history lacks. Settings, Analytics → My results, sounds, window size
and Reset all data are new.

### Added

- **Bids has a Sure column**: 100% for a lot a merchant pays its worth for, otherwise how sure the
  resale at the usual price is, as on the Deals pages.
- **Check Sure on Bids and on Market reset**, as on Resale: type a sell price, see Sure, sales a
  day and profit at it, Reset brings the own figures back. Market reset lost its Per item / Per day
  / % of gold boxes; those limits stay on Settings → General.
- **My items shows Sure for gear with no sales of its own**, from the item's other endings, greyed
  with "~", as on the Deals pages.
- **Gear seen too rarely for any estimate** (no sales of its own, no other ending sold) now takes
  Est./day and Sure from gear of about the same usual price, greyed with "~"; the Risk line says so.
- **Sounds for a sale and an outbid** (Settings → Automation → Notices, both on by default): a coin
  sound when one of your auctions sells, an alarm when a bid of yours is outbid. Several sales in a
  few seconds make one sound, not a chorus; the deal sound works as before.
- **Window size** (Settings → Display): 90%, 100% or 110%. Smaller fits more rows in the lists on a
  small screen; the window stays in its place in the auction house. Reset settings brings 100% back.
- **The Data page says what is saved**: prices of how many items on this auction house and on all of
  them, journal entries, items in stock, when the last full scan was, and whether the last logout
  had to leave old prices out to keep the saved file loadable.
- **Analytics → My results**: every item that earned or lost in the chosen period (day, week, month)
  with its profit, money in, units sold and return on what it cost, best first. The daily chart and
  top three already said how the period went; this says which items made it.
- **`tools/savedata.py`** keeps copies of the saved data outside the game (`backup [label]`, `list`,
  `restore <name>`). A copy inside the game is not possible: the saved file is already close to
  what the client reads back. Restore refuses while the game runs and copies what is there first.

- **Settings has seven pages.** General keeps the numbers (profit, money, Limits) and gains the
  **Market reset** limits and the **auction duration**, the same settings as on the Deals and
  Selling pages. **Automation** holds what runs by itself and the notices, **Display** the tooltip
  and Buy tab marks, *Learned recipes only* and the language, and **Data** what ForeverFlip learned
  (shown in full, no longer behind a hover) and the two resets. Each option says what it does
  under its name.
- **Reset settings** (Settings > Data): every setting back as on a new profile, the Careful preset
  and nothing running by itself; prices, sales, journals, the language and key bindings stay.
- **Market reset** (was Under market) is now its own strategy, not a second Resale: it buys every
  lot listed under the price it relists at, or nothing, so the relist is the cheapest left with no
  competition below. Resale still buys only part of the lots, up to a higher price that stays.
  The page's table is no longer dim, its text no longer overlaps, and the useless checkbox is gone.
- **The purchase strategy is kept.** A lot bought on Deals → Resale, Market reset, Bids or To vendor
  remembers its strategy; Selling → My items sells it that way and Best no longer overrides it. Only
  after 14 days, when the original route no longer pays, does Best decide again. The same lot may
  be offered on several Deals tabs, each with its own strategy.
- **Journal and Profit follow the strategies**: All / Resale / Market reset / Bids / To vendor /
  Crafting / Disenchant, in the order of the Deals tabs, and a purchase says what it was meant for
  (a market reset, disenchanting, the shopping list).
- **Crafting shows Sure** after Est./day when the product goes to the auction house, and **Best**
  replaces "Sell to": the route is chosen by the same rule as on My items (AH, Vendor, or AH / V
  when it is a close call).

- **Reset all data.** Settings → Messages → Saved data (or `/ff reset`) forgets every price, sale,
  journal, position and the shopping list after a confirmation, keeps your settings and reloads:
  a clean start to learn the market anew.
- **Check Sure on My items works as on Deals → Resale**: the price to check has its own box beside
  the button (Enter checks too), so the posting price stays as it was, and the item's row shows Sure
  at that price with the price in blue.

- **Stop quick scan.** While a quick scan runs, the scan button reads Stop quick scan; what it
  read is kept.
- **All shows a lot that pays both ways**: Deals → All adds a green "+ vendor" or "+ resale" after
  the name when the same lot is also on the other page.
- **Why that resale price.** Hovering a Resale lot says why the sell price is what it is: just under
  the next lot still on sale, what buyers really paid lately (the median asking price rarely sells),
  or just under the usual price. The tooltip shows a **Sales reach** line when real sales stay well
  under the usual price, which is why Resale can sell lower than the tooltip's median.
- **Quick scan while the Full scan waits.** The server allows a full scan once in 15 minutes;
  in between, the scan button offers **Quick scan**: one browse of the whole house (the way TSM
  reads it), the cheapest price of each item recorded and the likely deals checked, at most three
  minutes. The status line counts the items read and the ones left to check. The lowest price in
  the tooltip is the newer of the Full scan's and the Quick scan's.
- **The item tooltip in a new layout**: FOREVER FLIP and the house, then **Selling** (vendor,
  lowest and median AH price, craft and disenchant values with what they bring at today's lowest
  prices, best and worst time to buy, Recommendation, with "A or B" when two routes are within 3%),
  **Demand** (your last scan, sales a day, recent sales, Sure at the post price) and
  **References** (community data, 14-day median / mean, trend 3d / 7d / 14d).
- **Messages in their own chat tab** instead of a separate window.

- **Sure and Est./day now say how much they can be trusted.** They are measured from the raw
  scans again (scan pairs, lot sizes, disappearances), each with 80% limits and the sample behind
  it. Below the threshold the number is replaced by **No reliable data** and the reason (too few
  scan pairs or hours, old data, measured by an older version). The first login after the update
  rebuilds the statistics in the background (the Full scan button says so) and keeps the old ones
  for 7 days; `/ff stats rollback` restores them. Items with no raw scan keep their values, marked
  as measured by an older version. Analytics shows how often your posts really sold against what
  Sure predicted, once there are enough of them.
- **Below usual price**, a second resale strategy, on by default: lots under the item's usual price
  (its median of the last 7 days), relisted at it, with their own limits (per item, per day, half of
  your gold), the same buy confirmation and price checks, and the risk on every deal. Items without
  reliable sales data are shown grey with "few sales data" and buy at most a day of sales (one unit
  while none is measured), so the page is usable before the sales are measured. An empty page says
  why: off, no sales measured yet, or what stopped the last scan's items, the most common first,
  with the gold left for today. A dev build that saved it off at 20% moves to the new defaults once.
- **Production chain** in the item tooltip: auction (after the cut, with Sure), vendor, disenchant
  and craft into a learned recipe, best first.
- **Journal chains**: a held item you craft or disenchant carries its cost into the products, and
  the lot's history shows what the products brought and the chain's profit.
- **Price chart** in the item history: 14 days of the usual and cheapest price plus scan points,
  gaps shown as gaps.
- **Log window**: ForeverFlip's messages go to its own window instead of the general chat; errors
  still echo to chat and a sound can mark them (both settings).
- **Crafting section** with Crafting and Disenchant pages. Disenchant left the settings, and the
  page says why it is off when it is. The crafting tooltip looks like the item tooltip.
- **Today** period in Analytics; **Check Sure** with your own price on For sale, and **Reset**.
- **The sniper keeps out of your way in the Buy tab.** A search of your own, or an open purchase
  page, stops and pauses it (it used to take over your search and page through it, changing the
  list as you read); it resumes after a minute of quiet or on ForeverFlip's page.
- **Market reference** in the item tooltip and history: your scans and community scans side by
  side (median, mean, days, last seen), the 3/7/14-day trend and an undervalued note that needs
  enough data. Undermine Exchange has no documented API for WoW Forever, so it is not used.
- **Community status you can trust**: Sync tells uploaded, published and downloaded apart with
  their times, and the addon says **No community price yet** and why.
- Auction and vendor are judged apart: **Best** shows AH / V, and a deal can be either.

### Changed

- **The item tooltip is easier to read.** Every name is on the left and its figures on the right
  (ages and notes in grey beside the value). The vendor price is for the whole stack, as the game's
  Sell Price line, with the price of one in grey. The recommendation is one short line, *Auction at
  5s 48c* or *Vendor at 75c*; the reason under it appears only when another route pays nearly as
  much. Sure on the Demand line has the colours of the auction house window.
- **Choose AH and Choose vendor** on Selling → My items show their whole names again: after the
  short labels (AH / Vendor) were used once, the full ones stayed cut to the old width.
- The status summary under the menu keeps only the lines that fit: with Analytics and its views
  open it no longer runs under the money and out of the window.
- *Usual price* and *Posts sold* are a little wider, so their Ukrainian names are no longer cut.
- **Column headers agree across the windows.** One name for one thing (*Buy at* in the Journal,
  *Cheapest other* on Undercuts, *Cheapest* on the shopping list), the same widths for Qty (50),
  Sure (60) and Best (70, left-aligned, as it holds a word), and the shopping list loses its
  *Source/status* column, which repeated Status. Ukrainian headers that were cut short got shorter
  names (*Шанс*, *Нова ставка*, *Днів продажу*, *Продаж/д*) or wider columns; a header that still
  does not fit names its column in full when hovered.
- **One rule for the most to pay.** Bids, Sniper, Disenchant and vendor deals share
  `Market.maxBuy`: a disenchant purchase now needs the minimum return as well as the minimum
  profit, so thin disenchant deals are no longer offered.
- **Disenchant against selling.** Gear whose vendor price or auction price (after the cut and the
  deposit) brings as much as disenchanting is no longer a disenchant deal.
- Colours: one shade per meaning; the slightly different oranges and greys are now one each.
- **Deals tabs in the order** All / Resale / Market reset / Bids / To vendor.
- **My items**: Qty and Sure are written in full (the room comes from Name), the buttons sit in
  even rows, the "*" after AH / Vendor is gone, and Choose AH / Choose vendor appear only for a
  really disputed item. Reset now also forgets your AH / Vendor choice.
- **Undercuts** shows every column title (the room comes from Name); **My auctions**' last column is
  simply **Time**.

- **Fresh data is "still being learned", not "not sold".** An item watched for less than an hour of
  full scans that has not been seen sold yet is counted as still being learned on the empty Resale
  page. Before, a new profile or a reset read as if nothing in the house sold.
- **My items → For sale reads at a glance**: Best names only the route (AH, Vendor or AH / V), a new
  Profit column says what it brings for the units held (both sums while you still have to choose),
  and Sure is shown only for the auction house, since a vendor buys at once. Listed is gone. An item
  waiting for your route says so in red in Note, and its hover explains that a vendor will not be
  offered it until you choose. The buttons now run Hide, Rule, Choose AH, Choose vendor, then the
  Check Sure box, Check Sure and Reset; Reset also undoes the route chosen for an AH / V item.
- **For sale fits its columns**: Cost each is gone, Profit of an AH / V item reads just "N / N"
  (auction house first), and Note says a short red **Choose** (its hover explains the choice). The
  buttons spread over the whole width, scroll bar included, in four groups: Hide and Rule, Choose AH
  and Choose vendor, the Check Sure box with its button, and Reset at the right edge.
- **Below usual price is now Under market, and it offers something from the first scan.** It needed
  3 days of prices per item, so on a fresh profile it said "19464 have fewer than 3 days of prices"
  and stayed empty. With fewer days, the lowest of what is known (the days there are, the last usual
  price, the measured market price) is the target, and such finds are shown grey (few data) and buy
  at most a day of sales. The 7-day median takes over once there are 3 days.

- **Best stops asking when the answer is plain.** When both the auction house and a vendor pay,
  Best no longer always reads AH / V: a vendor that pays no less than the auction house's profit
  wins, and so does a vendor when the auction house, counting the chance it does not sell, would add
  under 10%. The auction house wins when it should bring clearly more and nothing makes it doubtful,
  or when it is doubtful but the vendor pays under half of it. Only a doubtful auction house (Sure
  under 50%, too few sales seen, or rivals answering undercuts) with a fair vendor price is left to
  the player, and the Why line names the doubts.

- **Settings → Sharing → Status in two even columns**: the labels in one column, one fact a line
  beside them, so nothing wraps under a label any more.
- **The full scan reads the house about twice as fast.** Reading the 200 000-odd auctions the
  server sends takes 12 ms a frame instead of 6, and a click or a price check slows it to 6 ms
  instead of 2 (a purchase still to 2). The frame rate drops a little while the list is read; every
  auction is still read.
- **Full scans finish sooner.** While the server prepares the answer (2 to 10 minutes), the data of
  every item this house listed before is loaded, so far fewer rows wait for item data once the list
  arrives. Auctions of items the server no longer has are given up at once instead of holding the
  end of the scan back by 30 seconds; their lots are not counted as sold.

- **Save in Settings is off when there is nothing to save.** It turns on once a box is changed
  and says "Nothing to save" on hover otherwise; check boxes and presets are saved at once.
- **Vendor price is the game's Sell Price, without a "confirm" note.** It is the same figure the
  tooltip's Sell Price line shows, and merchants paid exactly it for 113 of 115 items sold by hand
  (the other two were worn gear). The note asking to sell one to a merchant first is gone, and so is
  the `*` on vendor deals, unless the safety margin is set. A merchant paying a different price for a
  non-gear item still replaces it, with a note on the tooltip.
- **One Sure, and it means something.** Rivals who undercut later used to count as whole lots in
  front of yours for two days: a busy ore selling about 290 a day showed Sure 0% at every price.
  Now they take a share of the buyers, at most half. The tooltip, Deals and Selling → My items ask
  Sure for the same units (what you would sell) at the same price, so the item shows one number.
- **No auction recommendation that will not sell.** The tooltip ranks the auction house by what it
  likely brings (net × Sure); under Sure 10% it is never the recommendation, and with no other
  route the tooltip says to hold. The line names the price to post ("Auction house at 1g 99s, after
  the cut"), so the sum on the right is clearly what you get after the cut.
- **Fewer numbers.** Est./day and Sure lost their 80% ranges; Est./day shows whole units from 10 up.
- **Price without an AH check undercuts today's cheapest lot** of the full scan instead of posting
  above it at the usual price.
- **One sell price, with its reason.** The tooltip's recommendation, the Sell page's suggested
  price and the Resale exit used three different rules (the median asking price, the cheapest
  seller, what buyers paid), so one item showed 1g34, 1g22 and 69s. Now all three use one rule:
  one step under the cheapest other lot, never above what buyers really paid. The tooltip says why
  under the recommendation, and when the item is a Resale deal it recommends the deal's price.
- **Deal now sits inside Selling** in the tooltip, right after the recommendation.
- **The vendor price note** says what it is: the client's price, confirmed only after you sell one
  to a merchant. Wowhead shows the same client figure; the Forever server sometimes pays less.
- **An empty full scan says why**: the server answers a full scan only once in 15 minutes and
  returns nothing in between; the message says so and points at Quick scan instead of "try again
  later". The button does not offer a Full scan within 15 minutes of the last one.
- **Full scan and Check all are lighter**: the raw-scan hash is about a quarter faster and the
  finish step checks the clock after every item, so it stops for a frame on time.
- **Selling → My items**: Check Sure sits with the price it checks, the Sure column is shown, and
  **AH / V** (both routes pass) stays off the vendor list until you choose. A lower price gives a
  higher Sure, never a lower one.
- **Crafting is called Professions**; ForeverFlip's AH tab comes before TSM's; the Disenchant deals
  checkbox is gone (the Disenchant page says when it is off); the Sharing page is shorter;
  Analytics Overview has no stray "..", and Lost most is the size of the lines around it; button
  labels fit their buttons.

- **Check all on your own auctions is fast when nobody else sells**: an item seen alone at the
  scan (under 2 hours) is answered from it at once, marked *as of the scan*; a silent search is not
  tried twice in one run (30 items: 3 minutes → under 2 seconds with a recent scan). **Search**
  checks one auction for real.
- **Settings**: General and Safety are one page, the limits in a **Limits** section. The
  ForeverFlip tab no longer sits on TSM's. The price settings explain themselves on hover.
- The Shopping list footer is smaller and the list shows 15 rows; tables show more rows; KPI money
  is shortened to fit.

- **Item tooltips go quiet when the auction scan data are a day old.** Fresh data come either way,
  and either is enough: a complete Full scan in the game, or a scan of the house brought by the
  Sync helper (Sync stays optional). Once the newest of them is 24 hours old, or there are none,
  ForeverFlip's block in an item tooltip is replaced by a warning with its age and both ways out:
  a Full scan, or Sync and then `/reload`. Prices, Sure, sales, advice and Best were all read from
  those data and were shown as if current. Running Sync without it bringing a newer scan does not
  reset the time. The game's own lines and other addons' lines stay.
- **New profiles start on the Careful preset**, and Careful's vendor deal minimum is now 15c (it
  was 50c, which hid most vendor deals, the ones with no resale risk). Existing profiles keep every
  value they have.
- **Full scan is greyed out while a press would only fail**: during the cooldown (with its
  countdown, as before), while a purchase, post or search is on the wire, and while the server
  says it is busy. The click still checks again before sending.
- **To vendor's button is Buy first** and buys the top row of the table as it is sorted now, after
  checking that lot again; it was "Buy all to vendor" and took its own order.
- **Money keeps two digits after the largest coin** in every table and line (1g 05s, 26s 00c), so
  columns line up and 26s 0c is not read as 26s and 0 gold.
- **The item tooltip's deal line says what its Sure is for**: "Sure 26% to sell all 15 at 75c".
  The Demand section's Sure is for one unit at the post price; both read just "Sure" before and
  looked like the same number shown twice.
- **Hovering an item row in a table shows the item tooltip only.** The seven lines under it (Qty,
  Buy at, Sells at, Profit, Est/day, Sure, Status) repeated the row's own columns.
- Wording and fit: a sold auction reads **sold**; the Analytics tabs are **Cheaper** and
  **Dearer**; the third Market column is **Cheapest** (or **Best time** on the timing tabs) and
  wide enough for its money; **Sells/day**; the learned professions text sits a line higher and
  its button fits its label.

### Changed

- **My items shows Sells at instead of Profit**: the price one unit sells for on the route in
  Best (the auction price the Price each box gets, or what a vendor pays; both while you choose).
  The profit is still on hover and in the text below.
- **Resale and Market reset are two different strategies again.** Both sold at the price buyers
  paid lately, so the pages showed the same deals. Market reset buys every lot under the median
  and sells at the median. Resale buys up to a lot and picks its Sells at from the sales: one step
  under the next lot left, or what buyers really paid, whichever Sure expects to bring more money,
  so it sells at a price people buy at rather than just under a rival. It buys only as many as
  Est./day says sell there in a day. Stock either one bought is posted at that price on Selling.

### Fixed

- **Sync did not bring your own scans back**: the helper's data skipped every scan you had uploaded
  yourself, since it was in your history already. After Reset all data (or on another computer) it
  is not, and References showed one day of prices and no trend. What decides now is the scan's
  house and time, not who made it: a scan your history does not hold is merged (your own as your
  prices, so the 14-day median and the trends come back at the next login), and one it holds is
  skipped. Every full scan you make is remembered for this, so the helper never brings it twice.
  Your own scans still do not count as community data.
- **Empty tooltip on gear seen once**: an item with a single lot on the auction never got a
  history, so its tooltip showed only the vendor price. The full scan now records every item it
  sees, and gear with no data of its own shows the price of its other versions, an estimate of
  sales per day and Sure taken from them or from gear of about the same price.
- **The list tooltip and the bag tooltip disagreed**: hovering a stack in My items now prices the
  whole stack, the same as the bag does.
- **Check all took minutes** (35 deals: 8 checked after two minutes). It now asks for the lowest
  price of every item in one query first: a deal whose item nobody sells any more, or whose lowest
  price is at or above what the deal sells for, is settled from that answer at once. Those were the
  searches the server never answers, each waited 5 seconds and was sent once more at the end. The
  log says how long each Check all took (`Check all: N items in S s`).
- **Market reset and Resale showed "-" for Est./day and Sure** on a gear ending with no sales data
  of its own (a new "of the Owl" of an item seen often). They are now estimated from the item's
  other endings, each at its own usual price, and shown greyed with "~"; the Risk line says so.
- **Tooltips no longer block clicks** on table rows: the cells only show the tooltip and let the
  click through to the row.
- **Tooltips are no longer cut off at the right**: a long line wraps instead of running past the
  edge (item tooltip, Selling, Crafting, Deals).

- **Checking the bags no longer hangs on items nobody sells.** WoW Forever does not answer an exact
  search for an item without lots, so each such item waited up to 30 seconds and was then searched a
  second time (36 items took 2–3 minutes). A full scan up to 2 hours old now says which items nobody
  sells (also after a /reload), an unanswered bag search is not sent again, and one bag item waits
  at most 12 seconds.
- **No empty rows on For sale after the check.** An item without a price of the last scan takes its
  older market data (days, sales between scans, prices buyers paid), then the usual price of other
  versions of the item, before the cost or vendor guess. A row with only a guess shows its likely
  route greyed with "?" (AH? or Vendor?) and a "~" profit; the merchant's list and Post AH-worthy
  still never act on a guess.
- **A resale below the usual price riding with another deal is no longer confused with the price of
  a deal of its own** (both were `median`): the scan's save and the merge of a vendor deal with a
  resale no longer fail on it.

- **The saved data can no longer grow past what the game can read.** The client reads the saved
  file with Lua 5.1, which accepts at most 262 143 distinct values. At about 260 000 the file
  failed to load ("constant table overflow" in `Logs\FrameXML.log`), the addon started empty and
  the next logout wrote the empty data over it. That wiped the sales history of 26 000 items and
  the journal, and Resale fell from about 30 deals to 3 because nothing looked like it was selling.
  At logout the estimates in the item histories (hours, rates, weekday factors) now keep four
  significant digits, which cuts the real file of that day from 259 000 to 173 000 values. If the
  file would still hold more than 200 000, the items seen longest ago are dropped (never the ones
  the player holds or has listed), and the log says so at the next login.
- **No false "empty list" before a full scan.** The server first clears the list and sends the
  auctions 10-15 seconds later; the scan gave up on the cleared list, said the server refused it,
  and then read the real answer as another addon's scan. It now keeps waiting and reports a refusal
  only when the list stays empty for a minute.
- **One quick-scan row per piece of gear.** The browse gives one lowest price an item, whatever
  its ending; it was listed under every ending the history knows, so one cheap Giant Club showed as
  13 identical rows. Now one row, the ending whose deal pays least, and every ending is still
  checked.
- **The quick scan froze the game and crawled.** Every page copied the whole result list twice, and
  each page's candidates were checked before the next page was asked for. A page now reads only
  the rows it brought, and the candidates are checked after the last page.
- **The vendor minimum profit was applied to the whole deal**, so a stack of 7c-a-unit lots passed
  a 15c minimum. It is per unit now.
- **Deals lost their checked status within a minute**: the sniper re-queued them after 60 seconds.
  A checked deal now stays ready for 5 minutes, unless a cheaper lot shows up; background
  re-checks no longer flip it to queued.
- **The tooltip's Sure range could raise a Lua error**: its cache key left out the lot sizes the
  value depends on, so it read an entry that was never written. One key now serves both.
- **A quick scan on a house with no saved Full scan** would not check what it found and gave up
  after three minutes; it now checks its candidates there too.
- **The tooltip's recommendation disagreed with Best** below your minimum price: it used the net at
  your price, Best the net at the market's.

### Development

- The mock measures text when a test asks (`measureText`, 6 px a letter), and a test checks that
  every fixed column's name fits its width in English and Ukrainian on every page.
- The unification review is carried out: `Market.thresholds` / `maxBuy` / `unitNet` /
  `auctionNet`, `Deals.priceOf` / `usualOf`, `F.STRATEGIES` (Deals pages, Journal views, Selling
  note), `UI.C` / `UI.paint`, `UI.pct` / `UI.pctText`, `UI.tip`, `UI.ROUTE` and the option-line
  helpers shared by the item and My auctions tooltips, `Disenchant.sellValue`, and `Util.TUNING`
  for the fixed judgements.
- `UI.tipPair` (a two-column tooltip line that wraps when long) replaces direct `AddDoubleLine`;
  `UI.routeLabel` is the Best label for My items and Crafting; `Trade.boughtWay` / `T.KEEP_DAYS`
  keep a purchase's strategy (`lot.strategy`, `position.strategy`); `Crafting.profits` decides the
  route with `Market.sellRoutes` + `Market.routeVerdict`. `docs/unification-review.md` lists what is
  still not unified. Tests: BoughtWayTests in `test_review_trade_b`, journal and purchase views.

- `Market.postPrice` (the one sell price and its reason), `Trade.postLimit`, `UI.priceWhy`;
  deals keep `exitWhy`. Tests: `test_one_price`.
- `AH.browseAnswer(updated, added)` reads one browse event once (the ADDED payload, or the whole
  list for UPDATED); `Sniper.onResults(first, rows, whole)` takes its rows; `Sniper.stopQuick()`.
  The mock fires ADDED with its payload. New tests: pages before checks, stopping a quick scan,
  the 5-minute hold, the per-unit vendor minimum, the All marker, the resale why line.

- `Sniper.quick`/`startQuick`/`canQuick`, `Sniper.lows` and `Sniper.low(id)` (per house);
  `UI.lowestFor`, `UI.craftRoutes`, `UI.disenchantLow`. New `test_tooltip_layout`; quick-scan tests
  in `test_fast_sniper`.
- `Scan.canStart()` runs the same checks as `Scan.start()` without sending or spending the
  stuck-throttle allowance; the Full scan button follows it.
- Each market keeps `scannedAt`, the end of its last complete full scan (older data fall back to
  `peak.at`), and `syncScanAt`, the time of the newest scan of the house that Sync brought and the
  history took (merged now, or at an earlier login). `UI.scanDataAt()` is the newer of the two.
- The presets moved to `Data.PRESETS`; `Data.open` applies Careful only when no saved file exists.
  The test runtime sets Balanced, the values the existing tests were written for.
- New test modules: `test_scan_button_state`, `test_new_profile_preset`, `test_stale_tooltip`.
- Statistics are versioned (`STATS_VERSION`), merged per item with a 7-day backup
  (`Data.commitStats`/`rollbackStats`); the model is described in `docs/analytics-model.md`.
- `Engine.scope()` and `Engine.hardcore()` are cached until the realm, house or rules change; they
  were rebuilt on every frame and hover.
- ForeverFlip Sync: beta channel detected from the installed TOC, several installs (profiles),
  self-update from GitHub releases checked by SHA-256, real community exchange status.
- The addon is reorganised into layers: `Compat.lua` (capabilities and C_* wrappers), Market
  reading the game only through `Market.env`, services reaching the screen through
  `Engine.emit/listen`, `UI.lua` split into page files, and `schemaVersion` with ordered
  migrations in `Data.open`.
- Community aggregator: archive recovery, duplicate and wrong-market refusals,
  `shared/status.json`; the data workflow checks out `main` and retries its push.


## [2.3.0-beta.1] - 2026-11-15

Crafting plans profitable batches and their material purchases; Selling explains its Best route.

Known issue: the server can still refuse addon posting with "That action is currently restricted"
while the client reports no active restriction. This beta explains the refusal and frees the
buttons; it does not claim to resolve the server refusal. In-game checks remain pending.

### Added

- **The Crafting page plans how many crafts to make and what to buy for them.** Select a recipe:
  the lines under the table say how many crafts pay now and what stopped the plan there (a day of
  the product's sales, the product you already hold, the next lots costing too much, no more
  material listed, the money on hand), then for each material how many are needed, how many you
  hold, how many to buy and up to what price, and the profit of the plan. Crafts are added one at a
  time, each taking its materials cheapest first — your own stock, then the lots of a fresh check
  or the last full scan, then a merchant — while what the craft brings stays at least 5% above what
  its materials cost. **Shop materials** puts exactly that on the shopping list: the units to buy
  of each material at the dearest price that keeps the crafts paying. Until now it put one day of
  materials at their usual price, which the auction house often did not have, and said nothing
  about how many crafts were worth it.

### Changed

- **Selling → My items says why Best chose its route.** The footer opens with a **Best** line
  naming the winner and by how much (the auction house brings 9s 80c more than a vendor, or the
  vendor pays more than the auction at market prices). Under it, every route is listed in the
  Undercuts page's shape, with the chosen one marked `>` and `(best)`: what one unit brings, and in
  grey how — the price posted, the cut, the deposits expected to be lost and the profit for the
  auction house; at once, no cut and no deposit for a vendor (with a note when the price comes from
  the item data); the materials for disenchanting. The Price and Market lines are led by their
  subject the same way. A **Why** line under Best names what decided it: an item that hardly sells
  loses more in expired deposits than the auction house would gain (with how many posts are
  expected to expire), the cut leaving less than the vendor's price, no merchant buying it, or the
  materials being worth more. The text block has six rows, so the last no longer runs into
  **Price each**, and a line too long for a row goes on in the next one instead of being cut off.
  Until now the reason was only in the Best cell's hover.
- **Profit on Deals → To vendor is per unit.** It is Sells at less Buy at, the two columns beside it,
  so a lot of 40 no longer reads as 40 times the gain of one; sorting by Profit follows. The line
  under the table still adds up the whole offers.
- **No more Gear I can't use button over the merchant's own tabs.** It sat over the items on the
  Merchant and Buyback tabs. Unusable gear is sold from the merchant's ForeverFlip tab.

### Fixed

- **Learned recipes only now hides the recipes you have not learned.** On WoW Forever the game's
  recipe data carries no "learned" flag, so no recipe was ever known to be unlearned: the button
  showed no count and hid nothing (Smelt Thorium stayed listed for Mining 140). The page now asks
  the spell book (`C_SpellBook.IsSpellKnown`, a recipe's ID being its spell's) each time it is
  drawn, so recipes saved earlier are answered too without reopening the profession window. If the
  spell book knows none of the recipes, its answer is not trusted and nothing is hidden.
- **The Crafting footer no longer runs into its buttons.** Its four text rows and the scrollbar
  reached below the top of Learned professions / Learned recipes only; the footer is taller now
  and the table keeps its 15 rows.
- **The last row of My items no longer runs under the For sale / Hidden / Rule / Hide buttons.** The
  list shows 11 rows instead of 12; the wheel and the scrollbar reach the rest.
- **Posting while the game restricts addons no longer locks the buttons.** The game refuses a post,
  a purchase or a cancel from an addon during combat, a boss encounter, a keystone or a PvP match,
  and the server only answers "That action is currently restricted": ForeverFlip then waited ten
  seconds for an auction that never came, with every posting button off, and the next click tried
  the same thing again. The posting and cancel buttons now stay off while such a restriction is
  on, a post asked for then says why without reaching the server, and a post the server refuses
  ends the wait at once. When the server itself answers "That action is currently restricted"
  while the game reports no such restriction, the page says so as the server's answer instead of
  blaming combat; the cause of that answer is not known yet. An item the
  server refuses for another reason (bound, quest item...) is skipped by Post all until the auction
  house is opened again, so the next click posts the next item.

### Development

- `test_sell_route_and_restrictions`: the Best verdict and routes in the footer, and posting under
  a game restriction (`C_RestrictedActions`) or after the server refuses a post.


## [2.2.0-beta.2] - 2026-11-14

The ForeverFlip tab is back in the auction house, and the merchant page opens again.

### Fixed

- **2.2.0-beta.1 showed no ForeverFlip tab and broke the merchant page.** The change that widens a
  button to fit a longer translation measured the label the wrong way, which the game treats as an
  error. The first button of each window failed, so the auction house tab and the merchant page
  were never built, and a red error was printed in chat each time.

### Development

- **The simulated client no longer hides a method called without its frame.** A method the mock
  did not know did nothing, so the faulty call passed every test. Buttons now have a
  `GetFontString` that fails the same way the game does.


## [2.2.0-beta.1] - 2026-11-14

A vendor deal is no longer offered on an item no merchant buys, Check all during a full scan no
longer throws the scan away, and Selling → My items says why a route pays more.

### Added

- **The Crafting page can hide recipes you have not learned.** The game lists every recipe of a
  profession, learned or not, so recipes you cannot craft yet stood in the profit table with a
  profit you could not take. A button above the footer switches between **Learned recipes only**
  and **All recipes**, the count says how many are hidden, and an unlearned recipe shown in the
  full list is greyed with `(not learned)`. Off by default.
- **Check all works on the Journal pages.** It reads the current price of every item the page
  shows (Resale, To vendor and Bids read their own purchases), so the figures behind the rows can
  be brought up to date without leaving the page.
- **The Best column of My items explains itself.** Hovering it shows both routes for one unit side
  by side — what a vendor pays (marked `*` until a merchant has been seen to pay it), what the
  auction house brings after its cut, and the deposits a lot is expected to lose — with the
  difference and which way it goes. Until now the column said `Vendor` or `AH` and left the
  arithmetic to the player.
- **The My items footer has been rebuilt.** Three fixed lines and the price controls underneath sat
  in a 108-pixel block, so a long explanation (the sale route, the market, the minimum) ran into the
  fields. It now has the Undercuts page's shape: seven scrolling lines on top, then the price,
  quantity and duration, then the posting buttons, in a 146-pixel block.
- **`/ff refused` shows, and can forget, the session's merchant refusals.** A sale the server was
  too busy to take can look exactly like a merchant refusing the item, and the verdict lasted the
  session. The command names what has been learned and `clear` forgets it.

### Fixed

- **Check all no longer ends the full scan.** The button read **Stop** whenever any work ran, and a
  full scan counts as work: pressing **Check all** during the five to ten minutes of a scan
  cancelled the scan the player was waiting for, and the checks that were wanted never ran. The
  button keeps its own name during a scan (the checks wait for it and start when it settles) and
  reads **Stop** only while checks, a sale or a purchase run, which is what it actually ends. A
  running scan is stopped from its own button, which reads **Stop scan** while it runs. A Check all
  whose searches the scan holds back is no longer counted as unanswered either, so the chat no
  longer says "no answer for: ..." about searches that were never sent.
- **The gear button no longer runs off the merchant window.** `Sell gear I can't use` is 30 letters
  in Ukrainian against a 180-pixel button anchored to the frame's right edge, and the game lets a
  button's text spill past it, so the label left the window. Buttons now widen to fit their label,
  whichever language it is in.
- **A vendor deal on an item merchants do not buy.** Item data gives a sell price for some items a
  merchant refuses — a rogue's poisons are the ones seen — so they were listed under **To vendor**
  as certain profit and could not be sold. There is no client call that says a merchant will refuse
  an item before the sale, so the refusal is learned: a stack the merchant does not take (three
  tries over ten seconds, with the merchant still open and the stack still in the bags) is
  remembered for the session, and from then on the item is left off **Sell to vendor** and no scan
  or price check brings its vendor deal back to the list. The Merchant tab adds a line when items in
  the bags are left out for this reason, so their absence is explained rather than silent. An item
  the game itself flags as having no value (`hasNoValue` in the container info) is left out at once.
  A wrong verdict — a sale the server was too busy to take — would keep a good item off both lists
  until the next reload, so `/ff refused` lists what has been learned this session and
  `/ff refused clear` forgets it.
- **The auction house is no longer named twice.** The game's title bar read "ForeverFlip: Alliance
  AH" while the addon's own bottom bar already names the open house; the title is just ForeverFlip.
- **The learned professions list no longer runs off the window.** It was one text under the
  Crafting table: with more than a few professions the last lines were past the bottom edge and
  could not be reached. It scrolls now, like the other text blocks, and the whole list is readable.
- **A vendor offer is listed whatever it costs.** A **To vendor** row was only listed if the money
  in the bags paid for all of it, so an offer worth more than the purse simply vanished. Vendor
  deals are paid at once and carry no risk, so the offer is now shown in full — Qty and Cost are
  the whole lot on the shelf — and Buy takes the part the money covers, the Status column saying
  `cannot afford it yet` while it covers none. The offered units were also thrown away when the
  purse could not pay, so the deal could not come back when the money did; it does now.
- **The To vendor table shows what it is about.** Its columns are Name, Qty, Buy at, Sells at,
  Cost, Profit and Status: Cost is the money the whole lot asks for (Qty × Buy at), which was not
  shown anywhere, and Est./day and Sure are gone (a merchant pays at once, so there is nothing to
  wait for and nothing to estimate).
- **A purchase sold before its own mail arrived was counted twice.** Buying, selling, reading the
  sale's mail and only then looting the purchase's own mail (the sale's invoice is the one that
  arrives first) booked the purchase a second time: an extra row in the journal, a stock figure
  with units that were never paid for, and a purchase lot left open for good. The sale now settles
  the waiting purchase, so the later mail is matched rather than booked.
- **A "wait" advice is no longer a dead end.** When keeping an auction paid best, **Answer next**
  showed `(0)` and stayed grey — it counted only auctions whose advice is an action. The other way
  out buttons did work, but a list of undercuts beside a disabled button reads as broken. The panel
  now says in words why Answer next leaves that one alone.
- **A running buy out is marked instead of holding the page.** While a buy out from **Answer next**
  runs, its row says `buy out running` in the Advice column and is no longer counted as an undercut
  to answer, so a finished decision stops standing in the list as if it were still open.

### Development

- **The tests run in parallel.** `python tools/devflow.py test` runs one process per module, about
  a minute in twenty seconds, and `test <word>` narrows the run to a module or a test name.
- **`pyflakes` is part of the check.** The pre-commit hook and CI report unused imports and
  undefined names in the tests, the Sync helper and the tools.
- **CI checks Windows too,** where the local flow, the hooks and the Sync helper actually run.
- **The Lua diagnostics see the game.** `undefined-global` is on again: the names the game's
  interface gives the addon live in `references/wow-forever-globals.lua`, so a misspelt call is
  reported and a wrong one is not.


## [2.1.0-beta.2] - 2026-11-13

Full scans keep the whole house again, and the Sync helper is fast and can stay in the tray.

### Added

- **The Sync helper can keep syncing in the tray.** With **Keep syncing in the tray when closed**
  (off by default) closing the window hides it into the notification area; the helper goes on
  syncing prices and sharing scans. Click the icon to open it, right-click for Sync now and Quit.

### Fixed

- **Full scan lost most of a busy house.** When the game had not loaded the data of the items with
  the most lots, their rows (210 000 of 242 000 in game) were read again row by row on every pass;
  one pass took longer than the 30-second wait, so rows whose data arrived meanwhile were given up.
  The scan then knew 1 588 items instead of 1 732, and resale found 2 deals. Waiting rows are now
  kept per item and read again only once its data has arrived; the count moves at once, and the
  wait runs on 30 seconds after the last item came in (5 minutes at most).
- **The Sync helper froze for a minute after each `/reload`.** It read the whole saved file (68 MB with
  eight full scans) a character at a time: 65 seconds in a thread that held the window. It now
  reads only the scans table, quoted strings in one step and the rows of scans not shared yet:
  about 3 seconds. Window layouts no longer repeat for each resize event and the progress bar moves
  one shape instead of drawing a new one 60 times a second.
- **The helper's status ring turns while it works**, instead of standing still.
- **Settings → Sharing tells what the helper shared**: how many of your scans and the age of the
  newest, and how many still wait. Shared scans leave the saved file at login, not only after the
  next full scan.
- **Item data loads faster after a full scan.** It was asked for at a fixed 40 items a second, seven
  minutes for the 16 000 items of a busy house. Now up to 100 go every 0.1 seconds while fewer than
  400 are unanswered, so the pace follows how fast the game answers.

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

[Unreleased]: ../../compare/v3.1.0...HEAD
[3.1.0]: ../../compare/v3.0.0...v3.1.0
[3.0.0]: ../../compare/v2.3.0-beta.1...v3.0.0
[2.3.0-beta.1]: ../../compare/v2.2.0-beta.2...v2.3.0-beta.1
[2.2.0-beta.2]: ../../compare/v2.2.0-beta.1...v2.2.0-beta.2
[2.2.0-beta.1]: ../../compare/v2.1.0-beta.2...v2.2.0-beta.1
[2.1.0-beta.2]: ../../compare/v2.1.0-beta.1...v2.1.0-beta.2
[2.1.0-beta.1]: ../../compare/v2.0.0-beta.1...v2.1.0-beta.1
[1.2.0-beta.6]: ../../compare/v1.2.0-beta.5...v1.2.0-beta.6
[1.2.0-beta.5]: ../../compare/v1.2.0-beta.4...v1.2.0-beta.5
[1.2.0-beta.4]: ../../compare/v1.2.0-beta.3...v1.2.0-beta.4
[1.2.0]: ../../compare/v1.1.0...v1.2.0
[1.1.0]: ../../releases/tag/v1.1.0
[1.0.0]: ../../releases/tag/v1.0.0
