import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/mock_portfolio_service.dart';
import '../services/crypto_api_service.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedPeriod = '7d';
  String _selectedCurrency = 'USD';
  bool _showCurrencyInPercent = false; // Показывать в процентах или USD
  String _selectedClosedTab = 'Закрытые ордера';
  String _selectedOrderTypeTab = 'Бессрочные USDT';

  // Данные о монетах в портфеле
  List<Map<String, dynamic>> _coinsList = [];
  bool _isLoadingCoins = false;

  // Состояние чекбоксов для графика стоимости ордеров
  bool _showTotalOrderValue = true;
  bool _showPurchaseValue = false;
  bool _showSaleValue = false;

  // Фильтрация по торговым парам
  List<String> _availableTradingPairs = [
    'BTC/USDT',
    'ETH/USDT',
    'BNB/USDT',
    'SOL/USDT',
    'XRP/USDT'
  ];
  List<String> _selectedTradingPairs = [];
  bool _showTradingPairsDropdown = false;

  // Пользовательский период
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  // Обновление данных
  bool _isRefreshing = false;
  DateTime? _lastUpdateTime;

  // Кэш для данных графиков (чтобы не пересчитывать при каждом build)
  Map<String, List<FlSpot>>? _cachedChartData;
  String? _cachedPeriod;

  // Вычисление дат периода
  Map<String, String> _getPeriodDates() {
    final now = DateTime.now();
    DateTime startDate;
    DateTime endDate = now;

    if (_selectedPeriod == 'Пользовательский' &&
        _customStartDate != null &&
        _customEndDate != null) {
      startDate = _customStartDate!;
      endDate = _customEndDate!;
    } else {
      switch (_selectedPeriod) {
        case '7d':
          startDate = now.subtract(const Duration(days: 7));
          break;
        case '30d':
          startDate = now.subtract(const Duration(days: 30));
          break;
        case '60d':
          startDate = now.subtract(const Duration(days: 60));
          break;
        case '90d':
          startDate = now.subtract(const Duration(days: 90));
          break;
        case '180d':
          startDate = now.subtract(const Duration(days: 180));
          break;
        default:
          startDate = now.subtract(const Duration(days: 7));
      }
    }

    return {
      'start':
          '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}',
      'end':
          '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}',
    };
  }

  // Генерация данных для графика на основе периода
  List<FlSpot> _generateChartData(String period) {
    // Всегда генерируем свежие данные (убрали кэш для обновления графиков)
    List<FlSpot> spots;

    // Используем моковые данные, если включен флаг
    if (MockPortfolioService.useMockData) {
      spots = MockPortfolioService.getPortfolioHistory(period);
    } else {
      // Реальные данные (пока нули, можно заменить на API вызов)
      int days;
      switch (period) {
        case '7d':
          days = 7;
          break;
        case '30d':
          days = 30;
          break;
        case '60d':
          days = 60;
          break;
        case '90d':
          days = 90;
          break;
        case '180d':
          days = 180;
          break;
        default:
          days = 7;
      }

      spots = List.generate(days + 1, (index) {
        return FlSpot(index.toDouble(), 0.0);
      });
    }

    // Не кэшируем данные, чтобы всегда получать свежие графики с циклами
    return spots;
  }

  // Генерация данных для P&L графика
  List<FlSpot> _generatePnlChartData(String period, {bool isFutures = false}) {
    if (MockPortfolioService.useMockData) {
      // Для бессрочных и фьючерсов используем те же значения P&L
      return MockPortfolioService.getPnlHistory(period);
    }
    // Реальные данные
    final days = MockPortfolioService.getDaysForPeriod(period);
    return List.generate(days + 1, (index) => FlSpot(index.toDouble(), 0.0));
  }

  // Генерация данных для суточного P&L
  List<FlSpot> _generateDailyPnlChartData(String period) {
    if (MockPortfolioService.useMockData) {
      // Используем кумулятивный суточный P&L для графика (накопленная сумма)
      return MockPortfolioService.getCumulativeDailyPnlHistory(period);
    }
    // Реальные данные
    final days = MockPortfolioService.getDaysForPeriod(period);
    return List.generate(days + 1, (index) => FlSpot(index.toDouble(), 0.0));
  }

  // Генерация данных для стоимости ордеров
  Map<String, List<FlSpot>> _generateOrderValueData(String period,
      {bool isFutures = false}) {
    if (MockPortfolioService.useMockData) {
      return MockPortfolioService.getOrderValueHistory(period,
          isFutures: isFutures);
    }
    // Реальные данные
    final days = MockPortfolioService.getDaysForPeriod(period);
    return {
      'total':
          List.generate(days + 1, (index) => FlSpot(index.toDouble(), 0.0)),
      'purchase':
          List.generate(days + 1, (index) => FlSpot(index.toDouble(), 0.0)),
      'sale': List.generate(days + 1, (index) => FlSpot(index.toDouble(), 0.0)),
    };
  }

  // Вспомогательные методы для расчета minY и maxY
  double _calculateMinY(List<FlSpot> spots) {
    if (spots.isEmpty) return 0.0;
    final min = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    return min - (min.abs() * 0.1); // Добавляем 10% отступа снизу
  }

  double _calculateMaxY(List<FlSpot> spots) {
    if (spots.isEmpty) return 100.0;
    final max = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    return max + (max.abs() * 0.1); // Добавляем 10% отступа сверху
  }

  double _calculateMinYForOrderValue(String period) {
    final data = _generateOrderValueData(period);
    final allSpots = <FlSpot>[];
    if (data['total'] != null) allSpots.addAll(data['total']!);
    if (data['purchase'] != null) allSpots.addAll(data['purchase']!);
    if (data['sale'] != null) allSpots.addAll(data['sale']!);
    if (allSpots.isEmpty) return 0.0;
    final min = allSpots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    return (min - (min.abs() * 0.1)).clamp(0.0, double.infinity);
  }

  double _calculateMaxYForOrderValue(String period) {
    final data = _generateOrderValueData(period);
    final allSpots = <FlSpot>[];
    if (data['total'] != null) allSpots.addAll(data['total']!);
    if (data['purchase'] != null) allSpots.addAll(data['purchase']!);
    if (data['sale'] != null) allSpots.addAll(data['sale']!);
    if (allSpots.isEmpty) return 5000.0;
    final max = allSpots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    return max + (max.abs() * 0.1);
  }

  // Вспомогательные методы для получения моковых значений
  String _getHistoricalPnl() {
    if (!MockPortfolioService.useMockData) return '0.00';
    final pnlData = MockPortfolioService.getPnlHistory(_selectedPeriod);
    if (pnlData.isEmpty) return '0.00';
    final lastPnl = pnlData.last.y;
    return '${lastPnl >= 0 ? '+' : ''}${lastPnl.toStringAsFixed(2)}';
  }

  double _getHistoricalPnlValue() {
    if (!MockPortfolioService.useMockData) return 0.0;
    final pnlData = MockPortfolioService.getPnlHistory(_selectedPeriod);
    if (pnlData.isEmpty) return 0.0;
    return pnlData.last.y;
  }

  String _getHistoricalPnlPercent() {
    if (!MockPortfolioService.useMockData) return '0.00%';
    final pnlValue = _getHistoricalPnlValue();
    // Используем текущий баланс минус P&L для расчета начального баланса
    final currentBalance = MockPortfolioService.totalUsd;
    final initialBalance = currentBalance - pnlValue;
    if (initialBalance <= 0 ||
        initialBalance.isNaN ||
        initialBalance.isInfinite) {
      return '0.00%';
    }
    final percent = (pnlValue / initialBalance) * 100;
    if (percent.isNaN || percent.isInfinite) {
      return '0.00%';
    }
    return '${percent >= 0 ? '+' : ''}${percent.toStringAsFixed(2)}%';
  }

  String _getPnlTodayPercent() {
    if (!MockPortfolioService.useMockData) return '0.00%';
    final pnlToday = MockPortfolioService.pnlToday;
    final totalUsd = MockPortfolioService.totalUsd;
    if (totalUsd == 0 || totalUsd.isNaN || totalUsd.isInfinite) {
      return '0.00%';
    }
    final percent = (pnlToday / totalUsd) * 100;
    if (percent.isNaN || percent.isInfinite) {
      return '0.00%';
    }
    return '${percent >= 0 ? '+' : ''}${percent.toStringAsFixed(2)}%';
  }

  String _getDailyPnlValue() {
    if (!MockPortfolioService.useMockData) return '0.00';
    // Суточное значение = Общий P&L за период / количество дней
    final totalPnl = _getHistoricalPnlValue();
    final days = MockPortfolioService.getDaysForPeriod(_selectedPeriod);
    if (days == 0) return '0.00';
    final dailyPnl = totalPnl / days;
    return '${dailyPnl >= 0 ? '+' : ''}${dailyPnl.toStringAsFixed(2)}';
  }

  // Получение общей стоимости исполненных ордеров
  String _getTotalOrderValue() {
    if (!MockPortfolioService.useMockData) return '0.00';
    final orderData =
        MockPortfolioService.getOrderValueHistory(_selectedPeriod);
    if (orderData['total'] == null || orderData['total']!.isEmpty)
      return '0.00';
    final total = orderData['total']!.map((s) => s.y).reduce((a, b) => a + b);
    return total.toStringAsFixed(2);
  }

  // Получение торгового объема
  String _getTradingVolume() {
    if (!MockPortfolioService.useMockData) return '0.00';
    final orderData =
        MockPortfolioService.getOrderValueHistory(_selectedPeriod);
    if (orderData['total'] == null || orderData['total']!.isEmpty)
      return '0.00';
    final total = orderData['total']!.map((s) => s.y).reduce((a, b) => a + b);
    return total.toStringAsFixed(2);
  }

  // Получение стоимости покупок
  String _getPurchaseValue({bool isFutures = false}) {
    if (!MockPortfolioService.useMockData) return '+0.00 USD';
    final orderData = MockPortfolioService.getOrderValueHistory(_selectedPeriod,
        isFutures: isFutures);
    if (orderData['purchase'] == null || orderData['purchase']!.isEmpty)
      return '+0.00 USD';
    final total =
        orderData['purchase']!.map((s) => s.y).reduce((a, b) => a + b);
    return '+${total.toStringAsFixed(2)} USD';
  }

  // Получение стоимости продаж
  String _getSaleValue({bool isFutures = false}) {
    if (!MockPortfolioService.useMockData) return '+0.00 USD';
    final orderData = MockPortfolioService.getOrderValueHistory(_selectedPeriod,
        isFutures: isFutures);
    if (orderData['sale'] == null || orderData['sale']!.isEmpty)
      return '+0.00 USD';
    final total = orderData['sale']!.map((s) => s.y).reduce((a, b) => a + b);
    return '+${total.toStringAsFixed(2)} USD';
  }

  // Получение ROI
  String _getROI() {
    if (!MockPortfolioService.useMockData) return '+0.00%';
    final pnlValue = _getHistoricalPnlValue();
    final percent = (pnlValue / MockPortfolioService.initialBalance) * 100;
    return '${percent >= 0 ? '+' : ''}${percent.toStringAsFixed(2)}%';
  }

  // Получение процента успешных сделок
  String _getWinRate() {
    if (!MockPortfolioService.useMockData) return '0.00%';
    // Моковое значение - 68.5%
    return '68.50%';
  }

  // Получение общего количества позиций
  String _getTotalPositions() {
    if (!MockPortfolioService.useMockData) return '0';
    // Моковое значение
    return '127';
  }

  // Получение P&L для состязания
  String _getContestPnl() {
    if (!MockPortfolioService.useMockData) return '+0.00';
    final pnlValue = _getHistoricalPnlValue();
    return '${pnlValue >= 0 ? '+' : ''}${pnlValue.toStringAsFixed(2)}';
  }

  // Получение дат для оси X графика
  List<DateTime> _getChartDates(String period) {
    final now = DateTime.now();
    int days;

    switch (period) {
      case '7d':
        days = 7;
        break;
      case '30d':
        days = 30;
        break;
      case '60d':
        days = 60;
        break;
      case '90d':
        days = 90;
        break;
      case '180d':
        days = 180;
        break;
      default:
        days = 7;
    }

    final dates = <DateTime>[];
    for (int i = 0; i <= days; i++) {
      dates.add(now.subtract(Duration(days: days - i)));
    }

    return dates;
  }

  // Форматирование даты для отображения на графике
  String _formatChartDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // Очистка кэша при смене периода
  void _onPeriodChanged(String period) {
    if (_selectedPeriod != period) {
      setState(() {
        _selectedPeriod = period;
        // Очищаем кэш для пересчета данных
        _cachedChartData = null;
        _cachedPeriod = null;

        // Если выбран пользовательский период, открываем DatePicker
        if (period == 'Пользовательский') {
          _selectCustomPeriod();
        }
      });
    }
  }

  // Выбор пользовательского периода
  Future<void> _selectCustomPeriod() async {
    final DateTime now = DateTime.now();
    final DateTime? startDate = await showDatePicker(
      context: context,
      initialDate: _customStartDate ?? now.subtract(const Duration(days: 7)),
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppTheme.primaryGreen,
              onPrimary: Colors.black,
              surface: AppTheme.backgroundCard,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (startDate != null) {
      final DateTime? endDate = await showDatePicker(
        context: context,
        initialDate: _customEndDate ?? now,
        firstDate: startDate,
        lastDate: now,
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.dark(
                primary: AppTheme.primaryGreen,
                onPrimary: Colors.black,
                surface: AppTheme.backgroundCard,
                onSurface: AppTheme.textPrimary,
              ),
            ),
            child: child!,
          );
        },
      );

      if (endDate != null) {
        setState(() {
          _customStartDate = startDate;
          _customEndDate = endDate;
          _cachedChartData = null;
          _cachedPeriod = null;
        });
      }
    }
  }

  // Обновление данных
  Future<void> _refreshData() async {
    setState(() {
      _isRefreshing = true;
    });

    // Имитация загрузки данных
    await Future.delayed(const Duration(seconds: 1));

    setState(() {
      _isRefreshing = false;
      _lastUpdateTime = DateTime.now();
      _cachedChartData = null;
      _cachedPeriod = null;
    });
  }

  // Форматирование времени последнего обновления
  String _formatLastUpdateTime() {
    if (_lastUpdateTime == null) {
      final now = DateTime.now();
      return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} UTC';
    }
    return '${_lastUpdateTime!.year}-${_lastUpdateTime!.month.toString().padLeft(2, '0')}-${_lastUpdateTime!.day.toString().padLeft(2, '0')} ${_lastUpdateTime!.hour.toString().padLeft(2, '0')}:${_lastUpdateTime!.minute.toString().padLeft(2, '0')} UTC';
  }

  // Создание интерактивных настроек для графиков
  LineTouchData _buildLineTouchData() {
    return LineTouchData(
      touchTooltipData: LineTouchTooltipData(
        tooltipRoundedRadius: 8,
        tooltipPadding: const EdgeInsets.all(8),
        tooltipBgColor: AppTheme.backgroundCard,
        tooltipBorder: BorderSide(color: AppTheme.borderColor, width: 1),
        getTooltipItems: (List<LineBarSpot> touchedSpots) {
          return touchedSpots.map((LineBarSpot touchedSpot) {
            final dates = _getChartDates(_selectedPeriod);
            final index = touchedSpot.x.toInt();
            if (index < 0 || index >= dates.length) {
              return null;
            }
            return LineTooltipItem(
              '${_formatChartDate(dates[index])}\n${touchedSpot.y.toStringAsFixed(2)}',
              TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            );
          }).toList();
        },
      ),
      handleBuiltInTouches: true,
      getTouchedSpotIndicator:
          (LineChartBarData barData, List<int> indicators) {
        return indicators.map((int index) {
          return TouchedSpotIndicatorData(
            FlLine(color: AppTheme.primaryGreen, strokeWidth: 2),
            FlDotData(
              getDotPainter: (spot, percent, barData, index) =>
                  FlDotCirclePainter(
                radius: 4,
                color: AppTheme.primaryGreen,
                strokeWidth: 2,
                strokeColor: AppTheme.backgroundCard,
              ),
            ),
          );
        }).toList();
      },
    );
  }

  final List<String> _tabs = [
    'Активы',
    'Спот',
    'Бессрочные и фьючерсы',
    'Опцион',
  ];

  final List<String> _periods = [
    '7d',
    '30d',
    '60d',
    '90d',
    '180d',
    'Пользовательский',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _selectedTradingPairs =
        List.from(_availableTradingPairs); // По умолчанию выбраны все пары
    _lastUpdateTime = DateTime.now();
    _loadCoinsData();
  }

  // Загрузка данных о монетах
  Future<void> _loadCoinsData() async {
    setState(() {
      _isLoadingCoins = true;
    });

    try {
      if (MockPortfolioService.useMockData) {
        // Принудительно обновляем цены из API перед получением списка монет
        await MockPortfolioService.refreshPrices();

        // Моковые данные
        await Future.delayed(const Duration(milliseconds: 300));
        _coinsList = MockPortfolioService.getCoinsList();
      } else {
        // Реальные данные из API
        final balanceData = await CryptoApiService.getTotalBalance();
        _coinsList = (balanceData['coins'] as List<dynamic>?)
                ?.map((coin) => coin as Map<String, dynamic>)
                .toList() ??
            [];
      }
    } catch (e) {
      _coinsList = [];
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingCoins = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 0, 0, 0),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
          padding: EdgeInsets.zero,
        ),
        leadingWidth: 48,
        title: const Center(child: Text('Анализ')),
        centerTitle: true,
        actions: [
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _refreshData,
            padding: EdgeInsets.zero,
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {},
            padding: EdgeInsets.zero,
          ),
        ],
      ),
      body: Column(
        children: [
          // Tabs
          Container(
            color: AppTheme.backgroundDark,
            padding: const EdgeInsets.only(left: 16),
            child: TabBar(
              controller: _tabController,
              tabs: _tabs
                  .map((tab) => Tab(
                        child: Text(
                          tab,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ))
                  .toList(),
              labelColor: AppTheme.textPrimary,
              unselectedLabelColor: AppTheme.textSecondary,
              indicatorColor: AppTheme.textPrimary,
              indicatorSize: TabBarIndicatorSize.tab,
              isScrollable: false,
              labelStyle: const TextStyle(fontSize: 11),
              unselectedLabelStyle: const TextStyle(fontSize: 11),
              labelPadding: const EdgeInsets.symmetric(horizontal: 8),
              dividerColor: Colors.transparent,
            ),
          ),
          // Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAssetsTab(),
                _buildSpotTab(),
                _buildFuturesTab(),
                _buildOptionsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Обзор активов
          _buildSectionHeader('Обзор активов', showDropdown: true),
          const SizedBox(height: 12),
          // P&L за сегодня и Исторический P&L в ряд
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'P&L за сегодня (USD)',
                  MockPortfolioService.useMockData
                      ? '${MockPortfolioService.pnlToday >= 0 ? '+' : ''}${MockPortfolioService.pnlToday.toStringAsFixed(2)}'
                      : '0.00',
                  MockPortfolioService.useMockData
                      ? _getPnlTodayPercent()
                      : '0%',
                  isPositive: MockPortfolioService.useMockData
                      ? MockPortfolioService.pnlToday >= 0
                      : true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  'Исторический P&L (USD)',
                  MockPortfolioService.useMockData
                      ? _getHistoricalPnl()
                      : '0.00',
                  MockPortfolioService.useMockData
                      ? _getHistoricalPnlPercent()
                      : '-29.11%',
                  isPositive: MockPortfolioService.useMockData
                      ? _getHistoricalPnlValue() >= 0
                      : false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Последнее обновление: ${_formatLastUpdateTime()}',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 10,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.refresh,
                color: AppTheme.textSecondary,
                size: 16,
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Период
          _buildPeriodSelector(),
          const SizedBox(height: 16),
          Text(
            'Последнее обновление: ${_formatLastUpdateTime()}',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 24),
          // Суммарный P&L
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Суммарный P&L (USD)',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Row(
                children: [
                  _buildCurrencyToggle('\$', true),
                  const SizedBox(width: 8),
                  _buildCurrencyToggle('%', false),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '2025-11-25',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            MockPortfolioService.useMockData ? _getHistoricalPnl() : '0.00',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          // График суммарного P&L
          _buildPnlChart(),
          const SizedBox(height: 24),
          // Суточный P&L
          Text(
            'Суточный P&L (USD)',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '2025-11-25',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _getDailyPnlValue(),
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.bar_chart, color: AppTheme.textSecondary, size: 20),
              const SizedBox(width: 8),
              Icon(Icons.list, color: AppTheme.textSecondary, size: 20),
            ],
          ),
          const SizedBox(height: 16),
          // График суточного P&L
          _buildDailyPnlChart(),
          const SizedBox(height: 24),
          // Тренд суммарных активов
          Text(
            'Тренд суммарных активов (USD)',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '2025-11-23',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            MockPortfolioService.useMockData
                ? MockPortfolioService.totalUsd.toStringAsFixed(2)
                : '0.00',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          // График тренда активов
          _buildAssetsTrendChart(),
          const SizedBox(height: 24),
          // Распределение активов
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Распределение активов',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Row(
                children: [
                  _buildCurrencyToggle('\$', !_showCurrencyInPercent),
                  const SizedBox(width: 8),
                  _buildCurrencyToggle('%', _showCurrencyInPercent),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Последнее обновление: ${_formatLastUpdateTime()}',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 16),
          // Список монет с распределением
          if (_isLoadingCoins)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_coinsList.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  'Нет активов',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ),
            )
          else
            _buildCoinsList(),
          const SizedBox(height: 24),
          // Всего активов
          Text(
            'Всего активов (USD)',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            MockPortfolioService.useMockData
                ? MockPortfolioService.totalUsd.toStringAsFixed(2)
                : _coinsList
                    .fold<double>(
                      0.0,
                      (sum, coin) =>
                          sum + (coin['usdValue'] as num? ?? 0).toDouble(),
                    )
                    .toStringAsFixed(2),
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 32),
          // Дисклеймеры
          Text(
            'P&L за сегодня и разбивка активов указаны в режиме реального времени. Другие данные включают значения только до предыдущего дня.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Из-за сложностей в расчетах данных возможны задержки и небольшие несоответствия. Все данные представлены исключительно в справочных целях.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpotTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Торговые пары', showDropdown: true),
          if (_showTradingPairsDropdown) ...[
            const SizedBox(height: 12),
            _buildTradingPairsSelector(),
          ],
          const SizedBox(height: 16),
          // Общий P&L и стоимость ордеров
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.backgroundCard,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Общий P&L (USD)',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        MockPortfolioService.useMockData
                            ? _getHistoricalPnl()
                            : '+0.00',
                        style: TextStyle(
                          color: AppTheme.primaryGreen,
                          fontSize: 14,
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
                        'Общая стоимость исполненных ордеров (USD)',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getTotalOrderValue(),
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Данные на 2025-11-25 23:59:59 UTC',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 24),
          _buildPeriodSelector(),
          const SizedBox(height: 12),
          // Даты периода
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _getPeriodDates()['start'] ?? '2025-11-18',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 10,
                ),
              ),
              Text(
                _getPeriodDates()['end'] ?? '2025-11-25',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // График тренда
          Text(
            'График тренда стоимости исполненных ордеров',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          // Чекбоксы в ряд
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                flex: 3,
                child: _buildCheckboxRow(
                  'Общая стоимость исполненных ордеров',
                  _showTotalOrderValue,
                  onTap: () {
                    setState(() {
                      _showTotalOrderValue = !_showTotalOrderValue;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: 2,
                child: _buildCheckboxRow(
                  'Стоимость покупки',
                  _showPurchaseValue,
                  onTap: () {
                    setState(() {
                      _showPurchaseValue = !_showPurchaseValue;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: 2,
                child: _buildCheckboxRow(
                  'Стоимость продажи',
                  _showSaleValue,
                  onTap: () {
                    setState(() {
                      _showSaleValue = !_showSaleValue;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildOrderValueChart(),
          const SizedBox(height: 16),
          // Легенда графика
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Общая стоимость исполненных ордеров',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Стоимость покупки',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryRed,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Стоимость продажи',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          // P&L рейтинг
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'P&L рейтинг',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'P&L (USD)',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Тикер',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          _buildEmptyState('Нет данных'),
          const SizedBox(height: 24),
          // Детали сделки
          Text(
            'Детали сделки',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Данные на 2025-11-25 23:59:59 UTC',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 16),
          _buildEmptyState('Нет данных'),
        ],
      ),
    );
  }

  Widget _buildFuturesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Все контракты', showDropdown: true),
          const SizedBox(height: 16),
          // Общий P&L и торговый объем
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.backgroundCard,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Общий P&L (USD)',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        MockPortfolioService.useMockData
                            ? _getHistoricalPnl()
                            : '--',
                        style: TextStyle(
                          color: MockPortfolioService.useMockData
                              ? (_getHistoricalPnlValue() >= 0
                                  ? AppTheme.primaryGreen
                                  : AppTheme.primaryRed)
                              : AppTheme.textSecondary,
                          fontSize: 18,
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
                        'Торговый объем (USD)',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getTradingVolume(),
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Данные на 2025-11-25 23:59:59 UTC',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 24),
          _buildPeriodSelector(),
          const SizedBox(height: 24),
          Text(
            'Данные на 2025-11-25 23:59:59 UTC',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          // График P&L
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'График P&L',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(Icons.open_in_new, color: AppTheme.textSecondary, size: 20),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Общий P&L',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 24),
              Text(
                'Суточный P&L',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '2025-11-25 (UTC)',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_getHistoricalPnl()} USD',
                    style: TextStyle(
                      color: AppTheme.primaryGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_getDailyPnlValue()} USD',
                    style: TextStyle(
                      color: AppTheme.primaryGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildPnlChart(isFutures: true),
          const SizedBox(height: 24),
          // Календарь P&L
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Календарь P&L',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () {},
                    iconSize: 20,
                    color: AppTheme.textSecondary,
                  ),
                  Text(
                    '2025-11',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 12,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () {},
                    iconSize: 20,
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildPnlMetrics(),
          const SizedBox(height: 16),
          _buildCalendar(),
          const SizedBox(height: 24),
          // P&L рейтинг
          _buildPnLRatingSection(),
          const SizedBox(height: 24),
          // Закрытые ордера/позиции
          _buildClosedOrdersPositionsSection(),
          const SizedBox(height: 24),
          // Информация об ордере
          _buildOrderInfoSection(),
        ],
      ),
    );
  }

  Widget _buildPnLRatingSection() {
    // Моковые данные для P&L рейтинга
    final pnlData = [
      {'contract': 'SOLUSDT', 'pnl': 359.69},
      {'contract': 'LTCUSDT', 'pnl': 282.41},
    ];

    // Находим максимальный P&L для нормализации полосок
    final maxPnl =
        pnlData.map((e) => e['pnl'] as double).reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'P&L рейтинг',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'P&L (USD)',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Контракты',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        // Список контрактов с P&L
        ...pnlData.map((data) {
          final contract = data['contract'] as String;
          final pnl = data['pnl'] as double;
          final percent = maxPnl > 0 ? (pnl / maxPnl * 100) : 0.0;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      contract,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: AppTheme.primaryGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Прогресс-бар для визуализации P&L
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: percent / 100,
                    minHeight: 4,
                    backgroundColor: AppTheme.backgroundDark,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppTheme.primaryGreen,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildClosedOrdersPositionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Табы для закрытых ордеров/позиций
        Row(
          children: [
            _buildTabButton(
              'Закрытые ордера',
              _selectedClosedTab == 'Закрытые ордера',
              onTap: () {
                setState(() {
                  _selectedClosedTab = 'Закрытые ордера';
                });
              },
            ),
            const SizedBox(width: 16),
            _buildTabButton(
              'Закрытые позиции',
              _selectedClosedTab == 'Закрытые позиции',
              onTap: () {
                setState(() {
                  _selectedClosedTab = 'Закрытые позиции';
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Данные на 2025-11-27 23:59:59 UTC',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 16),
        // Метрики с моковыми данными
        _buildMetricRow('Общее количество закрытых ордеров', '12'),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Процент успешных сделок',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
            ),
            Row(
              children: [
                Text(
                  '75%',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.open_in_new,
                  color: AppTheme.textSecondary,
                  size: 14,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildMetricRow(
          'P&L закрытых лонг-ордеров (USD)',
          '+642.10',
          isPositive: true,
        ),
        const SizedBox(height: 12),
        _buildMetricRow(
          'P&L закрытых шорт-ордеров (USD)',
          '+0.00',
          isPositive: true,
        ),
      ],
    );
  }

  Widget _buildOrderInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Информация об ордере',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Flexible(
              child: Text(
                'Данные обновляются в реальном времени. Последнее обновление: 2025-11-28 05:07:28.',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 10,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.refresh,
              color: AppTheme.textSecondary,
              size: 14,
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Табы для типов контрактов
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildTabButton(
                'Бессрочные USDT',
                _selectedOrderTypeTab == 'Бессрочные USDT',
                onTap: () {
                  setState(() {
                    _selectedOrderTypeTab = 'Бессрочные USDT';
                  });
                },
              ),
              const SizedBox(width: 8),
              _buildTabButton(
                'USDT фьючерсы',
                _selectedOrderTypeTab == 'USDT фьючерсы',
                onTap: () {
                  setState(() {
                    _selectedOrderTypeTab = 'USDT фьючерсы';
                  });
                },
              ),
              const SizedBox(width: 8),
              _buildTabButton(
                'Бессрочные USDC',
                _selectedOrderTypeTab == 'Бессрочные USDC',
                onTap: () {
                  setState(() {
                    _selectedOrderTypeTab = 'Бессрочные USDC';
                  });
                },
              ),
              const SizedBox(width: 8),
              _buildTabButton(
                'USDC фьючерсы',
                _selectedOrderTypeTab == 'USDC фьючерсы',
                onTap: () {
                  setState(() {
                    _selectedOrderTypeTab = 'USDC фьючерсы';
                  });
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Детали закрытого ордера
        _buildClosedOrderDetails(),
      ],
    );
  }

  Widget _buildTabButton(String label, bool isSelected,
      {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyStateWithBlackBackground(String message) {
    return Container(
      color: AppTheme.backgroundDark,
      padding: const EdgeInsets.all(40),
      child: Column(
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
            message,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClosedOrderDetails() {
    // Моковые данные для закрытого ордера в зависимости от выбранного таба
    Map<String, dynamic> orderData;

    switch (_selectedOrderTypeTab) {
      case 'Бессрочные USDT':
        orderData = {
          'contract': 'SOLUSDT',
          'closedPnl': 2.8054,
          'quantity': 15.0,
          'entryPrice': 150.25,
          'exitPrice': 150.45,
          'openVolume': 2253.75,
          'closedVolume': 2256.75,
          'openCommission': 1.126875,
          'closeCommission': 1.128375,
          'fundingCommission': 0.025,
          'executionType': 'Торговля',
          'closeTime': '2025-11-18 23:29:10',
        };
        break;
      case 'USDT фьючерсы':
        orderData = {
          'contract': 'LTCUSDT',
          'closedPnl': 1.5234,
          'quantity': 27.21,
          'entryPrice': 80.15,
          'exitPrice': 80.25,
          'openVolume': 2180.88,
          'closedVolume': 2183.60,
          'openCommission': 1.09044,
          'closeCommission': 1.09180,
          'fundingCommission': 0.015,
          'executionType': 'Торговля',
          'closeTime': '2025-11-18 22:15:30',
        };
        break;
      case 'Бессрочные USDC':
        orderData = {
          'contract': 'LTCUSDC',
          'closedPnl': 0.8923,
          'quantity': 27.21,
          'entryPrice': 80.10,
          'exitPrice': 80.18,
          'openVolume': 2179.52,
          'closedVolume': 2181.70,
          'openCommission': 1.08976,
          'closeCommission': 1.09085,
          'fundingCommission': 0.012,
          'executionType': 'Торговля',
          'closeTime': '2025-11-18 21:45:15',
        };
        break;
      case 'USDC фьючерсы':
        orderData = {
          'contract': 'SOLUSDC',
          'closedPnl': 1.6542,
          'quantity': 15.0,
          'entryPrice': 150.20,
          'exitPrice': 150.35,
          'openVolume': 2253.0,
          'closedVolume': 2255.25,
          'openCommission': 1.1265,
          'closeCommission': 1.127625,
          'fundingCommission': 0.020,
          'executionType': 'Торговля',
          'closeTime': '2025-11-18 20:30:45',
        };
        break;
      default:
        orderData = {
          'contract': 'SOLUSDT',
          'closedPnl': 2.8054,
          'quantity': 15.0,
          'entryPrice': 150.25,
          'exitPrice': 150.45,
          'openVolume': 2253.75,
          'closedVolume': 2256.75,
          'openCommission': 1.126875,
          'closeCommission': 1.128375,
          'fundingCommission': 0.025,
          'executionType': 'Торговля',
          'closeTime': '2025-11-18 23:29:10',
        };
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundCard,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Название контракта и кнопки
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                orderData['contract'] as String,
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryRed.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Закрыть Long',
                      style: TextStyle(
                        color: AppTheme.primaryRed,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Успешные сделки',
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Дата и время закрытия
          Text(
            orderData['closeTime'] as String,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          // Закрытый P&L
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    'Закрытый P&L (USDT)',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.open_in_new,
                    color: AppTheme.textSecondary,
                    size: 12,
                  ),
                ],
              ),
              Text(
                orderData['closedPnl'].toString(),
                style: TextStyle(
                  color: AppTheme.primaryGreen,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Детали ордера
          _buildOrderDetailRow(
              'Кол-во ордера', orderData['quantity'].toString()),
          const SizedBox(height: 12),
          _buildOrderDetailRow(
              'Цена входа', orderData['entryPrice'].toString()),
          const SizedBox(height: 12),
          _buildOrderDetailRow(
              'Цена выхода', orderData['exitPrice'].toString()),
          const SizedBox(height: 12),
          _buildOrderDetailRow(
              'Объем открытых сделок', orderData['openVolume'].toString()),
          const SizedBox(height: 12),
          _buildOrderDetailRow(
              'Объем закрытых сделок', orderData['closedVolume'].toString()),
          const SizedBox(height: 12),
          _buildOrderDetailRow(
              'Комиссия за открытие', '${orderData['openCommission']} USDT'),
          const SizedBox(height: 12),
          _buildOrderDetailRow(
              'Комиссия за закрытие', '${orderData['closeCommission']} USDT'),
          const SizedBox(height: 12),
          _buildOrderDetailRow('Комиссия за финансирование',
              '${orderData['fundingCommission']} USDT'),
          const SizedBox(height: 12),
          _buildOrderDetailRow(
              'Тип исполнения', orderData['executionType'] as String),
        ],
      ),
    );
  }

  Widget _buildOrderDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildOptionsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'USDT',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, color: AppTheme.textSecondary),
              const SizedBox(width: 16),
              Text(
                'Все активы',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, color: AppTheme.textSecondary),
            ],
          ),
          const SizedBox(height: 16),
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
                  'Общий P&L (USD)',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  MockPortfolioService.useMockData
                      ? _getHistoricalPnl()
                      : '+0.00',
                  style: TextStyle(
                    color: AppTheme.primaryGreen,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Данные на 2025-11-25 23:59:59 UTC',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 24),
          _buildPeriodSelector(),
          const SizedBox(height: 24),
          Text(
            'Данные на 2025-11-25 23:59:59 UTC',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Общий P&L',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Суточный P&L',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '2025-11-25 (UTC)',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_getHistoricalPnl()} USD',
                    style: TextStyle(
                      color: AppTheme.primaryGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_getDailyPnlValue()} USD',
                    style: TextStyle(
                      color: AppTheme.primaryGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildPnlChart(),
          const SizedBox(height: 24),
          // Календарь P&L
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Календарь P&L',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () {},
                    iconSize: 20,
                    color: AppTheme.textSecondary,
                  ),
                  Text(
                    '2025-11',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 12,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () {},
                    iconSize: 20,
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildPnlMetrics(),
          const SizedBox(height: 16),
          _buildCalendar(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {bool showDropdown = false}) {
    return GestureDetector(
      onTap: showDropdown && title == 'Торговые пары'
          ? () {
              setState(() {
                _showTradingPairsDropdown = !_showTradingPairsDropdown;
              });
            }
          : null,
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (showDropdown) ...[
            const SizedBox(width: 4),
            Icon(
              _showTradingPairsDropdown && title == 'Торговые пары'
                  ? Icons.arrow_drop_up
                  : Icons.arrow_drop_down,
              color: AppTheme.textSecondary,
              size: 20,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, String percentage,
      {required bool isPositive}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '$value ',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '($percentage)',
                style: TextStyle(
                  color:
                      isPositive ? AppTheme.primaryGreen : AppTheme.primaryRed,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _periods.map((period) {
          final isSelected = period == _selectedPeriod;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                _onPeriodChanged(period);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color:
                      isSelected ? AppTheme.backgroundCard : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.primaryGreen
                        : AppTheme.backgroundCard,
                  ),
                ),
                child: Text(
                  period,
                  style: TextStyle(
                    color: isSelected
                        ? AppTheme.primaryGreen
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
    );
  }

  Widget _buildCurrencyToggle(String label, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          if (label == '%') {
            _showCurrencyInPercent = true;
          } else {
            _showCurrencyInPercent = false;
          }
        });
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryGreen : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? AppTheme.primaryGreen : AppTheme.textSecondary,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.black : AppTheme.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPnlChart({bool isFutures = false}) {
    final chartData =
        _generatePnlChartData(_selectedPeriod, isFutures: isFutures);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey(
            'pnl_${_selectedPeriod}_${isFutures ? 'futures' : 'assets'}'),
        height: 200,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color.fromARGB(255, 0, 0, 0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: 55,
              getDrawingHorizontalLine: (value) {
                return FlLine(
                  color: const Color.fromARGB(255, 47, 47, 47),
                  strokeWidth: 0.5,
                );
              },
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  getTitlesWidget: (value, meta) {
                    return Text(
                      value.toStringAsFixed(0),
                      style: TextStyle(
                        color: const Color.fromARGB(255, 163, 150, 138),
                        fontSize: 10,
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  getTitlesWidget: (value, meta) {
                    final dates = _getChartDates(_selectedPeriod);
                    final index = value.toInt();
                    if (index < 0 || index >= dates.length)
                      return const Text('');

                    // Показываем только первую и последнюю дату, и несколько промежуточных
                    final totalDays = dates.length - 1;
                    if (index == 0 ||
                        index == totalDays ||
                        (totalDays > 7 &&
                            (index == totalDays ~/ 3 ||
                                index == totalDays * 2 ~/ 3))) {
                      return Text(
                        _formatChartDate(dates[index]),
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 10,
                        ),
                      );
                    }
                    return const Text('');
                  },
                ),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            borderData: FlBorderData(show: false),
            minX: 0,
            maxX: chartData.length - 1.0,
            minY: _calculateMinY(chartData),
            maxY: _calculateMaxY(chartData),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                tooltipRoundedRadius: 8,
                tooltipPadding: const EdgeInsets.all(8),
                tooltipBgColor: AppTheme.backgroundCard,
                tooltipBorder:
                    BorderSide(color: AppTheme.borderColor, width: 1),
                getTooltipItems: (List<LineBarSpot> touchedSpots) {
                  return touchedSpots.map((LineBarSpot touchedSpot) {
                    final dates = _getChartDates(_selectedPeriod);
                    final index = touchedSpot.x.toInt();
                    if (index < 0 || index >= dates.length) {
                      return null;
                    }
                    return LineTooltipItem(
                      '${_formatChartDate(dates[index])}\n${touchedSpot.y.toStringAsFixed(2)} USD',
                      TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }).toList();
                },
              ),
              handleBuiltInTouches: true,
              getTouchedSpotIndicator:
                  (LineChartBarData barData, List<int> indicators) {
                return indicators.map((int index) {
                  return TouchedSpotIndicatorData(
                    FlLine(color: AppTheme.primaryGreen, strokeWidth: 2),
                    FlDotData(
                      getDotPainter: (spot, percent, barData, index) =>
                          FlDotCirclePainter(
                        radius: 4,
                        color: AppTheme.primaryGreen,
                        strokeWidth: 2,
                        strokeColor: AppTheme.backgroundCard,
                      ),
                    ),
                  );
                }).toList();
              },
            ),
            lineBarsData: [
              LineChartBarData(
                spots: chartData,
                isCurved: true,
                color: Colors.green,
                barWidth: 2,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.5, 1.0],
                    colors: [
                      Colors.green.withValues(alpha: 0.4),
                      Colors.green.withValues(alpha: 0.2),
                      Colors.green.withValues(alpha: 0.05),
                    ],
                  ),
                  cutOffY: 0,
                  applyCutOffY: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssetsTrendChart() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey('assets_$_selectedPeriod'),
        height: 200,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color.fromARGB(255, 0, 0, 0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: true,
              horizontalInterval: 25,
              getDrawingHorizontalLine: (value) {
                return FlLine(
                  color: const Color.fromARGB(255, 47, 47, 47),
                  strokeWidth: 1,
                  dashArray: [5, 5],
                );
              },
              getDrawingVerticalLine: (value) {
                return FlLine(
                  color: const Color.fromARGB(255, 0, 0, 0).withOpacity(0.7),
                  strokeWidth: 1,
                  dashArray: [5, 5],
                );
              },
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  getTitlesWidget: (value, meta) {
                    return Text(
                      value.toStringAsFixed(0),
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  getTitlesWidget: (value, meta) {
                    final dates = _getChartDates(_selectedPeriod);
                    final index = value.toInt();
                    if (index < 0 || index >= dates.length)
                      return const Text('');

                    // Показываем только первую и последнюю дату, и несколько промежуточных
                    final totalDays = dates.length - 1;
                    if (index == 0 ||
                        index == totalDays ||
                        (totalDays > 7 &&
                            (index == totalDays ~/ 3 ||
                                index == totalDays * 2 ~/ 3))) {
                      return Text(
                        _formatChartDate(dates[index]),
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 10,
                        ),
                      );
                    }
                    return const Text('');
                  },
                ),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            borderData: FlBorderData(show: false),
            minX: 0,
            maxX: _generateDailyPnlChartData(_selectedPeriod).length - 1.0,
            minY: _calculateMinY(_generateDailyPnlChartData(_selectedPeriod)),
            maxY: _calculateMaxY(_generateDailyPnlChartData(_selectedPeriod)),
            lineTouchData: _buildLineTouchData(),
            lineBarsData: [
              LineChartBarData(
                spots: _generateDailyPnlChartData(_selectedPeriod),
                isCurved: false,
                color: Colors.orange,
                barWidth: 2,
                dotData: FlDotData(
                  show: false, // Убираем точки, чтобы не слипались
                  getDotPainter: (spot, percent, barData, index) {
                    // Показываем точки только на определенных интервалах для коротких периодов
                    final totalSpots = barData.spots.length;
                    final showDot = totalSpots <= 30 &&
                        (index == 0 ||
                            index == totalSpots - 1 ||
                            index % 5 == 0);
                    if (!showDot) {
                      return FlDotCirclePainter(
                        radius: 0,
                        color: Colors.transparent,
                      );
                    }
                    return FlDotCirclePainter(
                      radius: 3,
                      color: Colors.orange,
                      strokeWidth: 1.5,
                      strokeColor: AppTheme.backgroundCard,
                    );
                  },
                ),
                belowBarData: BarAreaData(show: false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDailyPnlChart() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey('daily_$_selectedPeriod'),
        height: 200,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color.fromARGB(255, 0, 0, 0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: 55,
              getDrawingHorizontalLine: (value) {
                return FlLine(
                  color: const Color.fromARGB(255, 47, 47, 47),
                  strokeWidth: 0.5,
                );
              },
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  getTitlesWidget: (value, meta) {
                    return Text(
                      value.toStringAsFixed(0),
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  getTitlesWidget: (value, meta) {
                    final dates = _getChartDates(_selectedPeriod);
                    final index = value.toInt();
                    if (index < 0 || index >= dates.length)
                      return const Text('');

                    // Показываем только первую и последнюю дату, и несколько промежуточных
                    final totalDays = dates.length - 1;
                    if (index == 0 ||
                        index == totalDays ||
                        (totalDays > 7 &&
                            (index == totalDays ~/ 3 ||
                                index == totalDays * 2 ~/ 3))) {
                      return Text(
                        _formatChartDate(dates[index]),
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 10,
                        ),
                      );
                    }
                    return const Text('');
                  },
                ),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            borderData: FlBorderData(show: false),
            minX: 0,
            maxX: _generateDailyPnlChartData(_selectedPeriod).length - 1.0,
            minY: _calculateMinY(_generateDailyPnlChartData(_selectedPeriod)),
            maxY: _calculateMaxY(_generateDailyPnlChartData(_selectedPeriod)),
            lineTouchData: _buildLineTouchData(),
            lineBarsData: _buildDailyPnlLineBars(),
          ),
        ),
      ),
    );
  }

  List<LineChartBarData> _buildDailyPnlLineBars() {
    final spots = _generateDailyPnlChartData(_selectedPeriod);

    // Разделяем точки на положительные и отрицательные относительно начального значения
    final initialValue = spots.isNotEmpty ? spots.first.y : 0.0;
    final positiveSpots = <FlSpot>[];
    final negativeSpots = <FlSpot>[];

    for (final spot in spots) {
      final relativeValue = spot.y - initialValue;
      if (relativeValue >= 0) {
        positiveSpots.add(FlSpot(spot.x, spot.y));
        negativeSpots.add(
            FlSpot(spot.x, initialValue)); // Линия на нуле для отрицательных
      } else {
        negativeSpots.add(FlSpot(spot.x, spot.y));
        positiveSpots.add(
            FlSpot(spot.x, initialValue)); // Линия на нуле для положительных
      }
    }

    return [
      // Отрицательные значения (красная заливка)
      LineChartBarData(
        spots: negativeSpots,
        isCurved: true,
        color: AppTheme.primaryRed,
        barWidth: 2,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.0, 0.5, 1.0],
            colors: [
              AppTheme.primaryRed.withValues(alpha: 0.4),
              AppTheme.primaryRed.withValues(alpha: 0.2),
              AppTheme.primaryRed.withValues(alpha: 0.05),
            ],
          ),
          cutOffY: initialValue,
          applyCutOffY: true,
        ),
      ),
      // Положительные значения (зеленая заливка)
      LineChartBarData(
        spots: positiveSpots,
        isCurved: true,
        color: Colors.green,
        barWidth: 2,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.0, 0.5, 1.0],
            colors: [
              Colors.green.withValues(alpha: 0.4),
              Colors.green.withValues(alpha: 0.2),
              Colors.green.withValues(alpha: 0.05),
            ],
          ),
          cutOffY: initialValue,
          applyCutOffY: true,
        ),
      ),
    ];
  }

  Widget _buildOrderValueChart() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey(
            'order_${_selectedPeriod}_${_showTotalOrderValue}_${_showPurchaseValue}_${_showSaleValue}'),
        height: 200,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color.fromARGB(255, 0, 0, 0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: 0.7,
              getDrawingHorizontalLine: (value) {
                return FlLine(
                  color: const Color.fromARGB(255, 0, 0, 0),
                  strokeWidth: 1,
                );
              },
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  getTitlesWidget: (value, meta) {
                    return Text(
                      value.toStringAsFixed(2),
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  getTitlesWidget: (value, meta) {
                    final dates = _getChartDates(_selectedPeriod);
                    final index = value.toInt();
                    if (index < 0 || index >= dates.length)
                      return const Text('');

                    // Показываем только первую и последнюю дату, и несколько промежуточных
                    final totalDays = dates.length - 1;
                    if (index == 0 ||
                        index == totalDays ||
                        (totalDays > 7 &&
                            (index == totalDays ~/ 3 ||
                                index == totalDays * 2 ~/ 3))) {
                      return Text(
                        _formatChartDate(dates[index]),
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 10,
                        ),
                      );
                    }
                    return const Text('');
                  },
                ),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            borderData: FlBorderData(show: false),
            minX: 0,
            maxX: _generateChartData(_selectedPeriod).length - 1.0,
            minY: _calculateMinYForOrderValue(_selectedPeriod),
            maxY: _calculateMaxYForOrderValue(_selectedPeriod),
            lineTouchData: _buildLineTouchData(),
            lineBarsData: [
              // Общая стоимость исполненных ордеров (оранжевая)
              if (_showTotalOrderValue)
                LineChartBarData(
                  spots:
                      _generateOrderValueData(_selectedPeriod)['total'] ?? [],
                  isCurved: false,
                  color: Colors.orange,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: false),
                ),
              // Стоимость покупки (зеленая)
              if (_showPurchaseValue)
                LineChartBarData(
                  spots: _generateOrderValueData(_selectedPeriod)['purchase'] ??
                      [],
                  isCurved: false,
                  color: AppTheme.primaryGreen,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: false),
                ),
              // Стоимость продажи (красная)
              if (_showSaleValue)
                LineChartBarData(
                  spots: _generateOrderValueData(_selectedPeriod)['sale'] ?? [],
                  isCurved: false,
                  color: AppTheme.primaryRed,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: false),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckboxRow(String label, bool isChecked,
      {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                border: Border.all(
                  color: isChecked
                      ? AppTheme.primaryGreen
                      : AppTheme.textSecondary,
                ),
                borderRadius: BorderRadius.circular(4),
                color: isChecked ? AppTheme.primaryGreen : Colors.transparent,
              ),
              child: isChecked
                  ? const Icon(Icons.check, size: 12, color: Colors.black)
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 11,
              ),
              maxLines: 2,
              softWrap: true,
              overflow: TextOverflow.visible,
              textAlign: TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPnlMetrics() {
    return Column(
      children: [
        _buildMetricRow(
          'Трейдерское состязание этого месяца по P&L (USD)',
          MockPortfolioService.useMockData ? _getContestPnl() : '+0.00',
          isPositive: true,
        ),
        const SizedBox(height: 12),
        _buildMetricRow(
          'ROI',
          MockPortfolioService.useMockData ? _getROI() : '+0.00%',
          isPositive: true,
        ),
        const SizedBox(height: 12),
        _buildMetricRow(
          'Процент успешных сделок',
          MockPortfolioService.useMockData ? _getWinRate() : '0.00%',
          isPositive: null,
        ),
        const SizedBox(height: 12),
        _buildMetricRow(
          'Всего позиций',
          MockPortfolioService.useMockData ? _getTotalPositions() : '0',
          isPositive: null,
        ),
      ],
    );
  }

  // Построение списка монет с распределением
  Widget _buildCoinsList() {
    // Вычисляем общую сумму для расчета процентов
    final totalUsd = _coinsList.fold<double>(
      0.0,
      (sum, coin) => sum + (coin['usdValue'] as num? ?? 0).toDouble(),
    );

    // Сортируем по стоимости в USD (от большего к меньшему)
    final sortedCoins = List<Map<String, dynamic>>.from(_coinsList)
      ..sort((a, b) {
        final aValue = (a['usdValue'] as num? ?? 0).toDouble();
        final bValue = (b['usdValue'] as num? ?? 0).toDouble();
        return bValue.compareTo(aValue);
      });

    return Column(
      children: sortedCoins.map((coin) {
        final coinName = coin['coin']?.toString() ?? '';
        final equity = (coin['equity'] as num? ?? 0).toDouble();
        final usdValue = (coin['usdValue'] as num? ?? 0).toDouble();
        final percent = totalUsd > 0 ? (usdValue / totalUsd * 100) : 0.0;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.backgroundCard,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      // Иконка монеты (можно добавить позже)
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            coinName.substring(
                                0, coinName.length > 3 ? 3 : coinName.length),
                            style: TextStyle(
                              color: AppTheme.primaryGreen,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            coinName,
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${equity.toStringAsFixed(coinName == 'BTC' || coinName == 'ETH' ? 4 : 2)} $coinName',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _showCurrencyInPercent
                            ? '${percent.toStringAsFixed(2)}%'
                            : '\$${usdValue.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (!_showCurrencyInPercent)
                        Text(
                          '${percent.toStringAsFixed(2)}%',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Прогресс-бар распределения
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percent / 100,
                  minHeight: 4,
                  backgroundColor: AppTheme.backgroundDark,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppTheme.primaryGreen,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMetricRow(String label, String value, {bool? isPositive}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: isPositive == null
                ? AppTheme.textPrimary
                : isPositive
                    ? AppTheme.primaryGreen
                    : AppTheme.primaryRed,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(
            Icons.description_outlined,
            color: AppTheme.textSecondary,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // Виджет для выбора торговых пар
  Widget _buildTradingPairsSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundCard,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Выберите торговые пары',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    if (_selectedTradingPairs.length ==
                        _availableTradingPairs.length) {
                      _selectedTradingPairs.clear();
                    } else {
                      _selectedTradingPairs = List.from(_availableTradingPairs);
                    }
                  });
                },
                child: Text(
                  _selectedTradingPairs.length == _availableTradingPairs.length
                      ? 'Снять все'
                      : 'Выбрать все',
                  style: TextStyle(
                    color: AppTheme.primaryGreen,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _availableTradingPairs.map((pair) {
              final isSelected = _selectedTradingPairs.contains(pair);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedTradingPairs.remove(pair);
                    } else {
                      _selectedTradingPairs.add(pair);
                    }
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color:
                        isSelected ? AppTheme.primaryGreen : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primaryGreen
                          : AppTheme.borderColor,
                    ),
                  ),
                  child: Text(
                    pair,
                    style: TextStyle(
                      color: isSelected ? Colors.black : AppTheme.textPrimary,
                      fontSize: 11,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Days of week
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                .map((day) => Text(
                      day,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          // Calendar grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: 35,
            itemBuilder: (context, index) {
              final day = index - 0; // Adjust based on first day of month
              if (day < 1 || day > 30) {
                return const SizedBox.shrink();
              }
              return Container(
                decoration: BoxDecoration(
                  color: AppTheme.backgroundElevated,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: Text(
                    day.toString(),
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

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
