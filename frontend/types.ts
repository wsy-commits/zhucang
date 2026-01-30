export interface CandleData {
  time: string;
  open: number;
  high: number;
  low: number;
  close: number;
  volume: number;
}

export interface OrderBookItem {
  price: number;
  size: number;
  total: number;
  depth: number; // percentage for visual bar
}

export interface Trade {
  id: string;
  price: number;
  amount: number;
  time: string;
  side: 'buy' | 'sell';
  buyer?: string;
  seller?: string;
  txHash?: string;
}

export enum OrderSide {
  BUY = 'buy',
  SELL = 'sell'
}

export enum OrderType {
  MARKET = 'Market',
  LIMIT = 'Limit'
}

// ✅ 新增：保证金模式枚举
export enum MarginMode {
  CROSS = 0,      // 全仓模式
  ISOLATED = 1    // 逐仓模式
}

export interface PositionSnapshot {
  size: bigint;
  entryPrice: bigint;
  mode?: MarginMode;           // ✅ 新增：保证金模式
  isolatedMargin?: bigint;     // ✅ 新增：逐仓保证金
}

export interface DisplayPosition {
  symbol: string;
  leverage?: number;
  size: number;
  entryPrice: number;
  markPrice: number;
  liqPrice?: number;
  pnl: number;
  pnlPercent: number;
  side: 'long' | 'short';
  mode?: MarginMode;           // ✅ 新增：保证金模式
  isolatedMargin?: number;     // ✅ 新增：逐仓保证金显示
  marginRatio?: number;        // 保证金率（健康度）
}
