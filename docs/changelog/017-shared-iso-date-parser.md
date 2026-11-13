# 017：独立共用 ISO 日期解析

日期：2026-11-13

Issue：https://github.com/YuSec2021/ai-usage-display/issues/8

将既有双格式 ISO 解析移动到 Services/ISODateParser，移除 Claude 对 Codex 工具方法的依赖及 Kimi 的重复实现。数字时间、Desktop 日志专用格式、用户时区与统计策略不变，不缓存共享 Formatter。

验证：make generate、make verify 通过；最终显式开启本机 GPU 预览后，73 项 Swift 测试和 16 项流程测试全部通过。Z/偏移、小数秒、缺失与无效输入回归通过，原 Provider 日统计与重置测试保持通过。最终累计兼容回归另覆盖遗留 JSON 字符串中的括号和转义。通用 Release 构建、双架构与签名验证通过，本机已备份、替换并稳定启动；新设置界面的自动化读取超时，未声称完成该项人工核对。安装清单位于忽略目录 .build/local-update/simplification-batch/installation.json。

版本保持 1.2.2（Build 6），未发布；变更由独立工作分支承载。
