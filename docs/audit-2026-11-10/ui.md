# UI audit — 2026-11-10

Scope: current working tree UI.lua, NativeLayout.lua, NativeShopping.lua, ItemDisplay.lua, Locale.lua, Progress.lua, relevant tests and checked-out Forever native UI reference. Read-only audit; no production/game edits or UI actions. Reproductions below execute addon code in existing `test_ui.ui_runtime()` with controlled external WoW mocks using `C:/FF/.tools/python/Scripts/python.exe`. They establish Lua state, routing, text and widget allocation; they do not establish native rendering, font measurements, protected-action behavior or real AH responses.

## Prioritized confirmed findings

### 1. [P2] Action routes reopen the remembered Trading subpage instead of the selected deal

Source: `NativeShopping.lua:214`; `UI.lua:342,457,2179`; remembered-page fallback `NativeLayout.lua:271`.

Trigger: visit Trading → Sell what you bought (or Calculation/Bids), return to Auction, click a deal. `ui:show("trade")` omits `"deal"`, so `selectPage` restores the previous subpage. The exact search runs, but the deal card and purchase controls stay hidden. The same issue affects toolbar exact search, planner-line routing and reagent procurement. Explicit navigation should choose the destination page while ordinary tab clicks can continue remembering their page.

Empirical reproduction after `l=ui_runtime()`:
```lua
u:show('trade','sell');u:show('deals')
c.candidates={{key={itemID=1},rows=rows,at=now,scope='scope',family=false,kind='commodity'}}
u:refresh();u.dealRows[1]:Click()
print(u.section,u.pages.trade,u.sections.trade.split.pages.deal:IsShown(),c.job~=nil)
-- trade, sell, false, true
```
Existing routing tests assert only `u.section=='trade'`, so they pass while the destination controls are invisible.

### 2. [P2] Every profession calculator displays its result on a different, hidden category

Source: result scroll created `UI.lua:2135–2142`; moved only into Reagents `UI.lua:2696`; calculator callbacks e.g. `UI.lua:2017–2022`; renderer `UI.lua:2555–2590`.

The shared result scroll lies at original y=670 and is migrated exclusively into Tools → Buying reagents. Vendor, Crafting, Disenchanting and Between markets buttons calculate and write that scroll, but never navigate to its page. Clicking Calculate on those four pages appears to produce no result except the generic completion footer. The user must discover that Buying reagents contains every calculator result.

Empirical reproduction:
```lua
u.fields.materials:SetText('1*3@0.01');u.fields.outputPrice:SetText('1')
u:show('tools','craft');u.actions.craftCalc:Click()
print(u.toolScroll:GetParent()==u.sections.tools.split.pages.reagents,
      u.pages.tools,u.sections.tools.split.pages.reagents:IsShown(),u.toolResult~=nil)
-- true, craft, false, true
```
Tests check the result model/text, not the visibility of its ancestor page.

### 3. [P2] The Sell panel drops purchased items beyond its first six and clears externally selected later items

Source: fixed count `UI.lua:3273,3302`; truncation and selection invalidation `UI.lua:3465–3490`.

Seven or more purchased item identities in bags produce a complete `sellCandidates()` list, but only its first six are rendered. There is no paging, scrolling or alternate selector in this panel. `stillThere` is also calculated only over those six displayed rows, so selecting the seventh through another route is cleared on refresh despite the item remaining in bags. This prevents using the addon sell flow for later items until earlier identities disappear.

Empirical setup: append seven owned buy entries with keys `1:0:0:0` through `7:0:0:0`, and have `api.bagItems()` return one matching stack per identity. Observed `#u:sellCandidates()==7`, `#u.sellRows==6`, last rendered ID=6. Then:
```lua
u:show('trade','sell');local seven=u:sellCandidates()[7]
u:selectSellItem(seven);u:refresh()
print(seven.key.itemID,u.sellItem~=nil)
-- 7, false
```

### 4. [P2] My auctions silently discards every owned listing after the eighth

Source: `UI.lua:3180–3185` creates eight rows; `UI.lua:3225–3226` always uses `list[i]`.

`c.owned` can contain the entire owned-auction response, but My auctions displays only the first eight. No page controls, scroll child or count/truncation notice exist. Users cannot inspect sold/undercut status for the rest of their auctions, a normal case for an auction trading addon.

Empirical reproduction: fill `c.owned` with nine `{key={itemID=i},qty=1,buyout=1000}` records, set `c.ownedAt=now`, then show Portfolio/auctions. `#c.owned==9`, `#u.ownedRows==8`, last rendered name is Item 8; Item 9 has no row.

### 5. [P2] Visible Portfolio sale advice ignores the configured risk reserve

Source: `UI.lua:3006–3014`, particularly net calculation at 3008. Contrast correct reserve deduction in the hidden legacy text at `UI.lua:1736–1738`.

