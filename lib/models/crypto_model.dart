class CryptoModel {
  final String id;
  final String symbol;
  final String name;
  final double price;
  final double change24h;
  final double volume24h; // Объем торгов (количество монет)
  final double turnover24h; // Оборот (объем * цена)
  final double? marketCap;
  final String? imageUrl;

  CryptoModel({
    required this.id,
    required this.symbol,
    required this.name,
    required this.price,
    required this.change24h,
    required this.volume24h,
    required this.turnover24h,
    this.marketCap,
    this.imageUrl,
  });

  bool get isPositive => change24h >= 0;

  String get pair {
    // Для опционов символ уже содержит полное название (например, MNTUSDT-24NOV25-1.04-C)
    if (symbol.contains('-')) {
      return symbol;
    }
    return '$symbol/USDT';
  }

  // Парсинг из Bybit API v5 tickers endpoint
  factory CryptoModel.fromBybitJson(Map<String, dynamic> json) {
    final symbol = json['symbol'] ?? '';
    // Для опционов символ имеет формат типа MNTUSDT-24NOV25-1.04-C
    // Не нужно обрезать символ для опционов
    String baseSymbol = symbol;
    if (symbol.contains('-')) {
      // Это опцион, оставляем символ как есть
      baseSymbol = symbol;
    } else if (symbol.endsWith('USDT')) {
      baseSymbol = symbol.replaceAll('USDT', '');
    } else if (symbol.endsWith('USD')) {
      baseSymbol = symbol.replaceAll('USD', '');
    }

    // Парсим процент изменения
    double change24h = 0.0;

    if (symbol.contains('-')) {
      // Это опцион
      // Для опционов change24h в API - это уже в процентах, но очень маленькие значения
      // Используем change24h из API напрямую (уже в процентах)
      final change24hStr = json['change24h']?.toString() ?? '0';
      change24h = double.tryParse(change24hStr) ?? 0.0;

      // Если change24h = 0, но есть highPrice24h и lowPrice24h,
      // вычисляем изменение от highPrice24h к lowPrice24h (для "Лидеры падения")
      // Это будет использоваться только если нужно показать падение
      // Но для нормального отображения используем change24h из API
    } else {
      // Для остальных категорий используем price24hPcnt
      final price24hPcnt = json['price24hPcnt']?.toString() ?? '0';
      final changeValue = double.tryParse(price24hPcnt) ?? 0.0;
      // Если значение меньше 1, значит это доля (0.05 = 5%), умножаем на 100
      change24h = changeValue.abs() < 1 ? changeValue * 100 : changeValue;
    }

    return CryptoModel(
      id: symbol.toLowerCase(),
      symbol: baseSymbol,
      name: baseSymbol,
      price: double.tryParse(json['lastPrice']?.toString() ?? '0') ?? 0.0,
      change24h: change24h,
      // volume24h - объем торгов (количество монет)
      volume24h: double.tryParse(json['volume24h']?.toString() ?? '0') ?? 0.0,
      // turnover24h - оборот (объем * цена в USDT)
      turnover24h:
          double.tryParse(json['turnover24h']?.toString() ?? '0') ?? 0.0,
      marketCap: null, // Bybit не предоставляет market cap напрямую
      imageUrl: null, // Можно добавить позже через другой endpoint
    );
  }

  // Парсинг из CoinGecko API markets endpoint (для обратной совместимости)
  factory CryptoModel.fromJson(Map<String, dynamic> json) {
    final price = (json['current_price'] ?? 0.0).toDouble();
    final volume = (json['total_volume'] ?? 0.0).toDouble();
    return CryptoModel(
      id: json['id'] ?? '',
      symbol: (json['symbol'] ?? '').toUpperCase(),
      name: json['name'] ?? '',
      price: price,
      change24h: (json['price_change_percentage_24h'] ?? 0.0).toDouble(),
      volume24h: volume,
      turnover24h: volume * price, // Вычисляем оборот
      marketCap: json['market_cap']?.toDouble(),
      imageUrl: json['image'],
    );
  }

  // Парсинг из CoinGecko API detail endpoint
  factory CryptoModel.fromDetailJson(Map<String, dynamic> json) {
    final marketData = json['market_data'] ?? {};
    final price = (marketData['current_price']?['usdt'] ??
            marketData['current_price']?['usd'] ??
            0.0)
        .toDouble();
    final volume = (marketData['total_volume']?['usdt'] ??
            marketData['total_volume']?['usd'] ??
            0.0)
        .toDouble();
    return CryptoModel(
      id: json['id'] ?? '',
      symbol: (json['symbol'] ?? '').toUpperCase(),
      name: json['name'] ?? '',
      price: price,
      change24h: (marketData['price_change_percentage_24h'] ?? 0.0).toDouble(),
      volume24h: volume,
      turnover24h: volume * price, // Вычисляем оборот
      marketCap: marketData['market_cap']?['usdt']?.toDouble() ??
          marketData['market_cap']?['usd']?.toDouble(),
      imageUrl: json['image']?['large'] ?? json['image']?['small'],
    );
  }

  // Для совместимости со старым кодом
  Map<String, dynamic> toMap() {
    return {
      'symbol': pair,
      'price': price,
      'volume': volume24h,
      'change': change24h,
      'isPositive': isPositive,
    };
  }
}
