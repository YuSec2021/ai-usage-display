# AI Usage 变更日志

从本次流程接入起，逐次变更采用编号记录；此前的发布历史保留在根目录 [CHANGELOG.md](../../CHANGELOG.md)。记录描述对应构建和验证范围，不代表已发布或已安装。

## 最新更新

- [006：原生预览导出改为本机显式启用](006-local-preview-export.md)：避免 Intel 托管 runner 的虚拟 GPU 触发 Metal 崩溃，CI 继续执行全部逻辑与菜单圆环图像测试。
- [005：自动构建通用 Release 安装包](005-automated-release-build.md)：Tag 或手动触发版本校验、测试、通用 DMG 构建及 GitHub Release 附件上传，整合原有 Tag 检查。
- [004：导入 standard-dev-flow 完整技能包](004-import-standard-dev-flow.md)：从 `ai_novel_agent` 原样复制四个技能文件并提供本地入口，保留当前项目的 Git 与验证规则。
- [003：液态玻璃界面与模型额度圆环](003-liquid-glass-quota-rings.md)：macOS 26 原生 Liquid Glass、透明度设置、ChatGPT/模型图标外圈显示 5 小时已用额度，并保留无数据和无障碍状态。
- [002：接入 MacEverything 标准化开发流程](002-standard-development-workflow.md)：同步 About 与日志的规则、统一 Make 入口、固定测试语言，以及 Apple Silicon/Intel PR 检查；版本保持 1.2.1（Build 5）。
- [001：修复 Claude Code 旧额度与缺失数据显示](001-claude-quota-refresh.md)：移除已过期额度、按窗口选择有效来源，保留无额度快照时的本地 Token；真实新额度样本尚待验证。

## 变更索引

| # | 类型 | 标题 | 日期 |
| --- | --- | --- | --- |
| [001](001-claude-quota-refresh.md) | bugfix | 修复 Claude Code 旧额度与缺失数据显示 | 2026-11-11 |
| [002](002-standard-development-workflow.md) | workflow | 接入 MacEverything 标准化开发流程 | 2026-11-11 |
| [003](003-liquid-glass-quota-rings.md) | feature | 液态玻璃界面与模型额度圆环 | 2026-11-11 |
| [004](004-import-standard-dev-flow.md) | chore | 导入 standard-dev-flow 完整技能包 | 2026-11-11 |
| [005](005-automated-release-build.md) | chore | 自动构建通用 Release 安装包 | 2026-11-11 |
| [006](006-local-preview-export.md) | test | 原生预览导出改为本机显式启用 | 2026-11-12 |
