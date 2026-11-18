"""Release posts and public numbers for promoting ForeverFlip, without any telemetry in the addon.

    python tools/promo.py post --version 3.2.0 --channel reddit     # a post drafted from CHANGELOG.md
    python tools/promo.py metrics                                   # downloads and sharing players

`post` takes the bold headlines of the version's Added and Fixed sections and wraps them for a
channel (reddit, discord, telegram); it prints a draft to read and edit before posting by hand.
`metrics` reads only public data: the download counts of the GitHub releases and, per auction
house, how many players' scans the community prices rest on (status.json of the data repository).
"""

import argparse
import json
import pathlib
import re
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from release_notes import render  # noqa: E402

REPO = "Danissemo/ForeverFlip"
DATA_REPO = "Danissemo/ForeverFlip-Data"
CHANNELS = ("reddit", "discord", "telegram")


def headlines(notes: str) -> dict:
    """{section: [headline]} from the bold lead of each '- **...**' item of Added and Fixed."""
    found, section = {}, None
    for line in notes.splitlines():
        heading = re.match(r"^### (\w+)", line)
        if heading:
            section = heading.group(1)
        elif section in ("Added", "Fixed"):
            item = re.match(r"^- \*\*(.+?)\*\*", line)
            if item:
                found.setdefault(section, []).append(item.group(1).rstrip("."))
    return found


def post(changelog: str, version: str, channel: str, repository: str = REPO) -> str:
    news = headlines(render(changelog, version, repository))
    release = f"https://github.com/{repository}/releases/tag/v{version}"
    added, fixed = news.get("Added", []), news.get("Fixed", [])
    if channel == "reddit":
        lines = [f"# ForeverFlip {version}: a free auction-house flipping addon for WoW Forever", "",
                 "ForeverFlip scans the auction house and shows, before you buy, what a flip should earn "
                 "after the cut (Profit), how many sell a day (Est./day) and how likely it sells at that "
                 "price (Sure). Free, standalone, no TSM needed.", ""]
        if added:
            lines += ["**New in this version**", ""] + [f"- {h}" for h in added] + [""]
        if fixed:
            more = f" and {len(fixed) - 6} more" if len(fixed) > 6 else ""
            lines += [f"**Fixed** ({len(fixed)})", ""] + [f"- {h}" for h in fixed[:6]] + ([f"- …{more}", ""] if more else [""])
        lines += [f"Download and full notes: {release}", "",
                  "Feedback and numbers from your server are welcome in the comments or on GitHub Discussions."]
    elif channel == "discord":
        lines = [f"**ForeverFlip {version} is out**"] + [f"• {h}" for h in added[:4]]
        if fixed:
            lines.append(f"…and {len(fixed)} fix{'' if len(fixed) == 1 else 'es'}.")
        lines += [release, "Share your scans with ForeverFlip Sync: every player makes the community prices better."]
    elif channel == "telegram":
        lines = [f"🔄 ForeverFlip {version} — безкоштовний аддон для перепродажу на аукціоні WoW Forever", "",
                 "Ще до покупки показує прибуток після комісії, скільки продається за день і наскільки "
                 "ймовірно продасться за цією ціною. Працює сам, без TSM.", ""]
        if added:
            lines += ["Нове:"] + [f"• {h}" for h in added] + [""]
        if fixed:
            lines += [f"Виправлень: {len(fixed)}.", ""]
        lines += [f"Завантажити: {release}", "Аддон перекладено українською."]
    else:
        raise ValueError(f"unknown channel {channel}; one of {', '.join(CHANNELS)}")
    return "\n".join(lines) + "\n"


def downloads(releases: list) -> list:
    """[(tag, downloads)] of the published releases, newest first, counting every asset."""
    return [(r["tag_name"], sum(a.get("download_count", 0) for a in r.get("assets", [])))
            for r in releases if not r.get("draft")]


def houses(status: dict) -> list:
    """[(auction house, players sharing, published scans)] from a data repository status.json."""
    rows = []
    for scope, info in sorted((status.get("markets") or {}).items()):
        rows.append((scope, info.get("uploaders") or 0, info.get("published") or 0))
    return rows


def fetch_json(url: str):
    request = urllib.request.Request(url, headers={"User-Agent": "ForeverFlip-promo",
                                                   "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def metrics() -> str:
    lines = []
    rows = downloads(fetch_json(f"https://api.github.com/repos/{REPO}/releases?per_page=100"))
    lines.append(f"Downloads: {sum(n for _, n in rows)} in all")
    lines += [f"  {tag:<16} {n}" for tag, n in rows]
    try:
        status = fetch_json(f"https://raw.githubusercontent.com/{DATA_REPO}/main/shared/status.json")
    except OSError as error:
        lines.append(f"Community status: not read ({error})")
    else:
        lines.append("Players sharing scans, per auction house:")
        lines += [f"  {scope:<32} {sharers} players, {scans} published scans" for scope, sharers, scans in houses(status)] or ["  none yet"]
    return "\n".join(lines) + "\n"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    draft = commands.add_parser("post", help="draft a release post from CHANGELOG.md")
    draft.add_argument("--version", required=True)
    draft.add_argument("--channel", choices=CHANNELS, default="reddit")
    draft.add_argument("--changelog", type=pathlib.Path, default=ROOT / "CHANGELOG.md")
    commands.add_parser("metrics", help="public download and sharing numbers")
    args = parser.parse_args(argv)
    if args.command == "post":
        text = post(args.changelog.read_text(encoding="utf-8"), args.version, args.channel)
    else:
        text = metrics()
    sys.stdout.buffer.write(text.encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
