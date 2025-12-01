import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'crypto_api_service.dart';
import '../config/app_constants.dart';

/// Сервис для моковых данных портфеля
/// Легко переключиться на реальные данные, заменив вызовы на реальный API
class MockPortfolioService {
  // Флаг для переключения между моковыми и реальными данными
  // По умолчанию true (моковые данные), можно изменить на false для реальных данных
  static const bool _defaultUseMockData = true; // Значение по умолчанию
  static bool _useMockData = _defaultUseMockData;
  static bool get useMockData => _useMockData;

  // Ключ для сохранения настройки
  static const String _prefsKey = AppConstants.prefsKeyUseMockData;

  /// Инициализация - загружает настройку из SharedPreferences
  /// Если значение изменено в коде (не равно дефолтному), оно сохраняется в SharedPreferences
  /// и имеет приоритет
  static Future<void> init({bool forceLoadFromPrefs = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Если значение было изменено в коде (не равно дефолтному) и не принудительная загрузка
      if (!forceLoadFromPrefs && _useMockData != _defaultUseMockData) {
        // Значение изменено в коде - сохраняем его в SharedPreferences
        await prefs.setBool(_prefsKey, _useMockData);
        return;
      }

      // Загружаем из SharedPreferences, если есть сохраненное значение
      if (prefs.containsKey(_prefsKey)) {
        _useMockData = prefs.getBool(_prefsKey) ?? _defaultUseMockData;
      } else {
        // Если в SharedPreferences нет значения, используем текущее (которое может быть изменено в коде)
        // или значение по умолчанию
        _useMockData = _useMockData;
      }
    } catch (e) {
      // Если ошибка, оставляем текущее значение _useMockData
    }
  }

