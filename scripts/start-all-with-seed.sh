#!/usr/bin/env bash
set -euo pipefail

echo "=================================================="
echo "   Monad Exchange: Clean Start & Seed Data"
echo "=================================================="

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" pwd)"ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" pwd)"

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
./run-anvil-deploy.sh > /dev/null 2>&1 &
ANVIL_PID=$!

# Wait for deployment to finish (check for .env.local update)
echo "Waiting for deployment..."
sleep 10 
# A better check would be looping until .env.local is updated, but sleep is simple for now.

# 3. Start Indexer
echo "[3/5] Starting Indexer..."
# Start Docker services first
docker compose -f indexer/generated/docker-compose.yaml up -d
# Start Envio indexer in background
cd indexer && TUI_OFF=true pnpm start > indexer.log 2>&1 &
INDEXER_PID=$!
cd ..

echo "Waiting for Indexer to initialize..."
sleep 15

# 4. Seed Data
echo "[4/5] Seeding Data (Deposits, Trades, Candles)..."
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 # Alice (Deployer)
# Ensure we are in root before cd contract
cd "$ROOT_DIR" || cd . 
cd contract
forge script script/SeedData.s.sol:SeedDataScript --broadcast --rpc-url http://127.0.0.1:8545
cd ..

# 5. Start Frontend
echo "[5/5] Starting Frontend..."
./start-frontend.sh
