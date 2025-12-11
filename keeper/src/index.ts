import { PriceKeeper } from './services/PriceKeeper';
import { Liquidator } from './services/Liquidator';

async function main() {
    console.log('--- Monad Exchange Keeper Service ---');

    const priceKeeper = new PriceKeeper(1000); // Update every 1 second
    const liquidator = new Liquidator(5000);   // Check every 5 seconds

    priceKeeper.start();
    await liquidator.start();

    // Handle shutdown
    process.on('SIGINT', () => {
        console.log('\nShutting down...');
        priceKeeper.stop();
        liquidator.stop();
        process.exit(0);
    });
}

main().catch(console.error);
