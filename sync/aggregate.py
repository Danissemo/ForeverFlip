"""Community data aggregator, run by GitHub Actions in the data repository.

Anyone with a GitHub account can contribute scans. The ForeverFlip Sync helper checks a scan, puts it
into a secret gist of the uploader and opens an issue "Scan upload: ..." that points to the gist. For
every such issue this script:

1. reads the gist, which must belong to the author of the issue, and compares its bytes with the
   SHA-256 written in the issue;
2. checks the scan again (`ffscan.check`): format, age, plausible values and the seal, the checksum
   the addon computed while it read the scan, so a scan changed afterwards is refused;
3. applies the uploader limits (banned uploaders, new GitHub accounts, too many uploads);
4. archives the file unchanged in the release `raw-YYYY-MM-DD` of its day (UTC);
5. records it in `registry/scans.jsonl`, comments on the issue and closes it.

A scan is published (its summary added to `shared/<realm>-<faction>.txt`) once it is confirmed:

* scans of trusted uploaders (`registry/uploaders.json`) at once;
* other scans when a scan of another uploader of the same auction house, taken within 3 hours,
  shares at least half of its auctions. Only the items whose prices agree with that scan are
  published, so a lot added or changed by hand never reaches the summaries.

A scan that finds no such scan within 24 hours stays in the archive, marked unconfirmed.

Before a confirmed scan is published, its prices are compared with the community's history (the
published summaries of the last 3 days): an item more than twice or less than half its usual price
there is left out, and a scan with more than a quarter of its compared items out of line is not
published at all ("disputed").

Usage (in the workflow): python aggregate.py --data <data repository checkout>
Environment: GITHUB_TOKEN, GITHUB_REPOSITORY.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import calendar
import gzip
import hashlib
import json
import os
import pathlib
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zlib
from collections import Counter

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import ffscan  # noqa: E402
from ffscan import scope_file  # noqa: E402

API = "https://api.github.com"
GIST_RAW = "https://gist.githubusercontent.com/"
TITLE = "Scan upload:"
KEEP = 12  # summaries kept per auction house
MAX_BYTES = 40 * 1024 * 1024  # base64 text of one upload
PEER_WINDOW = 3 * 3600  # a confirming scan is at most this far apart
MIN_OVERLAP = 0.5  # share of auctions a confirming scan must have in common
PRICE_AGREES = 0.25  # usual prices within 25% agree
WAIT = 24 * 3600  # how long a scan waits for a confirming scan
MIN_ACCOUNT_AGE = 7 * 86400
MAX_PER_DAY = 48  # uploads per uploader in 24 hours
MIN_GAP = 10 * 60  # between two uploads of one uploader for the same auction house
HISTORY_DAYS = 3  # summaries the prices of a new scan are compared with
HISTORY_RATIO = 2.0  # a usual price more than twice or less than half the community's is out of line
HISTORY_MIN_ITEMS = 20  # items in common needed to judge a whole scan
HISTORY_MAX_OFF = 0.25  # share of out-of-line items that disputes a whole scan



class Hub:
    def __init__(self, repo: str, token: str):
        self.repo, self.token = repo, token

    def call(self, method, url, data=None, content_type=None, accept="application/vnd.github+json", auth=True):
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Accept", accept)
        if auth:
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

    def json(self, method, path, value=None):
        data = json.dumps(value).encode() if value is not None else None
        return self.call(method, f"{API}{path}", data, "application/json" if data else None)

    # Releases
    def release(self, tag, create_body=None):
        try:
            return self.json("GET", f"/repos/{self.repo}/releases/tags/{urllib.parse.quote(tag)}")
        except urllib.error.HTTPError as exc:
            if exc.code != 404 or create_body is None:
                raise
        return self.json("POST", f"/repos/{self.repo}/releases",
                         {"tag_name": tag, "name": tag, "body": create_body, "prerelease": True})

    def assets(self, release):
        out, page = [], 1
        while True:
            batch = self.json("GET", f"/repos/{self.repo}/releases/{release['id']}/assets?per_page=100&page={page}")
            out += batch
            if len(batch) < 100:
                return out
            page += 1

    def upload(self, release, name, data):
        url = release["upload_url"].split("{")[0] + "?name=" + urllib.parse.quote(name)
        try:
            self.call("POST", url, data, "application/gzip")
        except urllib.error.HTTPError as exc:
            if exc.code != 422:  # already archived
                raise

    def download_archived(self, tag, name) -> bytes:
        for asset in self.assets(self.release(tag)):
            if asset["name"] == name:
                return self.call("GET", asset["url"], accept="application/octet-stream")
        raise FileNotFoundError(f"{tag}/{name}")

    # Issues, gists, users
    def scan_issues(self):
        issues = self.json("GET", f"/repos/{self.repo}/issues?state=open&per_page=100&sort=created&direction=asc")
        return [i for i in issues if "pull_request" not in i and i["title"].startswith(TITLE)]

    def comment(self, number, text):
        self.json("POST", f"/repos/{self.repo}/issues/{number}/comments", {"body": text})

    def close(self, number, completed):
        self.json("PATCH", f"/repos/{self.repo}/issues/{number}",
                  {"state": "closed", "state_reason": "completed" if completed else "not_planned"})

    # The workflow's token has no access to gists; secret gists are read without one.
    def gist(self, gist_id):
        return self.call("GET", f"{API}/gists/{gist_id}", auth=False)

    def raw(self, url) -> bytes:
        if not url.startswith(GIST_RAW):
            raise ValueError("unexpected gist address")
        return self.call("GET", url, accept="text/plain", auth=False)

    def account_created(self, login) -> float:
        user = self.json("GET", f"/users/{urllib.parse.quote(login)}")
        return calendar.timegm(time.strptime(user["created_at"], "%Y-%m-%dT%H:%M:%SZ"))


# --- Registry ------------------------------------------------------------------------------------

def load_registry(data: pathlib.Path) -> list[dict]:
    path = data / "registry" / "scans.jsonl"
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def save_registry(data: pathlib.Path, entries: list[dict]) -> None:
    folder = data / "registry"
    folder.mkdir(parents=True, exist_ok=True)
    text = "".join(json.dumps(e, sort_keys=True) + "\n" for e in sorted(entries, key=lambda e: (e["at"], e["name"])))
    (folder / "scans.jsonl").write_text(text, encoding="utf-8")


def load_uploaders(data: pathlib.Path) -> dict:
    path = data / "registry" / "uploaders.json"
    value = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    return {"trusted": [u.lower() for u in value.get("trusted", [])],
            "banned": [u.lower() for u in value.get("banned", [])]}


# --- Uploads -------------------------------------------------------------------------------------

def parse_issue(body: str) -> dict:
    fields = dict(re.findall(r"^(scope|time|auctions|seal|sha256|gist|helper): *(.+?) *$", body or "", re.M))
    if not re.fullmatch(r"[0-9a-f]{20,40}", fields.get("gist", "")):
        raise ValueError("the issue does not name a gist")
    if not re.fullmatch(r"[0-9a-f]{64}", fields.get("sha256", "")):
        raise ValueError("the issue does not give the SHA-256 of the scan")
    return fields


def read_gist(hub: Hub, gist_id: str, author: str) -> bytes:
    """The uploaded file: the gist's parts (scan.001.b64, scan.002.b64, ...) joined and decoded."""
    try:
        gist = hub.gist(gist_id)
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            raise ValueError("the gist was not found") from exc
        raise
    owner = (gist.get("owner") or {}).get("login", "")
    if owner.lower() != author.lower():
        raise ValueError("the gist does not belong to the author of the issue")
    files = gist.get("files") or {}
    names = sorted(n for n in files if re.fullmatch(r"scan\.\d{3}\.b64", n))
    if not names or sum(files[n].get("size", 0) for n in names) > MAX_BYTES:
        raise ValueError("the gist has no scan or is too large")
    text = []
    for name in names:
        f = files[name]
        content = f.get("content")
        if f.get("truncated") or content is None:
            content = hub.raw(f["raw_url"]).decode("ascii")
        text.append(content.strip())
    try:
        return base64.b64decode("".join(text), validate=True)
    except (binascii.Error, ValueError) as exc:
        raise ValueError("the gist is not valid base64") from exc


