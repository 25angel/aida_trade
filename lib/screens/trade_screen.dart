import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_theme.dart';
import '../config/app_constants.dart';
import '../services/crypto_api_service.dart';
import '../services/mock_portfolio_service.dart';
import '../services/bybit_websocket_service.dart';
import '../models/crypto_model.dart';

class TradeScreen extends StatefulWidget {
  final String? initialPair;
  final ValueNotifier<String?>? pairNotifier;

  const TradeScreen({
    super.key,
    this.initialPair,
    this.pairNotifier,
  });

  @override
  State<TradeScreen> createState() => _TradeScreenState();
}

class _TradeScreenState extends State<TradeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  String _selectedPair = 'BTC/USDT';
  String _selectedMainTab = 'График';
  String _selectedPeriod = '15мин.';
  Set<String> _selectedIndicators = {};
  String _selectedOrderTab = 'Книга ордеров';
  String _selectedMarketType =
      'Спот'; // Конвертация, Спот, Фьючерсы, Опцион, TradFi
  bool _showChartView = true; // true = график, false = книжка ордеров
  bool _isBuySelected = true; // true = Купить, false = Продать
  int _leverage =
      1; // Кредитное плечо для фьючерсов (1x, 2x, 5x, 10x, 20x, 50x, 100x)
  String _marginMode =
      'Cross'; // Режим маржи: 'Cross' (Кросс) или 'Isolated' (Изолированная)
  String _selectedOrdersTab =
      'Ордера'; // Ордера, Позиции, Активы, Займы, Инструме
  double _percentageSlider = 0.0; // Значение слайдера (0.0 - 1.0)

  // Данные графика
  List<Map<String, dynamic>> _klines = [];
  CryptoModel? _currentCoin;
  bool _isLoading = false;

  // Данные книги ордеров
  Map<String, dynamic>? _orderBookData;
  bool _isLoadingOrderBook = false;

  // Интерактивность графика
  int? _selectedCandleIndex;
  Offset? _touchPosition;

  // Масштабирование и прокрутка графика
  int _visibleCandles = 50; // Количество видимых свечей
  int _chartStartIndex = 0; // Индекс первой видимой свечи
  double _scaleFactor = 1.0; // Масштаб (1.0 = нормальный)
  Offset _panOffset = Offset.zero; // Смещение при прокрутке
  double _lastScale = 1.0; // Последний масштаб для жеста

  late TabController _indicatorTabController;

  // Таймер для обновления цен в реальном времени
  Timer? _priceUpdateTimer;
  Timer? _orderBookUpdateTimer;
  Timer? _fundingRateTimer;

  // WebSocket для реального времени
  BybitWebSocketService? _websocketService;

  // Funding Rate данные
  double _fundingRate = 0.0011; // 0.0011%
  Duration _fundingRateCountdown = Duration(hours: 1, minutes: 40, seconds: 40);

  // Контроллеры для формы ордера
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _totalController = TextEditingController();

  // Ордера и позиции
  List<Map<String, dynamic>> _orders = []; // Активные ордера
  List<Map<String, dynamic>> _positions = []; // Открытые позиции
  double _availableBalance = 0.0; // Доступный баланс USDT (будет загружен)
  DateTime? _lastPairChangeTime; // Время последнего переключения пары
  Set<String> _positionsBeingClosed = {}; // Позиции, которые уже закрываются

  final List<String> _mainTabs = [
    'График',
    'Обзор',
    'Данные',
    'Лента новостей'
  ];
  final List<String> _periods = ['15мин.', '1Ч', '4Ч', '1Д', 'Ещё'];
  final List<String> _indicators = [
    'MA',
    'EMA',
    'BOLL',
    'SAR',
    'MAVOL',
    'MACD',
    'KDJ',
    'RSI',
    'WR'
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Используем переданную пару или значение по умолчанию
    if (widget.initialPair != null) {
      _selectedPair = widget.initialPair!;
    }
    _indicatorTabController = TabController(
      length: _indicators.length,
      vsync: this,
      initialIndex: 4, // MAVOL selected
    );
    _loadChartData();
    _loadCurrentCoin();
    _loadOrderBook();
    _loadAvailableBalance();
    _connectWebSocket();

    // Инициализация контроллеров
    _priceController.addListener(_onPriceOrQuantityChanged);
    _quantityController.addListener(_onPriceOrQuantityChanged);
    _totalController.addListener(_onTotalChanged);

    // Установить текущую цену в поле цены
    _updatePriceFromCurrentCoin();

    // Слушаем изменения пары извне
    widget.pairNotifier?.addListener(_onPairChanged);

    // Запускаем периодическое обновление цен
    _startPriceUpdates();

    // Загружаем позиции из глобального хранилища
    _loadPositionsFromGlobal();

    // Слушаем изменения в глобальном хранилище позиций
    MockPortfolioService.positionsNotifier
        .addListener(_onGlobalPositionsChanged);
  }

  void _loadPositionsFromGlobal() {
    final globalPositions = MockPortfolioService.getPositions();
    setState(() {
      _positions = List.from(globalPositions);
    });
  }

  void _onGlobalPositionsChanged() {
    if (mounted) {
      _loadPositionsFromGlobal();
      // Обновляем P&L после изменения позиций
      _updateAllPositionsPnl();
    }
  }

  // Сброс масштаба и позиции графика при смене пары или периода
  void _resetChartView() {
    setState(() {
      _visibleCandles = 50;
      _chartStartIndex = 0;
      _scaleFactor = 1.0;
      _panOffset = Offset.zero;
    });
  }

  void _onPairChanged() {
    final newPair = widget.pairNotifier?.value;
    if (newPair != null && _selectedPair != newPair) {
      updateSelectedPair(newPair);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.pairNotifier?.removeListener(_onPairChanged);
    MockPortfolioService.positionsNotifier
        .removeListener(_onGlobalPositionsChanged);
    _priceController.dispose();
    _quantityController.dispose();
    _totalController.dispose();
    _indicatorTabController.dispose();
    // Останавливаем таймеры
    _priceUpdateTimer?.cancel();
    _orderBookUpdateTimer?.cancel();
    _fundingRateTimer?.cancel();
    // Отключаем WebSocket
    _websocketService?.disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Обновляем баланс при возврате приложения в активное состояние
    if (state == AppLifecycleState.resumed) {
      _loadAvailableBalance();
    }
  }

  // Метод для обновления выбранной пары извне
  void updateSelectedPair(String pair) {
    if (_selectedPair != pair) {
      // Сначала обновляем время переключения, чтобы защита сработала сразу
      _lastPairChangeTime = DateTime.now();

      setState(() {
        _selectedPair = pair;
        _klines = []; // Очищаем данные графика сразу при переключении монеты
      });
      _resetChartView(); // Сбрасываем масштаб и позицию
      // Перезагружаем данные для новой пары
      _loadChartData();
      _loadCurrentCoin();
      _loadOrderBook();
      _connectWebSocket();
      _updatePriceFromCurrentCoin();
    }
  }

  void _onPriceOrQuantityChanged() {
    final price =
        double.tryParse(_priceController.text.replaceAll(',', '')) ?? 0.0;
    final quantity =
        double.tryParse(_quantityController.text.replaceAll(',', '')) ?? 0.0;
    final total = price * quantity;
    if (total > 0) {
      _totalController.text = _formatPriceForDisplay(total);
    } else {
      _totalController.text = '';
    }
  }

  void _onTotalChanged() {
    final total =
        double.tryParse(_totalController.text.replaceAll(',', '')) ?? 0.0;
    final price =
        double.tryParse(_priceController.text.replaceAll(',', '')) ?? 0.0;
    if (price > 0 && total > 0) {
      final quantity = total / price;
      _quantityController.text = _formatQuantity(quantity);
    }
  }

  void _updatePriceFromCurrentCoin() {
    if (_currentCoin != null && _currentCoin!.price > 0) {
      _priceController.text = _formatPriceForDisplay(_currentCoin!.price);
    }
  }

  Future<void> _loadAvailableBalance() async {
    try {
      // Используем тот же подход, что и в wallet_screen.dart
      if (MockPortfolioService.useMockData) {
        // Обновляем цены асинхронно (не ждем)
        MockPortfolioService.refreshPrices();
        if (mounted) {
          setState(() {
            // Для спот-торговли используем USDT из Funding аккаунта
            // Для фьючерсов - из Unified Trading аккаунта
            if (_selectedMarketType == 'Фьючерсы') {
              // Для фьючерсов используем USDT из Unified Trading
              double unifiedUsdt = MockPortfolioService.unifiedTradingUsd;

              // Вычитаем замороженную маржу из открытых позиций
              // В Cross режиме маржа общая, в Isolated - отдельная для каждой позиции
              double frozenMargin = 0.0;
              if (_marginMode == 'Cross') {
                // Cross: считаем общую маржу всех позиций
                for (var position in _positions) {
                  final entryPrice = position['entryPrice'] as double;
                  final size = position['size'] as double;
                  final leverage = position['leverage'] as int;
                  frozenMargin += (entryPrice * size) / leverage;
                }
              } else {
                // Isolated: считаем только маржу позиций в изолированном режиме
                for (var position in _positions) {
                  final positionMarginMode =
                      position['marginMode'] as String? ?? 'Isolated';
                  if (positionMarginMode == 'Isolated') {
                    final entryPrice = position['entryPrice'] as double;
                    final size = position['size'] as double;
                    final leverage = position['leverage'] as int;
                    frozenMargin += (entryPrice * size) / leverage;
                  }
                }
              }

              _availableBalance =
                  (unifiedUsdt - frozenMargin).clamp(0.0, double.infinity);
            } else {
              // Для спота используем Funding аккаунт (стандартная логика Bybit)
              // Можно также использовать Unified Trading, если там есть USDT
              // Для гибкости: используем Funding, но если там мало средств,
              // можно добавить логику использования Unified Trading
              _availableBalance = MockPortfolioService.availableUsd;
            }
          });
        }
      } else {
        // Реальные данные из API
        double availableUsdt = 0.0;

        if (_selectedMarketType == 'Фьючерсы') {
          // Для фьючерсов используем Unified Trading аккаунт
          final unified = await CryptoApiService.getUnifiedTradingBalance();

          if (unified['list'] != null && (unified['list'] as List).isNotEmpty) {
            final account = unified['list'][0];
            if (account['coin'] != null) {
              for (var coin in account['coin']) {
                final coinName = coin['coin']?.toString() ?? '';
                // Ищем USDT в Unified Trading аккаунте
                if (coinName == 'USDT') {
                  final equity =
                      double.tryParse(coin['equity']?.toString() ?? '0') ?? 0.0;
                  availableUsdt = equity;
                  break;
                }
              }
            }
          }

          // P&L уже учтен в equity, но для отображения доступного баланса
          // нужно вычесть замороженную маржу
          // В Cross режиме маржа общая, в Isolated - отдельная для каждой позиции
          double frozenMargin = 0.0;
          if (_marginMode == 'Cross') {
            // Cross: считаем общую маржу всех позиций
            for (var position in _positions) {
              final entryPrice = position['entryPrice'] as double;
              final size = position['size'] as double;
              final leverage = position['leverage'] as int;
              frozenMargin += (entryPrice * size) / leverage;
            }
          } else {
            // Isolated: считаем только маржу позиций в изолированном режиме
            for (var position in _positions) {
              final positionMarginMode =
                  position['marginMode'] as String? ?? 'Isolated';
              if (positionMarginMode == 'Isolated') {
                final entryPrice = position['entryPrice'] as double;
                final size = position['size'] as double;
                final leverage = position['leverage'] as int;
                frozenMargin += (entryPrice * size) / leverage;
              }
            }
          }
          availableUsdt = availableUsdt - frozenMargin;
        } else {
          // Для спота используем Funding аккаунт
          final funding = await CryptoApiService.getFundingBalance();

          if (funding['list'] != null && (funding['list'] as List).isNotEmpty) {
            final account = funding['list'][0];
            if (account['coin'] != null) {
              for (var coin in account['coin']) {
                final coinName = coin['coin']?.toString() ?? '';
                // Ищем USDT в Funding аккаунте
                if (coinName == 'USDT') {
                  final equity =
                      double.tryParse(coin['equity']?.toString() ?? '0') ?? 0.0;
                  availableUsdt = equity;
                  break;
                }
              }
            }
          }
        }

        if (mounted) {
          setState(() {
            _availableBalance = availableUsdt;
          });
        }
      }
    } catch (e) {
      // В случае ошибки оставляем текущее значение или 0
      if (mounted) {
        setState(() {
          _availableBalance = 0.0;
        });
      }
    }
  }

  void _handleBuySell() {
    final price =
        double.tryParse(_priceController.text.replaceAll(',', '')) ?? 0.0;
    final quantity =
        double.tryParse(_quantityController.text.replaceAll(',', '')) ?? 0.0;
    final total = price * quantity;

    if (price <= 0 || quantity <= 0) {
      // Показать сообщение об ошибке
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Введите корректные цену и количество'),
          backgroundColor: AppTheme.primaryRed,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_isBuySelected) {
      // Покупка
      if (total > _availableBalance) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Недостаточно средств'),
            backgroundColor: AppTheme.primaryRed,
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      // Для фьючерсов создаем позицию сразу, для спота - ордер
      if (_selectedMarketType == 'Фьючерсы') {
        // Создаем позицию для фьючерсов
        final position = {
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'symbol': _selectedPair.replaceAll('/', ''),
          'pair': _selectedPair,
          'side': 'Long', // Лонг
          'size': quantity,
          'entryPrice': price,
          'markPrice': price, // Начальная маркировочная цена = цене входа
          'leverage': _leverage,
          'marginMode': _marginMode, // Режим маржи (Cross или Isolated)
          'unrealizedPnl': 0.0,
          'unrealizedPnlPercent': 0.0,
          'liquidationPrice':
              _calculateLiquidationPrice(price, quantity, _leverage, true),
          'tpPrice': null, // Take Profit
          'slPrice': null, // Stop Loss
          'partialSize': 0.0,
          'createdAt': DateTime.now(),
        };

        // Добавляем в глобальное хранилище
        MockPortfolioService.addPosition(position);

        setState(() {
          _positions = List.from(MockPortfolioService.getPositions());
        });

        // Обновляем баланс после создания позиции (с учетом замороженной маржи)
        _loadAvailableBalance();
        // Обновляем P&L чтобы обновить балансы (это также уведомит об изменениях)
        _updateAllPositionsPnl();
      } else {
        // Для спота создаем ордер
        final order = {
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'type': 'buy',
          'pair': _selectedPair,
          'price': price,
          'quantity': quantity,
          'total': total,
          'status': 'active', // active, filled, cancelled
          'createdAt': DateTime.now(),
          'orderType': 'limit',
        };

        setState(() {
          _orders.add(order);
          _availableBalance -= total;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ордер на покупку создан'),
            backgroundColor: AppTheme.primaryGreen,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      // Продажа
      if (_selectedMarketType == 'Фьючерсы') {
        // Для фьючерсов создаем шорт позицию
        final position = {
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'symbol': _selectedPair.replaceAll('/', ''),
          'pair': _selectedPair,
          'side': 'Short', // Шорт
          'size': quantity,
          'entryPrice': price,
          'markPrice': price,
          'leverage': _leverage,
          'marginMode': _marginMode, // Режим маржи (Cross или Isolated)
          'unrealizedPnl': 0.0,
          'unrealizedPnlPercent': 0.0,
          'liquidationPrice':
              _calculateLiquidationPrice(price, quantity, _leverage, false),
          'tpPrice': null,
          'slPrice': null,
          'partialSize': 0.0,
          'createdAt': DateTime.now(),
        };

        // Добавляем в глобальное хранилище
        MockPortfolioService.addPosition(position);

        setState(() {
          _positions = List.from(MockPortfolioService.getPositions());
        });

        // Обновляем баланс после создания позиции (с учетом замороженной маржи)
        _loadAvailableBalance();
        // Обновляем P&L чтобы обновить балансы (это также уведомит об изменениях)
        _updateAllPositionsPnl();
      } else {
        // Для спота создаем ордер на продажу
        final order = {
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'type': 'sell',
          'pair': _selectedPair,
          'price': price,
          'quantity': quantity,
          'total': total,
          'status': 'active',
          'createdAt': DateTime.now(),
          'orderType': 'limit',
        };

        setState(() {
          _orders.add(order);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ордер на продажу создан'),
            backgroundColor: AppTheme.primaryRed,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }

    // Очищаем поля количества и объема
    _quantityController.clear();
    _totalController.clear();
  }

  // Расчет цены ликвидации для изолированной маржи
  double _calculateLiquidationPrice(
      double entryPrice, double size, int leverage, bool isLong) {
    // Упрощенный расчет: для лонга цена ликвидации ниже цены входа, для шорта - выше
    // Формула: liquidationPrice = entryPrice * (1 - 1/leverage) для лонга
    // liquidationPrice = entryPrice * (1 + 1/leverage) для шорта
    if (isLong) {
      return entryPrice *
          (1 - 0.95 / leverage); // 95% от маржи для безопасности
    } else {
      return entryPrice * (1 + 0.95 / leverage);
    }
  }

  // Запуск периодического обновления цен
  void _startPriceUpdates() {
    // Обновляем цены каждые 2 секунды
    _priceUpdateTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        _loadCurrentCoin();
        _updateAllPositionsPnl();
      }
    });

    // Обновляем книжку ордеров каждые 3 секунды
    _orderBookUpdateTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) {
        _loadOrderBook();
      }
    });

    // Обновляем отсчет Funding Rate каждую секунду (только для фьючерсов)
    _fundingRateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && _selectedMarketType == 'Фьючерсы') {
        setState(() {
          if (_fundingRateCountdown.inSeconds > 0) {
            _fundingRateCountdown = Duration(
              seconds: _fundingRateCountdown.inSeconds - 1,
            );
          } else {
            // Сбрасываем на 8 часов (стандартный период funding rate)
            _fundingRateCountdown = Duration(hours: 8);
          }
        });
      }
    });
  }

  // Обновление P&L всех позиций (не только для текущей пары)
  Future<void> _updateAllPositionsPnl() async {
    if (_positions.isEmpty) {
      // Если позиций нет, обнуляем нереализованный P&L
      MockPortfolioService.setUnrealizedPnl(0.0);
      // Обновляем доступный баланс
      if (mounted) {
        _loadAvailableBalance();
      }
      return;
    }

    // Обновляем цены перед расчетом P&L
    await MockPortfolioService.refreshPrices();

    // Создаем копию списка позиций для безопасной итерации
    final positionsCopy = List<Map<String, dynamic>>.from(_positions);

    // Сначала обновляем все позиции
    for (var position in positionsCopy) {
      // Проверяем, что позиция все еще существует в оригинальном списке
      if (!_positions.contains(position)) continue;

      final positionSymbol = position['symbol'] as String;
      final positionPair = position['pair'] as String;

      // Обновляем entryPrice только для старых моковых позиций (solana_/ltc_),
      // а не для позиций, созданных пользователем через экран создания
      final positionId = position['id']?.toString() ?? '';
      if (positionSymbol == 'SOLUSDT' &&
          MockPortfolioService.useMockData &&
          positionId.startsWith('solana_')) {
        final newEntryPrice = MockPortfolioService.solEntryPrice;
        final currentEntryPrice = position['entryPrice'] as double;
        if (newEntryPrice != currentEntryPrice) {
          _updateMockPositionEntryPrice(position, newEntryPrice, 'SOLUSDT');
        }
      } else if (positionSymbol == 'LTCUSDT' &&
          MockPortfolioService.useMockData &&
          positionId.startsWith('ltc_')) {
        final newEntryPrice = MockPortfolioService.ltcEntryPrice;
        final currentEntryPrice = position['entryPrice'] as double;
        if (newEntryPrice != currentEntryPrice) {
          _updateMockPositionEntryPrice(position, newEntryPrice, 'LTCUSDT');
        }
      }

      // Если это текущая пара, используем актуальную цену
      if (positionPair == _selectedPair && _currentCoin != null) {
        _updateSinglePositionPnl(position, _currentCoin!.price);
      } else {
        // Для других пар загружаем цену отдельно
        await _updatePositionPnlForSymbol(position, positionSymbol);
      }
    }

    // Затем суммируем нереализованный P&L всех позиций (используем копию)
    double totalUnrealizedPnl = 0.0;
    final positionsCopy2 = List<Map<String, dynamic>>.from(_positions);
    for (var position in positionsCopy2) {
      totalUnrealizedPnl += position['unrealizedPnl'] as double? ?? 0.0;
    }

    // Обновляем нереализованный P&L в MockPortfolioService (это уведомит об изменениях)
    MockPortfolioService.setUnrealizedPnl(totalUnrealizedPnl);

    // Обновляем доступный баланс с учетом замороженной маржи
    if (mounted) {
      setState(() {
        // Обновляем доступный баланс напрямую без полной перезагрузки
        if (_selectedMarketType == 'Фьючерсы') {
          double unifiedUsdt = MockPortfolioService.unifiedTradingUsd;
          double frozenMargin = 0.0;
          if (_marginMode == 'Cross') {
            for (var position in _positions) {
              final entryPrice = position['entryPrice'] as double;
              final size = position['size'] as double;
              final leverage = position['leverage'] as int;
              frozenMargin += (entryPrice * size) / leverage;
            }
          } else {
            for (var position in _positions) {
              final positionMarginMode =
                  position['marginMode'] as String? ?? 'Isolated';
              if (positionMarginMode == 'Isolated') {
                final entryPrice = position['entryPrice'] as double;
                final size = position['size'] as double;
                final leverage = position['leverage'] as int;
                frozenMargin += (entryPrice * size) / leverage;
              }
            }
          }
          _availableBalance =
              (unifiedUsdt - frozenMargin).clamp(0.0, double.infinity);
        }
      });
    }
  }

  // Обновление entryPrice для моковой позиции
  void _updateMockPositionEntryPrice(
      Map<String, dynamic> position, double newEntryPrice, String symbol) {
    final oldEntryPrice = position['entryPrice'] as double;
    final size = position['size'] as double;

    // Обновляем entryPrice
    position['entryPrice'] = newEntryPrice;

    // Пересчитываем размер позиции, чтобы сохранить ту же стоимость
    // Старая стоимость = oldEntryPrice * size
    // Новая стоимость должна быть такой же
    final oldValue = oldEntryPrice * size;
    final newSize = oldValue / newEntryPrice;
    position['size'] = newSize;

    // Пересчитываем TP/SL на основе нового entryPrice
    if (symbol == 'SOLUSDT') {
      // Solana TP/SL: TP 145%, SL 95%
      final solanaTpPrice =
          newEntryPrice * 2.45; // 124.5 * 2.45 = 305.025 (прибыль 145%)
      final solanaSlPrice = newEntryPrice * 0.95; // 124.5 * 0.95 = 118.275

      position['tpPrice'] = solanaTpPrice;
      position['slPrice'] = solanaSlPrice;

      // Обновляем TP/SL ордер
      final tpSlOrder = _orders.firstWhere(
        (o) => o['orderType'] == 'tpsl' && o['pair'] == 'SOL/USDT',
        orElse: () => {},
      );
      if (tpSlOrder.isNotEmpty) {
        tpSlOrder['tpPrice'] = solanaTpPrice;
        tpSlOrder['slPrice'] = solanaSlPrice;
        tpSlOrder['entryPrice'] = newEntryPrice;
        tpSlOrder['quantity'] = newSize;
      }
    } else if (symbol == 'LTCUSDT') {
      // LTC TP/SL: TP 90%, SL 96%
      final ltcTpPrice =
          newEntryPrice * 1.90; // 74.5 * 1.90 = 141.55 (прибыль 90%)
      final ltcSlPrice = newEntryPrice * 0.96; // 74.5 * 0.96 = 71.52

      position['tpPrice'] = ltcTpPrice;
      position['slPrice'] = ltcSlPrice;

      // Обновляем TP/SL ордер
      final tpSlOrder = _orders.firstWhere(
        (o) => o['orderType'] == 'tpsl' && o['pair'] == 'LTC/USDT',
        orElse: () => {},
      );
      if (tpSlOrder.isNotEmpty) {
        tpSlOrder['tpPrice'] = ltcTpPrice;
        tpSlOrder['slPrice'] = ltcSlPrice;
        tpSlOrder['entryPrice'] = newEntryPrice;
        tpSlOrder['quantity'] = newSize;
      }
    }
  }

  // Обновление P&L для конкретной позиции по символу
  Future<void> _updatePositionPnlForSymbol(
      Map<String, dynamic> position, String symbol) async {
    try {
      // Для моковых позиций SOL и LTC используем цены из MockPortfolioService
      if (symbol == 'SOLUSDT' && MockPortfolioService.useMockData) {
        _updateSinglePositionPnl(position, MockPortfolioService.solPrice);
      } else if (symbol == 'LTCUSDT' && MockPortfolioService.useMockData) {
        _updateSinglePositionPnl(position, MockPortfolioService.ltcPrice);
      } else {
        // Для остальных позиций используем API
        final coin = await CryptoApiService.getCoinById(symbol);
        if (coin != null) {
          _updateSinglePositionPnl(position, coin.price);
        }
      }
    } catch (e) {
      // Игнорируем ошибки при обновлении
    }
  }

  // Обновление P&L одной позиции
  void _updateSinglePositionPnl(
      Map<String, dynamic> position, double currentPrice) {
    final entryPrice = position['entryPrice'] as double;
    final size = position['size'] as double;
    final isLong = position['side'] == 'Long';
    final leverage = position['leverage'] as int;
    final tpPrice = position['tpPrice'] as double?;
    final slPrice = position['slPrice'] as double?;

    // Обновляем маркировочную цену
    position['markPrice'] = currentPrice;

    // Проверка срабатывания Take Profit или Stop Loss
    // Добавляем небольшую задержку, чтобы избежать случайного закрытия при обновлении цены
    bool shouldClose = false;
    String closeReason = '';

    if (isLong) {
      // Для лонг-позиции:
      // TP срабатывает, когда цена поднимается выше TP цены
      if (tpPrice != null && tpPrice > 0 && currentPrice >= tpPrice) {
        shouldClose = true;
        closeReason = 'Take Profit';
      }
      // SL срабатывает, когда цена падает ниже SL цены
      else if (slPrice != null && slPrice > 0 && currentPrice <= slPrice) {
        shouldClose = true;
        closeReason = 'Stop Loss';
      }
    } else {
      // Для шорт-позиции:
      // TP срабатывает, когда цена падает ниже TP цены
      if (tpPrice != null && tpPrice > 0 && currentPrice <= tpPrice) {
        shouldClose = true;
        closeReason = 'Take Profit';
      }
      // SL срабатывает, когда цена поднимается выше SL цены
      else if (slPrice != null && slPrice > 0 && currentPrice >= slPrice) {
        shouldClose = true;
        closeReason = 'Stop Loss';
      }
    }

    // Автоматическое закрытие позиции при срабатывании TP/SL
    // Добавляем проверку, что позиция еще существует (не была закрыта вручную)
    // И что не было недавнего переключения пары (защита от случайного закрытия)
    if (shouldClose && mounted && _positions.contains(position)) {
      // Проверяем, что не было недавнего переключения пары (в течение 3 секунд)
      final timeSincePairChange = _lastPairChangeTime != null
          ? DateTime.now().difference(_lastPairChangeTime!)
          : const Duration(seconds: 10);

      // Не закрываем позицию, если недавно переключили пару
      if (timeSincePairChange.inSeconds < 3) {
        return;
      }

      // Проверяем, что позиция еще не закрывается
      final positionId = position['id'] as String? ?? '';
      if (_positionsBeingClosed.contains(positionId)) {
        return;
      }

      // Небольшая задержка для проверки, что цена действительно достигла TP/SL
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted && _positions.contains(position)) {
          // Повторная проверка цены перед закрытием
          final finalPrice = position['markPrice'] as double? ?? currentPrice;
          final finalTpPrice = position['tpPrice'] as double?;
          final finalSlPrice = position['slPrice'] as double?;

          bool stillShouldClose = false;
          if (isLong) {
            if (finalTpPrice != null &&
                finalTpPrice > 0 &&
                finalPrice >= finalTpPrice) {
              stillShouldClose = true;
            } else if (finalSlPrice != null &&
                finalSlPrice > 0 &&
                finalPrice <= finalSlPrice) {
              stillShouldClose = true;
            }
          } else {
            if (finalTpPrice != null &&
                finalTpPrice > 0 &&
                finalPrice <= finalTpPrice) {
              stillShouldClose = true;
            } else if (finalSlPrice != null &&
                finalSlPrice > 0 &&
                finalPrice >= finalSlPrice) {
              stillShouldClose = true;
            }
          }

          if (stillShouldClose && mounted && _positions.contains(position)) {
            _closePositionByTpSl(position, closeReason);
          }
        }
      });
    }

    // Расчет нереализованного P&L
    // Для фьючерсов: P&L = (markPrice - entryPrice) * size * direction
    // Процент рассчитывается от стоимости позиции с учетом плеча
    double pnl;
    if (isLong) {
      pnl = (currentPrice - entryPrice) * size;
    } else {
      pnl = (entryPrice - currentPrice) * size;
    }

    // Процент P&L рассчитывается от маржинальной стоимости (entryPrice * size / leverage)
    final marginValue = (entryPrice * size) / leverage;
    final pnlPercent = marginValue > 0 ? (pnl / marginValue) * 100 : 0.0;

    position['unrealizedPnl'] = pnl;
    position['unrealizedPnlPercent'] = pnlPercent;
  }

  // Закрытие позиции по TP/SL
  Future<void> _closePositionByTpSl(
      Map<String, dynamic> position, String reason) async {
    if (!mounted) return;

    final positionId = position['id'] as String? ?? '';

    // Проверяем, что позиция еще не закрывается
    if (_positionsBeingClosed.contains(positionId)) {
      return;
    }

    // Помечаем позицию как закрывающуюся
    _positionsBeingClosed.add(positionId);

    final unrealizedPnl = position['unrealizedPnl'] as double? ?? 0.0;
    final size = position['size'] as double;
    final entryPrice = position['entryPrice'] as double;
    final positionPair = position['pair'] as String;

    // Для всех позиций возвращаем только P&L
    // Маржа НЕ вычиталась при создании моковых позиций, поэтому не возвращаем её
    // Возвращаем только реализованный P&L
    final margin = entryPrice * size;
    final maxPnl = margin * 10; // Максимальный P&L = 10x от маржи
    final limitedPnl = unrealizedPnl.clamp(
        -margin, maxPnl); // P&L не может быть больше -100% или +1000%

    // Возвращаем только P&L (маржа не вычиталась при создании моковых позиций)
    final totalToAdd = limitedPnl; // Только P&L для всех позиций

    // Собираем ордера для удаления
    final ordersToRemove = _orders.where((o) {
      final orderType = o['orderType'] as String?;
      final orderPair = o['pair'] as String?;
      return orderType == 'tpsl' && orderPair == positionPair;
    }).toList();

    // Добавляем средства на баланс единого торгового аккаунта
    if (totalToAdd != 0.0) {
      MockPortfolioService.realizePnl(totalToAdd);
    }

    if (mounted) {
      // Удаляем из глобального хранилища
      final positionId = position['id'] as String? ?? position['id'].toString();
      MockPortfolioService.removePosition(positionId);

      setState(() {
        // Обновляем локальный список из глобального хранилища
        _positions = List.from(MockPortfolioService.getPositions());

        // Удаляем связанные TP/SL ордера при закрытии позиции
        for (var order in ordersToRemove) {
          _orders.remove(order);
        }
      });

      // Показываем уведомление о закрытии
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Позиция ${positionPair} закрыта: $reason'),
          backgroundColor: reason == 'Take Profit'
              ? AppTheme.primaryGreen
              : AppTheme.primaryRed,
          duration: Duration(seconds: 3),
        ),
      );

      // Обновляем P&L после закрытия позиции
      Future.microtask(() async {
        if (!mounted) return;
        await _updateAllPositionsPnl();
        // Уведомляем об изменении баланса
        if (mounted) {
          MockPortfolioService.balanceNotifier.value =
              MockPortfolioService.unifiedTradingBalance;
          if (mounted) {
            await _loadAvailableBalance();
          }
        }
        // Удаляем позицию из списка закрывающихся
        _positionsBeingClosed.remove(positionId);
      });
    }
  }

  Future<void> _loadCurrentCoin() async {
    try {
      final symbol = _selectedPair.replaceAll('/', '');

      // Определяем категорию в зависимости от типа рынка
      String category = 'spot';
      if (_selectedMarketType == 'Фьючерсы') {
        category = 'linear';
      } else if (_selectedMarketType == 'Опцион') {
        category = 'option';
      }

      // Для спота используем getCoinById, для фьючерсов/опционов - getMarkets
      CryptoModel? coin;
      if (category == 'spot') {
        coin = await CryptoApiService.getCoinById(symbol);
      } else {
        // Для фьючерсов/опционов получаем через getMarkets
        try {
          final markets = await CryptoApiService.getMarkets(
            category: category,
            perPage: 200,
          );
          coin = markets.firstWhere(
            (c) =>
                c.symbol == symbol.replaceAll('USDT', '') ||
                c.pair == _selectedPair ||
                c.symbol == symbol,
            orElse: () => markets.isNotEmpty ? markets[0] : markets.first,
          );
        } catch (e) {
          // Если не найдено, используем спотовые данные как fallback
          coin = await CryptoApiService.getCoinById(symbol);
        }
      }

      if (mounted) {
        setState(() {
          _currentCoin = coin;
        });
        // Обновляем цену в контроллере
        _updatePriceFromCurrentCoin();
        // Обновляем баланс при смене монеты (на случай если баланс изменился)
        _loadAvailableBalance();
        // Обновляем P&L всех позиций с задержкой, чтобы защита от закрытия успела сработать
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _updateAllPositionsPnl();
          }
        });
      }
    } catch (e) {
      // Ошибка загрузки
    }
  }

  Future<void> _showSpotMarketsModal(BuildContext context) async {
    // Загружаем список монет в зависимости от выбранного типа рынка
    List<CryptoModel> spotCoins = [];
    List<CryptoModel> filteredCoins = [];
    bool isLoading = true;
    String searchQuery = '';
    String selectedCurrency = 'USDT';
    String selectedMarketFilter = 'Все';

    final List<String> currencies = [
      'USDT',
      'USDC',
      'USDE',
      'MNT',
      'USD1',
      'EUR',
      'BRL',
      'PLN'
    ];

    final List<String> marketFilters = [
      'Все',
      'Новое',
      'Популярно',
      'xStocks',
      'Зона приключений',
      'Экосистема SOI'
    ];

    Future<void> loadCoins(String marketFilter) async {
      try {
        String mainCategory = 'Популярные';
        if (marketFilter == 'Новое') {
          mainCategory = 'Новые';
        } else if (marketFilter == 'Популярно') {
          mainCategory = 'Популярные';
        } else if (marketFilter == 'Активные монеты') {
          mainCategory = 'Активные монеты';
        }

        // Определяем подкатегорию в зависимости от выбранного типа рынка
        String subCategory = 'Спот';
        if (_selectedMarketType == 'Фьючерсы') {
          subCategory = 'Фьючерсы';
        } else if (_selectedMarketType == 'Опцион') {
          subCategory = 'Опцион';
        } else if (_selectedMarketType == 'TradFi') {
          subCategory = 'TradFi';
        }

        spotCoins = await CryptoApiService.getMarketsByCategory(
          mainCategory: mainCategory,
          subCategory: subCategory,
          perPage: 100,
        );
      } catch (e) {
        spotCoins = [];
      }
    }

    await loadCoins(selectedMarketFilter);
    // Применяем начальные фильтры
    filteredCoins = spotCoins.where((coin) {
      // Фильтр по валюте USDT
      if (!coin.pair.endsWith('/USDT') && !coin.pair.endsWith('USDT')) {
        return false;
      }
      return true;
    }).toList();
    // Сортировка по объему
    filteredCoins.sort((a, b) => b.turnover24h.compareTo(a.turnover24h));
    isLoading = false;

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          // Фильтрация монет
          Future<void> applyFilters({bool reloadData = false}) async {
            setModalState(() {
              isLoading = true;
            });

            // Если нужно перезагрузить данные
            if (reloadData) {
              await loadCoins(selectedMarketFilter);
            }

            setModalState(() {
              filteredCoins = spotCoins.where((coin) {
                // Фильтр по валюте
                if (selectedCurrency != 'USDT') {
                  if (!coin.pair.endsWith('/$selectedCurrency') &&
                      !coin.pair.endsWith(selectedCurrency)) {
                    return false;
                  }
                } else {
                  // Для USDT показываем все пары, которые заканчиваются на USDT
                  if (!coin.pair.endsWith('/USDT') &&
                      !coin.pair.endsWith('USDT')) {
                    return false;
                  }
                }

                // Фильтр по поиску
                if (searchQuery.isNotEmpty) {
                  final query = searchQuery.toLowerCase();
                  if (!coin.pair.toLowerCase().contains(query) &&
                      !coin.symbol.toLowerCase().contains(query) &&
                      !coin.name.toLowerCase().contains(query)) {
                    return false;
                  }
                }

                // Фильтр по популярности (для фильтра "Популярно")
                if (selectedMarketFilter == 'Популярно') {
                  if (coin.turnover24h < 50000000) {
                    return false;
                  }
                }

                return true;
              }).toList();

              // Сортировка по объему (по убыванию)
              filteredCoins
                  .sort((a, b) => b.turnover24h.compareTo(a.turnover24h));

              isLoading = false;
            });
          }

          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Expanded(
                  child: SafeArea(
                    top: false,
                    child: Column(
                      children: [
                        // Поисковая строка
                        Container(
                          margin: const EdgeInsets.only(
                              left: 16, right: 16, top: 12, bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.backgroundCard,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.search,
                                  color: AppTheme.textSecondary, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 14),
                                  decoration: InputDecoration(
                                    hintText: 'Введите торговую пару',
                                    hintStyle: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 14,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  onChanged: (value) {
                                    setModalState(() {
                                      searchQuery = value;
                                    });
                                    applyFilters();
                                  },
                                ),
                              ),
                              if (searchQuery.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () {
                                    setModalState(() {
                                      searchQuery = '';
                                    });
                                    applyFilters();
                                  },
                                  child: Icon(Icons.close,
                                      color: AppTheme.textSecondary, size: 18),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Фильтры по валютам
                        Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          margin: const EdgeInsets.only(bottom: 4),
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: currencies.length,
                            itemBuilder: (context, index) {
                              final currency = currencies[index];
                              final isSelected = currency == selectedCurrency;
                              return GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    selectedCurrency = currency;
                                  });
                                  applyFilters();
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppTheme.backgroundCard
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    currency,
                                    style: TextStyle(
                                      color: isSelected
                                          ? AppTheme.textPrimary
                                          : AppTheme.textSecondary,
                                      fontSize: 12,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        // Фильтры по рынкам
                        Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: marketFilters.length,
                            itemBuilder: (context, index) {
                              final filter = marketFilters[index];
                              final isSelected = filter == selectedMarketFilter;
                              return GestureDetector(
                                onTap: () async {
                                  setModalState(() {
                                    selectedMarketFilter = filter;
                                  });
                                  await applyFilters(reloadData: true);
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(right: 12),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        filter,
                                        style: TextStyle(
                                          color: isSelected
                                              ? AppTheme.textPrimary
                                              : AppTheme.textSecondary,
                                          fontSize: 11,
                                          fontWeight: isSelected
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                      ),
                                      if (filter == 'Популярно') ...[
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.local_fire_department,
                                          color: AppTheme.primaryRed,
                                          size: 12,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        // Заголовки колонок
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text(
                                  'Торговые пары / Объем',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  'Цена',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  'Изменение, 24ч',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Список монет
                        Expanded(
                          child: isLoading
                              ? const Center(child: CircularProgressIndicator())
                              : filteredCoins.isEmpty
                                  ? Center(
                                      child: Text(
                                        'Нет данных',
                                        style: TextStyle(
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: filteredCoins.length,
                                      padding: EdgeInsets.zero,
                                      itemBuilder: (context, index) {
                                        final coin = filteredCoins[index];
                                        final pair = coin.pair;
                                        final isSelected =
                                            pair == _selectedPair;
                                        final showFireIcon =
                                            coin.turnover24h > 50000000;
                                        final showLeverage =
                                            coin.turnover24h > 100000000;

                                        return GestureDetector(
                                          onTap: () {
                                            // Используем updateSelectedPair для правильного обновления времени переключения
                                            updateSelectedPair(pair);
                                            Navigator.pop(context);
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 16, vertical: 12),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? AppTheme.backgroundCard
                                                      .withValues(alpha: 0.6)
                                                  : Colors.transparent,
                                              border: Border(
                                                bottom: BorderSide(
                                                  color: AppTheme.borderColor
                                                      .withValues(alpha: 0.3),
                                                  width: 0.5,
                                                ),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  flex: 3,
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          if (showLeverage) ...[
                                                            Container(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                      horizontal:
                                                                          4,
                                                                      vertical:
                                                                          2),
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: AppTheme
                                                                    .textSecondary
                                                                    .withValues(
                                                                        alpha:
                                                                            0.2),
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            3),
                                                              ),
                                                              child: Text(
                                                                '10x',
                                                                style:
                                                                    TextStyle(
                                                                  color: AppTheme
                                                                      .textPrimary,
                                                                  fontSize: 9,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                width: 4),
                                                          ],
                                                          Flexible(
                                                            child: Text(
                                                              pair,
                                                              style: TextStyle(
                                                                color: AppTheme
                                                                    .textPrimary,
                                                                fontSize: 14,
                                                                fontWeight: isSelected
                                                                    ? FontWeight
                                                                        .w600
                                                                    : FontWeight
                                                                        .normal,
                                                              ),
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            ),
                                                          ),
                                                          if (showFireIcon) ...[
                                                            const SizedBox(
                                                                width: 4),
                                                            Icon(
                                                              Icons
                                                                  .local_fire_department,
                                                              color: AppTheme
                                                                  .primaryRed,
                                                              size: 14,
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        '${_formatVolume(coin.turnover24h)} USDT',
                                                        style: TextStyle(
                                                          color: AppTheme
                                                              .textSecondary,
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 2,
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .center,
                                                    children: [
                                                      Text(
                                                        _formatPrice(
                                                            coin.price),
                                                        style: TextStyle(
                                                          color: AppTheme
                                                              .textPrimary,
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                        textAlign:
                                                            TextAlign.center,
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        '${_formatPriceUSD(coin.price)} USD',
                                                        style: TextStyle(
                                                          color: AppTheme
                                                              .textSecondary,
                                                          fontSize: 11,
                                                        ),
                                                        textAlign:
                                                            TextAlign.center,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 2,
                                                  child: Align(
                                                    alignment:
                                                        Alignment.centerRight,
                                                    child: Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 10,
                                                          vertical: 6),
                                                      decoration: BoxDecoration(
                                                        color: coin.change24h >=
                                                                0
                                                            ? AppTheme
                                                                .primaryGreen
                                                            : AppTheme
                                                                .primaryRed,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(20),
                                                      ),
                                                      child: Text(
                                                        '${coin.change24h >= 0 ? '+' : ''}${coin.change24h.toStringAsFixed(2)}%',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Черный фон для нижней части (home indicator)
                Container(
                  height: MediaQuery.of(context).padding.bottom > 0
                      ? MediaQuery.of(context).padding.bottom
                      : 20,
                  color: Colors.black,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatVolume(double volume) {
    if (volume >= 1000000000) {
      return '${(volume / 1000000000).toStringAsFixed(2)}B';
    } else if (volume >= 1000000) {
      return '${(volume / 1000000).toStringAsFixed(2)}M';
    } else if (volume >= 1000) {
      return '${(volume / 1000).toStringAsFixed(2)}K';
    }
    return volume.toStringAsFixed(2);
  }

  String _formatPrice(double price) {
    if (price >= 1000) {
      return price.toStringAsFixed(1);
    } else if (price >= 1) {
      return price.toStringAsFixed(2);
    } else if (price >= 0.01) {
      return price.toStringAsFixed(4);
    } else {
      return price.toStringAsFixed(5);
    }
  }

  String _formatPriceUSD(double price) {
    if (price >= 1000) {
      return price.toStringAsFixed(1);
    } else if (price >= 1) {
      return price.toStringAsFixed(2);
    } else if (price >= 0.01) {
      return price.toStringAsFixed(2);
    } else {
      return price.toStringAsFixed(3);
    }
  }

  Future<void> _loadChartData() async {
    // Сохраняем текущую пару и период для проверки после загрузки
    final currentPair = _selectedPair;
    final currentPeriod = _selectedPeriod;

    setState(() {
      _isLoading = true;
    });

    try {
      final klines = await CryptoApiService.getKlines(
        symbol: currentPair,
        interval: currentPeriod,
        limit: 200,
      );

      if (mounted) {
        // Проверяем, что пара и период не изменились во время загрузки
        if (_selectedPair != currentPair || _selectedPeriod != currentPeriod) {
          // Пара или период изменились, игнорируем эти данные
          setState(() {
            _isLoading = false;
          });
          return;
        }

        // Сортируем klines по timestamp (Bybit может возвращать в обратном порядке)
        klines.sort(
            (a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int));

        setState(() {
          _klines = klines;
          _isLoading = false;
        });

        // Переподключаем WebSocket после загрузки данных
        _connectWebSocket();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Подключение к WebSocket для реального времени
  Future<void> _connectWebSocket() async {
    // Отключаем предыдущее подключение
    await _websocketService?.disconnect();

    try {
      final symbol = _selectedPair.replaceAll('/', '');
      String category = 'spot';
      if (_selectedMarketType == 'Фьючерсы') {
        category = 'linear';
      }

      // Получаем интервал из выбранного периода
      final apiInterval = AppConstants.intervalMapping[_selectedPeriod] ?? '15';

      _websocketService = BybitWebSocketService();
      await _websocketService!.connect(
        category: category,
        symbol: symbol,
        interval: apiInterval,
        onKlineUpdate: _updateKlineFromWebSocket,
      );
    } catch (e) {
      print('Error connecting WebSocket: $e');
    }
  }

  // Плавное обновление свечи из WebSocket
  void _updateKlineFromWebSocket(Map<String, dynamic> wsData) {
    if (!mounted || _klines.isEmpty) {
      print(
          'WebSocket update skipped: mounted=$mounted, klines empty=${_klines.isEmpty}');
      return;
    }

    try {
      // Получаем интервал из выбранного периода
      final apiInterval = AppConstants.intervalMapping[_selectedPeriod] ?? '15';

      // Проверяем, соответствует ли интервал
      final topic = wsData['topic']?.toString() ?? '';
      print(
          'WebSocket received topic: $topic, looking for: kline.$apiInterval.');

      if (!topic.contains('kline.$apiInterval.')) {
        print('WebSocket: Topic does not match interval $apiInterval');
        return; // Не наш интервал
      }

      print('WebSocket: Processing kline update for interval $apiInterval');

      // Bybit WebSocket возвращает данные в формате: {topic: "...", data: [{...}]}
      final klineList = wsData['data'] as List<dynamic>?;
      if (klineList == null || klineList.isEmpty) return;

      final kline = klineList[0] as Map<String, dynamic>;

      // Bybit возвращает: start, open, high, low, close, volume, confirm
      final startTime = int.parse(kline['start'].toString());
      final open = double.parse(kline['open'].toString());
      final high = double.parse(kline['high'].toString());
      final low = double.parse(kline['low'].toString());
      final close = double.parse(kline['close'].toString());
      final volume = double.parse(kline['volume'].toString());
      final confirm = kline['confirm'] as bool? ?? false;

      // Конвертируем start time в timestamp (Bybit WebSocket возвращает в миллисекундах)
      // Если меньше 13 цифр, значит в секундах - умножаем на 1000
      final timestamp =
          startTime < 1000000000000 ? startTime * 1000 : startTime;

      // Создаем новый список для обновления (важно для Flutter, чтобы увидел изменения)
      final updatedKlines = List<Map<String, dynamic>>.from(_klines);
      bool needsUpdate = false;

      // Ищем последнюю свечу с таким же timestamp
      final lastIndex = updatedKlines.length - 1;
      if (lastIndex >= 0 &&
          updatedKlines[lastIndex]['timestamp'] == timestamp) {
        // Обновляем последнюю свечу (текущая формирующаяся свеча)
        updatedKlines[lastIndex] = {
          'timestamp': timestamp,
          'open': open,
          'high': high,
          'low': low,
          'close': close,
          'volume': volume,
        };
        needsUpdate = true;
      } else if (confirm && lastIndex >= 0) {
        // Если свеча закрылась (confirm = true), добавляем новую
        if (updatedKlines[lastIndex]['timestamp'] < timestamp) {
          updatedKlines.add({
            'timestamp': timestamp,
            'open': open,
            'high': high,
            'low': low,
            'close': close,
            'volume': volume,
          });

          // Ограничиваем количество свечей (оставляем последние 200)
          if (updatedKlines.length > 200) {
            updatedKlines.removeAt(0);
          }
          needsUpdate = true;
        }
      } else {
        // Добавляем новую свечу, если её еще нет
        if (lastIndex < 0 ||
            updatedKlines[lastIndex]['timestamp'] < timestamp) {
          updatedKlines.add({
            'timestamp': timestamp,
            'open': open,
            'high': high,
            'low': low,
            'close': close,
            'volume': volume,
          });

          // Ограничиваем количество свечей
          if (updatedKlines.length > 200) {
            updatedKlines.removeAt(0);
          }
          needsUpdate = true;
        }
      }

      // Обновляем состояние только если были изменения
      if (needsUpdate && mounted) {
        print(
            'WebSocket: Updating chart with new kline data. Last candle: close=${updatedKlines.last['close']}, timestamp=${updatedKlines.last['timestamp']}');
        // Создаем полностью новый список для гарантии обновления
        setState(() {
          _klines = List<Map<String, dynamic>>.from(updatedKlines);
        });
        print('WebSocket: Chart updated, klines count: ${_klines.length}');
      } else {
        print(
            'WebSocket: No update needed. needsUpdate=$needsUpdate, mounted=$mounted');
      }
    } catch (e) {
      print('Error updating kline from WebSocket: $e');
    }
  }

  Future<void> _loadOrderBook() async {
    // Не показываем индикатор загрузки при периодическом обновлении
    final isInitialLoad = _orderBookData == null;

    if (isInitialLoad) {
      setState(() {
        _isLoadingOrderBook = true;
      });
    }

    try {
      final symbol = _selectedPair.replaceAll('/', '');
      String category = 'spot';
      if (_selectedMarketType == 'Фьючерсы') {
        category = 'linear';
      } else if (_selectedMarketType == 'Опцион') {
        category = 'option';
      }

      final orderBook = await CryptoApiService.getOrderBook(
        symbol: symbol,
        category: category,
        limit: 25,
      );

      if (mounted && orderBook != null) {
        // Проверяем, изменились ли данные перед обновлением
        bool hasChanged = false;
        if (_orderBookData == null) {
          hasChanged = true;
        } else {
          // Сравниваем первые несколько уровней цен для быстрой проверки
          final oldAsks = _orderBookData!['a'] as List<dynamic>? ?? [];
          final newAsks = orderBook['a'] as List<dynamic>? ?? [];
          final oldBids = _orderBookData!['b'] as List<dynamic>? ?? [];
          final newBids = orderBook['b'] as List<dynamic>? ?? [];

          // Проверяем первые 3 уровня
          if (oldAsks.length != newAsks.length ||
              oldBids.length != newBids.length) {
            hasChanged = true;
          } else if (oldAsks.isNotEmpty && newAsks.isNotEmpty) {
            final oldFirstAsk = oldAsks[0] as List<dynamic>?;
            final newFirstAsk = newAsks[0] as List<dynamic>?;
            if (oldFirstAsk != null &&
                newFirstAsk != null &&
                oldFirstAsk.isNotEmpty &&
                newFirstAsk.isNotEmpty) {
              final oldPrice = oldFirstAsk[0]?.toString() ?? '';
              final newPrice = newFirstAsk[0]?.toString() ?? '';
              hasChanged = oldPrice != newPrice;
            }
          }
        }

        if (hasChanged) {
          setState(() {
            _orderBookData = orderBook;
            _isLoadingOrderBook = false;
          });
        } else if (isInitialLoad) {
          setState(() {
            _isLoadingOrderBook = false;
          });
        }
      }
    } catch (e) {
      if (mounted && isInitialLoad) {
        setState(() {
          _isLoadingOrderBook = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            // Top market type tabs - fixed, doesn't scroll
            _buildMarketTypeTabs(),
            // Top header with pair and controls - fixed, doesn't scroll
            _buildHeader(),

            // Chart or Order Book view based on toggle
            if (_showChartView) ...[
              // Для спота делаем полноэкранный скролл, для фьючерсов - как было
              if (_selectedMarketType == 'Спот') ...[
                // Полноэкранный скролл для спота
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        // Main tabs
                        _buildMainTabs(),
                        // Price and stats
                        _buildPriceAndStats(),
                        // Chart section
                        if (_selectedMainTab == 'График') ...[
                          _buildChartControls(),
                          _buildCandlestickChart(),
                          _buildVolumeChart(),
                          _buildIndicatorTabs(),
                          _buildOrderBook(),
                        ] else if (_selectedMainTab == 'Обзор') ...[
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.5,
                            child: Center(
                              child: Text(
                                'Обзор',
                                style: TextStyle(color: AppTheme.textPrimary),
                              ),
                            ),
                          ),
                        ] else if (_selectedMainTab == 'Данные') ...[
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.5,
                            child: Center(
                              child: Text(
                                'Данные',
                                style: TextStyle(color: AppTheme.textPrimary),
                              ),
                            ),
                          ),
                        ] else ...[
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.5,
                            child: Center(
                              child: Text(
                                'Лента новостей',
                                style: TextStyle(color: AppTheme.textPrimary),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(
                            height: 20), // Отступ снизу перед кнопками
                      ],
                    ),
                  ),
                ),
                // Buy/Sell buttons - зафиксированы внизу для спота
                _buildActionButtons(),
              ] else ...[
                // Для фьючерсов и других - полноэкранный скролл как в споте
                // Полноэкранный скролл для фьючерсов
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        // Main tabs
                        _buildMainTabs(),
                        // Price and stats
                        _buildPriceAndStats(),
                        // Chart section
                        if (_selectedMainTab == 'График') ...[
                          _buildChartControls(),
                          _buildCandlestickChart(),
                          _buildVolumeChart(),
                          _buildIndicatorTabs(),
                          _buildOrderBook(),
                        ] else if (_selectedMainTab == 'Обзор') ...[
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.5,
                            child: Center(
                              child: Text(
                                'Обзор',
                                style: TextStyle(color: AppTheme.textPrimary),
                              ),
                            ),
                          ),
                        ] else if (_selectedMainTab == 'Данные') ...[
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.5,
                            child: Center(
                              child: Text(
                                'Данные',
                                style: TextStyle(color: AppTheme.textPrimary),
                              ),
                            ),
                          ),
                        ] else ...[
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.5,
                            child: Center(
                              child: Text(
                                'Лента новостей',
                                style: TextStyle(color: AppTheme.textPrimary),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(
                            height: 20), // Отступ снизу перед кнопками
                      ],
                    ),
                  ),
                ),
                // Buy/Sell buttons - зафиксированы внизу для фьючерсов
                _buildActionButtons(),
              ],
            ] else ...[
              // Order form + Order book view - scrollable content
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Top bar: Buy/Sell/Margin/Icons in one row
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 8),
                        child: Row(
                          children: [
                            // Buy button (только для спота)
                            if (_selectedMarketType != 'Фьючерсы') ...[
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _isBuySelected = true;
                                    });
                                  },
                                  child: Container(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 6),
                                    decoration: BoxDecoration(
                                      color: _isBuySelected
                                          ? AppTheme.primaryGreen
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Купить',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: _isBuySelected
                                            ? Colors.white
                                            : AppTheme.textSecondary,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Sell button (только для спота)
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _isBuySelected = false;
                                    });
                                  },
                                  child: Container(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 6),
                                    decoration: BoxDecoration(
                                      color: !_isBuySelected
                                          ? AppTheme.primaryRed
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Продать',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: !_isBuySelected
                                            ? Colors.white
                                            : AppTheme.textSecondary,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            // Margin toggle (только для спота)
                            if (_selectedMarketType != 'Фьючерсы') ...[
                              Text(
                                'Маржа',
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 9,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Transform.scale(
                                scale: 0.7,
                                child: Switch(
                                  value: false,
                                  onChanged: (value) {},
                                  activeColor: AppTheme.primaryGreen,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            // Icons (только для спота)
                            if (_selectedMarketType != 'Фьючерсы') ...[
                              Icon(
                                Icons.show_chart,
                                color: AppTheme.textSecondary,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Stack(
                                children: [
                                  Icon(
                                    Icons.more_vert,
                                    color: AppTheme.textSecondary,
                                    size: 18,
                                  ),
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    child: Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryRed,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Top part - Order form + Order book
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left: Order form
                          Align(
                            alignment: Alignment.topLeft,
                            child: _buildOrderBookView(),
                          ),
                          // Right: Order book
                          Expanded(
                            child: _buildOrderBookRight(),
                          ),
                        ],
                      ),
                      // Bottom part - Orders/Positions/Assets view (full width)
                      _buildOrdersPositionsView(),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMarketTypeTabs() {
    final marketTypes = ['Конвертация', 'Спот', 'Фьючерсы', 'Опцион', 'TradFi'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: marketTypes.map((type) {
            final isSelected = type == _selectedMarketType;
            return Padding(
              padding: const EdgeInsets.only(right: 16),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedMarketType = type;

                    // Перезагружаем данные при смене типа рынка
                    _loadCurrentCoin();
                    _loadChartData();
                    // Перезагружаем баланс (для спота - Funding, для фьючерсов - Unified)
                    _loadAvailableBalance();
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isSelected ? Colors.orange : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    type,
                    style: TextStyle(
                      color: isSelected
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          // Top row: Pair, change, MM, chart/doc toggles, icons
          Row(
            children: [
              // Left side: Pair and change
              GestureDetector(
                onTap: () {
                  _showSpotMarketsModal(context);
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _selectedPair,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_drop_down,
                      color: AppTheme.textSecondary,
                      size: 20,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${(_currentCoin?.change24h ?? -0.98) >= 0 ? '+' : ''}${(_currentCoin?.change24h ?? -0.98).toStringAsFixed(2)}%',
                style: TextStyle(
                  color: AppTheme.textPrimary, // White color for percentage
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Right side: MM, toggles, icons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // MM badge - only letters in green container, percentage below
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00FF88), // Green color
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'MM',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '0.00%',
                        style: TextStyle(
                          color: const Color(0xFF00C853), // Green color
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  // Toggle switch with two segments - larger size
                  Container(
                    decoration: BoxDecoration(
                      color:
                          const Color(0xFF1A1A1A), // Dark background for toggle
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Chart segment (left)
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _showChartView = true;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: _showChartView
                                  ? const Color(
                                      0xFF2A2A2A) // Dark grey for selected
                                  : Colors.transparent,
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(10),
                                bottomLeft: Radius.circular(10),
                              ),
                            ),
                            child: Icon(Icons.candlestick_chart,
                                color: _showChartView
                                    ? AppTheme.textPrimary
                                    : AppTheme.textSecondary,
                                size: 22),
                          ),
                        ),
                        // Document segment (right)
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _showChartView = false;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: !_showChartView
                                  ? const Color(
                                      0xFF2A2A2A) // Dark grey for selected
                                  : Colors.transparent,
                              borderRadius: BorderRadius.only(
                                topRight: Radius.circular(10),
                                bottomRight: Radius.circular(10),
                              ),
                            ),
                            child: Icon(Icons.description,
                                color: !_showChartView
                                    ? AppTheme.textPrimary
                                    : AppTheme.textSecondary,
                                size: 22),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPriceAndStats() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Large price
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentCoin != null
                      ? _formatPriceForDisplay(_currentCoin!.price)
                      : '91,335.00',
                  style: TextStyle(
                    color: const Color(0xFF00FF88), // Green color
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '≈${_currentCoin != null ? _formatPriceForDisplay(_currentCoin!.price) : '91,335.00'} USD',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Stats on right
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatRow(
                  'МАКС, 24Ч',
                  _klines.isNotEmpty
                      ? _klines
                          .map((k) => k['high'] as double)
                          .reduce((a, b) => a > b ? a : b)
                          .toStringAsFixed(1)
                      : '0.0',
                ),
                const SizedBox(height: 8),
                _buildStatRow(
                  'МИН, 24Ч',
                  _klines.isNotEmpty
                      ? _klines
                          .map((k) => k['low'] as double)
                          .reduce((a, b) => a < b ? a : b)
                          .toStringAsFixed(1)
                      : '0.0',
                ),
                const SizedBox(height: 8),
                _buildStatRow(
                  'Оборот за 24ч',
                  _currentCoin != null
                      ? _formatTurnover(_currentCoin!.turnover24h)
                      : '0.0',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  String _formatPriceForDisplay(double price) {
    if (price >= 1000) {
      final parts = price.toStringAsFixed(2).split('.');
      final integerPart = parts[0];
      final decimalPart = parts[1];
      // Add commas every 3 digits from right
      String result = '';
      for (int i = 0; i < integerPart.length; i++) {
        if (i > 0 && (integerPart.length - i) % 3 == 0) {
          result += ',';
        }
        result += integerPart[i];
      }
      return '$result.$decimalPart';
    } else if (price >= 1) {
      return price.toStringAsFixed(2);
    } else if (price >= 0.01) {
      return price.toStringAsFixed(4);
    } else {
      return price.toStringAsFixed(5);
    }
  }

  Widget _buildMainTabs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Main tabs
            ..._mainTabs.map((tab) {
              final isSelected = tab == _selectedMainTab;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedMainTab = tab;
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isSelected
                            ? AppTheme.textPrimary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    tab,
                    style: TextStyle(
                      color: isSelected
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary,
                      fontSize: 10,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
            const SizedBox(width: 8),
            // Icons: FEE %, Star, Bell
            Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: () {},
                  child: Text(
                    'FEE %',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 9,
                    ),
                  ),
                ),
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryRed,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: () {},
                  child: Icon(Icons.star_border,
                      color: AppTheme.textSecondary, size: 16),
                ),
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryRed,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: () {},
                  child: Icon(Icons.notifications_none,
                      color: AppTheme.textSecondary, size: 16),
                ),
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryRed,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          // Period selector
          Row(
            children: [
              Text(
                'Срок',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 12),
              ..._periods.map((period) {
                final isSelected = period == _selectedPeriod;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedPeriod = period;
                        _klines =
                            []; // Очищаем данные графика сразу при переключении периода
                      });
                      _resetChartView(); // Сбрасываем масштаб и позицию
                      _loadChartData();
                      _connectWebSocket(); // Переподключаем WebSocket для нового периода
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.backgroundCard
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primaryGreen
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            period,
                            style: TextStyle(
                              color: isSelected
                                  ? AppTheme.primaryGreen
                                  : AppTheme.textSecondary,
                              fontSize: 11,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                          if (period == 'Ещё') ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_drop_down,
                              color: isSelected
                                  ? AppTheme.primaryGreen
                                  : AppTheme.textSecondary,
                              size: 16,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 8),
          // MA values
          Row(
            children: [
              Text(
                'MA7: ${_klines.isNotEmpty && _klines.length >= 7 ? _calculateMA(7).last.toStringAsFixed(1) : '0.0'}',
                style: TextStyle(
                  color: Colors.yellow,
                  fontSize: 10,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'MA14: ${_klines.isNotEmpty && _klines.length >= 14 ? _calculateMA(14).last.toStringAsFixed(1) : '0.0'}',
                style: TextStyle(
                  color: Colors.lightBlue,
                  fontSize: 10,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'MA28: ${_klines.isNotEmpty && _klines.length >= 28 ? _calculateMA(28).last.toStringAsFixed(1) : '0.0'}',
                style: TextStyle(
                  color: Colors.purple,
                  fontSize: 10,
                ),
              ),
              const Spacer(),
              Text(
                'Глубина',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 10,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.edit, color: AppTheme.textSecondary, size: 16),
              const SizedBox(width: 8),
              Icon(Icons.settings, color: AppTheme.textSecondary, size: 16),
            ],
          ),
        ],
      ),
    );
  }

  // Форматирование оборота
  String _formatTurnover(double turnover) {
    if (turnover >= 1000000000) {
      return '${(turnover / 1000000000).toStringAsFixed(2)}B';
    } else if (turnover >= 1000000) {
      return '${(turnover / 1000000).toStringAsFixed(2)}M';
    } else if (turnover >= 1000) {
      return '${(turnover / 1000).toStringAsFixed(2)}K';
    }
    return turnover.toStringAsFixed(2);
  }

  // Вычисление скользящих средних
  List<double> _calculateMA(int period) {
    if (_klines.isEmpty || _klines.length < period) {
      return [];
    }

    List<double> ma = [];
    for (int i = period - 1; i < _klines.length; i++) {
      double sum = 0;
      for (int j = i - period + 1; j <= i; j++) {
        sum += _klines[j]['close'] as double;
      }
      ma.add(sum / period);
    }
    return ma;
  }

  // Вспомогательный метод для корректировки spots при отображении части графика
  List<FlSpot> _adjustSpotsForDisplay(List<FlSpot> spots, int startIndex) {
    List<FlSpot> displaySpots = [];
    for (int i = 0; i < spots.length; i++) {
      if (spots[i].x >= startIndex) {
        displaySpots.add(FlSpot(spots[i].x - startIndex, spots[i].y));
      }
    }
    return displaySpots;
  }

  // Вычисление EMA (Exponential Moving Average)
  List<double> _calculateEMA(int period) {
    if (_klines.isEmpty || _klines.length < period) {
      return [];
    }

    List<double> ema = [];
    double multiplier = 2.0 / (period + 1);

    // Первое значение EMA = SMA
    double sum = 0;
    for (int i = 0; i < period; i++) {
      sum += _klines[i]['close'] as double;
    }
    ema.add(sum / period);

    // Остальные значения EMA
    for (int i = period; i < _klines.length; i++) {
      double close = _klines[i]['close'] as double;
      double prevEma = ema.last;
      ema.add((close - prevEma) * multiplier + prevEma);
    }

    return ema;
  }

  // Вычисление Bollinger Bands
  Map<String, List<FlSpot>> _calculateBOLL(int period, double stdDev) {
    if (_klines.isEmpty || _klines.length < period) {
      return {
        'upper': <FlSpot>[],
        'middle': <FlSpot>[],
        'lower': <FlSpot>[],
      };
    }

    List<FlSpot> upperSpots = [];
    List<FlSpot> middleSpots = [];
    List<FlSpot> lowerSpots = [];

    for (int i = period - 1; i < _klines.length; i++) {
      // Средняя линия (SMA)
      double sum = 0;
      for (int j = i - period + 1; j <= i; j++) {
        sum += _klines[j]['close'] as double;
      }
      double sma = sum / period;

      // Стандартное отклонение
      double variance = 0;
      for (int j = i - period + 1; j <= i; j++) {
        double diff = (_klines[j]['close'] as double) - sma;
        variance += diff * diff;
      }
      double std = math.sqrt(variance / period);

      double upper = sma + (stdDev * std);
      double lower = sma - (stdDev * std);

      middleSpots.add(FlSpot(i.toDouble(), sma));
      upperSpots.add(FlSpot(i.toDouble(), upper));
      lowerSpots.add(FlSpot(i.toDouble(), lower));
    }

    return {
      'upper': upperSpots,
      'middle': middleSpots,
      'lower': lowerSpots,
    };
  }

  // Вычисление Parabolic SAR
  List<FlSpot> _calculateSAR() {
    if (_klines.isEmpty || _klines.length < 2) {
      return [];
    }

    List<FlSpot> sarSpots = [];
    double af = 0.02; // Acceleration Factor
    double maxAf = 0.2; // Maximum AF
    bool isRising =
        (_klines[1]['close'] as double) > (_klines[0]['close'] as double);
    double sar = isRising
        ? (_klines[0]['low'] as double)
        : (_klines[0]['high'] as double);
    double ep = isRising
        ? (_klines[0]['high'] as double)
        : (_klines[0]['low'] as double);

    for (int i = 1; i < _klines.length; i++) {
      double high = _klines[i]['high'] as double;
      double low = _klines[i]['low'] as double;
      // close не используется в расчетах SAR, только high и low

      sar = sar + af * (ep - sar);

      if (isRising) {
        if (low < sar) {
          isRising = false;
          sar = ep;
          ep = low;
          af = 0.02;
        } else {
          if (high > ep) {
            ep = high;
            af = (af + 0.02).clamp(0.0, maxAf);
          }
        }
      } else {
        if (high > sar) {
          isRising = true;
          sar = ep;
          ep = high;
          af = 0.02;
        } else {
          if (low < ep) {
            ep = low;
            af = (af + 0.02).clamp(0.0, maxAf);
          }
        }
      }

      sarSpots.add(FlSpot(i.toDouble(), sar));
    }

    return sarSpots;
  }

  Widget _buildCandlestickChart() {
    if (_isLoading) {
      return Container(
        height: 350,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.backgroundCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: CircularProgressIndicator(
            color: AppTheme.primaryGreen,
          ),
        ),
      );
    }

    if (_klines.isEmpty) {
      return Container(
        height: 350,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.backgroundCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            'Нет данных',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
      );
    }

    // Вычисляем min/max для масштабирования
    double minPrice =
        _klines.map((k) => k['low'] as double).reduce((a, b) => a < b ? a : b);
    double maxPrice =
        _klines.map((k) => k['high'] as double).reduce((a, b) => a > b ? a : b);
    final priceRange = maxPrice - minPrice;
    minPrice -= priceRange * 0.1;
    maxPrice += priceRange * 0.1;

    // Вычисляем индикаторы в зависимости от выбора
    List<FlSpot> ma7Spots = [];
    List<FlSpot> ma14Spots = [];
    List<FlSpot> ma28Spots = [];
    List<FlSpot> ema12Spots = [];
    List<FlSpot> ema26Spots = [];
    List<FlSpot> bollUpperSpots = [];
    List<FlSpot> bollMiddleSpots = [];
    List<FlSpot> bollLowerSpots = [];
    List<FlSpot> sarSpots = [];

    if (_selectedIndicators.contains('MA')) {
      final ma7 = _calculateMA(7);
      final ma14 = _calculateMA(14);
      final ma28 = _calculateMA(28);

      for (int i = 0; i < ma7.length; i++) {
        ma7Spots.add(FlSpot((6 + i).toDouble(), ma7[i]));
      }
      for (int i = 0; i < ma14.length; i++) {
        ma14Spots.add(FlSpot((13 + i).toDouble(), ma14[i]));
      }
      for (int i = 0; i < ma28.length; i++) {
        ma28Spots.add(FlSpot((27 + i).toDouble(), ma28[i]));
      }
    }

    if (_selectedIndicators.contains('EMA')) {
      final ema12 = _calculateEMA(12);
      final ema26 = _calculateEMA(26);

      for (int i = 0; i < ema12.length; i++) {
        ema12Spots.add(FlSpot((11 + i).toDouble(), ema12[i]));
      }
      for (int i = 0; i < ema26.length; i++) {
        ema26Spots.add(FlSpot((25 + i).toDouble(), ema26[i]));
      }
    }

    if (_selectedIndicators.contains('BOLL')) {
      final boll = _calculateBOLL(20, 2);
      bollUpperSpots = boll['upper'] as List<FlSpot>;
      bollMiddleSpots = boll['middle'] as List<FlSpot>;
      bollLowerSpots = boll['lower'] as List<FlSpot>;
    }

    if (_selectedIndicators.contains('SAR')) {
      sarSpots = _calculateSAR();
    }

    // Создаем точки для candlestick (используем close для упрощения)
    List<FlSpot> closeSpots = [];
    for (int i = 0; i < _klines.length; i++) {
      closeSpots.add(FlSpot(i.toDouble(), _klines[i]['close'] as double));
    }

    // Форматируем время для нижней оси
    List<String> timeLabels = [];
    final step = (_klines.length / 6).ceil();
    for (int i = 0; i < _klines.length; i += step) {
      if (i < _klines.length) {
        final timestamp = _klines[i]['timestamp'] as int;
        final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
        timeLabels.add(
            '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}');
      }
    }

    // Вычисляем видимую область с учетом масштаба и прокрутки
    // Масштаб влияет на количество видимых свечей
    final baseVisibleCandles = 50;
    final scaledVisibleCandles =
        (baseVisibleCandles / _scaleFactor).round().clamp(10, _klines.length);

    // Вычисляем startIndex с учетом прокрутки
    int calculatedStartIndex = _chartStartIndex;

    // Если прокрутка не задана, показываем последние свечи
    if (_chartStartIndex == 0 && _panOffset == Offset.zero) {
      calculatedStartIndex = _klines.length > scaledVisibleCandles
          ? _klines.length - scaledVisibleCandles
          : 0;
    } else {
      // Ограничиваем startIndex в пределах доступных данных
      calculatedStartIndex =
          calculatedStartIndex.clamp(0, _klines.length - scaledVisibleCandles);
    }

    final endIndex =
        (calculatedStartIndex + scaledVisibleCandles).clamp(0, _klines.length);
    final startIndex = calculatedStartIndex;
    final displayedKlines = _klines.sublist(startIndex, endIndex);

    // Пересчитываем min/max для отображаемых свечей
    double displayMinPrice = displayedKlines
        .map((k) => k['low'] as double)
        .reduce((a, b) => a < b ? a : b);
    double displayMaxPrice = displayedKlines
        .map((k) => k['high'] as double)
        .reduce((a, b) => a > b ? a : b);
    final displayPriceRange = displayMaxPrice - displayMinPrice;
    displayMinPrice -= displayPriceRange * 0.05;
    displayMaxPrice += displayPriceRange * 0.05;

    // Пересчитываем spots для отображаемых свечей
    List<FlSpot> displayMa7Spots = _adjustSpotsForDisplay(ma7Spots, startIndex);
    List<FlSpot> displayMa14Spots =
        _adjustSpotsForDisplay(ma14Spots, startIndex);
    List<FlSpot> displayMa28Spots =
        _adjustSpotsForDisplay(ma28Spots, startIndex);
    List<FlSpot> displayEma12Spots =
        _adjustSpotsForDisplay(ema12Spots, startIndex);
    List<FlSpot> displayEma26Spots =
        _adjustSpotsForDisplay(ema26Spots, startIndex);
    List<FlSpot> displayBollUpperSpots =
        _adjustSpotsForDisplay(bollUpperSpots, startIndex);
    List<FlSpot> displayBollMiddleSpots =
        _adjustSpotsForDisplay(bollMiddleSpots, startIndex);
    List<FlSpot> displayBollLowerSpots =
        _adjustSpotsForDisplay(bollLowerSpots, startIndex);
    List<FlSpot> displaySarSpots = _adjustSpotsForDisplay(sarSpots, startIndex);

    return Container(
      height: 320,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 0, 0, 0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: GestureDetector(
        // Масштабирование (pinch-to-zoom)
        onScaleStart: (details) {
          _lastScale = _scaleFactor;
        },
        onScaleUpdate: (details) {
          if (_klines.isEmpty) return;

          setState(() {
            final chartWidth = MediaQuery.of(context).size.width - 32 - 60;

            // Если один палец - это прокрутка (pan)
            if (details.pointerCount == 1) {
              final scaledVisibleCandles =
                  (50 / _scaleFactor).round().clamp(10, _klines.length);

              // Вычисляем смещение в свечах
              final deltaCandles = (details.focalPointDelta.dx /
                      chartWidth *
                      scaledVisibleCandles)
                  .round();

              // Обновляем startIndex
              _chartStartIndex = (_chartStartIndex - deltaCandles)
                  .clamp(0, _klines.length - scaledVisibleCandles);
              _visibleCandles = scaledVisibleCandles;
            }
            // Если два пальца - это масштабирование (zoom)
            else if (details.pointerCount == 2) {
              // Обновляем масштаб
              _scaleFactor = (_lastScale * details.scale).clamp(0.5, 5.0);

              // Пересчитываем количество видимых свечей
              final baseVisibleCandles = 50;
              final scaledVisibleCandles = (baseVisibleCandles / _scaleFactor)
                  .round()
                  .clamp(10, _klines.length);

              // Если мы в конце графика, остаемся в конце
              if (_chartStartIndex == 0 &&
                  _panOffset == Offset.zero &&
                  _klines.length > scaledVisibleCandles) {
                _chartStartIndex = _klines.length - scaledVisibleCandles;
              } else {
                // Сохраняем текущую позицию при масштабировании
                final currentCenter =
                    _chartStartIndex + (_visibleCandles / 2).round();
                _chartStartIndex = (currentCenter - scaledVisibleCandles / 2)
                    .round()
                    .clamp(0, _klines.length - scaledVisibleCandles);
              }
              _visibleCandles = scaledVisibleCandles;
            }
          });
        },
        onScaleEnd: (details) {
          // Сбрасываем pan offset после окончания жеста
          setState(() {
            _panOffset = Offset.zero;
          });
        },
        onTapDown: (details) {
          final chartWidth = MediaQuery.of(context).size.width -
              32 -
              60; // margin + padding + labels
          final spacing = chartWidth / displayedKlines.length;

          final localX = details.localPosition.dx;
          final localY = details.localPosition.dy;
          final chartHeight = 350.0 - 30.0; // height - labels

          // Проверяем, что нажатие в области графика (не на labels)
          if (localY > chartHeight || localX < 0 || localX > chartWidth) {
            // Нажатие вне области графика - скрываем информацию
            if (mounted) {
              setState(() {
                _selectedCandleIndex = null;
                _touchPosition = null;
              });
            }
            return;
          }

          final candleIndex = (localX / spacing).floor();
          final candleCenterX = candleIndex * spacing + spacing / 2;
          final distanceFromCenter = (localX - candleCenterX).abs();

          // Если нажатие близко к центру свечи (в пределах половины ширины свечи)
          if (candleIndex >= 0 &&
              candleIndex < displayedKlines.length &&
              distanceFromCenter < spacing * 0.5) {
            if (mounted) {
              setState(() {
                _selectedCandleIndex = startIndex + candleIndex;
                _touchPosition = details.localPosition;
              });
            }
          } else {
            // Нажатие вне свечей - скрываем информацию
            if (mounted) {
              setState(() {
                _selectedCandleIndex = null;
                _touchPosition = null;
              });
            }
          }
        },
        child: Stack(
          children: [
            // Candlestick chart
            RepaintBoundary(
              child: ClipRect(
                child: CustomPaint(
                  key: ValueKey(
                      'chart_${_klines.length}_${_klines.isNotEmpty ? _klines.last['timestamp'] : 0}'),
                  size: Size.infinite,
                  painter: CandlestickPainter(
                    klines: displayedKlines,
                    minPrice: displayMinPrice,
                    maxPrice: displayMaxPrice,
                    ma7Spots: displayMa7Spots,
                    ma14Spots: displayMa14Spots,
                    ma28Spots: displayMa28Spots,
                    ema12Spots: displayEma12Spots,
                    ema26Spots: displayEma26Spots,
                    bollUpperSpots: displayBollUpperSpots,
                    bollMiddleSpots: displayBollMiddleSpots,
                    bollLowerSpots: displayBollLowerSpots,
                    sarSpots: displaySarSpots,
                    selectedIndicators: _selectedIndicators,
                    selectedIndex: _selectedCandleIndex != null
                        ? _selectedCandleIndex! - startIndex
                        : null,
                  ),
                ),
              ),
            ),
            // Y-axis labels (right side)
            Positioned(
              right: 0,
              top: 0,
              bottom: 30,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(5, (index) {
                  final value = displayMaxPrice -
                      (displayMaxPrice - displayMinPrice) * index / 4;
                  return Text(
                    value.toStringAsFixed(1),
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                    ),
                  );
                }),
              ),
            ),
            // X-axis labels (bottom)
            Positioned(
              left: 0,
              right: 60,
              bottom: 0,
              height: 30,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: timeLabels.map((label) {
                  return Text(
                    label,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                    ),
                  );
                }).toList(),
              ),
            ),
            // Информационное окно при нажатии
            if (_selectedCandleIndex != null &&
                _selectedCandleIndex! < _klines.length)
              _buildCandleInfoOverlay(
                  _klines[_selectedCandleIndex!], _touchPosition),
          ],
        ),
      ),
    );
  }

  Widget _buildCandleInfoOverlay(Map<String, dynamic> kline, Offset? position) {
    if (position == null) return const SizedBox.shrink();

    final open = kline['open'] as double;
    final high = kline['high'] as double;
    final low = kline['low'] as double;
    final close = kline['close'] as double;
    final volume = kline['volume'] as double;
    final timestamp = kline['timestamp'] as int;

    final change = close - open;
    final changePercent = (change / open) * 100;
    final range = high - low;
    final rangePercent = (range / open) * 100;

    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final dateStr =
        '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    final volumeUsdt = volume * close;
    final volumeUsdtStr = volumeUsdt >= 1000000
        ? '${(volumeUsdt / 1000000).toStringAsFixed(2)}M'
        : volumeUsdt >= 1000
            ? '${(volumeUsdt / 1000).toStringAsFixed(2)}K'
            : volumeUsdt.toStringAsFixed(2);

    return Positioned(
      right: 8,
      top: position.dy - 100 < 0 ? position.dy + 20 : position.dy - 200,
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.backgroundCard.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppTheme.borderColor,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Time',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 10,
              ),
            ),
            Text(
              dateStr,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Open',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                  ),
                ),
                Text(
                  open.toStringAsFixed(1),
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'High',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                  ),
                ),
                Text(
                  high.toStringAsFixed(1),
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Low',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                  ),
                ),
                Text(
                  low.toStringAsFixed(1),
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Close',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                  ),
                ),
                Text(
                  close.toStringAsFixed(1),
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Изменение',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                  ),
                ),
                Text(
                  '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)} (${changePercent >= 0 ? '+' : ''}${changePercent.toStringAsFixed(2)}%)',
                  style: TextStyle(
                    color: change >= 0
                        ? AppTheme.primaryGreen
                        : AppTheme.primaryRed,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Диапазон',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                  ),
                ),
                Text(
                  '${range.toStringAsFixed(1)} (${rangePercent.toStringAsFixed(2)}%)',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Объём(BTC)',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                  ),
                ),
                Text(
                  volume.toStringAsFixed(3),
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Объём(USDT)',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                  ),
                ),
                Text(
                  volumeUsdtStr,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Вычисление MA для объемов
  List<double> _calculateVolumeMA(int period) {
    if (_klines.isEmpty || _klines.length < period) {
      return [];
    }

    List<double> ma = [];
    for (int i = period - 1; i < _klines.length; i++) {
      double sum = 0;
      for (int j = i - period + 1; j <= i; j++) {
        sum += _klines[j]['volume'] as double;
      }
      ma.add(sum / period);
    }
    return ma;
  }

  Widget _buildVolumeChart() {
    if (_klines.isEmpty) {
      return const SizedBox.shrink();
    }

    final volumes = _klines.map((k) => k['volume'] as double).toList();
    final maxVolume = volumes.reduce((a, b) => a > b ? a : b);
    final ma5 = _calculateVolumeMA(5);
    final ma10 = _calculateVolumeMA(10);

    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.backgroundCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  children: [
                    Text(
                      'VOL: ${volumes.isNotEmpty ? volumes.last.toStringAsFixed(2) : '0.0'}',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 8,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'MA5: ${ma5.isNotEmpty ? ma5.last.toStringAsFixed(2) : '0.0'}',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 8,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'MA10: ${ma10.isNotEmpty ? ma10.last.toStringAsFixed(2) : '0.0'}',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 8,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    maxVolume.toStringAsFixed(1),
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 7,
                    ),
                  ),
                  Text(
                    (maxVolume / 2).toStringAsFixed(1),
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 7,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 0),
          SizedBox(
            height: 24,
            child: BarChart(
              BarChartData(
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(
                  _klines.length > 50 ? 50 : _klines.length,
                  (index) {
                    final kline = _klines[index];
                    final isUp =
                        (kline['close'] as double) >= (kline['open'] as double);
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: (kline['volume'] as double) / maxVolume,
                          color: isUp
                              ? AppTheme.primaryGreen
                              : AppTheme.primaryRed,
                          width: 4,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(2)),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndicatorTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _indicators.map((indicator) {
            final isSelected = _selectedIndicators.contains(indicator);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedIndicators.remove(indicator);
                    } else {
                      _selectedIndicators.add(indicator);
                    }
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primaryGreen.withValues(alpha: 0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primaryGreen
                          : AppTheme.borderColor,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    indicator,
                    style: TextStyle(
                      color: isSelected
                          ? AppTheme.primaryGreen
                          : AppTheme.textSecondary,
                      fontSize: 11,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildOrderBook() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          // Tabs: Книга ордеров, Трейды, Контракт (для фьючерсов)
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedOrderTab = 'Книга ордеров';
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: _selectedOrderTab == 'Книга ордеров'
                              ? AppTheme.textPrimary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      'Книга ордеров',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _selectedOrderTab == 'Книга ордеров'
                            ? AppTheme.textPrimary
                            : AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: _selectedOrderTab == 'Книга ордеров'
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedOrderTab = 'Трейды';
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: _selectedOrderTab == 'Трейды'
                              ? AppTheme.textPrimary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      'Трейды',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _selectedOrderTab == 'Трейды'
                            ? AppTheme.textPrimary
                            : AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: _selectedOrderTab == 'Трейды'
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
              // Вкладка "Контракт" только для фьючерсов
              if (_selectedMarketType == 'Фьючерсы')
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedOrderTab = 'Контракт';
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _selectedOrderTab == 'Контракт'
                                ? AppTheme.textPrimary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        'Контракт',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _selectedOrderTab == 'Контракт'
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: _selectedOrderTab == 'Контракт'
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // Контент в зависимости от выбранной вкладки
          SizedBox(
            height: 400,
            child: _selectedOrderTab == 'Книга ордеров'
                ? _buildOrderBookContent()
                : _selectedOrderTab == 'Трейды'
                    ? _buildTradesContent()
                    : _selectedOrderTab == 'Контракт'
                        ? _buildContractContent()
                        : _buildOrderBookContent(),
          ),
        ],
      ),
    );
  }

  // Контент для вкладки "Книга ордеров"
  Widget _buildOrderBookContent() {
    final currentPrice = _currentCoin?.price ?? 90877.0;

    return Column(
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.39,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'B 39%',
              style: TextStyle(
                color: AppTheme.primaryGreen,
                fontSize: 10,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '61% S',
              style: TextStyle(
                color: AppTheme.primaryRed,
                fontSize: 10,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.primaryRed.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerRight,
                  widthFactor: 0.61,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.primaryRed,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Кол-во (BTC)',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.left,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Цена (USDT)',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Цена (USDT)',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Кол-во (BTC)',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            children: [
              // Buy orders (left)
              Expanded(
                child: ListView.builder(
                  itemCount: 20,
                  itemBuilder: (context, index) {
                    final price = currentPrice - (index + 1) * 0.1;
                    final quantity = (2.853 - index * 0.1).clamp(0.001, 10.0);
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              quantity.toStringAsFixed(3),
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                              ),
                              textAlign: TextAlign.left,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              price.toStringAsFixed(2),
                              style: TextStyle(
                                color: AppTheme.primaryGreen,
                                fontSize: 11,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Container(
                              height: 20,
                              alignment: Alignment.centerRight,
                              child: Container(
                                width: (quantity / 3.0 * 100).clamp(0.0, 100.0),
                                height: 20,
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryGreen
                                      .withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.only(
                                    topRight: Radius.circular(2),
                                    bottomRight: Radius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              // Current price divider
              Container(
                width: 1,
                color: AppTheme.borderColor.withValues(alpha: 0.3),
                margin: const EdgeInsets.symmetric(horizontal: 8),
              ),
              // Sell orders (right)
              Expanded(
                child: ListView.builder(
                  itemCount: 20,
                  itemBuilder: (context, index) {
                    final price = currentPrice + (index + 1) * 0.1;
                    final quantity = (3.318 - index * 0.15).clamp(0.001, 10.0);
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: Container(
                              height: 20,
                              alignment: Alignment.centerLeft,
                              child: Container(
                                width: (quantity / 3.5 * 100).clamp(0.0, 100.0),
                                height: 20,
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryRed
                                      .withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(2),
                                    bottomLeft: Radius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              price.toStringAsFixed(2),
                              style: TextStyle(
                                color: AppTheme.primaryRed,
                                fontSize: 11,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              quantity.toStringAsFixed(3),
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Контент для вкладки "Трейды"
  Widget _buildTradesContent() {
    final currentPrice = _currentCoin?.price ?? 90877.0;
    final random = math.Random(42);

    // Генерируем список недавних сделок
    final trades = List.generate(50, (index) {
      final isLong = random.nextBool();
      final priceOffset = (random.nextDouble() - 0.5) * 2.0;
      final price = currentPrice + priceOffset;
      final quantity = (random.nextDouble() * 0.5 + 0.001);
      final now = DateTime.now();
      final time = now.subtract(Duration(seconds: index * 2));

      return {
        'time': time,
        'direction': isLong ? 'Long' : 'Short',
        'price': price,
        'quantity': quantity,
      };
    });

    return Column(
      children: [
        const SizedBox(height: 8),
        // Заголовки таблицы
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Время',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.left,
                ),
              ),
              Expanded(
                child: Text(
                  'Направление',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: Text(
                  'Цена',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: Text(
                  'К-во',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppTheme.borderColor),
        // Список сделок
        Flexible(
          child: ListView.builder(
            itemCount: trades.length,
            itemBuilder: (context, index) {
              final trade = trades[index];
              final isLong = trade['direction'] == 'Long';

              return Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: AppTheme.borderColor.withValues(alpha: 0.2),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        () {
                          final time = trade['time'] as DateTime;
                          return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
                        }(),
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.left,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        trade['direction'] as String,
                        style: TextStyle(
                          color: isLong
                              ? AppTheme.primaryGreen
                              : AppTheme.primaryRed,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        (trade['price'] as double).toStringAsFixed(2),
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        (trade['quantity'] as double).toStringAsFixed(3),
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Контент для вкладки "Контракт"
  Widget _buildContractContent() {
    final currentPrice = _currentCoin?.price ?? 90857.90;
    final markPrice = currentPrice + 6.19;
    final indexPrice = currentPrice + 62.47;

    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 8),
          _buildContractRow('Рыноч.Цена', currentPrice.toStringAsFixed(2)),
          _buildContractRow('Цена маркировки', markPrice.toStringAsFixed(2)),
          _buildContractRow('Значение индекса', indexPrice.toStringAsFixed(2)),
          _buildContractRow('Ставка финансирования', '0.0100% Через 8 часов'),
          _buildContractRow('Начальная маржа', '1.0%'),
          _buildContractRow('Поддерживающая маржа', '0.5%'),
          _buildContractRow('24ч Оборот', '7.088B USDT'),
          _buildContractRow('24ч Объем', '78,468.554 BTC'),
          _buildContractRow('Открытые позиции', '58,128.565 BTC'),
          _buildContractRow('Размер тика', '0.1 USDT'),
          _buildContractRow('Макс. цена ордера', '1,999,999.80 USDT'),
          _buildContractRow('Макс. к-во ордеров', '1,190.000 BTC'),
          _buildContractRow('Мин. кол-во', '0.001 BTC'),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildContractRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppTheme.borderColor.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatPriceWithCommas(double price) {
    return price.toStringAsFixed(2).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );
  }

  String _formatQuantity(double qty) {
    if (qty >= 1000) {
      return qty.toStringAsFixed(2);
    } else if (qty >= 1) {
      return qty.toStringAsFixed(4);
    } else if (qty >= 0.01) {
      return qty.toStringAsFixed(6);
    } else {
      return qty.toStringAsFixed(8);
    }
  }

  Widget _buildOrderBookView() {
    final currentPrice = _currentCoin?.price ?? 0.0;
    final baseSymbol = _selectedPair.split('/')[0]; // BTC, ETH и т.д.

    return Container(
      width: 240,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ========== Режим маржи и плечо (только для фьючерсов) ==========
          if (_selectedMarketType == 'Фьючерсы') ...[
            Row(
              children: [
                // Режим маржи
                Expanded(
                  child: _MarginModeDropdown(
                    marginMode: _marginMode,
                    onChanged: (mode) {
                      setState(() {
                        _marginMode = mode;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 4),
                // Плечо
                Expanded(
                  child: _LeverageDropdown(
                    leverage: _leverage,
                    onChanged: (leverage) {
                      setState(() {
                        _leverage = leverage;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          // ========== Доступный баланс ==========
          Container(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'Доступно',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      '${_formatPriceForDisplay(_availableBalance)} USDT',
                      style: TextStyle(
                        color: const Color.fromARGB(255, 252, 255, 254),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () {
                        // Можно добавить функционал пополнения баланса
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Функция пополнения в разработке'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: Icon(
                        Icons.add_circle_outline,
                        color: AppTheme.primaryGreen,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // ========== Тип ордера ==========
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.backgroundCard,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Лимитный',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 9,
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  color: AppTheme.textSecondary,
                  size: 16,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // ========== Цена ==========
          Text(
            'Цена',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 9,
            ),
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.backgroundCard,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: TextField(
                    controller: _priceController,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 10,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: currentPrice > 0
                          ? _formatPriceWithCommas(currentPrice)
                          : '--',
                      hintStyle: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      // Заменяем запятую на точку при вводе
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      TextInputFormatter.withFunction((oldValue, newValue) {
                        // Заменяем запятую на точку
                        final text = newValue.text.replaceAll(',', '.');
                        return TextEditingValue(
                          text: text,
                          selection: newValue.selection,
                        );
                      }),
                    ],
                  ),
                ),
                Text(
                  'USDT',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // ========== Количество ==========
          Text(
            'Количество',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.backgroundCard,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: TextField(
                    controller: _quantityController,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 10,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: '0',
                      hintStyle: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      // Заменяем запятую на точку при вводе
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      TextInputFormatter.withFunction((oldValue, newValue) {
                        // Заменяем запятую на точку
                        final text = newValue.text.replaceAll(',', '.');
                        return TextEditingValue(
                          text: text,
                          selection: newValue.selection,
                        );
                      }),
                    ],
                  ),
                ),
                Text(
                  baseSymbol,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // ========== Процентный слайдер с индикаторами ==========
          LayoutBuilder(
            builder: (context, constraints) {
              final percentages = [0.0, 0.25, 0.5, 0.75, 1.0];

              return SizedBox(
                height: 20,
                child: GestureDetector(
                  onPanStart: (details) {
                    final RenderBox? box =
                        context.findRenderObject() as RenderBox?;
                    if (box == null) return;
                    final localPosition =
                        box.globalToLocal(details.globalPosition);
                    final newValue = (localPosition.dx / constraints.maxWidth)
                        .clamp(0.0, 1.0);
                    // Любое значение от 0 до 1, без привязки
                    setState(() {
                      _percentageSlider = newValue;
                    });
                    final price = double.tryParse(
                            _priceController.text.replaceAll(',', '')) ??
                        0.0;
                    if (price > 0) {
                      final maxQuantity = _availableBalance / price;
                      final quantity = maxQuantity * newValue;
                      _quantityController.text = _formatQuantity(quantity);
                    }
                  },
                  onPanUpdate: (details) {
                    final RenderBox? box =
                        context.findRenderObject() as RenderBox?;
                    if (box == null) return;
                    final localPosition =
                        box.globalToLocal(details.globalPosition);
                    final newValue = (localPosition.dx / constraints.maxWidth)
                        .clamp(0.0, 1.0);
                    // Любое значение от 0 до 1, без привязки
                    setState(() {
                      _percentageSlider = newValue;
                    });
                    final price = double.tryParse(
                            _priceController.text.replaceAll(',', '')) ??
                        0.0;
                    if (price > 0) {
                      final maxQuantity = _availableBalance / price;
                      final quantity = maxQuantity * newValue;
                      _quantityController.text = _formatQuantity(quantity);
                    }
                  },
                  onTapDown: (details) {
                    final RenderBox? box =
                        context.findRenderObject() as RenderBox?;
                    if (box == null) return;
                    final localPosition =
                        box.globalToLocal(details.globalPosition);
                    final newValue = (localPosition.dx / constraints.maxWidth)
                        .clamp(0.0, 1.0);
                    // Любое значение от 0 до 1, без привязки
                    setState(() {
                      _percentageSlider = newValue;
                    });
                    final price = double.tryParse(
                            _priceController.text.replaceAll(',', '')) ??
                        0.0;
                    if (price > 0) {
                      final maxQuantity = _availableBalance / price;
                      final quantity = maxQuantity * newValue;
                      _quantityController.text = _formatQuantity(quantity);
                    }
                  },
                  child: Stack(
                    children: [
                      // Линия слайдера
                      Positioned(
                        left: 10,
                        right: 0,
                        top: 9,
                        child: Container(
                          height: 2,
                          color: AppTheme.borderColor,
                        ),
                      ),
                      // Кружки-индикаторы
                      ...List.generate(5, (index) {
                        final percentage = percentages[index];
                        final position =
                            (constraints.maxWidth - 12) * (index / 4);

                        return Positioned(
                          left: position,
                          top: 4,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _percentageSlider = percentage;
                              });
                              final price = double.tryParse(_priceController
                                      .text
                                      .replaceAll(',', '')) ??
                                  0.0;
                              if (price > 0) {
                                final maxQuantity = _availableBalance / price;
                                final quantity = maxQuantity * percentage;
                                _quantityController.text =
                                    _formatQuantity(quantity);
                              }
                            },
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.borderColor,
                              ),
                            ),
                          ),
                        );
                      }),
                      // Ползунок (белый контур поверх активного кружка)
                      Positioned(
                        left:
                            (constraints.maxWidth - 16) * _percentageSlider - 8,
                        top: 2,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.transparent,
                            border: Border.all(
                              color: Colors.white,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          // ========== Объем ордера ==========
          Text(
            'Объем ордера',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 9,
            ),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.backgroundCard,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: TextField(
                    controller: _totalController,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 10,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: '0',
                      hintStyle: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                Text(
                  'USDT',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Макс. покупка: ${_formatQuantity(_availableBalance / (currentPrice > 0 ? currentPrice : 1))} $baseSymbol',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 8,
            ),
          ),
          // ========== Расчет стоимости/цены ликвидации (только для фьючерсов) ==========
          if (_selectedMarketType == 'Фьючерсы') ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Стоимость',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _calculateOrderCostForFutures(),
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Цена',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _calculateOrderPriceForFutures(),
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Цена ликвидации',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _calculateLiquidationPriceForFutures(),
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    setState(() {});
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundCard,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: AppTheme.borderColor,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      'Рассчитать',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 7,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          // ========== Опции ордера ==========
          Row(
            children: [
              Icon(
                Icons.check_box_outline_blank,
                color: AppTheme.textSecondary,
                size: 12,
              ),
              const SizedBox(width: 4),
              Text(
                'TP/SL',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 9,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.check_box_outline_blank,
                color: AppTheme.textSecondary,
                size: 12,
              ),
              const SizedBox(width: 4),
              Text(
                'Post-Only',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 9,
                ),
              ),
              // Reduce-Only только для фьючерсов
              if (_selectedMarketType == 'Фьючерсы') ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.check_box_outline_blank,
                  color: AppTheme.textSecondary,
                  size: 12,
                ),
                const SizedBox(width: 4),
                Text(
                  'Reduce-Only',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 9,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          // ========== Время действия ордера ==========
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.backgroundCard,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'GTC',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 9,
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  color: AppTheme.textSecondary,
                  size: 16,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // ========== Кнопки Long/Short для фьючерсов или Купить/Продать для спота ==========
          if (_selectedMarketType == 'Фьючерсы') ...[
            // Две кнопки Long и Short - сразу открывают позиции
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _isBuySelected = true;
                      });
                      _handleBuySell();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Long',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _isBuySelected = false;
                      });
                      _handleBuySell();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Short',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            // Для спота - одна кнопка Купить/Продать
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _handleBuySell,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isBuySelected
                      ? AppTheme.primaryGreen
                      : AppTheme.primaryRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  _isBuySelected ? 'Купить' : 'Продать',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOrdersPositionsView() {
    // Фильтруем ордера для счетчика
    var activeOrders = _orders.where((o) => o['status'] == 'active').toList();
    if (_selectedMarketType == 'Спот') {
      activeOrders = activeOrders.where((o) {
        final orderType = o['orderType'] as String?;
        final pair = o['pair'] as String?;
        if (orderType == 'tpsl' && (pair == 'SOL/USDT' || pair == 'LTC/USDT')) {
          return false;
        }
        return true;
      }).toList();
    }
    final activeOrdersCount = activeOrders.length;

    // Фильтруем позиции для счетчика
    final activePositionsCount = _selectedMarketType == 'Спот'
        ? _positions.where((p) {
            final symbol = p['symbol'] as String;
            return symbol != 'SOLUSDT' && symbol != 'LTCUSDT';
          }).length
        : _positions.length;

    final tabs = [
      {'label': 'Ордера ($activeOrdersCount)', 'key': 'Ордера'},
      {'label': 'Позиции ($activePositionsCount)', 'key': 'Позиции'},
      {'label': 'Активы', 'key': 'Активы'},
      {'label': 'Займы (0)', 'key': 'Займы'},
      {'label': 'Инструменты', 'key': 'Инструменты'},
    ];

    return Container(
      color: AppTheme.backgroundDark,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top tabs bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border(
                bottom: BorderSide(
                  color: AppTheme.borderColor.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: tabs.map((tab) {
                        final isSelected = _selectedOrdersTab == tab['key'];
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedOrdersTab = tab['key'] as String;
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 12),
                            padding: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Text(
                              tab['label'] as String,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : AppTheme.textSecondary,
                                fontSize: 11,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                // Settings and list icons
                Icon(
                  Icons.settings,
                  color: AppTheme.textSecondary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.list,
                  color: AppTheme.textSecondary,
                  size: 18,
                ),
              ],
            ),
          ),
          // Filter bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border(
                bottom: BorderSide(
                  color: AppTheme.borderColor.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: Checkbox(
                        value: true,
                        onChanged: (value) {},
                        activeColor: AppTheme.primaryGreen,
                        checkColor: Colors.black,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Все рынки',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Все типы',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 10,
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down,
                      color: AppTheme.textSecondary,
                      size: 16,
                    ),
                  ],
                ),
                const Spacer(),
                Icon(
                  Icons.filter_list,
                  color: AppTheme.textSecondary,
                  size: 18,
                ),
              ],
            ),
          ),
          // Content area - без Expanded, чтобы скроллился вместе с родителем
          Container(
            color: AppTheme.backgroundDark,
            child: _buildOrdersPositionsContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersPositionsContent() {
    if (_selectedOrdersTab == 'Ордера') {
      // Фильтруем ордера: моковые TP/SL ордера показываем только во вкладке "Фьючерсы"
      var activeOrders = _orders.where((o) => o['status'] == 'active').toList();

      // Если выбрана вкладка "Спот", скрываем моковые TP/SL ордера
      if (_selectedMarketType == 'Спот') {
        activeOrders = activeOrders.where((o) {
          final orderType = o['orderType'] as String?;
          final pair = o['pair'] as String?;
          // Скрываем TP/SL ордера для Solana и LTC
          if (orderType == 'tpsl' &&
              (pair == 'SOL/USDT' || pair == 'LTC/USDT')) {
            return false;
          }
          return true;
        }).toList();
      }

      if (activeOrders.isEmpty) {
        return Container(
          color: AppTheme.backgroundDark,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                  ),
                  child: CustomPaint(
                    painter: DocumentIconPainter(),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Нет данных',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: activeOrders.map((order) {
          final isBuy = order['type'] == 'buy';
          final pair = order['pair'] as String;
          final price = order['price'] as double?;
          final quantity = order['quantity'] as double?;
          final total = order['total'] as double?;
          final orderType = order['orderType'] as String?;
          final isTpSl = orderType == 'tpsl';
          final tpPrice = order['tpPrice'] as double?;
          final slPrice = order['slPrice'] as double?;
          final tpTriggerType = order['tpTriggerType'] as String?;
          final slTriggerType = order['slTriggerType'] as String?;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: AppTheme.borderColor.withValues(alpha: 0.1),
                  width: 0.5,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Пара
                    Expanded(
                      child: Text(
                        pair,
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                    // Бессрочные
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(255, 36, 36, 36),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Бессрочные',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Закрыть Long
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(255, 36, 36, 36),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Закрыть Long',
                        style: TextStyle(
                          color: const Color.fromARGB(255, 249, 0, 0),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Spacer(),
                    // Бейджи TP и SL
                    if (isTpSl) ...[
                      if (tpPrice != null && tpPrice > 0)
                        Text(
                          'TP',
                          style: TextStyle(
                            color: const Color.fromARGB(255, 255, 255, 255),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (slPrice != null && slPrice > 0)
                        Text(
                          '/SL',
                          style: TextStyle(
                            color: const Color.fromARGB(255, 255, 255, 255),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ] else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isBuy
                              ? AppTheme.primaryGreen.withValues(alpha: 0.2)
                              : AppTheme.primaryRed.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          isBuy ? 'Купить' : 'Продать',
                          style: TextStyle(
                            color: isBuy
                                ? AppTheme.primaryGreen
                                : AppTheme.primaryRed,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                if (isTpSl) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // Количество и Вся позиция
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Кол-во',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              quantity != null
                                  ? _formatQuantity(quantity)
                                  : '-',
                              style: TextStyle(
                                color: const Color.fromARGB(255, 255, 255, 255),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Триггер. цена
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Триггер. цена',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 9,
                              ),
                            ),
                            const SizedBox(height: 2),
                            if (tpPrice != null &&
                                tpPrice > 0 &&
                                slPrice != null &&
                                slPrice > 0)
                              Row(
                                children: [
                                  Text(
                                    _formatPriceForDisplay(tpPrice),
                                    style: TextStyle(
                                      color: AppTheme.primaryGreen,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    ' / ',
                                    style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 10,
                                    ),
                                  ),
                                  Text(
                                    _formatPriceForDisplay(slPrice),
                                    style: TextStyle(
                                      color: AppTheme.primaryRed,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              )
                            else if (tpPrice != null && tpPrice > 0)
                              Text(
                                _formatPriceForDisplay(tpPrice),
                                style: TextStyle(
                                  color: AppTheme.primaryGreen,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            else if (slPrice != null && slPrice > 0)
                              Text(
                                _formatPriceForDisplay(slPrice),
                                style: TextStyle(
                                  color: AppTheme.primaryRed,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Цена ордера
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Цена ордера',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 9,
                              ),
                            ),
                            const SizedBox(height: 2),
                            if (tpPrice != null &&
                                tpPrice > 0 &&
                                slPrice != null &&
                                slPrice > 0)
                              Row(
                                children: [
                                  Text(
                                    tpTriggerType ?? 'Рыночный',
                                    style: TextStyle(
                                      color: AppTheme.primaryGreen,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    ' / ',
                                    style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 10,
                                    ),
                                  ),
                                  Text(
                                    slTriggerType ?? 'Рыночный',
                                    style: TextStyle(
                                      color: AppTheme.primaryRed,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              )
                            else if (tpPrice != null && tpPrice > 0)
                              Text(
                                tpTriggerType ?? 'Рыночный',
                                style: TextStyle(
                                  color: AppTheme.primaryGreen,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            else if (slPrice != null && slPrice > 0)
                              Text(
                                slTriggerType ?? 'Рыночный',
                                style: TextStyle(
                                  color: AppTheme.primaryRed,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Кнопка Отменить
                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          order['status'] = 'cancelled';
                          if (isBuy && total != null) {
                            _availableBalance += total;
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(255, 0, 0, 0),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.borderColor,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          'Отменить',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      // Цена
                      Expanded(
                        flex: 2,
                        child: Text(
                          price != null ? _formatPriceForDisplay(price) : '-',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      // Количество
                      Expanded(
                        flex: 2,
                        child: Text(
                          quantity != null ? _formatQuantity(quantity) : '-',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 10,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      // Объем
                      Expanded(
                        flex: 2,
                        child: Text(
                          total != null ? _formatPriceForDisplay(total) : '-',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 10,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Кнопка Отменить
                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          order['status'] = 'cancelled';
                          if (isBuy && total != null) {
                            _availableBalance += total;
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.backgroundCard,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: AppTheme.borderColor,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          'Отменить',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      );
    } else if (_selectedOrdersTab == 'Позиции') {
      if (_positions.isEmpty) {
        return Container(
          color: AppTheme.backgroundDark,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                  ),
                  child: CustomPaint(
                    painter: DocumentIconPainter(),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Нет данных',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      // Фильтруем позиции: моковые позиции показываем только во вкладке "Фьючерсы"
      final filteredPositions = _selectedMarketType == 'Спот'
          ? _positions.where((p) {
              final symbol = p['symbol'] as String;
              // Скрываем моковые позиции (Solana и LTC) во вкладке "Спот"
              return symbol != 'SOLUSDT' && symbol != 'LTCUSDT';
            }).toList()
          : _positions;

      if (filteredPositions.isEmpty) {
        return Container(
          color: AppTheme.backgroundDark,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                  ),
                  child: CustomPaint(
                    painter: DocumentIconPainter(),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Нет данных',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: filteredPositions.map((position) {
          return _buildPositionCard(position);
        }).toList(),
      );
    } else if (_selectedOrdersTab == 'Активы') {
      // Экран активов - показываем баланс Единого торгового аккаунта
      final unifiedBalance = MockPortfolioService.unifiedTradingBalance;
      final unrealizedPnl = MockPortfolioService.useMockData
          ? (unifiedBalance - 4427.0) // P&L = текущий баланс - начальный баланс
          : 0.0;

      return Container(
        color: AppTheme.backgroundDark,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок
            Text(
              'Единый торговый',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            // Баланс
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.backgroundCard,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Баланс',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_formatPriceForDisplay(unifiedBalance)} USDT',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (unrealizedPnl != 0.0) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'Нереализованный P&L: ',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          '${unrealizedPnl >= 0 ? '+' : ''}${_formatPriceForDisplay(unrealizedPnl)} USDT',
                          style: TextStyle(
                            color: unrealizedPnl >= 0
                                ? AppTheme.primaryGreen
                                : AppTheme.primaryRed,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Информация о позициях
            Text(
              'Активы связаны с позициями',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Баланс обновляется в зависимости от P&L позиций Solana и LTC',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    } else {
      // Для других табов показываем пустое состояние
      return Container(
        color: AppTheme.backgroundDark,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                ),
                child: CustomPaint(
                  painter: DocumentIconPainter(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Нет данных',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildOrderBookRight() {
    final currentPrice = _currentCoin?.price ?? 0.0;

    // Получаем символ для отображения количества (BTC, ETH и т.д.)
    final baseSymbol = _selectedPair.split('/')[0];

    // Парсим данные книги ордеров
    List<Map<String, double>> asks = [];
    List<Map<String, double>> bids = [];
    double totalAskVolume = 0.0;
    double totalBidVolume = 0.0;

    if (_orderBookData != null && _isLoadingOrderBook == false) {
      final asksList = _orderBookData!['a'] as List<dynamic>? ?? [];
      final bidsList = _orderBookData!['b'] as List<dynamic>? ?? [];

      // Парсим asks (ордера на продажу)
      for (var item in asksList.take(10)) {
        if (item is List && item.length >= 2) {
          final price = double.tryParse(item[0].toString()) ?? 0.0;
          final qty = double.tryParse(item[1].toString()) ?? 0.0;
          if (price > 0 && qty > 0) {
            asks.add({'price': price, 'qty': qty});
            totalAskVolume += qty * price;
          }
        }
      }

      // Парсим bids (ордера на покупку)
      for (var item in bidsList.take(10)) {
        if (item is List && item.length >= 2) {
          final price = double.tryParse(item[0].toString()) ?? 0.0;
          final qty = double.tryParse(item[1].toString()) ?? 0.0;
          if (price > 0 && qty > 0) {
            bids.add({'price': price, 'qty': qty});
            totalBidVolume += qty * price;
          }
        }
      }
    }

    // Вычисляем реальные проценты
    final totalVolume = totalAskVolume + totalBidVolume;
    final buyPercent =
        totalVolume > 0 ? (totalBidVolume / totalVolume * 100) : 50.0;
    final sellPercent =
        totalVolume > 0 ? (totalAskVolume / totalVolume * 100) : 50.0;

    // Находим максимальное количество для нормализации глубины
    double maxQty = 0.0;
    for (var ask in asks) {
      if (ask['qty']! > maxQty) maxQty = ask['qty']!;
    }
    for (var bid in bids) {
      if (bid['qty']! > maxQty) maxQty = bid['qty']!;
    }
    if (maxQty == 0.0) maxQty = 1.0; // Избегаем деления на ноль

    return SizedBox(
      width: 240,
      height: 363,
      child: Container(
        color: AppTheme.backgroundDark,
        child: Column(
          children: [
            // Иконки и Funding Rate для фьючерсов (вверху книжки ордеров)
            if (_selectedMarketType == 'Фьючерсы')
              Column(
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(
                          Icons.show_chart,
                          color: AppTheme.textSecondary,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Stack(
                          children: [
                            Icon(
                              Icons.more_vert,
                              color: AppTheme.textSecondary,
                              size: 18,
                            ),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryRed,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Funding Rate / Отсчет
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Funding Rate / Отсчет',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 8,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              '${_fundingRate >= 0 ? '+' : ''}${_fundingRate.toStringAsFixed(4)}%',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 8,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '/',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 8,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatCountdown(_fundingRateCountdown),
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 8,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            // Order book headers
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Цена (USDT)',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 9,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        'Кол-во ($baseSymbol)',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 9,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_drop_down,
                        color: AppTheme.textSecondary,
                        size: 14,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Asks (sell orders) - red
            _isLoadingOrderBook
                ? Expanded(
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.primaryGreen,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                : asks.isEmpty
                    ? Expanded(
                        child: Center(
                          child: Text(
                            'Нет данных',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      )
                    : Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          switchInCurve: Curves.easeInOut,
                          switchOutCurve: Curves.easeInOut,
                          child: SingleChildScrollView(
                            key: ValueKey(
                                'asks_${asks.length}_${asks.firstOrNull?['price'] ?? 0}'),
                            reverse: true,
                            physics: const NeverScrollableScrollPhysics(),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: asks.reversed.map((order) {
                                final price = order['price']!;
                                final qty = order['qty']!;
                                return Padding(
                                  key: ValueKey('ask_$price'),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 1),
                                  child: Stack(
                                    children: [
                                      // Background bar
                                      Positioned.fill(
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: FractionallySizedBox(
                                            widthFactor:
                                                (qty / maxQty).clamp(0.0, 1.0),
                                            child: Container(
                                              height: 18,
                                              decoration: BoxDecoration(
                                                color: AppTheme.primaryRed
                                                    .withValues(alpha: 0.2),
                                                borderRadius:
                                                    BorderRadius.circular(2),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Content
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _formatPriceWithCommas(price),
                                            style: TextStyle(
                                              color: AppTheme.primaryRed,
                                              fontSize: 10,
                                            ),
                                          ),
                                          Text(
                                            _formatQuantity(qty),
                                            style: TextStyle(
                                              color: AppTheme.textSecondary,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
            // Current price
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: child,
                );
              },
              child: Padding(
                key: ValueKey('price_$currentPrice'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentPrice > 0
                              ? _formatPriceWithCommas(currentPrice)
                              : '--',
                          style: TextStyle(
                            color: currentPrice > 0
                                ? (_currentCoin?.change24h ?? 0) >= 0
                                    ? AppTheme.primaryGreen
                                    : AppTheme.primaryRed
                                : AppTheme.textSecondary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          currentPrice > 0
                              ? '≈${_formatPriceWithCommas(currentPrice)} USD'
                              : '-- USD',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: AppTheme.textPrimary,
                      size: 12,
                    ),
                  ],
                ),
              ),
            ),
            // Bids (buy orders) - green
            _isLoadingOrderBook
                ? const Expanded(child: SizedBox.shrink())
                : bids.isEmpty
                    ? Expanded(
                        child: Center(
                          child: Text(
                            'Нет данных',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      )
                    : Expanded(
                        child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: bids.map((order) {
                              final price = order['price']!;
                              final qty = order['qty']!;
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 1),
                                child: Stack(
                                  children: [
                                    // Background bar
                                    Positioned.fill(
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: FractionallySizedBox(
                                          widthFactor:
                                              (qty / maxQty).clamp(0.0, 1.0),
                                          child: Container(
                                            height: 18,
                                            decoration: BoxDecoration(
                                              color: AppTheme.primaryGreen
                                                  .withValues(alpha: 0.2),
                                              borderRadius:
                                                  BorderRadius.circular(2),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Content
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _formatPriceWithCommas(price),
                                          style: TextStyle(
                                            color: AppTheme.primaryGreen,
                                            fontSize: 10,
                                          ),
                                        ),
                                        Text(
                                          _formatQuantity(qty),
                                          style: TextStyle(
                                            color: AppTheme.textSecondary,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
            const SizedBox(height: 4),
            // Sentiment bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: (buyPercent / 100).clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppTheme.primaryGreen,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'B ${buyPercent.toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: AppTheme.primaryGreen,
                      fontSize: 9,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${sellPercent.toStringAsFixed(0)}% S',
                    style: TextStyle(
                      color: AppTheme.primaryRed,
                      fontSize: 9,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryRed.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerRight,
                        widthFactor: (sellPercent / 100).clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppTheme.primaryRed,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            // Bottom input
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundCard,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '0.01',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_drop_down,
                          color: AppTheme.textSecondary,
                          size: 14,
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryRed,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPositionCard(Map<String, dynamic> position) {
    final symbol = position['symbol'] as String;
    final side = position['side'] as String;
    final isLong = side == 'Long';
    final size = position['size'] as double;
    final entryPrice = position['entryPrice'] as double;
    final markPrice = position['markPrice'] as double;
    final leverage = position['leverage'] as int;
    final marginMode = position['marginMode'] as String;
    final unrealizedPnl = position['unrealizedPnl'] as double;
    final unrealizedPnlPercent = position['unrealizedPnlPercent'] as double;
    final liquidationPrice = position['liquidationPrice'] as double;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 0, 0, 0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppTheme.borderColor.withValues(alpha: 0.3),
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Верхняя часть: символ / направление / плечо слева, P&L справа
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Левая часть
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          symbol,
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                AppTheme.primaryGreen.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isLong ? 'Лонг' : 'Шорт',
                            style: TextStyle(
                              color: AppTheme.primaryGreen,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${marginMode == 'Cross' ? 'Кросс' : 'Изолированная'} ${leverage.toStringAsFixed(0)}x',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              // Правая часть: нереализованный P&L
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Нереализ. P&L',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        Icons.open_in_new,
                        color: AppTheme.textSecondary,
                        size: 10,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    unrealizedPnl >= 0
                        ? '+${unrealizedPnl.toStringAsFixed(2)}'
                        : unrealizedPnl.toStringAsFixed(2),
                    style: TextStyle(
                      color: unrealizedPnl >= 0
                          ? AppTheme.primaryGreen
                          : AppTheme.primaryRed,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '(${unrealizedPnlPercent >= 0 ? '+' : ''}${unrealizedPnlPercent.toStringAsFixed(2)}%)',
                    style: TextStyle(
                      color: unrealizedPnlPercent >= 0
                          ? AppTheme.primaryGreen
                          : AppTheme.primaryRed,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Средняя часть: четыре колонки с основными параметрами
          Row(
            children: [
              _buildPositionStatColumn(
                'Размер позиции',
                _formatQuantity(size),
              ),
              _buildPositionStatColumn(
                'Цена входа',
                _formatPriceForDisplay(entryPrice),
              ),
              _buildPositionStatColumn(
                'Цена маркировки',
                _formatPriceForDisplay(markPrice),
              ),
              _buildPositionStatColumn(
                'Ориент. цена ликвидации',
                _formatPriceForDisplay(liquidationPrice),
                isWarning: true,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // TP/SL информация

          const SizedBox(height: 8),
          // Кнопки действий
          Row(
            children: [
              Expanded(
                child: _buildPositionActionButton(
                  'Установить TP/SL',
                  () {
                    _showTpSlDialog(position);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildPositionActionButton(
                  'Скользящий стоп-ордер',
                  () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Функция в разработке'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildPositionActionButton(
                  'Закрыть с помощью',
                  () {
                    _showClosePositionDialog(position);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Колонка для блока с основными параметрами позиции (размер, цены и т.п.)
  Widget _buildPositionStatColumn(String label, String value,
      {bool isWarning = false}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: isWarning ? Colors.orange : AppTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPositionActionButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppTheme.textPrimary.withValues(alpha: 0.8),
            width: 1,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  void _showTpSlDialog(Map<String, dynamic> position) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _TpSlDialogContent(
        position: position,
        onSave:
            (tpPrice, slPrice, tpTriggerType, slTriggerType, isFullPosition) {
          setState(() {
            position['tpPrice'] = tpPrice;
            position['slPrice'] = slPrice;

            final pair = position['pair'] as String;
            final side = position['side'] as String;
            final size = position['size'] as double;
            final entryPrice = position['entryPrice'] as double;

            // Создаем один ордер для TP/SL с данными обоих
            if ((tpPrice != null && tpPrice > 0) ||
                (slPrice != null && slPrice > 0)) {
              final tpSlOrder = {
                'id': 'tpsl_${DateTime.now().millisecondsSinceEpoch}',
                'type': side == 'Long' ? 'sell' : 'buy',
                'pair': pair,
                'status': 'active',
                'createdAt': DateTime.now(),
                'orderType': 'tpsl', // Тип ордера - TP/SL
                'tpPrice': tpPrice,
                'slPrice': slPrice,
                'tpTriggerType': tpTriggerType,
                'slTriggerType': slTriggerType,
                'quantity': isFullPosition ? size : (size * 0.5),
                'entryPrice': entryPrice,
              };
              _orders.add(tpSlOrder);
            }
          });
        },
      ),
    );
  }

  void _showClosePositionDialog(Map<String, dynamic> position) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.backgroundCard,
        title: Text(
          'Закрыть позицию',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          'Вы уверены, что хотите закрыть позицию ${position['symbol']}?',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Отмена',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              // Получаем нереализованный P&L перед закрытием
              final unrealizedPnl = position['unrealizedPnl'] as double? ?? 0.0;
              final size = position['size'] as double;
              final entryPrice = position['entryPrice'] as double;
              final symbol = position['symbol'] as String;

              // Для всех позиций возвращаем только P&L
              // Маржа НЕ вычиталась при создании моковых позиций, поэтому не возвращаем её
              // Возвращаем только реализованный P&L
              final margin = entryPrice * size;
              final maxPnl = margin * 10; // Максимальный P&L = 10x от маржи
              final limitedPnl = unrealizedPnl.clamp(
                  -margin, maxPnl); // P&L не может быть больше -100% или +1000%

              // Возвращаем только P&L (маржа не вычиталась при создании моковых позиций)
              final totalToAdd = limitedPnl; // Только P&L для всех позиций

              // Отладочная информация (можно убрать позже)
              print('Закрытие позиции: $symbol');
              print('  Маржа: $margin (entryPrice: $entryPrice, size: $size)');
              print('  P&L: $unrealizedPnl (ограничен: $limitedPnl)');
              print(
                  '  Итого на счет: $totalToAdd (только P&L, маржа не возвращается)');

              // Сохраняем пару позиции для удаления ордеров
              final positionPair = position['pair'] as String;

              // Сначала собираем ордера для удаления (до setState, чтобы избежать ConcurrentModificationError)
              final ordersToRemove = _orders.where((o) {
                final orderType = o['orderType'] as String?;
                final orderPair = o['pair'] as String?;
                return orderType == 'tpsl' && orderPair == positionPair;
              }).toList();

              // Добавляем средства на баланс единого торгового аккаунта
              if (totalToAdd != 0.0) {
                MockPortfolioService.realizePnl(totalToAdd);
              }

              // Удаляем из глобального хранилища
              final positionId =
                  position['id'] as String? ?? position['id'].toString();
              MockPortfolioService.removePosition(positionId);

              setState(() {
                // Обновляем локальный список из глобального хранилища
                _positions = List.from(MockPortfolioService.getPositions());

                // Удаляем связанные TP/SL ордера при закрытии позиции
                for (var order in ordersToRemove) {
                  _orders.remove(order);
                }
              });

              Navigator.pop(context);

              // Обновляем P&L после закрытия позиции (вне setState, так как это async)
              // Используем Future.microtask чтобы выполнить после завершения setState
              Future.microtask(() async {
                if (!mounted) return;
                await _updateAllPositionsPnl();
                // Уведомляем об изменении баланса
                if (mounted) {
                  MockPortfolioService.balanceNotifier.value =
                      MockPortfolioService.unifiedTradingBalance;
                  if (mounted) {
                    await _loadAvailableBalance();
                  }
                }
              });
            },
            child: Text(
              'Закрыть',
              style: TextStyle(color: AppTheme.primaryRed),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.backgroundCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Левая часть - иконки в ряд
          Row(
            children: [
              // Инструменты
              GestureDetector(
                onTap: () {},
                child: Container(
                  width: 48,
                  height: 48,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.show_chart,
                        color: AppTheme.textPrimary,
                        size: 20,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Инструменты',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 7,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Фьючерсы
              GestureDetector(
                onTap: () {},
                child: Container(
                  width: 48,
                  height: 48,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.description,
                        color: AppTheme.textPrimary,
                        size: 20,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Фьючерсы',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 7,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          // Правая часть - кнопки Купить и Продать (меньше)
          Expanded(
            child: Row(
              children: [
                // Кнопка Купить
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF26B626),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Купить',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Кнопка Продать
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Продать',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Вспомогательные методы для расчетов фьючерсов
  String _calculateOrderCostForFutures() {
    final price =
        double.tryParse(_priceController.text.replaceAll(',', '')) ?? 0.0;
    final quantity =
        double.tryParse(_quantityController.text.replaceAll(',', '')) ?? 0.0;
    if (price > 0 && quantity > 0) {
      final cost = (price * quantity) / _leverage;
      return '${_formatPriceForDisplay(cost)} USDT';
    }
    return '0/0 USDT';
  }

  String _calculateOrderPriceForFutures() {
    final price =
        double.tryParse(_priceController.text.replaceAll(',', '')) ?? 0.0;
    if (price > 0) {
      return '${_formatPriceForDisplay(price)} USDT';
    }
    return '0/0 USDT';
  }

  String _calculateLiquidationPriceForFutures() {
    final price =
        double.tryParse(_priceController.text.replaceAll(',', '')) ?? 0.0;
    final quantity =
        double.tryParse(_quantityController.text.replaceAll(',', '')) ?? 0.0;
    if (price > 0 && quantity > 0) {
      final liquidationPrice = _calculateLiquidationPrice(
          price, quantity, _leverage, _isBuySelected);
      return '${_formatPriceForDisplay(liquidationPrice)} USDT';
    }
    return '0/0 USDT';
  }

  // Форматирование времени отсчета Funding Rate
  String _formatCountdown(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

// Отдельный StatefulWidget для модального окна TP/SL
class _TpSlDialogContent extends StatefulWidget {
  final Map<String, dynamic> position;
  final Function(double?, double?, String, String, bool) onSave;

  const _TpSlDialogContent({
    required this.position,
    required this.onSave,
  });

  @override
  State<_TpSlDialogContent> createState() => _TpSlDialogContentState();
}

class _TpSlDialogContentState extends State<_TpSlDialogContent> {
  late final double size;
  late final double entryPrice;
  late final double markPrice;
  late final double liquidationPrice;
  late final bool isLong;

  bool isFullPosition = true;
  String tpTriggerType = 'Рыночный';
  String slTriggerType = 'Рыночный';
  double tpRoi = 10.0;
  double slRoi = 10.0;

  late final TextEditingController tpPriceController;
  late final TextEditingController slPriceController;

  @override
  void initState() {
    super.initState();
    size = widget.position['size'] as double;
    entryPrice = widget.position['entryPrice'] as double;
    markPrice = widget.position['markPrice'] as double;
    liquidationPrice = widget.position['liquidationPrice'] as double;
    isLong = widget.position['side'] == 'Long';

    // Получаем существующие TP/SL цены или вычисляем на основе ROI
    final existingTpPrice = widget.position['tpPrice'] as double?;
    final existingSlPrice = widget.position['slPrice'] as double?;

    // Вычисляем ROI на основе существующих цен или используем значения по умолчанию
    if (existingTpPrice != null && existingTpPrice > 0) {
      if (isLong) {
        tpRoi = ((existingTpPrice / entryPrice) - 1) * 100;
      } else {
        tpRoi = (1 - (existingTpPrice / entryPrice)) * 100;
      }
      tpRoi = tpRoi.clamp(0.0, 150.0);
    }

    if (existingSlPrice != null && existingSlPrice > 0) {
      if (isLong) {
        slRoi = (1 - (existingSlPrice / entryPrice)) * 100;
      } else {
        slRoi = ((existingSlPrice / entryPrice) - 1) * 100;
      }
      slRoi = slRoi.clamp(0.0, 75.0);
    }

    // Инициализация цен
    final initialTpPrice = existingTpPrice ??
        (isLong
            ? entryPrice * (1 + tpRoi / 100)
            : entryPrice * (1 - tpRoi / 100));
    final initialSlPrice = existingSlPrice ??
        (isLong
            ? entryPrice * (1 - slRoi / 100)
            : entryPrice * (1 + slRoi / 100));

    tpPriceController = TextEditingController(
      text: initialTpPrice.toStringAsFixed(4),
    );
    slPriceController = TextEditingController(
      text: initialSlPrice.toStringAsFixed(4),
    );
  }

  @override
  void dispose() {
    tpPriceController.dispose();
    slPriceController.dispose();
    super.dispose();
  }

  // Функции для пересчета
  void _updateTpPriceFromRoi() {
    final tpPrice = isLong
        ? entryPrice * (1 + tpRoi / 100)
        : entryPrice * (1 - tpRoi / 100);
    tpPriceController.text = tpPrice.toStringAsFixed(4);
  }

  void _updateSlPriceFromRoi() {
    final slPrice = isLong
        ? entryPrice * (1 - slRoi / 100)
        : entryPrice * (1 + slRoi / 100);
    slPriceController.text = slPrice.toStringAsFixed(4);
  }

  void _updateTpRoiFromPrice() {
    // Нормализуем строку: заменяем запятую на точку для парсинга
    final tpPriceText = tpPriceController.text.replaceAll(',', '.');
    final tpPrice = double.tryParse(tpPriceText) ?? entryPrice;
    if (isLong) {
      tpRoi = ((tpPrice / entryPrice) - 1) * 100;
    } else {
      tpRoi = (1 - (tpPrice / entryPrice)) * 100;
    }
    tpRoi = tpRoi.clamp(0.0, 150.0);
  }

  void _updateSlRoiFromPrice() {
    // Нормализуем строку: заменяем запятую на точку для парсинга
    final slPriceText = slPriceController.text.replaceAll(',', '.');
    final slPrice = double.tryParse(slPriceText) ?? entryPrice;
    if (isLong) {
      slRoi = (1 - (slPrice / entryPrice)) * 100;
    } else {
      slRoi = ((slPrice / entryPrice) - 1) * 100;
    }
    slRoi = slRoi.clamp(0.0, 75.0);
  }

  Widget _buildTriggerTypeOption(
      String title, VoidCallback onTap, bool isSelected) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color:
              isSelected ? Colors.orange.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.orange : AppTheme.textPrimary,
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Заголовок TP/SL
          Text(
            'TP/SL',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          // Метрики позиции
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Кол-во',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      size.toStringAsFixed(1),
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Цена входа',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entryPrice.toStringAsFixed(4),
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Рыноч.Цена',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      markPrice.toStringAsFixed(4),
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Цена ликв.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      liquidationPrice.toStringAsFixed(4),
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Переключатель Вся позиция / Часть позиции (как вкладки)
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      isFullPosition = true;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isFullPosition
                              ? Colors.orange
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      'Вся позиция',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      isFullPosition = false;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: !isFullPosition
                              ? Colors.orange
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      'Часть позиции',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              Icon(
                Icons.help_outline,
                color: AppTheme.textSecondary,
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Take Profit и Stop Loss секции
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Take Profit заголовок (без контейнера)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Take Profit-Срабатывание по ROI (%)',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Icon(
                        Icons.arrow_drop_down,
                        color: AppTheme.textSecondary,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Триггер цена и ROI для TP в одном ряду
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.backgroundCard,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: tpPriceController,
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.left,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  inputFormatters: [
                                    // Заменяем запятую на точку при вводе
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'[0-9.,]')),
                                    TextInputFormatter.withFunction(
                                        (oldValue, newValue) {
                                      // Заменяем запятую на точку
                                      final text =
                                          newValue.text.replaceAll(',', '.');
                                      return TextEditingValue(
                                        text: text,
                                        selection: newValue.selection,
                                      );
                                    }),
                                  ],
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                    hintText: 'Триггер. цена',
                                    hintStyle: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                  onChanged: (value) {
                                    if (value.isNotEmpty) {
                                      setState(() {
                                        _updateTpRoiFromPrice();
                                      });
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: GestureDetector(
                                  onTap: () {
                                    // Показываем выпадающий список для выбора типа триггера
                                    showModalBottomSheet(
                                      context: context,
                                      backgroundColor: AppTheme.backgroundCard,
                                      builder: (context) => Container(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _buildTriggerTypeOption('Рыночный',
                                                () {
                                              setState(() {
                                                tpTriggerType = 'Рыночный';
                                              });
                                              Navigator.pop(context);
                                            }, tpTriggerType == 'Рыночный'),
                                            _buildTriggerTypeOption(
                                                'Последняя цена', () {
                                              setState(() {
                                                tpTriggerType =
                                                    'Последняя цена';
                                              });
                                              Navigator.pop(context);
                                            },
                                                tpTriggerType ==
                                                    'Последняя цена'),
                                            _buildTriggerTypeOption(
                                                'Индексная цена', () {
                                              setState(() {
                                                tpTriggerType =
                                                    'Индексная цена';
                                              });
                                              Navigator.pop(context);
                                            },
                                                tpTriggerType ==
                                                    'Индексная цена'),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          tpTriggerType,
                                          style: TextStyle(
                                            color: AppTheme.textPrimary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.arrow_drop_down,
                                        color: AppTheme.textSecondary,
                                        size: 16,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.backgroundCard,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'ROI',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    tpRoi.toStringAsFixed(1),
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '%',
                                    style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Слайдер для TP
                  Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '0%',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                          Text(
                            '10%',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                          Text(
                            '150%',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: tpRoi,
                        min: 0,
                        max: 150,
                        divisions: 150,
                        activeColor: Colors.orange,
                        inactiveColor: AppTheme.backgroundCard,
                        onChanged: (value) {
                          setState(() {
                            tpRoi = value;
                            _updateTpPriceFromRoi();
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Stop Loss заголовок (без контейнера)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Stop Loss-Срабатывание по ROI (%)',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Icon(
                        Icons.arrow_drop_down,
                        color: AppTheme.textSecondary,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Триггер цена и ROI для SL в одном ряду
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.backgroundCard,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: slPriceController,
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.left,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  inputFormatters: [
                                    // Заменяем запятую на точку при вводе
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'[0-9.,]')),
                                    TextInputFormatter.withFunction(
                                        (oldValue, newValue) {
                                      // Заменяем запятую на точку
                                      final text =
                                          newValue.text.replaceAll(',', '.');
                                      return TextEditingValue(
                                        text: text,
                                        selection: newValue.selection,
                                      );
                                    }),
                                  ],
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                    hintText: 'Триггер. цена',
                                    hintStyle: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                  onChanged: (value) {
                                    if (value.isNotEmpty) {
                                      setState(() {
                                        _updateSlRoiFromPrice();
                                      });
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: GestureDetector(
                                  onTap: () {
                                    // Показываем выпадающий список для выбора типа триггера
                                    showModalBottomSheet(
                                      context: context,
                                      backgroundColor: AppTheme.backgroundCard,
                                      builder: (context) => Container(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _buildTriggerTypeOption('Рыночный',
                                                () {
                                              setState(() {
                                                slTriggerType = 'Рыночный';
                                              });
                                              Navigator.pop(context);
                                            }, slTriggerType == 'Рыночный'),
                                            _buildTriggerTypeOption(
                                                'Последняя цена', () {
                                              setState(() {
                                                slTriggerType =
                                                    'Последняя цена';
                                              });
                                              Navigator.pop(context);
                                            },
                                                slTriggerType ==
                                                    'Последняя цена'),
                                            _buildTriggerTypeOption(
                                                'Индексная цена', () {
                                              setState(() {
                                                slTriggerType =
                                                    'Индексная цена';
                                              });
                                              Navigator.pop(context);
                                            },
                                                slTriggerType ==
                                                    'Индексная цена'),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          slTriggerType,
                                          style: TextStyle(
                                            color: AppTheme.textPrimary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.arrow_drop_down,
                                        color: AppTheme.textSecondary,
                                        size: 16,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.backgroundCard,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'ROI',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    slRoi.toStringAsFixed(1),
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '%',
                                    style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Слайдер для SL
                  Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '0%',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                          Text(
                            '10%',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                          Text(
                            '75%',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: slRoi,
                        min: 0,
                        max: 75,
                        divisions: 75,
                        activeColor: Colors.orange,
                        inactiveColor: AppTheme.backgroundCard,
                        onChanged: (value) {
                          setState(() {
                            slRoi = value;
                            _updateSlPriceFromRoi();
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          // Кнопка Подтвердить
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 16),
            child: ElevatedButton(
              onPressed: () {
                // Сохраняем TP/SL в позицию
                // Нормализуем строки: заменяем запятую на точку для парсинга
                final tpPriceText = tpPriceController.text.replaceAll(',', '.');
                final slPriceText = slPriceController.text.replaceAll(',', '.');
                final tpPrice = double.tryParse(tpPriceText) ?? 0.0;
                final slPrice = double.tryParse(slPriceText) ?? 0.0;

                widget.onSave(
                  tpPrice > 0 ? tpPrice : null,
                  slPrice > 0 ? slPrice : null,
                  tpTriggerType,
                  slTriggerType,
                  isFullPosition,
                );

                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('TP/SL установлены'),
                    backgroundColor: AppTheme.primaryGreen,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(
                'Подтвердить',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Выпадающий список для режима маржи
class _MarginModeDropdown extends StatefulWidget {
  final String marginMode;
  final Function(String) onChanged;

  const _MarginModeDropdown({
    required this.marginMode,
    required this.onChanged,
  });

  @override
  State<_MarginModeDropdown> createState() => _MarginModeDropdownState();
}

class _MarginModeDropdownState extends State<_MarginModeDropdown> {
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  void _showDropdown() {
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideDropdown() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  OverlayEntry _createOverlayEntry() {
    RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    final size = renderBox?.size ?? Size.zero;

    return OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 4),
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.backgroundCard,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildOption('Isolated', 'Изолированная'),
                  Container(height: 1, color: AppTheme.borderColor),
                  _buildOption('Cross', 'Кросс'),
                  Container(height: 1, color: AppTheme.borderColor),
                  _buildOption('Portfolio', 'Портфель'),
                  Container(height: 1, color: AppTheme.borderColor),
                  _buildOption('More', 'Подробнее'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOption(String mode, String title) {
    final isSelected = widget.marginMode == mode;
    return GestureDetector(
      onTap: () {
        if (mode == 'More') {
          _hideDropdown();
          return;
        }
        widget.onChanged(mode);
        _hideDropdown();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isSelected
                      ? const Color(0xFFFF6B35)
                      : AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hideDropdown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        onTap: () {
          if (_overlayEntry == null) {
            _showDropdown();
          } else {
            _hideDropdown();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.backgroundCard,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.marginMode == 'Cross'
                    ? 'Кросс'
                    : widget.marginMode == 'Portfolio'
                        ? 'Портфель'
                        : 'Изолированная',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 9,
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                color: AppTheme.textSecondary,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Выпадающий список для плеча
class _LeverageDropdown extends StatefulWidget {
  final int leverage;
  final Function(int) onChanged;

  const _LeverageDropdown({
    required this.leverage,
    required this.onChanged,
  });

  @override
  State<_LeverageDropdown> createState() => _LeverageDropdownState();
}

class _LeverageDropdownState extends State<_LeverageDropdown> {
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();
  final leverageOptions = [1, 3, 5, 10, 25, 50, 100];

  void _showDropdown() {
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideDropdown() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  OverlayEntry _createOverlayEntry() {
    RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    final size = renderBox?.size ?? Size.zero;

    return OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 4),
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.backgroundCard,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...leverageOptions.map((leverage) {
                    final isLast = leverage == leverageOptions.last;
                    return Column(
                      children: [
                        _buildOption(leverage),
                        if (!isLast)
                          Container(height: 1, color: AppTheme.borderColor),
                      ],
                    );
                  }),
                  Container(height: 1, color: AppTheme.borderColor),
                  _buildCustomizeOption(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOption(int leverage) {
    final isSelected = widget.leverage == leverage;
    return GestureDetector(
      onTap: () {
        widget.onChanged(leverage);
        _hideDropdown();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                leverage == 100 ? '100.0x' : '${leverage}x',
                style: TextStyle(
                  color: isSelected
                      ? const Color(0xFFFF6B35)
                      : AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomizeOption() {
    return GestureDetector(
      onTap: () {
        _hideDropdown();
        _showCustomLeverageDialog();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Настроить',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomLeverageDialog() {
    final controller = TextEditingController(text: widget.leverage.toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.backgroundCard,
        title: Text(
          'Настроить плечо',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: TextField(
          controller: controller,
          style: TextStyle(color: AppTheme.textPrimary),
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'Введите плечо (1-100)',
            hintStyle: TextStyle(color: AppTheme.textSecondary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppTheme.borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppTheme.borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppTheme.primaryGreen),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Отмена',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              final value = int.tryParse(controller.text);
              if (value != null && value >= 1 && value <= 100) {
                widget.onChanged(value);
                Navigator.pop(context);
              }
            },
            child: Text(
              'Применить',
              style: TextStyle(color: AppTheme.primaryGreen),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _hideDropdown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        onTap: () {
          if (_overlayEntry == null) {
            _showDropdown();
          } else {
            _hideDropdown();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.backgroundCard,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${widget.leverage}x',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 9,
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                color: AppTheme.textSecondary,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Кастомный painter для отрисовки candlestick графика
class CandlestickPainter extends CustomPainter {
  final List<Map<String, dynamic>> klines;
  final double minPrice;
  final double maxPrice;
  final List<FlSpot> ma7Spots;
  final List<FlSpot> ma14Spots;
  final List<FlSpot> ma28Spots;
  final List<FlSpot> ema12Spots;
  final List<FlSpot> ema26Spots;
  final List<FlSpot> bollUpperSpots;
  final List<FlSpot> bollMiddleSpots;
  final List<FlSpot> bollLowerSpots;
  final List<FlSpot> sarSpots;
  final Set<String> selectedIndicators;
  final int? selectedIndex;

  CandlestickPainter({
    required this.klines,
    required this.minPrice,
    required this.maxPrice,
    required this.ma7Spots,
    required this.ma14Spots,
    required this.ma28Spots,
    this.ema12Spots = const [],
    this.ema26Spots = const [],
    this.bollUpperSpots = const [],
    this.bollMiddleSpots = const [],
    this.bollLowerSpots = const [],
    this.sarSpots = const [],
    this.selectedIndicators = const {},
    this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (klines.isEmpty) return;

    final chartHeight = size.height - 30;
    final chartWidth = size.width - 40;
    final priceRange = maxPrice - minPrice;
    final candleWidth = chartWidth / klines.length * 1;
    final spacing = chartWidth / klines.length;

    // Ограничиваем область рисования границами графика
    canvas.clipRect(Rect.fromLTWH(0, 0, chartWidth, chartHeight));

    // Рисуем сетку
    final gridPaint = Paint()
      ..color = AppTheme.borderColor.withValues(alpha: 0.3)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (int i = 0; i <= 4; i++) {
      final y = chartHeight * i / 4;
      canvas.drawLine(
        Offset(0, y),
        Offset(chartWidth, y),
        gridPaint,
      );
    }

    // Рисуем индикаторы в зависимости от выбора
    if (selectedIndicators.contains('MA')) {
      if (ma7Spots.isNotEmpty) {
        _drawMALine(canvas, ma7Spots, Colors.yellow, chartWidth, chartHeight);
      }
      if (ma14Spots.isNotEmpty) {
        _drawMALine(
            canvas, ma14Spots, Colors.lightBlue, chartWidth, chartHeight);
      }
      if (ma28Spots.isNotEmpty) {
        _drawMALine(canvas, ma28Spots, Colors.purple, chartWidth, chartHeight);
      }
    }

    if (selectedIndicators.contains('EMA')) {
      if (ema12Spots.isNotEmpty) {
        _drawMALine(canvas, ema12Spots, Colors.orange, chartWidth, chartHeight);
      }
      if (ema26Spots.isNotEmpty) {
        _drawMALine(canvas, ema26Spots, Colors.cyan, chartWidth, chartHeight);
      }
    }

    if (selectedIndicators.contains('BOLL')) {
      if (bollUpperSpots.isNotEmpty) {
        _drawMALine(canvas, bollUpperSpots, Colors.blue.withValues(alpha: 0.6),
            chartWidth, chartHeight);
      }
      if (bollMiddleSpots.isNotEmpty) {
        _drawMALine(
            canvas, bollMiddleSpots, Colors.blue, chartWidth, chartHeight);
      }
      if (bollLowerSpots.isNotEmpty) {
        _drawMALine(canvas, bollLowerSpots, Colors.blue.withValues(alpha: 0.6),
            chartWidth, chartHeight);
      }
    }

    if (selectedIndicators.contains('SAR')) {
      _drawSARPoints(canvas, sarSpots, chartWidth, chartHeight);
    }

    // Рисуем свечи
    for (int i = 0; i < klines.length; i++) {
      final kline = klines[i];
      final open = kline['open'] as double;
      final high = kline['high'] as double;
      final low = kline['low'] as double;
      final close = kline['close'] as double;

      final x = (i * spacing + spacing / 2).clamp(0.0, chartWidth);
      final isUp = close >= open;

      final openY =
          (chartHeight - ((open - minPrice) / priceRange * chartHeight))
              .clamp(0.0, chartHeight);
      final closeY =
          (chartHeight - ((close - minPrice) / priceRange * chartHeight))
              .clamp(0.0, chartHeight);
      final highY =
          (chartHeight - ((high - minPrice) / priceRange * chartHeight))
              .clamp(0.0, chartHeight);
      final lowY = (chartHeight - ((low - minPrice) / priceRange * chartHeight))
          .clamp(0.0, chartHeight);

      final color = isUp ? AppTheme.primaryGreen : AppTheme.primaryRed;
      final wickPaint = Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      final bodyPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      // Рисуем фитиль
      canvas.drawLine(
        Offset(x, highY),
        Offset(x, lowY),
        wickPaint,
      );

      // Рисуем тело свечи
      final bodyTop = openY < closeY ? openY : closeY;
      final bodyBottom = openY > closeY ? openY : closeY;
      final bodyHeight = (bodyBottom - bodyTop).abs();

      if (bodyHeight > 0.5) {
        canvas.drawRect(
          Rect.fromLTWH(
            x - candleWidth / 2,
            bodyTop,
            candleWidth,
            bodyHeight,
          ),
          bodyPaint,
        );
      } else {
        canvas.drawLine(
          Offset(x - candleWidth / 2, openY),
          Offset(x + candleWidth / 2, openY),
          wickPaint..strokeWidth = 2,
        );
      }
    }
  }

  void _drawMALine(Canvas canvas, List<FlSpot> spots, Color color, double width,
      double height) {
    if (spots.isEmpty) return;

    final priceRange = maxPrice - minPrice;
    final path = Path();
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final spacing = width / klines.length;
    bool isFirst = true;

    for (final spot in spots) {
      final x = spot.x * spacing + spacing / 2;
      // Ограничиваем координаты в пределах графика
      final clampedX = x.clamp(0.0, width);
      final y = height - ((spot.y - minPrice) / priceRange * height);
      // Ограничиваем координату Y в пределах графика
      final clampedY = y.clamp(0.0, height);

      if (isFirst) {
        path.moveTo(clampedX, clampedY);
        isFirst = false;
      } else {
        path.lineTo(clampedX, clampedY);
      }
    }

    canvas.drawPath(path, paint);
  }

  void _drawSARPoints(
      Canvas canvas, List<FlSpot> spots, double width, double height) {
    if (spots.isEmpty) return;

    final priceRange = maxPrice - minPrice;
    final spacing = width / klines.length;
    final pointPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    for (final spot in spots) {
      final x = spot.x * spacing + spacing / 2;
      final y = height - ((spot.y - minPrice) / priceRange * height);

      // Ограничиваем координаты в пределах графика
      final clampedX = x.clamp(0.0, width);
      final clampedY = y.clamp(0.0, height);

      // Рисуем точку SAR только если она в пределах графика
      if (clampedX >= 0 &&
          clampedX <= width &&
          clampedY >= 0 &&
          clampedY <= height) {
        canvas.drawCircle(Offset(clampedX, clampedY), 2, pointPaint);
      }
    }
  }

  @override
  bool shouldRepaint(CandlestickPainter oldDelegate) {
    // Всегда перерисовываем при изменении данных для реального времени
    if (oldDelegate.klines.length != klines.length) return true;
    if (oldDelegate.selectedIndicators != selectedIndicators) return true;
    if ((oldDelegate.minPrice - minPrice).abs() > 0.01 ||
        (oldDelegate.maxPrice - maxPrice).abs() > 0.01) return true;

    // Проверяем, изменилась ли последняя свеча (для плавного обновления)
    if (klines.isNotEmpty && oldDelegate.klines.isNotEmpty) {
      final lastOld = oldDelegate.klines.last;
      final lastNew = klines.last;

      // Сравниваем все поля свечи с учетом погрешности для double
      final oldClose = lastOld['close'] as double;
      final newClose = lastNew['close'] as double;
      final oldHigh = lastOld['high'] as double;
      final newHigh = lastNew['high'] as double;
      final oldLow = lastOld['low'] as double;
      final newLow = lastNew['low'] as double;
      final oldOpen = lastOld['open'] as double;
      final newOpen = lastNew['open'] as double;

      if (lastOld['timestamp'] != lastNew['timestamp'] ||
          (oldClose - newClose).abs() > 0.0001 ||
          (oldHigh - newHigh).abs() > 0.0001 ||
          (oldLow - newLow).abs() > 0.0001 ||
          (oldOpen - newOpen).abs() > 0.0001) {
        return true;
      }
    }

    // Проверяем изменения в индикаторах
    if (oldDelegate.ma7Spots.length != ma7Spots.length ||
        oldDelegate.ma14Spots.length != ma14Spots.length ||
        oldDelegate.ma28Spots.length != ma28Spots.length) {
      return true;
    }

    // Проверяем изменения в последних точках индикаторов
    if (ma7Spots.isNotEmpty && oldDelegate.ma7Spots.isNotEmpty) {
      final lastMa7Old = oldDelegate.ma7Spots.last;
      final lastMa7New = ma7Spots.last;
      if ((lastMa7Old.y - lastMa7New.y).abs() > 0.0001) return true;
    }

    return false;
  }
}

// Custom painter for document icon with curled corner
class DocumentIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final fillPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    // Draw main document rectangle
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width * 0.7, size.height * 0.8),
      const Radius.circular(2),
    );
    canvas.drawRRect(rect, fillPaint);
    canvas.drawRRect(rect, paint);

    // Draw horizontal lines inside document
    final lineY1 = size.height * 0.25;
    final lineY2 = size.height * 0.45;
    canvas.drawLine(
      Offset(size.width * 0.15, lineY1),
      Offset(size.width * 0.55, lineY1),
      paint..strokeWidth = 1.5,
    );
    canvas.drawLine(
      Offset(size.width * 0.15, lineY2),
      Offset(size.width * 0.55, lineY2),
      paint..strokeWidth = 1.5,
    );

    // Draw curled corner (top right)
    final cornerX = size.width * 0.7;
    final cornerY = 0.0;
    final curlRadius = size.width * 0.15;

    final curlPath = Path()
      ..moveTo(cornerX - curlRadius, cornerY)
      ..quadraticBezierTo(
        cornerX - curlRadius * 0.5,
        cornerY + curlRadius * 0.3,
        cornerX,
        cornerY + curlRadius * 0.6,
      );

    canvas.drawPath(curlPath, paint);

    // Draw shadow/glow effect
    final glowPaint = Paint()
      ..color = const Color(0xFF8B4513).withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    canvas.drawPath(curlPath, glowPaint);
  }

  @override
  bool shouldRepaint(DocumentIconPainter oldDelegate) => false;
}
