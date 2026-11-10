# Audit remediation implementation plan

> **For agentic workers:** Use superpowers:subagent-driven-development and test-driven-development. User explicitly requested fixes for all audit findings; execute without additional design approval.

**Goal:** Repair confirmed findings F01РІР‚вЂњF23 and address actionable quality gaps without promising unverified in-game profit.

**Architecture:** Keep the user's 6.3 native split-page UI and existing saved schema. Share effective ledger views, financial calculations and price steps. Preserve unknown outcomes and manual spending confirmation. Mail has no reliable immutable server ID: persistent multiplicity reconciliation must conservatively refuse ambiguous scope/identity rather than invent certainty.

**Tech stack:** Lua 5.1, Forever Interface16001, Python unittest/lupa; existing C:/FF toolchain.

## Global constraints

- Preserve current user modifications: full source ZIP backup made before edits; use existing fix/5.5-tab-workflows checkout.
- No WTF writes, no automatic purchases, real-test cumulative ceiling remains1g.
- Workers own disjoint production files; no commits by workers.
- Existing models remain scenarios, not promises of filled orders or TSM superiority.

## Review focus

- Repeated/identical mail across refresh/reload; ambiguous scope must not auto-book.
- Financial bounds applied equally to sparse-history and credible-history deals.
- Visible page and controls, not hidden legacy text, are the UX test target.
- Cold market restoration must yield and not overwrite exact newer results.
- New-version saved data rejects/quarantines corruption without destroying original.

## Tasks

- [x] T1 Transactions: Adapters/Controller/Ledger/Store and new audit_transaction regression tests. F01РІР‚вЂњF04,F08,F11РІР‚вЂњF12,F20. RED then GREEN; incremental restoration interface consumed by Core.
- [x] T2 Models: Market/Professions/Stats and new audit_models tests. F05РІР‚вЂњF10; effective void accounting via Ledger view; finite/fee/quantity checks; document scenario limitations.
- [x] T3 UI: UI/NativeLayout/NativeShopping/Progress/Locale/ItemDisplay and new audit_ui tests. F13РІР‚вЂњF19,F21; visible tooltips, bounded list pagination, scrollable long content.
- [x] T4 Root: Core integration, idempotent registration/setup, deterministic dependency setup, build gates, stronger mock opt-in semantics, current docs/version/status matrix. F22РІР‚вЂњF23,D02РІР‚вЂњD08.
- [x] T5 Integration: full tests, compile, lint, LuaLS, benchmarks and independent review. Resolve review findings with regressions.
- [ ] T6 Delivery: archive/source/receipt, back up installed addon, hash-verified deployment; native live attempt if available; explicitly retain unverified checks and0-spend truth if capture unavailable.

## Rulings

- Preserve intentional daily NPC budget growth; show accurate limits in UI/docs and retain a separate hard1g ceiling for any actual agent test. User asked to fix defects, not restore old trading policy.
- Previously auto-imported mail is not deleted heuristically; retain uncertain legacy records, prevent new duplicates and expose conservative manual reconciliation.
- Runtime validation and honest labels address model limitations; actual superiority/market liquidity cannot be manufactured by code changes.

## Verification progress

- Independent financial review resolved all3 extra findings; 347 tests passed at that checkpoint.
- Independent runtime review resolved stale snapshot, moved-stack and manual-completion regressions; failure maps now capped together at4000 with RED/GREEN regression.
- UI16 + Radar4 audit tests passed. Full current build is the final gate.
- Native capture attempted twice: FrameArrived/window capture timeout; no input,0 spend.

Final gate checkpoint:351 tests,21 Lua5.1 modules, StyLua and LuaLS passed. Review has no outstanding actionable findings. T6 deployment pending; native test unverified.
