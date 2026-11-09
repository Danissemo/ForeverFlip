# Embedded auction tab fix 5.2.1

User screenshot showed a detached high-strata movable panel beside an empty
auction window. Actual installed LibAHTab5 controls tab visibility only, not frame
layout. Fix root viewport anchored AH interior (4,-34)/(-4,28), separate logical
1080x680 child canvas fitted to parent dimensions, inherited frame strata, no
detached move/resize/close. All nine sections remain in the shared viewport.
Slash selects the library tab; fallback uses the native bottom-tab template and
clears native display before showing content. Saved dimensions ignored.

Regression tests failed before fix, pass after. No trading changes. Installer
backs up current addon and copies only addon files while game is running; no WTF
writes. A UI reload is needed to load updated Lua. Native screenshot capture timed
out; final live visual acceptance remains for the user after reload.

User extended the request to Auctionator-like item presentation. Version5.2.2
adds ItemDisplay.lua native icon/name/quantity/unit-price/PnL/status columns,
quality borders and GameTooltip. Carry actual item links through replication,
ranking and allocation. Unknown families/variants never get invented base-item
exact tooltips. Bounded C_Item data loads and batched GET_ITEM_INFO_RECEIVED
refresh keep cache bursts from triggering repeated expensive ranking.
A second fresh read-only review found no Important/Critical findings and reran
141 tests; an additional family-tooltip regression now passes as well.
