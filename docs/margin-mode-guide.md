# 逐仓/全仓模式切换功能指南

本指南详细说明了永续合约交易所的逐仓（Isolated）和全仓（Cross）保证金模式切换功能。

---

## 1. 功能概述

### 1.1 两种保证金模式

| 特性 | 全仓模式 (Cross) | 逐仓模式 (Isolated) |
|------|------------------|---------------------|
| **保证金共享** | 所有仓位共享一个保证金池 | 每个仓位有独立的保证金 |
| **挂单保证金计算** | Max(买单保证金, 卖单保证金) | 买单保证金 + 卖单保证金 |
| **清算风险** | 所有仓位相互影响 | 每个仓位独立计算 |
| **资金效率** | 高（保证金可复用） | 低（需要更多保证金） |
| **适合策略** | 对冲、多仓位、套利 | 单方向重仓、风险隔离 |

### 1.2 核心概念

**全仓模式 (Cross Margin)**
- 所有仓位共享 `crossMargin` 保证金池
- 挂单时，买单和卖单的保证金需求取最大值（因为它们不会同时成交）
- 一个仓位亏损会影响所有仓位
- 资金利用率高，适合对冲策略

**逐仓模式 (Isolated Margin)**
- 每个仓位有独立的 `isolatedMargin`
- 挂单时，买单和卖单的保证金需求相加（因为都是独立仓位）
- 每个仓位的风险独立，一个仓位清算不影响其他仓位
- 需要更多保证金，适合单方向重仓

---

## 2. 数据结构

### 2.1 合约数据结构

```solidity
// 保证金模式枚举
enum MarginMode {
    CROSS,      // 全仓模式
    ISOLATED    // 逐仓模式
}

// 持仓结构体
struct Position {
    int256 size;              // 持仓数量 (正=多头, 负=空头)
    uint256 entryPrice;       // 入场价格 (加权平均)
    MarginMode mode;          // 保证金模式
    uint256 isolatedMargin;   // 逐仓保证金（仅逐仓模式使用）
}

// 账户结构体
struct Account {
    uint256 crossMargin;      // 全仓保证金池
    Position position;        // 用户持仓
}
```

### 2.2 前端状态管理

```typescript
class ExchangeStore {
    marginMode: MarginMode;        // 当前保证金模式
    crossMargin: bigint;           // 全仓保证金余额
    isolatedMargin: bigint;        // 逐仓保证金余额
    // ...
}
```

---

## 3. 合约接口

### 3.1 视图函数

```solidity
// 获取用户全仓保证金
function getCrossMargin(address trader) external view returns (uint256);

// 获取用户保证金模式
function getMarginMode(address trader) external view returns (MarginMode);

// 获取用户逐仓保证金
function getIsolatedMargin(address trader) external view returns (uint256);

// 获取完整账户详情
function getAccountDetails(address trader) external view returns (
    uint256 crossMargin,
    MarginMode mode,
    uint256 isolatedMargin,
    int256 size,
    uint256 entryPrice
);
```

### 3.2 保证金管理

```solidity
// 分配保证金到逐仓（从 crossMargin 转移到 isolatedMargin）
function allocateToIsolated(uint256 amount) external;

// 从逐仓回收保证金（从 isolatedMargin 转移回 crossMargin）
function removeFromIsolated(uint256 amount) external;
```

### 3.3 下单接口

```solidity
// 下单（支持保证金模式参数）
function placeOrder(
    bool isBuy,
    uint256 price,
    uint256 amount,
    uint256 hintId,
    MarginMode marginMode  // 保证金模式：CROSS 或 ISOLATED
) external returns (uint256 orderId);
```

---

## 4. 使用流程

### 4.1 全仓模式交易流程

```solidity
// 1. 充值保证金到全仓池
exchange.deposit{value: 100 ether}();

// 2. 直接下单（默认 CROSS 模式）
exchange.placeOrder(true, 1000e18, 1 ether, 0, MarginMode.CROSS);

// 3. 所有仓位共享 crossMargin
// 4. 提现时检查所有仓位的维持保证金
exchange.withdraw(10 ether);
```

### 4.2 逐仓模式交易流程

