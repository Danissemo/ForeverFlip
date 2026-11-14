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


if __name__ == "__main__":
    unittest.main()
