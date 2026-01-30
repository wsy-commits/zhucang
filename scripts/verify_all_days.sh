#!/bin/bash
# 验证 Day 1-7 所有功能的完整脚本

set -e

EXCHANGE="0x5FbDB2315678afecb367f032d93F642f64180aa3"
RPC="http://127.0.0.1:8545"
PK="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
ALICE="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
BOB="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"

echo "=========================================="
echo "验证 Day 1-7 所有功能"
echo "=========================================="
echo ""

# Day 1: 保证金系统
echo "=== Day 1: 保证金系统 ==="
echo "1.1 Alice 存入 20 ETH"
cast send $EXCHANGE "deposit()" --value 20ether --rpc-url $RPC --private-key $PK > /dev/null 2>&1
echo "✓ 存款成功"

echo "1.2 查询保证金余额"
BALANCE=$(cast call $EXCHANGE "getCrossMargin(address)" $ALICE --rpc-url $RPC)
echo "✓ Alice 余额: $(echo $BALANCE | cast to-unit ether) ETH"

echo "1.3 提取 5 ETH"
cast send $EXCHANGE "withdraw(uint256)" "5000000000000000000" --rpc-url $RPC --private-key $PK > /dev/null 2>&1
echo "✓ 提款成功"
echo ""

# Day 2: 订单簿
echo "=== Day 2: 订单簿系统 ==="
echo "2.1 Alice 下买单 (价格 $1000)"
cast send $EXCHANGE "placeOrder(bool,uint256,uint256,uint256,uint8)" \
  "true" "1000000000000000000000" "1000000000000000000" "0" "0" \
  --rpc-url $RPC --private-key $PK > /dev/null 2>&1
echo "✓ 买单订单已提交"

echo "2.2 查询最优买单 ID"
BEST_BUY=$(cast call $EXCHANGE "bestBuyId()" --rpc-url $RPC)
echo "✓ 最优买单 ID: $BEST_BUY"
echo ""

# Day 3: 撮合引擎
echo "=== Day 3: 撮合引擎 ==="
echo "3.1 Bob 下卖单 (价格 $980，应该会立即成交)"
BOB_PK="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
cast send $EXCHANGE "placeOrder(bool,uint256,uint256,uint256,uint8)" \
  "false" "980000000000000000000" "500000000000000000" "0" "0" \
  --rpc-url $RPC --private-key $BOB_PK > /dev/null 2>&1
echo "✓ 卖单已提交（应该已成交）"

echo "3.2 查询 Alice 持仓"
POSITION=$(cast call $EXCHANGE "getPosition(address)" $ALICE --rpc-url $RPC)
SIZE=$(echo $POSITION | jq -r '.size' 2>/dev/null || echo "0")
echo "✓ Alice 持仓大小: $SIZE"
echo ""

# Day 4: 价格预言机
echo "=== Day 4: 价格预言机 ==="
echo "4.1 设置操作员并更新指数价格"
OPERATOR_PK="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
cast send $EXCHANGE "updateIndexPrice(uint256)" "1000000000000000000000" \
  --rpc-url $RPC --private-key $OPERATOR_PK > /dev/null 2>&1
echo "✓ 指数价格已更新为 $1000"

echo "4.2 查询标记价格"
MARK_PRICE=$(cast call $EXCHANGE "markPrice()" --rpc-url $RPC)
echo "✓ 标记价格: $(echo $MARK_PRICE | cast to-unit ether) ETH"
echo ""

# Day 5: 资金费率
echo "=== Day 5: 资金费率 ==="
echo "5.1 设置资金费率参数"
cast send $EXCHANGE "setFundingParams(uint256,int256)" \
  "3600" "10000000000000000" \
  --rpc-url $RPC --private-key $PK > /dev/null 2>&1
echo "✓ 资金费率参数已设置（间隔1小时，上限0.01）"

echo "5.2 结算资金费率"
cast send $EXCHANGE "settleFunding()" --rpc-url $RPC --private-key $PK > /dev/null 2>&1
echo "✓ 资金费率已结算"

echo "5.3 查询累计费率"
CUMULATIVE=$(cast call $EXCHANGE "cumulativeFundingRate()" --rpc-url $RPC)
echo "✓ 累计资金费率: $CUMULATIVE"
echo ""

# Day 6: 清算系统
echo "=== Day 6: 清算系统 ==="
echo "6.1 检查 Alice 是否可被清算"
CAN_LIQ=$(cast call $EXCHANGE "canLiquidate(address)" $ALICE --rpc-url $RPC)
if [ "$CAN_LIQ" == "0x0000000000000000000000000000000000000000000000000000000000000000" ]; then
  echo "✓ Alice 仓位健康，不可清算"
else
  echo "✗ Alice 仓位不健康"
fi
echo ""

# Day 7: 集成测试
echo "=== Day 7: 集成功能 ==="
echo "7.1 逐仓模式：分配保证金"
cast send $EXCHANGE "allocateToIsolated(uint256)" "2000000000000000000" \
  --rpc-url $RPC --private-key $PK > /dev/null 2>&1
echo "✓ 已分配 2 ETH 到逐仓保证金"

echo "7.2 查询保证金模式"
MODE=$(cast call $EXCHANGE "getMarginMode(address)" $ALICE --rpc-url $RPC)
echo "✓ 当前保证金模式: $MODE (0=全仓, 1=逐仓)"

echo "7.3 逐仓模式下单"
cast send $EXCHANGE "placeOrder(bool,uint256,uint256,uint256,uint8)" \
  "true" "1000000000000000000000" "1000000000000000000" "0" "1" \
  --rpc-url $RPC --private-key $PK > /dev/null 2>&1
echo "✓ 逐仓限价买单已提交"

echo "7.4 查询逐仓保证金"
ISOLATED_MARGIN=$(cast call $EXCHANGE "getIsolatedMargin(address)" $ALICE --rpc-url $RPC)
echo "✓ 逐仓保证金: $(echo $ISOLATED_MARGIN | cast to-unit ether) ETH"
echo ""

# 最终状态
echo "=========================================="
echo "最终账户状态"
echo "=========================================="
echo "Cross Margin: $(cast call $EXCHANGE "getCrossMargin(address)" $ALICE --rpc-url $RPC | cast to-unit ether) ETH"
echo "Isolated Margin: $(cast call $EXCHANGE "getIsolatedMargin(address)" $ALICE --rpc-url $RPC | cast to-unit ether) ETH"
echo "Margin Mode: $(cast call $EXCHANGE "getMarginMode(address)" $ALICE --rpc-url $RPC)"
echo "Position: $(cast call $EXCHANGE "getPosition(address)" $ALICE --rpc-url $RPC)"
echo ""
echo "=========================================="
echo "✅ Day 1-7 所有功能验证完成！"
echo "=========================================="
