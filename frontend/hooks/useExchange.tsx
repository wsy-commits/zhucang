import React, { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import { Address, Hash, parseAbiItem, parseEther } from 'viem';
import { EXCHANGE_ABI } from '../onchain/abi';
import { EXCHANGE_ADDRESS, EXCHANGE_DEPLOY_BLOCK } from '../onchain/config';
import { chain, getFallbackWalletClient, getWalletClient, publicClient, fallbackAccount } from '../onchain/client';
import { OrderBookItem, OrderSide, OrderType, PositionSnapshot, Trade } from '../types';

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
  timestamp: bigint;
  trader: Address;
};

type ExchangeContextValue = {
  account?: Address;
  margin: bigint;

  position?: PositionSnapshot;
  markPrice: bigint;
  indexPrice: bigint;
  orderBook: OrderBookState;
  myOrders: OpenOrder[];
  trades: Trade[];
  syncing: boolean;
  error?: string;
  connectWallet: () => Promise<void>;
  deposit: (ethAmount: string) => Promise<void>;
  withdraw: (amount: string) => Promise<void>;
  placeOrder: (params: {
    side: OrderSide;
    orderType?: OrderType;
    price?: string;
    amount: string;
    hintId?: string;
  }) => Promise<void>;
  refresh: () => Promise<void>;
};

const ExchangeContext = createContext<ExchangeContextValue | undefined>(undefined);

const parseRaw = (value: string): bigint => {
  const clean = value.trim();
  if (!clean) throw new Error('Value required');
  if (clean.startsWith('-')) throw new Error('Negative values not allowed');
  if (clean.includes('.')) {
    const [whole] = clean.split('.');
    return BigInt(whole);
  }
  return BigInt(clean);
};

const formatBlockTime = (timestamp?: number) => {
  if (!timestamp) return '';
  const date = new Date(timestamp * 1000);
  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
};

