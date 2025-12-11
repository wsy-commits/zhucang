import React, { useMemo, useState } from 'react';
import { formatEther } from 'viem';
import { observer } from 'mobx-react-lite';
import { useExchangeStore } from '../store/exchangeStore';
import { OrderSide } from '../types';

export const Positions: React.FC = observer(() => {
  const [activeTab, setActiveTab] = useState('positions');
  const { account, position, margin, markPrice, trades, myOrders, syncing, refresh, cancelOrder } = useExchangeStore();
  const store = useExchangeStore();

  const displayPosition = useMemo(() => {
    if (!position || position.size === 0n) return undefined;
    // Use formatEther to convert from wei to ETH units for display
    const entry = Number(formatEther(position.entryPrice));
    const mark = markPrice > 0n ? Number(formatEther(markPrice)) : entry;
    const size = Number(formatEther(position.size));
    const absSize = Math.abs(size);

    const unrealized = (mark - entry) * size;
    const realized = Number(formatEther(position.realizedPnl));
    const pnl = unrealized + realized;

    // Margin is in ETH (100). PnL is in ETH.
    // margin in store is freeMargin.
    const freeMargin = Number(formatEther(margin));
    const effectiveMargin = freeMargin + realized;
    const mmRatio = 0.005; // 0.5% maintenance margin

    let liqPrice = 0;
    if (size > 0) {
      // Long: (Entry * Size - Margin) / (Size * (1 - MM))
      // Derived from: Margin + (Price - Entry)*Size = Price*Size*MM
      // Margin - Entry*Size = Price*Size*MM - Price*Size = Price*Size*(MM - 1)
      // Price = (Margin - Entry*Size) / (Size * (MM - 1))
      //       = (Entry*Size - Margin) / (Size * (1 - MM))
      const numerator = entry * size - effectiveMargin;
      const denominator = size * (1 - mmRatio);
      liqPrice = numerator / denominator;
      if (liqPrice < 0) liqPrice = 0;
    } else {
      // Short: (Margin + Entry * SizeAbs) / (SizeAbs * (1 + MM))
      // Derived from: Margin + (Entry - Price)*SizeAbs = Price*SizeAbs*MM
      // Margin + Entry*SizeAbs = Price*SizeAbs*MM + Price*SizeAbs = Price*SizeAbs*(1 + MM)
      // Price = (Margin + Entry*SizeAbs) / (SizeAbs * (1 + MM))
      const numerator = effectiveMargin + entry * absSize;
      const denominator = absSize * (1 + mmRatio);
      liqPrice = numerator / denominator;
    }

    const totalMargin = Number(formatEther(margin));

    // ROI Calculation (Return on Initial Margin)
    // Initial Margin = Position Value * Initial Margin Rate
    // We use the store's initialMarginBps (default 100 = 1%)
    const imBps = Number(store.initialMarginBps);
    const positionValue = entry * absSize;
    const initialMargin = positionValue * (imBps / 10000);

    const pnlPercent = initialMargin > 0 ? (pnl / initialMargin) * 100 : 0;

    return {
      symbol: 'ETH',
      leverage: undefined,
      size: absSize,
      entryPrice: entry,
      markPrice: mark,
      liqPrice,
      pnl,
      pnlPercent,
      side: size >= 0 ? 'long' : 'short',
    };
  }, [margin, markPrice, position, store.initialMarginBps]);

  const myTrades = useMemo(() => {
    const viewer = account?.toLowerCase();
    return trades.filter((t) =>
      viewer ? t.buyer?.toLowerCase() === viewer || t.seller?.toLowerCase() === viewer : true,
    );
  }, [account, trades]);

  return (
    <div className="bg-[#10121B] rounded-xl border border-white/5 p-4 h-full flex flex-col">
      <div className="flex items-center space-x-6 border-b border-white/5 pb-2 mb-4">
        {['Positions', 'Open Orders', 'History'].map(tab => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab.toLowerCase().replace(' ', ''))}
            className={`text-sm font-medium pb-2 -mb-2.5 transition-colors border-b-2 ${activeTab === tab.toLowerCase().replace(' ', '')
              ? 'text-white border-nebula-violet'
              : 'text-gray-500 border-transparent hover:text-gray-300'
              }`}
          >
            {tab}
          </button>
        ))}
        <div className="flex-1" />
        <button
          onClick={refresh}
          className="text-[10px] px-2 py-1 rounded bg-white/5 text-gray-400 hover:text-white"
        >
          {syncing ? 'Syncing…' : 'Refresh'}
        </button>
      </div>

      <div className="overflow-x-auto">
        {activeTab === 'positions' && (
          <>
            <table className="w-full text-left">
              <thead>
                <tr className="text-[10px] text-gray-500 uppercase tracking-wider">
                  <th className="pb-3 pl-2">Symbol</th>
                  <th className="pb-3 text-right">Size</th>
                  <th className="pb-3 text-right">Entry Price</th>
                  <th className="pb-3 text-right">Mark Price</th>
                  <th className="pb-3 text-right">Liq. Price</th>
                  <th className="pb-3 text-right">PnL (ROE%)</th>
                </tr>
              </thead>
              <tbody className="text-sm">
                {displayPosition && (
                  <tr className="border-b border-white/5 last:border-0 hover:bg-white/5 transition-colors">
                    <td className="py-3 pl-2">
                      <div className="flex items-center space-x-2">
                        <div className={`w-1 h-8 rounded-full ${displayPosition.side === 'long' ? 'bg-nebula-teal' : 'bg-nebula-pink'}`} />
                        <div>
                          <div className="font-bold text-gray-200">{displayPosition.symbol}</div>
                          <div className={`text-[10px] font-mono ${displayPosition.side === 'long' ? 'text-nebula-teal' : 'text-nebula-pink'}`}>
                            {displayPosition.side.toUpperCase()}
                          </div>
                        </div>
                      </div>
                    </td>
                    <td className="py-3 text-right font-mono text-gray-300">
                      {displayPosition.size.toLocaleString('en-US', { minimumFractionDigits: 2 })} {displayPosition.symbol}
                    </td>
                    <td className="py-3 text-right font-mono text-gray-300">{displayPosition.entryPrice.toLocaleString()}</td>
                    <td className="py-3 text-right font-mono text-gray-300">{displayPosition.markPrice.toLocaleString()}</td>
                    <td className="py-3 text-right font-mono text-nebula-orange">{displayPosition.liqPrice.toLocaleString(undefined, { maximumFractionDigits: 2 })}</td>
                    <td className="py-3 text-right font-mono">
                      <div className={displayPosition.pnl >= 0 ? 'text-nebula-teal' : 'text-nebula-pink'}>
                        {displayPosition.pnl >= 0 ? '+' : ''}
                        {displayPosition.pnl.toFixed(2)} MON
                      </div>
                      <div className={`text-[10px] ${displayPosition.pnl >= 0 ? 'text-nebula-teal/70' : 'text-nebula-pink/70'}`}>
                        {displayPosition.pnlPercent >= 0 ? '+' : ''}
                        {displayPosition.pnlPercent.toFixed(2)}%
                      </div>
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
            {!displayPosition && (
              <div className="flex flex-col items-center justify-center py-12 text-gray-600">
                <p>No open positions</p>
              </div>
            )}
          </>
        )}

        {activeTab === 'openorders' && (
          <table className="w-full text-left">
            <thead>
              <tr className="text-[10px] text-gray-500 uppercase tracking-wider">
                <th className="pb-3 pl-2">Id</th>
                <th className="pb-3 text-right">Side</th>
                <th className="pb-3 text-right">Price</th>
                <th className="pb-3 text-right">Progress</th>
                <th className="pb-3 text-right">Placed</th>
                <th className="pb-3 text-right pr-2">Action</th>
              </tr>
            </thead>
            <tbody className="text-sm">
              {myOrders.map((o) => (
                <tr key={o.id.toString()} className="border-b border-white/5 last:border-0 hover:bg-white/5 transition-colors">
                  <td className="py-3 pl-2 font-mono text-gray-300">#{o.id.toString()}</td>
                  <td className="py-3 text-right font-mono">
                    <span className={o.isBuy ? 'text-nebula-teal' : 'text-nebula-pink'}>
                      {o.isBuy ? 'BUY' : 'SELL'}
                    </span>
                  </td>
                  <td className="py-3 text-right font-mono text-gray-300">{Number(formatEther(o.price)).toLocaleString()}</td>
                  <td className="py-3 text-right font-mono text-gray-300">
                    <div className="flex flex-col items-end gap-1">
                      <span className="text-xs">
                        {formatEther(BigInt(o.initialAmount) - BigInt(o.amount))} / {formatEther(BigInt(o.initialAmount))} ETH
                      </span>
                      <div className="w-24 h-1.5 bg-gray-700 rounded-full overflow-hidden">
                        <div
                          className={`h-full rounded-full ${o.isBuy ? 'bg-nebula-teal' : 'bg-nebula-pink'}`}
                          style={{ width: `${Math.min(100, ((Number(o.initialAmount) - Number(o.amount)) / Number(o.initialAmount)) * 100)}%` }}
                        />
                      </div>
                    </div>
                  </td>
                  <td className="py-3 text-right font-mono text-gray-500">
                    {new Date(Number(o.timestamp) * 1000).toLocaleTimeString()}
                  </td>
                  <td className="py-3 text-right pr-2">
                    <button
                      onClick={() => store.cancelOrder(o.id)}
                      className="text-[10px] px-2 py-1 rounded bg-red-500/10 text-red-400 hover:bg-red-500/20 transition-colors"
                    >
                      Cancel
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
            {myOrders.length === 0 && (
              <tbody>
                <tr>
                  <td colSpan={6} className="text-center text-gray-600 py-8">No open orders</td> {/* colSpan updated to 6 */}
                </tr>
              </tbody>
            )}
          </table>
        )}

        {activeTab === 'history' && (
          <table className="w-full text-left">
            <thead>
              <tr className="text-[10px] text-gray-500 uppercase tracking-wider">
                <th className="pb-3 pl-2">Side</th>
                <th className="pb-3 text-right">Price</th>
                <th className="pb-3 text-right">Amount</th>
                <th className="pb-3 text-right">Time</th>
              </tr>
            </thead>
            <tbody className="text-sm">
              {myTrades.map((t) => (
                <tr key={t.id} className="border-b border-white/5 last:border-0 hover:bg-white/5 transition-colors">
                  <td className="py-3 pl-2 font-mono">
                    <span className={t.side === OrderSide.BUY ? 'text-nebula-teal' : 'text-nebula-pink'}>
                      {t.side.toUpperCase()}
                    </span>
                  </td>
                  <td className="py-3 text-right font-mono text-gray-300">{t.price.toLocaleString()}</td>
                  <td className="py-3 text-right font-mono text-gray-300">{t.amount.toLocaleString()} ETH</td>
                  <td className="py-3 text-right font-mono text-gray-500">{t.time || '--'}</td>
                </tr>
              ))}
            </tbody>
            {myTrades.length === 0 && (
              <tbody>
                <tr>
                  <td colSpan={4} className="text-center text-gray-600 py-8">No fills yet</td>
                </tr>
              </tbody>
            )}
          </table>
        )}
      </div>
    </div>
  );
});
