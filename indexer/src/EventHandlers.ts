import {
  Exchange,
  Order,
  MarginEvent,
  Trade,
  Position,
  Candle,        // ← 取消注释
  LatestCandle,
  FundingEvent,
  Liquidation,  // ← 如果也用到了，也一起导进来
} from "../generated";

/**
 * Event Handlers - 脚手架版本
 * 
 * 这个文件定义了如何处理合约事件并存储到数据库。
 * 
 * TODO: 学生需要实现以下事件处理器：
 * 1. MarginDeposited - 记录充值事件
 * 2. MarginWithdrawn - 记录提现事件
 * 3. OrderPlaced - 记录新订单
 * 4. OrderRemoved - 更新订单状态 (取消/成交)
 * 5. TradeExecuted - 记录成交，更新订单、K线、持仓
 */

/**
 * 处理保证金充值事件
 * 
 * TODO: 实现此处理器
 * 步骤:
 * 1. 从 event.params 获取 trader 和 amount
 * 2. 创建 MarginEvent 实体
 * 3. 使用 context.MarginEvent.set 保存
 */


Exchange.MarginDeposited.handler(async ({ event, context }) => {
    const entity: MarginEvent = {
        id: `${event.transaction.hash}-${event.logIndex}`,
        trader: event.params.trader,
        amount: event.params.amount,
        eventType: "DEPOSIT",
        timestamp: event.block.timestamp,
        txHash: event.transaction.hash,
    };
    context.MarginEvent.set(entity);
});

Exchange.MarginWithdrawn.handler(async ({ event, context }) => {
    const entity: MarginEvent = {
        id: `${event.transaction.hash}-${event.logIndex}`,
        trader: event.params.trader,
        amount: event.params.amount,
        eventType: "WITHDRAW",
        timestamp: event.block.timestamp,
        txHash: event.transaction.hash,
    };
    context.MarginEvent.set(entity);
});

Exchange.OrderPlaced.handler(async ({ event, context }) => {
    const order: Order = {
        id: event.params.id.toString(),
        trader: event.params.trader,
        isBuy: event.params.isBuy,
        price: event.params.price,
        initialAmount: event.params.amount,
        amount: event.params.amount,
        status: "OPEN",
        timestamp: event.block.timestamp,
    };
    context.Order.set(order);
});

Exchange.OrderRemoved.handler(async ({ event, context }) => {
    const order = await context.Order.get(event.params.id.toString());
    if (order) {
        context.Order.set({
            ...order,
            status: order.amount === 0n ? "FILLED" : "CANCELLED",
            amount: 0n, // 清零以便 GET_OPEN_ORDERS 过滤
        });
    }
});

Exchange.TradeExecuted.handler(async ({ event, context }) => {
    // 1. 创建成交记录
    const trade: Trade = {
        id: `${event.transaction.hash}-${event.logIndex}`,
        buyer: event.params.buyer,
        seller: event.params.seller,
        price: event.params.price,
        amount: event.params.amount,
        timestamp: event.block.timestamp,
        txHash: event.transaction.hash,
        buyOrderId: event.params.buyOrderId,
        sellOrderId: event.params.sellOrderId,
    };
    context.Trade.set(trade);

     // Day 5: 更新 K 线 (1m)
const resolution = "1m";
// 向下取整到最近的分钟
const timestamp = event.block.timestamp - (event.block.timestamp % 60);
const candleId = `${resolution}-${timestamp}`;

const existingCandle = await context.Candle.get(candleId);

if (!existingCandle) {
    // 新 K 线：使用上一根 K 线的 close 作为 open
    const latestCandleState = await context.LatestCandle.get("1");
    const openPrice = latestCandleState ? latestCandleState.closePrice : event.params.price;
    
    const candle: Candle = {
        id: candleId,
        resolution,
        timestamp,
        openPrice: openPrice,
        highPrice: event.params.price > openPrice ? event.params.price : openPrice,
        lowPrice: event.params.price < openPrice ? event.params.price : openPrice,
        closePrice: event.params.price,
        volume: event.params.amount,
    };
    context.Candle.set(candle);
} else {
    // 更新现有 K 线
    const newHigh = event.params.price > existingCandle.highPrice ? event.params.price : existingCandle.highPrice;
    const newLow = event.params.price < existingCandle.lowPrice ? event.params.price : existingCandle.lowPrice;

    context.Candle.set({
        ...existingCandle,
        highPrice: newHigh,
        lowPrice: newLow,
        closePrice: event.params.price,
        volume: existingCandle.volume + event.params.amount,
    });
}

// 更新全局最新价格状态
context.LatestCandle.set({
    id: "1",
    closePrice: event.params.price,
    timestamp: event.block.timestamp
});

    // 2. 更新买卖双方订单的剩余量
    const buyOrder = await context.Order.get(event.params.buyOrderId.toString());
    if (buyOrder) {
        const newAmount = buyOrder.amount - event.params.amount;
        context.Order.set({
            ...buyOrder,
            amount: newAmount,
            status: newAmount === 0n ? "FILLED" : "OPEN",
        });
    }

    const sellOrder = await context.Order.get(event.params.sellOrderId.toString());
    if (sellOrder) {
        const newAmount = sellOrder.amount - event.params.amount;
        context.Order.set({
            ...sellOrder,
            amount: newAmount,
            status: newAmount === 0n ? "FILLED" : "OPEN",
        });
    }
});

