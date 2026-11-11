# ForeverFlipAPI

ForeverFlip offers its prices to other addons through one global table, `ForeverFlipAPI`.
Everything else in ForeverFlip is private and may change; this table will not. New functions may be
added (and `version` raised); the existing ones keep their names, arguments and meaning.

## Using it

Add ForeverFlip as an optional dependency in your TOC, so it loads first when both are installed:

```
## OptionalDeps: ForeverFlip
```

Check that it is there before calling it:

```lua
local ff = ForeverFlipAPI
if ff and ff.IsReady() then
    local usual, cheapest, sellsAt, perDay, age = ff.GetPrice(itemLink)
    if usual then
        print(("ForeverFlip: %d copper, seen %d min ago"):format(usual, age / 60))
    end
end
```

`item` is an item link, an item string (`"item:2589::::::"`) or an item ID (`2589` or `"2589"`).
Gear is priced per ending ("of the Bear"); pass a link to get the right one. Prices are in copper per
unit, for the auction house the player uses (realm and faction, or the neutral house while one is
open; hardcore realms have their own). Anything ForeverFlip does not know returns nil, never an error.

## Functions

| Call | Returns |
|---|---|
| `ForeverFlipAPI.version` | `1`. Raised when a function is added. |
| `ForeverFlipAPI.IsReady()` | `true` once ForeverFlip's saved data has loaded. |
| `ForeverFlipAPI.GetPrice(item)` | `usual, cheapestToday, sellsAt, perDay, age`. `usual` is the typical asking price of the last full scan (the player's own, or a newer one shared by another player). `cheapestToday` is the lowest price seen today. `sellsAt` is the median of the sales seen (nil with fewer than 3). `perDay` is units sold per day near the usual price (nil if unknown). `age` is seconds since the usual price was measured. |
| `ForeverFlipAPI.GetDeal(item)` | `mode, profit, cost, qty, fresh`. `mode` is `"vendor"`, `"flip"`, `"shop"` or `"disenchant"`. `fresh` is true when the deal was checked on the auction house in the last 45 seconds. nil when the item has no deal. |

The functions read ForeverFlip's tables when called; nothing runs every frame.

## Prices from auxForever

If [auxForever](https://github.com/TylerHampton/aux-forever) is installed, ForeverFlip uses
`AuxForeverAPI.GetUsualPrice` as a fallback price for crafting materials it has not seen itself.
