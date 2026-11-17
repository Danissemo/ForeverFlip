"""Release documentation sanity checks: local links, versions and historical scope."""

from pathlib import Path
import re
import unittest
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parent.parent
LINK = re.compile(r"\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
TOC_VERSION = re.compile(r"^## Version:\s*(\S+)", re.M)
RUNTIME_VERSION = re.compile(r'^F\.version\s*=\s*"([^"]+)"', re.M)


class DocumentationTests(unittest.TestCase):
    def test_release_and_runtime_versions_match_documentation(self):
        toc = (ROOT / "ForeverFlip/ForeverFlip.toc").read_text(encoding="utf-8")
        util = (ROOT / "ForeverFlip/Core/Util.lua").read_text(encoding="utf-8")
        toc_version = TOC_VERSION.search(toc)
        runtime_version = RUNTIME_VERSION.search(util)
        self.assertIsNotNone(toc_version)
        self.assertIsNotNone(runtime_version)
        self.assertEqual(toc_version.group(1), runtime_version.group(1))
        version = toc_version.group(1)
        for path in ("README.md", "docs/current-work.md"):
            with self.subTest(path=path):
                self.assertIn(version, (ROOT / path).read_text(encoding="utf-8"))

    def test_repository_markdown_links_point_to_existing_paths(self):
        for doc in sorted(ROOT.rglob("*.md")):
            if any(part in (".git", "dist", "research", ".venv") for part in doc.parts):
                continue
            source = doc.read_text(encoding="utf-8")
            for raw in LINK.findall(source):
                if raw.startswith("#") or re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", raw) or raw.startswith("//"):
                    continue
                path = unquote(raw.split("#", 1)[0].split("?", 1)[0])
                if not path:
                    continue
                target = (doc.parent / path).resolve()
                with self.subTest(doc=doc.relative_to(ROOT).as_posix(), link=raw):
                    self.assertTrue(target.exists(), f"Broken local Markdown link: {doc}: {raw}")

    def test_current_release_diagnostics_and_archived_checklist_are_documented(self):
        saved = (ROOT / "docs/saved-data.md").read_text(encoding="utf-8")
        guide = (ROOT / "docs/user-guide.md").read_text(encoding="utf-8")
        testing = (ROOT / "docs/testing.md").read_text(encoding="utf-8")
        formulas = (ROOT / "docs/formulas.uk.md").read_text(encoding="utf-8")
        for name in ("trace", "traceStats", "traceSlow", "tipSkew", "Server"):
            with self.subTest(saved_field=name):
                self.assertIn(name, saved)
        for command in ("/ff trace", "/ff dev", "/ff stats rollback"):
            with self.subTest(command=command):
                self.assertIn(command, guide)
        self.assertIn('<a id="current-beta-checklist"></a>', testing)
        self.assertIn("Архівний чек-лист 2.3.0-beta.1", testing)
        self.assertIn("release-3.1.0-validation.md", testing)
        self.assertNotIn("C:/FF/development/foreverflip", formulas)


if __name__ == "__main__":
    unittest.main()
