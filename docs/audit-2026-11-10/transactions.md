# Transaction/accounting audit — 2026-11-10

Scope: current working-tree `ForeverFlip/Controller.lua`, `Adapters.lua`, `Ledger.lua`, `Store.lua`, `Core.lua`; read-only source inspection. No game actions, source edits, or purchases. All paths below are relative to `C:/FF/development/foreverflip`.

## Additional confirmed findings

### P2 — Ledger capacity is checked after spending, leaving the successful purchase unreconcilable

Locations: `ForeverFlip/Controller.lua:844` (`requestBuy`), `:942` (receipt), `:994` (reconcile); `ForeverFlip/Ledger.lua:6`.

Trigger: accumulate 10,000 ledger entries and buy another otherwise-valid lot. `allowed`, `requestBuy` and `confirmBuy` allow the operation and invoke the spending API. Receipt append then fails because the ledger is full, sets the operation to `unknown`, and retains its reservation. Manual success reconciliation calls the same append function and fails forever at that capacity. Export does not remove entries, and corrections also require capacity (`Ledger.lua:36`). Thus the UI permits a real purchase whose cost/stock cannot be recorded or reconciled successfully through the provided flow; the user can only falsely cancel the operation or edit data externally.

Tested with Lua 5.1 harness: fill ledger with 10,000 valid zero-cost expense entries, search commodity ID 1, request/quote/confirm a 10-item 1,000c purchase; mocked spending count becomes 1, receipt leaves ledger length 10,000/status unknown, and `reconcile(uid,true)` returns false. The same guard is absent for item buy and bid paths. Recommendation: block spending when no receipt slot can be reserved, and provide a safe capacity/archival recovery path.

### P2 — Two distinct, identical sale invoices share a UID and one sale disappears

Locations: `ForeverFlip/Adapters.lua:411-419`; `ForeverFlip/Controller.lua:1934-1938`.

The native fingerprint has no per-message identifier or occurrence discriminator. Two separate auctions of the same item/quantity, same buyer, same bid, same subject, same proceeds, with expiry in the same minute produce the same fingerprint even though their inbox indices differ. `recordMailSale` uses that fingerprint as its unique ledger UID. The second legitimate invoice is rejected as a duplicate, understating sales and retaining FIFO stock that was actually sold.

Tested the downstream path: two distinct mail tables with identical seller/name/qty/amount/deposit/fingerprint and a unique matching listing result in `mailRecorded == 1` and one ledger entry. Static adapter inspection confirms that inbox index is available (`index=i`) but not represented in the identity, so the native input can produce these collisions. This is additional to the already-known decreasing-daysLeft duplicate-recording defect: fixing expiry volatility alone does not distinguish multiple identical live messages. Recommendation: reconcile invoice multiplicity with persistent stable matching, rather than assuming content fields uniquely identify a mail.

### P2 — Automatic mail recording can charge a sale to the wrong market

Locations: `ForeverFlip/Controller.lua:1892-1908`, `:1941-1945`; `ForeverFlip/Adapters.lua:395-420`.

Trigger: the character has posted the same named item/quantity in two market scopes (e.g. faction and neutral), has the faction market selected when visiting the mailbox, and receives proceeds for the neutral sale. The invoice carries no market scope; `mailProposals` considers only listings whose scope equals the currently selected market and `recordMailSale` writes `scope=self.api.scope()`. Even when listings exist for both scopes, the other scope is excluded before ambiguity checking. The neutral sale is therefore confidently auto-recorded against the faction FIFO queue, changing both markets' stock/profit incorrectly.

Tested: install listing history for scopes `Neutral` and `Alliance`, same item/key/name/qty; set current scope `Alliance`; feed one seller invoice representing the neutral sale. `mailProposals()` appends a sell entry with scope `Alliance`. The invoice-origin label is deliberately outside the supported mail fields, demonstrating the missing evidence. Both scopes are legitimate configured market choices in `UI.lua:2341-2350`. Recommendation: consider all owner listings and require explicit scope resolution when the invoice cannot identify one market, rather than filtering ambiguity away.

### P2 — Corrected buys still exhaust material-request and NPC purchase budgets

Locations: `ForeverFlip/Controller.lua:267-283` (material request), `:345-351` (NPC spend); comparison: `ForeverFlip/Ledger.lua:71-85` correctly excludes voided entries.

A user can append a correction for an erroneous purchase through the ledger UI. FIFO summary then removes the buy, but the material-request loop reads raw `buy` entries after `request.first`, ignoring the appended `void`. The request can remain completely fulfilled/spent despite there being no actual purchase in the corrected ledger. The NPC daily-spend loop likewise counts voided buys and refuses further purchases until its time window expires. This is a separate operational effect of the already-known raw-buy/void Stats issue.

