# 按模型定向刷新：模块设计

## 1. 基本信息
- ISSUE：https://github.com/YuSec2021/ai-usage-display/issues/3
- 状态：已确认；负责人：当前项目维护者；日期：2026-11-13
- 唯一工作分支：codex/issue-3-targeted-refresh（已创建）

## 2. 背景与目标
Claude 文件变化调用全量刷新，触发无关模型的网络和进程。将刷新范围作为参数，共用状态合并。手动和定时刷新仍覆盖已选模型；文件事件仅刷新 Claude。非目标：不引入调度框架、不改变 Provider 的额度来源和历史统计。

## 3. 现状与约束
遵守 AGENTS.md 和现有 Swift actor 隔离；无单独 ADR。复用 Swift TaskGroup，无新增依赖或权限。保留用户刷新间隔、选择迁移与并行加载。

## 4. 复用声明
- 仓库是否已有该能力：部分已有，UsageStore 已并行加载并合并快照。
- 搜索关键词：refresh、refreshClaudeIfSnapshotChanged、isRefreshing、history、stop。
- 看过实现：App/UsageStore.swift、Views/MenuBarView.swift、SettingsView.swift、UsageProvider 协议、现有 Provider fixture。
- 为什么不能完全复用：原 refresh 只支持全量且直接丢弃重入请求，必须增加范围、待处理集合和停止代次；其结果更新直接复用为单个 apply 方法。

## 5. 方案
refresh(providers:) 把请求并入待处理集合，唯一活动循环并行加载本轮所选范围；重入请求由后续轮处理。取消选择立即清除旧数据，结果返回时再次核对选择和待处理请求。stop 增加代次并清空队列，旧代次结果不再写入；新一轮刷新不受旧 defer 影响。测试注入 UserDefaults、Claude 修改时间与自动启动开关，四家 Provider 用隔离 stub。

| 模块 / 路径 | 修改内容 | 调用方/依赖 | 验证方式 |
| --- | --- | --- | --- |
| App/UsageStore.swift | 刷新范围、队列、代次、共享 apply 与定向 Claude 监听 | 原各刷新调用方 | 调用计数、延迟 fixture |
| Tests/AIUsageTests/UsageStoreTests.swift | 全量/定向、重入、选择变化、停止重启回归 | 假 Provider 与隔离偏好 | XCTest |

接口与数据：refresh() 保持原调用方式；增加可选范围参数，不修改 ProviderResult 或持久化格式。

## 6. 异常、安全与兼容性
重入合并而非丢弃；停止只丢弃旧结果，不销毁已采集快照。依赖 Provider 现有失败状态，队列最终统一复位。测试不扫描真实日志、调用 CLI/网络或改用户偏好。

## 7. 可观测性与埋点
复用 isRefreshing/lastRefresh；测试用 Provider 调用计数，不新增用户日志。

## 8. 验证与发布
make generate、make verify；新增延迟 fixture 验证旧结果无法回写。About 与日志同步；实际 UI 在最终构建验收，未发布。后续 PR/main 自动发布，回滚对应提交。

## 9. 待决策项
N/A — 无阻塞项，刷新并发规则已明确。
