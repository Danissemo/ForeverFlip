"""Formats shared by the ForeverFlip Sync helper and the community data aggregator.

* SavedVariables: a reader for the Lua tables World of Warcraft writes (`lua_assignments`).
* Raw scans (FFR1): a full scan as the addon read it, one line per auction, in scan order.
* Summaries (FF1): per item the usual price, cheapest unit price and units listed, the same text the
  addon uses for sharing in game (`ForeverFlip/Share.lua`).

Only the Python standard library is used.
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass, field

RAW_FORMAT = "FFR1"
SUMMARY_VERSION = 1
SEAL_MOD = 2147483647
MAX_AGE = 7 * 86400
MIN_ROWS = 50
MAX_ROWS = 3_000_000
BUCKET = math.log(1.02)
DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"


# --- SavedVariables ----------------------------------------------------------------------------

class LuaError(ValueError):
    pass


class _Reader:
    """A reader for the subset of Lua that SavedVariables files use: tables, strings, numbers,
    booleans and nil, assigned to global names."""

    ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "a": "\a", "b": "\b",
               "f": "\f", "v": "\v", "\n": "\n"}

    def __init__(self, text: str):
        self.s, self.i = text, 0

    def skip(self):
        s, n = self.s, len(self.s)
        while self.i < n:
            c = s[self.i]
            if c in " \t\r\n,;":
                self.i += 1
            elif s.startswith("--", self.i):
                if s.startswith("--[[", self.i):
                    end = s.find("]]", self.i)
                    self.i = n if end < 0 else end + 2
                else:
                    end = s.find("\n", self.i)
                    self.i = n if end < 0 else end + 1
            else:
                break

    def value(self):
        self.skip()
        s = self.s
        if self.i >= len(s):
            raise LuaError("unexpected end")
        c = s[self.i]
        if c == "{":
            return self.table()
        if c in "\"'":
            return self.string()
        if c == "[" and re.match(r"\[=*\[", s[self.i:]):
            return self.long_string()
        m = re.compile(r"-?(0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+(?:[eE][-+]?\d+)?)").match(s, self.i)
        if m:
            self.i = m.end()
            text = m.group(0)
            if "x" in text.lower():
                return int(text, 16)
            number = float(text)
            return int(number) if number.is_integer() and "." not in text and "e" not in text.lower() else number
        for word, result in (("true", True), ("false", False), ("nil", None)):
            if s.startswith(word, self.i):
                self.i += len(word)
                return result
        raise LuaError(f"unexpected {c!r} at {self.i}")

    def string(self):
        s, quote = self.s, self.s[self.i]
        self.i += 1
        out = []
        while True:
            if self.i >= len(s):
                raise LuaError("unfinished string")
            c = s[self.i]
            if c == quote:
                self.i += 1
                return "".join(out)
            if c == "\\":
                nxt = s[self.i + 1]
                if nxt.isdigit():
                    m = re.match(r"\d{1,3}", s[self.i + 1:])
                    out.append(chr(int(m.group(0))))
                    self.i += 1 + len(m.group(0))
                    continue
                out.append(self.ESCAPES.get(nxt, nxt))
                self.i += 2
                continue
            out.append(c)
            self.i += 1

    def long_string(self):
        m = re.match(r"\[(=*)\[", self.s[self.i:])
        close = "]" + m.group(1) + "]"
        start = self.i + len(m.group(0))
        end = self.s.find(close, start)
        if end < 0:
            raise LuaError("unfinished long string")
        self.i = end + len(close)
        text = self.s[start:end]
        return text[1:] if text.startswith("\n") else text

    def table(self):
        self.i += 1
        result, n = {}, 1
        while True:
            self.skip()
            if self.s[self.i] == "}":
                self.i += 1
                break
            if self.s[self.i] == "[" and not re.match(r"\[=*\[", self.s[self.i:]):
                self.i += 1
                key = self.value()
                self.skip()
                if self.s[self.i] != "]":
                    raise LuaError("expected ]")
                self.i += 1
                self.skip()
                if self.s[self.i] != "=":
                    raise LuaError("expected =")
                self.i += 1
                result[key] = self.value()
                continue
            m = re.compile(r"([A-Za-z_]\w*)\s*=(?!=)").match(self.s, self.i)
            if m:
                self.i = m.end()
                result[m.group(1)] = self.value()
                continue
            result[n] = self.value()
            n += 1
        if result and all(isinstance(k, int) for k in result) and sorted(result) == list(range(1, len(result) + 1)):
            return [result[k] for k in range(1, len(result) + 1)]
        return result


def lua_assignments(text: str) -> dict:
    """Global assignments of a SavedVariables file: {name: value}."""
    reader, out = _Reader(text), {}
    while True:
        reader.skip()
        if reader.i >= len(text):
            return out
        m = re.compile(r"([A-Za-z_]\w*)\s*=").match(text, reader.i)
        if not m:
            raise LuaError(f"expected an assignment at {reader.i}")
        reader.i = m.end()
        out[m.group(1)] = reader.value()


# --- Raw scans ---------------------------------------------------------------------------------

@dataclass
class Auction:
    item: int
    count: int
    buyout: int
    min_bid: int | None
    bid: int | None
    band: int | None
    own: bool
    kind: str  # "c", "i", "g" or "" when unknown
    name: str

    def key(self) -> str | None:
        if self.kind == "c":
            return f"c:{self.item}"
        if self.kind == "i":
            return f"i:{self.item}"
        if self.kind == "g" and self.name:
            return f"g:{self.item}:{self.name.lower()}"
        return None


@dataclass
class RawScan:
    scope: str
    at: int
    realm: str
    faction: str
    addon: str
    rows: list = field(default_factory=list)  # Auction, in scan order (None for unreadable rows)
    seal: int | None = None  # the checksum the addon computed while reading the scan
    text: str | None = None  # the auction lines exactly as the addon wrote them


def _int(text: str) -> int | None:
    return int(text) if text not in ("", None) else None


def parse_rows(text: str) -> list:
    rows = []
    for line in text.split("\n"):
        parts = line.split(",", 8)
        if len(parts) < 7 or not parts[0]:
            rows.append(None)
            continue
        parts += [""] * (9 - len(parts))
        rows.append(Auction(
            item=int(parts[0]), count=_int(parts[1]) or 0, buyout=_int(parts[2]) or 0,
            min_bid=_int(parts[3]), bid=_int(parts[4]), band=_int(parts[5]), own=parts[6] == "1",
            kind=parts[7], name=parts[8],
        ))
    return rows


def scans_from_saved_variables(text: str) -> list[RawScan]:
    """Raw scans the addon kept in ForeverFlipRaw (newest first)."""
    data = lua_assignments(text).get("ForeverFlipRaw")
    if not isinstance(data, dict):
        return []
    scans = data.get("scans") or []
    if isinstance(scans, dict):
        scans = [scans[k] for k in sorted(scans)]
    out = []
    for s in scans:
        if isinstance(s, dict) and s.get("scope") and s.get("at") and isinstance(s.get("rows"), str):
            rows = parse_rows(s["rows"]) if s.get("count") else []
            seal = s.get("seal")
            out.append(RawScan(scope=s["scope"], at=int(s["at"]), realm=s.get("realm") or "",
                               faction=s.get("faction") or "", addon=str(s.get("addon") or ""),
                               rows=rows, seal=int(seal) if isinstance(seal, (int, float)) else None,
                               text=s["rows"]))
    return out


# --- Seal --------------------------------------------------------------------------------------

def _hash(data: bytes) -> int:
    h = 0
    for b in data:
        h = (h * 31 + b) % SEAL_MOD
    return h


def _chain(seal: int, text: str) -> int:
    return (seal * 1000003 + _hash(text.encode("utf-8")) + 1) % SEAL_MOD


def rows_text(scan: RawScan) -> str:
    """The auction lines: as the addon wrote them, or written again from the parsed rows."""
    if scan.text is not None:
        return scan.text
    lines = []
    for r in scan.rows:
        if r is None:
            lines.append("")
            continue
        lines.append(",".join([
            str(r.item), str(r.count), str(r.buyout), "" if r.min_bid is None else str(r.min_bid),
            "" if r.bid is None else str(r.bid), "" if r.band is None else str(r.band), "1" if r.own else "0",
            r.kind, r.name,
        ]))
    return "\n".join(lines)


def compute_seal(scan: RawScan) -> int:
    """The checksum the addon computes while reading a scan (Raw.lua: R.chain over every line, then
    over "<scope>|<time>|<auctions>"). Any changed line, number or header field changes it."""
    seal = 0
    if scan.rows:
        for line in rows_text(scan).split("\n"):
            seal = _chain(seal, line)
    return _chain(seal, f"{scan.scope}|{scan.at}|{len(scan.rows)}")


def check(scan: RawScan, now: float) -> str | None:
    """Why a scan cannot be shared, or None. The helper checks before uploading and the data
    repository checks again before archiving."""
    if not re.fullmatch(r"[^|\n]+-(Alliance|Horde|Neutral)", scan.scope):
        return "bad auction house name"
    if scan.at > now + 600:
        return "the scan is from the future"
    if now - scan.at > MAX_AGE:
        return "the scan is more than 7 days old"
    if not MIN_ROWS <= len(scan.rows) <= MAX_ROWS:
        return "implausible number of auctions"
    if scan.seal is None:
        return "the scan has no seal (it was made by a ForeverFlip version before 1.1.0)"
    if compute_seal(scan) != scan.seal:
        return "the seal does not match: the scan was changed after the game read it"
    unreadable = 0
    for r in scan.rows:
        if r is None:
            unreadable += 1
        elif r.item <= 0 or r.count <= 0 or r.count > 10000 or r.buyout < 0 or r.buyout > 10 ** 12 \
                or r.kind not in ("c", "i", "g", "") or (r.band is not None and not 0 <= r.band <= 3):
            return "implausible values"
    if unreadable > len(scan.rows) // 2:
        return "most auctions are unreadable"
    return None


def encode_raw(scan: RawScan) -> str:
    """The file a raw scan is uploaded as: a header line, then one line per auction."""
    header = "|".join([RAW_FORMAT, scan.scope, str(scan.at), scan.realm, scan.faction, scan.addon,
                       str(len(scan.rows)), "" if scan.seal is None else str(scan.seal)])
    return header + "\n" + rows_text(scan) if scan.rows else header


def decode_raw(text: str) -> RawScan:
    header, _, body = text.partition("\n")
    parts = header.split("|")
    if len(parts) < 7 or parts[0] != RAW_FORMAT:
        raise ValueError("not a ForeverFlip raw scan")
    scan = RawScan(scope=parts[1], at=int(parts[2]), realm=parts[3], faction=parts[4], addon=parts[5])
    scan.seal = int(parts[7]) if len(parts) > 7 and parts[7].isdigit() else None
    scan.rows = parse_rows(body) if int(parts[6]) > 0 else []
    scan.text = body
    if len(scan.rows) != int(parts[6]):
        raise ValueError(f"expected {parts[6]} auctions, found {len(scan.rows)}")
    return scan


# --- Summaries ---------------------------------------------------------------------------------

def scope_file(scope: str) -> str:
    return re.sub(r"[^A-Za-z0-9-]", "-", scope) + ".txt"


def enc36(n: float) -> str:
    n = int(math.floor(n or 0))
    if n <= 0:
        return "0"
    out = ""
    while n > 0:
        n, d = divmod(n, 36)
        out = DIGITS[d] + out
    return out


def _esc(text: str) -> str:
    return re.sub(r"[%,;|]", lambda m: "%%%02X" % ord(m.group(0)), text)


def usual_price(units_by_price: list[tuple[float, int]]) -> int | None:
    """The addon's usual price (Market.bucketValue): 2% price buckets, the cheapest price of the
    bucket that reaches 30% of the listed units."""
    buckets: dict[int, list] = {}
    total = 0
    for unit, qty in units_by_price:
        if unit <= 0 or qty <= 0:
            continue
        b = math.floor(math.log(unit) / BUCKET)
        if b in buckets:
            buckets[b][0] += qty
            buckets[b][1] = min(buckets[b][1], unit)
        else:
            buckets[b] = [qty, unit]
        total += qty
    if total == 0:
        return None
    seen = 0
    for b in sorted(buckets):
        seen += buckets[b][0]
        if seen >= total * 0.3:
            return int(math.floor(buckets[b][1]))
    return None


def summarize(scan: RawScan) -> dict:
    """{key: (usual, cheapest, units)} of other players' auctions with a buyout."""
    groups: dict[str, list] = {}
    for r in scan.rows:
        if r is None or r.own or r.buyout <= 0 or r.count <= 0:
            continue
        key = r.key()
        if key:
            groups.setdefault(key, []).append((r.buyout / r.count, r.count))
    out = {}
    for key, lots in groups.items():
        usual = usual_price(lots)
        if usual:
            out[key] = (usual, int(math.floor(min(u for u, _ in lots))), sum(q for _, q in lots))
    return out


