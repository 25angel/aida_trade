import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/crypto_api_service.dart';
import '../services/mock_portfolio_service.dart';

class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  String _fromAccount = 'FUND'; // 'FUND' или 'UNIFIED'
  String _toAccount = 'UNIFIED'; // 'FUND' или 'UNIFIED'
  String _selectedCoin = 'USDT';
  final TextEditingController _amountController = TextEditingController();
  double _availableBalance = 0.0;
  bool _isLoading = false;
  bool _isTransferring = false;

  @override
  void initState() {
    super.initState();
    _loadAvailableBalance();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailableBalance() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (MockPortfolioService.useMockData) {
        if (_fromAccount == 'FUND') {
          _availableBalance = MockPortfolioService.availableUsd;
        } else {
          _availableBalance = MockPortfolioService.unifiedTradingUsd;
        }
      } else {
        Map<String, dynamic> accountData;
        if (_fromAccount == 'FUND') {
          accountData = await CryptoApiService.getFundingBalance();
        } else {
          accountData = await CryptoApiService.getUnifiedTradingBalance();
        }

        double availableUsdt = 0.0;
        if (accountData['list'] != null &&
            (accountData['list'] as List).isNotEmpty) {
          final account = accountData['list'][0];
          if (account['coin'] != null) {
            for (var coin in account['coin']) {
              final coinName = coin['coin']?.toString() ?? '';
              if (coinName == 'USDT') {
                final equity =
                    double.tryParse(coin['equity']?.toString() ?? '0') ?? 0.0;
                availableUsdt = equity;
                break;
              }
            }
          }
        }
        _availableBalance = availableUsdt;
      }
    } catch (e) {
      _availableBalance = 0.0;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _swapAccounts() {
    setState(() {
      final temp = _fromAccount;
      _fromAccount = _toAccount;
      _toAccount = temp;
      _amountController.clear();
    });
    _loadAvailableBalance();
  }

  String _getAccountName(String accountType) {
    return accountType == 'FUND'
        ? 'Аккаунт финансирования'
        : 'Единый торговый аккаунт';
  }

  Future<void> _handleTransfer() async {
    // Нормализуем строку: заменяем запятую на точку для парсинга
    final amountText = _amountController.text.replaceAll(',', '.');
    final amount = double.tryParse(amountText) ?? 0.0;

    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Введите корректную сумму'),
          backgroundColor: AppTheme.primaryRed,
        ),
      );
      return;
    }

    if (amount > _availableBalance) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Недостаточно средств'),
          backgroundColor: AppTheme.primaryRed,
        ),
      );
      return;
    }

    setState(() {
      _isTransferring = true;
    });

    try {
      if (MockPortfolioService.useMockData) {
        // Используем моковый перевод
        await MockPortfolioService.transferBetweenAccounts(
          coin: _selectedCoin,
          amount: amount.toString(),
          fromAccountType: _fromAccount,
          toAccountType: _toAccount,
        );
      } else {
        // Используем реальный API
        await CryptoApiService.transferBetweenAccounts(
          coin: _selectedCoin,
          amount: amount.toString(),
          fromAccountType: _fromAccount,
          toAccountType: _toAccount,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Перевод выполнен успешно'),
            backgroundColor: AppTheme.primaryGreen,
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.of(context)
            .pop(true); // Возвращаем true для обновления данных
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Ошибка перевода';
        if (e.toString().contains('Приватные запросы отключены')) {
          errorMessage =
              'Приватные запросы отключены. Используйте моковые данные для тестирования.';
        } else if (e.toString().contains('Недостаточно средств')) {
          errorMessage = 'Недостаточно средств для перевода';
        } else {
          errorMessage =
              'Ошибка перевода: ${e.toString().replaceAll('Exception: ', '')}';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: AppTheme.primaryRed,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTransferring = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: Text(
          'В аккаунте',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.description_outlined,
                color: AppTheme.textSecondary),
            onPressed: () {},
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // От (From)
                        _buildSectionLabel('От'),
                        const SizedBox(height: 8),
                        _buildAccountField(
                          _getAccountName(_fromAccount),
                          () {
                            _showAccountSelector(true);
                          },
                        ),
                        const SizedBox(height: 16),
                        // Кнопка swap
                        Center(
                          child: GestureDetector(
                            onTap: _swapAccounts,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppTheme.backgroundCard,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppTheme.borderColor,
                                  width: 1,
                                ),
                              ),
                              child: Icon(
                                Icons.swap_vert,
                                color: AppTheme.textPrimary,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Кому (To)
                        _buildSectionLabel('Кому'),
                        const SizedBox(height: 8),
                        _buildAccountField(
                          _getAccountName(_toAccount),
                          () {
                            _showAccountSelector(false);
                          },
                        ),
                        const SizedBox(height: 24),
                        // Монета (Coin)
                        _buildSectionLabel('Монета'),
                        const SizedBox(height: 8),
                        _buildCoinField(),
                        const SizedBox(height: 24),
                        // Сумма (Amount)
                        _buildSectionLabel('Сумма'),
                        const SizedBox(height: 8),
                        _buildAmountField(),
                        const SizedBox(height: 16),
                        // Доступный баланс
                        Row(
                          children: [
                            Text(
                              'Доступный баланс',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 10,
                              ),
                            ),
                            Spacer(),
                            const SizedBox(height: 4),
                            Text(
                              '${_availableBalance.toStringAsFixed(2)} $_selectedCoin',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(width: 4),
                            GestureDetector(
                              onTap: () {
                                // Показать информацию о балансе
                              },
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: AppTheme.textSecondary
                                      .withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.help_outline,
                                  size: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
                // Кнопка подтверждения закреплена внизу
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isTransferring ? null : _handleTransfer,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            Color(0xFFD4A574), // Brown-orange color
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: _isTransferring
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              'Подтверждение',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        color: AppTheme.textSecondary,
        fontSize: 10,
      ),
    );
  }

  Widget _buildAccountField(String value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              value,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              color: AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoinField() {
    return GestureDetector(
      onTap: () {
        // В будущем можно добавить выбор монеты
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.backgroundCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.borderColor,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  'S',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _selectedCoin,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            Spacer(),
            Icon(
              Icons.arrow_forward_ios,
              color: AppTheme.textSecondary,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.borderColor,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _amountController,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
              ),
              decoration: InputDecoration(
                hintText: 'Укажите',
                hintStyle: TextStyle(
                  color: AppTheme.textSecondary.withValues(alpha: 0.5),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
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
          GestureDetector(
            onTap: () {
              _amountController.text = _availableBalance.toStringAsFixed(2);
            },
            child: Text(
              'Макс.',
              style: TextStyle(
                color: Colors.orange,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _selectedCoin,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  void _showAccountSelector(bool isFrom) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.backgroundCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isFrom ? 'Выберите аккаунт (От)' : 'Выберите аккаунт (Кому)',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            _buildAccountOption('FUND', 'Аккаунт финансирования', isFrom),
            const SizedBox(height: 8),
            _buildAccountOption('UNIFIED', 'Единый торговый аккаунт', isFrom),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountOption(String accountType, String name, bool isFrom) {
    final isSelected =
        isFrom ? _fromAccount == accountType : _toAccount == accountType;
    final isDisabled =
        isFrom ? _toAccount == accountType : _fromAccount == accountType;

    return GestureDetector(
      onTap: isDisabled
          ? null
          : () {
              setState(() {
                if (isFrom) {
                  _fromAccount = accountType;
                } else {
                  _toAccount = accountType;
                }
                _amountController.clear();
              });
              Navigator.pop(context);
              _loadAvailableBalance();
            },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryGreen.withValues(alpha: 0.1)
              : AppTheme.backgroundDark,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.primaryGreen : AppTheme.borderColor,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  color: isDisabled
                      ? AppTheme.textSecondary.withValues(alpha: 0.5)
                      : AppTheme.textPrimary,
                  fontSize: 16,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check,
                color: AppTheme.primaryGreen,
              ),
          ],
        ),
      ),
    );
  }
}
