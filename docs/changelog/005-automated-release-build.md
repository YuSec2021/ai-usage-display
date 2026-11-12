# 005：自动构建通用 Release 安装包

日期：2026-11-11

用户需要 GitHub Action 自动构建 Release 包。本次新增 `.github/workflows/release.yml`，将原 `verify-release-tag.yml` 的版本检查整合到完整发布流程。准备草稿见 `docs/issues/automated-release-build.md`，类型为 `type/chore`，无需模块设计；未创建外部 Issue 或工作分支。

流程支持推送版本 Tag 及手动指定已有 Tag，先校验 `vX.Y.Z` / `X.Y.Z` 格式，再明确检出 `refs/tags/<tag>`。构建使用 Xcode 26，运行版本检查和 `make verify` 后，复用原打包脚本构建 DMG；上传 Actions Artifact，并由依赖构建成功的独立发布任务复核 SHA-256、创建或更新对应 GitHub Release 及附件。只有发布任务具有 `contents: write`，无需额外 PAT。

打包脚本接受明确 Tag，避免多个 Tag 共用提交时自动探测到错误版本；显式构建 `arm64 x86_64` 并用 `lipo` 验证，保留临时签名和 DMG/SHA-256 流程。新增版本回归测试覆盖带/不带 v 前缀、Tag 不符、构建 App 版本不符和 About 版本来源缺失。About 增加“下载最新版本”入口，README、开发文档、变更摘要和索引同步。

验证：

- `actionlint v1.7.12` 校验 Release 与 PR 工作流通过，Zsh 语法及 `git diff --check` 通过。
- 实际输入校验脚本的正反例，以及 Tag 检出、发布依赖、最小权限检查通过；显式传入不符版本会在构建前拒绝打包。
- `make verify` 通过：9 项流程测试、40 项 Swift 测试及构建后版本检查通过。
- 本地执行 `./scripts/build-direct-release.sh 1.2.1` 完成通用 Release 构建、临时签名及 DMG 创建；`lipo` 确认 `x86_64 arm64`，`hdiutil verify` 和 SHA-256 验证通过。

远程 Actions 执行、附件上传及干净机器安装尚未验证；此次只准备工作流，不推送 Tag 或实际发布。

版本与构建号仍为 1.2.1（Build 5）。本地检查包使用当前工作区，仅用于验证打包流程，不代表该版本已经重新发布。包为临时签名且未公证，发布说明会如实标注。
