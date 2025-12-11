# Monad Perp Exchange（教学版）

> ⚠️ 本仓库仅供教学与练习，不可用于生产。

一个用于教学/演示的极简永续合约模板，拆分为模块：保证金、订单簿、撮合、资金费率、清算、价格（Pyth）。

## 部署后操作提示
- **部署即绑定 Pyth 源**：构造函数需要传入 Pyth 合约地址和 priceId，并会立刻从 Pyth 读取价格设置标记价/指数价。
- **定期喂价**：资金费率/清算会在需要时自动拉取 Pyth 价格；如果希望更多同步，可由 `OPERATOR_ROLE` 周期性调用 `updateMarkPriceFromPyth`。
- **授予权限**：部署者默认是 `DEFAULT_ADMIN_ROLE` 和 `OPERATOR_ROLE`。如需其他账号更新价格，请先 `grantRole(OPERATOR_ROLE, account)`。
- **资金费率**：使用简化公式 `(mark-index)/index/24` 并可配置上限，未做价格保护或时间加权，仅用于演示资金费概念。
- **清算/订单假设**：教学版假设锁定保证金与订单金额保持同步，清算时直接删除挂单并释放锁仓；生产环境需逐步核对。

## 快速喂价脚本
使用 Foundry script 示例从 Pyth 拉取并更新标记价（调用方需要 `OPERATOR_ROLE`）：
```bash
EXCHANGE_ADDR=0xYourExchange forge script script/SetInitialPrice.s.sol:SetInitialPriceScript --broadcast --rpc-url <RPC>
```

## 运行测试
```bash
PYTH_RPC_URL=https://rpc1.monad.xyz forge test
```

其中 fork 测试依赖可用 RPC；无网络时可跳过 fork 测试。其余测试涵盖保证金、订单簿、撮合、资金费率、清算等基础流程。

## 本地联调（anvil fork + 前端）
1. 启动本地 fork（示例使用 Monad 公共 RPC，可替换）：  
   `anvil --fork-url https://rpc1.monad.xyz --chain-id 31337 --port 8545`
2. 部署合约（使用默认 anvil 私钥，或自行覆盖 `PRIVATE_KEY`）：  
   `cd contract && PRIVATE_KEY=0xac0974becf0b5d11acc2c655c4f2c7bfe713f0226f8896f5b1f3c0ba6dfe3e8a forge script script/DeployExchange.s.sol:DeployExchangeScript --broadcast --rpc-url http://127.0.0.1:8545`  
   - 若 fork 节点没有 Pyth，可加 `USE_MOCK_PYTH=true MOCK_PRICE=2000 MOCK_EXPO=0` 走内置 MockPyth。
3. 记录脚本输出的 `Exchange` 地址与部署块高（用于前端扫描事件）。
4. 配置前端环境变量（`frontend/.env.local`）：  
   ```
   VITE_RPC_URL=http://127.0.0.1:8545
   VITE_CHAIN_ID=31337
   VITE_EXCHANGE_ADDRESS=<上一步的部署地址>
   VITE_EXCHANGE_DEPLOY_BLOCK=<部署块号，选填优化日志查询>
   VITE_TEST_PRIVATE_KEY=<可选，本地测试用私钥，无注入钱包时启用前端签名>
   ```
5. 前端运行：`cd frontend && npm install && npm run dev`，用浏览器连接 anvil 钱包账户（或导入脚本使用的私钥）即可在界面上充值、下单、查看挂单/成交。
