// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "./LiquidationModule.sol";

    /// @notice Margin accounting (deposit/withdraw) plus margin locks for orders.
    abstract contract MarginModule is LiquidationModule {
        function deposit() external payable virtual nonReentrant {
            accounts[msg.sender].freeMargin += msg.value;
            emit MarginDeposited(msg.sender, msg.value);
        }

        function withdraw(uint256 amount) external virtual nonReentrant {
            require(amount > 0, "amount=0");
            _applyFunding(msg.sender);
            require(accounts[msg.sender].freeMargin >= amount, "not enough margin");
            _ensureWithdrawKeepsMaintenance(msg.sender, amount);
            accounts[msg.sender].freeMargin -= amount;
            (bool ok, ) = msg.sender.call{value: amount}("");
            require(ok, "withdraw failed");
            emit MarginWithdrawn(msg.sender, amount);
        }

    /// @notice Calculate margin needed for a position at current mark price
    function _calculatePositionMargin(int256 size) internal view returns (uint256) {
        if (size == 0) return 0;
        uint256 absSize = size > 0 ? uint256(size) : uint256(-size);
        uint256 notional = (absSize * markPrice) / 1e18;
        return (notional * initialMarginBps) / 10_000;
    }

    /// @notice Count pending orders for a trader (O(1) via counter)
    function _countPendingOrders(address trader) internal view returns (uint256) {
        return pendingOrderCount[trader];
    }

    /// @notice Calculate worst-case margin if all pending orders execute
    function _calculateWorstCaseMargin(address trader) internal view returns (uint256) {
        Position memory pos = accounts[trader].position;
        
        // Accumulate all pending buy and sell sizes
        uint256 totalBuySize = 0;
        uint256 totalSellSize = 0;
        
        uint256 id = bestBuyId;
        while (id != 0) {
            if (orders[id].trader == trader) {
                totalBuySize += orders[id].amount;
            }
            id = orders[id].next;
        }
        
        id = bestSellId;
        while (id != 0) {
            if (orders[id].trader == trader) {
                totalSellSize += orders[id].amount;
            }
            id = orders[id].next;
        }
        
        // Calculate two scenarios: all buys execute OR all sells execute
        int256 sizeIfAllBuy = pos.size + int256(totalBuySize);
        int256 sizeIfAllSell = pos.size - int256(totalSellSize);
        
        uint256 marginIfAllBuy = _calculatePositionMargin(sizeIfAllBuy);
        uint256 marginIfAllSell = _calculatePositionMargin(sizeIfAllSell);
        
        // Return the maximum (worst case)
        return marginIfAllBuy > marginIfAllSell ? marginIfAllBuy : marginIfAllSell;
    }

    /// @notice Check if trader has enough margin for worst-case scenario
    function _checkWorstCaseMargin(address trader) internal view {
        uint256 required = _calculateWorstCaseMargin(trader);
        
        Position memory p = accounts[trader].position;
        int256 marginBalance = int256(accounts[trader].freeMargin)
                             + p.realizedPnl
                             + _unrealizedPnl(p);
        
        console.log("_checkWorstCaseMargin:", trader);
        console.log("  Required:", required);
        console.log("  Available:", uint256(marginBalance));
        
        require(
            marginBalance >= int256(required),
            string(abi.encodePacked(
                "insufficient margin: need ",
                _toString(required / 1e18),
                " ETH, have ",
                _toString(uint256(marginBalance) / 1e18),
                " ETH"
            ))
        );
    }

    function _toString(uint256 value) private pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

        function _ensureWithdrawKeepsMaintenance(address trader, uint256 amount) internal view {
            Position storage p = accounts[trader].position;
            if (p.size == 0) return;

            require(markPrice > 0, "mark price unset");
            uint256 priceBase = markPrice;
            int256 marginBalance = int256(accounts[trader].freeMargin - amount) + p.realizedPnl + _unrealizedPnl(p);
            uint256 positionValue = SignedMath.abs((int256(priceBase) * p.size) / 1e18);
            uint256 maintenance = (positionValue * maintenanceMarginBps) / 10_000;
            uint256 initialReq = (positionValue * initialMarginBps) / 10_000;
            uint256 requiredMargin = initialReq > maintenance ? initialReq : maintenance;
            require(marginBalance >= int256(requiredMargin), "withdraw breaches maintenance");
        }

    }
