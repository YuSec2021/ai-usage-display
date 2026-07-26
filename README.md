# AI Usage for macOS

AI Usage 是一个原生 macOS 菜单栏应用，用于查看 Codex、Claude Code、Kimi Code 与 MiniMax 的本机使用情况，以及可用的订阅额度窗口和重置时间。

> 当前版本：1.1.0。仓库包含原生 macOS 工程、Codex/Claude Code/Claude Desktop/Kimi Code/MiniMax 数据采集、三态主题、历史图表、设置页、测试和视觉原型。

## 产品目标

- 在菜单栏中同时查看 Codex、Claude Code、Kimi Code 和 MiniMax 的用量。
- 在用量详情中上下拖动模型卡片调整优先级，重启应用后仍保留顺序。
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

Kimi Code 的本地 Token 无需安装额外集成。应用会读取 `$KIMI_CODE_HOME/sessions`（默认 `~/.kimi-code/sessions`）中的 `usage.record` 用量事件，并兼容旧版 `~/.kimi/sessions` 的状态事件。安装 Kimi Desktop 后，还会从 `~/Library/Logs/kimi-desktop/main.log` 读取订阅总额度百分比和刷新日期。

如需显示 Kimi Code 的 5 小时与每周额度，请在“设置 → 集成 → Kimi Code”中填写从 Kimi Code 控制台获取的 API Key。Key 只保存在 macOS 钥匙串中，应用使用它直接请求 `https://api.kimi.com/coding/v1/usages`；不会发送到开发者服务器。也可在开发环境通过 `KIMI_API_KEY` 环境变量提供。

MiniMax 只读取 MiniMax Desktop Chromium HTTP 缓存目录
`~/Library/Application Support/MiniMax/Cache/Cache_Data` 中官方订阅额度接口的最近一次完整响应。应用选择 `model_name == "general"` 的套餐记录，展示 5 小时与本周已用百分比及重置时间。该缓存是 MiniMax 卡片的唯一事实源；应用不使用 Claude Code 会话推算 MiniMax 用量，也不读取 API 日志、API Key、Cookie 或对话内容。MiniMax Desktop 当前没有提供可用于每日汇总的历史 Token 数据，因此 MiniMax 不出现在 Token 历史图表中。

## 直接构建发布包

在尚未配置 Apple Developer Team ID 时，可以生成带临时签名的 Release DMG：

```bash
./scripts/build-direct-release.sh
```

构建结果位于 `dist/AI-Usage-1.1.0.dmg`，并同时生成 SHA-256 校验文件。该版本没有 Developer ID 签名，也没有经过 Apple 公证。其他用户首次打开时，需要在 Finder 中右键应用并选择“打开”；如果系统仍然阻止运行，请前往“系统设置 → 隐私与安全性”选择“仍要打开”。

正式配置 Apple Developer Team ID 后，应改用 Developer ID 签名并提交 Apple 公证，不再发布临时签名构建。

## 隐私原则

应用只提取用量字段，不保存提示词、回答、工具调用参数或源代码。除用户主动配置并保存至 macOS 钥匙串的 Kimi Code API Key 外，应用不会读取 `~/.codex/auth.json`、浏览器 Cookie、Claude Code、Kimi Code 或 MiniMax 的认证信息。

完整说明见 [PRIVACY.md](PRIVACY.md)。

## 预计里程碑

1. 完善增量文件监听与大日志性能。
2. 扩展更多模型用量 Provider。
3. 配置 Developer ID 签名与 Apple 公证。
4. 增加自动更新和用量阈值通知。

详细计划见 [项目文档](docs/PROJECT.md)。
