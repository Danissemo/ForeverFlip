# Operation progress and Auctionator-style rows 5.3.1

Progress.lua reads controller state without executing actions. Waiting stages
have no percentage; processing uses real index/total. Terminal success, error,
manual confirmation, timeout, Stop, watch duration and throttle have distinct
labels. The Core tick paints the footer without expensive full reranking.
More transitions from manual-next-page to request waiting. FullScan throttling
now reports its failure instead of silently leaving Ready.

Rows match the inspected native20-unit Auctionator template and use the same
Blizzard auctionhouse-rowstripe-1 / auctionhouse-ui-row-highlight atlases.
Native money strings and real cached item levels are retained with exact links.
Fresh read-only review reported no Important/Critical findings,182 tests pass.
Final expanded185 tests verify throttle/Core tick and native data rendering.
Game capture is unavailable, so live progress animation/table appearance remain
unverified. Installer writes only addon files and preserves previous version.
