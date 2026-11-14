#!/usr/bin/env python3
"""Check that a release PR contains exactly the trusted generator's output."""

from __future__ import annotations

from datetime import date
import importlib.util
from pathlib import Path
import re
import subprocess
import sys
import tempfile

spec = importlib.util.spec_from_file_location("bump_release", Path(__file__).with_name("bump-release-version.py"))
bump = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bump)


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=root, text=True).strip()


def version(project: str) -> str:
    match = re.search(r"(?m)^\s*MARKETING_VERSION:\s*[\"']?(\d+\.\d+\.\d+)", project)
    if not match:
        raise ValueError("项目缺少有效 MARKETING_VERSION")
    return match[1]


def validate_release(root: Path, base: str, generate: bool = True) -> list[str]:
    base = git(root, "rev-parse", base)
    changed = set(git(root, "diff", "--name-only", base, "HEAD").splitlines())
    records = [name for name in changed if re.fullmatch(r"docs/changelog/\d{3}-release-\d+\.\d+\.\d+\.md", name)]
    if len(records) != 1:
        return ["版本 PR 必须包含且只包含一条新发布记录"]
    allowed = {"project.yml", "README.md", "CHANGELOG.md", "docs/changelog/README.md", records[0],
               "AIUsage.xcodeproj/project.pbxproj"}
    if changed - allowed:
        return ["版本 PR 含非版本产物：" + ", ".join(sorted(changed - allowed))]
    entry = (root / records[0]).read_text()
    stamp = re.search(r"(?m)^日期：(\d{4}-\d{2}-\d{2})$", entry)
    if not stamp:
        return ["发布记录缺少有效日期"]
    with tempfile.TemporaryDirectory() as directory:
        expected = Path(directory) / "expected"
        subprocess.run(["git", "clone", "--quiet", "--shared", str(root.resolve()), str(expected)], check=True)
        subprocess.run(["git", "checkout", "--quiet", "--detach", base], cwd=expected, check=True)
        # A retry may run after this release's tag has been created. Its own tag
        # must not be treated as an older release when reconstructing the output.
        current = version((root / "project.yml").read_text())
        for tag in (current, "v" + current):
            if tag in git(expected, "tag", "--list").splitlines():
                subprocess.run(["git", "tag", "-d", tag], cwd=expected, check=True, stdout=subprocess.DEVNULL)
        result = bump.prepare_release(expected, date.fromisoformat(stamp[1]))
        if result["changed"] != "true":
            return ["版本 PR 的来源提交已经是发布版本"]
        if generate:
            subprocess.run(["xcodegen", "generate"], cwd=expected, check=True, stdout=subprocess.DEVNULL)
        errors = []
        for name in allowed:
            if not generate and name == "AIUsage.xcodeproj/project.pbxproj":
                continue
            target = expected / name
            if not target.is_file() or not (root / name).is_file() or target.read_bytes() != (root / name).read_bytes():
                errors.append(f"版本 PR 内容不符合发布脚本生成结果：{name}")
        return errors


def release_mode(root: Path) -> str:
    current = version((root / "project.yml").read_text())
    previous = version(git(root, "show", "HEAD^:project.yml"))
    if current != previous:
        errors = validate_release(root, "HEAD^")
        if errors:
            raise ValueError("；".join(errors))
        return "publish"
    if any(tag in {current, "v" + current} for tag in git(root, "tag", "--points-at", "HEAD").splitlines()):
        return "publish"
    return "prepare"


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    try:
        if len(sys.argv) == 2 and sys.argv[1] == "mode":
            print("mode=" + release_mode(root))
        elif len(sys.argv) == 3 and sys.argv[1] == "validate":
            errors = validate_release(root, sys.argv[2])
            if errors:
                raise ValueError("；".join(errors))
            print("版本 PR 契约通过：仅包含发布脚本与 XcodeGen 的精确生成内容。")
        else:
            raise ValueError("用法：release-contract.py mode | validate <base-ref>")
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f"发布契约检查失败：{error}")
