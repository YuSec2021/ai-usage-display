# 030：Windows 毛玻璃胶囊浮窗与悬浮详情卡

- 日期：2026-11-22
- 类型：feature
- 关联 Issue：[#35](https://github.com/YuSec2021/ai-usage-display/issues/35)
- 准备记录：`docs/issues/issue-35.json`、`docs/issues/issue-35-windows-floating-dock.md`、`docs/design/issue-35-windows-floating-dock.md`

## 变更说明

- **毛玻璃胶囊 Dock（`FloatingWindow`）**：按新原型将 Windows 桌面浮窗重构为 `256×64` DIP（4 模型基准）、圆角 `29` 的毛玻璃胶囊条，移除原版拖拽手柄 `⠿`、展开按钮 `⌄`/`⌃` 与关闭按钮 `×`，改为拖动空白区域移动并在松开后吸附屏幕边缘。
- **联动悬浮详情卡（`FloatingDetailWindow`）**：新增独立无边框毛玻璃 Popover 窗口（`240×106` DIP，圆角 `15`），悬停或点击圆环时自动弹出并把指示标识对齐当前圆环中心；顶部空间不足时自动翻转至 Dock 下方。详情卡包含 32px 圆形图标底、模型名、`5 小时额度`、固定详情（Pin）、`···` 更多操作菜单（刷新额度、打开主面板、隐藏浮窗）、5px 无百分比胶囊进度条、中文相对重置倒计时与相对更新时间。
- **圆环与深浅色适配（`RingView`、`UsageModels`）**：移除胶囊圆环内的白色方底并更新模型配色（Codex `#6CA15A`、Claude Code `#F58A12`、Kimi Code `#367CF4`、MiniMax `#8B99AF` 未知虚线）；浅色模式还原原型配色，深色模式提供匹配的深色毛玻璃与图标对比度衬底。
- **核心布局与格式化逻辑（`FloatingPresentation.cs`）**：抽离中文相对重置倒计时、相对更新时间、Dock 尺寸计算、圆环中心定位与 Popover 上下翻转/箭头对齐逻辑，并补充单元测试与原生冒烟校验更新。

## 验证记录

- 已通过：`make check-process`（准备门禁、34 项 WorkflowTests 与 About/变更日志检查）、`make test`（90 项 macOS Swift 测试全部通过）与 `./scripts/verify-release-version.sh`（版本 1.2.8 校验通过）。
- 未在本地验证：`make windows-test`（本机 macOS 未安装 `dotnet` SDK）、Windows 11 WinUI 3 Release 编译、原生 `--smoke-test` 截图渲染、桌面毛玻璃视觉效果及真实额度刷新，需在安装 .NET 10 SDK 的环境或 GitHub Actions Windows runner 中验证。
