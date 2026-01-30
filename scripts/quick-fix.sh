#!/bin/bash
# 快速修复脚本：初始化价格并充值

set -e

echo "=== 初始化价格和充值 ==="

# 设置变量
RPC="http://127.0.0.1:8545"
EXCHANGE="0x52a4573bce8b38532f4bec84ea8aa1843ca3e0f0"
# Account 0 private key (Anvil 默认账户)
PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

echo "1. 设置 Index Price 为 1000 USD..."
cast send "$EXCHANGE" "updateIndexPrice(uint256)" 1000000000000000000000 \
  --rpc-url "$RPC" --private-key "$PRIVATE_KEY"

echo ""
echo "2. 为 Alice (0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266) 充值 100 ETH..."
cast send "$EXCHANGE" "deposit()" \
  --value 100ether \
  --rpc-url "$RPC" \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --from 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

echo ""
echo "3. 验证价格..."
cast call "$EXCHANGE" "indexPrice()" --rpc-url "$RPC"

echo ""
echo "4. 验证余额..."
cast call "$EXCHANGE" "getCrossMargin(address)" 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --rpc-url "$RPC"

echo ""
echo "✅ 初始化完成！"
echo ""
echo "现在可以刷新前端页面，应该能看到："
echo "- Mark Price: 1000 USD"
echo "- Index Price: 1000 USD"
echo "- Available: 100 ETH"
