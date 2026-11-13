# 011：移除 MiniMax API 授权入口

日期：2026-11-13

Issue：https://github.com/YuSec2021/ai-usage-display/issues/9

按用户决定移除 MiniMax 专属授权状态、网络验证、服务及相关测试。保留本地缓存状态和更新说明，不主动读取或删除遗留钥匙串条目与区域偏好。设计见 docs/design/issue-9-remove-minimax-authorization.md。

验证：make generate、make verify、版本检查通过；16 项流程测试和 53 项功能测试通过，1 项 GPU 预览按默认设置跳过。生产 Sources/Tests 中已无 MiniMax 专属授权引用。最终桌面 UI 与安装尚待统一验收。

版本保持 1.2.2（Build 6），未发布；变更由独立工作分支承载。
