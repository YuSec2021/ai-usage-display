# #4：Kimi 验证状态与旧响应回写

> 最终交付：已通过 [PR #14](https://github.com/YuSec2021/ai-usage-display/pull/14) 与 [PR #19](https://github.com/YuSec2021/ai-usage-display/pull/19) 合入 main，并发布 [v1.2.3](https://github.com/YuSec2021/ai-usage-display/releases/tag/v1.2.3)；[Issue #4](https://github.com/YuSec2021/ai-usage-display/issues/4) 已关闭。下文保留实施阶段记录，其中“待 PR”“尚未发布”描述的是当时状态。

- Issue：https://github.com/YuSec2021/ai-usage-display/issues/4
- 类型：type/bug；状态：本地实现及隔离验证完成，待 PR 交付；负责人：当前项目维护者
- 唯一工作分支：codex/issue-4-kimi-verification-state（已创建）
- 设计：N/A — bug 不要求模块设计。

## 背景与目标
MiniMax 授权已按 #9 移除，范围缩小为 Kimi。原 Kimi 验证在 await 后直接更新 View 的 configured/verified/message，易被旧请求覆盖。使用一个明确的验证状态，集中保存/移除/验证的状态转换，并以请求代次和 Key 快照拒绝旧响应。

## 四行根因
- 现象：验证中移除或更换 Key，旧结果可能回写“已连接”；将用可控延迟 fixture 复现。
- 根因：SettingsView.verifyKimiConnection 在 KimiUsageAPI.load() 返回后没有检查请求是否仍有效。
- 影响面：设置的授权文字与当前凭证状态，不改变额度事实源，不恢复或删除已移除的 Key。
- 回归：覆盖删除 Key、更换 Key、同 Key 请求逆序、错误重试与凭证保存/移除失败，旧结果不得写回。

## 复用与模块拆解
检索 verifyKimiConnection、KimiCredentialStore、KimiUsageAPI.load；已阅读 SettingsView 授权区和两个服务。复用原 Keychain 存储及真实 API 解码；原 View 的分散布尔状态无法直接覆盖异步请求生命周期，需要小型可注入状态模型。

| 模块 | 修改与调用方 | 验证 |
| --- | --- | --- |
| Services/KimiConnectionModel.swift | 集中状态、请求代次，调用既有凭证服务和 API | 延迟假 loader 与内存凭证 |
| Views/SettingsView.swift | 绑定模型状态，保留 Key 草稿和用户操作 | 构建、现有额度回归 |
| Services/KimiUsageAPI.swift | 允许显式传入本次请求 Key，原 load() 调用兼容 | 假 loader 与原解码测试 |

## 验收与非目标
- [x] 旧响应不恢复移除后的连接状态，不覆盖新 Key 或新验证结果。
- [x] configured=false/verified=true 不再能由独立布尔值拼出。
- [x] 保存/移除失败保留原配置；成功重试清掉旧错误。
- [x] make verify、About 与日志同步通过。
不创建通用凭证框架、不重写整个设置页、不读取测试机钥匙串或网络。无新增依赖与权限。

## 风险、验证与发布
异步请求不能只比较 Key（同一 Key 的逆序请求仍可能过期），同时检查代次；删除 Key 先使旧代次失效。使用隔离 fixture 复现与验证。未完成的 GUI 核对如实记录，实际安装在最终构建统一处理。后续 PR/main 发布，可回退本提交，无凭证格式迁移。

## 本地结果
延迟 fixture 已验证删除/更换/同 Key 逆序响应不可回写，错误重试和存储失败保持一致状态。make verify 通过。无真实 Keychain 或网络被测试调用，未声称实机网络竞态复现，尚未发布。
