# 022：落实标准开发门禁与受保护分支发布

日期：2026-11-14

Issue：[21](https://github.com/YuSec2021/ai-usage-display/issues/21)。唯一工作分支：`codex/issue-21-standard-dev-flow`。准备文档与 JSON 已先于实施独立提交。

## 问题与结果

项目已有测试、更新记录和自动发布，但 main 无强制保护，准备材料未接入检查，技能与项目分支规则不一致，重复日志编号可通过，历史 Issue 本地材料缺最终状态。统一规则后，将准备门禁、编号校验接入 Make/PR 检查；机器人创建版本 PR，通过相同检查并合入后才打 Tag 和发布，支持开启无豁免的 main 保护。

## 实现范围

- 技能、模板、AGENTS 和开发文档统一 `codex/issue-<真实Issue号>-<描述>`；JSON 关联唯一任务和材料，检查独立准备提交顺序。CI 复核远程 Issue 类型与分支。
- feature/refactor 要求设计与复用声明，bug 要求四行根因，spike 要求调研问题与产出，chore/docs 标记无需设计。
- 变更记录编号全局唯一；历史 Issue #4 顶部补最终 PR/Release 入口，保留原阶段证据。
- 版本 PR 只接受可信 main 的发布脚本与 XcodeGen 精确生成内容；不直接推 main、不覆盖 Tag；token 创建 PR 后显式派发检查。
- 同步 About 中英文说明、索引、Unreleased；不改用量采集与凭证功能。

## 验证与远程状态

34 项隔离流程测试通过，覆盖准备顺序、缺失/冲突材料、重复编号、开发 PR 手动升版和伪装版本变更；make verify 的 Swift 测试报告 73 项、0 失败，1 项 GPU 预览默认跳过，构建版本核对通过。actionlint/ShellCheck、差异检查通过。

远程双架构 CI、main 保护和版本 PR 发布闭环结果以 [Issue #21 的最终交付记录](https://github.com/YuSec2021/ai-usage-display/issues/21) 为准；本条记录保留本地实施验证范围。

## 未验证范围

不以流程测试代替应用 UI、真实额度刷新或安装验证；本次不安装应用。结构检查无法证明设计内容的事实正确性，仍须维护者审查。

## 版本

开发分支保持 1.2.5（Build 9），不手动升版。版本 PR 自动同步配置与工程；About 的版本与构建号仍从 Info.plist 读取。
