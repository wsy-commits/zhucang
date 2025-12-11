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

echo "Creating Position for Alice..."

# Check if Alice has enough margin
echo "Checking Alice's Margin..."
MARGIN=$(cast call --rpc-url $RPC_URL $EXCHANGE "margin(address)(uint256)" $(cast wallet address --private-key $ALICE))
echo "Alice Margin: $MARGIN"

# If margin is low (e.g. < 100 ETH), deposit more
if [ "$MARGIN" == "0" ] || [ "$MARGIN" -lt "100000000000000000000" ]; then
    echo "Depositing 1000 ETH for Alice..."
    cast send --rpc-url $RPC_URL --private-key $ALICE $EXCHANGE "deposit()" --value 1000ether > /dev/null
fi

# Alice places a Buy Order that matches existing Sell Orders
# Existing Sells: 1550, 1580, 1600
# Alice Buys 1 ETH @ 1600 (Market/Limit)
echo "Alice buying 1 ETH @ 1600..."
cast send --rpc-url $RPC_URL --private-key $ALICE $EXCHANGE "placeOrder(bool,uint256,uint256,uint256)" true 1600ether 1ether 0 > /dev/null

echo "Position Created."
