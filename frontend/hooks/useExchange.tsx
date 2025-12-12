import React, { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import { Address, Hash, parseEther } from 'viem';
import { EXCHANGE_ABI } from '../onchain/abi';
import { EXCHANGE_ADDRESS, EXCHANGE_DEPLOY_BLOCK } from '../onchain/config';
import { chain, getFallbackWalletClient, getWalletClient, publicClient, fallbackAccount } from '../onchain/client';
import { OrderBookItem, OrderSide, OrderType, PositionSnapshot, Trade } from '../types';

interface OrderStruct {
  id: bigint;
  trader: Address;
  isBuy: boolean;
  price: bigint;
  amount: bigint;
  initialAmount: bigint;
  timestamp: bigint;
  next: bigint;
}

interface OrderBookState {
  bids: OrderBookItem[];
  asks: OrderBookItem[];
}

interface OpenOrder {
  id: bigint;
  isBuy: boolean;
  price: bigint;
  amount: bigint;
  timestamp: bigint;
  trader: Address;
}

interface ExchangeContextValue {
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
  deposit: (amount: string) => Promise<void>;
  withdraw: (amount: string) => Promise<void>;
  placeOrder: (params: {
    side: OrderSide;
    orderType?: OrderType;
    price?: string;
    amount: string;
    hintId?: string;
  }) => Promise<void>;
  cancelOrder: (orderId: string) => Promise<void>;
  refresh: () => Promise<void>;
}

const ExchangeContext = createContext<ExchangeContextValue | undefined>(undefined);

function parseRaw(value: string): bigint {
  try {
    return parseEther(value);
  } catch {
    return 0n;
  }
}

/**
 * Exchange Provider - 脚手架版本
 * 
 * 这个 Provider 提供了与合约交互的接口，但实现为空。
 * 学生需要完成以下功能：
 * 
 * 1. deposit() - 调用合约的 deposit 函数
 * 2. withdraw() - 调用合约的 withdraw 函数
 * 3. placeOrder() - 调用合约的 placeOrder 函数
 * 4. cancelOrder() - 调用合约的 cancelOrder 函数
 * 5. 数据读取 - 从合约读取余额、持仓、订单簿等
 */
export function ExchangeProvider({ children }: { children: React.ReactNode }) {
  // ============================================
  // State - 这些状态用于 UI 显示
  // ============================================
  const [account, setAccount] = useState<Address | undefined>();
  const [margin, setMargin] = useState<bigint>(0n);
  const [position, setPosition] = useState<PositionSnapshot | undefined>();
  const [markPrice, setMarkPrice] = useState<bigint>(0n);
  const [indexPrice, setIndexPrice] = useState<bigint>(0n);
  const [orderBook, setOrderBook] = useState<OrderBookState>({ bids: [], asks: [] });
  const [myOrders, setMyOrders] = useState<OpenOrder[]>([]);
  const [trades, setTrades] = useState<Trade[]>([]);
  const [syncing, setSyncing] = useState(false);
  const [error, setError] = useState<string | undefined>();

  // ============================================
  // 合约交互函数 - TODO: 学生需要实现
  // ============================================

  /**
   * 存入保证金
   * TODO: 实现此函数
   * 
   * 步骤:
   * 1. 获取钱包客户端
   * 2. 调用合约的 deposit() 函数，附带 ETH
   * 3. 等待交易确认
   * 4. 刷新数据
   */
  const deposit = useCallback(async (amount: string) => {
    console.log('TODO: Implement deposit', amount);
    setError('deposit 功能尚未实现，请完成 useExchange.tsx 中的 deposit 函数');
  }, []);

  /**
   * 提取保证金
   * TODO: 实现此函数
   * 
   * 步骤:
   * 1. 获取钱包客户端
   * 2. 调用合约的 withdraw(amount) 函数
   * 3. 等待交易确认
   * 4. 刷新数据
   */
  const withdraw = useCallback(async (amount: string) => {
    console.log('TODO: Implement withdraw', amount);
    setError('withdraw 功能尚未实现，请完成 useExchange.tsx 中的 withdraw 函数');
  }, []);

  /**
   * 下单
   * TODO: 实现此函数
   * 
   * 步骤:
   * 1. 获取钱包客户端
   * 2. 解析参数 (side -> isBuy, price, amount, hintId)
   * 3. 调用合约的 placeOrder(isBuy, price, amount, hintId) 函数
   * 4. 等待交易确认
   * 5. 刷新数据
   */
  const placeOrder = useCallback(async (params: {
    side: OrderSide;
    orderType?: OrderType;
    price?: string;
    amount: string;
    hintId?: string;
  }) => {
    console.log('TODO: Implement placeOrder', params);
    setError('placeOrder 功能尚未实现，请完成 useExchange.tsx 中的 placeOrder 函数');
  }, []);

  /**
   * 取消订单
   * TODO: 实现此函数
   * 
   * 步骤:
   * 1. 获取钱包客户端
   * 2. 调用合约的 cancelOrder(orderId) 函数
   * 3. 等待交易确认
   * 4. 刷新数据
   */
  const cancelOrder = useCallback(async (orderId: string) => {
    console.log('TODO: Implement cancelOrder', orderId);
    setError('cancelOrder 功能尚未实现，请完成 useExchange.tsx 中的 cancelOrder 函数');
  }, []);

  /**
   * 刷新所有数据
   * TODO: 实现此函数
   * 
   * 步骤:
   * 1. 读取用户余额 margin(account)
   * 2. 读取用户持仓 getPosition(account)
   * 3. 读取标记价和指数价 markPrice(), indexPrice()
   * 4. 读取订单簿 (遍历 bestBuyId/bestSellId 链表)
   * 5. 读取用户的挂单
   * 6. 读取最近成交 (TradeExecuted 事件)
   */
  const refresh = useCallback(async () => {
    console.log('TODO: Implement refresh');
    setSyncing(true);

    // 示例: 设置一些模拟数据供 UI 显示
    setMarkPrice(parseEther('100'));
    setIndexPrice(parseEther('100'));
    setMargin(parseEther('10'));

    setSyncing(false);
  }, []);

  // ============================================
  // 初始化和事件监听
  // ============================================

  useEffect(() => {
    // TODO: 获取当前账户地址
    // 可以使用 getWalletClient 或 fallbackAccount
    if (fallbackAccount) {
      setAccount(fallbackAccount.address);
    }

    // 初始刷新
    refresh();
  }, [refresh]);

  // ============================================
  // Context Value
  // ============================================
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
    deposit,
    withdraw,
    placeOrder,
    cancelOrder,
    refresh,
  };

  return (
    <ExchangeContext.Provider value={value}>
      {children}
    </ExchangeContext.Provider>
  );
}

export function useExchange() {
  const context = useContext(ExchangeContext);
  if (!context) {
    throw new Error('useExchange must be used within ExchangeProvider');
  }
  return context;
}