export const ExchangeProvider: React.FC<React.PropsWithChildren> = ({ children }) => {
  const walletClient = useMemo(() => getWalletClient() || getFallbackWalletClient(), []);
  const [account, setAccount] = useState<Address | undefined>();
  const [margin, setMargin] = useState<bigint>(0n);

  const [position, setPosition] = useState<PositionSnapshot | undefined>();
  const [markPrice, setMarkPrice] = useState<bigint>(0n);
  const [indexPrice, setIndexPrice] = useState<bigint>(0n);
  const [orderBook, setOrderBook] = useState<OrderBookState>({ bids: [], asks: [] });
  const [trades, setTrades] = useState<Trade[]>([]);
  const [myOrders, setMyOrders] = useState<OpenOrder[]>([]);
  const [syncing, setSyncing] = useState(false);
  const [error, setError] = useState<string | undefined>();

  const ensureContract = useCallback(() => {
    if (!EXCHANGE_ADDRESS) {
      throw new Error('Set VITE_EXCHANGE_ADDRESS to your MonadPerpExchange address');
    }
    return EXCHANGE_ADDRESS;
  }, []);

  const loadOrderChain = useCallback(
    async (headId: bigint | undefined | null) => {
      const head: OrderStruct[] = [];
      if (headId === undefined || headId === null) return head;
      let current = headId;
      const visited = new Set<string>();
      for (let i = 0; i < 128 && typeof current === 'bigint' && current !== 0n; i++) {
        if (visited.has(current.toString())) break;
        visited.add(current.toString());
        const data = (await publicClient.readContract({
          abi: EXCHANGE_ABI,
          address: ensureContract(),
          functionName: 'orders',
          args: [current],
        })) as OrderStruct;
        if (data.id === 0n) break;
        head.push(data);
        current = data.next;
      }
      return head;
    },
    [ensureContract],
  );

  const formatOrderBook = useCallback((orders: OrderStruct[], isBuy: boolean): OrderBookItem[] => {
    const filtered = orders.filter((o) => o.isBuy === isBuy);
    let running = 0;
    const rows = filtered.map((o) => {
      const size = Number(o.amount);
      running += size;
      return {
        price: Number(o.price),
        size,
        total: running,
        depth: 0,
      };
    });
    const maxTotal = rows.reduce((m, r) => (r.total > m ? r.total : m), 0);
    return rows.map((r) => ({
      ...r,
      depth: maxTotal > 0 ? Math.min(100, Math.round((r.total / maxTotal) * 100)) : 0,
    }));
  }, []);

  const loadTrades = useCallback(
    async (viewer?: Address): Promise<Trade[]> => {
      const logs = await publicClient.getLogs({
        address: ensureContract(),
        event: parseAbiItem(
          'event TradeExecuted(uint256 indexed buyOrderId,uint256 indexed sellOrderId,uint256 price,uint256 amount,address buyer,address seller)',
        ),
        fromBlock: EXCHANGE_DEPLOY_BLOCK,
        toBlock: 'latest',
      });

      const recent = logs.slice(-30); // keep UI light
      const timestamps = await Promise.all(
        recent.map(async (log) => {
          const block = await publicClient.getBlock({ blockNumber: log.blockNumber });
          return Number(block.timestamp);
        }),
      );

      return recent.map((log, idx) => {
        const args = log.args as {
          price?: bigint;
          amount?: bigint;
          buyer?: Address;
          seller?: Address;
        };
        const buyerLower = args.buyer?.toLowerCase();
        const sellerLower = args.seller?.toLowerCase();
        const viewerLower = viewer?.toLowerCase();
        const side =
          viewerLower && buyerLower === viewerLower
            ? 'buy'
            : viewerLower && sellerLower === viewerLower
              ? 'sell'
              : 'buy';

        return {
          id: `${log.transactionHash}-${log.logIndex ?? 0n}`,
          price: Number(args.price ?? 0n),
          amount: Number(args.amount ?? 0n),
          time: formatBlockTime(timestamps[idx]),
          side,
          buyer: args.buyer,
          seller: args.seller,
          txHash: log.transactionHash as Hash,
        };
      });
    },
    [ensureContract],
  );

  const refresh = useCallback(async () => {
    try {
      setSyncing(true);
      setError(undefined);
      const address = ensureContract();
      const [mark, index, bestBid, bestAsk] = await Promise.all([
        publicClient.readContract({ abi: EXCHANGE_ABI, address, functionName: 'markPrice' }) as Promise<bigint>,
        publicClient.readContract({ abi: EXCHANGE_ABI, address, functionName: 'indexPrice' }) as Promise<bigint>,
        publicClient.readContract({ abi: EXCHANGE_ABI, address, functionName: 'bestBuyId' }) as Promise<bigint>,
        publicClient.readContract({ abi: EXCHANGE_ABI, address, functionName: 'bestSellId' }) as Promise<bigint>,
      ]);
      setMarkPrice(mark);
      setIndexPrice(index);
      console.debug('[orderbook] head ids', { bestBid: bestBid?.toString?.(), bestAsk: bestAsk?.toString?.() });

      if (account) {
        const [m, pos] = await Promise.all([
          publicClient.readContract({
            abi: EXCHANGE_ABI,
            address,
            functionName: 'margin',
            args: [account],
          }) as Promise<bigint>,
          publicClient.readContract({
            abi: EXCHANGE_ABI,
            address,
            functionName: 'getPosition',
            args: [account],
          }) as Promise<PositionSnapshot>,
        ]);
        setMargin(m);
        setPosition(pos);
      }

      let bidsRaw: OrderStruct[] = [];
      let asksRaw: OrderStruct[] = [];
      try {
        [bidsRaw, asksRaw] = await Promise.all([loadOrderChain(bestBid), loadOrderChain(bestAsk)]);
      } catch (inner) {
        setError((inner as Error)?.message || 'Failed to load orderbook');
      }

      // 兜底：全量扫描前 N 个 id，合并去重，保证 UI 有数据
      const scanned: OrderStruct[] = [];
      const SCAN_LIMIT = 128n;
      for (let i = 1n; i <= SCAN_LIMIT; i++) {
        const data = (await publicClient.readContract({
          abi: EXCHANGE_ABI,
          address,
          functionName: 'orders',
          args: [i],
        })) as OrderStruct;
        if (data.id !== 0n && data.amount > 0n) scanned.push(data);
      }
      const merged = new Map<bigint, OrderStruct>();
      [...bidsRaw, ...asksRaw, ...scanned].forEach((o) => {
        if (o && o.id) merged.set(o.id, o);
      });
      const allOrders = Array.from(merged.values());
      const bids = allOrders.filter((o) => o.isBuy && o.amount > 0n);
      const asks = allOrders.filter((o) => !o.isBuy && o.amount > 0n);
      console.debug('[orderbook] bids/asks', { bids, asks, merged: merged.size });

      setOrderBook({
        bids: formatOrderBook(bids, true),
        asks: formatOrderBook(asks, false),
      });
      try {
        const tradesRaw = await loadTrades(account);
        setTrades(tradesRaw);
      } catch {
        // keep previous trades on failure
      }
      if (account) {
        const accountLower = account.toLowerCase();
        const mine = [...bidsRaw, ...asksRaw]
          .filter((o) => o.trader && o.trader.toLowerCase() === accountLower)
          .map(
            (o): OpenOrder => ({
              id: o.id,
              isBuy: o.isBuy,
              price: o.price,
              amount: o.amount,
              timestamp: o.timestamp,
              trader: o.trader,
            }),
          );
        setMyOrders(mine);
      } else {
        setMyOrders([]);
      }
    } catch (e) {
      setError((e as Error)?.message || 'Failed to sync exchange data');
    } finally {
      setSyncing(false);
    }
  }, [account, ensureContract, formatOrderBook, loadOrderChain, loadTrades]);

  const connectWallet = useCallback(async () => {
    if (!walletClient) {
      setError('No injected wallet or test private key configured');
      return;
    }
    try {
      if ('requestAddresses' in walletClient) {
        const [addr] = await walletClient.requestAddresses();
        setAccount(addr);
      } else if ('getAddresses' in walletClient) {
        const addrs = await (walletClient as any).getAddresses();
        if (addrs.length > 0) {
          setAccount(addrs[0]);
        }
      } else if ((walletClient as any).account?.address) {
        setAccount((walletClient as any).account.address);
      } else if (fallbackAccount) {
        setAccount(fallbackAccount.address);
      }
    } catch (e) {
      setError((e as Error)?.message || 'Wallet connection failed');
    }
  }, [walletClient]);

  const waitFor = useCallback(async (hash: Hash) => {
    await publicClient.waitForTransactionReceipt({ hash, chain });
  }, []);

  const deposit = useCallback(
    async (ethAmount: string) => {
      if (!walletClient || !account) throw new Error('Connect wallet before depositing');
      const value = parseEther(ethAmount || '0');
      const hash = await walletClient.writeContract({
        account,
        address: ensureContract(),
        abi: EXCHANGE_ABI,
        functionName: 'deposit',
        args: [],
        value,
      });
      await waitFor(hash);
      await refresh();
    },
    [account, ensureContract, refresh, waitFor, walletClient],
  );

  const withdraw = useCallback(
    async (amount: string) => {
      if (!walletClient || !account) throw new Error('Connect wallet before withdrawing');
      const parsed = parseEther(amount || '0');
      const hash = await walletClient.writeContract({
        account,
        address: ensureContract(),
        abi: EXCHANGE_ABI,
        functionName: 'withdraw',
        args: [parsed],
      });
      await waitFor(hash);
      await refresh();
    },
    [account, ensureContract, refresh, waitFor, walletClient],
  );

  const placeOrder = useCallback(
    async ({
      side,
      orderType = OrderType.LIMIT,
      price,
      amount,
      hintId,
    }: {
      side: OrderSide;
      orderType?: OrderType;
      price?: string;
      amount: string;
      hintId?: string;
    }) => {
      if (!walletClient || !account) throw new Error('Connect wallet before placing orders');
      const currentPrice = markPrice > 0 ? markPrice : 1n;
      const parsedPrice = price ? parseRaw(price) : currentPrice;
      const effectivePrice =
        orderType === OrderType.MARKET
          ? side === OrderSide.BUY
            ? currentPrice + 1n // cross existing asks
            : currentPrice - 1n > 0 ? currentPrice - 1n : 1n
          : parsedPrice;
      const parsedAmount = parseRaw(amount);
      const parsedHint = hintId ? parseRaw(hintId) : 0n;

      const hash = await walletClient.writeContract({
        account,
        address: ensureContract(),
        abi: EXCHANGE_ABI,
        functionName: 'placeOrder',
        args: [side === OrderSide.BUY, effectivePrice, parsedAmount, parsedHint],
      });
      await waitFor(hash);
      await refresh();
    },
    [account, ensureContract, markPrice, refresh, walletClient, waitFor],
  );

  // Auto fetch account if wallet already authorized or fallback PK configured
  useEffect(() => {
    const fetchAccount = async () => {
      if (fallbackAccount) {
        setAccount(fallbackAccount.address);
        return;
      }
      if (!walletClient) return;
      try {
        if ('getAddresses' in walletClient) {
          const addrs = await (walletClient as any).getAddresses();
          if (addrs.length > 0) {
            setAccount(addrs[0]);
          }
        }
      } catch {
        // ignore
      }
    };
    fetchAccount();
  }, [walletClient]);

  useEffect(() => {
    refresh();
    const timer = setInterval(() => {
      refresh().catch(() => { });
    }, 4000);
    return () => clearInterval(timer);
  }, [refresh]);

  const value: ExchangeContextValue = {
    account,
    margin,

    position,
    markPrice,
    indexPrice,
    orderBook,
    myOrders,
    trades,
    syncing,
    error,
    connectWallet,
    deposit,
    withdraw,
    placeOrder,
    refresh,
  };

  return <ExchangeContext.Provider value={value}>{children}</ExchangeContext.Provider>;
};

export const useExchange = () => {
  const ctx = useContext(ExchangeContext);
  if (!ctx) {
    throw new Error('useExchange must be used within ExchangeProvider');
  }
  return ctx;
};
