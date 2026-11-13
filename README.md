# AI Usage for macOS

AI Usage 是一个原生 macOS 菜单栏应用，用于查看 Codex、Claude Code、Kimi Code 与 MiniMax 的本机使用情况，以及可用的订阅额度窗口和重置时间。

> 当前版本：1.2.3。仓库包含原生 macOS 工程、Codex/Claude Code/Claude Desktop/Kimi Code/MiniMax 数据采集、三态主题、历史图表、设置页、测试和视觉原型。

## 产品目标

- 在菜单栏中同时查看 Codex、Claude Code、Kimi Code 和 MiniMax 的用量。
- 在用量详情中上下拖动模型卡片调整优先级，重启应用后仍保留顺序。
- 展示短周期、长周期额度及准确的重置时间。
- 汇总本机每日和每周 token 使用情况。
- 支持浅色、深色和跟随系统三种外观模式。
- macOS 26+ 使用原生 Liquid Glass，支持实时调整并保存背景透明度；旧系统使用兼容材质。
- 菜单栏以模型图标及外圈显示 5 小时已用额度，Codex 使用 ChatGPT 图标；悬停可查看准确百分比。
- 全程本地处理，不读取凭证，不上传对话或代码内容。
- 当 CLI 未安装、尚无数据或数据格式发生变化时，给出可恢复的状态提示。

## 文档导航

- [项目文档](docs/PROJECT.md)：产品目标、范围、需求、验收标准与路线图。
- [开发文档](docs/DEVELOPMENT.md)：技术栈、数据采集、实现步骤、测试和发布。
- [架构文档](docs/ARCHITECTURE.md)：模块边界、数据流、模型和安全设计。
- [原型说明](docs/PROTOTYPE.md)：视觉原型、交互规则和界面状态。
- [项目更新流程](AGENTS.md)：每次变更的 About、日志、测试与版本要求。
- [标准开发流程技能](.agents/skills/standard-dev-flow/SKILL.md)：从 `ai_novel_agent` 完整复制的 Issue 准备、类型门禁与模块拆解技能，含 Issue 和模块设计模板。
- [变更记录与索引](docs/changelog/README.md)：逐次变更、验证结果及未验证范围；发布摘要见 [CHANGELOG.md](CHANGELOG.md)。

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

运行要求：macOS 13+；原生液态玻璃效果需要 macOS 26+。构建需要带 macOS 26 SDK 的 Xcode 26+。仓库已经包含生成后的 `AIUsage.xcodeproj`；如修改了 `project.yml`，需要安装 XcodeGen 后运行 `make generate` 重新生成工程。

