# Full functionality / formula audit 2026-11-09

Baseline af73854,149 tests green. First independent read-only audit reviewed
Controller, Adapters/native contracts, Ledger, Advisor, Workbench and identified
two reproduced P2s: seller mail included returned deposit in profit and posting
formula context lacked supported sources. Parent's independent arithmetic and
integer/decimal oracle tests found further edge defects.
Every fix had a failing reproduction then green verification. Second fresh
read-only reviewer found no Important/Critical issues in the final patch and
independently ran167 tests under Lua51. No user SavedVariables rewritten.
Original releases preserved; version5.2.4 packaged and deployed after verification.
