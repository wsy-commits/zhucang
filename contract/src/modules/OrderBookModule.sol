// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "./MarginModule.sol";

/// @notice Order placement and matching logic.
/// @dev Day 2-3: 订单簿与撮合模块
abstract contract OrderBookModule is MarginModule {

    /// @notice 下单
    /// @param isBuy 是否为买单
    /// @param price 价格
    /// @param amount 数量
    /// @param hintId 插入提示 (可选优化)
    /// @return 订单 ID
    function placeOrder(bool isBuy, uint256 price, uint256 amount, uint256 hintId)
        external
        virtual
        nonReentrant
        returns (uint256)
    {
        // TODO: 请实现此函数
        // 步骤:
        // 1. 检查 price > 0 && amount > 0
        // 2. 应用资金费 _applyFunding
        // 3. 检查挂单数量限制
        // 4. 检查保证金 _checkWorstCaseMargin
        // 5. 创建订单，生成订单 ID
        // 6. 触发 OrderPlaced 事件
        // 7. 调用 _matchBuy 或 _matchSell 进行撮合
        // 8. 返回订单 ID
        revert("Not implemented");
    }

    /// @notice 取消订单
    /// @param orderId 订单 ID
    function cancelOrder(uint256 orderId) external virtual nonReentrant {
        // TODO: 请实现此函数
        // 步骤:
        // 1. 检查订单存在
        // 2. 检查是订单所有者
        // 3. 从链表中移除订单
        // 4. 减少 pendingOrderCount
        // 5. 触发 OrderRemoved 事件
        // 6. 删除订单
    }

    /// @notice 从链表中移除指定订单
    function _removeOrderFromList(uint256 head, uint256 targetId) internal returns (uint256 newHead) {
        // TODO: 请实现此函数
        return head;
    }

    /// @notice 买单撮合
    /// @dev Day 3: 撮合买单与卖单链表
    function _matchBuy(Order memory incoming, uint256 hintId) internal virtual {
        // TODO: 请实现此函数
        // 步骤:
        // 1. 循环: 当 incoming.amount > 0 且 bestSellId != 0
        // 2. 获取最优卖单，检查价格是否匹配 (incoming.price >= sell.price)
        // 3. 计算成交数量 matched = min(incoming.amount, sell.amount)
        // 4. 调用 _executeTrade
        // 5. 更新双方订单剩余数量
        // 6. 如果卖单完全成交，移除并更新 bestSellId
        // 7. 如果 incoming 还有剩余，插入买单链表
    }

    /// @notice 卖单撮合
    function _matchSell(Order memory incoming, uint256 hintId) internal virtual {
        // TODO: 请实现此函数
        // 类似 _matchBuy，但方向相反
    }

    /// @notice 插入买单到链表
    /// @dev Day 2: 维护价格优先级 (高价优先)
    function _insertBuy(Order memory incoming, uint256 hintId) internal virtual {
        // TODO: 请实现此函数
        // 步骤:
        // 1. 从 hint 或链表头开始
        // 2. 找到正确插入位置 (价格降序)
        // 3. 插入订单并更新链表指针
        // 4. 增加 pendingOrderCount
    }

    /// @notice 插入卖单到链表
    /// @dev Day 2: 维护价格优先级 (低价优先)
    function _insertSell(Order memory incoming, uint256 hintId) internal virtual {
        // TODO: 请实现此函数
        // 类似 _insertBuy，但价格升序
    }

    /// @notice 从 hint 位置开始遍历
    function _startFromHint(bool isBuy, uint256 price, uint256 hintId) internal view virtual returns (uint256 prev, uint256 curr) {
        // TODO: 请实现此函数
        if (hintId == 0) {
            return (0, isBuy ? bestBuyId : bestSellId);
        }
        return (hintId, orders[hintId].next);
    }

    /// @notice 清算用户
    /// @dev Day 6: 强制平仓
    function liquidate(address trader, uint256 amount) external virtual nonReentrant {
        // TODO: 请实现此函数
        // 步骤:
        // 1. 检查不能自我清算
        // 2. 检查标记价已设置
        // 3. 应用资金费
        // 4. 检查 canLiquidate(trader)
        // 5. 清除用户挂单
        // 6. 执行市价平仓
        // 7. 计算并转移清算费
        // 8. 触发 Liquidated 事件
    }

    /// @notice 清算卖单撮合 (市价)
    function _matchLiquidationSell(Order memory incoming) internal {
        // TODO: 请实现此函数
    }

    /// @notice 清算买单撮合 (市价)
    function _matchLiquidationBuy(Order memory incoming) internal {
        // TODO: 请实现此函数
    }
}
