// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../core/ExchangeStorage.sol";

/// @notice Read-only helpers for offchain consumers.
abstract contract ViewModule is ExchangeStorage {
    function getOrder(uint256 id) external view virtual returns (Order memory) {
        Order memory o = orders[id];
        return o;
    }

    function margin(address trader) external view virtual returns (uint256) {
        return accounts[trader].freeMargin;
    }

    // lockedMargin removed - using position-based margin instead

    function positions(address trader) external view virtual returns (Position memory) {
        return accounts[trader].position;
    }

    function getPosition(address trader) external view virtual returns (Position memory) {
        return accounts[trader].position;
    }
}
