# Validation and release status

Release: **5.0.0-preview**, target WoW Forever 1.60.1.70862 / Interface 16001.

Automated coverage runs actual Lua 5.1 through Lupa, not Lua 5.4 syntax alone:

- Full/partial/mismatched/stale results, repeated quotes and raised quotes.
- Independent history, volume quantile, MAD/outliers, unknown/future prices.
- Exact buy ladder, indivisible item lots, NPC without AH history, current
  wallet and exposure limits, group holdings and per-character reservations.
- FIFO partial unknown cost, integer allocation, owner/variant separation,
  receipt duplication and append-only corrections.
- Unknown trade after timeout/reload, missing receipt fields, itemID-only
  native event requiring manual reconciliation.
- v4 migration, real recipe/yield field mapping, atomic legacy assignment,
  malformed/future schemas preserved without enabling trading.
- Safe formulas, malformed group exchange, exact-key groups/watchlist,
  market/timestamp checks on price import, bounded history/ladders.
- Eight UI sections, callbacks, calculator persistence, formula changes,
  actual LibAHTab major name and native line endpoint signature.
- 100,000 synthetic replicate rows processed in batches of 220; no trade
  API calls occur from the full-scan path.

An independent reviewer found substantive defects in an earlier development
commit. Dedicated regression tests reproduced them before the fixes. The final
test log is packaged beside the ZIP as `tests.txt`; the build records module
count and checksums in `build-report.json`. LuaLS Error-level diagnostics are
also checked against the installed WoW API annotations. Mock UI assertions are
limited evidence for real layout and native API execution.

**Not verified in a running WoW client:** real tab layout, asynchronous server
timing, protected purchase/post/bid acceptance, real NPC quotes, mailbox invoices,
Auctionator coexistence and measured frame times. No gold was spent during
development. This preview must not be represented as live-tested or as more
profitable than TSM.

Conscious boundaries: no automatic execution of protected actions, no paid TSM
database, no HTTP requests in the addon, no automatic attribution of itemID-only
receipts to a variant. Mail matching is a suggestion; the player confirms actual
receipt and amount. Bank/mail physical quantities are not inferred as known:
positions show in-bag quantity separately from quantities outside bags.

Live acceptance steps: install with backup, open AH, check all eight pages,
scan an item and a variant, request and cancel a commodity quote, test one small
purchase and one post manually, reconcile receipts, verify an NPC valuation,
then reload and check that reservations and FIFO balances remain correct.
