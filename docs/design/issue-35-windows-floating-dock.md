# Windows 毛玻璃胶囊浮窗与悬浮详情卡：模块设计

## 1. 基本信息

- ISSUE：https://github.com/YuSec2021/ai-usage-display/issues/35
- 状态：已确认
- 负责人：AI Usage 维护者
- 更新日期：2026-11-22

## 2. 背景与目标

### 背景

当前 Windows 端浮窗（`FloatingWindow`）采用传统的紧凑条与垂直展开列表：左侧固定显示拖拽手柄（`⠿`），右侧放置展开按钮（`⌄`/`⌃`）和关闭按钮（`×`），圆环内部使用白色圆角方底包裹图标。新设计的 Windows 浮窗交互原型将体验简化为更贴近 Windows 11 桌面小组件的「毛玻璃胶囊 Dock + 悬浮详情卡（Popover）」形态：平时只展示干净的胶囊圆环条，悬停或点击某个模型圆环时再在上方弹出对应模型的详情卡。

### 目标

- 将 Windows 桌面浮窗重构为毛玻璃胶囊 Dock（4 模型基准 `256×64` DIP，圆角 `29`，空白区域拖拽并支持边缘吸附）。
- 新增与 Dock 联动的悬浮详情卡（Popover，`240×106` DIP 基准，圆角 `15`，底部对齐指示箭头随激活模型变化），展示 32px 圆形图标底、模型名、`5 小时额度` 副标题、`固定详情（Pin）`、`更多操作（···）`、5px 无百分比胶囊进度条、相对重置倒计时与相对更新时间。
- 在 `···` 菜单中提供「刷新额度」「打开主面板」「隐藏浮窗」。
- 升级模型圆环视觉：去掉圆环内白色方底，居中绘制品牌图标，采用原型配色（Codex `#6CA15A`、Claude Code `#F58A12`、Kimi Code `#367CF4`、MiniMax `#8B99AF` 未知虚线）。
- 浅色模式严格遵循原型毛玻璃与文字配色；深色模式提供协调的深色毛玻璃与图标对比度，兼容现有 `light` / `dark` / `system` 主题设置。
- 保持浮窗区域（含 Dock 与 Popover）不出现百分比数字，并通过纯 C# 单元测试与 Windows 原生冒烟测试校验。

### 非目标

- 不更改 macOS 端 SwiftUI 菜单栏与卡片样式。
- 不更改 Windows 主窗口（`MainWindow`）的导航结构、统计逻辑或数据源采集实现。
- 不修改现有 `settings.json` 持久化结构的兼容性，不新增外部第三方 NuGet 依赖。

## 3. 现状与约束

- 必须遵守的 ADR / 规范：`docs/DEVELOPMENT.md`（标准化开发流程）、`docs/design/issue-24-windows-rings.md`（Windows 首版圆环与浮窗无百分比契约）、`PRIVACY.md`。
- 外部依赖与权限：沿用现有 `Microsoft.WindowsAppSDK` 1.8 与 Win32 `user32.dll` / `dwmapi.dll`，不引入新 NuGet 包或额外系统权限。

## 4. 复用声明

- 仓库是否已有该能力：部分已有。仓库已具备 Windows WinUI 3 浮窗生命周期管理、桌面毛玻璃背景、边缘吸附定位算法、模型圆环绘制与原生冒烟截图校验，但缺少胶囊 Dock 交互与悬浮详情 Popover 窗口及相对时间格式化能力。
- 搜过什么关键词：`FloatingWindow`、`RingView`、`WindowPlacement`、`DesktopAcrylicBackdrop`、`SmokeCapture`、`UsageModels`、`ProviderId`。
- 看过哪些既有实现：`windows/AIUsage.Windows/FloatingWindow.xaml`、`windows/AIUsage.Windows/FloatingWindow.cs`、`windows/AIUsage.Windows/RingView.cs`、`windows/AIUsage.Windows/Native.cs`、`windows/AIUsage.Windows/App.xaml.cs`、`windows/AIUsage.Windows/SmokeCapture.cs`、`windows/AIUsage.Core/UsageModels.cs`、`windows/AIUsage.Core/LocalSettings.cs`、`windows/AIUsage.Core.Tests/UsageTests.cs`。
- 为什么不能复用：既有 `FloatingWindow` 采用单窗口垂直堆叠列表与显式 `⠿`/`⌄`/`×` 按钮，无法直接呈现胶囊 Dock 与独立悬浮气泡详情卡（悬停切换、Pin 锁定、对齐箭头与上方/下方自适应翻转）；既有 `RingView` 硬编码白色圆角底块与旧色值，且 `AIUsage.Core` 尚未提供原型所需的中文相对重置倒计时、相对更新时间与 Popover 位置/箭头对齐纯计算逻辑。因此复用现有 `WindowPlacement.Fit`、`WindowHook`、`UsageMonitor`、`DesktopAcrylicBackdrop` 与 `SmokeCapture` 框架，并在其上扩展布局计算、详情 Popover 窗口与新版圆环样式。