def safe(text: str) -> str:
    return re.sub(r"[^A-Za-z0-9-]", "-", text) or "x"


def archive_name(scan: ffscan.RawScan, uploader: str) -> str:
    return f"{safe(scan.realm)}_{safe(scan.faction)}_{scan.at}_{safe(uploader)}.ffr.gz"


def limits(entries: list[dict], uploader: str, scan: ffscan.RawScan, digest: str, now: float) -> str | None:
    mine = [e for e in entries if e["uploader"].lower() == uploader.lower()]
    if any(e["sha256"] == digest for e in entries):
        return "this scan was uploaded already"
    if sum(1 for e in mine if now - e["received"] < 86400) >= MAX_PER_DAY:
        return f"more than {MAX_PER_DAY} uploads in 24 hours"
    if any(e["scope"] == scan.scope and abs(e["at"] - scan.at) < MIN_GAP for e in mine):
        return "another scan of this auction house was uploaded less than 10 minutes apart"
    return None


def accept_upload(hub: Hub, issue: dict, entries: list[dict], uploaders: dict, now: float) -> tuple[dict, ffscan.RawScan]:
    """Checks one upload issue and archives the scan; raises ValueError with the reason to refuse."""
    author = issue["user"]["login"]
    if author.lower() in uploaders["banned"]:
        raise ValueError("uploads of this account are not accepted")
    trusted = author.lower() in uploaders["trusted"]
    if not trusted and now - hub.account_created(author) < MIN_ACCOUNT_AGE:
        raise ValueError("GitHub accounts younger than 7 days cannot upload yet")
    fields = parse_issue(issue.get("body") or "")
    packed = read_gist(hub, fields["gist"], author)
    digest = hashlib.sha256(packed).hexdigest()
    if digest != fields["sha256"]:
        raise ValueError("the gist does not match the SHA-256 in the issue (it was changed)")
    try:
        scan = ffscan.decode_raw(gzip.decompress(packed).decode("utf-8"))
    except (OSError, EOFError, UnicodeDecodeError, zlib.error) as exc:
        raise ValueError("the file is not a gzip-compressed scan") from exc
    why = ffscan.check(scan, now) or limits(entries, author, scan, digest, now)
    if why:
        raise ValueError(why)
    entry = archive_scan(hub, scan, packed, digest, author, now, "trusted" if trusted else "pending")
    entry["issue"] = issue["number"]
    return entry, scan


