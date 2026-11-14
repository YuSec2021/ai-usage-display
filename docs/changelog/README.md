# AI Usage 变更日志

从本次流程接入起，逐次变更采用编号记录；此前的发布历史保留在根目录 [CHANGELOG.md](../../CHANGELOG.md)。记录描述对应构建和验证范围，不代表已发布或已安装。

## 最新更新

- [023：发布 1.2.6](023-release-1.2.6.md)：自动补丁升版为 1.2.6（Build 10），发布结果以 Actions 为准。
- [022：落实标准开发门禁与受保护分支发布](022-standard-dev-gates.md)：统一 Issue/分支准备记录，检查准备提交顺序和日志编号，采用版本 PR 发布并落实 main 保护。

- [021：发布 1.2.5](021-release-1.2.5.md)：自动补丁升版为 1.2.5（Build 9），发布结果以 Actions 为准。
- [020：精简 README 与技术栈展示](020-simplify-readme.md)：聚焦功能、安装和接入，迁移详细使用说明，增加技术栈徽章与适配明暗主题的 Star 历史曲线。

- [019：发布 1.2.4](019-release-1.2.4.md)：自动补丁升版为 1.2.4（Build 8），发布结果以 Actions 为准。
- [018：发布 1.2.3](018-release-1.2.3.md)：自动补丁升版为 1.2.3（Build 7），发布结果以 Actions 为准。
- [017：独立共用 ISO 日期解析](017-shared-iso-date-parser.md)：Codex、Claude、Kimi 共用独立 ISO 日期解析，保留时区与小数秒兼容及原有解析失败回退。

- [016：合并 Claude 重置推断遍历](016-claude-reset-inference.md)：复用 Claude 短周期与周额度的重置推断遍历，保留原有零值、负值和过期规则。

- [015：复用增量行读取与残行处理](015-incremental-line-reader.md)：复用日志增量行读取，保留各模型的初读与去重策略；失败会重试，尺寸快照外的追加留到下轮。

- [014：MiniMax 标准缓存直接解码 JSON](014-minimax-direct-json.md)：MiniMax 标准缓存响应直接解码 JSON，旧格式扫描独立回退，保留缓存和额度保护。

- [013：集中 Kimi 验证状态并拒绝旧响应](013-kimi-verification-state.md)：Kimi 授权使用明确的验证状态，更换或移除 Key 后旧响应不会恢复连接状态。

- [012：按模型定向刷新](012-targeted-provider-refresh.md)：Claude 文件变化只刷新 Claude；全量刷新与定向刷新共用结果合并，并保留刷新期间的后续请求。

- [011：移除 MiniMax API 授权入口](011-remove-minimax-authorization.md)：移除 MiniMax API Key 与区域验证入口，额度仍由 Desktop 本地缓存刷新；Kimi 授权保留。

- [010：修复 MiniMax 额度缓存刷新](010-minimax-cache-refresh.md)：解析新版 Brotli 与已用百分比字符串，明确周额度无限制，兼容旧明文响应并保留写入中的有效样本。

- [009：修复 Codex 重置后的额度缺失](009-codex-quota-refresh.md)：主动读取官方当前额度，超时回退日志，打开面板刷新并区分已重置和无数据。

