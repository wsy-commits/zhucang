#!/usr/bin/env bash
set -e

# Load environment variables from frontend/.env
# Load environment variables from frontend/.env.local (priority) or .env
ENV_LOCAL="$(dirname "${BASH_SOURCE[0]}")/../frontend/.env.local"
ENV_DEFAULT="$(dirname "${BASH_SOURCE[0]}")/../frontend/.env"

if [ -f "$ENV_LOCAL" ]; then
    export $(grep -v '^#' "$ENV_LOCAL" | xargs)
    echo "Loaded config from frontend/.env.local"
elif [ -f "$ENV_DEFAULT" ]; then
    export $(grep -v '^#' "$ENV_DEFAULT" | xargs)
    echo "Loaded config from frontend/.env"
else
    echo "Error: frontend/.env.local or .env not found"
    exit 1
fi

export EXCHANGE_ADDRESS=$VITE_EXCHANGE_ADDRESS
export RPC_URL=$VITE_RPC_URL
echo "Exchange: $EXCHANGE_ADDRESS"
echo "RPC: $RPC_URL"

# Start the keeper
echo "Starting Keeper Service..."
cd "$(dirname "${BASH_SOURCE[0]}")"
npm install
npx ts-node src/index.ts
