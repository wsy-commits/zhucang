// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "./MarginModule.sol";

import "forge-std/console.sol";

    /// @notice Order placement and matching logic.
    abstract contract OrderBookModule is MarginModule {

    function placeOrder(bool isBuy, uint256 price, uint256 amount, uint256 hintId)
        external
        virtual
        nonReentrant
        returns (uint256)
    {
        require(price > 0 && amount > 0, "invalid params");
        
        // Apply funding FIRST to update freeMargin
        _applyFunding(msg.sender);
        
        // Check pending order limit
        uint256 pendingCount = _countPendingOrders(msg.sender);
        require(pendingCount < MAX_PENDING_ORDERS, "too many pending orders");
        
        // Check worst-case margin (current position + all pending orders + this new order)
        // Note: This is done before adding to orderbook, so it's conservative
        _checkWorstCaseMargin(msg.sender);

        orderIdCounter += 1;
        uint256 orderId = orderIdCounter;
        emit OrderPlaced(orderId, msg.sender, isBuy, price, amount);

        Order memory incoming = Order(orderId, msg.sender, isBuy, price, amount, amount, block.timestamp, 0);

        if (isBuy) {
            _matchBuy(incoming, hintId);
        } else {
            _matchSell(incoming, hintId);
        }

        return orderId;
    }

    // cancelOrder function
    function cancelOrder(uint256 orderId) external virtual nonReentrant {
        Order storage o = orders[orderId];
        require(o.id != 0, "order not found");
        require(o.trader == msg.sender, "not your order");
        
        // Remove from linked list
        if (o.isBuy) {
            bestBuyId = _removeOrderFromList(bestBuyId, orderId);
        } else {
            bestSellId = _removeOrderFromList(bestSellId, orderId);
        }
        
        pendingOrderCount[msg.sender]--;
        emit OrderRemoved(orderId);
        delete orders[orderId];
    }

    function _removeOrderFromList(uint256 head, uint256 targetId) internal returns (uint256 newHead) {
        if (head == targetId) return orders[head].next;
        
        uint256 prev = head;
        uint256 curr = orders[head].next;
        while (curr != 0) {
            if (curr == targetId) {
                orders[prev].next = orders[curr].next;
                break;
            }
            prev = curr;
            curr = orders[curr].next;
        }
        return head;
    }

    function _matchBuy(Order memory incoming, uint256 hintId) internal virtual {
        while (incoming.amount > 0 && bestSellId != 0) {
            Order storage head = orders[bestSellId];
            if (incoming.price < head.price) break;

            uint256 matched = Math.min(incoming.amount, head.amount);

            _executeTrade(incoming.trader, head.trader, incoming.id, head.id, matched, head.price);

            incoming.amount -= matched;
            head.amount -= matched;
            if (head.amount == 0) {
                uint256 nextHead = head.next;
                uint256 removedId = head.id;
                pendingOrderCount[head.trader]--;
                delete orders[bestSellId];
                bestSellId = nextHead;
                emit OrderRemoved(removedId);
            }
        }

        if (incoming.amount > 0) {
            _insertBuy(incoming, hintId);
            // M-5: Post-fill margin check (only if order remains in book)
            _checkWorstCaseMargin(incoming.trader);
        }
    }

    function _matchSell(Order memory incoming, uint256 hintId) internal virtual {
        while (incoming.amount > 0 && bestBuyId != 0) {
            Order storage head = orders[bestBuyId];
            if (incoming.price > head.price) break;

            uint256 matched = Math.min(incoming.amount, head.amount);


            _executeTrade(head.trader, incoming.trader, head.id, incoming.id, matched, head.price);


            incoming.amount -= matched;
            head.amount -= matched;
            if (head.amount == 0) {
                uint256 nextHead = head.next;
                uint256 removedId = head.id;
                pendingOrderCount[head.trader]--;
                delete orders[bestBuyId];
                bestBuyId = nextHead;
                emit OrderRemoved(removedId);
            }
        }

        if (incoming.amount > 0) {
            _insertSell(incoming, hintId);
            // M-5: Post-fill margin check (only if order remains in book)
            _checkWorstCaseMargin(incoming.trader);
        }
    }

    function _insertBuy(Order memory incoming, uint256 hintId) internal virtual {
        (uint256 prevId, uint256 currentId) = _startFromHint(true, incoming.price, hintId);

        while (currentId != 0 && orders[currentId].price > incoming.price) {
            prevId = currentId;
            currentId = orders[currentId].next;
        }
        while (currentId != 0 && orders[currentId].price == incoming.price) {
            prevId = currentId;
            currentId = orders[currentId].next;
        }

        incoming.next = currentId;
        orders[incoming.id] = incoming;

        if (prevId == 0) {
            bestBuyId = incoming.id;
        } else {
            orders[prevId].next = incoming.id;
        }
        pendingOrderCount[incoming.trader]++;
    }

    function _insertSell(Order memory incoming, uint256 hintId) internal virtual {
        (uint256 prevId, uint256 currentId) = _startFromHint(false, incoming.price, hintId);

        while (currentId != 0 && orders[currentId].price < incoming.price) {
            prevId = currentId;
            currentId = orders[currentId].next;
        }
        while (currentId != 0 && orders[currentId].price == incoming.price) {
            prevId = currentId;
            currentId = orders[currentId].next;
        }

        incoming.next = currentId;
        orders[incoming.id] = incoming;

        if (prevId == 0) {
            bestSellId = incoming.id;
        } else {
            orders[prevId].next = incoming.id;
        }
        pendingOrderCount[incoming.trader]++;
    }

    function _startFromHint(bool isBuy, uint256 price, uint256 hintId) internal view virtual returns (uint256 prev, uint256 curr) {
        if (hintId == 0) {
            return (0, isBuy ? bestBuyId : bestSellId);
        }
        Order storage hint = orders[hintId];
        require(hint.id != 0, "invalid hint");

        if (isBuy) {
            require(price <= hint.price, "hint too deep");
            if (price == hint.price && hint.next != 0) {
                require(orders[hint.next].price != price, "hint not last");
            }
        } else {
            require(price >= hint.price, "hint too deep");
            if (price == hint.price && hint.next != 0) {
                require(orders[hint.next].price != price, "hint not last");
            }
        }

        return (hintId, hint.next);
    }

    function liquidate(address trader, uint256 amount) external virtual nonReentrant {
        require(msg.sender != trader, "cannot self-liquidate");
        require(markPrice > 0, "mark price unset");
        require(amount > 0, "amount=0");
        _applyFunding(trader);
        require(canLiquidate(trader), "position healthy");
        
        _clearTraderOrders(trader);

        Position storage p = accounts[trader].position;
        uint256 sizeAbs = SignedMath.abs(p.size);
        require(amount <= sizeAbs, "amount > position");

        // 1. Execute Market Close (Force Trader to close against Book)
        if (p.size > 0) {
            // Trader Long -> Sell to close
            Order memory closeOrder = Order(0, trader, false, 0, amount, amount, block.timestamp, 0);
            _matchLiquidationSell(closeOrder);
        } else {
            // Trader Short -> Buy to close
            Order memory closeOrder = Order(0, trader, true, 0, amount, amount, block.timestamp, 0);
            _matchLiquidationBuy(closeOrder);
        }
        
        // 2. Calculate and Transfer Liquidation Fee (Reward)
        // Fee = Notional Value * liquidationFeeBps
        // Notional = Amount * MarkPrice (approximate value of closed portion)
        uint256 notional = (amount * markPrice) / 1e18;
        uint256 fee = (notional * liquidationFeeBps) / 10_000;
        // M-4: Minimum fee to incentivize liquidators
        if (fee < minLiquidationFee) fee = minLiquidationFee;
        
        // Deduct from Trader, Give to Liquidator
        // Note: Trader might already be negative (bad debt). We still deduct (make it more negative).
        // Liquidator gets paid from Trader's remaining margin (or system debt if we had insurance).
        // Here we just transfer balance. If Trader has 0, Liquidator gets 0? 
        // No, in this model, Liquidator MUST get paid. 
        // If Trader has funds, we transfer.
        // If Trader has NO funds (bad debt), Liquidator gets nothing? 
        // User said "bad debt persists". 
        // Ideally, we transfer from Trader to Liquidator.
        
        if (accounts[trader].freeMargin >= fee) {
            accounts[trader].freeMargin -= fee;
            accounts[msg.sender].freeMargin += fee;
        } else {
            // Trader doesn't have enough free margin.
            // We take whatever is left? Or we push realizedPnl negative?
            // "Bad debt persists" -> We push realizedPnl negative.
            // But freeMargin can't be negative.
            // So we deduct from realizedPnl.
            
            uint256 available = accounts[trader].freeMargin;
            accounts[trader].freeMargin = 0;
            
            // Transfer available first
            accounts[msg.sender].freeMargin += available;
            
            // The rest is debt
            uint256 debt = fee - available;
            p.realizedPnl -= int256(debt); // Make trader more negative
            
            // Liquidator gets the debt part? No, Liquidator needs REAL money.
            // If system has no insurance fund, Liquidator CANNOT get paid the debt part.
            // Liquidator only gets what's available.
            // This is the limitation of "No Insurance Fund".
            // But for this example, let's just give Liquidator what's available.
            // Or, to simulate "System pays", we could mint? No.
            // Let's stick to: Liquidator gets whatever is in Trader's margin.
        }
        
        emit Liquidated(trader, msg.sender, fee, 0);
        
        // H-1 Fix: After partial liquidation, verify remaining position (if any) is healthy
        // This prevents attackers from repeatedly liquidating tiny amounts to extract fees
        Position storage pAfterLiq = accounts[trader].position;
        if (pAfterLiq.size != 0) {
            require(!canLiquidate(trader), "must fully liquidate unhealthy position");
        }
    }

    function _matchLiquidationSell(Order memory incoming) internal {
        while (incoming.amount > 0 && bestBuyId != 0) {
            Order storage head = orders[bestBuyId];
            // Market order: accept best available price
            
            uint256 matched = Math.min(incoming.amount, head.amount);
            
            // Execute Trade
            // Trader (incoming) Sells, Head Buys.
            _executeTrade(head.trader, incoming.trader, head.id, 0, matched, head.price);

            incoming.amount -= matched;
            head.amount -= matched;
            
            if (head.amount == 0) {
                uint256 nextHead = head.next;
                uint256 removedId = head.id;
                delete orders[bestBuyId];
                bestBuyId = nextHead;
                emit OrderRemoved(removedId);
            }
        }
    }

    function _matchLiquidationBuy(Order memory incoming) internal {
        while (incoming.amount > 0 && bestSellId != 0) {
            Order storage head = orders[bestSellId];
            // Market order: accept best available price
            
            uint256 matched = Math.min(incoming.amount, head.amount);
            
            // Execute Trade
            // Trader (incoming) Buys, Head Sells.
            _executeTrade(incoming.trader, head.trader, 0, head.id, matched, head.price);

            incoming.amount -= matched;
            head.amount -= matched;
            
            if (head.amount == 0) {
                uint256 nextHead = head.next;
                uint256 removedId = head.id;
                delete orders[bestSellId];
                bestSellId = nextHead;
                emit OrderRemoved(removedId);
            }
        }
    }
}
