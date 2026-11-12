from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest


class ReleaseVersionTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        project = Path(__file__).resolve().parents[2]
        for name in ("scripts/verify-release-version.sh", "project.yml", "Sources/AIUsage/Views/SettingsView.swift"):
            destination = self.root / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(project / name, destination)
        self.version = next(
            line.split(":", 1)[1].strip()
            for line in (self.root / "project.yml").read_text().splitlines()
            if "MARKETING_VERSION:" in line
        )

    def verify(self, tag, app=None):
        args = ["/bin/zsh", str(self.root / "scripts/verify-release-version.sh"), tag]
        if app:
            args.append(str(app))
        return subprocess.run(args, capture_output=True, text=True)

    def app(self, version):
        app = self.root / "AIUsage.app"
        contents = app / "Contents"
        contents.mkdir(parents=True, exist_ok=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps({"CFBundleShortVersionString": version}))
        return app

    def test_accepts_matching_tag_with_or_without_v_prefix(self):
        for prefix in ("", "v"):
            with self.subTest(prefix=prefix):
                self.assertEqual(self.verify(prefix + self.version).returncode, 0)

    def test_rejects_tag_mismatch(self):
        result = self.verify("v9999.0.0")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("版本不一致", result.stderr)

    def test_accepts_matching_built_app(self):
        self.assertEqual(self.verify("v" + self.version, self.app(self.version)).returncode, 0)

    def test_rejects_built_app_version_mismatch(self):
        result = self.verify("v" + self.version, self.app("9999.0.0"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("构建出的 App", result.stderr)

    def test_rejects_missing_about_version_source(self):
        (self.root / "Sources/AIUsage/Views/SettingsView.swift").write_text("// missing version source\n")
        result = self.verify("v" + self.version)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("关于", result.stderr)
