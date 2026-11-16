# Issue #26：支持 Google Antigravity 本地 Token 与多分组额度监控

## 基本信息
- Issue：https://github.com/YuSec2021/ai-usage-display/issues/26
- 类型：`type/feature`
- 状态：实施中
- 唯一工作分支：`codex/issue-26-antigravity-usage`
- 负责人：YuSec2021
- 设计或产出文档：[docs/design/issue-26-antigravity-usage.md](../design/issue-26-antigravity-usage.md)

## 背景
AI Usage 现已支持 Codex、Claude Code、Kimi Code 与 MiniMax 的本地用量与额度展示，用户希望将 Google Antigravity 的本地 Token 用量与多分组模型额度（Gemini 5 小时/本周、Gemini 4 Argon 本周、Claude & GPT 5 小时/本周）一并纳入菜单栏、详情卡片与 7 天历史统计。

## 目标
- 新增 `Antigravity` 模型支持（`ProviderID.antigravity` 与官方矢量图标 `AntigravityLogo`），接入菜单栏圆环、详情卡片、7 天历史图与设置页。
- 增量解析 `~/.gemini/antigravity`（及 `~/.gemini/antigravity-ide`）下 `brain/*/.system_generated/logs/transcript.jsonl` 的 Token 记录，按 `step_index` 去重统计今日 Token 与最近 7 天日用量。
- 通过本地 `daemon/*.json` 连接本机运行中的 Antigravity Language Server 读取 `RetrieveUserQuotaSummary`，主圆环展示 Gemini 5 小时额度，卡片同时展示 Gemini 本周、Gemini 4 Argon 本周及 Claude/GPT 5 小时与本周等分组额度。

## 非目标
- N/A — 不读取会话正文与思考内容，不发起外部互联网请求，不修改 Antigravity 配置文件。

## 根因说明
N/A — 当前类型为功能新增，不需要 Bug 四行根因说明。

## 验收标准
- [ ] `ProviderID` 包含 `antigravity`，具备矢量模板图标 `AntigravityLogo`，旧默认全选配置自动迁移包含 Antigravity。
- [ ] `AntigravityUsageProvider` 能从临时 fixture 的 `transcript.jsonl` 增量解析输入、缓存读取与输出 Token，同一 `step_index` 重复记录不重复累加。
- [ ] `AntigravityUsageProvider` 能解析 `RetrieveUserQuotaSummary` 响应，将 Gemini 5 小时额度作为主 5 小时圆环窗口，并完整展示 Gemini 本周、Argon 本周与 Claude/GPT 5 小时/本周等分组额度及重置时间。
- [ ] 设置页“集成”与“关于”说明、编号变更记录、`docs/changelog/README.md` 与 `CHANGELOG.md` 同步更新，并通过 `make check-prepare` 与 `make verify`。

## 模块拆解
| 模块 / 路径 | 修改内容 | 依赖 | 完成条件 |
|---|---|---|---|
| Sources/AIUsage/Models/UsageModels.swift | 新增 `ProviderID.antigravity` 及图标/颜色定义 | 无 | 编译通过且排序/选择逻辑覆盖新模型 |
| Sources/AIUsage/Providers/AntigravityUsageProvider.swift、UsageProvider.swift | 实现本地轨迹增量解析与本地 Language Server 额度摘要读取 | IncrementalLineReader、ISODateParser | 隔离单元测试覆盖 Token 聚合、额度映射与离线回退 |
| Sources/AIUsage/App/UsageStore.swift | 接入 `AntigravityUsageProvider` 与默认勾选迁移 | AntigravityUsageProvider | `UsageStoreTests` 验证全模型刷新与迁移 |
| Sources/AIUsage/Views/SettingsView.swift、ProviderCard.swift、Resources | 新增 `AntigravityLogo.imageset`、设置集成检测说明与 About 版本说明 | UsageModels、ProviderPaths | `make verify` 通过 |
| Tests/AIUsageTests/ProviderTests.swift、UsageStoreTests.swift | 新增 Antigravity 单元测试与回归验证 | XCTest | 全部测试通过 |

## 风险、假设与待决策项
- 风险：Antigravity 未运行时本地 Language Server 不可连接；此时保留进程内上次未过期额度或回退为仅展示本地 `transcript.jsonl` Token 统计。
- 假设：本机 Antigravity 使用默认 `~/.gemini/antigravity` 或 `~/.gemini/antigravity-ide` 目录结构（支持 `ANTIGRAVITY_HOME` 覆盖）。
- 待决策：N/A — 无阻塞项，展示范围已由用户确认。

## 验证计划
- 自动验证：运行 `make check-prepare`、`make test` 与 `make verify`，使用临时目录 fixture 验证 `AntigravityUsageProvider` 与 `UsageStore`。
- 人工验证：检查设置页、关于页与变更记录一致性；真实桌面 UI 交互如未在测试进程外手点则在交付说明中明确标注。
- 埋点与可观测性：沿用本地状态枚举 `ProviderAvailability`，不采集或输出任何用户会话内容与凭证。
- 发布与回滚：合并至 `main` 后由版本 PR 自动升版发布；如需回滚可直接还原本次 PR 提交。

## 完成定义
- [ ] 设计和拆解与最终实现一致。
- [ ] 所有验收标准已完成。
- [ ] 必要测试、评测、构建和审查已通过。
- [ ] 文档、埋点、迁移、发布及回滚事项已处理或明确标记不适用。
