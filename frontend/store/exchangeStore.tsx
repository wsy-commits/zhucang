import React, { createContext, useContext, useEffect } from 'react';
import { makeAutoObservable, runInAction } from 'mobx';
import { Address, Hash, parseAbiItem, parseEther, formatEther } from 'viem';
import { EXCHANGE_ABI } from '../onchain/abi';
import { EXCHANGE_ADDRESS, EXCHANGE_DEPLOY_BLOCK } from '../onchain/config';
import { chain, getWalletClient, publicClient, fallbackAccount, ACCOUNTS } from '../onchain/client';
import { OrderBookItem, OrderSide, OrderType, PositionSnapshot, Trade, CandleData, MarginMode } from '../types';
// Day 2 TODO: 取消注释以启用 IndexerClient
// import { client, GET_CANDLES, GET_RECENT_TRADES, GET_POSITIONS, GET_OPEN_ORDERS, GET_MY_TRADES } from './IndexerClient';

type OrderStruct = {
  id: bigint;
  trader: Address;
  isBuy: boolean;
  price: bigint;
  amount: bigint;
  initialAmount: bigint;
  timestamp: bigint;
  next: bigint;
};

type OrderBookState = {
  bids: OrderBookItem[];
  asks: OrderBookItem[];
};

export type OpenOrder = {
  id: bigint;
  isBuy: boolean;
  price: bigint;
  amount: bigint;
  initialAmount: bigint;
  timestamp: bigint;
  trader: Address;
};

class ExchangeStore {
  account?: Address;
  accountIndex = 0; // New observable state
  margin = 0n;
  crossMargin = 0n;        // ✅ 新增：全仓保证金
  marginMode = MarginMode.CROSS;  // ✅ 新增：当前保证金模式
  isolatedMargin = 0n;    // ✅ 新增：逐仓保证金

  position?: PositionSnapshot;
  markPrice = 0n;
  indexPrice = 0n;
  initialMarginBps = 100n; // Default 1%
  fundingRate = 0; // Estimated hourly funding rate
  orderBook: OrderBookState = { bids: [], asks: [] };
  trades: Trade[] = [];
  candles: CandleData[] = [];
  myOrders: OpenOrder[] = [];
  myTrades: Trade[] = [];
  syncing = false;
  cancellingOrderId?: bigint; // Day 2: 正在取消的订单 ID
  error?: string;
  walletClient = getWalletClient();

  constructor() {
    makeAutoObservable(this);
    this.autoConnect();
    this.refresh();
    // 定时刷新（静默模式，不触发 syncing 状态变化）
    setInterval(() => {
      this.refresh(true).catch(() => { });
    }, 500);
    console.info('[store] 交易所 store 初始化完成');
  }

  ensureContract() {
    if (!EXCHANGE_ADDRESS) throw new Error('Set VITE_EXCHANGE_ADDRESS');
    return EXCHANGE_ADDRESS;
  }

  autoConnect = async () => {
    // Check URL params first
    const params = new URLSearchParams(window.location.search);
    const urlAccount = params.get('account');
    if (urlAccount && urlAccount.startsWith('0x')) {
      runInAction(() => (this.account = urlAccount as Address));
      return;
    }

    if (fallbackAccount) {
      runInAction(() => (this.account = fallbackAccount.address));
      return;
    }

  };

  connectWallet = async () => {
    if (!this.walletClient) {
      runInAction(() => (this.error = 'No wallet configured'));
      return;
    }
    if ((this.walletClient as any).account?.address) {
      runInAction(() => (this.account = (this.walletClient as any).account.address));
    } else if (fallbackAccount) {
      runInAction(() => (this.account = fallbackAccount.address));
    }
  };

  switchAccount = () => {
    this.accountIndex = (this.accountIndex + 1) % ACCOUNTS.length;
    const newAccount = ACCOUNTS[this.accountIndex];
    this.walletClient = getWalletClient(newAccount);
    runInAction(() => {
      this.account = newAccount.address;
      this.refresh();
    });
  };

