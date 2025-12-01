import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/crypto_api_service.dart';
import '../models/crypto_model.dart';
import '../config/app_constants.dart';

class EarnScreen extends StatefulWidget {
  const EarnScreen({super.key});

  @override
  State<EarnScreen> createState() => _EarnScreenState();
}

class _EarnScreenState extends State<EarnScreen> {
  String _searchQuery = '';
  String _selectedEarnType = 'Easy Earn'; // Easy Earn или Advanced Earn
  String _selectedTab = 'Постоянный доход';
  final Map<String, bool> _expandedCoins =
      {}; // Для отслеживания раскрытых секций
  List<Map<String, dynamic>> _earnProducts = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Загружаем данные (можно будет заменить на API)
    _loadEarnProducts();
  }

  Future<void> _loadEarnProducts() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Получаем реальные монеты из API
      final coins = await CryptoApiService.getMarkets(
        category: 'spot',
        perPage: 50,
      );

      // Сортируем монеты: сначала популярные, затем по обороту
      final sortedCoins = List<CryptoModel>.from(coins);
      sortedCoins.sort((a, b) {
        final aIsPopular = AppConstants.topCoins.contains(a.symbol);
        final bIsPopular = AppConstants.topCoins.contains(b.symbol);

        // Популярные монеты идут первыми
        if (aIsPopular && !bIsPopular) return -1;
        if (!aIsPopular && bIsPopular) return 1;

        // Если обе популярные или обе нет, сортируем по позиции в списке topCoins
        if (aIsPopular && bIsPopular) {
          final aIndex = AppConstants.topCoins.indexOf(a.symbol);
          final bIndex = AppConstants.topCoins.indexOf(b.symbol);
          return aIndex.compareTo(bIndex);
        }

        // Если обе не популярные, сортируем по обороту (turnover24h)
        return b.turnover24h.compareTo(a.turnover24h);
      });

      // Берем первые 10 монет (самые популярные)
      final topCoins = sortedCoins.take(10).toList();

      // Преобразуем монеты в формат Earn продуктов
      final earnProducts = topCoins.map((coin) {
        final symbol = coin.symbol;
        final name = coin.name;
        final iconColor = _getCoinColor(symbol);

        // Генерируем продукты с разными периодами
        final products = _generateEarnProducts(symbol, coin);

        return {
          'symbol': symbol,
          'name': name,
          'iconColor': iconColor,
          'earnType': 'Easy Earn', // Все монеты пока в Easy Earn
          'products': products,
        };
      }).toList();

      setState(() {
        _earnProducts = earnProducts;

        // По умолчанию все секции раскрыты
        for (var product in _earnProducts) {
          _expandedCoins[product['symbol']] = true;
        }

        _isLoading = false;
      });
    } catch (e) {
      // В случае ошибки используем моковые данные
      setState(() {
        _earnProducts = _getMockEarnProducts();
        for (var product in _earnProducts) {
          _expandedCoins[product['symbol']] = true;
        }
        _isLoading = false;
      });
    }
  }

  // Генерация продуктов Earn на основе монеты
  List<Map<String, dynamic>> _generateEarnProducts(
    String symbol,
    CryptoModel coin,
  ) {
    final products = <Map<String, dynamic>>[];

    // Базовый APR зависит от типа монеты
    double baseApr = _getBaseApr(symbol, coin);

    // Гибкий период (всегда есть)
    products.add({
      'type': 'Easy Earn',
      'period': 'Гибкий',
      'apr': baseApr,
    });

    // Дополнительные периоды для популярных монет
    if (_isPopularCoin(symbol)) {
      products.add({
        'type': 'Easy Earn',
        'period': '30 д.',
        'apr': baseApr * 0.5,
      });

      if (symbol == 'USDT' || symbol == 'USDC') {
        products.add({
          'type': 'Easy Earn',
          'period': '90 д.',
          'apr': baseApr * 1.3,
        });
      }
    }

    return products;
  }

  // Получить базовый APR для монеты
  double _getBaseApr(String symbol, CryptoModel coin) {
    // Для стабильных монет более высокий APR
    if (symbol == 'USDT' || symbol == 'USDC' || symbol == 'BUSD') {
      return 6.0 + (coin.volume24h > 1000000 ? 2.0 : 0.0);
    }

    // Для популярных монет средний APR
    if (_isPopularCoin(symbol)) {
      return 2.0 + (coin.change24h > 0 ? 0.5 : 0.0);
    }

    // Для остальных монет базовый APR
    return 1.5 + (coin.volume24h > 500000 ? 1.0 : 0.0);
  }

  // Проверка, является ли монета популярной
  bool _isPopularCoin(String symbol) {
    const popularCoins = [
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
    return popularCoins.contains(symbol);
  }

  // Получить цвет для монеты
  Color _getCoinColor(String symbol) {
    final colorMap = {
      'BTC': Color(0xFFF7931A),
      'ETH': Color(0xFF627EEA),
      'USDT': Color(0xFF26A17B),
      'USDC': Color(0xFF2775CA),
      'BNB': Color(0xFFF3BA2F),
      'SOL': Color(0xFF14F195),
      'XRP': Color(0xFF000000),
      'ADA': Color(0xFF0033AD),
      'DOGE': Color(0xFFC2A633),
      'MATIC': Color(0xFF8247E5),
      'AVAX': Color(0xFFE84142),
      'DOT': Color(0xFFE6007A),
      'LINK': Color(0xFF2A5ADA),
      'UNI': Color(0xFFFF007A),
      'ATOM': Color(0xFF2E3148),
      'LTC': Color(0xFFBFBBBB),
      'ETC': Color(0xFF328332),
    };

    return colorMap[symbol] ?? AppTheme.primaryGreen;
  }

  // Моковые данные для fallback
  List<Map<String, dynamic>> _getMockEarnProducts() {
    return [
      {
        'symbol': 'BTC',
        'name': 'Bitcoin',
        'iconColor': Color(0xFFF7931A),
        'earnType': 'Easy Earn',
        'products': [
          {
            'type': 'Easy Earn',
            'period': 'Гибкий',
            'apr': 2.30,
          },
          {
            'type': 'Easy Earn',
            'period': '30 д.',
            'apr': 0.30,
          },
        ],
      },
      {
        'symbol': 'ETH',
        'name': 'Ethereum',
        'iconColor': Color(0xFF627EEA),
        'earnType': 'Easy Earn',
        'products': [
          {
            'type': 'Easy Earn',
            'period': 'Гибкий',
            'apr': 0.80,
          },
        ],
      },
      {
        'symbol': 'USDT',
        'name': 'Tether',
        'iconColor': Color(0xFF26A17B),
        'earnType': 'Easy Earn',
        'products': [
          {
            'type': 'Easy Earn',
            'period': 'Гибкий',
            'apr': 6.4,
          },
          {
            'type': 'Easy Earn',
            'period': '90 д.',
            'apr': 8.2,
          },
        ],
      },
    ];
  }

  List<Map<String, dynamic>> get _filteredProducts {
    var filtered = _earnProducts;

    // Фильтр по типу Earn
    if (_selectedEarnType == 'Easy Earn') {
      filtered = filtered.where((p) => p['earnType'] == 'Easy Earn').toList();
    } else {
      filtered =
          filtered.where((p) => p['earnType'] == 'Advanced Earn').toList();
    }

    // Фильтр по поисковому запросу
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((p) {
        return p['symbol'].toString().toLowerCase().contains(query) ||
            (p['name'] != null &&
                p['name'].toString().toLowerCase().contains(query));
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Search bar with icons
            SliverToBoxAdapter(
              child: _buildSearchBar(),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 24),
            ),
            // Earn type buttons
            SliverToBoxAdapter(
              child: _buildEarnTypeButtons(),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 24),
            ),
            // Header with tabs
            SliverToBoxAdapter(
              child: _buildHeaderWithTabs(),
            ),
            // Products list
            _buildProductsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppTheme.backgroundCard,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, color: AppTheme.textSecondary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Введите предпочитаемую монету',
                        hintStyle: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 15,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                    ),
                  ),
                  if (_searchQuery.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                      child: Icon(
                        Icons.close,
                        color: AppTheme.textSecondary,
                        size: 18,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Ticket icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.backgroundCard,
              borderRadius: BorderRadius.circular(22),
            ),
            child: IconButton(
              onPressed: () {},
              icon: Icon(
                Icons.confirmation_number_outlined,
                color: AppTheme.textPrimary,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Grid icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.backgroundCard,
              borderRadius: BorderRadius.circular(22),
            ),
            child: IconButton(
              onPressed: () {},
              icon: Icon(
                Icons.grid_view_outlined,
                color: AppTheme.textPrimary,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEarnTypeButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Easy Earn button
          GestureDetector(
            onTap: () {
              setState(() {
                _selectedEarnType = 'Easy Earn';
              });
            },
            child: Column(
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundCard,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.account_balance_wallet_outlined,
                    color: AppTheme.textPrimary,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Easy Earn',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 48),
          // Advanced Earn button
          GestureDetector(
            onTap: () {
              setState(() {
                _selectedEarnType = 'Advanced Earn';
              });
            },
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundCard,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.trending_up_outlined,
                        color: AppTheme.textPrimary,
                        size: 24,
                      ),
                    ),
                    // New badge
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.depositButton,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'йNew',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Продвинутый Earn',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderWithTabs() {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Text(
                'Смотреть продукты',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () {},
                icon: Icon(
                  Icons.tune,
                  color: AppTheme.textPrimary,
                  size: 24,
                ),
              ),
            ],
          ),
        ),
        // Tabs
        _buildTabs(),
      ],
    );
  }

  Widget _buildTabs() {
    final tabs = [
      'Постоянный доход',
      'Макс. рост',
      'Эксклюзивно для VIP',
    ];

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final isSelected = tab == _selectedTab;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedTab = tab;
              });
            },
            child: Container(
              margin: const EdgeInsets.only(right: 24),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color:
                        isSelected ? AppTheme.primaryGreen : Colors.transparent,
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
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProductsList() {
    if (_isLoading) {
      return SliverFillRemaining(
        child: Center(
          child: CircularProgressIndicator(
            color: AppTheme.primaryGreen,
          ),
        ),
      );
    }

    final filtered = _filteredProducts;

    if (filtered.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Text(
            _searchQuery.isNotEmpty
                ? 'Ничего не найдено'
                : 'Нет доступных продуктов',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final product = filtered[index];
            return _buildCoinSection(product);
          },
          childCount: filtered.length,
        ),
      ),
    );
  }

  Widget _buildCoinSection(Map<String, dynamic> coinData) {
    final symbol = coinData['symbol'] as String;
    final iconColor = coinData['iconColor'] as Color;
    final products = coinData['products'] as List<Map<String, dynamic>>;
    final isExpanded = _expandedCoins[symbol] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 0, 0, 0),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          // Header
          GestureDetector(
            onTap: () {
              setState(() {
                _expandedCoins[symbol] = !isExpanded;
              });
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Icon
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        symbol.isNotEmpty ? symbol.substring(0, 1) : '?',
                        style: TextStyle(
                          color: iconColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Symbol
                  Text(
                    symbol,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  // Chevron
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    color: AppTheme.textSecondary,
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
          // Products list (раскрывается/сворачивается)
          if (isExpanded)
            ...products.map((product) => _buildProductItem(product)),
        ],
      ),
    );
  }

  Widget _buildProductItem(Map<String, dynamic> product) {
    final type = product['type'] as String;
    final period = product['period'] as String;
    final apr = product['apr'] as double;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppTheme.borderColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Type with question mark
          Row(
            children: [
              Text(
                type,
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: AppTheme.textSecondary.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '?',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          // Period
          Text(
            period,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          // APR
          Row(
            children: [
              Text(
                'APR',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${apr.toStringAsFixed(2)}%',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          // Arrow
          Icon(
            Icons.arrow_forward_ios,
            color: AppTheme.textSecondary,
            size: 16,
          ),
        ],
      ),
    );
  }
}
