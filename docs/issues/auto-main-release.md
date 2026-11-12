# main 合入后自动升版、创建 Tag 并构建 Release

## 基本信息

- 类型：`type/chore`
- 状态：本地实现与验证完成；远程结果以关联 PR 和 Actions 为准
- 工作分支：`codex/auto-main-release`（遵循当前仓库 AGENTS.md；本地草稿，没有外部 Issue 编号）
- 负责人：当前项目维护者
- 设计或产出文档：N/A — 当前类型不需要设计；直接复用现有 Release 工作流、XcodeGen 和版本检查。

## 背景

用户明确要求完整的 main 合入自动发布链路。当前 Release 仅监听版本 Tag 与手动触发，项目仍为 1.2.1（Build 5）。已阅读项目规则、技能、现有工作流、版本检查、打包脚本及其调用方；本项目无单独 ADR 目录。

复用调查：检索 `MARKETING_VERSION`、`CURRENT_PROJECT_VERSION`、`build-direct-release`、`verify-release-version` 和 README 版本引用。现有 Release 已具备校验、测试、通用 DMG、签名与附件上传能力，只需添加 `workflow_call`；不复制打包实现，不添加 PAT 或外部依赖。

## 目标

- main 更新后自动增加补丁版本与构建号，同步工程、README 和发布日志，提交后创建 Tag。
- 使用内置 GITHUB_TOKEN，通过可复用工作流显式调用 Release，可靠衔接构建与上传。
- 重试已标记的版本不重复升版；不覆盖已有 Tag，原子推送避免半完成状态。

## 非目标

- 不自动猜测主版本/次版本升级，不配置 Developer ID 或 Apple 公证。
- 不修改分支保护，不使用强制推送；现有保护若阻止机器人版本提交，应明确失败。
- 不修改额度读取、圆环与玻璃行为，不创建外部 Issue。

## 根因说明（仅 `type/bug`）

N/A — 当前类型不需要根因说明。衔接约束：GITHUB_TOKEN 推送的 Tag 通常不触发新的 push 工作流，因此不能只加一条 git tag/push 命令。

## 验收标准

- [x] main 自动触发版本准备，默认补丁号和构建号各加一。
- [x] 版本、生成工程、README、发布摘要与编号记录同步，重复执行不会额外升版。
- [x] Tag 指向版本提交，main 与 Tag 原子推送；显式调用现有 Release，不依赖额外 Token。
- [ ] 版本准备正反例、重试与记录同步测试、actionlint、make verify 及双架构 PR 检查通过。
- [ ] 合入后跟进真实自动升版、Tag、Release 构建和附件结果。

## 模块拆解

| 模块 / 路径 | 修改内容 | 依赖 | 完成条件 |
| --- | --- | --- | --- |
| scripts/bump-release-version.py、Tests/WorkflowTests | 版本与记录准备、重试判断及回归验证 | Git 和现有文件格式 | 真实临时 Git fixture 正反例通过 |
| .github/workflows/auto-release.yml、release.yml | main 串行准备、原子推送和可复用构建 | 原 Release 实现 | 无循环、无覆盖、无需额外密钥 |
| AGENTS.md、About、README、开发文档、日志 | 记录自动发布规则与操作说明 | 最终实现 | 自动流程与项目规则一致 |

## 风险、假设与待决策项

- 风险：提交准备期间 main 变化会使原子推送失败；不强制覆盖新提交，可重跑自动流程。
- 风险：安装包仍是临时签名、未公证版本，保留现有发布标注。
- 假设：默认自动升级补丁号；已在本次任务中向用户说明。当前 main 未受保护，机器人写入已获得用户授权。
- 待决策：N/A — 不需要额外密钥或权限扩张；仅授予版本准备与发布任务 contents: write。

## 验证计划

- 自动验证：临时 Git fixture、workflow 语法、项目验证、PR 双架构 CI、真实 main 自动发布运行。
- 人工验证：核对 Tag 与版本提交、附件和版本日志；不声称已完成桌面 UI 或干净机器安装验证。
- 埋点与可观测性：复用 Actions 日志、Job 输出和 Git 历史。
- 发布与回滚：配置经 PR 合入；失败可重跑同一版本。停止自动发布应通过 PR 移除 main 触发器，保留已有 Tag 和 Release。

## 完成定义

- [ ] 设计和拆解与最终实现一致。
- [ ] 验收完成，未完成项已具体说明。
- [ ] 必要测试、构建和远程验证通过。
- [ ] 文档、发布与回滚事项已处理。

## 本地验证结果

- 16 项流程测试、39 项功能测试通过，1 项硬件相关预览导出按设计跳过；actionlint 与版本检查通过。
- 实际工作流命令的隔离 Git 演练通过：版本为 1.2.2（Build 6），生成工程同步，main 与 Tag 原子推送且指向同一版本提交，重试不重复升版。
- 远程验证将在配置 PR 合入后由自动流程执行，结果可在 PR 和 Actions 核对，避免为回填草稿再触发无内容升版。
