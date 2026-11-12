# 007：main 自动升版并调用 Release

日期：2026-11-12

用户明确要求 main 合入后自动升版、创建 Tag 并构建 Release。新增 `auto-release.yml` 监听 main 更新并支持手动重试，默认递增补丁号和构建号，更新 `project.yml`、README、发布摘要与编号日志，再用 XcodeGen 同步工程。版本提交与 Tag 原子推送，不覆盖已有引用；已标记版本可直接复用，重试不重复升版。

现有 `release.yml` 新增 `workflow_call`，由自动流程显式调用，复用版本校验、测试、通用 DMG、临时签名、SHA-256 和附件上传。由于内置 GITHUB_TOKEN 的推送不会再次触发普通 push 工作流，不能只靠推 Tag 衔接。此实现无需额外 PAT，也不通过关闭分支保护或强制推送完成发布。

AGENTS.md 与开发文档同步用户授权的自动发布例外；About 的下载链接明确为安装包。自动版本提交不硬编码 About 版本，仍读取 Info.plist。准备记录见 `docs/issues/auto-main-release.md`。

本地验证：16 项流程测试通过；`make verify` 通过（39 项功能测试，1 项 GPU 预览导出按设计跳过），版本检查及 `actionlint` 均通过。隔离 Git 仓库演练使用实际工作流提交/推送命令，确认生成 1.2.2（Build 6）、Xcode 工程版本同步、main 与 Tag 指向同一个版本提交，且重复运行不再升版。演练没有修改真实远程仓库。

远程双架构 CI 与实际自动升版/构建/附件结果以关联 PR 和 Actions 为准。应用版本暂不在开发分支改变，预计配置合入后自动生成 1.2.2（Build 6）；实际版本以自动提交为准。安装包仍为临时签名、未公证。
