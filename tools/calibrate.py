"""Development only: compare ForeverFlip's sales and price estimates with TradeSkillMaster's data.

TSM's desktop app downloads region data for WoW Forever into
Interface/AddOns/TradeSkillMaster_AppHelper/AppData.lua: units sold per day, sale rate and the
average sale price over weeks, for the whole region. ForeverFlip itself never reads TSM in game
(players do not need any other addon); this tool reads both files on the developer's machine and
reports where ForeverFlip's own estimates disagree, to tune the formulas' parameters.

    python tools/calibrate.py [--save FILE] [--tsm FILE] [--scope SCOPE] [--region NAME]
                              [--top N] [--csv FILE]

Defaults: the first saved file under the game's WTF (FF_GAME / ff.game, as devflow.py) and the game's
TSM AppHelper data. Both files are only read. Run it with the game closed or on a copy: the game
rewrites the saved file at logout.
"""

from __future__ import annotations

import argparse
import csv
import math
import pathlib
import re
import statistics
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import devflow  # noqa: E402

ADDON = devflow.ROOT / "ForeverFlip"
MOCK = devflow.ROOT / "tests" / "mock.lua"
BLOCK = re.compile(
    r'LoadData\("([A-Z_]+)","([^"]+)",\[\[return \{downloadTime=(\d+),fields=\{([^}]*)\},data=\{(.*?)\}\}\]\]',
    re.S,
)
# TSM keeps sale rate and sold per day multiplied by 1000 (its tooltip divides them back).
THOUSANDTHS = {"regionSalePercent", "regionSoldPerDay"}


def tsm_number(text: str) -> int:
    """A TSM base-32 number (values over 6 digits are split in two 30-bit halves, as TSM does)."""
    if len(text) > 6:
        return int(text[-6:], 32) + int(text[:-6], 32) * 2**30
    return int(text, 32)


def read_tsm(path: pathlib.Path) -> dict:
    """{(set, realm): {"at": downloadTime, "items": {itemID: {field: value}}}} for plain item IDs."""
    out = {}
    for name, realm, at, fields, data in BLOCK.findall(path.read_text(encoding="utf-8", errors="replace")):
        names = [f.strip().strip('"') for f in fields.split(",")]
        items = {}
        for row in re.findall(r"\{([^{}]*)\}", data):
            cells = row.split(",")
            if len(cells) != len(names) or not cells[0].isdigit():
                continue  # item strings with bonus IDs, quoted: not plain items
            values = {}
            for field, cell in zip(names[1:], cells[1:]):
                value = tsm_number(cell)
                values[field] = value / 1000 if field in THOUSANDTHS else value
            items[int(cells[0])] = values
        out[(name, realm)] = {"at": int(at), "items": items}
    return out


def toc_files() -> list[pathlib.Path]:
    toc = (ADDON / "ForeverFlip.toc").read_text(encoding="utf-8")
    return [ADDON / line.strip().replace("\\", "/") for line in toc.splitlines()
            if line.strip().endswith(".lua") and not line.startswith("#")]


def load_addon(save: pathlib.Path):
    """The addon's own code over the saved data, in the test client (no ADDON_LOADED: nothing is
    migrated or trimmed, the saved tables are read as they are)."""
    import lupa.lua51 as lupa

    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK.read_text(encoding="utf-8"))
    lua.execute(save.read_text(encoding="utf-8", errors="replace"))
    for path in toc_files():
        lua.execute(path.read_text(encoding="utf-8"))
    return lua


def ff_estimates(lua, scope: str | None) -> tuple[str, list[dict]]:
    """Per plain item of one house: usual price and units sold per day at that price."""
    data = lua.globals().ForeverFlipData
    markets = data and data.markets
    if not markets:
        raise SystemExit("no markets in the saved data")
    scopes = {str(k): markets[k] for k in markets.keys()}
    if scope is None:
        scope = max(scopes, key=lambda s: len(list((scopes[s].history or {}).keys())) if scopes[s].history else 0)
    if scope not in scopes:
        raise SystemExit("no house %r; houses: %s" % (scope, ", ".join(sorted(scopes))))
    history = scopes[scope].history
    M = lua.globals().ForeverFlip.Market
    rows = []
    for key in history.keys():
        key = str(key)
        if not (key.startswith("c:") or key.startswith("i:")):
            continue  # gear versions have no one TSM price
        h = history[key]
        usual = M.usual(h)
        usual = usual[0] if isinstance(usual, tuple) else usual  # price, time, sharer
        if not usual:
            continue
        at = h.scan and h.scan.at or 0
        sale = M.saleability(h, usual, at)
        rows.append({
            "key": key,
            "id": int(key.split(":")[1]),
            "usual": float(usual),
            "perDay": float(sale.perDay) if sale.known and sale.perDay is not None else None,
            "pairs": float(sale.pairs or 0),
        })
    return scope, rows


def ratio_line(label: str, ratios: list[float]) -> str:
    if not ratios:
        return "%s: no items with both values" % label
    logs = sorted(math.log(r) for r in ratios)

    def q(p):
        return math.exp(logs[min(len(logs) - 1, int(p * len(logs)))])
    return "%s: %d items, median x%.2f, middle half x%.2f..x%.2f" % (
        label, len(ratios), math.exp(statistics.median(logs)), q(0.25), q(0.75))


