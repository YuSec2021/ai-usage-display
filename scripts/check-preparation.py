#!/usr/bin/env python3
"""Validate the task record and its preparation commit, locally and in PR checks."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

TYPES = {"feature", "bug", "chore", "docs", "spike", "refactor"}
SECTIONS = ("基本信息", "背景", "目标", "非目标", "根因说明", "验收标准", "模块拆解",
            "风险、假设与待决策项", "验证计划", "完成定义")


def validate_material(kind: str, text: str, path: str) -> list[str]:
    fields = ("决策问题", "产出") if kind == "spike" else (
        "仓库是否已有该能力", "搜过什么关键词", "看过哪些既有实现", "为什么不能复用")
    errors = [f"{path} 缺少已填写的 {field}" for field in fields
              if not re.search(rf"{field}：\S.+", text)]
    if re.search(r"<[^>]+>|待填写|待补充", text):
        errors.append(f"{path} 仍有模板占位符")
    return errors


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=root, text=True).strip()


def validate_record(record: dict, document: str, branch: str) -> list[str]:
    errors = []
    number = record.get("issue")
    kind = record.get("type")
    if type(number) is not int or number <= 0 or kind not in TYPES:
        errors.append("准备记录必须包含真实 Issue 正整数和一个有效 type")
    if record.get("branch") != branch or not re.fullmatch(rf"codex/issue-{number}-[a-z0-9]+(?:-[a-z0-9]+)*", branch):
        errors.append("工作分支必须与准备记录一致：codex/issue-<Issue号>-<描述>")
    if record.get("status") not in {"ready", "implementing", "complete"}:
        errors.append("准备状态必须为 ready、implementing 或 complete")
    for section in SECTIONS:
        match = re.search(rf"(?m)^## {re.escape(section)}[ \t]*\n([^#]+)", document)
        if not match or not match[1].strip():
            errors.append(f"准备文档缺少已填写章节：{section}")
    if set(re.findall(r"type/(feature|bug|chore|docs|spike|refactor)\b", document)) != {kind}:
        errors.append("准备文档必须且只能声明与记录一致的 type/*")
    if branch not in document or f"/issues/{number}" not in document:
        errors.append("准备文档须包含真实 Issue 链接与唯一分支")
    if not re.search(r"(?m)^- \[[ xX]\] .+", document):
        errors.append("准备文档缺少可核验的验收条目")
    if not re.search(r"(?m)^\|[^\n]+\|", document):
        errors.append("准备文档缺少模块拆解表")
    for field in ("自动验证", "人工验证", "埋点与可观测性", "发布与回滚"):
        if not re.search(rf"{field}：\S.+", document):
            errors.append(f"验证计划缺少：{field}")
    if kind == "bug":
        for field in ("现象", "根因", "影响面", "回归"):
            if not re.search(rf"(?m)^- {field}：\S.+", document):
                errors.append(f"Bug 缺少四行根因：{field}")
    elif kind in {"chore", "docs"} and "N/A — 当前类型不需要设计" not in document:
        errors.append("维护/文档须标记 N/A — 当前类型不需要设计")
    if re.search(r"<[^>]+>|待填写|待补充", document):
        errors.append("准备文档仍有模板占位符")
    return errors


def check_preparation(root: Path, base: str | None = None, branch: str | None = None,
                      github: bool = False) -> list[str]:
    branch = branch or git(root, "branch", "--show-current")
    if branch.startswith("codex/release-"):
        # The exact generated release tree is checked by check-project-update.
        return [] if base else ["版本 PR 必须提供 main 基准"]
    if branch in {"main", ""} and base is None:
        # Release builds validate a clean, already-reviewed main/tag checkout.
        return [] if not git(root, "status", "--porcelain") else ["main 上有未提交修改，请使用 Issue 工作分支"]
    match = re.fullmatch(r"codex/issue-(\d+)-[a-z0-9]+(?:-[a-z0-9]+)*", branch)
    if not match:
        return ["普通工作分支必须为 codex/issue-<Issue号>-<描述>"]
    number = int(match[1])
    path = f"docs/issues/issue-{number}.json"
    try:
        record = json.loads((root / path).read_text())
        document_path = record["document"]
        document_file = root / document_path
        if not re.fullmatch(r"docs/issues/[a-z0-9-]+\.md", document_path):
            raise ValueError("准备文档必须位于 docs/issues/ 下")
        document = document_file.read_text()
    except (OSError, ValueError, KeyError, TypeError) as error:
        return [f"缺少有效准备记录 {path}：{error}"]
    errors = validate_record(record, document, branch)
    materials = {path, document_path}
    kind = record.get("type")
    if kind in {"feature", "refactor", "spike"}:
        key, directory = ("research", "docs/research") if kind == "spike" else ("design", "docs/design")
        target = record.get(key)
        if not isinstance(target, str) or not re.fullmatch(rf"{directory}/[a-z0-9-]+\.md", target):
            errors.append(f"type/{kind} 须关联 {directory} 中的 {key} 文档")
        else:
            materials.add(target)
            try:
                text = (root / target).read_text()
                errors += validate_material(kind, text, target)
            except OSError as error:
                errors.append(f"缺少准备材料：{error}")
    for other in (root / "docs/issues").glob("issue-*.json"):
        try:
            data = json.loads(other.read_text())
            if other.name != Path(path).name and data.get("branch") == branch:
                errors.append(f"同一分支关联了其他 Issue：{other.name}")
            if other.name != Path(path).name and data.get("issue") == number:
                errors.append(f"同一 Issue 存在第二条准备记录：{other.name}")
        except (ValueError, OSError):
            errors.append(f"准备记录无法解析：{other.name}")

    base = base or "origin/main"
    ancestor = git(root, "merge-base", base, "HEAD")
    commits = git(root, "rev-list", "--reverse", "--first-parent", f"{ancestor}..HEAD").splitlines()
    prepared = False
    for commit in commits:
        changed = set(git(root, "diff-tree", "--no-commit-id", "--name-only", "-r", commit).splitlines())
        if not prepared and path in changed:
            if changed - materials:
                errors.append("准备记录必须在独立准备提交中先于实施产物落地")
            try:
                initial = json.loads(git(root, "show", f"{commit}:{path}"))
                initial_doc = git(root, "show", f"{commit}:{document_path}")
                errors += [f"准备提交未通过：{error}" for error in validate_record(initial, initial_doc, branch)]
                for material in materials:
                    git(root, "cat-file", "-e", f"{commit}:{material}")
                if kind in {"feature", "refactor", "spike"}:
                    target = record.get("research" if kind == "spike" else "design")
                    if target in materials:
                        errors += validate_material(kind, git(root, "show", f"{commit}:{target}"), target)
            except (ValueError, subprocess.CalledProcessError) as error:
                errors.append(f"准备提交材料不完整：{error}")
            prepared = True
        elif not prepared and changed - materials:
            errors.append("存在早于准备提交的实施产物")
    if not prepared:
        errors.append("尚无独立准备提交；先提交 Issue 记录和所需材料，再实施")
    if github:
        repository = os.environ["GITHUB_REPOSITORY"]
        issue = json.loads(subprocess.check_output(
            ["gh", "api", f"repos/{repository}/issues/{number}"], text=True))
        if "pull_request" in issue or branch not in (issue.get("body") or ""):
            errors.append("远程 Issue 不存在或未记录此唯一工作分支")
        if set(re.findall(r"type/(feature|bug|chore|docs|spike|refactor)\b", issue.get("body") or "")) != {kind}:
            errors.append("远程 Issue 类型与准备记录不一致")
        pages = json.loads(subprocess.check_output(
            ["gh", "api", "--paginate", "--slurp", f"repos/{repository}/pulls?state=open&per_page=100"], text=True))
        pulls = [pull for page in pages for pull in page]
        associated = False
        for pull in pulls:
            if re.search(rf"(?i)(?:closes|fixes|resolves)\s+#{number}\b", pull.get("body") or ""):
                if pull["head"]["ref"] != branch:
                    errors.append("此 Issue 已有其他工作分支的开放 PR")
                elif path in (pull.get("body") or ""):
                    associated = True
        if not associated:
            errors.append("PR 正文须关联本 Issue（Closes #编号）及准备 JSON 路径")
    return errors


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base")
    parser.add_argument("--branch", default=os.environ.get("PR_BRANCH"))
    parser.add_argument("--github", action="store_true")
    args = parser.parse_args()
    try:
        errors = check_preparation(Path(__file__).resolve().parent.parent, args.base, args.branch, args.github)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        errors = [f"准备门禁无法完成：{error}"]
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        sys.exit(1)
    print("准备门禁通过：Issue、类型、唯一分支、准备材料和提交顺序有效。")
