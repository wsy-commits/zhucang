import { formatEther } from 'viem';
import { walletClient, publicClient } from '../client';
import { EXCHANGE_ABI } from '../abi';
import { EXCHANGE_ADDRESS as ADDRESS } from '../config';

export class Liquidator {
    private intervalId: NodeJS.Timeout | null = null;
    private isRunning = false;
    // Simple in-memory set of active traders. 
    // In production, this should be a DB or synced from Indexer.
    private activeTraders = new Set<string>();

    constructor(private intervalMs: number = 10000) { }

    async start() {
        if (this.isRunning) return;
        this.isRunning = true;
        console.log(`[Liquidator] Starting liquidation checks every ${this.intervalMs}ms...`);

        // Initial scan (simplified: just listen for new events for now, 
        // or we could query the indexer if we had one connected here. 
        // For this demo, we'll rely on catching new events or manual addition)
        this.watchEvents();

        // DEBUG: Manually add Carol
        this.activeTraders.add("0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC");

        this.intervalId = setInterval(() => this.checkHealth(), this.intervalMs);
    }

    stop() {
        if (this.intervalId) {
            clearInterval(this.intervalId);
            this.intervalId = null;
        }
        this.isRunning = false;
        console.log('[Liquidator] Stopped.');
    }

    private watchEvents() {
        // Watch for OrderPlaced to find active traders
        publicClient.watchContractEvent({
            address: ADDRESS as `0x${string}`,
            abi: EXCHANGE_ABI,
            eventName: 'OrderPlaced',
            onLogs: logs => {
                logs.forEach(log => {
                    const trader = log.args.trader;
                    if (trader && !this.activeTraders.has(trader)) {
                        console.log(`[Liquidator] Found new trader: ${trader}`);
                        this.activeTraders.add(trader);
                    }
                });
            }
        });

        // Watch for TradeExecuted
        publicClient.watchContractEvent({
            address: ADDRESS as `0x${string}`,
            abi: EXCHANGE_ABI,
            eventName: 'TradeExecuted',
            onLogs: logs => {
                logs.forEach(log => {
                    if (log.args.buyer) this.activeTraders.add(log.args.buyer);
                    if (log.args.seller) this.activeTraders.add(log.args.seller);
                });
            }
        });
    }

    private async checkHealth() {
        if (this.activeTraders.size === 0) return;

        console.log(`[Liquidator] Checking health for ${this.activeTraders.size} traders...`);

        for (const trader of this.activeTraders) {
            try {
                const margin = await publicClient.readContract({
                    address: ADDRESS as `0x${string}`,
                    abi: EXCHANGE_ABI,
                    functionName: 'margin',
                    args: [trader as `0x${string}`]
                }) as bigint;

                const position = await publicClient.readContract({
                    address: ADDRESS as `0x${string}`,
                    abi: EXCHANGE_ABI,
                    functionName: 'getPosition',
                    args: [trader as `0x${string}`]
                });

                // const [freeMargin, lockedMargin, position] = account;

                // Simplified Health Check Logic (Mirroring Contract)
                // Note: Real logic needs Mark Price.
                // We can fetch Mark Price or just try to liquidate if we suspect.
                // Let's just try to liquidate if they have a position and low margin?
                // Or better, let's implement the health calc.

                if (position.size === 0n) continue;

                // If we want to be precise, we need Mark Price.
                // For this demo, we'll just blindly try to liquidate everyone with a position 
                // who has very low margin, or just rely on the contract to revert if healthy.
                // But sending txs costs gas.

                // Let's just try to liquidate everyone with a position for now to demonstrate the bot works.
                // In a real bot, you'd calculate:
                // Margin = Free + Locked + PnL
                // Maintenance = PositionValue * MaintenanceMarginBps
                // If Margin < Maintenance -> Liquidate

                // For now, let's just log.
                // console.log(`[Liquidator] Trader ${trader}: Size ${formatEther(position.size)}`);

                // Attempt liquidation (will fail if healthy)
                // To avoid spamming, only try if we have a reason.
                // But user asked for a bot. Let's make it aggressive for the demo.

                // Actually, let's only try if we haven't checked recently? 
                // Or just try.

                // console.log(`[Liquidator] Attempting to liquidate ${trader}...`);
                try {
                    // Calculate absolute size for full liquidation
                    const size = position.size > 0n ? position.size : -position.size;

                    // Simulate call first to avoid gas waste
                    await publicClient.simulateContract({
                        account: walletClient.account,
                        address: ADDRESS as `0x${string}`,
                        abi: EXCHANGE_ABI,
                        functionName: 'liquidate',
                        args: [trader as `0x${string}`, size] as any
                    });

                    // If simulation succeeds, send it!
                    console.log(`[Liquidator] !!! LIQUIDATABLE POSITION FOUND: ${trader} !!!`);
                    const hash = await walletClient.writeContract({
                        address: ADDRESS as `0x${string}`,
                        abi: EXCHANGE_ABI,
                        functionName: 'liquidate',
                        args: [trader as `0x${string}`, size] as any
                    });
                    console.log(`[Liquidator] Liquidation Tx Sent: ${hash}`);

                } catch (e) {
                    // Expected for healthy positions
                    // console.debug(`[Liquidator] ${trader} is healthy.`);
                }

            } catch (e) {
                console.error(`[Liquidator] Error checking ${trader}:`, e);
            }
        }
    }
}
