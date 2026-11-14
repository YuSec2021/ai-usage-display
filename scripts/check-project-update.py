#!/usr/bin/env python3
"""Check the About/changelog update contract in the worktree or a PR diff."""

from __future__ import annotations

import argparse
import importlib.util
import os
from pathlib import Path
import re
import subprocess
import sys


def check_update(root: Path, base: str | None = None, branch: str | None = None) -> list[str]:
    branch = branch or subprocess.check_output(["git", "branch", "--show-current"], cwd=root, text=True).strip()
    def git(*args: str) -> set[str]:
        output = subprocess.check_output(["git", *args], cwd=root)
        return {name.decode() for name in output.split(b"\0") if name}

    comparison = f"{base}...HEAD" if base else "HEAD"
    changed = git("diff", "--name-only", "-z", comparison, "--")
    changed |= git("ls-files", "--others", "--exclude-standard", "-z")
    added = git("diff", "--name-only", "--diff-filter=A", "-z", comparison, "--")
    added |= git("ls-files", "--others", "--exclude-standard", "-z")

    about = "Sources/AIUsage/Views/SettingsView.swift"
    index = "docs/changelog/README.md"
    errors = []
    numbers = {}
    for entry in (root / "docs/changelog").glob("*.md"):
        match = re.match(r"(\d+)-", entry.name)
        if match:
            number = int(match[1])
            if number in numbers:
                errors.append(f"变更编号重复：{numbers[number]} 与 {entry.name}")
            numbers[number] = entry.name
    index_path = root / index
    if not index_path.is_file():
        return [f"缺少变更索引：{index}"]
    index_text = index_path.read_text()
    for name in re.findall(r"\]\(([^)]+\.md)\)", index_text):
        if not (index_path.parent / name).is_file():
            errors.append(f"变更索引链接不存在：{name}")

    if branch and branch.startswith("codex/release-"):
        if not base or not re.fullmatch(r"codex/release-\d+\.\d+\.\d+-[0-9a-f]{12}", branch):
            return errors + ["版本 PR 分支或基准无效"]
        spec = importlib.util.spec_from_file_location("release_contract", Path(__file__).with_name("release-contract.py"))
        release = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(release)
        return errors + release.validate_release(root, base)

    if base and "project.yml" in changed:
        original = subprocess.check_output(["git", "show", f"{base}:project.yml"], cwd=root, text=True)
        current = (root / "project.yml").read_text()
        for key in ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION"):
            pattern = rf"(?m)^\s*{key}:.*$"
            if re.findall(pattern, original) != re.findall(pattern, current):
                errors.append(f"普通开发 PR 不可手动修改 {key}，请通过自动版本 PR 升版")

    if changed:
        for required in (about, index, "CHANGELOG.md"):
            if required not in changed:
                errors.append(f"本次更新须同步修改：{required}")
        entries = sorted(name for name in added if re.fullmatch(r"docs/changelog/\d{3}-.+\.md", name))
        if not entries:
            errors.append("本次更新须新增 docs/changelog/NNN-description.md 变更记录")
        for entry in entries:
            name = Path(entry).name
            sections = index_text.split("## 变更索引", 1)
            if len(sections) != 2 or any(f"]({name})" not in section for section in sections):
                errors.append(f"变更记录须同时列入最新更新和变更索引：{name}")
    return errors


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", help="PR base ref; defaults to uncommitted changes against HEAD")
    parser.add_argument("--branch", default=os.environ.get("PR_BRANCH"))
    args = parser.parse_args()
    try:
        errors = check_update(Path(__file__).resolve().parent.parent, args.base, args.branch)
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"无法检查项目更新流程：{error}", file=sys.stderr)
        sys.exit(1)
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        sys.exit(1)
    print("项目更新检查通过：About、变更记录与索引已同步。")
