# 028：显示 Grok 订阅周额度

日期：2026-11-17

Issue：[30](https://github.com/YuSec2021/ai-usage-display/issues/30)。唯一分支：`codex/issue-30-grok-subscription-usage`。准备提交 `d308d7b` 独立包含 Issue、JSON 和模块设计，先通过准备门禁再实施。

## 问题与结果

新增 Grok 个人订阅周额度显示。数据来自已登录 Grok Bot 的本地共享周额度缓存；不支持浏览器直接登录或 xAI API Key 用量。用户需要在 Grok Bot 的 Usage & Billing 更新缓存，AI Usage 的刷新只重新读取本地文件。

## 实现范围

- 精确读取当前账号槽位与该账号 weekly-usage.cache 两个逻辑键，支持 Base32 文件名及长键 SHA-256 帧校验；每份文件有界读取，不扫描其他账号、凭证或会话，不发网络请求，不修改 Grok Bot 数据。
- 保留真实 0%，拒绝负值、非有限数、缺字段及未知 schema；不将缺失额度当作零值。账号切换、退出登录、团队状态和额度 slice 删除清空旧样本；同账号半写可保留仍有效的旧样本并标旧。
- 超过 5 分钟标记旧样本；超过缓存 expiresAtMs、24 小时上限或服务端重置时间不再展示当前进度；未知重置时间不推算。
- Grok 主圆环为周额度，其他模型继续选择明确的 300 分钟窗口；最高 5 小时模式不比较周额度。Grok 不显示本地 Token，不生成 Token 历史。
- 新增图标、默认全选迁移、设置数据来源说明和打开 Grok Bot 的入口；保留自定义选择及排序。图标来源与 MIT 许可见 [GROK_ASSET_LICENSE](../GROK_ASSET_LICENSE.md)。
- About、编号记录和索引、Unreleased、使用指南及生成工程同步。028 编号避开已存在的 v1.2.8 版本 PR 使用的 027。

## 验证

临时 fixture 回归覆盖零值、普通值、超限、缺少额度、schema、团队隔离、账号切换/退出与读取竞争、缓存/周期到期、半写与删除、文件上限/符号链接和长键帧；表现回归覆盖 Grok 周圆环、未知与零值图像差异及最高 5 小时隔离；Store 回归覆盖全选迁移、自定义选择及幂等性。最终 `make verify BASE_REF=origin/main` 通过：34 项流程测试、90 项 Swift 测试报告（默认跳过 1 项 GPU 预览，0 失败），构建版本 1.2.7（Build 11）核对通过。另行启用 GPU 预览并运行对应测试，1 项通过；人工检查浅色/深色匿名样本渲染，Grok 显示周额度、重置时间，且没有 Token 行。

## 未验证范围

已通过已安装 Grok Bot 的 Usage & Billing 界面及额度白名单确认数据来源与字段结构；新增 AI Usage 实际窗口核对因 Mac 锁屏未能执行，未验证生产 Provider 的真实缓存刷新或安装。匿名样本渲染不等于实际窗口交互验证。Windows、浏览器直接登录、团队额度、xAI API Key 用量、24 小时常驻资源占用均不在本次验证范围；未自动合并 main、升版或替换已安装应用。

## 版本

开发分支沿用 main 的 1.2.7（Build 11），无手动升版；About 的版本/构建号继续读取 Info.plist。后续合入最新 main 时按其已发布版本同步，最终版本由版本 PR 决定。
