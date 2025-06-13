import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import _HashMap "mo:base/HashMap";
import _Iter "mo:base/Iter";
import LLM "mo:llm";
import Nat "mo:base/Nat";
import _Option "mo:base/Option";
import Principal "mo:base/Principal";
import _Result "mo:base/Result";
import Time "mo:base/Time";
import Error "mo:base/Error";
import Float "mo:base/Float";
import _ExperimentalCycles "mo:base/ExperimentalCycles";
// import Pyth "mo:pyth";

shared ({caller = owner}) actor class Quanturnic() = this {
  // Types
  public type Asset = {
    #BTC;
    #ETH;
    #ICP;
    #SOL;
    #USDT
  };

  public type TradeDirection = {
    #BUY;
    #SELL
  };

  public type Trade = {
    asset : Asset;
    direction : TradeDirection;
    amount : Float;
    price : Float;
    timestamp : Int;
    reason : Text
  };

  public type Strategy = {
    #TrendFollowing;
    #MeanReversion;
    #Arbitrage;
    #SentimentAnalysis
  };

  public type MarketData = {
    asset : Asset;
    price : Float;
    volume : Float;
    timestamp : Int;
    change24h : Float;
    marketCap : Float
  };

  public type Portfolio = {
    balances : [(Asset, Float)];
    totalValue : Float;
    performance24h : Float
  };

  // State
  stable var trades : [Trade] = [];
  stable var marketData : [MarketData] = [];
  stable var strategies : [Strategy] = [#TrendFollowing, #MeanReversion];
  stable var portfolio : Portfolio = {
    balances = [
      (#BTC, 0.0),
      (#ETH, 0.0),
      (#ICP, 10.0),
      (#SOL, 0.0),
      (#USDT, 1000.0)
    ];
    totalValue = 1010.0; // Initial value
    performance24h = 0.0
  };
  stable var emergencyPaused : Bool = false;

  // Initialize Pyth oracle
  // let pyth = Pyth.Pyth();

  // AI Chat Interface
  public func prompt(prompt : Text) : async Text {
    assert (not emergencyPaused);
    await LLM.prompt(#Llama3_1_8B, prompt)
  };

  public func chat(messages : [LLM.ChatMessage]) : async Text {
    assert (not emergencyPaused);
    await LLM.chat(#Llama3_1_8B, messages)
  };

  // Trading Functions
  public func fetchMarketData() : async [MarketData] {
    assert (not emergencyPaused);

    let newData : [MarketData] = [
      {
        asset = #BTC;
        price = 50000.0;
        volume = 1000000000.0;
        timestamp = Time.now();
        change24h = 2.5;
        marketCap = 1e12
      },
      {
        asset = #ETH;
        price = 3000.0;
        volume = 500000000.0;
        timestamp = Time.now();
        change24h = 1.8;
        marketCap = 360e9
      },
      {
        asset = #ICP;
        price = 10.0;
        volume = 10000000.0;
        timestamp = Time.now();
        change24h = -0.5;
        marketCap = 5e9
      },
      {
        asset = #SOL;
        price = 100.0;
        volume = 50000000.0;
        timestamp = Time.now();
        change24h = 3.2;
        marketCap = 40e9
      },
      {
        asset = #USDT;
        price = 1.0;
        volume = 0.0;
        timestamp = Time.now();
        change24h = 0.0;
        marketCap = 0.0
      }
    ];

    marketData := newData;
    await updatePortfolioValue();
    newData
  };

  func validateTrade(asset : Asset, amount : Float, price : Float) : Bool {
    if (emergencyPaused) return false;

    let maxPositionSize = 0.1 * portfolio.totalValue;
    let tradeValue = amount * price;

    if (tradeValue > maxPositionSize) return false;

    // Check sufficient balance
    switch (Array.find(portfolio.balances, func(b : (Asset, Float)) : Bool {b.0 == asset})) {
      case (?(_, balance)) {
        if (balance < amount) return false
      };
      case null {return false}
    };

    true
  };

  public func executeTrade(
    asset : Asset,
    direction : TradeDirection,
    amount : Float
  ) : async Trade {
    assert (not emergencyPaused);

    let currentPrice = switch (Array.find(marketData, func(d : MarketData) : Bool {d.asset == asset})) {
      case (?data) {data.price};
      case null {throw Error.reject("Asset not found")}
    };

    if (not validateTrade(asset, amount, currentPrice)) {
      throw Error.reject("Trade validation failed")
    };

    let reason = await generateTradeReason(asset, direction, amount, currentPrice);

    let trade : Trade = {
      asset;
      direction;
      amount;
      price = currentPrice;
      timestamp = Time.now();
      reason
    };

    trades := Array.append(trades, [trade]);
    await updatePortfolio(trade);
    trade
  };

  func updatePortfolio(trade : Trade) : async () {
    let newBalances = Buffer.Buffer<(Asset, Float)>(portfolio.balances.size());
    for (balance in portfolio.balances.vals()) {
      newBalances.add(balance)
    };

    func findAssetIndex(asset : Asset) : ?Nat {
      var index : Nat = 0;
      for ((a, _) in portfolio.balances.vals()) {
        if (a == asset) {
          return ?index
        };
        index += 1
      };
      null
    };

    let usdtIndex = findAssetIndex(#USDT);
    let assetIndex = findAssetIndex(trade.asset);

    switch (trade.direction) {
      case (#BUY) {
        switch (usdtIndex, assetIndex) {
          case (?uIdx, ?aIdx) {
            let (_, usdtBal) = newBalances.get(uIdx);
            let (_, assetBal) = newBalances.get(aIdx);
            newBalances.put(uIdx, (#USDT, usdtBal - (trade.amount * trade.price)));
            newBalances.put(aIdx, (trade.asset, assetBal + trade.amount))
          };
          case (_, _) {}
        }
      };
      case (#SELL) {
        switch (usdtIndex, assetIndex) {
          case (?uIdx, ?aIdx) {
            let (_, usdtBal) = newBalances.get(uIdx);
            let (_, assetBal) = newBalances.get(aIdx);
            newBalances.put(uIdx, (#USDT, usdtBal + (trade.amount * trade.price)));
            newBalances.put(aIdx, (trade.asset, assetBal - trade.amount))
          };
          case (_, _) {}
        }
      }
    };

    let totalValue = calculatePortfolioValue(Buffer.toArray(newBalances));

    portfolio := {
      balances = Buffer.toArray(newBalances);
      totalValue;
      performance24h = calculate24hPerformance(totalValue)
    }
  };

  func calculatePortfolioValue(balances : [(Asset, Float)]) : Float {
    var total : Float = 0.0;

    for ((asset, amount) in balances.vals()) {
      let price = switch (Array.find(marketData, func(d : MarketData) : Bool {d.asset == asset})) {
        case (?data) {data.price};
        case null {0.0}
      };
      total += amount * price
    };

    total
  };

  func calculate24hPerformance(newValue : Float) : Float {
    if (portfolio.totalValue == 0.0) return 0.0;
    ((newValue - portfolio.totalValue) / portfolio.totalValue) * 100.0
  };

  func updatePortfolioValue() : async () {
    let totalValue = calculatePortfolioValue(portfolio.balances);
    portfolio := {
      balances = portfolio.balances;
      totalValue;
      performance24h = calculate24hPerformance(totalValue)
    }
  };

  public func getPortfolio() : async Portfolio {
    portfolio
  };

  public func getTradeHistory() : async [Trade] {
    trades
  };

  public func getMarketData() : async [MarketData] {
    marketData
  };

  func generateTradeReason(
    asset : Asset,
    direction : TradeDirection,
    amount : Float,
    price : Float
  ) : async Text {
    let prompt = "Explain in one sentence why we should " #
    (
      switch (direction) {
        case (#BUY) {"buy "};
        case (#SELL) {"sell "}
      }
    ) #
    Float.toText(amount) # " " #
    (
      switch (asset) {
        case (#BTC) {"Bitcoin"};
        case (#ETH) {"Ethereum"};
        case (#ICP) {"ICP"};
        case (#SOL) {"Solana"};
        case (#USDT) {"USDT"}
      }
    ) # " at $" # Float.toText(price) # " based on current market conditions.";

    await LLM.prompt(#Llama3_1_8B, prompt)
  };

  public func autoTrade() : async Trade {
    assert (not emergencyPaused);

    let currentMarket = await fetchMarketData();

    // Enhanced trading strategy
    let icpData = Array.find(currentMarket, func(d : MarketData) : Bool {d.asset == #ICP});
    let icp = switch (icpData) {
      case (?data) {data};
      case null {return await executeTrade(#ICP, #BUY, 0.0)}
    };

    // Simple RSI-like strategy
    let (direction, amount) = if (icp.change24h > 2.0 and icp.volume > 500000.0) {
      (#BUY, min(portfolio.totalValue * 0.05 / icp.price, 5.0))
    } else if (icp.change24h < -1.5) {
      (
        #SELL,
        min(
          switch (Array.find(portfolio.balances, func(b : (Asset, Float)) : Bool {b.0 == #ICP})) {
            case (?(_, bal)) {bal * 0.5}; // Sell 50% of position
            case null {0.0}
          },
          5.0
        )
      )
    } else {
      (#BUY, 0.0); // No trade
    };

    if (amount > 0.0) {
      await executeTrade(#ICP, direction, amount)
    } else {
      throw Error.reject("No trade opportunity found")
    }
  };

  // Admin functions
  public shared ({caller}) func emergencyPause() : async () {
    if (Principal.notEqual(caller, owner)) {
      throw Error.reject("Unauthorized")
    };
    emergencyPaused := true
  };

  public shared ({caller}) func resume() : async () {
    if (Principal.notEqual(caller, owner)) {
      throw Error.reject("Unauthorized")
    };
    emergencyPaused := false
  };

  public shared ({caller}) func resetPortfolio() : async () {
    if (Principal.notEqual(caller, owner)) {
      throw Error.reject("Unauthorized")
    };

    portfolio := {
      balances = [
        (#BTC, 0.0),
        (#ETH, 0.0),
        (#ICP, 10.0),
        (#SOL, 0.0),
        (#USDT, 1000.0)
      ];
      totalValue = 1010.0;
      performance24h = 0.0
    };
    trades := []
  };

  public func getStrategies() : async [Strategy] {
    strategies
  };

  public func addStrategy(strategy : Strategy) : async () {
    strategies := Array.append(strategies, [strategy])
  };

  // Helper functions
  func min(a : Float, b : Float) : Float {
    if (a < b) {a} else {b}
  }
}
