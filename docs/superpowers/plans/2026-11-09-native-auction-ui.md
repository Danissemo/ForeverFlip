# Native auction UI 5.3 implementation plan

User explicitly asks to fully rewrite visual UI to match supplied Auctionator
reference. Existing trade/math backend remains; no new design/approval gate.
Use wow-forever-addons, writing-plans, inline TDD, one fresh final review.

1. Add regression tests: no scaling canvas or vertical global nav, native inset
and top-tab templates, full-width readable pages, stable root AH interior, native
shopping two-pane list/table with correctly bounded columns at800x538, resize and
click identities. Preserve existing169-ish trade/data tests.
2. NativeLayout.lua owns responsive widget anchoring and native chrome. Main
shell: single search row, native top tabs, native bottom status; no logo/sidebar
or duplicated wallet/internal realm codes. Locale.font keeps standard fonts for
English and uses bundled Cyrillic where needed. No font shrink from global scale.
3. NativeShopping.lua replaces the old Deals page: native left lists/groups/watch,
right price/name/available/PnL table, native column headers and scrolling/paging,
filter/search/sort actions, row clicks only exact searches. No duplicate sidebar.
4. Migrate the existing nine-page callbacks into the new shell and responsive
full-width native-inset forms. Auction primary tab has subgroup tabs for Deals,
Plan and Watch. Keep all rule/accounting/profession features; no trade backend edits.
5. ItemDisplay rows get native highlight/selection and responsive price-first
column geometry. Quality icons and exact native tooltips remain. Rebuild/reflow
on parent size without SetScale. Native import/export modal fits parent.
6. Independent review; full Lua51 suite, compile, LuaLS, Ukrainian coverage,
package5.3.0-preview, backup/installonlyaddonfiles, noWTF writes, /reload activation.
Nativevisual acceptance still cannotbeclaimedwithoutclientcapture.

Ruling: native shapes/assets/templates come from loaded Blizzard AH UI, not copied
Auctionator code or imported addon templates. Existing source repo is isolated from
live game; dedicated branchfeature/5.3-native-auction-ui.
