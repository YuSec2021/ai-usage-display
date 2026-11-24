# 032：macOS/Windows 用量统计共享 fixture 与一致性测试

- 日期：2026-11-24
- 类型：refactor
- 关联 Issue：[#39](https://github.com/YuSec2021/ai-usage-display/issues/39)
- 准备记录：`docs/issues/issue-39.json`、`docs/issues/issue-39-shared-usage-fixtures.md`、`docs/design/issue-39-shared-usage-fixtures.md`
- 版本变更：否（保持 `1.2.9`，Build `13`，由合并至 `main` 后的自动版本 PR 处理升版）

## 问题与结果

- **问题**：macOS（Swift，`Sources/AIUsage/Providers`）与 Windows（C#，`windows/AIUsage.Core`）分别维护独立的 Codex、Claude Code、Kimi Code 用量解析实现，此前各自使用内联单元测试样本，缺少共享匿名 fixture 与统一预期文件，存在统计口径漂移风险。
- **结果**：在 `Tests/Fixtures/shared/` 下建立 3 个 Provider 共 15 组匿名共享用例及 `expected.json`，双端测试（`make test` 与 `make windows-test`）自动遍历同一批输入并按统一归一化规则与 `platformExemptions` 校验一致性；源码审计发现的两端差异（D1–D10）均已写入设计文档。

## 实现范围

- **共享 fixture 资产（`Tests/Fixtures/shared/`）**：覆盖 `codex`、`claude`、`kimi`，每个 Provider 包含 5 个完全匿名合成用例（正常累计、重复/增量去重、畸形行容错、7 天窗口截断、额度窗口解析），输入目录保持各 Provider 真实布局。
- **最小可测试性注入**：
  - Swift `CodexUsageProvider` 与 `KimiUsageProvider` 增加默认值为 `Date.init` 的可选 `now` 参数（与 `ClaudeUsageProvider` 对齐），不改变生产行为。
  - C# `LogUsageProvider` 增加默认值为 `TimeZoneInfo.Local` 的可选 `timeZone` 参数，支持固定时区日桶测试。
- **双端测试 harness**：
  - macOS：新增 `Tests/AIUsageTests/SharedFixtureTests.swift`，并通过 `make generate` 同步 `AIUsage.xcodeproj/project.pbxproj`。
  - Windows Core：新增 `windows/AIUsage.Core.Tests/SharedFixtureTests.cs`，更新 `windows/AIUsage.Core.Tests/AIUsage.Core.Tests.csproj` 复制共享 fixture 至测试输出目录。
- **文档与流程同步**：更新 `SettingsView.swift` About 版本说明、`docs/changelog/README.md`、`CHANGELOG.md`、`docs/DEVELOPMENT.md` 与 `docs/windows/README.md`。

## 验证记录

- 已通过：`make check-prepare`（独立准备提交门禁通过）。
- 已通过：`make verify` 与 `make verify BASE_REF=origin/main`（含 `make check-process`、WorkflowTests、全量 Swift 测试含 15 组共享 fixture 一致性测试，以及构建后版本校验 `1.2.9`）。
- 已通过：`make windows-test`（共 34 项 .NET 核心测试全部通过，含 15 组共享 fixture 用例与目录完整性检查，并额外在 `TZ=Asia/Tokyo` 下复核时区无关性）。

## 未验证项

- 本次重构不涉及 UI 改动、macOS/Windows 实机界面交互、真实在线额度刷新（Codex CLI / Claude status line / Kimi API）及 Windows 原生 WinUI 3 GUI 构建；相关项留待 CI 或后续专项验证。