Tested material case: start request for 10 units at 100c (1,000c budget), append a matching buy, correct its UID, then call `options`. Summary stock is 0, while `materialQty == 0` and `materialBudget == 0`; the legitimate replenishment is blocked. The NPC loop has the same static omission. Recommendation: calculate request spend/quantity and NPC daily spend from effective non-voided ledger entries, while retaining the existing pending-operation reservations.

## Verification and limits

Executed from `C:/FF/development/foreverflip/tests`:

`C:/FF/.tools/python/Scripts/python.exe -m unittest test_controller test_integrity test_final_workflows -q`

Result: 19 tests passed. Four isolated additional reproductions above passed assertions in fresh `controller_runtime()` instances using `lupa.lua51`; only mock spending functions ran. No test/source files were written.

Read the installed wow-forever-addons skill, TOC/load order, current schema migration/legacy adoption, FIFO/void accounting, bid/receipt/quote/posting paths and mail logic. Cross-checked current local Forever UI reference at `C:/FF/references/wow-ui-source`: auction event payloads and API signatures (`Blizzard_APIDocumentationGenerated/AuctionHouseDocumentation.lua`); post confirmation behavior (`Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseItemSellFrame.lua:489-509` and commodities equivalent); invoice semantics (`Blizzard_MailFrame/MailFrame.lua:790-846`). PostItem/PostCommodity boolean means needsConfirmation, and the adapter/controller interpretation agrees with the native UI. ITEM_PURCHASED supplies only itemID; the separate AUCTION_HOUSE_PURCHASE_COMPLETED auctionID provides exact item purchase matching as intended.

Not verified in the client: protected action restrictions/taint; ordering/timing of real receipt and price events; live auction errors or bid win/outbid lifecycle; actual mailbox refresh and withdrawal ordering; real legacy SavedVariables variants beyond existing mocks; live item-key behavior for equipment level fallbacks, random suffixes and pets. The focused tests do not prove those client behaviors. Known decreasing-daysLeft fingerprint duplication, Stats raw-buy void handling, and ladder formula/nil-target issues are not re-reported as new findings here.

## Additional data-recovery finding

### P2 — Schema-5 nested corruption is accepted as writable and crashes ordinary workflows

Locations: `ForeverFlip/Store.lua:27-64`; consumers `Controller.lua:78`, `Controller.lua:123`, `Ledger.lua:84`, `Market.lua:10`.

`Store.open` validates top-level table presence, that ledger/pending rows are tables, and selected default setting types. It does not validate the row values those workflows immediately index or calculate with. A partly damaged or hand-edited SavedVariables table is accepted as writable rather than preserved with the read-only recovery message. Tested independently in fresh harnesses, passing each database through `Store.open` and asserting writable before the call:

- `db.pending.bad={owner='owner',status='unknown',total='oops'}` -> `c:reserved()` errors attempting arithmetic on a string at Controller:78.
- `db.ledger={{kind='buy',owner='owner',scope='scope',key={},qty=1,total=1}}` -> `c:summary()` errors concatenating a table key at Ledger:84.
- `db.groups={4}` -> `c:rule({itemID=1})` errors indexing a number at Controller:123.
- `db.markets.scope={['1:0:0:0']={samples={3}}}` -> normal search-results processing errors indexing sample `s` in Market:10.

This is a recovery/availability issue for damaged local data, not an untrusted-code security claim. Existing schema rejection support makes safe rejection or quarantine the natural repair. Validate pending amounts/quantity/identity/status, ledger identity/numeric fields, group rows, sample shapes, and sequence before enabling mutation; preserve original data. Four error outcomes reproduced with Lua 5.1; no real SavedVariables were read or executed.

## Remaining uncertain leads

- Equipment exact searches can fall back from a nonzero item level to level 0 (`Controller.lua:750-767`), while ledger identity uses the query key (`:831`) and bag postings use their native key. This may split a single item's FIFO inventory across keys when native bag keys include a level that search results omit. `sameListing` intentionally tolerates this mismatch, whereas `U.key`/FIFO do not. Needs actual Forever keys for affected equipment to establish a reachable incorrect sale match; not promoted to a finding.
- `Controller.post` clamps noncommodity posting quantity to one (`:1799`) and native `api.post` passes one to PostItem (`Adapters.lua:386`). The API supports quantity, but whether any auctionable Forever noncommodity can have a stack greater than one was not established. No finding without such an item.
- Bids stay reserved until manual reconciliation; the addon does not register BIDS_UPDATED or auto-match buyer invoices. This appears consistent with the explicit manual bid/unknown reconciliation workflow, so not reported as a defect. A mocked receipt does not prove actual winning/outbid event behavior.
- Successful posts are recorded as submitted after pcall, without waiting for auction-creation confirmation, and retained listing history is used for mail suggestions. A server rejection can leave stale suggestions. A concrete incorrect invoice/item-key assignment requires a same-name variant scenario and was not established; no additional finding.
- Failed/expired auction deposits are not automatically booked as expenses. The UI supports manual expense entry; absent a requirement for automatic deposit accounting, this remains a coverage limitation rather than a confirmed correctness defect.
