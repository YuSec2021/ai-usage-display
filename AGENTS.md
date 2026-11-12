# 项目更新流程

本流程移植自 MacEverything 的 `AGENTS.md`、变更日志与构建检查，按 AI Usage 的 Swift/Xcode 工程适配。来源与操作步骤见 [开发文档](docs/DEVELOPMENT.md#0-标准化开发流程)。

每次更新项目时，必须同步完成以下事项：

1. 先阅读相关实现、调用方和测试，保留工作区已有修改。新建分支使用 `codex/` 前缀。
2. 更新 `Sources/AIUsage/Views/SettingsView.swift` 中的 About 版本说明，使内容反映本次构建的实际行为；版本和构建号继续从 Info.plist 读取。
3. 在 `docs/changelog/` 中新增编号变更记录，同步更新 `docs/changelog/README.md` 的“最新更新”和“变更索引”，以及根目录 `CHANGELOG.md` 的未发布摘要。
4. 修复须包含相关回归验证。Provider 测试使用临时 fixture，不读取用户的真实日志或凭证；UI 检查和真实额度刷新未验证时，明确记录。
5. 完成前运行 `make verify`，检查 About、变更记录、版本配置与实际改动一致。修改 `project.yml` 后运行 `make generate` 并提交生成的工程。
6. 仅在准备发布时递增 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`，同步 README 与发布日志，再执行版本检查与打包。普通开发更新不自动升版、打 Tag、发布或替换已安装应用。

统一命令：`make help`。详细验收与发布步骤见 [开发文档](docs/DEVELOPMENT.md)。
