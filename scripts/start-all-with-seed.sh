#!/usr/bin/env bash
set -euo pipefail

echo "=================================================="
echo "   Monad Exchange: Clean Start & Seed Data"
echo "=================================================="

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 1. Cleanup
echo "[1/5] Cleaning up existing processes and data..."
pkill -f anvil || true
pkill -f "envio" || true
pkill -f "vite" || true
# Force kill any process on port 9898 (Indexer)
lsof -ti:9898 | xargs kill -9 2>/dev/null || true
docker compose -f indexer/generated/docker-compose.yaml down -v

# 2. Start Anvil & Deploy
echo "[2/5] Starting Anvil and Deploying Contracts..."
"${ROOT_DIR}/scripts/run-anvil-deploy.sh" > /dev/null 2>&1 &
ANVIL_PID=$!

# Wait for deployment to finish (check for .env.local update)
echo "Waiting for deployment..."
sleep 10 

# 3. Start Indexer
echo "[3/5] Starting Indexer..."
# Start Docker services first
docker compose -f indexer/generated/docker-compose.yaml up -d

# Regenerate indexer code since the address in config.yaml changed
echo "Regenerating indexer code..."
cd indexer && npx envio codegen && cd ..

# Wait for Hasura to be ready
echo "Waiting for Hasura to be ready..."
for i in {1..30}; do
  if curl -s http://localhost:8080/v1/version > /dev/null; then
    echo "Hasura is ready."
    break
  fi
  sleep 1
done

# Start Envio indexer in background
cd indexer && TUI_OFF=true pnpm start > indexer.log 2>&1 &
INDEXER_PID=$!
cd ..

echo "Waiting for Indexer to initialize..."
sleep 5

# 4. Seed Data
echo "[4/5] Seeding Data (Deposits, Trades, Candles)..."
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 # Alice (Deployer)

# Load dynamic exchange address from .env.local
if [[ -f "${ROOT_DIR}/frontend/.env.local" ]]; then
    # Parse the address from the file
    EX_ADDR=$(grep VITE_EXCHANGE_ADDRESS "${ROOT_DIR}/frontend/.env.local" | cut -d'=' -f2)
    export VITE_EXCHANGE_ADDRESS=$EX_ADDR
    echo "Using dynamic exchange address: $VITE_EXCHANGE_ADDRESS"
fi

# Ensure we are in root before cd contract
cd "$ROOT_DIR"
cd contract
forge script script/SeedData.s.sol:SeedDataScript --broadcast --rpc-url http://127.0.0.1:8545
cd ..

# 5. Start Frontend
echo "[5/5] Starting Frontend..."
"${ROOT_DIR}/scripts/start-frontend.sh"
