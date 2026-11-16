# 026：新增 Google Antigravity 用量与多分组额度监控

日期：2026-11-16

Issue：[26](https://github.com/YuSec2021/ai-usage-display/issues/26)。唯一工作分支：`codex/issue-26-antigravity-usage`。准备文档、模块设计与 JSON 已先于实施独立提交。

## 问题与结果

AI Usage 此前支持 Codex、Claude Code、Kimi Code 与 MiniMax 四种模型的本地用量与额度展示，尚未支持 Google Antigravity。本次新增 `Antigravity` 模型与官方矢量模板图标 `AntigravityLogo`，支持从 `~/.gemini/antigravity`（及 `~/.gemini/antigravity-ide`）增量统计本地会话 Token，并通过本机运行中的 Antigravity Language Server 读取多分组模型额度，主圆环展示 Gemini 5 小时额度，卡片同时展示 Gemini 本周、Gemini 4 Argon 本周及 Claude/GPT 5 小时与本周额度。

## 实现范围

- `UsageModels.swift` 新增 `ProviderID.antigravity`、配色与 `AntigravityLogo` 矢量模板图标资产。
- `UsageProvider.swift` 与 `AntigravityUsageProvider.swift` 新增 Antigravity 数据目录探测、`brain/*/.system_generated/logs/transcript.jsonl` 增量 Token 解析（按 `step_index` 去重，汇总输入、缓存与输出 Token）以及最近 7 天日用量聚合。
- `AntigravityQuotaClient` 通过本地 `daemon/*.json` 发现存活的本机 Language Server，请求 `RetrieveUserQuotaSummary`，将 `gemini-5h` 映射为主 5 小时圆环窗口，同时将 `gemini-weekly`、`gemini-argon-wtu-weekly`、`3p-5h`、`3p-weekly` 等分组额度展示在详情卡片中；服务离线时保留上次有效额度或回退为本地 Token。
- `UsageStore.swift` 接入 `AntigravityUsageProvider` 并新增 `migrateProviderSelectionForAntigravity()`，使旧默认全选配置平滑升级包含 Antigravity，保留用户自定义选择。
- `SettingsView.swift` 新增 Antigravity 本地数据检测说明，同步更新“关于”页中英文版本说明。
- `ProviderTests.swift` 与 `UsageStoreTests.swift` 新增隔离 fixture 回归测试，覆盖轨迹增量去重、多分组额度映射、过期降级、进程发现过滤与默认勾选迁移。

## 验证

- 运行 `make check-prepare`，验证 Issue #26 准备记录、模块设计、唯一分支与独立准备提交顺序通过。
- 运行 `make verify`，流程自测、Swift 单元测试与构建后版本检查全部通过。
- 本机通过 `RetrieveUserQuotaSummary` 实测核对返回分组字段结构（仅验证额度白名单字段，不写入仓库）。

## 未验证范围

- 未在测试进程外人工点击验证 macOS 菜单栏弹窗拖拽与设置窗口交互。
- 未执行 24 小时常驻资源占用观察与 Release DMG 安装替换。

## 版本

同步最新 main 后，开发分支保持 1.2.7（Build 11），不手动升版。合入 `main` 后由版本 PR 自动递增补丁版本与构建号；About 的版本与构建号继续从 Info.plist 读取。
