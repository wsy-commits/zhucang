# 10 天区块链实战课程大纲：构建链上合约交易所 DApp

面向对象：大三下学期计算机相关专业，有 Solidity / 前端 / 后端基础的学生（进阶实战班）
目标成果：每个团队完成一个运行在 Monad 测试网的「链上合约永续合约交易所」DApp，包括：

- Solidity 智能合约（订单簿撮合 + 资金费率 + 清算 等）
- Node.js + TypeScript 后端辅助服务（预言机更新、监听事件、推送数据等）
- 前端页面（下单、订单簿、持仓、风险提示等）
- 以团队合作方式完成，最后进行结业展示和答辩

教学节奏：
每天 9:00–17:00，上下午各 3 小时，中午 2 小时休息。
第 1–6 天：知识点讲解 + 分模块开发
第 7–8 天：系统集成 + 测试网部署 + 优化
第 9–10 天：自由创作 + 项目展示和课程总结

**课程定位**：
本课程不再赘述基础语法，而是聚焦于**工程实战**与**系统集成**。学生将挑战在高性能链上实现全功能的订单簿交易所。

---

## 第 1 天：课程介绍与快速启动

### 上午：系统架构与 Monad 特性

*   **课程目标**：
    *   10 天内完成一个包含订单簿、撮合、资金费率、清算的完整 DEX。
*   **核心概念回顾（快速过）**：
    *   **AMM vs Orderbook**：
        *   为什么以太坊主网多用 AMM（Gas 贵、TPS 低）？
        *   为什么 Monad 适合做 Orderbook（高性能、低延迟）？
    *   **永续合约机制**：资金费率锚定现货价格的基本原理。
*   **系统架构设计**：
## 第 1 天：环境搭建与核心数据结构（The Foundation）
*   **上午**：Monad 架构讲解，介绍 `ExchangeStorage.sol` 核心存储与模块继承关系。
*   **下午**：
    *   [Solidity] 定义 `Order`、`Position`、`Account` 结构体。
    *   [Solidity] 编写 `MarginModule.sol` 的 `deposit()` 与 `withdraw()` 逻辑（使用原生 MON）。
    *   [Frontend] 连接钱包，实现"领水"与"存款"功能。
*   **产出**：DApp 跑通存取款，完成核心数据结构与保证金模块。

## 第 2 天：订单簿数据结构（The OrderBook）
*   **上午**：
    *   [Solidity] 链表（Linked List）原理与 O(1) 插入实现。
    *   [Solidity] 编写 `OrderBookModule.sol` 中 `_insertBuy`/`_insertSell` 排序插入逻辑。
*   **下午**：
    *   [Solidity] 完成 `placeOrder()` 函数与保证金检查 `_checkWorstCaseMargin()`。
    *   [Frontend] 开发 OrderForm 组件，对接挂单接口。
    *   [Debug] 使用 Foundry Console 验证链表排序。
*   **产出**：前端能挂单，链上能查到订单数据。

## 第 3 天：撮合引擎与成交（The Matching）
*   **上午**：
    *   [Solidity] 编写 `_matchBuy` 与 `_matchSell` 循环撮合逻辑。
    *   [Solidity] 实现 `_executeTrade` 与 `_updatePosition`（持仓记账）。
*   **下午**：
    *   [Solidity] 完善 `TradeExecuted` 事件，处理部分成交与完全成交。
    *   [Frontend] 开发 RecentTrades（成交列表）与 OrderBook（深度图）。
    *   [Script] 模拟成交脚本。
*   **产出**：User A 挂单被 User B 吃单，前端列表实时更新。

## 第 4 天：价格服务与标记价格（The Pricing）
*   **上午**：
    *   [Solidity] 编写 `PricingModule.sol`，实现 `updateIndexPrice()` 与 `_calculateMarkPrice()`。
    *   [Solidity] 讲解 Mark Price 三价取中逻辑（Bid/Ask/Index）与 5% 偏离保护。
*   **下午**：
    *   [Keeper] 编写 PriceKeeper，对接 Binance API 推送价格上链。
    *   [Frontend] Header 显示实时 Index Price 与 Mark Price。
*   **产出**：DEX 价格随外部市场实时跳动。

## 第 5 天：数据索引与 K 线（The Data）
*   **上午**：
    *   [Backend] 配置 Indexer（Envio）解析 TradeExecuted 事件。
    *   [Backend] 生成 Candle (OHLC) 数据结构。
*   **下午**：
    *   [Frontend] 集成图表库，对接 Indexer API 展示 K 线。
*   **产出**：专业的 K 线行情看板。

## 第 6 天：资金费率机制（The Funding）
*   **上午**：
    *   [Solidity] 在 `FundingModule.sol` 实现币安风格资金费率公式。
    *   [Solidity] 开发全局 `settleFunding()` 与用户级 `_applyFunding()` 结算逻辑。
*   **下午**：
    *   [Keeper] 定时触发全局结算。
    *   [Frontend] Positions 组件显示"未结资金费"与"强平价格"。
*   **产出**：持仓盈亏随时间自动变化。

## 第 7 天：清算系统与风控闭环（The Liquidation）
*   **上午**：
    *   [Solidity] 在 `LiquidationModule.sol` 实现 `canLiquidate()` 健康度判定。
    *   [Solidity] 完善 `liquidate()` 函数，实现部分清算与激励机制。
*   **下午**：
    *   [Keeper] 编写 Liquidator 机器人扫描风险账户。
    *   [Frontend] 增加"危险预警" Toast 与保证金率显示。
    *   [演习] **大逃杀预演**：全员模拟极端行情，验证清算效率。
*   **产出**：具备完整风控闭环的 DEX。

---

## 第 8-10 天：3 日黑客松 (Monad Perp Hackathon)

### 赛制安排

*   **Day 8：创意与启动**
    *   **上午**：公布四大赛道（安全/性能/体验/创新），各组提交技术方案（RFC）。
    *   **下午**：进入 Coding 状态，导师提供架构咨询。
*   **Day 9：极限开发**
    *   **全天**：沉浸式开发。导师提供“SLA 级”技术支持。
    *   **里程碑**：下午 17:00 前需完成核心功能联调。
*   **Day 10：决战 Demo Day**
    *   **上午**：UI 细节打磨、部署主网/测试网、录制演示视频。
    *   **下午**：正式路演（Demo Show）。每组 15 分钟展示 + 答辩。
    *   **评选**：颁发“Monad 最佳构建者”等奖项与结业证书。