  mapOrder(data: any): OrderStruct {
    // 优先检查命名属性（viem 通常返回带命名属性的数组）
    if (data && typeof data.price !== 'undefined') {
      return {
        id: data.id,
        trader: data.trader,
        isBuy: data.isBuy,
        price: data.price,
        amount: data.amount,
        initialAmount: data.initialAmount,
        timestamp: data.timestamp,
        next: data.next,
      };
    }

    if (Array.isArray(data)) {
      return {
        id: data[0],
        trader: data[1],
        isBuy: data[2],
        price: data[3],
        amount: data[4],
        initialAmount: data[5],
        timestamp: data[6],
        next: data[7],
      };
    }
    return data as OrderStruct;
  }

  loadOrderChain = async (headId?: bigint | null) => {
    const head: OrderStruct[] = [];
    if (!headId || headId === 0n) return head;
    const visited = new Set<string>();
    let current: bigint | undefined | null = headId;
    for (let i = 0; i < 128 && typeof current === 'bigint' && current !== 0n; i++) {
      if (visited.has(current.toString())) break;
      visited.add(current.toString());
      const raw = await publicClient.readContract({
        abi: EXCHANGE_ABI,
        address: this.ensureContract(),
        functionName: 'orders',
        args: [current],
      } as any);
      const data = this.mapOrder(raw);
      if (data.id === 0n) break;
      head.push(data);
      current = data.next;
    }
    return head;
  };

  formatOrderBook = (orders: OrderStruct[], isBuy: boolean): OrderBookItem[] => {
    // 1. Filter valid orders
    const filtered = orders.filter((o) => o.isBuy === isBuy && o.amount > 0n);

    // 2. Aggregate by price
    const aggregated = new Map<number, number>();
    filtered.forEach((o) => {
      const price = Number(formatEther(o.price));
      const size = Number(formatEther(o.amount));
      aggregated.set(price, (aggregated.get(price) || 0) + size);
    });

    // 3. Convert to array
    const rows = Array.from(aggregated.entries()).map(([price, size]) => ({
      price,
      size,
      total: 0,
      depth: 0,
    }));

    // 4. Sort: Bids Descending / Asks Ascending
    rows.sort((a, b) => (isBuy ? b.price - a.price : a.price - b.price));

    // 5. Calculate cumulative total
    let running = 0;
    const result = rows.map((r) => {
      running += r.size;
      return { ...r, total: running };
    });

    // 6. Calculate relative depth
    const maxTotal = result.length > 0 ? result[result.length - 1].total : 0;
    return result.map((r) => ({
      ...r,
      depth: maxTotal > 0 ? Math.min(100, Math.round((r.total / maxTotal) * 100)) : 0,
    }));
  };

  // ============================================
  // Day 5 TODO: 从 Indexer 获取 K 线数据
  // ============================================
  loadCandles = async () => {
    // ✅ 只生成一次，避免重复
    if (this.candles.length > 0) {
      console.log('[loadCandles] Using cached candles:', this.candles.length);
      return;
    }

    const now = Date.now();
    const basePrice = Number(formatEther(this.markPrice || 1000n));
    const mockCandles: CandleData[] = [];

    // ✅ 生成最近 100 根 15 分钟 K 线
    // 按时间升序：从早到晚（i=0 是最早，i=100 是最新）
    for (let i = 0; i <= 100; i++) {
      const time = new Date(now - (100 - i) * 15 * 60 * 1000);
      const volatility = 0.02; // 2% 波动
      const open = basePrice * (1 + (Math.random() - 0.5) * volatility);
      const close = open * (1 + (Math.random() - 0.5) * volatility);
      const high = Math.max(open, close) * (1 + Math.random() * 0.01);
      const low = Math.min(open, close) * (1 - Math.random() * 0.01);

      mockCandles.push({
        time: time.toISOString(),
        open: open.toFixed(2),
        high: high.toFixed(2),
        low: low.toFixed(2),
        close: close.toFixed(2),
        volume: (Math.random() * 100).toFixed(2),
      });
    }

    // 🔍 详细验证数据顺序
    const firstTime = new Date(mockCandles[0].time).getTime();
    const secondTime = new Date(mockCandles[1].time).getTime();
    const lastTime = new Date(mockCandles[mockCandles.length - 1].time).getTime();

    console.log('=== 🕊️ CANDLE DATA VERIFICATION ===');
    console.log('Total candles:', mockCandles.length);
    console.log('First candle (index 0):', mockCandles[0].time, 'timestamp:', firstTime);
    console.log('Second candle (index 1):', mockCandles[1].time, 'timestamp:', secondTime);
    console.log('Last candle (index 100):', mockCandles[100].time, 'timestamp:', lastTime);
    console.log('Order check:', firstTime < secondTime ? '✅ ASCENDING (correct)' : '❌ DESCENDING (wrong!)');
    console.log('=====================================');

    runInAction(() => {
      this.candles = mockCandles;
    });
  };

