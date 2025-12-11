// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Shared state, structs, events, and roles for the Monad perpetual exchange.
abstract contract ExchangeStorage is AccessControl, ReentrancyGuard {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    string public constant COLLATERAL_SYMBOL = "MON";
    uint8 public constant COLLATERAL_DECIMALS = 18;

    struct Order {
        uint256 id;
        address trader;
        bool isBuy;
        uint256 price;
        uint256 amount;
        uint256 initialAmount;
        uint256 timestamp;
        uint256 next;
    }

    struct Position {
        int256 size; // positive = long, negative = short
        uint256 entryPrice;
        int256 realizedPnl;
    }

    struct Account {
        uint256 freeMargin; // 可用保证金（MON）
        // lockedMargin removed - using position-based margin instead
        Position position;
    }

    // Order book
    mapping(uint256 => Order) public orders;
    uint256 public bestBuyId;
    uint256 public bestSellId;
    uint256 internal orderIdCounter;

    // Margin and positions
    mapping(address => Account) internal accounts;
    mapping(address => uint256) public pendingOrderCount;

    // Funding
    int256 public cumulativeFundingRate; // 1e18 precision
    mapping(address => int256) public lastFundingIndex;
    uint256 public lastFundingTime;
    uint256 public markPrice;
    uint256 public indexPrice;
    uint256 public fundingInterval = 1 hours;
    int256 public maxFundingRatePerInterval; // 0 表示不做上限限制，单位 1e18



    // Risk
    // Update: Lowered to 1% (100 bps) to allow up to 100x leverage.
    uint256 public initialMarginBps = 100;
    uint256 public maintenanceMarginBps = 50; // 0.5%
    uint256 public liquidationFeeBps = 125; // 1.25% (Binance Style)
    uint256 public minLiquidationFee = 0.01 ether; // Minimum fee to incentivize liquidators

    // insuranceFund removed - bad debt persists
    
    // Limit max pending orders per user to simplify worst-case margin calculation
    uint256 public constant MAX_PENDING_ORDERS = 10;

    // Price update tracking
    // 为了简化，移除顺序约束，依赖每次操作前从 Pyth 拉取最新价

    event MarginDeposited(address indexed trader, uint256 amount);
    event MarginWithdrawn(address indexed trader, uint256 amount);
    event OrderPlaced(uint256 indexed id, address indexed trader, bool isBuy, uint256 price, uint256 amount);
    event OrderRemoved(uint256 indexed id);
    event TradeExecuted(
        uint256 indexed buyOrderId,
        uint256 indexed sellOrderId,
        uint256 price,
        uint256 amount,
        address buyer,
        address seller
    );
    event MarkPriceUpdated(uint256 markPrice, uint256 indexPrice);
    event FundingUpdated(int256 cumulativeFundingRate, uint256 timestamp);
    event FundingParamsUpdated(uint256 interval, int256 maxRatePerInterval);
    event Liquidated(address indexed trader, address indexed liquidator, uint256 reward, uint256 sentToFund);
    event FundingPaid(address indexed trader, int256 amount);

    event OperatorUpdated(address operator);
}
