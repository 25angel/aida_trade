import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/mock_portfolio_service.dart';

class AddBalanceScreen extends StatefulWidget {
  const AddBalanceScreen({super.key});

  @override
  State<AddBalanceScreen> createState() => _AddBalanceScreenState();
}

class _AddBalanceScreenState extends State<AddBalanceScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _amountController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _addBalance() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final amountText = _amountController.text.replaceAll(',', '.');
      final amount = double.parse(amountText);

      if (amount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Сумма должна быть больше нуля'),
            backgroundColor: AppTheme.primaryRed,
            duration: Duration(seconds: 2),
          ),
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Добавляем баланс в Funding аккаунт
      MockPortfolioService.addFundingBalance(amount);

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Баланс ${_formatBalance(amount)} USD успешно добавлен в Финансирования'),
          backgroundColor: AppTheme.primaryGreen,
          duration: const Duration(seconds: 2),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка добавления баланса: $e'),
          backgroundColor: AppTheme.primaryRed,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  String _formatBalance(double balance) {
    if (balance == 0.0) return '0.00';
    if (balance.abs() < 0.01) {
      return balance.toStringAsFixed(8);
    } else if (balance.abs() < 1) {
      return balance.toStringAsFixed(4);
    } else {
      return balance.toStringAsFixed(2);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundCard,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Добавить баланс',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Сумма будет добавлена в аккаунт Финансирования (USDT)',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              // Поле для ввода суммы
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundCard,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Сумма (USD)',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _amountController,
                      keyboardType:
                          TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        TextInputFormatter.withFunction((oldValue, newValue) {
                          var text = newValue.text;
                          // Заменяем запятую на точку
                          text = text.replaceAll(',', '.');
                          // Убираем лишние точки (оставляем только первую)
                          final parts = text.split('.');
                          if (parts.length > 2) {
                            text = parts[0] + '.' + parts.sublist(1).join('');
                          }
                          // Вычисляем новую позицию курсора
                          int selectionOffset = newValue.selection.baseOffset;
                          final lengthDiff = text.length - newValue.text.length;
                          selectionOffset += lengthDiff;
                          if (selectionOffset < 0) selectionOffset = 0;
                          if (selectionOffset > text.length) {
                            selectionOffset = text.length;
                          }
                          return TextEditingValue(
                            text: text,
                            selection: TextSelection.collapsed(
                              offset: selectionOffset,
                            ),
                          );
                        }),
                      ],
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppTheme.backgroundDark,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: AppTheme.primaryGreen,
                            width: 2,
                          ),
                        ),
                        hintText: 'Введите сумму',
                        hintStyle: const TextStyle(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Введите сумму';
                        }
                        final amount =
                            double.tryParse(value.replaceAll(',', '.'));
                        if (amount == null || amount <= 0) {
                          return 'Введите корректную сумму';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Кнопка добавления
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _addBalance,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Добавить баланс',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.textSecondary.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: AppTheme.textSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Баланс будет добавлен в аккаунт Финансирования и будет доступен для спот-торговли',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
