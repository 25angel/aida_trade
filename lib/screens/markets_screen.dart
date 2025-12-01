import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/crypto_model.dart';
import '../services/crypto_api_service.dart';
import '../widgets/crypto_list_item.dart';

class MarketsScreen extends StatefulWidget {
  final Map<String, List<CryptoModel>>? favoriteCoins;
  final Function(String)? onNavigateToTrade;

  const MarketsScreen({
    super.key,
    this.favoriteCoins,
    this.onNavigateToTrade,
  });

  @override
  State<MarketsScreen> createState() => _MarketsScreenState();
}

class _MarketsScreenState extends State<MarketsScreen> {
  String _selectedMainTab = 'Популярные';
  String _selectedSubTab = 'Спот';
  String _selectedCurrency = 'USDT';
  String _selectedFilter = 'Все';
  String _searchQuery = '';
  List<CryptoModel> _cryptoList = [];
  bool _isLoading = true;

  // Сортировка
  String? _sortColumn; // 'pair', 'volume', 'price', 'change'
  bool _sortAscending = true;

  final List<String> _mainTabs = [
    'Избранное',
    'Популярные',
    'Премаркет',
    'Новые',
    'Активные монеты',
    'Оборот',
    'Возможности'
  ];

  final List<String> _subTabs = ['Спот', 'Alpha', 'Деривативы', 'TradFi'];

  final List<String> _currencies = [
    'USDT',
    'USDC',
    'USDE',
    'MNT',
    'USD1',
    'EUR',
    'BRL',
    'PLN'
  ];
  final List<String> _filters = ['Все', 'Новое', 'Популярно', 'xStocks'];

  @override
  void initState() {
    super.initState();
    _loadCryptoData();
  }

