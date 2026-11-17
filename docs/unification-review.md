# What is not unified yet

A review of ForeverFlip after the Best-route, strategy-lock and Market reset work (2026-11-17).
Each item says where the code differs, why it matters, and what unifying it would take.

**Status: all ten were carried out on 2026-11-17** (installed, not committed):
1. `Market.THRESHOLDS` + `Market.thresholds(s)`; `Data.lua` defaults come from it.
2. `Market.maxBuy(value, route, s, perUnit)` for Bids, Sniper, Disenchant and the vendor deals. Now
   every route asks both the minimum profit and the minimum return (Disenchant and Sniper's
   disenchant limit asked only the profit; Sniper's auction limit per unit asks the return only).
3. `Deals.priceOf` (fresh check, then usual) for Crafting and Disenchant; `Deals.usualOf` for Trade.
4. `Market.unitNet` and `Market.auctionNet` for Crafting, Sniper, Bids and Merchant.
5. `F.STRATEGIES` (Util.lua): the Deals pages, the Journal views and the Selling note are built from
   it. The ids stay.
6. `UI.C` + `UI.paint`: one shade per meaning (orange and grey shades merged).
7. `UI.pct` / `UI.pctText`: one rounding (half up).
8. `UI.tip(frame, title, body, anchor)` for page buttons and column headers.
9. Disenchant judges selling the item as it is (`Disenchant.sellValue`, by `Market.sellRoutes`):
   when that brings as much, there is no disenchant deal. The item tooltip and the My auctions
   tooltip share `UI.ROUTE`, `UI.optionHead`, `UI.optionMark`, `UI.optionDetail`.
10. `Util.TUNING`: the route judgement, the 14 days, the plan return and the Analytics shares. None
    was moved into Settings; say which should be.

Already unified in this round, for reference:
- **Route choice.** Selling (`Trade.sellWay`) and Crafting (`Crafting.profits`) now both choose the
  route through `Market.sellRoutes` and `Market.routeVerdict`.
  - Crafting shows the same Best labels as Selling, through `UI.routeLabel`.
  - Crafting has a Sure column.
- **Two-column tooltip lines.** Every one now goes through `UI.tipPair`, which wraps a long line
  instead of cutting it off at the right edge. Direct `AddDoubleLine` calls remain only inside
  `UI.tipPair`.
- **The purchase strategy.** It is kept on the lot (`lot.strategy`) and on the position
  (`p.strategy`). It is read in one place, `Trade.boughtWay`.

## 1. Profit thresholds: the defaults are repeated about 25 times

`s.minProfit or 100`, `s.minROI or 0.2` and `s.vendorMinProfit or 10` are written out in:
- Bids.lua;
- Disenchant.lua;
- Market.lua (5 places);
- Sniper.lua;
- UI.lua;
- UIDeals.lua.

The defaults already live in `Data.lua`'s settings defaults. If a default changes, every copy has
to change with it.

**Proposal:** a single `Market.thresholds(s)` that returns `{ minProfit, minROI, vendorMin }`.

## 2. "The most to pay": three different formulas

| Where | Formula |
| --- | --- |
| `Bids.maxBid` | `min(value - minProfit, value / (1 + minROI))`: both conditions at once |
| `Sniper` (auction exit) | `(net(exit) - deposit) / (1 + minROI)`: ROI only, no minProfit |
| `Sniper` and `Market` (vendor) | `vendor - max(1, vendorMinProfit)` |
| `Sniper` (disenchant) | `value - minProfit`: no ROI |

So for the same item, Sniper may pay more than Bids would bid.

**Proposal:** one `Market.maxBuy(value, route, s)` used by Bids, Sniper and the Deals pages.

## 3. "The usual price of an item" is read in four ways

- **`Crafting.usual`:** a fresh check (`Trade.freshCheapest`) first, then `Market.usual`.
- **`Disenchant.usualOf`:** `Market.usual` only.
  - The fresh check is ignored, so Disenchant can disagree with Crafting about the same material.
- **`Trade.usualOf(key)`:** `Market.usual` on the scope's history.
- **`Market.usualTarget`:** the target price for posting.

**Proposal:** a single `Deals.priceOf(key)` (fresh check, then the usual price), used by Crafting,
Disenchant and Selling.

## 4. Deposit and auction net: computed in three places

- **Selling:** `Trade.depositFor` uses `Market.postDeposit` with the post's duration.
- **Crafting:** calls `Market.postDeposit` itself with `Market.duration`.
- **Sniper:** uses `Market.unitDeposit`.
- **The net after the cut:**
  - `Market.net` is used everywhere, which is good;
  - but "net minus deposit" is put together by hand in Crafting, Sniper and `Market.quote`.

**Proposal:** `Market.auctionNet(id, kind, key, price, units)`, which returns net, deposit, and
net minus deposit.

## 5. Strategy names: three vocabularies

| Internal id | Deals tab | Journal | Selling note |
| --- | --- | --- | --- |
| `flip` | Resale | Resale | resale |
| `median` | Market reset | Market reset | market reset |
| `bid` | Bids | Bids | bid |
| `vendor` | To vendor | To vendor | vendor deal |
| `disenchant` | (Disenchant page) | Disenchant | (Best: Disenchant) |
| chain `craft` | (Crafting page) | Crafting | other |

The ids `flip` and `median` are old and do not match their names. "median" is now the Market reset
strategy and has nothing to do with a median. Renaming them means a SavedVariables migration
(positions, lots, the log and settings keys).

**Proposal:** keep the ids, and add one table, `F.STRATEGIES = { id → label, order, colour }`. The
Deals tabs, the Journal views, the Selling note and the profit views would all be built from it,
so the order and the names cannot drift apart again.

## 6. Colours are written as raw codes

The same meanings are written as raw `|cff…` codes:

| Code | Uses |
| --- | --- |
| `|cff40ff40` | 26 |
| `|cffff6060` | 18 |
| `|cffffd100` | 30 |
| `|cff999999` | 33 |

Similar shades are mixed:
- orange: `ffb84d`, `ffa040`, `ff9933`;
- grey: `999999`, `aaaaaa`, `b0b0b0`.

**Proposal:** `UI.color.good / bad / warn / dim / vendor / disenchant / choice`, plus a helper
`UI.paint(kind, text)`.

## 7. Percent and Sure formatting

- `UI.sureText` colours Sure at 70% and 40%.
- The other percentages (ROI, the share of the stock, return) are formatted by hand with
  `string.format("%d%%")` in about 17 places, with different rounding (floor vs +0.5).

**Proposal:** `UI.pct(x)` with one rounding rule.

## 8. Table rows and tooltips on the pages

- **Selling cells:** now `UI.hoverOnly`, so a click goes through to the row.
- **Deals, Crafting, Journal:** use the table's own row tooltip.
- **Some page buttons:** still set their own `OnEnter`/`OnLeave` with `GameTooltip` directly
  instead of `UI.tip`.

The behaviour is the same, but there are two ways to write it.

**Proposal:** `UI.tip(frame, title, lines)` everywhere.

## 9. The Sell-to note and the Best column in other places

- **The Disenchant page:** shows its own "value" without the route rule. An item that is better
  sold than disenchanted is judged only by its own figures, not by `sellRoutes`.
- **The item tooltip (UITab):** has its own block of sums for the auction and the vendor. The
  figures come from the same `routes`, but the layout code is separate from the Selling
  tooltip's.

## 10. Thresholds and constants scattered in modules

Examples:
- `Market.ROUTE_SURE`, `Market.ROUTE_GAIN`;
- `Trade.KEEP_DAYS = 14` (new: how long a purchase strategy is kept);
- `Crafting.PLAN_RETURN = 0.05`;
- `Analytics` "0.95 of market" and "±5%".

Some are player settings in all but name.

**Proposal:** gather them in one place, `Data.lua` constants, and decide which of them belong in
Settings.
