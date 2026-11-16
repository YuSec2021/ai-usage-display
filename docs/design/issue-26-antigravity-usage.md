# Google Antigravity 用量与多分组额度监控：模块设计

## 1. 基本信息

- ISSUE：https://github.com/YuSec2021/ai-usage-display/issues/26
- 状态：已确认
- 负责人：YuSec2021
- 更新日期：2026-11-16
- 唯一工作分支：codex/issue-26-antigravity-usage

## 2. 背景与目标

### 背景

AI Usage 目前支持 Codex、Claude Code、Kimi Code 与 MiniMax 四种模型的本地用量与额度展示，尚未接入 Google Antigravity（包含 Antigravity 2.0 桌面端与 Antigravity IDE）。Antigravity 在本地 `~/.gemini/antigravity`（及 `~/.gemini/antigravity-ide`）目录保存会话轨迹日志 `brain/*/ .system_generated/logs/transcript.jsonl`，并在运行期间通过 `daemon/hub_*.json` 或 `daemon/ls_*.json` 暴露本地回环 Language Server 的 `RetrieveUserQuotaSummary` 接口，返回 Gemini Models（5 小时与本周）、Gemini 4 Argon（本周）以及 Claude and GPT models（5 小时与本周）等多分组额度百分比与重置时间。

### 目标

- 新增 `ProviderID.antigravity`（展示名称 `Antigravity`，内置官方矢量图标 `AntigravityLogo`），支持菜单栏圆环、详情卡片拖拽排序、模型勾选迁移与最近 7 天本地 Token 历史图表。
- 新增 `AntigravityUsageProvider`，增量读取本地 `transcript.jsonl` 中的 `input_tokens`、`cache_read_tokens`、`cache_write_tokens` 与 `output_tokens`，按 `step_index` 去重聚合今日 Token 与最近 7 天日统计。
- 通过本地 `daemon/*.json` 发现运行中的 Antigravity Language Server，仅向本机 `127.0.0.1` 请求 `RetrieveUserQuotaSummary`，将 Gemini 5 小时额度映射为主圆环窗口，同时在卡片展示 Gemini 本周、Gemini 4 Argon 本周及 Claude/GPT 5 小时与本周等其他返回分组额度。
- 当 Language Server 未运行或额度接口暂不可用时，保留上次已获取的有效额度或回退为仅展示本地 Token，不读取或保存提示词、回答正文、思考内容或工具调用参数。

### 非目标

- N/A — 不读取 `transcript_full.jsonl` 或会话正文，不发起任何外部互联网请求，不修改 `~/.gemini/config/config.json` 或 Antigravity 自身配置。

## 3. 现状与约束

- 必须遵守的 ADR / 规范：遵循根目录 `AGENTS.md`、`docs/DEVELOPMENT.md` 与 `standard-dev-flow` 规范，开发分支不手动升版。
- 外部依赖与权限：无需新增第三方依赖或外部网络权限；仅读取本机 `~/.gemini/antigravity`、`~/.gemini/antigravity-ide` 及 `/Applications/Antigravity.app`，以及连接本机 `127.0.0.1` 回环端口。

## 4. 复用声明

- 仓库是否已有该能力：部分已有；仓库已有 `UsageProvider` 协议、`IncrementalLineReader` 增量行读取器、`ISODateParser` 日期解析器、`RateLimitWindow` 额度窗口模型与 `UsageRing` 圆环组件，但尚无 Google Antigravity 的目录探测、轨迹 Token 聚合与本地 Language Server 额度读取实现。
- 搜过什么关键词：ProviderID、UsageProvider、ProviderPaths、IncrementalLineReader、ISODateParser、fiveHourWindow、migrateProviderSelection、RetrieveUserQuotaSummary、transcript.jsonl。
- 看过哪些既有实现：Sources/AIUsage/Models/UsageModels.swift、Sources/AIUsage/Providers/UsageProvider.swift、Sources/AIUsage/Providers/CodexUsageProvider.swift、Sources/AIUsage/Providers/ClaudeUsageProvider.swift、Sources/AIUsage/Providers/KimiUsageProvider.swift、Sources/AIUsage/Providers/MiniMaxUsageProvider.swift、Sources/AIUsage/App/UsageStore.swift、Sources/AIUsage/Views/SettingsView.swift、Sources/AIUsage/Views/ProviderCard.swift、Tests/AIUsageTests/ProviderTests.swift。
- 为什么不能复用：直接复用 `IncrementalLineReader`、`ISODateParser`、`UsageSnapshot`、`RateLimitWindow` 与 `UsageStore` 调度框架；Antigravity 的 `transcript.jsonl` 字段结构（`step_index`、`created_at`、`input_tokens`、`cache_read_tokens`、`output_tokens`）与本地 Language Server ConnectRPC 额度摘要（`RetrieveUserQuotaSummary` 的 `groups`/`buckets`）属于新数据源，需新增独立的 `AntigravityUsageProvider`。

## 5. 方案

### 核心流程

