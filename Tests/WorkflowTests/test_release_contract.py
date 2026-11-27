from datetime import date
import importlib.util
import os
from pathlib import Path
import stat
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

    def install_fake_xcodegen(self, upgrade_version: str, include_build_architectures: bool):
        bin_dir = tempfile.TemporaryDirectory()
        self.addCleanup(bin_dir.cleanup)
        script = Path(bin_dir.name) / "xcodegen"
        arch_line = '      buildArchitectures = "Automatic"\\n' if include_build_architectures else ""
        script.write_text(
            "#!/usr/bin/env python3\n"
            "from pathlib import Path\n"
            "import re\n"
            "project = Path('project.yml').read_text()\n"
            "ver = re.search(r'MARKETING_VERSION:\\s*(\\S+)', project)[1]\n"
            "bld = re.search(r'CURRENT_PROJECT_VERSION:\\s*(\\S+)', project)[1]\n"
            "Path('AIUsage.xcodeproj/xcshareddata/xcschemes').mkdir(parents=True, exist_ok=True)\n"
            "Path('AIUsage.xcodeproj/project.pbxproj').write_text(\n"
            f"    '\\t\\t\\t\\tLastUpgradeCheck = {upgrade_version};\\n'\n"
            "    f'\\t\\t\\t\\tCURRENT_PROJECT_VERSION = {bld};\\n'\n"
            "    f'\\t\\t\\t\\tMARKETING_VERSION = {ver};\\n'\n"
            "    '\\t\\t\\t\\tPRODUCT_BUNDLE_IDENTIFIER = com.yusec.aiusage;\\n'\n"
            ")\n"
            "Path('AIUsage.xcodeproj/xcshareddata/xcschemes/AIUsage.xcscheme').write_text(\n"
            "    '<?xml version=\"1.0\" encoding=\"UTF-8\"?>\\n'\n"
            "    '<Scheme\\n'\n"
            f"    '   LastUpgradeVersion = \"{upgrade_version}\"\\n'\n"
            "    '   version = \"1.7\">\\n'\n"
            "    '   <BuildAction\\n'\n"
            "    '      parallelizeBuildables = \"YES\"\\n'\n"
            "    '      buildImplicitDependencies = \"YES\"\\n'\n"
            f"    '{arch_line}'\n"
            "    '      runPostActionsOnFailure = \"NO\">\\n'\n"
            "    '   </BuildAction>\\n'\n"
            "    '</Scheme>\\n'\n"
            ")\n"
        )
        script.chmod(script.stat().st_mode | stat.S_IXUSR)
        original_path = os.environ.get("PATH", "")
        os.environ["PATH"] = f"{bin_dir.name}{os.pathsep}{original_path}"
        self.addCleanup(lambda: os.environ.__setitem__("PATH", original_path))

    def setup_xcode_fixture(self, pr_upgrade: str, pr_arch: bool, base_upgrade: str = "1430", base_arch: bool = False):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.git("init", "-qb", "main")
        self.git("config", "commit.gpgSign", "false")
        self.git("config", "tag.gpgSign", "false")
        self.write("project.yml", "  MARKETING_VERSION: 1.2.9\n  CURRENT_PROJECT_VERSION: 13\n")
        self.write("README.md", "> 当前版本：1.2.9。fixture\n")
        self.write("CHANGELOG.md", "# Changelog\n\n## Unreleased\n\n- fixture change\n")
        self.write("docs/changelog/README.md", "# Changes\n\n## 最新更新\n\n## 变更索引\n")
        self.install_fake_xcodegen(base_upgrade, base_arch)
        subprocess.run(["xcodegen", "generate"], cwd=self.root, check=True)
        self.commit()
        self.base = self.git("rev-parse", "HEAD")
        contract.bump.prepare_release(self.root, date(2026, 11, 27))
        self.install_fake_xcodegen(pr_upgrade, pr_arch)
        subprocess.run(["xcodegen", "generate"], cwd=self.root, check=True)
        self.commit()

    def test_accepts_cross_version_xcodegen_metadata_drift(self):
        # PR generated with XcodeGen 2.48.0 (1600 + buildArchitectures), verified on 2.46.0 (1430)
        self.setup_xcode_fixture(pr_upgrade="1600", pr_arch=True)
        self.install_fake_xcodegen("1430", False)
        self.assertEqual(contract.validate_release(self.root, self.base, generate=True), [])

        # Reverse: PR generated with 2.46.0 (1430), verified on 2.48.0 (1600 + buildArchitectures)
        self.setup_xcode_fixture(pr_upgrade="1430", pr_arch=False)
        self.install_fake_xcodegen("1600", True)
        self.assertEqual(contract.validate_release(self.root, self.base, generate=True), [])

    def test_rejects_tampered_xcscheme_pbxproj_and_extra_scheme(self):
        self.setup_xcode_fixture(pr_upgrade="1600", pr_arch=True)
        self.install_fake_xcodegen("1430", False)

        # Tampered buildArchitectures value
        scheme_path = "AIUsage.xcodeproj/xcshareddata/xcschemes/AIUsage.xcscheme"
        original_scheme = (self.root / scheme_path).read_text()
        self.write(scheme_path, original_scheme.replace('Automatic', 'x86_64'))
        self.commit()
        self.assertTrue(contract.validate_release(self.root, self.base, generate=True))

        # Tampered extra XML element in AIUsage.xcscheme
        self.write(scheme_path, original_scheme.replace('</Scheme>', '   <ExtraAction />\n</Scheme>'))
        self.commit()
        self.assertTrue(contract.validate_release(self.root, self.base, generate=True))
        self.write(scheme_path, original_scheme)

        # Tampered project.pbxproj build setting
        pbx_path = "AIUsage.xcodeproj/project.pbxproj"
        original_pbx = (self.root / pbx_path).read_text()
        self.write(pbx_path, original_pbx.replace('com.yusec.aiusage', 'com.evil.aiusage'))
        self.commit()
        self.assertTrue(contract.validate_release(self.root, self.base, generate=True))
        self.write(pbx_path, original_pbx)

        # Unexpected extra scheme file
        self.write("AIUsage.xcodeproj/xcshareddata/xcschemes/Extra.xcscheme", original_scheme)
        self.commit()
        errors = contract.validate_release(self.root, self.base, generate=True)
        self.assertTrue(any("非版本产物" in error for error in errors))
