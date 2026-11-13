# 增量行读取复用：模块设计

## 1. 基本信息
Issue：https://github.com/YuSec2021/ai-usage-display/issues/6；状态：已确认；负责人：当前项目维护者；日期：2026-11-13。
唯一工作分支：codex/issue-6-incremental-line-reader（已创建）。

## 2. 背景与目标
三家 JSONL 和 Kimi Desktop 日志重复维护偏移、尾部读取、残行和截断恢复。只复用字节 I/O、分行及 cursor，保留每家事件消费、初读范围和业务聚合。非目标：不统一 Provider/schema，不合并 Token 去重策略，不新增框架。

## 3. 现状与约束
遵守 AGENTS.md 与已有大日志/历史边界回归，无单独 ADR、新权限或依赖。Kimi Desktop 使用相同分行语义，作为直接复用调用方一并迁移。

## 4. 复用声明
部分已有：Codex parseChanges、Claude parseTranscriptChanges、Kimi parseChanges/parseDesktopLogChanges 含相同 I/O 模板。检索 offset、remainder、wasRewritten、consumeTranscript、consumeDesktopLogLine；已逐一阅读这些实现及状态结构。业务 consume 无法互相复用，基础分行可抽为纯同步 helper，cursor 只含偏移和残行。

## 5. 方案
IncrementalLineReader.read 接收 URL、文件尺寸快照、Cursor、可选初读偏移计算与非逃逸 consume(Data)->Bool。打开/关闭和读取集中管理；首次尾部读丢掉开头的残片，完整行消费一次；末尾无换行时由消费方判断是否完整，未完整者保存在新 cursor。读取只到已观察的文件尺寸，避免同时追加的行被本轮消费后下轮重复读。短读/打开失败在调用 consume 之前抛出，调用方保留原状态与旧元数据，使下次仍会重试。

每家仍自行比较截断/同尺寸改写并创建新的业务状态；初读策略分别为 Codex 1 MiB、Claude 逆向扫描七天边界、Kimi JSONL 从头、Kimi Desktop 1 MiB。同步非逃逸回调在原 actor 中执行，不跨线程共享业务状态。

| 模块 / 路径 | 修改内容 | 调用方/依赖 | 验证方式 |
| --- | --- | --- | --- |
| Services/IncrementalLineReader.swift | Cursor、尺寸有界读取、分行与失败契约 | 四处读取调用方 | 小型临时文件 fixture |
| Providers/CodexUsageProvider.swift、ClaudeUsageProvider.swift、KimiUsageProvider.swift | 用共享读取替换重复模板，保留初读/消费/业务缓存 | 原 load | 原大日志和聚合回归 |
| Tests/AIUsageTests | 追加、半行、无换行、尾读、尺寸快照、失败重试和重写 | 临时目录 | XCTest |

无持久化格式变化，cursor 仅为内存状态。

## 6. 异常、安全与兼容性
不确认失败读取的元数据，旧状态保留且可重试；捕获短读，不提交部分业务更新。未知事件与损坏完整行是否丢弃仍由各 consumer 决定。无真实日志、凭证或内容进入 fixture/输出。

## 7. 可观测性与埋点
复用已有 ProviderAvailability；不新增日志，测试以消费计数验证无重记。

## 8. 验证与发布
make generate、make verify；原 Claude 反向历史扫描、Kimi 旧格式去重与 Codex token 差值回归必须保留。About、日志同步，最终统一 UI/安装验收；后续 PR/main 发布，独立提交可回滚。

## 9. 待决策项
N/A — 所有策略保留在调用方，无阻塞项。
