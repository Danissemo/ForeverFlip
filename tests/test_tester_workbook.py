"""The tester workbook (docs/tester-checklist.uk.xlsx) holds every card of docs/testing.md."""

import pathlib
import subprocess
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent


class TesterWorkbookTests(unittest.TestCase):
    def test_the_workbook_matches_the_guide_and_the_version(self):
        try:
            import openpyxl  # noqa: F401  # only asks whether the optional tool is there
            del openpyxl
        except ImportError:
            self.skipTest("openpyxl is not installed (requirements-dev.txt)")
        done = subprocess.run(
            [sys.executable, str(ROOT / "tools" / "make_tester_workbook.py"), "--check"],
            capture_output=True, text=True, encoding="utf-8",
        )
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)


    def test_the_check_reads_the_steps_and_the_links_not_only_the_ids(self):
        # The check once compared the card IDs and one cell: a changed step or expected result, or a
        # release link to the old version, passed as up to date.
        try:
            from openpyxl import load_workbook
        except ImportError:
            self.skipTest("openpyxl is not installed (requirements-dev.txt)")
        import importlib.util
        spec = importlib.util.spec_from_file_location("make_tester_workbook",
                                                      ROOT / "tools" / "make_tester_workbook.py")
        tool = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(tool)
        book = load_workbook(tool.BOOK)
        want = tool.content(book)
        self.assertEqual(tool.compare(want, want), [])
        book["Перевірки"]["F2"] = "a step nobody wrote"
        changed = tool.compare(tool.content(book), want)
        self.assertEqual(len(changed), 1, changed)
        self.assertTrue(changed[0].startswith("Перевірки!F2"), changed)
        for row in book["Як почати"].iter_rows():
            for cell in row:
                if cell.hyperlink and tool.RELEASES in str(cell.hyperlink.target):
                    cell.hyperlink = tool.RELEASES + "0.0.1"
        self.assertGreater(len(tool.compare(tool.content(book), want)), 1, "the release link is read too")

if __name__ == "__main__":
    unittest.main()
