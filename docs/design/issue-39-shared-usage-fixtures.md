# macOS/Windows 用量统计共享 fixture 与一致性测试：模块设计

## 1. 基本信息

- ISSUE：https://github.com/YuSec2021/ai-usage-display/issues/39
- 状态：已确认
- 负责人：AI Usage 维护者
- 更新日期：2026-11-24

## 2. 背景与目标

### 背景

AI Usage 在 macOS（Swift，`Sources/AIUsage/Providers/`）与 Windows（C#，`windows/AIUsage.Core/`）分别维护了两套独立的本地日志解析与额度提取实现。两套代码共享相同的产品语义，但目前各自的单元测试均为内联构造的孤立样本，缺乏共同的测试数据基线。当任一端调整去重策略、缓存 Token 口径、窗口截断边界或额度解析逻辑时，另一端不会收到回归提示，极易产生统计漂移。

### 目标

- 建立位于 `Tests/Fixtures/shared/{provider}/{case}/` 的跨平台共享匿名 fixture 资产，覆盖双端共有的 `codex`、`claude`、`kimi` 三个 Provider。
- 定义版本化的 `expected.json` 契约与跨平台归一化对比规则，使 Swift XCTest 与 C# xUnit 可针对完全相同的输入与预期执行一致性断言。
- 完整盘点两端 Codex / Claude / Kimi 实现的既有行为差异，区分“规则归一化”、“统一修复（D1、D2）”、“可选平台豁免（`platformExemptions`）”与“最小化可测试性补齐”。
- 范围扩展（已确认）：统一修复已暴露的 D1（macOS Codex/Claude/Kimi 7 天历史截断边界对齐为 `today-6 ~ today` 共 7 个自然日）与 D2（Windows Claude `Cached` 统一计入 `cache_read_input_tokens + cache_creation_input_tokens`），移除全部 4 处 `platformExemptions`，实现 15/15 共享 fixture 零豁免通过。
- 确保每个 Provider 至少覆盖 5 类典型场景：正常累计、重复/增量去重、畸形行容错、7 天窗口截断、额度窗口解析。

### 非目标

- 不合并两端代码实现，不引入跨语言共享库或 FFI。
- 不在 Windows 端补齐 MiniMax、Antigravity、Grok Provider。
- 不引入任何真实用户日志、真实路径、会话正文或 API 凭证。
- 不调整 macOS / Windows 既有 UI 或发布流水线。

## 3. 现状与约束

- 必须遵守的 ADR / 规范：`AGENTS.md`、`docs/ARCHITECTURE.md`（安全边界与可测试性第 10–11 节）、`docs/DEVELOPMENT.md`（标准化开发流程与测试规范）。
- 外部依赖与权限：无新增第三方依赖；Swift 端继续使用 Foundation + XCTest，C# 端继续使用 `System.Text.Json` + xUnit，均可在离线本地环境运行 `make test` 与 `make windows-test`。

## 4. 复用声明

- 仓库是否已有该能力：部分已有。macOS 端已有 `Tests/AIUsageTests/ProviderTests.swift` 等内联构造临时目录的 Provider 测试，Windows 端已有 `windows/AIUsage.Core.Tests/UsageTests.cs` 的内联临时目录测试，但仓库尚不存在 `Tests/Fixtures/` 目录，也不存在跨平台共享 fixture 文件与统一 `expected.json` 契约。
- 搜过什么关键词：`Fixtures`、`fixture`、`CodexUsageProvider`、`ClaudeUsageProvider`、`KimiUsageProvider`、`LogUsageProvider`、`QuotaParsers`。
- 看过哪些既有实现：`Sources/AIUsage/Providers/CodexUsageProvider.swift`、`Sources/AIUsage/Providers/ClaudeUsageProvider.swift`、`Sources/AIUsage/Providers/KimiUsageProvider.swift`、`Sources/AIUsage/Services/KimiUsageAPI.swift`、`Sources/AIUsage/Models/UsageModels.swift`、`Tests/AIUsageTests/ProviderTests.swift`、`windows/AIUsage.Core/LogUsageProvider.cs`、`windows/AIUsage.Core/QuotaParsers.cs`、`windows/AIUsage.Core/UsageModels.cs`、`windows/AIUsage.Core/JsonlReader.cs`、`windows/AIUsage.Core.Tests/UsageTests.cs`。
- 为什么不能复用：既有两套单元测试均将测试数据硬编码在各自语言源码字符串中，使用各自的动态 `Date()` / `DateTimeOffset.UtcNow` 与本机时区，无法被另一端直接读取和交叉校验；本设计复用了两端既有的 Provider 与 Parser 生产入口（`CodexUsageProvider`、`ClaudeUsageProvider`、`KimiUsageProvider`、`KimiUsageAPI.decode`、`LogUsageProvider`、`QuotaParsers.Kimi`），仅新增共享 fixture 文件目录与两端的轻量测试加载器。

