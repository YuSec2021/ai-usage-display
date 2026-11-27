# Issue #45：修复自动版本 PR 因跨 Runner XcodeGen 输出差异导致发布契约失败

## 基本信息

- Issue：https://github.com/YuSec2021/ai-usage-display/issues/45
- 类型：`type/bug`
- 状态：待实施
- 唯一工作分支：`codex/issue-45-release-contract-xcodegen`
- 负责人：YuSec2021
- 设计或产出文档：N/A — Bug 使用四行根因说明，不要求模块设计。

## 背景

`Automatic release` 准备版本 PR（如 `v1.2.9` 的 PR #37 与 `v1.2.10` 的 PR #44）后，双架构 `PR checks` 屡次在 `scripts/release-contract.py` 处失败，阻断自动发版流程。先前发布只能人工回退 `AIUsage.xcscheme` 与 `LastUpgradeCheck` 才能勉强合并，如今随着 Apple Silicon Runner 升级到 XcodeGen 2.48.0 而 Intel Runner 仍为 XcodeGen 2.46.0，任何单一静态生成结果都无法同时通过双架构逐字节比对。

## 目标

- 在 `scripts/release-contract.py` 中允许并严格校验 XcodeGen 生成的 `AIUsage.xcodeproj/xcshareddata/xcschemes/AIUsage.xcscheme`，并对已知跨 XcodeGen 版本元数据差异做最小化规范后再比对，确保 `Verify arm64` 与 `Verify x86_64` 均能稳定通过，同时继续拦截任何篡改。
- 在 `.github/workflows/release.yml` 中先于 `make generate` 执行 `make verify`，避免 Tag 检出因 Runner 上 Homebrew XcodeGen 升级弄脏 `AIUsage.xcodeproj` 而导致工作区洁净检查误报失败。
- 补充能复现旧版失败与新版通过的回归测试，并同步 About 与编号变更记录 `035`。

## 非目标

- 不修改 macOS/Windows 产品功能代码、Provider 采集逻辑或 `project.yml` 版本号。
- 不放宽版本 PR 除 `project.yml`、`README.md`、`CHANGELOG.md`、`docs/changelog/README.md`、单条发布记录、`AIUsage.xcodeproj/project.pbxproj`、`AIUsage.xcodeproj/xcshareddata/xcschemes/AIUsage.xcscheme` 以外任何文件的限制。
- 不绕过受保护 `main` 的双架构 PR 检查或修改既有 Tag。

## 根因说明

- 现象：`Automatic release` 生成的 `v1.2.10` 版本 PR #44 在 `PR checks` 的 `Verify arm64` 与 `Verify x86_64` 双双失败，报错为 `版本 PR 含非版本产物：AIUsage.xcodeproj/xcshareddata/xcschemes/AIUsage.xcscheme`。
- 根因：`scripts/release-contract.py` 第 36-37 行未将 `AIUsage.xcodeproj/xcshareddata/xcschemes/AIUsage.xcscheme` 列入 `allowed`，而 `.github/workflows/auto-release.yml` 第 77 行会提交整个 `AIUsage.xcodeproj`；同时第 64 行对 `AIUsage.xcodeproj` 做原始逐字节比对，但 `macos-15` / `macos-26` 安装 Homebrew `xcodegen 2.48.0`（输出 `LastUpgradeCheck = 1600`、`LastUpgradeVersion = "1600"` 与 `buildArchitectures = "Automatic"`），`macos-15-intel` 安装 `xcodegen 2.46.0`（输出 `1430` 且无 `buildArchitectures`），导致双架构不可能逐字节一致；另外 `.github/workflows/release.yml` 第 65-66 行在 Tag 检出后先执行 `make generate` 再执行 `make verify`，XcodeGen 版本漂移也会弄脏工作区并触发 `check-preparation.py` 失败。
- 影响面：每次 `main` 更新后由 `Automatic release` 自动创建的版本 PR 都会在双架构检查中失败，且后续手动重跑旧 Tag 的 `Release` 工作流也存在失败风险；不影响已安装应用与用户本地数据。
- 回归：在 `Tests/WorkflowTests/test_release_contract.py` 新增使用隔离伪 `xcodegen` 模拟 2.48.0 与 2.46.0 双向输出差异的回归测试（覆盖放行合法版本元数据差异与拦截 `project.pbxproj`/`AIUsage.xcscheme` 篡改及多余文件），并在 `Tests/WorkflowTests/test_release_workflows.py` 固定 `release.yml` 先执行 `make verify` 再执行 `make generate` 的顺序契约。

