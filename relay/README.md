# Upload relay

Players without a GitHub account share their full scans through this relay. It is a single
Cloudflare Worker ([`worker.js`](worker.js)) on the free plan, with one KV namespace for storage.

The relay only keeps files. It holds no GitHub credential and publishes nothing. Every 30 minutes
the data repository's workflow collects the waiting scans with a secret key and checks them like
any other upload: format, age and seal, confirmation by another player's scan, and agreement with
the community's price history (see [Community data](../docs/community.md)). Collected and refused
files are deleted from the relay; a file nobody collects is dropped after three days.

## What the relay checks

| Check | Limit |
|---|---|
| Scan details sent with the file | auction house name, time, seal, auction count, SHA-256, helper version |
| Scan age | not from the future, at most 7 days old |
| File | gzip, at most 25 MB |
| Scans waiting per player | 4 (a player is a keyed hash of the address; the address is not stored) |
| Scans waiting in all | 300 |
| Same file twice | kept once |

## Setting it up (about ten minutes, no command line)

1. Create a free account at [dash.cloudflare.com](https://dash.cloudflare.com).
2. **Storage & Databases → KV → Create**: name it `foreverflip-uploads`.
3. **Workers & Pages → Create → Worker** (the "Hello World" start), name it `foreverflip-relay`,
   press **Deploy**, then **Edit code**. Replace all the code with the contents of
   [`worker.js`](worker.js) and press **Deploy** again.
4. In the worker, **Settings → Bindings → Add → KV namespace**: variable name `UPLOADS`, namespace
   `foreverflip-uploads`.
5. Make a random key. In Windows PowerShell:

   ```powershell
   $b = New-Object byte[] 32; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); ($b | % { $_.ToString('x2') }) -join ''
   ```

   In the worker, **Settings → Variables and Secrets → Add**: type **Secret**, name `RELAY_KEY`,
   value the key.
6. Open the worker's address (`https://foreverflip-relay.<your-name>.workers.dev`). It should answer
   `{"ok":true,"service":"ForeverFlip upload relay"}`.
7. In the data repository on GitHub, **Settings → Secrets and variables → Actions**:
   - **Secrets → New repository secret**: `RELAY_KEY`, the same key;
   - **Variables → New repository variable**: `RELAY_URL`, the worker's address.
8. Put the address into `relay.json` at the root of the data repository:

   ```json
   {"url": "https://foreverflip-relay.<your-name>.workers.dev"}
   ```

   The Sync helper reads it, so a new address needs no new helper build.

The key never goes into the helper or into a repository: only the worker and the data repository's
workflow know it. To stop anonymous uploads, delete `relay.json`; to cut one player off, add their
`anon-...` id to `banned` in the data repository's `registry/uploaders.json`.

## Free plan limits

KV on the free plan allows 1,000 writes and 100,000 reads a day and 1 GB of storage: about 1,000
uploads a day, far above what the community produces. If the limits are reached, uploads are
refused for the rest of the day and the helper retries later; nothing already shared is lost.