- [008：发布 1.2.2](008-release-1.2.2.md)：自动补丁升版为 1.2.2（Build 6），发布结果以 Actions 为准。
- [007：main 自动升版并调用 Release](007-auto-main-release.md)：main 更新后自动增加补丁号与构建号，同步版本记录并原子推送 Tag，再复用 Release 构建和发布；无需额外 Token。
- [006：原生预览导出改为本机显式启用](006-local-preview-export.md)：避免 Intel 托管 runner 的虚拟 GPU 触发 Metal 崩溃，CI 继续执行全部逻辑与菜单圆环图像测试。
- [005：自动构建通用 Release 安装包](005-automated-release-build.md)：Tag 或手动触发版本校验、测试、通用 DMG 构建及 GitHub Release 附件上传，整合原有 Tag 检查。
- [004：导入 standard-dev-flow 完整技能包](004-import-standard-dev-flow.md)：从 `ai_novel_agent` 原样复制四个技能文件并提供本地入口，保留当前项目的 Git 与验证规则。
- [003：液态玻璃界面与模型额度圆环](003-liquid-glass-quota-rings.md)：macOS 26 原生 Liquid Glass、透明度设置、ChatGPT/模型图标外圈显示 5 小时已用额度，并保留无数据和无障碍状态。
- [002：接入 MacEverything 标准化开发流程](002-standard-development-workflow.md)：同步 About 与日志的规则、统一 Make 入口、固定测试语言，以及 Apple Silicon/Intel PR 检查；版本保持 1.2.1（Build 5）。
- [001：修复 Claude Code 旧额度与缺失数据显示](001-claude-quota-refresh.md)：移除已过期额度、按窗口选择有效来源，保留无额度快照时的本地 Token；真实新额度样本尚待验证。

## 变更索引

| # | 类型 | 标题 | 日期 |
| --- | --- | --- | --- |
| [001](001-claude-quota-refresh.md) | bugfix | 修复 Claude Code 旧额度与缺失数据显示 | 2026-11-11 |
| [002](002-standard-development-workflow.md) | workflow | 接入 MacEverything 标准化开发流程 | 2026-11-11 |
| [003](003-liquid-glass-quota-rings.md) | feature | 液态玻璃界面与模型额度圆环 | 2026-11-11 |
| [004](004-import-standard-dev-flow.md) | chore | 导入 standard-dev-flow 完整技能包 | 2026-11-11 |
| [005](005-automated-release-build.md) | chore | 自动构建通用 Release 安装包 | 2026-11-11 |
| [006](006-local-preview-export.md) | test | 原生预览导出改为本机显式启用 | 2026-11-12 |
| [007](007-auto-main-release.md) | chore | main 自动升版并调用 Release | 2026-11-12 |
| [008](008-release-1.2.2.md) | release | 发布 1.2.2 | 2026-11-12 |
| [009](009-codex-quota-refresh.md) | bugfix | 修复 Codex 重置后的额度缺失 | 2026-11-12 |
| [010](010-minimax-cache-refresh.md) | bugfix | 修复 MiniMax 额度缓存刷新 | 2026-11-13 |
| [011](011-remove-minimax-authorization.md) | refactor | 移除 MiniMax API 授权入口 | 2026-11-13 |
| [012](012-targeted-provider-refresh.md) | refactor | 按模型定向刷新 | 2026-11-13 |
| [013](013-kimi-verification-state.md) | bugfix | 集中 Kimi 验证状态并拒绝旧响应 | 2026-11-13 |
| [014](014-minimax-direct-json.md) | refactor | MiniMax 标准缓存直接解码 JSON | 2026-11-13 |
| [015](015-incremental-line-reader.md) | refactor | 复用增量行读取与残行处理 | 2026-11-13 |
| [016](016-claude-reset-inference.md) | refactor | 合并 Claude 重置推断遍历 | 2026-11-13 |
| [017](017-shared-iso-date-parser.md) | refactor | 独立共用 ISO 日期解析 | 2026-11-13 |
| [018](018-release-1.2.3.md) | release | 发布 1.2.3 | 2026-11-12 |
| [019](019-release-1.2.4.md) | release | 发布 1.2.4 | 2026-11-14 |
| [020](020-simplify-readme.md) | docs | 精简 README 与技术栈展示 | 2026-11-14 |
| [021](021-release-1.2.5.md) | release | 发布 1.2.5 | 2026-11-14 |
| [022](022-standard-dev-gates.md) | chore | 落实标准开发门禁与受保护分支发布 | 2026-11-14 |
| [023](023-release-1.2.6.md) | release | 发布 1.2.6 | 2026-11-14 |