## 验收标准

- [ ] `scripts/release-contract.py` 允许 `AIUsage.xcodeproj/xcshareddata/xcschemes/AIUsage.xcscheme` 并仅规范化 `LastUpgradeCheck`、`LastUpgradeVersion` 与 `buildArchitectures = "Automatic"` 三项 XcodeGen 版本元数据，其余内容仍严格逐字节校验。
- [ ] `Tests/WorkflowTests/test_release_contract.py` 新增回归测试在修复前复现失败、修复后通过，且篡改 `AIUsage.xcscheme`（如追加参数或修改 `buildArchitectures` 值）、篡改 `project.pbxproj` 或新增额外 `.xcscheme` 仍被拒绝。
- [ ] `.github/workflows/release.yml` 在 Tag 检出后先执行 `make verify` 再执行 `make generate`，`Tests/WorkflowTests/test_release_workflows.py` 新增对应回归验证。
- [ ] `make verify BASE_REF=origin/main` 与 `git diff --check` 全部通过，About 说明、`docs/changelog/035-release-contract-xcodegen.md`、索引与 `CHANGELOG.md` 同步更新，且不手动升版。
- [ ] PR 远端 `Verify arm64`、`Verify x86_64` 与 `Windows x64` 检查全部通过；合入 `main` 后新生成的 `v1.2.10` 版本 PR 双架构检查通过。

## 模块拆解

| 模块 / 路径 | 修改内容 | 依赖 | 完成条件 |
|---|---|---|---|
| `scripts/release-contract.py` | 将 `AIUsage.xcscheme` 纳入生成工程白名单，并对两份 XcodeGen 生成文件做最小化版本元数据规范后严格比对 | 无 | 跨版本回归通过且篡改用例全部被拦截 |
| `.github/workflows/release.yml` | 将 Tag 构建中的 `make verify` 调整至 `make generate` 之前，避免 XcodeGen 漂移污染工作区 | 无 | 工作流回归与 YAML 校验通过 |
| `Tests/WorkflowTests/test_release_contract.py`、`Tests/WorkflowTests/test_release_workflows.py` | 补充跨 XcodeGen 版本比对、篡改拦截与 `release.yml` 验证顺序回归 | `scripts/release-contract.py`、`.github/workflows/release.yml` | `make check-process` 全部通过 |
| `Sources/AIUsage/Views/SettingsView.swift`、`CHANGELOG.md`、`docs/changelog/035-release-contract-xcodegen.md`、`docs/changelog/README.md` | 同步 About 构建说明与 `035` 编号变更记录 | 实施与验证完成 | `make verify BASE_REF=origin/main` 全部通过 |

## 风险、假设与待决策项

- 风险：如果未来 XcodeGen 新增除上述三项外的无害格式字段，仍需按同样方式显式加入白名单规范，不能宽泛忽略整个文件，以免破坏防篡改契约。
- 假设：GitHub Actions macOS Runner 的 Homebrew `xcodegen` 版本差异仅涉及上述 Xcode 升级提示号与默认 `buildArchitectures = "Automatic"` 属性，已基于 PR #44 实测 diff 验证。
- 待决策：N/A — 方案范围清晰，无需额外决策。

## 验证计划

- 自动验证：先执行 `make check-prepare BASE_REF=origin/main` 确认独立准备提交有效；修复前验证新回归用例失败，修复后执行 `make verify BASE_REF=origin/main`、`git diff --check` 与 `actionlint`（如本机已安装），并在 PR 上通过双架构 Mac 与 Windows CI 检查。
- 人工验证：合入 `main` 后检查 `Automatic release` 新生成的 `v1.2.10` 版本 PR 是否无需人工修改直接通过 `Verify arm64` 与 `Verify x86_64`；本次不修改应用 UI 与 Provider 采集，macOS 界面实机交互与真实在线额度刷新未复验并在变更记录中说明。
- 埋点与可观测性：不新增外部遥测或埋点；沿用 GitHub Actions 日志与 `release-contract.py` 明确错误输出定位契约问题。
- 发布与回滚：按受保护 `main` PR 流程合入，由后续 `Automatic release` 生成新的 `v1.2.10` 版本 PR 并关闭旧版本 PR；异常时直接回滚本 PR 提交即可恢复既有契约逻辑。

## 完成定义

- [ ] 根因与模块拆解和最终实现一致。
- [ ] 所有验收标准已完成。
- [ ] 必要测试、构建和审查已通过。
- [ ] 文档、发布及回滚事项已处理或明确标记不适用。
