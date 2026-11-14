# 使用指南

[返回首页](../README.md) · [隐私说明](../PRIVACY.md)

## 外观与菜单栏

在“设置 → 通用 → 玻璃透明度”中拖动滑块，可将背景透明度设为 0–100%，偏好会自动保存。该设置只调节背景，文字与图标保持清晰；系统启用“减少透明度”时优先使用实色背景。

菜单栏和详情卡片的主圆环表示 **5 小时已用额度**，从顶部顺时针填充。没有可靠的 5 小时数据时显示虚线圆环，不将周额度或 Token 数量作为替代；详情中其他额度窗口单独标明。菜单栏原有“最高用量”偏好现在显示最高 5 小时用量的模型圆环，不再显示数字；也可选择各模型圆环或仅模型图标。准确百分比保留在悬停提示和 VoiceOver 中。

## Codex

Codex 的额度通过本机已登录的 `codex app-server` 官方只读接口主动读取，打开面板时也会立即刷新，重置后无需先发送消息。应用从 PATH、`/opt/homebrew/bin/codex`、`/usr/local/bin/codex` 、`~/.local/bin/codex` 和 `/Applications/ChatGPT.app` 的内置 CLI 查找可执行文件；若 CLI 缺失、未登录、接口不支持或请求超过 8 秒，则回退到本地会话日志。离线旧窗口会提示等待更新，不推算当前百分比。本地 Token 仍从会话日志统计。CLI 自行管理现有认证，AI Usage 不读取凭证文件，不创建对话或生成请求。协议见 [OpenAI 官方 App Server 文档](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt)。

## Claude Code

在“设置 → 集成”中安装 Claude Code 用量集成。安装器会备份现有 `statusLine` 配置，卸载时自动恢复。

Claude Code 的“刷新”会重新读取本地用量文件，不会主动向 Claude 请求订阅额度。完成一次 Claude Code 对话后，status line 才能写入新的额度样本。已超过重置时间的额度不会继续显示为当前值；未知重置时间的样本最多保留对应的 5 小时或 7 天窗口。缺少额度样本时，仍可显示本地 Token 统计。

## Kimi Code

Kimi Code 的本地 Token 无需安装额外集成。应用会读取 `$KIMI_CODE_HOME/sessions`（默认 `~/.kimi-code/sessions`）中的 `usage.record` 用量事件，并兼容旧版 `~/.kimi/sessions` 的状态事件。安装 Kimi Desktop 后，还会从 `~/Library/Logs/kimi-desktop/main.log` 读取订阅总额度百分比和刷新日期。

如需显示 Kimi Code 的 5 小时与每周额度，请在“设置 → 集成 → Kimi Code”中填写从 Kimi Code 控制台获取的 API Key。Key 只保存在 macOS 钥匙串中，应用使用它直接请求 `https://api.kimi.com/coding/v1/usages`；不会发送到开发者服务器。也可在开发环境通过 `KIMI_API_KEY` 环境变量提供。

## MiniMax

MiniMax 只读取 MiniMax Desktop Chromium HTTP 缓存目录
`~/Library/Application Support/MiniMax/Cache/Cache_Data` 中官方订阅额度接口的最近一次完整响应。应用选择 `model_name == "general"` 的套餐记录，兼容新版 Brotli 压缩、`"24%"` 形式的已用百分比与旧版明文剩余百分比，展示 5 小时用量、周额度及重置时间。周额度无限制时直接显示“无限制”，不当作 0% 的有限额度；缓存正写入或损坏时保留并标记上次有效样本。刷新会重新读取此缓存；MiniMax Desktop 尚未写入新响应时，请先打开 MiniMax Code 的额度面板。已过期短窗口不会继续显示为当前用量。该缓存仍是 MiniMax 用量卡片的唯一事实源；应用不使用 Claude Code 会话推算 MiniMax 用量，也不读取 API 日志、Cookie 或对话内容。MiniMax Desktop 当前没有提供可用于每日汇总的历史 Token 数据，因此 MiniMax 不出现在 Token 历史图表中。

MiniMax 无需 API Key；设置只保留本地缓存状态和更新说明。旧版本保存的 MiniMax API Key 与区域偏好不会被自动读取或删除，需要清理遗留 Key 时可使用 macOS“钥匙串访问”。

构建、测试与发布步骤见[开发文档](DEVELOPMENT.md#8-构建与发布)。
