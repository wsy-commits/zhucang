import {
    Exchange,
    Trade,
    Candle,
    Order,
    Position,
    MarginEvent,
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
    console.log('TODO: Implement MarginDeposited handler');
    // const entity: MarginEvent = {
    //     id: `${event.transaction.hash}-${event.logIndex}`,
    //     trader: event.params.trader,
    //     amount: event.params.amount,
    //     eventType: "DEPOSIT",
    //     timestamp: event.block.timestamp,
    // };
    // context.MarginEvent.set(entity);
});

/**
 * 处理保证金提现事件
 */
Exchange.MarginWithdrawn.handler(async ({ event, context }) => {
    console.log('TODO: Implement MarginWithdrawn handler');
});

/**
 * 处理订单创建事件
 * 
 * TODO: 实现此处理器
 * 步骤:
 * 1. 从 event.params 获取订单信息
 * 2. 创建 Order 实体，status 设为 "OPEN"
 * 3. 使用 context.Order.set 保存
 */
Exchange.OrderPlaced.handler(async ({ event, context }) => {
    console.log('TODO: Implement OrderPlaced handler');
});

/**
 * 处理订单移除事件
 * 
 * TODO: 实现此处理器
 * 步骤:
 * 1. 获取现有订单 context.Order.get
 * 2. 根据剩余数量判断是 CANCELLED 还是 FILLED
 * 3. 更新订单状态
 */
Exchange.OrderRemoved.handler(async ({ event, context }) => {
    console.log('TODO: Implement OrderRemoved handler');
});

/**
 * 处理成交事件
 * 
 * TODO: 实现此处理器
 * 这是最复杂的处理器，需要：
 * 1. 创建 Trade 记录
 * 2. 更新买卖双方的 Order 剩余数量
 * 3. 更新 K 线数据 (Candle)
 * 4. 更新买卖双方的 Position
 */
Exchange.TradeExecuted.handler(async ({ event, context }) => {
    console.log('TODO: Implement TradeExecuted handler');

    // 步骤 1: 创建 Trade 记录
    // const trade: Trade = { ... };
    // context.Trade.set(trade);

    // 步骤 2: 更新订单
    // const buyOrder = await context.Order.get(event.params.buyOrderId.toString());
    // ...

    // 步骤 3: 更新 K 线
    // ...

    // 步骤 4: 更新持仓
    // await updatePosition(context, event.params.buyer, true, amount, price);
    // await updatePosition(context, event.params.seller, false, amount, price);
});

/**
 * 更新用户持仓
 * 
 * TODO: 实现此辅助函数
 * 
 * @param context - Envio context
 * @param trader - 交易者地址
 * @param isBuy - 是否为买入
 * @param amount - 成交数量
 * @param price - 成交价格
 */
async function updatePosition(
    context: any,
    trader: string,
    isBuy: boolean,
    amount: bigint,
    price: bigint
) {
    // TODO: 实现持仓更新逻辑
    // 1. 获取现有持仓 context.Position.get(trader)
    // 2. 如果是加仓，计算加权平均入场价
    // 3. 如果是减仓，计算已实现盈亏
    // 4. 更新持仓 context.Position.set
}
