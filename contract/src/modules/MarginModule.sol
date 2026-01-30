// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "./LiquidationModule.sol";

/// @notice Margin accounting (deposit/withdraw) plus margin checks.
/// @dev Day 1: 保证金模块
abstract contract MarginModule is LiquidationModule {

    /// @notice 存入保证金
    function deposit() external payable virtual nonReentrant {
       accounts[msg.sender].crossMargin += msg.value;
       emit MarginDeposited(msg.sender, msg.value);
    }

    /// @notice 提取保证金
    /// @param amount 提取金额
    function withdraw(uint256 amount) external virtual nonReentrant {
       require(amount > 0, "amount=0");
       _applyFunding(msg.sender);
       require(accounts[msg.sender].crossMargin >= amount, "not enough margin");
       _ensureWithdrawKeepsMaintenance(msg.sender, amount);

       accounts[msg.sender].crossMargin -= amount;
       (bool ok, ) = msg.sender.call{value: amount}("");
       require(ok, "withdraw failed");

       emit MarginWithdrawn(msg.sender, amount);
    }

    /// @notice 计算持仓所需保证金
    function _calculatePositionMargin(int256 size) internal view returns (uint256) {
    if (size == 0 || markPrice == 0) return 0;
    uint256 absSize = SignedMath.abs(size);
    uint256 notional = (absSize * markPrice) / 1e18;
    return (notional * initialMarginBps) / 10_000;
}

    /// @notice 获取用户待成交订单数量
    function _countPendingOrders(address trader) internal view returns (uint256) {
        return pendingOrderCount[trader];
    }

    /// @notice 计算最坏情况下所需保证金（扩展版：支持逐仓/全仓）
    /// @dev 假设所有挂单都成交后的保证金需求
    function _calculateWorstCaseMargin(address trader) internal view returns (uint256) {
        Position memory pos = accounts[trader].position;

        // ✅ 根据模式选择不同计算逻辑
        if (pos.mode == MarginMode.ISOLATED) {
            return _calculateIsolatedWorstCaseMargin(trader);
        } else {
            return _calculateCrossWorstCaseMargin(trader);  // 原有逻辑
        }
    }

    /// @notice 逐仓模式保证金计算
    function _calculateIsolatedWorstCaseMargin(address trader) internal view returns (uint256) {
        Position memory pos = accounts[trader].position;

        // 1. 持仓保证金
        uint256 positionMargin = _calculatePositionMargin(pos.size);

        // 2. 挂单保证金（逐仓特点：买单和卖单都占用，不能抵消）
        uint256 buyOrderMargin = 0;
        uint256 id = bestBuyId;
        while (id != 0) {
            if (orders[id].trader == trader) {
                 uint256 orderVal = (orders[id].price * orders[id].amount) / 1e18;
                 buyOrderMargin += (orderVal * initialMarginBps) / 10_000;
            }
            id = orders[id].next;
        }

        uint256 sellOrderMargin = 0;
        id = bestSellId;
        while (id != 0) {
            if (orders[id].trader == trader) {
                 uint256 orderVal = (orders[id].price * orders[id].amount) / 1e18;
                 sellOrderMargin += (orderVal * initialMarginBps) / 10_000;
            }
            id = orders[id].next;
        }

        // 逐仓：持仓 + 所有挂单（买单和卖单相加）
        return positionMargin + buyOrderMargin + sellOrderMargin;
    }

    /// @notice 全仓模式保证金计算（保持原有逻辑）
    function _calculateCrossWorstCaseMargin(address trader) internal view returns (uint256) {
        Position memory pos = accounts[trader].position;

        // 1. 挂单保证金（买单或卖单，取较大值）
        uint256 buyOrderMargin = 0;
        uint256 id = bestBuyId;
        while (id != 0) {
            if (orders[id].trader == trader) {
                 uint256 orderVal = (orders[id].price * orders[id].amount) / 1e18;
                 buyOrderMargin += (orderVal * initialMarginBps) / 10_000;
            }
            id = orders[id].next;
        }

        uint256 sellOrderMargin = 0;
        id = bestSellId;
        while (id != 0) {
            if (orders[id].trader == trader) {
                 uint256 orderVal = (orders[id].price * orders[id].amount) / 1e18;
                 sellOrderMargin += (orderVal * initialMarginBps) / 10_000;
            }
            id = orders[id].next;
        }

        // 2. 持仓保证金
        uint256 positionMargin = _calculatePositionMargin(pos.size);

        // 3. 全仓：持仓 + Max(买单, 卖单)
        return positionMargin + (buyOrderMargin > sellOrderMargin ? buyOrderMargin : sellOrderMargin);
    }

    /// @notice 检查用户是否有足够保证金
    function _checkWorstCaseMargin(address trader) internal view {
        uint256 required = _calculateWorstCaseMargin(trader);
        Position memory p = accounts[trader].position;

        int256 marginBalance =
            int256(accounts[trader].crossMargin) + _unrealizedPnl(p);

        require(marginBalance >= int256(required), "insufficient margin");
    }

    /// @notice 确保提现后仍满足维持保证金要求
/// @dev Day 6: 提现时的维持保证金检查
function _ensureWithdrawKeepsMaintenance(address trader, uint256 amount) internal view {
    Position memory p = accounts[trader].position;

    // 1. 如果没有持仓，直接返回
    if (p.size == 0) return;

    // 2. 计算提现后的 marginBalance
    int256 marginAfter = int256(accounts[trader].crossMargin) - int256(amount);
    int256 unrealized = _unrealizedPnl(p);
    int256 marginBalance = marginAfter + unrealized;

    // 3. 计算持仓价值和维持保证金
    uint256 priceBase = markPrice == 0 ? p.entryPrice : markPrice;
    uint256 positionValue = SignedMath.abs(int256(priceBase) * p.size) / 1e18;
    uint256 maintenance = (positionValue * maintenanceMarginBps) / 10_000;

    // 4. require(marginBalance >= maintenance)
    require(marginBalance >= int256(maintenance), "withdraw would trigger liquidation");
}

    // ========== ✅ 新增：逐仓保证金管理接口 ==========

    /// @notice 分配保证金到逐仓仓位
    /// @param amount 分配金额（从 crossMargin 转移到 isolatedMargin）
    /// @dev 允许用户在 CROSS 模式下预分配保证金，为 ISOLATED 开仓做准备
    function allocateToIsolated(uint256 amount) external nonReentrant {
        Position storage pos = accounts[msg.sender].position;

        // ✅ 允许在 CROSS 模式下预分配，或已经在 ISOLATED 模式下追加保证金
        // 只有当有仓位且模式不同时才拒绝（不允许混合模式）
        if (pos.size != 0) {
            require(pos.mode == MarginMode.ISOLATED, "position is not isolated mode");
        }

        // 检查：全仓保证金充足
        require(accounts[msg.sender].crossMargin >= amount, "insufficient cross margin");

        // 执行转移
        accounts[msg.sender].crossMargin -= amount;
        pos.isolatedMargin += amount;

        emit IsolatedMarginAllocated(msg.sender, amount);
    }

    /// @notice 从逐仓仓位回收保证金
    /// @param amount 回收金额（从 isolatedMargin 转移回 crossMargin）
    /// @dev 允许用户在任意模式下回收未使用的 Isolated 保证金
    function removeFromIsolated(uint256 amount) external nonReentrant {
        Position storage pos = accounts[msg.sender].position;

        // ✅ 允许回收未使用的保证金，但如果有仓位则必须是 ISOLATED 模式
        if (pos.size != 0) {
            require(pos.mode == MarginMode.ISOLATED, "position is not isolated mode");
            // 有仓位时，必须检查回收后是否满足维持保证金
            require(_checkIsolatedMaintenanceAfterRemoval(msg.sender, amount), "would trigger liquidation");
        }

        require(pos.isolatedMargin >= amount, "insufficient isolated margin");

        // 执行转移
        pos.isolatedMargin -= amount;
        accounts[msg.sender].crossMargin += amount;

        emit IsolatedMarginRemoved(msg.sender, amount);
    }

    /// @notice 检查逐仓维持保证金（回收保证金后）
    /// @param trader 用户地址
    /// @param removeAmount 计划回收的金额
    /// @return 是否满足维持保证金要求
    function _checkIsolatedMaintenanceAfterRemoval(
        address trader,
        uint256 removeAmount
    ) internal view returns (bool) {
        Position memory pos = accounts[trader].position;

        // 计算回收后的保证金余额
        uint256 marginAfter = pos.isolatedMargin - removeAmount;
        int256 unrealized = _unrealizedPnl(pos);
        int256 marginBalance = int256(marginAfter) + unrealized;

        // 计算维持保证金需求
        uint256 priceBase = markPrice == 0 ? pos.entryPrice : markPrice;
        uint256 positionValue = SignedMath.abs(int256(priceBase) * pos.size) / 1e18;
        uint256 maintenance = (positionValue * maintenanceMarginBps) / 10_000;

        return marginBalance >= int256(maintenance);
    }
}
