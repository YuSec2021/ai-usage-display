# 013：集中 Kimi 验证状态并拒绝旧响应

日期：2026-11-13

Issue：https://github.com/YuSec2021/ai-usage-display/issues/4

移除设置页独立 configured/verified 布尔值，验证、保存和移除集中到可注入模型。以 Key 快照和请求代次校验结果；保存/移除失败保留原配置，成功重试清除旧错误。仅刷新 Kimi，保留现有 Keychain 与 API 解码。

验证：make generate、make verify 通过；16 项流程、61 项功能测试通过，1 项 GPU 预览默认跳过。4 项内存凭证/延迟请求回归验证删除、更换、同 Key 逆序、错误重试与存储失败，未访问真实钥匙串或网络。

版本保持 1.2.2（Build 6），未发布；变更由独立工作分支承载。
