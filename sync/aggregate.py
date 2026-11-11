"""Community data aggregator, run by GitHub Actions in the data repository.

For every scan uploaded to the `incoming` release:

1. check it (format, age, size);
2. archive it unchanged in the release `raw-YYYY-MM-DD` of its day (UTC), where it stays available
   for any later use;
3. add its summary (FF1) to `shared/<realm>-<faction>.txt`, which the ForeverFlip Sync helper
   downloads; each file keeps the 12 newest scans of its auction house;
4. remove it from `incoming`.

Usage (in the workflow): python aggregate.py --data <data repository checkout>
Environment: GITHUB_TOKEN, GITHUB_REPOSITORY.
"""

from __future__ import annotations

import argparse
import gzip
import json
import os
import pathlib
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import ffscan  # noqa: E402

API = "https://api.github.com"
KEEP = 12
MAX_AGE = 7 * 86400
MAX_GZIP = 80 * 1024 * 1024
MAX_ROWS = 3_000_000
MIN_ROWS = 50


class Hub:
    def __init__(self, repo: str, token: str):
        self.repo, self.token = repo, token

    def call(self, method, url, data=None, content_type=None, accept="application/vnd.github+json"):
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Accept", accept)
        req.add_header("Authorization", f"Bearer {self.token}")
        req.add_header("User-Agent", "ForeverFlip-aggregator")
        req.add_header("X-GitHub-Api-Version", "2022-11-28")
        if content_type:
            req.add_header("Content-Type", content_type)
        with urllib.request.urlopen(req, timeout=300) as resp:
            body = resp.read()
        if accept.endswith("json") and body:
            return json.loads(body)
        return body

    def release(self, tag, create_body=None):
        try:
            return self.call("GET", f"{API}/repos/{self.repo}/releases/tags/{urllib.parse.quote(tag)}")
        except urllib.error.HTTPError as exc:
            if exc.code != 404 or create_body is None:
                raise
        payload = json.dumps({"tag_name": tag, "name": tag, "body": create_body, "prerelease": True}).encode()
        return self.call("POST", f"{API}/repos/{self.repo}/releases", payload, "application/json")

    def assets(self, release):
        out, page = [], 1
        while True:
            batch = self.call("GET", f"{API}/repos/{self.repo}/releases/{release['id']}/assets?per_page=100&page={page}")
            out += batch
            if len(batch) < 100:
                return out
            page += 1

    def download(self, asset) -> bytes:
        return self.call("GET", asset["url"], accept="application/octet-stream")

    def upload(self, release, name, data):
        url = release["upload_url"].split("{")[0] + "?name=" + urllib.parse.quote(name)
        try:
            self.call("POST", url, data, "application/gzip")
        except urllib.error.HTTPError as exc:
            if exc.code != 422:  # already archived
                raise

    def delete(self, asset):
        self.call("DELETE", f"{API}/repos/{self.repo}/releases/assets/{asset['id']}")


def check(scan: ffscan.RawScan, now: float) -> str | None:
    """Why a scan is refused, or None."""
    if not re.fullmatch(r"[^|\n]+-(Alliance|Horde|Neutral)", scan.scope):
        return "bad auction house name"
    if scan.at > now + 600 or now - scan.at > MAX_AGE:
        return "too old or in the future"
    if not MIN_ROWS <= len(scan.rows) <= MAX_ROWS:
        return "implausible number of auctions"
    if any(r is not None and (r.buyout < 0 or r.count < 0) for r in scan.rows):
        return "negative values"
    return None


def scope_file(scope: str) -> str:
    return re.sub(r"[^A-Za-z0-9-]", "-", scope) + ".txt"


def add_summary(shared: pathlib.Path, scan: ffscan.RawScan) -> bool:
    """Adds the scan's summary to its auction house file; False for a scan already there."""
    path = shared / scope_file(scan.scope)
    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    entries = []
    for line in lines:
        m = re.match(r"^FF1\|[^|]+\|(\w+)\|", line)
        if m:
            entries.append((int(m.group(1), 36), line))
    if any(abs(at - scan.at) < 120 for at, _ in entries):
        return False  # the same server scan, read by another player
    entries.append((scan.at, ffscan.encode_summary(scan.scope, scan.at, ffscan.summarize(scan))))
    entries.sort(key=lambda e: e[0], reverse=True)
    path.write_text("\n".join(text for _, text in entries[:KEEP]) + "\n", encoding="utf-8")
    return True


def write_index(shared: pathlib.Path) -> None:
    index = {}
    for path in sorted(shared.glob("*.txt")):
        lines = [l for l in path.read_text(encoding="utf-8").splitlines() if l.startswith("FF1|")]
        if lines:
            scope = re.sub(r"%([0-9A-Fa-f]{2})", lambda m: chr(int(m.group(1), 16)), lines[0].split("|")[1])
            latest = max(int(l.split("|")[2], 36) for l in lines)
            index[scope] = {"file": path.name, "scans": len(lines), "latest": latest}
    (shared / "index.json").write_text(json.dumps(index, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", required=True, help="checkout of the data repository")
    args = parser.parse_args()
    hub = Hub(os.environ["GITHUB_REPOSITORY"], os.environ["GITHUB_TOKEN"])
    shared = pathlib.Path(args.data) / "shared"
    shared.mkdir(parents=True, exist_ok=True)
    now = time.time()
    incoming = hub.release("incoming", "Uploads of the ForeverFlip Sync helper, processed every few minutes.")
    done = refused = 0
    for asset in hub.assets(incoming):
        name = asset["name"]
        try:
            if asset["size"] > MAX_GZIP:
                raise ValueError("file too large")
            packed = hub.download(asset)
            scan = ffscan.decode_raw(gzip.decompress(packed).decode("utf-8"))
            why = check(scan, now)
            if why:
                raise ValueError(why)
        except (ValueError, OSError, EOFError) as exc:
            print(f"refused {name}: {exc}")
            hub.delete(asset)
            refused += 1
            continue
        day = time.strftime("%Y-%m-%d", time.gmtime(scan.at))
        archive = hub.release(f"raw-{day}", f"Full auction house scans of {day} (UTC), unchanged, one file per scan.")
        hub.upload(archive, name, packed)  # the uploaded file itself, unchanged
        added = add_summary(shared, scan)
        hub.delete(asset)
        done += 1
        print(f"archived {name} in raw-{day}; summary {'added' if added else 'already present'}")
    write_index(shared)
    print(f"done: {done} archived, {refused} refused")


if __name__ == "__main__":
    main()
