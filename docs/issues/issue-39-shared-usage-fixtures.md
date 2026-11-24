# macOS/Windows 用量统计共享 fixture 与一致性测试

## 基本信息

- Issue：https://github.com/YuSec2021/ai-usage-display/issues/39
- 类型：`type/refactor`
- 状态：待验收
- 工作分支：`codex/issue-39-shared-usage-fixtures`
- 负责人：AI Usage 维护者
- 设计或产出文档：`docs/design/issue-39-shared-usage-fixtures.md`

## 背景

macOS（Swift，`Sources/AIUsage/Providers`）与 Windows（C#，`windows/AIUsage.Core`）的用量统计是两套独立实现，目前各自使用内联构造的单元测试样本，缺乏跨平台共享的匿名 fixture 与统一预期文件。随着两套实现各自演进，Codex、Claude、Kimi 的解析、去重、时间窗口截断与额度提取规则已经出现细微差异与漂移风险。

## 目标

- 在 `Tests/Fixtures/shared/{provider}/{case}/` 下建立匿名、可复现的跨平台共享 fixture 集合与统一 `expected.json` 契约，覆盖 Codex、Claude、Kimi 三个双端共有 Provider。
- 每个 Provider 至少覆盖 5 类核心场景：正常累计、重复或增量去重、畸形行容错、7 天窗口截断、额度窗口解析。
- 在 macOS（`Tests/AIUsageTests`）与 Windows Core（`windows/AIUsage.Core.Tests`）各自新增共享 fixture 一致性测试 harness，读取同一批输入并对比同一份 `expected.json`，任何一端行为漂移即触发测试失败。
- 盘点并记录两端已知行为差异；在范围扩展中统一修复已暴露的 D1（macOS Codex/Claude/Kimi 7 天历史窗口截断边界对齐为 `today-6 ~ today` 共 7 个自然日）与 D2（Windows Claude `Cached` 统一计入 `cache_read_input_tokens + cache_creation_input_tokens`），移除全部 4 处 `platformExemptions`，实现 15/15 共享 fixture 零豁免通过。
- 保持最小、向后兼容的生产代码变更，不合并两端实现。

## 非目标

- 不合并 macOS 与 Windows 实现，不引入共享核心库或 FFI。
- 不在 Windows 端补齐 MiniMax、Antigravity、Grok 等仅 macOS 支持的 Provider。
- 不读取用户真实日志、会话正文、路径或任何凭证；所有 fixture 均为完全匿名合成数据。
- 不改变 macOS 或 Windows 的既有 UI 布局、发布流程或版本号。

## 根因说明

N/A — 当前类型为 `type/refactor`，不需要根因说明。

## 验收标准

- [x] `Tests/Fixtures/shared/` 包含 `codex`、`claude`、`kimi` 三个目录，每个目录至少包含 5 个匿名场景（正常累计、重复/增量去重、畸形行、7 天窗口截断、额度窗口），均附带符合 schema 的 `expected.json`。
- [x] `docs/design/issue-39-shared-usage-fixtures.md` 完整定义目录结构、`expected.json` schema、两端归一化与对比规则，以及基于源码审计的已知行为差异表。
- [x] 已完成 D1（macOS Codex/Claude/Kimi 7 天历史截断统一为 `today-6 ~ today`）与 D2（Windows Claude `Cached` 统一为 `cache_read_input_tokens + cache_creation_input_tokens`）修复，并移除全部 4 处 `platformExemptions`。
- [x] Swift 测试（`make test`）自动遍历 `Tests/Fixtures/shared/` 全部 15 个用例并零豁免断言通过。
- [x] C# 测试（`make windows-test`）自动遍历同一批 `Tests/Fixtures/shared/` 全部 15 个用例并零豁免断言通过。
- [x] `SettingsView.swift` About 说明、`docs/changelog/032-shared-usage-fixtures.md`、`docs/changelog/README.md`、`CHANGELOG.md` 已同步更新，`make verify` 与 `make windows-test` 全部通过。

## 模块拆解