## 5. 方案

### 核心流程

1. **目录发现**：Swift 与 C# 测试 harness 从仓库根目录定位 `Tests/Fixtures/shared/`，遍历 `{provider}/{case}/expected.json`。
2. **隔离准备**：为每个用例创建独立临时工作目录，将 `{case}/input/` 完整复制到临时目录，并将所有复制文件的修改时间统一设为 `expected.json` 中的固定 `now`（避免宿主当前时间远晚于 fixture 固定 `now` 时触发文件修改时间过滤差异）。
3. **Provider 调用**：
   - **Codex**：将临时 `input/` 作为 `rootDirectory` / `directory` 传入 `CodexUsageProvider`（Swift）与 `LogUsageProvider(ProviderId.Codex, ...)`（C#），注入固定 `now` 与 `timeZone`（UTC），不调用真实外部 CLI。
   - **Claude**：将临时 `input/` 作为 `claudeDirectory` / `directory`；若用例目录存在 `claude-snapshot.json`，复制到临时路径并作为 `snapshotURL` / `snapshotPath` 传入；Swift 端 `planUsageURL` 指向不存在的临时路径以隔离本机 Desktop 历史；注入固定 `now` 与 `timeZone`。
   - **Kimi**：将临时 `input/` 作为 `rootDirectory` / `directory`；Swift 端 `desktopLogURLs` 传空数组以隔离本机 Desktop 日志；若用例目录存在 `kimi-usage-api.json`，Swift 端通过 `rateLimitLoader` 返回 `KimiUsageAPI.decode(data, observedAt: now)`，C# 端通过 `liveReader` 返回 `QuotaParsers.Kimi(doc.RootElement)`；注入固定 `now` 与 `timeZone`。
4. **结果归一化与断言**：将两端的每日 Token 列表、额度窗口列表与状态映射为规范结构，应用 `platformExemptions`（若存在且针对当前平台），按既定容差执行逐项断言。

### 接口与数据

#### 1. Fixture 目录结构

```text
Tests/Fixtures/shared/
├── codex/
│   ├── normal-accumulation/
│   │   ├── input/
│   │   │   └── sessions/2026/06/session-001.jsonl
│   │   └── expected.json
│   ├── incremental-dedup/
│   ├── malformed-lines/
│   ├── window-cutoff/
│   └── quota-windows/
├── claude/
│   ├── normal-accumulation/
│   │   ├── input/
│   │   │   └── projects/sample-project/session-001.jsonl
│   │   └── expected.json
│   ├── message-dedup/
│   ├── malformed-lines/
│   ├── window-cutoff/
│   └── quota-windows/
│       ├── input/
│       │   └── projects/sample-project/session-001.jsonl
│       ├── claude-snapshot.json
│       └── expected.json
└── kimi/
    ├── normal-accumulation/
    │   ├── input/
    │   │   └── sessions/session-001/agents/main/wire.jsonl
    │   └── expected.json
    ├── legacy-message-dedup/
    ├── malformed-lines/
    ├── window-cutoff/
    └── quota-windows/
        ├── input/
        │   └── sessions/session-001/agents/main/wire.jsonl
        ├── kimi-usage-api.json
        └── expected.json
```

说明：
- `input/` 严格保持各 Provider 的真实目录层级（Codex 为 `sessions/**/*.jsonl` 及可选 `archived_sessions/*.jsonl`；Claude 为 `projects/**/*.jsonl`；Kimi 为 `sessions/**/wire.jsonl`）。
- 不属于 Provider 数据目录内部的附属输入（`claude-snapshot.json`、`kimi-usage-api.json`）放在 `{case}/` 根目录，与 `expected.json` 同级。
- 所有文件内容完全匿名合成：项目名统一使用 `sample-project` 等占位名，会话/消息 ID 使用 `session-001` / `msg-001`，不包含真实路径、用户名、提示词或凭证。

#### 2. `expected.json` Schema

