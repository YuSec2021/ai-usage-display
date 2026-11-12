import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest


spec = importlib.util.spec_from_file_location(
    "check_project_update", Path(__file__).resolve().parents[2] / "scripts/check-project-update.py"
)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class ProjectUpdateTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.git("init", "-q")
        for name in ("Sources/AIUsage/Views/SettingsView.swift", "CHANGELOG.md", "docs/changelog/README.md"):
            self.write(name, "baseline\n")
        self.git("add", ".")
        self.git("-c", "user.name=Workflow Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "baseline")

    def git(self, *args):
        subprocess.run(["git", *args], cwd=self.root, check=True, capture_output=True)

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def complete_update(self):
        self.write("Sources/AIUsage/Views/SettingsView.swift", "updated notes\n")
        self.write("CHANGELOG.md", "unreleased changes\n")
        self.write("docs/changelog/001-update.md", "change and verification\n")
        self.write("docs/changelog/README.md", "## 最新更新\n[001](001-update.md)\n## 变更索引\n[001](001-update.md)\n")

    def test_accepts_complete_uncommitted_and_committed_pr_updates(self):
        self.complete_update()
        self.assertEqual(checker.check_update(self.root), [])
        self.git("add", ".")
        self.git("-c", "user.name=Workflow Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "update")
        self.assertEqual(checker.check_update(self.root, "HEAD~1"), [])

    def test_rejects_missing_about_update(self):
        self.complete_update()
        self.git("restore", "Sources/AIUsage/Views/SettingsView.swift")
        self.assertTrue(any("SettingsView.swift" in error for error in checker.check_update(self.root)))

    def test_rejects_missing_new_entry(self):
        self.complete_update()
        (self.root / "docs/changelog/001-update.md").unlink()
        self.assertTrue(any("须新增" in error for error in checker.check_update(self.root)))

    def test_rejects_missing_index_section_and_broken_links(self):
        self.complete_update()
        self.write("docs/changelog/README.md", "## 最新更新\n[001](001-update.md)\n[missing](999-missing.md)\n## 变更索引\n")
        errors = checker.check_update(self.root)
        self.assertTrue(any("链接不存在" in error for error in errors))
        self.assertTrue(any("同时列入" in error for error in errors))
