// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "./PricingModule.sol";
import "forge-std/console.sol";


    /// @notice Liquidation checks and execution.
    abstract contract LiquidationModule is PricingModule {
    function canLiquidate(address trader) public view virtual returns (bool) {
        Position memory p = accounts[trader].position;
        if (p.size == 0) return false;

        uint256 markPrice = _calculateMarkPrice(indexPrice);
        
        int256 unrealized = _unrealizedPnl(p);
        
        int256 marginBalance = int256(accounts[trader].freeMargin) + p.realizedPnl + unrealized;
        
        uint256 priceBase = markPrice == 0 ? p.entryPrice : markPrice;
        uint256 positionValue = SignedMath.abs(int256(priceBase) * p.size) / 1e18;
        // Binance Style: Maintenance + Liquidation Fee is the trigger line
        uint256 maintenance = (positionValue * (maintenanceMarginBps + liquidationFeeBps)) / 10_000;
        
        return marginBalance < int256(maintenance);
        }

    function liquidate(address trader) external virtual nonReentrant {
        // Implemented in OrderBookModule
    }

    // _executeTrade and _updatePosition moved back to OrderBookModule/Exchange.sol
    // or kept here if needed by both?
    // Actually, if OrderBookModule overrides liquidate, it can use its own _executeTrade.
    // But _executeTrade uses _updatePosition.
    // Let's keep _updatePosition here or in MarginModule?
    // MarginModule seems best for _updatePosition as it touches margin.
    // But for now, let's move them back to OrderBookModule or keep them here if OrderBookModule inherits this.
    // OrderBookModule inherits MarginModule inherits LiquidationModule.
    // So if they are here, OrderBookModule can use them.
    // So I will KEEP `_executeTrade` and `_updatePosition` here for reuse.
    
    // Wait, I need to remove the specific "Liquidator Takeover" logic from `liquidate`.
    
    // ... (keeping helper functions)

    function _clearTraderOrders(address trader) internal returns (uint256 freedLocked) {
        freedLocked = 0; // No longer tracking locked margin
        bestBuyId = _removeOrders(bestBuyId, trader);
        bestSellId = _removeOrders(bestSellId, trader);
        accounts[trader].freeMargin += freedLocked;
    }

    function _removeOrders(uint256 headId, address trader) internal returns (uint256 newHead) {
        newHead = headId;
        uint256 current = headId;
        uint256 prev = 0;

        while (current != 0) {
            Order storage o = orders[current];
            uint256 next = o.next;
            if (o.trader == trader) {
                if (prev == 0) {
                    newHead = next;
                } else {
                    orders[prev].next = next;
                }
                emit OrderRemoved(o.id);
                delete orders[current];
                current = next;
                continue;
            }
            prev = current;
            current = next;
        }
    }

    // Moved from OrderBookModule
    uint256 constant SCALE = 1e18;

    function _executeTrade(
        address buyer,
        address seller,
        uint256 buyOrderId,
        uint256 sellOrderId,
        uint256 amount,
        uint256 price
    ) internal virtual {
        _applyFunding(buyer);
        _applyFunding(seller);

        _updatePosition(buyer, true, amount, price);
        _updatePosition(seller, false, amount, price);

        console.log("TradeExecuted: Price", price);
        console.log("TradeExecuted: Amount", amount);

        emit TradeExecuted(buyOrderId, sellOrderId, price, amount, buyer, seller);
    }

    function _updatePosition(
        address trader,
        bool isBuy,
        uint256 amount,
        uint256 tradePrice
    ) internal virtual {
        Position storage p = accounts[trader].position;
        int256 signed = isBuy ? int256(amount) : -int256(amount);

        if (p.size == 0 || (p.size > 0) == (signed > 0)) {
            uint256 existingAbs = SignedMath.abs(p.size);
            uint256 newAbs = existingAbs + amount;
            uint256 weighted = existingAbs == 0
                ? tradePrice
                : (existingAbs * p.entryPrice + amount * tradePrice) / newAbs;
            p.entryPrice = weighted;
            p.size += signed;
            return;
        }

        uint256 existingAbsNeg = SignedMath.abs(p.size);
        uint256 closing = amount < existingAbsNeg ? amount : existingAbsNeg;
        int256 pnlPerUnit =
            p.size > 0 ? int256(tradePrice) - int256(p.entryPrice) : int256(p.entryPrice) - int256(tradePrice);
        int256 pnl = (pnlPerUnit * int256(closing)) / int256(SCALE);

        p.realizedPnl += pnl;

        int256 newMargin = int256(accounts[trader].freeMargin) + pnl;
        
        if (newMargin < 0) {
            accounts[trader].freeMargin = 0;
        } else {
            accounts[trader].freeMargin = uint256(newMargin);
        }

        uint256 remaining = amount - closing;
        if (closing == existingAbsNeg) {
            if (remaining == 0) {
                p.size = 0;
                p.entryPrice = tradePrice;
            } else {
                p.size = signed > 0 ? int256(remaining) : -int256(remaining);
                p.entryPrice = tradePrice;
            }
        } else {
            if (p.size > 0) {
                p.size -= int256(closing);
            } else {
                p.size += int256(closing);
            }
        }
    }


}
