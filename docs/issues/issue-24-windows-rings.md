# Issue #24：Windows 模型圆环托盘与桌面浮窗首版

## 基本信息
- Issue：https://github.com/YuSec2021/ai-usage-display/issues/24
- 类型：`type/feature`
- 状态：准备完成，待实施
- 工作分支：`codex/issue-24-windows-rings`（已核对无同名分支，唯一关联本 Issue）
- 负责人：YuSec2021
- 设计或产出文档：`docs/design/issue-24-windows-rings.md`，已完成复用调查、模块拆解和验证计划

## 背景
现有 AI Usage 为 SwiftUI/macOS 应用。用户确认 Windows 端采用 C#、WinUI 3、任务栏右侧模型圆环与独立桌面浮窗；常驻区域只显示模型 Logo 和外圈 5 小时已用额度，不显示百分比文字。现有圆环、数据模型、Codex 官方只读额度客户端、Claude status line 与 Kimi API 已研读，需原生 Windows 适配。当前开发机为 macOS，无本地 Windows/.NET 环境，需安装本地 .NET 测试核心并用 Windows CI 验证原生应用。

## 目标
- 新增 Windows 11 x64 原生应用：模型托盘图标、普通任务栏主窗口、可独立显示/隐藏且置顶的圆环浮窗；拖动、吸附、多屏位置恢复，点击打开详情。
- 同一进程、同一用量仓库驱动所有视图，保留真实零值、未知、过期、无限额度和仅 5 小时主圆环语义；浮窗/托盘不显示百分比文字。
- 先接入 Windows 本机 Codex 当前额度和日志、Claude 集成与本地 Token、Kimi 额度 API 和本地用量；MiniMax Windows 数据源未验证时明确暂不支持，禁止模拟真实额度。
- 提供设置、模型选择/顺序、刷新、7 天可用 Token 历史、三态主题、Kimi 凭证安全保存和退出恢复入口。
- 提供 Windows CI、隔离回归、原生构建/发布 ZIP 和启动烟雾验证，保留 macOS 工程与已有用户修改。

## 非目标
本次不接入 WSL，不猜测 MiniMax Windows 缓存格式，不申请签名证书或发布商店；不更改 macOS 数据采集，不替换已安装应用，不手动升项目版本。macOS 的自动版本 PR 流程保持，本 PR 不修改其触发策略；Windows 独立 CI 和手动构建入口提供首版产物。

## 根因说明
N/A — 当前类型不需要 Bug 根因说明。

## 验收标准
- [ ] 准备 JSON、完整设计及复用声明独立提交，通过 make check-prepare 后实施。
- [ ] 托盘/浮窗采用模型 Logo + 外圈、无常驻百分比；无数据不伪装 0%，过期样本不作为当前额度。
- [ ] 浮窗可拖动置顶、吸附、记忆/恢复位置，隐藏后由托盘恢复；Explorer 重启可恢复图标，多实例可恢复已有入口。
- [ ] Codex 只读协议有界退出并回退日志；Claude 集成可保留并恢复已有 statusLine；Kimi Key 使用 Windows Credential Manager，不记录密钥或会话正文。
- [ ] 临时 fixture 覆盖解析、过期、无限、部分写入、凭证/集成恢复与状态；测试不读取真实日志或凭证。
- [ ] Windows CI 编译、核心测试、原生启动与产物打包验证；无法完成的 GUI/真实额度范围如实记录。
- [ ] About、编号记录、索引、Unreleased、README/Windows 使用文档同步；make verify 与工作流静态检查通过。

## 模块拆解
| 模块 / 路径 | 修改内容 | 调用方或依赖 | 验证 |
| --- | --- | --- | --- |
| windows/AIUsage.Core | 平台无关领域模型、5 小时规则、解析/增量读取、Provider、历史与刷新 | 原 Swift 模型/Provider 的字段和行为 | .NET 临时 fixture 单元测试 |
| windows/AIUsage.Windows | WinUI 3 主窗口/浮窗、Win32 托盘与位置、设置/钥匙串、Claude CLI collector | Core 单一仓库，已有模型 SVG 资产 | Windows 构建和匿名数据原生启动烟雾 |
| windows/AIUsage.Core.Tests、.github/workflows/windows.yml、Makefile | 跨平台核心回归、Windows x64 自包含 ZIP/校验和 | .NET10/Windows App SDK 稳定包 | 本机核心测试、Windows CI 与产物验证 |
| docs/design、docs/windows、README、About、changelog | 产品与安装边界、实际验证范围、更新记录 | AGENTS/标准流程 | make verify、链接和静态检查 |

## 风险、假设与待决策项
- 风险：Windows 托盘排列和折叠由系统/用户控制；DPI/显示器变化需恢复位置。原生 GUI 需 Windows CI，不能以 macOS 编译核心替代。
- 假设：首版优先本机 Windows 11 x64，按现有匿名样本移植协议，不直接共享 SwiftUI 源码。安装包使用自包含 ZIP，不启用静默安装或更新。
- 待决策：N/A — 用户已授权按建议实施；具体 API/包版本按官方文档和实际 NuGet 源核验。

## 验证计划
- 自动验证：核心隔离 fixture、协议超时和日志边界、Windows x64 build/publish/ZIP、原生启动 smoke、make verify、actionlint、git diff --check。
- 人工验证：检查 Windows 原生截图/烟雾产物；交互与真实额度刷新未验证时明确标注，不读取用户日志测试。
- 埋点与可观测性：仅保存聚合用量、设置、来源状态与脱敏错误；不保存 Key、RPC 原文、提示词、回答或代码。
- 发布与回滚：通过 PR 交付，独立 Windows Actions 产物；未授权前不替换应用，回退对应 PR/关闭 Windows 构建入口即可，不覆盖 Tag。

## 完成定义
- [ ] 设计、复用、唯一分支和拆解与最终实现一致。
- [ ] 验收结果与未验证范围准确记录。
- [ ] 本机 make verify、核心测试、Windows CI 通过。
- [ ] 文档、凭证、发布与回滚事项处理完成。
