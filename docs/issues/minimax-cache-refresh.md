# 修复 MiniMax Desktop 额度无法刷新

## 基本信息

- 类型：`type/bug`
- 状态：实现、测试及本机安装完成；菜单面板的自动化抓取超时，限制已记录
- 工作分支：`codex/fix-minimax-cache-refresh`（本地草稿，无外部 Issue 编号；遵循 AGENTS.md 的分支规则，没有其他关联分支）
- 负责人：当前项目维护者
- 设计或产出文档：N/A — bug 不要求模块设计，复用原 MiniMax provider、额度窗口和系统 Compression。

## 背景

用户截图显示 MiniMax 5 小时已用 24%、周限额无限制，但 AI Usage 无法刷新。只检查 Desktop HTTP 额度响应后确认：新版 `/backend/account/token_plan/remains_percent` 响应为 Brotli，使用 `current_interval_used_percent: "24%"` 与 `current_weekly_status: 3`；旧代码只搜索明文 JSON 与旧 remaining 字段。旧 Zstandard 响应来自上个月，不能作为当前值。截图的无限制状态与当前响应 status 3 对应。上一轮 Codex 修复已保存为本地提交，本分支以该提交为基础，不丢失已安装修复。

## 目标

- 正确读取新版 Brotli 缓存与百分比字符串，兼容原有明文 remaining 字段。
- 更新同一缓存文件时能刷新；损坏、半写、失败或过期响应不伪装为当前额度。
- 周限额无限制明确显示“无限制”，不显示为 0% 的有限额度。

## 非目标

- 不读取 Cookie、凭证、会话内容或 API 日志，不主动调用 MiniMax 私有接口。
- 不接入过期的旧 Zstandard 样本；不增加第三方解压依赖或运行时外部命令。
- 不改动已完成的 Codex 刷新逻辑，不推送或发布。

## 根因说明（仅 `type/bug`）

- 现象：MiniMax Desktop 有 24% 用量，AI Usage MiniMax 仍无额度，点击刷新无变化。
- 根因：`MiniMaxUsageProvider.quotaResponse` 在压缩字节中查找 model_remains；`MiniMaxModelQuota` 仅解码旧 remaining_percent，无法识别新版 used_percent 字符串与无限制状态。
- 影响面：MiniMax 主圆环、周额度与状态提示；Token 历史无变化，无需数据迁移。
- 回归：临时 Chromium Simple Cache fixture 覆盖 Brotli、明文、24%/0%、无限制、同文件更新、半写/损坏/错误响应、最新有效样本和过期过滤；禁止读取用户数据作为自动测试。

## 验收标准

- [x] 新格式读取 24% 用量，周限额显示无限制；保留旧明文格式。
- [x] 按缓存结构分离响应体与头部，限制解压输出，不解析其他接口的压缩内容。
- [x] 变更缓存后刷新可观察到新值；失败响应不覆盖上一条可用样本。
- [x] make verify、通用 Release 构建通过，真实额度与本机安装验证如实记录。

## 模块拆解

| 模块 / 路径 | 修改内容 | 依赖 | 完成条件 |
| --- | --- | --- | --- |
| Providers/MiniMaxUsageProvider.swift | Chromium Simple Cache 读取、系统 Brotli 解压、新旧额度映射及错误处理 | Compression、zlib；已有元数据增量扫描 | 隔离 fixture 与真实白名单字段核对 |
| Models/UsageModels.swift、Views/ProviderCard.swift、UsageRing.swift、MenuBarView.swift | 额度窗口保留无限制属性，文字和无障碍正确显示 | 既有圆环、窗口选择 | 无限制不会变成有限用量百分比 |
| Tests、Settings About、文档和编号日志 | 回归与行为说明同步 | 最终实现 | make verify、构建和本机验收 |

## 风险、假设与待决策项

- 风险：Desktop 未更新缓存时，本地刷新不能创造新额度；过期数据继续按现有规则隐藏并明确提示。
- 假设：新版当前采用 Brotli，系统 macOS 12+ 原生支持，项目最低 macOS 13；无限制状态按截图和响应的对应关系映射。
- 待决策：N/A — 无阻塞项；不需要新密钥或依赖。

## 验证计划

- 自动验证：真实格式的合成缓存（头/体/EOF/CRC），有界 Brotli 解压、百分比字符串、无限制、错误和增量刷新，make verify。
- 人工验证：只输出用量白名单；核对截图和已安装应用，若锁屏或原始样本过期则明确注明。
- 埋点与可观测性：不打印缓存原文，只使用现有 provider 状态和刷新时间。
- 发布与回滚：本机替换前备份，继续保留 1.2.2（Build 6）；远程发布由用户另行授权。

## 完成定义

- [x] 根因与最终实现一致。
- [x] 验收标准完成，未验证范围具体记录。
- [x] 测试与构建通过。
- [x] About、日志、用户说明和回滚备份已处理。

## 验证结果

- make verify 通过：16 项流程测试、54 项功能测试，1 项 GPU 渲染按默认设置跳过；之后显式开启本机 GPU 预览，55 项 Swift 测试全部通过。深浅两色示例卡片渲染成功，已核对深色 MiniMax 24% 圆环及“本周无限制”布局。
- 增量测试验证 24% → 37% → 文件半写保留并标记过期 → 完整真实 0% 恢复。独立 Brotli fixture、CRC、长度边界、错误响应、旧格式、无效百分比、解压上限和模型编码兼容均通过。
- 真实只读 provider 先读取到 25%，重置后读取到当前 0%，且周额度无限制。使用 MiniMax Code 官方“用量”菜单核对为 0%、约 4 小时 57 分后重置、周限额无限制，数据一致。
- 通用 Release DMG、arm64/x86_64、临时签名和版本检查通过。本机应用已备份、替换并稳定启动，安装清单位于忽略目录 `.build/local-update/minimax-cache-fix/installation.json`。
- AI Usage 菜单面板的自动化抓取超时；不声称已完成新安装应用的菜单界面核对，卡片使用隔离示例渲染验证。没有修改用户的模型选择、主题或其他偏好。
- 未推送、合并或发布；版本仍为 1.2.2（Build 6）。
