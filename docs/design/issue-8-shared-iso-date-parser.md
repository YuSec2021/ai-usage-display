# 公共 ISO 日期解析：模块设计

## 1. 基本信息
Issue：https://github.com/YuSec2021/ai-usage-display/issues/8；状态：已确认；负责人：当前项目维护者；日期：2026-11-13。
唯一工作分支：codex/issue-8-shared-iso-date-parser（已创建）。

## 2. 背景与目标
Claude 调用 Codex 的 parseDate，Kimi API 与 Provider 又有相同实现。目标是独立小型 ISODateParser，所有调用方复用同一日期兼容规则。非目标：不缓存共享可变 Formatter，不改时区、数字 epoch、日志专用日期格式或聚合时间策略，不宣称性能提升。

## 3. 现状与约束
遵守 AGENTS.md，无额外 ADR、依赖或权限，继续 Foundation 的带/不带小数秒解析顺序。

## 4. 复用声明
已有三份相同的 ISO8601DateFormatter 双格式逻辑。检索 ISO8601DateFormatter、CodexUsageProvider.parseDate、KimiUsageAPI.parseDate，已阅读 Claude 调用方与 Kimi 的数字时间兼容。直接复用既有算法，移入独立服务即可，不引入日期框架。

## 5. 方案与拆解
ISODateParser.parse(String?)->Date? 先尝试含小数秒，再尝试普通 ISO；nil/无效值保持 nil。Codex 去掉自带静态方法；Claude、Kimi API 和 Kimi Provider 的 ISO 分支使用服务，Kimi 数字时间分支与 Desktop 日志格式保持。

| 模块 / 路径 | 修改内容 | 调用方/依赖 | 验证方式 |
| --- | --- | --- | --- |
| Services/ISODateParser.swift | 无可变共享状态的公共解析 | 三家 Provider/Kimi API | 格式 fixture |
| Providers/CodexUsageProvider.swift、ClaudeUsageProvider.swift、KimiUsageProvider.swift、Services/KimiUsageAPI.swift | 替换重复调用和跨 Provider 工具依赖 | 原 load | 既有统计与重置回归 |
| Tests/AIUsageTests/ISODateParserTests.swift | Z、偏移、小数秒、缺失和无效输入 | Foundation | XCTest |

仅内部工具入口改变，无持久化或产品接口变化。

## 6. 异常、安全与兼容性
无效时间的回退仍由原调用方处理，不抛异常。Formatter 每次局部创建，避免 Swift 6 共享状态隔离风险；不访问用户文件或凭证。

## 7. 可观测性与埋点
N/A — 纯工具重构不新增日志。

## 8. 验证与发布
make generate、make verify，日期格式回归与全部 Provider 统计保持通过；About/日志同步。最终统一安装和 UI 验收，后续 PR/main 发布，独立提交可回滚。

## 9. 待决策项
N/A — 直接保留既有解析规则。
