import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../theme/app_theme.dart';
import '../widgets/bottom_nav_bar.dart';
import '../services/crypto_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/crypto_model.dart';
import 'markets_screen.dart';
import 'trade_screen.dart';
import 'earn_screen.dart';
import 'wallet_screen.dart';
import 'p2p_trading_screen.dart';
import '../services/mock_portfolio_service.dart';
import '../config/app_constants.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final GlobalKey<_HomeMainScreenState> _homeMainKey =
      GlobalKey<_HomeMainScreenState>();
  final ValueNotifier<String?> _tradePairNotifier =
      ValueNotifier<String?>(null);

  late final List<Widget> _screens = [
    HomeMainScreen(
      key: _homeMainKey,
      onNavigateToMarkets: () {
        setState(() {
          _currentIndex = 1; // Переключаемся на Markets
        });
      },
    ),
    MarketsScreen(
      favoriteCoins: _homeMainKey.currentState?._favoriteCoins,
      onNavigateToTrade: (String pair) {
        // Обновляем пару в TradeScreen и переключаемся на него
        _tradePairNotifier.value = pair;
        setState(() {
          _currentIndex = 2; // Переключаемся на TradeScreen
        });
      },
    ),
    TradeScreen(
      pairNotifier: _tradePairNotifier,
    ),
    const EarnScreen(),
    const WalletScreen(),
  ];

  @override
  void dispose() {
    _tradePairNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Обновляем MarketsScreen с актуальными favoriteCoins
    final updatedScreens = [
      _screens[0], // HomeMainScreen
      MarketsScreen(
        favoriteCoins: _homeMainKey.currentState?._favoriteCoins,
        onNavigateToTrade: (String pair) {
          // Обновляем пару в TradeScreen и переключаемся на него
          _tradePairNotifier.value = pair;
          setState(() {
            _currentIndex = 2; // Переключаемся на TradeScreen
          });
        },
      ),
      _screens[2], // TradeScreen
      _screens[3], // EarnScreen
      _screens[4], // WalletScreen
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: updatedScreens,
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}

class HomeMainScreen extends StatefulWidget {
  final VoidCallback? onNavigateToMarkets;

  const HomeMainScreen({super.key, this.onNavigateToMarkets});

  @override
  State<HomeMainScreen> createState() => _HomeMainScreenState();
}

class _HomeMainScreenState extends State<HomeMainScreen> {
  bool _balanceVisible = true;
  String _selectedMainTab = 'Популярные';
  String _selectedSubTab = 'Спот';
  List<CryptoModel> _cryptoList = [];
  bool _isLoading = true;
  String _searchQuery = '';

  // Данные баланса
  double _totalUsd = 0.0;
  double _pnlToday = 0.0;

  // Кэш для каждой категории
  final Map<String, List<CryptoModel>> _dataCache = {};
  final Map<String, bool> _loadingCache = {};

  // Для избранного: выбранные монеты (для выбора новых)
  final Set<String> _selectedCoins = {};

  // Сохраненные избранные монеты по категориям: {категория: [список монет]}
  final Map<String, List<CryptoModel>> _favoriteCoins = {};

  final List<String> _mainTabs = [
    'Избранное',
    'Популярные',
    'Новые',
    'Активные монеты',
    'Лидеры падения',
    'Оборот'
  ];
  // Получить подкатегории в зависимости от главной категории
  List<String> get _subTabs {
    switch (_selectedMainTab) {
      case 'Избранное':
        return ['Спот', 'Деривативы', 'TradFi'];
      case 'Популярные':
      case 'Новые':
        return ['Спот', 'Alpha', 'Деривативы', 'TradFi'];
      case 'Активные монеты':
      case 'Лидеры падения':
        return ['Спот', 'Фьючерсы', 'Опцион', 'TradFi'];
      case 'Оборот':
        return ['Спот', 'Деривативы', 'TradFi'];
      default:
        return ['Спот', 'Alpha', 'Деривативы', 'TradFi'];
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedSubTab = _subTabs.first;
    _loadFavoriteCoinsFromFirebase();
    _preloadAllCategories();
    _loadCategoryData(_selectedSubTab);
    _loadBalanceData();
    // Слушаем изменения баланса в реальном времени
    MockPortfolioService.balanceNotifier.addListener(_onBalanceChanged);
  }

  @override
  void dispose() {
    // Удаляем слушатель при dispose
    MockPortfolioService.balanceNotifier.removeListener(_onBalanceChanged);
    super.dispose();
  }

  void _onBalanceChanged() {
    // Обновляем баланс при изменении P&L в реальном времени
    if (mounted && MockPortfolioService.useMockData) {
      setState(() {
        _totalUsd = MockPortfolioService.totalUsd;
        _pnlToday = MockPortfolioService.pnlToday;
      });
    }
  }

  // Загрузка данных баланса
  Future<void> _loadBalanceData() async {
    // Используем моковые данные, если включен флаг
    if (MockPortfolioService.useMockData) {
      // Принудительно обновляем цены из API перед расчетом баланса
      await MockPortfolioService.refreshPrices();

      if (!mounted) return;
      setState(() {
        _totalUsd = MockPortfolioService.totalUsd;
        // P&L за сегодня теперь рассчитывается на основе баланса на начало дня
        _pnlToday = MockPortfolioService.pnlToday;
      });
      return;
    }

    // Реальные данные из API
    try {
      final totalBalance = await CryptoApiService.getTotalBalance();
      // Для P&L за сегодня можно использовать разницу или отдельный API
      // Пока используем 0, если нет отдельного API для P&L за сегодня
      if (!mounted) return;
      setState(() {
        _totalUsd = totalBalance['usd'] ?? 0.0;
        _pnlToday = 0.0; // TODO: загрузить реальный P&L за сегодня из API
      });
    } catch (e) {
      // В случае ошибки оставляем значения по умолчанию
      if (!mounted) return;
      setState(() {
        _totalUsd = 0.0;
        _pnlToday = 0.0;
      });
    }
  }

  // Загрузить избранные монеты из локального хранилища
  Future<void> _loadFavoriteCoinsFromFirebase() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Получаем userId из Firebase Auth
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null)
        return; // Если пользователь не авторизован, не загружаем

      final favoriteData =
          prefs.getString('${AppConstants.prefsKeyFavoriteCoins}$userId');
      if (favoriteData != null) {
        final Map<String, dynamic> decoded = json.decode(favoriteData);
        if (!mounted) return;
        setState(() {
          decoded.forEach((key, value) {
            if (value is List) {
              _favoriteCoins[key] = value
                  .map((json) => CryptoModel(
                        id: json['id'] ?? '',
                        symbol: json['symbol'] ?? '',
                        name: json['name'] ?? '',
                        price: (json['price'] ?? 0).toDouble(),
                        change24h: (json['change24h'] ?? 0).toDouble(),
                        volume24h: (json['volume24h'] ?? 0).toDouble(),
                        turnover24h: (json['turnover24h'] ?? 0).toDouble(),
                      ))
                  .toList();
            }
          });
        });
      }
    } catch (e) {
      // Ошибка загрузки - продолжаем с пустым списком
    }
  }

  // Сохранить избранные монеты в локальное хранилище
  Future<void> _saveFavoriteCoinsToLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Получаем userId из Firebase Auth
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null)
        return; // Если пользователь не авторизован, не сохраняем

      final Map<String, dynamic> dataToSave = {};
      _favoriteCoins.forEach((key, value) {
        dataToSave[key] = value
            .map((crypto) => {
                  'id': crypto.id,
                  'symbol': crypto.symbol,
                  'name': crypto.name,
                  'price': crypto.price,
                  'change24h': crypto.change24h,
                  'volume24h': crypto.volume24h,
                  'turnover24h': crypto.turnover24h,
                })
            .toList();
      });
      await prefs.setString('${AppConstants.prefsKeyFavoriteCoins}$userId',
          json.encode(dataToSave));
    } catch (e) {
      // Ошибка сохранения
    }
  }

  // Предзагрузка данных для всех категорий (параллельно)
  Future<void> _preloadAllCategories() async {
    final futures = <Future<void>>[];
    for (final tab in _subTabs) {
      final cacheKey = '${_selectedMainTab}_$tab';
      if (!_dataCache.containsKey(cacheKey)) {
        futures.add(_loadCategoryData(tab, silent: true));
      }
    }
    // Загружаем все категории параллельно, но не ждем завершения
    if (futures.isNotEmpty) {
      Future.wait(futures).catchError((_) {
        // Игнорируем ошибки при предзагрузке
        return <void>[];
      });
    }
  }

  // Загрузка данных для конкретной категории
  Future<void> _loadCategoryData(String category, {bool silent = false}) async {
    final cacheKey = '${_selectedMainTab}_$category';
    if (!silent && _loadingCache[cacheKey] == true) return;

    _loadingCache[cacheKey] = true;

    try {
      List<CryptoModel> data;

      // Для "Избранное" показываем сохраненные монеты, если они есть
      // Или показываем выборку для добавления новых
      if (_selectedMainTab == 'Избранное') {
        final favoriteKey = category; // Спот, Деривативы, TradFi
        if (_favoriteCoins.containsKey(favoriteKey) &&
            _favoriteCoins[favoriteKey]!.isNotEmpty) {
          // Показываем сохраненные избранные монеты
          data = _favoriteCoins[favoriteKey]!;
        } else {
          // Если избранных нет, загружаем топ 6 для выбора
          final mainCategory = 'Популярные';
          data = await CryptoApiService.getMarketsByCategory(
            mainCategory: mainCategory,
            subCategory: category,
            perPage: 6,
          );
        }
      } else {
        // Для остальных категорий загружаем как обычно
        final perPage = _selectedMainTab == 'Активные монеты' ? 5 : 20;
        data = await CryptoApiService.getMarketsByCategory(
          mainCategory: _selectedMainTab,
          subCategory: category,
          perPage: perPage,
        );
      }

      _dataCache[cacheKey] = data;
      _loadingCache[cacheKey] = false;

      // Синхронизируем цены с MockPortfolioService (для экрана активов)
      // Делаем это асинхронно, чтобы не блокировать UI
      if (MockPortfolioService.useMockData) {
        // Используем scheduleMicrotask для неблокирующего обновления
        scheduleMicrotask(() {
          MockPortfolioService.updatePricesFromCryptoList(data);
        });
      }

      // Обновляем UI только если это текущая категория
      if (category == _selectedSubTab && mounted) {
        setState(() {
          _cryptoList = data;
          _isLoading = false;
          // Для "Избранное" автоматически выбираем все монеты
          if (_selectedMainTab == 'Избранное') {
            _selectedCoins.clear();
            _selectedCoins.addAll(data.map((crypto) => crypto.id).toSet());
          }
        });
      }
    } catch (e) {
      _loadingCache[cacheKey] = false;
      if (category == _selectedSubTab && mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadCryptoData() async {
    final cacheKey = '${_selectedMainTab}_$_selectedSubTab';

    // Если данные уже есть в кэше, показываем их сразу
    if (_dataCache.containsKey(cacheKey)) {
      if (!mounted) return;
      setState(() {
        _cryptoList = _dataCache[cacheKey]!;
        _isLoading = false;
        // Для "Избранное" автоматически выбираем все монеты
        if (_selectedMainTab == 'Избранное') {
          _selectedCoins.clear();
          _selectedCoins.addAll(_cryptoList.map((crypto) => crypto.id).toSet());
        }
      });
      // Обновляем данные в фоне
      _loadCategoryData(_selectedSubTab, silent: false);
      return;
    }

    // Если данных нет, показываем индикатор загрузки
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    await _loadCategoryData(_selectedSubTab, silent: false);
  }

  // Получить отфильтрованный список криптовалют
  List<CryptoModel> get _filteredCryptoList {
    if (_searchQuery.isEmpty) {
      return _cryptoList;
    }
    final query = _searchQuery.toLowerCase();
    return _cryptoList.where((crypto) {
      return crypto.pair.toLowerCase().contains(query) ||
          crypto.symbol.toLowerCase().contains(query) ||
          (crypto.name.toLowerCase().contains(query));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            // Header with search
            SliverToBoxAdapter(
              child: _buildHeader(),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 20),
            ),
            // Balance section
            SliverToBoxAdapter(
              child: _buildBalanceSection(),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 28),
            ),
            // Quick access features
            SliverToBoxAdapter(
              child: _buildQuickFeatures(),
            ),
            // Markets section
            SliverToBoxAdapter(
              child: _buildMarketsSection(),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 80), // Space for bottom nav
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: [
          // Profile icon
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.grey.shade800,
            child: const Icon(Icons.person, color: Colors.white70, size: 20),
          ),
          const SizedBox(width: 12),
          // Search bar
          Expanded(
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppTheme.backgroundCard,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Colors.white24, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      style: TextStyle(color: Colors.white70, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'Поиск торговой пары',
                        hintStyle: TextStyle(
                          color: Colors.white38,
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
                      child: const Icon(
                        Icons.close,
                        color: Colors.white38,
                        size: 18,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.qr_code_scanner, color: Colors.white54),
          ),
          Stack(
            children: [
              IconButton(
                onPressed: () {},
                icon:
                    const Icon(Icons.notifications_none, color: Colors.white54),
              ),
              Positioned(
                right: 8,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                  constraints:
                      const BoxConstraints(minWidth: 18, minHeight: 18),
                  child: const Text(
                    '18',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Общие активы', style: TextStyle(color: Colors.white54)),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _balanceVisible = !_balanceVisible;
                  });
                },
                child: const Icon(Icons.remove_red_eye,
                    color: Colors.white24, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _balanceVisible
                            ? _totalUsd.toStringAsFixed(2).replaceAllMapped(
                                RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                                (Match m) => '${m[1]},')
                            : '••••',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('USD',
                            style:
                                TextStyle(color: Colors.white54, fontSize: 14)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                      'P&L за сегодня ${_pnlToday >= 0 ? '+' : ''}${_pnlToday.toStringAsFixed(2)} USD',
                      style: TextStyle(
                          color: _pnlToday >= 0
                              ? AppTheme.primaryGreen
                              : AppTheme.primaryRed)),
                ],
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.depositButton,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                  child: const Text(
                    'Депозит',
                    style: TextStyle(
                        color: Colors.black, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickFeatures() {
    final items = [
      _IconItem(icon: Icons.account_balance_wallet, label: 'Bybit Earn'),
      _IconItem(icon: Icons.group_add, label: 'Пригласить друзей'),
      _IconItem(icon: Icons.card_giftcard, label: 'Бонусный центр'),
      _IconItem(icon: Icons.sync_alt, label: 'Копитрейдинг'),
      _IconItem(icon: Icons.smart_toy, label: 'Трейдинг-бот'),
      _IconItem(icon: Icons.view_module, label: 'ByStarter'),
      _IconItem(icon: Icons.swap_horiz, label: 'Р2Р торговля'),
      _IconItem(icon: Icons.more_horiz, label: 'Ещё'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: GridView.count(
        crossAxisCount: 4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 24,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 0.75,
        children: items.map((it) => _IconCircle(item: it)).toList(),
      ),
    );
  }

  Widget _buildMarketsSection() {
    final filteredList = _filteredCryptoList;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _isLoading &&
              _cryptoList.isEmpty // Show loading only if no data is cached
          ? const Padding(
              padding: EdgeInsets.all(32.0),
              child: Center(child: CircularProgressIndicator()),
            )
          : Container(
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  // Main tabs - с горизонтальным скроллингом
                  Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _mainTabs.length,
                      itemBuilder: (context, index) {
                        final tab = _mainTabs[index];
                        final isSelected = tab == _selectedMainTab;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              final oldMainTab = _selectedMainTab;
                              _selectedMainTab = tab;
                              // При смене главной категории всегда выбираем первую подкатегорию
                              if (oldMainTab != tab) {
                                final newSubTabs = _subTabs;
                                _selectedSubTab = newSubTabs.first;
                              }
                            });
                            // Перезагружаем данные при смене главной категории
                            _loadCryptoData();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 14),
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(),
                            child: Text(
                              tab,
                              style: TextStyle(
                                color: isSelected
                                    ? AppTheme.textPrimary
                                    : AppTheme.textSecondary,
                                fontSize: 12.5,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Sub tabs - без разделения между ними
                  Container(
                    height: 40,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _subTabs.length,
                      itemBuilder: (context, index) {
                        final tab = _subTabs[index];
                        final isSelected = tab == _selectedSubTab;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedSubTab = tab;
                            });
                            // Переключаемся на кэшированные данные или загружаем
                            final cacheKey = '${_selectedMainTab}_$tab';
                            if (_dataCache.containsKey(cacheKey)) {
                              setState(() {
                                _cryptoList = _dataCache[cacheKey]!;
                                _isLoading = false;
                                // Для "Избранное" автоматически выбираем все монеты
                                if (_selectedMainTab == 'Избранное') {
                                  _selectedCoins.clear();
                                  _selectedCoins.addAll(_cryptoList
                                      .map((crypto) => crypto.id)
                                      .toSet());
                                }
                              });
                              // Обновляем в фоне
                              _loadCategoryData(tab, silent: false);
                            } else {
                              _loadCryptoData();
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  tab,
                                  style: TextStyle(
                                    color: isSelected
                                        ? AppTheme.textPrimary
                                        : AppTheme.textSecondary,
                                    fontSize: 11,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                                if (tab == 'Alpha') ...[
                                  const SizedBox(width: 4),
                                  const Icon(
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
                  // Для "Избранное": если есть сохраненные монеты - показываем список, иначе - карточки для выбора
                  if (_selectedMainTab == 'Избранное') ...[
                    // Проверяем, есть ли сохраненные монеты
                    if (_favoriteCoins.containsKey(_selectedSubTab) &&
                        _favoriteCoins[_selectedSubTab]!.isNotEmpty) ...[
                      // Показываем сохраненные монеты в виде списка (топ 5)
                      ...List.generate(
                        filteredList.length > 5 ? 5 : filteredList.length,
                        (index) {
                          final crypto = filteredList[index];
                          final isLast = index ==
                              (filteredList.length > 5
                                  ? 4
                                  : filteredList.length - 1);
                          return _buildCryptoItemInList(crypto, isLast);
                        },
                      ),
                      // Кнопка "Ещё →" внутри того же контейнера
                      if (filteredList.length > 5)
                        GestureDetector(
                          onTap: () {
                            if (widget.onNavigateToMarkets != null) {
                              widget.onNavigateToMarkets!();
                            } else {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const MarketsScreen(),
                                ),
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            alignment: Alignment.center,
                            child: Text(
                              'Ещё →',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                    ] else ...[
                      // Показываем карточки для выбора новых монет
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 1.9,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                          ),
                          itemCount:
                              filteredList.length > 6 ? 6 : filteredList.length,
                          itemBuilder: (context, index) {
                            final crypto = filteredList[index];
                            return _buildCryptoCardWithCheckbox(crypto);
                          },
                        ),
                      ),
                      // Кнопка "Добавить в Избранное"
                      if (filteredList.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: ElevatedButton(
                            onPressed: () async {
                              // Сохраняем выбранные монеты в избранное
                              if (_selectedCoins.isNotEmpty) {
                                final favoriteKey =
                                    _selectedSubTab; // Спот, Деривативы, TradFi
                                final selectedCryptoList = filteredList
                                    .where((crypto) =>
                                        _selectedCoins.contains(crypto.id))
                                    .toList();

                                if (!mounted) return;
                                setState(() {
                                  // Добавляем выбранные монеты к существующим (или создаем новый список)
                                  if (_favoriteCoins.containsKey(favoriteKey)) {
                                    // Объединяем, избегая дубликатов
                                    final existingIds =
                                        _favoriteCoins[favoriteKey]!
                                            .map((c) => c.id)
                                            .toSet();
                                    final newCoins = selectedCryptoList
                                        .where(
                                            (c) => !existingIds.contains(c.id))
                                        .toList();
                                    _favoriteCoins[favoriteKey]!
                                        .addAll(newCoins);
                                  } else {
                                    _favoriteCoins[favoriteKey] =
                                        selectedCryptoList;
                                  }
                                  _selectedCoins.clear();
                                });
                                // Сохраняем в локальное хранилище
                                await _saveFavoriteCoinsToLocal();
                                // Обновляем список для отображения
                                if (!mounted) return;
                                _loadCategoryData(_selectedSubTab);

                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Добавлено в избранное: ${selectedCryptoList.length} монет',
                                    ),
                                  ),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: AppTheme.depositButton,
                              elevation: 0,
                              minimumSize: const Size(double.infinity, 44),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              'Добавить в Избранное',
                              style: TextStyle(
                                color: AppTheme.depositButton,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ] else ...[
                    // Обычный список монет (до 5 штук)
                    if (filteredList.isEmpty && _searchQuery.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Center(
                          child: Text(
                            'Ничего не найдено',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      )
                    else
                      ...List.generate(
                        filteredList.length > 5 ? 5 : filteredList.length,
                        (index) {
                          final crypto = filteredList[index];
                          final isLast = index ==
                              (filteredList.length > 5
                                  ? 4
                                  : filteredList.length - 1);
                          return _buildCryptoItemInList(crypto, isLast);
                        },
                      ),
                    // Кнопка "Ещё →" внутри того же контейнера
                    if (filteredList.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          if (widget.onNavigateToMarkets != null) {
                            widget.onNavigateToMarkets!();
                          } else {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const MarketsScreen(),
                              ),
                            );
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          alignment: Alignment.center,
                          child: Text(
                            'Ещё →',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildCryptoItemInList(CryptoModel crypto, bool isLast) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(),
      child: Row(
        children: [
          // Icon - цветной круг или изображение
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _getCryptoColor(crypto.symbol),
              shape: BoxShape.circle,
            ),
            child: crypto.imageUrl != null
                ? ClipOval(
                    child: _buildCryptoImage(crypto),
                  )
                : Center(
                    child: Text(
                      crypto.symbol.substring(0, 1),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        crypto.pair,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    // Тег "10x" означает кредитное плечо ×10 (маржинальная/фьючерсная торговля)
                    // Показывается для спотовых монет (не опционы, не фьючерсы)
                    if (!crypto.symbol.contains('-') &&
                        (_selectedSubTab == 'Спот' ||
                            _selectedSubTab == 'Alpha' ||
                            _selectedSubTab == 'Деривативы' ||
                            _selectedSubTab == 'TradFi')) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.backgroundElevated,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '10x',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${_formatVolume(crypto.volume24h)} USDT',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          // Price and change
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatPrice(crypto.price),
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: crypto.isPositive
                      ? AppTheme.primaryGreen.withValues(alpha: 0.15)
                      : AppTheme.primaryRed.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${crypto.isPositive ? '+' : ''}${crypto.change24h.toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: crypto.isPositive
                        ? AppTheme.primaryGreen
                        : AppTheme.primaryRed,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Виджет для отображения монеты с чекбоксом (для режима "Избранное")
  // Виджет для отображения монеты в виде карточки с чекбоксом (для режима "Избранное")
  Widget _buildCryptoCardWithCheckbox(CryptoModel crypto) {
    final isSelected = _selectedCoins.contains(crypto.id);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedCoins.remove(crypto.id);
          } else {
            _selectedCoins.add(crypto.id);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF202020),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Название и цена с процентом
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Пара с разными цветами для base и quote
                  Row(
                    children: [
                      Text(
                        crypto.symbol,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (!crypto.symbol.contains('-')) ...[
                        const Text(
                          '/',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Text(
                          'USDT',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Цена и процент в одной строке
                  Row(
                    children: [
                      Text(
                        _formatPrice(crypto.price),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${crypto.isPositive ? '+' : ''}${crypto.change24h.toStringAsFixed(2)}%',
                        style: TextStyle(
                          color: crypto.isPositive
                              ? const Color(0xFF2ECC71)
                              : AppTheme.primaryRed,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Галочка
            Icon(
              isSelected ? Icons.check : Icons.radio_button_unchecked,
              color: isSelected
                  ? const Color(0xFFFFFFFF)
                  : const Color(0xFF141414),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCryptoImage(CryptoModel crypto) {
    return CachedNetworkImage(
      imageUrl: crypto.imageUrl!,
      width: 36,
      height: 36,
      fit: BoxFit.cover,
      placeholder: (context, url) => Center(
        child: Text(
          crypto.symbol.substring(0, 1),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      errorWidget: (context, url, error) => Center(
        child: Text(
          crypto.symbol.substring(0, 1),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      httpHeaders: const {
        'User-Agent': 'Mozilla/5.0',
      },
      maxHeightDiskCache: 200,
      maxWidthDiskCache: 200,
    );
  }

  Color _getCryptoColor(String symbol) {
    // Разные цвета для разных криптовалют
    final colors = {
      'BTC': const Color(0xFFF7931A), // Bitcoin orange
      'ETH': const Color(0xFF627EEA), // Ethereum blue
      'BNB': const Color(0xFFF3BA2F), // BNB yellow
      'SOL': const Color(0xFF9945FF), // Solana purple
      'XRP': const Color(0xFF23292F), // Ripple dark
      'ADA': const Color(0xFF0033AD), // Cardano blue
      'DOGE': const Color(0xFFC2A633), // Dogecoin yellow
      'MATIC': const Color(0xFF8247E5), // Polygon purple
    };
    return colors[symbol] ?? AppTheme.primaryGreen;
  }

  String _formatPrice(double price) {
    if (price >= 1000) {
      return price.toStringAsFixed(2);
    } else if (price >= 1) {
      return price.toStringAsFixed(2);
    } else if (price >= 0.01) {
      return price.toStringAsFixed(4);
    } else {
      return price.toStringAsFixed(6);
    }
  }

  String _formatVolume(double volume) {
    if (volume >= 1000000) {
      return '${(volume / 1000000).toStringAsFixed(2)}M';
    } else if (volume >= 1000) {
      return '${(volume / 1000).toStringAsFixed(2)}K';
    }
    return volume.toStringAsFixed(2);
  }
}

class _IconItem {
  final IconData icon;
  final String label;
  _IconItem({required this.icon, required this.label});
}

class _IconCircle extends StatelessWidget {
  final _IconItem item;
  const _IconCircle({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppTheme.backgroundCard,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black45,
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            onPressed: () {
              if (item.label == 'Р2Р торговля') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const P2PTradingScreen(),
                  ),
                );
              }
            },
            icon: Icon(item.icon, color: Colors.white70, size: 24),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: Text(
            item.label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}
