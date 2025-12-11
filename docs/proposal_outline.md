# 「10 天链上合约交易所实战营」课程提案大纲（领导版）

## 一、项目背景与目标

- 行业背景：
  - 永续合约交易是主流加密衍生品形态之一，对高性能链上基础设施需求强烈。
  - Monad 等新一代高性能公链提供了在链上实现「专业级交易所体验」的可能。
- 培养目标：
  - 面向大三计算机相关专业学生，系统培养「链上衍生品 + 全栈 DApp」综合能力。
  - 让学生在 10 天内从零到一完成一个可在 Monad 测试网运行的永续合约交易所 DApp。
- 产出目标：
  - 一套可运行的 Demo 级链上合约交易所（合约 + 后端 + 前端）。
  - 可对外展示的项目文档、架构图和项目演示材料。

## 二、课程总体设计

- 目标学员：
  - 大三下学期及以上，有 Solidity / 前端 / 后端基础的学生。
- 总体形式：
  - 10 天全日制集训营（每天 9:00–17:00）。
  - 上午理论与架构讲解，下午分组开发与代码实战。
- 技术栈（统一约定）：
  - 区块链：Monad 测试网（EVM 兼容，高 TPS、低延迟）。
  - 智能合约：Solidity + Foundry（主力）/ Hardhat（选修）。
  - 价格服务：Keeper 机器人推送（对接 Binance API，Operator 调用 `updateIndexPrice`）。
  - 后端：Node.js + TypeScript（事件监听、数据服务、价格推送脚本）。
  - 前端：React + MetaMask + wagmi + viem（固定栈，统一教学与支持）。
  - 测试：Foundry Solidity 测试（`*.t.sol`）。

## 三、预期学习成果（Learning Outcomes）

- 合约层能力：
  - 能设计并实现链上订单簿、撮合逻辑、仓位与保证金模型。
  - 能实现价格服务模块，理解 Mark Price 计算逻辑，并基于此实现资金费率和清算逻辑。
  - 掌握 Foundry 测试驱动开发（TDD）的基本方法。
- 全栈 DApp 能力：
  - 能使用 React + wagmi + viem 与链上合约交互，实现下单、持仓展示、风险提示等功能。
  - 能编写 Node.js/TS 脚本与服务，用于监听链上事件、推送价格和向前端推送数据。
- 工程与协作能力：
  - 掌握 Git 协作流程、基础代码规范、需求拆解与任务分工方法。
  - 具备完成端到端区块链项目 Demo 并对外展示的能力。

## 四、10 天内容结构（高层视图）

- **Day 1：环境搭建与核心数据结构（The Foundation）**
  - **9:00-12:00 [架构与环境]**：
    - 讲解 Monad 架构与课程全景图。
    - 跑通 `scripts/quickstart.sh`，确保本地 Anvil/Frontend/Indexer 全链路连通。
    - 介绍项目合约结构：`ExchangeStorage.sol` 核心存储与模块继承关系。
  - **14:00-17:00 [编码热身与核心定义]**：
    - **[Solidity 核心]**：在 `ExchangeStorage.sol` 中定义 `Order`、`Position`、`Account` 结构体。
    - [Solidity]：编写 `MarginModule.sol` 的 `deposit()` 与 `withdraw()` 保证金逻辑（使用原生 MON）。
    - [Frontend]：实现连接钱包，完成"领水"（从 Anvil 获取 MON）与"存款"交互。
  - **产出**：DApp 跑通存取款，代码库中有了核心 `struct` 定义与保证金模块。

- **Day 2：订单簿数据结构（The OrderBook）**
  - **9:00-12:00 [链表算法攻坚]**：
    - 讲解链表（Linked List）在合约中的 O(1) 插入与删除原理。
    - [Solidity]：实现 `OrderBookModule.sol` 中 `_insertBuy`/`_insertSell` 的**排序插入逻辑**（这是最难的算法部分）。
  - **14:00-17:00 [挂单交互]**：
    - [Solidity]：完成 `placeOrder()` 函数与保证金检查 `_checkWorstCaseMargin()`。
    - [Frontend]：开发 `OrderForm.tsx`，对接 `placeOrder` 接口。
    - [Debug]：使用 Foundry Console 打印链表状态，验证排序正确性。
  - **产出**：前端下单后，能在 Foundry 终端看到链表 Log，订单正确入账。

- **Day 3：撮合引擎与成交（The Matching）**
  - **9:00-12:00 [撮合算法]**：
    - [Solidity]：编写 `_matchBuy` 与 `_matchSell`，循环遍历链表撮合买卖单。
    - [Solidity]：实现 `_executeTrade` 与 `_updatePosition`（持仓记账）。
  - **14:00-17:00 [成交反馈]**：
    - [Solidity]：完善 `TradeExecuted` 事件，处理部分成交与完全成交。
    - [Frontend]：开发 `OrderBook.tsx`（深度图）与 `RecentTrades.tsx`（成交列表）。
    - [Script]：编写简单脚本模拟 User B 吃单。
  - **产出**：User A 挂单，User B 吃单，订单消失，成交列表刷新。

- **Day 4：价格服务与标记价格（The Pricing）**
  - **9:00-12:00 [合约定价逻辑]**：
    - [Solidity]：编写 `PricingModule.sol`，实现 `updateIndexPrice()` 与 `_calculateMarkPrice()`。
    - [Solidity]：讲解 Mark Price 三价取中逻辑（Bid/Ask/Index 的中位数）与 5% 偏离保护。
  - **14:00-17:00 [价格推送机器人]**：
    - [Keeper]：编写 `PriceKeeper.ts`，对接 Binance API，调用 `updateIndexPrice()` 推送价格上链。
    - [Frontend]：顶部 Header 实时显示当前 Index Price 与 Mark Price。
  - **产出**：前端价格数字随币安实时跳动，合约价格保护机制生效。

