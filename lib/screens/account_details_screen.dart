import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/crypto_api_service.dart';
import '../services/mock_portfolio_service.dart';
import 'transfer_screen.dart';

class AccountDetailsScreen extends StatefulWidget {
  final String accountType; // 'FUND' или 'UNIFIED'
  final String accountName; // 'Финансирования' или 'Единый торговый'

  const AccountDetailsScreen({
    super.key,
    required this.accountType,
    required this.accountName,
  });

  @override
  State<AccountDetailsScreen> createState() => _AccountDetailsScreenState();
}

class _AccountDetailsScreenState extends State<AccountDetailsScreen>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  List<Map<String, dynamic>> _coinsList = [];
  double _totalUsd = 0.0;
  double _totalBtc = 0.0;
  double _availableUsd = 0.0;
  double _usedUsd = 0.0;
  String _selectedTab = 'Криптовалюта'; // 'Криптовалюта' или 'Фиат'
  bool _hideZeroBalances = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAccountCoins();
    // Слушаем изменения баланса в реальном времени (только для UNIFIED)
    if (widget.accountType == 'UNIFIED') {
      MockPortfolioService.balanceNotifier.addListener(_onBalanceChanged);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.accountType == 'UNIFIED') {
      MockPortfolioService.balanceNotifier.removeListener(_onBalanceChanged);
    }
    super.dispose();
  }

  void _onBalanceChanged() {
    // Обновляем баланс при изменении P&L в реальном времени без полной перезагрузки
    if (mounted && MockPortfolioService.useMockData) {
      // Обновляем только данные без показа индикатора загрузки
      // Цены уже обновлены в trade_screen перед вызовом setUnrealizedPnl
      setState(() {
        // Обновляем общий баланс напрямую
        if (widget.accountType == 'UNIFIED') {
          _totalUsd = MockPortfolioService.unifiedTradingBalance;
          final btcPrice = MockPortfolioService.btcPrice;
          _totalBtc = btcPrice > 0 ? _totalUsd / btcPrice : 0.0;
          _availableUsd = _totalUsd;

          // Обновляем список монет с актуальными ценами
          final allCoins = MockPortfolioService.getCoinsList();
          _coinsList = allCoins
              .where((coin) => coin['accountType'] == widget.accountType)
              .toList();
        } else if (widget.accountType == 'FUND') {
          // Для Funding аккаунта также обновляем баланс
          final allCoins = MockPortfolioService.getCoinsList();
          _coinsList = allCoins
              .where((coin) => coin['accountType'] == widget.accountType)
              .toList();

          _totalUsd = _coinsList.fold<double>(
            0.0,
            (sum, coin) => sum + (coin['usdValue'] as num? ?? 0).toDouble(),
          );
          final btcPrice = MockPortfolioService.btcPrice;
          _totalBtc = btcPrice > 0 ? _totalUsd / btcPrice : 0.0;
          _availableUsd = _totalUsd;
        }
      });
    }
  }

  Future<void> _loadAccountCoins() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (MockPortfolioService.useMockData) {
        // Обновляем цены асинхронно (не ждем)
        MockPortfolioService.refreshPrices();

        // Моковые данные - фильтруем по типу аккаунта
        // Используем уже обновленные цены из кэша
        // Убираем задержку для быстрого обновления
        final allCoins = MockPortfolioService.getCoinsList();
        _coinsList = allCoins
            .where((coin) => coin['accountType'] == widget.accountType)
            .toList();

        // Если нет монет для этого аккаунта, добавляем примерные
        if (_coinsList.isEmpty) {
          final solPrice = MockPortfolioService.solPrice;
          final ltcPrice = MockPortfolioService.ltcPrice;

          if (widget.accountType == 'FUND') {
            // Funding аккаунт - USDT для спот-торговли
            // Используем availableUsd, который возвращает initialUsdt
            final usdtBalance = MockPortfolioService.availableUsd;
            _coinsList = [
              {
                'coin': 'USDT',
                'equity': usdtBalance,
                'usdValue': usdtBalance, // USDT = 1 USD
                'accountType': 'FUND',
              },
            ];
          } else if (widget.accountType == 'UNIFIED') {
            // Используем текущие цены из кэша (уже обновлены выше)
            _coinsList = [
              {
                'coin': 'SOL',
                'equity': 15.0,
                'usdValue': 15.0 * solPrice,
                'accountType': 'UNIFIED',
              },
              {
                'coin': 'LTC',
                'equity': 27.21,
                'usdValue': 27.21 * ltcPrice,
                'accountType': 'UNIFIED',
              },
            ];
          }
        }
      } else {
        // Реальные данные из API
        Map<String, dynamic> accountData;
        if (widget.accountType == 'FUND') {
          accountData = await CryptoApiService.getFundingBalance();
        } else {
          accountData = await CryptoApiService.getUnifiedTradingBalance();
        }

        _coinsList = [];
        if (accountData['list'] != null &&
            (accountData['list'] as List).isNotEmpty) {
          final account = accountData['list'][0];
          if (account['coin'] != null) {
            for (var coin in account['coin']) {
              final equity =
                  double.tryParse(coin['equity']?.toString() ?? '0') ?? 0.0;
              final usdValue =
                  double.tryParse(coin['usdValue']?.toString() ?? '0') ?? 0.0;

              // Показываем только монеты с балансом > 0
              if (equity > 0 || usdValue > 0) {
                _coinsList.add({
                  'coin': coin['coin']?.toString() ?? '',
                  'equity': equity,
                  'usdValue': usdValue,
                  'accountType': widget.accountType,
                });
              }
            }
          }
        }
      }

      // Вычисляем общую сумму и BTC
      // Для UNIFIED аккаунта используем unifiedTradingBalance, который включает нереализованный P&L
      if (widget.accountType == 'UNIFIED' && MockPortfolioService.useMockData) {
        _totalUsd = MockPortfolioService.unifiedTradingBalance;
      } else {
        _totalUsd = _coinsList.fold<double>(
          0.0,
          (sum, coin) => sum + (coin['usdValue'] as num? ?? 0).toDouble(),
        );
      }

      // Вычисляем BTC эквивалент используя текущую цену BTC
      final btcPrice = MockPortfolioService.btcPrice;
      _totalBtc = btcPrice > 0 ? _totalUsd / btcPrice : 0.0;

      // Для Funding аккаунта available = total, used = 0
      // Для Unified может быть иначе
      _availableUsd = _totalUsd;
      _usedUsd = 0.0;

      // Сортируем по стоимости (от большего к меньшему)
      _coinsList.sort((a, b) {
        final aValue = (a['usdValue'] as num? ?? 0).toDouble();
        final bValue = (b['usdValue'] as num? ?? 0).toDouble();
        return bValue.compareTo(aValue);
      });
    } catch (e) {
      _coinsList = [];
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Фильтруем монеты по выбранной вкладке и нулевым балансам
    final filteredCoins = _coinsList.where((coin) {
      if (_hideZeroBalances) {
        final equity = (coin['equity'] as num? ?? 0).toDouble();
        if (equity <= 0) return false;
      }
      // Пока показываем только криптовалюту
      return _selectedTab == 'Криптовалюта';
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.accountName,
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          // Кнопка перевода (только для Funding аккаунта)
          if (widget.accountType == 'FUND')
            IconButton(
              icon: const Icon(Icons.swap_horiz, color: AppTheme.textPrimary),
              onPressed: () {
                Navigator.of(context)
                    .push(
                  MaterialPageRoute(
                    builder: (context) => const TransferScreen(),
                  ),
                )
                    .then((result) {
                  // Обновляем данные после перевода через balanceNotifier
                  // Не нужно вызывать _loadAccountCoins(), так как balanceNotifier
                  // автоматически обновит данные через _onBalanceChanged()
                });
              },
              tooltip: 'Перевести',
            ),
          IconButton(
            icon: const Icon(Icons.help_outline, color: AppTheme.textSecondary),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.description_outlined,
                color: AppTheme.textSecondary),
            onPressed: () {},
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Общие активы
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Общие активы',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '\$${_totalUsd.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                'USD',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.arrow_drop_down,
                              color: AppTheme.textSecondary,
                              size: 20,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '≈ ${_formatBtc(_totalBtc)} BTC',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.info_outline,
                              color: AppTheme.textSecondary,
                              size: 16,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // Доступный баланс и Используется
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Доступный баланс',
                                    style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '\$${_availableUsd.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '≈ ${_formatBtc(_availableUsd / (MockPortfolioService.btcPrice > 0 ? MockPortfolioService.btcPrice : 91000))} BTC',
                                    style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'Используется',
                                    style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '\$${_usedUsd.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '≈ ${_formatBtc(_usedUsd / (MockPortfolioService.btcPrice > 0 ? MockPortfolioService.btcPrice : 91000))} BTC',
                                    style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Кнопки действий
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildActionButton('Депозит', AppTheme.depositButton,
                            Icons.arrow_downward),
                        _buildActionButton('Вывод средств',
                            AppTheme.backgroundCard, Icons.arrow_upward),
                        _buildActionButton('Перевод', AppTheme.backgroundCard,
                            Icons.swap_horiz, onTap: () {
                          Navigator.of(context)
                              .push(
                            MaterialPageRoute(
                              builder: (context) => const TransferScreen(),
                            ),
                          )
                              .then((result) {
                            // Обновляем данные после перевода
                            if (result == true) {
                              _loadAccountCoins();
                            }
                          });
                        }),
                        _buildActionButton('Конвертация',
                            AppTheme.backgroundCard, Icons.autorenew),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Баннер HODL
                  if (widget.accountType == 'FUND')
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundCard,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color:
                                  AppTheme.primaryGreen.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.attach_money,
                              color: AppTheme.primaryGreen,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'HODL: храните USDT и получайте до 3.85% APR!',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  // Табы и фильтры
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  _buildTabButton('Криптовалюта',
                                      _selectedTab == 'Криптовалюта'),
                                  const SizedBox(width: 16),
                                  _buildTabButton(
                                      'Фиат', _selectedTab == 'Фиат'),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.refresh,
                                  color: AppTheme.textSecondary),
                              onPressed: _loadAccountCoins,
                            ),
                            IconButton(
                              icon: const Icon(Icons.search,
                                  color: AppTheme.textSecondary),
                              onPressed: () {},
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Чекбокс "Скрыть нулевые балансы"
                        Row(
                          children: [
                            Checkbox(
                              value: _hideZeroBalances,
                              onChanged: (value) {
                                setState(() {
                                  _hideZeroBalances = value ?? false;
                                });
                              },
                              activeColor: AppTheme.primaryGreen,
                            ),
                            Text(
                              'Скрыть нулевые балансы',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Список монет
                  if (filteredCoins.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 64,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Нет активов',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filteredCoins.length,
                      itemBuilder: (context, index) {
                        final coin = filteredCoins[index];
                        final coinName = coin['coin']?.toString() ?? '';
                        final equity = (coin['equity'] as num? ?? 0).toDouble();
                        final usdValue =
                            (coin['usdValue'] as num? ?? 0).toDouble();

                        return _buildCoinItem(coinName, equity, usdValue);
                      },
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildActionButton(String label, Color backgroundColor, IconData icon,
      {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppTheme.textPrimary, size: 24),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String label, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTab = label;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
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
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildCoinItem(String coinName, double equity, double usdValue) {
    // Получаем полное название монеты
    final coinFullName = _getCoinFullName(coinName);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.borderColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Логотип монеты
          _buildCoinLogo(coinName),
          const SizedBox(width: 12),
          // Информация о монете
          Expanded(
            child: Column(
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
                const SizedBox(height: 2),
                Text(
                  coinFullName,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // Баланс
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${_formatCoinAmount(equity, coinName)}',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '≈ \$${usdValue.toStringAsFixed(2)}',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatBtc(double btc) {
    if (btc == 0.0) return '0.00000000';
    if (btc < 0.00000001) {
      return btc.toStringAsFixed(10);
    } else {
      return btc.toStringAsFixed(8);
    }
  }

  String _formatCoinAmount(double amount, String coinName) {
    if (amount == 0.0) return '0.00';

    // Для BTC и ETH показываем больше знаков после запятой
    if (coinName == 'BTC') {
      return amount.toStringAsFixed(8);
    } else if (coinName == 'ETH') {
      return amount.toStringAsFixed(6);
    } else if (coinName == 'USDT' || coinName == 'USDC') {
      return amount.toStringAsFixed(2);
    } else if (amount >= 1) {
      return amount.toStringAsFixed(4);
    } else if (amount >= 0.01) {
      return amount.toStringAsFixed(6);
    } else {
      return amount.toStringAsFixed(8);
    }
  }

  String _getCoinFullName(String coinName) {
    final names = {
      'BTC': 'Bitcoin',
      'ETH': 'Ethereum',
      'USDT': 'Tether USDT',
      'USDC': 'USD Coin',
      'XRP': 'XRP',
      'TRX': 'TRON',
      'BNB': 'BNB',
      'SOL': 'Solana',
    };
    return names[coinName] ?? coinName;
  }

  Widget _buildCoinLogo(String coinName) {
    // Цвета для разных монет
    Color logoColor;
    switch (coinName) {
      case 'BTC':
        logoColor = Colors.orange;
        break;
      case 'ETH':
        logoColor = Colors.white;
        break;
      case 'USDT':
        logoColor = const Color(0xFF26A17B);
        break;
      case 'USDC':
        logoColor = Colors.blue;
        break;
      case 'XRP':
        logoColor = Colors.white;
        break;
      case 'TRX':
        logoColor = Colors.red;
        break;
      default:
        logoColor = AppTheme.primaryGreen;
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: logoColor.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          coinName.length > 4 ? coinName.substring(0, 4) : coinName,
          style: TextStyle(
            color: logoColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
