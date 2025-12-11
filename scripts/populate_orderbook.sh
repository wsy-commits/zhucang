#!/usr/bin/env bash
set -e

# Load environment variables from frontend/.env.local
ENV_FILE="$(dirname "$0")/../frontend/.env.local"
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
    EXCHANGE="$VITE_EXCHANGE_ADDRESS"
else
    echo "Error: frontend/.env.local not found."
    exit 1
fi

RPC_URL="http://127.0.0.1:8545"
ALICE="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
BOB="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
CAROL="0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"

echo "Populating Orderbook..."

# Alice places Buy Orders
echo "Alice placing Buy Orders..."
cast send --rpc-url $RPC_URL --private-key $ALICE $EXCHANGE "placeOrder(bool,uint256,uint256,uint256)" true 1400ether 5ether 0 > /dev/null
cast send --rpc-url $RPC_URL --private-key $ALICE $EXCHANGE "placeOrder(bool,uint256,uint256,uint256)" true 1420ether 3ether 0 > /dev/null
cast send --rpc-url $RPC_URL --private-key $ALICE $EXCHANGE "placeOrder(bool,uint256,uint256,uint256)" true 1450ether 2ether 0 > /dev/null

# Bob places Sell Orders
echo "Bob placing Sell Orders..."
cast send --rpc-url $RPC_URL --private-key $BOB $EXCHANGE "placeOrder(bool,uint256,uint256,uint256)" false 1550ether 5ether 0 > /dev/null
cast send --rpc-url $RPC_URL --private-key $BOB $EXCHANGE "placeOrder(bool,uint256,uint256,uint256)" false 1580ether 4ether 0 > /dev/null
cast send --rpc-url $RPC_URL --private-key $BOB $EXCHANGE "placeOrder(bool,uint256,uint256,uint256)" false 1600ether 6ether 0 > /dev/null

echo "Orderbook Populated."