  @override
  void didUpdateWidget(MarketsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.favoriteCoins != widget.favoriteCoins) {
      _loadCryptoData();
    }
  }

  Future<void> _loadCryptoData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      List<CryptoModel> data;

      if (_selectedMainTab == 'Избранное') {
        final favoriteKey = _selectedSubTab;
        if (widget.favoriteCoins != null &&
            widget.favoriteCoins!.containsKey(favoriteKey) &&
            widget.favoriteCoins![favoriteKey]!.isNotEmpty) {
          data = widget.favoriteCoins![favoriteKey]!;
        } else {
          data = [];
        }
      } else {
        // Маппинг табов на категории API
        String mainCategory = 'Популярные';
        if (_selectedMainTab == 'Премаркет') {
          mainCategory = 'Новые';
        } else if (_selectedMainTab == 'Новые') {
          mainCategory = 'Новые';
        } else if (_selectedMainTab == 'Активные монеты') {
          mainCategory = 'Активные монеты';
        } else if (_selectedMainTab == 'Оборот') {
          mainCategory = 'Лидеры'; // Используем Лидеры для оборота
        } else if (_selectedMainTab == 'Возможности') {
          mainCategory = 'Популярные'; // Используем Популярные для возможностей
        }

        data = await CryptoApiService.getMarketsByCategory(
          mainCategory: mainCategory,
          subCategory: _selectedSubTab,
          perPage: 50,
        );
      }

      // Фильтрация по валюте
      if (_selectedCurrency != 'USDT') {
        data = data.where((coin) {
          return coin.pair.endsWith(_selectedCurrency);
        }).toList();
      }

      // Фильтрация по поисковому запросу
      if (_searchQuery.isNotEmpty) {
        data = data.where((coin) {
          return coin.pair.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              coin.symbol.toLowerCase().contains(_searchQuery.toLowerCase());
        }).toList();
      }

      // Применяем сортировку
      if (_sortColumn != null) {
        data = _sortData(data, _sortColumn!, _sortAscending);
      }

      if (!mounted) return;
      setState(() {
        _cryptoList = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<CryptoModel> _sortData(
      List<CryptoModel> data, String column, bool ascending) {
    final sorted = List<CryptoModel>.from(data);

    switch (column) {
      case 'pair':
        sorted.sort((a, b) =>
            ascending ? a.pair.compareTo(b.pair) : b.pair.compareTo(a.pair));
        break;
      case 'volume':
        sorted.sort((a, b) => ascending
            ? a.turnover24h.compareTo(b.turnover24h)
            : b.turnover24h.compareTo(a.turnover24h));
        break;
      case 'price':
        sorted.sort((a, b) => ascending
            ? a.price.compareTo(b.price)
            : b.price.compareTo(a.price));
        break;
      case 'change':
        sorted.sort((a, b) => ascending
            ? a.change24h.compareTo(b.change24h)
            : b.change24h.compareTo(a.change24h));
        break;
    }

    return sorted;
  }

  void _handleSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        // Если та же колонка - меняем направление
        _sortAscending = !_sortAscending;
      } else {
        // Новая колонка - сортируем по возрастанию
        _sortColumn = column;
        _sortAscending = true;
      }
    });
    // Применяем сортировку к текущему списку
    _cryptoList = _sortData(_cryptoList, _sortColumn!, _sortAscending);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            // Search bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.backgroundCard,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, color: AppTheme.textSecondary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      style:
                          TextStyle(color: AppTheme.textPrimary, fontSize: 14),
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
                        setState(() {
                          _searchQuery = value;
                        });
                        _loadCryptoData();
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
                        _loadCryptoData();
                      },
                      child: Icon(Icons.close,
                          color: AppTheme.textSecondary, size: 18),
                    ),
                  ],
                ],
              ),
            ),
            // Main tabs
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _mainTabs.length,
                itemBuilder: (context, index) {
                  final tab = _mainTabs[index];
                  final isSelected = tab == _selectedMainTab;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedMainTab = tab;
                      });
                      _loadCryptoData();
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 16),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color:
                                isSelected ? Colors.white : Colors.transparent,
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
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Sub tabs with dropdowns
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 36,
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
                              _loadCryptoData();
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
                                  Flexible(
                                    child: Text(
                                      tab,
                                      style: TextStyle(
                                        color: isSelected
                                            ? AppTheme.textPrimary
                                            : AppTheme.textSecondary,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                        fontSize: 11,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (tab == 'Alpha') ...[
                                    const SizedBox(width: 3),
                                    const Icon(Icons.local_fire_department,
                                        color: AppTheme.primaryRed, size: 11),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Currency dropdown
                  GestureDetector(
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: AppTheme.backgroundDark,
                        builder: (context) => Container(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: _currencies.map((currency) {
                              return ListTile(
                                title: Text(
                                  currency,
                                  style: TextStyle(color: AppTheme.textPrimary),
                                ),
                                trailing: _selectedCurrency == currency
                                    ? Icon(Icons.check,
                                        color: AppTheme.primaryGreen)
                                    : null,
                                onTap: () {
                                  setState(() {
                                    _selectedCurrency = currency;
                                  });
                                  Navigator.pop(context);
                                  _loadCryptoData();
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundCard,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _selectedCurrency,
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(Icons.arrow_drop_down,
                              color: AppTheme.textSecondary, size: 16),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Filter dropdown
                  GestureDetector(
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: AppTheme.backgroundDark,
                        builder: (context) => Container(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: _filters.map((filter) {
                              return ListTile(
                                title: Text(
                                  filter,
                                  style: TextStyle(color: AppTheme.textPrimary),
                                ),
                                trailing: _selectedFilter == filter
                                    ? Icon(Icons.check,
                                        color: AppTheme.primaryGreen)
                                    : null,
                                onTap: () {
                                  setState(() {
                                    _selectedFilter = filter;
                                  });
                                  Navigator.pop(context);
                                  _loadCryptoData();
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundCard,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _selectedFilter,
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(Icons.arrow_drop_down,
                              color: AppTheme.textSecondary, size: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Header row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        // Торговые пары
                        Flexible(
                          child: GestureDetector(
                            onTap: () => _handleSort('pair'),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    'Торговые пары',
                                    style: TextStyle(
                                      color: _sortColumn == 'pair'
                                          ? AppTheme.textPrimary
                                          : AppTheme.textSecondary,
                                      fontSize: 10,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Icon(
                                  _sortColumn == 'pair'
                                      ? (_sortAscending
                                          ? Icons.arrow_upward
                                          : Icons.arrow_downward)
                                      : Icons.swap_vert,
                                  color: _sortColumn == 'pair'
                                      ? AppTheme.textPrimary
                                      : AppTheme.textSecondary,
                                  size: 12,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '/',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Объем
                        Flexible(
                          child: GestureDetector(
                            onTap: () => _handleSort('volume'),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Объем',
                                  style: TextStyle(
                                    color: _sortColumn == 'volume'
                                        ? AppTheme.textPrimary
                                        : AppTheme.textSecondary,
                                    fontSize: 10,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Icon(
                                  _sortColumn == 'volume'
                                      ? (_sortAscending
                                          ? Icons.arrow_upward
                                          : Icons.arrow_downward)
                                      : Icons.swap_vert,
                                  color: _sortColumn == 'volume'
                                      ? AppTheme.textPrimary
                                      : AppTheme.textSecondary,
                                  size: 12,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: () => _handleSort('price'),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Цена',
                            style: TextStyle(
                              color: _sortColumn == 'price'
                                  ? AppTheme.textPrimary
                                  : AppTheme.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Icon(
                            _sortColumn == 'price'
                                ? (_sortAscending
                                    ? Icons.arrow_upward
                                    : Icons.arrow_downward)
                                : Icons.swap_vert,
                            color: _sortColumn == 'price'
                                ? AppTheme.textPrimary
                                : AppTheme.textSecondary,
                            size: 13,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: () => _handleSort('change'),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              'Изменение, 24ч',
                              style: TextStyle(
                                color: _sortColumn == 'change'
                                    ? AppTheme.textPrimary
                                    : AppTheme.textSecondary,
                                fontSize: 10,
                              ),
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            _sortColumn == 'change'
                                ? (_sortAscending
                                    ? Icons.arrow_upward
                                    : Icons.arrow_downward)
                                : Icons.swap_vert,
                            color: _sortColumn == 'change'
                                ? AppTheme.textPrimary
                                : AppTheme.textSecondary,
                            size: 12,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Crypto list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _cryptoList.length,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemBuilder: (context, index) {
                        final crypto = _cryptoList[index];
                        return CryptoListItem(
                          crypto: crypto,
                          index: index + 1,
                          isNew: _selectedMainTab == 'Новые' ||
                              _selectedFilter == 'Новое',
                          showFireIcon: _selectedFilter == 'Популярно' ||
                              crypto.turnover24h > 50000000,
                          onTap: () {
                            if (widget.onNavigateToTrade != null) {
                              widget.onNavigateToTrade!(crypto.pair);
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
