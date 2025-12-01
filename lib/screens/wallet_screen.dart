import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/crypto_api_service.dart';
import '../services/auth_service.dart';
import '../services/mock_portfolio_service.dart';
import 'login_screen.dart';
import 'analysis_screen.dart';
import 'account_details_screen.dart';
import 'transfer_screen.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with WidgetsBindingObserver {
  String _selectedTab = 'Аккаунт';
  bool _balanceVisible = true;
  bool _isLoading = true;

  // Данные аккаунта
  String _userEmail = 'user@****';
  double _totalUsd = 0.0;
  double _totalBtc = 0.0;
  double _availableUsd = 0.0;
  double _usedUsd = 0.0;
  double _fundingBalance = 0.0;
  double _unifiedTradingBalance = 0.0;
  double _pnlToday = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserData();
    _loadAccountData();
    // Слушаем изменения баланса в реальном времени
    MockPortfolioService.balanceNotifier.addListener(_onBalanceChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MockPortfolioService.balanceNotifier.removeListener(_onBalanceChanged);
    super.dispose();
  }

  void _onBalanceChanged() {
    // Обновляем баланс при изменении P&L в реальном времени без полной перезагрузки
    if (mounted && MockPortfolioService.useMockData) {
      // Обновляем все балансы без показа индикатора загрузки
      setState(() {
        _unifiedTradingBalance = MockPortfolioService.unifiedTradingBalance;
        _totalUsd = MockPortfolioService.totalUsd;
        _totalBtc = MockPortfolioService.totalBtc;
        _availableUsd = MockPortfolioService.availableUsd;
        _usedUsd = MockPortfolioService.usedUsd;
        _fundingBalance = MockPortfolioService.fundingBalance;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Обновляем данные при возврате приложения в активное состояние
    if (state == AppLifecycleState.resumed) {
      _loadAccountData();
    }
  }

  void _loadUserData() {
    final user = AuthService().currentUser;
    if (user != null) {
      setState(() {
        _userEmail = user.email ?? 'user@****';
      });
    }
  }

  Future<void> _loadAccountData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    // Используем моковые данные, если включен флаг
    if (MockPortfolioService.useMockData) {
      // Обновляем цены асинхронно (не ждем)
      MockPortfolioService.refreshPrices();

      // Убираем задержку для быстрого обновления
      if (!mounted) return;
      setState(() {
        _totalUsd = MockPortfolioService.totalUsd;
        _totalBtc = MockPortfolioService.totalBtc;
        _availableUsd = MockPortfolioService.availableUsd;
        _usedUsd = MockPortfolioService.usedUsd;
        _fundingBalance = MockPortfolioService.fundingBalance;
        _unifiedTradingBalance = MockPortfolioService.unifiedTradingBalance;
        _pnlToday = MockPortfolioService.pnlToday;
        _isLoading = false;
      });
      return;
    }

    // Реальные данные из API
    try {
      // Загружаем общий баланс
      final totalBalance = await CryptoApiService.getTotalBalance();

      // Загружаем балансы отдельных аккаунтов
      final funding = await CryptoApiService.getFundingBalance();
      final unified = await CryptoApiService.getUnifiedTradingBalance();

      // Парсим Funding баланс
      double fundingUsd = 0.0;
      if (funding['list'] != null && (funding['list'] as List).isNotEmpty) {
        final account = funding['list'][0];
        if (account['coin'] != null) {
          for (var coin in account['coin']) {
            final usdValue =
                double.tryParse(coin['usdValue']?.toString() ?? '0') ?? 0.0;
            fundingUsd += usdValue;
          }
        }
      }

      // Парсим Unified Trading баланс
      double unifiedUsd = 0.0;
      if (unified['list'] != null && (unified['list'] as List).isNotEmpty) {
        final account = unified['list'][0];
        if (account['coin'] != null) {
          for (var coin in account['coin']) {
            final usdValue =
                double.tryParse(coin['usdValue']?.toString() ?? '0') ?? 0.0;
            unifiedUsd += usdValue;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _totalUsd = totalBalance['totalUsd'] ?? 0.0;
        _totalBtc = totalBalance['totalBtc'] ?? 0.0;
        _availableUsd = totalBalance['availableUsd'] ?? 0.0;
        _usedUsd = totalBalance['usedUsd'] ?? 0.0;
        _fundingBalance = fundingUsd;
        _unifiedTradingBalance = unifiedUsd;
        _isLoading = false;
      });
    } catch (e) {
      // В случае ошибки показываем нулевые значения
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundDark,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            // Avatar
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.backgroundCard,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person,
                color: Colors.blue,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            // Email
            Expanded(
              child: Row(
                children: [
                  Text(
                    _userEmail,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.arrow_drop_down,
                      color: AppTheme.textSecondary,
                      size: 20,
                    ),
                    onSelected: (value) {
                      if (value == 'logout') {
                        _handleLogout();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'logout',
                        child: Text('Выйти из аккаунта'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadAccountData,
        color: AppTheme.primaryGreen,
        backgroundColor: AppTheme.backgroundCard,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Total Assets Section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Общие активы с иконкой глаза
                    Row(
                      children: [
                        Text(
                          'Общие активы',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _balanceVisible = !_balanceVisible;
                            });
                          },
                          child: Icon(
                            _balanceVisible
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: AppTheme.textSecondary,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Main balance
                    _isLoading
                        ? const SizedBox(
                            height: 50,
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _balanceVisible
                                    ? _formatBalance(_totalUsd)
                                    : '****',
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 32,
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
                                    fontWeight: FontWeight.normal,
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
                    const SizedBox(height: 8),
                    // BTC equivalent
                    _isLoading
                        ? const SizedBox.shrink()
                        : Row(
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
                    const SizedBox(height: 12),
                    // P&L за сегодня
                    _isLoading
                        ? const SizedBox.shrink()
                        : GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const AnalysisScreen(),
                                ),
                              );
                            },
                            child: Row(
                              children: [
                                Text(
                                  'P&L за сегодня ',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  '${_formatBalance(_pnlToday)} USD(${_pnlToday >= 0 ? '+' : ''}${_pnlToday.toStringAsFixed(2)}%)',
                                  style: TextStyle(
                                    color: _pnlToday >= 0
                                        ? AppTheme.primaryGreen
                                        : AppTheme.primaryRed,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.arrow_forward_ios,
                                  color: AppTheme.textSecondary,
                                  size: 14,
                                ),
                              ],
                            ),
                          ),
                    const SizedBox(height: 20),
                    // Available and Used Balance
                    _isLoading
                        ? const SizedBox.shrink()
                        : Row(
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
                                      '${_formatBalance(_availableUsd)} USD',
                                      style: TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
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
                                      '${_formatBalance(_usedUsd)} USD',
                                      style: TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
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
              const SizedBox(height: 24),
              // Quick Action Buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildActionButton(
                      'Депозит',
                      AppTheme.depositButton,
                      Icons.arrow_downward,
                    ),
                    _buildActionButton(
                      'Вывод средств',
                      AppTheme.backgroundCard,
                      Icons.arrow_upward,
                    ),
                    _buildActionButton(
                      'Перевод',
                      AppTheme.backgroundCard,
                      Icons.swap_horiz,
                      onTap: () {
                        Navigator.of(context)
                            .push(
                          MaterialPageRoute(
                            builder: (context) => const TransferScreen(),
                          ),
                        )
                            .then((result) {
                          // Обновление происходит автоматически через balanceNotifier
                          // после перевода в transferBetweenAccounts()
                        });
                      },
                    ),
                    _buildActionButton(
                      'Конвертация',
                      AppTheme.backgroundCard,
                      Icons.autorenew,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Account and Asset Tabs
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _buildTabButton('Аккаунт', _selectedTab == 'Аккаунт'),
                    const SizedBox(width: 16),
                    _buildTabButton('Актив', _selectedTab == 'Актив'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Financial Accounts List
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _buildAccountItem(
                      'Финансирования',
                      _isLoading
                          ? 'Загрузка...'
                          : '${_formatBalance(_fundingBalance)} USD',
                    ),
                    const SizedBox(height: 12),
                    _buildAccountItem(
                      'Единый торговый',
                      _isLoading
                          ? 'Загрузка...'
                          : '${_formatBalance(_unifiedTradingBalance)} USD',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
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
            child: Icon(
              icon,
              color: AppTheme.textPrimary,
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
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

  Widget _buildAccountItem(String label, String amount) {
    return GestureDetector(
      onTap: () {
        // Определяем тип аккаунта
        String accountType;
        if (label == 'Финансирования') {
          accountType = 'FUND';
        } else {
          accountType = 'UNIFIED';
        }

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => AccountDetailsScreen(
              accountType: accountType,
              accountName: label,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.backgroundCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            Row(
              children: [
                Text(
                  amount,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: AppTheme.textSecondary,
                  size: 16,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatBalance(double balance) {
    if (balance == 0.0) return '0.00';
    if (balance.abs() < 0.01) {
      return balance.toStringAsFixed(8);
    } else if (balance.abs() < 1) {
      return balance.toStringAsFixed(4);
    } else {
      // Выводим полную цену без сокращений K и M
      return balance.toStringAsFixed(2);
    }
  }

  String _formatBtc(double btc) {
    if (btc == 0.0) return '0.00000000';
    if (btc < 0.00000001) {
      return btc.toStringAsFixed(10);
    } else {
      return btc.toStringAsFixed(8);
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.backgroundCard,
        title: Text(
          'Выход из аккаунта',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          'Вы уверены, что хотите выйти?',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Отмена',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Выйти',
              style: TextStyle(color: AppTheme.primaryRed),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await AuthService().signOut();
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка выхода: ${e.toString()}'),
              backgroundColor: AppTheme.primaryRed,
            ),
          );
        }
      }
    }
  }
}