  // ============================================
  // Day 5 TODO: 从 Indexer 获取最近成交
  // ============================================
  loadTrades = async (): Promise<Trade[]> => {
    // 临时生成模拟交易数据（实际应该从 Indexer 获取）
    if (this.trades.length > 0) return this.trades;

    const now = Date.now();
    const basePrice = Number(formatEther(this.markPrice || 1000n));
    const mockTrades: Trade[] = [];

    // 生成最近 20 笔交易
    for (let i = 0; i < 20; i++) {
      const time = new Date(now - i * 30000); // 每 30 秒一笔
      const price = basePrice * (1 + (Math.random() - 0.5) * 0.001);
      const amount = Math.random() * 10;
      const isBuy = Math.random() > 0.5;

      mockTrades.push({
        id: `trade-${i}`,
        price: price.toFixed(2),
        amount: amount.toFixed(4),
        time: time.toLocaleTimeString(),
        side: isBuy ? 'buy' : 'sell',
      });
    }

    runInAction(() => {
      this.trades = mockTrades;
    });

    console.log('[loadTrades] Generated mock trades:', mockTrades.length);
    return mockTrades;
  };

  // ============================================
  // Day 2 TODO: 从 Indexer 获取用户订单
  // ============================================
  loadMyOrders = async (trader: Address): Promise<OpenOrder[]> => {
    // TODO: Day 2 - 实现从 Indexer 获取用户 OPEN 状态的订单
    return [];
  };

  // ============================================
  // Day 5 TODO: 从 Indexer 获取用户的成交历史
  // ============================================
  loadMyTrades = async (trader: Address): Promise<Trade[]> => {
    // TODO: Day 5 - 实现从 Indexer 获取用户成交历史
    return [];
  };

