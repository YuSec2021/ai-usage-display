# 024：Windows 圆环托盘与桌面浮窗预览

日期：2026-11-15

Issue：[24](https://github.com/YuSec2021/ai-usage-display/issues/24)。唯一分支：`codex/issue-24-windows-rings`。准备文档、JSON 与完整设计已独立提交，通过 make check-prepare 后实施。

## 问题与结果

新增独立 C# / .NET 10 / WinUI 3 工程，将 macOS 模型 Logo + 5 小时已用额度圆环迁移到 Windows 11 x64。任务栏右侧托盘与可置顶、拖动、吸附、记忆位置的浮窗共用一个状态仓库，常驻区域不显示百分比文字；主窗口含用量、历史与设置。

## 实现范围

- 沿用已有 Logo、5 小时窗口、真实零值、未知/过期区分和本地隐私原则；SwiftUI/AppKit 代码不与 Windows 强行共编译。
- 接入 Codex 官方只读额度与日志回退、可恢复 Claude status line 及本地 Token、Kimi 本地用量与官方额度 API；Windows Credential Manager 保存主动配置的 Key。
- MiniMax Windows 缓存和 WSL 明确暂不支持，不伪造模型用量。日志初读/行大小/文件数量有界，历史不完整时标记。
- 新增 Windows CI、匿名核心测试、原生启动/collector 烟雾、浮窗截图与自包含 ZIP/SHA-256；保留原 macOS 工程和发布流程。
- 同步 About 中英文说明、README、Windows 指南、索引与 Unreleased。PNG/ICO 从既有项目图标导出，用于 Windows 原生渲染。

## 验证

本地 .NET 核心 16 项隔离回归通过；make verify 的 34 项流程测试、73 项 Swift 测试报告通过（1 项 GPU 预览默认跳过），构建版本 1.2.6 核对通过。准备门禁、actionlint、差异检查通过。

[Windows 原生 CI](https://github.com/YuSec2021/ai-usage-display/actions/runs/43618912141) 已通过：Windows runner 上 16 项核心测试、自包含 publish、collector 脱敏、4 个托盘图标注册、主窗口/浮窗可见与置顶、隐藏恢复、无百分比、真实零值与未知状态、概览/历史/设置切换，以及 ZIP/SHA-256 打包。紧凑/展开浮窗、主窗口、历史与设置的 5 张原生 XAML 截图已人工检查；[Windows 指南](../windows/README.md) 收录浮窗效果，数据均为匿名 fixture。

修复了未打包 WinUI 工程的主资源索引命名与发布配置，并显式检查 resources.pri；CI 随后从预览 ZIP 解压到含空格路径，再运行同一原生 smoke，防止发布目录正常而下载包缺少运行文件。

## 未验证范围

当前开发机为 macOS；原生自动验证使用 Windows runner（NT 10.0.26100，Windows Server 环境），不代表已在用户的 Windows 11 机器验收。Windows 真实用户登录、额度刷新、鼠标拖动、多屏/DPI、Explorer 重启、第二实例恢复和凭证管理器实际读写尚未手工验证。不把 Windows 构建或匿名 smoke 当作真实额度验证。未安装应用或申请签名证书。

## 版本

保持根目录版本 1.2.6（Build 10）；Windows 从 project.yml 读取版本，macOS About 继续从 Info.plist 读取。未改 project.yml 或手动升版。
