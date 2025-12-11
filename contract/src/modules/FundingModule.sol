// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "../core/ExchangeStorage.sol";

    /// @notice Funding settlement and shared math helpers.
    abstract contract FundingModule is ExchangeStorage {
        function settleFunding() public virtual {
        // 1. Calculate time delta
        // 1. Check if interval has passed
        if (block.timestamp < lastFundingTime + fundingInterval) return;
        if (indexPrice == 0) return;

        // 2. Update cumulative funding rate
        // Binance Formula: F = P + clamp(I - P, 0.05%, -0.05%)
        // P (Premium Index) = (Mark - Index) / Index
        // I (Interest Rate) = 0.01% (0.0001)
        
        int256 mark = int256(markPrice);
        int256 index = int256(indexPrice);
        
        int256 premiumIndex = ((mark - index) * 1e18) / index;
        
        int256 interestRate = 1e14; // 0.01%
        int256 clampRange = 5e14;   // 0.05%
        
        int256 diff = interestRate - premiumIndex;
        int256 clamped = diff;
        
        if (diff > clampRange) clamped = clampRange;
        if (diff < -clampRange) clamped = -clampRange;
        
        int256 rate = premiumIndex + clamped;

        // Apply global cap if set
        if (maxFundingRatePerInterval > 0) {
            if (rate > maxFundingRatePerInterval) rate = maxFundingRatePerInterval;
            if (rate < -maxFundingRatePerInterval) rate = -maxFundingRatePerInterval;
        }

        // Add to cumulative
        cumulativeFundingRate += rate;
        lastFundingTime = block.timestamp;

        emit FundingUpdated(cumulativeFundingRate, block.timestamp);
    }

    function settleUserFunding(address trader) external virtual {
        _applyFunding(trader);
    }

    function setFundingParams(uint256 interval, int256 maxRatePerInterval) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        require(interval > 0, "interval=0");
        require(maxRatePerInterval >= 0, "cap<0");
        fundingInterval = interval;
        maxFundingRatePerInterval = maxRatePerInterval;
        emit FundingParamsUpdated(interval, maxRatePerInterval);
    }

    function _applyFunding(address trader) internal virtual {
        Account storage a = accounts[trader];
        Position storage p = a.position;
        if (p.size == 0) {
            lastFundingIndex[trader] = cumulativeFundingRate;
            return;
        }

        settleFunding();
        int256 diff = cumulativeFundingRate - lastFundingIndex[trader];
        if (diff == 0) {
            return;
        }

        // Payment = Position Value * Rate Diff
        // Value = Size * MarkPrice
        // Payment = (Size * MarkPrice * Diff) / 1e36
        //  Size (1e18) * Price (1e18) * Diff (1e18) = 1e54
        // Div by 1e36 -> 1e18 (MON)
        int256 payment = (int256(p.size) * int256(markPrice) * diff) / 1e36; // >0 表示扣款
        uint256 free = a.freeMargin;
        if (payment > 0) {
            uint256 pay = uint256(payment);
            if (pay > free) {
                // Not enough free margin, deduct from realized PnL
                uint256 debt = pay - free;
                a.freeMargin = 0;
                p.realizedPnl -= int256(debt);
            } else {
                a.freeMargin = free - pay;
            }
        } else if (payment < 0) {
            uint256 credit = uint256(-payment);
            a.freeMargin = free + credit;
        }
        lastFundingIndex[trader] = cumulativeFundingRate;
        emit FundingPaid(trader, payment);
    }

    function _unrealizedPnl(Position memory p) internal view returns (int256) {
        if (p.size == 0) return 0;
        int256 priceDiff = int256(markPrice) - int256(p.entryPrice);
        if (p.size < 0) priceDiff = -priceDiff;
        return (priceDiff * int256(SignedMath.abs(p.size))) / 1e18;
    }

    // 钩子：子模块可覆盖以在操作前拉取最新价格
    function _pullLatestPrice() internal virtual {}
}
