## 基本信息
- Issue：https://github.com/YuSec2021/ai-usage-display/issues/21
- 类型：`type/chore`
- 状态：准备完成，待实施
- 唯一工作分支：`codex/issue-21-standard-dev-flow`（仅关联本 Issue；实施前核对无同名分支或重复准备记录）。
- 负责人：YuSec2021
- 设计或产出文档：N/A — 当前类型不需要设计；流程、契约与模块拆解如下。

## 背景
只读审查确认 main 未保护、无 Ruleset；流程检查仅校验 About/日志/索引，未接入 Issue/类型/分支及类型准备材料。技能仍保留源项目分支映射。重复编号未拦截，本地 Issue #4 草稿缺最终交付状态。现有机器人直接向 main 推送版本提交，与强制 PR 规则不兼容。
已阅读 AGENTS、技能及模板、开发文档、Makefile、三套 workflow、发布和流程检查器及16项流程回归。保留工作区 AGENTS.md 既有用户修改。

## 目标
统一 codex/issue-21-standard-dev-flow（后续任务使用各自真实编号） 和六种类型，新增可验证的准备记录与 PR 入口，检查 Issue/草稿、唯一分支、设计/根因/调研材料；检查日志编号唯一性；补齐交付状态。机器人改为版本 PR，通过双架构检查且合并后才创建 Tag 并发布，最后启用 main 强制 PR 和双架构检查，无豁免、强推或覆盖 Tag。

## 非目标
不修改用量采集、凭证、应用功能和手工升版；不增加长期环境分支，不安装应用。历史准备材料不强制改写，保留阶段证据并附最终交付入口。

## 根因说明
N/A — type/chore 不要求四行 Bug 根因。

## 验收标准
- [ ] 项目规范与技能/模板统一分支映射；提供 Issue 和 PR 模板。
- [ ] 缺准备记录、类型冲突、分支/Issue不匹配、缺设计/根因/验收/拆解/验证等均拒绝；检查准备提交在实施之前，显式保留本次流程接入的引导路径。
- [ ] 重复编号日志被拒绝，并包含隔离回归。
- [ ] 版本 PR 按限定生成内容校验，普通 PR 不可通过发布例外绕过；GITHUB_TOKEN 创建版本 PR 后显式派发双架构检查。
- [ ] 机器人不直接推 main；main 强制 PR、arm64/x86_64 成功检查，管理员适用，无绕过列表/强推。
- [ ] Issue #4 本地准备文档补最终交付结果；本次状态链接到 Issue/PR。
- [ ] About、编号变更记录、索引、Unreleased 同步；make verify、流程回归及真实远程 PR/发布流程验证通过或准确记录阻塞。

## 模块拆解
| 模块/路径 | 修改和契约 | 调用方/依赖 | 验证门禁 |
| --- | --- | --- | --- |
| .agents/skills/standard-dev-flow、AGENTS、docs/DEVELOPMENT、.github 模板、docs/issues | 统一分支/准备记录/类型材料和交付说明，保留用户已有文字 | 人工与代理开发、PR | 文档链接、类型正反例、准备提交顺序 |
| scripts/check-project-update.py、新准备与版本PR检查、Tests/WorkflowTests、Makefile | 将准备门禁与编号唯一性接入 verify，版本例外仅接受发布脚本精确生成内容 | CI、本地命令 | 临时 Git fixture，无真实数据/凭证 |
| .github/workflows/auto-release.yml、pr-check.yml、发布脚本与GitHub设置 | 创建/复用版本PR，显式触发检查，合入后tag和发布；main保护 | GITHUB_TOKEN、原Release | 本地回归、双架构CI、真实main规则和版本PR发布闭环 |

## 风险、假设与待决策项
- 风险：GITHUB_TOKEN 创建PR不会自动触发其他workflow，因此增加显式workflow_dispatch；仓库需允许Actions创建PR。启用保护前先让新流程具备完整PR交付能力。
- 假设：用户“按建议完善”授权落实已列出的仓库流程与远程main保护；仅使用最小权限，不申请额外Token。未来版本PR由维护者合并。
- 待决策：N/A — 保留现有双架构检查、原Release打包实现，采用无保护豁免的版本PR流程。

## 验证计划
- 自动验证：隔离临时Git仓库正反例、全部流程测试、make generate（如需）、make verify、git diff --check；PR双架构检查。
- 人工验证：核对main保护和Actions权限、PR记录、版本PR/Tag/Release闭环；UI及真实额度刷新未验证则明确记录。
- 埋点与可观测性：沿用Actions日志与Issue/PR状态，不记录凭证、真实日志或会话内容。
- 发布与回滚：先交付新workflow并通过PR检查，再启用保护并合并；故障通过修复PR或重跑处理，不关闭保护、不强推、不覆写Tag。

## 完成定义
- [ ] 规则、模块拆解与实现一致，范围变更先回填。
- [ ] 所有验收通过，限制如实记录。
- [ ] 本地与远程门禁通过，保护与发布不冲突。
- [ ] 文档和最终交付状态同步。
