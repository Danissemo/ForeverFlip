# ForeverFlip user guide

This guide covers everything you see in game: the auction house tab and its pages, the mailbox,
merchant and profession window, tooltips, alerts, key bindings, settings and slash commands. To learn
how the numbers are calculated, read [How it works](how-it-works.md).

- [The ForeverFlip tab](#the-foreverflip-tab)
- [Top bar](#top-bar)
- [Deals pages](#deals-pages) (Deals)
- [Buying](#buying)
- [Shopping list and ignored items](#shopping-list-and-ignored-items)
- [Bids](#bids) (Deals → Bids)
- [Sell my items](#sell-my-items) (Selling → My items)
- [My auctions](#my-auctions) (Selling → My auctions)
- [Statistics by item](#statistics-by-item) (Analytics → By item)
- [Analytics](#analytics) (Analytics → Overview)
- [Crafting](#crafting)
- [Journal and profit](#journal-and-profit) (Analytics → Journal and profit)
- [Price history window](#price-history-window)
- [Settings](#settings)
- [Sharing scans](#sharing-scans)
- [Outside the auction house](#outside-the-auction-house)
- [Key bindings](#key-bindings)
- [Slash commands](#slash-commands)
- [Messages](#messages)
- [Troubleshooting](#troubleshooting)
- [A typical session](#a-typical-session)

---

## The ForeverFlip tab

When you open the auction house, a **ForeverFlip** tab appears next to the game's own tabs (Buy,
Sell, Auctions). If [LibAHTab](https://www.curseforge.com/wow/addons/libahtab) is installed, the tab
is created through it so it sits next to the tabs of other addons.

The window has three parts. Tables longer than their rows scroll with the mouse wheel; the first
column's header then shows which entries are on screen, for example `Name (5-15 / 15)`. The deals
have pages instead (Previous / Next).

- **Top bar:** scan and sniper buttons and a status line. A thin yellow bar along the top edge shows
  the progress of the current task.
- **Left column:** six entries and, below them, a short summary of the last scan and of the sniper
  (rounds, prices read, candidates, checks).
- **Right side:** the selected page. An entry with several pages shows them as tabs above the page.
  Most pages have a table on top and an explanation and buttons at the bottom.

| Entry | Tabs |
|---|---|
| **Deals** | All · To vendor · Resale · From the list (shopping list deals) · Bids |
| **Selling** | My items (the Sell my items page) · My auctions |
| **Shopping list** | |
| **Crafting** | |
| **Analytics** | Overview · By item (Statistics by item) · Journal and profit |
| **Settings** | |

ForeverFlip remembers the last page you opened, and each entry opens the tab you used last.

- **Sort any table** by clicking a column header. Click it again to reverse the order; an arrow marks
  the column. Names sort A to Z first, numbers largest first, and empty values always go last.
- **Right-click any item row** in any table to open its
[price history](#price-history-window).

At a neutral auction house (Booty Bay, Gadgetzan, Everlook) ForeverFlip keeps a separate price
history, because the listings are separate, and counts the 15% cut.

## Top bar

| Control | What it does |
|---|---|
| **Full scan** | Asks the server for every auction of the house. The button shows a countdown while the 15-minute cooldown runs. |
| **Sniper: ON / OFF** | Turns the [sniper](#sniper) on or off. |
| **Check all** | Searches every entry of the open page on the auction house again, one search after another, and the page shows what was found: deals are kept, updated or dropped (All, To vendor, Resale, From the list); the items on the **Shopping list** are checked as shopping deals; **Bids** reads the best bid of every candidate; **My items** and **My auctions** read the current price of every item (the Best column and the suggested prices use it); **Crafting** reads every material and product, and the recipes are priced with those prices for 5 minutes. While it runs the button shows `Checking <page>: done/total`. Afterwards it shows `Checked ...`. Searches without an answer are sent once more by themselves; what still has none is shown as `(N without an answer)` and named in the chat. On WoW Forever the server does not answer a search for an item nobody else sells, so these are usually items only you have; an item a full scan of the last 20 minutes did not see is not searched at all. |
| Auction house (bottom bar, beside the money display) | Which auction house is open: **Alliance AH** (blue), **Horde AH** (red) or **Neutral AH, 15% cut** (gold, at Booty Bay, Gadgetzan or Everlook). Each house keeps its own scans, prices and deals; the window title says it too. |
| Status line | The current task (`Reading auctions 12000 / 231000`, `Evaluating items ...`), the last message, or the number of deals and how many are checked. The sniper's own figures are in the summary on the left. |

### Full scan

A full scan runs in stages, all shown on the progress bar:

1. **Waiting for the auction house to send the full scan.** The server answers in a few seconds to a
   minute. The status line counts the seconds while ForeverFlip waits for the answer (minutes on a
   busy server). If it does not answer in 5 minutes, ForeverFlip says so and tries again a minute
   later.
2. **Reading auctions.** The scan is read in small portions per frame, so the game keeps running
   smoothly.
3. **Loading item data.** Some items are not in the game's cache yet. ForeverFlip asks the game to
   load them and waits up to 30 seconds.
4. **Evaluating items.** Each item is checked for a vendor deal, a resale, a shopping list entry, a
   disenchant deal and bids ending soon. Its sales since the previous scan are recorded.

The server allows **one full scan per 15 minutes per account**. With **Full scan every 15 minutes** on
(Settings, on by default), ForeverFlip starts the next scan by itself when the cooldown ends, if the
auction house is open and no other action is running.

If another addon (Auctionator, TSM, auxForever, ...) requests a full scan, ForeverFlip reads the
result too and says so in the status line.

The last scan and its deals are saved. After a `/reload` or a new login they are shown again until
the next scan, but every deal has to be checked again before you can buy it.

### Sniper

Between full scans, the sniper watches the whole auction house:

1. **A round** reads the lowest price of every item on the auction house, page by page. On WoW
   Forever this takes a few seconds. The rounds repeat with a pause of 2.5 seconds.
2. **During the pause,** the items most often near a deal and the items of your shopping list are
   read again, 100 items per request.
3. **A candidate** is an item whose lowest price is low enough to hold a deal: below the vendor
   price, far below the usual price of an item that sells, below the price on your shopping list, or
   below the disenchant value. Each candidate is read with an exact search and evaluated with the
   full deal rules. A deal that holds is listed as **ready** and raises an [alert](#alerts).

Candidates are checked before the next page is asked for, and the sniper pauses while you buy, post
or run a manual check. An unchanged lowest price is not checked again for two minutes. Searches
other addons make in the auction house feed the sniper too, without slowing the game.

If the game client does not offer the browse queries the sniper needs, it falls back to re-reading
the 150 items most often near a deal, one per second.

## Deals pages

**Deals** has five tabs; the first four list deals:

- **All:** every deal, best first.
- **To vendor:** lots priced below what a vendor pays. You buy them and sell them to any merchant.
  Profit is certain as long as the lot is still there and the vendor price is confirmed (a yellow
  `*` marks a vendor price not yet seen at a merchant, see [Settings](#settings), Safety).
- **Resale:** lots priced well below the next seller, for items that are measured to sell at the
  resale price. You buy them and post them again on the auction house.
- **From the list:** lots at or below the price on your [shopping list](#shopping-list-and-ignored-items).
- **Bids:** see [Bids](#bids).

**Disenchant** deals appear under All for a character who knows Disenchant: green and blue
weapons and armor priced below the expected value of their materials.

### Columns

| Column | Meaning |
|---|---|
| Item | Icon and name. Hover for the game tooltip; right-click for the price history. |
| Price | The highest unit price you pay in this deal (the last lot taken). |
| Qty | Units to buy. |
| Cost | Total price of those units. |
| Profit | Money you keep. For a resale: after the auction cut and the deposit risk. For a shopping deal: the saving against your price. For a disenchant deal: the material value minus the cost. |
| Status | See below. |
| Est./day | For resale deals: units per day that sell near the resale price. For other deals: the kind of deal. |

Click a column header to sort by it, and click it again to reverse the order. Use **<** and **>** to
change pages.

### Statuses

| Status | Meaning |
|---|---|
| **ready** (green) | Checked on the auction house in the last 45 seconds. You can buy it. |
| **checking...** | The exact search for this item is running now. |
| **queued** | Waiting for its turn to be checked. |
| **check again** | It was checked more than 45 seconds ago. Click it to check it again. |
| **from scan** | Found by the full scan and not checked yet. |
| **old scan** | Found by a scan more than 20 minutes ago. The lots may be gone. |
| **not enough money** (red) | The deal costs more than you carry. |

Deals that have not been checked are dropped 15 minutes after the scan that found them. A deal that
no longer holds when checked disappears from the list.

### Details of the selected deal

Under the table, the selected deal is explained in one or two sentences:

- For a vendor deal: its return. It is sold to a vendor at once, with no risk.
- For a resale: its return and roughly how many days the units take to sell at the measured rate.
  The sentence also says when the sales data is old.
- For a shopping or disenchant deal: what it is based on.
- When the [time-of-week pattern](how-it-works.md#time-of-week-pattern) of the item is known, it says
  when prices are usually higher, which is the better time to post.

**Ignore item** puts the selected item on the ignore list: it never becomes a deal again until you
remove it on the Shopping list page.

With **Check found deals automatically** on (Settings), ForeverFlip checks the best unchecked deals
by itself.

## Buying

1. Click a deal. If it has not been checked in the last 45 seconds, it is checked now. Wait for
   **ready**.
2. Click **Buy** (or press the [Buy key](#key-bindings)).
   - **Stackable goods (commodities)** are bought by quantity. The game first quotes the total price.
     When the status line says *Price confirmed*, click **Confirm purchase**.
     - If the quoted price is higher than the checked deal, the purchase is cancelled and the deal is
       checked again.
     - If the quote is about to expire when you confirm, ForeverFlip asks for a new quote instead,
       because a stale quote fails with an error on WoW Forever. Click **Confirm** again when it
       arrives.
     - Use **Cancel** to drop the quote.
   - **Items and gear** are bought one auction per click, because the server sells one lot per
     purchase. After a purchase the deal is worked out again from the lots its check read, without
     the lot just bought: the next click buys the next lot at once, with no new search, while the
     check is fresh (45 seconds).
   - A click on **Buy** does not wait for a search in flight (the sniper, a check): that search is
     sent again after the purchase.
3. When the purchase goes through, the status line shows *Purchase recorded*. The units are added to
   your stock at their real cost and logged in the journal.

If someone was faster, the purchase fails and costs nothing. The deal is checked again.

Units of a vendor deal bought while you hold the item for resale join the resale stock. **Sell
vendor deals** never sells an item whose average cost is above the vendor price.

If the game does not answer within 30 seconds, the purchase is kept as **unknown**. Settle it on the
[Journal](#journal-and-profit) page with **It was bought** or **Not bought**. The chat line *You won
an auction for ...* tells you which one is right; ForeverFlip also reads that line and settles the
purchase by itself when it appears.

**Check price** next to Buy runs an exact search for the selected item without buying.

Searching an item yourself in the game's **Buy** tab counts as a check too: if its listings hold a
deal, the deal is listed as **ready** at once.

## Shopping list and ignored items

The **Shopping list** page holds items you want to buy and the most you pay for one.

- **Add an entry:** Shift-click an item link into the **Item** field (or type the exact name of an item
  the game knows). Enter **Up to, each** and, optionally, a **Quantity**, then click **Add**.
- **What it does:** the full scan, the sniper and your own searches find lots at or below that price.
  They appear under **Deals → From the list** and are bought like any other deal.
- **Which deal wins:** if the same item also has a vendor deal or a resale with more profit, that
  deal is shown instead.
- **What you buy:** items bought from the shopping list are for your own use. They are kept out of
  Post next bought.

The table shows each entry's price, quantity, the cheapest price seen today and its status
(**watching** or **for sale now**). **Ignored items** are listed on the same page. Select a row and
click **Remove** to delete an entry or to stop ignoring an item.

## Bids

Items (not stackable goods) can carry a bid. **Deals → Bids** lists auctions found by the last full
scan that end within 30 minutes and whose next bid is well below what the item is worth. An item's
worth is its vendor price, or its usual auction price after the cut if it sells.

1. Click a row. The auction is read with an exact search (**Check price**), and the status turns
   **ready** when a bid is still worth placing.
2. Click **Place bid**. ForeverFlip bids the minimum the game accepts.
3. If you win, the item arrives by mail. The chat line or the "Auction won" mail books it as stock.
   If you are outbid, the money comes back by mail and the bid is closed.

Your open bids are listed under the table. Bids without news for two days are forgotten.

## Sell my items

This page lists the items in your bags that can be sold on the auction house. Bound items are left
out.

| Column | Meaning |
|---|---|
| Qty | Units in the bags. |
| Cost each | What you paid per unit, if it was bought through ForeverFlip. |
| Listed | Units you already have on the auction house. |
| Best | Where one unit brings the most, and how much: **Vendor** (a merchant pays at least what the auction house leaves after the cut and the deposits), **AH** (the auction house pays more), **Disenchant** (a character who can disenchant), or *AH: no price yet* when no scan priced the item. It is the same comparison as the item tooltip. |
| Note | Whether the item was bought for resale or as a vendor deal. |

Under the table:

- **For sale (N)** and **Hidden (N)** switch between the items for sale and the items you hid.
- **Hide** takes the selected item out of the list for sale. Post all and Post next bought skip it
  from then on. Use it for items you want to keep, such as consumables, tools or keepsakes.
- In the **Hidden** view, **Return to sale** puts the selected item back. Hidden items that are no
  longer in your bags stay listed there, so you can still return them.

At the bottom:

- **Selecting an item** reads its current listings at once, fills in the quantity and loads its rule.
- **Price each**, **Quantity** and **Duration** fields, and **Post** to create the auction for the
  selected item.
  - The price field accepts `1g 20s 5c`, `20s`, `1.5g` or a bare number of silver.
  - Duration is 2, 8 or 24 hours, or **Auto**: the shortest duration the item's measured sales fill
    (a shorter post costs a smaller deposit), else 24 hours.
- **Rule: min / max / keep** for the selected item, saved with **Save rule**:
  - **min:** never post below this price.
  - **max:** if the cheapest other seller asks more than this, it is ignored and the item is posted
    at its normal price (the usual price).
  - **keep:** this many units stay in the bags.
- **Check price** reads the current listings of the selected item. A price stays fresh for 5 minutes.
- **Post next bought (N)** handles the items you bought for resale, oldest first, still in the bags
  and not yet listed. N is how many are waiting.
- **Post all (N)** handles every sellable item in the bags, also items you did not buy through
  ForeverFlip. Vendor-deal stock, shopping purchases, ignored items and the units of a *keep* rule
  are left out.
- **Post AH-worthy (N)** is Post all without the items whose Best is **Vendor**: only what the
  auction house pays more for is posted, and the rest stays in the bags for a merchant. Items with no
  auction price yet are posted (nothing says a vendor pays more).

How the two posting queues work:

- **First click:** every item of the queue without a fresh price is searched, one per second, in
  the background (*Reading the current prices of the items to post*).
- **Each next click:** posts the first item whose price is known at the suggested price; items whose
  search is still on the way are passed over until their answer comes. The game allows one post per
  click, so a queue of 5 items takes 5 clicks after the first.
- **Below the floor:** the item is posted at the floor, or skipped with **Keep items in the bags
  when the market is below their floor** (Settings).

The **suggested price** is one legal step below the cheapest other seller, or the **Undercut %**
from Settings. Gear and plain items are listed in whole silver; commodities may use copper.

- **No other seller,** or the cheapest one asks more than the maximum: the normal price is used
  (the rule's normal price, else the usual price from the scans).
- **No other seller and no price history** (an item that is never on the auction house), in this
  order:
  1. your last posting price of the item;
  2. auxForever's usual price;
  3. your cost plus 25%;
  4. 1.5 × the vendor price, the game's own default.

  This also happens without waiting for a check when the item was not on the auction house at the
  last full scan (up to 20 minutes old), or when the auction house did not answer the check: on WoW
  Forever a search for an item without any lot gets no answer.

  The last two are guesses: they are shown in yellow and Post next bought / Post all skip them.
  Check the price, change it if needed and press **Post**. Every price you post is remembered for
  the next time.
- **The floor** is the highest of:
  - your break-even price for stock bought through ForeverFlip;
  - the rule's minimum;
  - the **Never post below** percent of the usual price.
- **A confirmation from the game** (for example, the price is far from the market): the status line
  says so and the next **Post** click confirms.

## My auctions

Your active auctions, with:

| Column | Meaning |
|---|---|
| Qty | Units in the auction. |
| My price | Your unit price. |
| Cheapest other | The cheapest listing of another seller, after a check. |
| Status | **cheapest**, **undercut**, **only yours** (nobody else sells the item), **sold, gold in the mail**, or **no answer** (the check got no answer). |
| Time left | The game's remaining time band. |

Buttons:

- **Check prices** checks your listed items one after another, one search per second. An item a
  full scan of the last 20 minutes saw only as many units of as you have listed is marked **only
  yours** without a search: WoW Forever does not answer a search for an item that nobody else sells.
- **Refresh** reloads your auctions from the server.
- **Cancel auction** cancels the selected auction. The item comes back by mail. **The deposit is
  lost**, and the game may charge more for cancelling.
- **Cancel undercut (N)** cancels the next undercut auction on each click. It only counts auctions
  whose repost price would still reach the item's floor; an auction that could only be reposted
  below its floor is left alone. Each cancel still costs the deposit. When the items are back from
  the mail, post them again with **Post next bought** or **Post all**.

When an auction is marked sold, the sale is booked once with its real quantity and price. The
profit is calculated against the average cost of your stock. The mail invoice later confirms it
without booking it twice.

## Statistics by item

One row per item you have traded through ForeverFlip:

| Column | Meaning |
|---|---|
| Bought | Units bought through ForeverFlip. |
| Sold | Units sold (auction house and vendor). |
| Stock | Units bought and not sold yet. **Red** when they have been held for 3 days or more without a sale. |
| Profit | Money received minus the cost of the units sold. `-` while nothing has sold. |
| Days | Average days between buying and selling a unit; only for units bought through ForeverFlip. |
| Sell % | Share of your posts that sold, from auction mail (sold against expired and cancelled). Shown after 3 posts. |

`-` means "nothing yet". Each ending of a gear item ("of the Bear", "of the Wolf") has its own row;
hover a row to see its full name.

When your own results for an item are poor, ForeverFlip trusts the scan estimate for that item less,
so fewer resale deals are suggested for it:

- **Unsold stock:** half after a day without a sale, a quarter after three days.
- **Low sale rate:** a sale rate below 50% scales the estimate down by the same proportion, no lower
  than a quarter.

## Analytics

The page has two parts.

**Your results** for the last 7 or 30 days:

- profit and profit per day, split into auction resale and vendor deals;
- number of sales, the share that made a profit, and the return on cost;
- units and money bought;
- money held in stock, and stock that has not sold for 3 days or more;
- average days to sell and how much of the stock turns over per day;
- gold of all characters of the realm, its change over the period, and their stock at cost;
- your best and worst items, and a bar chart of profit per day.

**The market** of the current auction house, built from the saved scan history:

| View | Shows |
|---|---|
| Below usual | Items whose cheapest price today is well below their usual price, weighted by how much of the item sells. |
| Sells most | Items with the most units sold per day near the usual price. |
| Falling | Items whose usual price fell the most against the previous five days. These may be good to buy. |
| Rising | Items whose usual price rose the most. These may be good to sell from stock. |
| Cheap now | Items that sell regularly and are usually cheaper at the current time of the week. |
| Sell now | Items you hold in stock that are usually dearer at the current time of the week. |

Columns: usual price, cheapest today, change, units per day, and for the time-of-week views, the
cheapest and dearest times. Click a row to check the item on the auction house now.

The lists fill in after a few full scans. Price changes need scans on two different days, and the
time-of-week pattern needs scans on at least four weekdays.

## Crafting

Open each of your profession windows once: ForeverFlip reads the recipes and saves them for the
character. The **Crafting** page then prices every recipe:

| Column | Meaning |
|---|---|
| Materials | Cost of the materials. Each material costs the cheaper of its usual auction price and the price a merchant asked (remembered from merchant windows). |
| Product | What one craft brings: the usual auction price of the product after the cut and the deposit, or its vendor price, whichever is higher. |
| Profit | Product minus materials. |
| Est./day | Measured sales of the product per day. |
| Sell to | Auction or vendor. |

If a material has no price yet, the row shows `?`: it needs a full scan or a merchant that sells it.
If auxForever is installed, its prices fill in materials ForeverFlip has not seen.

**Shop materials** puts the materials for one day of crafts (the product's sales per day, at least
one craft) on the shopping list, each at its current price.

## Journal and profit

- A summary of the last 7 days: money spent, money received, profit of closed sales, and stock
  bought and not sold yet.
- **Unknown purchases**, if any, with **It was bought** and **Not bought** to settle them.
- The latest entries of the journal: purchases, auction sales, vendor sales, posts that came back
  unsold and failed purchases.
- **Export CSV** opens the whole journal as CSV text. Press Ctrl+A, then Ctrl+C, and paste it into a
  spreadsheet. `/ff export` does the same.

The journal keeps the latest 500 entries per character.

## Price history window

Right-click an item in any table. The window shows up to 14 days:

- **yellow bars:** the usual price of each day;
- **blue bars:** the cheapest price seen that day;
- **green bars below:** units sold that day.

The line under the chart gives the usual price, the median price of the sales seen, the units sold
per day and the price at the top of the chart. Close the window with **X**.

## Settings

The Settings page has four tabs: **General** (the table below), **Key bindings**, **Sharing** and
**Safety**.

**Key bindings:**

- click the button next to an action, then press the key, with Shift, Ctrl or Alt if you like;
- right-click a button to clear its key, Escape to cancel;
- the keys are saved in the game's own key bindings and also appear in the game's Key Bindings window
  under AddOns;
- keys cannot be changed in combat.

**Sharing** is described in [Sharing scans](#sharing-scans).

**Safety:**

| Setting | Default | Meaning |
|---|---|---|
| Vendor prices not yet confirmed at a merchant count less, % | 20 | WoW Forever's server pays less than the game's item data says for some items. Until you sold an item to a merchant once, vendor deals count its vendor price this much lower. A vendor deal on such a price shows a yellow `*`. |
| Gold one auction house visit may spend on deals | 0 | 0 = no limit. Otherwise buying stops for the visit once this much gold was spent. |
| Cheap units of a vendor deal left for other buyers | 0 | The priciest of the cheap units stay listed, so you do not empty the market. |

The tab also lists the vendor prices learned at merchants that differ from the game's data, how many
of your own disenchants were recorded, what you spent this visit, and how often the auction house
throttle got stuck.

| Setting | Default | Meaning |
|---|---|---|
| Minimum profit of a vendor deal | 10c | Smaller vendor deals are not listed. |
| Minimum profit of a resale | 1s | Smaller resale deals are not listed. Also the minimum profit of disenchant deals and bids. |
| Minimum resale return, % | 20 | Profit divided by cost, for resale deals. |
| Money one deal may use, % | 80 | The share of the gold you carry that one deal may spend. |
| Money one item may hold, % | 30 | The share of your gold one item may hold, counting stock already bought plus the new resale. |
| Smallest profit with a sound notice | 50c | Smaller deals are listed without an alert. |
| Undercut, % | 0 | How far below the cheapest other seller to post. 0 means one legal price step. |
| Never post below, % of the usual price | 0 | A floor for every post. 0 turns it off. |
| Ignore sellers above, % of the usual price | 200 | A cheapest seller above this is ignored, and the item is posted at its usual price. |
| **Presets** | | **Careful**, **Balanced** (the defaults) and **Aggressive** set the profit, return and money limits in one click. |
| Check found deals automatically | on | Checks the best unchecked deals by itself. This option is reset when you log in. |
| Full scan every 15 minutes | on | Starts a full scan whenever the cooldown ends and the auction house is open. |
| Sniper | on | See [Sniper](#sniper). |
| Sound and screen notice | on | See [Alerts](#alerts). |
| Price history in item tooltips | on | See [Item tooltips](#item-tooltips). |
| Keep items in the bags when the market is below their floor | off | Off: such items are posted at the floor. On: they are skipped. |
| Learn prices and deals from my own searches | on | Your searches in the game's Buy tab update prices and check deals. |
| Mark deals in the game's Buy tab | on | See [Marks in the Buy tab](#marks-in-the-buy-tab). |
| Disenchant deals | on | Only for a character who knows Disenchant. |
| Language | client | English or Ukrainian. Ukrainian clients start in Ukrainian; other clients start in English. Takes effect after `/reload`. |

| Preset | Min. return | Min. resale profit | Min. vendor profit | Money per deal | Money per item | Alert from |
|---|---|---|---|---|---|---|
| Careful | 35% | 5s | 50c | 50% | 15% | 1s |
| Balanced | 20% | 1s | 10c | 80% | 30% | 50c |
| Aggressive | 10% | 50c | 5c | 95% | 50% | 20c |

Money fields accept `1g 20s 5c`, `20s`, `1.5g` or a bare number of silver. Click **Save** to apply
them.

## Sharing scans

Each ForeverFlip user sees only their own full scans, at most one per 15 minutes. Sharing scans pools
them:

- **More days of history**, and a time-of-week pattern that fills in faster.
- **A fresh usual price** when your own scan is older, or while your scan is on cooldown. Tooltips
  then say who shared it, for example `(5 min ago, shared by Friend)`.

A shared scan carries, for every item seen, its usual price, cheapest price and units listed. It never
creates deals by itself: deals still come from your own scans and live checks.

On the **Settings → Sharing** tab:

| Control | What it does |
|---|---|
| Accept full scans shared by guild and group members | On by default. Scans from other ForeverFlip users of your realm are added to your history. |
| Send my full scans to the guild after each scan | Off by default. Each of your full scans is sent to the guild in the background. |
| Send my last scan to: Guild / Group | Sends your last full scan once. |
| Player + Send | Sends it to one player (whisper channel; they need ForeverFlip and must accept shared scans). |
| Export as text / Import text | The scan as a text you can send anywhere, for example in Discord, and import on another account or by a friend. |
| Keep my full scans for the ForeverFlip Sync helper | Off by default. Keeps every full scan auction by auction for the [community sharing](community.md) through GitHub. |
| Share full scans with every ForeverFlip user of the realm | On by default. A hidden chat channel (`ForeverFlipPrices`, never shown in chat): after logging in ForeverFlip asks who has a newer scan, one player answers and sends it, and everyone who is behind keeps it. Your new scans are offered the same way. |

The tab also shows the community data the Sync helper wrote, and how many full scans are kept for it.

How a scan is sent and received:

- **Hidden addon messages** carry the scan, not chat lines, one message every 0.3 seconds. A scan of
  a few thousand items takes a minute or two.
- **What is accepted:** scans of your own realm, at most 7 days old, each scan once, and never your
  own scan back. An item whose shared price is more than 10 times off the usual price you know is
  left out.
- **The list of received scans** is on the same tab.

## Outside the auction house

### Saved data that was not read

If the game hands ForeverFlip no saved data at login, a window asks what to do. On a first install
press **Continue**. If you used ForeverFlip before, the game did not read the file: press **Reload**.
Playing on would replace your history with an empty one at logout.

### Alerts

When a checked deal can be bought and its profit is at least the alert minimum, ForeverFlip:

- plays the auction house sound;
- flashes the game icon on the taskbar;
- shows a yellow line in the middle of the screen;
- prints the deal in chat.

Each item alerts once, and alerts again only after 10 minutes or if the profit grew by a fifth.

### Item tooltips

Item tooltips get a **ForeverFlip** block, headed with the auction house its prices belong to
(for example `ForeverFlip: Alliance AH`; outside the auction house, your faction's house). Each line
appears only when there is something to show, so items you only hold or could sell to a vendor get
a block too:

| Line | Meaning |
|---|---|
| **Usual price** (age, shared by) | The typical asking price of the last scan (yours, or a newer shared one) and how old it is. |
| **Cheapest today** (N listed) | The lowest price seen today, and how many units the last scan listed. |
| **Sold per day** … at … | Units measured sold per day between scans, and the median price of the sales seen. Until two scans measured it: *Sales: not measured yet*. |
| **cheapest / dearest time** | When the time-of-week pattern is known. |
| **You hold** | Stock you bought (through ForeverFlip, a bid, or elsewhere) and what it cost each. |
| **On sale by you** | Your auctions of the item now, and the lowest price among them. |
| **Deal now** | The profit of the item's current deal. |
| **Vendor pays** | What a merchant pays, marked when not yet confirmed at a merchant. |
| **Auction house, after the cut and N deposits** | One unit's money from the auction house: the usual (or sale) price after the cut, less a deposit for each try. N is the tries your own sale rate of the item suggests, 3 until it is known. Commodities pay the deposit of a stack of 20, per unit. |
| **Disenchant** | The materials' value after the cut, for a character who can disenchant. |
| **Best: …** | Which of these pays the most. |

### Marks in the Buy tab

In the game's own Buy tab, rows get a green stripe on the left when their price is low enough to
hold a deal: below the vendor price, far below the usual price of an item that sells, at or below
your shopping list price, or below the disenchant value.

- **List of items:** a row is also marked when the item has a deal now.
- **Auctions of one item and price tiers of a commodity:** each row is judged by its own price.

The marks follow the list as you scroll. An item sold at exactly its vendor price, for example,
gets no mark: there is no profit in it.

### Mailbox

At a mailbox, **Take auction mail (N)** takes everything from auction house mail: gold from sales,
won items, and expired or cancelled items.

- It takes one mail every 0.4 seconds, because faster looting causes errors.
- It skips player mail and any mail with cash on delivery.
- It stops when the mailbox closes, your bags are full or no auction mail is left, and prints a
  summary in chat.

Every auction mail is also read for the books, whether you take it with this button, with the game's
own mailbox or with another mail addon:

- **Sale invoices** give the real sale price and cut. A sale not booked yet (for example, an item you
  posted with the game's own Sell tab) is booked against your stock.
- **Expired and cancelled mails** count against the item's sale rate.
- **Won and outbid mails** settle [bids](#bids).
- **The cut** of each auction house is learned from the invoices.

### Merchant

At a merchant, ForeverFlip adds two things:

- **Sell vendor deals (N)** sells every item in your bags that was bought as a vendor deal, and
  books the sales in the journal.
- **ForeverFlip: buy here, sell on the auction house** is a panel listing the items this merchant
  sells for less than they fetch on the auction house. For each item it shows the price here, the
  expected auction price, the profit per unit (after the cut and deposit) and the measured sales per
  day. **Buy** purchases the suggested quantity: no more than about one day of sales, and within
  your budget. The items are booked as stock for resale.

The merchant's prices are remembered for the [Crafting](#crafting) page.

### Profession window

Opening a profession window saves its recipes for the Crafting page. Nothing is shown in the window
itself.

## Key bindings

Set them on **Settings → Key bindings** in the ForeverFlip tab, or in the game's **Key Bindings**
window under **AddOns → ForeverFlip**:

| Binding | Action |
|---|---|
| Buy or confirm the selected deal | Confirms a quoted purchase, otherwise buys the selected deal (or checks it first). |
| Buy the next best deal | Each press moves on: selects the best deal you can afford (and checks it), buys it, confirms a commodity price. |
| Post next bought (then Post all) | One step of Post next bought; when nothing is left, one step of Post all. |
| Cancel the next undercut auction | One step of Cancel undercut. |
| Full scan | Starts a full scan. |

A key press is an action of yours, like a click, so it may buy, post and cancel.

## Slash commands

| Command | Action |
|---|---|
| `/ff`, `/foreverflip` | Version and a short hint. |
| `/ff diag` | Statistics of the last full scan: auctions total, read, skipped and your own; items; items with a known vendor price; items below vendor price; items still collecting sales data; deals; then how the last 5 full scan requests ended (read, no answer, list kept changing, dropped by the server, closed while waiting) and how many auctions the server had sent. |
| `/ff rescan` | Clears the scan cooldown. Use it when the server did not answer a scan and you do not want to wait 15 minutes. The server may still refuse. |
| `/ff bags` | Lists bag items that are not on the Sell page, with the reason: `bound`, `not_sellable` (the auction house refuses it) or `unknown_kind` (the game has not told what it is yet). Open the auction house first. |
| `/ff export` | Opens the journal as CSV. |
| `/ff lang en`, `/ff lang uk` | Sets the language. Type `/reload` afterwards. |

## Messages

| Message | Meaning |
|---|---|
| A full scan is allowed once per 15 minutes. | Wait for the countdown on the Full scan button. |
| The auction house did not answer the full scan in 5 minutes ... | Another addon may have used the 15-minute window. ForeverFlip tries again in a minute. |
| The auction house returned an empty scan. | Try again later. |
| The auction house is busy. | The server is throttling requests. Try again in a moment. |
| Checking the current price first... | Buy was clicked on a deal that is not freshly checked. It is being checked now. |
| The price changed. The deal is checked again. | The quote for a commodity was higher than the checked price. |
| The price offer was about to expire; a new one was asked. | Click Confirm when the new quote arrives. |
| The price offer expired. Press Buy again. | A new quote could not be asked for. |
| The purchase failed (someone was faster). | The lot was sold to someone else. Nothing was spent. |
| No answer from the auction house. Settle the purchase in the Journal. | See [Buying](#buying). |
| The game asks for a confirmation: press Post again. | The game warns about the posting price. |
| No undercut auction worth reposting. | Run **Check prices** on My auctions first, or nothing would be reposted above its floor. |
| Unknown item. | The shopping list needs a link (Shift-click) or the exact name of an item the game has loaded. |
| Bid placed. / Auction won. | See [Bids](#bids). |
| Not enough money. | The deal costs more than you carry. |
| Wait for the current action. | A purchase or post is still running. |
| The spending limit of this auction house visit is reached. | Settings → Safety: raise the limit, or close and reopen the auction house for a new visit. |
| No deal to buy right now. | The Buy next key found no deal you can afford. |

Errors inside the addon are printed once in chat, as `ForeverFlip error: ...`. The latest 20 are
saved in the SavedVariables file (see [Troubleshooting](#troubleshooting)).

## Troubleshooting

**No deals after a scan.**
- Vendor deals depend on the market at that moment; often there are none.
- Resale deals need sales data, so they appear after two or three scans.
- Check the minimums in Settings, or try the Aggressive preset.
- `/ff diag` shows how many items are still collecting data.

**The scan never starts, or waits forever.** Another addon may have used the account's
15-minute window. Wait for the countdown, or use `/ff rescan` if the server did not answer.

**Buy stays disabled.** The deal must be **ready** (checked in the last 45 seconds) and no other
search or purchase may be running. Click the deal to check it again.

**Resale estimates look too optimistic.** On a client that reports each auction's time left, sales
are tracked lot by lot, and expired or cancelled auctions are not counted. Otherwise they look like
sales between two scans. Either way, ForeverFlip limits each purchase to about one day of sales (two
units while only one pair of scans exists), caps the resale price at what real sales reached, and
lowers its trust when your own stock does not sell. Raise **Minimum resale return** or use the
Careful preset to be more careful.

**Crafting page is empty.** Open your profession windows once; recipes are read from them.

**Reporting a bug.** Type `/reload`, then open
`WTF/Account/<ACCOUNT>/SavedVariables/ForeverFlip.lua` and copy the `errors` section into an issue.
The result of `/ff diag` helps too.

## A typical session

1. Open the auction house. The automatic scan starts as soon as the cooldown allows, and the sniper
   watches the house between scans.
2. Buy the **ready** vendor deals and react to alerts (bind the Buy key to be quick).
3. Check the **Resale** page after a few scans. Buy deals with a good return and a good Est./day.
4. Use **Selling → My items → Post next bought** (or Post all) to list your purchases.
5. Every so often, run **Selling → My auctions → Check prices**, then **Cancel undercut**, and repost
   when the items are back.
6. At a mailbox, **Take auction mail**. At a merchant, **Sell vendor deals**.
7. Look at **Analytics** (Overview, and By item for the Sell %) and **Crafting** to see what actually
   makes money, and drop or ignore what does not.
