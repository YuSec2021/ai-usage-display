# 035：修复自动版本 PR 跨 Runner XcodeGen 发布契约失败

- 日期：2026-11-27
- 类型：bugfix
- 关联 Issue：[#45](https://github.com/YuSec2021/ai-usage-display/issues/45)
- 准备记录：`docs/issues/issue-45.json`、`docs/issues/issue-45-release-contract-xcodegen.md`

## 变更说明

- **发布契约兼容跨版本 XcodeGen 元数据（`scripts/release-contract.py`）**：将 `AIUsage.xcodeproj/xcshareddata/xcschemes/AIUsage.xcscheme` 纳入生成工程白名单，并对 `project.pbxproj` 中的 `LastUpgradeCheck` 与 `AIUsage.xcscheme` 中的 `LastUpgradeVersion`、默认 `buildArchitectures = "Automatic"` 做最小化规范后再与重新生成的工程逐字比对，解决 `macos-15`/`macos-26`（`xcodegen 2.48.0`）与 `macos-15-intel`（`xcodegen 2.46.0`）输出不一致导致的双架构误报，同时继续严格拦截任何构建设置、Scheme 行为篡改或额外文件。
- **Tag 构建先验证后生成（`.github/workflows/release.yml`）**：在 `Build universal DMG` 作业中调整为先执行 `make verify` 再执行 `make generate`，避免后续 Homebrew XcodeGen 升级在 Tag 检出上弄脏工作区触发洁净检查误报。
- **回归测试（`Tests/WorkflowTests/test_release_contract.py`、`Tests/WorkflowTests/test_release_workflows.py`）**：新增伪 `xcodegen` 跨版本双向契约回归测试（覆盖 2.48.0/2.46.0 互验、篡改 `AIUsage.xcscheme`/`project.pbxproj` 与额外 `.xcscheme` 拦截）以及 `release.yml` 验证顺序契约测试。

## 验证记录

- 回归复现：新增回归用例在修复前复现失败（`版本 PR 含非版本产物：AIUsage.xcodeproj/xcshareddata/xcschemes/AIUsage.xcscheme` 与 `make verify` / `make generate` 顺序断言失败），修复后全部通过。
- 已通过：`make verify BASE_REF=origin/main` 与 `git diff --check`（以本 PR 执行结果及双架构/Windows CI 为准）。
- 未验证范围：本次仅调整发布契约脚本与 Release 工作流，未改动 macOS/Windows 应用 UI 或 Provider 采集，macOS 界面实机交互与真实在线额度刷新未复验；合入 `main` 后将通过新生成的 `v1.2.10` 自动版本 PR 实测验收双架构检查与双平台自动发布。
