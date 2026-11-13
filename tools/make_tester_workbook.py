"""Builds the tester workbook (docs/tester-checklist.uk.xlsx) from the cards of docs/testing.md.

The workbook is its own template: the "Як почати" sheet keeps its layout and gets the version and
release links of the TOC version; the "Перевірки" sheet is filled again with every card of the
in-game checklist (ID, section, importance, what is needed, steps, expected result), with the same
styles, the result list, its colours, the filter and the progress formulas sized to the cards.

    python tools/make_tester_workbook.py            # writes docs/tester-checklist.uk.xlsx
    python tools/make_tester_workbook.py --check    # fails when the workbook is out of date
"""

from __future__ import annotations

import argparse
import copy
import io
import math
import pathlib
import re
import sys

from openpyxl import load_workbook
from openpyxl.formatting.rule import FormulaRule
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.worksheet.datavalidation import DataValidation

ROOT = pathlib.Path(__file__).resolve().parent.parent
GUIDE = ROOT / "docs" / "testing.md"
BOOK = ROOT / "docs" / "tester-checklist.uk.xlsx"
TOC = ROOT / "ForeverFlip" / "ForeverFlip.toc"
RELEASES = "https://github.com/Danissemo/ForeverFlip/releases/tag/v"

MUST, MAYBE = "Обов’язково", "За можливості"
RESULTS = ["⬜ Не перевірено", "✅ Пройдено", "❌ Не пройдено", "⏭ Пропущено"]
RESULT_STYLES = {  # fill, font colour
    "✅ Пройдено": ("C6EFCE", "006100"),
    "❌ Не пройдено": ("FFC7CE", "9C0006"),
    "⏭ Пропущено": ("FFEB9C", "7F6000"),
    "⬜ Не перевірено": ("F2F2F2", "595959"),
}
COLUMNS = ["ID", "Розділ", "Важливість", "Що перевіряємо", "Що потрібно заздалегідь", "Що робити",
           "Що має статися", "Результат", "Що сталося насправді / коментар"]
WIDTHS = [10, 14, 13, 26, 30, 62, 56, 17, 42]
ARIAL = "Arial"
STRIPE = PatternFill("solid", fgColor="F7F9FC")
NONE = PatternFill(fill_type=None)
IMPORTANCE = {MUST: PatternFill("solid", fgColor="FDE9D9"), MAYBE: PatternFill("solid", fgColor="EDEDED")}
EDGE = Side(style="thin", color="C9D3DF")
BORDER = Border(left=EDGE, right=EDGE, top=EDGE, bottom=EDGE)


def version() -> str:
    match = re.search(r"^## Version:\s*(\S+)", TOC.read_text(encoding="utf-8"), re.M)
    if not match:
        sys.exit("no version in the TOC")
    return match.group(1)


def plain(text: str) -> str:
    """Markdown of a card line as the workbook shows it: no code marks, bold or links."""
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    return text.replace("`", "").replace("**", "").strip()


def cards() -> list[dict]:
    """Every card of the in-game checklist, in order: the ##### headings under ### Чек-лист."""
    text = GUIDE.read_text(encoding="utf-8").replace("\r\n", "\n")
    start = text.index("### Чек-лист поточної бети")
    end = text.index("#### Автоперевірки складних ситуацій", start)
    out, section, card, part = [], None, None, None
    for line in text[start:end].split("\n"):
        heading = re.match(r"^#### (.+)$", line)
        if heading:
            section = heading.group(1).strip()
            continue
        head = re.match(r"^##### ([A-Z]+-\d+) — (.+)$", line)
        if head:
            card = {"id": head.group(1), "section": section, "title": plain(head.group(2)),
                    "importance": None, "needs": "", "steps": [], "expect": []}
            out.append(card)
            part = "needs"
            continue
        if not card:
            continue
        need = re.match(r"^\*(Обов’язково|За можливості)\.\*\s*\*\*Потрібно:\*\*\s*(.*)$", line)
        if need:
            card["importance"], card["needs"] = need.group(1), plain(need.group(2))
            continue
        if line.startswith("**Має статися:**"):
            part = "expect"
            continue
        step = re.match(r"^(\d+)\.\s+(.*)$", line)
        bullet = re.match(r"^-\s+(.*)$", line)
        if step and part in ("needs", "steps"):
            part = "steps"
            card["steps"].append(f"{step.group(1)}. {plain(step.group(2))}")
        elif bullet and part == "expect":
            card["expect"].append(plain(bullet.group(1)))
        elif line.startswith("  ") and line.strip():
            # a wrapped line continues the last step, bullet or the needs
            target = {"steps": card["steps"], "expect": card["expect"]}.get(part)
            if target:
                target[-1] += " " + plain(line)
            elif part == "needs":
                card["needs"] += " " + plain(line)
        elif part == "needs" and line.strip() and card["importance"]:
            card["needs"] += " " + plain(line)
    for c in out:
        if not c["importance"] or not c["steps"] or not c["expect"]:
            sys.exit(f"card {c['id']} lacks its importance, steps or expected result")
    return out


