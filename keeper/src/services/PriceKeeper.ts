import { parseEther } from 'viem';
import { walletClient, publicClient } from '../client';
import { EXCHANGE_ABI } from '../abi';
import { EXCHANGE_ADDRESS as ADDRESS } from '../config';

export class PriceKeeper {
    private intervalId: NodeJS.Timeout | null = null;
    private currentPrice = 2700; // Start at 2700 (fallback)
    private isRunning = false;
    private readonly PYTH_ETH_ID = '0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace';

    constructor(private intervalMs: number = 5000) { }

    start() {
        if (this.isRunning) return;
        this.isRunning = true;
        console.log(`[PriceKeeper] Starting price updates every ${this.intervalMs}ms...`);

        // Initial fetch
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

    private async updatePrice() {
        try {
            // Try to fetch real price from Pyth
            try {
                const res = await fetch(`https://hermes.pyth.network/v2/updates/price/latest?ids[]=${this.PYTH_ETH_ID}`);
                if (res.ok) {
                    const data = await res.json() as any;
                    if (data?.parsed?.[0]?.price) {
                        const p = data.parsed[0].price;
                        const rawPrice = Number(p.price);
                        const expo = Number(p.expo);
                        // Calculate price: raw * 10^expo
                        this.currentPrice = rawPrice * (10 ** expo);
                        console.log(`[PriceKeeper] Fetched Pyth Price: ${this.currentPrice.toFixed(2)}`);
                    }
                }
            } catch (fetchError) {
                console.warn('[PriceKeeper] Pyth fetch failed, using fallback/random walk', fetchError);
                // Ignore fetch errors, fallback to random walk
                const change = (Math.random() - 0.5) * 0.002;
                this.currentPrice = this.currentPrice * (1 + change);
            }

            // Safety bounds (1000 - 5000)
            if (this.currentPrice < 1000) this.currentPrice = 1000;
            if (this.currentPrice > 5000) this.currentPrice = 5000;

            const priceWei = parseEther(this.currentPrice.toFixed(2));

            console.log(`[PriceKeeper] Updating Index Price to ${this.currentPrice.toFixed(2)}...`);

            const hash = await walletClient.writeContract({
                address: ADDRESS as `0x${string}`,
                abi: EXCHANGE_ABI,
                functionName: 'updateIndexPrice',
                args: [priceWei]
            });

            console.log(`[PriceKeeper] Tx sent: ${hash}`);

        } catch (e) {
            console.error('[PriceKeeper] Error updating price:', e);
        }
    }
}
