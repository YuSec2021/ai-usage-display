#!/usr/bin/env python3
"""Prepare a patch release on a clean checkout; Git commit/push stays in Actions."""

from __future__ import annotations

from datetime import date, datetime
from pathlib import Path
import re
import subprocess
import sys
from zoneinfo import ZoneInfo


def prepare_release(root: Path, release_date: date | None = None) -> dict[str, str]:
    def git(*args: str) -> str:
        return subprocess.check_output(["git", *args], cwd=root, text=True).strip()

    if git("status", "--porcelain"):
        raise ValueError("版本准备需要干净工作区。")
    project_path = root / "project.yml"
    project = project_path.read_text()
    version_pattern = r"(?m)^([ \t]*MARKETING_VERSION:[ \t]*)([\"']?)(\d+\.\d+\.\d+)\2[ \t]*$"
    build_pattern = r"(?m)^([ \t]*CURRENT_PROJECT_VERSION:[ \t]*)([\"']?)(\d+)\2[ \t]*$"
    versions = list(re.finditer(version_pattern, project))
    builds = list(re.finditer(build_pattern, project))
    if len(versions) != 1 or len(builds) != 1:
        raise ValueError("project.yml 必须包含唯一的 X.Y.Z 版本与数字构建号。")
    current = versions[0].group(3)
    head = git("rev-parse", "HEAD")
    head_tags = git("tag", "--points-at", "HEAD").splitlines()
    for tag in (f"v{current}", current):
        if tag in head_tags:
            return {"tag": tag, "version": current, "changed": "false"}

    version_numbers = [tuple(map(int, current.split(".")))]
    for tag in git("tag", "--list").splitlines():
        match = re.fullmatch(r"v?(\d+)\.(\d+)\.(\d+)", tag)
        if match:
            version_numbers.append(tuple(map(int, match.groups())))
    major, minor, patch = max(version_numbers)
    version = f"{major}.{minor}.{patch + 1}"
    build = int(builds[0].group(3)) + 1
    stamp = str(release_date or datetime.now(ZoneInfo("America/New_York")).date())

    readme_path = root / "README.md"
    readme, count = re.subn(
        r"(?m)^(> 当前版本：)\d+\.\d+\.\d+(。.*)$",
        lambda match: f"{match[1]}{version}{match[2]}", readme_path.read_text()
    )
    if count != 1:
        raise ValueError("README 缺少唯一的当前版本声明。")
    readme = re.sub(r"dist/AI-Usage-\d+\.\d+\.\d+\.dmg", f"dist/AI-Usage-{version}.dmg", readme)

    changelog_path = root / "CHANGELOG.md"
    changelog = changelog_path.read_text()
    section = re.search(r"(?ms)^## Unreleased[ \t]*\n(.*?)(?=^## |\Z)", changelog)
    if not section:
        raise ValueError("CHANGELOG 缺少 Unreleased 章节。")
    notes = section[1].strip() or "- 常规维护更新。"
    changelog = changelog[:section.start()] + f"## Unreleased\n\n## {version} — {stamp}\n\n{notes}\n\n" + changelog[section.end():].lstrip("\n")

    directory = root / "docs/changelog"
    index_path = directory / "README.md"
    index = index_path.read_text()
    if index.count("## 最新更新\n") != 1 or index.count("## 变更索引\n") != 1:
        raise ValueError("编号日志索引缺少唯一的最新更新或变更索引章节。")
    numbers = [int(match[1]) for path in directory.glob("*.md")
               if (match := re.match(r"(\d+)-", path.name))]
    number = max(numbers, default=0) + 1
    name = f"{number:03d}-release-{version}.md"
    index = index.replace("## 最新更新\n", f"## 最新更新\n\n- [{number:03d}：发布 {version}]({name})：自动补丁升版为 {version}（Build {build}），发布结果以 Actions 为准。", 1)
    index = index.rstrip() + f"\n| [{number:03d}]({name}) | release | 发布 {version} | {stamp} |\n"
    entry = f"""# {number:03d}：发布 {version}

日期：{stamp}

main 自动准备补丁版本 {version}（Build {build}），同步 Xcode 工程、README 与根目录发布摘要。
来源提交：`{head}`。About 从 Info.plist 动态读取本次版本，无需硬编码。

Tag 为 `v{version}`，指向自动版本提交。后续校验、测试、通用 DMG 和附件上传由 Release 工作流执行；实际成功与否以 Actions 和 GitHub Release 为准。
变更详情见[根目录发布摘要](../../CHANGELOG.md)。产物仍为临时签名、未公证版本。
"""
    project = re.sub(version_pattern, lambda match: f"{match[1]}{match[2]}{version}{match[2]}", project)
    project = re.sub(build_pattern, lambda match: f"{match[1]}{match[2]}{build}{match[2]}", project)
    changes = {project_path: project, readme_path: readme, changelog_path: changelog,
               index_path: index, directory / name: entry}
    for path, content in changes.items():
        path.write_text(content)
    return {"tag": f"v{version}", "version": version, "changed": "true"}


if __name__ == "__main__":
    try:
        result = prepare_release(Path(__file__).resolve().parent.parent)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f"无法准备发布版本：{error}")
    for key, value in result.items():
        print(f"{key}={value}")
