# 010：修复 MiniMax 额度缓存刷新

日期：2026-11-13

问题：新版 MiniMax Code 额度响应改为 Brotli 压缩与 `current_interval_used_percent: "24%"`，原 provider 只搜索明文 JSON 和旧 remaining 字段，刷新时没有读取到额度。周额度无限制也缺少对应表示。

修改：按 Chromium Simple Cache v5 的结构与 CRC32 读取已知额度接口，使用 macOS 原生 Brotli 解压，限制输出大小，不增加第三方库或外部运行命令。解析新已用百分比字符串/数字，兼容旧剩余百分比；无限制不展示为有限百分比。半写和损坏缓存保留带旧时间的样本并标记过期，完整新样本恢复正常。缺少缓存时提示打开 MiniMax Code 的额度面板。保留此前 Codex 主动刷新修复，并修正其测试 fixture 在本地午夜时把前日 Token 当作今日 Token 的问题。

验证：make verify 通过（16 项流程测试、54 项功能测试，1 项 GPU 预览默认跳过）；显式开启本机预览后 55 项 Swift 测试全部通过。合成缓存覆盖独立 Brotli 样本、24%/0%、无限制、同文件更新、写入中保留、CRC、错误、边界与解压上限。真实只读探针先读取到 25%，重置后读取当前 0%，周额度无限制，与 MiniMax Code 官方用量菜单一致。通用 Release、双架构、版本及签名校验通过，本机应用已备份、替换并正常启动。

界面验证：已核对深色示例卡片的 MiniMax 圆环和无限制布局；新安装应用的菜单面板自动化抓取超时，未声称完成该项核对。

限制：数据源仍是 MiniMax Desktop 缓存；Desktop 不更新时，AI Usage 不会主动调用其私有 API，也不会读 Cookie 或生成当前用量。此前的过期 Zstandard 样本不作为当前值。

版本保持 1.2.2（Build 6），本机修复构建以 About 说明区分；尚未推送、合并或发布。
