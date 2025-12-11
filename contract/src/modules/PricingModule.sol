// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./FundingModule.sol";

/// @notice Price management (Operator updates only).
abstract contract PricingModule is FundingModule {
    function updateIndexPrice(uint256 newIndexPrice) external virtual onlyRole(OPERATOR_ROLE) {
        indexPrice = newIndexPrice;
        markPrice = _calculateMarkPrice(newIndexPrice);
        emit MarkPriceUpdated(markPrice, indexPrice);
    }

    function _calculateMarkPrice(uint256 indexPrice_) internal view virtual returns (uint256) {
        uint256 bestBid = 0;
        uint256 bestAsk = 0;

        if (bestBuyId != 0) {
            bestBid = orders[bestBuyId].price;
        }
        if (bestSellId != 0) {
            bestAsk = orders[bestSellId].price;
        }

        // If both empty, return index
        if (bestBid == 0 && bestAsk == 0) {
            return indexPrice_;
        }

        // If one side empty, use index for that side
        if (bestBid == 0) bestBid = indexPrice_;
        if (bestAsk == 0) bestAsk = indexPrice_;

        // Median of (Bid, Ask, Index)
        // Sort the 3 values: a, b, c
        uint256 a = bestBid;
        uint256 b = bestAsk;
        uint256 c = indexPrice_;
        
        if (a > b) (a, b) = (b, a);
        if (b > c) (b, c) = (c, b);
        if (a > b) (a, b) = (b, a);
        
        uint256 median = b;
        
        // M-3: Clamp mark price to within 5% of index to prevent manipulation
        uint256 maxDeviation = (indexPrice_ * 500) / 10_000; // 5%
        if (median > indexPrice_ + maxDeviation) {
            return indexPrice_ + maxDeviation;
        }
        if (indexPrice_ > maxDeviation && median < indexPrice_ - maxDeviation) {
            return indexPrice_ - maxDeviation;
        }
        return median;
    }

    function _pullLatestPrice() internal virtual override(FundingModule) {
        // No-op: Price is pushed by operator
    }
}
