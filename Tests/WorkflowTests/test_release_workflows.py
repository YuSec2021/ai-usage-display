"""Guard the cross-platform release handoff; actionlint checks YAML semantics."""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]


def block(text, key, indent):
    match = re.search(rf"(?m)^{' ' * indent}{re.escape(key)}:.*\n", text)
    if not match:
        raise AssertionError(f"Missing workflow block: {key}")
    rest = text[match.start():]
    end = re.search(rf"(?m)^\S|^ {{1,{indent}}}\S", rest[len(match[0]):])
    return rest[:len(match[0]) + end.start()] if end else rest


class ReleaseWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.release = (ROOT / ".github/workflows/release.yml").read_text()
        self.windows = (ROOT / ".github/workflows/windows.yml").read_text()

    def test_publisher_waits_for_both_platforms_and_checks_all_downloads(self):
        publisher = block(self.release, "release", 2)
        needs = re.search(r"needs:\s*\[([^\]]+)\]", publisher)
        self.assertIsNotNone(needs, "Publishing must require both platform jobs")
        self.assertEqual({v.strip() for v in needs[1].split(',')}, {"build", "windows"})
        self.assertNotIn("if: always()", publisher)
        self.assertIn("name: AI-Usage-${{ env.RELEASE_TAG }}-universal", publisher)
        self.assertIn("name: AI-Usage-Windows-x64-preview", publisher)
        self.assertIn("name: AI-Usage-Windows-x64-preview", self.windows)
        self.assertEqual(publisher.count("path: dist"), 2)
        self.assertLess(publisher.rindex("path: dist"), publisher.index("sha256sum -c ./*.sha256"))
        self.assertLess(publisher.index("sha256sum -c ./*.sha256"), publisher.index("softprops/action-gh-release"))
        for pattern in ("dist/*.dmg", "dist/*.dmg.sha256", "dist/*.zip", "dist/*.zip.sha256"):
            self.assertIn(pattern, publisher)
        self.assertIn("fail_on_unmatched_files: true", publisher)

    def test_release_reuses_windows_build_with_the_same_tag(self):
        windows_job = block(self.release, "windows", 2)
        self.assertIn("uses: ./.github/workflows/windows.yml", windows_job)
        self.assertIn("tag: ${{ inputs.tag || github.ref_name }}", windows_job)
        call = block(self.windows, "workflow_call", 2)
        self.assertIn("tag:", call)
        self.assertIn("required: true", call)
        self.assertIn("type: string", call)
        self.assertIn("ref: ${{ inputs.tag && format('refs/tags/{0}', inputs.tag) || github.sha }}", self.windows)
        self.assertIn("REQUESTED_TAG: ${{ inputs.tag || '' }}", self.windows)
        self.assertIn(r"$env:REQUESTED_TAG -notmatch '^v?[0-9]+\.[0-9]+\.[0-9]+$'", self.windows)
        self.assertLess(self.windows.index("$env:REQUESTED_TAG -notmatch"), self.windows.index("actions/checkout"))
        self.assertIn("$env:REQUESTED_TAG.TrimStart('v') -ne $version", self.windows)

    def test_reused_build_keeps_tests_packaging_smoke_and_evidence(self):
        for step in ("dotnet test windows/AIUsage.Core.Tests", "dotnet publish windows/AIUsage.Windows",
                     "Compress-Archive", "Get-FileHash", "Expand-Archive", "./windows/scripts/smoke.ps1",
                     "name: windows-verification", "name: AI-Usage-Windows-x64-preview"):
            self.assertIn(step, self.windows)
        self.assertLess(self.windows.index("./windows/scripts/smoke.ps1"),
                        self.windows.index("name: Upload portable preview"))
        self.assertIn('"$hash  $name`n" | Set-Content -Encoding ascii -NoNewline', self.windows)
        self.assertIn("group: windows-${{ inputs.tag || github.head_ref || github.ref_name }}", self.windows)
        self.assertIn("cancel-in-progress: ${{ !inputs.tag }}", self.windows)

    def test_release_workflow_changes_trigger_windows_validation(self):
        for event in ("pull_request", "push"):
            self.assertIn("'.github/workflows/release.yml'", block(self.windows, event, 2))