def archive_scan(hub, scan: ffscan.RawScan, packed: bytes, digest: str, uploader: str, now: float,
                 status: str) -> dict:
    day = time.strftime("%Y-%m-%d", time.gmtime(scan.at))
    tag = f"raw-{day}"
    name = archive_name(scan, uploader)
    archive = hub.release(tag, f"Full auction house scans of {day} (UTC), unchanged, one file per scan.")
    hub.upload(archive, name, packed)
    return {
        "name": name, "archive": tag, "scope": scan.scope, "at": scan.at, "uploader": uploader,
        "auctions": len(scan.rows), "seal": scan.seal, "sha256": digest, "addon": scan.addon,
        "issue": None, "received": int(now), "status": status, "peers": [], "compared": [], "items": 0,
    }



# --- Confirmation ---------------------------------------------------------------------------------

def lots(scan: ffscan.RawScan) -> Counter:
    return Counter((r.item, r.count, r.buyout, r.name) for r in scan.rows if r is not None and r.buyout > 0)


def overlap(a: Counter, b: Counter) -> float:
    smaller = min(sum(a.values()), sum(b.values()))
    return sum((a & b).values()) / smaller if smaller else 0.0


def agreeing_items(scan: ffscan.RawScan, peer: ffscan.RawScan) -> set[str]:
    """Items of `scan` the peer scan backs: their usual prices agree, or the cheap lots that set the
    usual price are listed in the peer scan too."""
    mine, theirs = ffscan.summarize(scan), ffscan.summarize(peer)
    peer_lots = lots(peer)
    by_key: dict[str, list] = {}
    for r in scan.rows:
        if r is not None and not r.own and r.buyout > 0 and r.count > 0 and r.key():
            by_key.setdefault(r.key(), []).append(r)
    agree = set()
    for key, (usual, _, _) in mine.items():
        other = theirs.get(key)
        if other and abs(usual - other[0]) <= PRICE_AGREES * other[0]:
            agree.add(key)
            continue
        cheap = [r for r in by_key.get(key, []) if r.buyout / r.count <= usual * 1.02]
        units = sum(r.count for r in cheap)
        seen = Counter()
        backed = 0
        for r in cheap:
            lot = (r.item, r.count, r.buyout, r.name)
            seen[lot] += 1
            if seen[lot] <= peer_lots[lot]:
                backed += r.count
        if units and backed >= units / 2:
            agree.add(key)
    return agree


def read_summaries(path: pathlib.Path) -> list[tuple[int, dict]]:
    """The published summaries of an auction house: [(time, {key: (usual, cheapest, units)})]."""
    out = []
    if not path.exists():
        return out
    unesc = lambda t: re.sub(r"%([0-9A-Fa-f]{2})", lambda m: chr(int(m.group(1), 16)), t)
    for line in path.read_text(encoding="utf-8").splitlines():
        parts = line.split("|", 3)
        if len(parts) != 4 or not parts[0].startswith("FF"):
            continue
        items = {}
        for record in parts[3].split(";"):
            fields = record.split(",")
            if len(fields) == 4:
                try:
                    items[unesc(fields[0])] = tuple(int(f, 36) for f in fields[1:])
                except ValueError:
                    continue
        out.append((int(parts[2], 36), items))
    return out


