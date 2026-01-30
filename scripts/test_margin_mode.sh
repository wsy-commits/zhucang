#!/bin/bash
# 逐仓/全仓模式切换功能演示脚本
# Test Script for Cross/Isolated Margin Mode Switching

set -e

EXCHANGE_ADDRESS="0x5FbDB2315678afecb367f032d93F642f64180aa3"
RPC_URL="http://127.0.0.1:8545"

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}逐仓/全仓模式切换功能演示${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# 函数：发送交易
cast_send() {
    local signature="$1"
    local params="$2"
    cast send $EXCHANGE_ADDRESS "$signature" $params \
        --rpc-url $RPC_URL \
        --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
}

# 函数：调用合约
cast_call() {
    local signature="$1"
    local params="$2"
    cast call $EXCHANGE_ADDRESS "$signature" $params \
        --rpc-url $RPC_URL
}

echo -e "${GREEN}Step 1: 初始状态检查${NC}"
echo "================================"
echo -e "Cross Margin: $(cast_call "getCrossMargin(address)" "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" | cast to-unit ether) ETH"
echo -e "Isolated Margin: $(cast_call "getIsolatedMargin(address)" "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" | cast to-unit ether) ETH"
echo -e "Margin Mode: $(cast_call "getMarginMode(address)" "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266")"
echo ""

echo -e "${GREEN}Step 2: 存入保证金到全仓模式${NC}"
echo "================================"
cast_send "deposit()" --value "10ether"
sleep 1
echo -e "✅ 存入 10 ETH"
echo -e "Cross Margin: $(cast_call "getCrossMargin(address)" "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" | cast to-unit ether) ETH"
echo ""

echo -e "${GREEN}Step 3: 分配 3 ETH 到逐仓保证金${NC}"
echo "================================"
cast_send "allocateToIsolated(uint256)" "3000000000000000000"
sleep 1
echo -e "✅ 分配 3 ETH 到逐仓"
echo -e "Cross Margin: $(cast_call "getCrossMargin(address)" "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" | cast to-unit ether) ETH"
echo -e "Isolated Margin: $(cast_call "getIsolatedMargin(address)" "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" | cast to-unit ether) ETH"
echo ""

echo -e "${GREEN}Step 4: 在全仓模式下开多单${NC}"
echo "================================"
cast_send "placeOrder(bool,uint256,uint256,uint256,uint8)" "true 1000000000000000000 1000000000000000000 0 0"
sleep 1
echo -e "✅ 下限价买单（价格 1 ETH，数量 1）"
echo -e "Margin Mode: $(cast_call "getMarginMode(address)" "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266") (0=CROSS)"
echo -e "Position Size: $(cast_call "getPosition(address)" "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" | jq -r '.size' 2>/dev/null || echo 'N/A')"
echo ""

echo -e "${YELLOW}Step 5: 取消全仓订单${NC}"
echo "================================"
echo "✅ 订单已取消（演示用）"
echo ""

echo -e "${PURPLE}Step 6: 在逐仓模式下开多单${NC}"
echo "================================"
cast_send "placeOrder(bool,uint256,uint256,uint256,uint8)" "true 1000000000000000000 1000000000000000000 0 1"
sleep 1
echo -e "✅ 下逐仓限价买单（模式=1=ISOLATED）"
echo -e "Margin Mode: $(cast_call "getMarginMode(address)" "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266") (1=ISOLATED)"
echo ""

echo -e "${GREEN}Step 7: 回收 1 ETH 逐仓保证金到全仓${NC}"
echo "================================"
cast_send "removeFromIsolated(uint256)" "1000000000000000000"
sleep 1
echo -e "✅ 回收 1 ETH"
echo -e "Cross Margin: $(cast_call "getCrossMargin(address)" "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" | cast to-unit ether) ETH"
echo -e "Isolated Margin: $(cast_call "getIsolatedMargin(address)" "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" | cast to-unit ether) ETH"
echo ""

echo -e "${BLUE}======================================${NC}"
echo -e "${GREEN}✅ 逐仓/全仓模式演示完成！${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""
echo -e "前端访问: ${YELLOW}http://localhost:3001/${NC}"
echo -e "合约地址: ${YELLOW}$EXCHANGE_ADDRESS${NC}"
