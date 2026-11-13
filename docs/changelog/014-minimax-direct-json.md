# 014：MiniMax 标准缓存直接解码 JSON

日期：2026-11-13

Issue：https://github.com/YuSec2021/ai-usage-display/issues/5

完整 Simple Cache 响应体直接交给 JSONDecoder，集中状态码校验；仅遗留二进制输入使用括号扫描。移除被有效样本前置检查保证的空窗口分支，保留 CRC、解压上限、旧样本和无限制保护。

验证：make verify 通过；16 项流程、62 项功能测试通过，1 项 GPU 预览默认跳过。新回归验证标准体的转义 JSON key 可直接解码、夹杂内容不会落入遗留回退，原明文/Brotli/CRC/半写/无限制回归保留。

版本保持 1.2.2（Build 6），未发布；变更由独立工作分支承载。