def community_history(shared: pathlib.Path, scope: str, at: int) -> dict[str, float]:
    """Median usual price of each item in the summaries of the 3 days before `at` (not the same scan)."""
    prices: dict[str, list[int]] = {}
    for when, items in read_summaries(shared / scope_file(scope)):
        if at - HISTORY_DAYS * 86400 <= when <= at + PEER_WINDOW and abs(when - at) >= 120:
            for key, (usual, _, _) in items.items():
                if usual > 0:
                    prices.setdefault(key, []).append(usual)
    out = {}
    for key, values in prices.items():
        values.sort()
        n = len(values)
        out[key] = values[n // 2] if n % 2 else (values[n // 2 - 1] + values[n // 2]) / 2
    return out


def out_of_line(items: dict, history: dict[str, float]) -> tuple[int, set[str]]:
    """Items compared with the history and those whose usual price is more than HISTORY_RATIO off."""
    compared, off = 0, set()
    for key, (usual, _, _) in items.items():
        past = history.get(key)
        if past:
            compared += 1
            if usual > past * HISTORY_RATIO or usual * HISTORY_RATIO < past:
                off.add(key)
    return compared, off


def add_summary(shared: pathlib.Path, scope: str, at: int, items: dict) -> bool:
    """Adds a scan's summary to its auction house file; False for a scan already there."""
    path = shared / scope_file(scope)
    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    entries = []
    for line in lines:
        m = re.match(r"^FF1\|[^|]+\|(\w+)\|", line)
        if m:
            entries.append((int(m.group(1), 36), line))
    if any(abs(t - at) < 120 for t, _ in entries):
        return False  # the same server scan, read by another player
    entries.append((at, ffscan.encode_summary(scope, at, items)))
    entries.sort(key=lambda e: e[0], reverse=True)
    path.write_text("\n".join(text for _, text in entries[:KEEP]) + "\n", encoding="utf-8")
    return True


def publish(shared: pathlib.Path, entry: dict, scan: ffscan.RawScan, keys: set[str] | None) -> None:
    items = ffscan.summarize(scan)
    if keys is not None:
        items = {k: v for k, v in items.items() if k in keys}
    entry["items"] = len(items)
    if items:
        add_summary(shared, scan.scope, scan.at, items)


def confirm_pending(entries: list[dict], load, shared: pathlib.Path, now: float) -> list[str]:
    """Compares waiting scans with the new scans of other uploaders. `load(entry)` returns a scan."""
    report = []
    for entry in entries:
        if entry["status"] != "pending":
            continue
        peers = [e for e in entries
                 if e is not entry and e["scope"] == entry["scope"] and e["status"] != "refused"
                 and e["uploader"].lower() != entry["uploader"].lower()
                 and abs(e["at"] - entry["at"]) <= PEER_WINDOW and e["name"] not in entry["compared"]]
        keys: set[str] = set()
        scan = None
        for peer in peers:
            entry["compared"].append(peer["name"])
            scan = scan or load(entry)
            other = load(peer)
            if overlap(lots(scan), lots(other)) >= MIN_OVERLAP:
                entry["peers"].append(peer["name"])
                keys |= agreeing_items(scan, other)
        if entry["peers"]:
            history = community_history(shared, entry["scope"], entry["at"])
            compared, off = out_of_line(ffscan.summarize(scan), history)
            entry["history"] = {"compared": compared, "off": len(off)}
            if compared >= HISTORY_MIN_ITEMS and len(off) > HISTORY_MAX_OFF * compared:
                entry["status"] = "disputed"
                report.append(f"disputed {entry['name']}: {len(off)} of {compared} prices far from the community's")
                continue
            keys -= off
            entry["status"] = "confirmed"
            publish(shared, entry, scan, keys)
            report.append(f"confirmed {entry['name']} by {', '.join(entry['peers'])}: {entry['items']} items")
        elif now - entry["received"] > WAIT:
            entry["status"] = "unconfirmed"
            report.append(f"unconfirmed {entry['name']}")
    return report


def write_index(shared: pathlib.Path) -> None:
    index = {}
    for path in sorted(shared.glob("*.txt")):
        lines = [line for line in path.read_text(encoding="utf-8").splitlines() if line.startswith("FF1|")]
        if lines:
            scope = re.sub(r"%([0-9A-Fa-f]{2})", lambda m: chr(int(m.group(1), 16)), lines[0].split("|")[1])
            latest = max(int(line.split("|")[2], 36) for line in lines)
            index[scope] = {"file": path.name, "scans": len(lines), "latest": latest}
    (shared / "index.json").write_text(json.dumps(index, indent=2, sort_keys=True) + "\n", encoding="utf-8")


STATUS_TEXT = {
    "trusted": "It is published in the community prices now.",
    "pending": "It is published as soon as a scan of another player, taken within 3 hours, confirms it "
               "(within 24 hours).",
}


def process(hub, data: pathlib.Path, now: float, defer_completion: bool = False) -> list[str]:
    """Handles the open upload issues and the waiting scans; returns a report."""
    shared = data / "shared"
    shared.mkdir(parents=True, exist_ok=True)
    entries, uploaders = load_registry(data), load_uploaders(data)
    loaded: dict[str, ffscan.RawScan] = {}
    report = []
    accepted = []
    registered = {entry["issue"]: entry for entry in entries if entry.get("issue") is not None}

    def load(entry):
        if entry["name"] not in loaded:
            packed = hub.download_archived(entry["archive"], entry["name"])
            loaded[entry["name"]] = ffscan.decode_raw(gzip.decompress(packed).decode("utf-8"))
        return loaded[entry["name"]]

    for issue in hub.scan_issues():
        number = issue["number"]
        if number in registered:
            # A previous run saved this scan but failed while acknowledging its issue.
            accepted.append(registered[number])
            continue
        try:
            entry, scan = accept_upload(hub, issue, entries, uploaders, now)
        except (ValueError, urllib.error.URLError) as exc:
            if not isinstance(exc, ValueError):
                opened = calendar.timegm(time.strptime(issue["created_at"], "%Y-%m-%dT%H:%M:%SZ"))
                if now - opened < WAIT:  # a network or rate-limit failure: try again at the next run
                    report.append(f"#{number} postponed: {exc}")
                    continue
            reason = str(exc) if isinstance(exc, ValueError) else "GitHub could not be read for 24 hours"
            report.append(f"refused #{number}: {reason}")
            hub.comment(number, f"❌ The scan was refused: {reason}.")
            hub.close(number, completed=False)
            continue
        entries.append(entry)
        loaded[entry["name"]] = scan
        if entry["status"] == "trusted":
            publish(shared, entry, scan, None)
        report.append(f"archived #{number} as {entry['archive']}/{entry['name']} ({entry['status']})")
        accepted.append(entry)

    report += confirm_pending(entries, load, shared, now)
    save_registry(data, entries)
    write_index(shared)
    # Workflows defer completion until the generated files have been pushed.
    if not defer_completion:
        report += acknowledge_entries(hub, accepted)
    report.append(f"done: {len(entries)} scans in the registry")
    return report


def acknowledge_entries(hub, entries: list[dict]) -> list[str]:
    """Acknowledge registered scans; failed notifications remain retryable."""
    report = []
    for entry in entries:
        number = entry["issue"]
        status = STATUS_TEXT.get(entry["status"], f"Current status: {entry['status']}.")
        try:
            hub.comment(number, f"✅ Archived unchanged as `{entry['name']}` in "
                                f"[{entry['archive']}](https://github.com/{hub.repo}/releases/tag/{entry['archive']}): "
                                f"{entry['auctions']} auctions. {status}")
            hub.close(number, completed=True)
        except (urllib.error.URLError, OSError) as exc:
            report.append(f"#{number} completion pending: {exc}")
    return report


def complete_registered(hub, data: pathlib.Path) -> list[str]:
    """Complete only open issues already present in the persisted registry."""
    registered = {entry["issue"]: entry for entry in load_registry(data) if entry.get("issue") is not None}
    entries = [registered[issue["number"]] for issue in hub.scan_issues() if issue["number"] in registered]
    return acknowledge_entries(hub, entries)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", required=True, help="checkout of the data repository")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--defer-completion", action="store_true",
                      help="keep accepted issues open until registry and summaries are committed and pushed")
    mode.add_argument("--complete-only", action="store_true",
                      help="acknowledge registered open issues without processing uploads or changing data")
    args = parser.parse_args()
    hub = Hub(os.environ["GITHUB_REPOSITORY"], os.environ["GITHUB_TOKEN"])
    data = pathlib.Path(args.data)
    report = (complete_registered(hub, data) if args.complete_only
              else process(hub, data, time.time(), defer_completion=args.defer_completion))
    for line in report:
        print(line)


if __name__ == "__main__":
    main()
