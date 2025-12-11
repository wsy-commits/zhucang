#!/usr/bin/env bash
set -e

# Load config
source frontend/.env.local

echo "--- Liquidation Live Test ---"
echo "Exchange: $VITE_EXCHANGE_ADDRESS"
echo "RPC: $VITE_RPC_URL"

# 1. Setup Carol (Trader)
CAROL_PK="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
CAROL_ADDR=$(cast wallet address --private-key $CAROL_PK)
echo "Carol: $CAROL_ADDR"

# Deposit Margin
echo "Depositing 1000 ETH for Carol..."
cast send $VITE_EXCHANGE_ADDRESS "deposit()" --value 1000ether --private-key $CAROL_PK --rpc-url $VITE_RPC_URL > /dev/null

# Place Long Order (10 ETH size @ 3100)
# Value = 31,000. Margin req (1%) = 310. Deposit = 1000 (increased)
echo "Placing Long Order..."
cast send $VITE_EXCHANGE_ADDRESS "placeOrder(bool,uint256,uint256,uint256)" true 3100000000000000000000 10000000000000000000 0 --private-key $CAROL_PK --rpc-url $VITE_RPC_URL > /dev/null

echo "Order placed. Waiting for fill..."
sleep 2

# 2. Setup Bob (Counterparty) - Ensure liquidity
BOB_PK="0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"
echo "Depositing 1000 ETH for Bob..."
cast send $VITE_EXCHANGE_ADDRESS "deposit()" --value 1000ether --private-key $BOB_PK --rpc-url $VITE_RPC_URL > /dev/null

echo "Bob placing Sell Order to fill Carol..."
cast send $VITE_EXCHANGE_ADDRESS "placeOrder(bool,uint256,uint256,uint256)" false 3100000000000000000000 10000000000000000000 0 --private-key $BOB_PK --rpc-url $VITE_RPC_URL > /dev/null

echo "Trade matched."
sleep 2

# 3. Drop Price to Trigger Liquidation
# Entry: 3100
# Size: 500
# Margin: 100
# Liq Price approx: Entry - (Margin / Size) = 3100 - (100/500)*3100? No.
# Long Liq: (Entry * Size - Margin) / (Size * (1 - MM))
# Approx: 3100 - (100/500) * 3100 is wrong.
# Simple: 500 ETH position. 100 ETH margin. 20% margin.
# Drop price by 20% -> 2480.
# Let's drop to 2000 to be sure.

echo "📉 Dropping Index Price to 2000..."
# Operator (Account #0) updates price
PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
cast send $VITE_EXCHANGE_ADDRESS "updateIndexPrice(uint256)" 2000000000000000000000 --private-key $PRIVATE_KEY --rpc-url $VITE_RPC_URL > /dev/null

echo "Price updated. Waiting for Keeper to Liquidate..."
sleep 10

# 4. Check Position
echo "Checking Carol's Position..."
POS=$(cast call $VITE_EXCHANGE_ADDRESS "getPosition(address)((int256,uint256,int256))" $CAROL_ADDR --rpc-url $VITE_RPC_URL)
echo "Position: $POS"

# Parse result (size should be 0 or reduced)
SIZE=$(echo $POS | awk '{print $1}')
if [[ "$SIZE" == "0" ]]; then
    echo "✅ Liquidation Successful! Position size is 0."
else
    echo "❌ Liquidation Failed. Position size: $SIZE"
fi
