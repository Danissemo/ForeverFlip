# 5.2 final independent review

Base d1cedd3. Fresh read-only reviewer identified one important bug: group quote
revalidation restored group budget without reapplying the newly computed advisor
cap after wallet changes. Regression reproduced quote2900/wallet100000 then
wallet90000/advisorcap2700: confirmation incorrectly succeeded. Reapply cap after
reservation restore. Regression now blocks the purchase.

A separate regression covers unresolved same-item quantities in the cold probe;
count held pending quantities excluding the current operation being revalidated.
A normal one-unit quote/confirmation still succeeds. The initial positive-path
fixture had 10 units at a 90% price decline, intentionally triggering the old crash
guard; corrected to a single-lot fixture, without weakening the market-crash guard.

Financial source boundaries, stale data and formula failures remain tested.
Final automated count, Lua51 compile and ZIP hashes are emitted by tools/build.py.
Live client layout, protected API calls and income impact remain unverified.
