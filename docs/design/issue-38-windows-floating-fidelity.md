# Windows 浮窗轮廓裁剪、原生三角箭头与过渡动效还原度优化：模块设计

## 1. 基本信息

- ISSUE：https://github.com/YuSec2021/ai-usage-display/issues/38
- 状态：已确认
- 负责人：AI Usage 维护者
- 更新日期：2026-11-23

## 2. 背景与目标

### 背景

`v1.2.9` 合并了 Windows 毛玻璃胶囊浮窗与悬浮详情卡首版（Issue #35），但在实机与虚拟机环境下仍有原型还原度偏差：
1. DWM 默认圆角只提供系统固定半径，无法贴合 `29` DIP 胶囊外框和底部带 `9` DIP 三角箭头的详情卡轮廓，且微软文档明确虚拟机环境不保证 DWM 圆角生效；
2. 详情卡指示器仍为横条 `Border`，并非与卡片融合的原生三角箭头 `Polygon`；
3. 胶囊圆环线宽偏粗（`3.2` DIP），深色模式仍使用浅色圆底衬板而非 `BitmapIcon` 单色前景；
4. 详情卡缺少淡入/轻移/轻缩放进出场过渡与箭头平滑滑动；同时当 `ActualThemeChanged` 或定时 `Render()` 在箭头滑动过程中触发 `Reposition` 时，若不判断目标是否变化，会错误重启 `180ms` 动画，导致三角指示器区域更新延迟与原生冒烟失败。

### 目标

- 去除 Win32 残留框线并引入 `SetWindowRgn` 自定义轮廓裁剪：Dock 使用 `CreateRoundRectRgn` 按尺寸/DPI 裁剪 `29` DIP 胶囊；详情卡预留 `9` DIP 独立箭头区（总高 `106 + 9 = 115` DIP），联合圆角卡片与三角箭头区域并在尺寸、DPI、箭头位置变化时刷新。
- 胶囊圆环线宽调整为 `2.6` DIP，圆环与详情卡头像统一使用 WinUI `BitmapIcon` 单色前景，深/浅色只切换语义前景，无真实额度维持虚线环。
- 详情卡指示器升级为同表面色原生 `Polygon` 三角箭头；补齐 `Storyboard` 淡入/轻移/轻缩放进出场动效与快速重入打断保护，并在系统禁用动画时直达终态。
- 修复 `FloatingDetailWindow.Reposition` 在同目标动画进行中重复 `Stop()`/`Restart()` `arrowTimer` 的缺陷。
- 移除系统托盘按单个模型拆分的多个图标，改为 1 个统一的应用托盘图标（使用 `Assets/app.ico`）。
- 将浮窗拖拽改为基于 `CapturePointer` + `GetCursorPos` + `SetWindowPos(SWP_NOSIZE|SWP_NOZORDER|SWP_NOACTIVATE)` 的轻量跟手拖拽，起拖立即隐藏非固定详情卡并在拖拽期间暂缓 `Floating.Refresh()` 重建。
- 扩展纯几何与拖拽阈值单元测试，以及原生 `SmokeCapture`（校验单托盘图标、实际 HWND 轮廓、浅/深双主题截图与重入打断），通过 `make verify` 与本地 `winbuild`。

### 非目标

- 不修改 macOS 端界面、Provider 数据抓取逻辑或 `settings.json` 持久化结构。
- 不替换或伪造系统 `DesktopAcrylicBackdrop` 材质（文档与截图不声称原生 Acrylic 与浏览器 CSS 逐像素一致）。

## 3. 现状与约束

- 必须遵守的 ADR / 规范：`docs/DEVELOPMENT.md`、`docs/design/issue-35-windows-floating-dock.md`、`PRIVACY.md`。
- 外部依赖与权限：仅使用 Win32 `user32.dll` / `gdi32.dll` / `dwmapi.dll` 与 `Microsoft.WindowsAppSDK` 1.8 内置控件，不新增 NuGet 依赖。

## 4. 复用声明