```solidity
// 1. 充值保证金
exchange.deposit{value: 100 ether}();

// 2. 分配保证金到逐仓
exchange.allocateToIsolated(20 ether);

// 3. 使用 ISOLATED 模式下单
exchange.placeOrder(true, 1000e18, 1 ether, 0, MarginMode.ISOLATED);

// 4. 可以继续追加逐仓保证金
exchange.allocateToIsolated(10 ether);

// 5. 平仓后可以回收保证金
exchange.removeFromIsolated(15 ether);

// 6. 回收的保证金回到 crossMargin
// crossMargin 增加，isolatedMargin 减少
```

---

## 5. 保证金计算逻辑

### 5.1 全仓模式保证金计算

```solidity
function _calculateCrossWorstCaseMargin(address trader) internal view returns (uint256) {
    // 1. 计算买单保证金需求
    uint256 buyOrderMargin = sum(all buy orders);

    // 2. 计算卖单保证金需求
    uint256 sellOrderMargin = sum(all sell orders);

    // 3. 计算持仓保证金需求
    uint256 positionMargin = calculatePositionMargin(position.size);

    // 4. 全仓：取买单和卖单的最大值 + 持仓保证金
    return positionMargin + max(buyOrderMargin, sellOrderMargin);
}
```

**示例：**
- 买单：1 ETH @ 1000 USD，初始保证金 1% = 10 USD
- 卖单：1 ETH @ 1000 USD，初始保证金 1% = 10 USD
- 持仓：1 ETH @ 1000 USD，初始保证金 1% = 10 USD
- **全仓保证金需求 = 10 + Max(10, 10) = 20 USD**

### 5.2 逐仓模式保证金计算

```solidity
function _calculateIsolatedWorstCaseMargin(address trader) internal view returns (uint256) {
    // 1. 计算买单保证金需求
    uint256 buyOrderMargin = sum(all buy orders);

    // 2. 计算卖单保证金需求
    uint256 sellOrderMargin = sum(all sell orders);

    // 3. 计算持仓保证金需求
    uint256 positionMargin = calculatePositionMargin(position.size);

    // 4. 逐仓：买单 + 卖单 + 持仓（全部相加）
    return positionMargin + buyOrderMargin + sellOrderMargin;
}
```

**示例：**
- 买单：1 ETH @ 1000 USD，初始保证金 1% = 10 USD
- 卖单：1 ETH @ 1000 USD，初始保证金 1% = 10 USD
- 持仓：1 ETH @ 1000 USD，初始保证金 1% = 10 USD
- **逐仓保证金需求 = 10 + 10 + 10 = 30 USD**

---

## 6. 清算逻辑

### 6.1 全仓模式清算

```solidity
function _canLiquidateCross(address trader) internal view returns (bool) {
    Position memory p = accounts[trader].position;

    // 1. 计算未实现盈亏
    int256 unrealized = _unrealizedPnl(p);

    // 2. 检查全仓保证金池
    int256 marginBalance = int256(crossMargin) + unrealized;

    // 3. 计算维持保证金
    uint256 maintenance = calculateMaintenance(p);

    // 4. 判断是否可清算
    return marginBalance < int256(maintenance);
}
```

**清算条件：** `crossMargin + unrealizedPnl < maintenanceMargin`

### 6.2 逐仓模式清算

```solidity
function _canLiquidateIsolated(address trader) internal view returns (bool) {
    Position memory p = accounts[trader].position;

    // 1. 计算未实现盈亏
    int256 unrealized = _unrealizedPnl(p);

    // 2. 只检查逐仓保证金
    int256 marginBalance = int256(isolatedMargin) + unrealized;

    // 3. 计算维持保证金
    uint256 maintenance = calculateMaintenance(p);

    // 4. 判断是否可清算
    return marginBalance < int256(maintenance);
}
```

**清算条件：** `isolatedMargin + unrealizedPnl < maintenanceMargin`

---

## 7. 前端使用

### 7.1 UI 组件

**OrderForm.tsx - 保证金模式选择器**

```tsx
// 保证金模式选择
<div className="flex bg-[#0B0E14] p-1 rounded-lg">
    <button
        onClick={() => setMarginMode(MarginMode.CROSS)}
        className={marginMode === MarginMode.CROSS ? 'active' : ''}
    >
        Cross
    </button>
    <button
        onClick={() => setMarginMode(MarginMode.ISOLATED)}
        className={marginMode === MarginMode.ISOLATED ? 'active' : ''}
    >
        Isolated
    </button>
</div>
```

