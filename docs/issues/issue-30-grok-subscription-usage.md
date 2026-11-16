# Issue #30：显示 Grok 订阅周额度

## 基本信息
- Issue：https://github.com/YuSec2021/ai-usage-display/issues/30
- 类型：`type/feature`
- 状态：待实施
- 唯一工作分支：`codex/issue-30-grok-subscription-usage`
- 负责人：YuSec2021
- 设计或产出文档：[模块设计](../design/issue-30-grok-subscription-usage.md)

## 背景
用户明确需要 grok.com / Grok App 订阅额度。官方说明付费订阅共享周使用池；本机已登录 Grok Bot 的 Usage & Billing 显示共享周额度及其他应用消耗，其本地 weekly-usage.cache 保存相同白名单额度字段。现有应用仅为主圆环选择 5 小时窗口，直接加入周数据会显示错误的窗口标题或空圆环。

## 目标
- 新增 Grok Provider，读取当前 Grok Bot 个人账号的共享周额度、观察时间与服务端重置时间；菜单栏和卡片明确显示周额度。
- 复用已有模型勾选、排序、刷新、圆环、日期格式；旧默认全选升级包含 Grok，自定义选择不变。
- 设置页明确来源是 Grok Bot 本地缓存，刷新应用只重读缓存；需要打开已登录 Grok Bot 的 Usage & Billing 才能更新服务端额度。

## 非目标
- 不读取浏览器 Cookie、sand-secrets、账户凭证、对话、提示词或工具参数；不发网络请求，不修改 Grok Bot 文件。
- 不提供 xAI API Key 用量、Web/App 直接登录、团队额度或 Windows 实现；不将周额度伪称 5 小时，不伪造 Token 和历史数据。

## 根因说明
N/A — 当前类型为功能新增，不需要 Bug 四行根因说明。

## 验收标准
- [ ] 仅读取 active account-slot 与该账号 weekly-usage.cache 两个逻辑键，不枚举会话或其他账号数据；退出登录、切换账号/团队或读取期间账号变化时不混用旧样本。
- [ ] 0% 保留，负值/非有限数/缺字段/错误版本拒绝；超过 100% 的可用值按既有圆环规则封顶；未知重置时间不推算。
- [ ] 5 分钟内为新鲜样本，超过 5 分钟但未超缓存期限显示过期提示；服务端周期结束、expiresAtMs 或 24 小时上限达到后不展示当前进度；同账号半写可保留仍有效旧样本并标旧。
- [ ] Grok 卡片和菜单栏显示周额度，不显示本地 Token；既有最高 5 小时模式继续忽略周窗口。
- [ ] 图标、选择迁移、设置集成、About、编号变更记录和索引同步；临时 fixture 回归、make generate、make verify、差异检查通过。

## 模块拆解
| 模块 / 路径 | 修改内容 | 依赖 | 完成条件 |
|---|---|---|---|
| Sources/AIUsage/Providers/GrokUsageProvider.swift、UsageProvider.swift | 有界读取两个缓存键、版本及账号校验、周窗口和失效处理 | Foundation、CryptoKit | 合成 fixture 覆盖有效/过期/损坏/账号隔离，不访问真实用户目录 |
| Sources/AIUsage/Models/UsageModels.swift、Views/ProviderCard.swift、UsageRing.swift、MenuBarView.swift | Grok 元数据与主周窗口、标题及无障碍说明，既有 5 小时选择函数保持语义 | 既有 RateLimitWindow、UsageRing | 表现测试覆盖周窗口及最高 5 小时隔离 |
| Sources/AIUsage/App/UsageStore.swift、Views/SettingsView.swift、Resources | 注入 Grok Provider、全选迁移、来源说明与 Logo | 既有刷新及偏好 | 迁移和刷新测试通过 |
| Tests/AIUsageTests、docs、CHANGELOG.md、AIUsage.xcodeproj | 隔离回归、文档及生成工程同步 | make generate / make verify | 流程、单元测试、版本检查全部通过 |

## 风险、假设与待决策项
- 风险：Grok Bot 未公开承诺缓存格式稳定；严格识别 schemaVersion，未知格式明确不可用。无 Grok Bot 或未登录时引导打开应用，不声称直接支持浏览器登录。
- 假设：用户本机运行中的 Grok Bot 与其想监控的订阅账号一致；显示来源为当前 Grok Bot 账号，可通过 Grok Bot 切换，不读取账户标识到日志或 UI。
- 待决策：N/A — 用户已确认订阅额度，当前存在可用只读缓存数据源。

## 验证计划
- 自动验证：临时目录 fixture 覆盖 Base32/URI 键、长键 SHA-256 帧、账号变化、零值、无额度、坏文件、旧版本、时间边界；表现/迁移回归；运行 make check-prepare、make generate、make verify 和 git diff --check。
- 人工验证：核对 Grok Bot Usage & Billing 的额度白名单与 AI Usage Grok 显示；未验证实际 UI、真实缓存刷新或安装时明确记录，不让自动测试访问真实日志或凭证。
- 埋点与可观测性：仅沿用 ProviderAvailability 展示读取状态，不记录账号、路径、原始缓存或凭证。
- 发布与回滚：开发分支沿用 main 版本，不自动合并或安装；合入后通过版本 PR 发布，可还原本次 PR 回滚。

## 完成定义
- [ ] 设计和拆解与最终实现一致。
- [ ] 所有验收标准已完成。
- [ ] 必要测试、构建和审查已通过。
- [ ] 文档、迁移、发布及回滚事项已处理或明确记录限制。