## 5. 方案

### 核心流程

1. **Dock 渲染与交互（`FloatingWindow`）**：
   - 使用 `DesktopAcrylicBackdrop` + DWM 圆角属性 + `CornerRadius="29"` 胶囊 `Border`。
   - 根据 `app.VisibleSnapshots()` 数量通过 `FloatingLayout.ComputeDockSize` 计算宽度（4 模型时为 `256×64` DIP）。
   - 空白区域按下鼠标左键调用 Win32 `WM_NCLBUTTONDOWN`（`HTCAPTION`）拖动窗口，拖动开始时收起未固定详情卡，拖动结束调用 `FitAndRemember()` 吸附边缘并同步 Popover 位置。
   - 每个模型渲染 `44×44` 圆环按钮：悬停（`PointerEntered`）或点击/键盘激活时显示或切换 `FloatingDetailWindow`；指针离开 Dock 且未移入 Popover、未固定时延迟 `180ms` 自动收起；按 `Esc` 立即收起详情卡。
2. **悬浮详情卡（`FloatingDetailWindow`）**：
   - 作为与 `FloatingWindow` 联动的独立无边框置顶 WinUI 3 窗口，避免单窗口透明镂空在 WinUI 3 中的兼容性风险，并原生获得 `DesktopAcrylicBackdrop` 与独立 `RenderTargetBitmap` 冒烟截图能力。
   - 位置由 `FloatingLayout.PlacePopover` 计算：默认置于 Dock 上方 `13` DIP 处，若顶部空间不足自动翻转到 Dock 下方，同时计算水平 `ArrowX` 以对齐当前激活圆环中心。
   - 卡片内容按原型排布：顶部为 `32×32` 圆形图标底 + 模型名（`14px` SemiBold）+ `5 小时额度`（`11px` 辅色）+ Pin 按钮 + `···` 菜单按钮；中部为 `5px` 圆角进度条（未知状态半透明空槽，无任何 `%` 文本）；底部左为 `FloatingPresentation.FormatResetCountdown`，右为 `FloatingPresentation.FormatUpdatedAge`。
   - `···` 菜单使用 WinUI 原生 `MenuFlyout`，提供「刷新额度」「打开主面板」「隐藏浮窗」。
3. **主题与视觉适配**：
   - 浅色模式采用原型色值：毛玻璃底 `rgba(229, 237, 250, 0.78)`、描边 `rgba(255, 255, 255, 0.72)`、主文 `#172332`、辅文 `#647187`、图标底 `rgba(88, 112, 150, 0.12)`、进度槽 `rgba(96, 117, 152, 0.17)`。
   - 深色模式采用协调暗色毛玻璃：底 `rgba(28, 36, 50, 0.82)`、描边 `rgba(255, 255, 255, 0.16)`、主文 `#EEF3FA`、辅文 `#9EB0C8`、图标底 `rgba(255, 255, 255, 0.14)`、进度槽 `rgba(255, 255, 255, 0.16)`，并为深色下的黑色矢量图标提供浅色柔光圆形衬底确保清晰可见。
   - 当系统/应用主题切换或设置页修改主题时，`FloatingWindow.ApplyAppearance()` 同步更新 Dock 与 Popover。

### 接口与数据

- `AIUsage.Core.Providers.Color(ProviderId)`：更新为原型配色 `#6CA15A` / `#F58A12` / `#367CF4` / `#8B99AF`。
- 新增 `AIUsage.Core.FloatingPresentation`：
  - `FormatResetCountdown(UsageSnapshot snapshot, DateTimeOffset now)`
  - `FormatUpdatedAge(UsageSnapshot snapshot, DateTimeOffset now)`
- 新增 `AIUsage.Core.FloatingLayout`：
  - `ComputeDockSize(int providerCount)`
  - `RingCenterX(int dockWidth, int providerCount, int index)`
  - `PlacePopover(WindowPlacement dock, WindowPlacement workArea, int popoverWidth, int popoverHeight, int gap, double ringCenterX)`
