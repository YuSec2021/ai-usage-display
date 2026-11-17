# 030：补齐 Windows Release 附件与自动发布

日期：2026-11-17

## 问题与结果

Windows CI 已有成功的自包含 ZIP 和 SHA-256，但 Release 只下载、发布 macOS Artifact，导致版本页面没有 Windows 包。修复关联 [Issue #33](https://github.com/YuSec2021/ai-usage-display/issues/33)。

Release 改为调用可复用 Windows workflow，按同一已有版本 Tag 构建，核对 project.yml 版本，并等待 macOS/Windows 均成功后下载两种 Artifact、检查全部 SHA-256、共同上传 DMG/ZIP 及校验文件。Windows 沿用既有核心回归、解压后原生启动和烟雾验证，没有复制一套构建实现。版本构建使用独立并发组且不取消进行中的任务；PR/main 继续按原有方式构建，Release 工作流变更也触发 Windows CI。

Windows 手动构建可填写可选 tag，仅生成验证产物，不发布。SHA-256 文件显式写入 LF 换行，避免 Windows 默认 CRLF 在 macOS shasum 中被读入文件名。Windows 指南、About 和索引同步下载方式与预览支持范围。

## 当前版本附件

v1.2.8 的 Windows 来源是 main 任务 [44012008360](https://github.com/YuSec2021/ai-usage-display/actions/runs/44012008360)，其提交与版本 Tag 一致：`6807c6421efb87208bf8f7c99c0656feb1941d9b`。该任务 16 项核心测试和原生解压烟雾均通过。已向 [v1.2.8 Release](https://github.com/YuSec2021/ai-usage-display/releases/tag/v1.2.8) 追加 ZIP/SHA-256 并补充说明，保留 Tag 及原有 DMG。Artifact 摘要、内层 ZIP 校验、必需 exe/resources.pri 和远端附件摘要均核对通过；校验文件仅规范为 LF，ZIP 字节保持原样。

Windows ZIP SHA-256：`6cdf1263daff86219de6576439827e35a36900256aac0ceb1b0ba76707f98413`。

## 验证与限制

- 新增 4 项发布流程回归：旧配置均失败，修复后通过；actionlint 通过。
- `make verify BASE_REF=origin/main` 通过：38 项流程测试，90 项 Swift 测试（1 项需要显式 GPU 导出的预览跳过，零失败），构建后版本核对通过；`git diff --check` 通过。
- 当前附件回填与远端摘要核对通过；新工作流的远程 CI 结果在 PR 中验收。
- 未执行 macOS About 实际界面检查、Windows 用户机器真实登录/额度刷新、多屏/DPI 或 Explorer 重启验证；CI 原生烟雾使用匿名 fixture。
- 首个新版本 Tag 的完整双平台自动发布须在工作流合入后验收；本次不修改数据采集或 UI 行为。

开发版本继续为 1.2.8（Build 12），未手动升版，未替换本地已安装应用。后续版本仍通过版本 PR、维护者合并与既有 Tag/Release 流程发布。
