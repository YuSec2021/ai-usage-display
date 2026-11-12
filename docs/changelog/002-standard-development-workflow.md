# 002：接入 MacEverything 标准化开发流程

日期：2026-11-11

来源：MacEverything 仓库 `46b2472` 的项目更新约定、About 说明、编号日志与双架构 PR 构建流程。按当前 Swift/Xcode 项目适配，无跨仓库运行依赖。

本次落实：

- 根目录 `AGENTS.md` 定义每次更新须同步 About、独立变更记录、日志索引和发布摘要，并在开发文档中补齐操作步骤与验收范围。
- 建立 `docs/changelog/`，补录本次会话的 Claude 修复；保留根目录已有发布历史。
- About 增加已发布功能、本次构建的 Claude 修复说明和完整变更记录链接，版本继续从 Info.plist 读取。
- 新增 Make 构建、测试、流程检查、版本检查和打包入口。流程检查器同时验证本地未提交变更与 PR diff，拒绝遗漏 About、日志摘要、新记录或索引链接的更新。
- 在 XcodeGen 源配置和共享测试 scheme 中仅为测试进程固定中文，消除本机英文偏好造成的既有测试失败。
- PR 在 Apple Silicon 与 Intel runner 分别执行统一验证，限时并取消过期任务；保留原有 Tag 版本检查。

验证：

- `make generate` 成功，生成工程的变更仅为测试 scheme 参数；App 的 Run/Profile 不带测试语言参数。
- `make verify` 通过：4 项流程检查器测试、34 项 Swift 单元测试、About 版本来源与构建后版本检查均通过；无需修改本机英文偏好或手工生成 `.xctestrun`。
- 流程检查器的临时 Git fixture 覆盖未提交更新、已提交 PR diff、缺少 About、新记录缺失、索引漏项和失效链接。
- `make build ARCH=x86_64 BUILD_DIR=.build/intel-check` 交叉构建成功；本机 arm64 构建与测试通过。`make help`、`make release-check` 与 `git diff --check` 通过。

未验证：远程 PR 工作流、Intel 原生运行、About 的人工 UI 检查、DMG 分发与真实 Claude 新额度采集。本次未提交、推送、发布或替换已安装应用。

版本与构建号未修改，仍为 1.2.1（Build 5），尚未发布。
