# AI Usage for macOS

[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](project.yml)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-007AFF)](Sources/AIUsage/Views)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white)](project.yml)
[![Xcode 26+](https://img.shields.io/badge/Xcode-26%2B-147EFB?logo=xcode&logoColor=white)](docs/DEVELOPMENT.md#1-技术选择)
[![XcodeGen](https://img.shields.io/badge/Build-XcodeGen-2C8EBB)](project.yml)

在 macOS 菜单栏，一眼查看 **Codex、Claude Code、Kimi Code 和 MiniMax** 的用量、额度窗口与重置时间。

> 当前版本：1.2.4。支持 Apple Silicon 与 Intel，运行需要 macOS 13+。

[下载最新版本](https://github.com/YuSec2021/ai-usage-display/releases/latest) · [使用指南](docs/USAGE.md) · [更新记录](CHANGELOG.md)

## 功能

- **额度一目了然**：菜单栏圆环显示 5 小时已用额度，详情展示其他可用额度窗口和重置时间。
- **最近 7 天用量**：查看 Codex、Claude Code、Kimi Code 的本地 Token 历史。
- **按习惯排列**：拖动卡片调整顺序，菜单栏显示优先级最高的前三个已选模型。
- **原生外观**：浅色、深色或跟随系统；macOS 26+ 支持 Liquid Glass 与透明度调节。
- **本地优先**：不上传提示词、回答或代码；主动配置的 Kimi API Key 保存在 macOS 钥匙串。

## 安装与接入

1. 从 [Releases](https://github.com/YuSec2021/ai-usage-display/releases/latest) 下载 DMG，将 **AIUsage** 拖入“应用程序”并打开。
2. 在菜单栏打开应用，进入“设置”选择要显示的模型。
3. 按下表接入数据：

| 模型 | 如何接入 |
| --- | --- |
| Codex | 安装并登录 Codex CLI，应用自动读取当前额度与本地 Token 用量。 |
| Claude Code | 在“设置 → 集成”安装用量集成，完成一次对话后更新额度。 |
| Kimi Code | 自动读取本地 Token；5 小时与每周额度需在“设置 → 集成”配置 Kimi Code API Key。 |
| MiniMax | 打开 MiniMax Code 的额度面板更新本地缓存，无需 API Key；不提供 Token 历史。 |

当前安装包采用临时签名，尚未经过 Apple 公证。首次打开若被阻止，可在 Finder 中右键选择“打开”，或前往“系统设置 → 隐私与安全性”选择“仍要打开”。

额度缺失、刷新方式与数据来源详见[使用指南](docs/USAGE.md)。

## 本地开发

需要 **Xcode 26+**（含 macOS 26 SDK）。仓库已包含生成的工程：

```bash
open AIUsage.xcodeproj
```

选择 `AIUsage` scheme 和 `My Mac` 后运行。开发命令见 `make help`，提交前运行 `make verify`；修改 `project.yml` 后需安装 XcodeGen 并运行 `make generate`。完整流程见[开发文档](docs/DEVELOPMENT.md)。

## 文档

[使用指南](docs/USAGE.md) · [隐私说明](PRIVACY.md) · [开发与发布](docs/DEVELOPMENT.md) · [架构设计](docs/ARCHITECTURE.md) · [产品与路线图](docs/PROJECT.md) · [视觉原型](docs/PROTOTYPE.md) · [变更明细](docs/changelog/README.md)

## Star History

<a href="https://www.star-history.com/?repos=YuSec2021%2Fai-usage-display&amp;type=date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=YuSec2021/ai-usage-display&amp;type=Date&amp;theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=YuSec2021/ai-usage-display&amp;type=Date" />
    <img alt="AI Usage 的 GitHub Star 历史曲线" src="https://api.star-history.com/svg?repos=YuSec2021/ai-usage-display&amp;type=Date" width="100%" />
  </picture>
</a>
