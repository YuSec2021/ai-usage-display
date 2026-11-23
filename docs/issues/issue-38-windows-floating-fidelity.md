# Windows 浮窗轮廓裁剪、原生三角箭头与过渡动效还原度优化

## 基本信息

- Issue：https://github.com/YuSec2021/ai-usage-display/issues/38
- 类型：`type/feature`
- 状态：待实施
- 工作分支：`codex/issue-38-windows-floating-fidelity`
- 负责人：AI Usage 维护者
- 设计或产出文档：`docs/design/issue-38-windows-floating-fidelity.md`

## 背景

`v1.2.9` 合并的 Windows 胶囊浮窗与悬浮详情卡首版依赖 DWM 默认圆角与横条指示器，在实机/虚拟机下存在胶囊与三角箭头轮廓不够贴合原型、深色模式图标衬底偏重、缺少进出场动效，以及主题切换/定时刷新触发 `Reposition` 时同目标 `arrowTimer` 动画被意外重启的问题。

## 目标

- 使用 Win32 无框样式清理与 `SetWindowRgn` 实现精准的 `29` DIP 胶囊轮廓和带 `9` DIP 原生三角箭头的详情卡轮廓。
- 将胶囊圆环线宽调整为 `2.6` DIP，统一使用 WinUI `BitmapIcon` 单色前景适配浅/深双主题。
- 将详情卡指示器替换为同表面色原生 `Polygon` 三角箭头，补齐 `Storyboard` 进出场动效与快速重入打断保护，并修复同目标 `Reposition` 重启 `arrowTimer` 动画的问题。
- 扩充纯几何单元测试、双主题原生冒烟轮廓校验与截图文档，通过 `make verify` 与本地 `winbuild`。

## 非目标

- 不修改 macOS 端 SwiftUI 界面、Provider 数据采集逻辑或 `settings.json` 持久化结构。
- 不声称原生系统 `DesktopAcrylicBackdrop` 与浏览器 CSS 毛玻璃逐像素相同。

## 根因说明

N/A — 当前类型为 `type/feature`，不需要根因说明。

## 验收标准

- [ ] Dock 与详情卡移除 Win32 残留框线并通过 `SetWindowRgn` 裁剪出胶囊轮廓及带 `9` DIP 三角箭头的复合轮廓，且在尺寸、DPI、活动模型变化时同步更新。
- [ ] 胶囊圆环线宽为 `2.6` DIP，圆环与详情卡头像使用 `BitmapIcon` 单色前景，无深色亮圆底；无真实额度保持虚线环。
- [ ] 详情卡具备原生 `Polygon` 三角箭头、`Storyboard` 淡入/轻移/轻缩放动效与快速重入保护；同目标 `Reposition` 不会打断或重启进行中的 `arrowTimer` 动画。
- [ ] `AIUsage.Core.Tests` 扩展几何测试与原生 `SmokeCapture`（实际 HWND 轮廓、双主题、动画重入）在本地 `winbuild` 全部通过。
- [ ] `make verify` 全部通过，About 与 `032` 编号变更记录、Windows 截图文档同步更新。

## 模块拆解

| 模块 / 路径 | 修改内容 | 依赖 | 完成条件 |
|---|---|---|---|
| `windows/AIUsage.Core/FloatingPresentation.cs` & `UsageTests.cs` | 新增 `PopoverHeight` 常量并补充多模型/多 DPI/翻转几何测试 | 无 | `winbuild` `core-tests` 全绿 |
| `windows/AIUsage.Windows/Native.cs` & `RingView.cs` | 无框样式清理、`SetWindowRgn` 轮廓裁剪、`2.6` DIP 单色前景圆环 | `AIUsage.Core` | 编译与原生冒烟通过 |
| `windows/AIUsage.Windows/FloatingWindow.*` & `FloatingDetailWindow.*` | 胶囊/详情卡轮廓联动、原生 `Polygon` 箭头、`Storyboard` 动效与同目标 `arrowTimer` 保护 | `Native.cs`、`RingView.cs` | 轮廓、双主题与重入校验全绿 |
| `windows/AIUsage.Windows/SmokeCapture.cs` & `App.xaml.cs` | 新增实际 HWND 轮廓、双主题与动画重入冒烟断言及详细诊断输出 | `FloatingWindow`、`FloatingDetailWindow` | `winbuild` `smoke-test` 全绿 |
| `docs/windows/`、`Sources/AIUsage/Views/SettingsView.swift`、`CHANGELOG.md`、`docs/changelog/` | 同步 Windows 文档/截图、About 与 `032` 变更记录 | 实施与验证完成 | `make verify` 通过 |

## 风险、假设与待决策项

- 风险：`SetWindowRgn` 在高 DPI 与动画切换期间对坐标精度敏感，需严格验证 `HRGN` 所有权释放与动画终态时机。
- 假设：目标运行环境为 Windows 11，支持 WinUI 3 `BitmapIcon`、`Storyboard` 与 Win32 `SetWindowRgn`。
- 待决策：N/A — 无阻塞项。

## 验证计划

- 自动验证：本地运行 `make verify`（准备门禁、WorkflowTests、Swift 测试、版本检查）与本地 `winbuild`（`AIUsage.Core.Tests`、`win-x64` Release 构建、AMD64 PE 校验、原生 WinUI 3 `--smoke-test`）。
- 人工验证：目视核对 `winbuild` 生成的浅/深双主题 Dock 与详情卡原生截图；真实 x64 Windows 硬件桌面交互与真实额度刷新待实机复核并在变更记录中说明。
- 埋点与可观测性：不新增外部遥测；复用 `--smoke-test` 的 `smoke.json` 与截图产物观察渲染与轮廓结果。
- 发布与回滚：按受保护 `main` PR 流程合入；异常时直接回滚本 PR 提交即可恢复 `v1.2.9` 实现。

## 完成定义

- [ ] 设计和拆解与最终实现一致。
- [ ] 所有验收标准已完成。
- [ ] 必要测试、评测、构建和审查已通过。
- [ ] 文档、埋点、迁移、发布及回滚事项已处理或明确标记不适用。
