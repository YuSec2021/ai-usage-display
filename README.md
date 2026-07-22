# AI Usage for macOS

AI Usage 是一个原生 macOS 菜单栏应用，用于查看 Codex 与 Claude Code 的本机使用情况、订阅额度窗口和重置时间。

> 当前版本：1.0.0。仓库包含原生 macOS 工程、Codex/Claude Code/Claude Desktop 数据采集、三态主题、历史图表、设置页、测试和视觉原型。

## 产品目标

- 在菜单栏中同时查看 Codex 和 Claude Code 的额度使用率。
- 展示短周期、长周期额度及准确的重置时间。
- 汇总本机每日和每周 token 使用情况。
- 支持浅色、深色和跟随系统三种外观模式。
- 全程本地处理，不读取凭证，不上传对话或代码内容。
- 当 CLI 未安装、尚无数据或数据格式发生变化时，给出可恢复的状态提示。

## 文档导航

- [项目文档](docs/PROJECT.md)：产品目标、范围、需求、验收标准与路线图。
- [开发文档](docs/DEVELOPMENT.md)：技术栈、数据采集、实现步骤、测试和发布。
- [架构文档](docs/ARCHITECTURE.md)：模块边界、数据流、模型和安全设计。
- [原型说明](docs/PROTOTYPE.md)：视觉原型、交互规则和界面状态。

## 技术栈

- Swift 6、SwiftUI、macOS 13+
- `MenuBarExtra` 菜单栏窗口
- Swift Concurrency
- SwiftUI `preferredColorScheme` 与 `AppStorage` 主题偏好
- Foundation JSON 解码
- 可配置后台刷新与最近 7 天范围扫描
- Swift Testing / XCTest
- 可选：Sparkle 自动更新

## 本地运行

环境要求：macOS 13+、Xcode 15+。仓库已经包含生成后的 `AIUsage.xcodeproj`；如修改了 `project.yml`，需要安装 XcodeGen 后重新生成工程。

```bash
open AIUsage.xcodeproj
```

在 Xcode 中选择 `AIUsage` scheme 和 `My Mac`，然后运行。也可以在终端构建：

```bash
xcodebuild -project AIUsage.xcodeproj \
  -scheme AIUsage \
  -configuration Debug \
  -derivedDataPath .build/xcode \
  CODE_SIGNING_ALLOWED=NO build
```

首次运行后，在“设置 → 集成”中安装 Claude Code 用量集成。安装器会备份现有 `statusLine` 配置，卸载时自动恢复。

## 直接构建发布包

在尚未配置 Apple Developer Team ID 时，可以生成带临时签名的 Release DMG：

```bash
./scripts/build-direct-release.sh
```

构建结果位于 `dist/AI-Usage-1.0.0.dmg`，并同时生成 SHA-256 校验文件。该版本没有 Developer ID 签名，也没有经过 Apple 公证。其他用户首次打开时，需要在 Finder 中右键应用并选择“打开”；如果系统仍然阻止运行，请前往“系统设置 → 隐私与安全性”选择“仍要打开”。

正式配置 Apple Developer Team ID 后，应改用 Developer ID 签名并提交 Apple 公证，不再发布临时签名构建。

## 隐私原则

应用只提取用量字段，不保存提示词、回答、工具调用参数、源代码或登录凭证。应用不会读取 `~/.codex/auth.json`、浏览器 Cookie 或 Claude Code 的认证信息。

完整说明见 [PRIVACY.md](PRIVACY.md)。

## 预计里程碑

1. 完善增量文件监听与大日志性能。
2. 扩展更多模型用量 Provider。
3. 配置 Developer ID 签名与 Apple 公证。
4. 增加自动更新和用量阈值通知。

详细计划见 [项目文档](docs/PROJECT.md)。
