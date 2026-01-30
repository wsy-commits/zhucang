    完整演示流程（用 Bob 账户）

  演示 1：查看当前 CROSS 模式

  echo "=== 步骤 1: 查看 Bob 当前状态 (CROSS 模式) ==="
  cast call 0x52a4573bce8b38532f4bec84ea8aa1843ca3e0f0 \
    "getPosition(address)(int256,uint256,uint8,uint256)" \
    0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
    --rpc-url http://127.0.0.1:8545

  在前端应该看到：
  - Size: 0.1 ETH
  - Side: SHORT
  - Mode: CROSS (蓝色)

  演示 2：平仓

  echo "=== 步骤 2: Bob 平仓 (下买单) ==="
  cast send 0x52a4573bce8b38532f4bec84ea8aa1843ca3e0f0 \
    "placeOrder(bool,uint256,uint256,uint256,uint8)" \
    true 1200000000000000000000 100000000000000000 0 0 \
    --private-key 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d \
    --from 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
    --rpc-url http://127.0.0.1:8545

  需要 Alice 接单：
  cast send 0x52a4573bce8b38532f4bec84ea8aa1843ca3e0f0 \
    "placeOrder(bool,uint256,uint256,uint256,uint8)" \
    false 900000000000000000000 100000000000000000 0 1 \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    --from 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
    --rpc-url http://127.0.0.1:8545

  验证平仓：
  echo "=== 验证持仓是否为 0 ==="
  cast call 0x52a4573bce8b38532f4bec84ea8aa1843ca3e0f0 \
    "getPosition(address)(int256,uint256,uint8,uint256)" \
    0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
    --rpc-url http://127.0.0.1:8545

  演示 3：切换到 ISOLATED 模式

  echo "=== 步骤 3: Bob 下 ISOLATED 模式的买单 ==="
  cast send 0x52a4573bce8b38532f4bec84ea8aa1843ca3e0f0 \
    "placeOrder(bool,uint256,uint256,uint256,uint8)" \
    true 1100000000000000000000 100000000000000000 0 1 \
    --private-key 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d \
    --from 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
    --rpc-url http://127.0.0.1:8545

  需要 Alice 接单：
  cast send 0x52a4573bce8b38532f4bec84ea8aa1843ca3e0f0 \
    "placeOrder(bool,uint256,uint256,uint256,uint8)" \
    false 900000000000000000000 100000000000000000 0 1 \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    --from 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
    --rpc-url http://127.0.0.1:8545

  演示 4：分配逐仓保证金

  echo "=== 步骤 4: Bob 分配 10 MON 到逐仓 ==="
  cast send 0x52a4573bce8b38532f4bec84ea8aa1843ca3e0f0 \
    "allocateToIsolated(uint256)" 10000000000000000000 \
    --private-key 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d \
    --from 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
    --rpc-url http://127.0.0.1:8545

  演示 5：验证切换成功

  echo "=== 步骤 5: 验证模式切换 ==="
  echo ""
  echo "Margin Mode (期望 1=ISOLATED):"
  cast call 0x52a4573bce8b38532f4bec84ea8aa1843ca3e0f0 \
    "getMarginMode(address)" 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
    --rpc-url http://127.0.0.1:8545
  echo ""
  echo "Isolated Margin (期望 10 MON):"
  cast call 0x52a4573bce8b38532f4bec84ea8aa1843ca3e0f0 \
    "getIsolatedMargin(address)" 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
    --rpc-url http://127.0.0.1:8545
  echo ""
  echo "Cross Margin (应该减少 10 MON):"
  cast call 0x52a4573bce8b38532f4bec84ea8aa1843ca3e0f0 \
    "getCrossMargin(address)" 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
    --rpc-url http://127.0.0.1:8545