  refresh = async (silent = false) => {
  try {
    if (!silent) {
      runInAction(() => {
        this.syncing = true;
        this.error = undefined;
      });
    }

    const address = this.ensureContract();

    const [mark, index, bestBid, bestAsk, imBps] = await Promise.all([
      publicClient.readContract({ abi: EXCHANGE_ABI, address, functionName: 'markPrice' } as any),
      publicClient.readContract({ abi: EXCHANGE_ABI, address, functionName: 'indexPrice' } as any),
      publicClient.readContract({ abi: EXCHANGE_ABI, address, functionName: 'bestBuyId' } as any),
      publicClient.readContract({ abi: EXCHANGE_ABI, address, functionName: 'bestSellId' } as any),
      publicClient.readContract({ abi: EXCHANGE_ABI, address, functionName: 'initialMarginBps' } as any),
    ]) as bigint[];

    runInAction(() => {
      this.markPrice = mark;
      this.indexPrice = index;
      this.initialMarginBps = imBps;

      // Day 6: Calculate funding rate
      const m = Number(formatEther(mark));
      const i = Number(formatEther(index));
      const premiumIndex = (m - i) / i;
      const interestRate = 0.0001; // 0.01%
      const clampRange = 0.0005;   // 0.05%

      let diff = interestRate - premiumIndex;
      if (diff > clampRange) diff = clampRange;
      if (diff < -clampRange) diff = -clampRange;

      this.fundingRate = premiumIndex + diff;
    });

    if (this.account) {
      const [m, mode, isolated, pos] = await Promise.all([
        publicClient.readContract({
          abi: EXCHANGE_ABI,
          address,
          functionName: 'getCrossMargin',
          args: [this.account],
        } as any) as Promise<bigint>,
        publicClient.readContract({
          abi: EXCHANGE_ABI,
          address,
          functionName: 'getMarginMode',
          args: [this.account],
        } as any) as Promise<number>,
        publicClient.readContract({
          abi: EXCHANGE_ABI,
          address,
          functionName: 'getIsolatedMargin',
          args: [this.account],
        } as any) as Promise<bigint>,
        publicClient.readContract({
          abi: EXCHANGE_ABI,
          address,
          functionName: 'getPosition',
          args: [this.account],
        } as any) as Promise<PositionSnapshot>,
      ]);

      runInAction(() => {
        this.margin = m;
        this.crossMargin = m;
        this.marginMode = mode;
        this.isolatedMargin = isolated;
        this.position = { ...pos, mode, isolatedMargin: isolated };
      });
    }

      let bidsRaw: OrderStruct[] = [];
      let asksRaw: OrderStruct[] = [];
      try {
        [bidsRaw, asksRaw] = await Promise.all([this.loadOrderChain(bestBid), this.loadOrderChain(bestAsk)]);
      } catch (inner) {
        const msg = (inner as Error)?.message || 'Failed to load orderbook';
        console.error('[orderbook] loadOrderChain error', msg);
        runInAction(() => (this.error = msg));
      }

      const scanned: OrderStruct[] = [];
      const SCAN_LIMIT = 20;
      for (let i = 1; i <= SCAN_LIMIT; i++) {
        try {
          const id = BigInt(i);
          const raw = await publicClient.readContract({
            abi: EXCHANGE_ABI,
            address,
            functionName: 'orders',
            args: [id],
          } as any);
          const data = this.mapOrder(raw);
          console.debug('[orderbook] slot', i, data);
          if (data.id !== 0n) scanned.push(data);
        } catch (inner) {
          console.error('[orderbook] scan error', i.toString(), (inner as Error)?.message);
          break;
        }
      }
      console.debug(
        '[orderbook] scanned raw',
        scanned.map((o) => ({
          id: o.id.toString(),
          p: o.price.toString(),
          a: o.amount.toString(),
          isBuy: o.isBuy,
          next: o.next.toString(),
        })),
      );
      const merged = new Map<bigint, OrderStruct>();
      [...bidsRaw, ...asksRaw, ...scanned].forEach((o) => {
        if (o && o.id) merged.set(o.id, o);
      });
      const allOrders = Array.from(merged.values());
      const bids = allOrders.filter((o) => o.isBuy && o.amount > 0n);
      const asks = allOrders.filter((o) => !o.isBuy && o.amount > 0n);
      console.debug('[orderbook] bids/asks', {
        bids: bids.map((o) => ({ id: o.id.toString(), p: o.price.toString(), a: o.amount.toString() })),
        asks: asks.map((o) => ({ id: o.id.toString(), p: o.price.toString(), a: o.amount.toString() })),
        merged: merged.size,
      });
      runInAction(() => {
        this.orderBook = { bids: this.formatOrderBook(bids, true), asks: this.formatOrderBook(asks, false) };
      });

      // Load Trades (Day 5)
       await this.loadTrades();

      // Load Candles (Day 5)
       this.loadCandles();

      // ============================================
      // Day 2 TODO: 从 Indexer 获取我的订单
      // ============================================
     // Day 2: 从 Indexer 获取我的订单
     if (this.account) {
     const orders = await this.loadMyOrders(this.account);
     runInAction(() => {
     this.myOrders = orders;
     });
    }
      // ============================================
      // Day 5 TODO: 从 Indexer 获取我的成交历史
      // ============================================
      // TODO: Day 5 - 调用 loadMyTrades 获取用户成交历史
       if (this.account) {
       await this.loadMyTrades(this.account);
       }
    } catch (e) {
    runInAction(() => {
      this.error = (e as Error)?.message || 'Failed to sync exchange data';
    });
  } finally {
    runInAction(() => {
      this.syncing = false;
    });
  }
};
  // ============================================
  // Day 1 TODO: 实现充值函数
  // ============================================
  deposit = async (ethAmount: string) => {
    if (!this.walletClient || !this.account) throw new Error('Connect wallet before depositing');
    const hash = await this.walletClient.writeContract({
      account: this.account,
      chain: this.walletClient.chain,
      address: this.ensureContract(),
      abi: EXCHANGE_ABI,
      functionName: 'deposit',
      value: parseEther(ethAmount),
    } as any);
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    if (receipt.status !== 'success') throw new Error('Transaction failed');
    await this.refresh();
  }
  // ============================================
  // Day 1 TODO: 实现提现函数
  // ============================================
  withdraw = async (amount: string) => {
    if (!this.walletClient || !this.account) throw new Error('Connect wallet before withdrawing');
    const parsed = parseEther(amount || '0');
    const hash = await this.walletClient.writeContract({
      account: this.account,
      chain: this.walletClient.chain,
      address: this.ensureContract(),
      abi: EXCHANGE_ABI,
      functionName: 'withdraw',
      args: [parsed],
    });
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    if (receipt.status !== 'success') throw new Error('Transaction failed');
    await this.refresh();
  }
  // ============================================
  // Day 2 TODO: 实现下单函数
  // ============================================
  placeOrder = async (params: {
    side: OrderSide;
    orderType?: OrderType;
    price?: string;
    amount: string;
    hintId?: string;
    marginMode?: MarginMode;  // ✅ 新增：保证金模式参数
  }) => {
    const { side, orderType = OrderType.LIMIT, price, amount, hintId, marginMode = this.marginMode } = params;
    if (!this.walletClient || !this.account) throw new Error('Connect wallet before placing orders');

    // 处理市价单：使用 markPrice 加滑点
    const currentPrice = this.markPrice > 0n ? this.markPrice : parseEther('1500');
    const parsedPrice = price ? parseEther(price) : currentPrice;
    const effectivePrice =
      orderType === OrderType.MARKET
        ? side === OrderSide.BUY
          ? currentPrice + parseEther('100')  // 买单加滑点
          : currentPrice - parseEther('100') > 0n ? currentPrice - parseEther('100') : 1n
        : parsedPrice;

    const parsedAmount = parseEther(amount);
    const parsedHint = hintId ? BigInt(hintId) : 0n;

    const hash = await this.walletClient.writeContract({
      account: this.account,
      address: this.ensureContract(),
      abi: EXCHANGE_ABI,
      functionName: 'placeOrder',
      args: [side === OrderSide.BUY, effectivePrice, parsedAmount, parsedHint, marginMode],
      chain: undefined,
    } as any);

    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    if (receipt.status !== 'success') throw new Error('Transaction failed');
    await this.refresh();
  }
  // ============================================
  // Day 2 TODO: 实现取消订单函数
  // ============================================
  cancelOrder = async (orderId: bigint) => {
    if (!this.walletClient || !this.account) throw new Error('Connect wallet before cancelling orders');
    runInAction(() => { this.cancellingOrderId = orderId; });
    try {
      const hash = await this.walletClient.writeContract({
        account: this.account,
        address: this.ensureContract(),
        abi: EXCHANGE_ABI,
        functionName: 'cancelOrder',
        args: [orderId],
        chain: undefined,
      } as any);
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      if (receipt.status !== 'success') throw new Error('Transaction failed');
      await this.refresh();
    } finally {
      runInAction(() => { this.cancellingOrderId = undefined; });
    }
  }

