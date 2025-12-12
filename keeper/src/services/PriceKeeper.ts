import { parseEther } from 'viem';
import { walletClient, publicClient } from '../client';
import { EXCHANGE_ABI } from '../abi';
import { EXCHANGE_ADDRESS as ADDRESS } from '../config';

/**
 * PriceKeeper Service - 脚手架版本
 * 
 * 这个服务负责定期更新交易所的指数价格。
 * 
 * TODO: 学生需要实现以下功能：
 * 1. 从 Pyth Network 获取 ETH/USD 价格
 * 2. 调用合约的 updateIndexPrice 函数更新价格
 */
export class PriceKeeper {
    private intervalId: NodeJS.Timeout | null = null;
    private currentPrice = 2700; // 默认价格
    private isRunning = false;

    // Pyth ETH/USD Price Feed ID
    private readonly PYTH_ETH_ID = '0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace';

    constructor(private intervalMs: number = 5000) { }

    start() {
        if (this.isRunning) return;
        this.isRunning = true;
        console.log(`[PriceKeeper] Starting price updates every ${this.intervalMs}ms...`);

        this.updatePrice();
        this.intervalId = setInterval(() => this.updatePrice(), this.intervalMs);
    }

    stop() {
        if (this.intervalId) {
            clearInterval(this.intervalId);
            this.intervalId = null;
        }
        this.isRunning = false;
        console.log('[PriceKeeper] Stopped.');
    }

    /**
     * 更新价格
     * 
     * TODO: 实现此函数
     * 步骤:
     * 1. 从 Pyth Hermes API 获取最新价格
     *    URL: https://hermes.pyth.network/v2/updates/price/latest?ids[]=${PYTH_ETH_ID}
     * 2. 解析价格 (注意 expo 指数)
     * 3. 调用合约的 updateIndexPrice
     */
    private async updatePrice() {
        try {
            // TODO: 从 Pyth 获取价格
            // const res = await fetch(`https://hermes.pyth.network/v2/updates/price/latest?ids[]=${this.PYTH_ETH_ID}`);
            // const data = await res.json();
            // 解析 data.parsed[0].price

            // 临时: 使用模拟价格
            console.log(`[PriceKeeper] TODO: Implement price fetching from Pyth`);
            console.log(`[PriceKeeper] Using mock price: ${this.currentPrice}`);

            // TODO: 调用合约更新价格
            // const priceWei = parseEther(this.currentPrice.toFixed(2));
            // const hash = await walletClient.writeContract({
            //     address: ADDRESS as `0x${string}`,
            //     abi: EXCHANGE_ABI,
            //     functionName: 'updateIndexPrice',
            //     args: [priceWei]
            // });

        } catch (e) {
            console.error('[PriceKeeper] Error updating price:', e);
        }
    }
}
