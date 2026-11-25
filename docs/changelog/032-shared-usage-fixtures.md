# 032：macOS/Windows 用量统计共享 fixture 与一致性测试

- 日期：2026-11-24
- 类型：refactor
- 关联 Issue：[#39](https://github.com/YuSec2021/ai-usage-display/issues/39)
- 准备记录：`docs/issues/issue-39.json`、`docs/issues/issue-39-shared-usage-fixtures.md`、`docs/design/issue-39-shared-usage-fixtures.md`
- 版本变更：否（保持 `1.2.9`，Build `13`，由合并至 `main` 后的自动版本 PR 处理升版）

## 问题与结果

- **问题**：macOS（Swift，`Sources/AIUsage/Providers`）与 Windows（C#，`windows/AIUsage.Core`）分别维护独立的 Codex、Claude Code、Kimi Code 用量解析实现，此前各自使用内联单元测试样本，缺少共享匿名 fixture 与统一预期文件，且在 7 天历史截断边界（D1：macOS 保留 8 个自然日 vs Windows 保留 7 个自然日）与 Claude `cached` 统计口径（D2：Windows 未计入 `cache_creation_input_tokens`）存在实际漂移。
- **结果**：在 `Tests/Fixtures/shared/` 下建立 3 个 Provider 共 15 组匿名共享用例及 `expected.json`，并统一修复 D1（macOS Codex/Claude/Kimi 对齐为 `today-6 ~ today` 共 7 个自然日）与 D2（Windows Claude `Cached` 统一计入 `cache_read_input_tokens + cache_creation_input_tokens`）；移除全部 4 处 `platformExemptions`，双端测试（`make test` 与 `make windows-test`）15/15 共享 fixture 零豁免通过；其余非目标差异（D3–D10）均已记录在设计文档中。

## 实现范围

- **共享 fixture 资产（`Tests/Fixtures/shared/`）**：覆盖 `codex`、`claude`、`kimi`，每个 Provider 包含 5 个完全匿名合成用例（正常累计、重复/增量去重、畸形行容错、7 天窗口截断、额度窗口解析），输入目录保持各 Provider 真实布局，零 `platformExemptions`。
- **最小可测试性注入与 D1/D2 统一修复**：
  - macOS（Swift）：`CodexUsageProvider` 与 `KimiUsageProvider` 增加默认值为 `Date.init` 的可选 `now` 参数（与 `ClaudeUsageProvider` 对齐）；将 `CodexUsageProvider`、`ClaudeUsageProvider`（含 transcript 与 metrics）、`KimiUsageProvider` 的 7 天历史截断边界由 `startOfDay(now) - 7天` 统一修正为 `startOfDay(now) - 6天`（保留 `today-6 ~ today` 共 7 个自然日，D1）。
  - Windows（C#）：`LogUsageProvider` 增加默认值为 `TimeZoneInfo.Local` 的可选 `timeZone` 参数；将 `QuotaParsers.Tokens(usage, claude: true)` 的 `Cached` 统一修正为 `cache_read_input_tokens + cache_creation_input_tokens`（保持 `Input` 不重复累加且防溢出，D2）。
- **双端测试 harness 与回归更新**：
  - macOS：新增 `Tests/AIUsageTests/SharedFixtureTests.swift`，同步更新 `Tests/AIUsageTests/ProviderTests.swift` 中受 7 天截断边界影响的既有单测，并通过 `make generate` 同步 `AIUsage.xcodeproj/project.pbxproj`。
  - Windows Core：新增 `windows/AIUsage.Core.Tests/SharedFixtureTests.cs`，同步更新 `windows/AIUsage.Core.Tests/UsageTests.cs` 覆盖 Claude `cache_creation_input_tokens` 计入 `Cached`，并更新 `windows/AIUsage.Core.Tests/AIUsage.Core.Tests.csproj` 复制共享 fixture 至测试输出目录。
- **文档与流程同步**：更新 `docs/design/issue-39-shared-usage-fixtures.md`、`docs/issues/issue-39-shared-usage-fixtures.md`、`SettingsView.swift` About 版本说明、`docs/changelog/README.md`、`CHANGELOG.md`、`docs/DEVELOPMENT.md` 与 `docs/windows/README.md`。

## 验证记录

- 已通过：`make check-prepare`（独立准备提交门禁通过）。
- 已通过：`make verify BASE_REF=origin/main`（含 `make check-process`、WorkflowTests、全量 Swift 测试含 15/15 共享 fixture 零豁免通过，以及构建后版本校验 `1.2.9`）。
- 已通过：`make windows-test`（共 34 项 .NET 核心测试全部通过，含 15/15 共享 fixture 零豁免通过）。

## 未验证项

- 本次重构不涉及 UI 改动、macOS/Windows 实机界面交互、真实在线额度刷新（Codex CLI / Claude status line / Kimi API）及 Windows 原生 WinUI 3 GUI 构建；相关项留待 CI 或后续专项验证。
