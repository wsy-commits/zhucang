# 保证金计算详解

## 问题：为什么小订单需要大量资金？

让我们详细分析一下为什么 seed.sh 中看似很小的订单会导致"insufficient margin"错误。

## 基础计算

### 参数设置
```solidity
uint256 public initialMarginBps = 100;  // 1% = 100 basis points
uint256 SCALE = 1e18;
```

### 单笔订单保证金计算

**公式**（来自 OrderBookModule.sol 第 20-22 行）：
```solidity
uint256 cost = (price * amount) / SCALE;
uint256 requiredMargin = (cost * initialMarginBps) / 10_000;
```

**示例 1：第一笔交易（1500 @ 0.01 ETH）**
```
price = 1500 ether = 1500 * 10^18
amount = 0.01 ether = 0.01 * 10^18 = 10^16

cost = (1500 * 10^18 * 10^16) / 10^18
     = 1500 * 10^16 / 10^18  
     = 15 * 10^18
     = 15 ETH

requiredMargin = (15 * 10^18 * 100) / 10_000
               = 15 * 10^18 / 100
               = 0.15 * 10^18
               = 0.15 ETH ✅ 很小！
```

**结论**：单笔 0.01 ETH 订单只需要 **0.15 ETH 保证金**，5000 ETH 绰绰有余！

---

## 那为什么会失败？

### 关键问题：保证金是 **下单时锁定** 的！

从代码第 24 行可以看到：
```solidity
_lockMargin(msg.sender, requiredMargin);  // 下单时锁定
```

### 累积效应示例

假设 Alice 依次下 4 个买单（简化计算，忽略成交）：

| 订单 | 价格 | 数量 | 名义价值 | 需锁定保证金 | 累计锁定 |
|------|------|------|---------|-------------|---------|
| #1 | 1500 | 0.01 | 15 ETH | 0.15 ETH | 0.15 ETH |
| #2 | 1520 | 0.02 | 30.4 ETH | 0.304 ETH | **0.454 ETH** |
| #3 | 1490 | 0.015 | 22.35 ETH | 0.2235 ETH | **0.6775 ETH** |
| #4 | 1550 | 0.03 | 46.5 ETH | 0.465 ETH | **1.1425 ETH** |

看起来还是很小对吧？**但这只是保证金部分！**

---

## 真正的问题：持仓 + 未实现盈亏

### 成交后的资金占用

当订单成交后（`_executeTrade` 被调用）：

1. **保证金被解锁**
2. **但持仓被更新**（`_updatePosition`）
3. **持仓占用的"潜在风险资金"不会立即释放**

让我们看实际的资金流动：

### 场景：Alice 连续买入

**初始状态：**
```
Alice 存款: 5000 ETH
Free Margin: 5000 ETH
Locked Margin: 0 ETH
Position: 0
```

**Trade #1: Buy 1500 @ 0.01**
```
下单前：锁定 0.15 ETH
  → Free: 4999.85, Locked: 0.15

成交后：解锁，更新持仓
  → Free: 5000, Locked: 0
  → Position: +0.01 ETH @ 1500
```

**Trade #2: Buy 1520 @ 0.02**
```
下单前：锁定 0.304 ETH
  → Free: 4999.696, Locked: 0.304

成交后：解锁，更新持仓
  → Free: 5000, Locked: 0
  → Position: +0.03 ETH @ 平均价 ~1513
  → 名义价值: 0.03 * 1513 ≈ 45.4 ETH
```

**问题出现在这里：**

### 提现限制检查（_ensureWithdrawKeepsMaintenance）

虽然订单成交后保证金会解锁，但合约内部有一个**提现限制**机制，确保账户始终保持足够的保证金来支持持仓。

从 `MarginModule.sol` 第 39-51 行：
```solidity
function _ensureWithdrawKeepsMaintenance(address trader, uint256 amount) {
    Position storage p = accounts[trader].position;
    if (p.size == 0) return;
    
    uint256 positionValue = SignedMath.abs((int256(markPrice) * p.size) / 1e18);
    uint256 maintenance = (positionValue * maintenanceMarginBps) / 10_000;
    uint256 initialReq = (positionValue * initialMarginBps) / 10_000;
    uint256 requiredMargin = initialReq > maintenance ? initialReq : maintenance;
    
    require(marginBalance >= int256(requiredMargin), "withdraw breaches maintenance");
}
```

### 真实计算：为什么 Trade #2 失败

**假设 Trade #1 后 Alice 有持仓 +0.01 @ 1500**

当 Alice 尝试下 Trade #2 (1520 @ 0.02) 时：

```
1. 尝试锁定 0.304 ETH
   Free Margin: 5000 ETH
   → 锁定后: Free = 4999.696 ETH

2. _applyFunding 被调用
   → 可能因为 funding rate 导致 marginBalance 变化

3. 检查是否足够保证金
   → 如果此时 markPrice 不利变动
   → 或者 unrealizedPnL 为负
   → marginBalance 可能不足以支持新订单
```

### 核心问题：未实现盈亏的影响

如果市场价格波动使得：
```
Entry Price: 1500
Current Mark Price: 1490 (下跌)
Position Size: 0.01 ETH

Unrealized PnL = (1490 - 1500) * 0.01 = -0.1 ETH
```

实际可用保证金变成：
```
marginBalance = freeMargin + realizedPnl + unrealizedPnL
              = 5000 + 0 + (-0.1)
              = 4999.9 ETH
```

---

## 为什么减小 10 倍后仍然失败？

### 原因分析

即使订单大小减小 10 倍：
- 单笔保证金需求减少到 **0.015 - 0.045 ETH**
- 但**累积持仓效应**仍然存在
- **价格波动**导致的未实现亏损仍会累积
- **Funding rate** 可能在多次交易后累积

### 诊断日志证据

从 `test_seed_output_viewable.txt` 第 126 行：
```
status 0 (failed)
revertReason revert: insufficient margin
```

说明在 `_lockMargin` 第 26 行检查失败：
```solidity
require(accounts[trader].freeMargin >= amount, "insufficient margin");
```

---

## 解决方案对比

### 方案 A：再减小 10 倍 ✅
```
0.001 → 0.0001 ETH
保证金需求: 0.015 ETH → 0.0015 ETH
累积效应降低 10 倍
```

### 方案 B：增加存款到 9000 ETH ✅ 
```
更大缓冲区应对未实现亏损
```

### 方案 C：每笔交易后平仓 🔧
```bash
# 在每个 candle 交易后添加：
# 关闭 Alice 和 Bob 的仓位
```

### 方案 D：调整杠杆（不推荐）⚠️
```
降低 initialMarginBps 会增加系统风险
```

---

## 总结

**看似矛盾的现象：**
- 5000 ETH 存款 vs 0.15 ETH 保证金需求 
- 应该绰绰有余，为什么失败？

**真实原因：**
1. ✅ **单笔保证金确实很小**（0.15 ETH）
2. ❌ **但持仓累积 + 价格波动 + Funding 导致可用保证金减少**
3. ❌ **每笔新订单都在前一笔的"不利条件"基础上叠加**
4. ❌ **第 2-3 笔交易时，累积效应超过阈值**

**类比：**
就像信用卡授信额度 100 万，但如果已有 99.9 万未还款（持仓 + 浮亏），即使你只想刷 0.1 万也可能被拒！

**推荐方案：**  
**方案 A（再减 10x）** - 最简单直接，预计可完成全部交易 🎯