```json
{
  "schemaVersion": 1,
  "provider": "codex",
  "case": "normal-accumulation",
  "description": "简要说明该用例验证的行为",
  "now": "2026-06-15T12:00:00Z",
  "timeZone": "UTC",
  "dailyUsage": [
    {
      "date": "2026-06-14",
      "tokens": {
        "input": 100,
        "cached": 20,
        "output": 10
      }
    }
  ],
  "quotaWindows": [
    {
      "minutes": 300,
      "usedPercent": 42.5,
      "resetsAt": "2026-06-15T15:00:00Z"
    }
  ],
  "state": "ready",
  "platformExemptions": {
    "windows": {
      "reason": "必须说明已知差异及原因",
      "dailyUsage": [],
      "quotaWindows": [],
      "state": "ready"
    }
  }
}
```

字段约束：
- `schemaVersion`：整数，当前固定为 `1`。
- `provider`：`"codex"` | `"claude"` | `"kimi"`。
- `case`：与目录名一致的短横线标识。
- `now`：固定评估时间点，ISO 8601 UTC 字符串。
- `timeZone`：固定 IANA 时区标识，统一使用 `"UTC"`。
- `dailyUsage`：按 `date`（`YYYY-MM-DD`）升序排列；`tokens` 包含 `input`（含缓存子集的总输入）、`cached`（缓存子集）、`output`。
- `quotaWindows`：每项包含 `minutes`（整数或 `null`）、`usedPercent`（0–100 浮点数）、`resetsAt`（ISO 8601 UTC 字符串或 `null`）。
- `state`：归一化状态，取值 `"ready"` | `"stale"` | `"waiting"` | `"missing"` | `"integrationRequired"` | `"unsupportedFormat"`。
- `platformExemptions`：可选对象，键为 `"macos"` 或 `"windows"`。每个豁免对象必须包含非空 `reason`，并可按需覆盖 `dailyUsage`、`quotaWindows`、`state` 中存在差异的字段；未覆盖的字段仍沿用顶层预期。

#### 3. 两端归一化与对比规则

- **时区与日期**：Swift 使用 `Calendar(identifier: .gregorian)` 并设置 `timeZone = TimeZone(identifier: expected.timeZone)!`；C# 使用 `TimeZoneInfo.FindSystemTimeZoneById(expected.timeZone)`。每日汇总统一转换为 `YYYY-MM-DD` 并按日期升序对比。
- **Token 数值**：`input`、`cached`、`output` 严格整数相等（容差为 `0`）。Swift 独有的 `reasoningOutput` 不纳入跨平台对比。
- **额度窗口**：两端输出先按 `(minutes ?? Int.MaxValue, usedPercent)` 升序排序后再逐项对比：
  - `minutes`：严格相等；C# 端 `0` 视为无时长，等价于 `null`。
  - `usedPercent`：绝对误差 `≤ 0.01`（吸收浮点除法舍入）。
  - `resetsAt`：同为 `null` 视为相等；均非空时时间差绝对值 `≤ 1.0` 秒（吸收 C# Unix 秒整数截断）。
- **状态映射**：
  - Swift `ProviderAvailability`：`.ready` 映射为 `"ready"`，`.stale` 映射为 `"stale"`，`.waitingForFirstSample` 映射为 `"waiting"`，`.cliNotInstalled` 映射为 `"missing"`，`.integrationNotInstalled` 映射为 `"integrationRequired"`，`.unsupportedFormat` 映射为 `"unsupportedFormat"`。
  - C# `SourceState`：`Ready` 映射为 `"ready"`，`Stale` 映射为 `"stale"`，`Waiting` 映射为 `"waiting"`，`Missing` 映射为 `"missing"`，`IntegrationRequired` 映射为 `"integrationRequired"`，`Unsupported` 映射为 `"unsupportedFormat"`。
- **生产代码最小可测试性补齐**：
  - Swift `CodexUsageProvider.init` 与 `KimiUsageProvider.init` 增加可选参数 `now: @escaping @Sendable () -> Date = Date.init`（与 `ClaudeUsageProvider` 保持一致），将内部 `Date()` 调用替换为 `now()`。
  - C# `LogUsageProvider` 构造函数增加可选参数 `TimeZoneInfo? timeZone = null`（默认 `TimeZoneInfo.Local`），将 `now.LocalDateTime` 与 `date.Value.LocalDateTime` 替换为 `TimeZoneInfo.ConvertTime(..., timeZone)`。

#### 4. 两端已知行为差异表（基于源码审计）

