# AI Usage 隐私说明

AI Usage 是一款本地运行的 macOS 菜单栏应用。

## 读取的数据

- Codex 本地会话中的 token 用量与额度窗口字段。
- Claude Code status line 提供的用量、额度与重置时间字段。
- Claude Desktop 本地保存的套餐用量百分比历史。

## 不读取或不保存的数据

- 登录密码、访问令牌、API Key 和浏览器 Cookie。
- 提示词、回答正文、源代码和工具调用参数。
- 与用量展示无关的会话内容。

## 网络与数据上传

AI Usage 的用量解析在本机完成。当前版本不会把用量数据、会话信息或设备信息上传到开发者服务器。

## 本地文件

Claude Code 集成启用后，应用会在用户的 Application Support 目录保存仅包含用量字段的本地快照。卸载集成时会恢复安装前的 Claude Code status line 配置。

---

# AI Usage Privacy Notice

AI Usage is a local macOS menu bar application. It reads only local usage, rate-limit, reset-time, and token-count fields required for display. It does not read or store passwords, access tokens, API keys, browser cookies, prompts, responses, source code, or tool arguments. The current version performs usage parsing locally and does not upload usage or conversation data to a developer-operated server.