For an owned unit costing 900 copper, current price 1000, fee 5%, reserve 10%, the visible row says to list and colors the advice green because it compares 950 to 900. The configured net is 850, below cost. This conflicts with the reserve-aware decision in the hidden legacy portfolio text and the rest of the risk-adjusted trading workflow.

Empirical reproduction: set `ForeverFlip.Util.vendor=function() return nil end`, settings fee=.05 and reserve=.10, market latest price=1000, append one owned buy at total=900; show Portfolio/items. Actual visible advice: `List at 0g 10s 00c each`; hidden old `portfolioText` says `watch`.

`test_portfolio_sale_hint_uses_actual_group_fee_and_reserve` inspects `portfolioText`, which now remains under the hidden old viewport. It does not validate the advice users see.

### 6. [P2] Auction name filtering cannot match common lowercase Ukrainian input

Source: `NativeShopping.lua:347,359`.

Both query and item/group text use Lua 5.1 byte-string `lower()`, which lowercases ASCII and leaves UTF-8 Cyrillic capitals unchanged. Typing a normal lowercase item name therefore does not match its capitalized localized display name. This affects the toolbar name-search flow because it forwards text to this filter, in the Ukrainian UI.

Empirical reproduction: make `GetItemInfo` return `Мідна руда`, supply one candidate, and show Auction. Query `мідна` produces zero visible results; query `Мідна` produces one. Use a supported UTF-8 case-folding function rather than byte-string lower.

### 7. [P3] Active or paused Live mode hides manual action failures behind generic Live status

Source: status replacement `UI.lua:3756–3778`; Live progress takes precedence over failures `Progress.lua:192–235,256`.

With radar enabled, the Auction status always replaces controller errors with the generic Live caption, even while radar is paused. The progress footer returns the Live state before checking the failures table. A failed explicit full-scan request is therefore not reported as throttled in either visible status surface.

Empirical reproduction: set `db.lastReplicate=now`, start radar, set `api.ready=function() return false end`, show Auction, click Full scan. Controller message is `throttled`; status is `Live search: one listing check per second ... Full scan in 15 min.`; progress is `Live paused — click Resume`. The dedicated throttled explanation and error indicator disappear. Prioritize the most recent failed manual action while preserving the background Live indicator separately.

## Native layout concerns requiring client rendering

The checked-out Forever `Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseFrame.xml:5` declares 800×538, matching the repository tests. At this size the canvas is 792×476, section height364, split-page interior approximately576×346. At1100×700 those interiors become876×508. Sizes refer to UI coordinates; lowering display resolution alone does not imply a smaller AuctionHouseFrame.

The fixed-width Sell controls reach x558 and fit the native default page; Stats columns reach x550 and owned/portfolio headers x555. No confirmed horizontal overflow at default size was found. Smaller third-party resized AH windows would need explicit native testing; no unsupported small-size claim is counted above.

History (`UI.lua:1826,1880–1916`, migration at2684) starts its multiline recent-day/hour text at page y315, after a220px chart. Eight daily rows plus the headings and up to four hourly rows can require roughly15–16 font lines. Only31px remains inside the default page, and the ancestor root clips children (`UI.lua:289`). The source geometry strongly predicts lost lower rows at800×538. Watch/group summaries at original y420 → page y240 likewise have unbounded lines without scrolling. These are source-derived native-rendering concerns, not empirically measured game rendering findings; the existing mock fixes font height at30 and does not solve anchors or inherited clipping. Verify with real font metrics and screenshots before claiming exact clipping extent.

The custom trade card has no tooltip handler on its actual visible icon/name; the exact item renderer is hidden by `refreshCard` (`UI.lua:3559`). Auction and planner rows do have real item tooltip handlers. Whether the visible trade card is expected to expose a tooltip needs product confirmation rather than a fabricated runtime failure.

## Other checks and limits

- Read TOC/load order, locale aliases/catalog/font usage, progress operation precedence, native tab selection, row column layout, AH source sizing and tooltip dispatch. No additional proven API incompatibility was found in these six modules.
- Existing tests passed:27 `test_*ui.py` tests;10 `test_native*.py`;7 ItemDisplay;7 Locale;10 Progress;20 `test_tab*.py`;15 Performance. Total96 tests. No production changes or test-file edits were made.
- Existing external widget mock accepts unknown methods as no-ops, ignores anchor solving, uses fixed font-string height, does not inherit parent visibility in `IsShown`, and permits `Click()` on hidden controls. Tests proving data/state changes or absence of Lua exceptions cannot establish actual accessibility/rendering.
- Progress omits `post_no_item`, `post_search`, `item_unavailable`, `rescan` from its failure table, so these can show Ready while the adjacent status explains the failure. This is a lower-priority presentation inconsistency; it was not counted separately from the proven manual-error masking above.
- No client profiling, protected-action test, actual purchase, auction submission, in-game screenshot, or live tab-integration action was performed. Root auditor owns the separate synchronous candidate-restoration performance finding.
