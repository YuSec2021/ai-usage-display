# 自动构建 Release 安装包并上传 GitHub Release

## 基本信息

- 类型：`type/chore`
- 状态：已完成（本地实现与验证；远程工作流尚未执行）
- 工作分支：`chore/<issue号>-automated-release-build`（仅为草稿占位符，未创建分支；没有真实 Issue 编号）
- 负责人：当前项目维护者
- 设计或产出文档：N/A — 当前类型不需要设计；复用现有发布脚本与版本检查。

## 背景

当前 Tag Action 只验证版本并构建 App，没有产出可下载的安装包。仓库已有 `scripts/build-direct-release.sh`，可以构建、临时签名并生成 DMG 与 SHA-256，但未接入自动发布。用户要求增加 Action 自动构建 Release 包。

已阅读 `AGENTS.md`、`standard-dev-flow`、开发文档和现有工作流；本次没有适用的 ADR。已检索 `build-direct-release`、`verify-release-tag`、`verify-release-version`，追踪 Makefile、README 和 Actions 的调用，确定直接复用现有脚本，不新增打包实现。

## 目标

- 推送版本 Tag 后自动校验、测试、构建通用 DMG 并上传 Actions 产物及 GitHub Release 附件。
- 支持手动指定已有版本 Tag 重建，不接受任意分支作为发布来源。
- 明确包含 arm64 与 x86_64，并验证版本、签名和校验和。
- 将旧 Tag 校验合入发布流程，保留门禁并避免重复构建。

## 非目标

- 不在本次会话创建或推送 Tag，不实际向 GitHub 发布。
- 不配置 Developer ID、Apple 公证、Sparkle 或额外密钥。
- 不自动修改应用版本，不混入已有 Claude/UI 工作区变更的提交。

## 根因说明（仅 `type/bug`）

N/A — 当前类型不需要根因说明。

## 验收标准

- [x] Release Action 支持自动 Tag 触发与手动指定已有 Tag。
- [x] 发布依赖构建成功，版本不符或测试失败时不能上传 Release。
- [x] 打包脚本可接收明确的 Tag，通用包包含两个架构且校验和可验证。
- [x] 版本检查回归测试、工作流校验、本地打包与 `make verify` 通过。
- [x] About、README、开发文档、变更摘要与索引已同步，明确临时签名和远程未验证范围。

## 模块拆解

| 模块 / 路径 | 修改内容 | 依赖 | 完成条件 |
| --- | --- | --- | --- |
| `.github/workflows/release.yml` | Tag/手动触发、现有 Tag 检出、校验测试、构建和附件上传 | 现有版本与打包脚本 | 构建门禁通过后才执行发布 |
| `.github/workflows/verify-release-tag.yml` | 校验整合到新流程后移除重复任务 | 新 Release 工作流 | 原有版本校验能力保留 |
| `scripts/build-direct-release.sh`、`Tests/WorkflowTests/` | 接收明确 Tag、强制并验证双架构、版本回归测试 | 现有打包实现 | 本地安装包、签名与校验和验证通过 |
| About、README、开发文档、日志 | 说明触发方式、产物和真实验证结果 | 最终工作流 | 信息准确且通过项目流程检查 |

## 风险、假设与待决策项

- 风险：当前无 Apple Developer 凭证，产物为临时签名且未公证；发布说明须明确此状态。
- 假设：使用现有版本化 DMG 作为 Release 包，发布时同时保留 Actions Artifact。手动重跑相同 Tag 会更新对应 Release 的附件。
- 待决策：N/A — 准备本地工作流无需新的外部权限；远程实际执行留待工作流合入并推送有效版本 Tag 后验证。

## 验证计划

- 自动验证：Actions 语法校验、版本检查正反例、`make verify`、本地执行打包脚本、`lipo`、`codesign`、DMG 与 SHA-256 验证、`git diff --check`。
- 人工验证：核对 Tag、检出 ref、构建依赖与发布权限范围；远程上传不在本次执行。
- 埋点与可观测性：复用 Actions 日志和附件，不新增应用运行时埋点。
- 发布与回滚：工作流随仓库提交生效；回滚本次工作流与脚本差异即可，不修改已安装应用。

## 完成定义

- [x] 设计和拆解与最终实现一致。
- [x] 所有验收标准已完成，未验证项目已注明。
- [x] 必要测试、评测、构建和审查已通过。
- [x] 文档、埋点、迁移、发布及回滚事项已处理或明确标记不适用。

## 验证结果

- `actionlint v1.7.12` 校验 Release 和 PR 工作流通过，Zsh 语法与 `git diff --check` 通过。
- 对实际工作流中的输入校验脚本执行带/不带 v 前缀正例及分支名、预发布后缀、换行反例；明确 Tag 检出、构建依赖和权限检查通过。
- `make verify` 通过：9 项流程测试、40 项 Swift 测试及构建后版本检查通过。明确传入不符版本时，打包脚本在构建前拒绝。
- 本地运行 `./scripts/build-direct-release.sh 1.2.1` 成功；通用二进制包含 `x86_64 arm64`，临时签名、DMG 完整性和 SHA-256 验证通过。
- 远程 Actions、GitHub Release 上传和干净机器安装未执行；本地测试产物不是对现有 1.2.1 发布的更新。