| 模块 / 路径 | 修改内容 | 依赖 | 完成条件 |
|---|---|---|---|
| `docs/issues/issue-39*` & `docs/design/issue-39-shared-usage-fixtures.md` | 准备记录、Issue 文档、共享 fixture 契约设计、两端差异表及 D1/D2 范围扩展 | 无 | 独立提交并通过 `make check-prepare` |
| `Sources/AIUsage/Providers/CodexUsageProvider.swift`、`ClaudeUsageProvider.swift` & `KimiUsageProvider.swift` | 补充默认值为 `Date.init` 的可选 `now` 时钟参数（Codex/Kimi）；统一 7 天历史截断边界为 `today-6 ~ today`（D1） | 准备门禁 | `make test` 全量通过（含受影响既有单测更新） |
| `windows/AIUsage.Core/LogUsageProvider.cs` & `QuotaParsers.cs` | 补充默认值为 `TimeZoneInfo.Local` 的可选 `timeZone` 参数；将 Claude `Cached` 统一为 `cache_read_input_tokens + cache_creation_input_tokens`（D2） | 准备门禁 | `make windows-test` 全量通过（含受影响既有单测更新） |
| `Tests/Fixtures/shared/{codex,claude,kimi}/` | 编写 3 个 Provider 共 15 个匿名合成用例与 `expected.json`，并移除全部 4 处 `platformExemptions` | 准备门禁 | 输入布局与真实目录一致，不含任何真实数据或凭证，15/15 零豁免 |
| `Tests/AIUsageTests/SharedFixtureTests.swift` & `ProviderTests.swift` | 新增 Swift 共享 fixture 自动发现、隔离复制、归一化与断言测试；更新受 D1 影响的既有单测 | 共享 fixture + D1 修复 | `make test` 全量通过 |
| `windows/AIUsage.Core.Tests/SharedFixtureTests.cs` & `UsageTests.cs` | 新增 C# 共享 fixture 自动发现、隔离复制、归一化与断言测试；更新受 D2 影响的既有单测 | 共享 fixture + D2 修复 | `make windows-test` 全量通过 |
| `Sources/AIUsage/Views/SettingsView.swift`、`docs/changelog/`、`CHANGELOG.md`、`docs/windows/README.md`、`docs/DEVELOPMENT.md` | 同步 About 说明、变更记录与开发文档 | 双端测试通过 | `make verify` 与 `make windows-test` 通过 |

## 风险、假设与待决策项

- 风险：统一修复 D1（macOS 8 天→7 天历史截断）与 D2（Windows Claude `Cached` 含 `cache_creation_input_tokens`）会影响两端依赖旧口径的既有单元测试。缓解方式：两端同步检查并更新既有单测及回归验证；其余非目标差异（D3–D10）继续记录在设计文档差异表中，不越界修改。
- 假设：共享 fixture 的时间戳统一采用固定 `now` 与 `UTC` 时区，测试 harness 在运行前将临时目录内 fixture 文件的修改时间设置为 `now`，以消除宿主机器时区与系统时间差异。
- 待决策：N/A — D1、D2 统一修复方案已确认，无阻塞项。

## 验证计划

- 自动验证：运行 `make check-prepare` 校验准备门禁；实施完成后运行 `make verify`（含 `make check-process`、`Tests/WorkflowTests`、全量 Swift 测试含新增 `SharedFixtureTests` 及构建版本检查）与 `make windows-test`（含新增 C# `SharedFixtureTests`）。
- 人工验证：抽检 `Tests/Fixtures/shared/` 所有文件确认完全匿名、无真实路径/ID/凭证，核对 `platformExemptions` 理由与设计文档差异表一致；本任务不涉及 UI 改动与真实额度采集，将在变更记录中明确标注未执行 UI 与真实额度检查。
- 埋点与可观测性：不新增遥测或日志字段；测试失败时 harness 输出具体 Provider、Case 名、字段差异与豁免状态便于定位漂移。
- 发布与回滚：按受保护 `main` PR 流程合入，不手动升版；如需回滚可直接撤销本 PR 提交，不影响运行时配置与数据格式。

## 完成定义

- [ ] 设计和拆解与最终实现一致。
- [ ] 所有验收标准已完成。
- [ ] 必要测试、评测、构建和审查已通过。
- [ ] 文档、埋点、迁移、发布及回滚事项已处理或明确标记不适用。