- 仓库是否已有该能力：部分已有。仓库已在 Issue #35 中实现毛玻璃胶囊 `FloatingWindow`、独立详情窗口 `FloatingDetailWindow`、`FloatingLayout` 几何计算与 `SmokeCapture` 冒烟框架，但缺少 HWND 区域裁剪、原生三角箭头 `Polygon`、`BitmapIcon` 单色前景与 `Storyboard` 进出场动效。
- 搜过什么关键词：`FloatingWindow`、`FloatingDetailWindow`、`RingView`、`ApplyRoundedCorners`、`PlacePopover`、`caretIndicator`、`SmokeCapture`。
- 看过哪些既有实现：`windows/AIUsage.Windows/FloatingWindow.xaml`、`windows/AIUsage.Windows/FloatingWindow.cs`、`windows/AIUsage.Windows/FloatingDetailWindow.xaml`、`windows/AIUsage.Windows/FloatingDetailWindow.cs`、`windows/AIUsage.Windows/RingView.cs`、`windows/AIUsage.Windows/Native.cs`、`windows/AIUsage.Windows/SmokeCapture.cs`、`windows/AIUsage.Core/FloatingPresentation.cs`、`windows/AIUsage.Core.Tests/UsageTests.cs`。
- 为什么不能复用：既有 `Native.ApplyRoundedCorners` 仅设置 DWM 默认圆角，无法表达 `29` DIP 胶囊与外凸三角箭头的复合窗口区域；既有 `caretIndicator` 为矩形横条且无过渡动效；既有 `RingView` 使用彩色/深色底板 `Image` 而非随主题切换语义前景的 `BitmapIcon`。因此复用现有窗口生命周期、`FloatingLayout.PlacePopover` 与 `SmokeCapture` 框架，并在其上扩展区域裁剪、箭头多边形、过渡动效与同目标重入保护。

## 5. 方案

### 核心流程

1. **Win32 框线清理与区域裁剪（`Native.cs`）**：
   - `ConfigureFloatingFrame(handle)` 移除残留标题栏/边框样式并关闭 DWM 默认圆角（`DWMWA_WINDOW_CORNER_PREFERENCE = 1`），由 `SetWindowRgn` 提供跨实机/虚拟机一致的轮廓。
   - `ApplyFloatingRegion(...)` 通过 `CreateRoundRectRgn` 与可选 `CreatePolygonRgn` + `CombineRgn(RGN_OR)` 生成窗口区域；`SetWindowRgn` 成功后由系统接管 `HRGN` 所有权不再释放，失败时在 `finally` 释放避免 GDI 泄漏。
   - 提供 `WindowRegionContains(handle, x, y)` 供原生冒烟验证实际 HWND 轮廓与三角尖端坐标。
2. **胶囊圆环与单色前景（`RingView.cs`、`FloatingWindow.*`）**：
   - 胶囊圆环线宽统一为 `2.6` DIP，中心图标使用 `BitmapIcon`（`ShowAsMonochrome = true`，18 DIP）随主题切换语义前景，无深色亮圆底。
   - `FloatingWindow` 在 `Refresh()` 和 `FitAndRemember()` 调整大小后同步重新应用胶囊 `HRGN`。
3. **详情卡原生三角箭头、过渡动效与同目标重入保护（`FloatingDetailWindow.*`、`FloatingPresentation.cs`）**：
   - `FloatingLayout.PopoverHeight = PopoverCardHeight + CaretHeight`（`115` DIP），为上下翻转时的原生 `Polygon` 三角预留 `9` DIP 空间。
   - `Storyboard` 驱动 `Opacity` / `TranslateY` / `ScaleX` / `ScaleY` 进出场动效；退出期间重入悬停/显示会立即取消退出并保留窗口；系统关闭动画时直接设置终态。
   - **同目标动画保护**：在 `Reposition(placement, scale)` 中，如果 `arrowTimer.IsEnabled`、窗口 `Bounds` 与 `PlacedAbove` 未变化，且新的 `target` 与当前正在动画的 `arrowTarget` 差值 `<= 0.1` DIP，则不停止、不重启 `arrowTimer`，避免主题切换事件或定时 `Render()` 打断正在进行的箭头滑动。
4. **单托盘图标与轻量跟手拖拽（`TrayIcons.cs`、`FloatingWindow.cs`、`Native.cs`、`FloatingPresentation.cs`）**：
   - `TrayIcons` 改为仅注册 1 个固定 GUID 的应用托盘图标（加载 `Assets/app.ico`），`Update` 仅刷新提示文本而不反复重绘多个模型位图，保留左键打开主面板与右键菜单。
   - `FloatingWindow` 放弃同步 `WM_NCLBUTTONDOWN(HTCAPTION)`，通过 `PointerPressed`（`handledEventsToo: true`）捕获指针，移动超过 `4` DIP 阈值后直接调用 `Native.MoveWindowPosition`（`SetWindowPos` 仅改位置、不改尺寸与 Z 序）1:1 跟随鼠标；起拖立即 `detail.HideDetail(immediate: true)` 并暂缓拖拽期间的 `Refresh()` 重建，松手后执行一次 `FitAndRemember()` 与延迟刷新。
