import '../models/crypto_model.dart';
import '../config/app_constants.dart';

/// Сервис для фильтрации криптовалют по различным критериям
class CryptoFilterService {
  CryptoFilterService._();

  /// Фильтрация по подкатегории
  static List<CryptoModel> filterBySubCategory(
    List<CryptoModel> coins,
    String subCategory,
  ) {
    switch (subCategory) {
      case 'TradFi':
        return _filterTradFi(coins);
      case 'Alpha':
        return _filterAlpha(coins);
      case 'Опцион':
        return _filterOptions(coins);
      case 'Деривативы':
      case 'Фьючерсы':
        return _filterDerivatives(coins);
      default:
        return _filterSpot(coins);
    }
  }

  /// Фильтрация для TradFi (стабильные монеты)
  static List<CryptoModel> _filterTradFi(List<CryptoModel> coins) {
    return coins.where((coin) {
      return AppConstants.stablecoinSymbols.contains(coin.symbol) ||
          (coin.price >= AppConstants.tradfiMinPrice &&
              coin.price <= AppConstants.tradfiMaxPrice &&
              coin.change24h.abs() < AppConstants.tradfiMaxVolatility);
    }).toList();
  }

  /// Фильтрация для Alpha (растущие альтернативные монеты)
  static List<CryptoModel> _filterAlpha(List<CryptoModel> coins) {
    final filtered = coins.where((coin) {
      return coin.change24h > AppConstants.alphaMinChange24h &&
          coin.volume24h > AppConstants.minVolume24hAlpha &&
          coin.volume24h < AppConstants.maxVolume24hAlpha &&
          !AppConstants.stablecoinSymbols.contains(coin.symbol) &&
          !AppConstants.topCoins.contains(coin.symbol);
    }).toList();

    // Сортируем по проценту роста
    filtered.sort((a, b) => b.change24h.compareTo(a.change24h));
    return filtered;
  }

  /// Фильтрация для опционов
  static List<CryptoModel> _filterOptions(List<CryptoModel> coins) {
    return coins.where((coin) {
      if (!coin.symbol.contains('-')) return false;

      // Исключаем обычные монеты
      for (final coinName in AppConstants.regularCoins) {
        if (coin.symbol == coinName ||
            coin.symbol == '${coinName}USDT' ||
            coin.symbol == '${coinName}USD' ||
            coin.symbol.startsWith('$coinName/')) {
          return false;
        }
      }

      return coin.volume24h > AppConstants.minVolume24h;
    }).toList();
  }

  /// Фильтрация для спота
  static List<CryptoModel> _filterSpot(List<CryptoModel> coins) {
    return coins.where((coin) {
      return !AppConstants.stablecoinSymbols.contains(coin.symbol) &&
          coin.volume24h > AppConstants.minVolume24h;
    }).toList();
  }

  /// Фильтрация для деривативов и фьючерсов
  static List<CryptoModel> _filterDerivatives(List<CryptoModel> coins) {
    return coins.where((coin) {
      return !AppConstants.stablecoinSymbols.contains(coin.symbol) &&
          coin.volume24h > AppConstants.minVolume24hDerivatives;
    }).toList();
  }

  /// Проверка, является ли символ опционом
  static bool isOptionSymbol(String symbol) {
    if (!symbol.contains('-')) return false;

    final parts = symbol.split('-');
    if (parts.length < 3) return false;

    // Проверяем, что вторая часть - дата
    final datePart = parts[1];
    if (datePart.length < 6 ||
        !datePart.contains(RegExp(r'[0-9]')) ||
        !datePart.contains(RegExp(r'[A-Z]'))) {
      return false;
    }

    return true;
  }

  /// Фильтрация опционов на уровне JSON (до парсинга)
  static bool isOptionJson(Map<String, dynamic> json) {
    final symbol = json['symbol']?.toString() ?? '';

    // Исключаем обычные монеты
    for (final coinName in AppConstants.regularCoins) {
      if (symbol == coinName ||
          symbol == '${coinName}USDT' ||
          symbol == '${coinName}USD' ||
          symbol.startsWith('$coinName/')) {
        return false;
      }
    }

    if (!symbol.contains('-')) return false;

    final parts = symbol.split('-');
    if (parts.length < 3) return false;

    final datePart = parts[1];
    if (datePart.length < 6 ||
        !datePart.contains(RegExp(r'[0-9]')) ||
        !datePart.contains(RegExp(r'[A-Z]'))) {
      return false;
    }

    final volume = double.tryParse(json['volume24h']?.toString() ?? '0') ?? 0.0;
    return volume > AppConstants.minVolume24h;
  }
}
