from datetime import date
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest


spec = importlib.util.spec_from_file_location(
    "bump_release_version", Path(__file__).resolve().parents[2] / "scripts/bump-release-version.py"
)
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class BumpReleaseVersionTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.git("init", "-q")
        self.git("config", "tag.gpgSign", "false")
        self.git("config", "tag.forceSignAnnotated", "false")
        self.git("config", "commit.gpgSign", "false")
        self.write("project.yml", '  MARKETING_VERSION: 1.2.1\n  CURRENT_PROJECT_VERSION: 5\n')
        self.write("README.md", '> 当前版本：1.2.1。\n\n安装包 dist/AI-Usage-1.2.1.dmg\n')
        self.write("CHANGELOG.md", '# Changelog\n\n## Unreleased\n\n- New quota rings.\n\n## 1.2.1 — 2026-09-26\n\n- Old release.\n')
        self.write("docs/changelog/001-existing.md", '# Existing change\n')
        self.write("docs/changelog/README.md", '# Changes\n\n## 最新更新\n\n- [001](001-existing.md)\n\n## 变更索引\n\n| # | 类型 | 标题 | 日期 |\n| --- | --- | --- | --- |\n| [001](001-existing.md) | test | Existing | 2026-11-11 |\n')
        self.commit()

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True).strip()

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def commit(self):
        self.git("add", ".")
        self.git("-c", "user.name=Release Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "fixture")

    def prepare(self):
        return release.prepare_release(self.root, date(2026, 11, 12))

    def test_updates_version_build_readme_and_release_records(self):
        self.assertEqual(self.prepare(), {"tag": "v1.2.2", "version": "1.2.2", "changed": "true"})
        self.assertIn("MARKETING_VERSION: 1.2.2", (self.root / "project.yml").read_text())
        self.assertIn("CURRENT_PROJECT_VERSION: 6", (self.root / "project.yml").read_text())
        self.assertIn("当前版本：1.2.2。", (self.root / "README.md").read_text())
        self.assertIn("AI-Usage-1.2.2.dmg", (self.root / "README.md").read_text())
        changelog = (self.root / "CHANGELOG.md").read_text()
        self.assertIn("## Unreleased\n\n## 1.2.2 — 2026-11-12\n\n- New quota rings.", changelog)
        self.assertIn("## 1.2.1 — 2026-09-26", changelog)
        self.assertTrue((self.root / "docs/changelog/002-release-1.2.2.md").is_file())
        self.assertEqual((self.root / "docs/changelog/README.md").read_text().count("](002-release-1.2.2.md)"), 2)

    def test_reuses_tagged_version_on_retry_without_changing_files(self):
        self.prepare()
        self.commit()
        self.git("tag", "v1.2.2")
        self.assertEqual(self.prepare(), {"tag": "v1.2.2", "version": "1.2.2", "changed": "false"})
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_accepts_existing_unprefixed_tag_for_retry(self):
        self.git("tag", "1.2.1")
        self.assertEqual(self.prepare()["tag"], "1.2.1")
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_avoids_existing_higher_version_tags(self):
        self.git("tag", "v1.4.9")
        self.git("tag", "v9.0.0-beta")
        self.assertEqual(self.prepare()["version"], "1.4.10")

    def test_rejects_dirty_worktree_without_overwriting_user_changes(self):
        self.write("README.md", 'User edit\n')
        with self.assertRaisesRegex(ValueError, "干净工作区"):
            self.prepare()
        self.assertEqual((self.root / "README.md").read_text(), "User edit\n")
        self.assertIn("MARKETING_VERSION: 1.2.1", (self.root / "project.yml").read_text())

    def test_rejects_bad_metadata_before_writing_any_files(self):
        self.write("docs/changelog/README.md", '# No required sections\n')
        self.commit()
        with self.assertRaisesRegex(ValueError, "编号日志索引"):
            self.prepare()
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_supports_quoted_versions_and_multi_digit_patch(self):
        self.write("project.yml", '  MARKETING_VERSION: "1.2.19"\n  CURRENT_PROJECT_VERSION: "17"\n')
        self.commit()
        self.assertEqual(self.prepare()["version"], "1.2.20")
        self.assertIn('CURRENT_PROJECT_VERSION: "18"', (self.root / "project.yml").read_text())
