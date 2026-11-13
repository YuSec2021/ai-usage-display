# Claude 重置推断复用：模块设计

## 1. 基本信息
Issue：https://github.com/YuSec2021/ai-usage-display/issues/7；状态：已确认；负责人：当前项目维护者；日期：2026-11-13。
唯一工作分支：codex/issue-7-claude-reset-inference（已创建）。

## 2. 背景与目标
5 小时和 7 天推断具有同一遍历流程，复用为接收用量字段、窗口时长和前值边界谓词的方法。非目标：不修订负值含义、不推算首次正值窗口，不更改过期规则。

## 3. 现状与约束
遵守 AGENTS.md，无单独 ADR/新增依赖或权限。当前原始 Desktop 样本不约束负值，短周期 previous==0 与周周期 previous<=0 的差异必须保留。

## 4. 复用声明
能力已有：两个推断函数。检索 inferredFiveHourReset、inferredSevenDayReset、normalized；已阅读 ClaudeUsageProvider 样本归一化、两段推断与现有推断过期测试。可共用遍历，但字段、时长与负值条件不同，故只参数化这些差异；不另建时间推断框架。

## 5. 方案与拆解
用 KeyPath 读取对应字段，保留 nil 跳过、<=0 清空起点、下降/前值边界识别起点。两次调用分别传 5h/7d 和各自的 ==0/<=0 谓词。

| 模块 / 路径 | 修改内容 | 调用方/依赖 | 验证方式 |
| --- | --- | --- | --- |
| Providers/ClaudeUsageProvider.swift | 合并重复遍历，保留边界差异 | loadLatestDesktopUsage | 原过期回归 |
| Tests/AIUsageTests/ClaudeResetInferenceTests.swift | 双窗口序列和不同字段 fixture | 临时状态/历史文件、固定时间 | XCTest |

接口和持久化无变化，私有样本类型保持。

## 6. 异常、安全与兼容性
空/缺失值和未知起点仍返回 nil；负值差异按原行为测试锁定。推断时间到期后仍被过滤，不读用户历史或设置。

## 7. 可观测性与埋点
N/A — 内部重构不增加日志，用窗口结果断言验证。

## 8. 验证与发布
make generate、make verify；表驱动覆盖空、零、首次正值、零转正、下降、缺失及负值，并验证两个字段独立。About/日志同步，后续 PR/main 发布，可回退独立提交。

## 9. 待决策项
N/A — 采用保留现有边界语义的最小重构。
