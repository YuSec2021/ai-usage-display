# 012：按模型定向刷新

日期：2026-11-13

Issue：https://github.com/YuSec2021/ai-usage-display/issues/3

增加刷新范围与待处理集合，统一 apply，使用停止代次防止旧结果写回。通过隔离偏好、修改时间和假 Provider 验证定向/全量、重入合并、选择变化和停止后新刷新。

验证：make generate、make verify 通过；16 项流程测试、57 项功能测试通过，1 项 GPU 预览默认跳过。新增 4 项 Store 测试覆盖定向/全量、重入、选择变化和停止代次。实际 GUI 尚待最终统一验收。

版本保持 1.2.2（Build 6），未发布；变更由独立工作分支承载。
