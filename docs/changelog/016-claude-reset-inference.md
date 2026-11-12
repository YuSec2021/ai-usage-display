# 016：合并 Claude 重置推断遍历

日期：2026-11-13

Issue：https://github.com/YuSec2021/ai-usage-display/issues/7

通过用量字段、窗口时长和边界谓词复用遍历；短周期 previous==0 与周周期 previous<=0 保持原意。新增空样本、零转正、首次正值、用量下降、字段缺失、负值与不同字段起点的表驱动回归。

验证：make generate、make verify 通过；16 项流程、69 项功能测试通过，1 项 GPU 预览默认跳过。表驱动检查九类序列及独立字段起点，原推断过期回归保持通过。

版本保持 1.2.2（Build 6），未发布；变更由独立工作分支承载。