- **Day 5：数据索引与 K 线（The Data）**
  - **9:00-12:00 [索引器配置]**：
    - [Backend]：配置 `indexer`（Envio），解析 `TradeExecuted` 事件。
    - [Backend]：生成数据 Schema (`Candle`, `Trade`)。
  - **14:00-17:00 [图表集成]**：
    - [Frontend]：集成图表库，对接 Indexer 的 GraphQL 接口。
    - [Frontend]：调试 1 分钟 K 线更新延迟。
  - **产出**：完整的专业级 K 线行情页。

- **Day 6：资金费率机制（The Funding）**
  - **9:00-12:00 [费率逻辑]**：
    - [Solidity]：在 `FundingModule.sol` 实现币安风格资金费率公式 `F = P + clamp(I - P, 0.05%, -0.05%)`。
    - [Solidity]：开发全局 `settleFunding()` 与用户级 `_applyFunding()` 结算逻辑。
  - **14:00-17:00 [持仓展示]**：
    - [Keeper]：编写 `FundingBot` 定时触发全局结算。
    - [Frontend]：完善 `Positions.tsx`，实时计算并展示"未结资金费"与"强平价格"。
  - **产出**：持仓盈亏随时间（资金费机制）自动变化。

- **Day 7：清算系统与风控闭环（The Liquidation）**
  - **9:00-12:00 [强平逻辑]**：
    - [Solidity]：在 `LiquidationModule.sol` 实现 `canLiquidate()` 健康度判定（Maintenance + Fee）。
    - [Solidity]：完善 `liquidate()` 函数，实现部分清算与激励机制。
  - **14:00-17:00 [清算机器人与演习]**：
    - [Keeper]：编写 `Liquidator.ts` 高频扫描风险账户。
    - [Frontend]：增加"危险预警" Toast 提示与保证金率显示。
    - [演习]：全班分组对抗，导师砸盘，验证机器人的清算速度。
  - **产出**：具备完整风控能力的 Perpetual DEX 闭环。

- **Day 8：3 日黑客松（Day 1）—— 创意与启动**
  - **9:00-12:00**: 命题发布与组队，提交技术架构 RFC。
  - **14:00-17:00**: 核心功能编码启动。

- **Day 9：3 日黑客松（Day 2）—— 攻坚与突破**
  - **全天**: 沉浸式开发 Sprint。
  - **里程碑**: 下午 17:00 前完成核心功能联调。

- **Day 10：3 日黑客松（Day 3）—— 决战与演示**
  - **9:00-12:00**: UI 细节打磨、部署主网/测试网、录制演示视频。
  - **14:00-17:00**: Demo Day 路演（每组 15 分钟 + 5 分钟答辩）。

## 五、项目交付物与评估方式

- 团队级交付物：
  - 完整代码仓库（合约 + 前端 + 后端），可在 Monad 测试网直接运行。
  - 技术文档（架构图、模块说明、部署说明、风险与限制）。
  - Demo 演示脚本与 PPT。
- 评估维度：
  - 功能完整度：核心闭环是否打通（下单–撮合–资金费率–清算）。
  - 技术实现质量：合约设计合理性、测试覆盖、前后端工程质量。
  - 创新/扩展：是否有额外功能或性能/体验优化。
  - 展示效果：演示连贯性、讲解清晰度、团队协作表现。

## 六、实施资源与支持需求

- 师资与助教配置：
  - 1 名主讲老师（合约 & 架构方向）。
  - 1 名前端方向助教（React + wagmi + viem）。
  - 1 名后端/脚本方向助教（Node.js/TS + Foundry 脚本）。
- 硬件与环境：
  - 教室或实验室（支持投屏、网络稳定、电源充足）。
  - 学生自带笔记本电脑（建议 16GB 内存及以上）。
- 链上资源：
  - Monad 测试网 RPC 及区块浏览器。
  - 测试网 MON 代币（Faucet 或统一发放，作为系统保证金）。
  - 价格推送 Keeper 服务（对接 Binance API 或其他数据源）。

## 七、风险与应对策略（高层）

- 学习曲线风险：
  - 部分学生 Solidity / React 基础不足，可能跟不上节奏。
  - 对策：Day 1 下午提供核心代码骨架（Skeleton），减少样板代码编写时间，确保学生聚焦核心逻辑。课程每天设立“必达里程碑”，完不成当天任务的队伍将由助教进行“一对一抢救”。
- 工期风险：
  - 10 天内实现完整 perp 交易所有挑战。
  - 对策：课程设定「必做功能」与「选做扩展」，保证每组至少完成一个稳定的最小可运行版本（MVP）。
- 链上环境风险：
  - 测试网波动、价格服务中断等可能影响演示。
  - 对策：提供本地 Anvil + 固定价格 Mock 方案与录制备份 Demo，确保展示不受单一外部依赖影响。

## 八、预期价值与后续延展

- 对学生：
  - 获得从零设计并实现一个完整 Web3 项目的实战经验。
  - 作品可作为求职/比赛的展示项目。
- 对学校/组织：
  - 形成一套可复用的高阶区块链实践课程模板。
  - 可在后续开设进阶专题（如多链部署、专业风控、性能优化、审计实践等）。
- 对生态（Monad / 相关项目）：
  - 培养一批熟悉 Monad 生态与工具链的开发者。
  - 产生可持续迭代的开源示例项目与教学资料。