**逐仓保证金管理（仅在 Isolated 模式显示）**

```tsx
{marginMode === MarginMode.ISOLATED && (
    <div className="isolated-margin-management">
        {/* 显示余额 */}
        <span>Cross: {crossMargin}</span>
        <span>Isolated: {isolatedMargin}</span>

        {/* 分配保证金 */}
        <button onClick={handleAllocate}>
            Allocate →
        </button>

        {/* 回收保证金 */}
        <button onClick={handleRemove}>
            ← Remove
        </button>
    </div>
)}
```

### 7.2 状态管理

```typescript
// 下单时传递保证金模式
const placeOrder = async (params: {
    side: OrderSide;
    amount: string;
    marginMode?: MarginMode;  // CROSS 或 ISOLATED
}) => {
    await exchange.placeOrder({
        side: params.side,
        marginMode: params.marginMode || this.marginMode,
        // ...
    });
};

// 分配保证金到逐仓
const allocateToIsolated = async (amount: string) => {
    await exchange.allocateToIsolated(parseEther(amount));
    await this.refresh();  // 刷新余额
};

// 从逐仓回收保证金
const removeFromIsolated = async (amount: string) => {
    await exchange.removeFromIsolated(parseEther(amount));
    await this.refresh();  // 刷新余额
};
```

---

## 8. 测试验证

### 8.1 运行测试

```bash
cd contract

# 运行逐仓/全仓模式测试
forge test --match-contract DayMarginModeTest -vvv

# 运行特定测试
forge test --match-contract DayMarginModeTest --match-test "testAllocateToIsolated" -vvv
```

### 8.2 测试覆盖

测试文件 `contract/test/DayMarginMode.t.sol` 包含以下测试组：

1. **保证金模式设置** (5 个测试)
   - 新仓位可以设置为逐仓模式
   - 新仓位默认为全仓模式
   - 不能在已有仓位上切换模式
   - 平仓后可以重新选择模式

2. **保证金分配/回收** (6 个测试)
   - 分配保证金到逐仓
   - 从逐仓回收保证金
   - 全仓保证金不足时无法分配
   - 逐仓保证金不足时无法回收
   - 无仓位时可以任意分配/回收

3. **保证金计算逻辑** (2 个测试)
   - 全仓模式挂单保证金取最大值
   - 逐仓模式挂单保证金相加

4. **清算逻辑** (3 个测试)
   - 逐仓清算只检查逐仓保证金
   - 全仓清算检查全仓保证金
   - 逐仓模式不影响全仓保证金

5. **提现限制** (2 个测试)
   - 逐仓模式下提现检查维持保证金
   - 全仓模式下提现检查维持保证金

6. **事件验证** (3 个测试)
   - 保证金模式变更事件
   - 保证金分配事件
   - 保证金回收事件

7. **边界情况** (5 个测试)
   - 零金额分配/回收
   - 连续分配和回收
   - 多用户独立保证金管理

---

## 9. 最佳实践

### 9.1 何时使用全仓模式

✅ **推荐场景：**
- 对冲策略（同时持有多空仓位）
- 套利交易
- 资金效率优先
- 多仓位交易
- 低风险偏好

⚠️ **风险：**
- 一个仓位大亏损可能导致所有仓位清算
- 需要更严格的风险管理

### 9.2 何时使用逐仓模式

✅ **推荐场景：**
- 单方向重仓（纯多或纯空）
- 风险隔离需求
- 高杠杆交易
- 新手用户（限制风险）
- 特定仓位独立管理

⚠️ **风险：**
- 需要更多保证金
- 资金利用率低
- 挂单成本更高

### 9.3 保证金管理建议

**全仓模式：**
- 确保有足够的 crossMargin 覆盖所有仓位
- 定期检查总保证金余额
- 避免过度杠杆

**逐仓模式：**
- 为每个仓位分配合适的 isolatedMargin
- 定期检查每个仓位的健康度
- 平仓后及时回收未使用的保证金

---

## 10. 常见问题

### Q1: 可以在已有仓位上切换保证金模式吗？

