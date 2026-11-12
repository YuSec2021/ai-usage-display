# 修复 Codex 重置后的 5 小时额度缺失

## 基本信息

- 类型：`type/bug`
- 状态：实现及本地验证完成；已安装本机修复构建，最终界面核对受锁屏阻挡
- 工作分支：`codex/fix-codex-quota-refresh`（遵循本仓库 AGENTS.md；本地 Issue 草稿，无外部编号；没有其他工作分支）
- 负责人：当前项目维护者
- 设计或产出文档：N/A — bug 不要求模块设计，直接复用现有 Provider、额度模型和圆环。

## 背景

用户截图中 Codex 周额度正常，5 小时圆环却显示“暂无数据”。只检查额度字段发现，最近日志里的短窗口已重置，直到用户继续 Codex 对话才写入新额度。真实 Provider 探针和已安装应用已恢复显示，说明读取格式正常，但刷新本地文件不能主动获取重置后的额度。已核对 OpenAI 官方 App Server 文档和本机 0.143.0 协议，初始化后调用只读 `account/rateLimits/read` 可获得当前额度；本机请求成功。

## 目标

- 刷新时通过已安装 Codex 的官方只读接口获取额度，空闲或跨重置后无需先发消息。
- CLI 缺失、未登录、接口错误、断网和超时时保留日志回退；不把过期值或推算的零当作当前额度。
- 打开面板立即刷新，离线旧窗口明确提示等待更新。

## 非目标

- 不生成对话，不登录或修改账户，不读取或保存凭证，不消费 reset credit；不修改其他模型的数据源。

## 根因说明（仅 `type/bug`）

- 现象：Codex 没有新 token_count 时，短窗口超过 resets_at 后主圆环消失，而周额度仍有效；刷新无效。
- 根因：`CodexUsageProvider.load` 仅读取会话日志，没有主动额度读取；`UsageSnapshot.fiveHourWindow` 正确过滤过期窗口，但 `ProviderCard` 把过期和从未采集统一写成“暂无数据”，`MenuBarView` 打开时也没有刷新。
- 影响面：Codex 短周期显示与菜单栏圆环；本地 Token 统计无损，不需迁移。CLI 不可用时仍依赖日志。
- 回归：隔离 JSONL 和假 stdio 服务验证官方额度覆盖过期样本、无日志、有错回退、初始化与多 bucket 选择、超时退出，以及过期提示与真实 0%。

## 验收标准

- [x] 官方当前 5 小时/7 天额度可更新圆环，保留本地 Token 汇总。
- [x] 只发送 initialize、initialized、account/rateLimits/read；只解析额度字段。
- [x] 无日志仍能显示官方额度；失败有界退出并使用本地样本，不伪造零用量。
- [x] 明确标记已重置等待更新；打开面板立即刷新。
- [x] make verify 通过，核对真实只读额度、签名、双架构与安装启动。
- [ ] 解锁后核对修复构建的菜单面板（自动 UI 工具明确返回 Mac 锁屏；未绕过）。

## 模块拆解

| 模块 / 路径 | 修改内容 | 依赖 | 完成条件 |
| --- | --- | --- | --- |
| Providers/CodexRateLimitClient.swift、CodexUsageProvider.swift、App/UsageStore.swift | 有界 stdio 只读客户端，生产环境注入，复用 makeWindows 和日志统计 | 已安装且已登录的 Codex | 隔离客户端与 Provider 回归通过；测试不访问用户 CLI |
| Models/UsageModels.swift、Views/ProviderCard.swift、MenuBarView.swift | 过期说明、打开刷新 | 现有窗口过滤及 UsageStore | 不将过期值显示为当前额度 |
| Tests、About、README、开发文档、编号日志 | 契约验证、用户说明和流程同步 | 最终实现 | make verify、真实额度核对 |

## 风险、假设与待决策项

- 风险：CLI 版本或网络不可用，必须超时回退；只启动自有 stdio 子进程并关闭，不连接或终止现有 Codex 进程。
- 假设：复用用户已安装、已登录的 CLI；GUI PATH 不可靠，检测常用 Homebrew 路径及 ChatGPT.app 内置 CLI。
- 待决策：N/A — 无阻塞项；CLI 不可用仍保持现有离线行为。

## 验证计划

- 自动验证：临时文件、注入额度 reader、假 stdio 子进程；make generate、make verify。
- 人工验证：只输出官方额度字段，核对菜单栏与卡片；不将用户日志或账户信息加入 fixture。
- 埋点与可观测性：不记录凭证、RPC 原文或对话；复用现有刷新时间和窗口状态。
- 发布与回滚：保留版本号，由 main 流程升版；安装前备份，失败可恢复上个应用。

## 完成定义

- [x] 根因和拆解与最终实现一致。
- [ ] 验收标准全部完成；最后的 UI 核对因锁屏未完成。
- [x] 测试、构建及实际额度验证通过。
- [x] 文档、发布与回滚说明同步。

## 验证结果

- make verify：16 项流程测试、47 项功能测试通过，1 项显式启用的 GPU 预览按默认设置跳过；git diff --check 通过。
- 假 stdio 服务验证握手、codex bucket、真实 0%、旧协议、错误、缺失 CLI、提前退出和超时；JSONL fixture 验证跨文件 token-only 事件不覆盖额度、无日志官方额度与本地 Token 保留。
- 真实新客户端只输出额度字段，返回有效 300/10080 分钟窗口，确认主动读取不需要新对话。
- 通用 Release DMG 构建通过，arm64/x86_64 与临时签名校验通过；本机 `/Applications/AI Usage.app` 替换并稳定启动。保留原版备份与忽略目录下的安装清单。
- 修复前旧构建的 UI 已恢复显示新日志额度；修复构建的最终 UI 核对被系统锁屏阻挡，未声称已完成。
- 尚未推送、合并或发布；本机版本仍为 1.2.2（Build 6），以 About 说明和本地安装清单区分本次修复构建。
