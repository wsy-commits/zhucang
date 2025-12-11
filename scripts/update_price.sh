#!/usr/bin/env bash
set -e

# Load env
source frontend/.env.local

RPC_URL="http://localhost:8545"
ALICE_PK="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

# Default to 1550 if no argument provided
NEW_PRICE=${1:-1550}

echo "Updating Index Price to $NEW_PRICE..."

# Convert to Wei (assuming input is ether)
# Use cast to convert
PRICE_WEI=$(cast to-wei $NEW_PRICE ether)

cast send --rpc-url $RPC_URL --private-key $ALICE_PK $VITE_EXCHANGE_ADDRESS "updateIndexPrice(uint256)" $PRICE_WEI --legacy

echo "Done. New Index Price: $NEW_PRICE"
