


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../core/ExchangeStorage.sol";

/// @notice Read-only helpers for offchain consumers.
/// @dev Day 1: 这些是视图函数，用于读取合约状态
abstract contract ViewModule is ExchangeStorage {

    /// @notice 获取订单详情
    /// @param id 订单 ID
    /// @return 订单结构体
    function getOrder(uint256 id) external view virtual returns (Order memory) {
        return orders[id];
    }

    /// @notice 获取用户全仓保证金
    /// @param trader 用户地址
    /// @return 全仓保证金数量
    function getCrossMargin(address trader) external view virtual returns (uint256) {
       return accounts[trader].crossMargin;
    }

    /// @notice 获取用户保证金模式
    /// @param trader 用户地址
    /// @return 保证金模式（CROSS 或 ISOLATED）
    function getMarginMode(address trader) external view virtual returns (MarginMode) {
        return accounts[trader].position.mode;
    }

    /// @notice 获取用户逐仓保证金
    /// @param trader 用户地址
    /// @return 逐仓保证金数量
    function getIsolatedMargin(address trader) external view virtual returns (uint256) {
        return accounts[trader].position.isolatedMargin;
    }

    /// @notice 获取用户持仓
    /// @param trader 用户地址
    /// @return 持仓结构体
    function getPosition(address trader) external view virtual returns (Position memory) {
        return accounts[trader].position;
    }

    /// @notice 获取完整账户详情
    /// @param trader 用户地址
    /// @return crossMargin 全仓保证金
    /// @return mode 保证金模式
    /// @return isolatedMargin 逐仓保证金
    /// @return size 持仓数量
    /// @return entryPrice 入场价格
    function getAccountDetails(address trader) external view virtual returns (
        uint256 crossMargin,
        MarginMode mode,
        uint256 isolatedMargin,
        int256 size,
        uint256 entryPrice
    ) {
        Account memory acc = accounts[trader];
        Position memory pos = acc.position;
        return (
            acc.crossMargin,
            pos.mode,
            pos.isolatedMargin,
            pos.size,
            pos.entryPrice
        );
    }

    /// @notice 兼容旧接口：获取用户账户保证金（返回全仓保证金）
    /// @param trader 用户地址
    /// @return 账户保证金数量
    function margin(address trader) external view virtual returns (uint256) {
       return accounts[trader].crossMargin;
    }
}