5. **冒烟校验与文档（`SmokeCapture.cs`、`windows/scripts/smoke.ps1`、`UsageTests.cs`、`docs/windows/`）**：
   - `UsageTests.cs` 覆盖 1–4 模型宽度、多 DPI、上下翻转几何与拖拽阈值断言。
   - `SmokeCapture.cs` 与 `smoke.ps1` 校验单托盘图标（`trayIcons == 1`）、等待箭头动画收敛后再校验实际 HWND 轮廓、浅/深双主题截图与退出动画重入打断。

### 接口与数据

- `AIUsage.Core.FloatingLayout` 新增常量 `PopoverHeight = PopoverCardHeight + CaretHeight`（`115`）。
- `AIUsage.Windows.Native` 新增 `ConfigureFloatingFrame`、`ApplyFloatingRegion`、`WindowRegionContains`。
- `Preferences` 与 `settings.json` 结构无变化，完全向后兼容。

### 受影响模块

| 模块 / 路径 | 修改内容 | 调用方或依赖 | 验证方式 |
|---|---|---|---|
| `windows/AIUsage.Core/FloatingPresentation.cs` | 新增 `PopoverHeight` 常量统一卡片与箭头总高度 | `FloatingWindow`、`UsageTests` | `winbuild` `core-tests` |
| `windows/AIUsage.Core.Tests/UsageTests.cs` | 补充 1–4 模型宽度、多 DPI 与上下翻转几何测试 | `AIUsage.Core` | `winbuild` `core-tests` |
| `windows/AIUsage.Windows/Native.cs` | 新增无框样式清理、`SetWindowRgn` 复合轮廓裁剪与区域查询 | `FloatingWindow`、`FloatingDetailWindow`、`SmokeCapture` | `winbuild` 编译与冒烟 |
| `windows/AIUsage.Windows/RingView.cs` | 胶囊圆环线宽 `2.6` DIP，改用 `BitmapIcon` 单色前景 | `FloatingWindow`、`MainWindow` | `winbuild` 冒烟截图 |
| `windows/AIUsage.Windows/FloatingWindow.*` | 接入无框样式与胶囊 `SetWindowRgn`，统一点击/悬停联动 | `App`、`SmokeCapture` | `winbuild` 冒烟 |
| `windows/AIUsage.Windows/FloatingDetailWindow.*` | 原生 `Polygon` 三角箭头、`Storyboard` 动效、同目标 `arrowTimer` 重入保护 | `FloatingWindow`、`SmokeCapture` | `winbuild` 冒烟与截图 |
| `windows/AIUsage.Windows/SmokeCapture.cs` & `App.xaml.cs` | 校验实际 HWND 轮廓、双主题截图与动画重入，增强轮廓失败诊断信息 | `windows/scripts/smoke.ps1` | `winbuild` 原生冒烟 |
| `docs/windows/README.md`、`docs/windows/screenshots/`、`Sources/AIUsage/Views/SettingsView.swift`、`CHANGELOG.md`、`docs/changelog/` | 更新 Windows 说明、截图、About 与 `032` 变更记录 | 发布与流程检查 | `make verify` |

## 6. 异常、安全与兼容性

- 失败处理：`SetWindowRgn` 失败时释放临时 `HRGN` 并静默回退至 XAML 边界；系统关闭动画时跳过 `Storyboard` 直达终态；窗口关闭/隐藏时停止所有定时器与动画。
- 安全与隐私：仅在匿名 fixture 下执行原生冒烟，不读取用户真实日志、密钥或安装覆盖已装应用。
- 兼容与迁移：不修改 `settings.json` 格式，直接覆盖升级无迁移成本。

## 7. 可观测性与埋点

不新增外部遥测或埋点。沿用 `--smoke-test` 的 `smoke.json`、`smoke-error.json`、`smoke-progress.json` 与双主题 PNG 截图作为验证证据。

## 8. 验证与发布

- 自动验证：本地执行 `make verify`（准备门禁、WorkflowTests、Swift 测试、版本校验）与本地 `winbuild`（`AIUsage.Core.Tests`、`win-x64` Release 打包、AMD64 PE 校验与原生 WinUI 3 冒烟）。
- 人工验证：目视核对 `winbuild` 生成的 `floating-light-dock.png`、`floating-light-detail.png`、`floating-dark-dock.png`、`floating-dark-detail.png`；真实 x64 硬件桌面交互与真实额度刷新待实机复核并在变更记录中说明。
- 发布与回滚：按受保护 `main` PR 流程合入，异常时直接回滚本 PR 即可恢复 `v1.2.9` 浮窗实现。

## 9. 待决策项

- N/A — 本轮需求与严格标准化流程已与用户确认，无阻塞项。
