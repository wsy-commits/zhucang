import {
    Exchange,
    Trade,
    Candle,
    Order,
    Position,
    MarginEvent,
} from "../generated";

Exchange.MarginDeposited.handler(async ({ event, context }) => {
    const entity: MarginEvent = {
        id: `${event.transaction.hash}-${event.logIndex}`,
        trader: event.params.trader,
        amount: event.params.amount,
        eventType: "DEPOSIT",
        timestamp: event.block.timestamp,
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
        // If amount is 0, it was filled. If > 0, it was cancelled.
        // We update this logic in TradeExecuted, but here is the final cleanup.
        if (order.amount > 0n) {
            context.Order.set({ ...order, status: "CANCELLED" });
        } else {
            context.Order.set({ ...order, status: "FILLED" });
        }
    }
});

Exchange.TradeExecuted.handler(async ({ event, context }) => {
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

    // --- Update Orders ---
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

    // --- Update Candles (1m resolution) ---
    const resolution = "1m";
    const timestamp = event.block.timestamp - (event.block.timestamp % 60);
    const candleId = `${resolution}-${timestamp}`;
    const existingCandle = await context.Candle.get(candleId);

    // Get the latest candle state to link open price
    const latestCandleState = await context.LatestCandle.get("1");

    if (!existingCandle) {
        // If no candle exists for this minute, create one.
        // Use the close price of the last known candle as the open price, if available.
        // Otherwise (first trade ever), use the current price.
        const openPrice = latestCandleState ? latestCandleState.closePrice : event.params.price;

        const highPrice = event.params.price > openPrice ? event.params.price : openPrice;
        const lowPrice = event.params.price < openPrice ? event.params.price : openPrice;

        const candle: Candle = {
            id: candleId,
            resolution,
            timestamp,
            openPrice: openPrice,
            highPrice: highPrice,
            lowPrice: lowPrice,
            closePrice: event.params.price,
            volume: event.params.amount,
        };

        context.Candle.set(candle);
        context.Candle.set(candle);
    } else {
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

    // Update the global latest candle state
    context.LatestCandle.set({
        id: "1",
        closePrice: event.params.price,
        timestamp: event.block.timestamp
    });

    // --- Update Positions ---
    await updatePosition(context, event.params.buyer, true, event.params.amount, event.params.price);
    await updatePosition(context, event.params.seller, false, event.params.amount, event.params.price);
});

async function updatePosition(context: any, trader: string, isBuy: boolean, amount: bigint, price: bigint) {
    const existingPosition = await context.Position.get(trader);
    let position: any;

    if (!existingPosition) {
        position = {
            id: trader,
            trader,
            size: 0n,
            entryPrice: 0n,
            realizedPnl: 0n,
        };
    } else {
        position = { ...existingPosition };
    }

    const signedAmount = isBuy ? amount : -amount;
    const currentSize = position.size;

    // If increasing position (or opening new)
    if (currentSize === 0n || (currentSize > 0n && isBuy) || (currentSize < 0n && !isBuy)) {
        const totalSize = currentSize + signedAmount;
        const absTotalSize = totalSize > 0n ? totalSize : -totalSize;
        const absCurrentSize = currentSize > 0n ? currentSize : -currentSize;

        // Weighted Average Entry Price
        // (oldSize * oldEntry + newAmt * newPrice) / totalSize
        if (absTotalSize > 0n) {
            // Ensure all operands are bigints
            const oldVal = BigInt(absCurrentSize) * BigInt(position.entryPrice);
            const newVal = BigInt(amount) * BigInt(price);
            position.entryPrice = (oldVal + newVal) / BigInt(absTotalSize);
        } else {
            position.entryPrice = 0n;
        }
        position.size = totalSize;
    } else {
        // Closing position
        // PnL = (price - entry) * amount (for long)
        // PnL = (entry - price) * amount (for short)
        const absCurrentSize = currentSize > 0n ? currentSize : -currentSize;
        const closeAmount = amount > absCurrentSize ? absCurrentSize : amount; // Cannot close more than we have

        let pnl = 0n;
        if (currentSize > 0n) { // Closing Long
            pnl = ((price - position.entryPrice) * closeAmount) / (10n ** 18n);
        } else { // Closing Short
            pnl = ((position.entryPrice - price) * closeAmount) / (10n ** 18n);
        }

        position.realizedPnl += pnl;
        position.size += signedAmount;

        if (position.size === 0n) {
            position.entryPrice = 0n;
        }
    }

    context.Position.set(position);
}
