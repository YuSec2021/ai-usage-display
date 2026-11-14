# 020：精简 README 与技术栈展示

日期：2026-11-14

准备记录：[本地 Issue 草稿](../issues/simplify-readme.md)。唯一工作分支：`codex/simplify-readme`。

## 问题与结果

首页混合使用、实现和发布细节，难以快速了解产品。README 改为简洁的功能介绍、下载安装、四个 Provider 接入表、本地开发入口和文档导航；顶部增加 Swift 6、SwiftUI、macOS 13+、Xcode 26+ 与 XcodeGen 徽章，底部嵌入当前仓库的 Star History 曲线，支持明暗主题和点击查看。

## 实现范围

- 原有额度显示、刷新机制、数据路径、API Key 与隐私限制迁入 `docs/USAGE.md`，构建发布细节链接已有开发文档。
- 保留唯一的当前版本声明，继续兼容 `scripts/bump-release-version.py` 的自动发布同步。
- 同步中英文 About 版本说明、变更索引与 Unreleased；不改变数据采集或刷新逻辑。

## 验证

- `make verify` 通过：16 项流程测试通过；Swift 测试报告 73 项、0 失败，其中 1 项本机 GPU 预览导出按默认配置跳过；构建后的 App 版本核对通过。
- `git diff --check` 与 README、指南、草稿、编号记录的相对链接检查通过。
- 在临时 fixture 中将实际新版 README 交给自动升版脚本，确认仅将版本声明从 1.2.3 改为 1.2.4，徽章、指南和图表内容完整保留；未修改实际项目版本。
- 徽章按 [Shields.io 官方格式](https://shields.io/badges/static-badge) 编写；曲线 `/svg`、`type=Date` 与 `theme=dark` 参数已对照 [Star History 官方服务源码](https://github.com/star-history/star-history/blob/main/backend/main.ts) 核对。
- 当前环境请求五张徽章与 Star History 图片均返回 HTTP 403，未确认图片加载成功；保留替代文本及可点击目标链接。

## 未验证范围

未执行 GitHub README 实际渲染、应用 UI 人工检查、真实额度刷新、远程 CI、发布或安装应用。GPU 预览导出未开启；外部图片加载受 HTTP 403 阻塞，也受服务可用性与 GitHub 缓存影响。

## 版本

同步最新 main 的自动发布版本 1.2.4（Build 8），版本与构建号仍从 Info.plist 读取；保留 main 的 Ko-fi 赞助配置。原编号 019 已由自动发布记录占用，本记录调整为 020 并同步索引。合并 main 后运行 `make generate`，未手动升版；PR 合入后由 Automatic release 处理后续版本。