  /// Сброс настройки - удаляет сохраненное значение из SharedPreferences
  /// и использует значение по умолчанию из кода
  static Future<void> reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
      _useMockData = _defaultUseMockData;
    } catch (e) {
      _useMockData = _defaultUseMockData;
    }
  }

  /// Переключение между моковыми и реальными данными
  /// [useMock] - true для моковых данных, false для реальных
  static Future<void> setUseMockData(bool useMock) async {
    _useMockData = useMock;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, useMock);
    } catch (e) {
      // Если ошибка сохранения, продолжаем с текущим значением
    }
  }

  // Начальный баланс портфеля
  static const double initialBalance = 12500.0;
  static const double initialBtc = 0.15;
  static const double initialEth = 2.5;
  // USDT в Funding аккаунте - для спот-торговли нужны USDT
  static const double initialUsdt =
      0.0; // USDT в Funding для торговли (убран баланс 5000)
  // USDT в Unified Trading аккаунте - для фьючерсов
  static const double initialUnifiedUsdt =
      4427.0; // USDT в Unified Trading для фьючерсов (начальный баланс 4427 USD)

  // Кэш для текущих цен (обновляются из API)
  static double _btcPrice = 91000.0; // Дефолтная цена
  static double _ethPrice = 3000.0; // Дефолтная цена
  static double _solPrice = 150.0; // Дефолтная цена SOL
  static double _ltcPrice = 80.0; // Дефолтная цена LTC
  static DateTime? _lastPriceUpdate;
  static const Duration _priceCacheDuration = AppConstants.priceCacheDuration;

  /// Получить текущие цены из API (с кэшированием)
  static Future<void> _updatePrices({bool force = false}) async {
    // Если цены недавно обновлялись и не принудительное обновление, не делаем запрос
    if (!force &&
        _lastPriceUpdate != null &&
        DateTime.now().difference(_lastPriceUpdate!) < _priceCacheDuration) {
      return;
    }

    try {
      // Получаем текущие цены BTC, ETH, SOL, LTC из API
      final btcCoin = await CryptoApiService.getCoinById('BTCUSDT');
      final ethCoin = await CryptoApiService.getCoinById('ETHUSDT');
      final solCoin = await CryptoApiService.getCoinById('SOLUSDT');
      final ltcCoin = await CryptoApiService.getCoinById('LTCUSDT');

      if (btcCoin != null && btcCoin.price > 0) {
        _btcPrice = btcCoin.price;
        _lastPriceUpdate = DateTime.now();
      }
      if (ethCoin != null && ethCoin.price > 0) {
        _ethPrice = ethCoin.price;
        _lastPriceUpdate = DateTime.now();
      }
      if (solCoin != null && solCoin.price > 0) {
        _solPrice = solCoin.price;
        _lastPriceUpdate = DateTime.now();
      }
      if (ltcCoin != null && ltcCoin.price > 0) {
        _ltcPrice = ltcCoin.price;
        _lastPriceUpdate = DateTime.now();
      }
    } catch (e) {
      // В случае ошибки используем последние известные цены или дефолтные
      // Не обновляем _lastPriceUpdate, чтобы попробовать снова при следующем запросе
      print('Ошибка обновления цен: $e');
    }
  }

  /// Получить текущую цену BTC (с обновлением из API)
  static Future<double> getBtcPrice({bool force = false}) async {
    await _updatePrices(force: force);
    return _btcPrice;
  }

  /// Получить текущую цену BTC (синхронно, из кэша)
  static double get btcPrice => _btcPrice;

  /// Получить текущую цену ETH (с обновлением из API)
  static Future<double> getEthPrice({bool force = false}) async {
    await _updatePrices(force: force);
    return _ethPrice;
  }

  /// Получить текущую цену ETH (синхронно, из кэша)
  static double get ethPrice => _ethPrice;

  /// Получить текущую цену SOL (с обновлением из API)
  static Future<double> getSolPrice({bool force = false}) async {
    await _updatePrices(force: force);
    return _solPrice;
  }

  /// Получить текущую цену SOL (синхронно, из кэша)
  static double get solPrice => _solPrice;

  /// Получить текущую цену LTC (с обновлением из API)
  static Future<double> getLtcPrice({bool force = false}) async {
    await _updatePrices(force: force);
    return _ltcPrice;
  }

  /// Получить текущую цену LTC (синхронно, из кэша)
  static double get ltcPrice => _ltcPrice;

  /// Принудительно обновить все цены из API
  static Future<void> refreshPrices() async {
    await _updatePrices(force: true);
  }

  /// Обновить цены на основе списка криптовалют (для синхронизации с главным экраном)
  static void updatePricesFromCryptoList(List<dynamic> cryptoList) {
    for (var crypto in cryptoList) {
      String symbol;
      double price;

      if (crypto is Map) {
        symbol =
            (crypto['symbol'] ?? crypto['pair'] ?? '').toString().toUpperCase();
        price = (crypto['price'] ?? 0).toDouble();
      } else {
        // Если это CryptoModel
        symbol = crypto.symbol.toUpperCase();
        price = crypto.price;
      }

      // Нормализуем символ (убираем USDT, USD, / и т.д.)
      final normalizedSymbol = symbol
          .replaceAll('USDT', '')
          .replaceAll('USD', '')
          .replaceAll('/', '')
          .replaceAll('-', '')
          .toUpperCase();

      // Обновляем цены для известных криптовалют
      if (normalizedSymbol == 'BTC' && price > 0) {
        _btcPrice = price;
        _lastPriceUpdate = DateTime.now();
      } else if (normalizedSymbol == 'ETH' && price > 0) {
        _ethPrice = price;
        _lastPriceUpdate = DateTime.now();
      } else if (normalizedSymbol == 'SOL' && price > 0) {
        _solPrice = price;
        _lastPriceUpdate = DateTime.now();
      } else if (normalizedSymbol == 'LTC' && price > 0) {
        _ltcPrice = price;
        _lastPriceUpdate = DateTime.now();
      }
    }
  }

  // Текущие балансы (могут изменяться)
  static double get totalUsd => _calculateTotalUsd();

  // BTC эквивалент общего баланса (totalUsd / btcPrice)
  static double get totalBtc {
    if (_btcPrice > 0) {
      return totalUsd / _btcPrice;
    }
    return initialBtc; // Fallback если цена еще не загружена
  }

  // Используем переменные вместо констант, чтобы можно было изменять балансы при переводах
  static double _currentFundingUsdt = initialUsdt;
  static double _currentUnifiedUsdt = initialUnifiedUsdt;

  // Funding баланс = USDT в Funding аккаунте (для спот-торговли)
  static double get fundingBalance => _currentFundingUsdt;

  // Доступный баланс для торговли = USDT в Funding (для спота)
  static double get availableUsd => _currentFundingUsdt;

  // USDT в Unified Trading аккаунте (для фьючерсов)
  static double get unifiedTradingUsd => _currentUnifiedUsdt;

  // Фиксация P&L при закрытии позиции - добавляет реализованный P&L к балансу
  static void realizePnl(double pnl) {
    _currentUnifiedUsdt += pnl;
    // Обнуляем нереализованный P&L этой позиции (уже учтен в балансе)
    // Уведомляем об изменении баланса
    balanceNotifier.value = unifiedTradingBalance;
  }

  // Используемый баланс (заблокирован в ордерах)
  static double get usedUsd => 0.0;

  // Нереализованный P&L от открытых позиций (обновляется из TradeScreen)
  static double _unrealizedPnl = 0.0;

  // ValueNotifier для уведомления об изменениях баланса
  static final ValueNotifier<double> balanceNotifier =
      ValueNotifier<double>(0.0);

  // Установить нереализованный P&L от позиций
  static void setUnrealizedPnl(double pnl) {
    _unrealizedPnl = pnl;
    // Уведомляем об изменении баланса
    balanceNotifier.value = unifiedTradingBalance;
  }

  // Unified Trading баланс = USDT + нереализованный P&L (связан с позициями)
  // Использует текущие цены из кэша
  static double get unifiedTradingBalance {
    final usdtValue = _currentUnifiedUsdt; // USDT в Unified Trading
    return usdtValue +
        _unrealizedPnl; // Баланс + нереализованный P&L от позиций
  }

  // Перевод средств между аккаунтами (моковая реализация)
  static Future<Map<String, dynamic>> transferBetweenAccounts({
    required String coin,
    required String amount,
    required String fromAccountType, // 'FUND' или 'UNIFIED'
    required String toAccountType, // 'FUND' или 'UNIFIED'
  }) async {
    final transferAmount = double.tryParse(amount) ?? 0.0;

    if (transferAmount <= 0) {
      throw Exception('Сумма перевода должна быть больше нуля');
    }

    // Проверяем достаточность средств
    if (fromAccountType == 'FUND') {
      if (transferAmount > _currentFundingUsdt) {
        throw Exception('Недостаточно средств в аккаунте финансирования');
      }
      _currentFundingUsdt -= transferAmount;
    } else if (fromAccountType == 'UNIFIED') {
      if (transferAmount > _currentUnifiedUsdt) {
        throw Exception('Недостаточно средств в едином торговом аккаунте');
      }
      _currentUnifiedUsdt -= transferAmount;
    }

    // Добавляем средства в целевой аккаунт
    if (toAccountType == 'FUND') {
      _currentFundingUsdt += transferAmount;
    } else if (toAccountType == 'UNIFIED') {
      _currentUnifiedUsdt += transferAmount;
    }

    // Уведомляем об изменении баланса сразу после перевода
    balanceNotifier.value = unifiedTradingBalance;

    // Имитируем небольшую задержку (уменьшена для быстрого обновления)
    await Future.delayed(Duration(milliseconds: 100));

    return {
      'transferId': DateTime.now().millisecondsSinceEpoch.toString(),
      'status': 'SUCCESS',
    };
  }

  // Сброс балансов к начальным значениям (для тестирования)
  static void resetBalances() {
    _currentFundingUsdt = initialUsdt;
    _currentUnifiedUsdt = initialUnifiedUsdt;
    _unrealizedPnl = 0.0;
  }

  // P&L за сегодня (моковое значение)
  // Рассчитывается реалистично относительно общего P&L за 180 дней (+847)
  // Средний дневной P&L = 847/180 ≈ 4.7 USD, за сегодня может быть от 0 до ~30 USD
  static double get pnlToday {
    // Используем фиксированный seed для стабильности, но с небольшими вариациями
    final random = math.Random(DateTime.now().day); // Меняется каждый день
    // Средний дневной P&L за 180 дней ≈ 4.7 USD
    // За сегодня может быть от -10 до +30 USD (реалистичные колебания)
    return (random.nextDouble() * 40 - 10)
        .clamp(-10.0, 30.0); // От -10 до +30 USD
  }

  // Расчет общего баланса в USD (использует текущие цены из кэша)
  // Включает: USDT из Funding + SOL и LTC из Unified Trading
  static double _calculateTotalUsd() {
    final fundingUsdt = _currentFundingUsdt; // USDT в Funding
    final unifiedUsdt = _currentUnifiedUsdt; // USDT в Unified Trading
    // Добавляем нереализованный P&L к общему балансу
    return fundingUsdt + unifiedUsdt + _unrealizedPnl;
  }

  /// Генерирует историю портфеля для графика активов
  /// Начинается с начального баланса и показывает реалистичный рост с колебаниями
  static List<FlSpot> getPortfolioHistory(String period) {
    final days = _getDaysForPeriod(period);
    final spots = <FlSpot>[];
    // Разные seed для разных периодов, чтобы графики были разными
    final seed = period.hashCode;
    final random = math.Random(seed);

    // Начальная точка = реальный баланс портфеля
    final startValue = _calculateTotalUsd(); // ~9427 USD
    double currentValue = startValue;

    // Количество циклов зависит от периода (разное для каждого периода)
    final numCycles = period == '7d'
        ? 1
        : (period == '30d'
            ? 2
            : (period == '60d'
                ? 2
                : (period == '90d' ? 3 : 4))); // 60d: 2, 90d: 3, 180d: 4
    // Разная амплитуда для разных периодов
    final amplitude = period == '7d'
        ? startValue * 0.05
        : (period == '30d'
            ? startValue * 0.07
            : (period == '60d'
                ? startValue * 0.08
                : (period == '90d' ? startValue * 0.09 : startValue * 0.10)));

    for (int i = 0; i <= days; i++) {
      final dayProgress = i / days; // Прогресс от 0 до 1
      final isLastPoint = i == days; // Последняя точка должна быть на максимуме

      // Определяем, в каком цикле мы находимся
      // Для последней точки используем последний цикл
      final cycleIndex = isLastPoint
          ? (numCycles - 1)
          : ((dayProgress * numCycles).floor().clamp(0, numCycles - 1));
      final cycleProgress = isLastPoint
          ? 1.0
          : ((dayProgress * numCycles) - cycleIndex).clamp(0.0, 1.0);

      // Создаем синусоидальную волну для каждого цикла
      double cycleWave;

      if (isLastPoint) {
        // Последняя точка всегда на максимуме (подъем)
        cycleWave = 1.0;
      } else if (cycleIndex == 0) {
        // Первый цикл: подъем, затем небольшое падение
        cycleWave = math.sin(cycleProgress * math.pi);
      } else if (cycleIndex == 1 && numCycles >= 2) {
        // Второй цикл: небольшое падение, затем подъем
        cycleWave = -math.sin(cycleProgress * math.pi) *
            0.6; // Уменьшаем падение на 40%
      } else if (cycleIndex == 2 && numCycles >= 3) {
        // Третий цикл: подъем, затем небольшое падение (для 90d)
        if (numCycles == 3) {
          cycleWave = math.sin(cycleProgress * math.pi * 0.5); // Только подъем
        } else {
          // Для 180d (4 цикла) - третий цикл: падение, затем подъем
          cycleWave = -math.sin(cycleProgress * math.pi) * 0.5;
        }
      } else if (cycleIndex == 3 && numCycles >= 4) {
        // Четвертый цикл (последний для 180d): подъем до конца
        cycleWave = math.sin(cycleProgress * math.pi * 0.5); // Только подъем
      } else {
        // Для последнего цикла всегда подъем
        cycleWave = math.sin(cycleProgress * math.pi * 0.5);
      }

      // Добавляем небольшие случайные колебания для реалистичности
      final noise = (random.nextDouble() * 0.04 - 0.02); // ±2% шума

      // Вычисляем значение с учетом цикла и небольшого общего роста
      final cycleValue = amplitude * cycleWave;
      final trend = i * 0.15; // Небольшой общий тренд роста
      currentValue = startValue + cycleValue + trend + (startValue * noise);

      // Минимальное значение не должно быть слишком низким
      if (currentValue < startValue * 0.75) {
        currentValue = startValue * 0.75 + random.nextDouble() * 300;
      }

      spots.add(FlSpot(i.toDouble(), currentValue));
    }

    return spots;
  }

  /// Генерирует историю P&L (прибыль/убыток)
  /// Целевые значения: 180d = +847, 90d = +423.50, 60d = +282.33, 30d = +141.17, 7d = +32.94
  /// Реалистичный график с циклами подъемов и падений (разное количество для разных периодов)
  static List<FlSpot> getPnlHistory(String period) {
    final days = _getDaysForPeriod(period);
    final spots = <FlSpot>[];
    // Разные seed для разных периодов, чтобы графики были разными
    final seed = period.hashCode + 1000;
    final random = math.Random(seed);

    // Целевые значения P&L для каждого периода
    final targetPnl = {
      '7d': 32.94,
      '30d': 141.17,
      '60d': 282.33,
      '90d': 423.50,
      '180d': 847.0,
    };

    final targetValue = targetPnl[period] ?? 0.0;
    double cumulativePnl = 0.0;

    // Количество циклов зависит от периода (разное для каждого периода)
    final numCycles = period == '7d'
        ? 1
        : (period == '30d'
            ? 2
            : (period == '60d'
                ? 2
                : (period == '90d' ? 3 : 4))); // 60d: 2, 90d: 3, 180d: 4
    // Разная амплитуда для разных периодов
    final amplitude = period == '7d'
        ? targetValue * 0.20
        : (period == '30d'
            ? targetValue * 0.22
            : (period == '60d'
                ? targetValue * 0.24
                : (period == '90d' ? targetValue * 0.26 : targetValue * 0.28)));

    for (int i = 0; i <= days; i++) {
      final dayProgress = i / days; // Прогресс от 0 до 1
      final isLastPoint = i == days; // Последняя точка должна быть на максимуме

      // Определяем, в каком цикле мы находимся
      // Для последней точки используем последний цикл
      final cycleIndex = isLastPoint
          ? (numCycles - 1)
          : ((dayProgress * numCycles).floor().clamp(0, numCycles - 1));
      final cycleProgress = isLastPoint
          ? 1.0
          : ((dayProgress * numCycles) - cycleIndex).clamp(0.0, 1.0);

      // Создаем синусоидальную волну для каждого цикла
      double cycleWave;

      if (isLastPoint) {
        // Последняя точка всегда на максимуме (подъем)
        cycleWave = 1.0;
      } else if (cycleIndex == 0) {
        // Первый цикл: подъем, затем небольшое падение
        cycleWave = math.sin(cycleProgress * math.pi);
      } else if (cycleIndex == 1 && numCycles >= 2) {
        // Второй цикл: небольшое падение, затем подъем
        cycleWave = -math.sin(cycleProgress * math.pi) *
            0.6; // Уменьшаем падение на 40%
      } else if (cycleIndex == 2 && numCycles >= 3) {
        // Третий цикл: подъем, затем небольшое падение (для 90d)
        if (numCycles == 3) {
          cycleWave = math.sin(cycleProgress * math.pi * 0.5); // Только подъем
        } else {
          // Для 180d (4 цикла) - третий цикл: падение, затем подъем
          cycleWave = -math.sin(cycleProgress * math.pi) * 0.5;
        }
      } else if (cycleIndex == 3 && numCycles >= 4) {
        // Четвертый цикл (последний для 180d): подъем до конца
        cycleWave = math.sin(cycleProgress * math.pi * 0.5); // Только подъем
      } else {
        // Для последнего цикла всегда подъем
        cycleWave = math.sin(cycleProgress * math.pi * 0.5);
      }

      // Вычисляем базовое значение P&L с учетом цикла
      final cycleValue = amplitude * cycleWave;
      final trend =
          targetValue * dayProgress; // Общий тренд к целевому значению

      // Добавляем небольшие случайные колебания для реалистичности
      final noise =
          targetValue * (random.nextDouble() * 0.06 - 0.03) / days; // ±3% шума

      cumulativePnl = cycleValue + trend + noise;

      // Корректируем последнюю точку, чтобы точно попасть в цель
      if (i == days) {
        cumulativePnl = targetValue;
      }

      spots.add(FlSpot(i.toDouble(), cumulativePnl));
    }

    // Финальная гарантия: последнее значение точно равно цели
    if (spots.isNotEmpty) {
      spots[spots.length - 1] = FlSpot(days.toDouble(), targetValue);
    }

    return spots;
  }

  /// Генерирует суточный P&L (каждый день отдельно)
  /// Значения рассчитываются так, чтобы сумма соответствовала целевым значениям:
  /// 180d = +847, 90d = +423.50, 60d = +282.33, 30d = +141.17, 7d = +32.94
  static List<FlSpot> getDailyPnlHistory(String period) {
    final days = _getDaysForPeriod(period);
    final spots = <FlSpot>[];
    final random = math.Random(456); // Фиксированный seed для стабильности

    // Целевые значения P&L для каждого периода
    final targetPnl = {
      '7d': 32.94,
      '30d': 141.17,
      '60d': 282.33,
      '90d': 423.50,
      '180d': 847.0,
    };

    final targetValue = targetPnl[period] ?? 0.0;
    final avgDailyPnl = targetValue / days;
    double totalPnl = 0.0;

    // Генерируем дневные значения с корректировкой, чтобы сумма была равна цели
    for (int i = 0; i <= days; i++) {
      double dailyPnl;

      if (i == days) {
        // Последний день: корректируем, чтобы сумма была точно равна цели
        final remainingPnl = targetValue - totalPnl;
        // Ограничиваем последнее значение, чтобы оно было реалистичным (от 30% до 200% от среднего)
        final minDailyPnl = avgDailyPnl * 0.3;
        final maxDailyPnl = avgDailyPnl * 2.0;
        dailyPnl = remainingPnl.clamp(minDailyPnl, maxDailyPnl);

        // Если ограничение слишком сильное, распределяем остаток на предыдущие дни
        if (dailyPnl != remainingPnl && i > 0) {
          final diff = remainingPnl - dailyPnl;
          // Распределяем разницу на последние несколько дней
          final daysToAdjust = math.min(5, i);
          final adjustmentPerDay = diff / daysToAdjust;
          for (int j = spots.length - daysToAdjust; j < spots.length; j++) {
            if (j >= 0) {
              spots[j] = FlSpot(spots[j].x, spots[j].y + adjustmentPerDay);
              totalPnl += adjustmentPerDay;
            }
          }
          // Пересчитываем последнее значение
          dailyPnl = targetValue - totalPnl;
        }
      } else {
        // Генерируем реалистичный дневной P&L
        // Средний дневной P&L варьируется от 40% до 200% от среднего (улучшено с 50%)
        final variation = 0.4 + random.nextDouble() * 1.6; // От 0.4 до 2.0
        dailyPnl = avgDailyPnl * variation;

        // Иногда добавляем более сильные колебания (15% шанс, уменьшено с 20%)
        if (random.nextDouble() < 0.15) {
          final spike =
              random.nextDouble() < 0.3 ? -1.0 : 1.0; // 30% отрицательных
          dailyPnl = avgDailyPnl * (1.5 + random.nextDouble() * 2.5) * spike;
        }

        // Корректировка для приближения к цели
        final progress = i / days;
        final remainingPnl = targetValue - totalPnl;
        final remainingDays = days - i;
        if (remainingDays > 0 && remainingPnl.abs() > 0.01) {
          // Корректировка становится сильнее ближе к концу периода
          final correctionFactor = 0.15 + (progress * 0.25); // От 15% до 40%
          final adjustment = (remainingPnl / remainingDays) * correctionFactor;
          dailyPnl += adjustment;
        }

        // Гарантируем минимальное значение (30% от среднего)
        dailyPnl = math.max(dailyPnl, avgDailyPnl * 0.3);
      }

      totalPnl += dailyPnl;
      spots.add(FlSpot(i.toDouble(), dailyPnl));
    }

    // Финальная корректировка: убеждаемся, что сумма точно равна цели
    if (spots.isNotEmpty) {
      final finalTotal =
          spots.map((s) => s.y).fold(0.0, (sum, val) => sum + val);
      final diff = targetValue - finalTotal;
      if (diff.abs() > 0.01 && spots.length > 1) {
        // Распределяем разницу на последние несколько дней
        final daysToAdjust = math.min(3, spots.length - 1);
        final adjustmentPerDay = diff / daysToAdjust;
        for (int j = spots.length - daysToAdjust - 1;
            j < spots.length - 1;
            j++) {
          if (j >= 0) {
            spots[j] = FlSpot(spots[j].x, spots[j].y + adjustmentPerDay);
          }
        }
        // Последний день получает остаток
        spots[spots.length - 1] = FlSpot(
          spots[spots.length - 1].x,
          targetValue -
              spots
                  .sublist(0, spots.length - 1)
                  .map((s) => s.y)
                  .fold(0.0, (sum, val) => sum + val),
        );
      }
    }

    return spots;
  }

  /// Генерирует кумулятивный суточный P&L (накопленная сумма всех дневных P&L)
  /// Начинается с начального значения и показывает 3 цикла подъемов и падений
  static List<FlSpot> getCumulativeDailyPnlHistory(String period) {
    final days = _getDaysForPeriod(period);
    final spots = <FlSpot>[];
    // Разные seed для разных периодов, чтобы графики были разными
    final seed = period.hashCode + 2000;
    final random = math.Random(seed);

    // Начальное значение = 4427 USD (баланс единого торгового аккаунта)
    final initialValue = 4427.0; // Начальный баланс единого торгового аккаунта

    final targetValue = AppConstants.targetPnl[period] ?? 0.0;
    final numCycles = AppConstants.periodCycles[period] ?? 1;
    // Разная амплитуда для разных периодов
    final amplitude = period == '7d'
        ? targetValue * 0.20
        : (period == '30d'
            ? targetValue * 0.22
            : (period == '60d'
                ? targetValue * 0.24
                : (period == '90d' ? targetValue * 0.26 : targetValue * 0.28)));

    for (int i = 0; i <= days; i++) {
      final dayProgress = i / days; // Прогресс от 0 до 1
      final isLastPoint = i == days; // Последняя точка должна быть на максимуме

      // Определяем, в каком цикле мы находимся
      // Для последней точки используем последний цикл
      final cycleIndex = isLastPoint
          ? (numCycles - 1)
          : ((dayProgress * numCycles).floor().clamp(0, numCycles - 1));
      final cycleProgress = isLastPoint
          ? 1.0
          : ((dayProgress * numCycles) - cycleIndex).clamp(0.0, 1.0);

      // Создаем синусоидальную волну для каждого цикла
      double cycleWave;

      if (isLastPoint) {
        // Последняя точка всегда на максимуме (подъем)
        cycleWave = 1.0;
      } else if (cycleIndex == 0) {
        // Первый цикл: подъем, затем небольшое падение
        cycleWave = math.sin(cycleProgress * math.pi);
      } else if (cycleIndex == 1 && numCycles >= 2) {
        // Второй цикл: небольшое падение, затем подъем
        cycleWave = -math.sin(cycleProgress * math.pi) *
            0.6; // Уменьшаем падение на 40%
      } else if (cycleIndex == 2 && numCycles >= 3) {
        // Третий цикл: подъем, затем небольшое падение (для 90d)
        if (numCycles == 3) {
          cycleWave = math.sin(cycleProgress * math.pi * 0.5); // Только подъем
        } else {
          // Для 180d (4 цикла) - третий цикл: падение, затем подъем
          cycleWave = -math.sin(cycleProgress * math.pi) * 0.5;
        }
      } else if (cycleIndex == 3 && numCycles >= 4) {
        // Четвертый цикл (последний для 180d): подъем до конца
        cycleWave = math.sin(cycleProgress * math.pi * 0.5); // Только подъем
      } else {
        // Для последнего цикла всегда подъем
        cycleWave = math.sin(cycleProgress * math.pi * 0.5);
      }

      // Вычисляем базовое значение P&L с учетом цикла
      final cycleValue = amplitude * cycleWave;
      final trend =
          targetValue * dayProgress; // Общий тренд к целевому значению

      // Добавляем небольшие случайные колебания для реалистичности
      final noise =
          targetValue * (random.nextDouble() * 0.06 - 0.03) / days; // ±3% шума

      final cumulativePnl = cycleValue + trend + noise;
      final cumulativeValue = initialValue + cumulativePnl;

      // Корректируем последнюю точку, чтобы точно попасть в цель
      if (i == days) {
        final finalValue = initialValue + targetValue;
        spots.add(FlSpot(i.toDouble(), finalValue));
      } else {
        spots.add(FlSpot(i.toDouble(), cumulativeValue));
      }
    }

    // Финальная корректировка последнего значения
    if (spots.isNotEmpty) {
      final finalValue = initialValue + targetValue;
      spots[spots.length - 1] = FlSpot(days.toDouble(), finalValue);
    }

    return spots;
  }

  /// Генерирует историю стоимости ордеров
  /// Реалистичные значения пропорциональны размеру портфеля (~$4400)
  /// За 180 дней можно сделать несколько оборотов, но не десятки тысяч
  static Map<String, List<FlSpot>> getOrderValueHistory(String period,
      {bool isFutures = false}) {
    final days = _getDaysForPeriod(period);
    final random = math.Random(789);

    // Размер портфеля для расчета реалистичного объема
    final portfolioSize = totalUsd; // ~$4400 (SOL + LTC)

    // Для бессрочных и фьючерсов используем меньшие объемы
    // Деривативы обычно имеют меньший объем торговли
    // Более реалистичные значения: небольшие ежедневные объемы
    final minDailyPercent =
        isFutures ? 0.005 : 0.01; // 0.5% для фьючерсов, 1% для спота
    final maxDailyPercent =
        isFutures ? 0.02 : 0.05; // 2% для фьючерсов, 5% для спота

    final totalOrderValue = <FlSpot>[];
    final purchaseValue = <FlSpot>[];
    final saleValue = <FlSpot>[];

    for (int i = 0; i <= days; i++) {
      // Дневной объем: от minDailyPercent до maxDailyPercent от портфеля
      final dailyPercent = minDailyPercent +
          random.nextDouble() * (maxDailyPercent - minDailyPercent);
      final total = portfolioSize * dailyPercent;

      // Покупки обычно больше продаж (60/40)
      final purchase = total * (0.5 + random.nextDouble() * 0.2);
      final sale = total - purchase;

      totalOrderValue.add(FlSpot(i.toDouble(), total));
      purchaseValue.add(FlSpot(i.toDouble(), purchase));
      saleValue.add(FlSpot(i.toDouble(), sale));
    }

    return {
      'total': totalOrderValue,
      'purchase': purchaseValue,
      'sale': saleValue,
    };
  }

  /// Получает количество дней для периода
  static int getDaysForPeriod(String period) {
    return AppConstants.periodDays[period] ?? 7;
  }

  /// Внутренний метод для получения дней (используется внутри класса)
  static int _getDaysForPeriod(String period) => getDaysForPeriod(period);

  /// Получает данные для распределения активов (использует текущие цены)
  static Map<String, double> getAssetDistribution() {
    // Активы теперь связаны с позициями, а не хранятся отдельно
    return {
      'USDT': _currentUnifiedUsdt + _unrealizedPnl,
    };
  }

  /// Получает список всех монет с балансами (формат как в API)
  /// Использует текущие цены из кэша
  static List<Map<String, dynamic>> getCoinsList() {
    final coins = <Map<String, dynamic>>[];

    // Funding Account - USDT для спот-торговли (только если есть баланс)
    if (_currentFundingUsdt > 0) {
      coins.add({
        'coin': 'USDT',
        'equity': _currentFundingUsdt,
        'usdValue': _currentFundingUsdt, // USDT = 1 USD
        'accountType': 'FUND',
      });
    }

    // Unified Trading Account - только USDT (SOL и LTC убраны, они теперь в позициях)
    // USDT в Unified Trading (только если есть баланс или нереализованный P&L)
    // Включаем нереализованный P&L в USDT для Unified Trading аккаунта
    final unifiedUsdtWithPnl = _currentUnifiedUsdt + _unrealizedPnl;
    if (_currentUnifiedUsdt > 0 || _unrealizedPnl != 0.0) {
      coins.add({
        'coin': 'USDT',
        'equity': unifiedUsdtWithPnl, // Включаем нереализованный P&L
        'usdValue': unifiedUsdtWithPnl, // USDT = 1 USD, включая P&L
        'accountType': 'UNIFIED',
      });
    }

    return coins;
  }

  /// Получает статистику торговли
  static Map<String, String> getTradingStats() {
    return {
      'totalProfit': '+1,234.56',
      'totalLoss': '-456.78',
      'netPnl': '+777.78',
      'roi': '+6.22%',
      'winRate': '68.5%',
      'totalTrades': '127',
    };
  }
}
