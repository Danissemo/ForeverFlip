# Text exchange and source contracts

No imported string is evaluated as Lua. All monetary values are copper unless
explicitly described as gold. Text exchange is manual; no background app required.

## Groups

```text
FFG1|Cloth|2589,2592|25|1|100|10
```

Name, item IDs, minimum ROI percent, minimum profit gold, budget gold, max quantity.
First matching group overrides these defaults. Use Settings for global formulas.
Group budget is cumulative across owned positions and pending trades in the
group, not a fresh allowance on each click. Trade-page overrides only tighten caps.

Exact variants use a second version:

```text
FFG2|Variant gear|123:42:7:0,123:42:8:0|25|1|100|2
```

Those entries match exact item keys; they do not match other suffixes/levels.

## Price observations

```text
FFP1|wowf:3:1234:Alliance|1794230000
2589:0:0:0,123,200
2592:0:0:0,456,100
```

The header is version, exact market scope shown by the addon, Unix observation
timestamp. Rows are exact item key, volume-quantile price in copper, listed units.
The example scope/time are illustrative and must be replaced with real provenance.
Scope mismatch, future timestamp, >60-day age, malformed data and >2000 rows
are rejected. Repeated imports within a ten-minute sample bucket do not add
independent evidence. Imported observations are labelled `import`.
This is ForeverFlip's format, not an assumed format of any third-party service.

## Ledger CSV

Columns: uid, kind, owner, scope, item, quantity, total_copper, fee_copper, at.
All text is quoted and quote characters doubled. Export does not execute formulas.
Keep player identifiers private if sharing the file. Ledger correction appends
a `void` event rather than deleting the original transaction.

## Formula assumptions

Supported sources are local `market`, `recent`, `vendorsell`, `avgbuy`, and
optional `aux`. An absent source is invalid. No TSM Premium data is bundled.
This language intentionally differs from TSM precedence and unsupported features;
test each imported idea in the rule fields instead of pasting arbitrary TSM strings.

## Scope and confirmation

Exact search, quote and purchase confirmations use the actual client API.
Local task IDs do not manufacture an unavailable server request ID. Avoid
concurrent trades for the same item in another addon. All protected actions
remain separate user clicks. Unknown execution results retain reservations.
