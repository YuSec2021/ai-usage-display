# Grok 订阅周额度：模块设计

## 1. 基本信息
- ISSUE：https://github.com/YuSec2021/ai-usage-display/issues/30
- 状态：已确认
- 负责人：YuSec2021
- 更新日期：2026-11-17
- 唯一工作分支：codex/issue-30-grok-subscription-usage

## 2. 背景与目标
用户选择 Grok 网站/App 订阅额度。[官方 FAQ](https://docs.x.ai/grok/faq) 说明共享周使用池与 Settings/Usage；本机 Grok Bot 的 Usage & Billing 显示同一周使用率和其他应用消耗。目标为无凭证、无网络的只读订阅额度监控，按真实周窗口展示。API Key 用量、直接 Web 登录、团队额度、Token 历史与 Windows 不在范围内。

## 3. 现状与约束
遵循 AGENTS、DEVELOPMENT 和 standard-dev-flow。先独立提交准备材料并通过门禁再实施。原工作区有用户 AGENTS 修改和未跟踪 Windows 文件，在独立检出目录实施。开发分支不升版，不自动合并或安装。

## 4. 复用声明
- 仓库是否已有该能力：部分已有；UsageProvider、UsageStore、RateLimitWindow、日期格式、菜单栏与卡片圆环已具备，但没有 Grok 缓存读取，现有主圆环仅选明确的 300 分钟窗口。
- 搜过什么关键词：Grok、weekly-usage.cache、account-slot、ProviderID、fiveHourWindow、migrateProviderSelection、KimiCredentialStore、KimiUsageAPI。
- 看过哪些既有实现：Sources/AIUsage/Providers/AntigravityUsageProvider.swift、UsageProvider.swift、Services/KimiCredentialStore.swift、KimiUsageAPI.swift、Models/UsageModels.swift、App/UsageStore.swift、Views/ProviderCard.swift、UsageRing.swift、MenuBarView.swift，以及 ProviderTests、PresentationTests、UsageStoreTests。
- 为什么不能复用：直接复用协议、刷新、窗口、圆环和日期组件；Grok 的账号隔离缓存键、Base32 文件名与周额度 schema 是新数据源，不能使用 API Key 路径或将周额度映射成 5 小时。只增加 provider 特有主窗口选择，保留五小时接口语义。

## 5. 方案
### 数据源依据
只读检查已安装的 Grok Bot.app/Contents/Resources/app.asar 内公开随应用分发的 renderer 与 main 代码，确认 weekly-usage.cache schemaVersion=3、client-meta.account-slot schemaVersion=1、缓存 readAtMs/nextResetMs/expiresAtMs 和 hasNonZeroIncludedLimit。未读取 sand-secrets、Cookies、对话或凭证。人工打开 Usage & Billing 核对了周使用率；生产不依赖分析工具或脚本。

### 核心流程与接口
1. 根目录为 ~/Library/Application Support/Grok Bot/sand-client-persistence（可通过 GROK_BOT_HOME 覆盖 Grok Bot 的 userData 目录），测试显式注入临时 root，不使用用户真实目录。
2. 精确读取 sand.client.slice.client-meta.account-slot 的 envelope，value 必须为有效 grok| 账号槽位。按 encodeURIComponent 规则编码槽位，构造 sand.client.slice.account.{encodedSlot}.weekly-usage.cache，不枚举其他 slice 或账号。
3. 本地文件名为小写 Base32(UTF-8 key)+.blob；长度超过 240 时为 Base32(SHA256(key))+.kblob，内容第一行 JSON 字符串必须精确等于所请求的 key，后续才是 envelope。metadata 最大 4 KiB、额度最大 64 KiB，拒绝超限或非普通文件。
4. 只解码 schemaVersion、kind、selectedTeamId、usage.percentUsed/nextResetMs/hasNonZeroIncludedLimit/isTeamSeat/readForTeamId、readAtMs、expiresAtMs。拒绝团队及无额度状态；读完再次核对账号槽位，确保读期间未切换。没有账号时清空旧样本。
5. 新鲜上限 5 分钟，有效上限同时取 expiresAtMs、readAtMs+24h 与服务端已知 reset；到期不展示进度，不从当前时间推算重置。未知 reset 保持 nil。同账号损坏/半写时可保留仍在有效期内的旧样本并标为 stale，换账号立即隔离。
6. Grok windows 仅一项 long/10080 分钟/本周。新增 primaryQuotaWindow 与主窗口文案，Grok 选择有效周窗口，其他 provider 始终复用 fiveHourWindow；五小时最高模式不比较 Grok 周窗口。卡片排除已经展示的主窗口，Grok 不显示今日 Token。
7. Grok Provider 注入 UsageStore；全选迁移只处理此前默认全选值，保留自定义选择。设置提供来源/检测说明与打开 Grok Bot 的入口，明确 AI Usage 刷新只重读缓存。

### 受影响模块
| 模块 / 路径 | 修改内容 | 调用方或依赖 | 验证方式 |
|---|---|---|---|
| Providers/GrokUsageProvider.swift、UsageProvider.swift | 缓存键、有界读取、账号校验和时间边界 | UsageStore、Foundation/CryptoKit | 匿名 fixture 单测 |
| Models/UsageModels.swift、Views/ProviderCard.swift、UsageRing.swift、MenuBarView.swift | Grok 元数据、独立主周窗口、准确标题与无障碍 | 既有窗口及圆环 | 周/五小时隔离与图像测试 |
| App/UsageStore.swift、Views/SettingsView.swift、Assets | 注入、全选迁移、缓存来源和 Logo | 既有偏好与刷新 | Store 与格式测试、编译 |
| Tests、docs、CHANGELOG.md、AIUsage.xcodeproj | 回归、About/编号记录和工程同步 | make generate / make verify | 完整检查 |

## 6. 异常、安全与兼容性
- 失败处理：缺应用/缓存、未登录、坏文件、未知 schema、无额度或团队状态明确提示；不显示伪造 0%，不恢复已过周期进度。
- 安全与隐私：只读两个明确额度相关键；文件大小有界，不解码/记录身份、凭证或会话；不发任何网络请求，不修改原应用文件，缓存失效必须遵循服务端时间。
- 兼容与迁移：既有五小时模型与最高五小时模式保持原语义，新增 Grok 全选迁移不覆盖用户自定义勾选或排序。缓存格式改变则不可用并引导打开 Grok Bot。

## 7. 可观测性与埋点
复用 ProviderAvailability；错误文案不包含账号、路径或缓存正文，无新增遥测。

## 8. 验证与发布
- 自动验证：独立 fixture 覆盖零/正常/超限、无额度、团队、未知 schema、损坏、超大、缓存/周期到期、半写旧样本、切换账号、多账号隔离、账号读取竞争与长键帧；旧 Provider 及窗口选择/全选迁移回归；make verify。
- 人工验证：使用实际 Grok Bot 额度白名单对照本 Provider 与 UI；不把真实缓存混入测试。UI 或真实刷新未执行则在日志中注明。
- 发布与回滚：开发分支保持版本，后续独立 PR/版本 PR 按流程发布；用户未授权本任务直接合并/安装，交付可审查变更。

## 9. 待决策项
- N/A — 用户确认订阅额度；首版采用本机存在的 Grok Bot 共享周额度只读缓存，来源限制在 UI 与文档中明确。