def lines(text: str, width: int) -> int:
    per = max(8, int(width * 1.15))
    return sum(max(1, math.ceil(len(p) / per)) for p in str(text).split("\n"))


def fill_checks(ws, all_cards: list[dict]) -> int:
    ws.delete_rows(1, ws.max_row)
    ws.conditional_formatting = type(ws.conditional_formatting)()
    ws.data_validations.dataValidation = []
    for i, (name, width) in enumerate(zip(COLUMNS, WIDTHS), start=1):
        cell = ws.cell(row=1, column=i, value=name)
        cell.font = Font(name=ARIAL, size=10, bold=True, color="FFFFFF")
        cell.fill = PatternFill("solid", fgColor="1F3A5F")
        cell.alignment = Alignment(wrap_text=True, vertical="center")
        cell.border = BORDER
        ws.column_dimensions[cell.column_letter].width = width
    ws.row_dimensions[1].height = 30
    for row, c in enumerate(all_cards, start=2):
        stripe = STRIPE if row % 2 == 0 else NONE
        values = [c["id"], c["section"], c["importance"], c["title"], c["needs"], "\n".join(c["steps"]),
                  "\n".join("• " + e for e in c["expect"]), RESULTS[0], None]
        for col, value in enumerate(values, start=1):
            cell = ws.cell(row=row, column=col, value=value)
            bold = col in (1, 4, 8)
            colour = "1F3A5F" if col == 1 else "000000"
            cell.font = Font(name=ARIAL, size=10, bold=bold, color=colour)
            cell.fill = IMPORTANCE[c["importance"]] if col == 3 else stripe
            cell.alignment = Alignment(horizontal="center" if col == 8 else None, vertical="top",
                                       wrap_text=col != 8)
            cell.border = BORDER
        tall = max(lines(v, w) for v, w in zip(values, WIDTHS) if v)
        ws.row_dimensions[row].height = max(30, 13 * tall + 6)
    last = len(all_cards) + 1
    results = f"H2:H{last}"
    dv = DataValidation(type="list", formula1='"' + ",".join(RESULTS) + '"', allow_blank=False)
    dv.add(results)
    ws.add_data_validation(dv)
    for result, (fill, font) in RESULT_STYLES.items():
        ws.conditional_formatting.add(results, FormulaRule(
            formula=[f'$H2="{result}"'], fill=PatternFill("solid", fgColor=fill, bgColor=fill),
            font=Font(color=font, bold=True)))
    ws.auto_filter.ref = f"A1:I{last}"
    ws.freeze_panes = "E2"
    ws.print_title_rows = "1:1"
    return last


def fill_start(ws, ver: str, last: int, total: int, must: int) -> None:
    for row in ws.iter_rows():
        for cell in row:
            if isinstance(cell.value, str):
                value = re.sub(r"\d+\.\d+\.\d+(?:-beta\.\d+)?", ver, cell.value) if (
                    "версії" in cell.value or "ForeverFlip-" in cell.value or RELEASES in cell.value
                ) else cell.value
                value = re.sub(r"'Перевірки'!\$([A-Z])\$2:\$\1\$\d+", lambda m: f"'Перевірки'!${m.group(1)}$2:${m.group(1)}${last}", value)
                if value != cell.value:
                    cell.value = value
                if cell.hyperlink and RELEASES in str(cell.hyperlink.target):
                    cell.hyperlink = RELEASES + ver


def build() -> bytes:
    ver = version()
    all_cards = cards()
    wb = load_workbook(BOOK)
    last = fill_checks(wb["Перевірки"], all_cards)
    must = sum(1 for c in all_cards if c["importance"] == MUST)
    fill_start(wb["Як почати"], ver, last, len(all_cards), must)
    wb.properties.title = f"ForeverFlip {ver} — бланк тестувальника"
    # The progress formulas carry no saved values: Excel and Google Sheets work them out on opening.
    wb.calculation.fullCalcOnLoad = True
    out = io.BytesIO()
    wb.save(out)
    return out.getvalue()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--check", action="store_true", help="only report whether it is up to date")
    args = parser.parse_args()
    if args.check:
        wb = load_workbook(BOOK)
        ws = wb["Перевірки"]
        ids = [ws.cell(row=r, column=1).value for r in range(2, ws.max_row + 1)]
        want = [c["id"] for c in cards()]
        ok = ids == want and version() in str(wb["Як почати"]["B3"].value)
        print("up to date" if ok else "out of date: run python tools/make_tester_workbook.py")
        return 0 if ok else 1
    BOOK.write_bytes(build())
    print(f"wrote {BOOK.relative_to(ROOT)}: {len(cards())} checks for {version()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
