# 006：原生预览导出改为本机显式启用

日期：2026-11-12

现象：PR #1 首轮 Apple Silicon CI 成功，Intel CI 在导出示例布局时崩溃；其余测试完成。

根因：`Tests/AIUsageTests/PresentationTests.swift` 的 `testRenderCardAndRingPreviewsWithIsolatedFixtures` 默认调用 SwiftUI `ImageRenderer`。Intel 托管 runner 的虚拟 GPU 无法加载对应 Metal 目标架构，触发 `Target device architecture is nil` 断言；该断言发生在系统图形驱动中，无法靠 Swift 错误捕获恢复。

影响：应用代码可以编译，全部额度逻辑与菜单圆环图像测试正常，但非必需的示例图片导出阻塞了 CI。

回归：预览导出仅在 `AI_USAGE_RENDER_PREVIEWS=1` 时运行；默认测试通过 `XCTSkip` 明确说明硬件要求。CI 保留全部逻辑和菜单圆环图像测试，不通过跳过整个测试套件解决问题。本机可用 `TEST_RUNNER_AI_USAGE_RENDER_PREVIEWS=1 make test` 生成浅深色图片。

本机验证：`make verify BASE_REF=origin/main` 通过，包含 9 项流程测试和 39 项逻辑/圆环图像测试，预览导出明确标记为跳过；`TEST_RUNNER_AI_USAGE_RENDER_PREVIEWS=1 make test` 也通过，40 项 Swift 测试全部执行并生成预览。`git diff --check` 通过。远程修复后的结果以 [PR #1 检查](https://github.com/YuSec2021/ai-usage-display/pull/1/checks) 为准。

应用行为、版本 1.2.1 和构建号 5 不变。