| 编号 | Provider | 差异项 | macOS（Swift）行为 | Windows（C#）行为 | 本次处理策略 |
|---|---|---|---|---|---|
| D1 | 全部 | 7 天历史窗口截断边界 | 原实现为 `startOfDay(now) - 7天`（保留 8 个自然日）；**已统一修改为 `startOfDay(now) - 6天`（保留 `today-6` 至 `today` 共 7 个自然日）** | `cutoff = DateOnly(now) - 6天`，保留 `today-6` 至 `today` 共 7 个自然日（`LogUsageProvider.cs:37`） | **已统一修复（范围扩展）**：修改 macOS 端 Codex / Claude / Kimi 截断边界对齐 Windows 与「7 天历史」语义；移除 3 个 `window-cutoff` 用例的 `platformExemptions.macos`，零豁免通过 |
| D2 | Claude | `cached` 字段统计口径 | `cachedInput = cache_creation_input_tokens + cache_read_input_tokens`（`ClaudeUsageProvider.swift:423`） | 原实现仅统计 `cache_read_input_tokens`；**已统一修改为 `cache_read_input_tokens + cache_creation_input_tokens`**（`QuotaParsers.cs`），与 macOS 及 Windows Kimi 口径一致 | **已统一修复（范围扩展）**：修改 Windows 端 `QuotaParsers.Tokens` 对 Claude 的 `Cached` 计算逻辑；移除 `claude/normal-accumulation` 的 `platformExemptions.windows`，零豁免通过 |
| D3 | Claude | 无 `message.id` 或顶层 `usage` / `metrics/costs.jsonl` | 支持无 `message.id` 的匿名累计，支持顶层 `usage` 与 `metrics/costs.jsonl` 取大值 | 仅读取带 `message.id` 的 `message.usage`，忽略匿名记录与 `metrics/costs.jsonl`（`LogUsageProvider.cs:139-142`） | 共享 fixture 的 Claude transcript 统一携带 `message.id` 与 `message.usage`；macOS 扩展路径继续由 `ProviderTests.swift` 单独覆盖 |
| D4 | Claude | 跨文件 `message.id` 去重 | 跨所有 transcript 文件全局去重（`seenMessages`） | 单文件内按 `message.id` 去重（`state.Messages`） | 共享 `message-dedup` 用例聚焦单文件内重复/更新 `message.id`；跨文件行为记入差异表 |
| D5 | Claude | 已过期额度窗口过滤时机 | `load()` 内过滤 `expiresAt ≤ now`，全部过期时直接返回空窗口与 `.stale`（`ClaudeUsageProvider.swift:87,98`） | `LoadAsync` 原样保留 `Snapshot.Windows`，由 `FiveHour(now)` / `IsStale(now)` 判定过期 | 共享 `quota-windows` 用例使用未过期窗口验证双端解析一致性；过期语义由两端既有单测分别覆盖 |
| D6 | Kimi | Unix 毫秒级数字时间戳 | `date(from:)` 自动识别大于 `1e11` 的毫秒时间戳、秒时间戳与 ISO 8601（`KimiUsageProvider.swift:416`） | `JsonFields.Timestamp()` 仅支持 Unix 秒（`≤ 253402300799`）与 ISO 8601，毫秒数字会返回 `null` 并丢弃整行（`QuotaParsers.cs:30`） | 共享 fixture 统一使用 ISO 8601 或 Unix 秒时间戳以验证核心累计；毫秒时间戳差异记入差异表，供后续评估是否统一修复 |
| D7 | Kimi | 额度窗口数组顺序 | `KimiUsageProvider.load()` 先追加 `300`（5 小时）再追加 `10080`（每周） | `QuotaParsers.Kimi()` 先追加 `10080`（`usage`）再追加 `300`（`limits`） | 通过归一化规则按 `minutes` 升序排序后对比，不依赖返回顺序 |
| D8 | Codex | 跨目录同名文件去重 | `sessions/` 与 `archived_sessions/` 按完整路径分别读取 | 按文件名去重，保留最新修改文件（`LogUsageProvider.cs:50`） | 共享 fixture 内不同目录使用唯一文件名；跨目录同名策略记入差异表 |
| D9 | Codex / Kimi | 全畸形行文件（无任何有效记录）状态 | 返回 `.unsupportedFormat` | 返回 `Waiting` | 共享 `malformed-lines` 用例验证“畸形行与合法行混排时跳过畸形行且保留合法结果（`ready`）”，全畸形文件状态差异记入差异表 |
| D10 | Codex / Claude / Kimi | 平台独占数据源与字段 | macOS 额外支持 `reasoningOutput`、Claude Desktop `plan-usage-history.json`、Kimi Desktop `main.log` | Windows 不含上述字段或 Desktop 数据源 | 不纳入跨平台共享 fixture，由 macOS 端既有单测覆盖 |

### 受影响模块

