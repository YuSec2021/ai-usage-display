# 移除 MiniMax API 授权入口：模块设计

## 1. 基本信息
- ISSUE：https://github.com/YuSec2021/ai-usage-display/issues/9
- 状态：已确认；用户于 2026-11-13 明确批准移除。
- 负责人：当前项目维护者
- 更新日期：2026-11-13
- 唯一工作分支：codex/issue-9-remove-minimax-authorization（已创建）

## 2. 背景与目标
MiniMax 的模型列表授权不参与额度读取。删除设置中的区域、Key、保存/移除、验证提示及自动验证，保留 Desktop 缓存检测与额度显示。非目标：不改 MiniMax 数据源，不移除 Kimi 授权，不主动读取或删除遗留 MiniMax 凭证。

## 3. 现状与约束
遵守根 AGENTS.md、standard-dev-flow 与既有额度缓存回归；N/A — 仓库没有适用的单独 ADR。用户已批准功能移除，无新增权限或外部依赖；保留旧钥匙串条目和区域偏好，避免不可逆清理。

## 4. 复用声明
- 仓库是否已有该能力：已有独立 MiniMaxUsageProvider，完全不依赖 API 授权。
- 搜过什么关键词：MiniMaxAuthorization、MiniMaxCredentialStore、miniMaxAPI、miniMaxRegion、modelsEndpoint。
- 看过哪些既有实现：SettingsView 授权区和验证方法、Services/MiniMaxAuthorization.swift、MiniMaxUsageProvider、ProviderTests 与 README/架构说明。
- 为什么不能复用：N/A — 直接复用 MiniMaxUsageProvider 和现有 Kimi 的 APIKeyCredentialStore；删除无额度用途的 MiniMax 专属授权实现。

## 5. 方案
移除 UI 与所有授权调用方，再删除专属服务及模型列表测试。MiniMax 设置只说明本地缓存与更新方式。同步 About、当前用户文档与编号日志，历史发布记录保留。

| 模块 / 路径 | 修改内容 | 调用方或依赖 | 验证方式 |
| --- | --- | --- | --- |
| Views/SettingsView.swift | 删除 MiniMax 授权状态和操作，保留缓存状态 | MiniMaxUsageProvider | 构建、静态引用检索 |
| Services/MiniMaxAuthorization.swift、ProviderTests | 删除授权服务及专属测试 | 无剩余运行调用方 | 全量测试、XcodeGen |
| README、ARCHITECTURE、About、日志 | 记录仅本地缓存；钥匙串与网络说明改为 Kimi | 当前用户说明 | 流程检查 |

接口与数据：ProviderResult、额度模型、Kimi 凭证 API 均无变化；只移除 MiniMax 专属授权类型。

## 6. 异常、安全与兼容性
缓存失败/过期继续走现有提示；不触碰 MiniMax 登录、Cookie 或钥匙串条目。旧配置无需迁移，无自动清理；回退代码可恢复旧入口。

## 7. 可观测性与埋点
N/A — 删除无关网络请求，不增加日志或采集。

## 8. 验证与发布
运行 make generate、make verify；确认 MiniMax 缓存测试全部保留，生产代码不再引用 MiniMax Key 或 models API。真实 GUI 验证与安装在最终构建统一执行；不声称当前已发布。后续发布遵循现有 PR/main 流程，回滚使用回退提交。

## 9. 待决策项
N/A — 用户已批准移除；遗留凭证默认保留，不主动读取或删除。
