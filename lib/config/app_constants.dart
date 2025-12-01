/// Константы приложения
class AppConstants {
  AppConstants._();

  // API константы
  static const String bybitBaseUrl = 'https://api.bybit.com';
  static const int defaultPerPage = 50;
  static const int maxPerPage = 200;
  // Оптимизация: загружаем меньше данных для быстрой загрузки
  static const int optimizedPerPage = 100; // Вместо 200 для ускорения
  static const Duration priceCacheDuration = Duration(seconds: 30);
  static const Duration requestTimeout = Duration(seconds: 10);

  // Минимальные объемы для фильтрации
  static const double minVolume24h = 100.0;
  static const double minVolume24hDerivatives = 100000.0;
  static const double minVolume24hAlpha = 10000.0;
  static const double maxVolume24hAlpha = 500000000.0;

  // Стабильные монеты
  static const List<String> stablecoinSymbols = [
    'USDT',
    'USDC',
    'BUSD',
    'DAI',
    'TUSD',
  ];

  // Популярные монеты (для исключения из Alpha)
  static const List<String> topCoins = [
    'BTC',
    'ETH',
    'BNB',
    'SOL',
    'XRP',
    'ADA',
    'DOGE',
    'MATIC',
    'AVAX',
    'DOT',
    'LINK',
    'UNI',
    'ATOM',
    'LTC',
    'ETC',
  ];

  // Обычные монеты (для фильтрации опционов)
  static const List<String> regularCoins = [
    'BTC',
    'ETH',
    'BNB',
    'SOL',
    'XRP',
    'ADA',
    'DOGE',
    'MATIC',
    'AVAX',
    'DOT',
    'LINK',
    'UNI',
    'ATOM',
    'LTC',
    'ETC',
    'TRX',
    'NEAR',
    'APT',
    'ARB',
    'OP',
    'SUI',
    'SEI',
    'VET',
    'FIL',
    'ICP',
  ];

  // Базовые активы для опционов
  static const List<String> optionBaseCoins = [
    'BTC',
    'ETH',
    'SOL',
    'MNT',
    'XRP',
    'BNB',
  ];

  // Критерии для TradFi
  static const double tradfiMinPrice = 0.98;
  static const double tradfiMaxPrice = 1.02;
  static const double tradfiMaxVolatility = 0.5;

  // Критерии для Alpha
  static const double alphaMinChange24h = 0.0;

  // Интервалы для графиков
  static const Map<String, String> intervalMapping = {
    '15мин.': '15',
    '1Ч': '60',
    '4Ч': '240',
    '1Д': 'D',
  };

  // Периоды для графиков
  static const Map<String, int> periodDays = {
    '7d': 7,
    '30d': 30,
    '60d': 60,
    '90d': 90,
    '180d': 180,
  };

  // Целевые значения P&L для периодов
  static const Map<String, double> targetPnl = {
    '7d': 32.94,
    '30d': 141.17,
    '60d': 282.33,
    '90d': 423.50,
    '180d': 847.0,
  };

  // Количество циклов для графиков по периодам
  static const Map<String, int> periodCycles = {
    '7d': 1,
    '30d': 2,
    '60d': 2,
    '90d': 3,
    '180d': 4,
  };

  // SharedPreferences ключи
  static const String prefsKeyUseMockData = 'use_mock_portfolio_data';
  static const String prefsKeyFavoriteCoins = 'favorite_coins_';

  // UI константы
  static const double defaultBorderRadius = 8.0;
  static const double cardBorderRadius = 14.0;
  static const double buttonBorderRadius = 22.0;
  static const double iconSize = 24.0;
  static const double smallIconSize = 18.0;
}

