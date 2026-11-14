import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("preparation", ROOT / "scripts/check-preparation.py")
preparation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preparation)


class PreparationTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.git("init", "-qb", "main")
        self.git("config", "commit.gpgSign", "false")
        self.write("baseline", "initial")
        self.commit()
        self.base = self.git("rev-parse", "HEAD")
        self.branch = "codex/issue-1-fixture"
        self.git("switch", "-qc", self.branch)
        self.record = {"issue": 1, "type": "chore", "branch": self.branch, "status": "ready",
                       "document": "docs/issues/issue-1-fixture.md", "design": None, "research": None}
        self.document = (ROOT / "docs/issues/issue-21-standard-dev-flow.md").read_text().replace(
            "codex/issue-21-standard-dev-flow", self.branch).replace("/issues/21", "/issues/1")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True, stderr=subprocess.PIPE).strip()

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def commit(self):
        self.git("add", ".")
        self.git("-c", "user.name=Preparation Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "fixture")

    def prepare(self):
        self.write("docs/issues/issue-1.json", json.dumps(self.record))
        self.write(self.record["document"], self.document)
        self.commit()

    def check(self):
        return preparation.check_preparation(self.root, self.base, self.branch)

    def test_accepts_preparation_before_implementation(self):
        self.prepare()
        self.write("implementation.py", "print('fixture')\n")
        self.commit()
        self.assertEqual(self.check(), [])

    def test_rejects_missing_record_and_wrong_branch(self):
        self.assertTrue(self.check())
        self.prepare()
        self.assertTrue(preparation.check_preparation(self.root, self.base, "codex/untracked-task"))

    def test_rejects_implementation_before_or_in_preparation_commit(self):
        self.write("implementation.py", "early\n")
        self.commit()
        self.prepare()
        self.assertTrue(any("早于" in error for error in self.check()))

    def test_rejects_preparation_and_implementation_in_same_commit(self):
        self.write("implementation.py", "too early\n")
        self.prepare()
        self.assertTrue(any("独立准备提交" in error for error in self.check()))

    def test_rejects_conflicting_types_and_missing_sections(self):
        self.document += "\n类型：type/bug\n"
        self.document = self.document.replace("## 验收标准", "## 未填写")
        self.prepare()
        errors = self.check()
        self.assertTrue(any("验收标准" in error for error in errors))
        self.assertTrue(any("只能声明" in error for error in errors))

    def test_bug_requires_all_four_root_cause_lines(self):
        self.record["type"] = "bug"
        self.document = self.document.replace("type/chore", "type/bug")
        self.prepare()
        self.assertTrue(any("四行根因" in error for error in self.check()))

    def test_refactor_requires_design_and_reuse_statement(self):
        self.record["type"] = "refactor"
        self.document = self.document.replace("type/chore", "type/refactor")
        self.record["design"] = "docs/design/issue-1-fixture.md"
        self.write(self.record["design"], "# Empty design\n")
        self.prepare()
        self.assertTrue(any("搜过什么关键词" in error for error in self.check()))

    def test_spike_requires_research_output(self):
        self.record["type"] = "spike"
        self.document = self.document.replace("type/chore", "type/spike")
        self.prepare()
        self.assertTrue(any("research" in error for error in self.check()))

    def test_accepts_complete_bug_feature_and_spike_materials(self):
        for kind in ("bug", "feature", "spike"):
            with self.subTest(kind=kind):
                self.record["type"] = kind
                document = self.document.replace("type/chore", "type/" + kind)
                if kind == "bug":
                    document += "\n- 现象：fixture 复现失败状态\n- 根因：baseline 中缺少校验\n- 影响面：fixture 数据\n- 回归：隔离测试覆盖失败与恢复\n"
                elif kind == "feature":
                    self.record["design"] = "docs/design/issue-1-fixture.md"
                    self.write(self.record["design"], "仓库是否已有该能力：部分已有 fixture\n搜过什么关键词：baseline\n看过哪些既有实现：baseline\n为什么不能复用：需要增加 fixture 的校验\n")
                else:
                    self.record["research"] = "docs/research/issue-1-fixture.md"
                    self.write(self.record["research"], "决策问题：fixture 是否可复用\n产出：可核验的调研结论\n")
                self.write("docs/issues/issue-1.json", json.dumps(self.record))
                self.write(self.record["document"], document)
                # Record the full initial material snapshot for each independent case.
                self.commit()
                errors = preparation.validate_record(self.record, document, self.branch)
                self.assertEqual(errors, [])

    def test_rejects_design_backfilled_after_preparation(self):
        self.record["type"] = "refactor"
        self.document = self.document.replace("type/chore", "type/refactor")
        self.record["design"] = "docs/design/issue-1-fixture.md"
        self.write(self.record["design"], "# not ready\n")
        self.prepare()
        self.write(self.record["design"], "仓库是否已有该能力：是 fixture\n搜过什么关键词：baseline\n看过哪些既有实现：baseline\n为什么不能复用：N/A — 将直接复用 baseline\n")
        self.commit()
        self.assertTrue(any("搜过什么关键词" in error for error in self.check()))

    def test_rejects_same_branch_assigned_to_two_issues(self):
        self.prepare()
        other = dict(self.record, issue=2)
        self.write("docs/issues/issue-2.json", json.dumps(other))
        self.assertTrue(any("其他 Issue" in error for error in self.check()))

    def test_rejects_record_pointing_outside_document_directory(self):
        self.record["document"] = "../../outside.md"
        self.write("docs/issues/issue-1.json", json.dumps(self.record))
        self.assertTrue(self.check())