  // ✅ 新增：分配保证金到逐仓
  allocateToIsolated = async (amount: string) => {
    if (!this.walletClient || !this.account) throw new Error('Connect wallet before allocating margin');
    const parsed = parseEther(amount);
    const hash = await this.walletClient.writeContract({
      account: this.account,
      address: this.ensureContract(),
      abi: EXCHANGE_ABI,
      functionName: 'allocateToIsolated',
      args: [parsed],
    });
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    if (receipt.status !== 'success') throw new Error('Transaction failed');
    await this.refresh();
  }

  // ✅ 新增：从逐仓回收保证金
  removeFromIsolated = async (amount: string) => {
    if (!this.walletClient || !this.account) throw new Error('Connect wallet before removing margin');
    const parsed = parseEther(amount);
    const hash = await this.walletClient.writeContract({
      account: this.account,
      address: this.ensureContract(),
      abi: EXCHANGE_ABI,
      functionName: 'removeFromIsolated',
      args: [parsed],
    });
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    if (receipt.status !== 'success') throw new Error('Transaction failed');
    await this.refresh();
  }
}
const ExchangeStoreContext = createContext<ExchangeStore | null>(null);
export const ExchangeStoreProvider: React.FC<React.PropsWithChildren> = ({ children }) => {
  const storeRef = React.useRef<ExchangeStore | undefined>(undefined);
  if (!storeRef.current) {
    storeRef.current = new ExchangeStore();
  }
  useEffect(() => {
    // ensure initial refresh
    storeRef.current?.refresh().catch(() => { });
  }, []);
  return <ExchangeStoreContext.Provider value={storeRef.current}>{children}</ExchangeStoreContext.Provider>;
};

export const useExchangeStore = () => {
  const ctx = useContext(ExchangeStoreContext);
  if (!ctx) throw new Error('useExchangeStore must be used within ExchangeStoreProvider');
  return ctx;
};