def spearman(xs: list[float], ys: list[float]) -> float | None:
    if len(xs) < 3:
        return None

    def ranks(v):
        order = sorted(range(len(v)), key=v.__getitem__)
        r = [0.0] * len(v)
        for i, j in enumerate(order):
            r[j] = i
        return r
    rx, ry = ranks(xs), ranks(ys)
    mx, my = statistics.mean(rx), statistics.mean(ry)
    num = sum((a - mx) * (b - my) for a, b in zip(rx, ry))
    den = math.sqrt(sum((a - mx) ** 2 for a in rx) * sum((b - my) ** 2 for b in ry))
    return num / den if den else None


def compare(rows: list[dict], tsm: dict, region: str) -> dict:
    sale = tsm.get(("AUCTIONDB_REGION_SALE", region), {}).get("items", {})
    stat = tsm.get(("AUCTIONDB_REGION_STAT", region), {}).get("items", {})
    joined = []
    for r in rows:
        s, m = sale.get(r["id"]), stat.get(r["id"])
        if not s and not m:
            continue
        joined.append(dict(r,
                           tsmPerDay=s and s.get("regionSoldPerDay") or 0.0,
                           tsmRate=s and s.get("regionSalePercent") or 0.0,
                           tsmSale=s and s.get("regionSale") or 0,
                           tsmMarket=m and m.get("regionMarketValue") or 0))
    both = [j for j in joined if j["perDay"] and j["tsmPerDay"]]
    return {
        "items": len(rows),
        "joined": joined,
        "perDay": [j["perDay"] / j["tsmPerDay"] for j in both],
        "perDayRank": spearman([j["perDay"] for j in both], [j["tsmPerDay"] for j in both]),
        "sale": [j["usual"] / j["tsmSale"] for j in joined if j["tsmSale"]],
        "market": [j["usual"] / j["tsmMarket"] for j in joined if j["tsmMarket"]],
        "cold": [j for j in joined if not j["perDay"] and j["tsmPerDay"] >= 1],
        "unseen": [j for j in joined if j["perDay"] and j["perDay"] >= 1 and not j["tsmPerDay"]],
    }


def report(scope: str, region: str, result: dict, top: int) -> None:
    print("house %s against TSM %s: %d items with a usual price, %d also in TSM"
          % (scope, region, result["items"], len(result["joined"])))
    print(ratio_line("sold per day, ForeverFlip / region", result["perDay"]))
    rank = result["perDayRank"]
    print("  same order of items (Spearman): %s" % ("%.2f" % rank if rank is not None else "n/a"))
    print(ratio_line("usual price / region sale price", result["sale"]))
    print(ratio_line("usual price / region market value", result["market"]))
    print("no ForeverFlip sales yet, region sells 1+/day: %d items" % len(result["cold"]))
    print("ForeverFlip sees 1+/day, region none: %d items" % len(result["unseen"]))
    far = sorted((j for j in result["joined"] if j["tsmSale"]),
                 key=lambda j: -abs(math.log(j["usual"] / j["tsmSale"])))[:top]
    if far:
        print("largest price disagreements (key, usual, region sale price, ratio):")
        for j in far:
            print("  %-12s %10d %10d  x%.2f" % (j["key"], j["usual"], j["tsmSale"], j["usual"] / j["tsmSale"]))


def write_csv(path: pathlib.Path, joined: list[dict]) -> None:
    fields = ["key", "usual", "perDay", "pairs", "tsmSale", "tsmMarket", "tsmPerDay", "tsmRate"]
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        w.writerows(joined)


def default_save() -> pathlib.Path | None:
    game = devflow.game_folder()
    if not game:
        return None
    found = sorted((game / "WTF" / "Account").glob("*/SavedVariables/ForeverFlip.lua"))
    return found[0] if found else None


def default_tsm() -> pathlib.Path | None:
    game = devflow.game_folder()
    path = game and game / "Interface" / "AddOns" / "TradeSkillMaster_AppHelper" / "AppData.lua"
    return path if path and path.is_file() else None


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--save", type=pathlib.Path)
    p.add_argument("--tsm", type=pathlib.Path)
    p.add_argument("--scope", help="auction house, e.g. Realm-Alliance (default: the one with most items)")
    p.add_argument("--region", default="Forever-EU")
    p.add_argument("--top", type=int, default=15)
    p.add_argument("--csv", type=pathlib.Path)
    a = p.parse_args(argv)
    save, tsm_path = a.save or default_save(), a.tsm or default_tsm()
    if not save or not save.is_file():
        print("no ForeverFlip saved data found; pass --save")
        return 2
    if not tsm_path or not tsm_path.is_file():
        print("no TSM AppHelper data found; pass --tsm")
        return 2
    tsm = read_tsm(tsm_path)
    if not any(realm == a.region for _, realm in tsm):
        print("TSM data has no region %r; it has: %s" % (a.region, ", ".join(sorted({r for _, r in tsm}))))
        return 2
    scope, rows = ff_estimates(load_addon(save), a.scope)
    result = compare(rows, tsm, a.region)
    report(scope, a.region, result, a.top)
    if a.csv:
        write_csv(a.csv, result["joined"])
        print("rows written to", a.csv)
    return 0


if __name__ == "__main__":
    sys.exit(main())
