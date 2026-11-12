# 004：导入 standard-dev-flow 完整技能包

日期：2026-11-11

用户要求将 `ai_novel_agent` 的 `standard-dev-workflow` 放入当前项目。源仓库实际技能名为 `standard-dev-flow`，本次从来源 HEAD `1df7a8bf6ff942b3146fc04e9b08296e459f2886` 的干净技能目录完整复制到 `.agents/skills/standard-dev-flow/`，保留原名、相对目录与内容。

交付文件：

- `SKILL.md`：Issue 优先、类型门禁、复用调查与模块拆解规则。
- `assets/issue.md`：完整中文 Issue 模板。
- `assets/module-design.md`：含复用声明的模块设计模板。
- `agents/openai.yaml`：中文技能名称、摘要与调用提示。

准备记录使用源模板填写为 `docs/issues/import-standard-dev-flow.md`，类型为 `type/chore`，无需模块设计。没有真实 Issue 编号，未创建远程 Issue 或工作分支。README 与开发文档增加本地入口、来源和适用边界；About 核对并明确透明度保存、ChatGPT 圆环和重新采集提示；根目录摘要与日志索引同步。

仅导入技能包，未迁入小说项目专用的 Git Hook、应用代码、环境分支和其他技能；当前项目的 Git 与验证规则保留。后续若要设为强制工作流，需先适配源包的类型分支映射与现有 `codex/` 约定。

验证：源/目标四个文件的清单和 SHA-256 完全一致；技能模板相对链接有效，界面 YAML 可解析，Issue 草稿保留全部必要章节。`make verify` 通过，包含 4 项流程测试、40 项 Swift 单元测试及构建后版本检查；`git diff --check` 通过。

未验证新会话的技能发现与远程 Issue/PR 流程；本次仅复制本地技能包，没有执行或授权这些外部操作。版本与构建号仍为 1.2.1（Build 5），未提交、推送、发布或替换已安装应用。