- `Preferences` 保持现有字段与 JSON 兼容，不破坏历史配置文件。

### 受影响模块

| 模块 / 路径 | 修改内容 | 调用方或依赖 | 验证方式 |
|---|---|---|---|
| `windows/AIUsage.Core/UsageModels.cs` | 更新各模型圆环默认强调色至原型色板 | `RingView`、`FloatingDetailWindow` | `make windows-test` |
| `windows/AIUsage.Core/FloatingPresentation.cs` | 新增中文相对重置倒计时、相对更新时间与 Dock/Popover 几何布局纯函数 | `FloatingWindow`、`FloatingDetailWindow` | `make windows-test` 新增单元测试 |
| `windows/AIUsage.Core.Tests/UsageTests.cs` | 为相对时间格式化、Dock 尺寸、Popover 上下翻转与箭头对齐补充单元测试 | `AIUsage.Core` | `make windows-test` |
| `windows/AIUsage.Windows/Native.cs` | 新增 DWM 圆角属性辅助声明（`DwmSetWindowAttribute`） | `FloatingWindow`、`FloatingDetailWindow` | Windows CI 构建与冒烟 |
| `windows/AIUsage.Windows/RingView.cs` | 支持无白底胶囊圆环样式与深色模式图标可读性 | `FloatingWindow`、`MainWindow` | Windows CI 构建与冒烟 |
| `windows/AIUsage.Windows/FloatingWindow.xaml` & `.cs` | 重构为毛玻璃胶囊 Dock，空白区拖拽、悬停/点击联动详情卡、Esc 收起 | `App`、`SmokeCapture` | Windows CI 构建与冒烟 |
| `windows/AIUsage.Windows/FloatingDetailWindow.xaml` & `.cs` | 新增毛玻璃悬浮详情 Popover 窗口（Pin、`···` 菜单、无百分比进度条、对齐箭头） | `FloatingWindow`、`SmokeCapture` | Windows CI 构建与冒烟 |
| `windows/AIUsage.Windows/SmokeCapture.cs` | 验证 Dock 与 Popover 均无 `%` 文本并截取胶囊与详情卡冒烟图 | `App`、`windows/scripts/smoke.ps1` | Windows CI 原生冒烟 |
| `Sources/AIUsage/Views/SettingsView.swift`、`CHANGELOG.md`、`docs/changelog/` | 同步 About 说明与变更记录 | 发布与流程检查 | `make verify` |

## 6. 异常、安全与兼容性

- 失败处理：当 `DwmSetWindowAttribute` 在旧版系统或特殊会话不可用时静默降级至 XAML `Border.CornerRadius`；当 `VisibleSnapshots()` 为空时仍保留最小胶囊尺寸不崩溃；指针离开或窗口隐藏时清理定时器并关闭详情卡。
- 安全与隐私：仅展示本地聚合的 5 小时额度进度、重置倒计时与更新时间，不输出任何用户日志、密钥或额外网络请求。
- 兼容与迁移：复用现有 `settings.json` 与 `FloatingX/Y/Display` 持久化，平滑升级无需数据迁移。

## 7. 可观测性与埋点

不新增外部遥测或埋点。沿用现有 `--smoke-test` 轨迹文件（`smoke-progress.json`、`smoke.json`、`floating-compact.png`、`floating-expanded.png`）记录冒烟阶段与渲染截图。

## 8. 验证与发布

- 自动验证：本地运行 `make windows-test`（.NET Core 单元测试）与 `make verify`（流程检查、WorkflowTests、macOS Swift 测试与版本校验）；PR 推送后由 GitHub Actions Windows runner 执行 WinUI 3 Release 构建与原生 `--smoke-test` 冒烟校验。
- 人工验证：由于当前开发环境为 macOS，Windows 实机视觉渲染、毛玻璃质感与鼠标悬停/拖拽手感需在 Windows 环境或 CI 冒烟截图产物中复核，并在变更记录中明确标注未在本地 Windows 实机验证。
- 发布与回滚：通过 PR 合入 `main` 后由 `Automatic release` 走既有受保护分支发布流程；如出现 Windows UI 异常，可直接回滚本 PR 提交恢复旧版 `FloatingWindow`。

## 9. 待决策项

- N/A — 远程 Issue 创建、深色模式毛玻璃适配及 `···` 菜单保留「打开主面板」均已与用户确认，无阻塞项。
