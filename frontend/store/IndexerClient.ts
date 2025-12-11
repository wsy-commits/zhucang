const INDEXER_URL = 'http://localhost:8080/v1/graphql';

export const client = {
  query: (query: string, variables: any = {}) => {
    return {
      toPromise: async () => {
        try {
          const response = await fetch(INDEXER_URL, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'x-hasura-admin-secret': 'testing'
            },
            body: JSON.stringify({ query, variables }),
          });
          const result = await response.json();
          return { data: result.data, error: result.errors };
        } catch (e) {
          console.error('[IndexerClient] fetch error:', e);
          return { data: null, error: e };
        }
      }
    };
  }
};

export const GET_CANDLES = `
  query GetCandles {
    Candle(order_by: { timestamp: desc }, limit: 100) {
      id
      timestamp
      openPrice
      highPrice
      lowPrice
      closePrice
      volume
    }
  }
`;

export const GET_RECENT_TRADES = `
  query GetRecentTrades {
    Trade(order_by: { timestamp: desc }, limit: 50) {
      id
      price
      amount
      buyer
      seller
      timestamp
      txHash
      buyOrderId
      sellOrderId
    }
  }
`;

export const GET_POSITIONS = `
  query GetPositions($trader: String!) {
    Position(where: { trader: { _eq: $trader } }) {
      trader
      size
      entryPrice
      realizedPnl
    }
  }
`;

export const GET_OPEN_ORDERS = `
  query GetOpenOrders($trader: String!) {
    Order(where: { trader: { _eq: $trader }, amount: { _gt: 0 } }, order_by: { id: desc }) {
      id
      trader
      isBuy
      price
      amount
      initialAmount
      timestamp
    }
  }
`;
