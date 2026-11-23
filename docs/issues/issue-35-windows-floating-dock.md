# Windows 桌面浮窗升级为毛玻璃胶囊 Dock 与悬浮详情卡样式

## 基本信息

- Issue：https://github.com/YuSec2021/ai-usage-display/issues/35
- 类型：`type/feature`
- 状态：待实施
- 工作分支：`codex/issue-35-windows-floating-dock`
- 负责人：AI Usage 维护者
- 设计或产出文档：`docs/design/issue-35-windows-floating-dock.md`

## 背景

现有 Windows 桌面浮窗采用带拖拽手柄（`⠿`）、展开/收起按钮（`⌄`/`⌃`）和关闭按钮（`×`）的紧凑条与垂直展开列表。新设计的 Windows 浮窗交互原型将浮窗升级为更轻盈的毛玻璃胶囊 Dock + 悬浮详情卡（Popover），减少桌面占用并提升悬停查看单个模型 5 小时额度的效率。

## 目标

- 按原型规范将 Windows 浮窗重构为毛玻璃胶囊 Dock（4 模型基准 `256×64` DIP，圆角 `29`，空白区域拖拽并支持边缘吸附）。
- 实现与 Dock 联动的毛玻璃悬浮详情卡（Popover，`240×106` DIP 基准，圆角 `15`，带对齐指示箭头、Pin 固定、`···` 菜单、无百分比进度条、相对重置倒计时与相对更新时间）。
- 在 `···` 菜单中提供「刷新额度」「打开主面板」「隐藏浮窗」。
- 升级模型圆环视觉，移除白色方底并采用原型配色，浅色模式还原原型，深色模式提供匹配的深色毛玻璃适配。
- 补充纯 C# 核心格式化与布局单元测试，并更新 Windows 原生冒烟验证。

## 非目标

- 不修改 macOS 端界面与行为。
- 不修改 Windows 主窗口导航结构或各 Provider 的额度抓取逻辑。
- 不引入新的第三方 NuGet 依赖或更改现有 `settings.json` 兼容结构。

## 根因说明

N/A — 当前类型为 `type/feature`，不需要根因说明。

## 验收标准

- [ ] Windows 浮窗呈现为毛玻璃胶囊 Dock，移除 `⠿`/`⌄`/`×` 按钮，支持拖动空白区域移动并在松开后吸附屏幕边缘。
- [ ] Dock 内各模型圆环为 `44×44` DIP，居中展示品牌图标，配色符合原型（Codex `#6CA15A`、Claude Code `#F58A12`、Kimi Code `#367CF4`、MiniMax `#8B99AF` 未知虚线）。
- [ ] 悬停或点击圆环时在浮窗上方（顶部空间不足时自动翻转至下方）弹出毛玻璃详情卡，指示箭头对齐当前圆环中心；支持 Pin 固定、移出/`Esc` 收起，以及 `···` 菜单中的「刷新额度」「打开主面板」「隐藏浮窗」。
- [ ] 详情卡包含 32px 圆形图标底、模型名、`5 小时额度`、5px 胶囊进度条（无百分比文字）、中文相对重置倒计时与相对更新时间。
- [ ] 浅色模式还原原型配色，深色模式具备匹配的深色毛玻璃配色，跟随应用主题设置切换。
- [ ] `make windows-test` 与 `make verify` 全部通过；Windows 原生冒烟校验覆盖 Dock 与详情卡无百分比断言并生成截图。

## 模块拆解

| 模块 / 路径 | 修改内容 | 依赖 | 完成条件 |
|---|---|---|---|
| `windows/AIUsage.Core/UsageModels.cs` & `FloatingPresentation.cs` | 更新模型配色，新增相对时间格式化与 Dock/Popover 布局计算 | 无 | `make windows-test` 全部通过 |
| `windows/AIUsage.Core.Tests/UsageTests.cs` | 新增相对重置倒计时、更新时间、Dock 尺寸与 Popover 翻转/箭头对齐测试 | `AIUsage.Core` | 新增用例稳定通过 |
| `windows/AIUsage.Windows/Native.cs` & `RingView.cs` | 增加 DWM 圆角封装，支持胶囊无白底圆环及深色可读性 | `AIUsage.Core` | 代码编译契合 WinUI 3 API |
| `windows/AIUsage.Windows/FloatingWindow.*` & `FloatingDetailWindow.*` | 重构胶囊 Dock 窗口并新增联动悬浮详情 Popover 窗口 | `Native.cs`、`RingView.cs`、`FloatingPresentation.cs` | 交互、主题、拖拽吸附与菜单行为完整 |
| `windows/AIUsage.Windows/SmokeCapture.cs` | 校验 Dock 与 Popover 无百分比并输出 `floating-compact.png` 与 `floating-expanded.png` | `FloatingWindow`、`FloatingDetailWindow` | 冒烟逻辑覆盖新浮窗与详情卡 |
| `Sources/AIUsage/Views/SettingsView.swift`、`CHANGELOG.md`、`docs/changelog/` | 同步 About 说明与变更日志 | 实施完成 | `make verify` 通过 |

## 风险、假设与待决策项

- 风险：当前开发机为 macOS，无法在本地直接运行 WinUI 3 编译和 Windows 桌面实机渲染，需依赖静态审查、.NET Core 单元测试以及 GitHub Actions Windows runner 验证编译与原生冒烟。
- 假设：目标运行环境为 Windows 11（`TargetPlatformMinVersion 10.0.22000.0`），支持 `DesktopAcrylicBackdrop` 与 `DwmSetWindowAttribute` 圆角属性。
- 待决策：N/A — 无阻塞项。

## 验证计划

- 自动验证：本地执行 `make windows-test` 与 `make verify`；远端 PR 触发 Windows CI 构建与 `windows/scripts/smoke.ps1` 原生冒烟验证。
- 人工验证：在 Windows 环境或 CI 冒烟产物中目视核对毛玻璃胶囊 Dock、详情卡对齐箭头、深浅色对比度与悬停/拖拽/Pin 交互；本地 macOS 环境未做 Windows 实机检查时在变更记录中明确标注。
- 埋点与可观测性：不新增遥测；复用 `--smoke-test` 进度日志与截图产物观察渲染状态。
- 发布与回滚：按受保护 `main` PR 流程合入并由 `Automatic release` 自动发版；异常时直接回滚本 PR 提交即可恢复原浮窗实现。

## 完成定义

- [ ] 设计和拆解与最终实现一致。
- [ ] 所有验收标准已完成。
- [ ] 必要测试、评测、构建和审查已通过。
- [ ] 文档、埋点、迁移、发布及回滚事项已处理或明确标记不适用。