**A:** 不可以。一旦开仓，保证金模式就不能更改。如果想切换模式，需要先平仓，然后重新开仓。

```solidity
// 错误示例
exchange.placeOrder(true, price, amount, 0, MarginMode.CROSS);
exchange.placeOrder(false, price, amount, 0, MarginMode.ISOLATED); // Revert!

// 正确做法：先平仓，再重新开仓
exchange.placeOrder(true, price, amount, 0, MarginMode.CROSS);
// ... 平仓操作 ...
exchange.placeOrder(false, price, amount, 0, MarginMode.ISOLATED); // OK
```

### Q2: 逐仓模式的保证金可以全部回收吗？

**A:** 如果有持仓，必须保留足够的维持保证金。如果没有持仓，可以全部回收。

```solidity
// 无仓位：可以全部回收
exchange.allocateToIsolated(10 ether);
exchange.removeFromIsolated(10 ether); // OK

// 有仓位：必须保留维持保证金
exchange.placeOrder(true, price, amount, 0, MarginMode.ISOLATED);
exchange.removeFromIsolated(10 ether); // 可能 revert
```

### Q3: 全仓模式和逐仓模式可以同时使用吗？

**A:** 不可以。每个用户在同一时间只能使用一种模式。但不同的用户可以使用不同的模式。

### Q4: 如何在 Solflare/Metamask 等钱包中使用？

**A:** 通过前端界面操作：
1. 连接钱包
2. 在 OrderForm 中选择保证金模式（Cross/Isolated）
3. 如果选择 Isolated，先 Allocate 保证金
4. 然后下单

### Q5: 资金费率如何计算？

**A:** 资金费率根据持仓计算，与保证金模式无关：
- **全仓模式：** 资金费从 `crossMargin` 扣除/增加
- **逐仓模式：** 资金费从 `isolatedMargin` 扣除/增加

---

## 11. 事件日志

### 11.1 保证金模式相关事件

```solidity
// 保证金模式变更事件
event MarginModeChanged(address indexed trader, MarginMode mode);

// 保证金分配事件（全仓→逐仓）
event IsolatedMarginAllocated(address indexed trader, uint256 amount);

// 保证金回收事件（逐仓→全仓）
event IsolatedMarginRemoved(address indexed trader, uint256 amount);
```

### 11.2 监听事件示例

```javascript
// 监听保证金模式变更
exchange.on('MarginModeChanged', (trader, mode) => {
    console.log(`${trader} switched to ${mode === 0 ? 'CROSS' : 'ISOLATED'}`);
});

// 监听保证金分配
exchange.on('IsolatedMarginAllocated', (trader, amount) => {
    console.log(`${trader} allocated ${amount} to isolated`);
});
```

---

## 12. Gas 消耗对比

| 操作 | 全仓模式 | 逐仓模式 | 差异 |
|------|---------|---------|------|
| **下单** | ~80k gas | ~85k gas | +5k |
| **分配保证金** | N/A | ~45k gas | - |
| **回收保证金** | N/A | ~50k gas | - |
| **清算检查** | ~12k gas | ~13k gas | +1k |

**结论：** 逐仓模式的 gas 消耗略高，但差异不大（约 5-10k gas）。

---

## 13. 总结

### 13.1 功能特性

✅ **完整实现：**
- 保证金模式切换（CROSS/ISOLATED）
- 保证金分配/回收
- 清算逻辑区分
- 视图函数支持
- 前端 UI 完整
- 测试覆盖全面

### 13.2 使用建议

**新手用户：**
- 推荐使用逐仓模式
- 限制单个仓位风险
- 更容易理解

**专业交易者：**
- 对冲策略使用全仓模式
- 单边重仓使用逐仓模式
- 根据策略灵活选择

**风险管理：**
- 设置止损
- 监控保证金余额
- 定期检查仓位健康度

---

## 14. 相关文档

- [Day 1 - 保证金系统](./day1-guide.md)
- [Day 6 - 资金费率机制](./day6-guide.md)
- [Day 7 - 清算系统](./day7-guide.md)
- [合约 API 文档](../contract/src/Exchange.sol)

---

**文档版本：** v1.0
**最后更新：** 2025-01-29
**维护者：** Monad Perp Exchange Team
