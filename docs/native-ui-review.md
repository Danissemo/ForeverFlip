# Native auction UI 5.3 review

User screenshots establish native Auctionator shopping layout as the target.
New NativeLayout.lua/NativeShopping.lua replace the scaled global dashboard
and oldDeals screen. General pages retain tested business callbacks in native
full-width scroll insets. No Controller/Market/Ledger/Advisor changes.

Fresh read-only reviewer checked current Blizzard XML/mixins and the exact
search callback contract;172 tests independently green. Reviewer found one P2:
history's fixed800px chart clipped at native750px body. Added red regression,
registered responsive chart and derived endpoints from actual width. Native
template OnShow/OnEvent can resize tabs and selection changes font objects;
added regressions and absolute tab resizing plus Cyrillic font restoration.
Final suite175 tests green. Native screenshot capture timed out even with game
foreground, so no live visual comparison. Installer backs up addon files and
updates only source/assets; no WTF writes, no actual trading during verification.
