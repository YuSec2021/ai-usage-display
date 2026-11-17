# Issue #33：修复 Release 缺少 Windows 预览包

## 基本信息
- Issue：https://github.com/YuSec2021/ai-usage-display/issues/33
- 类型：`type/bug`
- 状态：准备完成
- 唯一工作分支：`codex/issue-33-windows-release-assets`
- 负责人：YuSec2021
- 设计或产出文档：N/A — Bug 使用四行根因说明，不要求模块设计。

## 背景
v1.2.8 Release 只有 macOS DMG。Windows main 任务 44012008360 在同一提交 6807c6421efb87208bf8f7c99c0656feb1941d9b 上通过核心测试与原生烟雾验证，但 ZIP/SHA-256 留在 Actions Artifact 中。

## 目标
- 将已验证、与 v1.2.8 Tag 提交一致的 Windows ZIP 和 SHA-256 补充到既有 Release。
- 后续版本发布时复用 Windows 构建与烟雾流程，按同一版本 Tag 构建，两个平台均成功后校验并发布全部附件。
- 在 Windows 指南和版本说明提供正确下载入口与预览限制。

## 非目标
- 不修改 Windows Provider、原生界面、签名、安装器、WSL 支持或 main 分支保护。
- 不重写现有 Tag、覆盖已有附件、手动升版或替换已安装应用。

## 根因说明
- 现象：Windows 构建成功，Release 下载列表却只有 macOS DMG 及其校验文件。
- 根因：`.github/workflows/windows.yml` 的 Upload portable preview 仅上传 Artifact；`.github/workflows/release.yml` 的 release 作业只依赖 build、只下载 universal Artifact，Publish DMG and SHA-256 只匹配 DMG，没有 Windows 构建与发布依赖。
- 影响面：Windows 用户缺少持久版本下载入口，所有现行 Release 都不会自动带 Windows 包；已有构建产物和用户数据没有损坏。
- 回归：覆盖发布依赖两个平台、可复用 Windows 工作流按 Tag checkout/版本校验、Artifact 名称一致，以及 ZIP/DMG 与两份校验文件共同下载、校验和发布；原生 Windows CI 继续运行测试和解压烟雾验证。

## 验收标准
- [ ] v1.2.8 Release 补齐同一提交的 Windows ZIP 与 SHA-256，校验通过且不覆盖现有附件。
- [ ] Release 调用现有 Windows 流程并等待其成功；任一平台失败不执行发布。
- [ ] Windows 发布调用检出指定版本 Tag，拒绝非法 Tag 或版本不一致，普通 PR/main 构建行为保留。
- [ ] 工作流回归、actionlint、make verify 与差异检查通过；远程 Windows 原生测试、构建和烟雾结果明确记录。
- [ ] About、编号变更记录、索引和 Windows 下载文档同步，版本号保持 main 配置。

## 模块拆解
| 模块 / 路径 | 修改内容 | 依赖 | 完成条件 |
|---|---|---|---|
| .github/workflows/windows.yml、release.yml | 复用已有 Windows 作业，增加 Tag 输入、检出与版本校验；发布等待双平台、下载两种产物、共同校验并发布 | 原有 .NET 自包含打包、smoke.ps1、Mac Release | 契约回归和 actionlint 通过，Windows CI 原生验证通过 |
| Tests/WorkflowTests | 固定双平台发布、Tag 来源、附件和校验的回归契约 | Python 标准库、现有流程测试命令 | 能识别原有漏发条件，纳入 make verify |
| Sources/AIUsage/Views/SettingsView.swift、docs/windows/README.md、docs/DEVELOPMENT.md、docs/changelog、CHANGELOG.md | 同步下载方式、预览范围、About 和变更记录 | 现有文档结构与版本来源 | 流程检查通过，说明与实际行为一致 |
| v1.2.8 GitHub Release | 下载同 Tag Windows 成功 Artifact，校验 ZIP/SHA-256 后追加两份附件和使用说明 | run 44012008360、现有 Release | 发布附件名与远端摘要核对通过 |

## 风险、假设与待决策项
- 风险：Windows runner 故障将阻止整次发布，保留重试入口；预览包未签名，支持范围及 Windows 用户机器真实验证限制须明确。
- 假设：当前成功 Artifact 与 v1.2.8 Tag 的提交完全相同；上传前再次核对。发布复用既有测试/烟雾与打包步骤，避免重复维护。
- 待决策：N/A — 无阻塞项，按现有 Windows x64 预览格式发布。

## 验证计划
- 自动验证：先 make check-prepare；新增发布契约回归对旧配置失败、修复后通过；运行 actionlint、make verify BASE_REF=origin/main、git diff --check；PR Windows 原生 16 项核心测试、自包含构建、解压烟雾及双架构 Mac 门禁。
- 人工验证：校验当前 Release ZIP 的 SHA-256、必需 exe/resources.pri、来源提交与远端附件摘要。此次不改用量/UI，macOS About 实际界面、Windows 用户机器真实登录与额度刷新、多屏/DPI、Explorer 重启未验证；不以 CI 匿名烟雾替代真实使用验收。
- 埋点与可观测性：沿用 Actions 作业、测试报告与 windows-verification Artifact，无需增加产品埋点。
- 发布与回滚：仅补当前版本缺失附件，保留 Tag 和既有 DMG。工作流经 PR 审核合入，由既有版本 PR/Tag 流程发布下一版本；首个新 Tag 的完整双平台自动发布需在实际运行后验收。回滚可还原工作流 PR，错误新增附件可单独删除，不重写 Tag。

## 完成定义
- [ ] 根因与模块拆解和最终实现一致。
- [ ] 所有验收标准完成或明确记录远程验收状态。
- [ ] 必要回归、构建和检查已通过。
- [ ] 文档、发布及回滚事项已处理，真实机器未验证范围明确记录。
