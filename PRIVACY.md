# AI Usage 隐私说明

AI Usage 是一款本地运行的 macOS 菜单栏应用。

## 读取的数据

- Codex 本地会话中的 token 用量与额度窗口字段。
- Claude Code status line 提供的用量、额度与重置时间字段。
- Claude Desktop 本地保存的套餐用量百分比历史。
- Kimi Code 本地 `wire.jsonl` 会话事件中的时间与 token 用量字段。
- Kimi Desktop 本地日志中的订阅用量比例与重置时间字段。
- 用户主动配置 Kimi Code API Key 后，从 Kimi 官方用量接口返回的 5 小时与每周额度百分比、窗口长度和重置时间。
- MiniMax Desktop 本地 HTTP 缓存中官方订阅额度响应的套餐类型、剩余百分比与重置时间字段。
- 用户主动配置 MiniMax API Key 后，MiniMax 官方模型列表接口返回的模型标识，仅用于确认授权有效。

## 不读取或不保存的数据

- 登录密码、浏览器 Cookie及非用户主动配置的访问令牌或 API Key。
- 提示词、回答正文、源代码和工具调用参数。
- 与用量展示无关的会话内容。

## 网络与数据上传

AI Usage 的本地用量解析在本机完成。配置 Kimi Code API Key 后，应用会将该 Key 作为 Bearer 凭证仅发送至 Kimi 官方的 `https://api.kimi.com/coding/v1/usages`，以读取 5 小时与每周额度。

配置 MiniMax API Key 后，应用会将该 Key 作为 Bearer 凭证，仅发送至用户所选区域的官方模型列表接口：国内为 `https://api.minimaxi.com/v1/models`，海外为 `https://api.minimax.io/v1/models`。该请求不包含提示词或生成内容，只用于验证授权。应用不会把 Key、用量数据、会话信息或设备信息上传到开发者服务器。

## 本地文件

Claude Code 集成启用后，应用会在用户的 Application Support 目录保存仅包含用量字段的本地快照。卸载集成时会恢复安装前的 Claude Code status line 配置。

Kimi Code 用量直接从 `$KIMI_CODE_HOME/sessions`（默认 `~/.kimi-code/sessions`）读取，不修改 Kimi 配置与会话文件。

Kimi Desktop 额度从 `~/Library/Logs/kimi-desktop/main.log` 增量读取。应用不会读取 Kimi Desktop Cookie、访问令牌、IndexedDB 或对话上下文缓存。

用户在设置中配置的 Kimi Code API Key 只保存在 macOS 钥匙串中，可随时从设置移除，不写入 `UserDefaults`、日志、项目文件或用量历史。

用户在设置中配置的 MiniMax API Key 同样只保存在 macOS 钥匙串中，可随时移除。`UserDefaults` 只保存所选 API 区域，不保存 Key。

MiniMax 用量只从 `~/Library/Application Support/MiniMax/Cache/Cache_Data` 中最近一次完整的官方订阅额度响应读取。应用只解码 `general` 套餐的 5 小时与本周剩余比例和周期时间，不读取 API 日志、Cookie、其他访问令牌、对话内容、`~/.claude/projects` 或自定义的 `~/.claude-minimax` 目录。用户主动配置的 MiniMax API Key 只用于上述官方授权验证。

---

# AI Usage Privacy Notice

AI Usage is a local macOS menu bar application. It reads only usage, rate-limit, reset-time, and token-count fields required for display. Explicitly configured Kimi Code and MiniMax API keys are stored only in macOS Keychain and sent only to their documented official endpoints. MiniMax authorization uses the selected region's model-list endpoint and sends no prompt or generated content. MiniMax usage still comes exclusively from the latest complete official subscription-quota response in MiniMax Desktop's local HTTP cache. The app does not send credentials, usage, or conversation data to a developer-operated server, and does not save prompts, responses, source code, or tool arguments.