统一开发入口为 `make help`；提交前运行 `make verify`，检查更新记录、运行测试并核对构建后的版本。该命令不发布或安装应用，完整步骤见[标准化开发流程](docs/DEVELOPMENT.md#0-标准化开发流程)。

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

在“设置 → 通用 → 玻璃透明度”中拖动滑块，可将背景透明度设为 0–100%，偏好会自动保存。该设置只调节背景，文字与图标保持清晰；系统启用“减少透明度”时优先使用实色背景。

菜单栏和详情卡片的主圆环表示 **5 小时已用额度**，从顶部顺时针填充。没有可靠的 5 小时数据时显示虚线圆环，不将周额度或 Token 数量作为替代；详情中其他额度窗口单独标明。菜单栏原有“最高用量”偏好现在显示最高 5 小时用量的模型圆环，不再显示数字；也可选择各模型圆环或仅模型图标。准确百分比保留在悬停提示和 VoiceOver 中。

Codex 的额度通过本机已登录的 `codex app-server` 官方只读接口主动读取，打开面板时也会立即刷新，重置后无需先发送消息。应用从 PATH、`/opt/homebrew/bin/codex`、`/usr/local/bin/codex` 、`~/.local/bin/codex` 和 `/Applications/ChatGPT.app` 的内置 CLI 查找可执行文件；若 CLI 缺失、未登录、接口不支持或请求超过 8 秒，则回退到本地会话日志。离线旧窗口会提示等待更新，不推算当前百分比。本地 Token 仍从会话日志统计。CLI 自行管理现有认证，AI Usage 不读取凭证文件，不创建对话或生成请求。协议见 [OpenAI 官方 App Server 文档](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt)。

Claude Code 的“刷新”会重新读取本地用量文件，不会主动向 Claude 请求订阅额度。完成一次 Claude Code 对话后，status line 才能写入新的额度样本。已超过重置时间的额度不会继续显示为当前值；未知重置时间的样本最多保留对应的 5 小时或 7 天窗口。缺少额度样本时，仍可显示本地 Token 统计。

Kimi Code 的本地 Token 无需安装额外集成。应用会读取 `$KIMI_CODE_HOME/sessions`（默认 `~/.kimi-code/sessions`）中的 `usage.record` 用量事件，并兼容旧版 `~/.kimi/sessions` 的状态事件。安装 Kimi Desktop 后，还会从 `~/Library/Logs/kimi-desktop/main.log` 读取订阅总额度百分比和刷新日期。

如需显示 Kimi Code 的 5 小时与每周额度，请在“设置 → 集成 → Kimi Code”中填写从 Kimi Code 控制台获取的 API Key。Key 只保存在 macOS 钥匙串中，应用使用它直接请求 `https://api.kimi.com/coding/v1/usages`；不会发送到开发者服务器。也可在开发环境通过 `KIMI_API_KEY` 环境变量提供。

MiniMax 只读取 MiniMax Desktop Chromium HTTP 缓存目录
`~/Library/Application Support/MiniMax/Cache/Cache_Data` 中官方订阅额度接口的最近一次完整响应。应用选择 `model_name == "general"` 的套餐记录，兼容新版 Brotli 压缩、`"24%"` 形式的已用百分比与旧版明文剩余百分比，展示 5 小时用量、周额度及重置时间。周额度无限制时直接显示“无限制”，不当作 0% 的有限额度；缓存正写入或损坏时保留并标记上次有效样本。刷新会重新读取此缓存；MiniMax Desktop 尚未写入新响应时，请先打开 MiniMax Code 的额度面板。已过期短窗口不会继续显示为当前用量。该缓存仍是 MiniMax 用量卡片的唯一事实源；应用不使用 Claude Code 会话推算 MiniMax 用量，也不读取 API 日志、Cookie 或对话内容。MiniMax Desktop 当前没有提供可用于每日汇总的历史 Token 数据，因此 MiniMax 不出现在 Token 历史图表中。

MiniMax 无需 API Key；设置只保留本地缓存状态和更新说明。旧版本保存的 MiniMax API Key 与区域偏好不会被自动读取或删除，需要清理遗留 Key 时可使用 macOS“钥匙串访问”。

## 直接构建发布包

在尚未配置 Apple Developer Team ID 时，可以生成带临时签名的 Release DMG：

```bash
./scripts/build-direct-release.sh
```

构建结果位于 `dist/AI-Usage-1.2.3.dmg`，并同时生成 SHA-256 校验文件。该版本没有 Developer ID 签名，也没有经过 Apple 公证。其他用户首次打开时，需要在 Finder 中右键应用并选择“打开”；如果系统仍然阻止运行，请前往“系统设置 → 隐私与安全性”选择“仍要打开”。

正式配置 Apple Developer Team ID 后，应改用 Developer ID 签名并提交 Apple 公证，不再发布临时签名构建。

## 自动构建 Release

[Automatic release 工作流](.github/workflows/auto-release.yml) 在代码合入或推送到 `main` 后自动执行：补丁版本与构建号各加一，同步 Xcode 工程、README 和发布记录，提交版本后创建 `vX.Y.Z` Tag，再调用 [Release 工作流](.github/workflows/release.yml) 构建并发布。开发分支不用手动升版；例如 `1.2.1 (5)` 会自动变为 `1.2.2 (6)`。

工作流会校验 Tag 与项目版本、运行测试、构建含 Apple Silicon/Intel 两种架构的通用 DMG、验证临时签名和 SHA-256，然后上传 Actions Artifact，并为该 Tag 创建或更新 GitHub Release，附上 `.dmg` 和 `.dmg.sha256`。构建或验证失败时不会执行发布；重跑同一 Tag 会更新其附件。

流程使用内置 `GITHUB_TOKEN`，通过 `workflow_call` 显式衔接构建，不依赖机器人推送 Tag 触发新事件，也不会循环升版。版本提交与 Tag 原子推送，不覆盖新提交或已有 Tag。若构建失败，可在「Actions → Automatic release → Run workflow」重试；main 仍指向已标记的版本提交时，会复用同一版本。

仍保留推送版本 Tag 和「Actions → Release → Run workflow」指定已有 Tag 的单独重建入口，明确检出 `refs/tags/<tag>`。无需额外 PAT 或 Apple 签名密钥；产物仍为临时签名、未公证版本，发布说明会明确标注。

## 隐私原则

应用只提取用量字段，不保存提示词、回答、工具调用参数或源代码。用户主动配置的 Kimi Code API Key 只保存在 macOS 钥匙串；应用不会读取 `~/.codex/auth.json`、浏览器 Cookie 或其他 Claude Code、Kimi Code、MiniMax 认证信息。

完整说明见 [PRIVACY.md](PRIVACY.md)。

## 预计里程碑

1. 完善增量文件监听与大日志性能。
2. 扩展更多模型用量 Provider。
3. 配置 Developer ID 签名与 Apple 公证。
4. 增加自动更新和用量阈值通知。

详细计划见 [项目文档](docs/PROJECT.md)。
