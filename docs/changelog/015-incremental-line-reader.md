# 015：复用增量行读取与残行处理

日期：2026-11-13

Issue：https://github.com/YuSec2021/ai-usage-display/issues/6

共享 Cursor 与同步字节读取，迁移 Codex、Claude、Kimi JSONL 和 Kimi Desktop 日志四处模板。仅消费文件尺寸快照内的字节，短读/失败不更新元数据，以便重试；各家消费、历史扫描与重写业务状态独立。新增尺寸快照、无换行、残行、失败及三家重写/截断回归。

验证：make generate、make verify 通过；16 项流程、67 项功能测试通过，1 项 GPU 预览默认跳过。新增共享读取和三家 Provider 重写/截断回归，原 Claude 大日志七天边界及 Kimi 旧事件去重测试保留。

版本保持 1.2.2（Build 6），未发布；变更由独立工作分支承载。
