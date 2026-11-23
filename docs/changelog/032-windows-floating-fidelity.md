# 032：Windows 浮窗轮廓裁剪、原生三角箭头与过渡动效还原度优化

- 日期：2026-11-23
- 类型：feature
- 关联 Issue：[#38](https://github.com/YuSec2021/ai-usage-display/issues/38)
- 准备记录：`docs/issues/issue-38.json`、`docs/issues/issue-38-windows-floating-fidelity.md`、`docs/design/issue-38-windows-floating-fidelity.md`

## 变更说明

- **精准 HWND 轮廓裁剪（`Native.cs`、`FloatingWindow.cs`、`FloatingDetailWindow.cs`）**：去除 Win32 残留框线并改用 `SetWindowRgn` 裁剪 `29` DIP 胶囊 Dock 与带 `9` DIP 独立箭头区的详情卡（总高 `115` DIP），在窗口尺寸、DPI 与活动模型变化时同步更新，避免虚拟机中 DWM 默认圆角不生效或残留矩形外框。
- **圆环与图标视觉统一（`RingView.cs`、`FloatingDetailWindow.xaml`）**：胶囊圆环线宽调整为 `2.6` DIP，圆环与详情卡头像统一改用 WinUI `BitmapIcon` 单色前景，浅/深模式只切语义前景，去除深色亮圆底并保持未知状态虚线环。
- **原生三角箭头、进出场动效与动画重入修复（`FloatingDetailWindow.cs`、`FloatingPresentation.cs`）**：将指示横条替换为同表面色原生 `Polygon` 三角箭头；增加 WinUI `Storyboard` 淡入/轻移/轻缩放动效与快速重入取消退出保护；修复主题切换或定时刷新触发 `Reposition` 时同目标 `arrowTimer` 动画被错误重启的问题。
- **测试与文档（`UsageTests.cs`、`SmokeCapture.cs`、`docs/windows/`）**：扩展 1–4 模型与多 DPI 几何单测、原生 HWND 轮廓与浅/深双主题冒烟校验，并同步 Windows 文档截图。

## 验证记录

- 已通过：`make verify`（准备门禁、34 项 WorkflowTests、About/变更日志检查、90 项 macOS Swift 测试与版本校验）。
- 已通过（本地 Parallels Windows 11 `winbuild`）：`AIUsage.Core.Tests`（22/22 通过）、`dotnet publish`（`win-x64` 自包含 Release）、AMD64 PE 架构校验与原生 WinUI 3 `--smoke-test`（含 HWND 轮廓、活动三角对齐、浅/深双主题与退出重入断言）。
- 边界说明：本地 `winbuild` 在 Windows 11 ARM64 虚拟机的 x64 兼容层下完成构建与冒烟校验，原生系统 Acrylic 材质与真实 x64 Windows 硬件桌面交互、真实额度刷新仍需实机复核。
