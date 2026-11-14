# Windows 圆环托盘与浮窗：模块设计

## 1. 基本信息

- ISSUE：https://github.com/YuSec2021/ai-usage-display/issues/24
- 状态：已确认；负责人：YuSec2021；日期：2026-11-14
- 唯一工作分支：codex/issue-24-windows-rings

## 2. 背景与目标

将已确认的 macOS 模型 Logo + 5 小时已用额度圆环迁移到 Windows 11 x64：托盘与独立桌面浮窗不显示常驻百分比文字，点击打开原生详情/历史/设置。使用一个数据仓库，避免每个窗口重复扫描日志或请求额度。

首版提供 Codex 官方只读额度/本地日志、Claude 可恢复 statusLine 集成及本地 Token、Kimi 本地用量和用户主动配置 Key 的额度 API。MiniMax Windows 缓存尚未验证，明确显示暂不支持，不虚构额度。WSL、ARM64、商店签名、自动安装更新不在首版范围，不改 macOS 采集逻辑。

## 3. 现状与约束

遵循 AGENTS 与 standard-dev-flow，无单独 ADR。原 Swift 模型包含 SwiftUI 颜色，圆环依赖 AppKit，无法直接编译为 WinUI。新代码放在 windows 目录，原工程保持独立；采用 .NET 10 LTS、WinUI 3、NuGet 实际可用的 Windows App SDK 1.8 稳定版本，使用自包含文件夹 ZIP 发布。当前开发机为 macOS，跨平台核心本机测试，原生应用必须经 Windows runner 构建/启动验证。

## 4. 复用声明

- 仓库是否已有该能力：部分已有；macOS 已实现圆环语义、模型图标、刷新/历史、三家 Provider 与 Claude 集成，尚无 Windows 工程或 Win32 托盘/浮窗。
- 搜过什么关键词：UsageRing、MenuBarRingImage、fiveHourWindow、UsageSnapshot、rateLimits/read、statusLine、KimiUsageAPI、ProviderPaths、Windows、WinUI、浮窗。
- 看过哪些既有实现：Sources/AIUsage/Views/UsageRing.swift、Models/UsageModels.swift、Providers/CodexRateLimitClient.swift、CodexUsageProvider.swift、ClaudeUsageProvider.swift、MiniMaxUsageProvider.swift、Services/ClaudeIntegrationManager.swift、KimiUsageAPI.swift、Tests/AIUsageTests/ProviderTests.swift 与 CodexRateLimitClientTests.swift、现有 SVG 资产、Makefile、PR/发布工作流。
- 为什么不能复用：SwiftUI/AppKit、macOS 钥匙串和 zsh/osascript 集成依赖平台。复用字段、协议、匿名样本与现有 SVG 资产，在 C# 中实现等价规则；不引入跨平台服务或重写 macOS。

## 5. 方案

Core 以 ProviderId、QuotaWindow、UsageSnapshot、DailyUsage 为契约。5 小时主圆环只取 durationMinutes=300 的有效有限窗口，零值保留、未知虚线、过期降级，周额度/Token 不替代。刷新串行合并重入请求、支持取消，失败保留并标记旧样本。日志增量读取缓存游标并保留残行；初读/行大小有界，截断时明确历史范围有限，不将局部 Token 伪称完整账单。

WinUI 主窗口含概览/历史/设置，任务栏正常显示。独立浮窗不新增任务栏按钮，默认置顶，只有用户交互才激活；拖动把手、工作区边缘吸附，保存显示器与坐标，显示器断开或 DPI 变化后限制在可见工作区。每个选中模型一枚 Win32 Shell_NotifyIcon，图标由真实 Logo 和相同圆环规则生成；Explorer 重启后重新注册，所有 HICON/窗口子类化/菜单资源显式释放。右键提供详情、浮窗、刷新和退出，关闭浮窗不退出后台。退出释放互斥锁与托盘；第二实例激活已有入口。

Codex 启动用户已安装 CLI 的 app-server，8 秒超时、输出总量和单行有界，只发送 initialize/initialized/account/rateLimits/read，退出仅清理自有进程，失败回退本地日志。Claude collector 模式只提取允许的额度字段，安装前备份已有 statusLine、委托原命令输出，卸载仅在本集成仍拥有配置时恢复；命令引用路径需跨 Git Bash/Windows 正确转义。Kimi 凭证适配器放 Windows 层，Core 只接受可注入 loader，不在日志/设置 JSON 保存 Key。

| 模块 / 路径 | 修改内容 | 调用方/依赖 | 验证 |
| --- | --- | --- | --- |
| windows/AIUsage.Core | 领域、解析、Provider、增量日志、历史、刷新、设置/集成契约 | 移植既有 Swift 字段与规则 | .NET 临时 fixture，超时/取消/残行/重复/失效 |
| windows/AIUsage.Windows | WinUI UI、圆环、Win32 托盘/位置/凭证、collector 入口 | 单一 Core 仓库与已有 Logo 资产 | Windows build/publish、匿名 smoke 与原生渲染产物 |
| windows/AIUsage.Core.Tests | 不读真实文件/Key/网络的回归 | 注入目录、时间、HTTP/CLI loader | macOS/Windows 同样运行 |
| .github/workflows/windows.yml、Makefile、docs/windows | 构建、测试、自包含 ZIP/SHA-256，使用限制 | .NET10 / Windows runner | 独立 Windows CI 与原有 make verify |

## 6. 异常、安全与兼容性

不保存提示词、回答、工具参数或 RPC 原文。Key 使用 Windows Credential Manager；设置原子落盘，损坏时保留备份/显示错误。日志允许共享写入，失败下轮重试；旧授权响应与旧刷新不得覆盖新设置。未检测到来源显示未安装/待集成；无有效额度显示未知，MiniMax 明确暂不支持。测试与 smoke 使用显式临时目录及匿名样本，生产默认从不展示示例数据。

## 7. 可观测性与埋点

仅暴露来源状态、更新时间、刷新错误与历史范围提示。CI smoke 将进程/窗口/托盘注册和截图写入临时构建产物，不上报生产用户数据。未做真实 Windows GUI/额度验证时，不以构建成功代替。

## 8. 验证与发布

- 自动验证：匿名 JSON/JSONL、假 CLI/HTTP、配置恢复与并发回归；Windows 11 x64 编译和自包含 publish、ZIP/SHA-256；原生 smoke，make verify、actionlint、差异与链接检查。
- 人工验证：查看 Windows 原生渲染截图，核对无百分比常驻文字；实际用户机器的交互、托盘折叠、显示器/DPI 和真实额度刷新如未执行则明确记录。
- 发布与回滚：PR 提供 Actions 可下载 ZIP；无签名/商店/自动更新或本机安装。macOS 自动发布不改触发规则，合并与发布仍遵循现有保护。回滚本 PR 即可移除 Windows 入口，不触碰用户真实日志或 Key。

## 9. 待决策项

N/A — 技术基线、产品入口与首版兼容范围已明确，未验证数据源不冒充支持。