| 模块 / 路径 | 修改内容 | 调用方或依赖 | 验证方式 |
|---|---|---|---|
| `Sources/AIUsage/Providers/CodexUsageProvider.swift` | 增加默认值为 `Date.init` 的 `now` 注入参数；将 7 天历史截断边界统一为 `today-6 ~ today`（D1） | `UsageStore`、`ProviderTests`、`SharedFixtureTests` | `make test` |
| `Sources/AIUsage/Providers/ClaudeUsageProvider.swift` | 将 7 天历史截断边界（含 transcript 与 metrics 等）统一为 `today-6 ~ today`（D1） | `UsageStore`、`ProviderTests`、`SharedFixtureTests` | `make test` |
| `Sources/AIUsage/Providers/KimiUsageProvider.swift` | 增加默认值为 `Date.init` 的 `now` 注入参数；将 7 天历史截断边界统一为 `today-6 ~ today`（D1） | `UsageStore`、`ProviderTests`、`SharedFixtureTests` | `make test` |
| `windows/AIUsage.Core/LogUsageProvider.cs` | 增加默认值为 `TimeZoneInfo.Local` 的 `timeZone` 注入参数 | `UsageMonitor`、`UsageTests`、`SharedFixtureTests` | `make windows-test` |
| `windows/AIUsage.Core/QuotaParsers.cs` | 将 Claude `Cached` 统计统一为 `cache_read_input_tokens + cache_creation_input_tokens`（D2） | `LogUsageProvider`、`UsageTests`、`SharedFixtureTests` | `make windows-test` |
| `Tests/Fixtures/shared/` | 新增 3 个 Provider 共 15 个匿名共享 fixture 与 `expected.json`（移除全部 4 处 `platformExemptions`，实现零豁免基线） | 双端 `SharedFixtureTests` | 双端测试自动遍历 |
| `Tests/AIUsageTests/SharedFixtureTests.swift` & `ProviderTests.swift` | 新增 Swift 共享 fixture 测试加载器与断言；同步更新受 D1 影响的既有单测与回归覆盖 | `CodexUsageProvider`、`ClaudeUsageProvider`、`KimiUsageProvider`、`KimiUsageAPI` | `make test` |
| `windows/AIUsage.Core.Tests/SharedFixtureTests.cs` & `UsageTests.cs` | 新增 C# 共享 fixture 测试加载器与断言；同步更新受 D2 影响的既有单测与回归覆盖 | `LogUsageProvider`、`QuotaParsers` | `make windows-test` |
| `Sources/AIUsage/Views/SettingsView.swift`、`docs/changelog/`、`CHANGELOG.md`、`docs/windows/README.md`、`docs/DEVELOPMENT.md` | 更新 About 说明、变更记录与开发文档 | 项目更新流程检查 | `make verify` |

## 6. 异常、安全与兼容性

- 失败处理：fixture 解析或目录缺失时测试应立即失败并输出具体路径与字段差异，禁止静默跳过用例。
- 安全与隐私：所有 fixture 为 100% 匿名合成样本，不包含真实用户路径、用户名、会话内容、API Key 或真实日志片段；测试在隔离临时目录执行，绝不接触用户真实 `~/.codex`、`~/.claude`、`~/.kimi-code` 目录。
- 兼容与迁移：时钟/时区参数均带默认值，对所有既有调用方完全向后兼容；D1 修正后 macOS Codex/Claude/Kimi 的 7 天历史统计由 8 个自然日收敛为 7 个自然日（`today-6 ~ today`），D2 修正后 Windows Claude `Cached` 包含 `cache_creation_input_tokens`（与 `Input` 子集口径及 macOS/Kimi 一致），无配置文件或持久化数据迁移影响。

## 7. 可观测性与埋点

不涉及运行时埋点或遥测变更；测试层面通过清晰的断言消息输出 `{provider}/{case}` 名称、预期值、实际值及生效的 `platformExemptions` 原因。

## 8. 验证与发布

- 自动验证：`make check-prepare`、`make verify`（含 `make check-process`、全量 Swift 单元测试与版本校验）、`make windows-test`（含全量 C# xUnit 测试）。
- 人工验证：审查全部 fixture 内容确保完全匿名，核对已知差异表与 `platformExemptions` 一致性；本任务不涉及 UI 改动与真实在线额度拉取，将在变更记录中如实注明未验证范围。
- 发布与回滚：通过普通 PR 合入 `main`，由既有 `Automatic release` 工作流处理版本发布；开发分支不手动升版。回滚只需撤销对应 PR 提交。

## 9. 待决策项

- N/A — 无待决策项。