1. 目录与安装检测：`ProviderPaths.antigravityDirectories` 检查 `~/.gemini/antigravity` 与 `~/.gemini/antigravity-ide`（可通过环境变量 `ANTIGRAVITY_HOME` 覆盖），同时辅助检查 `/Applications/Antigravity.app`。若目录与应用均不存在且无在线额度返回，状态为 `.cliNotInstalled`。
2. 本地 Token 增量解析：枚举各数据目录下 `brain/*/.system_generated/logs/transcript.jsonl`，使用 `IncrementalLineReader` 按文件尺寸与修改时间增量读取；仅解码白名单字段（`step_index`、`created_at`、`input_tokens`、`cache_read_tokens`、`cache_write_tokens`、`output_tokens`）。同一文件按 `step_index` 记录最新值防止重复计数，汇总最近 7 天 `DailyUsage` 与今日 `TokenUsage`（`input = input_tokens + cache_read_tokens + cache_write_tokens`）。
3. 本地 Language Server 额度读取：扫描 `daemon/` 下的 `hub_*.json` 与 `ls_*.json`，校验进程存活（`kill(pid, 0) == 0`）后提取 `httpPort` 与 `csrfToken`，向 `http://127.0.0.1:httpPort/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary` 发送 3 秒超时的只读 POST 请求。
4. 额度窗口映射：將 `remainingFraction`（0~1）转换为已用百分比 `(1 - remainingFraction) * 100`。主 5 小时窗口优先取 Gemini 分组的 5 小时桶（`bucketId == "gemini-5h"` 或首个 `window == "5h"` 桶，`kind: .short`、`durationMinutes: 300`）；其余桶（Gemini 本周、Gemini 4 Argon 本周、Claude/GPT 5 小时与本周等）生成带清晰中英文标签的附加 `RateLimitWindow` 在卡片列表展示。

### 接口与数据

- `ProviderID` 新增 `case antigravity`，展示名 `Antigravity`，配色采用 Google 蓝，图标资产 `AntigravityLogo`。
- `UsageStore` 新增 `antigravityProvider` 注入参数与默认偏好迁移 `migrateProviderSelectionForAntigravity()`，使旧版本默认全选用户升级后自动勾选 Antigravity。
- `RateLimitWindow.id` 包含 `kind`、`label` 与 `durationMinutes`，确保多分组的 5 小时与周额度窗口在卡片列表中拥有唯一标识且除主 5 小时窗口外全部在卡片展开展示。

### 受影响模块

| 模块 / 路径 | 修改内容 | 调用方或依赖 | 验证方式 |
|---|---|---|---|
| Sources/AIUsage/Models/UsageModels.swift | 新增 `ProviderID.antigravity`、配色与图标元数据 | MenuBarView、ProviderCard、SettingsView、HistoryView | 单元测试与编译检查 |
| Sources/AIUsage/Providers/UsageProvider.swift、AntigravityUsageProvider.swift | 新增 Antigravity 路径定义、本地 `transcript.jsonl` 增量聚合与 Language Server 额度摘要解析 | UsageStore | ProviderTests 隔离 fixture 单元测试 |
| Sources/AIUsage/App/UsageStore.swift | 注入 `antigravityProvider` 并迁移默认勾选列表 | AIUsageApp、UsageStoreTests | UsageStoreTests |
| Sources/AIUsage/Views/SettingsView.swift、Resources/Assets.xcassets/AntigravityLogo.imageset | 新增矢量图标资产、设置集成页 Antigravity 状态说明及 About 版本说明 | SettingsView、ProviderLogo | `make verify` 与流程检查 |
| Tests/AIUsageTests/ProviderTests.swift、UsageStoreTests.swift | 新增 Antigravity 轨迹增量去重、多分组额度映射、过期/离线回退与存储迁移测试 | `make test` | 全部 XCTest 通过 |

## 6. 异常、安全与兼容性

- 失败处理：Language Server 未启动、端口失效或超时（3 秒）时，若已有进程内缓存的未过期额度则保留，否则回退为仅展示本地 Token；目录为空时返回 `.waitingForFirstSample`。
- 安全与隐私：不解码或缓存 `content`、`thinking`、`tool_calls`；`csrfToken` 仅在内存中用于向 `127.0.0.1` 发起只读请求，不写入日志或持久化缓存。
- 兼容与迁移：通过 `providers.selection.migrated.antigravity` 键将旧默认全选列表平滑升级为包含 `antigravity`，保留用户自定义取消勾选与排序。

## 7. 可观测性与埋点

仅通过 `ProviderAvailability` 与卡片文案展示数据更新时间、无数据或等待首次运行状态，不记录任何用户会话 ID、路径或凭证。

## 8. 验证与发布

- 自动验证：运行 `make check-prepare`、`make test` 与 `make verify`，覆盖流程自测、Swift 单元测试与构建版本检查。
- 人工验证：核对设置页、卡片与历史页的 Antigravity 文案及图标配置；GUI 交互与真机菜单栏渲染如未人工点击则在变更记录中如实标注。
- 发布与回滚：遵循版本 PR 自动发布流程，不在开发分支手动修改版本号；回滚可通过还原提交完成。

## 9. 待决策项

- N/A — 无待决策项，用户已确认创建 Issue #26 并展示 Gemini 主圆环及全部返回分组额度与本地 Token。
