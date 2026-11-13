# MiniMax 完整 JSON 直接解码：模块设计

## 1. 基本信息
Issue：https://github.com/YuSec2021/ai-usage-display/issues/5；状态：已确认；负责人：当前项目维护者；日期：2026-11-13。
唯一工作分支：codex/issue-5-minimax-json-decoding（已创建）。

## 2. 背景与目标
标准 Simple Cache 已准确分离/解压响应体，仍进入手写 marker/括号扫描。目标为标准体直接 JSONDecoder，旧二进制输入独立兼容。非目标：不删除旧格式、不改额度映射及缓存保护。

## 3. 现状与约束
遵守 AGENTS.md，无额外 ADR 或新依赖/权限；本地 MiniMax 修复已作为前置提交保存。

## 4. 复用声明
部分已有：已使用 JSONDecoder 和缓存结构解包。检索 quotaResponse、jsonQuotaResponse、objectStarts、completeJSONObject；阅读 MiniMaxUsageProvider、MiniMaxCacheTests 与 ProviderTests。原结构缺少直接体解码路径，但可以直接复用原解码器和所有模型，集中响应状态校验，不另建解析框架。

## 5. 方案与模块拆解
标准缓存体调用单一 decodeResponse，严格拒绝额外非 JSON 字节；只有非标准遗留输入进入旧扫描，再使用同一响应校验。删除已被有效样本前置条件保证的空 windows 分支。

| 模块 / 路径 | 修改内容 | 调用方/依赖 | 验证方式 |
| --- | --- | --- | --- |
| Providers/MiniMaxUsageProvider.swift | 标准直接解码、隔离 legacy fallback、共用状态校验 | 原 load 与缓存解包 | 原缓存回归 |
| Tests/AIUsageTests/MiniMaxCacheTests.swift | 完整体转义字段、严格拒绝夹杂内容 | 合成 Simple Cache | XCTest |

接口、文件格式和模型不变，只有内部解析路径调整。

## 6. 异常、安全与兼容性
CRC、解压上限、白名单 URL、错误状态码、旧样本保留、无限制和过期保护均保留。遗留明文嵌入兼容继续单独覆盖，不接触真实凭证。

## 7. 可观测性与埋点
N/A — 不增加日志，复用现有状态及合成 fixture。

## 8. 验证与发布
make verify、旧格式/新缓存全量回归，About 和编号日志同步。GUI 与实际额度在最终构建统一验收，后续 PR/main 发布，可回退独立提交。

## 9. 待决策项
N/A — 不移除兼容范围，无阻塞项。