def encode_summary(scope: str, at: int, items: dict) -> str:
    """The FF1 text the addon decodes (Share.decode)."""
    parts = [f"{_esc(k)},{enc36(m)},{enc36(low)},{enc36(n)}" for k, (m, low, n) in sorted(items.items())]
    return f"FF{SUMMARY_VERSION}|{_esc(scope)}|{enc36(at)}|" + ";".join(parts)


def lua_string(text: str) -> str:
    """A quoted Lua string."""
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def lua_data_file(summaries: list[str], generated: int, uploaded: list[str] | None = None) -> str:
    """Data.lua of the ForeverFlip_Shared addon. `uploaded`: the scans ("scope@time") this helper
    uploaded, so the addon stops keeping them (Raw.lua)."""
    lines = ["-- Written by the ForeverFlip Sync helper. Do not edit: it is replaced on every update.",
             "ForeverFlipShared = {", f"    generated = {int(generated)},", "    uploaded = {"]
    for ident in uploaded or []:
        lines.append(f"        [{lua_string(ident)}] = true,")
    lines += ["    },", "    scans = {"]
    for text in summaries:
        level = 1
        while "]" + "=" * level + "]" in text:
            level += 1
        eq = "=" * level
        lines.append(f"        [{eq}[{text}]{eq}],")
    lines += ["    },", "}", ""]
    return "\n".join(lines)


SHARED_TOC = """## Interface: 16001
## Title: ForeverFlip Shared Data
## Notes: Auction prices shared by the ForeverFlip community. Written by the ForeverFlip Sync helper.
## Author: ForeverFlip contributors

Data.lua
"""
