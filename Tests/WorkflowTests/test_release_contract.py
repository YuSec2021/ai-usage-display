from datetime import date
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("release_contract", ROOT / "scripts/release-contract.py")
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)


class ReleaseContractTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.git("init", "-qb", "main")
        self.git("config", "commit.gpgSign", "false")
        self.git("config", "tag.gpgSign", "false")
        self.write("project.yml", "  MARKETING_VERSION: 1.2.5\n  CURRENT_PROJECT_VERSION: 9\n")
        self.write("README.md", "> 当前版本：1.2.5。fixture\n")
        self.write("CHANGELOG.md", "# Changelog\n\n## Unreleased\n\n- fixture change\n")
        self.write("docs/changelog/README.md", "# Changes\n\n## 最新更新\n\n## 变更索引\n")
        self.commit()
        self.base = self.git("rev-parse", "HEAD")
        contract.bump.prepare_release(self.root, date(2026, 11, 14))
        self.commit()

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True, stderr=subprocess.PIPE).strip()

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def commit(self):
        self.git("add", ".")
        self.git("-c", "user.name=Release Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "fixture")

    def check(self):
        return contract.validate_release(self.root, self.base, generate=False)

    def test_accepts_exact_generated_release_and_retry_with_tag(self):
        self.assertEqual(self.check(), [])
        self.git("tag", "v1.2.6")
        self.assertEqual(self.check(), [])

    def test_rejects_application_change_disguised_as_release(self):
        self.write("Sources/AIUsage/App.swift", "tampered\n")
        self.commit()
        self.assertTrue(any("非版本产物" in error for error in self.check()))

    def test_rejects_tampered_version_and_readme(self):
        for name in ("README.md", "project.yml"):
            with self.subTest(name=name):
                original = (self.root / name).read_text()
                self.write(name, original + "tampered\n")
                self.commit()
                self.assertTrue(self.check())
                self.write(name, original)
                self.commit()

    def test_rejects_missing_release_entry(self):
        (self.root / "docs/changelog/001-release-1.2.6.md").unlink()
        self.commit()
        self.assertTrue(self.check())