Exchange.PositionUpdated.handler(async ({ event, context }) => {
    const position: Position = {
        id: event.params.trader,
        trader: event.params.trader,
        size: event.params.size,
        entryPrice: event.params.entryPrice,
        marginMode: 0, // 0 = CROSS (跨仓模式)
        isolatedMargin: 0n, // 跨仓模式下逐仓保证金为 0
    };
    context.Position.set(position);
});
// /**
//  * 处理保证金提现事件
//  */
Exchange.FundingUpdated.handler(async ({ event, context }) => {
    const entity: FundingEvent = {
        id: `${event.transaction.hash}-${event.logIndex}`,
        eventType: "GLOBAL_UPDATE",
        trader: undefined,
        cumulativeRate: event.params.cumulativeFundingRate,
        payment: undefined,
        timestamp: event.block.timestamp,
    };
    context.FundingEvent.set(entity);
});

Exchange.FundingPaid.handler(async ({ event, context }) => {
    const entity: FundingEvent = {
        id: `${event.transaction.hash}-${event.logIndex}`,
        eventType: "USER_PAID",
        trader: event.params.trader,
        cumulativeRate: undefined,
        payment: undefined,
        timestamp: event.block.timestamp,
    };
    context.FundingEvent.set(entity);
});

Exchange.Liquidated.handler(async ({ event, context }) => {
    const entity: Liquidation = {
        id: `${event.transaction.hash}-${event.logIndex}`,
        trader: event.params.trader,
        liquidator: event.params.liquidator,
        amount: event.params.amount,
        fee: event.params.reward,
        timestamp: event.block.timestamp,
        txHash: event.transaction.hash,
    };
    context.Liquidation.set(entity);
    
    // 清算后持仓应该归零或减少
    const position = await context.Position.get(event.params.trader);
    if (position) {
        const newSize = position.size > 0n 
            ? position.size - event.params.amount 
            : position.size + event.params.amount;
        context.Position.set({
            ...position,
            size: newSize,
        });
    }
});
// /**
//  * 处理订单创建事件
//  * 
//  * TODO: 实现此处理器
//  * 步骤:
//  * 1. 从 event.params 获取订单信息
//  * 2. 创建 Order 实体，status 设为 "OPEN"
//  * 3. 使用 context.Order.set 保存
//  */
// Exchange.OrderPlaced.handler(async ({ event, context }) => {
//     console.log('TODO: Implement OrderPlaced handler');
// });

// /**
//  * 处理订单移除事件
//  * 
//  * TODO: 实现此处理器
//  * 步骤:
//  * 1. 获取现有订单 context.Order.get
//  * 2. 根据剩余数量判断是 CANCELLED 还是 FILLED
//  * 3. 更新订单状态
//  */
// Exchange.OrderRemoved.handler(async ({ event, context }) => {
//     console.log('TODO: Implement OrderRemoved handler');
// });

// /**
//  * 处理成交事件
//  * 
//  * TODO: 实现此处理器
//  * 这是最复杂的处理器，需要：
//  * 1. 创建 Trade 记录
//  * 2. 更新买卖双方的 Order 剩余数量
//  * 3. 更新 K 线数据 (Candle)
//  * 4. 更新买卖双方的 Position
//  */
// Exchange.TradeExecuted.handler(async ({ event, context }) => {
//     console.log('TODO: Implement TradeExecuted handler');

//     // 步骤 1: 创建 Trade 记录
//     // const trade: Trade = { ... };
//     // context.Trade.set(trade);

//     // 步骤 2: 更新订单
//     // const buyOrder = await context.Order.get(event.params.buyOrderId.toString());
//     // ...

//     // 步骤 3: 更新 K 线
//     // ...

//     // 步骤 4: 更新持仓
//     // await updatePosition(context, event.params.buyer, true, amount, price);
//     // await updatePosition(context, event.params.seller, false, amount, price);
// });

// /**
//  * 更新用户持仓
//  * 
//  * TODO: 实现此辅助函数
//  * 
//  * @param context - Envio context
//  * @param trader - 交易者地址
//  * @param isBuy - 是否为买入
//  * @param amount - 成交数量
//  * @param price - 成交价格
//  */
// async function updatePosition(
//     context: any,
//     trader: string,
//     isBuy: boolean,
//     amount: bigint,
//     price: bigint
// ) {
//     // TODO: 实现持仓更新逻辑
//     // 1. 获取现有持仓 context.Position.get(trader)
//     // 2. 如果是加仓，计算加权平均入场价
//     // 3. 如果是减仓，计算已实现盈亏
//     // 4. 更新持仓 context.Position.set
// }
